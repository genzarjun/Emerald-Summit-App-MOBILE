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
        await _client.from('disciplines').select().order('sort_order', ascending: true);

    final sessRows = await _client
        .from('sessions_with_counts')
        .select()
        .order('start_time', ascending: true);

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

/// Create/update/delete sessions. Creates and edits are gated by RLS to admins
/// and volunteers who can edit sessions and are scoped to the session's
/// discipline; deletes are admin-only.
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

  @override
  Future<int> previewTimeConflicts(
      String sessionId, String start, String end) async {
    try {
      final res = await _client.rpc('session_time_conflicts', params: {
        'p_session_id': sessionId,
        'p_start': start,
        'p_end': end,
      });
      return (res as List).length;
    } catch (_) {
      // RPC not deployed yet / transient — don't block the save over a warning.
      return 0;
    }
  }

  @override
  Future<void> notifyTimeConflicts(String sessionId) async {
    await _client.rpc('notify_session_time_conflicts', params: {
      'p_session_id': sessionId,
    });
  }
}

/// The signed-in user's schedule (`registrations`). Reads are RLS-scoped to the
/// caller; toggles go through the `register_for_session` RPC, which enforces
/// capacity + no-time-overlap server-side.
class SupabaseScheduleRepository implements ScheduleRepository {
  SupabaseScheduleRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, ParticipationType>> fetchMyRegistrations() async {
    final rows = await _client
        .from('registrations')
        .select('session_id, participation_type');
    return {
      for (final r in rows)
        r['session_id'].toString():
            ParticipationTypeX.fromId(r['participation_type'] as String?),
    };
  }

  @override
  Future<RegistrationResult> toggle(
    String sessionId, {
    ParticipationType type = ParticipationType.participant,
    Map<String, String> answers = const {},
    ProjectChoice? project,
    String? newOwnerId,
  }) async {
    final Object? res;
    try {
      res = await _client.rpc(
        'register_for_session',
        params: {
          'p_session_id': sessionId,
          'p_participation_type': type.id,
          'p_answers': answers,
          'p_project_mode': project?.modeId,
          'p_project_name': project?.projectName,
          'p_team_code': project?.teamCode,
          // Only sent when set, so the call also matches the pre-ownership
          // signature of the RPC (teams_setup.sql).
          'p_new_owner_id': ?newOwnerId,
        },
      );
    } on PostgrestException catch (e) {
      // A removed member trying to rejoin is refused by a database trigger.
      if (e.message.contains('removed_from_team')) {
        return RegistrationResult.invalidProject(
            projectProblemMessage('removed_from_team')!);
      }
      rethrow;
    }
    final map = (res as Map).cast<String, dynamic>();
    final raw = (map['outcome'] ?? 'added') as String;
    final problem = projectProblemMessage(raw);
    if (problem != null) return RegistrationResult.invalidProject(problem);
    return switch (raw) {
      'removed' => const RegistrationResult(RegistrationOutcome.removed),
      'full' => const RegistrationResult(RegistrationOutcome.full),
      'participation_closed' =>
        const RegistrationResult(RegistrationOutcome.participationClosed),
      'conflict' => RegistrationResult(
          RegistrationOutcome.conflict, map['conflicting_title'] as String?),
      _ => RegistrationResult.added(teamCode: map['team_code'] as String?),
    };
  }

  @override
  Future<Map<String, String>> fetchMyAnswers(String sessionId) async {
    final row = await _client
        .from('registrations')
        .select('answers')
        .eq('session_id', sessionId)
        .maybeSingle();
    return RosterEntry.parseAnswers(row?['answers']);
  }

  @override
  Future<MyProject?> fetchMyProject(String sessionId) async {
    final res = await _client.rpc(
      'fetch_my_project',
      params: {'p_session_id': sessionId},
    );
    return MyProject.fromMap((res as Map?)?.cast<String, dynamic>());
  }

