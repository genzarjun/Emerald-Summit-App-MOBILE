import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  // Whether GoogleSignIn.instance.initialize has run this session (it must be
  // called exactly once before authenticate).
  bool _googleInitialized = false;

  @override
  bool get supportsGoogleSignIn => SupabaseConfig.googleSignInEnabled;

  @override
  Future<void> signInWithGoogle() async {
    if (!SupabaseConfig.googleSignInEnabled) {
      throw const AuthFailure('Google sign-in is not configured.');
    }
    try {
      final google = GoogleSignIn.instance;
      if (!_googleInitialized) {
        // The iOS client ID is only valid as `clientId` on iOS. On Android the
        // app is identified by its package name + signing SHA-1, so `clientId`
        // must be null there (env.json ships a single iOS ID for both platforms).
        final isIOS =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
        await google.initialize(
          // Web client ID = the audience Supabase's Google provider expects.
          serverClientId: SupabaseConfig.googleWebClientId,
          clientId: isIOS && SupabaseConfig.googleIosClientId.isNotEmpty
              ? SupabaseConfig.googleIosClientId
              : null,
        );
        _googleInitialized = true;
      }

      // Interactive sign-in. Throws GoogleSignInException(canceled) if the user
      // dismisses the sheet.
      final account = await google.authenticate();

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure('Google sign-in failed: no identity token.');
      }

      // Pass ONLY the ID token — no access token. In google_sign_in v7,
      // authentication (the ID token) and authorization (an access token from
      // authorizeScopes) are separate steps producing tokens that don't match:
      // the ID token's `at_hash` is bound to a different access token, so
      // supplying the authorized one makes Supabase reject it on iOS with
      // "access token hash does not match value in ID token". We only need the
      // user's identity, not a Google API token, so we omit it and Supabase
      // skips the at_hash check. Supabase still verifies the ID token and, when
      // the email matches an existing confirmed account, links this Google
      // identity to it (same user, same data).
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );
    } on GoogleSignInException catch (e) {
      // User-cancelled is a silent no-op, not an error to surface.
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      throw AuthFailure(e.description ?? 'Google sign-in was interrupted.');
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
