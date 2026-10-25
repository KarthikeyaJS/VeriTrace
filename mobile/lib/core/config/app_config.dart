import 'package:shared_preferences/shared_preferences.dart';

/// Runtime configuration.
///
/// The backend URL comes from `--dart-define=API_BASE_URL=http://<laptop-ip>:3000`
/// and can be overridden at runtime from the hidden settings on the login screen.
class AppConfig {
  AppConfig(this._prefs);

  static const String _compiledBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Optional `host:port` of the Firebase Auth emulator, e.g. `192.168.1.12:9099`.
  static const String authEmulatorHost = String.fromEnvironment('FIREBASE_AUTH_EMULATOR');

  static const _baseUrlKey = 'api_base_url_override';

  final SharedPreferences _prefs;

  String get defaultApiBaseUrl => _compiledBaseUrl;

  String get apiBaseUrl => _prefs.getString(_baseUrlKey) ?? _compiledBaseUrl;

  bool get hasOverride => _prefs.containsKey(_baseUrlKey);

  /// Saves an override; pass null or an empty string to go back to the compiled default.
  Future<void> setApiBaseUrl(String? url) async {
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      await _prefs.remove(_baseUrlKey);
    } else {
      await _prefs.setString(_baseUrlKey, value.replaceAll(RegExp(r'/+$'), ''));
    }
  }
}
