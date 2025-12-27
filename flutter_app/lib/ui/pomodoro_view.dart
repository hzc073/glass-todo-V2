import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/pomodoro_session.dart';
import '../models/pomodoro_settings.dart';
import '../models/pomodoro_state.dart';
import '../models/pomodoro_summary.dart';
import '../models/task.dart';
import 'app_theme.dart';

class PomodoroView extends StatefulWidget {
  const PomodoroView({
    super.key,
    required this.apiClient,
    required this.tasks,
    required this.onLogout,
    required this.onTaskUpdated,
  });

  final ApiClient apiClient;
  final List<Task> tasks;
  final VoidCallback onLogout;
  final ValueChanged<Task> onTaskUpdated;

  @override
  State<PomodoroView> createState() => _PomodoroViewState();
}

class _PomodoroViewState extends State<PomodoroView> {
  static const _prefsKeyDashboardExpanded = 'pomodoro.dashboardExpanded';
  static const _prefsKeyReminderSound = 'pomodoro.reminderSound';
  static const _prefsKeyReminderPopup = 'pomodoro.reminderPopup';
  static const _prefsKeySelectedTask = 'pomodoro.selectedTaskId';

  final _dateKeyFmt = DateFormat('yyyy-MM-dd');

  Timer? _ticker;

  bool _loading = true;
  bool _saving = false;

  bool _dashboardExpanded = true;
  bool _reminderSound = true;
  bool _reminderPopup = true;
  String? _selectedTaskId;

  PomodoroSettings _settings = const PomodoroSettings(
    workMin: 25,
    shortBreakMin: 5,
    longBreakMin: 15,
    longBreakEvery: 4,
    autoStartNext: false,
    autoStartBreak: false,
    autoStartWork: false,
    autoFinishTask: false,
  );

  PomodoroState _state = PomodoroState.initial();
  int _stageTotalMs = 25 * 60 * 1000;
  int? _stageStartedAt;

