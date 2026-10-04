import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/screens/session_detail_screen.dart';
import 'package:emerald_summit/theme.dart';

/// Replaces [session] in the sample catalog with a copy whose participant
/// deadline is [deadline] (Session has no copyWith).
Session setDeadline(SampleStore store, Session session, DateTime? deadline) {
  final s = session;
  final updated = Session(
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
    maxTeamSize: s.maxTeamSize,
    customProjectPrompt: s.customProjectPrompt,
    participantDeadline: deadline,
  );
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

Map<String, dynamic> row({Object? deadline}) => {
      'id': 's1',
      'discipline_id': 'techverse',
      'title': 'Robotics',
      'start_time': '10:00',
      'end_time': '11:00',
      'capacity': 10,
      'participant_deadline': deadline,
    };

void main() {
  group('Session.participantDeadline', () {
    test('parses the column as local time; null means no deadline', () {
      final utc = DateTime.utc(2027, 1, 15, 23, 30);
      final s = Session.fromMap(row(deadline: utc.toIso8601String()));
      expect(s.participantDeadline, utc.toLocal());
      expect(s.participantDeadline!.isUtc, isFalse);

      final none = Session.fromMap(row());
      expect(none.participantDeadline, isNull);
      expect(none.participationClosed, isFalse);
    });

    test('closes once the deadline passes', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final future = DateTime.now().add(const Duration(days: 1));
      expect(
        Session.fromMap(row(deadline: past.toUtc().toIso8601String()))
            .participationClosed,
        isTrue,
      );
      expect(
        Session.fromMap(row(deadline: future.toUtc().toIso8601String()))
            .participationClosed,
        isFalse,
      );
    });

    test('formats as weekday, date and 12-hour time', () {
      final year = DateTime.now().year;
      expect(formatDeadline(DateTime(year, 3, 5, 15, 7)),
          matches(RegExp(r'^\w{3}, Mar 5 at 3:07 PM$')));
      expect(formatDeadline(DateTime(year, 3, 5, 0, 0)), endsWith('12:00 AM'));
      expect(formatDeadline(DateTime(2027, 1, 15, 12, 30)),
          year == 2027 ? 'Fri, Jan 15 at 12:30 PM'
              : 'Fri, Jan 15, 2027 at 12:30 PM');
    });
  });

  group('sample schedule repository', () {
    late SampleStore store;
    late SampleScheduleRepository repo;
    late Session session;

    setUp(() {
      store = SampleStore();
      repo = SampleScheduleRepository(store);
      session = store.allSessions.first;
    });

    test('refuses participants after the deadline but allows spectators',
        () async {
      setDeadline(store, session,
          DateTime.now().subtract(const Duration(hours: 1)));

      final participate = await repo.toggle(session.id);
      expect(participate.outcome, RegistrationOutcome.participationClosed);
      expect(await repo.fetchMyRegistrations(), isEmpty);

      final spectate =
          await repo.toggle(session.id, type: ParticipationType.spectator);
      expect(spectate.outcome, RegistrationOutcome.added);
    });

    test('a future deadline still lets people participate', () async {
      setDeadline(
          store, session, DateTime.now().add(const Duration(days: 1)));
      final res = await repo.toggle(
        session.id,
        project: const ProjectChoice.solo('Kite'),
      );
      expect(res.outcome, RegistrationOutcome.added);
    });
  });

  group('session page', () {
    late SampleStore store;

    setUp(() async {
      await getIt.reset();
      await configureBackend();
      store = SampleStore();
      getIt
        ..unregister<CatalogRepository>()
        ..registerSingleton<CatalogRepository>(SampleCatalogRepository(store))
        ..unregister<ScheduleRepository>()
        ..registerSingleton<ScheduleRepository>(
            SampleScheduleRepository(store));
    });

    Future<Session> pump(WidgetTester tester, DateTime deadline) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final session = setDeadline(store, store.allSessions.first, deadline);
      await appState.loadCatalog();
      await tester.pumpWidget(MaterialApp(
        theme: EmeraldTheme.light(),
        home: SessionDetailScreen(session: session),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      return session;
    }

    testWidgets('an open deadline says when participating closes',
        (tester) async {
      final deadline = DateTime.now().add(const Duration(days: 2));
      await pump(tester, deadline);
      expect(
        find.text('Register to participate by ${formatDeadline(deadline)}'),
        findsOneWidget,
      );
      expect(find.textContaining('still register to spectate'), findsOneWidget);
    });

    testWidgets('after the deadline only spectating can be chosen',
        (tester) async {
      final deadline = DateTime.now().subtract(const Duration(hours: 3));
      final session = await pump(tester, deadline);
      expect(find.text('Participant registration closed'), findsOneWidget);
      expect(find.textContaining('You can still register to spectate'),
          findsOneWidget);

      final add = find.text('Add to my day');
      await tester.scrollUntilVisible(add, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(add);
      await tester.pumpAndSettle();

      final participate = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'Participate'));
      expect(participate.enabled, isFalse);
      expect(
        find.text('Registration to participate closed on '
            '${formatDeadline(deadline)}.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Spectate'));
      await tester.pumpAndSettle();
      expect(appState.participationOf(session.id),
          ParticipationType.spectator);
      await appState.toggle(session); // tidy up
    });
  });
}
