import 'models.dart';
import 'schools.dart';
import 'user_profile.dart';

/// Row and column label for people who left a question blank.
const noSchoolLabel = 'No school given';
const noGradeLabel = 'No grade given';

/// A sign-up answer for grade, reduced to a column: "9" to "12" (also from
/// "11th", "Junior", …), "Other" for anything else, or [noGradeLabel].
String gradeLabel(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  if (s.isEmpty) return noGradeLabel;
  const words = {
    'freshman': '9',
    'sophomore': '10',
    'junior': '11',
    'senior': '12',
  };
  for (final e in words.entries) {
    if (s.contains(e.key)) return e.value;
  }
  final n = int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '');
  if (n != null && n >= 1 && n <= 12) return '$n';
  return 'Other';
}

/// Grade columns in reading order: numbers ascending, then Other, then blank.
int compareGrades(String a, String b) {
  int rank(String g) =>
      int.tryParse(g) ?? (g == 'Other' ? 100 : (g == noGradeLabel ? 101 : 99));
  return rank(a).compareTo(rank(b));
}

/// The school a sign-up answer counts under, or [noSchoolLabel].
String schoolLabel(String? raw) => canonicalSchoolName(raw) ?? noSchoolLabel;

/// One account, as the admin metrics see it: no name or contact details.
class MetricsPerson {
  const MetricsPerson({
    required this.id,
    required this.role,
    required this.school,
    required this.grade,
  });

  final String id;
  final SummitRole role;

  /// [schoolLabel] and [gradeLabel] of their answers.
  final String school;
  final String grade;

  factory MetricsPerson.fromMap(Map<String, dynamic> m) => MetricsPerson(
    id: m['id'].toString(),
    role: SummitRoleX.fromId(m['role'] as String?),
    school: schoolLabel(m['school'] as String?),
    grade: gradeLabel(m['grade']?.toString()),
  );
}

/// One registration (a person added a session to their day).
class MetricsRegistration {
  const MetricsRegistration({
    required this.userId,
    required this.sessionId,
    required this.disciplineId,
    required this.disciplineName,
    required this.type,
  });

  final String userId;
  final String sessionId;
  final String disciplineId;
  final String disciplineName;
  final ParticipationType type;

  factory MetricsRegistration.fromMap(Map<String, dynamic> m) =>
      MetricsRegistration(
        userId: m['user_id'].toString(),
        sessionId: m['session_id'].toString(),
        disciplineId: m['discipline_id'].toString(),
        disciplineName: (m['discipline_name'] ?? m['discipline_id']).toString(),
        type: ParticipationTypeX.fromId(m['participation_type'] as String?),
      );
}

/// Everything the admin Metrics screen counts: every onboarded account and
/// every registration (`fetch_summit_metrics`, admins only).
class SummitMetrics {
  const SummitMetrics({required this.people, required this.registrations});

  final List<MetricsPerson> people;
  final List<MetricsRegistration> registrations;

  factory SummitMetrics.fromMap(Map<String, dynamic> m) => SummitMetrics(
    people: [
      for (final p in (m['people'] as List? ?? const []))
        MetricsPerson.fromMap((p as Map).cast<String, dynamic>()),
    ],
    registrations: [
      for (final r in (m['registrations'] as List? ?? const []))
        MetricsRegistration.fromMap((r as Map).cast<String, dynamic>()),
    ],
  );
}

/// A count of distinct people per (row, column), e.g. schools × disciplines.
/// Rows are sorted by their total, largest first, with the "not given" row
/// last; columns keep the order given.
class CrossTab {
  CrossTab._(
    this.rows,
    this.columns,
    this._cells,
    this.rowTotals,
    this.columnTotals,
    this.total,
  );

  /// [facts] is one (row, column, person id) per thing to count. A person
  /// counts once per cell, once per row total, and once per column total, so
  /// someone in two Tech sessions is one Tech person.
  factory CrossTab.of(
    Iterable<(String, String, String)> facts, {
    required List<String> columns,
    String? lastRow,
  }) {
    final cells = <(String, String), Set<String>>{};
    final rowPeople = <String, Set<String>>{};
    final colPeople = <String, Set<String>>{};
    final everyone = <String>{};
    for (final (row, col, id) in facts) {
      (cells[(row, col)] ??= {}).add(id);
      (rowPeople[row] ??= {}).add(id);
      (colPeople[col] ??= {}).add(id);
      everyone.add(id);
    }
    final rows = rowPeople.keys.toList()
      ..sort((a, b) {
        if (a == lastRow) return 1;
        if (b == lastRow) return -1;
        final byCount = rowPeople[b]!.length.compareTo(rowPeople[a]!.length);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return CrossTab._(
      rows,
      [
        ...columns.where(colPeople.containsKey),
        ...colPeople.keys.where((c) => !columns.contains(c)),
      ],
      {for (final e in cells.entries) e.key: e.value.length},
      {for (final e in rowPeople.entries) e.key: e.value.length},
      {for (final e in colPeople.entries) e.key: e.value.length},
      everyone.length,
    );
  }

  final List<String> rows;
  final List<String> columns;
  final Map<(String, String), int> _cells;
  final Map<String, int> rowTotals;
  final Map<String, int> columnTotals;

  /// Distinct people in the whole table.
  final int total;

  int count(String row, String column) => _cells[(row, column)] ?? 0;

  /// The largest single cell, for shading.
  int get maxCell => _cells.values.fold(0, (max, v) => v > max ? v : max);

  bool get isEmpty => rows.isEmpty;
}

/// Distinct people per label, largest first, "not given" last.
List<(String, int)> countBy(
  Iterable<(String, String)> labelAndPerson, {
  String? last,
  int Function(String, String)? compare,
}) {
  final people = <String, Set<String>>{};
  for (final (label, id) in labelAndPerson) {
    (people[label] ??= {}).add(id);
  }
  final out = [for (final e in people.entries) (e.key, e.value.length)];
  out.sort((a, b) {
    if (compare != null) return compare(a.$1, b.$1);
    if (a.$1 == last) return 1;
    if (b.$1 == last) return -1;
    final byCount = b.$2.compareTo(a.$2);
    return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
  });
  return out;
}
