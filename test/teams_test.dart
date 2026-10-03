import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/screens/session_registration_screen.dart';
import 'package:emerald_summit/theme.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/models/models.dart';

void main() {
  group('team codes', () {
    test('summit disciplines get their pinned prefixes', () {
      expect(teamCodePrefix('techverse', 'TechVerse'), 'TV');
      expect(teamCodePrefix('ventureverse', 'VentureVerse'), 'VV');
      expect(teamCodePrefix('biosphere', 'BioSphere'), 'BS');
      expect(teamCodePrefix('novasphere', 'NovaSphere'), 'NS');
      expect(teamCodePrefix('civicverse', 'CivicVerse'), 'CV');
      expect(teamCodePrefix('imaginex', 'ImagineX'), 'IX');
    });

    test('other disciplines fall back to the capitals of their name', () {
      expect(teamCodePrefix('robosphere', 'RoboSphere'), 'RS');
      expect(teamCodePrefix('chess', 'chess'), 'CH');
      expect(teamCodePrefix('x', 'X'), 'XX');
    });

    test('typed codes are normalized', () {
      expect(normalizeTeamCode(' tv 4821 '), 'TV4821');
    });
  });

  group('RosterEntry project fields', () {
    test('parses team and solo rows', () {
      final team = RosterEntry.fromMap({
        'user_id': 'u1',
        'project_mode': 'team',
        'project_name': 'Solar Rover',
        'team_id': 't1',
        'team_code': 'TV1234',
      });
      expect(team.isTeam, isTrue);
      expect(team.projectName, 'Solar Rover');
      expect(team.teamCode, 'TV1234');

      final solo = RosterEntry.fromMap({
        'user_id': 'u2',
        'project_mode': 'solo',
        'project_name': 'Kite',
      });
      expect(solo.isTeam, isFalse);
      expect(solo.teamId, isNull);

      final legacy = RosterEntry.fromMap({'user_id': 'u3'});
      expect(legacy.isTeam, isNull);
    });
  });

  group('sample schedule repository', () {
    late SampleStore store;
    late SampleScheduleRepository repo;
    late Session session;
    late Session other;

    setUp(() {
      store = SampleStore();
      repo = SampleScheduleRepository(store);
      final sessions = store.allSessions
          .where((s) => s.disciplineId == 'techverse')
          .toList();
      session = sessions.first;
      other = store.allSessions.firstWhere(
        (s) => s.disciplineId != 'techverse' && !s.overlaps(session),
      );
    });

    test('creating a team issues a discipline-prefixed code', () async {
      final res = await repo.toggle(
        session.id,
        project: const ProjectChoice.createTeam('Solar Rover'),
      );
      expect(res.outcome, RegistrationOutcome.added);
      expect(res.teamCode, startsWith('TV'));

      final mine = await repo.fetchMyProject(session.id);
      expect(mine!.isTeam, isTrue);
      expect(mine.projectName, 'Solar Rover');
      expect(mine.teamCode, res.teamCode);

      final lookup = await repo.findTeam(session.id, res.teamCode!.toLowerCase());
      expect(lookup.outcome, TeamLookupOutcome.found);
      expect(lookup.projectName, 'Solar Rover');

      final elsewhere = await repo.findTeam(other.id, res.teamCode!);
      expect(elsewhere.outcome, TeamLookupOutcome.wrongSession);
    });

    test('joining with an unknown code registers nothing', () async {
      final res = await repo.toggle(
        session.id,
        project: const ProjectChoice.joinTeam('TV0000'),
      );
      expect(res.outcome, RegistrationOutcome.invalidProject);
      expect(await repo.fetchMyRegistrations(), isEmpty);
    });

    test('a solo participant can switch to a team later', () async {
      await repo.toggle(
        session.id,
        project: const ProjectChoice.solo('Kite'),
      );
      expect((await repo.fetchMyProject(session.id))!.isTeam, isFalse);

      final updated = await repo.updateMyRegistration(
        session.id,
        answers: const {},
        project: const ProjectChoice.createTeam('Kite Squad'),
      );
      expect(updated.isTeam, isTrue);
      expect(updated.teamCode, startsWith('TV'));

      // Back to solo: the emptied team is deleted, so its code stops working.
      await repo.updateMyRegistration(
        session.id,
        answers: const {},
        project: const ProjectChoice.solo('Kite'),
      );
      final lookup = await repo.findTeam(session.id, updated.teamCode!);
      expect(lookup.outcome, TeamLookupOutcome.notFound);
    });

    test('unregistering removes the project', () async {
      await repo.toggle(
        session.id,
        project: const ProjectChoice.createTeam('Solar Rover'),
      );
      final code = (await repo.fetchMyProject(session.id))!.teamCode!;
      final res = await repo.toggle(session.id);
      expect(res.outcome, RegistrationOutcome.removed);
      expect(await repo.fetchMyProject(session.id), isNull);
      expect((await repo.findTeam(session.id, code)).outcome,
          TeamLookupOutcome.notFound);
    });
  });

  group('registration form', () {
    setUp(() async {
      await getIt.reset();
      await configureBackend();
      await appState.loadCatalog();
    });

    /// Pumps a launcher that opens the form and records what it pops.
    Future<List<RegistrationFormResult?>> open(
        WidgetTester tester, Session session) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final results = <RegistrationFormResult?>[];
      await tester.pumpWidget(MaterialApp(
        theme: EmeraldTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SessionRegistrationScreen(session: session),
              )),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('solo requires a project name', (tester) async {
      final session = appState.allSessions.first;
      final results = await open(tester, session);
      expect(find.text(DefaultQuestions.soloOrTeam), findsOneWidget);
      expect(find.text(DefaultQuestions.unsureNote), findsOneWidget);

      await tester.tap(find.text('Confirm & add'));
      await tester.pump();
      expect(find.textContaining('solo or as a team'), findsOneWidget);

      await tester.tap(find.text('Solo'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Kite');
      for (final q in session.participantQuestions) {
        await tester.enterText(find.widgetWithText(TextField, q.prompt), 'x');
      }
      await tester.scrollUntilVisible(find.text('Confirm & add'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Confirm & add'));
      await tester.pumpAndSettle();
      expect(results.single!.project.action, ProjectAction.solo);
      expect(results.single!.project.projectName, 'Kite');
    });

    testWidgets('joining asks to confirm the project name', (tester) async {
      final session = appState.allSessions.first;
      final created = await scheduleRepository.toggle(
        session.id,
        project: const ProjectChoice.createTeam('Solar Rover'),
      );
      final results = await open(tester, session);

      await tester.tap(find.text('Team'));
      await tester.pump();
      await tester.tap(find.text('Join'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, DefaultQuestions.teamCode),
          created.teamCode!.toLowerCase());
      await tester.tap(find.text('Find team'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Is your project name '), findsOneWidget);
      expect(find.textContaining('Solar Rover'), findsWidgets);

      await tester.tap(find.text("Yes, that's us"));
      await tester.pumpAndSettle();
      expect(find.text('Joining team ${created.teamCode}'), findsOneWidget);

      for (final q in session.participantQuestions) {
        await tester.enterText(find.widgetWithText(TextField, q.prompt), 'x');
      }
      await tester.scrollUntilVisible(find.text('Confirm & add'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Confirm & add'));
      await tester.pumpAndSettle();
      expect(results.single!.project.action, ProjectAction.joinTeam);
      expect(results.single!.project.teamCode, created.teamCode);
    });
  });
}
