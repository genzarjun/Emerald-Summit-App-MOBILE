import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../models/models.dart';

/// Reads the session catalog from Supabase: all disciplines with their sessions
/// nested in. Sessions come from the `sessions_with_counts` view so each carries
/// a live `enrolled` count and its discipline name. Replaces SampleData as the
/// catalog source when the backend is configured.
class DisciplinesRepository {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Fetches disciplines (ordered) with their sessions grouped underneath.
  static Future<List<Discipline>> fetchAll() async {
    final discRows = await _client
        .from('disciplines')
        .select()
        .order('sort_order');

    final sessRows = await _client
        .from('sessions_with_counts')
        .select()
        .order('start_time');

    // Group sessions by their discipline_id (present on the view rows).
    final byDiscipline = <String, List<Session>>{};
    for (final row in sessRows) {
      final did = row['discipline_id'].toString();
      (byDiscipline[did] ??= <Session>[]).add(Session.fromMap(row));
    }

    return discRows
        .map((d) => Discipline.fromMap(
              d,
              sessions: byDiscipline[d['id'].toString()] ?? const [],
            ))
        .toList();
  }

  /// Creates a discipline (admin only — enforced by RLS). Column map keys:
  /// id, name, tagline, icon, sort_order.
  static Future<void> create(Map<String, dynamic> data) async {
    await _client.from('disciplines').insert(data);
  }
}
