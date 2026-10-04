import 'dart:async';
import 'dart:typed_data';

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

  // No live registrations to clash with in demo mode.
  @override
  Future<int> previewTimeConflicts(
          String sessionId, String start, String end) async =>
      0;

  @override
  Future<void> notifyTimeConflicts(String sessionId) async {}
}

class SampleScheduleRepository implements ScheduleRepository {
  SampleScheduleRepository(this._store);

  final SampleStore _store;

  @override
  Future<Map<String, ParticipationType>> fetchMyRegistrations() async =>
      {..._store.myRegistrations};

  @override
  Future<RegistrationResult> toggle(
    String sessionId, {
    ParticipationType type = ParticipationType.participant,
    Map<String, String> answers = const {},
    ProjectChoice? project,
    String? newOwnerId,
  }) async {
    final session = _store.sessionById(sessionId);
    if (session == null) {
      return const RegistrationResult.added();
    }
    if (_store.myRegistrations.containsKey(sessionId)) {
      try {
        _leaveTeam(_myEntry(sessionId)?.teamId, newOwnerId);
      } on TeamCodeException catch (e) {
        return RegistrationResult.invalidProject(e.message);
      }
      _store.myRegistrations.remove(sessionId);
      _store.rosters[sessionId]
          ?.removeWhere((e) => e.userId == _demoUserId);
      return const RegistrationResult(RegistrationOutcome.removed);
    }
    if (session.isFull) {
      return const RegistrationResult(RegistrationOutcome.full);
    }
    for (final id in _store.myRegistrations.keys) {
      final other = _store.sessionById(id);
      if (other != null && other.overlaps(session)) {
        return RegistrationResult(RegistrationOutcome.conflict, other.title);
      }
    }
    final RosterEntry entry;
    try {
      entry = _entryFor(
        session,
        type: type,
        answers: answers,
        project: type == ParticipationType.participant ? project : null,
      );
    } on TeamCodeException catch (e) {
      return RegistrationResult.invalidProject(e.message);
    }
    _store.myRegistrations[sessionId] = type;
    // Reflect the join on the demo roster so the Participants tab shows it.
    (_store.rosters[sessionId] ??= []).add(entry);
    return RegistrationResult.added(
      teamCode: project?.action == ProjectAction.createTeam
          ? entry.teamCode
          : null,
    );
  }

  @override
  Future<Map<String, String>> fetchMyAnswers(String sessionId) async =>
      {...?_myEntry(sessionId)?.answers};

  @override
  Future<MyProject?> fetchMyProject(String sessionId) async {
    final e = _myEntry(sessionId);
    if (e == null || e.isTeam == null) return null;
    final max = _store.sessionById(sessionId)?.maxTeamSize ??
        kDefaultMaxTeamSize;
    final team = _teamById(e.teamId);
    if (team == null) {
      return MyProject(
          isTeam: false, projectName: e.projectName ?? '', maxTeamSize: max);
    }
    return MyProject(
      isTeam: true,
      projectName: team.projectName,
      teamCode: team.code,
      isOwner: team.ownerId == _demoUserId,
      maxTeamSize: max,
      members: [
        for (final m in team.members.entries)
          TeamMember(id: m.key, name: m.value, isOwner: m.key == team.ownerId),
      ],
    );
  }

  @override
  Future<TeamLookup> findTeam(String sessionId, String code) async {
    final team = _store.teams[normalizeTeamCode(code)];
    if (team == null) return const TeamLookup(TeamLookupOutcome.notFound);
    if (team.sessionId != sessionId) {
      return TeamLookup(
        TeamLookupOutcome.wrongSession,
        sessionTitle: _store.sessionById(team.sessionId)?.title,
      );
    }
    final max = _store.sessionById(sessionId)?.maxTeamSize ??
        kDefaultMaxTeamSize;
    return TeamLookup(
      team.members.length >= max
          ? TeamLookupOutcome.full
          : TeamLookupOutcome.found,
      projectName: team.projectName,
      memberCount: team.members.length,
      maxTeamSize: max,
    );
  }

