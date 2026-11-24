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

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/metrics.dart';
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
    this.conflictKind = ConflictKind.registered,
  ])  : teamCode = null,
        message = null;

  const RegistrationResult.added({this.teamCode})
      : outcome = RegistrationOutcome.added,
        conflictingTitle = null,
        conflictKind = ConflictKind.registered,
        message = null;

  const RegistrationResult.invalidProject(String this.message)
      : outcome = RegistrationOutcome.invalidProject,
        conflictingTitle = null,
        conflictKind = ConflictKind.registered,
        teamCode = null;

  final RegistrationOutcome outcome;
  final String? conflictingTitle;

  /// For a conflict: what the session clashes with.
  final ConflictKind conflictKind;
  final String? teamCode;
  final String? message;
}

/// User-facing text for the project/team outcomes the backend can return.
String? projectProblemMessage(String? outcome) => switch (outcome) {
      'team_not_found' || 'no_team' =>
        "That team doesn't exist anymore. Check the code with your teammate.",
      'team_wrong_session' => 'That team code is for a different session.',
      'team_full' => 'That team is already full.',
      'teams_not_allowed' => "This session is solo only. Teams are not allowed.",
      'removed_from_team' =>
        "That team's owner removed you from it, so you can't rejoin it.",
      'project_name_required' => 'Please enter your project name.',
      'choose_new_owner' =>
        'You own this team. Choose a teammate to take over before you leave.',
      'invalid_new_owner' =>
        "That person isn't on your team anymore. Pick someone else.",
      'expert_not_approved' =>
        'Only approved expert accounts can serve as an expert.',
      _ => null,
    };

/// Shown while `website_registration_open` is off and the server refuses a
/// new sign-up with `registration_closed`. Same words as the website.
const registrationClosedMessage = 'Registration will open on November 21st';

/// User-facing text for a sign-up the server refused with an error (rather
/// than an outcome), matched by the error code in [error]. Null when [error]
/// isn't one of them.
String? registrationRefusalMessage(String error) {
  if (error.contains('removed_from_team')) {
    return projectProblemMessage('removed_from_team');
  }
  if (error.contains('registration_closed')) return registrationClosedMessage;
  if (error.contains('eighth_grade_not_allowed')) {
    return "This session isn't open to 8th graders for participating. You "
        'can still add it as a spectator.';
  }
  if (error.contains('middle_school_not_allowed')) {
    return 'Participating is for high schoolers, and 8th graders in some '
        'sessions. You can still add this session as a spectator.';
  }
  if (error.contains('removed_from_session')) {
    return "An organizer removed you from this session, so you can't sign up "
        'for it again. If you think this was a mistake, contact the Summit '
        'team.';
  }
  return null;
}

/// Outcome of an admin assigning a volunteer to a session. [conflict] mirrors
/// the server-side overlap guard (the volunteer is already committed to an
/// overlapping session or personal registration).
enum AssignmentOutcome { assigned, conflict, registeredConfirm }

/// Result of a volunteer→session assignment. [conflictingTitle] is set only for
/// [AssignmentOutcome.conflict].
class AssignmentResult {
  const AssignmentResult(
    this.outcome, [
    this.conflictingTitle,
    this.conflictKind = ConflictKind.registered,
  ]);

  final AssignmentOutcome outcome;
  final String? conflictingTitle;

  /// For a conflict: what the session clashes with.
  final ConflictKind conflictKind;
}

/// What a time conflict is with (the backend's `conflict_kind`).
enum ConflictKind {
  /// Another session the person is signed up for.
  registered,

  /// Another session the person manages.
  managing,

  /// This same session: they manage it, so they can't also sign up for it.
  managingThis,

  /// This same session: they're signed up for it, so they can't manage it.
  registeredThis,
}

ConflictKind conflictKindFrom(Object? raw) => switch (raw) {
      'managing' => ConflictKind.managing,
      'managing_this' => ConflictKind.managingThis,
      'registered_this' => ConflictKind.registeredThis,
      _ => ConflictKind.registered,
    };

/// A newly-posted announcement delivered over a live feed. Backends without
/// realtime simply never emit these.
class AnnouncementEvent {
  const AnnouncementEvent({
    required this.id,
    required this.title,
    required this.body,
    this.createdBy,
    this.author = '',
    this.audience = '',
    this.disciplineId,
    this.targetUserId,
    this.deleted = false,
    this.announcement,
  });

