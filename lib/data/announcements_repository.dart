import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../supabase_config.dart';

/// Fetches announcements. When Supabase is configured it reads live from the
/// `announcements` table; otherwise it's the caller's job to fall back to
/// sample data. This is the connectivity test for the backend.
class AnnouncementsRepository {
  /// Pulls announcements newest-first, pinned ones surfaced to the top.
  static Future<List<Announcement>> fetch() async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase is not configured');
    }
    final rows = await Supabase.instance.client
        .from('announcements')
        .select()
        .order('pinned', ascending: false)
        .order('created_at', ascending: false);

    return rows.map((r) => Announcement.fromMap(r)).toList();
  }

  /// Posts a new announcement (admin only — enforced by RLS). Every open app is
  /// notified via Realtime, and the row's insert is what a future push pipeline
  /// would hang off. [disciplineId] targets an audience; null = everyone.
  static Future<void> create({
    required String title,
    required String body,
    required String author,
    String audience = 'Everyone',
    bool pinned = false,
    String? disciplineId,
  }) async {
    final client = Supabase.instance.client;
    await client.from('announcements').insert({
      'title': title,
      'body': body,
      'author': author,
      'audience': audience,
      'pinned': pinned,
      'discipline_id': disciplineId,
      'created_by': client.auth.currentUser?.id,
    });
  }
}