  @override
  Future<MyProject> updateMyRegistration(
    String sessionId, {
    required Map<String, String> answers,
    required ProjectChoice project,
    String? newOwnerId,
  }) async {
    final roster = _store.rosters[sessionId];
    final i = roster?.indexWhere((e) => e.userId == _demoUserId) ?? -1;
    final session = _store.sessionById(sessionId);
    if (roster == null || i < 0 || session == null ||
        roster[i].participationType != ParticipationType.participant) {
      throw StateError("You're not registered as a participant here.");
    }
    final current = roster[i];
    final rejoining = project.action == ProjectAction.joinTeam &&
        normalizeTeamCode(project.teamCode ?? '') == current.teamCode;
    if (project.action == ProjectAction.stayOnTeam || rejoining) {
      final team = _teamById(current.teamId);
      if (team == null) {
        throw const TeamCodeException("That team doesn't exist anymore.");
      }
      final name = rejoining ? '' : project.projectName?.trim() ?? '';
      if (name.isNotEmpty) team.projectName = name;
      roster[i] = _withTeam(current, team, answers);
    } else {
      // Validate the destination before leaving the old team so a bad code
      // (or a missing new owner) changes nothing.
      _entryFor(session,
          type: ParticipationType.participant,
          answers: answers,
          project: project,
          dryRun: true);
      _leaveTeam(current.teamId, newOwnerId);
      roster[i] = _entryFor(session,
          type: ParticipationType.participant,
          answers: answers,
          project: project,
          attended: current.attended);
    }
    return (await fetchMyProject(sessionId))!;
  }

  @override
  Future<void> transferTeamOwnership(
      String sessionId, String newOwnerId) async {
    final team = _teamById(_myEntry(sessionId)?.teamId);
    if (team == null || team.ownerId != _demoUserId) {
      throw const TeamCodeException("Only the team's owner can hand it over.");
    }
    if (newOwnerId == _demoUserId || !team.members.containsKey(newOwnerId)) {
      throw const TeamCodeException(
          "That person isn't on your team anymore. Pick someone else.");
    }
    team.ownerId = newOwnerId;
  }

  RosterEntry? _myEntry(String sessionId) {
    for (final e in _store.rosters[sessionId] ?? const <RosterEntry>[]) {
      if (e.userId == _demoUserId) return e;
    }
    return null;
  }

  SampleTeam? _teamById(String? id) {
    if (id == null) return null;
    for (final t in _store.teams.values) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Takes the demo user off [teamId]. Mirrors teams_ownership_setup.sql: an
  /// owner with teammates must name [newOwnerId]; an emptied team is deleted.
  void _leaveTeam(String? teamId, String? newOwnerId) {
    final team = _teamById(teamId);
    if (team == null) return;
    final others = team.members.keys.where((id) => id != _demoUserId);
    if (team.ownerId == _demoUserId && others.isNotEmpty) {
      if (newOwnerId == null) {
        throw const TeamCodeException(
            'You own this team. Choose a teammate to take over before you '
            'leave.');
      }
      if (!others.contains(newOwnerId)) {
        throw const TeamCodeException(
            "That person isn't on your team anymore. Pick someone else.");
      }
      team.ownerId = newOwnerId;
    }
    team.members.remove(_demoUserId);
    if (team.members.isEmpty) _store.teams.remove(team.code);
  }

  /// Builds the demo user's roster entry for [project], creating or joining a
  /// team as needed (unless [dryRun]). Throws [TeamCodeException] for an
  /// unusable project answer.
  RosterEntry _entryFor(
    Session session, {
    required ParticipationType type,
    required Map<String, String> answers,
    ProjectChoice? project,
    bool attended = false,
    bool dryRun = false,
  }) {
    final base = RosterEntry(
      userId: _demoUserId,
      name: _store.profile?.fullName.isNotEmpty == true
          ? _store.profile!.fullName
          : 'You',
      email: _store.profile?.email ?? '',
      attended: attended,
      participationType: type,
      answers: answers,
    );
    if (project == null) return base;
    final name = project.projectName?.trim() ?? '';
    switch (project.action) {
      case ProjectAction.solo:
        if (name.isEmpty) {
          throw const TeamCodeException('Please enter your project name.');
        }
        return RosterEntry(
          userId: base.userId,
          name: base.name,
          email: base.email,
          attended: attended,
          participationType: type,
          answers: answers,
          isTeam: false,
          projectName: name,
        );
      case ProjectAction.createTeam:
        if (name.isEmpty) {
          throw const TeamCodeException('Please enter your project name.');
        }
        if (dryRun) return base;
        final prefix =
            teamCodePrefix(session.disciplineId, session.disciplineName);
        var n = 1000 + _store.teams.length;
        while (_store.teams.containsKey('$prefix$n')) {
          n++;
        }
        final team = SampleTeam(
          id: 'team-$prefix$n',
          sessionId: session.id,
          code: '$prefix$n',
          projectName: name,
          ownerId: _demoUserId,
        );
        _store.teams[team.code] = team;
        return _withTeam(base, team, answers);
      case ProjectAction.joinTeam:
        final team = _store.teams[normalizeTeamCode(project.teamCode ?? '')];
        if (team == null) {
          throw const TeamCodeException(
              "We couldn't find a team with that code.");
        }
        if (team.sessionId != session.id) {
          throw const TeamCodeException(
              'That team code is for a different session.');
        }
        if (!team.members.containsKey(_demoUserId) &&
            team.members.length >= session.maxTeamSize) {
          throw const TeamCodeException('That team is already full.');
        }
        if (dryRun) return base;
        return _withTeam(base, team, answers);
      case ProjectAction.stayOnTeam:
        throw const TeamCodeException("You're not on a team yet.");
    }
  }

  RosterEntry _withTeam(
      RosterEntry e, SampleTeam team, Map<String, String> answers) {
    team.members.putIfAbsent(e.userId, () => e.name);
    return RosterEntry(
      userId: e.userId,
      name: e.name,
      email: e.email,
      attended: e.attended,
      participationType: e.participationType,
      answers: answers,
      isTeam: true,
      projectName: team.projectName,
      teamId: team.id,
      teamCode: team.code,
      isTeamOwner: team.ownerId == e.userId,
    );
  }

  /// Stable id for the demo user's own roster entry in sample mode.
  static const String _demoUserId = 'demo-user';
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

  @override
  Future<Set<String>> fetchDismissed() async =>
      {..._store.dismissedAnnouncementIds};

  @override
  Future<void> hideForMe(String id) async =>
      _store.dismissedAnnouncementIds.add(id);

  @override
  Future<void> unhideForMe(String id) async =>
      _store.dismissedAnnouncementIds.remove(id);

  @override
  Future<void> deleteForEveryone(String id) async =>
      _store.announcements.removeWhere((a) => a.id == id);

  // No realtime in demo mode: a stream that never emits. The feed still works
  // via fetch() + pull-to-refresh.
  @override
  Stream<AnnouncementEvent> get events => const Stream.empty();

  @override
  Future<void> stopEvents() async {}
}

class SampleGalleryRepository implements GalleryRepository {
  SampleGalleryRepository(this._store);

