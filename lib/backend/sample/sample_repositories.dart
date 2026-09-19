import 'dart:async';

import '../../models/models.dart';
import '../../models/user_profile.dart';
import '../auth_service.dart';
import '../repositories.dart';
import 'sample_store.dart';

/// In-memory implementations of the repository interfaces, backed by a shared
/// [SampleStore]. Enforce the same capacity + no-overlap rules the live backend
/// does server-side, so demo mode behaves like the real thing.

class SampleCatalogRepository implements CatalogRepository {
  SampleCatalogRepository(this._store);

  final SampleStore _store;

  @override
  Future<List<Discipline>> fetchAll() async => _store.disciplines;

  @override
  Future<void> createDiscipline(Map<String, dynamic> data) async {
    _store.disciplines.add(Discipline.fromMap(data));
  }
}

class SampleContentRepository implements ContentRepository {
  // Session authoring is a no-op in demo mode; the catalog is read-only sample
  // content. Kept so admin/volunteer UIs don't crash when there's no backend.
  @override
  Future<void> createSession(Map<String, dynamic> data) async {}

  @override
  Future<void> updateSession(String id, Map<String, dynamic> data) async {}

  @override
  Future<void> deleteSession(String id) async {}
}

class SampleScheduleRepository implements ScheduleRepository {
  SampleScheduleRepository(this._store);

  final SampleStore _store;

  @override
  Future<Set<String>> fetchMySessionIds() async => {..._store.mySessionIds};

  @override
  Future<RegistrationResult> toggle(String sessionId) async {
    final session = _store.sessionById(sessionId);
    if (session == null) {
      return const RegistrationResult(RegistrationOutcome.added);
    }
    if (_store.mySessionIds.contains(sessionId)) {
      _store.mySessionIds.remove(sessionId);
      return const RegistrationResult(RegistrationOutcome.removed);
    }
    if (session.isFull) {
      return const RegistrationResult(RegistrationOutcome.full);
    }
    for (final id in _store.mySessionIds) {
      final other = _store.sessionById(id);
      if (other != null && other.overlaps(session)) {
        return RegistrationResult(RegistrationOutcome.conflict, other.title);
      }
    }
    _store.mySessionIds.add(sessionId);
    return const RegistrationResult(RegistrationOutcome.added);
  }
}

class SampleProfileRepository implements ProfileRepository {
  SampleProfileRepository(this._store);

  final SampleStore _store;

  @override
  Future<UserProfile?> fetchMine() async => _store.profile;

  @override
  Future<void> save(UserProfile profile) async {
    _store.profile = profile;
  }

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    final p = _store.profile;
    if (p == null) return;
    if (fields.containsKey('notifications_enabled')) {
      p.notificationsEnabled = fields['notifications_enabled'] as bool;
    }
    if (fields.containsKey('volunteer_hours')) {
      p.volunteerHours = (fields['volunteer_hours'] as num).toDouble();
    }
  }
}

class SampleAnnouncementsRepository implements AnnouncementsRepository {
  SampleAnnouncementsRepository(this._store);

  final SampleStore _store;

  @override
  Future<List<Announcement>> fetch() async => _store.announcements;

  @override
  Future<void> create({
    required String title,
    required String body,
    required String author,
    String audience = 'Everyone',
    bool pinned = false,
    String? disciplineId,
  }) async {
    _store.announcements.insert(
      0,
      Announcement(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        body: body,
        author: author,
        audience: audience,
        timeAgo: 'just now',
        pinned: pinned,
        disciplineId: disciplineId,
      ),
    );
  }

  @override
  Future<({Set<String> seen, Set<String> opened})> fetchReadState() async => (
        seen: {..._store.seenAnnouncementIds},
        opened: {..._store.openedAnnouncementIds},
      );

  @override
  Future<void> markSeen(Iterable<String> ids) async =>
      _store.seenAnnouncementIds.addAll(ids);

  @override
  Future<void> markOpened(String id) async {
    _store.seenAnnouncementIds.add(id);
    _store.openedAnnouncementIds.add(id);
  }

  // No realtime in demo mode: a stream that never emits. The feed still works
  // via fetch() + pull-to-refresh.
  @override
  Stream<AnnouncementEvent> get events => const Stream.empty();

  @override
  Future<void> stopEvents() async {}
}

class SampleAllowlistRepository implements AllowlistRepository {
  // Gated roles never appear in demo mode (no auth gate), so nobody is eligible.
  @override
  Future<bool> isEligible(SummitRole role) async => false;
}

/// In-memory rooms catalog (seeded from the sample sessions' rooms).
class SampleRoomsRepository implements RoomsRepository {
  SampleRoomsRepository(this._store);

  final SampleStore _store;

  @override
  Future<List<Room>> fetchAll() async {
    final list = [..._store.rooms]
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return list;
  }

