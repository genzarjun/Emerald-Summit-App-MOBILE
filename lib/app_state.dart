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
  AppState() {
    // Opening the News tab (by tap or via the in-app banner) marks the feed
    // read, Instagram-style, so the unread badge clears.
    rootTab.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (rootTab.value == kNewsTabIndex) markAnnouncementsSeen();
  }

  @override
  void dispose() {
    rootTab.removeListener(_onTabChanged);
    super.dispose();
  }

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

  // ---- Gallery (dashboard slideshow) ---------------------------------------
  // Each photo set is a storage bucket; every image in it is shown. Other app
  // sections can read their own bucket the same way (add a field + loader here).
  static const String dashboardGalleryBucket = 'gallery_photos';

  List<GalleryPhoto> galleryPhotos = const [];

  /// Loads the dashboard slideshow photos from [dashboardGalleryBucket] and
  /// shuffles them, so the order is fresh on each load (startup + pull-to-
  /// refresh). Best-effort — the repository never throws, so a failure just
  /// leaves the slideshow hidden.
  Future<void> loadGallery() async {
    final photos = [...await galleryRepository.fetchPhotos(dashboardGalleryBucket)]
      ..shuffle();
    galleryPhotos = photos;
    notifyListeners();
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

  /// True if the signed-in volunteer is assigned to manage this session (an
  /// admin action — the user can't add/remove it themselves).
  bool isManaging(String id) => myAssignedSessionIds.contains(id);

  /// The user's full schedule: sessions they manage (assigned) AND sessions they
  /// attend (registered), each tagged with the role, sorted by start time.
  /// Managing wins if a session is both.
  List<ScheduleEntry> get scheduleEntries {
    final byId = <String, ScheduleEntry>{};
    for (final s in myAssignedSessions) {
      byId[s.id] = ScheduleEntry(session: s, managing: true);
    }
    for (final s in mySessions) {
      byId.putIfAbsent(s.id, () => ScheduleEntry(session: s, managing: false));
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.session.startMinutes.compareTo(b.session.startMinutes));
    return list;
  }

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

  // ---- Rooms (admin-managed catalog) ---------------------------------------
  List<Room> rooms = const [];

  Future<void> loadRooms() async {
    rooms = await roomsRepository.fetchAll();
    notifyListeners();
  }

  Future<void> createRoom(Map<String, dynamic> data) async {
    await roomsRepository.create(data);
    await loadRooms();
  }

  Future<void> updateRoom(String id, Map<String, dynamic> data) async {
    await roomsRepository.update(id, data);
    await loadRooms();
  }

  Future<void> deleteRoom(String id) async {
    await roomsRepository.delete(id);
    await loadRooms();
  }

  // ---- Session assignments (volunteer roster/attendance access) ------------
  Set<String> myAssignedSessionIds = const {};

  /// The sessions the signed-in volunteer is assigned to (roster + attendance).
  List<Session> get myAssignedSessions =>
      [for (final s in allSessions) if (myAssignedSessionIds.contains(s.id)) s];

  /// Loads the signed-in volunteer's session assignments. No-op for other roles.
  Future<void> loadMyAssignments() async {
    if (!isVolunteer) {
      myAssignedSessionIds = const {};
      return;
    }
    try {
      myAssignedSessionIds =
          await assignmentRepository.fetchMyAssignedSessionIds();
    } catch (_) {
      myAssignedSessionIds = const {};
    }
    notifyListeners();
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
  /// everyone (null target), admins (all), a volunteer who manages it, or anyone
  /// with an activity in that discipline.
  bool announcementReaches(String? disciplineId) {
    if (disciplineId == null) return true;
    if (isAdmin) return true;
    if (canManageDiscipline(disciplineId)) return true;
    return myDisciplineIds.contains(disciplineId);
  }

  String? get _myUserId => profile?.id ?? authService.currentUser?.id;

  /// Whether an announcement reaches this user, accounting for PERSONAL
  /// targeting: a targeted announcement reaches only its recipient; otherwise
  /// the discipline-audience rules apply.
  bool reachesMe({String? disciplineId, String? targetUserId}) {
    if (targetUserId != null) return targetUserId == _myUserId;
    return announcementReaches(disciplineId);
  }

  /// The announcements this user should actually see: audience-filtered,
  /// personal announcements only for their recipient, and anything they've
  /// hidden from their own feed ("delete from my view") removed.
  List<Announcement> get visibleAnnouncements => announcements
      .where((a) =>
          reachesMe(
              disciplineId: a.disciplineId, targetUserId: a.targetUserId) &&
          !_dismissedAnnouncementIds.contains(a.id))
      .toList();

  // ---- Read state (per-user, two-tier) -------------------------------------
  // [_seen] clears the red unread count (set when the News feed is viewed);
  // [_opened] clears a card's unread dot (set when the user taps that card).
  // Both are loaded from the backend on sign-in and are private per user.
  final Set<String> _seenAnnouncementIds = {};
  final Set<String> _openedAnnouncementIds = {};

  // Announcement ids the user has hidden from their own feed (swipe-left
  // "delete from my view"). Private per user; loaded alongside read-state.
  final Set<String> _dismissedAnnouncementIds = {};

  /// False until read-state has been fetched at least once. The announcements
  /// list loads a beat before read-state, so without this gate the badge would
  /// briefly flash "everything unseen" (e.g. 6) before correcting to the real
  /// count. Suppressing the badge/dots until read-state is in avoids that flash.
  bool _readStateLoaded = false;

  /// How many of the announcements this user can see are still unseen. Drives
  /// the News-tab badge and the dashboard "What's new" tile. Reports 0 until
  /// read-state has loaded, so a stale count never flashes on launch.
  int get unreadAnnouncementCount => !_readStateLoaded
      ? 0
      : visibleAnnouncements
          .where((a) => !_seenAnnouncementIds.contains(a.id))
          .length;

  /// Whether [id] still deserves an unread dot — i.e. the user hasn't opened
  /// that specific announcement yet. Persists after the red badge clears. Shows
  /// no dot until read-state has loaded (same anti-flash reasoning as above).
  bool isAnnouncementUnopened(String id) =>
      _readStateLoaded && !_openedAnnouncementIds.contains(id);

  /// Loads the signed-in user's per-announcement read state (seen + opened).
  Future<void> loadReadAnnouncements() async {
    try {
      final state = await announcementsRepository.fetchReadState();
      _seenAnnouncementIds
        ..clear()
        ..addAll(state.seen);
      _openedAnnouncementIds
        ..clear()
        ..addAll(state.opened);
      final dismissed = await announcementsRepository.fetchDismissed();
      _dismissedAnnouncementIds
        ..clear()
        ..addAll(dismissed);
    } catch (_) {
      // Leave read-state empty on failure; nothing is worse than a stale badge.
    } finally {
      // Mark loaded either way so the badge can reflect the real count (or a
      // genuine "all unseen" when read-state truly is empty) without flashing.
      _readStateLoaded = true;
      notifyListeners();
    }
  }

  /// Marks every currently-visible unseen announcement as seen (locally +
  /// backend), clearing the red count. No-op — and importantly no notify — when
  /// nothing is unseen, so the rootTab listener can call it without a rebuild
  /// loop. Does NOT touch "opened", so per-card dots remain.
  Future<void> markAnnouncementsSeen() async {
    final unseen = [
      for (final a in visibleAnnouncements)
        if (!_seenAnnouncementIds.contains(a.id)) a.id,
    ];
    if (unseen.isEmpty) return;
    _seenAnnouncementIds.addAll(unseen);
    notifyListeners();
    try {
      await announcementsRepository.markSeen(unseen);
    } catch (_) {
      // Local state already reflects "seen"; a failed persist just means the
      // badge may reappear on next launch until it succeeds.
    }
  }

  /// Marks one announcement opened (locally + backend), clearing its dot. Seeing
  /// implies opening covers the count too. No-op/no-notify if already opened.
  Future<void> markAnnouncementOpened(String id) async {
    if (_openedAnnouncementIds.contains(id)) return;
    _openedAnnouncementIds.add(id);
    _seenAnnouncementIds.add(id);
    notifyListeners();
    try {
      await announcementsRepository.markOpened(id);
    } catch (_) {
      // Local state already reflects "opened"; a failed persist just means the
      // dot may reappear on next launch until it succeeds.
    }
  }

  /// Hides an announcement from just this user's feed ("delete from my view").
  /// Optimistic: removes it locally and rebuilds, then persists. Available to
  /// every user. Safe to call for an already-hidden id.
  Future<void> hideAnnouncement(String id) async {
    if (!_dismissedAnnouncementIds.add(id)) return;
    notifyListeners();
    try {
      await announcementsRepository.hideForMe(id);
    } catch (_) {
      // Local state already reflects "hidden"; a failed persist just means it
      // may reappear on next launch until it succeeds.
    }
  }

  /// Undo of [hideAnnouncement] — brings a hidden announcement back into this
  /// user's feed. No-op if it wasn't hidden.
  Future<void> unhideAnnouncement(String id) async {
    if (!_dismissedAnnouncementIds.remove(id)) return;
    notifyListeners();
    try {
      await announcementsRepository.unhideForMe(id);
    } catch (_) {
      // Local state already reflects "visible"; a failed persist just means it
      // may vanish again on next launch until it succeeds.
    }
  }

  /// Permanently deletes an announcement for EVERYONE (admin-only; the backend
  /// rejects a non-admin call). Optimistic: drops it locally, then deletes on
  /// the backend. Realtime propagates the removal to other open apps. Rethrows
  /// on failure after restoring the local copy so the UI can report it.
  Future<void> deleteAnnouncementForEveryone(String id) async {
    final index = announcements.indexWhere((a) => a.id == id);
    if (index < 0) return;
    final removed = announcements[index];
    announcements = List.of(announcements)..removeAt(index);
    notifyListeners();
    try {
      await announcementsRepository.deleteForEveryone(id);
    } catch (e) {
      // Restore on failure (e.g. a rejected delete) so the feed stays truthful.
      final restored = List.of(announcements)..insert(index, removed);
      announcements = restored;
      notifyListeners();
      rethrow;
    }
  }

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
    // A delete-for-everyone: drop it from the local feed immediately, no banner.
    if (event.deleted) {
      final next = announcements.where((a) => a.id != event.id).toList();
      if (next.length != announcements.length) {
        announcements = next;
        notifyListeners();
      }
      return;
    }
    // Refresh the feed for everyone (keeps ordering/pinned correct).
    loadAnnouncements();
    // A personal notice aimed at me is usually an assign/unassign change — pull
    // my assignments so the Schedule + "managing" list update live too.
    if (event.targetUserId != null && event.targetUserId == _myUserId) {
      loadMyAssignments();
    }
    // Don't banner the poster, or if they muted notifications.
    if (event.createdBy != null &&
        event.createdBy == authService.currentUser?.id) {
      return;
    }
    if (!notificationsEnabled) return;
    // Only banner if it actually reaches this user (audience or personal target).
    if (!reachesMe(
        disciplineId: event.disciplineId, targetUserId: event.targetUserId)) {
      return;
    }
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
  bool get isVolunteer => profile?.role == SummitRole.volunteer;

  /// Capability flags (server-owned; admins implicitly have them all).
  bool get canEditSessions =>
      isAdmin || (profile?.canEditSessions ?? false);
  bool get canPostAnnouncements =>
      isAdmin || (profile?.canPostAnnouncements ?? false);
  bool get canCheckInFrontDesk =>
      isAdmin || (profile?.canCheckInFrontDesk ?? false);

  /// Whether to surface the "New announcement" composer. Admins always; a
  /// volunteer only when they can post AND actually have a discipline to target
  /// (posting requires a scope, so `can_post_announcements` with no discipline
  /// is inert — don't show a composer that leads nowhere).
  bool get canComposeAnnouncement {
    if (isAdmin) return true;
    final p = profile;
    if (p == null || !p.canPostAnnouncements) return false;
    return p.managedDisciplines.isNotEmpty;
  }

  /// The volunteer's subtype label (e.g. "EAF Ambassador"), or null.
  String? get volunteerSubtypeLabel => profile?.volunteerSubtype?.label;

  /// Whether the signed-in user may manage content in [disciplineId] (admins:
  /// always; volunteers: only when they can edit sessions and are scoped to it
  /// or hold the `*` wildcard).
  bool canManageDiscipline(String disciplineId) =>
      profile?.canManageDiscipline(disciplineId) ?? false;

  /// Whether the signed-in user may post an announcement to [disciplineId].
  bool canPostToDiscipline(String disciplineId) =>
      profile?.canPostToDiscipline(disciplineId) ?? false;

  /// For a volunteer, the human-readable disciplines they manage (names, or
  /// "All disciplines" for the `*` wildcard). Null for non-volunteers / no
  /// scope yet.
  String? get volunteerScopeLabel {
    final p = profile;
    if (p == null || p.role != SummitRole.volunteer) return null;
    final ids = p.managedDisciplines;
    if (ids.isEmpty) return null;
    if (ids.contains('*')) return 'All disciplines';
    return ids.map((id) {
      final match = _disciplines.where((d) => d.id == id);
      return match.isNotEmpty ? match.first.name : id;
    }).join(' · ');
  }

  // ---- Test/dev-login accounts ---------------------------------------------
  // Set when the current session was established via the dev-login bypass, so
  // the gate can auto-assign the role (from the allowlist) instead of showing
  // the manual role picker — a real user still onboards normally.
  bool _isTestAccountSession = false;

  /// A one-time notice to show after a test account is auto-onboarded, e.g.
  /// "…automatically assigned the Participant role…". Read once via
  /// [consumeTestAccountNotice].
  String? _testAccountNotice;

  /// Marks that the just-created session came from the dev-login bypass.
  void markTestAccountSignIn() => _isTestAccountSession = true;

  /// Returns the pending test-account notice and clears it (shown once).
  String? consumeTestAccountNotice() {
    final n = _testAccountNotice;
    _testAccountNotice = null;
    return n;
  }

  /// Loads the signed-in user's profile, then their catalog + schedule + feed.
  /// Called by the auth gate once a session exists.
  Future<void> loadProfile() async {
    profileLoading = true;
    notifyListeners();
    try {
      profile = await profileRepository.fetchMine();
      // Test accounts skip the manual role picker: assign the role straight from
      // the allowlist (participant if unlisted) so the tester lands in the app
      // already "being" that persona.
      if (_isTestAccountSession &&
          profile != null &&
          !profile!.onboarded) {
        await _autoOnboardTestAccount();
      }
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
    await loadReadAnnouncements();
    await loadMyAssignments();
    await loadGallery();
    subscribeAnnouncements();
  }

  /// Auto-onboards a dev-login test account: picks the role from the allowlist
  /// (admin > volunteer > participant), saves the profile onboarded, and lets
  /// the server trigger apply the subtype/capabilities. Sets [_testAccountNotice].
  Future<void> _autoOnboardTestAccount() async {
    final p = profile;
    if (p == null) return;
    SummitRole role;
    try {
      // Gated roles come from the allowlist (the trigger re-verifies on save).
      if (await allowlistRepository.isEligible(SummitRole.admin)) {
        role = SummitRole.admin;
      } else if (await allowlistRepository.isEligible(SummitRole.volunteer)) {
        role = SummitRole.volunteer;
      } else {
        // Open roles (participant/expert/parent-spectator) aren't in any sheet,
        // so infer from the code email's local part — test accounts are named by
        // role (expert@…, spectator@…, participant@…).
        role = _inferOpenTestRole(p.email);
      }
    } catch (_) {
      role = _inferOpenTestRole(p.email);
    }
    // A friendly default name from the email's local part (e.g. "student-plain").
    final localPart = p.email.split('@').first;
    p.fullName = p.fullName.isNotEmpty ? p.fullName : localPart;
    p.role = role;
    p.onboarded = true;
    await profileRepository.save(p);
    // Re-read so the trigger's enforced role + subtype/capabilities land locally.
    profile = await profileRepository.fetchMine() ?? p;
    final subtype = profile!.volunteerSubtype?.label;
    final roleText = subtype == null
        ? profile!.role.label
        : '${profile!.role.label} · $subtype';
    _testAccountNotice =
        'Testing account — you were automatically assigned the $roleText '
        'role. No role picker needed.';
  }

  /// Infers an OPEN role for a test account from its code-email local part.
  /// Only used for dev-login accounts not covered by the allowlist.
  static SummitRole _inferOpenTestRole(String email) {
    final local = email.split('@').first.toLowerCase();
    if (local.contains('expert')) return SummitRole.expert;
    if (local.contains('spectator') || local.contains('parent')) {
      return SummitRole.parent;
    }
    return SummitRole.participant;
  }

  /// Saves the finished onboarding profile and marks the user onboarded, so
  /// the auth gate moves them into the app.
  Future<void> completeOnboarding(UserProfile updated) async {
    updated.onboarded = true;
    await profileRepository.save(updated);
    // Re-read so the server's enforced role + volunteer scope/capabilities (set
    // by the role_allowlist trigger) are reflected locally, not just what we sent.
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
    galleryPhotos = const [];
    _seenAnnouncementIds.clear();
    _openedAnnouncementIds.clear();
    _dismissedAnnouncementIds.clear();
    _readStateLoaded = false;
    myAssignedSessionIds = const {};
    rooms = const [];
    _isTestAccountSession = false;
    _testAccountNotice = null;
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
