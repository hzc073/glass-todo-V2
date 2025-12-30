import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/in_app_notification.dart';

class NotificationsDialog extends StatefulWidget {
  const NotificationsDialog({
    super.key,
    required this.apiClient,
    required this.onChecklistChanged,
  });

  final ApiClient apiClient;
  final VoidCallback onChecklistChanged;

  @override
  State<NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<NotificationsDialog> {
  bool _loading = true;
  bool _acting = false;
  List<InAppNotification> _notifications = <InAppNotification>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.apiClient.getNotifications(limit: 200);
      if (!mounted) return;
      setState(() => _notifications = list);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载通知失败。')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int? _inviteIdFor(InAppNotification n) {
    final data = n.data;
    if (data == null) return null;
    return _parseInt(data['inviteId'] ?? data['invite_id']);
  }

  bool _isUnread(InAppNotification n) => n.readAt == null;

  Future<void> _markRead(InAppNotification n) async {
    if (!_isUnread(n)) return;
    try {
      await widget.apiClient.readNotification(n.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标记已读失败。')),
      );
    }
  }

  Future<void> _markAllRead() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await widget.apiClient.readAllNotifications();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全部已读失败。')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _handleInviteAction({
    required InAppNotification notification,
    required bool accept,
  }) async {
    final inviteId = _inviteIdFor(notification);
    if (inviteId == null || _acting) return;
    setState(() => _acting = true);
    try {
      if (accept) {
        await widget.apiClient.acceptChecklistInvite(inviteId);
      } else {
        await widget.apiClient.rejectChecklistInvite(inviteId);
      }
      await widget.apiClient.readNotification(notification.id);
      widget.onChecklistChanged();
      await _load();
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? '接受邀请失败。' : '拒绝邀请失败。')),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          )
        : _notifications.isEmpty
            ? const SizedBox(
                height: 120,
                child: Center(child: Text('暂无通知。')),
              )
            : SizedBox(
                width: 520,
                height: 520,
                child: ListView.separated(
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final n = _notifications[index];
                    final inviteId = n.type == 'checklist_invite' ? _inviteIdFor(n) : null;
                    final unread = _isUnread(n);
                    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        );
                    return ListTile(
                      dense: true,
                      title: Text(n.title.isEmpty ? n.type : n.title, style: titleStyle),
                      subtitle: n.body.trim().isEmpty ? null : Text(n.body),
                      trailing: inviteId != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _acting
                                      ? null
                                      : () => _handleInviteAction(
                                            notification: n,
                                            accept: false,
                                          ),
                                  child: const Text('拒绝'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _acting
                                      ? null
                                      : () => _handleInviteAction(
                                            notification: n,
                                            accept: true,
                                          ),
                                  child: const Text('接受'),
                                ),
                              ],
                            )
                          : unread
                              ? IconButton(
                                  tooltip: '标记已读',
                                  onPressed: _acting ? null : () => _markRead(n),
                                  icon: const Icon(Icons.done),
                                )
                              : null,
                      onTap: inviteId != null || _acting ? null : () => _markRead(n),
                    );
                  },
                ),
              );

    return AlertDialog(
      title: const Text('通知'),
      content: content,
      actions: [
        TextButton(
          onPressed: _acting ? null : _load,
          child: const Text('刷新'),
        ),
        TextButton(
          onPressed: _acting ? null : _markAllRead,
          child: const Text('全部已读'),
        ),
        TextButton(
          onPressed: _acting ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

