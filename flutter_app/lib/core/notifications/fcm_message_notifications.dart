import 'dart:ui';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_bootstrap.dart';
import 'local_notifications.dart';

class FcmMessageNotifications {
  FcmMessageNotifications._();

  static final FcmMessageNotifications instance = FcmMessageNotifications._();

  static const String _channelId = 'fcm_messages';
  static const String _channelName = '推送通知';
  static const String _channelDescription = '来自服务器的推送通知';

  Future<void> show(RemoteMessage message) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    final ready = await LocalNotifications.instance.ensureInitialized();
    if (!ready) return;

    final title =
        _stringOrNull(message.data['title']) ?? message.notification?.title ?? 'Glass-ToDo';
    final body = _stringOrNull(message.data['body']) ?? message.notification?.body ?? '';

    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty && trimmedBody.isEmpty) return;

    final tag = _stringOrNull(message.data['tag'])?.trim();
    final id = _stableId(tag ?? DateTime.now().millisecondsSinceEpoch.toString());
    final payload = _buildPayload(message);

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        icon: 'ic_notify',
        largeIcon: const DrawableResourceAndroidBitmap('ic_launcher'),
        importance: Importance.high,
        priority: Priority.high,
        tag: tag == null || tag.isEmpty ? null : tag,
      ),
    );

    await LocalNotifications.instance.plugin.show(
      id,
      trimmedTitle.isEmpty ? 'Glass-ToDo' : trimmedTitle,
      trimmedBody.isEmpty ? null : trimmedBody,
      details,
      payload: payload,
    );
  }

  static String? _buildPayload(RemoteMessage message) {
    final url = _stringOrNull(message.data['url'])?.trim();
    if (url == null || url.isEmpty) return null;
    return 'fcm_url:$url';
  }

  static String? _stringOrNull(Object? value) {
    final raw = value?.toString();
    final trimmed = raw?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int _stableId(String raw) {
    var hash = 0x811c9dc5;
    for (final unit in raw.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final positive = hash & 0x7FFFFFFF;
    return positive == 0 ? 1 : positive;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await FirebaseBootstrap.ensureInitialized();
  await FcmMessageNotifications.instance.show(message);
}

