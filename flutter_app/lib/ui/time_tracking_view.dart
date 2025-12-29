import 'dart:async';

import 'package:flutter/foundation.dart';
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
    this.onOpenStats,
    this.onOpenGoal,
  });

  final List<TimeActivity> activities;
  final List<TimeEntry> entries;
  final List<TimeEntry> runningEntries;
  final List<Task> tasks;
  final bool loading;
  final bool saving;
  final DateTime? lastSync;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddActivity;
  final Future<void> Function(TimeActivity) onToggleActivity;
  final Future<void> Function(TimeActivity) onEditActivity;
  final Future<void> Function(TimeActivity) onDeleteActivity;
  final Future<void> Function(TimeEntry entry)? onEditEntry;
  final VoidCallback? onOpenStats;
  final void Function(TimeActivity activity)? onOpenGoal;

  @override
  State<TimeTrackingView> createState() => _TimeTrackingViewState();
}

class _TimeTrackingViewState extends State<TimeTrackingView> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  bool get _hasRunning => widget.runningEntries.any((entry) => entry.isRunning);
  bool get _useAndroidUi =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    _now = DateTime.now();
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
      onStats: widget.onOpenStats,
    );

    final timerColumn = _TimerColumn(
      saving: widget.saving,
      loading: widget.loading,
      syncLabel: syncLabel,
      useSquareActivities: _useAndroidUi,
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
      onOpenGoal: widget.onOpenGoal,
    );

    final recordColumn = _RecordColumn(
      saving: widget.saving,
      now: _now,
      running: running,
      ended: ended,
      activityById: activityById,
      onEditEntry: widget.onEditEntry,
    );

    if (_useAndroidUi) {
      final safeBottom = MediaQuery.of(context).padding.bottom;
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: timerColumn,
          ),
          Positioned(
            left: 16,
            bottom: 16 + safeBottom,
            child: FloatingActionButton.small(
              heroTag: 'time_tracking_record_fab',
              onPressed: () => _openRecordSheet(
                context,
                recordColumn: recordColumn,
              ),
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.ink,
              child: const Icon(Icons.receipt_long),
            ),
          ),
          if (widget.onOpenStats != null)
            Positioned(
              left: 16,
              bottom: 16 + safeBottom + 56,
              child: FloatingActionButton.small(
                heroTag: 'time_tracking_stats_fab',
                onPressed: widget.onOpenStats,
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.ink,
                child: const Icon(Icons.bar_chart),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 16 + safeBottom,
            child: FloatingActionButton(
              heroTag: 'time_tracking_add_fab',
              onPressed: widget.saving ? null : widget.onAddActivity,
              backgroundColor: AppColors.accentCool,
              child: const Icon(Icons.add, size: 28),
            ),
          ),
        ],
      );
    }

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
    required this.onStats,
  });

  final bool saving;
  final bool loading;
  final String syncLabel;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  final VoidCallback? onStats;

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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: loading ? null : () => onRefresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
              if (onStats != null)
                OutlinedButton.icon(
                  onPressed: onStats,
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('统计'),
                ),
            ],
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
          onPressed: loading ? null : () => onRefresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('刷新'),
        ),
        if (onStats != null) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onStats,
            icon: const Icon(Icons.bar_chart),
            label: const Text('统计'),
          ),
        ],
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
    required this.syncLabel,
    required this.useSquareActivities,
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
    this.onOpenGoal,
  });

  final bool saving;
  final bool loading;
  final String syncLabel;
  final bool useSquareActivities;
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
  final void Function(TimeActivity activity)? onOpenGoal;

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${activities.length} 个',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 2),
              Text(
                syncLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (useSquareActivities)
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final activity in activities)
              _ActivitySquareTile(
                activity: activity,
                running: runningActivityIds.contains(activity.id),
                disabled: saving,
                onTap: () => onToggleActivity(activity),
                onGoal: onOpenGoal == null ? null : () => onOpenGoal!(activity),
                onEdit: () => onEditActivity(activity),
                onDelete: () => onDeleteActivity(activity),
              ),
          ],
        )
      else
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
                onGoal: onOpenGoal == null ? null : () => onOpenGoal!(activity),
                onEdit: () => onEditActivity(activity),
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
        physics: const AlwaysScrollableScrollPhysics(),
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
              physics: const AlwaysScrollableScrollPhysics(),
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
    required this.onEdit,
    required this.onDelete,
    this.onGoal,
  });

  final TimeActivity activity;
  final bool running;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onGoal;

  @override
  Widget build(BuildContext context) {
    final activityColor = _parseHexColor(activity.color) ?? AppColors.accentSoft;
    final title = activity.name.trim().isEmpty ? '未命名活动' : activity.name.trim();
    final bg = running ? activityColor.withOpacity(0.18) : Colors.white.withOpacity(0.85);
    final border = running ? activityColor.withOpacity(0.8) : AppColors.outline;

    Future<void> openMenu() async {
      if (disabled) return;
      final action = await showModalBottomSheet<_ActivityMenuAction>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onGoal != null)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('目标'),
                  onTap: () {
                    Navigator.of(context).pop(_ActivityMenuAction.goal);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑活动'),
                onTap: () {
                  Navigator.of(context).pop(_ActivityMenuAction.edit);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除活动'),
                onTap: () {
                  Navigator.of(context).pop(_ActivityMenuAction.delete);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      );
      switch (action) {
        case _ActivityMenuAction.goal:
          onGoal?.call();
          break;
        case _ActivityMenuAction.edit:
          onEdit();
          break;
        case _ActivityMenuAction.delete:
          onDelete();
          break;
        case null:
          break;
      }
    }

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
            onTap: disabled ? null : openMenu,
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
        onLongPress: disabled ? null : onEdit,
        borderRadius: BorderRadius.circular(14),
        child: chip,
      ),
    );
  }
}