  @override
  Future<TeamLookup> findTeam(String sessionId, String code) async {
    final res = await _client.rpc(
      'find_team',
      params: {'p_session_id': sessionId, 'p_code': code},
    );
    final map = (res as Map).cast<String, dynamic>();
    return switch (map['outcome']) {
      'found' || 'full' => TeamLookup(
          map['outcome'] == 'full'
              ? TeamLookupOutcome.full
              : TeamLookupOutcome.found,
          projectName: map['project_name'] as String?,
          memberCount: (map['member_count'] as num?)?.toInt() ?? 0,
          maxTeamSize: (map['max_team_size'] as num?)?.toInt() ??
              kDefaultMaxTeamSize,
        ),
      'teams_not_allowed' =>
        const TeamLookup(TeamLookupOutcome.teamsNotAllowed),
      'removed' => TeamLookup(
          TeamLookupOutcome.removed,
          projectName: map['project_name'] as String?,
        ),
      'wrong_session' => TeamLookup(
          TeamLookupOutcome.wrongSession,
          sessionTitle: map['session_title'] as String?,
        ),
      _ => const TeamLookup(TeamLookupOutcome.notFound),
    };
  }

  @override
  Future<MyProject> updateMyRegistration(
    String sessionId, {
    required Map<String, String> answers,
    required ProjectChoice project,
    String? newOwnerId,
  }) async {
    final Object? res;
    try {
      res = await _client.rpc(
        'update_my_registration',
        params: {
          'p_session_id': sessionId,
          'p_answers': answers,
          'p_project_mode': project.modeId,
          'p_project_name': project.projectName,
          'p_team_code': project.teamCode,
          'p_new_owner_id': ?newOwnerId,
        },
      );
    } on PostgrestException catch (e) {
      if (e.message.contains('removed_from_team')) {
        throw TeamCodeException(projectProblemMessage('removed_from_team')!);
      }
      rethrow;
    }
    final map = (res as Map).cast<String, dynamic>();
    final outcome = map['outcome'] as String?;
    final problem = projectProblemMessage(outcome);
    if (problem != null) throw TeamCodeException(problem);
    if (outcome != 'updated') {
      throw StateError("You're not registered as a participant here.");
    }
    // Re-read so a team edit comes back with its full member list.
    return await fetchMyProject(sessionId) ??
        MyProject(
          isTeam: map['team_code'] != null,
          projectName: (map['project_name'] ?? '') as String,
          teamCode: map['team_code'] as String?,
        );
  }

  @override
  Future<void> transferTeamOwnership(
      String sessionId, String newOwnerId) async {
    final res = await _client.rpc(
      'transfer_team_ownership',
      params: {'p_session_id': sessionId, 'p_new_owner_id': newOwnerId},
    );
    final outcome = (res as Map?)?['outcome'];
    if (outcome == 'transferred') return;
    throw TeamCodeException(projectProblemMessage(outcome as String?) ??
        "Only the team's owner can hand it over.");
  }

