import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'app_config.dart';

/// Initialises Firebase. Consumers never need it, so a missing configuration only
/// disables business login instead of crashing the app.
class FirebaseBootstrap {
  static bool ready = false;
  static String? error;

  static Future<void> init() async {
    final emulator = AppConfig.authEmulatorHost;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (emulator.isEmpty) {
        error = 'Firebase is not configured in this build (google-services.json missing).';
        debugPrint('Firebase init failed: $e');
        return;
      }
      // Emulator-only build: any options work because the emulator does not check them.
      try {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: 'demo-key',
            appId: '1:000000000000:android:0000000000000000',
            messagingSenderId: '000000000000',
            projectId: 'demo-veritrace',
          ),
        );
      } catch (e2) {
        error = 'Firebase could not start: $e2';
        return;
      }
    }
    if (emulator.isNotEmpty) {
      final parts = emulator.split(':');
      await FirebaseAuth.instance.useAuthEmulator(parts.first, parts.length > 1 ? int.parse(parts[1]) : 9099);
    }
    ready = true;
  }
}
