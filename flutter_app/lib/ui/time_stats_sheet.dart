import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/time_activity.dart';
import '../models/time_goals.dart';
import '../models/time_stats.dart';
import 'app_theme.dart';
import 'time_goal_editor_sheet.dart';
import 'time_stats_detail_sheet.dart';
import 'time_stats_view.dart';

class TimeStatsSheet extends StatefulWidget {
  const TimeStatsSheet({
    super.key,
    required this.apiClient,
    required this.activities,
    required this.tzOffsetMinutes,
  });

  final ApiClient apiClient;
  final List<TimeActivity> activities;
  final int tzOffsetMinutes;

  @override
  State<TimeStatsSheet> createState() => _TimeStatsSheetState();
}

class _TimeStatsSheetState extends State<TimeStatsSheet> {
  int _rangeFrom = 0;
  int _rangeTo = 0;
  bool _loading = false;
  TimeStats? _stats;
  TimeGoalsSnapshot? _goals;

  @override
  void initState() {
    super.initState();
    _setDefaultRange();
    _load();
  }

  void _setDefaultRange() {
    const dayMs = 24 * 60 * 60 * 1000;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final offsetMs = widget.tzOffsetMinutes * 60 * 1000;
    final startOfTodayMs = ((nowMs + offsetMs) ~/ dayMs) * dayMs - offsetMs;
    _rangeFrom = startOfTodayMs - (dayMs * 6);
    _rangeTo = nowMs;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await widget.apiClient.getTimeStats(
        from: _rangeFrom,
        to: _rangeTo,
        tzOffsetMinutes: widget.tzOffsetMinutes,
      );
      if (!mounted) return;
      setState(() => _stats = stats);

      try {
        final goals = await widget.apiClient.getTimeGoals(
          tzOffsetMinutes: widget.tzOffsetMinutes,
        );
        if (!mounted) return;
        setState(() => _goals = goals);
      } on UnauthorizedException {
        rethrow;
      } catch (_) {}
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载时间统计失败。')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openGoalEditor({String? activityId}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: TimeGoalEditorSheet(
          apiClient: widget.apiClient,
          activities: widget.activities,
          existingGoals: _goals?.goals ?? const <TimeGoalItem>[],
          initialActivityId: activityId,
        ),
      ),
    );
    if (result == true) {
      await _load();
    }
  }

  void _openDetail({required String type, required String id}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: TimeStatsDetailSheet(
          apiClient: widget.apiClient,
          activities: widget.activities,
          rangeFrom: _rangeFrom,
          rangeTo: _rangeTo,
          tzOffsetMinutes: widget.tzOffsetMinutes,
          type: type,
          id: id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '时间统计',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TimeStatsView(
                stats: _stats,
                goals: _goals,
                activities: widget.activities,
                loading: _loading,
                rangeFrom: _rangeFrom,
                rangeTo: _rangeTo,
                onRefresh: _load,
                onAddGoal: () => _openGoalEditor(),
                onEditGoal: (activityId) => _openGoalEditor(activityId: activityId),
                onOpenActivityDetail: (activityId) => _openDetail(
                  type: 'activity',
                  id: activityId,
                ),
                onOpenCategoryDetail: (category) => _openDetail(
                  type: 'category',
                  id: category,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
