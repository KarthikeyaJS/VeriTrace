import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Anonymous per-install identifier sent with scans (clone detection). Not linked to a person.
class DeviceId {
  static const _key = 'device_id';

  static Future<String> getOrCreate(SharedPreferences prefs) async {
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_key, id);
    return id;
  }
}