  @override
  Future<void> removeTeamMember(String sessionId, String userId) async {
    final res = await _client.rpc(
      'remove_team_member',
      params: {'p_session_id': sessionId, 'p_user_id': userId},
    );
    switch ((res as Map?)?['outcome']) {
      case 'removed':
        return;
      case 'not_member':
        throw const TeamCodeException("That person isn't on your team anymore.");
      case 'cannot_remove_self':
        throw const TeamCodeException(
            'To leave your own team, use "Leave team / go solo".');
      default:
        throw const TeamCodeException(
            "Only the team's owner can remove members.");
    }
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
  Future<Set<String>> fetchDismissed() async {
    if (_client.auth.currentUser == null) return <String>{};
    try {
      final rows = await _client
          .from('announcement_dismissals')
          .select('announcement_id');
      return rows.map((r) => r['announcement_id'].toString()).toSet();
    } catch (_) {
      // Dismissals table not set up (migration not run) → nothing hidden.
      return <String>{};
    }
  }

  @override
  Future<void> hideForMe(String id) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('announcement_dismissals').upsert(
        {'user_id': user.id, 'announcement_id': id},
        onConflict: 'user_id,announcement_id',
        ignoreDuplicates: true,
      );
    } catch (_) {
      // Best-effort: a missing table / transient error just leaves it visible.
    }
  }

  @override
  Future<void> unhideForMe(String id) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client
          .from('announcement_dismissals')
          .delete()
          .eq('user_id', user.id)
          .eq('announcement_id', id);
    } catch (_) {
      // Best-effort: a transient error just leaves it hidden until next sync.
    }
  }

  @override
  Future<void> deleteForEveryone(String id) async {
    // Admin-only, enforced by the DELETE RLS policy — a non-admin call is
    // rejected server-side. Let errors surface so the UI can report them.
    await _client.from('announcements').delete().eq('id', id);
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
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'announcements',
            callback: (payload) {
              // A delete-for-everyone: drop it from every open feed. Default
              // replica identity gives us the primary key in oldRecord, which is
              // all the app needs to remove the row.
              final id = payload.oldRecord['id'];
              if (id == null) return;
              controller.add(AnnouncementEvent(
                id: id.toString(),
                title: '',
                body: '',
                deleted: true,
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

/// Lists every image in a public storage [bucket] and resolves each to a public
/// CDN URL. The bucket IS the source of truth — no curation table — so photos
/// are managed purely by uploading/deleting files. Best-effort: any error
/// (missing bucket, offline) yields an empty list so the caller just shows
/// nothing. Listing requires a public SELECT policy on storage.objects for the
/// bucket (see gallery_setup.sql).
class SupabaseGalleryRepository implements GalleryRepository {
  SupabaseGalleryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<GalleryPhoto>> fetchPhotos(String bucket) async {
    try {
      final store = _client.storage.from(bucket);
      final objects = await store.list();
      final photos = <GalleryPhoto>[];
      for (final o in objects) {
        // Skip subfolders (null id) and the hidden .emptyFolderPlaceholder /
        // any dotfile Supabase keeps for empty prefixes.
        if (o.id == null || o.name.startsWith('.')) continue;
        photos.add(GalleryPhoto(
          id: o.name,
          imageUrl: store.getPublicUrl(o.name),
        ));
      }
      return photos;
    } catch (_) {
      return const [];
    }
  }
}

/// Session photos, stored one folder per session in the `session_photos`
/// bucket. Public read/list; writes are gated server-side (Storage RLS) to
/// admins and the session's discipline editors.
class SupabaseSessionMediaRepository implements SessionMediaRepository {
  SupabaseSessionMediaRepository(this._client);

  final SupabaseClient _client;

  static const String _bucket = 'session_photos';

  @override
  Future<List<GalleryPhoto>> fetchPhotos(String sessionId) async {
    try {
      final store = _client.storage.from(_bucket);
      final objects = await store.list(path: sessionId);
      final photos = <GalleryPhoto>[];
      for (final o in objects) {
        // Skip subfolders (null id) and Supabase's empty-folder placeholder.
        if (o.id == null || o.name.startsWith('.')) continue;
        photos.add(GalleryPhoto(
          id: o.name,
          imageUrl: store.getPublicUrl('$sessionId/${o.name}'),
        ));
      }
      return photos;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<GalleryPhoto> uploadPhoto(
      String sessionId, Uint8List bytes, String fileName) async {
    final store = _client.storage.from(_bucket);
    final path = '$sessionId/$fileName';
    await store.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: _contentTypeFor(fileName),
      ),
    );
    return GalleryPhoto(id: fileName, imageUrl: store.getPublicUrl(path));
  }

  @override
  Future<void> deletePhoto(String sessionId, String fileName) async {
    await _client.storage.from(_bucket).remove(['$sessionId/$fileName']);
  }

  static String _contentTypeFor(String fileName) {
    final f = fileName.toLowerCase();
    if (f.endsWith('.png')) return 'image/png';
    if (f.endsWith('.webp')) return 'image/webp';
    if (f.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
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
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
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

  @override
  Future<AssignmentResult> setManage(String sessionId, bool manage) async {
    // Admin self-manage: overlap-guarded self add/remove into session_volunteers.
    final res = await _client.rpc('set_session_manage', params: {
      'p_session_id': sessionId,
      'p_manage': manage,
    });
    final map = (res as Map).cast<String, dynamic>();
    final outcome = switch ((map['outcome'] ?? 'managing') as String) {
      'conflict' => AssignmentOutcome.conflict,
      _ => AssignmentOutcome.assigned,
    };
    return AssignmentResult(outcome, map['conflicting_title'] as String?);
  }
}

/// Attendance: session rosters + mark, and the front-desk attendee directory +
/// check-in. Every call is a SECURITY DEFINER RPC that enforces the right gate
/// (session assignment / discipline editor, or the front-desk capability)
/// server-side.
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
