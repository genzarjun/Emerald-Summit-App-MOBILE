import '../../data/sample_data.dart';
import '../../models/models.dart';
import '../../models/user_profile.dart';

/// Mutable in-memory state shared by the sample backend's repositories, seeded
/// from the static [SampleData]. Keeps the app fully runnable with no backend
/// configured (demo mode).
class SampleStore {
  final List<Discipline> disciplines = List.of(SampleData.disciplines);
  final Set<String> mySessionIds = {};
  final List<Announcement> announcements = List.of(SampleData.announcements);

  /// Per-announcement read state for the (demo) user. In-memory only, so the
  /// unread badge + per-card dots behave like the live backend during a demo.
  /// [seen] clears the red count; [opened] clears a card's dot.
  final Set<String> seenAnnouncementIds = {};
  final Set<String> openedAnnouncementIds = {};

  /// Null until onboarding saves one; while null the app shows demo values,
  /// matching the pre-seam sample behavior.
  UserProfile? profile;

  List<Session> get allSessions => [for (final d in disciplines) ...d.sessions];

  Session? sessionById(String id) {
    for (final s in allSessions) {
      if (s.id == id) return s;
    }
    return null;
  }
}
