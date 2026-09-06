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

  /// Ends the current session.
  Future<void> signOut();
}
