import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../../models/user_settings.dart';
import 'fcm_config.dart';
import 'firebase_bootstrap.dart';

enum FcmSyncState {
  disabled,
  enabled,
  notConfigured,
  permissionDenied,
  missingVapidKey,
  error,
}

class FcmSyncResult {
  const FcmSyncResult(this.state, {this.details});

  final FcmSyncState state;
  final String? details;
}

class FcmNotificationController {
  static const _tokenPrefKey = 'glass_fcm_token';

  ApiClient _apiClient;
  StreamSubscription<String>? _tokenRefreshSub;
  String? _currentToken;

  FcmNotificationController({required ApiClient apiClient})
      : _apiClient = apiClient;

  void updateApiClient(ApiClient apiClient) {
    _apiClient = apiClient;
  }

  Future<FcmSyncResult> syncFromSettings(UserSettings settings) async {
    final enabled = settings.notifications.enabled;
    if (!enabled) {
      await disable();
      return const FcmSyncResult(FcmSyncState.disabled);
    }
    return enable();
  }

  Future<FcmSyncResult> enable() async {
    final ready = await FirebaseBootstrap.ensureInitialized();
    if (!ready) {
      return const FcmSyncResult(FcmSyncState.notConfigured);
    }

    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      return const FcmSyncResult(FcmSyncState.permissionDenied);
    }

    if (kIsWeb && FcmConfig.webVapidKey.trim().isEmpty) {
      return const FcmSyncResult(FcmSyncState.missingVapidKey);
    }

    final token = await messaging.getToken(
      vapidKey: kIsWeb ? FcmConfig.webVapidKey : null,
    );
    if (token == null || token.trim().isEmpty) {
      return const FcmSyncResult(
        FcmSyncState.error,
        details: 'FCM token is null/empty.',
      );
    }

    await _apiClient.registerFcmToken(
      token: token,
      platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
    );

    _currentToken = token;
    await _persistToken(token);

    _tokenRefreshSub ??= messaging.onTokenRefresh.listen((nextToken) async {
      final trimmed = nextToken.trim();
      if (trimmed.isEmpty) return;
      _currentToken = trimmed;
      await _persistToken(trimmed);
      await _apiClient.registerFcmToken(
        token: trimmed,
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
      );
    });

    return const FcmSyncResult(FcmSyncState.enabled);
  }

  Future<void> disable() async {
    final saved = await _loadPersistedToken();
    final token = _currentToken ?? saved;

    try {
      if (token != null && token.isNotEmpty) {
        await _apiClient.unregisterFcmToken(token: token);
      } else {
        await _apiClient.unregisterFcmToken();
      }
    } catch (_) {
      // Don't block local cleanup on server errors.
    }

    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}

    _currentToken = null;
    await _clearPersistedToken();

    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }

  Future<String?> _loadPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tokenPrefKey);
    final trimmed = raw?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _persistToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenPrefKey, token);
  }

  Future<void> _clearPersistedToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenPrefKey);
  }
}
