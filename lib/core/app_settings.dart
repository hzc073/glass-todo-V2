import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  AppSettings._(this._prefs, {this.apiBaseUrlOverride});

  static const _apiBaseUrlKey = 'glass_api_base_url_override';

  final SharedPreferences _prefs;
  String? apiBaseUrlOverride;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_apiBaseUrlKey);
    return AppSettings._(prefs, apiBaseUrlOverride: raw?.trim().isEmpty == true ? null : raw);
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
}
