import 'package:flutter/material.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

import '../../models/task.dart';
import '../../models/time_activity.dart';
import '../app_theme.dart';

class TimeActivityDraft {
  TimeActivityDraft({
    required this.name,
    this.taskId,
    this.icon,
    this.color,
    this.category,
    this.note,
  });

  final String name;
  final String? taskId;
  final String? icon;
  final String? color;
  final String? category;
  final String? note;
}

class TimeActivityEditorSheet extends StatefulWidget {
  const TimeActivityEditorSheet({
    super.key,
    required this.tasks,
    this.activity,
  });

  final List<Task> tasks;
  final TimeActivity? activity;

  @override
  State<TimeActivityEditorSheet> createState() => _TimeActivityEditorSheetState();
}

class _TimeActivityEditorSheetState extends State<TimeActivityEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _iconController;
  late final TextEditingController _categoryController;
  late final TextEditingController _noteController;
  late String _selectedTaskId;
  late String _selectedColor;
  bool _missingTask = false;
  bool _advancedExpanded = false;

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

  static const _colorPresets = <String>[
    '',
    '#22C55E',
    '#3B82F6',
    '#8B5CF6',
    '#F97316',
    '#F43F5E',
    '#14B8A6',
    '#111827',
  ];

  Future<void> _openEmojiPicker(BuildContext context) async {
    final surface = Theme.of(context).colorScheme.surface;
    final height = MediaQuery.of(context).size.height * 0.6;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: height,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) {
              _iconController.text = emoji.emoji;
              _iconController.selection = TextSelection.collapsed(
                offset: _iconController.text.length,
              );
              Navigator.of(sheetContext).maybePop();
            },
            config: Config(
              height: height,
              emojiViewConfig: EmojiViewConfig(
                backgroundColor: surface,
                columns: 8,
                emojiSizeMax: 30,
                gridPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              categoryViewConfig: const CategoryViewConfig(
                dividerColor: Colors.transparent,
              ),
              bottomActionBarConfig: BottomActionBarConfig(
                showBackspaceButton: false,
                backgroundColor: surface,
                buttonColor: AppColors.accent,
                buttonIconColor: Colors.white,
              ),
              searchViewConfig: SearchViewConfig(
                backgroundColor: surface,
                hintText: '搜索表情',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.activity?.name ?? '');
    _iconController = TextEditingController(text: widget.activity?.icon ?? '');
    _categoryController = TextEditingController(text: widget.activity?.category ?? '');
    _noteController = TextEditingController(text: widget.activity?.note ?? '');
    _selectedColor = widget.activity?.color ?? '';
    final initialTaskId = widget.activity?.taskId ?? '';
    if (initialTaskId.isNotEmpty && widget.tasks.every((task) => task.id != initialTaskId)) {
      _missingTask = true;
      _selectedTaskId = '';
    } else {
      _selectedTaskId = initialTaskId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _iconController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.activity != null;
    final tasks = widget.tasks;
    final hasTasks = tasks.isNotEmpty;

    Widget colorDot(String hex, {required bool selected}) {
      final isDefault = hex.trim().isEmpty;
      final color = isDefault ? AppColors.surface : _parseHexColor(hex) ?? AppColors.surface;
      final borderColor = selected ? AppColors.accent : AppColors.outline;
      return InkWell(
        onTap: () => setState(() => _selectedColor = hex),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: isDefault
              ? const Icon(Icons.format_color_reset, size: 14, color: AppColors.inkSoft)
              : null,
        ),
      );
    }

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
                isEditing ? '编辑活动' : '新建活动',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
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
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: '活动名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _iconController,
            decoration: InputDecoration(
              labelText: '图标（表情）',
              suffixIcon: IconButton(
                tooltip: '选择表情',
                onPressed: () => _openEmojiPicker(context),
                icon: const Icon(Icons.emoji_emotions_outlined),
              ),
            ),
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
          const SizedBox(height: 14),
          Text(
            '颜色',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final hex in _colorPresets)
                colorDot(hex, selected: _selectedColor.trim() == hex.trim()),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '更多设置',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            onExpansionChanged: (value) => setState(() => _advancedExpanded = value),
            initiallyExpanded: _advancedExpanded,
            children: [
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedTaskId,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('不关联任务'),
                  ),
                  ...tasks.map(
                    (task) => DropdownMenuItem(
                      value: task.id,
                      child: Text(
                        task.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: hasTasks ? (value) => setState(() => _selectedTaskId = value ?? '') : null,
                decoration: InputDecoration(
                  labelText: '关联任务',
                  helperText: hasTasks
                      ? (_missingTask ? '原关联任务已删除，已取消关联' : '选择要关联的任务')
                      : '暂无可关联的任务',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: '类别'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              const SizedBox(height: 6),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submit,
                  child: Text(isEditing ? '保存' : '创建'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('活动名称不能为空。')),
      );
      return;
    }
    Navigator.of(context).pop(
      TimeActivityDraft(
        name: name,
        taskId: _selectedTaskId.isEmpty ? null : _selectedTaskId,
        icon: _iconController.text.trim(),
        color: _selectedColor.trim(),
        category: _categoryController.text.trim(),
        note: _noteController.text.trim(),
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
