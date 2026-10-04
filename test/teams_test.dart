import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/screens/session_detail_screen.dart';
import 'package:emerald_summit/screens/session_registration_screen.dart';
import 'package:emerald_summit/theme.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/models/models.dart';

/// [s] with its team size limit replaced (Session has no copyWith).
Session withTeamSize(Session s, int maxTeamSize) => Session(
      id: s.id,
      disciplineId: s.disciplineId,
      title: s.title,
      disciplineName: s.disciplineName,
      track: s.track,
      room: s.room,
      roomId: s.roomId,
      expertName: s.expertName,
      start: s.start,
      end: s.end,
      capacity: s.capacity,
      enrolled: s.enrolled,
      description: s.description,
      participantQuestions: s.participantQuestions,
      maxTeamSize: maxTeamSize,
    );

/// Replaces [session] in the sample catalog with a copy of team size [size].
Session setTeamSize(SampleStore store, Session session, int size) {
  final updated = withTeamSize(session, size);
  for (var i = 0; i < store.disciplines.length; i++) {
    final d = store.disciplines[i];
    if (d.id != session.disciplineId) continue;
    store.disciplines[i] = Discipline(
      id: d.id,
      name: d.name,
      tagline: d.tagline,
      icon: d.icon,
      sessions: [
        for (final x in d.sessions) x.id == session.id ? updated : x,
      ],
    );
  }
  return updated;
}

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

  group('ownership parsing', () {
    test('MyProject reads member details and the size limit', () {
      final p = MyProject.fromMap({
        'mode': 'team',
        'project_name': 'Solar Rover',
        'team_code': 'TV1234',
        'is_owner': false,
        'max_team_size': 6,
        'members': ['Ana', 'You'],
        'member_details': [
          {'id': 'u2', 'name': 'Ana', 'is_owner': true},
          {'id': 'u1', 'name': 'You', 'is_owner': false},
        ],
      })!;
      expect(p.ownerName, 'Ana');
      expect(p.maxTeamSize, 6);
      expect(p.mustHandOff, isFalse);
    });

    test('roster rows carry the owner flag', () {
      final e = RosterEntry.fromMap({
        'user_id': 'u2',
        'project_mode': 'team',
        'team_id': 't1',
        'is_team_owner': true,
      });
      expect(e.isTeamOwner, isTrue);
      expect(e.copyWith(attended: true).isTeamOwner, isTrue);
    });

    test('sessions default to a team size of 4', () {
      expect(Session.fromMap({'id': 's'}).maxTeamSize, 4);
      expect(Session.fromMap({'id': 's', 'max_team_size': 3}).maxTeamSize, 3);
      expect(Session.fromMap({'id': 's', 'max_team_size': 1}).teamsAllowed,
          isFalse);
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

    /// Creates a team as the demo user and adds [others] (id → name) to it.
    Future<String> teamWith(Map<String, String> others) async {
      final res = await repo.toggle(
        session.id,
        project: const ProjectChoice.createTeam('Solar Rover'),
      );
      store.teams[res.teamCode]!.members.addAll(others);
      return res.teamCode!;
    }

    test('the creator owns the team', () async {
      await teamWith({'u2': 'Ana'});
      final mine = (await repo.fetchMyProject(session.id))!;
      expect(mine.isOwner, isTrue);
      expect(mine.ownerName, 'You');
      expect(mine.mustHandOff, isTrue);
      expect(mine.maxTeamSize, kDefaultMaxTeamSize);
    });

    test('an owner with teammates must name a new owner to leave', () async {
      final code = await teamWith({'u2': 'Ana', 'u3': 'Ben'});

      await expectLater(
        repo.updateMyRegistration(session.id,
            answers: const {}, project: const ProjectChoice.solo('Kite')),
        throwsA(isA<TeamCodeException>()),
      );
      expect((await repo.fetchMyProject(session.id))!.isTeam, isTrue,
          reason: 'a refused leave changes nothing');

      await expectLater(
        repo.updateMyRegistration(session.id,
            answers: const {},
            project: const ProjectChoice.solo('Kite'),
            newOwnerId: 'nobody'),
        throwsA(isA<TeamCodeException>()),
      );

      final solo = await repo.updateMyRegistration(session.id,
          answers: const {},
          project: const ProjectChoice.solo('Kite'),
          newOwnerId: 'u3');
      expect(solo.isTeam, isFalse);
      final team = store.teams[code]!;
      expect(team.ownerId, 'u3');
      expect(team.members.keys, ['u2', 'u3']);
    });

    test('an owner unregistering hands the team over', () async {
      final code = await teamWith({'u2': 'Ana'});
      final refused = await repo.toggle(session.id);
      expect(refused.outcome, RegistrationOutcome.invalidProject);
      expect(await repo.fetchMyRegistrations(), contains(session.id));

      final removed = await repo.toggle(session.id, newOwnerId: 'u2');
      expect(removed.outcome, RegistrationOutcome.removed);
      expect(store.teams[code]!.ownerId, 'u2');
    });

    test('a non-owner member leaves freely', () async {
      final code = await teamWith({'u2': 'Ana'});
      store.teams[code]!.ownerId = 'u2';
      final solo = await repo.updateMyRegistration(session.id,
          answers: const {}, project: const ProjectChoice.solo('Kite'));
      expect(solo.isTeam, isFalse);
      expect(store.teams[code]!.members.keys, ['u2']);
    });

    test('ownership can be transferred while staying', () async {
      final code = await teamWith({'u2': 'Ana'});
      await repo.transferTeamOwnership(session.id, 'u2');
      final mine = (await repo.fetchMyProject(session.id))!;
      expect(mine.isOwner, isFalse);
      expect(mine.ownerName, 'Ana');
      expect(store.teams[code]!.members.length, 2);
      await expectLater(repo.transferTeamOwnership(session.id, 'u2'),
          throwsA(isA<TeamCodeException>()));
    });

    test('a full team cannot be joined', () async {
      final code = await teamWith({'u2': 'Ana', 'u3': 'Ben', 'u4': 'Cy'});
      // Hand the team off and leave it, so the demo user can try to rejoin.
      await repo.toggle(session.id, newOwnerId: 'u2');
      store.teams[code]!.members['u5'] = 'Di';

      final lookup = await repo.findTeam(session.id, code);
      expect(lookup.outcome, TeamLookupOutcome.full);
      expect(lookup.problem, contains('full'));

      final res = await repo.toggle(session.id,
          project: ProjectChoice.joinTeam(code));
      expect(res.outcome, RegistrationOutcome.invalidProject);
    });

    test('a solo-only session refuses new teams', () async {
      setTeamSize(store, session, kSoloOnlyTeamSize);
      final created = await repo.toggle(
        session.id,
        project: const ProjectChoice.createTeam('Solar Rover'),
      );
      expect(created.outcome, RegistrationOutcome.invalidProject);
      expect(created.message, contains('solo only'));

      final solo = await repo.toggle(
        session.id,
        project: const ProjectChoice.solo('Kite'),
      );
      expect(solo.outcome, RegistrationOutcome.added);
    });

    test('turning teams off keeps existing teams but blocks joins', () async {
      final code = await teamWith({'u2': 'Ana'});
      setTeamSize(store, session, kSoloOnlyTeamSize);

      expect((await repo.findTeam(session.id, code)).outcome,
          TeamLookupOutcome.teamsNotAllowed);
      // Staying on the team (and renaming it) still works.
      final stayed = await repo.updateMyRegistration(session.id,
          answers: const {},
          project: const ProjectChoice.stayOnTeam('Solar Rover 2'));
      expect(stayed.isTeam, isTrue);
      expect(stayed.teamsAllowed, isFalse);
      // But a new team can't be started.
      await expectLater(
        repo.updateMyRegistration(session.id,
            answers: const {},
            project: const ProjectChoice.createTeam('Other'),
            newOwnerId: 'u2'),
        throwsA(isA<TeamCodeException>()),
      );
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

    testWidgets('a solo-only session only asks for the project name',
        (tester) async {
      final session = withTeamSize(appState.allSessions.first, 1);
      final results = await open(tester, session);
      expect(find.text(DefaultQuestions.soloOrTeam), findsNothing);
      expect(find.textContaining('solo only'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, DefaultQuestions.projectName), 'Kite');
      for (final q in session.participantQuestions) {
        await tester.enterText(find.widgetWithText(TextField, q.prompt), 'x');
      }
      await tester.scrollUntilVisible(find.text('Confirm & add'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Confirm & add'));
      await tester.pumpAndSettle();
      expect(results.single!.project.action, ProjectAction.solo);
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

  group('session page', () {
    setUp(() async {
      await getIt.reset();
      await configureBackend();
      await appState.loadCatalog();
    });

    testWidgets('a team member can leave the team and go solo',
        (tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final session = appState.allSessions.first;
      await appState.toggle(
        session,
        project: const ProjectChoice.createTeam('Solar Rover'),
      );

      await tester.pumpWidget(MaterialApp(
        theme: EmeraldTheme.light(),
        home: SessionDetailScreen(session: session),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
          find.text('Leave team / go solo'), 200,
          scrollable: scrollable);
      expect(find.text('Team project'), findsOneWidget);
      expect(find.textContaining('Owner'), findsWidgets);

      await tester.ensureVisible(find.text('Leave team / go solo'));
      await tester.pump();
      await tester.tap(find.text('Leave team / go solo'));
      await tester.pumpAndSettle();
      expect(find.text('Leave team?'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Your solo project name'), 'Kite');
      await tester.tap(find.widgetWithText(FilledButton, 'Leave team'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Solo project', skipOffstage: false), findsOneWidget);
      expect(find.text('Kite', skipOffstage: false), findsOneWidget);
      final mine = await appState.myProject(session);
      expect(mine!.isTeam, isFalse);
      await appState.toggle(session); // tidy the shared sample store
    });
  });
}
