/// Supabase connection settings — the ONLY place credentials live.
///
/// Values are injected at build time from a gitignored `env.json` file via
/// `--dart-define-from-file=env.json`, so no keys ever live in source control.
/// See `env.example.json` for the template and README "Configuration".
///
/// The publishable key is safe to ship in the app (Row Level Security protects
/// the data). NEVER put a `secret` key (`sb_secret_...`, formerly
/// `service_role`) in `env.json` — that key bypasses RLS and belongs on a
/// server only.
///
/// This file is Supabase-specific by design: swapping backends means adding a
/// sibling config under the new backend's folder, not editing app code.
class SupabaseConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: '');

  /// Whether real credentials were provided at build time. When false, the app
  /// falls back to the in-memory sample backend — e.g. if you forget the
  /// `--dart-define-from-file=env.json` flag.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Google Sign-In client IDs, injected at build time from `env.json`.
  ///
  /// The native flow (`signInWithIdToken`) needs the **Web** client ID as the
  /// `serverClientId` on both platforms — that is the audience Supabase's Google
  /// provider is configured against — plus the platform's own client ID
  /// (`clientId`). iOS uses [googleIosClientId]; Android needs no `clientId`
  /// (Google resolves it from the package name + SHA-1). When [googleWebClientId]
  /// is empty the sign-in screen hides the Google button and only OTP is shown.
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');

  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '');

  /// Whether native Google sign-in is wired up (the Web client ID is present).
  static bool get googleSignInEnabled => googleWebClientId.isNotEmpty;

  /// TEST/DEV ONLY. When true, the sign-in screen attempts the `dev-login`
  /// bypass for "code emails" before the normal OTP flow (see
  /// [SUPABASE.md]). Off unless the build passes `--dart-define DEV_LOGIN=true`
  /// (e.g. a `"DEV_LOGIN": true` entry in a dev `env.json`). NEVER enable it in
  /// a production build; the Edge Function has its own second guard.
  static const bool devLoginEnabled =
      bool.fromEnvironment('DEV_LOGIN', defaultValue: false);
}
