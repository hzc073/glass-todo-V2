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
      final startDateLabel = DateFormat('M月d日').format(date);
      final startTime = task.startTime.trim();
      final endRaw = task.endTime.trim();

      if (startTime.isEmpty && endRaw.isEmpty) return startDateLabel;

      int? parseTimeMinutes(String raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return null;
        final timePart = trimmed.split('+').first.trim();
        final parts = timePart.split(':');
        if (parts.length != 2) return null;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) return null;
        if (hour < 0 || hour > 24) return null;
        if (minute < 0 || minute > 59) return null;
        if (hour == 24 && minute != 0) return null;
        return hour * 60 + minute;
      }

      final startLabel =
          startTime.isEmpty ? startDateLabel : '$startDateLabel $startTime';
      if (endRaw.isEmpty) return startLabel;

      final plusIndex = endRaw.lastIndexOf('+');
      final hasExplicitOffset = plusIndex > 0;
      final explicitOffset = hasExplicitOffset
          ? (int.tryParse(endRaw.substring(plusIndex + 1).trim()) ?? 0)
          : 0;
      final timePart =
          (hasExplicitOffset ? endRaw.substring(0, plusIndex) : endRaw).trim();

      var offsetDays = explicitOffset.clamp(0, 1);
      var displayTime = timePart;
      if (timePart == '24:00') {
        offsetDays = 1;
        displayTime = '00:00';
      } else if (!hasExplicitOffset) {
        final startMinutes = parseTimeMinutes(startTime);
        final endMinutes = parseTimeMinutes(timePart);
        if (startMinutes != null &&
            endMinutes != null &&
            endMinutes <= startMinutes) {
          offsetDays = 1;
        }
      }

      if (offsetDays > 0) {
        final endDateLabel =
            DateFormat('M月d日').format(date.add(Duration(days: offsetDays)));
        return startTime.isEmpty
            ? '$startDateLabel - $endDateLabel $displayTime'
            : '$startDateLabel $startTime - $endDateLabel $displayTime';
      }

      return startTime.isEmpty
          ? '$startDateLabel $displayTime'
          : '$startDateLabel $startTime - $displayTime';
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
