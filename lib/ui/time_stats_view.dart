import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/time_activity.dart';
import '../models/time_stats.dart';
import 'app_theme.dart';
import 'widgets/empty_state.dart';

class TimeStatsView extends StatelessWidget {
  const TimeStatsView({
    super.key,
    required this.stats,
    required this.activities,
    required this.loading,
    required this.rangeFrom,
    required this.rangeTo,
    required this.onRefresh,
  });

  final TimeStats? stats;
  final List<TimeActivity> activities;
  final bool loading;
  final int rangeFrom;
  final int rangeTo;
  final VoidCallback onRefresh;

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
    } else if (stats == null || (stats!.totalMs == 0 && stats!.byDay.isEmpty)) {
      body = Center(
        child: EmptyState(
          title: '暂无统计数据',
          subtitle: '先在时间记录里开始计时，再回来查看统计。',
        ),
      );
    } else {
      body = ListView(
        children: [
          _SummaryCard(totalMs: stats!.totalMs),
          const SizedBox(height: 12),
          _ActivityBreakdown(
            byActivity: stats!.byActivity,
            activities: activities,
          ),
          const SizedBox(height: 12),
          _DayBreakdown(byDay: stats!.byDay),
        ],
      );
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
    if (rangeFrom == 0 || rangeTo == 0) return '近7天 · UTC';
    final from = DateTime.fromMillisecondsSinceEpoch(rangeFrom, isUtc: true);
    final to = DateTime.fromMillisecondsSinceEpoch(rangeTo, isUtc: true);
    final fmt = DateFormat('M月d日');
    return '${fmt.format(from)} - ${fmt.format(to)} · UTC';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totalMs});

  final int totalMs;

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
                '总计时长',
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
  });

  final Map<String, int> byActivity;
  final List<TimeActivity> activities;

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
              return Padding(
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
            '每日趋势（UTC）',
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
              final date = DateTime.tryParse('${entry.key}T00:00:00Z');
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

String _formatDuration(int ms) {
  if (ms <= 0) return '0分钟';
  final totalSeconds = (ms / 1000).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours > 0) return '$hours小时${minutes}分钟';
  if (minutes > 0) return '$minutes分钟';
  return '${totalSeconds}秒';
}
