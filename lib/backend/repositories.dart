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
/// the server-side enforcer can return (capacity + no time overlap, plus a
/// project/team answer it couldn't accept, and participating after the
/// session's participant deadline).
enum RegistrationOutcome {
  added,
  removed,
  full,
  conflict,
  invalidProject,
  participationClosed,
}

/// Result of a schedule toggle. [conflictingTitle] is set only for
/// [RegistrationOutcome.conflict]; [message] only for
/// [RegistrationOutcome.invalidProject]. On an add that created a team,
/// [teamCode] is the code to share with teammates.
class RegistrationResult {
  const RegistrationResult(
    this.outcome, [
    this.conflictingTitle,
  ])  : teamCode = null,
        message = null;

  const RegistrationResult.added({this.teamCode})
      : outcome = RegistrationOutcome.added,
        conflictingTitle = null,
        message = null;

  const RegistrationResult.invalidProject(String this.message)
      : outcome = RegistrationOutcome.invalidProject,
        conflictingTitle = null,
        teamCode = null;

  final RegistrationOutcome outcome;
  final String? conflictingTitle;
  final String? teamCode;
  final String? message;
}

/// User-facing text for the project/team outcomes the backend can return.
String? projectProblemMessage(String? outcome) => switch (outcome) {
      'team_not_found' || 'no_team' =>
        "That team doesn't exist anymore. Check the code with your teammate.",
      'team_wrong_session' => 'That team code is for a different session.',
      'team_full' => 'That team is already full.',
      'teams_not_allowed' => "This session is solo only — teams aren't allowed.",
      'removed_from_team' =>
        "That team's owner removed you from it, so you can't rejoin it.",
      'project_name_required' => 'Please enter your project name.',
      'choose_new_owner' =>
        'You own this team. Choose a teammate to take over before you leave.',
      'invalid_new_owner' =>
        "That person isn't on your team anymore. Pick someone else.",
      _ => null,
    };

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

  /// Admin-only (enforced by the backend).
  Future<void> deleteSession(String id);

  /// How many people registered for [sessionId] would have a schedule clash if
  /// the session ran at [start]–[end] (`HH:mm`) — i.e. they're also registered
  /// for another session overlapping that window. Used to warn an admin before
  /// they save a time change. Best-effort: returns 0 if the check is unavailable.
  Future<int> previewTimeConflicts(String sessionId, String start, String end);

  /// Posts a personal "the session moved and now clashes" announcement (+ banner)
  /// to everyone whose schedule the just-saved time change conflicts with.
  /// Best-effort — called after a successful save; a failure never blocks it.
  Future<void> notifyTimeConflicts(String sessionId);
}

/// The signed-in user's personal schedule.
abstract interface class ScheduleRepository {
  /// The current user's registrations: session id → how they joined.
  Future<Map<String, ParticipationType>> fetchMyRegistrations();

  /// Toggles a session in the schedule, enforcing capacity + no-overlap. On the
  /// ADD branch, records [type] and (for participants) [answers] to the session's
  /// questions plus their [project] (solo / create team / join team); all are
  /// ignored when the call toggles a registration OFF. When a team owner with
  /// teammates unregisters, [newOwnerId] names the teammate taking over.
  Future<RegistrationResult> toggle(
    String sessionId, {
    ParticipationType type = ParticipationType.participant,
    Map<String, String> answers = const {},
    ProjectChoice? project,
    String? newOwnerId,
  });

  /// The current user's saved answers to [sessionId]'s questions (question id →
  /// answer). Empty if they aren't registered or answered nothing.
  Future<Map<String, String>> fetchMyAnswers(String sessionId);

  /// The current user's project for [sessionId], or null if they aren't
  /// registered or haven't answered the project question yet.
  Future<MyProject?> fetchMyProject(String sessionId);

  /// Looks up a team code for [sessionId] so the user can confirm its project
  /// name before joining.
  Future<TeamLookup> findTeam(String sessionId, String code);

  /// Replaces the current participant's answers and project for a session
  /// they're registered for, returning the updated project. A team owner with
  /// teammates who leaves their team passes [newOwnerId]. Throws
  /// [TeamCodeException] if the project/team can't be used (or a new owner is
  /// needed), or a [StateError] if they aren't registered as a participant.
  Future<MyProject> updateMyRegistration(
    String sessionId, {
    required Map<String, String> answers,
    required ProjectChoice project,
    String? newOwnerId,
  });

  /// Hands the caller's team in [sessionId] to teammate [newOwnerId]. Owner
  /// only; throws [TeamCodeException] if it's refused.
  Future<void> transferTeamOwnership(String sessionId, String newOwnerId);

  /// Takes [userId] off the caller's team in [sessionId] (owner only). They
  /// stay registered for the session with no project answer, and are notified.
  /// Throws [TeamCodeException] if it's refused.
  Future<void> removeTeamMember(String sessionId, String userId);
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

