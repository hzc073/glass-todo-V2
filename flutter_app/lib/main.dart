import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/app_settings.dart';
import 'core/auth_store.dart';
import 'core/login_attempt_limiter.dart';
import 'core/notifications/fcm_message_notifications.dart';
import 'core/notifications/fcm_notification_controller.dart';
import 'core/notifications/local_notifications.dart';
import 'core/notifications/time_tracking_notifications.dart';
import 'core/time_tracking_refresh_bus.dart';
import 'models/time_activity.dart';
import 'models/user_settings.dart';
import 'shells/shell_router.dart';
import 'ui/app_theme.dart';
import 'ui/login_page.dart';
import 'ui/widgets/app_settings_dialog.dart';
import 'ui/widgets/backend_settings_dialog.dart';
import 'utils/download.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  final config = await AppConfig.load();
  final authStore = await AuthStore.load();
  final settings = await AppSettings.load();
  final loginAttemptLimiter = await LoginAttemptLimiter.load();
  runApp(
    GlassTodoApp(
      config: config,
      authStore: authStore,
      settings: settings,
      loginAttemptLimiter: loginAttemptLimiter,
    ),
  );
}

class GlassTodoApp extends StatefulWidget {
  const GlassTodoApp({
    super.key,
    required this.config,
    required this.authStore,
    required this.settings,
    required this.loginAttemptLimiter,
  });

  final AppConfig config;
  final AuthStore authStore;
  final AppSettings settings;
  final LoginAttemptLimiter loginAttemptLimiter;

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
  late bool _timeTrackingOngoingNotificationEnabled;

  bool _fcmHandlersBound = false;
  StreamSubscription<RemoteMessage>? _fcmForegroundSub;
  StreamSubscription<RemoteMessage>? _fcmOpenedSub;
  bool _localNotificationsBound = false;
  bool _handlingTimeTrackingNotificationAction = false;

  @override
  void initState() {
    super.initState();
    _apiBaseUrl =
        widget.settings.apiBaseUrlOverride ?? widget.config.apiBaseUrl;
    _apiClient = ApiClient(baseUrl: _apiBaseUrl, authStore: widget.authStore);
    _fcmController = FcmNotificationController(apiClient: _apiClient);
    _timeTrackingOngoingNotificationEnabled =
        widget.settings.timeTrackingOngoingNotificationEnabled;
    unawaited(_bindLocalNotifications());
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
              timeTrackingOngoingNotificationEnabled:
                  _timeTrackingOngoingNotificationEnabled,
              onLogout: _handleLogout,
              onOpenSettings: _openAppSettings,
            )
          : LoginPage(
              appTitle: widget.config.appTitle,
              loginAttemptLimiter: widget.loginAttemptLimiter,
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

  Future<void> _bindLocalNotifications() async {
    if (_localNotificationsBound) return;
    _localNotificationsBound = true;

    final ready = await LocalNotifications.instance.ensureInitialized(
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
    );
    if (!ready) return;

    final launchDetails = await LocalNotifications.instance.plugin
        .getNotificationAppLaunchDetails();
    final response = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true && response != null) {
      unawaited(_handleLocalNotificationResponse(response));
    }
  }

