import 'package:flutter/foundation.dart';

class AppVersion {
  AppVersion._();

  static const String mobile = 'v2.0.1';
  static const String web = 'v2.0.1+251229';

  static String get current => kIsWeb ? web : mobile;
}

