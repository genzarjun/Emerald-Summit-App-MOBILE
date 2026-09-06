import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../../models/models.dart';
import '../../models/user_profile.dart';
import '../repositories.dart';

/// Supabase implementations of the app's repository interfaces. All Supabase
/// query syntax lives here (and in the auth service) — nowhere else in the app.

/// Reads the catalog: disciplines with their sessions nested in. Sessions come
/// from the `sessions_with_counts` view so each carries a live `enrolled` count
/// and its discipline name.
class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Discipline>> fetchAll() async {
    final discRows =
        await _client.from('disciplines').select().order('sort_order');

    final sessRows = await _client
        .from('sessions_with_counts')
        .select()
        .order('start_time');

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

  @override
  Future<void> createDiscipline(Map<String, dynamic> data) async {
    await _client.from('disciplines').insert(data);
  }
}

/// Create/update/delete sessions. Writes are gated by RLS to admins and mentors
/// scoped to the session's discipline.
class SupabaseContentRepository implements ContentRepository {
  SupabaseContentRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> createSession(Map<String, dynamic> data) async {
    await _client.from('sessions').insert(data);
  }

  @override
  Future<void> updateSession(String id, Map<String, dynamic> data) async {
    await _client.from('sessions').update(data).eq('id', id);
  }

  @override
  Future<void> deleteSession(String id) async {
    await _client.from('sessions').delete().eq('id', id);
  }
}

/// The signed-in user's schedule (`registrations`). Reads are RLS-scoped to the
/// caller; toggles go through the `register_for_session` RPC, which enforces
/// capacity + no-time-overlap server-side.
class SupabaseScheduleRepository implements ScheduleRepository {
  SupabaseScheduleRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> fetchMySessionIds() async {
    final rows = await _client.from('registrations').select('session_id');
    return rows.map((r) => r['session_id'].toString()).toSet();
  }

  @override
  Future<RegistrationResult> toggle(String sessionId) async {
    final res = await _client.rpc(
      'register_for_session',
      params: {'p_session_id': sessionId},
    );
    final map = (res as Map).cast<String, dynamic>();
    final outcome = switch ((map['outcome'] ?? 'added') as String) {
      'added' => RegistrationOutcome.added,
      'removed' => RegistrationOutcome.removed,
      'full' => RegistrationOutcome.full,
      'conflict' => RegistrationOutcome.conflict,
      _ => RegistrationOutcome.added,
    };
    return RegistrationResult(outcome, map['conflicting_title'] as String?);
  }
}

/// Reads and writes the signed-in user's own `profiles` row (RLS-scoped to
/// `auth.uid()`).
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile?> fetchMine() async {
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

  @override
  Future<void> save(UserProfile profile) async {
    await _client.from('profiles').upsert(profile.toMap());
  }

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('profiles').update(fields).eq('id', user.id);
  }
}

/// Announcements feed + Realtime. Realtime is best-effort: connection errors
/// are swallowed and never reach the UI.
class SupabaseAnnouncementsRepository implements AnnouncementsRepository {
  SupabaseAnnouncementsRepository(this._client);

  final SupabaseClient _client;

  RealtimeChannel? _channel;
  StreamController<AnnouncementEvent>? _controller;

  @override
  Future<List<Announcement>> fetch() async {
    final rows = await _client
        .from('announcements')
        .select()
        .order('pinned', ascending: false)
        .order('created_at', ascending: false);
    return rows.map((r) => Announcement.fromMap(r)).toList();
  }

  @override
  Future<void> create({
    required String title,
    required String body,
    required String author,
    String audience = 'Everyone',
    bool pinned = false,
    String? disciplineId,
  }) async {
    await _client.from('announcements').insert({
      'title': title,
      'body': body,
      'author': author,
      'audience': audience,
      'pinned': pinned,
      'discipline_id': disciplineId,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  @override
  Stream<AnnouncementEvent> get events {
    final existing = _controller;
    if (existing != null) return existing.stream;

    final controller = StreamController<AnnouncementEvent>.broadcast();
    _controller = controller;
    try {
      _channel = _client
          .channel('public:announcements')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'announcements',
            callback: (payload) {
              final row = payload.newRecord;
              controller.add(AnnouncementEvent(
                id: row['id'].toString(),
                title: (row['title'] ?? 'New announcement') as String,
                body: (row['body'] ?? '') as String,
                createdBy: row['created_by']?.toString(),
                disciplineId: row['discipline_id'] as String?,
              ));
            },
          )
          .subscribe((status, error) {
        if (error != null && kDebugMode) {
          debugPrint('Realtime announcements: $status ($error)');
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Realtime subscribe skipped: $e');
    }
    return controller.stream;
  }

  @override
  Future<void> stopEvents() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
    await _controller?.close();
    _controller = null;
  }
}

/// Advisory gated-role eligibility check. RLS only ever returns the caller's own
/// allowlist row; the real guarantee is the server-side enforcement trigger.
class SupabaseAllowlistRepository implements AllowlistRepository {
  SupabaseAllowlistRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> isEligible(SummitRole role) async {
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
