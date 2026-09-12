// Hide Supabase's own AuthUser so our backend-neutral AuthUser is unambiguous.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../auth_service.dart';
import 'supabase_config.dart';

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
  Future<bool> tryDevLogin(String email) async {
    // First guard: only ever attempt this in a build explicitly flagged for it.
    if (!SupabaseConfig.devLoginEnabled) return false;
    final e = email.trim().toLowerCase();
    try {
      // The dev-login function checks the test_accounts table (second guard is
      // its own DEV_LOGIN_ENABLED secret) and, for a code email, returns the OTP
      // to complete the normal verify flow — a real Supabase session.
      final res = await _client.functions.invoke('dev-login', body: {'email': e});
      final data = res.data;
      if (data is! Map || data['test'] != true) return false;
      final otp = data['otp'] as String?;
      if (otp == null || otp.isEmpty) return false;
      final type = (data['type'] as String?) == 'magiclink'
          ? OtpType.magiclink
          : OtpType.email;
      await _client.auth.verifyOTP(type: type, email: e, token: otp);
      return true;
    } on AuthException catch (ex) {
      // A known code email whose sign-in genuinely failed — surface it.
      throw AuthFailure(ex.message);
    } catch (_) {
      // Function absent/disabled, not a code email, network hiccup → let the
      // caller fall back to the normal emailed-OTP flow.
      return false;
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