  PomodoroSummary? _summary;
  List<PomodoroSession> _sessions = <PomodoroSession>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  Task? get _selectedTask {
    final id = _selectedTaskId;
    if (id == null || id.isEmpty) return null;
    for (final task in widget.tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  int _durationMsFor(PomodoroMode mode) {
    final minutes = switch (mode) {
      PomodoroMode.work => _settings.workMin,
      PomodoroMode.shortBreak => _settings.shortBreakMin,
      PomodoroMode.longBreak => _settings.longBreakMin,
    };
    return math.max(1, minutes) * 60 * 1000;
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final dashboardExpanded = prefs.getBool(_prefsKeyDashboardExpanded);
    final reminderSound = prefs.getBool(_prefsKeyReminderSound);
    final reminderPopup = prefs.getBool(_prefsKeyReminderPopup);
    final selectedTaskId = prefs.getString(_prefsKeySelectedTask);

    setState(() {
      _dashboardExpanded = dashboardExpanded ?? true;
      _reminderSound = reminderSound ?? true;
      _reminderPopup = reminderPopup ?? true;
      _selectedTaskId = selectedTaskId;
    });

    try {
      final settings = await widget.apiClient.getPomodoroSettings();
      final savedState = await widget.apiClient.getPomodoroState();
      final summary = await widget.apiClient.getPomodoroSummary(days: 60);
      final sessions = await widget.apiClient.getPomodoroSessions(limit: 200);

      PomodoroState nextState;
      if (savedState == null) {
        nextState = PomodoroState.initial().copyWith(remainingMs: settings.workMin * 60 * 1000);
      } else {
        nextState = savedState;
        if (nextState.isRunning && nextState.targetEnd != null) {
          final remaining = math.max(0, nextState.targetEnd! - DateTime.now().millisecondsSinceEpoch);
          nextState = nextState.copyWith(remainingMs: remaining);
          if (remaining == 0) {
            nextState = nextState.copyWith(isRunning: false, clearTargetEnd: true);
          }
        } else {
          nextState = nextState.copyWith(isRunning: false, clearTargetEnd: true);
        }
      }

      setState(() {
        _settings = settings;
        _state = nextState;
        _stageTotalMs = math.max(_durationMsFor(nextState.mode), math.max(1, nextState.remainingMs));
        _summary = summary;
        _sessions = sessions;
        _loading = false;
      });

      if (_state.isRunning && _state.targetEnd != null) {
        _startTicker();
      }
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _summary = const PomodoroSummary(
          totalWorkSessions: 0,
          totalWorkMinutes: 0,
          totalBreakMinutes: 0,
          days: <String, PomodoroDaySummary>{},
        );
        _sessions = const <PomodoroSession>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载番茄钟数据失败。')),
      );
    }
  }

  Future<void> _refreshDashboard() async {
    try {
      final summary = await widget.apiClient.getPomodoroSummary(days: 60);
      final sessions = await widget.apiClient.getPomodoroSessions(limit: 200);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _sessions = sessions;
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刷新统计失败。')),
      );
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _saveState(PomodoroState state) async {
    try {
      await widget.apiClient.savePomodoroState(state);
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      // ignore transient errors to keep UX smooth
    }
  }

  void _tick() {
    if (!_state.isRunning || _state.targetEnd == null) return;
    final remaining = math.max(0, _state.targetEnd! - DateTime.now().millisecondsSinceEpoch);
    if (remaining == 0) {
      _handleStageFinished();
      return;
    }
    if (!mounted) return;
    setState(() {
      _state = _state.copyWith(remainingMs: remaining);
    });
  }

  void _toggleRunPause() {
    if (_state.isRunning) {
      _pause();
    } else {
      _start();
    }
  }

  void _start() {
    if (_state.isRunning) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final targetEnd = now + _state.remainingMs;
    final startedAt = _stageStartedAt ?? now;
    final next = _state.copyWith(isRunning: true, targetEnd: targetEnd);
    setState(() {
      _state = next;
      _stageStartedAt = startedAt;
    });
    _startTicker();
    unawaited(_saveState(next));
  }

  void _pause() {
    if (!_state.isRunning) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = _state.targetEnd == null ? _state.remainingMs : math.max(0, _state.targetEnd! - now);
    _stopTicker();
    final next = _state.copyWith(isRunning: false, remainingMs: remaining, clearTargetEnd: true);
    setState(() => _state = next);
    unawaited(_saveState(next));
  }

  void _reset() {
    _pause();
    final total = _durationMsFor(_state.mode);
    final next = _state.copyWith(remainingMs: total, clearTargetEnd: true);
    setState(() {
      _state = next;
      _stageTotalMs = total;
      _stageStartedAt = null;
    });
    unawaited(_saveState(next));
  }

  void _skip() {
    _pause();
    final nextMode = _nextMode(after: _state.mode, cycleCount: _state.cycleCount);
    final nextCycle = _state.mode == PomodoroMode.work ? _state.cycleCount + 1 : _state.cycleCount;
    final total = _durationMsFor(nextMode);
    final next = _state.copyWith(
      mode: nextMode,
      remainingMs: total,
      cycleCount: nextCycle,
      clearTargetEnd: true,
      isRunning: false,
    );
    setState(() {
      _state = next;
      _stageTotalMs = total;
      _stageStartedAt = null;
    });
    unawaited(_saveState(next));
    _maybeAutoStart(nextMode);
  }

  PomodoroMode _nextMode({required PomodoroMode after, required int cycleCount}) {
    if (after == PomodoroMode.work) {
      final nextWorkCount = cycleCount + 1;
      final every = math.max(1, _settings.longBreakEvery);
      final isLong = nextWorkCount % every == 0;
      return isLong ? PomodoroMode.longBreak : PomodoroMode.shortBreak;
    }
    return PomodoroMode.work;
  }

  void _maybeAutoStart(PomodoroMode nextMode) {
    final shouldAuto = _settings.autoStartNext ||
        (nextMode == PomodoroMode.work ? _settings.autoStartWork : _settings.autoStartBreak);
    if (!shouldAuto) return;
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _start();
    });
  }

