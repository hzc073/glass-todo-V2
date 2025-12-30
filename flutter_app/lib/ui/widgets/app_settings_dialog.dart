import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_version.dart';
import '../../core/keyboard_shortcuts.dart';
import '../../core/notifications/fcm_notification_controller.dart';
import '../../core/notifications/firebase_bootstrap.dart';
import '../../core/notifications/local_task_notifications.dart';
import '../../models/user_settings.dart';
import '../app_theme.dart';

enum AppSettingsSection {
  user,
  preferences,
  notifications,
  data,
  advanced,
  about,
}

Future<void> showAppSettingsDialog(
  BuildContext context, {
  required ApiClient apiClient,
  required String username,
  required UserSettings initialSettings,
  required bool timeTrackingOngoingNotificationEnabled,
  required Future<void> Function(bool enabled)
      onTimeTrackingOngoingNotificationEnabledChanged,
  required VoidCallback onLogout,
  required ValueChanged<UserSettings> onSettingsApplied,
  required ValueChanged<ThemeMode> onThemeModeChanged,
  Future<void> Function()? onOpenBackendSettings,
  Future<void> Function()? onExportData,
  Future<void> Function()? onExportExcel,
  Future<void> Function()? onImportData,
  Future<void> Function(int retentionDays)? onClearCompleted,
  Future<void> Function()? onDeleteAccount,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AppSettingsDialog(
      apiClient: apiClient,
      username: username,
      initialSettings: initialSettings,
      timeTrackingOngoingNotificationEnabled:
          timeTrackingOngoingNotificationEnabled,
      onTimeTrackingOngoingNotificationEnabledChanged:
          onTimeTrackingOngoingNotificationEnabledChanged,
      onLogout: onLogout,
      onSettingsApplied: onSettingsApplied,
      onThemeModeChanged: onThemeModeChanged,
      onOpenBackendSettings: onOpenBackendSettings,
      onExportData: onExportData,
      onExportExcel: onExportExcel,
      onImportData: onImportData,
      onClearCompleted: onClearCompleted,
      onDeleteAccount: onDeleteAccount,
    ),
  );
}

class _AppSettingsDialog extends StatefulWidget {
  const _AppSettingsDialog({
    required this.apiClient,
    required this.username,
    required this.initialSettings,
    required this.timeTrackingOngoingNotificationEnabled,
    required this.onTimeTrackingOngoingNotificationEnabledChanged,
    required this.onLogout,
    required this.onSettingsApplied,
    required this.onThemeModeChanged,
    required this.onOpenBackendSettings,
    required this.onExportData,
    required this.onExportExcel,
    required this.onImportData,
    required this.onClearCompleted,
    required this.onDeleteAccount,
  });

  final ApiClient apiClient;
  final String username;
  final UserSettings initialSettings;
  final bool timeTrackingOngoingNotificationEnabled;
  final Future<void> Function(bool enabled)
      onTimeTrackingOngoingNotificationEnabledChanged;
  final VoidCallback onLogout;
  final ValueChanged<UserSettings> onSettingsApplied;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function()? onOpenBackendSettings;
  final Future<void> Function()? onExportData;
  final Future<void> Function()? onExportExcel;
  final Future<void> Function()? onImportData;
  final Future<void> Function(int retentionDays)? onClearCompleted;
  final Future<void> Function()? onDeleteAccount;

  @override
  State<_AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends State<_AppSettingsDialog> {
  AppSettingsSection _section = AppSettingsSection.preferences;
  late UserSettings _settings;

  late final TextEditingController _nicknameController;
  late final TextEditingController _avatarController;
  late final TextEditingController _backupPathController;
  late bool _timeTrackingOngoingNotificationEnabled;

  bool _loading = false;
  bool _saving = false;
  DateTime? _lastSavedAt;
  Timer? _saveDebounce;

  bool _isAdmin = false;
  String _inviteCode = '';
  bool _loadingInvite = false;

  bool _sendingFcmTest = false;
  bool _sendingLocalTest = false;

  bool get _showDevOptions => !kReleaseMode;

  Future<String?> _promptShortcut(
    BuildContext context, {
    required String title,
    required String currentValue,
  }) async {
    String? captured;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.of(context).pop();
                return KeyEventResult.handled;
              }
              final value = shortcutStringFromKeyEvent(event);
              if (value == null) return KeyEventResult.ignored;
              setState(() => captured = value);
              return KeyEventResult.handled;
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请按下你想使用的快捷键组合（按 Esc 取消）。'),
                const SizedBox(height: 12),
                Text('当前：${shortcutDisplayLabel(currentValue)}'),
                const SizedBox(height: 8),
                Text(
                  '新快捷键：${captured == null ? '（等待输入）' : shortcutDisplayLabel(captured!)}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: captured == null
                  ? null
                  : () => Navigator.of(context).pop(captured),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    return result?.trim().isEmpty == true ? null : result;
  }

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _timeTrackingOngoingNotificationEnabled =
        widget.timeTrackingOngoingNotificationEnabled;
    _nicknameController =
        TextEditingController(text: _settings.profile.nickname);
    _avatarController = TextEditingController(text: _settings.profile.avatar);
    _backupPathController =
        TextEditingController(text: _settings.data.backup.serverPath);
    _loadLatestSettings();
    _loadInviteCodeIfAdmin();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _nicknameController.dispose();
    _avatarController.dispose();
    _backupPathController.dispose();
    super.dispose();
  }

