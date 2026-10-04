import 'dart:convert';

import 'package:flutter/material.dart';

/// Maps a discipline's stored `icon` string (from the `disciplines` table) to a
/// Material [IconData]. We store a key rather than a Flutter object in the DB;
/// admins pick from these when creating a discipline. Unknown keys fall back to
/// a neutral icon so a new key never crashes the catalog.
IconData disciplineIcon(String key) => switch (key) {
      'terminal' => Icons.terminal,
      'precision_manufacturing' => Icons.precision_manufacturing,
      'biotech' => Icons.biotech,
      'rocket_launch' => Icons.rocket_launch,
      'palette' => Icons.palette,
      'functions' => Icons.functions,
      'science' => Icons.science,
      'public' => Icons.public,
      'psychology' => Icons.psychology,
      'music_note' => Icons.music_note,
      'engineering' => Icons.engineering,
      'calculate' => Icons.calculate,
      _ => Icons.category,
    };

/// One of the STEAM disciplines at the summit (spec section 04).
class Discipline {
  const Discipline({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    required this.sessions,
  });

  final String id;
  final String name;
  final String tagline;
  final IconData icon;
  final List<Session> sessions;

  /// Builds a [Discipline] from a `disciplines` row. Its [sessions] are fetched
  /// separately (they live in their own table) and passed in by the repository.
  factory Discipline.fromMap(
    Map<String, dynamic> row, {
    List<Session> sessions = const [],
  }) =>
      Discipline(
        id: row['id'].toString(),
        name: (row['name'] ?? '') as String,
        tagline: (row['tagline'] ?? '') as String,
        icon: disciplineIcon((row['icon'] ?? 'category') as String),
        sessions: sessions,
      );
}

/// One editor-authored content section on a session's "vibrant" page — a titled
/// block of body text. Sessions carry an ordered list of these in the
/// `page_blocks` jsonb column; anyone who can edit the session authors them.
class SessionPageBlock {
  const SessionPageBlock({required this.title, required this.body});

  final String title;
  final String body;

  factory SessionPageBlock.fromMap(Map<String, dynamic> map) => SessionPageBlock(
        title: (map['title'] ?? '') as String,
        body: (map['body'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {'title': title, 'body': body};

  /// Parses the raw `page_blocks` value (a jsonb list, which some backends hand
  /// back as a decoded [List] and others as a JSON [String]). Anything malformed
  /// yields an empty list so a bad row never crashes the catalog.
  static List<SessionPageBlock> parse(dynamic raw) {
    if (raw == null) return const [];
    List<dynamic> list;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        list = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        return const [];
      }
    } else if (raw is List) {
      list = raw;
    } else {
      return const [];
    }
    return [
      for (final e in list)
        if (e is Map) SessionPageBlock.fromMap(e.cast<String, dynamic>()),
    ];
  }
}

/// One admin/manager-authored question a participant must answer when they add a
/// session as a **participant** (e.g. "What is your project name?"). Sessions
/// carry an ordered list in the `participant_questions` jsonb column; answers are
/// stored on the registration keyed by [id], so editing a prompt's text never
/// orphans existing answers.
class SessionQuestion {
  const SessionQuestion({required this.id, required this.prompt});

  final String id;
  final String prompt;

