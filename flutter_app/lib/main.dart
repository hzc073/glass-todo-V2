import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/app_settings.dart';
import 'core/auth_store.dart';
import 'core/notifications/fcm_notification_controller.dart';
import 'models/user_settings.dart';
import 'shells/shell_router.dart';
import 'ui/app_theme.dart';
import 'ui/login_page.dart';
import 'ui/widgets/app_settings_dialog.dart';
import 'ui/widgets/backend_settings_dialog.dart';
import 'utils/download.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  final authStore = await AuthStore.load();
  final settings = await AppSettings.load();
  runApp(
      GlassTodoApp(config: config, authStore: authStore, settings: settings));
}

class GlassTodoApp extends StatefulWidget {
  const GlassTodoApp({
    super.key,
    required this.config,
    required this.authStore,
    required this.settings,
  });

  final AppConfig config;
  final AuthStore authStore;
  final AppSettings settings;

  @override
  State<GlassTodoApp> createState() => _GlassTodoAppState();
}

class _GlassTodoAppState extends State<GlassTodoApp> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  late ApiClient _apiClient;
  late final FcmNotificationController _fcmController;
  late String _apiBaseUrl;
  Key _taskPageKey = UniqueKey();
  UserSettings _userSettings = UserSettings.defaults();
  ThemeMode _themeMode = ThemeMode.system;

  bool _fcmHandlersBound = false;
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;

  @override
  void initState() {
    super.initState();
    _apiBaseUrl =
        widget.settings.apiBaseUrlOverride ?? widget.config.apiBaseUrl;
    _apiClient = ApiClient(baseUrl: _apiBaseUrl, authStore: widget.authStore);
    _fcmController = FcmNotificationController(apiClient: _apiClient);
    if (widget.authStore.isLoggedIn) {
      _loadUserSettings();
    }
  }

  @override
  void dispose() {
    _fcmForegroundSub?.cancel();
    _fcmOpenedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.config.appTitle,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      home: widget.authStore.isLoggedIn
          ? ShellRouter(
              key: _taskPageKey,
              appTitle: widget.config.appTitle,
              username: widget.authStore.username ?? '用户',
              apiClient: _apiClient,
              userSettings: _userSettings,
              onLogout: _handleLogout,
              onOpenSettings: _openAppSettings,
            )
          : LoginPage(
              appTitle: widget.config.appTitle,
              onLogin: _handleLogin,
              onOpenSettings: _openBackendSettings,
            ),
    );
  }

  Future<LoginOutcome> _handleLogin(
    String username,
    String password,
    String inviteCode,
  ) async {
    try {
      final result = await _apiClient.login(
        username,
        password,
        inviteCode: inviteCode,
      );
      final success = result['success'] == true;
      setState(() {});
      if (success) {
        await _loadUserSettings();
      }
      return LoginOutcome(
        success: success,
        error: result['error']?.toString(),
        needInvite: result['needInvite'] == true,
      );
    } catch (e) {
      return const LoginOutcome(success: false, error: '登录失败。');
    }
  }

  Future<void> _handleLogout() async {
    await _fcmController.disable();
    await _fcmForegroundSub?.cancel();
    await _fcmOpenedSub?.cancel();
    _fcmForegroundSub = null;
    _fcmOpenedSub = null;
    _fcmHandlersBound = false;
    await widget.authStore.clear();
    setState(() {});
  }

  ThemeMode _themeModeFor(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> _loadUserSettings() async {
    try {
      final settings = await _apiClient.getUserSettings();
      if (!mounted) return;
      setState(() {
        _userSettings = settings;
        _themeMode = _themeModeFor(settings.preferences.theme);
      });
      unawaited(_syncFcmFromSettings(settings));
    } on UnauthorizedException {
      await _handleLogout();
    } catch (_) {}
  }

  Future<void> _syncFcmFromSettings(UserSettings settings) async {
    try {
      final result = await _fcmController.syncFromSettings(settings);
      if (!mounted) return;
      if (result.state == FcmSyncState.enabled) {
        _bindFcmMessageHandlers();
      }
    } catch (_) {}
  }

  void _bindFcmMessageHandlers() {
    if (_fcmHandlersBound) return;
    _fcmHandlersBound = true;

    _fcmForegroundSub ??= FirebaseMessaging.onMessage.listen((message) {
      final ctx = _navKey.currentContext;
      if (ctx == null) return;
      final title =
          message.notification?.title ?? message.data['title']?.toString() ?? '通知';
      final body =
          message.notification?.body ?? message.data['body']?.toString() ?? '';
      final text = body.trim().isEmpty ? title : '$title：$body';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
    });

    _fcmOpenedSub ??= FirebaseMessaging.onMessageOpenedApp.listen((_) {});

    unawaited(FirebaseMessaging.instance.getInitialMessage().then((_) {}));
  }

  Future<void> _openAppSettings() async {
    final navContext = _navKey.currentContext;
    if (navContext == null) return;
    await showAppSettingsDialog(
      navContext,
      apiClient: _apiClient,
      username: widget.authStore.username ?? '用户',
      initialSettings: _userSettings,
      onLogout: () => _handleLogout(),
      onSettingsApplied: (settings) {
        setState(() => _userSettings = settings);
        unawaited(_syncFcmFromSettings(settings));
      },
      onThemeModeChanged: (mode) {
        setState(() => _themeMode = mode);
      },
      onOpenBackendSettings: _openBackendSettings,
      onExportData: () => _exportData(navContext),
      onImportData: () => _importData(navContext),
      onClearCompleted: (days) => _clearCompletedTasks(navContext, days),
      onDeleteAccount: () => _deleteAccount(navContext),
    );
  }

  Future<void> _exportData(BuildContext context) async {
    try {
      final payload = await _apiClient.exportAllData();
      final pretty = const JsonEncoder.withIndent('  ').convert(payload);
      final now = DateTime.now();
      final stamp = [
        now.year.toString().padLeft(4, '0'),
        now.month.toString().padLeft(2, '0'),
        now.day.toString().padLeft(2, '0'),
        '-',
        now.hour.toString().padLeft(2, '0'),
        now.minute.toString().padLeft(2, '0'),
        now.second.toString().padLeft(2, '0'),
      ].join();
      final filename = 'glass-todo-export-$stamp.json';
      final downloaded = await downloadTextFile(
          filename: filename, content: pretty, mimeType: 'application/json');
      await Clipboard.setData(ClipboardData(text: pretty));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(downloaded ? '已导出 JSON，并复制到剪贴板。' : '已复制 JSON 到剪贴板。')),
      );
    } on UnauthorizedException {
      await _handleLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('导出失败。')));
    }
  }

  Future<String?> _pickImportMode(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 JSON 导入'),
        content: const Text('请选择导入模式：覆盖会先清空本账号数据，再导入文件内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('merge'),
            child: const Text('合并'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('overwrite'),
            child: const Text('覆盖'),
          ),
        ],
      ),
    );
  }

  Future<void> _importData(BuildContext context) async {
    try {
      final mode = await _pickImportMode(context);
      if (mode == null) return;
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读取文件失败。')));
        return;
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('JSON 格式不正确。')));
        return;
      }
      final data = decoded.cast<String, dynamic>();
      await _apiClient.importAllData(mode: mode, data: data);
      await _loadUserSettings();
      if (!mounted) return;
      setState(() => _taskPageKey = UniqueKey());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('导入完成。')));
    } on UnauthorizedException {
      await _handleLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('导入失败。')));
    }
  }

  Future<void> _clearCompletedTasks(
      BuildContext context, int retentionDays) async {
    try {
      final purged =
          await _apiClient.cleanupCompletedTasks(retentionDays: retentionDays);
      if (!mounted) return;
      setState(() => _taskPageKey = UniqueKey());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已清空 $purged 个已完成任务。')));
    } on UnauthorizedException {
      await _handleLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('清空失败。')));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    try {
      await _apiClient.deleteAccountAndData();
      await _handleLogout();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('账号已删除。')));
    } on UnauthorizedException {
      await _handleLogout();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败。')));
    }
  }

  Future<void> _openBackendSettings() async {
    final navContext = _navKey.currentContext;
    if (navContext == null) return;
    final current =
        _apiBaseUrl.trim().isEmpty ? widget.config.apiBaseUrl : _apiBaseUrl;
    final next =
        await showBackendSettingsDialog(navContext, initialValue: current);
    if (next == null) return;
    await _updateBaseUrl(next);
  }

  Future<void> _updateBaseUrl(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      await widget.settings.setApiBaseUrlOverride(null);
      _apiBaseUrl = widget.config.apiBaseUrl;
    } else {
      await widget.settings.setApiBaseUrlOverride(trimmed);
      _apiBaseUrl = trimmed;
    }
    _apiClient = ApiClient(baseUrl: _apiBaseUrl, authStore: widget.authStore);
    _fcmController.updateApiClient(_apiClient);
    if (widget.authStore.isLoggedIn) {
      unawaited(_syncFcmFromSettings(_userSettings));
    }
    setState(() {});
  }
}