  @override
  Future<void> create(Map<String, dynamic> data) async {
    _store.rooms.add(Room(
      id: 'room-${DateTime.now().microsecondsSinceEpoch}',
      name: (data['name'] ?? '') as String,
      sortOrder: (data['sort_order'] as num?)?.toInt() ?? 0,
    ));
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    final i = _store.rooms.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final old = _store.rooms[i];
    _store.rooms[i] = Room(
      id: old.id,
      name: (data['name'] ?? old.name) as String,
      sortOrder: (data['sort_order'] as num?)?.toInt() ?? old.sortOrder,
    );
  }

  @override
  Future<void> delete(String id) async {
    _store.rooms.removeWhere((r) => r.id == id);
  }
}

/// In-memory volunteer↔session assignments, replicating the server overlap
/// guard: an assignment is refused if the target session's time overlaps any of
/// that volunteer's other assignments OR the demo user's personal registrations.
class SampleAssignmentRepository implements AssignmentRepository {
  SampleAssignmentRepository(this._store);

  final SampleStore _store;

  @override
  Future<Set<String>> fetchMyAssignedSessionIds() async =>
      {..._store.myAssignedSessionIds};

  @override
  Future<List<VolunteerRef>> fetchSessionVolunteers(String sessionId) async =>
      [...?_store.sessionVolunteers[sessionId]];

  @override
  Future<List<VolunteerRef>> fetchVolunteers() async => [..._store.volunteers];

  @override
  Future<AssignmentResult> assign(String sessionId, String userId,
      {bool confirmRegistered = false}) async {
    final target = _store.sessionById(sessionId);
    if (target == null) {
      return const AssignmentResult(AssignmentOutcome.assigned);
    }
    final existing = _store.assignmentsByUser[userId] ?? <String>{};
    if (existing.contains(sessionId)) {
      return const AssignmentResult(AssignmentOutcome.assigned);
    }
    // Overlap against the volunteer's other assignments + demo registrations
    // (excluding this session — registering for it is not a conflict).
    final commitments = {...existing, ..._store.mySessionIds};
    for (final id in commitments) {
      if (id == sessionId) continue;
      final other = _store.sessionById(id);
      if (other != null && other.overlaps(target)) {
        return AssignmentResult(AssignmentOutcome.conflict, other.title);
      }
    }
    // Registered for this very session → confirm first.
    if (!confirmRegistered && _store.mySessionIds.contains(sessionId)) {
      return const AssignmentResult(AssignmentOutcome.registeredConfirm);
    }
    (_store.assignmentsByUser[userId] ??= <String>{}).add(sessionId);
    final vols = _store.sessionVolunteers[sessionId] ??= <VolunteerRef>[];
    final ref = _store.volunteers.where((v) => v.id == userId);
    vols.add(ref.isNotEmpty
        ? ref.first
        : VolunteerRef(id: userId, name: userId, email: ''));
    return const AssignmentResult(AssignmentOutcome.assigned);
  }

  @override
  Future<void> unassign(String sessionId, String userId) async {
    _store.assignmentsByUser[userId]?.remove(sessionId);
    _store.sessionVolunteers[sessionId]?.removeWhere((v) => v.id == userId);
  }
}

/// In-memory attendance: per-session rosters and the front-desk directory.
class SampleAttendanceRepository implements AttendanceRepository {
  SampleAttendanceRepository(this._store);

  final SampleStore _store;

  @override
  Future<List<RosterEntry>> fetchSessionRoster(String sessionId) async =>
      [...?_store.rosters[sessionId]];

  @override
  Future<void> markSessionAttendance(
      String sessionId, String userId, bool attended) async {
    final roster = _store.rosters[sessionId];
    if (roster == null) return;
    final i = roster.indexWhere((e) => e.userId == userId);
    if (i >= 0) roster[i] = roster[i].copyWith(attended: attended);
  }

  @override
  Future<List<Attendee>> fetchAttendeeDirectory([String query = '']) async {
    final q = query.trim().toLowerCase();
    return [
      for (final a in _store.attendees)
        if (q.isEmpty ||
            a.name.toLowerCase().contains(q) ||
            a.email.toLowerCase().contains(q))
          a,
    ];
  }

  @override
  Future<void> markSummitCheckin(String attendeeId, bool present) async {
    final i = _store.attendees.indexWhere((a) => a.id == attendeeId);
    if (i >= 0) _store.attendees[i] = _store.attendees[i].copyWith(present: present);
  }
}

/// No-account auth for demo mode: nobody is ever signed in, and the OTP calls
/// are unreachable because the auth gate isn't shown without a live backend.
class SampleAuthService implements AuthService {
  @override
  Stream<void> get authStateChanges => const Stream.empty();

  @override
  AuthUser? get currentUser => null;

  @override
  bool get isSignedIn => false;

  @override
  Future<void> sendEmailOtp(String email) async {
    throw const AuthFailure('Sign-in is unavailable in demo mode.');
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {
    throw const AuthFailure('Sign-in is unavailable in demo mode.');
  }

  @override
  Future<bool> tryDevLogin(String email) async => false;

  @override
  bool get supportsGoogleSignIn => false;

  @override
  Future<void> signInWithGoogle() async {
    throw const AuthFailure('Sign-in is unavailable in demo mode.');
  }

  @override
  Future<void> signOut() async {}
}
