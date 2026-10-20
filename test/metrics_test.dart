import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/metrics.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/schools.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/metrics_screen.dart';
import 'package:emerald_summit/theme.dart';

class _FakeMetrics implements MetricsRepository {
  _FakeMetrics(this.data);
  final SummitMetrics data;

  @override
  Future<SummitMetrics> fetchSummitMetrics() async => data;
}

MetricsPerson _person(
  String id,
  String school,
  String grade, [
  SummitRole role = SummitRole.participant,
]) => MetricsPerson(
  id: id,
  role: role,
  school: schoolLabel(school),
  grade: gradeLabel(grade),
);

MetricsRegistration _reg(
  String user,
  String session,
  String discipline, [
  ParticipationType type = ParticipationType.participant,
]) => MetricsRegistration(
  userId: user,
  sessionId: session,
  disciplineId: discipline.toLowerCase(),
  disciplineName: discipline,
  type: type,
);

void main() {
  group('school answers', () {
    test('typed variants land on the listed school', () {
      expect(canonicalSchoolName('Emerald High'), 'Emerald High School');
      expect(
        canonicalSchoolName(' dublin high school. '),
        'Dublin High School',
      );
      expect(canonicalSchoolName('Cal High'), 'California High School');
      expect(canonicalSchoolName('DVHS'), 'Dougherty Valley High School');
      expect(canonicalSchoolName('Athenian'), 'The Athenian School');
    });

    test('Valley High and Valley Christian stay apart', () {
      expect(canonicalSchoolName('Valley High'), 'Valley High School');
      expect(
        canonicalSchoolName('Valley Christian'),
        'Valley Christian High School',
      );
    });

    test('unlisted schools are tidied, blanks are null', () {
      expect(
        canonicalSchoolName('  ohlone   college of the arts '),
        'Ohlone College of the Arts',
      );
      expect(canonicalSchoolName('ISB'), 'ISB');
      expect(canonicalSchoolName('  '), isNull);
      expect(schoolLabel(null), noSchoolLabel);
    });
  });

  test('grade answers reduce to columns', () {
    expect(gradeLabel('11'), '11');
    expect(gradeLabel('11th'), '11');
    expect(gradeLabel('Junior'), '11');
    expect(gradeLabel('grade 9'), '9');
    expect(gradeLabel('college'), 'Other');
    expect(gradeLabel(''), noGradeLabel);
    expect(['Other', '12', noGradeLabel, '9']..sort(compareGrades), [
      '9',
      '12',
      'Other',
      noGradeLabel,
    ]);
  });

  test('CrossTab counts each person once per cell and per total', () {
    final t = CrossTab.of(
      [
        ('Amador', 'Tech', 'a'),
        ('Amador', 'Tech', 'a'), // a second Tech session
        ('Amador', 'Biosphere', 'a'),
        ('Amador', 'Tech', 'b'),
        ('Dublin', 'Biosphere', 'c'),
        (noSchoolLabel, 'Tech', 'd'),
        (noSchoolLabel, 'Tech', 'e'),
        (noSchoolLabel, 'Tech', 'f'),
      ],
      columns: ['Biosphere', 'Arts', 'Tech'],
      lastRow: noSchoolLabel,
    );
    expect(t.rows, ['Amador', 'Dublin', noSchoolLabel]);
    expect(t.columns, ['Biosphere', 'Tech']); // no Arts sign-ups
    expect(t.count('Amador', 'Tech'), 2);
    expect(t.count('Dublin', 'Tech'), 0);
    expect(t.rowTotals['Amador'], 2);
    expect(t.columnTotals['Tech'], 5);
    expect(t.total, 6);
    expect(t.maxCell, 3);
  });

  group('admin Metrics screen', () {
    setUp(() async {
      await getIt.reset();
      await configureBackend();
      getIt.unregister<MetricsRepository>();
      getIt.registerSingleton<MetricsRepository>(
        _FakeMetrics(
          SummitMetrics(
            people: [
              for (var i = 0; i < 10; i++)
                _person('amador$i', 'Amador Valley High School', '11'),
              _person('dublin', 'Dublin High', '9'),
              _person(
                'parent',
                'Dublin High School',
                '',
                SummitRole.parentSpectator,
              ),
            ],
            registrations: [
              for (var i = 0; i < 10; i++) _reg('amador$i', 's1', 'Tech'),
              _reg('dublin', 's2', 'Biosphere'),
              _reg('parent', 's2', 'Biosphere', ParticipationType.spectator),
            ],
          ),
        ),
      );
    });

    testWidgets('shows sign-ups and discipline counts by school', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: EmeraldTheme.light(), home: const MetricsScreen()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Participants only by default: the parent isn't counted.
      expect(find.text('Signed up'), findsOneWidget);
      expect(find.text('11'), findsWidgets);
      expect(find.text('Amador Valley High School'), findsWidgets);
      expect(find.text('Dublin High School'), findsWidgets);
      expect(
        find.byTooltip('10 people from Amador Valley High School in Tech'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('1 person from Dublin High School in Biosphere'),
        findsOneWidget,
      );
      expect(find.text('Grades by school'), findsOneWidget);

      await tester.tap(find.text('Parents & spectators'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('1 person from Dublin High School in Biosphere'),
        findsOneWidget,
      );
      expect(find.text('Grades by school'), findsNothing);
    });
  });
}
