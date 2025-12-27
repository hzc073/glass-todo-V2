import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pomodoro_session.dart';
import '../models/pomodoro_summary.dart';
import '../models/task.dart';
import '../models/time_stats.dart';
import 'app_theme.dart';
import 'widgets/empty_state.dart';

enum _StatsSection { home, yesterday, events }

class StatsDashboardView extends StatefulWidget {
  const StatsDashboardView({
    super.key,
    required this.tasks,
    required this.timeStats,
    required this.pomodoroSummary,
    required this.pomodoroSessions,
    required this.loading,
    required this.onRefresh,
  });

  final List<Task> tasks;
  final TimeStats? timeStats;
  final PomodoroSummary? pomodoroSummary;
  final List<PomodoroSession> pomodoroSessions;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  State<StatsDashboardView> createState() => _StatsDashboardViewState();
}

class _StatsDashboardViewState extends State<StatsDashboardView> {
  _StatsSection _section = _StatsSection.home;

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks;
    final timeStats = widget.timeStats;
    final pomodoroSummary = widget.pomodoroSummary;
    final pomodoroSessions = widget.pomodoroSessions;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateKeyFmt = DateFormat('yyyy-MM-dd');

    final yesterdayKey = dateKeyFmt.format(yesterday);
    final utcYesterdayKey = dateKeyFmt
        .format(DateTime.now().toUtc().subtract(const Duration(days: 1)));

    final allTasks = tasks.where((task) => task.deletedAt == null).toList();
    final tasksByDayKey = <String, List<Task>>{};
    for (final task in allTasks) {
      final key = task.dueDate.trim();
      if (key.isEmpty) continue;
      tasksByDayKey.putIfAbsent(key, () => []).add(task);
    }

    final last7Days =
        List.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
    final pomodoroTrend = <_DayValue>[];
    final taskWorkloadTrend = <_DayValue>[];
    final taskMissTrend = <_DayValue>[];
    for (final day in last7Days) {
      final key = dateKeyFmt.format(day);
      final pomodoroMin = pomodoroSummary?.days[key]?.workMinutes ?? 0;
      pomodoroTrend.add(
          _DayValue(label: _weekdayLabel(day), value: pomodoroMin.toDouble()));

      final dayTasks = tasksByDayKey[key] ?? const <Task>[];
      final workloadMin =
          dayTasks.fold<int>(0, (sum, task) => sum + _taskPlannedMinutes(task));
      final missedCount = dayTasks.where((task) => !task.isCompleted).length;
      taskWorkloadTrend.add(
          _DayValue(label: _weekdayLabel(day), value: workloadMin.toDouble()));
      taskMissTrend.add(
          _DayValue(label: _weekdayLabel(day), value: missedCount.toDouble()));
    }

    final yesterdayPomodoroMin =
        pomodoroSummary?.days[yesterdayKey]?.workMinutes ?? 0;
    final yesterdayHeat = _buildHourHeatmap(pomodoroSessions, day: yesterday);

    final yesterdayEventMs = timeStats?.byDay[utcYesterdayKey] ?? 0;

    final dueLast7Keys = last7Days.map(dateKeyFmt.format).toSet();
    final tasksLast7 = [
      for (final key in dueLast7Keys) ...(tasksByDayKey[key] ?? const <Task>[]),
    ];
    final completedLast7 = tasksLast7.where((task) => task.isCompleted).length;
    final plannedMinLast7 =
        tasksLast7.fold<int>(0, (sum, task) => sum + _taskPlannedMinutes(task));
    final completionRate =
        tasksLast7.isEmpty ? null : completedLast7 / tasksLast7.length;

    final totalCompleted = allTasks.where((task) => task.isCompleted).length;

    final weekdayMost = _mostProductiveWeekday(allTasks, today: today);
    final timeControl = _timeControlScore(
      completed: completedLast7,
      total: tasksLast7.length,
      plannedMinutes: plannedMinLast7,
      focusMinutes:
          pomodoroTrend.fold<int>(0, (sum, item) => sum + item.value.round()),
    );

