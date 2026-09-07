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
  // content. Kept so admin/mentor UIs don't crash when there's no backend.
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
  Future<void> signOut() async {}
}
