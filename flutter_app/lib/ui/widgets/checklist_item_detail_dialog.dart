import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/checklist.dart';
import '../../utils/download.dart';

class ChecklistItemDetailDialog extends StatefulWidget {
  const ChecklistItemDetailDialog({
    super.key,
    required this.apiClient,
    required this.list,
    required this.item,
  });

  final ApiClient apiClient;
  final ChecklistList list;
  final ChecklistItem item;

  @override
  State<ChecklistItemDetailDialog> createState() =>
      _ChecklistItemDetailDialogState();
}

class _ChecklistItemDetailDialogState extends State<ChecklistItemDetailDialog> {
  bool get _canEdit => widget.list.canEdit;

  late ChecklistItem _item;
  late List<ChecklistSubtask> _draftSubtasks;
  bool _working = false;
  bool _dirty = false;
  bool _serverChanged = false;
  final Set<String> _downloadingIds = <String>{};

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _subtaskController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _draftSubtasks = List<ChecklistSubtask>.from(_item.subtasks);
    _syncControllersFromItem();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  void _syncControllersFromItem() {
    _titleController.text = _item.title;
    _notesController.text = _item.notes;
    _tagsController.text = _item.tags.join(', ');
  }

  List<String> _parseTags(String raw) {
    final parts = raw
        .split(RegExp(r'[,\\s]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    final seen = <String>{};
    final tags = <String>[];
    for (final tag in parts) {
      final key = tag.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      tags.add(tag);
      if (tags.length >= 20) break;
    }
    return tags;
  }

  String _formatAttachmentSize(int bytes) {
    if (bytes <= 0) return '0B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)}MB';
  }

  Future<void> _save() async {
    if (!_canEdit || _working) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }

    setState(() => _working = true);
    try {
      final updated = await widget.apiClient.updateChecklistItem(
        listId: _item.listId,
        itemId: _item.id,
        title: title,
        notes: _notesController.text,
        tags: _parseTags(_tagsController.text),
        subtasks: _draftSubtasks,
        expectedUpdatedAt: _item.updatedAt,
      );
      if (!mounted) return;
      setState(() {
        _item = updated;
        _draftSubtasks = List<ChecklistSubtask>.from(updated.subtasks);
        _dirty = false;
        _serverChanged = true;
      });
      _syncControllersFromItem();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(_serverChanged ? _item : null);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conflict: please refresh and retry.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save failed')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save failed')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  void _addSubtask() {
    if (!_canEdit) return;
    final title = _subtaskController.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _draftSubtasks = [
        ..._draftSubtasks,
        ChecklistSubtask(title: title, completed: false, note: ''),
      ];
      _subtaskController.clear();
      _dirty = true;
    });
  }

  void _toggleSubtask(int index, bool value) {
    if (!_canEdit) return;
    if (index < 0 || index >= _draftSubtasks.length) return;
    final subtasks = List<ChecklistSubtask>.from(_draftSubtasks);
    subtasks[index] = subtasks[index].copyWith(completed: value);
    setState(() {
      _draftSubtasks = subtasks;
      _dirty = true;
    });
  }

  void _removeSubtask(int index) {
    if (!_canEdit) return;
    if (index < 0 || index >= _draftSubtasks.length) return;
    setState(() {
      final subtasks = List<ChecklistSubtask>.from(_draftSubtasks)..removeAt(index);
      _draftSubtasks = subtasks;
      _dirty = true;
    });
  }

