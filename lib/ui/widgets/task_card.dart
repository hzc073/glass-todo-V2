import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/task.dart';
import '../app_theme.dart';
import '../task_colors.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    this.onTap,
    this.onEditTitle,
    this.isSelected = false,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onEditTitle;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final isDone = task.isCompleted;
    final cardColor = TaskColors.resolveBackground(task.id, task.colorHex);
    final dueLabel = _buildDueLabel(task);
    final metaPills = <Widget>[];
    if (dueLabel != null) {
      metaPills.add(
        _MetaPill(
          label: dueLabel,
          color: AppColors.accentCool,
          compact: true,
        ),
      );
    }
    if (task.inbox && !isDone) {
      metaPills.add(
        const _MetaPill(
          label: '收集箱',
          color: AppColors.accentSoft,
          compact: true,
        ),
      );
    }
    for (final tag in task.displayTags) {
      metaPills.add(_MetaPill(label: tag, color: AppColors.accent, compact: true));
    }
    final titleText = Text(
      task.title.isEmpty ? '未命名任务' : task.title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? AppColors.inkSoft : AppColors.ink,
          ),
    );
    final titleWidget = onEditTitle == null
        ? titleText
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEditTitle,
            child: titleText,
          );
    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(
          color: isSelected ? AppColors.accent : AppColors.outline,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusToggle(isDone: isDone, onTap: onToggle),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (metaPills.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [titleWidget, ...metaPills],
                      )
                    else
                      titleWidget,
                    if (task.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        task.notes,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _buildDueLabel(Task task) {
    if (task.dueDate.trim().isEmpty) return null;
    try {
      final date = DateFormat('yyyy-MM-dd').parse(task.dueDate);
      final friendly = DateFormat('M月d日').format(date);
      if (task.startTime.trim().isNotEmpty || task.endTime.trim().isNotEmpty) {
        final start = task.startTime.trim();
        final end = task.endTime.trim();
        final range = [start, end].where((value) => value.isNotEmpty).join(' - ');
        return '$friendly $range';
      }
      return friendly;
    } catch (_) {
      return task.dueDate;
    }
  }
}

class _StatusToggle extends StatelessWidget {
  const _StatusToggle({required this.isDone, required this.onTap});

  final bool isDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isDone ? AppColors.accentCool : AppColors.outline,
            width: 2,
          ),
          color: isDone ? AppColors.accentCool : Colors.transparent,
        ),
        child: isDone
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 6);
    final textStyle = (compact
            ? Theme.of(context).textTheme.labelSmall
            : Theme.of(context).textTheme.labelMedium)
        ?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        );
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: textStyle,
      ),
    );
  }
}
