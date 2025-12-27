import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'fcm_config.dart';

class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static bool get isInitialized => Firebase.apps.isNotEmpty;

  /// Initializes Firebase if configured.
  ///
  /// - Web: requires `FcmConfig.isWebConfigured == true` and uses options.
  /// - Non-web: calls `Firebase.initializeApp()` (expects native Firebase files).
  static Future<bool> ensureInitialized() async {
    if (isInitialized) return true;
    try {
      if (kIsWeb) {
        if (!FcmConfig.isWebConfigured) return false;
        await Firebase.initializeApp(options: FcmConfig.webOptions);
        return true;
      }
      await Firebase.initializeApp();
      return true;
    } on FirebaseException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
