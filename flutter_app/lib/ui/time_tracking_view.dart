import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../models/time_activity.dart';
import '../models/time_entry.dart';
import 'app_theme.dart';
import 'widgets/empty_state.dart';

class TimeTrackingView extends StatefulWidget {
  const TimeTrackingView({
    super.key,
    required this.activities,
    required this.entries,
    required this.runningEntries,
    required this.tasks,
    required this.loading,
    required this.saving,
    required this.lastSync,
    required this.onRefresh,
    required this.onAddActivity,
    required this.onToggleActivity,
    required this.onEditActivity,
    required this.onDeleteActivity,
    this.onEditEntry,
  });

  final List<TimeActivity> activities;
  final List<TimeEntry> entries;
  final List<TimeEntry> runningEntries;
  final List<Task> tasks;
  final bool loading;
  final bool saving;
  final DateTime? lastSync;
  final VoidCallback onRefresh;
  final VoidCallback onAddActivity;
  final Future<void> Function(TimeActivity) onToggleActivity;
  final Future<void> Function(TimeActivity) onEditActivity;
  final Future<void> Function(TimeActivity) onDeleteActivity;
  final Future<void> Function(TimeEntry entry)? onEditEntry;

  @override
  State<TimeTrackingView> createState() => _TimeTrackingViewState();
}

class _TimeTrackingViewState extends State<TimeTrackingView> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  bool get _hasRunning => widget.runningEntries.any((entry) => entry.isRunning);

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant TimeTrackingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadRunning = oldWidget.runningEntries.any((entry) => entry.isRunning);
    final hasRunning = _hasRunning;
    if (hadRunning != hasRunning) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (!_hasRunning) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activityById = {for (final activity in widget.activities) activity.id: activity};
    final taskById = {for (final task in widget.tasks) task.id: task};

    final running = widget.runningEntries.where((entry) => entry.isRunning).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final runningIds = running.map((entry) => entry.id).toSet();
    final ended = widget.entries
        .where((entry) => entry.deletedAt == null && !entry.isRunning && !runningIds.contains(entry.id))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    final currentEntry = running.isEmpty ? null : running.first;
    final currentActivity =
        currentEntry == null ? null : activityById[currentEntry.activityId];

    final syncLabel = widget.loading || widget.saving
        ? '同步中...'
        : widget.lastSync == null
            ? '尚未同步'
            : '更新于 ${DateFormat('HH:mm').format(widget.lastSync!)}';

    final screenWidth = MediaQuery.of(context).size.width;
    final twoColumn = screenWidth >= 900;

    final actions = _ActionsRow(
      saving: widget.saving,
      loading: widget.loading,
      syncLabel: syncLabel,
      onAdd: widget.onAddActivity,
      onRefresh: widget.onRefresh,
    );

    final timerColumn = _TimerColumn(
      saving: widget.saving,
      loading: widget.loading,
      now: _now,
      currentEntry: currentEntry,
      currentActivity: currentActivity,
      runningActivityIds: running.map((entry) => entry.activityId).toSet(),
      activities: widget.activities,
      taskById: taskById,
      onToggleActivity: widget.onToggleActivity,
      onEditActivity: widget.onEditActivity,
      onDeleteActivity: widget.onDeleteActivity,
      onEditEntry: widget.onEditEntry,
    );

    final recordColumn = _RecordColumn(
      saving: widget.saving,
      now: _now,
      running: running,
      ended: ended,
      activityById: activityById,
      onEditEntry: widget.onEditEntry,
    );

    if (!twoColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          actions,
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                Expanded(child: timerColumn),
                const SizedBox(height: 12),
                Expanded(child: recordColumn),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        actions,
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: timerColumn),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: recordColumn),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.saving,
    required this.loading,
    required this.syncLabel,
    required this.onAdd,
    required this.onRefresh,
  });

  final bool saving;
  final bool loading;
  final String syncLabel;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 640;
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: saving ? null : onAdd,
            icon: const Icon(Icons.add),
            label: const Text('添加活动'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
          const SizedBox(height: 6),
          Text(
            syncLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      );
    }

    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: saving ? null : onAdd,
          icon: const Icon(Icons.add),
          label: const Text('添加活动'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('刷新'),
        ),
        const SizedBox(width: 16),
        Text(
          syncLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
        ),
      ],
    );
  }
}

