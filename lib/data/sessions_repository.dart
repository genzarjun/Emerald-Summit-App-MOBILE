import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// Create/update/delete sessions. Writes are gated by RLS to admins and mentors
/// scoped to the session's discipline (see role_allowlist_setup.sql), so an
/// unauthorized write is rejected by the database even if the UI is bypassed.
class SessionsRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Column map keys: discipline_id, title, track, room, expert_name,
  /// start_time, end_time, capacity, description, sponsor.
  static Future<void> create(Map<String, dynamic> data) async {
    await _client.from('sessions').insert(data);
  }

  static Future<void> update(String id, Map<String, dynamic> data) async {
    await _client.from('sessions').update(data).eq('id', id);
  }

  static Future<void> delete(String id) async {
    await _client.from('sessions').delete().eq('id', id);
  }
}
