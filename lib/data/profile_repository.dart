import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import '../supabase_config.dart';

/// Reads and writes the signed-in user's own `profiles` row. Every call is
/// scoped by RLS to `auth.uid()`, so a user can only ever touch their own
/// profile.
class ProfileRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Loads the current user's profile. Returns null if nobody is signed in.
  /// If the row is somehow missing (e.g. the sign-up trigger didn't fire),
  /// returns a blank, not-yet-onboarded profile so onboarding can proceed.
  static Future<UserProfile?> fetchMine() async {
    if (!SupabaseConfig.isConfigured) return null;
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      return UserProfile(id: user.id, email: user.email ?? '');
    }
    return UserProfile.fromMap(row);
  }

  /// Inserts or updates the user's profile row.
  static Future<void> save(UserProfile profile) async {
    await _client.from('profiles').upsert(profile.toMap());
  }

  /// Updates just the given columns on the current user's row (RLS-scoped to
  /// them). Used for per-user state like the notifications toggle, so it never
  /// clobbers the rest of the profile.
  static Future<void> patch(Map<String, dynamic> fields) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('profiles').update(fields).eq('id', user.id);
  }
}
