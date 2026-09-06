import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's personal schedule (the `registrations` table). Replaces
/// the in-memory AppState._mySessionIds so a schedule follows the account across
/// devices. Reads are RLS-scoped to the caller; adds/removes go through the
/// `register_for_session` RPC, which enforces capacity + no-time-overlap
/// server-side.
class RegistrationsRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// The session ids the current user has added to their day.
  static Future<Set<String>> fetchMySessionIds() async {
    final rows = await _client.from('registrations').select('session_id');
    return rows.map((r) => r['session_id'].toString()).toSet();
  }

  /// Toggles a session in the schedule via the RPC. Returns the outcome map:
  /// `{ outcome: added|removed|full|conflict, conflicting_title?: String }`.
  static Future<Map<String, dynamic>> toggle(String sessionId) async {
    final res = await _client.rpc(
      'register_for_session',
      params: {'p_session_id': sessionId},
    );
    return (res as Map).cast<String, dynamic>();
  }
}