  factory SessionQuestion.fromMap(Map<String, dynamic> map) => SessionQuestion(
        id: (map['id'] ?? '').toString(),
        prompt: (map['prompt'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {'id': id, 'prompt': prompt};

  /// Parses the raw `participant_questions` value (a jsonb list some backends
  /// hand back as a decoded [List] and others as a JSON [String]). Anything
  /// malformed, or an entry with a blank id/prompt, is dropped so a bad row never
  /// crashes the catalog.
  static List<SessionQuestion> parse(dynamic raw) {
    if (raw == null) return const [];
    List<dynamic> list;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        list = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        return const [];
      }
    } else if (raw is List) {
      list = raw;
    } else {
      return const [];
    }
    return [
      for (final e in list)
        if (e is Map)
          SessionQuestion.fromMap(e.cast<String, dynamic>())
    ].where((q) => q.id.isNotEmpty && q.prompt.trim().isNotEmpty).toList();
  }
}

/// The app's built-in registration questions, asked of EVERY participant on top
/// of a session's own [SessionQuestion]s. Session editors see them (read-only)
/// in the session editor.
abstract final class DefaultQuestions {
  static const soloOrTeam = 'Are you participating in a team, or solo?';
  static const projectName = 'What is your project name?';
  static const teamCode = "What's your team code?";
  static const unsureNote =
      "Not sure yet whether you'll have a team? Register as solo for now — you "
      'can always change your answer later from the session page.';
}

/// The two-letter prefix that starts every team code in a discipline (e.g.
/// TV4821 for TechVerse). Mirrors `team_code_prefix` in teams_setup.sql, which
/// is what actually issues codes — this is only for display.
String teamCodePrefix(String disciplineId, String disciplineName) {
  const pinned = {
    'techverse': 'TV',
    'ventureverse': 'VV',
    'biosphere': 'BS',
    'novasphere': 'NS',
    'civicverse': 'CV',
    'imaginex': 'IX',
  };
  final fixed = pinned[disciplineId];
  if (fixed != null) return fixed;
  final caps = disciplineName.replaceAll(RegExp('[^A-Z]'), '');
  if (caps.length >= 2) return caps.substring(0, 2);
  final letters = disciplineName.replaceAll(RegExp('[^A-Za-z]'), '');
  if (letters.isEmpty) return 'TM';
  return letters.substring(0, letters.length < 2 ? letters.length : 2)
      .toUpperCase()
      .padRight(2, 'X');
}

/// Cleans up a typed team code ("tv 4821" → "TV4821").
String normalizeTeamCode(String code) =>
    code.replaceAll(RegExp(r'\s'), '').toUpperCase();

/// What a participant chose for the built-in project question.
enum ProjectAction {
  /// Working alone; [ProjectChoice.projectName] is their project.
  solo,

  /// Starting a team; [ProjectChoice.projectName] names it and a code is issued.
  createTeam,

  /// Joining a teammate's team by [ProjectChoice.teamCode].
  joinTeam,

  /// (Editing only) staying on the current team, optionally renaming its
  /// project to [ProjectChoice.projectName].
  stayOnTeam,
}

/// A participant's answer to the built-in solo/team question, sent along with a
/// registration (or a later edit of it).
class ProjectChoice {
  const ProjectChoice.solo(String this.projectName)
      : action = ProjectAction.solo,
        teamCode = null;
  const ProjectChoice.createTeam(String this.projectName)
      : action = ProjectAction.createTeam,
        teamCode = null;
  const ProjectChoice.joinTeam(String this.teamCode)
      : action = ProjectAction.joinTeam,
        projectName = null;
  const ProjectChoice.stayOnTeam([this.projectName])
      : action = ProjectAction.stayOnTeam,
        teamCode = null;

  final ProjectAction action;
  final String? projectName;
  final String? teamCode;

  /// The `p_project_mode` value the backend RPCs take.
  String get modeId => switch (action) {
        ProjectAction.solo => 'solo',
        ProjectAction.createTeam => 'create',
        ProjectAction.joinTeam => 'join',
        ProjectAction.stayOnTeam => 'stay',
      };
}

/// The default team size limit for a session (editors can change it).
const int kDefaultMaxTeamSize = 4;

/// The largest team size limit an editor can choose.
const int kLargestTeamSizeLimit = 8;

/// The team size limit meaning "no teams allowed, only solos".
const int kSoloOnlyTeamSize = 1;

/// One person on a team, as their teammates see them.
class TeamMember {
  const TeamMember({required this.id, required this.name, this.isOwner = false});

  final String id;
  final String name;

  /// The team's owner — its creator until they hand it over.
  final bool isOwner;

  factory TeamMember.fromMap(Map<String, dynamic> map) => TeamMember(
        id: map['id'].toString(),
        name: (map['name'] ?? '') as String,
        isOwner: (map['is_owner'] ?? false) as bool,
      );
}

/// The signed-in participant's project for one session — what the session page
/// shows them (and the team code they share with teammates).
class MyProject {
  const MyProject({
    required this.isTeam,
    required this.projectName,
    this.teamCode,
    this.members = const [],
    this.isOwner = false,
    this.maxTeamSize = kDefaultMaxTeamSize,
  });

