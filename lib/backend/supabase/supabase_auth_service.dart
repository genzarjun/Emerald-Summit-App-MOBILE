// Hide Supabase's own AuthUser so our backend-neutral AuthUser is unambiguous.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../auth_service.dart';

/// Supabase implementation of [AuthService] (passwordless email OTP). Maps
/// Supabase's [AuthException] onto the neutral [AuthFailure] so callers never
/// see a backend-specific error type.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> get authStateChanges =>
      _client.auth.onAuthStateChange.map((_) {});

  @override
  AuthUser? get currentUser {
    final u = _client.auth.currentUser;
    return u == null ? null : AuthUser(id: u.id, email: u.email);
  }

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  Future<void> sendEmailOtp(String email) async {
    try {
      await _client.auth.signInWithOtp(email: email, shouldCreateUser: true);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    try {
      await _client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: code,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
