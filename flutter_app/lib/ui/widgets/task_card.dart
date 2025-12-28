import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dart:convert';

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
    final remindLabel = _buildRemindLabel(task);
    final repeatLabel = _buildRepeatLabel(task.repeatRule);
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
    if (remindLabel != null) {
      metaPills.add(
        _MetaPill(
          icon: Icons.notifications_active_outlined,
          label: remindLabel,
          color: AppColors.inkSoft,
          compact: true,
        ),
      );
    }
    if (repeatLabel != null) {
      metaPills.add(
        _MetaPill(
          icon: Icons.repeat,
          label: repeatLabel,
          color: AppColors.inkSoft,
          compact: true,
        ),
      );
    }
    if (task.attachments.isNotEmpty) {
      metaPills.add(
        _MetaPill(
          icon: Icons.attach_file,
          label: task.attachments.length.toString(),
          color: AppColors.inkSoft,
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
      final endDateKey = task.endDate.trim();

      DateTime? parseDayKey(String raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return null;
        try {
          return DateFormat('yyyy-MM-dd').parseStrict(trimmed);
        } catch (_) {
          final parsed = DateTime.tryParse('${trimmed}T00:00:00');
          return parsed;
        }
      }

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

      final parsedEndDay = parseDayKey(endDateKey);
      if (startTime.isEmpty && endRaw.isEmpty) {
        if (parsedEndDay != null && parsedEndDay.isAfter(date)) {
          final endDateLabel = DateFormat('M月d日').format(parsedEndDay);
          return '$startDateLabel - $endDateLabel';
        }
        return startDateLabel;
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

      var endDay = parsedEndDay ?? date;
      if (endDateKey.isEmpty && explicitOffset > 0) {
        endDay = date.add(Duration(days: explicitOffset.clamp(0, 36525)));
      }

      var displayTime = timePart;
      var endMinutes = parseTimeMinutes(timePart);
      if (timePart == '24:00' || endMinutes == 24 * 60) {
        displayTime = '00:00';
        endMinutes = 0;
        endDay = endDay.add(const Duration(days: 1));
      }

      final startMinutes = parseTimeMinutes(startTime);
      if (startMinutes != null &&
          endMinutes != null &&
          endDay.year == date.year &&
          endDay.month == date.month &&
          endDay.day == date.day &&
          endMinutes <= startMinutes) {
        endDay = endDay.add(const Duration(days: 1));
      }

      if (endDay.isAfter(date)) {
        final endDateLabel = DateFormat('M月d日').format(endDay);
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

  String? _buildRemindLabel(Task task) {
    final millis = task.remindAt;
    if (millis == null) return null;

    DateTime? dueDate;
    if (task.dueDate.trim().isNotEmpty) {
      try {
        dueDate = DateFormat('yyyy-MM-dd').parse(task.dueDate);
      } catch (_) {
        dueDate = null;
      }
    }

    try {
      final remindAt = DateTime.fromMillisecondsSinceEpoch(millis);
      final isSameDay = dueDate != null &&
          remindAt.year == dueDate.year &&
          remindAt.month == dueDate.month &&
          remindAt.day == dueDate.day;
      return isSameDay
          ? DateFormat('HH:mm').format(remindAt)
          : DateFormat('M/d HH:mm').format(remindAt);
    } catch (_) {
      return millis.toString();
    }
  }

  String? _buildRepeatLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return '重复';
      final freq = decoded['freq']?.toString() ?? '';
      switch (freq) {
        case 'daily':
          return '每天';
        case 'weekly':
          return '每周';
        case 'monthly':
          return '每月';
        case 'yearly':
          return '每年';
        default:
          return '重复';
      }
    } catch (_) {
      return '重复';
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
    this.icon,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final IconData? icon;
  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconOnly = icon != null && label.trim().isEmpty;
    final padding = compact
        ? (iconOnly
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 4))
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 14 : 16, color: color),
            if (label.trim().isNotEmpty) const SizedBox(width: 4),
          ],
          if (label.trim().isNotEmpty) Text(label, style: textStyle),
        ],
      ),
    );
  }
}