  /// True for a team project, false for solo.
  final bool isTeam;
  final String projectName;
  final String? teamCode;

  /// Everyone on the team (including the caller), in the order they joined.
  final List<TeamMember> members;

  /// True when the caller owns their team. An owner leaving a team that still
  /// has other members must pick a new owner first.
  final bool isOwner;

  /// The session's team size limit ([kSoloOnlyTeamSize] = solo only).
  final int maxTeamSize;

  /// False when the session is solo only.
  bool get teamsAllowed => maxTeamSize >= 2;

  /// The owner's display name, if known.
  String? get ownerName {
    for (final m in members) {
      if (m.isOwner) return m.name;
    }
    return null;
  }

  /// True when leaving would need a new owner: the caller owns a team that
  /// still has someone else on it.
  bool get mustHandOff => isTeam && isOwner && members.length > 1;

  bool get isFull => teamsAllowed && members.length >= maxTeamSize;

  /// Parses the `fetch_my_project` result. Null when the user isn't registered
  /// or registered before the team question existed (no answer yet).
  static MyProject? fromMap(Map<String, dynamic>? row) {
    if (row == null) return null;
    final mode = row['mode'] as String?;
    if (mode != 'solo' && mode != 'team') return null;
    final details = row['member_details'] as List?;
    return MyProject(
      isTeam: mode == 'team',
      projectName: (row['project_name'] ?? '') as String,
      teamCode: row['team_code'] as String?,
      isOwner: (row['is_owner'] ?? false) as bool,
      maxTeamSize:
          (row['max_team_size'] as num?)?.toInt() ?? kDefaultMaxTeamSize,
      // `member_details` arrives with the ownership migration; before it, only
      // names are available.
      members: details != null
          ? [
              for (final m in details)
                if (m is Map) TeamMember.fromMap(m.cast<String, dynamic>()),
            ]
          : [
              for (final m in (row['members'] as List?) ?? const [])
                TeamMember(id: '', name: '$m'),
            ],
    );
  }
}

/// Result of looking up a team code before joining.
enum TeamLookupOutcome {
  found,
  full,
  notFound,
  wrongSession,
  teamsNotAllowed,

  /// The team's owner removed the caller, so they can't rejoin it.
  removed,
}

class TeamLookup {
  const TeamLookup(
    this.outcome, {
    this.projectName,
    this.memberCount = 0,
    this.maxTeamSize = kDefaultMaxTeamSize,
    this.sessionTitle,
  });

  final TeamLookupOutcome outcome;

  /// The team's project, for the "Is your project name …?" confirmation.
  final String? projectName;
  final int memberCount;
  final int maxTeamSize;

  /// For [TeamLookupOutcome.wrongSession]: the session the code belongs to.
  final String? sessionTitle;

