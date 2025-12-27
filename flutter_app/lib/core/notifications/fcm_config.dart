import 'package:firebase_core/firebase_core.dart';

/// FCM/Firebase configuration for Flutter Web.
///
/// This project is currently Web-first; Android/iOS native projects can be
/// added later (then you can use google-services.json / GoogleService-Info.plist
/// and call `Firebase.initializeApp()` without options on mobile).
///
/// For Web, we keep config out of git by default and read it from `--dart-define`.
///
/// Example:
/// `flutter run -d chrome --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... ...`
class FcmConfig {
  const FcmConfig._();

  // Web Firebase config (from Firebase console -> Project settings -> Web app)
  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String authDomain =
      String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const String storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String measurementId =
      String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

  // Web Push certificate key (Firebase console -> Cloud Messaging -> Web Push)
  static const String webVapidKey =
      String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

  static bool get isWebConfigured =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  static FirebaseOptions get webOptions {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      measurementId: measurementId.isEmpty ? null : measurementId,
    );
  }
}