    final hasAnyData =
        tasks.isNotEmpty || timeStats != null || pomodoroSummary != null;
    final data = _StatsComputed(
      hasAnyData: hasAnyData,
      yesterdayEventMs: yesterdayEventMs,
      yesterdayPomodoroMin: yesterdayPomodoroMin,
      pomodoroTrend: pomodoroTrend,
      yesterdayHeat: yesterdayHeat,
      completedLast7: completedLast7,
      plannedMinLast7: plannedMinLast7,
      taskWorkloadTrend: taskWorkloadTrend,
      taskMissTrend: taskMissTrend,
      completionRate: completionRate,
      totalCountLast7: tasksLast7.length,
      totalCompleted: totalCompleted,
      weekdayMost: weekdayMost,
      timeControl: timeControl,
    );

    final scrollable = switch (_section) {
      _StatsSection.home => _buildHome(context, data),
      _StatsSection.yesterday => _buildYesterdayPage(context, data),
      _StatsSection.events => _buildEventsPage(context, data),
    };

    return Stack(
      children: [
        RefreshIndicator(onRefresh: widget.onRefresh, child: scrollable),
        if (widget.loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  ListView _buildHome(BuildContext context, _StatsComputed data) {
    final completion = data.completionRate == null
        ? '—'
        : '${(data.completionRate!.clamp(0.0, 1.0) * 100).round()}%';

    return ListView(
      key: const ValueKey('stats_home'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Spacer(),
            OutlinedButton.icon(
              onPressed: widget.loading
                  ? null
                  : () {
                      widget.onRefresh();
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
        if (!data.hasAnyData) ...[
          const SizedBox(height: 12),
          const EmptyState(
            title: '暂无统计数据',
            subtitle: '先添加任务或使用番茄钟/时间记录，再回来查看统计。',
          ),
        ],
        const SizedBox(height: 12),
        _NavCard(
          title: '昨日小结',
          subtitle: '事件工作量、番茄专注趋势、热力图',
          icon: Icons.summarize_outlined,
          accent: AppColors.accentCool,
          metrics: [
            ('事件工作量', _formatDurationMs(data.yesterdayEventMs)),
            ('番茄专注', _formatMinutes(data.yesterdayPomodoroMin)),
          ],
          onTap: () => setState(() => _section = _StatsSection.yesterday),
        ),
        const SizedBox(height: 12),
        _NavCard(
          title: '事件统计',
          subtitle: '达成数、工作量趋势、完成率、拖延趋势',
          icon: Icons.query_stats,
          accent: AppColors.accent,
          metrics: [
            ('近7天达成', '${data.completedLast7}'),
            ('完成率', completion),
          ],
          onTap: () => setState(() => _section = _StatsSection.events),
        ),
      ],
    );
  }

  ListView _buildYesterdayPage(BuildContext context, _StatsComputed data) {
    return ListView(
      key: const ValueKey('stats_yesterday'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _PageHeader(
          title: '昨日小结',
          onBack: () => setState(() => _section = _StatsSection.home),
          onRefresh: widget.loading ? null : widget.onRefresh,
        ),
        const SizedBox(height: 12),
        if (!data.hasAnyData) ...[
          const EmptyState(
            title: '暂无统计数据',
            subtitle: '先添加任务或使用番茄钟/时间记录，再回来查看统计。',
          ),
        ] else ...[
          _DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.work_outline,
                        label: '事件工作量',
                        value: _formatDurationMs(data.yesterdayEventMs),
                        accent: AppColors.accentCool,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricTile(
                        icon: Icons.timer_outlined,
                        label: '番茄专注时长',
                        value: _formatMinutes(data.yesterdayPomodoroMin),
                        accent: AppColors.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _SubTitle(text: '工作量趋势（番茄专注）'),
                const SizedBox(height: 8),
                _LineChart(values: data.pomodoroTrend, unitLabel: 'min'),
                const SizedBox(height: 14),
                const _SubTitle(text: '昨日番茄专注热力图'),
                const SizedBox(height: 8),
                _Heatmap24h(values: data.yesterdayHeat),
              ],
            ),
          ),
        ],
      ],
    );
  }

  ListView _buildEventsPage(BuildContext context, _StatsComputed data) {
    return ListView(
      key: const ValueKey('stats_events'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _PageHeader(
          title: '事件统计',
          onBack: () => setState(() => _section = _StatsSection.home),
          onRefresh: widget.loading ? null : widget.onRefresh,
        ),
        const SizedBox(height: 12),
        if (!data.hasAnyData) ...[
          const EmptyState(
            title: '暂无统计数据',
            subtitle: '先添加任务或使用番茄钟/时间记录，再回来查看统计。',
          ),
        ] else ...[
          _DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _CompactMetric(
                      label: '任务达成数（近7天）',
                      value: '${data.completedLast7}',
                    ),
                    _CompactMetric(
                      label: '任务工作量（近7天）',
                      value: _formatMinutes(data.plannedMinLast7),
                    ),
                    _CompactMetric(
                      label: '历史累计达成',
                      value: '${data.totalCompleted}',
                    ),
                    _CompactMetric(
                      label: '周几最勤奋',
                      value: data.weekdayMost ?? '—',
                    ),
                    _CompactMetric(
                      label: '时间掌控度',
                      value: data.timeControl.label,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _SubTitle(text: '工作量趋势（任务）'),
                const SizedBox(height: 8),
                _LineChart(values: data.taskWorkloadTrend, unitLabel: 'min'),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 520;
                    final completion = _DashboardPanel(
                      title: '任务完成率',
                      child: _PieChart(
                        completedRatio: data.completionRate,
                        completedLabel: '${data.completedLast7}',
                        totalLabel: '${data.totalCountLast7}',
                      ),
                    );
                    final procrastination = _DashboardPanel(
                      title: '拖延症趋势（未达成）',
                      child: _LineChart(
                          values: data.taskMissTrend, unitLabel: 'count'),
                    );
                    if (isNarrow) {
                      return Column(
                        children: [
                          completion,
                          const SizedBox(height: 12),
                          procrastination,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: completion),
                        const SizedBox(width: 12),
                        Expanded(child: procrastination),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatsComputed {
  const _StatsComputed({
    required this.hasAnyData,
    required this.yesterdayEventMs,
    required this.yesterdayPomodoroMin,
    required this.pomodoroTrend,
    required this.yesterdayHeat,
    required this.completedLast7,
    required this.plannedMinLast7,
    required this.taskWorkloadTrend,
    required this.taskMissTrend,
    required this.completionRate,
    required this.totalCompleted,
    required this.weekdayMost,
    required this.timeControl,
    required this.totalCountLast7,
  });

  final bool hasAnyData;

  final int yesterdayEventMs;
  final int yesterdayPomodoroMin;
  final List<_DayValue> pomodoroTrend;
  final List<double> yesterdayHeat;

  final int completedLast7;
  final int plannedMinLast7;
  final List<_DayValue> taskWorkloadTrend;
  final List<_DayValue> taskMissTrend;
  final double? completionRate;
  final int totalCountLast7;

  final int totalCompleted;
  final String? weekdayMost;
  final _TimeControl timeControl;
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.onBack,
    required this.onRefresh,
  });

  final String title;
  final VoidCallback onBack;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.chevron_left),
          tooltip: '返回',
        ),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: onRefresh == null
              ? null
              : () {
                  onRefresh!();
                },
          icon: const Icon(Icons.refresh),
          label: const Text('刷新'),
        ),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.metrics,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<(String, String)> metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withOpacity(0.22)),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.inkSoft),
                    ),
                    if (metrics.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final item in metrics)
                            _NavMetric(label: item.$1, value: item.$2),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right,
                    color: AppColors.inkSoft.withOpacity(0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavMetric extends StatelessWidget {
  const _NavMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title?.trim().isNotEmpty == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTitle) ...[
              Text(
                title!,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SubTitle extends StatelessWidget {
  const _SubTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.inkSoft,
          ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.25)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _DayValue {
  const _DayValue({required this.label, required this.value});

  final String label;
  final double value;
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.values, required this.unitLabel});

  final List<_DayValue> values;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.isEmpty
        ? 0.0
        : values.map((item) => item.value).reduce(math.max);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    return Column(
      children: [
        SizedBox(
          height: 86,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _LineChartPainter(values: values, maxValue: safeMax),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Text(
                  _unitLabel(unitLabel),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final item in values)
              Expanded(
                child: Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _unitLabel(String raw) {
  final value = raw.trim().toLowerCase();
  return switch (value) {
    'min' => '分钟',
    'count' => '个',
    _ => raw,
  };
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.values, required this.maxValue});

  final List<_DayValue> values;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    const padding = 8.0;
    final plotHeight = (size.height - padding * 2).clamp(0.0, double.infinity);
    final baselineY = padding + plotHeight;

    final gridPaint = Paint()
      ..color = AppColors.outline.withOpacity(0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(0, baselineY), Offset(size.width, baselineY), gridPaint);
    canvas.drawLine(
      Offset(0, padding + plotHeight / 2),
      Offset(size.width, padding + plotHeight / 2),
      gridPaint..color = AppColors.outline.withOpacity(0.35),
    );

    final points = <Offset>[];
    final count = values.length;
    for (var i = 0; i < count; i++) {
      final x = count == 1 ? size.width / 2 : size.width * (i / (count - 1));
      final ratio = (values[i].value / maxValue).clamp(0.0, 1.0);
      final y = padding + (1 - ratio) * plotHeight;
      points.add(Offset(x, y));
    }

    final fillPaint = Paint()
      ..color = AppColors.accentCool.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = AppColors.accentCool
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotBgPaint = Paint()..color = AppColors.surface;
    final dotPaint = Paint()..color = AppColors.accentCool;

    if (points.length == 1) {
      canvas.drawCircle(points.first, 4, dotBgPaint);
      canvas.drawCircle(points.first, 3, dotPaint);
      return;
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final areaPath = Path.from(linePath)
      ..lineTo(points.last.dx, baselineY)
      ..lineTo(points.first.dx, baselineY)
      ..close();

    canvas.drawPath(areaPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
    for (final point in points) {
      canvas.drawCircle(point, 4, dotBgPaint);
      canvas.drawCircle(point, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.maxValue != maxValue || oldDelegate.values != values;
  }
}

class _PieChart extends StatelessWidget {
  const _PieChart({
    required this.completedRatio,
    required this.completedLabel,
    required this.totalLabel,
  });

  final double? completedRatio;
  final String completedLabel;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final ratio = completedRatio?.clamp(0.0, 1.0);
    final label = ratio == null ? '—' : '${(ratio * 100).round()}%';
    return Center(
      child: SizedBox(
        width: 140,
        height: 140,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PiePainter(ratio: ratio),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$completedLabel / $totalLabel',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  const _PiePainter({required this.ratio});

  final double? ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = AppColors.outline.withOpacity(0.7)
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..color = AppColors.accentCool
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, bgPaint);
    final value = ratio ?? 0.0;
    final startAngle = -math.pi / 2;
    canvas.drawArc(rect, startAngle, math.pi * 2 * value, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.ratio != ratio;
}

class _Heatmap24h extends StatelessWidget {
  const _Heatmap24h({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.isEmpty ? 0.0 : values.reduce(math.max);
    if (maxValue <= 0) {
      return Text(
        '昨日暂无番茄专注记录。',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.inkSoft),
      );
    }

    const cols = 12;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: 24,
      itemBuilder: (context, index) {
        final minutes = index < values.length ? values[index] : 0.0;
        final ratio = (minutes / maxValue).clamp(0.0, 1.0);
        final color = AppColors.accentCool.withOpacity(0.15 + 0.8 * ratio);
        return Tooltip(
          message:
              '${index.toString().padLeft(2, '0')}:00  ${minutes.toStringAsFixed(0)}m',
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.outline.withOpacity(0.7)),
            ),
          ),
        );
      },
    );
  }
}

List<double> _buildHourHeatmap(List<PomodoroSession> sessions,
    {required DateTime day}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  final buckets = List<double>.filled(24, 0.0);

  for (final session in sessions) {
    final ended = DateTime.fromMillisecondsSinceEpoch(session.endedAt);
    final approxStarted = session.startedAt == null
        ? ended.subtract(Duration(minutes: math.max(1, session.durationMin)))
        : DateTime.fromMillisecondsSinceEpoch(session.startedAt!);

    final start = approxStarted.isAfter(dayStart) ? approxStarted : dayStart;
    final end = ended.isBefore(dayEnd) ? ended : dayEnd;
    if (!end.isAfter(start)) continue;

    for (var hour = 0; hour < 24; hour++) {
      final hourStart =
          DateTime(dayStart.year, dayStart.month, dayStart.day, hour);
      final hourEnd = hourStart.add(const Duration(hours: 1));
      final segStart = start.isAfter(hourStart) ? start : hourStart;
      final segEnd = end.isBefore(hourEnd) ? end : hourEnd;
      if (!segEnd.isAfter(segStart)) continue;
      buckets[hour] += segEnd.difference(segStart).inMilliseconds / 60000.0;
    }
  }

  return buckets;
}

int _taskPlannedMinutes(Task task) {
  final start = _parseTimeToMinutes(task.startTime);
  if (start == null) return 0;
  final end = _parseTimeToMinutes(task.endTime);
  if (end != null && end > start) return end - start;
  return (start + 30).clamp(0, 24 * 60) - start;
}

int? _parseTimeToMinutes(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 24) return null;
  if (minute < 0 || minute > 59) return null;
  if (hour == 24 && minute != 0) return null;
  return hour * 60 + minute;
}

String _weekdayLabel(DateTime date) {
  return switch (date.weekday) {
    DateTime.monday => '一',
    DateTime.tuesday => '二',
    DateTime.wednesday => '三',
    DateTime.thursday => '四',
    DateTime.friday => '五',
    DateTime.saturday => '六',
    DateTime.sunday => '日',
    _ => '',
  };
}

String? _mostProductiveWeekday(List<Task> tasks, {required DateTime today}) {
  final start = today.subtract(const Duration(days: 29));
  final fmt = DateFormat('yyyy-MM-dd');
  final startKey = fmt.format(start);
  final endKey = fmt.format(today);
  final counts = List<int>.filled(7, 0);
  for (final task in tasks) {
    if (!task.isCompleted) continue;
    final key = task.dueDate.trim();
    if (key.isEmpty) continue;
    if (key.compareTo(startKey) < 0 || key.compareTo(endKey) > 0) continue;
    final date = DateTime.tryParse('${key}T00:00:00');
    if (date == null) continue;
    counts[date.weekday - 1] += 1;
  }
  final maxValue = counts.reduce(math.max);
  if (maxValue <= 0) return null;
  final index = counts.indexOf(maxValue);
  final weekday = index + 1;
  return switch (weekday) {
    DateTime.monday => '周一',
    DateTime.tuesday => '周二',
    DateTime.wednesday => '周三',
    DateTime.thursday => '周四',
    DateTime.friday => '周五',
    DateTime.saturday => '周六',
    DateTime.sunday => '周日',
    _ => null,
  };
}

_TimeControl _timeControlScore({
  required int completed,
  required int total,
  required int plannedMinutes,
  required int focusMinutes,
}) {
  final completion = total <= 0 ? null : completed / total;
  final focusRatio = plannedMinutes <= 0 ? null : focusMinutes / plannedMinutes;
  final focusScore = focusRatio == null ? null : focusRatio.clamp(0.0, 1.0);

  final score = switch ((completion, focusScore)) {
    (final c?, final f?) => c * 0.6 + f * 0.4,
    (final c?, null) => c,
    (null, final f?) => f,
    _ => 0.0,
  };

  final percent = (score * 100).round();
  final label = switch (percent) {
    >= 85 => '掌控良好 · $percent%',
    >= 60 => '基本掌控 · $percent%',
    >= 35 => '略有失控 · $percent%',
    _ => '需要调整 · $percent%',
  };
  return _TimeControl(label: label);
}

class _TimeControl {
  const _TimeControl({required this.label});

  final String label;
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) return '0分钟';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours > 0) return '${hours}小时${mins}分钟';
  return '${mins}分钟';
}

String _formatDurationMs(int ms) {
  if (ms <= 0) return '0分钟';
  final totalSeconds = (ms / 1000).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours > 0) return '$hours小时${minutes}分钟';
  if (minutes > 0) return '$minutes分钟';
  return '${totalSeconds}秒';
}