  /// The user-facing reason a code can't be used, or null when [found].
  String? get problem => switch (outcome) {
        TeamLookupOutcome.found => null,
        TeamLookupOutcome.full =>
          '"${projectName ?? 'That team'}" is full ($memberCount of '
              '$maxTeamSize members).',
        TeamLookupOutcome.removed =>
          "The owner of \"${projectName ?? 'that team'}\" removed you from "
              "it, so you can't rejoin with this code.",
        TeamLookupOutcome.teamsNotAllowed =>
          "This session is solo only — teams aren't allowed.",
        TeamLookupOutcome.notFound =>
          "We couldn't find a team with that code. Check it with your teammate.",
        TeamLookupOutcome.wrongSession => sessionTitle == null
            ? 'That code is for a different session.'
            : 'That code is for "$sessionTitle", not this session.',
      };
}

/// A team-code problem reported by the backend when saving a registration
/// (e.g. the team was deleted between lookup and save).
class TeamCodeException implements Exception {
  const TeamCodeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Splits a stored 24-hour `HH:mm` time into what the session editor shows:
/// the 12-hour clock text (`h:mm`) and whether it's PM. Tolerates a trailing
/// seconds part (`HH:mm:ss`).
(String, bool) to12HourTime(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return ('$h12:$m', h >= 12);
}

/// Converts a typed 12-hour time (`10:30`, `9`, `10:30 pm`) plus the AM/PM
/// choice into the 24-hour `HH:mm` the backend stores, or null when [input]
/// isn't a valid 12-hour time. An "am"/"pm" typed into [input] wins over [pm].
String? to24HourTime(String input, {required bool pm}) {
  final match = RegExp(
    r'^(\d{1,2})(?::([0-5]\d))?\s*(?:([ap])\.?\s*m?\.?)?$',
    caseSensitive: false,
  ).firstMatch(input.trim());
  if (match == null) return null;
  final h = int.parse(match[1]!);
  if (h < 1 || h > 12) return null;
  final m = match[2] ?? '00';
  final isPm = switch (match[3]?.toLowerCase()) {
    'a' => false,
    'p' => true,
    _ => pm,
  };
  final h24 = h % 12 + (isPm ? 12 : 0);
  return '${h24.toString().padLeft(2, '0')}:$m';
}

/// A date and time like "Fri, Jan 15 at 3:00 PM" (local time), adding the year
/// when it isn't the current one.
String formatDeadline(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final year = d.year == DateTime.now().year ? '' : ', ${d.year}';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final period = d.hour >= 12 ? 'PM' : 'AM';
  return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}$year '
      'at $h:$m $period';
}

/// A single session/activity a participant can add to their day plan.
class Session {
  const Session({
    required this.id,
    required this.disciplineId,
    required this.title,
    required this.disciplineName,
    required this.track,
    required this.room,
    this.roomId,
    required this.expertName,
    required this.start,
    required this.end,
    required this.capacity,
    required this.enrolled,
    required this.description,
    this.sponsor,
    this.heroImageUrl,
    this.pageBlocks = const [],
    this.participantQuestions = const [],
    this.maxTeamSize = kDefaultMaxTeamSize,
    this.customProjectPrompt,
    this.participantDeadline,
  });

  /// Builds a [Session] from a `sessions_with_counts` view row. The view carries
  /// the live `enrolled` count and the parent `discipline_name`, so capacity
  /// rules and the display name work without a second query.
  factory Session.fromMap(Map<String, dynamic> row) => Session(
        id: row['id'].toString(),
        disciplineId: (row['discipline_id'] ?? '').toString(),
        title: (row['title'] ?? '') as String,
        disciplineName: (row['discipline_name'] ?? '') as String,
        track: (row['track'] ?? '') as String,
        room: (row['room'] ?? '') as String,
        roomId: row['room_id']?.toString(),
        expertName: (row['expert_name'] ?? '') as String,
        start: (row['start_time'] ?? '00:00') as String,
        end: (row['end_time'] ?? '00:00') as String,
        capacity: (row['capacity'] ?? 0) as int,
        enrolled: (row['enrolled'] as num?)?.toInt() ?? 0,
        description: (row['description'] ?? '') as String,
        sponsor: row['sponsor'] as String?,
        heroImageUrl: (row['hero_image_url'] as String?)?.isEmpty ?? true
            ? null
            : row['hero_image_url'] as String?,
        pageBlocks: SessionPageBlock.parse(row['page_blocks']),
        participantQuestions:
            SessionQuestion.parse(row['participant_questions']),
        maxTeamSize:
            (row['max_team_size'] as num?)?.toInt() ?? kDefaultMaxTeamSize,
        customProjectPrompt: switch ((row['project_prompt'] as String?)?.trim()) {
          final String p when p.isNotEmpty => p,
          _ => null,
        },
        participantDeadline: switch (row['participant_deadline']) {
          final String d => DateTime.tryParse(d)?.toLocal(),
          _ => null,
        },
      );

  final String id;

  /// The parent discipline's id (from `sessions.discipline_id`). Drives edit
  /// permission on the detail page via [AppState.canManageDiscipline].
  final String disciplineId;
  final String title;
  final String disciplineName;
  final String track;
  final String room;

