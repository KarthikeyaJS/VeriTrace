import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_bootstrap.dart';
import 'core/device/device_id.dart';
import 'features/auth/data/auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final config = AppConfig(prefs);
  await FirebaseBootstrap.init();
  final deviceId = await DeviceId.getOrCreate(prefs);

  final firebaseAuth = FirebaseBootstrap.ready ? FirebaseAuth.instance : null;
  final api = ApiClient(
    config: config,
    tokenProvider: () async => firebaseAuth?.currentUser?.getIdToken(),
  );
  final authRepository = FirebaseAuthRepository(api: api, auth: firebaseAuth, unavailableReason: FirebaseBootstrap.error);

  runApp(VeriTraceApp(config: config, api: api, authRepository: authRepository, deviceId: deviceId));
}
