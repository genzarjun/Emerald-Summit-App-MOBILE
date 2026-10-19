import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/profile_screen.dart';
import 'package:emerald_summit/screens/volunteer_hours_screen.dart';
import 'package:emerald_summit/theme.dart';

void main() {
  group('hour formatting', () {
    test('formatMinutes', () {
      expect(formatMinutes(45), '45 min');
      expect(formatMinutes(180), '3 hr');
      expect(formatMinutes(150), '2 hr 30 min');
    });

    test('formatHours trims trailing zeros', () {
      expect(formatHours(0), '0');
      expect(formatHours(150), '2.5');
      expect(formatHours(180), '3');
      expect(formatHours(600), '10');
      expect(formatHours(100), '1.67');
    });

    test('a log is end minus start', () {
      final log = VolunteerHourLog(
        id: 'l',
        startedAt: DateTime(2026, 10, 10, 15, 0),
        endedAt: DateTime(2026, 10, 10, 17, 15),
        description: 'Planning',
      );
      expect(log.minutes, 135);
    });

    test('summit sessions count only after they end on the summit date', () {
      const s = Session(
        id: 'x',
        title: 'T',
        disciplineId: 'd',
        disciplineName: 'D',
        track: '',
        room: '',
        expertName: '',
        start: '10:00',
        end: '12:00',
        capacity: 10,
        enrolled: 0,
        description: '',
      );
      final day = DateTime(2027, 1, 23);
      expect(summitSessionCounted(s, null, DateTime(2030)), isFalse);
      expect(
        summitSessionCounted(s, day, DateTime(2027, 1, 23, 11, 59)),
        isFalse,
      );
      expect(summitSessionCounted(s, day, DateTime(2027, 1, 23, 12)), isTrue);
      expect(summitSessionCounted(s, day, DateTime(2027, 2, 1)), isTrue);
    });

    test('volunteers and admins get an optional digits-only student ID', () {
      for (final role in [SummitRole.volunteer, SummitRole.admin]) {
        final f = role.onboardingFields.firstWhere(
          (f) => f.key == 'student_id',
        );
        expect(f.required, isFalse);
        expect(f.digitsOnly, isTrue);
      }
      for (final role in [
        SummitRole.participant,
        SummitRole.expert,
        SummitRole.parentSpectator,
      ]) {
        expect(
          role.onboardingFields.any((f) => f.key == 'student_id'),
          isFalse,
        );
      }
    });
  });

  group('VolunteerHoursScreen', () {
    late SampleStore store;

    setUp(() async {
      await getIt.reset();
      await configureBackend();
      store = SampleStore();
      getIt
        ..unregister<CatalogRepository>()
        ..registerSingleton<CatalogRepository>(SampleCatalogRepository(store))
        ..unregister<AssignmentRepository>()
        ..registerSingleton<AssignmentRepository>(
          SampleAssignmentRepository(store),
        )
        ..unregister<SummitRepository>()
        ..registerSingleton<SummitRepository>(SampleSummitRepository(store))
        ..unregister<VolunteerHoursRepository>()
        ..registerSingleton<VolunteerHoursRepository>(
          SampleVolunteerHoursRepository(store),
        );
      appState.profile = UserProfile(
        id: 'v1',
        email: 'v@e.com',
        role: SummitRole.volunteer,
      );
    });

    tearDown(() {
      appState.summitStatus = SummitStatus.unknown;
      appState.profile = null;
      appState.myAssignedSessionIds = const {};
    });

    Future<void> pump(WidgetTester tester, Widget home) async {
      // Tall enough that every section is built without scrolling.
      tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: EmeraldTheme.light(), home: home),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('adds managed sessions and manual logs into the total', (
      tester,
    ) async {
      // s1 runs 10:00–10:45 (45 min) and s2 13:00–14:00 (60 min). A summit
      // date in the past means both have ended and count.
      store.summitStatus = SummitStatus(date: DateTime(2026, 1, 10));
      store.myAssignedSessionIds.addAll(['s1', 's2']);
      store.hourLogs.add(
        VolunteerHourLog(
          id: 'l1',
          startedAt: DateTime(2026, 10, 10, 15, 0),
          endedAt: DateTime(2026, 10, 10, 17, 15),
          description: 'Booth layout meeting',
        ),
      );

      await pump(tester, const VolunteerHoursScreen());

      // 45 + 60 + 135 = 240 min.
      expect(find.text('4'), findsOneWidget);
      expect(
        find.text('2.25 logged by you · 1.75 on summit day'),
        findsOneWidget,
      );
      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('1 hr'), findsOneWidget);
      expect(find.text('Booth layout meeting'), findsOneWidget);
      expect(find.text('2 hr 15 min'), findsOneWidget);
    });

    testWidgets('without a summit date, sessions are listed but not counted', (
      tester,
    ) async {
      store.myAssignedSessionIds.add('s1');
      await pump(tester, const VolunteerHoursScreen());
      expect(find.text('0'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      expect(find.text('Not counted yet'), findsOneWidget);
      expect(
        find.textContaining('once the summit date is set'),
        findsOneWidget,
      );
      expect(find.text('Download certificate'), findsNothing);
    });

    testWidgets('empty state explains both sections', (tester) async {
      await pump(tester, const VolunteerHoursScreen());
      expect(find.text('0'), findsOneWidget);
      expect(
        find.textContaining("You aren't managing any sessions"),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing logged yet'), findsOneWidget);
    });

    testWidgets('editor refuses a log without times or description', (
      tester,
    ) async {
      await pump(tester, const HourLogEditorScreen());
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Pick a start and end time.'), findsOneWidget);
      expect(store.hourLogs, isEmpty);
    });

    testWidgets('deleting a log removes it', (tester) async {
      store.hourLogs.add(
        VolunteerHourLog(
          id: 'l1',
          startedAt: DateTime(2026, 10, 10, 15, 0),
          endedAt: DateTime(2026, 10, 10, 16, 0),
          description: 'Sponsor calls',
        ),
      );
      await pump(tester, const VolunteerHoursScreen());
      await tester.tap(find.text('Sponsor calls'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(store.hourLogs, isEmpty);
      expect(find.text('Sponsor calls'), findsNothing);
    });
  });

  group('Profile entry point', () {
    setUp(() async {
      await getIt.reset();
      await configureBackend();
    });

    tearDown(() => appState.profile = null);

    Future<void> pumpProfile(WidgetTester tester, SummitRole role) async {
      tester.view.physicalSize = const Size(375 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      appState.profile = UserProfile(id: 'u', email: 'u@e.com', role: role);
      await tester.pumpWidget(
        MaterialApp(theme: EmeraldTheme.light(), home: const ProfileScreen()),
      );
      await tester.pump();
    }

    for (final role in [SummitRole.volunteer, SummitRole.admin]) {
      testWidgets('${role.name} sees Track volunteer hours', (tester) async {
        await pumpProfile(tester, role);
        expect(find.text('Track volunteer hours'), findsOneWidget);
      });
    }

    for (final role in [
      SummitRole.participant,
      SummitRole.expert,
      SummitRole.parentSpectator,
    ]) {
      testWidgets('${role.name} does not see volunteer hours', (tester) async {
        await pumpProfile(tester, role);
        expect(find.text('Track volunteer hours'), findsNothing);
        expect(find.textContaining('hours'), findsNothing);
      });
    }
  });
}