  /// The rooms-catalog id this session is tied to (nullable: "Unassigned").
  /// The display string is [room]; [roomId] is the structured link admins set.
  final String? roomId;
  final String expertName;
  final String start; // "HH:mm" 24h
  final String end; // "HH:mm" 24h
  final int capacity;
  final int enrolled;
  final String description;
  final String? sponsor;

  /// The session page's hero banner image (a public URL), or null when unset.
  final String? heroImageUrl;

  /// Ordered editor-authored content sections shown on the session page.
  final List<SessionPageBlock> pageBlocks;

  /// Ordered questions a participant must answer when adding this session as a
  /// participant (empty = no questions; participating registers directly).
  final List<SessionQuestion> participantQuestions;

  /// The most people one team may have in this session (set by its editors);
  /// [kSoloOnlyTeamSize] means no teams, only solos.
  final int maxTeamSize;

  /// False when the session is solo only.
  bool get teamsAllowed => maxTeamSize >= 2;

  /// The editors' wording for the built-in project question, or null for the
  /// default ([DefaultQuestions.projectName]).
  final String? customProjectPrompt;

  /// How the built-in project question reads for this session.
  String get projectPrompt =>
      customProjectPrompt ?? DefaultQuestions.projectName;

  /// When registering to participate closes (local time), or null for no
  /// deadline. After it, people can still spectate while seats are left.
  final DateTime? participantDeadline;

  /// True once the participant deadline has passed.
  bool get participationClosed {
    final deadline = participantDeadline;
    return deadline != null && !DateTime.now().isBefore(deadline);
  }

  bool get isFull => enrolled >= capacity;
  int get seatsLeft => capacity - enrolled;

  int get startMinutes => _toMinutes(start);
  int get endMinutes => _toMinutes(end);

  /// True if this session's time block overlaps [other]'s.
  bool overlaps(Session other) =>
      startMinutes < other.endMinutes && other.startMinutes < endMinutes;

