import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/checklist.dart';
import '../../models/checklist_log_entry.dart';

class ChecklistLogsDialog extends StatefulWidget {
  const ChecklistLogsDialog({
    super.key,
    required this.apiClient,
    required this.list,
  });

  final ApiClient apiClient;
  final ChecklistList list;

  @override
  State<ChecklistLogsDialog> createState() => _ChecklistLogsDialogState();
}

class _ChecklistLogsDialogState extends State<ChecklistLogsDialog> {
  bool _loading = true;
  List<ChecklistLogEntry> _logs = <ChecklistLogEntry>[];

  final TextEditingController _actorController = TextEditingController();
  final TextEditingController _typeController = TextEditingController();
  final TextEditingController _itemIdController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _actorController.dispose();
    _typeController.dispose();
    _itemIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = _fromDate == null
          ? null
          : DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day)
              .millisecondsSinceEpoch;
      final to = _toDate == null
          ? null
          : DateTime(_toDate!.year, _toDate!.month, _toDate!.day)
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch;
      final logs = await widget.apiClient.getChecklistLogs(
        listId: widget.list.id,
        actor: _actorController.text.trim().isEmpty ? null : _actorController.text.trim(),
        type: _typeController.text.trim().isEmpty ? null : _typeController.text.trim(),
        targetType: _itemIdController.text.trim().isEmpty ? null : 'item',
        targetId: _itemIdController.text.trim().isEmpty ? null : _itemIdController.text.trim(),
        from: from,
        to: to,
        limit: 200,
      );
      if (!mounted) return;
      setState(() => _logs = logs);
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载操作记录失败。')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String formatDate(DateTime date) {
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final content = _loading
        ? const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          )
        : SizedBox(
            width: 640,
            height: 520,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _actorController,
                        decoration: const InputDecoration(
                          labelText: '按人筛选',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _typeController,
                        decoration: const InputDecoration(
                          labelText: '按类型筛选',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _itemIdController,
                        decoration: const InputDecoration(
                          labelText: '按条目 ID',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('应用'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _fromDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (picked == null || !mounted) return;
                          setState(() => _fromDate = picked);
                        },
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(
                          _fromDate == null ? 'From' : 'From: ${formatDate(_fromDate!)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _toDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (picked == null || !mounted) return;
                          setState(() => _toDate = picked);
                        },
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(
                          _toDate == null ? 'To' : 'To: ${formatDate(_toDate!)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => setState(() {
                        _fromDate = null;
                        _toDate = null;
                      }),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _logs.isEmpty
                      ? const Center(child: Text('暂无记录。'))
                      : ListView.separated(
                          itemCount: _logs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final log = _logs[index];
                            final when = DateTime.fromMillisecondsSinceEpoch(log.createdAt);
                            final subtitle = [
                              log.type,
                              if (log.targetType != null) '${log.targetType}:${log.targetId ?? ''}',
                              when.toLocal().toString(),
                            ].where((s) => s.trim().isNotEmpty).join(' · ');
                            return ListTile(
                              dense: true,
                              title: Text(log.actor.isEmpty ? '未知' : log.actor),
                              subtitle: Text(subtitle),
                            );
                          },
                        ),
                ),
              ],
            ),
          );

    return AlertDialog(
      title: Text('操作记录 · ${widget.list.name.isEmpty ? widget.list.id : widget.list.name}'),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
