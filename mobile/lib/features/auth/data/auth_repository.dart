import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/models.dart';

/// Business login. Firebase Auth proves identity; the backend's `/me` supplies the role.
abstract class AuthRepository {
  bool get isAvailable;
  String? get unavailableReason;
  Future<UserProfile?> restoreSession();
  Future<UserProfile> signIn(String email, String password);
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({required this._api, this._auth, this._unavailableReason});

  final ApiClient _api;
  final FirebaseAuth? _auth;
  final String? _unavailableReason;

  @override
  bool get isAvailable => _auth != null;

  @override
  String? get unavailableReason => _unavailableReason;

  Future<UserProfile> _fetchProfile() async {
    final res = await _api.get('/me');
    final profile = UserProfile.fromJson(Map<String, dynamic>.from(res['user'] as Map));
    if (profile.role == UserRole.none) {
      throw const ApiException(code: 'NO_ROLE', message: 'This account has no business role.');
    }
    return profile;
  }

  @override
  Future<UserProfile?> restoreSession() async {
    final auth = _auth;
    if (auth == null || auth.currentUser == null) return null;
    try {
      return await _fetchProfile();
    } on ApiException catch (e) {
      // Account deactivated / profile removed: sign out. Network errors keep the session.
      if (e.statusCode == 401 || e.statusCode == 403) await auth.signOut();
      rethrow;
    }
  }

  @override
  Future<UserProfile> signIn(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      throw ApiException(code: 'FIREBASE_UNAVAILABLE', message: _unavailableReason ?? 'Business login is not configured.');
    }
    try {
      await auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (e) {
      throw ApiException(code: e.code, message: _firebaseMessage(e));
    }
    try {
      return await _fetchProfile();
    } catch (_) {
      await auth.signOut();
      rethrow;
    }
  }

  @override
  Future<void> signOut() async => _auth?.signOut();

  static String _firebaseMessage(FirebaseAuthException e) => switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-login-credentials' => 'Incorrect email or password.',
        'invalid-email' => 'Enter a valid email address.',
        'user-disabled' => 'This account has been deactivated. Contact your admin.',
        'too-many-requests' => 'Too many attempts. Please wait a moment and try again.',
        'network-request-failed' => 'No connection to the sign-in service. Check your internet connection.',
        _ => e.message ?? 'Sign-in failed (${e.code}).',
      };
}