class _TimerColumn extends StatelessWidget {
  const _TimerColumn({
    required this.saving,
    required this.loading,
    required this.now,
    required this.currentEntry,
    required this.currentActivity,
    required this.runningActivityIds,
    required this.activities,
    required this.taskById,
    required this.onToggleActivity,
    required this.onEditActivity,
    required this.onDeleteActivity,
    required this.onEditEntry,
  });

  final bool saving;
  final bool loading;
  final DateTime now;
  final TimeEntry? currentEntry;
  final TimeActivity? currentActivity;
  final Set<String> runningActivityIds;
  final List<TimeActivity> activities;
  final Map<String, Task> taskById;
  final Future<void> Function(TimeActivity) onToggleActivity;
  final Future<void> Function(TimeActivity) onEditActivity;
  final Future<void> Function(TimeActivity) onDeleteActivity;
  final Future<void> Function(TimeEntry entry)? onEditEntry;

  @override
  Widget build(BuildContext context) {
    if (loading && activities.isEmpty && currentEntry == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final list = <Widget>[
      _CurrentActivityCard(
        saving: saving,
        now: now,
        entry: currentEntry,
        activity: currentActivity,
        taskById: taskById,
        onTap: currentActivity == null ? null : () => onToggleActivity(currentActivity!),
        onLongPress: currentEntry == null
            ? null
            : () {
                final handler = onEditEntry;
                if (handler == null) return;
                handler(currentEntry!);
              },
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Text(
            '活动',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            '${activities.length} 个',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final activity in activities)
            _ActivityChip(
              activity: activity,
              running: runningActivityIds.contains(activity.id),
              disabled: saving,
              onTap: () => onToggleActivity(activity),
              onLongPress: () => onEditActivity(activity),
              onDelete: () => onDeleteActivity(activity),
            ),
        ],
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView(
        children: list,
      ),
    );
  }
}

class _RecordColumn extends StatelessWidget {
  const _RecordColumn({
    required this.saving,
    required this.now,
    required this.running,
    required this.ended,
    required this.activityById,
    required this.onEditEntry,
  });

  final bool saving;
  final DateTime now;
  final List<TimeEntry> running;
  final List<TimeEntry> ended;
  final Map<String, TimeActivity> activityById;
  final Future<void> Function(TimeEntry entry)? onEditEntry;

  @override
  Widget build(BuildContext context) {
    final entryCount = running.length + ended.length;
    if (entryCount == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: EmptyState(
            title: '还没有记录',
            subtitle: '点击左侧活动开始计时，记录会显示在这里。',
            flat: true,
          ),
        ),
      );
    }

    final rows = <_RecordListItem>[];
    if (running.isNotEmpty) {
      rows.add(const _RecordListItem.header('进行中'));
      for (final entry in running) {
        rows.add(_RecordListItem.entry(entry));
      }
    }

    DateTime? currentDay;
    for (final entry in ended) {
      final day = _startOfDay(DateTime.fromMillisecondsSinceEpoch(entry.startedAt));
      if (currentDay != day) {
        currentDay = day;
        rows.add(_RecordListItem.header(_dayLabel(day, now)));
      }
      rows.add(_RecordListItem.entry(entry));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '记录',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$entryCount 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final row = rows[index];
                if (row.isHeader) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                    child: Text(
                      row.label!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.inkSoft,
                          ),
                    ),
                  );
                }

                final entry = row.entry!;
                final activity = activityById[entry.activityId];
                return _EntryCard(
                  entry: entry,
                  now: now,
                  activity: activity,
                  disabled: saving,
                  onTap: onEditEntry == null ? null : () => onEditEntry!(entry),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordListItem {
  const _RecordListItem.header(this.label) : entry = null;
  const _RecordListItem.entry(this.entry) : label = null;

  final String? label;
  final TimeEntry? entry;

  bool get isHeader => label != null;
}

DateTime _startOfDay(DateTime value) => DateTime(value.year, value.month, value.day);

String _dayLabel(DateTime day, DateTime now) {
  final today = _startOfDay(now);
  if (day == today) return '今天';
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == yesterday) return '昨天';
  return DateFormat('yyyy-MM-dd').format(day);
}

class _CurrentActivityCard extends StatelessWidget {
  const _CurrentActivityCard({
    required this.saving,
    required this.now,
    required this.entry,
    required this.activity,
    required this.taskById,
    required this.onTap,
    required this.onLongPress,
  });

