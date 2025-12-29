import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings._(
    this._prefs, {
    this.apiBaseUrlOverride,
    required this.timeTrackingOngoingNotificationEnabled,
  });

  static const _apiBaseUrlKey = 'glass_api_base_url_override';
  static const _timeTrackingOngoingNotificationEnabledKey =
      'glass_time_tracking_ongoing_notification_enabled';

  final SharedPreferences _prefs;
  String? apiBaseUrlOverride;
  bool timeTrackingOngoingNotificationEnabled;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_apiBaseUrlKey);
    final timeTrackingOngoingNotificationEnabled =
        prefs.getBool(_timeTrackingOngoingNotificationEnabledKey) ?? false;
    return AppSettings._(
      prefs,
      apiBaseUrlOverride: raw?.trim().isEmpty == true ? null : raw,
      timeTrackingOngoingNotificationEnabled:
          timeTrackingOngoingNotificationEnabled,
    );
  }

  Future<void> setApiBaseUrlOverride(String? value) async {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      apiBaseUrlOverride = null;
      await _prefs.remove(_apiBaseUrlKey);
    } else {
      apiBaseUrlOverride = trimmed;
      await _prefs.setString(_apiBaseUrlKey, trimmed);
    }
  }

  Future<void> setTimeTrackingOngoingNotificationEnabled(bool enabled) async {
    timeTrackingOngoingNotificationEnabled = enabled;
    await _prefs.setBool(_timeTrackingOngoingNotificationEnabledKey, enabled);
  }
}