class _ActivitySquareTile extends StatelessWidget {
  const _ActivitySquareTile({
    required this.activity,
    required this.running,
    required this.disabled,
    required this.onTap,
    this.onGoal,
    required this.onEdit,
    required this.onDelete,
  });

  static const double _size = 104;

  final TimeActivity activity;
  final bool running;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback? onGoal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final activityColor = _parseHexColor(activity.color) ?? AppColors.accentSoft;
    final title = activity.name.trim().isEmpty ? '未命名活动' : activity.name.trim();
    final bg = running ? activityColor.withOpacity(0.18) : Colors.white.withOpacity(0.85);
    final border = running ? activityColor.withOpacity(0.8) : AppColors.outline;

    Future<void> openMenu() async {
      if (disabled) return;
      final action = await showModalBottomSheet<_ActivityMenuAction>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onGoal != null)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('目标'),
                  onTap: () {
                    Navigator.of(context).pop(_ActivityMenuAction.goal);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('编辑活动'),
                onTap: () {
                  Navigator.of(context).pop(_ActivityMenuAction.edit);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除活动'),
                onTap: () {
                  Navigator.of(context).pop(_ActivityMenuAction.delete);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      );
      switch (action) {
        case _ActivityMenuAction.goal:
          onGoal?.call();
          break;
        case _ActivityMenuAction.edit:
          onEdit();
          break;
        case _ActivityMenuAction.delete:
          onDelete();
          break;
        case null:
          break;
      }
    }

    return SizedBox(
      width: _size,
      height: _size,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: disabled ? null : onTap,
          onLongPress: disabled ? null : openMenu,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: activityColor.withOpacity(0.22),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _activityIcon(activity, title),
                              style: _emojiStyle(
                                Theme.of(context).textTheme.labelLarge,
                                color: AppColors.ink,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: _AutoFittingText(
                          title,
                          maxLines: 3,
                          maxFontSize: 13,
                          minFontSize: 8,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    onPressed: disabled ? null : openMenu,
                    icon: const Icon(Icons.more_vert, size: 18),
                    color: AppColors.inkSoft,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    tooltip: '更多',
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

enum _ActivityMenuAction { goal, edit, delete }

class _AutoFittingText extends StatelessWidget {
  const _AutoFittingText(
    this.text, {
    required this.maxLines,
    required this.maxFontSize,
    required this.minFontSize,
    required this.style,
    required this.textAlign,
  });

  final String text;
  final int maxLines;
  final double maxFontSize;
  final double minFontSize;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodySmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final direction = Directionality.of(context);
        double chosen = minFontSize;
        for (double size = maxFontSize; size >= minFontSize; size -= 1) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: baseStyle?.copyWith(fontSize: size)),
            textDirection: direction,
            maxLines: maxLines,
          )..layout(maxWidth: constraints.maxWidth);
          if (!painter.didExceedMaxLines &&
              painter.height <= constraints.maxHeight + 0.5) {
            chosen = size;
            break;
          }
        }
        return Text(
          text,
          maxLines: maxLines,
          softWrap: true,
          textAlign: textAlign,
          style: baseStyle?.copyWith(fontSize: chosen),
        );
      },
    );
  }
}

Future<void> _openRecordSheet(
  BuildContext context, {
  required Widget recordColumn,
}) async {
  final height = MediaQuery.of(context).size.height * 0.85;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          height: height,
          child: recordColumn,
        ),
      ),
    ),
  );
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