  Future<void> _loadLatestSettings() async {
    setState(() => _loading = true);
    try {
      final latest = await widget.apiClient.getUserSettings();
      if (!mounted) return;
      setState(() {
        _settings = latest;
        _loading = false;
      });
      _syncProfileControllers(latest);
      widget.onSettingsApplied(latest);
      widget.onThemeModeChanged(_themeModeFor(latest.preferences.theme));
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadInviteCodeIfAdmin() async {
    setState(() => _loadingInvite = true);
    try {
      final code = await widget.apiClient.getInviteCode();
      if (!mounted) return;
      setState(() {
        _isAdmin = code.trim().isNotEmpty;
        _inviteCode = code;
        _loadingInvite = false;
      });
    } on UnauthorizedException {
      widget.onLogout();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _inviteCode = '';
        _loadingInvite = false;
      });
      if (e.statusCode == 403) return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInvite = false);
    }
  }

  void _updateSettings(UserSettings next, {bool scheduleSave = true}) {
    setState(() => _settings = next);
    _syncProfileControllers(next);
    widget.onSettingsApplied(next);
    if (scheduleSave) _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _saveNow() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.apiClient.saveUserSettings(_settings);
      if (!mounted) return;
      setState(() {
        _settings = saved;
        _saving = false;
        _lastSavedAt = DateTime.now();
      });
      widget.onSettingsApplied(saved);
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存设置失败，请稍后重试。')),
      );
    }
  }

  Future<void> _resetToDefaults() async {
    final ok = await _confirm(
      context,
      title: '恢复默认',
      message: '将所有设置恢复为默认值，并立即同步到服务器。',
      confirmText: '恢复默认',
    );
    if (!ok) return;
    final defaults = UserSettings.defaults();
    _updateSettings(defaults, scheduleSave: false);
    widget.onThemeModeChanged(_themeModeFor(defaults.preferences.theme));
    await _saveNow();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 760;
    final title = _saving ? '保存中…' : (_lastSavedAt == null ? '设置' : '已同步');

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _buildSectionContent(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
              child: Row(
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : _resetToDefaults,
                    child: const Text('恢复默认'),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: isWide
                  ? Row(
                      children: [
                        _buildRail(context),
                        const VerticalDivider(width: 1),
                        Expanded(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: content)),
                      ],
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: _buildSectionDropdown(context),
                        ),
                        const Divider(height: 1),
                        Expanded(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: content)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    return SizedBox(
      width: 190,
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: _section.index,
        onDestinationSelected: (index) =>
            setState(() => _section = AppSettingsSection.values[index]),
        labelType: NavigationRailLabelType.all,
        destinations: const [
          NavigationRailDestination(
              icon: Icon(Icons.person), label: Text('用户')),
          NavigationRailDestination(
              icon: Icon(Icons.tune), label: Text('偏好设置')),
          NavigationRailDestination(
              icon: Icon(Icons.notifications), label: Text('通知设置')),
          NavigationRailDestination(
              icon: Icon(Icons.storage), label: Text('数据管理')),
          NavigationRailDestination(
              icon: Icon(Icons.auto_fix_high), label: Text('高级')),
          NavigationRailDestination(
              icon: Icon(Icons.info_outline), label: Text('关于')),
        ],
      ),
    );
  }

  Widget _buildSectionDropdown(BuildContext context) {
    return DropdownButtonFormField<AppSettingsSection>(
      value: _section,
      decoration: const InputDecoration(labelText: '设置分类'),
      items: const [
        DropdownMenuItem(value: AppSettingsSection.user, child: Text('用户')),
        DropdownMenuItem(
            value: AppSettingsSection.preferences, child: Text('偏好设置')),
        DropdownMenuItem(
            value: AppSettingsSection.notifications, child: Text('通知设置')),
        DropdownMenuItem(value: AppSettingsSection.data, child: Text('数据管理')),
        DropdownMenuItem(value: AppSettingsSection.advanced, child: Text('高级')),
        DropdownMenuItem(value: AppSettingsSection.about, child: Text('关于')),
      ],
      onChanged: (value) => setState(() => _section = value ?? _section),
    );
  }

  Widget _buildSectionContent(BuildContext context) {
    switch (_section) {
      case AppSettingsSection.user:
        return _buildUserSection(context);
      case AppSettingsSection.preferences:
        return _buildPreferencesSection(context);
      case AppSettingsSection.notifications:
        return _buildNotificationsSection(context);
      case AppSettingsSection.data:
        return _buildDataSection(context);
      case AppSettingsSection.advanced:
        return _buildAdvancedSection(context);
      case AppSettingsSection.about:
        return _buildAboutSection(context);
    }
  }

  Widget _buildUserSection(BuildContext context) {
    final profile = _settings.profile;
    final avatar = profile.avatar.trim();
    final nickname = profile.nickname.trim();
    final displayName = nickname.isEmpty ? widget.username : nickname;
    return ListView(
      children: [
        Text(
          '用户',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.accentCool.withOpacity(0.2),
              child: Text(
                avatar.isNotEmpty ? avatar : _avatarLetter(displayName),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nicknameController,
          decoration: const InputDecoration(
            labelText: '昵称',
            hintText: '用于多端显示（可留空）',
          ),
          onChanged: (value) {
            _updateSettings(
                _settings.copyWith(profile: profile.copyWith(nickname: value)));
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _avatarController,
          decoration: const InputDecoration(
            labelText: '头像（表情/字符）',
            hintText: '例如 😀 / 🧠 / A',
          ),
          onChanged: (value) {
            _updateSettings(
                _settings.copyWith(profile: profile.copyWith(avatar: value)));
          },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _openChangePassword(context),
                icon: const Icon(Icons.lock_reset),
                label: const Text('修改密码'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '邀请码',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (_loadingInvite)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!_isAdmin)
          Text(
            '仅管理员可查看与刷新邀请码。',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.inkSoft),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _inviteCode,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _inviteCode)),
                  child: const Text('复制'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _saving ? null : _refreshInvite,
                  child: const Text('刷新'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPreferencesSection(BuildContext context) {
    final prefs = _settings.preferences;
    final defaultSort = prefs.defaultSort.trim();
    final safeDefaultSort = <String>{
      'manual',
      'due',
      'created',
      if (_showDevOptions) 'quadrant',
    }.contains(defaultSort)
        ? defaultSort
        : 'manual';
    final calendar = _settings.calendarSettings;
    return ListView(
      children: [
        Text(
          '偏好设置',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: prefs.defaultView,
          decoration: const InputDecoration(labelText: '默认视图'),
          items: const [
            DropdownMenuItem(value: 'inbox', child: Text('收件箱')),
            DropdownMenuItem(value: 'today', child: Text('今天')),
            DropdownMenuItem(value: 'checklists', child: Text('清单')),
            DropdownMenuItem(value: 'matrix', child: Text('四象限')),
            DropdownMenuItem(value: 'calendar', child: Text('日历视图')),
            DropdownMenuItem(value: 'timeTracking', child: Text('时间记录')),
            DropdownMenuItem(value: 'pomodoro', child: Text('番茄钟')),
            DropdownMenuItem(value: 'stats', child: Text('统计')),
          ],
          onChanged: (value) {
            _updateSettings(_settings.copyWith(
                preferences:
                    prefs.copyWith(defaultView: value ?? prefs.defaultView)));
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs.undoEnabled,
          onChanged: (v) => _updateSettings(
              _settings.copyWith(preferences: prefs.copyWith(undoEnabled: v))),
          title: const Text('允许一键撤销（Undo）'),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          value: prefs.undoSeconds,
          decoration: const InputDecoration(labelText: 'Undo 时长'),
          items: const [
            DropdownMenuItem(value: 2, child: Text('2 秒')),
            DropdownMenuItem(value: 5, child: Text('5 秒')),
          ],
          onChanged: (value) {
            _updateSettings(_settings.copyWith(
                preferences:
                    prefs.copyWith(undoSeconds: value ?? prefs.undoSeconds)));
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: safeDefaultSort,
          decoration: const InputDecoration(labelText: '默认排序'),
          items: [
            const DropdownMenuItem(value: 'manual', child: Text('手动拖拽')),
            if (_showDevOptions)
              const DropdownMenuItem(value: 'quadrant', child: Text('按四象限')),
            const DropdownMenuItem(value: 'due', child: Text('按截止日期')),
            const DropdownMenuItem(value: 'created', child: Text('按创建时间')),
          ],
          onChanged: (value) {
            _updateSettings(_settings.copyWith(
                preferences:
                    prefs.copyWith(defaultSort: value ?? safeDefaultSort)));
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: prefs.theme,
          decoration: const InputDecoration(labelText: '主题'),
          items: const [
            DropdownMenuItem(value: 'light', child: Text('浅色')),
            DropdownMenuItem(value: 'dark', child: Text('深色')),
            DropdownMenuItem(value: 'system', child: Text('跟随系统')),
          ],
          onChanged: (value) {
            final theme = value ?? prefs.theme;
            _updateSettings(
                _settings.copyWith(preferences: prefs.copyWith(theme: theme)));
            widget.onThemeModeChanged(_themeModeFor(theme));
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: prefs.timeZoneOffsetMinutes,
          decoration: const InputDecoration(labelText: '时区（UTC 偏移）'),
          items: [
            for (var hour = -12; hour <= 14; hour++)
              DropdownMenuItem(
                value: hour * 60,
                child: Text(_formatUtcOffsetMinutes(hour * 60)),
              ),
          ],
          onChanged: (value) {
            _updateSettings(_settings.copyWith(
                preferences: prefs.copyWith(
                    timeZoneOffsetMinutes:
                        value ?? prefs.timeZoneOffsetMinutes)));
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: prefs.weekStart,
          decoration: const InputDecoration(labelText: '星期起始日'),
          items: const [
            DropdownMenuItem(value: 'monday', child: Text('周一')),
            DropdownMenuItem(value: 'tuesday', child: Text('周二')),
            DropdownMenuItem(value: 'wednesday', child: Text('周三')),
            DropdownMenuItem(value: 'thursday', child: Text('周四')),
            DropdownMenuItem(value: 'friday', child: Text('周五')),
            DropdownMenuItem(value: 'saturday', child: Text('周六')),
            DropdownMenuItem(value: 'sunday', child: Text('周日')),
          ],
          onChanged: (value) {
            _updateSettings(_settings.copyWith(
                preferences:
                    prefs.copyWith(weekStart: value ?? prefs.weekStart)));
          },
        ),
        const SizedBox(height: 12),
        Text(
          '快捷键',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: prefs.shortcutsEnabled,
          onChanged: (v) => _updateSettings(_settings.copyWith(
              preferences: prefs.copyWith(shortcutsEnabled: v))),
          title: const Text('启用快捷键'),
          subtitle: const Text('可自定义：新建任务、搜索任务（桌面/Web 推荐）'),
        ),
        const SizedBox(height: 6),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('新建任务'),
          subtitle: const Text('聚焦顶部快速添加输入框'),
          trailing: OutlinedButton(
            onPressed: _saving
                ? null
                : () async {
                    final next = await _promptShortcut(
                      context,
                      title: '设置「新建任务」快捷键',
                      currentValue: prefs.shortcutNewTask,
                    );
                    if (!mounted || next == null) return;
                    final nextNormalized =
                        normalizeShortcutString(next).toLowerCase();
                    final otherNormalized =
                        normalizeShortcutString(prefs.shortcutSearch)
                            .toLowerCase();
                    if (nextNormalized.isNotEmpty &&
                        nextNormalized == otherNormalized) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('快捷键冲突：已被「搜索任务」使用')),
                      );
                      return;
                    }
                    _updateSettings(_settings.copyWith(
                        preferences: prefs.copyWith(shortcutNewTask: next)));
                  },
            child: Text(shortcutDisplayLabel(prefs.shortcutNewTask)),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('搜索任务'),
          subtitle: const Text('聚焦顶部搜索框'),
          trailing: OutlinedButton(
            onPressed: _saving
                ? null
                : () async {
                    final next = await _promptShortcut(
                      context,
                      title: '设置「搜索任务」快捷键',
                      currentValue: prefs.shortcutSearch,
                    );
                    if (!mounted || next == null) return;
                    final nextNormalized =
                        normalizeShortcutString(next).toLowerCase();
                    final otherNormalized =
                        normalizeShortcutString(prefs.shortcutNewTask)
                            .toLowerCase();
                    if (nextNormalized.isNotEmpty &&
                        nextNormalized == otherNormalized) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('快捷键冲突：已被「新建任务」使用')),
                      );
                      return;
                    }
                    _updateSettings(_settings.copyWith(
                        preferences: prefs.copyWith(shortcutSearch: next)));
                  },
            child: Text(shortcutDisplayLabel(prefs.shortcutSearch)),
          ),
        ),
        if (_showDevOptions) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.naturalLanguageEnabled,
            onChanged: (v) => _updateSettings(_settings.copyWith(
                preferences: prefs.copyWith(naturalLanguageEnabled: v))),
            title: const Text('允许自然语言解析'),
            subtitle: const Text('例如：明天 9点 开会 #工作 !高（开发中）'),
          ),
          const SizedBox(height: 8),
        ],
        DropdownButtonFormField<String>(
          value: prefs.matrixScope,
          decoration: const InputDecoration(labelText: '四象限范围'),
          items: const [
            DropdownMenuItem(value: 'today', child: Text('仅今天未完成')),
            DropdownMenuItem(value: '3days', child: Text('近3天未完成')),
            DropdownMenuItem(value: 'all', child: Text('全部未完成')),
          ],
          onChanged: (value) {
            final scope = (value ?? prefs.matrixScope).trim();
            _updateSettings(_settings.copyWith(
                preferences: prefs.copyWith(matrixScope: scope)));
          },
        ),
        const SizedBox(height: 18),
        Text(
          '日历视图 · 任务块显示',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          value: prefs.calendarTimelineDefaultHour,
          decoration: const InputDecoration(labelText: '时间轴默认时间'),
          items: [
            for (var hour = 0; hour < 24; hour++)
              DropdownMenuItem(
                value: hour,
                child: Text('${hour.toString().padLeft(2, '0')}:00'),
              ),
          ],
          onChanged: (value) {
            _updateSettings(_settings.copyWith(
                preferences: prefs.copyWith(
                    calendarTimelineDefaultHour:
                        value ?? prefs.calendarTimelineDefaultHour)));
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: calendar.taskBlockShowStartTimeDay,
          onChanged: (v) => _updateSettings(
            _settings.copyWith(
                calendarSettings:
                    calendar.copyWith(taskBlockShowStartTimeDay: v)),
          ),
          title: const Text('日视图：显示开始时间'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: calendar.taskBlockShowTagsDay,
          onChanged: (v) => _updateSettings(
            _settings.copyWith(
                calendarSettings: calendar.copyWith(taskBlockShowTagsDay: v)),
          ),
          title: const Text('日视图：显示标签'),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: calendar.taskBlockShowStartTimeWeek,
          onChanged: (v) => _updateSettings(
            _settings.copyWith(
                calendarSettings:
                    calendar.copyWith(taskBlockShowStartTimeWeek: v)),
          ),
          title: const Text('周视图：显示开始时间'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: calendar.taskBlockShowTagsWeek,
          onChanged: (v) => _updateSettings(
            _settings.copyWith(
                calendarSettings: calendar.copyWith(taskBlockShowTagsWeek: v)),
          ),
          title: const Text('周视图：显示标签'),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: calendar.taskBlockShowStartTimeMonth,
          onChanged: (v) => _updateSettings(
            _settings.copyWith(
                calendarSettings:
                    calendar.copyWith(taskBlockShowStartTimeMonth: v)),
          ),
          title: const Text('月视图：显示开始时间'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: calendar.taskBlockShowTagsMonth,
          onChanged: (v) => _updateSettings(
            _settings.copyWith(
                calendarSettings: calendar.copyWith(taskBlockShowTagsMonth: v)),
          ),
          title: const Text('月视图：显示标签'),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection(BuildContext context) {
    final n = _settings.notifications;
    return ListView(
      children: [
        Text(
          '通知设置',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: n.enabled,
          onChanged: (v) {
            _updateSettings(
              _settings.copyWith(
                notifications: n.copyWith(enabled: v),
                pushEnabled: v,
              ),
            );
          },
          title: const Text('允许通知（总开关）'),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: n.leadMinutes,
          decoration: const InputDecoration(labelText: '提醒提前量'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('0 分钟')),
            DropdownMenuItem(value: 5, child: Text('5 分钟')),
            DropdownMenuItem(value: 10, child: Text('10 分钟')),
            DropdownMenuItem(value: 30, child: Text('30 分钟')),
          ],
          onChanged: n.enabled
              ? (value) => _updateSettings(
                    _settings.copyWith(
                        notifications:
                            n.copyWith(leadMinutes: value ?? n.leadMinutes)),
                  )
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          '静默时段（勿扰）',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: n.quietHoursEnabled,
          onChanged: n.enabled
              ? (v) => _updateSettings(
                    _settings.copyWith(
                      notifications: n.copyWith(quietHoursEnabled: v),
                    ),
                  )
              : null,
          title: const Text('启用勿扰时段'),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: n.enabled ? () => _pickQuietTime(start: true) : null,
                child: Text('开始：${n.quietStart}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed:
                    n.enabled ? () => _pickQuietTime(start: false) : null,
                child: Text('结束：${n.quietEnd}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: n.dueReminder,
          onChanged: n.enabled
              ? (v) => _updateSettings(
                  _settings.copyWith(notifications: n.copyWith(dueReminder: v)))
              : null,
          title: const Text('到期提醒'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: n.planStartReminder,
          onChanged: n.enabled
              ? (v) => _updateSettings(_settings.copyWith(
                  notifications: n.copyWith(planStartReminder: v)))
              : null,
          title: const Text('计划开始提醒'),
        ),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: 12),
          Text(
            '计时通知',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _timeTrackingOngoingNotificationEnabled,
            onChanged: _saving
                ? null
                : (v) async {
                    if (v) {
                      final granted = await LocalTaskNotifications.instance
                          .requestPermission();
                      if (!mounted) return;
                      if (!granted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('系统未授予通知权限')),
                        );
                        return;
                      }
                    }
                    setState(() => _timeTrackingOngoingNotificationEnabled = v);
                    try {
                      await widget
                          .onTimeTrackingOngoingNotificationEnabledChanged(v);
                    } catch (_) {
                      if (!mounted) return;
                      setState(() => _timeTrackingOngoingNotificationEnabled =
                          !v);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('保存失败')),
                      );
                    }
                  },
            title: const Text('通知栏显示进行中活动'),
            subtitle:
                const Text('显示活动名称、开始时间与计时器，并提供停止/切换活动操作。'),
          ),
        ],
        if (_showDevOptions) const SizedBox(height: 12),
        if (_showDevOptions)
          OutlinedButton.icon(
          onPressed: n.enabled && !_sendingLocalTest
              ? () async {
                  setState(() => _sendingLocalTest = true);
                  try {
                    final granted =
                        await LocalTaskNotifications.instance.requestPermission();
                    if (!mounted) return;
                    if (!granted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('系统未授予通知权限。')),
                      );
                      return;
                    }
                    await LocalTaskNotifications.instance.showTestNotification();
                  } finally {
                    if (mounted) setState(() => _sendingLocalTest = false);
                  }
                }
              : null,
          icon: const Icon(Icons.notifications),
          label: Text(_sendingLocalTest ? '发送中…' : '测试本地通知'),
        ),
        if (_showDevOptions) const SizedBox(height: 8),
        if (_showDevOptions)
          OutlinedButton.icon(
          onPressed: n.enabled && !_sendingFcmTest
              ? () async {
                  setState(() => _sendingFcmTest = true);
                  try {
                    final ready = await FirebaseBootstrap.ensureInitialized();
                    if (!mounted) return;
                    if (!ready) {
                      final hint = kIsWeb
                          ? '请先配置 Web 的 Firebase 信息（FcmConfig）。'
                          : 'Android 需配置 `android/app/google-services.json` 并启用 Google Services 插件。';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('FCM 未配置，无法发送通知。$hint')),
                      );
                      return;
                    }

                    final sync = await FcmNotificationController(
                      apiClient: widget.apiClient,
                    ).enable();
                    if (!mounted) return;
                    if (sync.state != FcmSyncState.enabled) {
                      final msg = switch (sync.state) {
                        FcmSyncState.permissionDenied =>
                          '系统未授予通知权限，请在系统设置中允许通知后重试。',
                        FcmSyncState.notConfigured => 'FCM 未配置，无法启用通知。',
                        FcmSyncState.missingVapidKey =>
                          '缺少 Web VAPID Key，无法启用通知。',
                        FcmSyncState.disabled => '通知已关闭。',
                        FcmSyncState.error =>
                          '启用通知失败：${sync.details ?? '未知错误'}',
                        FcmSyncState.enabled => '已启用通知。',
                      };
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(msg)));
                      return;
                    }

                    await widget.apiClient.sendFcmTest();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已发送测试通知。')),
                    );
                  } on ApiException catch (e) {
                    if (!mounted) return;
                    final body = e.body.trim();
                    final isFcmNotConfigured = e.statusCode == 500 &&
                        (body.contains('FCM not configured') ||
                            body.contains('\"FCM not configured\"'));
                    final msg = switch (e.statusCode) {
                      404 => '未找到设备 Token，请先打开“允许通知”，授予系统通知权限，并重新进入应用后再试。',
                      _ when isFcmNotConfigured =>
                        '服务器未配置 FCM（local_server 需设置 FIREBASE_SERVICE_ACCOUNT_JSON / FIREBASE_SERVICE_ACCOUNT_PATH）。',
                      _ => '发送失败：${e.body}',
                    };
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(msg)));
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('发送失败。')),
                    );
                  } finally {
                    if (mounted) setState(() => _sendingFcmTest = false);
                  }
                }
              : null,
          icon: const Icon(Icons.notifications_active_outlined),
          label: Text(_sendingFcmTest ? '发送中…' : '发送测试推送（FCM，高级）'),
        ),
      ],
    );
  }

  Widget _buildDataSection(BuildContext context) {
    final data = _settings.data;
    final backup = data.backup;
    final sync = data.sync;
    final retention = data.clearCompletedRetentionDays;

    String retentionLabel;
    switch (retention) {
      case 30:
        retentionLabel = '保留 30 天';
        break;
      case 90:
        retentionLabel = '保留 90 天';
        break;
      case -1:
        retentionLabel = '永久保留';
        break;
      default:
        retentionLabel = retention.toString();
        break;
    }

    return ListView(
      children: [
        Text(
          '数据管理',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onExportData == null
                    ? null
                    : () => widget.onExportData!.call(),
                icon: const Icon(Icons.file_download),
                label: const Text('导出 JSON'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onImportData == null
                    ? null
                    : () => widget.onImportData!.call(),
                icon: const Icon(Icons.file_upload),
                label: const Text('从 JSON 导入'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.onExportExcel == null
              ? null
              : () => widget.onExportExcel!.call(),
          icon: const Icon(Icons.table_view),
          label: const Text('导出 Excel'),
        ),
        if (_showDevOptions) ...[
          const SizedBox(height: 18),
          Text(
            '自动备份',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: backup.enabled,
            onChanged: (v) => _updateSettings(_settings.copyWith(
                data: data.copyWith(backup: backup.copyWith(enabled: v)))),
            title: const Text('开启自动备份（开发中）'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: backup.frequency,
            decoration: const InputDecoration(labelText: '频率'),
            items: const [
              DropdownMenuItem(value: 'daily', child: Text('每日')),
              DropdownMenuItem(value: 'weekly', child: Text('每周')),
            ],
            onChanged: backup.enabled
                ? (value) => _updateSettings(
                      _settings.copyWith(
                          data: data.copyWith(
                              backup: backup.copyWith(
                                  frequency: value ?? backup.frequency))),
                    )
                : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: backup.keep,
            decoration: const InputDecoration(labelText: '保留最近 N 份'),
            items: const [
              DropdownMenuItem(value: 5, child: Text('5 份')),
              DropdownMenuItem(value: 10, child: Text('10 份')),
              DropdownMenuItem(value: 20, child: Text('20 份')),
              DropdownMenuItem(value: 30, child: Text('30 份')),
            ],
            onChanged: backup.enabled
                ? (value) => _updateSettings(
                      _settings.copyWith(
                          data: data.copyWith(
                              backup: backup.copyWith(
                                  keep: value ?? backup.keep))),
                    )
                : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: backup.location,
            decoration: const InputDecoration(labelText: '备份位置'),
            items: const [
              DropdownMenuItem(value: 'local', child: Text('本地')),
              DropdownMenuItem(value: 'server', child: Text('服务器路径（自部署）')),
            ],
            onChanged: backup.enabled
                ? (value) => _updateSettings(
                      _settings.copyWith(
                          data: data.copyWith(
                              backup: backup.copyWith(
                                  location: value ?? backup.location))),
                    )
                : null,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _backupPathController,
            decoration: const InputDecoration(
              labelText: '服务器备份路径',
              hintText: '例如 /data/backups',
            ),
            onChanged: backup.enabled
                ? (value) => _updateSettings(_settings.copyWith(
                    data: data.copyWith(
                        backup: backup.copyWith(serverPath: value))))
                : null,
          ),
          const SizedBox(height: 18),
          Text(
            '同步',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: sync.mode,
            decoration: const InputDecoration(labelText: '同步开关'),
            items: const [
              DropdownMenuItem(value: 'local', child: Text('仅本地（开发中）')),
              DropdownMenuItem(value: 'server', child: Text('与服务器同步')),
            ],
            onChanged: (value) => _updateSettings(_settings.copyWith(
                data: data.copyWith(
                    sync: sync.copyWith(mode: value ?? sync.mode)))),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: sync.conflictStrategy,
            decoration: const InputDecoration(labelText: '冲突策略（开发中）'),
            items: const [
              DropdownMenuItem(value: 'latest', child: Text('以最新为准')),
              DropdownMenuItem(value: 'manual', child: Text('手动选择')),
              DropdownMenuItem(value: 'duplicate', child: Text('保留两份')),
            ],
            onChanged: (value) => _updateSettings(
              _settings.copyWith(
                  data: data.copyWith(
                      sync: sync.copyWith(
                          conflictStrategy: value ?? sync.conflictStrategy))),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          '危险操作',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900, color: AppColors.accentDeep),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: retention,
          decoration: const InputDecoration(labelText: '清空已完成任务：保留策略'),
          items: const [
            DropdownMenuItem(value: 30, child: Text('保留 30 天')),
            DropdownMenuItem(value: 90, child: Text('保留 90 天')),
            DropdownMenuItem(value: -1, child: Text('永久保留')),
          ],
          onChanged: (value) {
            if (value == null) return;
            _updateSettings(_settings.copyWith(
                data: data.copyWith(clearCompletedRetentionDays: value)));
          },
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentDeep,
              side: const BorderSide(color: AppColors.accentDeep),
            ),
            onPressed: widget.onClearCompleted == null || retention == -1
                ? null
                : () async {
                    final ok = await _confirmWithPhrase(
                      context,
                      title: '清空已完成任务',
                      message: '将删除超过 $retentionLabel 的已完成任务，此操作不可撤销。',
                      phrase: 'CLEAR',
                      confirmText: '清空',
                    );
                    if (!ok) return;
                    await widget.onClearCompleted!.call(retention);
                  },
            icon: const Icon(Icons.delete_sweep),
            label: const Text('清空已完成任务'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentDeep,
              foregroundColor: Colors.white,
            ),
            onPressed: widget.onDeleteAccount == null
                ? null
                : () async {
                    final ok = await _confirmWithPhrase(
                      context,
                      title: '删除账号与数据',
                      message: '将永久删除账号及所有数据，此操作不可撤销。',
                      phrase: 'DELETE',
                      confirmText: '删除',
                    );
                    if (!ok) return;
                    await widget.onDeleteAccount!.call();
                  },
            icon: const Icon(Icons.delete_forever),
            label: const Text('删除账号与数据'),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedSection(BuildContext context) {
    final adv = _settings.advanced;
    return ListView(
      children: [
        Text(
          '高级',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (_showDevOptions) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: adv.nlpExperimental,
            onChanged: (v) => _updateSettings(_settings.copyWith(
                advanced: adv.copyWith(nlpExperimental: v))),
            title: const Text('自然语言解析（实验）'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: adv.lowEnergySortExperimental,
            onChanged: (v) => _updateSettings(_settings.copyWith(
                advanced: adv.copyWith(lowEnergySortExperimental: v))),
            title: const Text('低能量模式排序（实验）'),
          ),
        ],
        if (widget.onOpenBackendSettings != null) ...[
          const SizedBox(height: 18),
          Text(
            '连接',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => widget.onOpenBackendSettings!.call(),
              icon: const Icon(Icons.cloud),
              label: const Text('后端地址设置'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    const githubUrl = 'https://github.com/hzc073';

    return ListView(
      children: [
        Text(
          '关于',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: const Text('版本'),
          subtitle: Text(AppVersion.current),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: const Text('作者'),
          subtitle: const Text('夜莺'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.link),
          title: const Text('GitHub'),
          subtitle: const Text(githubUrl),
          trailing: IconButton(
            tooltip: '复制',
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: githubUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制 GitHub 地址')),
              );
            },
            icon: const Icon(Icons.copy),
          ),
          onTap: () {
            Clipboard.setData(const ClipboardData(text: githubUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制 GitHub 地址')),
            );
          },
        ),
      ],
    );
  }

  Future<void> _refreshInvite() async {
    setState(() => _loadingInvite = true);
    try {
      final code = await widget.apiClient.refreshInviteCode();
      if (!mounted) return;
      setState(() {
        _inviteCode = code;
        _loadingInvite = false;
      });
    } on UnauthorizedException {
      widget.onLogout();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInvite = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刷新邀请码失败。')),
      );
    }
  }

  Future<void> _openChangePassword(BuildContext context) async {
    final result = await showDialog<_ChangePasswordResult>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );
    if (result == null) return;
    try {
      await widget.apiClient.changePassword(
          oldPassword: result.oldPassword, newPassword: result.newPassword);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已更新。')),
      );
    } on UnauthorizedException {
      widget.onLogout();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.body.isEmpty ? '修改密码失败。' : e.body)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('修改密码失败。')),
      );
    }
  }

  Future<void> _pickQuietTime({required bool start}) async {
    final n = _settings.notifications;
    final initial = start ? _parseTime(n.quietStart) : _parseTime(n.quietEnd);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    final normalized = _timeToHHmm(picked);
    _updateSettings(
      _settings.copyWith(
        notifications: start
            ? n.copyWith(quietStart: normalized)
            : n.copyWith(quietEnd: normalized),
      ),
    );
  }

  void _syncProfileControllers(UserSettings settings) {
    final profile = settings.profile;
    if (_nicknameController.text != profile.nickname) {
      _nicknameController.text = profile.nickname;
    }
    if (_avatarController.text != profile.avatar) {
      _avatarController.text = profile.avatar;
    }
    final backupPath = settings.data.backup.serverPath;
    if (_backupPathController.text != backupPath) {
      _backupPathController.text = backupPath;
    }
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消')),
        ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText)),
      ],
    ),
  );
  return result == true;
}