  Future<void> _handleStageFinished() async {
    _stopTicker();
    final finishedMode = _state.mode;
    final cycleCount = finishedMode == PomodoroMode.work ? _state.cycleCount + 1 : _state.cycleCount;
    final endedAt = DateTime.now().millisecondsSinceEpoch;

    final finished = _state.copyWith(
      remainingMs: 0,
      isRunning: false,
      clearTargetEnd: true,
      cycleCount: cycleCount,
    );

    if (mounted) {
      setState(() => _state = finished);
    }
    unawaited(_saveState(finished));

    if (_reminderSound) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
    if (mounted && _reminderPopup) {
      final msg = finishedMode == PomodoroMode.work ? '专注完成' : '休息完成';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    if (finishedMode == PomodoroMode.work) {
      final durationMin = math.max(1, (_stageTotalMs / (60 * 1000)).round());
      final dateKey = _dateKeyFmt.format(DateTime.now());
      final taskTitle = _selectedTask?.title.trim();
      try {
        await widget.apiClient.addPomodoroSession(
          taskTitle: (taskTitle == null || taskTitle.isEmpty) ? null : taskTitle,
          startedAt: _stageStartedAt,
          endedAt: endedAt,
          durationMin: durationMin,
          dateKey: dateKey,
        );
      } on UnauthorizedException {
        widget.onLogout();
        return;
      } catch (_) {}

      if (_settings.autoFinishTask) {
        final task = _selectedTask;
        if (task != null && !task.isCompleted) {
          try {
            final updated = await widget.apiClient.updateTask(task.id, status: 'completed');
            widget.onTaskUpdated(updated);
          } on UnauthorizedException {
            widget.onLogout();
            return;
          } catch (_) {}
        }
      }

      unawaited(_refreshDashboard());
    }

    final nextMode = _nextMode(after: finishedMode, cycleCount: _state.cycleCount);
    final nextTotal = _durationMsFor(nextMode);
    final next = finished.copyWith(mode: nextMode, remainingMs: nextTotal);
    if (mounted) {
      setState(() {
        _state = next;
        _stageTotalMs = nextTotal;
        _stageStartedAt = null;
      });
    }
    unawaited(_saveState(next));
    _maybeAutoStart(nextMode);
  }

  Future<void> _setDashboardExpanded(bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyDashboardExpanded, expanded);
    if (!mounted) return;
    setState(() => _dashboardExpanded = expanded);
  }

  Future<void> _openSettings() async {
    final result = await showModalBottomSheet<_SettingsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PomodoroSettingsSheet(
        settings: _settings,
        reminderSound: _reminderSound,
        reminderPopup: _reminderPopup,
      ),
    );
    if (result == null) return;

