import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class LocalNotifications {
  LocalNotifications._();

  static final LocalNotifications instance = LocalNotifications._();

  final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  Future<bool>? _initializing;
  bool _tzInitialized = false;

  DidReceiveNotificationResponseCallback? _onDidReceiveNotificationResponse;
  DidReceiveBackgroundNotificationResponseCallback?
      _onDidReceiveBackgroundNotificationResponse;

  bool get _isTestEnv => const bool.fromEnvironment('FLUTTER_TEST');

  Future<bool> ensureInitialized({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    if (kIsWeb) return false;
    if (_isTestEnv) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return false;

    final nextOnDidReceive =
        onDidReceiveNotificationResponse ?? _onDidReceiveNotificationResponse;
    final nextOnDidReceiveBackground =
        onDidReceiveBackgroundNotificationResponse ??
            _onDidReceiveBackgroundNotificationResponse;

    final shouldReinitialize = !_initialized ||
        nextOnDidReceive != _onDidReceiveNotificationResponse ||
        nextOnDidReceiveBackground != _onDidReceiveBackgroundNotificationResponse;

    _onDidReceiveNotificationResponse = nextOnDidReceive;
    _onDidReceiveBackgroundNotificationResponse = nextOnDidReceiveBackground;

    if (!shouldReinitialize) return true;

    if (_initializing != null) return await _initializing!;

    _initializing = _doInitialize();
    try {
      return await _initializing!;
    } finally {
      _initializing = null;
    }
  }

  Future<bool> requestPermission() async {
    final ready = await ensureInitialized();
    if (!ready) return false;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<bool> areNotificationsEnabled() async {
    final ready = await ensureInitialized();
    if (!ready) return false;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  Future<bool> _doInitialize() async {
    if (!_tzInitialized) {
      tz_data.initializeTimeZones();
      try {
        final tzInfo = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
      } catch (_) {}
      _tzInitialized = true;
    }

    const settingsAndroid = AndroidInitializationSettings('ic_notify');
    const settings = InitializationSettings(android: settingsAndroid);
    await plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onDidReceiveBackgroundNotificationResponse,
    );

    _initialized = true;
    return true;
  }
}
