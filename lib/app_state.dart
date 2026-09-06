import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_navigation.dart';
import 'backend/backend.dart';
import 'backend/service_locator.dart';
import 'models/models.dart';
import 'models/user_profile.dart';
import 'widgets/in_app_banner.dart';

/// Result of trying to add a session to the day plan (app/UI-facing).
enum AddOutcome { added, removed, conflict, full }

class AddResult {
  const AddResult(this.outcome, [this.conflictingTitle]);
  final AddOutcome outcome;
  final String? conflictingTitle;
}

/// App-wide state. Talks ONLY to the backend seam (`backend/`) — it has no
/// knowledge of which backend is active. Catalog, schedule, profile, and
/// announcements all flow through the repository interfaces; the sample backend
/// stands in when nothing is configured, so the UI skeleton still runs
/// standalone.
class AppState extends ChangeNotifier {
  // ---- Catalog -------------------------------------------------------------
  List<Discipline> _disciplines = const [];
  bool catalogLoading = false;
  Object? catalogError;

  List<Discipline> get disciplines => _disciplines;

  /// Flattened list of every session across all disciplines.
  List<Session> get allSessions =>
      [for (final d in _disciplines) ...d.sessions];

  /// Loads the catalog. Safe to call repeatedly; used on startup and by
  /// pull-to-refresh.
  Future<void> loadCatalog() async {
    catalogLoading = true;
    catalogError = null;
    notifyListeners();
    try {
      _disciplines = await catalogRepository.fetchAll();
    } catch (e) {
      catalogError = e;
    } finally {
      catalogLoading = false;
      notifyListeners();
    }
  }

  /// Re-fetches the catalog WITHOUT flipping the loading flag, so enrolled
  /// counts refresh after a registration change without flashing a spinner.
  Future<void> _refreshCatalogSilently() async {
    try {
      _disciplines = await catalogRepository.fetchAll();
    } catch (_) {
      // Keep the last-known catalog; the counts just stay briefly stale.
    }
  }

  // ---- Schedule ------------------------------------------------------------
  final Set<String> _mySessionIds = {};

  List<Session> get mySessions {
    final list = allSessions
        .where((s) => _mySessionIds.contains(s.id))
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return list;
  }

  bool isRegistered(String id) => _mySessionIds.contains(id);