    setState(() {
      _settings = result.settings;
      _reminderSound = result.reminderSound;
      _reminderPopup = result.reminderPopup;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyReminderSound, _reminderSound);
    await prefs.setBool(_prefsKeyReminderPopup, _reminderPopup);

    setState(() => _saving = true);
    try {
      final saved = await widget.apiClient.savePomodoroSettings(_settings);
      if (!mounted) return;
      setState(() => _settings = saved);

      if (!_state.isRunning) {
        final total = _durationMsFor(_state.mode);
        setState(() {
          _state = _state.copyWith(remainingMs: total);
          _stageTotalMs = total;
          _stageStartedAt = null;
        });
        unawaited(_saveState(_state));
      }
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存番茄钟设置失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openTaskPicker() async {
    final selected = await showModalBottomSheet<Task?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TaskPickerSheet(
        tasks: widget.tasks.where((t) => t.deletedAt == null).toList(),
        selectedId: _selectedTaskId,
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeySelectedTask, selected.id);
    if (!mounted) return;
    setState(() => _selectedTaskId = selected.id);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final twoColumn = width >= 980;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final timerColumn = _buildTimerColumn(context);
    final dashboard = _PomodoroDashboard(
      expanded: _dashboardExpanded,
      loading: _summary == null,
      summary: _summary,
      sessions: _sessions,
      onCollapse: () => _setDashboardExpanded(false),
      onRefresh: _refreshDashboard,
    );

    if (!_dashboardExpanded) {
      return Stack(
        children: [
          Positioned.fill(child: timerColumn),
          Positioned(
            right: 18,
            top: 14,
            child: FilledButton.tonalIcon(
              onPressed: _saving ? null : () => _setDashboardExpanded(true),
              icon: const Icon(Icons.bar_chart),
              label: const Text('数据看板'),
            ),
          ),
        ],
      );
    }

    if (!twoColumn) {
      return Column(
        children: [
          Expanded(child: timerColumn),
          const SizedBox(height: 12),
          SizedBox(height: 360, child: dashboard),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: timerColumn),
        const SizedBox(width: 12),
        Expanded(flex: 5, child: dashboard),
      ],
    );
  }

  Widget _buildTimerColumn(BuildContext context) {
    final ratio = _stageTotalMs <= 0 ? 0.0 : (_state.remainingMs / _stageTotalMs).clamp(0.0, 1.0);
    final timeLabel = _formatRemaining(_state.remainingMs);
    final modeLabel = _state.mode.label;
    final selectedTask = _selectedTask;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(
                '番茄钟 · $modeLabel',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: '设置',
                onPressed: _saving ? null : _openSettings,
                icon: const Icon(Icons.settings, color: AppColors.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _PomodoroRing(
                    progress: ratio,
                    isRunning: _state.isRunning,
                    onToggle: _saving ? null : _toggleRunPause,
                    timeLabel: timeLabel,
                    onTapTime: _saving ? null : _openSettings,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('重置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _skip,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('跳过'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _saving ? null : _openTaskPicker,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.task_alt, size: 18, color: AppColors.inkSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedTask == null ? '选择要专注的任务（可选）' : selectedTask.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    selectedTask == null ? '选择' : '更换',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentDeep,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _settings.autoFinishTask ? '开启：专注结束后自动完成任务' : '可在设置中开启：专注结束后自动完成任务',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

String _formatRemaining(int ms) {
  final clamped = math.max(0, ms);
  final totalSeconds = (clamped / 1000).ceil();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class _PomodoroRing extends StatelessWidget {
  const _PomodoroRing({
    required this.progress,
    required this.isRunning,
    required this.onToggle,
    required this.timeLabel,
    required this.onTapTime,
  });

  final double progress;
  final bool isRunning;
  final VoidCallback? onToggle;
  final String timeLabel;
  final VoidCallback? onTapTime;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '番茄钟计时器',
      child: CustomPaint(
        painter: _PomodoroRingPainter(progress: progress),
        child: Center(
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.outline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 54,
                      color: AppColors.accentDeep,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  onTap: onTapTime,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PomodoroRingPainter extends CustomPainter {
  _PomodoroRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) / 2) - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = AppColors.outline.withOpacity(0.6)
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = AppColors.accentCool
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, bgPaint);

    // Remaining time: start at 12 o'clock and shrink towards 11 o'clock.
    final startAngle = -math.pi / 2;
    final sweep = (math.pi * 2) * progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, startAngle, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _PomodoroRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _PomodoroDashboard extends StatelessWidget {
  const _PomodoroDashboard({
    required this.expanded,
    required this.loading,
    required this.summary,
    required this.sessions,
    required this.onCollapse,
    required this.onRefresh,
  });

  final bool expanded;
  final bool loading;
  final PomodoroSummary? summary;
  final List<PomodoroSession> sessions;
  final VoidCallback onCollapse;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final summary = this.summary;
    final today = summary?.days[todayKey] ?? const PomodoroDaySummary(workSessions: 0, workMinutes: 0, breakMinutes: 0);
    final totalPomodoro = summary?.totalWorkSessions ?? 0;
    final totalFocusMin = summary?.totalWorkMinutes ?? 0;
    final todayPomodoro = today.workSessions;
    final todayFocusMin = today.workMinutes;

    final last7 = List.generate(7, (index) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: index));
      final key = DateFormat('yyyy-MM-dd').format(day);
      return (day: day, key: key, stats: summary?.days[key]);
    });

    final historyRows = <_HistoryRow>[];
    DateTime? currentDay;
    for (final session in sessions) {
      final ended = DateTime.fromMillisecondsSinceEpoch(session.endedAt);
      final day = DateTime(ended.year, ended.month, ended.day);
      if (currentDay != day) {
        currentDay = day;
        historyRows.add(_HistoryRow.header(_dayLabel(day, now)));
      }
      historyRows.add(_HistoryRow.session(session));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '数据看板',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: '刷新',
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh, color: AppColors.inkSoft),
              ),
              IconButton(
                tooltip: '收起',
                onPressed: onCollapse,
                icon: const Icon(Icons.chevron_right, color: AppColors.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      _MetricGrid(
                        todayPomodoro: todayPomodoro,
                        totalPomodoro: totalPomodoro,
                        todayFocusMin: todayFocusMin,
                        totalFocusMin: totalFocusMin,
                      ),
                      const SizedBox(height: 14),
                      _SectionTitle(title: '最近七天'),
                      const SizedBox(height: 8),
                      ...last7.map(
                        (item) {
                          final stats = item.stats ?? const PomodoroDaySummary(workSessions: 0, workMinutes: 0, breakMinutes: 0);
                          final label = _dayLabel(item.day, now);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _DayCard(
                              label: label,
                              sessions: stats.workSessions,
                              minutes: stats.workMinutes,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _SectionTitle(title: '完成历史'),
                      const SizedBox(height: 8),
                      if (historyRows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '还没有番茄记录',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
                          ),
                        )
                      else
                        ...historyRows.map(
                          (row) {
                            if (row.isHeader) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                                child: Text(
                                  row.label!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.inkSoft,
                                      ),
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SessionCard(session: row.session!),
                            );
                          },
                        ),
                      const SizedBox(height: 6),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.todayPomodoro,
    required this.totalPomodoro,
    required this.todayFocusMin,
    required this.totalFocusMin,
  });

  final int todayPomodoro;
  final int totalPomodoro;
  final int todayFocusMin;
  final int totalFocusMin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 360;
        final children = [
          _MetricCard(title: '今日番茄', value: todayPomodoro.toString(), icon: Icons.local_fire_department),
          _MetricCard(title: '总番茄', value: totalPomodoro.toString(), icon: Icons.all_inclusive),
          _MetricCard(title: '今日专注', value: _formatMinutes(todayFocusMin), icon: Icons.timer),
          _MetricCard(title: '总专注', value: _formatMinutes(totalFocusMin), icon: Icons.query_stats),
        ];
        if (!twoCol) {
          return Column(
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 10),
                Expanded(child: children[1]),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: children[2]),
                const SizedBox(width: 10),
                Expanded(child: children[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentSoft.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentSoft.withOpacity(0.35)),
            ),
            child: Icon(icon, size: 18, color: AppColors.accentDeep),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.label, required this.sessions, required this.minutes});

  final String label;
  final int sessions;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '$sessions 个',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatMinutes(minutes),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});

  final PomodoroSession session;

  @override
  Widget build(BuildContext context) {
    final ended = DateTime.fromMillisecondsSinceEpoch(session.endedAt);
    final approxStarted = session.startedAt == null
        ? ended.subtract(Duration(minutes: math.max(1, session.durationMin)))
        : DateTime.fromMillisecondsSinceEpoch(session.startedAt!);
    final timeFmt = DateFormat('HH:mm');
    final title = (session.taskTitle ?? '').trim().isEmpty ? '专注' : session.taskTitle!.trim();
    final range = '${timeFmt.format(approxStarted)} - ${timeFmt.format(ended)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentCool.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accentCool.withOpacity(0.35)),
            ),
            child: const Icon(Icons.timer, size: 18, color: AppColors.accentCool),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  range,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${session.durationMin}m',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow {
  const _HistoryRow.header(this.label) : session = null;
  const _HistoryRow.session(this.session) : label = null;

  final String? label;
  final PomodoroSession? session;

  bool get isHeader => label != null;
}

String _dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return '今天';
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == yesterday) return '昨天';
  return DateFormat('yyyy-MM-dd').format(day);
}

String _formatMinutes(int minutes) {
  final m = math.max(0, minutes);
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  final mm = m % 60;
  if (mm == 0) return '${h}h';
  return '${h}h${mm}m';
}

class _SettingsResult {
  const _SettingsResult({
    required this.settings,
    required this.reminderSound,
    required this.reminderPopup,
  });

