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

/// A single session/activity a participant can add to their day plan.
class Session {
  const Session({
    required this.id,
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
  });

  /// Builds a [Session] from a `sessions_with_counts` view row. The view carries
  /// the live `enrolled` count and the parent `discipline_name`, so capacity
  /// rules and the display name work without a second query.
  factory Session.fromMap(Map<String, dynamic> row) => Session(
        id: row['id'].toString(),
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
      );

  final String id;
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
  });

  final String userId;
  final String name;
  final String email;
  final bool attended;

  factory RosterEntry.fromMap(Map<String, dynamic> row) => RosterEntry(
        userId: row['user_id'].toString(),
        name: (row['full_name'] ?? '') as String,
        email: (row['email'] ?? '') as String,
        attended: (row['attended'] ?? false) as bool,
      );

  RosterEntry copyWith({bool? attended}) => RosterEntry(
        userId: userId,
        name: name,
        email: email,
        attended: attended ?? this.attended,
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
