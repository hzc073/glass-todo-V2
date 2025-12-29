import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/time_activity.dart';
import '../models/time_goals.dart';
import '../models/time_stats.dart';
import 'app_theme.dart';
import 'widgets/empty_state.dart';

class TimeStatsView extends StatelessWidget {
  const TimeStatsView({
    super.key,
    required this.stats,
    required this.goals,
    required this.activities,
    required this.loading,
    required this.rangeFrom,
    required this.rangeTo,
    required this.onRefresh,
    this.onAddGoal,
    this.onEditGoal,
    this.onOpenActivityDetail,
    this.onOpenCategoryDetail,
  });

  final TimeStats? stats;
  final TimeGoalsSnapshot? goals;
  final List<TimeActivity> activities;
  final bool loading;
  final int rangeFrom;
  final int rangeTo;
  final VoidCallback onRefresh;
  final VoidCallback? onAddGoal;
  final void Function(String activityId)? onEditGoal;
  final void Function(String activityId)? onOpenActivityDetail;
  final void Function(String category)? onOpenCategoryDetail;

  @override
  Widget build(BuildContext context) {
    final rangeLabel = _rangeLabel();
    final isCompact = MediaQuery.of(context).size.width < 640;
    final actionRow = isCompact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新统计'),
              ),
              const SizedBox(height: 8),
              Text(
                rangeLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          )
        : Row(
            children: [
              OutlinedButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新统计'),
              ),
              const SizedBox(width: 12),
              Text(
                rangeLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          );

    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final children = <Widget>[];
      if (goals != null) {
        children.addAll([
          _GoalsCard(
            snapshot: goals!,
            activities: activities,
            onAdd: onAddGoal,
            onEdit: onEditGoal,
          ),
          const SizedBox(height: 12),
        ]);
      }
      if (stats == null || (stats!.totalMs == 0 && stats!.byDay.isEmpty)) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 24),
          child: EmptyState(
            title: '暂无统计数据',
            subtitle: '先在时间记录里开始计时，再回来查看统计。',
          ),
        ));
      } else {
        children.addAll([
          _SummaryCard(totalMs: stats!.totalMs, untrackedMs: stats!.untrackedMs),
          const SizedBox(height: 12),
          _ActivityBreakdown(
            byActivity: stats!.byActivity,
            activities: activities,
            onOpenDetail: onOpenActivityDetail,
          ),
          const SizedBox(height: 12),
          _CategoryBreakdown(
            byCategory: stats!.byCategory,
            onOpenDetail: onOpenCategoryDetail,
          ),
          const SizedBox(height: 12),
          _DayBreakdown(byDay: stats!.byDay),
        ]);
      }
      body = ListView(children: children);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        actionRow,
        const SizedBox(height: 16),
        Expanded(child: body),
      ],
    );
  }

  String _rangeLabel() {
    if (rangeFrom == 0 || rangeTo == 0) return '近7天 · 本地';
    final from = DateTime.fromMillisecondsSinceEpoch(rangeFrom);
    final to = DateTime.fromMillisecondsSinceEpoch(rangeTo);
    final fmt = DateFormat('M月d日');
    return '${fmt.format(from)} - ${fmt.format(to)} · 本地';
  }
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard({
    required this.snapshot,
    required this.activities,
    required this.onAdd,
    required this.onEdit,
  });

  final TimeGoalsSnapshot snapshot;
  final List<TimeActivity> activities;
  final VoidCallback? onAdd;
  final void Function(String activityId)? onEdit;

  @override
  Widget build(BuildContext context) {
    final goals = snapshot.goals;
    final activityMap = {for (final a in activities) a.id: a};

    final sorted = goals.toList()
      ..sort((a, b) {
        final aName = activityMap[a.activityId]?.name ?? a.activityId;
        final bName = activityMap[b.activityId]?.name ?? b.activityId;
        return aName.compareTo(bName);
      });

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined, color: AppColors.accentCool),
              const SizedBox(width: 8),
              Text(
                '目标',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              if (onAdd != null)
                OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('新增'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '时区 ${_formatUtcOffsetMinutes(snapshot.tzOffsetMinutes)} · 周起始 ${_weekStartLabel(snapshot.weekStart)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                ),
          ),
          const SizedBox(height: 12),
          if (sorted.isEmpty)
            Text(
              '暂无目标，点击“新增”开始设置。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            )
          else
            ...sorted.map((goal) {
              final activity = activityMap[goal.activityId];
              final name = activity?.name ?? '未命名事件';
              final category = activity?.category.trim() ?? '';
              final subtitle = category.isEmpty ? null : '分类：$category';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: onEdit == null ? null : () => onEdit!(goal.activityId),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            if (onEdit != null)
                              const Icon(Icons.chevron_right, color: AppColors.inkSoft),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.inkSoft,
                                ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _GoalLine(
                          label: '今日',
                          target: goal.targets.daily,
                          progress: goal.progress.daily,
                        ),
                        const SizedBox(height: 6),
                        _GoalLine(
                          label: '本周',
                          target: goal.targets.weekly,
                          progress: goal.progress.weekly,
                        ),
                        const SizedBox(height: 6),
                        _GoalLine(
                          label: '累计',
                          target: goal.targets.total,
                          progress: goal.progress.total,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _GoalLine extends StatelessWidget {
  const _GoalLine({
    required this.label,
    required this.target,
    required this.progress,
  });

  final String label;
  final TimeGoalPeriod target;
  final TimeGoalPeriod progress;

  @override
  Widget build(BuildContext context) {
    final hasDuration = target.durationMs > 0;
    final hasCount = target.count > 0;
    final parts = <String>[];
    if (hasDuration) {
      parts.add('${_formatDuration(progress.durationMs)} / ${_formatDuration(target.durationMs)}');
    }
    if (hasCount) {
      parts.add('${progress.count}/${target.count}次');
    }
    final text = parts.isEmpty ? '未设置' : parts.join(' · ');
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: parts.isEmpty ? AppColors.inkSoft : AppColors.ink,
                  fontWeight: parts.isEmpty ? FontWeight.w400 : FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalMs,
    required this.untrackedMs,
  });

  final int totalMs;
  final int untrackedMs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: AppColors.accent, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已记录',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDuration(totalMs),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                '未记录',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDuration(untrackedMs),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityBreakdown extends StatelessWidget {
  const _ActivityBreakdown({
    required this.byActivity,
    required this.activities,
    required this.onOpenDetail,
  });

  final Map<String, int> byActivity;
  final List<TimeActivity> activities;
  final void Function(String activityId)? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final activityMap = {for (final item in activities) item.id: item};
    final entries = byActivity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxMs = entries.isEmpty ? 0 : entries.map((e) => e.value).reduce(max);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '按事件汇总',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              '暂时没有事件统计。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            )
          else
            ...entries.map((entry) {
              final activity = activityMap[entry.key];
              final label = activity?.name ?? '未命名事件';
              final ratio = maxMs == 0 ? 0.0 : entry.value / maxMs;
              final row = Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.outline.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: Text(
                        _formatDuration(entry.value),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                      ),
                    ),
                  ],
                ),
              );

              final handler = onOpenDetail;
              if (handler == null) return row;
              return InkWell(
                onTap: () => handler(entry.key),
                borderRadius: BorderRadius.circular(12),
                child: row,
              );
            }),
        ],
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.byCategory,
    required this.onOpenDetail,
  });

  final Map<String, int> byCategory;
  final void Function(String category)? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxMs = entries.isEmpty ? 0 : entries.map((e) => e.value).reduce(max);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '按类别汇总',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              '暂时没有类别统计。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            )
          else
            ...entries.map((entry) {
              final label = entry.key.trim().isEmpty ? '未分类' : entry.key.trim();
              final ratio = maxMs == 0 ? 0.0 : entry.value / maxMs;
              final row = Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.outline.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.accentCool,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: Text(
                        _formatDuration(entry.value),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                      ),
                    ),
                  ],
                ),
              );

              final handler = onOpenDetail;
              if (handler == null) return row;
              return InkWell(
                onTap: () => handler(entry.key),
                borderRadius: BorderRadius.circular(12),
                child: row,
              );
            }),
        ],
      ),
    );
  }
}

