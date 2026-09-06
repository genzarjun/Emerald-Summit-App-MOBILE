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
  /// who have an activity in that discipline (plus admins / its mentors). Null
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
