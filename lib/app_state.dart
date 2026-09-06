import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'app_navigation.dart';
import 'data/announcements_repository.dart';
import 'data/disciplines_repository.dart';
import 'data/profile_repository.dart';
import 'data/registrations_repository.dart';
import 'data/sample_data.dart';
import 'data/sessions_repository.dart';
import 'models/models.dart';
import 'models/user_profile.dart';
import 'supabase_config.dart';
import 'widgets/in_app_banner.dart';

/// Result of trying to add a session to the day plan.
enum AddOutcome { added, removed, conflict, full }

class AddResult {
  const AddResult(this.outcome, [this.conflictingTitle]);
  final AddOutcome outcome;
  final String? conflictingTitle;
}

/// App-wide state. As of Phase 1 the catalog (disciplines + sessions) and the
/// personal schedule are backed by Supabase; the notifications toggle and
/// volunteer hours live on the user's profile row. When Supabase isn't
/// configured everything falls back to in-memory [SampleData] so the UI
/// skeleton still runs standalone.
class AppState extends ChangeNotifier {
  bool get _backend => SupabaseConfig.isConfigured;

  // ---- Catalog -------------------------------------------------------------
  List<Discipline> _disciplines = const [];
  bool catalogLoading = false;
  Object? catalogError;

  List<Discipline> get disciplines => _disciplines;

  /// Flattened list of every session across all disciplines.
  List<Session> get allSessions =>
      [for (final d in _disciplines) ...d.sessions];