  /// Loads the user's registrations into the local cache the UI reads.
  Future<void> loadSchedule() async {
    try {
      final ids = await scheduleRepository.fetchMySessionIds();
      _mySessionIds
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {
      // Leave the schedule empty on failure; the user can retry by reopening.
    }
  }

  /// Toggles a session in the plan. The repository is the trusted enforcer of
  /// capacity + no-overlap (server-side for a live backend, in-memory for the
  /// sample one); this just mirrors the outcome into the UI cache.
  Future<AddResult> toggle(Session session) async {
    final res = await scheduleRepository.toggle(session.id);
    switch (res.outcome) {
      case RegistrationOutcome.added:
        _mySessionIds.add(session.id);
        await _refreshCatalogSilently();
        notifyListeners();
      case RegistrationOutcome.removed:
        _mySessionIds.remove(session.id);
        await _refreshCatalogSilently();
        notifyListeners();
      case RegistrationOutcome.full:
      case RegistrationOutcome.conflict:
        break; // nothing changed
    }
    return AddResult(_toAddOutcome(res.outcome), res.conflictingTitle);
  }

  static AddOutcome _toAddOutcome(RegistrationOutcome o) => switch (o) {
        RegistrationOutcome.added => AddOutcome.added,
        RegistrationOutcome.removed => AddOutcome.removed,
        RegistrationOutcome.full => AddOutcome.full,
        RegistrationOutcome.conflict => AddOutcome.conflict,
      };

  // ---- Content management (mentors/admins) ---------------------------------
  /// Creates or updates a session, then refreshes the catalog. The backend
  /// enforces that the caller may manage [data]'s discipline.
  Future<void> saveSession({String? id, required Map<String, dynamic> data}) async {
    if (id == null) {
      await contentRepository.createSession(data);
    } else {
      await contentRepository.updateSession(id, data);
    }
    await loadCatalog();
  }

  Future<void> deleteSession(String id) async {
    await contentRepository.deleteSession(id);
    await loadCatalog();
  }

  /// Creates a discipline (admin only), then refreshes the catalog.
  Future<void> createDiscipline(Map<String, dynamic> data) async {
    await catalogRepository.createDiscipline(data);
    await loadCatalog();
  }

  // ---- Announcements (News feed + live events) -----------------------------
  List<Announcement> announcements = const [];
  bool announcementsLoading = false;
  Object? announcementsError;
  StreamSubscription<AnnouncementEvent>? _annSub;

  /// Discipline ids the user has an activity in (any registered session's
  /// discipline). Drives which discipline-targeted announcements reach them.
  Set<String> get myDisciplineIds => {
        for (final d in _disciplines)
          if (d.sessions.any((s) => _mySessionIds.contains(s.id))) d.id,
      };

  /// Whether an announcement targeting [disciplineId] reaches this user:
  /// everyone (null target), admins (all), a mentor who manages it, or anyone
  /// with an activity in that discipline.
  bool announcementReaches(String? disciplineId) {
    if (disciplineId == null) return true;
    if (isAdmin) return true;
    if (canManageDiscipline(disciplineId)) return true;
    return myDisciplineIds.contains(disciplineId);
  }

  /// The announcements this user should actually see (audience-filtered).
  List<Announcement> get visibleAnnouncements =>
      announcements.where((a) => announcementReaches(a.disciplineId)).toList();

  Future<void> loadAnnouncements() async {
    announcementsLoading = true;
    announcementsError = null;
    notifyListeners();
    try {
      announcements = await announcementsRepository.fetch();
    } catch (e) {
      announcementsError = e;
    } finally {
      announcementsLoading = false;
      notifyListeners();
    }
  }

  /// Subscribes to the live announcements feed so every open app updates and
  /// shows an in-app banner. Idempotent. A backend without realtime yields a
  /// stream that never emits, so this is a harmless no-op there.
  void subscribeAnnouncements() {
    if (_annSub != null) return;
    _annSub = announcementsRepository.events.listen(_onAnnouncementInserted);
  }

  void _onAnnouncementInserted(AnnouncementEvent event) {
    // Refresh the feed for everyone (keeps ordering/pinned correct).
    loadAnnouncements();
    // Don't banner the poster, or if they muted notifications.
    if (event.createdBy != null &&
        event.createdBy == authService.currentUser?.id) {
      return;
    }
    if (!notificationsEnabled) return;
    // Only banner if the announcement's audience actually reaches this user.
    if (!announcementReaches(event.disciplineId)) return;
    inAppBanner.show(BannerMessage(
      title: event.title,
      body: event.body,
      onTap: () => rootTab.value = kNewsTabIndex,
    ));
  }

  Future<void> _unsubscribeAnnouncements() async {
    await _annSub?.cancel();
    _annSub = null;
    await announcementsRepository.stopEvents();
  }

  // ---- Signed-in user ------------------------------------------------------
  // With a live backend, [profile] is loaded after sign-in. In sample mode it
  // stays null and the demo values below show.
  UserProfile? profile;
  bool profileLoading = false;

  static const String _demoName = 'Alex Rivera';
  static const String _demoRole = 'Participant';

  // Display source for the profile screen. Synced from [profile] on load; the
  // demo defaults apply only in sample mode.
  bool notificationsEnabled = true;
  double volunteerHours = 6.5;

  String get userName =>
      (profile?.fullName.isNotEmpty ?? false) ? profile!.fullName : _demoName;

  String get userRole => profile != null ? profile!.role.label : _demoRole;

  bool get isOnboarded => profile?.onboarded ?? false;

  // ---- Role helpers --------------------------------------------------------
  bool get isAdmin => profile?.role == SummitRole.admin;
  bool get isMentor => profile?.role == SummitRole.mentor;

  /// Whether the signed-in user may manage content in [disciplineId] (admins:
  /// always; mentors: only their scoped disciplines or the `*` wildcard).
  bool canManageDiscipline(String disciplineId) =>
      profile?.canManageDiscipline(disciplineId) ?? false;

  /// For a mentor, the human-readable disciplines they manage (names, or "All
  /// disciplines" for the `*` wildcard). Null for non-mentors / no scope yet.
  String? get mentorScopeLabel {
    final p = profile;
    if (p == null || p.role != SummitRole.mentor) return null;
    final ids = p.managedDisciplines;
    if (ids.isEmpty) return null;
    if (ids.contains('*')) return 'All disciplines';
    return ids.map((id) {
      final match = _disciplines.where((d) => d.id == id);
      return match.isNotEmpty ? match.first.name : id;
    }).join(' · ');
  }

  /// Loads the signed-in user's profile, then their catalog + schedule + feed.
  /// Called by the auth gate once a session exists.
  Future<void> loadProfile() async {
    profileLoading = true;
    notifyListeners();
    try {
      profile = await profileRepository.fetchMine();
      if (profile != null) {
        notificationsEnabled = profile!.notificationsEnabled;
        volunteerHours = profile!.volunteerHours;
      }
    } finally {
      profileLoading = false;
      notifyListeners();
    }
    await loadCatalog();
    await loadSchedule();
    await loadAnnouncements();
    subscribeAnnouncements();
  }

  /// Saves the finished onboarding profile and marks the user onboarded, so
  /// the auth gate moves them into the app.
  Future<void> completeOnboarding(UserProfile updated) async {
    updated.onboarded = true;
    await profileRepository.save(updated);
    // Re-read so the server's enforced role + mentor scope (set by the
    // role_allowlist trigger) are reflected locally, not just what we sent.
    profile = await profileRepository.fetchMine() ?? updated;
    notificationsEnabled = profile!.notificationsEnabled;
    volunteerHours = profile!.volunteerHours;
    notifyListeners();
  }

  /// Signs the user out and clears their in-memory state.
  Future<void> signOut() async {
    await _unsubscribeAnnouncements();
    await authService.signOut();
    profile = null;
    _mySessionIds.clear();
    _disciplines = const [];
    announcements = const [];
    notifyListeners();
  }

  Future<void> setNotifications(bool value) async {
    notificationsEnabled = value;
    profile?.notificationsEnabled = value;
    notifyListeners();
    await profileRepository.patch({'notifications_enabled': value});
  }
}

/// Global instance used throughout the skeleton.
final appState = AppState();
