import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/time_activity.dart';
import '../../models/time_entry.dart';
import '../app_theme.dart';

class TimeEntryEditResult {
  const TimeEntryEditResult({
    required this.activityId,
    required this.activityName,
    required this.startedAt,
    required this.endedAt,
    required this.note,
    required this.tags,
    required this.activityIcon,
    required this.deleteEntry,
  });

  final String activityId;
  final String? activityName;
  final int startedAt;
  final int? endedAt;
  final String note;
  final List<String> tags;
  final String? activityIcon;
  final bool deleteEntry;
}

class TimeEntryEditorSheet extends StatefulWidget {
  const TimeEntryEditorSheet({
    super.key,
    required this.entry,
    required this.activities,
  });

  final TimeEntry entry;
  final List<TimeActivity> activities;

  @override
  State<TimeEntryEditorSheet> createState() => _TimeEntryEditorSheetState();
}

class _TimeEntryEditorSheetState extends State<TimeEntryEditorSheet> {
  late String _activityId;
  late DateTime _startedAt;
  DateTime? _endedAt;
  late final TextEditingController _activityNameController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagsController;
  late final TextEditingController _iconController;

  static const _emojiPresets = <String>[
    '📚',
    '💻',
    '📝',
    '🎯',
    '☕',
    '🏃',
    '🧘',
    '🎨',
    '🎵',
    '🧹',
    '🛒',
  ];

  @override
  void initState() {
    super.initState();
    _activityId = widget.entry.activityId;
    _startedAt = DateTime.fromMillisecondsSinceEpoch(widget.entry.startedAt);
    _endedAt = widget.entry.endedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.entry.endedAt!);
    _activityNameController = TextEditingController(text: _activityFor(_activityId)?.name ?? '');
    _noteController = TextEditingController(text: widget.entry.note);
    _tagsController = TextEditingController(text: widget.entry.tags.join(' '));
    _iconController = TextEditingController(text: _activityFor(_activityId)?.icon ?? '');
  }

  @override
  void dispose() {
    _activityNameController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  TimeActivity? _activityFor(String id) {
    for (final activity in widget.activities) {
      if (activity.id == id) return activity;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final activity = _activityFor(_activityId);
    final title = widget.entry.isRunning ? '编辑进行中活动' : '编辑记录';
    final startLabel = DateFormat('HH:mm').format(_startedAt);
    final endLabel = _endedAt == null ? '未结束' : DateFormat('HH:mm').format(_endedAt!);
    final activityItems = <DropdownMenuItem<String>>[
      if (activity == null)
        DropdownMenuItem(
          value: _activityId,
          child: Text(
            '已删除活动 ($_activityId)',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ...widget.activities.map(
        (a) => DropdownMenuItem(
          value: a.id,
          child: Text(
            a.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _activityId,
            items: activityItems,
            onChanged: (value) {
              final next = value ?? '';
              if (next.isEmpty) return;
              setState(() {
                _activityId = next;
                final selected = _activityFor(next);
                _activityNameController.text = selected?.name ?? '';
                _iconController.text = selected?.icon ?? '';
              });
            },
            decoration: const InputDecoration(labelText: '活动'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _activityNameController,
            enabled: activity != null,
            decoration: const InputDecoration(labelText: '活动名称'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: '开始时间',
                  value: startLabel,
                  onTap: _pickStartTime,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeButton(
                  label: '结束时间',
                  value: endLabel,
                  onTap: _pickEndTime,
                  onClear: _endedAt == null ? null : () => setState(() => _endedAt = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '用空格或逗号分隔',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          const SizedBox(height: 14),
          Text(
            '活动图标（表情）',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _iconController,
            decoration: const InputDecoration(hintText: '例如：🎯'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final emoji in _emojiPresets)
                InkWell(
                  onTap: () {
                    _iconController.text = emoji;
                    _iconController.selection =
                        TextSelection.collapsed(offset: _iconController.text.length);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 18)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red.withOpacity(0.55)),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _submit(activity),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final initial = TimeOfDay.fromDateTime(_startedAt);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final next = DateTime(
      _startedAt.year,
      _startedAt.month,
      _startedAt.day,
      picked.hour,
      picked.minute,
    );
    setState(() {
      _startedAt = next;
      if (_endedAt != null && _endedAt!.isBefore(_startedAt)) {
        _endedAt = _startedAt;
      }
    });
  }

  Future<void> _pickEndTime() async {
    final base = _endedAt ?? _startedAt;
    final initial = TimeOfDay.fromDateTime(base);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    var next = DateTime(
      _startedAt.year,
      _startedAt.month,
      _startedAt.day,
      picked.hour,
      picked.minute,
    );
    if (next.isBefore(_startedAt)) {
      next = next.add(const Duration(days: 1));
    }
    setState(() => _endedAt = next);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;
    Navigator.of(context).pop(
      TimeEntryEditResult(
        activityId: _activityId,
        activityName: null,
        startedAt: _startedAt.millisecondsSinceEpoch,
        endedAt: _endedAt?.millisecondsSinceEpoch,
        note: _noteController.text,
        tags: _parseTags(_tagsController.text),
        activityIcon: _iconController.text.trim().isEmpty ? null : _iconController.text.trim(),
        deleteEntry: true,
      ),
    );
  }

  void _submit(TimeActivity? activity) {
    final tags = _parseTags(_tagsController.text);
    final selected = activity;
    final icon = _iconController.text.trim();
    final nextIcon = icon.isEmpty ? '' : icon;
    final originalIcon = selected?.icon ?? '';
    final changedIcon = nextIcon == originalIcon ? null : nextIcon;
    final rawName = _activityNameController.text.trim();
    final originalName = selected?.name.trim() ?? '';
    final changedName = rawName.isEmpty || rawName == originalName ? null : rawName;

    Navigator.of(context).pop(
      TimeEntryEditResult(
        activityId: _activityId,
        activityName: changedName,
        startedAt: _startedAt.millisecondsSinceEpoch,
        endedAt: _endedAt?.millisecondsSinceEpoch,
        note: _noteController.text,
        tags: tags,
        activityIcon: changedIcon,
        deleteEntry: false,
      ),
    );
  }

  List<String> _parseTags(String raw) {
    final normalized = raw.replaceAll('，', ',');
    return normalized
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: AppColors.inkSoft),
                ),
              ),
            ] else ...[
              const Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
            ],
          ],
        ),
      ),
    );
  }
}
