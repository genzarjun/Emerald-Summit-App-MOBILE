import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

/// Checks whether the signed-in user is eligible for a gated role (mentor or
/// admin). This is ADVISORY — it drives the "you aren't eligible" message during
/// onboarding. The real guarantee is the `profiles` enforcement trigger in
/// role_allowlist_setup.sql, which the client cannot bypass. RLS only ever
/// returns the caller's own allowlist row.
class AllowlistRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// True if the current user's email is allow-listed for [role].
  static Future<bool> isEligible(SummitRole role) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) return false;
    final row = await _client
        .from('role_allowlist')
        .select('email')
        .eq('email', email.toLowerCase())
        .eq('role', role.id)
        .maybeSingle();
    return row != null;
  }
}
