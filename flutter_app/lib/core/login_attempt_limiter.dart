import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LoginAttemptState {
  const LoginAttemptState({
    required this.failedAttempts,
    required this.lastFailedAtMillis,
    required this.lockedUntilMillis,
  });

  final int failedAttempts;
  final int? lastFailedAtMillis;
  final int? lockedUntilMillis;

  bool get isLocked {
    final until = lockedUntilMillis;
    if (until == null) return false;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  Duration? get remainingLock {
    final until = lockedUntilMillis;
    if (until == null) return null;
    final delta = until - DateTime.now().millisecondsSinceEpoch;
    if (delta <= 0) return null;
    return Duration(milliseconds: delta);
  }
}

class LoginAttemptLimiter {
  LoginAttemptLimiter._(this._prefs);

  static const int maxFailedAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 10);
  static const Duration failureWindow = Duration(minutes: 10);

  static const String _failedAttemptsPrefix = 'glass_login_failed_attempts_';
  static const String _lastFailedAtPrefix = 'glass_login_last_failed_at_';
  static const String _lockedUntilPrefix = 'glass_login_locked_until_';

  final SharedPreferences _prefs;

  static Future<LoginAttemptLimiter> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LoginAttemptLimiter._(prefs);
  }

  LoginAttemptState stateFor(String username) {
    final suffix = _suffixFor(username);
    if (suffix == null) {
      return const LoginAttemptState(
        failedAttempts: 0,
        lastFailedAtMillis: null,
        lockedUntilMillis: null,
      );
    }

    return LoginAttemptState(
      failedAttempts: _prefs.getInt('$_failedAttemptsPrefix$suffix') ?? 0,
      lastFailedAtMillis: _prefs.getInt('$_lastFailedAtPrefix$suffix'),
      lockedUntilMillis: _prefs.getInt('$_lockedUntilPrefix$suffix'),
    );
  }

  Future<LoginAttemptState> recordSuccess(String username) async {
    final suffix = _suffixFor(username);
    if (suffix == null) return stateFor(username);
    await _prefs.remove('$_failedAttemptsPrefix$suffix');
    await _prefs.remove('$_lastFailedAtPrefix$suffix');
    await _prefs.remove('$_lockedUntilPrefix$suffix');
    return stateFor(username);
  }

  Future<LoginAttemptState> recordFailure(String username) async {
    final suffix = _suffixFor(username);
    if (suffix == null) return stateFor(username);

    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final existing = stateFor(username);

    final lockedUntilMillis = existing.lockedUntilMillis;
    if (lockedUntilMillis != null && lockedUntilMillis > nowMillis) {
      return existing;
    }

    var failedAttempts = existing.failedAttempts;
    final lastFailedAtMillis = existing.lastFailedAtMillis;
    if (lastFailedAtMillis != null) {
      final deltaMillis = nowMillis - lastFailedAtMillis;
      if (deltaMillis > failureWindow.inMilliseconds) {
        failedAttempts = 0;
      }
    }

    failedAttempts += 1;

    int? newLockedUntilMillis;
    if (failedAttempts >= maxFailedAttempts) {
      newLockedUntilMillis = nowMillis + lockDuration.inMilliseconds;
      failedAttempts = 0;
    }

    await _prefs.setInt('$_failedAttemptsPrefix$suffix', failedAttempts);
    await _prefs.setInt('$_lastFailedAtPrefix$suffix', nowMillis);
    if (newLockedUntilMillis != null) {
      await _prefs.setInt('$_lockedUntilPrefix$suffix', newLockedUntilMillis);
    } else {
      await _prefs.remove('$_lockedUntilPrefix$suffix');
    }

    return stateFor(username);
  }

  String? _suffixFor(String username) {
    final trimmed = username.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final encoded = base64UrlEncode(utf8.encode(trimmed));
    return encoded.replaceAll('=', '');
  }
}

