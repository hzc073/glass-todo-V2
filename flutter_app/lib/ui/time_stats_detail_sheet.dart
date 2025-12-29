import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../models/time_activity.dart';
import '../models/time_stats_detail.dart';
import 'app_theme.dart';
import 'widgets/empty_state.dart';

class TimeStatsDetailSheet extends StatefulWidget {
  const TimeStatsDetailSheet({
    super.key,
    required this.apiClient,
    required this.activities,
    required this.rangeFrom,
    required this.rangeTo,
    required this.tzOffsetMinutes,
    required this.type,
    required this.id,
  });

  final ApiClient apiClient;
  final List<TimeActivity> activities;
  final int rangeFrom;
  final int rangeTo;
  final int tzOffsetMinutes;
  final String type;
  final String id;

  @override
  State<TimeStatsDetailSheet> createState() => _TimeStatsDetailSheetState();
}

class _TimeStatsDetailSheetState extends State<TimeStatsDetailSheet> {
  bool _loading = false;
  TimeStatsDetail? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _title {
    final type = widget.type.trim().toLowerCase();
    if (type == 'activity') {
      final activity = widget.activities
          .cast<TimeActivity?>()
          .firstWhere((a) => a?.id == widget.id, orElse: () => null);
      return activity?.name ?? '事件详情';
    }
    if (type == 'category') {
      final label = widget.id.trim();
      return label.isEmpty ? '未分类' : label;
    }
    return '详情';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail = await widget.apiClient.getTimeStatsDetail(
        from: widget.rangeFrom,
        to: widget.rangeTo,
        type: widget.type,
        id: widget.id,
        tzOffsetMinutes: widget.tzOffsetMinutes,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载详情失败。')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '返回',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : detail == null
                    ? Center(
                        child: EmptyState(
                          title: '暂无详情数据',
                          subtitle: '稍后重试或先添加一些时间记录。',
                        ),
                      )
                    : _DetailBody(detail: detail, title: _title),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.title,
  });

  final TimeStatsDetail detail;
  final String title;

  @override
  Widget build(BuildContext context) {
    final byDayEntries = detail.byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxDayMs = byDayEntries.isEmpty
        ? 0
        : byDayEntries.map((e) => e.value.totalMs).reduce(max);
    final dayFmt = DateFormat('M月d日');

    final hourly = detail.hourly.length == 24 ? detail.hourly : List<int>.filled(24, 0);
    final maxHourMs = hourly.isEmpty ? 0 : hourly.reduce(max);

    final weekday = detail.weekday.length == 7 ? detail.weekday : List<int>.filled(7, 0);
    final maxWeekdayMs = weekday.isEmpty ? 0 : weekday.reduce(max);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryCard(
          title: title,
          totalMs: detail.totalMs,
          count: detail.count,
        ),
        const SizedBox(height: 12),
        _BarCard(
          title: '每日趋势（本地）',
          emptyText: '暂无每日数据。',
          maxValue: maxDayMs,
          rows: byDayEntries.map((entry) {
            final date = _parseDateKey(entry.key);
            final label = date == null ? entry.key : dayFmt.format(date);
            return _BarRow(
              label: label,
              valueMs: entry.value.totalMs,
              valueLabel: '${_formatDuration(entry.value.totalMs)} · ${entry.value.count}次',
              barColor: AppColors.accentCool,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _BarCard(
          title: '小时分布（本地）',
          emptyText: '暂无小时分布数据。',
          maxValue: maxHourMs,
          rows: List.generate(24, (hour) {
            final label = hour.toString().padLeft(2, '0');
            final value = hourly[hour];
            return _BarRow(
              label: label,
              valueMs: value,
              valueLabel: _formatDuration(value),
              barColor: AppColors.accent,
            );
          }),
        ),
        const SizedBox(height: 12),
        _BarCard(
          title: '星期分布（本地）',
          emptyText: '暂无星期分布数据。',
          maxValue: maxWeekdayMs,
          rows: List.generate(7, (index) {
            const labels = ['一', '二', '三', '四', '五', '六', '日'];
            final value = weekday[index];
            return _BarRow(
              label: labels[index],
              valueMs: value,
              valueLabel: _formatDuration(value),
              barColor: AppColors.accentCool,
            );
          }),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.totalMs,
    required this.count,
  });

  final String title;
  final int totalMs;
  final int count;

  @override
  Widget build(BuildContext context) {
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
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(label: '总时长', value: _formatDuration(totalMs)),
              _Metric(label: '次数', value: '$count'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _BarCard extends StatelessWidget {
  const _BarCard({
    required this.title,
    required this.emptyText,
    required this.maxValue,
    required this.rows,
  });

  final String title;
  final String emptyText;
  final int maxValue;
  final List<_BarRow> rows;

  @override
  Widget build(BuildContext context) {
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
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              emptyText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
            )
          else
            ...rows.map((row) {
              final ratio = maxValue <= 0 ? 0.0 : row.valueMs / maxValue;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        row.label,
                        overflow: TextOverflow.ellipsis,
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
                            widthFactor: ratio.clamp(0.0, 1.0),
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: row.barColor,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: Text(
                        row.valueLabel,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
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

class _BarRow {
  const _BarRow({
    required this.label,
    required this.valueMs,
    required this.valueLabel,
    required this.barColor,
  });

  final String label;
  final int valueMs;
  final String valueLabel;
  final Color barColor;
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

String _formatDuration(int ms) {
  if (ms <= 0) return '0分钟';
  final totalSeconds = (ms / 1000).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours > 0) return '$hours小时${minutes}分钟';
  if (minutes > 0) return '$minutes分钟';
  return '${totalSeconds}秒';
}
