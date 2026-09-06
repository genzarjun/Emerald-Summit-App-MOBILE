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
}