  final PomodoroSettings settings;
  final bool reminderSound;
  final bool reminderPopup;
}

class _PomodoroSettingsSheet extends StatefulWidget {
  const _PomodoroSettingsSheet({
    required this.settings,
    required this.reminderSound,
    required this.reminderPopup,
  });

  final PomodoroSettings settings;
  final bool reminderSound;
  final bool reminderPopup;

  @override
  State<_PomodoroSettingsSheet> createState() => _PomodoroSettingsSheetState();
}

class _PomodoroSettingsSheetState extends State<_PomodoroSettingsSheet> {
  late final TextEditingController _work;
  late final TextEditingController _short;
  late final TextEditingController _long;
  late final TextEditingController _every;

  late bool _autoNext;
  late bool _autoBreak;
  late bool _autoWork;
  late bool _autoFinishTask;

  late bool _reminderSound;
  late bool _reminderPopup;

  @override
  void initState() {
    super.initState();
    _work = TextEditingController(text: widget.settings.workMin.toString());
    _short = TextEditingController(text: widget.settings.shortBreakMin.toString());
    _long = TextEditingController(text: widget.settings.longBreakMin.toString());
    _every = TextEditingController(text: widget.settings.longBreakEvery.toString());
    _autoNext = widget.settings.autoStartNext;
    _autoBreak = widget.settings.autoStartBreak;
    _autoWork = widget.settings.autoStartWork;
    _autoFinishTask = widget.settings.autoFinishTask;
    _reminderSound = widget.reminderSound;
    _reminderPopup = widget.reminderPopup;
  }

