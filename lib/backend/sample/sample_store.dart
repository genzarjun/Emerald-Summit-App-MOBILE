import '../../data/sample_data.dart';
import '../../models/models.dart';
import '../../models/user_profile.dart';

/// Mutable in-memory state shared by the sample backend's repositories, seeded
/// from the static [SampleData]. Keeps the app fully runnable with no backend
/// configured (demo mode).
class SampleStore {
  final List<Discipline> disciplines = List.of(SampleData.disciplines);

  /// The demo user's registrations: session id → how they joined. Replaces the
  /// old plain id set so demo mode carries participation type like the live one.
  final Map<String, ParticipationType> myRegistrations = {};

  /// Just the registered session ids — for the overlap loops that only care
  /// whether a slot is taken, not how.
  Set<String> get mySessionIds => myRegistrations.keys.toSet();
  final List<Announcement> announcements = List.of(SampleData.announcements);
  final List<GalleryPhoto> galleryPhotos = List.of(SampleData.galleryPhotos);

  /// Per-announcement read state for the (demo) user. In-memory only, so the
  /// unread badge + per-card dots behave like the live backend during a demo.
  /// [seen] clears the red count; [opened] clears a card's dot.
  final Set<String> seenAnnouncementIds = {};
  final Set<String> openedAnnouncementIds = {};

  /// Announcement ids the (demo) user has hidden from their own feed via the
  /// swipe-left "delete from my view" action. In-memory only.
  final Set<String> dismissedAnnouncementIds = {};

  /// Null until onboarding saves one; while null the app shows demo values,
  /// matching the pre-seam sample behavior.
  UserProfile? profile;

  // ---- Volunteers feature (rooms / assignments / attendance) --------------
  // In-memory analogues of the Supabase tables/RPCs, so demo mode and unit tests
  // exercise the same repository contracts. Seeded lazily on first access.

  List<Room>? _rooms;

  /// The rooms catalog, seeded from the distinct room strings the sample
  /// sessions carry (mirrors the live migration in rooms_setup.sql).
  List<Room> get rooms => _rooms ??= _seedRooms();

  List<Room> _seedRooms() {
    final names = <String>{
      for (final s in allSessions)
        if (s.room.trim().isNotEmpty) s.room.trim(),
    };
    var i = 0;
    return [
      for (final name in names) Room(id: 'room-${i++}', name: name, sortOrder: i),
    ];
  }

  /// The signed-in volunteer's own assignments (session ids). Empty in demo.
  final Set<String> myAssignedSessionIds = {};

  /// userId → session ids they're assigned to (drives the overlap guard).
  final Map<String, Set<String>> assignmentsByUser = {};

  /// sessionId → volunteers assigned (admin view).
  final Map<String, List<VolunteerRef>> sessionVolunteers = {};

  /// The volunteer directory for the admin assignment picker.
  final List<VolunteerRef> volunteers = [];

  /// sessionId → its roster (registered participants + attendance state).
  final Map<String, List<RosterEntry>> rosters = {};

  /// The summit-wide attendee directory for front-desk check-in.
  final List<Attendee> attendees = [];

  /// Project teams, keyed by code (in-memory analogue of the `teams` table).
  final Map<String, SampleTeam> teams = {};

  List<Session> get allSessions => [for (final d in disciplines) ...d.sessions];

  Session? sessionById(String id) {
    for (final s in allSessions) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// One demo team: the session it belongs to, its project, and member user ids.
class SampleTeam {
  SampleTeam({
    required this.id,
    required this.sessionId,
    required this.code,
    required this.projectName,
  });

  final String id;
  final String sessionId;
  final String code;
  String projectName;
  final Set<String> memberIds = {};
}
