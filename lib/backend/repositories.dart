/// Backend-neutral data contracts.
///
/// Every repository the app uses is defined here as an abstract interface. App
/// code (screens, [AppState]) depends only on these interfaces — never on a
/// backend SDK. A backend supplies one implementation per interface under its
/// own folder (see `supabase/`, `sample/`).
///
/// ## The row contract
/// Repositories return the app's domain models ([Discipline], [Session],
/// [Announcement], [UserProfile]) or plain maps whose keys match the model
/// `fromMap`/`toMap` decoders in `models/`. A new backend's adapter is
/// responsible for shaping its rows to those keys, so the models stay
/// backend-agnostic.
library;

import 'dart:typed_data';

import '../models/models.dart';
import '../models/user_profile.dart';

/// Outcome of toggling a session in the personal schedule. Mirrors the states
/// the server-side enforcer can return (capacity + no time overlap).
enum RegistrationOutcome { added, removed, full, conflict }

/// Result of a schedule toggle. [conflictingTitle] is set only for
/// [RegistrationOutcome.conflict].
class RegistrationResult {
  const RegistrationResult(this.outcome, [this.conflictingTitle]);

  final RegistrationOutcome outcome;
  final String? conflictingTitle;
}

/// Outcome of an admin assigning a volunteer to a session. [conflict] mirrors
/// the server-side overlap guard (the volunteer is already committed to an
/// overlapping session or personal registration).
enum AssignmentOutcome { assigned, conflict, registeredConfirm }

/// Result of a volunteer→session assignment. [conflictingTitle] is set only for
/// [AssignmentOutcome.conflict].
class AssignmentResult {
  const AssignmentResult(this.outcome, [this.conflictingTitle]);

  final AssignmentOutcome outcome;
  final String? conflictingTitle;
}

/// A newly-posted announcement delivered over a live feed. Backends without
/// realtime simply never emit these.
class AnnouncementEvent {
  const AnnouncementEvent({
    required this.id,
    required this.title,
    required this.body,
    this.createdBy,
    this.disciplineId,
    this.targetUserId,
    this.deleted = false,
  });

  final String id;
  final String title;
  final String body;

  /// User id of the poster, so the app can avoid bannering the author.
  final String? createdBy;

  /// Target discipline, or null for an everyone-announcement.
  final String? disciplineId;

  /// When set, a personal announcement for that single user (e.g. an assignment
  /// notification) — only they should see/banner it.
  final String? targetUserId;

  /// True for a "removed" event: the announcement [id] was deleted for everyone.
  /// The app just drops it from the feed (never banners it). Only [id] is
  /// meaningful on a deletion event.
  final bool deleted;
}

/// The session catalog: disciplines with their sessions nested underneath.
abstract interface class CatalogRepository {
  Future<List<Discipline>> fetchAll();

  /// Creates a discipline (admin-only; enforced by the backend). Map keys:
  /// id, name, tagline, icon, sort_order.
  Future<void> createDiscipline(Map<String, dynamic> data);
}

/// Session authoring for mentors/admins. Authorization is enforced by the
/// backend, so an unauthorized write is rejected even if the UI is bypassed.
abstract interface class ContentRepository {
  /// Map keys: discipline_id, title, track, room, expert_name, start_time,
  /// end_time, capacity, description, sponsor.
  Future<void> createSession(Map<String, dynamic> data);

  Future<void> updateSession(String id, Map<String, dynamic> data);

  Future<void> deleteSession(String id);
}

/// The signed-in user's personal schedule.
abstract interface class ScheduleRepository {
  /// Session ids the current user has added to their day.
  Future<Set<String>> fetchMySessionIds();

  /// Toggles a session in the schedule, enforcing capacity + no-overlap.
  Future<RegistrationResult> toggle(String sessionId);
}

/// The signed-in user's own profile row.
abstract interface class ProfileRepository {
  /// Loads the current user's profile, or null if nobody is signed in.
  Future<UserProfile?> fetchMine();

  /// Inserts or updates the user's profile.
  Future<void> save(UserProfile profile);

  /// Updates just the given fields on the current user's row.
  Future<void> patch(Map<String, dynamic> fields);
}

/// The announcements feed, plus an optional live event stream.
abstract interface class AnnouncementsRepository {
  /// Announcements newest-first, pinned surfaced to the top.
  Future<List<Announcement>> fetch();

  /// Posts an announcement (admin-only; enforced by the backend).
  /// [disciplineId] targets an audience; null = everyone.
  Future<void> create({
    required String title,
    required String body,
    required String author,
    String audience,
    bool pinned,
    String? disciplineId,
  });

  /// The current user's per-announcement read state:
  ///   * [seen]   — surfaced in the feed; clears the red unread count.
  ///   * [opened] — the user tapped the card; clears its unread dot.
  /// Both empty when signed out, or for a backend without per-user read tracking
  /// (e.g. before the `announcement_reads` table exists). Best-effort — never
  /// throws to the UI.
  Future<({Set<String> seen, Set<String> opened})> fetchReadState();

  /// Marks [ids] as seen (a row exists). Idempotent and best-effort — never
  /// throws. No-op when nobody is signed in or [ids] is empty.
  Future<void> markSeen(Iterable<String> ids);

  /// Marks one announcement opened (sets `opened_at`). Best-effort — never
  /// throws. No-op when nobody is signed in.
  Future<void> markOpened(String id);