  Future<void> _handleLocalNotificationResponse(
    NotificationResponse response,
  ) async {
    final actionId = response.actionId;
    if (!TimeTrackingNotifications.instance.isTimeTrackingAction(actionId)) {
      return;
    }

    if (_handlingTimeTrackingNotificationAction) return;
    _handlingTimeTrackingNotificationAction = true;

    try {
      if (!widget.authStore.isLoggedIn) {
        await TimeTrackingNotifications.instance.cancelOngoing();
        return;
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final switchActivityId =
          TimeTrackingNotifications.instance.switchActivityIdFromAction(actionId);

      final running = await _apiClient.getRunningEntries();
      if (running.isNotEmpty) {
        await Future.wait(
          running.map((entry) => _apiClient.stopEntry(entry.id, endedAt: nowMs)),
        );
      }

      if (actionId == TimeTrackingNotifications.actionStop) {
        await TimeTrackingNotifications.instance.cancelOngoing();
      } else if (switchActivityId != null) {
        final entry = await _apiClient.startEntry(
          activityId: switchActivityId,
          startedAt: nowMs,
        );

        final activities = await _apiClient.getActivities();
        TimeActivity? activity;
        for (final item in activities) {
          if (item.deletedAt != null) continue;
          if (item.id == switchActivityId) {
            activity = item;
            break;
          }
        }

        await TimeTrackingNotifications.instance.syncOngoing(
          enabled: _timeTrackingOngoingNotificationEnabled,
          runningEntry: entry,
          runningActivity: activity,
          activities: activities,
        );
      }

      TimeTrackingRefreshBus.instance.notify();
    } catch (_) {
      final ctx = _navKey.currentContext;
      if (ctx == null) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('计时操作失败')),
      );
    } finally {
      _handlingTimeTrackingNotificationAction = false;
    }
  }

  Future<void> _openAppSettings() async {
    final navContext = _navKey.currentContext;
    if (navContext == null) return;
    await showAppSettingsDialog(
      navContext,
      apiClient: _apiClient,
      username: widget.authStore.username ?? '用户',
      initialSettings: _userSettings,
      timeTrackingOngoingNotificationEnabled:
          _timeTrackingOngoingNotificationEnabled,
      onTimeTrackingOngoingNotificationEnabledChanged: (enabled) async {
        await widget.settings.setTimeTrackingOngoingNotificationEnabled(enabled);
        if (!mounted) return;
        setState(() => _timeTrackingOngoingNotificationEnabled = enabled);
      },
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
      onExportExcel: () => _exportExcelData(navContext),
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

  CellValue? _excelCellValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    if (value is String) return TextCellValue(value);
    try {
      return TextCellValue(jsonEncode(value));
    } catch (_) {
      return TextCellValue(value.toString());
    }
  }

  void _appendExcelTable({
    required Excel excel,
    required String sheetName,
    required List<Map<String, dynamic>> rows,
    List<String>? preferredColumns,
  }) {
    final sheet = excel[sheetName];

    final ordered = <String>[];
    final remaining = <String>{};
    for (final row in rows) {
      remaining.addAll(row.keys.map((k) => k.toString()));
    }

    if (preferredColumns != null) {
      for (final col in preferredColumns) {
        if (remaining.remove(col)) ordered.add(col);
      }
    }

    final rest = remaining.toList()..sort();
    ordered.addAll(rest);

    sheet.appendRow(ordered.map((col) => TextCellValue(col)).toList());
    for (final row in rows) {
      sheet.appendRow(
        ordered.map((col) => _excelCellValue(row[col])).toList(),
      );
    }
  }

  List<Map<String, dynamic>> _flattenToRows(Map<String, dynamic> map) {
    final rows = <Map<String, dynamic>>[];

    void walk(String prefix, dynamic node) {
      if (node is Map) {
        final typed = node.cast<String, dynamic>();
        for (final entry in typed.entries) {
          final next = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
          walk(next, entry.value);
        }
        return;
      }

      if (node is List) {
        rows.add({
          'path': prefix,
          'value': jsonEncode(node),
        });
        return;
      }

      rows.add({
        'path': prefix,
        'value': node,
      });
    }

    walk('', map);
    return rows;
  }

  Future<void> _exportExcelData(BuildContext context) async {
    try {
      final payload = await _apiClient.exportAllData();
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
      final filename = 'glass-todo-export-$stamp.xlsx';

      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet();
      if (defaultSheet != null) {
        excel.rename(defaultSheet, 'meta');
      }

      final meta = excel['meta'];
      meta.appendRow([TextCellValue('key'), TextCellValue('value')]);
      meta.appendRow([TextCellValue('exportedAt'), _excelCellValue(payload['exportedAt'])]);

      final data = payload['data'];
      if (data is Map) {
        final typed = data.cast<String, dynamic>();

        final settingsRaw = typed['settings'];
        if (settingsRaw is Map) {
          _appendExcelTable(
            excel: excel,
            sheetName: 'settings',
            rows: _flattenToRows(settingsRaw.cast<String, dynamic>()),
            preferredColumns: const ['path', 'value'],
          );
        }

        final tasksRaw = typed['tasks'];
        if (tasksRaw is List) {
          _appendExcelTable(
            excel: excel,
            sheetName: 'tasks',
            rows: tasksRaw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
            preferredColumns: const [
              'id',
              'title',
              'notes',
              'status',
              'dueDate',
              'startTime',
              'endDate',
              'endTime',
              'tags',
              'inbox',
              'priority',
              'remindAt',
              'repeatRule',
              'createdAt',
              'updatedAt',
              'deletedAt',
            ],
          );
        }

        final checklistsRaw = typed['checklists'];
        if (checklistsRaw is Map) {
          final checklists = checklistsRaw.cast<String, dynamic>();
          final listsRaw = checklists['lists'];
          if (listsRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'checklists_lists',
              rows:
                  listsRaw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
              preferredColumns: const [
                'id',
                'name',
                'owner',
                'sharedCount',
                'createdAt',
                'updatedAt',
              ],
            );
          }

          final columnsRaw = checklists['columns'];
          if (columnsRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'checklists_columns',
              rows: columnsRaw
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList(),
              preferredColumns: const [
                'id',
                'listId',
                'name',
                'sortOrder',
                'createdAt',
                'updatedAt',
              ],
            );
          }

          final itemsRaw = checklists['items'];
          if (itemsRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'checklists_items',
              rows:
                  itemsRaw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
              preferredColumns: const [
                'id',
                'listId',
                'columnId',
                'title',
                'completed',
                'completedBy',
                'notes',
                'createdAt',
                'updatedAt',
              ],
            );
          }

          final sharesRaw = checklists['shares'];
          if (sharesRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'checklists_shares',
              rows: sharesRaw
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList(),
              preferredColumns: const [
                'listId',
                'sharedUser',
                'canEdit',
                'createdAt',
              ],
            );
          }
        }

        final timeTrackingRaw = typed['timeTracking'];
        if (timeTrackingRaw is Map) {
          final tracking = timeTrackingRaw.cast<String, dynamic>();
          final activitiesRaw = tracking['activities'];
          if (activitiesRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'time_activities',
              rows: activitiesRaw
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList(),
              preferredColumns: const [
                'id',
                'name',
                'taskId',
                'icon',
                'color',
                'category',
                'goal',
                'note',
                'createdAt',
                'updatedAt',
                'deletedAt',
              ],
            );
          }

          final entriesRaw = tracking['entries'];
          if (entriesRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'time_entries',
              rows: entriesRaw
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList(),
              preferredColumns: const [
                'id',
                'activityId',
                'taskId',
                'startedAt',
                'endedAt',
                'durationMs',
                'note',
                'tags',
                'createdAt',
                'updatedAt',
                'deletedAt',
              ],
            );
          }

          final goalsRaw = tracking['goals'];
          if (goalsRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'time_goals',
              rows: goalsRaw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
            );
          }
        }

        final pomodoroRaw = typed['pomodoro'];
        if (pomodoroRaw is Map) {
          final pomodoro = pomodoroRaw.cast<String, dynamic>();
          final pomodoroSettingsRaw = pomodoro['settings'];
          if (pomodoroSettingsRaw is Map) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'pomodoro_settings',
              rows: _flattenToRows(pomodoroSettingsRaw.cast<String, dynamic>()),
              preferredColumns: const ['path', 'value'],
            );
          }
          final pomodoroStateRaw = pomodoro['state'];
          if (pomodoroStateRaw is Map) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'pomodoro_state',
              rows: _flattenToRows(pomodoroStateRaw.cast<String, dynamic>()),
              preferredColumns: const ['path', 'value'],
            );
          }
          final sessionsRaw = pomodoro['sessions'];
          if (sessionsRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'pomodoro_sessions',
              rows: sessionsRaw
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList(),
            );
          }
          final dailyStatsRaw = pomodoro['dailyStats'];
          if (dailyStatsRaw is List) {
            _appendExcelTable(
              excel: excel,
              sheetName: 'pomodoro_daily',
              rows: dailyStatsRaw
                  .whereType<Map>()
                  .map((e) => e.cast<String, dynamic>())
                  .toList(),
            );
          }
        }
      }

      final bytes = excel.encode();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to encode excel');
      }

      final downloaded = await downloadBytesFile(
        filename: filename,
        bytes: Uint8List.fromList(bytes),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(downloaded ? '已导出 Excel。' : '已生成 Excel。')),
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
