import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/checklist.dart';
import '../../models/checklist_invite.dart';
import '../../models/checklist_share.dart';
import '../../models/user_candidate.dart';
import 'checklist_logs_dialog.dart';

class ChecklistSharingDialog extends StatefulWidget {
  const ChecklistSharingDialog({
    super.key,
    required this.apiClient,
    required this.list,
    required this.currentUsername,
  });

  final ApiClient apiClient;
  final ChecklistList list;
  final String currentUsername;

  @override
  State<ChecklistSharingDialog> createState() => _ChecklistSharingDialogState();
}

class _ChecklistSharingDialogState extends State<ChecklistSharingDialog> {
  bool get _isOwner => widget.list.role == 'owner';

  bool _loading = true;
  bool _working = false;

  ChecklistShareInfo? _shares;
  List<ChecklistInvite> _invites = <ChecklistInvite>[];
  List<UserCandidate> _candidates = <UserCandidate>[];
  List<UserCandidate> _searchResults = <UserCandidate>[];
  final Set<String> _selectedUserKeys = <String>{};

  final TextEditingController _searchController = TextEditingController();
  String _inviteRole = 'editor';

  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final shares = await widget.apiClient.getChecklistShares(widget.list.id);
      final candidates = await widget.apiClient.getCollabCandidates(limit: 12);
      final invites = _isOwner
          ? await widget.apiClient.getChecklistInvites(widget.list.id, limit: 200)
          : <ChecklistInvite>[];
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _candidates = candidates;
        _invites = invites;
      });
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(_changed);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加载共享信息失败。')),
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

  Future<void> _searchUsers(String value) async {
    final q = value.trim();
    if (q.length < 3) {
      setState(() => _searchResults = <UserCandidate>[]);
      return;
    }
    try {
      final results = await widget.apiClient.searchUsers(query: q, limit: 20);
      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('搜索用户失败。')),
      );
    }
  }

  Future<void> _sendInvites() async {
    if (_working) return;
    final keys = _selectedUserKeys.toList();
    if (keys.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要邀请的用户。')),
      );
      return;
    }

    setState(() => _working = true);
    try {
      await widget.apiClient.inviteUsersToChecklist(
        listId: widget.list.id,
        userKeys: keys,
        role: _inviteRole,
      );
      _changed = true;
      _selectedUserKeys.clear();
      _searchController.clear();
      setState(() => _searchResults = <UserCandidate>[]);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已发送邀请。')),
      );
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).pop(_changed);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送邀请失败。')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _revokeInvite(ChecklistInvite invite) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.apiClient.revokeChecklistInvite(invite.id);
      _changed = true;
      await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('撤回邀请失败。')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleMemberCanEdit(ChecklistMember member, bool canEdit) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.apiClient.updateChecklistShareRole(
        listId: widget.list.id,
        username: member.user,
        canEdit: canEdit,
      );
      _changed = true;
      await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('更新成员权限失败。')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _removeMember(ChecklistMember member) async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定移除 ${member.user} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await widget.apiClient.removeChecklistShare(
        listId: widget.list.id,
        username: member.user,
      );
      _changed = true;
      await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('移除成员失败。')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _leaveChecklist() async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出清单'),
        content: const Text('退出后将立即失去访问权限。确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await widget.apiClient.leaveChecklist(widget.list.id);
      _changed = true;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('退出清单失败。')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _transferOwner(ChecklistMember member) async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('转让所有权'),
        content: Text('确定将清单所有权转让给 ${member.user} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('转让'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _working = true);
    try {
      await widget.apiClient.transferChecklistOwner(
        listId: widget.list.id,
        userKey: member.user,
      );
      _changed = true;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('转让所有权失败。')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _openLogs() {
    showDialog<void>(
      context: context,
      builder: (context) => ChecklistLogsDialog(
        apiClient: widget.apiClient,
        list: widget.list,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shares = _shares;
    final selectedCount = _selectedUserKeys.length;
    final query = _searchController.text.trim();

    final content = _loading
        ? const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          )
        : shares == null
            ? const SizedBox(height: 160, child: Center(child: Text('加载失败。')))
            : SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '拥有者：${shares.owner.isEmpty ? widget.list.owner : shares.owner}',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          TextButton(
                            onPressed: _openLogs,
                            child: const Text('操作记录'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '成员',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (shares.shared.isEmpty)
                        const Text('暂无成员。')
                      else
                        ...shares.shared.map((m) {
                          final roleLabel = m.canEdit ? '可编辑' : '只读';
                          return ListTile(
                            dense: true,
                            title: Text(m.user),
                            subtitle: Text(roleLabel),
                            trailing: _isOwner
                                ? Wrap(
                                    spacing: 8,
                                    children: [
                                      Switch(
                                        value: m.canEdit,
                                        onChanged: _working ? null : (value) => _toggleMemberCanEdit(m, value),
                                      ),
                                      IconButton(
                                        tooltip: '移除',
                                        onPressed: _working ? null : () => _removeMember(m),
                                        icon: const Icon(Icons.person_remove),
                                      ),
                                      IconButton(
                                        tooltip: '转让所有权',
                                        onPressed: _working ? null : () => _transferOwner(m),
                                        icon: const Icon(Icons.admin_panel_settings_outlined),
                                      ),
                                    ],
                                  )
                                : null,
                          );
                        }),
                      if (!_isOwner) ...[
                        const Divider(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _working ? null : _leaveChecklist,
                            child: const Text('退出清单'),
                          ),
                        ),
                      ],
                      if (_isOwner) ...[
                        const Divider(),
                        Text(
                          '邀请成员',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: const InputDecoration(
                                  labelText: '搜索用户（至少 3 个字符）',
                                  isDense: true,
                                ),
                                onChanged: _working ? null : _searchUsers,
                              ),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: _inviteRole,
                              onChanged: _working
                                  ? null
                                  : (value) => setState(() => _inviteRole = value ?? 'editor'),
                              items: const [
                                DropdownMenuItem(value: 'editor', child: Text('可编辑')),
                                DropdownMenuItem(value: 'readonly', child: Text('只读')),
                              ],
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _working ? null : _sendInvites,
                              child: Text(selectedCount == 0 ? '发送' : '发送 ($selectedCount)'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '提示：输入对方用户名关键字搜索（至少 3 个字符），结果会打码展示；勾选后再点发送。也可用下方“最近协作/邀请”候选。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (query.length >= 3 && _searchResults.isEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '未找到匹配用户：$query',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                        if (_candidates.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: _candidates.map((c) {
                              final selected = _selectedUserKeys.contains(c.userKey);
                              return FilterChip(
                                label: Text(c.display.isEmpty ? c.userKey : c.display),
                                selected: selected,
                                onSelected: _working
                                    ? null
                                    : (value) {
                                        setState(() {
                                          if (value) {
                                            _selectedUserKeys.add(c.userKey);
                                          } else {
                                            _selectedUserKeys.remove(c.userKey);
                                          }
                                        });
                                      },
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_searchResults.isNotEmpty)
                          ..._searchResults.map((u) {
                            final selected = _selectedUserKeys.contains(u.userKey);
                            return CheckboxListTile(
                              dense: true,
                              value: selected,
                              onChanged: _working
                                  ? null
                                  : (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedUserKeys.add(u.userKey);
                                        } else {
                                          _selectedUserKeys.remove(u.userKey);
                                        }
                                      });
                                    },
                              title: Text(u.display.isEmpty ? u.userKey : u.display),
                              subtitle: Text(u.userKey),
                            );
                          }),
                        const SizedBox(height: 8),
                        Text(
                          '邀请记录',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        if (_invites.isEmpty)
                          const Text('暂无邀请。')
                        else
                          ..._invites.where((i) => i.status == 'pending').map((i) {
                            return ListTile(
                              dense: true,
                              title: Text(i.inviteeDisplay.isEmpty ? i.inviteeKey : i.inviteeDisplay),
                              subtitle: Text('${i.role} · ${i.status}'),
                              trailing: TextButton(
                                onPressed: _working ? null : () => _revokeInvite(i),
                                child: const Text('撤回'),
                              ),
                            );
                          }),
                      ],
                    ],
                  ),
                ),
              );

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_changed);
        return false;
      },
      child: AlertDialog(
        title: Text('协作 · ${widget.list.name.isEmpty ? widget.list.id : widget.list.name}'),
        content: content,
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(_changed),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
