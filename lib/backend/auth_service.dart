/// Backend-neutral authentication contract.
///
/// The app talks ONLY to this interface — it never imports a backend SDK. The
/// active backend (Supabase today) provides an implementation under its own
/// folder. To move to a different backend, implement this once there; no screen
/// or app-state code changes.
library;

/// A signed-in user, stripped of any backend-specific type.
class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

/// Thrown by [AuthService] when a sign-in step fails, carrying a message that is
/// safe to show the user. Backends map their own error types onto this so
/// callers never catch a backend-specific exception.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Passwordless (email one-time-code) auth surface the app needs.
abstract interface class AuthService {
  /// Emits whenever the auth state changes (sign-in, sign-out, token refresh).
  /// Carries no payload — listeners re-read [currentUser] / [isSignedIn].
  Stream<void> get authStateChanges;

  /// The current user, or null if nobody is signed in.
  AuthUser? get currentUser;

  /// Whether a session currently exists.
  bool get isSignedIn;

  /// Sends a one-time login code to [email], creating the account on first use.
  /// Throws [AuthFailure] with a user-safe message on failure.
  Future<void> sendEmailOtp(String email);

  /// Verifies the [code] emailed to [email], establishing a session.
  /// Throws [AuthFailure] with a user-safe message on failure.
  Future<void> verifyEmailOtp({required String email, required String code});

  /// TEST/DEV ONLY. Whether [email] is a registered "code email" (a test
  /// account), so the sign-in screen asks for the test-account password instead
  /// of emailing a code. Always false in a build without `DEV_LOGIN=true`, and
  /// false when the check can't be made, so the caller falls back to normal OTP.
  Future<bool> isTestAccount(String email);

  /// TEST/DEV ONLY. Signs in as a registered "code email" (a test account)
  /// WITHOUT an emailed OTP, using the shared test-account [password]. Returns
  /// once a real session exists. Throws [AuthFailure] with a user-safe message
  /// for a wrong email or password, or when test accounts are turned off.
  ///
  /// Guarded three ways (see the dev-login Edge Function + [SUPABASE.md]): the
  /// app must be built with `--dart-define DEV_LOGIN=true`, the function must
  /// have `DEV_LOGIN_ENABLED=true`, and it checks `DEV_LOGIN_PASSWORD`. It must
  /// never be enabled in production.
  Future<void> signInWithTestAccount({
    required String email,
    required String password,
  });

  /// Whether native Google sign-in is available in this build (provider
  /// configured, client IDs present). The sign-in screen shows the Google
  /// button only when this is true.
  bool get supportsGoogleSignIn;

  /// Signs in with Google via the native flow. Because accounts are keyed to a
  /// confirmed email, a Google identity whose email matches an existing account
  /// links to it — same user, same profile and data. Returns without error once
  /// a session is established; the auth-state stream drives navigation.
  ///
  /// Throws [AuthFailure] with a user-safe message on failure. A user who
  /// dismisses the Google sheet is a silent no-op (no session, no error).
  Future<void> signInWithGoogle();

  /// Ends the current session.
  Future<void> signOut();
}
