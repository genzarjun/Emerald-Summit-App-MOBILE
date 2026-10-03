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
  });

  final String id;
  final String name;
  final String email;

  /// Stored subtype id (e.g. 'student_volunteer'), or null.
  final String? subtype;

  /// `id` for the directory RPC, `user_id` for the session-volunteers RPC.
  factory VolunteerRef.fromMap(Map<String, dynamic> row) => VolunteerRef(
        id: (row['id'] ?? row['user_id']).toString(),
        name: (row['full_name'] ?? '') as String,
        email: (row['email'] ?? '') as String,
        subtype: row['subtype'] as String?,
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

  factory RosterEntry.fromMap(Map<String, dynamic> row) => RosterEntry(
        userId: row['user_id'].toString(),
        name: (row['full_name'] ?? '') as String,
        email: (row['email'] ?? '') as String,
        attended: (row['attended'] ?? false) as bool,
        participationType:
            ParticipationTypeX.fromId(row['participation_type'] as String?),
        answers: parseAnswers(row['answers']),
      );

  /// Decodes the `answers` jsonb (a decoded [Map] from some backends, a JSON
  /// [String] from others) into a `{questionId: answer}` string map.
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
