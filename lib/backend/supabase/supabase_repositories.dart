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

/// Create/update/delete sessions. Writes are gated by RLS to admins and
/// volunteers who can edit sessions and are scoped to the session's discipline.
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
  Future<({Set<String> seen, Set<String> opened})> fetchReadState() async {
    if (_client.auth.currentUser == null) {
      return (seen: <String>{}, opened: <String>{});
    }
    try {
      final rows = await _client
          .from('announcement_reads')
          .select('announcement_id, opened_at');
      final seen = <String>{};
      final opened = <String>{};
      for (final r in rows) {
        final id = r['announcement_id'].toString();
        seen.add(id);
        if (r['opened_at'] != null) opened.add(id);
      }
      return (seen: seen, opened: opened);
    } catch (_) {
      // The opened_at column may not exist yet (second migration not run). Fall
      // back to seen-only so the red badge still persists; dots just won't.
      try {
        final rows = await _client
            .from('announcement_reads')
            .select('announcement_id');
        return (
          seen: rows.map((r) => r['announcement_id'].toString()).toSet(),
          opened: <String>{},
        );
      } catch (_) {
        // Reads table not set up at all: treat as none-read.
        return (seen: <String>{}, opened: <String>{});
      }
    }
  }

  @override
  Future<void> markSeen(Iterable<String> ids) async {
    final user = _client.auth.currentUser;
    if (user == null || ids.isEmpty) return;
    final rows = [
      for (final id in ids) {'user_id': user.id, 'announcement_id': id},
    ];
    try {
      // ignoreDuplicates so an already-seen row keeps its opened_at.
      await _client.from('announcement_reads').upsert(
            rows,
            onConflict: 'user_id,announcement_id',
            ignoreDuplicates: true,
          );
    } catch (_) {
      // Best-effort: a missing table / transient error just leaves them unread.
    }
  }

  @override
  Future<void> markOpened(String id) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      // Upsert (update on conflict) so opened_at is set whether or not a "seen"
      // row already exists.
      await _client.from('announcement_reads').upsert(
        {
          'user_id': user.id,
          'announcement_id': id,
          'opened_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,announcement_id',
      );
    } catch (_) {
      // Best-effort: a missing column / transient error just leaves the dot.
    }
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
                targetUserId: row['target_user_id'] as String?,
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

/// The admin-managed rooms catalog. Public read; writes are RLS-gated to admins.
class SupabaseRoomsRepository implements RoomsRepository {
  SupabaseRoomsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Room>> fetchAll() async {
    final rows = await _client
        .from('rooms')
        .select()
        .order('sort_order')
        .order('name');
    return rows.map((r) => Room.fromMap(r)).toList();
  }

  @override
  Future<void> create(Map<String, dynamic> data) async {
    await _client.from('rooms').insert(data);
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    await _client.from('rooms').update(data).eq('id', id);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('rooms').delete().eq('id', id);
  }
}

/// Volunteer↔session assignments. Reads are RLS-scoped; the assign path goes
/// through the `assign_volunteer_to_session` RPC (admin-only, overlap-guarded),
/// and the admin directory/list come from SECURITY DEFINER RPCs.
class SupabaseAssignmentRepository implements AssignmentRepository {
  SupabaseAssignmentRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Set<String>> fetchMyAssignedSessionIds() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await _client
        .from('session_volunteers')
        .select('session_id')
        .eq('user_id', uid);
    return rows.map((r) => r['session_id'].toString()).toSet();
  }

  @override
  Future<List<VolunteerRef>> fetchSessionVolunteers(String sessionId) async {
    final res = await _client.rpc(
      'fetch_session_volunteers',
      params: {'p_session_id': sessionId},
    );
    return (res as List)
        .map((r) => VolunteerRef.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<VolunteerRef>> fetchVolunteers() async {
    final res = await _client.rpc('fetch_volunteers');
    return (res as List)
        .map((r) => VolunteerRef.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<AssignmentResult> assign(String sessionId, String userId,
      {bool confirmRegistered = false}) async {
    final res = await _client.rpc(
      'assign_volunteer_to_session',
      params: {
        'p_session_id': sessionId,
        'p_user_id': userId,
        'p_confirm_registered': confirmRegistered,
      },
    );
    final map = (res as Map).cast<String, dynamic>();
    final outcome = switch ((map['outcome'] ?? 'assigned') as String) {
      'conflict' => AssignmentOutcome.conflict,
      'registered_confirm' => AssignmentOutcome.registeredConfirm,
      _ => AssignmentOutcome.assigned,
    };
    return AssignmentResult(outcome, map['conflicting_title'] as String?);
  }

  @override
  Future<void> unassign(String sessionId, String userId) async {
    // SECURITY DEFINER RPC: deletes the assignment and notifies the volunteer
    // (personal announcement + in-app banner). Admin-only, enforced server-side.
    await _client.rpc('unassign_volunteer_from_session', params: {
      'p_session_id': sessionId,
      'p_user_id': userId,
    });
  }
}

/// Attendance: session rosters + mark, and the front-desk attendee directory +
/// check-in. Every call is a SECURITY DEFINER RPC that enforces the right gate
/// (session assignment, or the front-desk capability) server-side.
class SupabaseAttendanceRepository implements AttendanceRepository {
  SupabaseAttendanceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<RosterEntry>> fetchSessionRoster(String sessionId) async {
    final res = await _client.rpc(
      'fetch_session_roster',
      params: {'p_session_id': sessionId},
    );
    return (res as List)
        .map((r) => RosterEntry.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> markSessionAttendance(
      String sessionId, String userId, bool attended) async {
    await _client.rpc('mark_session_attendance', params: {
      'p_session_id': sessionId,
      'p_user_id': userId,
      'p_attended': attended,
    });
  }

  @override
  Future<List<Attendee>> fetchAttendeeDirectory([String query = '']) async {
    final res = await _client.rpc(
      'fetch_attendee_directory',
      params: {'p_query': query},
    );
    return (res as List)
        .map((r) => Attendee.fromMap((r as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> markSummitCheckin(String attendeeId, bool present) async {
    await _client.rpc('mark_summit_checkin', params: {
      'p_attendee_id': attendeeId,
      'p_present': present,
    });
  }
}
