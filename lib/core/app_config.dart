import 'dart:convert';

import 'package:http/http.dart' as http;

class AppConfig {
  static const String defaultApiBaseUrl = 'http://localhost:3000';

  const AppConfig({
    required this.apiBaseUrl,
    required this.useLocalStorage,
    required this.holidayJsonUrl,
    required this.appTitle,
  });

  final String apiBaseUrl;
  final bool useLocalStorage;
  final String holidayJsonUrl;
  final String appTitle;

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final rawApiBaseUrl = (json['apiBaseUrl'] ?? '').toString().trim();
    return AppConfig(
      apiBaseUrl: rawApiBaseUrl.isEmpty ? defaultApiBaseUrl : rawApiBaseUrl,
      useLocalStorage: json['useLocalStorage'] == true,
      holidayJsonUrl: (json['holidayJsonUrl'] ?? '').toString().trim(),
      appTitle: (json['appTitle'] ?? 'Glass Todo').toString(),
    );
  }

  static Future<AppConfig> load() async {
    try {
      final uri = Uri.base.resolve('config.json');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json is Map<String, dynamic>) {
          return AppConfig.fromJson(json);
        }
      }
    } catch (_) {
      // Fallback to defaults when config.json is unavailable.
    }
    return const AppConfig(
      apiBaseUrl: defaultApiBaseUrl,
      useLocalStorage: false,
      holidayJsonUrl: '',
      appTitle: 'Glass Todo',
    );
  }
}