  /// The current user's set of announcement ids hidden from their OWN feed (the
  /// swipe-left "delete from my view" action). Empty when signed out, or for a
  /// backend without dismissal tracking. Best-effort — never throws to the UI.
  Future<Set<String>> fetchDismissed();

  /// Hides [id] from just the current user's feed (does not affect anyone else).
  /// Idempotent and best-effort — never throws. No-op when nobody is signed in.
  Future<void> hideForMe(String id);

  /// Un-hides [id] for the current user (undo of [hideForMe]). Idempotent and
  /// best-effort — never throws. No-op when nobody is signed in.
  Future<void> unhideForMe(String id);

  /// Permanently deletes [id] for EVERYONE (admin-only; enforced by the
  /// backend). Throws on a rejected delete so the UI can surface it.
  Future<void> deleteForEveryone(String id);

  /// Live stream of newly-inserted announcements. A backend without realtime
  /// returns a stream that never emits; the feed still works via [fetch] +
  /// pull-to-refresh. Never surfaces connection errors to the UI.
  Stream<AnnouncementEvent> get events;

  /// Tears down any live subscription (e.g. on sign-out). No-op if none.
  Future<void> stopEvents();
}

/// Photo sets shown in the app, each backed by its own storage bucket: EVERY
/// image in the given bucket is a photo. Curation is just uploading/deleting
/// files — no table. Different parts of the app read different buckets (the
/// dashboard slideshow, a future sponsors wall, etc.).
abstract interface class GalleryRepository {
  /// Every image in [bucket], as photos. Never throws to the UI — a missing
  /// bucket or offline read yields an empty list so the caller simply shows
  /// nothing. Order is not guaranteed; callers that want a specific order (or a
  /// shuffle) impose it themselves.
  Future<List<GalleryPhoto>> fetchPhotos(String bucket);
}

/// A session's own photos (hero + gallery), each backed by a per-session folder
/// (`<session_id>/…`) in the `session_photos` Storage bucket. Reads are public;
/// writes are gated server-side to admins and the session's discipline editors,
/// so an unauthorized upload/delete is rejected even if the UI is bypassed.
abstract interface class SessionMediaRepository {
  /// Every photo uploaded for [sessionId]. Never throws to the UI — a missing
  /// folder or offline read yields an empty list.
  Future<List<GalleryPhoto>> fetchPhotos(String sessionId);

  /// Uploads [bytes] (a JPEG/PNG) under [sessionId]'s folder as [fileName] and
  /// returns the stored photo (with its public URL). Throws on a rejected write.
  Future<GalleryPhoto> uploadPhoto(
      String sessionId, Uint8List bytes, String fileName);

  /// Deletes [fileName] from [sessionId]'s folder. Throws on a rejected delete.
  Future<void> deletePhoto(String sessionId, String fileName);
}

/// Advisory eligibility check for gated roles (volunteer/admin). The real guard is
/// server-side; this only drives the "you aren't eligible" onboarding message.
abstract interface class AllowlistRepository {
  Future<bool> isEligible(SummitRole role);
}

/// The admin-managed rooms catalog. Sessions are tied to a room; volunteers are
/// assigned to sessions. Writes are admin-only (enforced by the backend).
abstract interface class RoomsRepository {
  Future<List<Room>> fetchAll();

  /// Creates a room. Map keys: name, sort_order.
  Future<void> create(Map<String, dynamic> data);

  Future<void> update(String id, Map<String, dynamic> data);

  Future<void> delete(String id);
}

/// Volunteer↔session assignments. Admins assign; assignment grants the volunteer
/// access to that session's roster + attendance. All authorization is enforced
/// server-side.
abstract interface class AssignmentRepository {
  /// Sessions (as ids) the signed-in volunteer is assigned to.
  Future<Set<String>> fetchMyAssignedSessionIds();

  /// The volunteers currently assigned to [sessionId] (admin view).
  Future<List<VolunteerRef>> fetchSessionVolunteers(String sessionId);

  /// The full volunteer directory, for the admin assignment picker.
  Future<List<VolunteerRef>> fetchVolunteers();

  /// Assigns [userId] to [sessionId], enforcing the no-overlap guard, and drops
  /// a personal "you're managing this session" notification into the volunteer's
  /// feed. Returns [AssignmentOutcome.conflict] (with the clashing title) if the
  /// volunteer is already committed to an overlapping session/registration; or
  /// [AssignmentOutcome.registeredConfirm] if they're already registered for
  /// this very session and [confirmRegistered] is false — call again with
  /// [confirmRegistered] true to proceed.
  Future<AssignmentResult> assign(String sessionId, String userId,
      {bool confirmRegistered = false});

  Future<void> unassign(String sessionId, String userId);
}

/// Attendance: per-session rosters (for session-assigned volunteers) and the
/// summit-wide front-desk directory (for front-desk-capable volunteers). Every
/// method is gated server-side.
abstract interface class AttendanceRepository {
  /// The registered participants of [sessionId] + their attendance state.
  Future<List<RosterEntry>> fetchSessionRoster(String sessionId);

  Future<void> markSessionAttendance(
      String sessionId, String userId, bool attended);

  /// All attendees + their arrival state, optionally filtered by [query].
  Future<List<Attendee>> fetchAttendeeDirectory([String query]);

  Future<void> markSummitCheckin(String attendeeId, bool present);
}
