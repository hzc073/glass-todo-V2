import 'dart:ui' as ui;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../../models/time_activity.dart';
import '../../models/time_entry.dart';
import 'local_notifications.dart';

class TimeTrackingNotifications {
  TimeTrackingNotifications._();

  static final TimeTrackingNotifications instance = TimeTrackingNotifications._();
  static final Map<String, Uint8List> _emojiIconCache = <String, Uint8List>{};

  static const int ongoingNotificationId = 82001;
  static const String ongoingPayload = 'time_tracking_ongoing';

  static const String actionStop = 'time_tracking_stop';
  static const String actionSwitchPrefix = 'time_tracking_switch:';

  static const String _channelId = 'time_tracking_ongoing';
  static const String _channelName = '计时';
  static const String _channelDescription = '显示进行中的活动计时与快捷操作';

  bool isTimeTrackingAction(String? actionId) {
    final raw = actionId ?? '';
    if (raw == actionStop) return true;
    if (raw.startsWith(actionSwitchPrefix)) return true;
    return false;
  }

  String? switchActivityIdFromAction(String? actionId) {
    final raw = actionId ?? '';
    if (!raw.startsWith(actionSwitchPrefix)) return null;
    final activityId = raw.substring(actionSwitchPrefix.length).trim();
    return activityId.isEmpty ? null : activityId;
  }

  Future<void> cancelOngoing() async {
    final ready = await LocalNotifications.instance.ensureInitialized();
    if (!ready) return;
    await LocalNotifications.instance.plugin.cancel(ongoingNotificationId);
  }

  Future<void> syncOngoing({
    required bool enabled,
    required TimeEntry? runningEntry,
    required TimeActivity? runningActivity,
    required List<TimeActivity> activities,
  }) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final ready = await LocalNotifications.instance.ensureInitialized();
    if (!ready) return;

    if (!enabled || runningEntry == null || runningActivity == null) {
      await cancelOngoing();
      return;
    }

    final canPost = await LocalNotifications.instance.areNotificationsEnabled();
    if (!canPost) return;

    final startedAtMs = runningEntry.startedAt;
    final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);
    final startLabel = DateFormat('HH:mm').format(startedAt);

    final icon = runningActivity.icon.trim();
    final name = runningActivity.name.trim();
    final title = switch ((icon.isEmpty, name.isEmpty)) {
      (true, true) => '计时中',
      (false, true) => icon,
      (true, false) => name,
      (false, false) => '$icon $name',
    };
    final body = '开始 $startLabel';

    AndroidBitmap<Object>? largeIcon;
    final emoji = icon.characters.take(1).toString();
    final emojiBytes = await _emojiPngBytes(emoji);
    if (emojiBytes != null) {
      largeIcon = ByteArrayAndroidBitmap(emojiBytes);
    } else {
      largeIcon = const DrawableResourceAndroidBitmap('ic_launcher');
    }

    final otherActivities = activities
        .where((item) => item.deletedAt == null && item.id != runningActivity.id)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final actions = <AndroidNotificationAction>[
      const AndroidNotificationAction(
        actionStop,
        '停止',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      ...otherActivities.take(3).map(
            (activity) => AndroidNotificationAction(
              '$actionSwitchPrefix${activity.id}',
              _actionTitle(_activityLabel(activity)),
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ),
    ];

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        icon: 'ic_notify',
        largeIcon: largeIcon,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: true,
        when: startedAtMs,
        usesChronometer: true,
        category: AndroidNotificationCategory.service,
        actions: actions,
      ),
    );

    await LocalNotifications.instance.plugin.show(
      ongoingNotificationId,
      title,
      body,
      details,
      payload: ongoingPayload,
    );
  }

  static Future<Uint8List?> _emojiPngBytes(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final emoji = trimmed.characters.take(1).toString();
    if (emoji.isEmpty) return null;
    final cached = _emojiIconCache[emoji];
    if (cached != null) return cached;
    try {
      const canvasSize = 128;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      final painter = TextPainter(
        text: TextSpan(
          text: emoji,
          style: const TextStyle(fontSize: 96),
        ),
        textAlign: ui.TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      );
      painter.layout();
      painter.paint(
        canvas,
        ui.Offset(
          (canvasSize - painter.width) / 2,
          (canvasSize - painter.height) / 2,
        ),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(canvasSize, canvasSize);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return null;
      _emojiIconCache[emoji] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static String _actionTitle(String rawName) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return '切换';
    const max = 8;
    final chars = trimmed.characters;
    if (chars.length <= max) return trimmed;
    return chars.take(max).toString() + '…';
  }

  static String _activityLabel(TimeActivity activity) {
    final icon = activity.icon.trim();
    final name = activity.name.trim();
    if (icon.isNotEmpty && name.isNotEmpty) return '$icon $name';
    if (icon.isNotEmpty) return icon;
    if (name.isNotEmpty) return name;
    return '切换';
  }
}