  Future<void> _uploadAttachment() async {
    if (!_canEdit || _working) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File bytes unavailable')),
      );
      return;
    }

    setState(() => _working = true);
    try {
      final uploaded = await widget.apiClient.uploadChecklistItemAttachment(
        listId: _item.listId,
        itemId: _item.id,
        filename: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _item = _item.copyWith(
          attachments: [..._item.attachments, uploaded.attachment],
          updatedAt: uploaded.itemUpdatedAt,
        );
        _serverChanged = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded: ${uploaded.attachment.name}')),
      );
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(_serverChanged ? _item : null);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _downloadAttachment(ChecklistItemAttachment attachment) async {
    if (_downloadingIds.contains(attachment.id)) return;
    setState(() => _downloadingIds.add(attachment.id));
    try {
      final bytes = await widget.apiClient.downloadChecklistItemAttachmentBytes(
        listId: _item.listId,
        itemId: _item.id,
        attachmentId: attachment.id,
      );
      final ok = await downloadBytesFile(
        filename: attachment.name,
        bytes: bytes,
        mimeType: attachment.mime.trim().isEmpty
            ? 'application/octet-stream'
            : attachment.mime.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Downloaded: ${attachment.name}' : 'Download cancelled')),
      );
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(_serverChanged ? _item : null);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download failed')),
      );
    } finally {
      if (mounted) setState(() => _downloadingIds.remove(attachment.id));
    }
  }

  Future<void> _deleteAttachment(ChecklistItemAttachment attachment) async {
    if (!_canEdit || _working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete attachment'),
        content: Text('Delete "${attachment.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      final updatedAt = await widget.apiClient.deleteChecklistItemAttachment(
        listId: _item.listId,
        itemId: _item.id,
        attachmentId: attachment.id,
      );
      if (!mounted) return;
      setState(() {
        _item = _item.copyWith(
          attachments: _item.attachments.where((a) => a.id != attachment.id).toList(),
          updatedAt: updatedAt ?? _item.updatedAt,
        );
        _serverChanged = true;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(_serverChanged ? _item : null);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete failed')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool> _confirmClose() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes. Discard them?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final completedBy = _item.completedBy.trim();
    final subtitle = _item.completed && completedBy.isNotEmpty ? 'Completed by $completedBy' : '';

    return WillPopScope(
      onWillPop: () async {
        final ok = await _confirmClose();
        if (!ok) return false;
        Navigator.of(context).pop(_serverChanged ? _item : null);
        return false;
      },
      child: AlertDialog(
        title: Text(_item.title.isEmpty ? 'Checklist item' : _item.title),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle.isNotEmpty) ...[
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    isDense: true,
                  ),
                  enabled: _canEdit && !_working,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    isDense: true,
                  ),
                  enabled: _canEdit && !_working,
                  maxLines: 3,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma separated)',
                    isDense: true,
                  ),
                  enabled: _canEdit && !_working,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 18),
                Text(
                  'Subtasks',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                if (_draftSubtasks.isEmpty)
                  Text(
                    'No subtasks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  ..._draftSubtasks.asMap().entries.map((entry) {
                    final index = entry.key;
                    final subtask = entry.value;
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: subtask.completed,
                      onChanged: !_canEdit || _working ? null : (v) => _toggleSubtask(index, v == true),
                      title: Text(subtask.title),
                      secondary: !_canEdit
                          ? null
                          : IconButton(
                              tooltip: 'Remove',
                              onPressed: _working ? null : () => _removeSubtask(index),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                    );
                  }),
                if (_canEdit) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _subtaskController,
                          decoration: const InputDecoration(
                            labelText: 'Add subtask',
                            isDense: true,
                          ),
                          enabled: !_working,
                          onSubmitted: (_) => _addSubtask(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _working ? null : _addSubtask,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Attachments',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (_canEdit)
                      TextButton.icon(
                        onPressed: _working ? null : _uploadAttachment,
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: const Text('Upload'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_item.attachments.isEmpty)
                  Text(
                    'No attachments',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                else
                  ..._item.attachments.map((attachment) {
                    final downloading = _downloadingIds.contains(attachment.id);
                    final size = _formatAttachmentSize(attachment.size);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(attachment.name.isEmpty ? attachment.id : attachment.name),
                      subtitle: Text(size),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            tooltip: 'Download',
                            onPressed: downloading || _working ? null : () => _downloadAttachment(attachment),
                            icon: downloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.download_outlined, size: 18),
                          ),
                          if (_canEdit)
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: _working ? null : () => _deleteAttachment(attachment),
                              icon: const Icon(Icons.delete_outline, size: 18),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working
                ? null
                : () async {
                    final ok = await _confirmClose();
                    if (!mounted || !ok) return;
                    Navigator.of(context).pop(_serverChanged ? _item : null);
                  },
            child: const Text('Close'),
          ),
          if (_canEdit)
            ElevatedButton(
              onPressed: _working || !_dirty ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
    );
  }
}