  final SampleStore _store;

  // Demo mode ignores the bucket name and returns the seeded sample photos.
  @override
  Future<List<GalleryPhoto>> fetchPhotos(String bucket) async =>
      _store.galleryPhotos;
}

class SampleSessionMediaRepository implements SessionMediaRepository {
  // In-memory per-session photos, so the editor's add/remove works in demo mode
  // (bytes are discarded; a data-free placeholder URL stands in for the upload).
  final Map<String, List<GalleryPhoto>> _bySession = {};

  @override
  Future<List<GalleryPhoto>> fetchPhotos(String sessionId) async =>
      [...?_bySession[sessionId]];

  @override
  Future<GalleryPhoto> uploadPhoto(
      String sessionId, Uint8List bytes, String fileName) async {
    final photo = GalleryPhoto(
      id: fileName,
      imageUrl: 'https://picsum.photos/seed/$sessionId-$fileName/1200/675',
    );
    (_bySession[sessionId] ??= []).add(photo);
    return photo;
  }

  @override
  Future<void> deletePhoto(String sessionId, String fileName) async {
    _bySession[sessionId]?.removeWhere((p) => p.id == fileName);
  }
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

  @override
  Future<AssignmentResult> setManage(String sessionId, bool manage) async {
    if (!manage) {
      _store.myAssignedSessionIds.remove(sessionId);
      return const AssignmentResult(AssignmentOutcome.assigned);
    }
    final target = _store.sessionById(sessionId);
    if (target == null) {
      return const AssignmentResult(AssignmentOutcome.assigned);
    }
    // Overlap against everything already on the demo user's schedule
    // (registrations + other managed sessions), excluding this session.
    final commitments = {
      ..._store.myRegistrations.keys,
      ..._store.myAssignedSessionIds,
    };
    for (final id in commitments) {
      if (id == sessionId) continue;
      final other = _store.sessionById(id);
      if (other != null && other.overlaps(target)) {
        return AssignmentResult(AssignmentOutcome.conflict, other.title);
      }
    }
    _store.myAssignedSessionIds.add(sessionId);
    return const AssignmentResult(AssignmentOutcome.assigned);
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