  /// The volunteer hub: every other onboarded volunteer and admin with their
  /// role, subtype and mobile number, so the team can reach each other on
  /// summit day. Readable by volunteers and admins only (enforced
  /// server-side).
  Future<List<VolunteerRef>> fetchVolunteerHub();

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

  /// Admin self-manage: adds ([manage] true) or removes ([manage] false) the
  /// calling admin as a manager of [sessionId]. Overlap-guarded like [assign];
  /// returns [AssignmentOutcome.conflict] (with the clashing title) if managing
  /// would overlap something already on the admin's schedule. Admin-only,
  /// enforced server-side.
  Future<AssignmentResult> setManage(String sessionId, bool manage);
}

/// Attendance: per-session rosters (for session-assigned volunteers) and the
/// summit-wide front-desk directory (for front-desk-capable volunteers). Every
/// method is gated server-side.
abstract interface class AttendanceRepository {
  /// The registered participants of [sessionId] + their attendance state and
  /// project/team. Readable by the session's attendance takers and its editors.
  Future<List<RosterEntry>> fetchSessionRoster(String sessionId);

  Future<void> markSessionAttendance(
      String sessionId, String userId, bool attended);

  /// All attendees + their arrival state, optionally filtered by [query].
  Future<List<Attendee>> fetchAttendeeDirectory([String query]);

  Future<void> markSummitCheckin(String attendeeId, bool present);
}

// ---- Archie (AI assistant) --------------------------------------------------

/// One turn of the visible Archie conversation, resent with each question so
/// the assistant has the context (the server keeps no chat state).
class ArchieTurn {
  const ArchieTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

/// A web page Archie read or cited while answering.
class ArchieSource {
  const ArchieSource({required this.title, required this.url});

  final String title;
  final String url;
}

/// One event in a streamed Archie answer, in arrival order.
sealed class ArchieEvent {
  const ArchieEvent();
}

/// A progress step, e.g. "Searching the web for …". Shown above the answer.
class ArchieStatus extends ArchieEvent {
  const ArchieStatus(this.text);
  final String text;
}

/// The next fragment of answer text (markdown); append in order.
class ArchieDelta extends ArchieEvent {
  const ArchieDelta(this.text);
  final String text;
}

/// The web sources the finished answer drew on.
class ArchieSources extends ArchieEvent {
  const ArchieSources(this.sources);
  final List<ArchieSource> sources;
}

/// The answer failed; [message] is user-facing.
class ArchieFailure extends ArchieEvent {
  const ArchieFailure(this.message);
  final String message;
}

/// Questions allowed per Archie chat before the user must start a new one.
/// Mirrors the server-side limits (archie_history_setup.sql + archie-chat).
const int kArchieMaxQuestionsPerChat = 15;

/// Saved Archie chats kept per account; starting one more drops the oldest.
const int kArchieMaxSavedChats = 10;

/// A saved Archie chat, for the history list.
class ArchieChatSummary {
  const ArchieChatSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
}

/// One saved message in an Archie chat.
class ArchieSavedMessage {
  const ArchieSavedMessage({
    required this.fromUser,
    required this.text,
    this.sources = const [],
    this.steps = const [],
  });

  final bool fromUser;
  final String text;
  final List<ArchieSource> sources;
  final List<String> steps;
}

/// An anonymous question → answer pair, for the organizers' insights view.
class ArchieExchange {
  const ArchieExchange({
    required this.question,
    required this.answer,
    required this.sourceCount,
    required this.askedAt,
  });

  final String question;
  final String answer;
  final int sourceCount;
  final DateTime askedAt;
}

/// A saved chat's title: its first question on one line, capped at 80 chars.
String archieChatTitle(String question) {
  final oneLine = question.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length <= 80 ? oneLine : '${oneLine.substring(0, 79)}…';
}

/// The chat already has [kArchieMaxQuestionsPerChat] questions.
class ArchieChatFullException implements Exception {
  const ArchieChatFullException();
}

/// Archie, the in-app assistant.
abstract interface class ArchieRepository {
  /// Streams the answer to the last user turn in [transcript]; the stream
  /// closes when the answer is complete. Cancelling the subscription stops
  /// generation.
  Stream<ArchieEvent> ask(List<ArchieTurn> transcript);

  /// The signed-in user's saved chats, most recently used first.
  Future<List<ArchieChatSummary>> listChats();

  /// Every message of one of the user's chats, in order.
  Future<List<ArchieSavedMessage>> loadChat(String chatId);

  /// Saves a finished question + answer. Starts a new chat (titled from the
  /// question) when [chatId] is null — which may drop the user's oldest chat.
  /// Returns the chat's id. Throws [ArchieChatFullException] when the chat is
  /// at its question limit.
  Future<String> saveExchange({
    String? chatId,
    required String question,
    required ArchieSavedMessage answer,
  });

  Future<void> deleteChat(String chatId);

  /// Admin only: recent question → answer pairs across all users, with no
  /// user identity attached. Newest first.
  Future<List<ArchieExchange>> recentExchanges({int limit = 100});
}
