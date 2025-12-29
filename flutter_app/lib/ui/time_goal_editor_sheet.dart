import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/time_activity.dart';
import '../models/time_goals.dart';
import 'app_theme.dart';

class TimeGoalEditorSheet extends StatefulWidget {
  const TimeGoalEditorSheet({
    super.key,
    required this.apiClient,
    required this.activities,
    required this.existingGoals,
    this.initialActivityId,
  });

  final ApiClient apiClient;
  final List<TimeActivity> activities;
  final List<TimeGoalItem> existingGoals;
  final String? initialActivityId;

  @override
  State<TimeGoalEditorSheet> createState() => _TimeGoalEditorSheetState();
}

class _TimeGoalEditorSheetState extends State<TimeGoalEditorSheet> {
  late String _activityId;
  bool _saving = false;

  late final TextEditingController _dailyMinutes;
  late final TextEditingController _dailyCount;
  late final TextEditingController _weeklyMinutes;
  late final TextEditingController _weeklyCount;
  late final TextEditingController _totalMinutes;
  late final TextEditingController _totalCount;

  @override
  void initState() {
    super.initState();
    final activityIds = widget.activities
        .where((a) => a.deletedAt == null)
        .map((a) => a.id)
        .toList();
    final initial = widget.initialActivityId;
    _activityId = activityIds.contains(initial) ? initial! : (activityIds.isEmpty ? '' : activityIds.first);

    _dailyMinutes = TextEditingController();
    _dailyCount = TextEditingController();
    _weeklyMinutes = TextEditingController();
    _weeklyCount = TextEditingController();
    _totalMinutes = TextEditingController();
    _totalCount = TextEditingController();

    _syncFromExisting();
  }

  @override
  void dispose() {
    _dailyMinutes.dispose();
    _dailyCount.dispose();
    _weeklyMinutes.dispose();
    _weeklyCount.dispose();
    _totalMinutes.dispose();
    _totalCount.dispose();
    super.dispose();
  }

  void _syncFromExisting() {
    final existing = widget.existingGoals
        .cast<TimeGoalItem?>()
        .firstWhere((g) => g?.activityId == _activityId, orElse: () => null);

    int toMinutes(int durationMs) => (durationMs / (60 * 1000)).round();
    String fmtInt(int value) => value <= 0 ? '' : value.toString();

    if (existing == null) {
      _dailyMinutes.text = '';
      _dailyCount.text = '';
      _weeklyMinutes.text = '';
      _weeklyCount.text = '';
      _totalMinutes.text = '';
      _totalCount.text = '';
      return;
    }

    _dailyMinutes.text = fmtInt(toMinutes(existing.targets.daily.durationMs));
    _dailyCount.text = fmtInt(existing.targets.daily.count);
    _weeklyMinutes.text = fmtInt(toMinutes(existing.targets.weekly.durationMs));
    _weeklyCount.text = fmtInt(existing.targets.weekly.count);
    _totalMinutes.text = fmtInt(toMinutes(existing.targets.total.durationMs));
    _totalCount.text = fmtInt(existing.targets.total.count);
  }

  int _parseNonNegativeInt(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  TimeGoalPeriods _buildTargets() {
    int minutesToMs(int minutes) => minutes <= 0 ? 0 : minutes * 60 * 1000;

    final dailyMin = _parseNonNegativeInt(_dailyMinutes.text);
    final weeklyMin = _parseNonNegativeInt(_weeklyMinutes.text);
    final totalMin = _parseNonNegativeInt(_totalMinutes.text);

    final dailyCount = _parseNonNegativeInt(_dailyCount.text);
    final weeklyCount = _parseNonNegativeInt(_weeklyCount.text);
    final totalCount = _parseNonNegativeInt(_totalCount.text);

    return TimeGoalPeriods(
      daily: TimeGoalPeriod(durationMs: minutesToMs(dailyMin), count: dailyCount),
      weekly: TimeGoalPeriod(durationMs: minutesToMs(weeklyMin), count: weeklyCount),
      total: TimeGoalPeriod(durationMs: minutesToMs(totalMin), count: totalCount),
    );
  }

  bool get _hasAnyTarget {
    final targets = _buildTargets();
    return targets.daily.durationMs > 0 ||
        targets.daily.count > 0 ||
        targets.weekly.durationMs > 0 ||
        targets.weekly.count > 0 ||
        targets.total.durationMs > 0 ||
        targets.total.count > 0;
  }

  Future<void> _save() async {
    if (_activityId.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final targets = _buildTargets();
      await widget.apiClient.saveTimeGoal(activityId: _activityId, targets: targets);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存目标失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_activityId.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.apiClient.deleteTimeGoal(_activityId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除目标失败。')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activities = widget.activities.where((a) => a.deletedAt == null).toList();
    final activityMap = {for (final a in activities) a.id: a};
    final selectedActivity = activityMap[_activityId];
    final danger = Theme.of(context).colorScheme.error;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '目标设置',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _activityId.isEmpty ? null : _activityId,
              decoration: const InputDecoration(labelText: '选择事件'),
              items: activities
                  .map((a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      final next = value ?? '';
                      if (next == _activityId) return;
                      setState(() => _activityId = next);
                      _syncFromExisting();
                    },
            ),
            if (selectedActivity != null && selectedActivity.category.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '分类：${selectedActivity.category}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: [
                  _SectionTitle(title: '每日'),
                  const SizedBox(height: 8),
                  _Row2(
                    left: TextField(
                      controller: _dailyMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '时长(分钟)'),
                    ),
                    right: TextField(
                      controller: _dailyCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '次数(条)'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionTitle(title: '每周'),
                  const SizedBox(height: 8),
                  _Row2(
                    left: TextField(
                      controller: _weeklyMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '时长(分钟)'),
                    ),
                    right: TextField(
                      controller: _weeklyCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '次数(条)'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SectionTitle(title: '累计'),
                  const SizedBox(height: 8),
                  _Row2(
                    left: TextField(
                      controller: _totalMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '时长(分钟)'),
                    ),
                    right: TextField(
                      controller: _totalCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '次数(条)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '提示：留空或填 0 表示不设置；次数按“记录条数”统计，跨天记录也算 1 次。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.existingGoals.any((g) => g.activityId == _activityId))
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: danger,
                        side: BorderSide(color: danger),
                      ),
                      child: const Text('删除目标'),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : () {
                            if (!_hasAnyTarget) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请至少设置一个目标值。')),
                              );
                              return;
                            }
                            _save();
                          },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 520;
    if (isCompact) {
      return Column(
        children: [
          left,
          const SizedBox(height: 10),
          right,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}
