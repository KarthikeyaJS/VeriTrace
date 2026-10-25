import '../../../core/api/api_client.dart';
import '../../../core/models/models.dart';

class AdminRepository {
  AdminRepository(this._api);
  final ApiClient _api;

  Future<List<UserProfile>> users({UserRole? role}) async {
    final res = await _api.get('/users', query: role == null ? null : {'role': role.name});
    return (res['users'] as List? ?? const []).whereType<Map>().map((u) => UserProfile.fromJson(Map<String, dynamic>.from(u))).toList();
  }

  Future<UserProfile> createUser({required String email, required String password, required String displayName, required UserRole role}) async {
    final res = await _api.post('/users', body: {'email': email, 'password': password, 'displayName': displayName, 'role': role.name});
    return UserProfile.fromJson(Map<String, dynamic>.from(res['user'] as Map));
  }

  Future<UserProfile> updateUser(String uid, {UserRole? role, bool? active, String? displayName}) async {
    final res = await _api.patch('/users/${Uri.encodeComponent(uid)}', body: {
      'role': ?role?.name,
      'active': ?active,
      'displayName': ?displayName,
    });
    return UserProfile.fromJson(Map<String, dynamic>.from(res['user'] as Map));
  }
}