  String get timeLabel => '${_display(start)} – ${_display(end)}';

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static String _display(String hhmm) {
    final parts = hhmm.split(':');
    var h = int.parse(parts[0]);
    final m = parts[1];
    final period = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:$m $period';
  }
}

/// Announcement feed item (spec section 04 — Announcements).
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.audience,
    required this.timeAgo,
    this.pinned = false,
    this.disciplineId,
    this.targetUserId,
  });

  final String id;
  final String title;
  final String body;
  final String author;
  final String audience;
  final String timeAgo;
  final bool pinned;

  /// When set, this announcement targets one discipline — it only reaches users
  /// who have an activity in that discipline (plus admins / its volunteers). Null
  /// means it goes to everyone.
  final String? disciplineId;

  /// When set, this is a PERSONAL announcement for one user (e.g. "you've been
  /// assigned to manage X") — shown only to that user, never in anyone else's
  /// feed. Null for normal broadcast/discipline announcements.
  final String? targetUserId;

  /// Builds an [Announcement] from a backend row (see the repository row
  /// contract). Columns map 1:1 except [timeAgo], derived from `created_at`.
  factory Announcement.fromMap(Map<String, dynamic> row) {
    return Announcement(
      id: row['id'].toString(),
      title: (row['title'] ?? '') as String,
      body: (row['body'] ?? '') as String,
      author: (row['author'] ?? 'Summit') as String,
      audience: (row['audience'] ?? 'Everyone') as String,
      pinned: (row['pinned'] ?? false) as bool,
      timeAgo: _relativeTime(row['created_at'] as String?),
      disciplineId: row['discipline_id'] as String?,
      targetUserId: row['target_user_id'] as String?,
    );
  }

  static String _relativeTime(String? iso) {
    if (iso == null) return '';
    final then = DateTime.tryParse(iso);
    if (then == null) return '';
    final diff = DateTime.now().difference(then);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// A photo shown in the app (e.g. the dashboard slideshow). The bytes live in a
/// public Supabase Storage bucket; every file in the bucket is a photo. The
/// repository lists the bucket and resolves each file to a public URL, so photos
/// are managed by uploading/deleting files — no build or table needed.
class GalleryPhoto {
  const GalleryPhoto({required this.id, required this.imageUrl});

  /// Stable identifier — the file name within its bucket.
  final String id;

  /// Fully-resolved, publicly-readable image URL. The repository turns a storage
  /// file into this before constructing the model, so app code (and the
  /// [Image.network] that loads it) stays backend-agnostic.
  final String imageUrl;
}

/// A document in the resources hub (spec section 04 — Resources hub).
class ResourceDoc {
  const ResourceDoc({
    required this.id,
    required this.title,
    required this.category,
    required this.icon,
  });

  final String id;
  final String title;
  final String category;
  final IconData icon;
}

/// How a person joined a session (stored on `registrations.participation_type`).
/// "Managing" is NOT one of these — it lives in `session_volunteers` — so a
/// schedule entry is either managing OR carries one of these.
enum ParticipationType { participant, spectator, expert }

extension ParticipationTypeX on ParticipationType {
  /// Value stored in the database.
  String get id => switch (this) {
        ParticipationType.participant => 'participant',
        ParticipationType.spectator => 'spectator',
        ParticipationType.expert => 'expert',
      };

  /// The short label for a schedule/roster chip.
  String get chipLabel => switch (this) {
        ParticipationType.participant => 'Participating',
        ParticipationType.spectator => 'Spectating',
        ParticipationType.expert => 'Expert',
      };

  /// First-person status line for the session page.
  String get statusLabel => switch (this) {
        ParticipationType.participant => "You're participating in this session.",
        ParticipationType.spectator => "You're spectating this session.",
        ParticipationType.expert => "You're serving as an expert here.",
      };

  /// Parses the stored id, defaulting to [ParticipationType.participant] for an
  /// unknown/absent value (matches the DB column default).
  static ParticipationType fromId(String? id) {
    for (final t in ParticipationType.values) {
      if (t.id == id) return t;
    }
    return ParticipationType.participant;
  }
}

/// One entry on a user's personal schedule: a [session] plus the role they play
/// in it — [managing] (assigned by an admin, or self-assigned by an admin, to
/// run it) or the [participationType] they registered under. Managing takes
/// precedence when both are true.
class ScheduleEntry {
  const ScheduleEntry({
    required this.session,
    required this.managing,
    this.participationType,
  });

  final Session session;
  final bool managing;

  /// How the user registered, when not [managing]. Null for a pure managing
  /// entry (they haven't also registered).
  final ParticipationType? participationType;

  String get roleLabel => managing
      ? 'Managing'
      : (participationType ?? ParticipationType.participant).chipLabel;
}

/// A room in the admin-managed catalog. Sessions are tied to one of these; the
/// session editor picks from them and volunteers are assigned to the sessions.
class Room {
  const Room({required this.id, required this.name, this.sortOrder = 0});

  final String id;
  final String name;
  final int sortOrder;

  factory Room.fromMap(Map<String, dynamic> row) => Room(
        id: row['id'].toString(),
        name: (row['name'] ?? '') as String,
        sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      );
}

/// A volunteer as seen by an admin (from `fetch_volunteers` /
/// `fetch_session_volunteers`) — for the assignment picker and assigned list.
class VolunteerRef {
  const VolunteerRef({
    required this.id,
    required this.name,
    required this.email,
    this.subtype,
    this.phone,
    this.role,
  });

  final String id;
  final String name;
  final String email;

  /// Stored subtype id (e.g. 'student_volunteer'), or null.
  final String? subtype;

  /// Mobile number from the volunteer's onboarding answers. Only the volunteer
  /// hub RPC returns it; null elsewhere or when they didn't give one.
  final String? phone;

  /// Account role id ('volunteer' / 'admin'). Only the volunteer hub RPC
  /// returns it, since that's the one list that mixes in admins.
  final String? role;

  bool get isAdmin => role == 'admin';

  /// `id` for the directory RPC, `user_id` for the session-volunteers RPC.
  factory VolunteerRef.fromMap(Map<String, dynamic> row) => VolunteerRef(
        id: (row['id'] ?? row['user_id']).toString(),
        name: (row['full_name'] ?? '') as String,
        email: (row['email'] ?? '') as String,
        subtype: row['subtype'] as String?,
        phone: row['phone'] as String?,
        role: row['role'] as String?,
      );
}

/// One participant on a session's roster (from `fetch_session_roster`), with the
/// attendance state a session-assigned volunteer can toggle.
class RosterEntry {
  const RosterEntry({
    required this.userId,
    required this.name,
    required this.email,
    required this.attended,
    this.participationType = ParticipationType.participant,
    this.answers = const {},
    this.isTeam,
    this.projectName,
    this.teamId,
    this.teamCode,
    this.isTeamOwner = false,
    this.role,
    this.details = const {},
  });

  final String userId;
  final String name;
  final String email;
  final bool attended;

  /// How this person joined the session (participant / spectator / expert).
  final ParticipationType participationType;

  /// The participant's answers to the session's questions, keyed by question id.
  /// Empty for spectators/experts and for sessions with no questions.
  final Map<String, String> answers;

  /// True for a team project, false for solo, null when the participant hasn't
  /// answered the project question (spectators, experts, older registrations).
  final bool? isTeam;

  /// Their project's name (the team's, for a team member).
  final String? projectName;

  /// The team they're on — teammates share it, which is how the roster groups
  /// them. Null for solo participants.
  final String? teamId;
  final String? teamCode;

  /// True for the owner of their team.
  final bool isTeamOwner;

  /// Their account role id (`profiles.role`, e.g. "expert"), for the profile
  /// sheet organizers open from the roster. Null from older backends.
  final String? role;

  /// Their onboarding answers (`profiles.details`: school, grade, phone, bio…),
  /// keyed like [ProfileField.key]. Empty from older backends.
  final Map<String, String> details;

  factory RosterEntry.fromMap(Map<String, dynamic> row) {
    final mode = row['project_mode'] as String?;
    return RosterEntry(
      userId: row['user_id'].toString(),
      name: (row['full_name'] ?? '') as String,
      email: (row['email'] ?? '') as String,
      attended: (row['attended'] ?? false) as bool,
      participationType:
          ParticipationTypeX.fromId(row['participation_type'] as String?),
      answers: parseAnswers(row['answers']),
      isTeam: switch (mode) {
        'team' => true,
        'solo' => false,
        _ => null,
      },
      projectName: row['project_name'] as String?,
      teamId: row['team_id']?.toString(),
      teamCode: row['team_code'] as String?,
      isTeamOwner: (row['is_team_owner'] ?? false) as bool,
      role: row['role'] as String?,
      details: parseAnswers(row['details']),
    );
  }

  /// Decodes a jsonb object (a decoded [Map] from some backends, a JSON
  /// [String] from others) into a string map — `answers` (`{questionId:
  /// answer}`) and `details`.
  static Map<String, String> parseAnswers(dynamic raw) {
    if (raw == null) return const {};
    Map<dynamic, dynamic> map;
    if (raw is String) {
      if (raw.trim().isEmpty) return const {};
      try {
        map = jsonDecode(raw) as Map<dynamic, dynamic>;
      } catch (_) {
        return const {};
      }
    } else if (raw is Map) {
      map = raw;
    } else {
      return const {};
    }
    return {
      for (final e in map.entries) e.key.toString(): '${e.value ?? ''}',
    };
  }

  RosterEntry copyWith({bool? attended}) => RosterEntry(
        userId: userId,
        name: name,
        email: email,
        attended: attended ?? this.attended,
        participationType: participationType,
        answers: answers,
        isTeam: isTeam,
        projectName: projectName,
        teamId: teamId,
        teamCode: teamCode,
        isTeamOwner: isTeamOwner,
        role: role,
        details: details,
      );
}

/// A summit attendee in the front-desk directory (from
/// `fetch_attendee_directory`), with their arrival state.
class Attendee {
  const Attendee({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.present,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final bool present;

  factory Attendee.fromMap(Map<String, dynamic> row) => Attendee(
        id: row['id'].toString(),
        name: (row['full_name'] ?? '') as String,
        email: (row['email'] ?? '') as String,
        role: (row['role'] ?? '') as String,
        present: (row['present'] ?? false) as bool,
      );

  Attendee copyWith({bool? present}) => Attendee(
        id: id,
        name: name,
        email: email,
        role: role,
        present: present ?? this.present,
      );
}

/// What a front-desk QR pass encodes: the attendee's user id, a bare UUID
/// (the same payload as the website's QR pass). Returns the normalized id, or
/// null when [raw] isn't one — a URL, a menu code, anything else — so the
/// scanner can reject it without a round trip.
String? parseCheckinPass(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  return uuid.hasMatch(s) ? s : null;
}

enum ScanCheckinOutcome { checkedIn, alreadyCheckedIn, notFound }

/// The result of scanning an attendee's QR pass at the front desk.
class ScanCheckinResult {
  const ScanCheckinResult({
    required this.outcome,
    required this.attendeeId,
    this.name = '',
    this.email = '',
    this.role = '',
    this.checkedInAt,
  });

  final ScanCheckinOutcome outcome;
  final String attendeeId;
  final String name;
  final String email;
  final String role;

  /// When they arrived: now for a fresh check-in, the original time when they
  /// were already checked in.
  final DateTime? checkedInAt;

  factory ScanCheckinResult.fromMap(String attendeeId, Map<String, dynamic> row) {
    final at = row['checked_in_at'];
    return ScanCheckinResult(
      outcome: row['attendee_found'] != true
          ? ScanCheckinOutcome.notFound
          : row['already_checked_in'] == true
              ? ScanCheckinOutcome.alreadyCheckedIn
              : ScanCheckinOutcome.checkedIn,
      attendeeId: attendeeId,
      name: (row['full_name'] ?? '') as String,
      email: (row['email'] ?? '') as String,
      role: (row['role'] ?? '') as String,
      checkedInAt: at == null ? null : DateTime.parse(at as String).toLocal(),
    );
  }
}

/// Checked-in vs total for one group of attendees.
typedef CheckinCount = ({int checkedIn, int total});

/// Live front-desk stats: onboarded accounts per role id (`participant`,
/// `volunteer`, …) and how many of each have checked in.
class CheckinStats {
  const CheckinStats(this.byRole);

  final Map<String, CheckinCount> byRole;

  CheckinCount get everyone => (
        checkedIn: byRole.values.fold(0, (n, c) => n + c.checkedIn),
        total: byRole.values.fold(0, (n, c) => n + c.total),
      );

  CheckinCount get participants =>
      byRole['participant'] ?? (checkedIn: 0, total: 0);

  CheckinCount get volunteers =>
      byRole['volunteer'] ?? (checkedIn: 0, total: 0);

  /// From `fetch_checkin_stats` rows: `{role, total, checked_in}`.
  factory CheckinStats.fromRows(List<Map<String, dynamic>> rows) =>
      CheckinStats({
        for (final r in rows)
          (r['role'] ?? '').toString(): (
            checkedIn: (r['checked_in'] as num?)?.toInt() ?? 0,
            total: (r['total'] as num?)?.toInt() ?? 0,
          ),
      });

  /// Tallied from a directory, for the sample backend.
  factory CheckinStats.fromAttendees(Iterable<Attendee> attendees) {
    final byRole = <String, CheckinCount>{};
    for (final a in attendees) {
      final c = byRole[a.role] ?? (checkedIn: 0, total: 0);
      byRole[a.role] =
          (checkedIn: c.checkedIn + (a.present ? 1 : 0), total: c.total + 1);
    }
    return CheckinStats(byRole);
  }
}

/// The signed-in user's own front-desk status, shown on their QR pass.
class MyCheckinStatus {
  const MyCheckinStatus({required this.present, this.checkedInAt});

  final bool present;
  final DateTime? checkedInAt;

  static const notArrived = MyCheckinStatus(present: false);

  factory MyCheckinStatus.fromMap(Map<String, dynamic> row) {
    final at = row['checked_in_at'];
    return MyCheckinStatus(
      present: row['present'] == true,
      checkedInAt: at == null ? null : DateTime.parse(at as String).toLocal(),
    );
  }
}