  /// Loads the catalog from Supabase (or sample data). Safe to call repeatedly;
  /// used on startup and by pull-to-refresh.
  Future<void> loadCatalog() async {
    catalogLoading = true;
    catalogError = null;
    notifyListeners();
    try {
      _disciplines =
          _backend ? await DisciplinesRepository.fetchAll() : SampleData.disciplines;
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
    if (!_backend) return;
    try {
      _disciplines = await DisciplinesRepository.fetchAll();
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

  /// Loads the signed-in user's registrations. No-op in sample mode (the plan
  /// is kept in memory there).
  Future<void> loadSchedule() async {
    if (!_backend) return;
    try {
      final ids = await RegistrationsRepository.fetchMySessionIds();
      _mySessionIds
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {
      // Leave the schedule empty on failure; the user can retry by reopening.
    }
  }

  /// Toggles a session in the plan. In backend mode this defers to the
  /// `register_for_session` RPC (the trusted enforcer of capacity + no-overlap);
  /// in sample mode it applies the same rules in memory.
  Future<AddResult> toggle(Session session) async {
    if (_backend) return _toggleBackend(session);
    return _toggleLocal(session);
  }

  Future<AddResult> _toggleBackend(Session session) async {
    final res = await RegistrationsRepository.toggle(session.id);
    final outcome = _outcome((res['outcome'] ?? 'added') as String);
    switch (outcome) {
      case AddOutcome.added:
        _mySessionIds.add(session.id);
        await _refreshCatalogSilently();
        notifyListeners();
      case AddOutcome.removed:
        _mySessionIds.remove(session.id);
        await _refreshCatalogSilently();
        notifyListeners();
      case AddOutcome.full:
      case AddOutcome.conflict:
        break; // nothing changed
    }
    return AddResult(outcome, res['conflicting_title'] as String?);
  }

  AddResult _toggleLocal(Session session) {
    if (_mySessionIds.contains(session.id)) {
      _mySessionIds.remove(session.id);
      notifyListeners();
      return const AddResult(AddOutcome.removed);
    }
    if (session.isFull) return const AddResult(AddOutcome.full);
    for (final s in mySessions) {
      if (s.overlaps(session)) {
        return AddResult(AddOutcome.conflict, s.title);
      }
    }
    _mySessionIds.add(session.id);
    notifyListeners();
    return const AddResult(AddOutcome.added);
  }

  static AddOutcome _outcome(String s) => switch (s) {
        'added' => AddOutcome.added,
        'removed' => AddOutcome.removed,
        'full' => AddOutcome.full,
        'conflict' => AddOutcome.conflict,
        _ => AddOutcome.added,
      };

  // ---- Content management (mentors/admins) ---------------------------------
  /// Creates or updates a session, then refreshes the catalog. RLS enforces that
  /// the caller may manage [data]'s discipline.
  Future<void> saveSession({String? id, required Map<String, dynamic> data}) async {
    if (id == null) {
      await SessionsRepository.create(data);
    } else {
      await SessionsRepository.update(id, data);
    }
    await loadCatalog();
  }

  Future<void> deleteSession(String id) async {
    await SessionsRepository.delete(id);
    await loadCatalog();
  }

  /// Creates a discipline (admin only), then refreshes the catalog.
  Future<void> createDiscipline(Map<String, dynamic> data) async {
    await DisciplinesRepository.create(data);
    await loadCatalog();
  }

  // ---- Announcements (News feed + Realtime) --------------------------------
  List<Announcement> announcements = const [];
  bool announcementsLoading = false;
  Object? announcementsError;
  RealtimeChannel? _annChannel;

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
      announcements = _backend
          ? await AnnouncementsRepository.fetch()
          : SampleData.announcements;
    } catch (e) {
      announcementsError = e;
    } finally {
      announcementsLoading = false;
      notifyListeners();
    }
  }

  /// Subscribes to new announcements so every open app updates its feed live and
  /// shows an in-app banner. No-op in sample mode or if already subscribed.
  ///
  /// Realtime is a NICE-TO-HAVE, not required: if the socket can't connect (e.g.
  /// the project's concurrent-Realtime limit is hit) we stay completely silent —
  /// the feed still works via REST + pull-to-refresh. Failures never reach the
  /// UI; the News error state is driven only by [loadAnnouncements].
  void subscribeAnnouncements() {
    if (!_backend || _annChannel != null) return;
    try {
      _annChannel = Supabase.instance.client
          .channel('public:announcements')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'announcements',
            callback: (payload) => _onAnnouncementInserted(payload.newRecord),
          )
          .subscribe((status, error) {
        // Swallow connection status/errors — no user-facing message, ever.
        if (error != null && kDebugMode) {
          debugPrint('Realtime announcements: $status ($error)');
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Realtime subscribe skipped: $e');
    }
  }

  void _onAnnouncementInserted(Map<String, dynamic> row) {
    // Refresh the feed for everyone (keeps ordering/pinned correct).
    loadAnnouncements();
    // Don't banner the admin who just posted it, or if they muted notifications.
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (row['created_by']?.toString() == me) return;
    if (!notificationsEnabled) return;
    // Only banner if the announcement's audience actually reaches this user.
    if (!announcementReaches(row['discipline_id'] as String?)) return;
    inAppBanner.show(BannerMessage(
      title: (row['title'] ?? 'New announcement') as String,
      body: (row['body'] ?? '') as String,
      onTap: () => rootTab.value = kNewsTabIndex,
    ));
  }

  Future<void> _unsubscribeAnnouncements() async {
    if (_annChannel != null) {
      await Supabase.instance.client.removeChannel(_annChannel!);
      _annChannel = null;
    }
  }

  // ---- Signed-in user ------------------------------------------------------
  // When Supabase is configured, [profile] is loaded from the backend after
  // sign-in. In sample mode it stays null and the demo values below show.
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

  /// Loads the signed-in user's profile from Supabase, then their catalog +
  /// schedule. Called by the auth gate once a session exists.
  Future<void> loadProfile() async {
    profileLoading = true;
    notifyListeners();
    try {
      profile = await ProfileRepository.fetchMine();
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
    await ProfileRepository.save(updated);
    // Re-read so the server's enforced role + mentor scope (set by the
    // role_allowlist trigger) are reflected locally, not just what we sent.
    profile = await ProfileRepository.fetchMine() ?? updated;
    notificationsEnabled = profile!.notificationsEnabled;
    volunteerHours = profile!.volunteerHours;
    notifyListeners();
  }

  /// Signs the user out and clears their in-memory state.
  Future<void> signOut() async {
    await _unsubscribeAnnouncements();
    await Supabase.instance.client.auth.signOut();
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
    if (_backend) {
      await ProfileRepository.patch({'notifications_enabled': value});
    }
  }
}

/// Global instance used throughout the skeleton.
final appState = AppState();
