import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../models/task.dart';

class LocalTaskNotifications {
  LocalTaskNotifications._();

  static final LocalTaskNotifications instance = LocalTaskNotifications._();

  static const String taskReminderPayloadPrefix = 'task_reminder:';
  static const String _channelId = 'task_reminders';
  static const String _channelName = '任务提醒';
  static const String _channelDescription = '任务开始时间提醒';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<bool> ensureInitialized() async {
    if (kIsWeb) return false;
    if (_initialized) return true;

    tz_data.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {}

    const settingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: settingsAndroid);
    await _plugin.initialize(settings);

    _initialized = true;
    return true;
  }

  Future<bool> requestPermission() async {
    final ready = await ensureInitialized();
    if (!ready) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    }
    return true;
  }

  Future<void> showTestNotification() async {
    final ready = await ensureInitialized();
    if (!ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      0,
      '测试通知',
      '如果你看到这条通知，说明本地通知已正常工作。',
      details,
    );
  }

  Future<void> cancelAllTaskReminders() async {
    final ready = await ensureInitialized();
    if (!ready) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final item in pending) {
      final payload = item.payload ?? '';
      if (!payload.startsWith(taskReminderPayloadPrefix)) continue;
      await _plugin.cancel(item.id);
    }
  }

  Future<void> syncTaskReminders(List<Task> tasks) async {
    final ready = await ensureInitialized();
    if (!ready) return;

    await cancelAllTaskReminders();

    final now = DateTime.now();
    for (final task in tasks) {
      if (task.deletedAt != null) continue;
      if (task.isCompleted) continue;
      final remindAt = task.remindAt;
      if (remindAt == null) continue;

      final when = DateTime.fromMillisecondsSinceEpoch(remindAt);
      if (!when.isAfter(now.add(const Duration(seconds: 1)))) continue;

      final id = _taskNotificationId(task.id);
      final body = task.title.trim().isEmpty ? '任务提醒' : task.title.trim();

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

      await _plugin.zonedSchedule(
        id,
        '开始时间提醒',
        body,
        tz.TZDateTime.from(when, tz.local),
        details,
        payload: '$taskReminderPayloadPrefix${task.id}',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  int _taskNotificationId(String rawId) {
    var hash = 0x811c9dc5;
    for (final unit in rawId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final positive = hash & 0x7FFFFFFF;
    return positive == 0 ? 1 : positive;
  }
}