class _DayBreakdown extends StatelessWidget {
  const _DayBreakdown({required this.byDay});

  final Map<String, int> byDay;

  @override
  Widget build(BuildContext context) {
    final entries = byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxMs = entries.isEmpty ? 0 : entries.map((e) => e.value).reduce(max);
    final fmt = DateFormat('M月d日');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每日趋势（本地）',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              '暂无每日统计。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            )
          else
            ...entries.map((entry) {
              final date = _parseDateKey(entry.key);
              final label = date == null ? entry.key : fmt.format(date);
              final ratio = maxMs == 0 ? 0.0 : entry.value / maxMs;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.outline.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.accentCool,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: Text(
                        _formatDuration(entry.value),
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.inkSoft,
                            ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

DateTime? _parseDateKey(String raw) {
  final parts = raw.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

String _formatUtcOffsetMinutes(int minutes) {
  final sign = minutes >= 0 ? '+' : '-';
  final abs = minutes.abs();
  final hh = (abs ~/ 60).toString().padLeft(2, '0');
  final mm = (abs % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hh:$mm';
}

String _weekStartLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'tuesday':
      return '周二';
    case 'wednesday':
      return '周三';
    case 'thursday':
      return '周四';
    case 'friday':
      return '周五';
    case 'saturday':
      return '周六';
    case 'sunday':
      return '周日';
    case 'monday':
    default:
      return '周一';
  }
}

String _formatDuration(int ms) {
  if (ms <= 0) return '0分钟';
  final totalSeconds = (ms / 1000).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours > 0) return '$hours小时${minutes}分钟';
  if (minutes > 0) return '$minutes分钟';
  return '${totalSeconds}秒';
}
