import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glass_todo_flutter/main.dart';
import 'package:glass_todo_flutter/core/app_config.dart';
import 'package:glass_todo_flutter/core/app_settings.dart';
import 'package:glass_todo_flutter/core/auth_store.dart';
import 'package:glass_todo_flutter/core/login_attempt_limiter.dart';

void main() {
  testWidgets('Launches login page when logged out', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    final config = AppConfig(
      apiBaseUrl: AppConfig.defaultApiBaseUrl,
      useLocalStorage: false,
      holidayJsonUrl: '',
      appTitle: 'Glass-ToDo',
    );
    final authStore = await AuthStore.load();
    final settings = await AppSettings.load();
    final loginAttemptLimiter = await LoginAttemptLimiter.load();

    await tester.pumpWidget(
      GlassTodoApp(
        config: config,
        authStore: authStore,
        settings: settings,
        loginAttemptLimiter: loginAttemptLimiter,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('用户名'), findsOneWidget);
  });
}