Future<bool> _confirmWithPhrase(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmText,
}) async {
  final controller = TextEditingController();
  String? error;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 10),
                Text('请输入确认词：$phrase'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: phrase,
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim() != phrase) {
                  setState(() => error = '确认词不正确。');
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: Text(confirmText),
            ),
          ],
        ),
      );
    },
  );

  controller.dispose();
  return result == true;
}

ThemeMode _themeModeFor(String value) {
  switch (value.trim()) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

TimeOfDay? _parseTime(String value) {
  final raw = value.trim();
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

String _timeToHHmm(TimeOfDay value) {
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatUtcOffsetMinutes(int minutes) {
  final sign = minutes >= 0 ? '+' : '-';
  final abs = minutes.abs();
  final hh = (abs ~/ 60).toString().padLeft(2, '0');
  final mm = (abs % 60).toString().padLeft(2, '0');
  final base = 'UTC$sign$hh:$mm';
  if (minutes == 8 * 60) return '$base (上海)';
  return base;
}

String _avatarLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.characters.first.toUpperCase();
}

class _ChangePasswordResult {
  const _ChangePasswordResult(
      {required this.oldPassword, required this.newPassword});

  final String oldPassword;
  final String newPassword;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _old = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _newPwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改密码'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _old,
              decoration: const InputDecoration(labelText: '原密码'),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newPwd,
              decoration: const InputDecoration(labelText: '新密码'),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              decoration: const InputDecoration(labelText: '确认新密码'),
              obscureText: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.accentDeep),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }

  void _submit() {
    final oldPwd = _old.text;
    final newPwd = _newPwd.text;
    final confirm = _confirm.text;
    if (oldPwd.isEmpty || newPwd.isEmpty) {
      setState(() => _error = '请输入原密码和新密码。');
      return;
    }
    if (newPwd != confirm) {
      setState(() => _error = '两次输入的新密码不一致。');
      return;
    }
    Navigator.of(context)
        .pop(_ChangePasswordResult(oldPassword: oldPwd, newPassword: newPwd));
  }
}