  @override
  void dispose() {
    _work.dispose();
    _short.dispose();
    _long.dispose();
    _every.dispose();
    super.dispose();
  }

  int _readInt(TextEditingController controller, int fallback) {
    final parsed = int.tryParse(controller.text.trim());
    if (parsed == null) return fallback;
    return math.max(1, parsed);
  }

  void _submit() {
    final next = widget.settings.copyWith(
      workMin: _readInt(_work, widget.settings.workMin),
      shortBreakMin: _readInt(_short, widget.settings.shortBreakMin),
      longBreakMin: _readInt(_long, widget.settings.longBreakMin),
      longBreakEvery: _readInt(_every, widget.settings.longBreakEvery),
      autoStartNext: _autoNext,
      autoStartBreak: _autoBreak,
      autoStartWork: _autoWork,
      autoFinishTask: _autoFinishTask,
    );
    Navigator.of(context).pop(
      _SettingsResult(
        settings: next,
        reminderSound: _reminderSound,
        reminderPopup: _reminderPopup,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '番茄钟设置',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _work,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '专注时间（分钟）'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _short,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '短休时间（分钟）'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _long,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '长休时间（分钟）'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _every,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '长休间隔（番茄数）'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoNext,
                  onChanged: (v) => setState(() => _autoNext = v),
                  title: const Text('自动开启下一轮'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoBreak,
                  onChanged: (v) => setState(() => _autoBreak = v),
                  title: const Text('自动开始休息'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoWork,
                  onChanged: (v) => setState(() => _autoWork = v),
                  title: const Text('自动开始专注'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoFinishTask,
                  onChanged: (v) => setState(() => _autoFinishTask = v),
                  title: const Text('番茄结束后自动完成任务'),
                ),
                const Divider(height: 22),
                Text(
                  '提醒设置',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reminderSound,
                  onChanged: (v) => setState(() => _reminderSound = v),
                  title: const Text('结束提示音'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reminderPopup,
                  onChanged: (v) => setState(() => _reminderPopup = v),
                  title: const Text('结束提示条（Snackbar）'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskPickerSheet extends StatefulWidget {
  const _TaskPickerSheet({required this.tasks, required this.selectedId});

  final List<Task> tasks;
  final String? selectedId;

  @override
  State<_TaskPickerSheet> createState() => _TaskPickerSheetState();
}

class _TaskPickerSheetState extends State<_TaskPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final tasks = widget.tasks
        .where((t) => t.deletedAt == null)
        .where((t) => _query.trim().isEmpty || t.title.toLowerCase().contains(_query.trim().toLowerCase()))
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '选择任务',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索任务名称…',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      final selected = task.id == widget.selectedId;
                      return InkWell(
                        onTap: () => Navigator.of(context).pop(task),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: selected ? AppColors.accent : AppColors.outline),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: selected ? AppColors.accentDeep : AppColors.inkSoft,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