  /// The whole row as a feed item, when the live message carried all of it,
  /// so the app can add it without reloading the feed. Null on deletions and
  /// when Realtime cut the row short (very long posts); the app reloads then.
  final Announcement? announcement;

  final String id;
  final String title;
  final String body;

  /// Display name of the poster and the audience label (e.g. a discipline
  /// name), so an admin's banner can say who sent it where.
  final String author;
  final String audience;

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
  /// Map keys: discipline_id, title, room, start_time,
  /// end_time, capacity, description.
  /// Throws [SessionWriteDeniedException] when the backend refuses the caller.
  Future<void> createSession(Map<String, dynamic> data);

  /// Throws [SessionWriteDeniedException] when the backend refuses the caller.
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
  /// [add] pins the direction: true only adds (already in → `added`, nothing
  /// changes), false only removes (already out → `removed`). Null toggles.
  Future<RegistrationResult> toggle(
    String sessionId, {
    ParticipationType type = ParticipationType.participant,
    Map<String, String> answers = const {},
    ProjectChoice? project,
    String? newOwnerId,
    bool? add,
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

/// An expert account waiting for an admin's approval.
class ExpertRequest {
  const ExpertRequest({
    required this.userId,
    required this.fullName,
    required this.email,
    this.expertise,
    this.bio,
    this.phone,
    this.requestedAt,
  });

  final String userId;
  final String fullName;
  final String email;
  final String? expertise;
  final String? bio;
  final String? phone;
  final DateTime? requestedAt;

  factory ExpertRequest.fromMap(Map<String, dynamic> row) => ExpertRequest(
        userId: row['user_id'] as String,
        fullName: (row['full_name'] ?? '') as String,
        email: (row['email'] ?? '') as String,
        expertise: row['expertise'] as String?,
        bio: row['bio'] as String?,
        phone: row['phone'] as String?,
        requestedAt: row['requested_at'] == null
            ? null
            : DateTime.parse(row['requested_at'] as String).toLocal(),
      );
}

/// Expert approval and the experts shown on a session page. The backend
/// enforces who may do what (see `supabase/expert_approval.sql`).
abstract interface class ExpertsRepository {
  /// Names of the approved experts registered for [sessionId].
  Future<List<String>> fetchSessionExperts(String sessionId);

  /// Admin only: expert accounts waiting for approval, oldest first.
  Future<List<ExpertRequest>> fetchRequests();

  /// Admin only: approves or declines [userId]. Returns false when there was
  /// nothing to review (another admin got there first, or the person picked a
  /// different role).
  Future<bool> review(String userId, {required bool approve});

  /// Clears the signed-in user's "your expert request was declined" note.
  Future<void> acknowledgeDecline();
}

/// What a role change does to one of the person's sessions
/// (`preview_role_change`). Moving to a role that can't participate, serve as
/// an expert or manage moves that session down to spectating.
class RoleChangeItem {
  const RoleChangeItem({
    required this.sessionId,
    required this.title,
    required this.from,
    required this.to,
    this.team,
  });

  final String sessionId;
  final String title;

  /// `participant`, `expert` or `managing`.
  final String from;

  /// `spectator`; `dropped` (managing a full session: removed from the day);
  /// or `unchanged` (they were also registered, so only the managing ends).
  final String to;

  /// What happens to their team, if they were on one.
  final RoleChangeTeam? team;

  factory RoleChangeItem.fromMap(Map<String, dynamic> m) => RoleChangeItem(
        sessionId: m['session_id'] as String,
        title: (m['title'] ?? '') as String,
        from: (m['from'] ?? '') as String,
        to: (m['to'] ?? 'spectator') as String,
        team: m['team'] == null
            ? null
            : RoleChangeTeam.fromMap((m['team'] as Map).cast()),
      );
}

/// The team side of a [RoleChangeItem].
class RoleChangeTeam {
  const RoleChangeTeam({
    required this.action,
    required this.projectName,
    this.toName,
    this.code,
  });

  /// `handed_off` (to [toName]), `deleted` (nobody else on it; [code] stops
  /// working) or `left`.
  final String action;
  final String projectName;
  final String? toName;
  final String? code;

  factory RoleChangeTeam.fromMap(Map<String, dynamic> m) => RoleChangeTeam(
        action: (m['action'] ?? 'left') as String,
        projectName: (m['project_name'] ?? '') as String,
        toName: m['to_name'] as String?,
        code: m['code'] as String?,
      );
}

/// The signed-in user's own profile row.
abstract interface class ProfileRepository {
  /// Loads the current user's profile, or null if nobody is signed in.
  Future<UserProfile?> fetchMine();

  /// Inserts or updates the user's profile.
  Future<void> save(UserProfile profile);

  /// Updates just the given fields on the current user's row.
  Future<void> patch(Map<String, dynamic> fields);

  /// What switching to [role] would do to the user's sessions. Nothing is
  /// changed; the database applies the same rules when the role is saved.
  Future<List<RoleChangeItem>> previewRoleChange(SummitRole role);

  /// Records that the signed-in account agreed to agreement [version], with
  /// its photo permission answer when the agreement asks one.
  Future<void> agreeToCodeOfConduct(String version, {bool? photoConsent});
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
    List<AnnouncementAttachment> attachments,
  });

  /// Uploads one photo/file to send with an announcement (the caller then
  /// passes the result to [create]). Only admins and volunteers who may post
  /// announcements can upload (enforced by the backend). Throws on failure.
  Future<AnnouncementAttachment> uploadAttachment(
      Uint8List bytes, String fileName);

  /// Removes uploaded attachments, e.g. when posting fails after the upload.
  /// Best-effort — never throws.
  Future<void> deleteAttachments(Iterable<AnnouncementAttachment> attachments);

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

/// The bell's Notifications list (`notifications_setup.sql`): short notes about
/// the signed-in person, written by the backend. Separate from News.
abstract interface class NotificationsRepository {
  /// The signed-in person's notes, newest first (at most [limit]). Empty when
  /// signed out. Throws on a failed read so the screen can offer a retry.
  Future<List<AppNotification>> fetch({int limit = 100});

  /// Marks [ids] read, or every unread note when [ids] is null ("Mark all as
  /// read"). Best-effort: never throws.
  Future<void> markRead([Iterable<String>? ids]);

  /// Asks the backend to add "starts within the hour" reminders for the
  /// signed-in person's sessions. Does nothing until the summit date is set.
  /// Best-effort: never throws.
  Future<void> queueMyReminders();

  /// Fires whenever one of the signed-in person's notes is added or changed,
  /// so the list can reload. A backend without realtime never fires.
  Stream<void> get changes;

  /// Tears down the live subscription (e.g. on sign-out). No-op if none.
  Future<void> stopChanges();
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

  /// Admin only: what assigning [userId] to manage [sessionId] would take off
  /// their day (volunteer_conflict_override.sql). Null when the backend
  /// doesn't have it yet, so callers keep the old refusal.
  Future<List<ReplacedItem>?> previewManagerAssignment(
      String sessionId, String userId);

  /// Admin only: makes [userId] a manager of [sessionId], removing their
  /// sign-up for it and anything that overlaps it, and tells them. Pass your
  /// own id to manage it yourself. Returns what was replaced.
  Future<List<ReplacedItem>> assignManagerReplacingConflicts(
      String sessionId, String userId);
}

/// What one item a manager assignment replaces is.
enum ReplacedKind {
  /// Signed up for this same session; they'll manage it instead.
  registeredThis,

  /// Signed up for an overlapping session.
  registered,

  /// Manages an overlapping session.
  managing,
}

/// One thing taken off someone's day when they're made a session's manager.
class ReplacedItem {
  const ReplacedItem({
    required this.sessionId,
    required this.title,
    required this.kind,
    this.participationType,
    this.teamName,
    this.teamOwner = false,
    this.teammates = 0,
  });

  factory ReplacedItem.fromMap(Map<String, dynamic> m) => ReplacedItem(
        sessionId: m['session_id'].toString(),
        title: switch (m['title']) {
          final String t when t.isNotEmpty => t,
          _ => 'a session',
        },
        kind: switch (m['kind']) {
          'registered_this' => ReplacedKind.registeredThis,
          'managing' => ReplacedKind.managing,
          _ => ReplacedKind.registered,
        },
        participationType: switch (m['participation_type']) {
          'participant' => ParticipationType.participant,
          'spectator' => ParticipationType.spectator,
          'expert' => ParticipationType.expert,
          _ => null,
        },
        teamName: switch (m['team_name']) {
          final String t when t.isNotEmpty => t,
          _ => null,
        },
        teamOwner: m['team_owner'] == true,
        teammates: (m['teammates'] as num?)?.toInt() ?? 0,
      );

  static List<ReplacedItem> listFrom(Object? raw) => [
        if (raw is List)
          for (final r in raw)
            ReplacedItem.fromMap((r as Map).cast<String, dynamic>()),
      ];

  final String sessionId;
  final String title;
  final ReplacedKind kind;
  final ParticipationType? participationType;
  final String? teamName;
  final bool teamOwner;

  /// Others on the team.
  final int teammates;
}

String _doing(ParticipationType? t) => switch (t) {
      ParticipationType.spectator => 'spectate',
      ParticipationType.expert => 'serve as an expert',
      _ => 'participate',
    };

/// One line of the replace dialog, about someone else ([self] false) or the
/// admin themselves. Same wording as the website's `describeReplacement`.
String describeReplacement(ReplacedItem item, {required bool self}) {
  final doing = _doing(item.participationType);
  final line = switch (item.kind) {
    ReplacedKind.managing => '"${item.title}", which '
        '${self ? 'you manage' : 'they manage'}. '
        "${self ? 'You' : 'They'}'ll stop managing it.",
    ReplacedKind.registeredThis =>
      '${self ? 'Your' : 'Their'} sign-up to $doing in this session. '
          "${self ? "You'll" : "They'll"} manage it instead.",
    ReplacedKind.registered => '"${item.title}", where '
        "${self ? "you're" : "they're"} signed up to $doing.",
  };
  final team = describeTeamEffect(item, self: self);
  return team == null ? line : '$line $team';
}

/// What leaving a sign-up does to its team, or null when it has none.
String? describeTeamEffect(ReplacedItem item, {required bool self}) {
  final name = item.teamName;
  if (name == null) return null;
  if (item.teammates == 0) {
    return '${self ? 'Your' : 'Their'} team "$name" has no one else, so '
        "it's deleted.";
  }
  if (item.teamOwner) {
    return '${self ? 'You own' : 'They own'} "$name"; it passes to the '
        'teammate who joined first.';
  }
  return '${self ? 'Your' : 'Their'} teammates on "$name" are told.';
}

/// The signed-in volunteer's or admin's own manual hour logs. Rows are scoped
/// to the owner, and only volunteers and admins may add or edit (enforced
/// server-side).
abstract interface class VolunteerHoursRepository {
  /// The caller's logs, newest first.
  Future<List<VolunteerHourLog>> fetchMine();

  Future<void> add(DateTime startedAt, DateTime endedAt, String description);

  Future<void> update(
    String id,
    DateTime startedAt,
    DateTime endedAt,
    String description,
  );

  Future<void> delete(String id);
}

/// The summit date and the post-summit follow-ups: expert feedback and the
/// volunteers' "volunteer for EAF again?" answer. Writes are role-checked and
/// only accepted once feedback is open (enforced server-side).
abstract interface class SummitRepository {
  Future<SummitStatus> fetchStatus();

  /// The signed-in expert's saved feedback (empty if none yet).
  Future<List<ExpertFeedback>> fetchMyFeedback();

  /// Saves the expert's feedback, replacing earlier answers for the same
  /// app / summit / session.
  Future<void> submitFeedback(List<ExpertFeedback> items);

  /// The signed-in volunteer's or admin's answer, or null if not answered.
  Future<bool?> fetchMyEafInterest();

  Future<void> setEafInterest(bool yes);
}

/// What `remove_session_registration` did.
enum SessionRemovalOutcome { removed, notRegistered, cannotRemoveSelf }

/// One person an organizer removed from a session
/// (`fetch_session_removals`).
class SessionRemoval {
  const SessionRemoval({
    required this.userId,
    required this.name,
    required this.email,
    this.participationType,
    this.removedBy,
    this.removedAt,
  });

  factory SessionRemoval.fromMap(Map<String, dynamic> m) => SessionRemoval(
        userId: m['user_id'].toString(),
        name: (m['full_name'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        participationType: switch (m['participation_type']) {
          'participant' => ParticipationType.participant,
          'spectator' => ParticipationType.spectator,
          'expert' => ParticipationType.expert,
          _ => null,
        },
        removedBy: m['removed_by_name'] as String?,
        removedAt: switch (m['removed_at']) {
          final String t => DateTime.tryParse(t)?.toLocal(),
          _ => null,
        },
      );

  final String userId;
  final String name;
  final String email;
  final ParticipationType? participationType;
  final String? removedBy;
  final DateTime? removedAt;
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

  /// Takes [userId] off [sessionId] (session_participant_removal.sql): deletes
  /// their registration, blocks them from signing up for it again and sends
  /// them a notice. Open to everyone who can see the roster.
  Future<SessionRemovalOutcome> removeFromSession(
      String sessionId, String userId);

  /// Lifts the block from [removeFromSession]; it doesn't re-register them.
  Future<void> allowBackToSession(String sessionId, String userId);

  /// Who was removed from [sessionId], newest first. Throws when the backend
  /// doesn't have removals yet (the SQL not run), so the roster can hide them.
  Future<List<SessionRemoval>> fetchSessionRemovals(String sessionId);

  /// All attendees + their arrival state, optionally filtered by [query].
  Future<List<Attendee>> fetchAttendeeDirectory([String query]);

  Future<void> markSummitCheckin(String attendeeId, bool present);

  /// Checks in the owner of a scanned QR pass. Never un-checks anyone: an
  /// attendee who already arrived comes back as
  /// [ScanCheckinOutcome.alreadyCheckedIn] with their original time.
  Future<ScanCheckinResult> scanSummitCheckin(String attendeeId);

  /// The signed-in user's own front-desk status (for their QR pass).
  Future<MyCheckinStatus> fetchMyCheckin();

  /// Summit-wide check-in counts per role (front-desk only).
  Future<CheckinStats> fetchCheckinStats();

  /// Emits whenever anyone, on any device, checks an attendee in or out, so
  /// every front-desk screen stays in sync. Listening opens the realtime
  /// subscription; cancelling closes it. Best-effort: may never emit offline.
  Stream<void> checkinChanges();
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

/// The caller may not create/edit sessions in that discipline (RLS refused
/// it). Any other save failure surfaces as the backend's own error.
class SessionWriteDeniedException implements Exception {
  const SessionWriteDeniedException();
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

/// Summit-wide counts for the admin Metrics screen. Per-session metrics come
/// from [AttendanceRepository.fetchSessionRoster] instead, which already
/// carries each registrant's school and grade.
abstract interface class MetricsRepository {
  /// Every onboarded account (role, school, grade; no names) and every
  /// registration. Admins only; anyone else gets an error.
  Future<SummitMetrics> fetchSummitMetrics();

  /// Every onboarded non-expert account with its Code of Conduct photo
  /// permission answer (photo_permission_list.sql). Admins only.
  Future<List<PhotoPermission>> fetchPhotoPermissions();
}

/// One account's answer to the Code of Conduct's "Media Rights and Consent"
/// question.
class PhotoPermission {
  const PhotoPermission({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    this.school,
    this.granted,
    this.agreedAt,
  });

  factory PhotoPermission.fromMap(Map<String, dynamic> m) => PhotoPermission(
        userId: m['user_id'].toString(),
        name: (m['full_name'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        role: SummitRoleX.fromId(m['role'] as String?),
        school: switch ((m['school'] as String?)?.trim()) {
          final String s when s.isNotEmpty => s,
          _ => null,
        },
        granted: m['photo_consent'] as bool?,
        agreedAt: switch (m['agreed_at']) {
          final String t => DateTime.tryParse(t)?.toLocal(),
          _ => null,
        },
      );

  final String userId;
  final String name;
  final String email;
  final SummitRole role;
  final String? school;

  /// True: granted. False: did not grant. Null: has not answered yet.
  final bool? granted;
  final DateTime? agreedAt;
}

// ---- Bug reports and feedback ---------------------------------------------

/// The two ticket categories (`bug_reports.kind`).
enum ReportKind {
  bug,
  feedback;

  /// "Bug" / "Feedback", as in "Bug #12".
  String get ticketLabel => this == bug ? 'Bug' : 'Feedback';
}

/// One screenshot picked for a report.
class ReportScreenshot {
  const ReportScreenshot({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  final Uint8List bytes;
  final String mimeType;
  final String name;
}

/// What the person filled in, plus [client] (the app's diagnostics).
class BugReportInput {
  const BugReportInput({
    required this.kind,
    required this.name,
    required this.description,
    required this.screenshots,
    required this.emailCopy,
    required this.client,
  });

  final ReportKind kind;
  final String name;
  final String description;
  final List<ReportScreenshot> screenshots;
  final bool emailCopy;
  final Map<String, Object?> client;
}

/// A sent report's ticket number, and whether the emailed copy went
/// (null when no copy was asked for).
class ReportSubmitResult {
  const ReportSubmitResult({required this.ticketNo, this.emailed});
  final int ticketNo;
  final bool? emailed;
}

/// One `bug_reports` row, for the admins' list.
class BugReport {
  const BugReport({
    required this.id,
    required this.ticketNo,
    required this.kind,
    required this.reporterName,
    required this.description,
    required this.screenshots,
    required this.client,
    required this.snapshot,
    required this.resolved,
    required this.createdAt,
    this.emailError,
  });

  factory BugReport.fromMap(Map<String, dynamic> m) => BugReport(
        id: m['id'].toString(),
        ticketNo: (m['ticket_no'] as num?)?.toInt() ?? 0,
        kind: m['kind'] == 'feedback' ? ReportKind.feedback : ReportKind.bug,
        reporterName: (m['reporter_name'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        screenshots: [
          for (final s in (m['screenshots'] as List?) ?? const []) '$s',
        ],
        client: (m['client'] as Map?)?.cast<String, dynamic>() ?? const {},
        snapshot: (m['snapshot'] as Map?)?.cast<String, dynamic>() ?? const {},
        resolved: m['status'] == 'resolved',
        createdAt:
            DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
        emailError: m['email_error'] as String?,
      );

  final String id;
  final int ticketNo;
  final ReportKind kind;
  final String reporterName;
  final String description;
  final List<String> screenshots;
  final Map<String, dynamic> client;
  final Map<String, dynamic> snapshot;
  final bool resolved;
  final DateTime createdAt;
  final String? emailError;

  BugReport withResolved(bool value) => BugReport(
        id: id,
        ticketNo: ticketNo,
        kind: kind,
        reporterName: reporterName,
        description: description,
        screenshots: screenshots,
        client: client,
        snapshot: snapshot,
        resolved: value,
        createdAt: createdAt,
        emailError: emailError,
      );
}

/// Bug reports and feedback (bug_reports_setup.sql and the bug-report-email
/// Edge Function).
abstract interface class BugReportsRepository {
  /// Uploads the screenshots, saves the report (the server adds its own
  /// snapshot of the account), then asks for the emails. A failed email
  /// doesn't fail the report.
  Future<ReportSubmitResult> submit(BugReportInput input);

  /// Every report, newest first (admins; anyone else gets their own).
  Future<List<BugReport>> fetchAll();

  /// Admins: marks a report open or resolved.
  Future<void> setResolved(String id, bool resolved);

  /// Short-lived links to a report's screenshots.
  Future<List<String>> screenshotUrls(List<String> paths);
}

const maxReportScreenshots = 5;
const maxScreenshotBytes = 10 * 1024 * 1024;
const maxReportDescription = 5000;
const maxReporterName = 120;
const reportScreenshotTypes = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/gif': 'gif',
};

/// The server's refusals, in words; anything else is a generic failure.
String reportErrorMessage(Object error) {
  final text = '$error';
  const refusals = {
    'not_signed_in': 'Please sign in again, then send the report.',
    'name_required': 'Please add your name.',
    'description_required': 'Please describe the bug or your feedback.',
    'too_long': 'That description is too long. Please shorten it.',
    'too_many_reports':
        "You've sent a lot of reports in the last hour. Please try again "
            'later.',
  };
  for (final e in refusals.entries) {
    if (text.contains(e.key)) return e.value;
  }
  return "We couldn't send your report. Please try again.";
}

/// The whole report as Markdown, for pasting to whoever fixes it: what the
/// person wrote, then everything attached, as JSON. Same layout as the
/// website's `reportAsMarkdown`.
String reportAsMarkdown(BugReport r, {List<String> links = const []}) {
  const encoder = JsonEncoder.withIndent('  ');
  final label = r.kind == ReportKind.feedback ? 'Feedback' : 'Bug report';
  return [
    '# $label #${r.ticketNo}',
    '',
    '- From: ${r.reporterName}',
    '- Sent: ${r.createdAt.toUtc().toIso8601String()}',
    '- Status: ${r.resolved ? 'resolved' : 'open'}',
    '',
    '## Description',
    '',
    r.description,
    if (links.isNotEmpty) ...[
      '',
      '## Screenshots',
      '',
      for (var i = 0; i < links.length; i++)
        '- [Screenshot ${i + 1}](${links[i]})',
    ],
    '',
    '## Device, pages and errors (from the app)',
    '',
    '```json',
    encoder.convert(r.client),
    '```',
    '',
    '## Account (from the server)',
    '',
    '```json',
    encoder.convert(r.snapshot),
    '```',
  ].join('\n');
}

/// A random (version 4) UUID, for a report's id.
String newUuid() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b
      .sublist(from, to)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