  final bool saving;
  final DateTime now;
  final TimeEntry? entry;
  final TimeActivity? activity;
  final Map<String, Task> taskById;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (entry == null || activity == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            const Icon(Icons.hourglass_empty, color: AppColors.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '当前没有进行中的活动',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
            ),
          ],
        ),
      );
    }

    final activityColor = _parseHexColor(activity!.color) ?? AppColors.accentSoft;
    final start = DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(entry!.startedAt));
    final elapsedMs = now.millisecondsSinceEpoch - entry!.startedAt;
    final taskLabel = _taskLabelFor(activity!, taskById);

    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: activityColor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: activityColor.withOpacity(0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: activityColor.withOpacity(0.25),
            child: Text(
              _activityIcon(activity, activity!.name),
              style: _emojiStyle(
                Theme.of(context).textTheme.titleMedium,
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${activity!.name} - $start',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  taskLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatStopwatch(elapsedMs),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
          ),
        ],
      ),
    );

    if (onTap == null && onLongPress == null) return card;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: saving ? null : onTap,
        onLongPress: saving ? null : onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }

  String _taskLabelFor(TimeActivity activity, Map<String, Task> taskById) {
    final taskId = activity.taskId;
    if (taskId == null || taskId.isEmpty) return '未关联任务';
    final task = taskById[taskId];
    if (task == null) return '关联任务已删除';
    final title = task.title.trim();
    return title.isEmpty ? '未命名任务' : title;
  }
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({
    required this.activity,
    required this.running,
    required this.disabled,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  final TimeActivity activity;
  final bool running;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final activityColor = _parseHexColor(activity.color) ?? AppColors.accentSoft;
    final title = activity.name.trim().isEmpty ? '未命名活动' : activity.name.trim();
    final bg = running ? activityColor.withOpacity(0.18) : Colors.white.withOpacity(0.85);
    final border = running ? activityColor.withOpacity(0.8) : AppColors.outline;

    final chip = Container(
      width: 170,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: activityColor.withOpacity(0.25),
            child: Text(
              _activityIcon(activity, title),
              style: _emojiStyle(
                Theme.of(context).textTheme.labelLarge,
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
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
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  running ? '进行中 · 点击结束' : '点击开始',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: disabled ? null : onDelete,
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.more_vert, size: 18, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: disabled ? null : onTap,
        onLongPress: disabled ? null : onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: chip,
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.now,
    required this.activity,
    required this.disabled,
    required this.onTap,
  });

  final TimeEntry entry;
  final DateTime now;
  final TimeActivity? activity;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = (activity?.name ?? '').trim().isEmpty ? '未命名活动' : (activity?.name ?? '').trim();
    final activityColor = _parseHexColor(activity?.color ?? '') ?? AppColors.accentSoft;
    final activityIcon = (activity?.icon ?? '').trim();
    final started = DateTime.fromMillisecondsSinceEpoch(entry.startedAt);
    final startLabel = DateFormat('HH:mm').format(started);
    final endedAt = entry.endedAt;
    final endLabel =
        endedAt == null ? null : DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(endedAt));

    final durationMs = endedAt == null
        ? now.millisecondsSinceEpoch - entry.startedAt
        : (entry.durationMs ?? (endedAt - entry.startedAt));

    final timeRange = endLabel == null ? '$startLabel - 现在' : '$startLabel - $endLabel';

    final card = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: activityColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: activityColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: activityColor.withOpacity(0.25),
            child: Text(
              activityIcon.isNotEmpty ? activityIcon : _avatarLetter(name),
              style: _emojiStyle(
                Theme.of(context).textTheme.labelLarge,
                color: AppColors.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeRange,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _formatStopwatch(durationMs),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}

Color? _parseHexColor(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return null;
  final hex = raw.startsWith('#') ? raw.substring(1) : raw;
  if (hex.length == 6) {
    final parsed = int.tryParse('FF$hex', radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }
  if (hex.length == 8) {
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }
  return null;
}

String _avatarLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first;
}

String _activityIcon(TimeActivity? activity, String fallback) {
  final icon = activity?.icon.trim() ?? '';
  if (icon.isNotEmpty) return icon;
  return _avatarLetter(fallback);
}

TextStyle _emojiStyle(
  TextStyle? base, {
  required Color color,
  required double fontSize,
  required FontWeight fontWeight,
}) {
  const fallback = <String>[
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Color Emoji',
  ];
  final next = (base ?? const TextStyle()).copyWith(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: 1.0,
    fontFamilyFallback: fallback,
  );
  return next;
}

String _formatStopwatch(int ms) {
  final safe = ms < 0 ? 0 : ms;
  final totalSeconds = (safe / 1000).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
