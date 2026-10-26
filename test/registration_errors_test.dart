import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/session_detail_screen.dart';
import 'package:emerald_summit/theme.dart';

/// Holds each toggle until [release], or throws when [fail] is set.
class _SlowSchedule extends SampleScheduleRepository {
  _SlowSchedule(super.store);
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<RegistrationResult> toggle(
    String sessionId, {
    ParticipationType type = ParticipationType.participant,
    Map<String, String> answers = const {},
    ProjectChoice? project,
    String? newOwnerId,
    bool? add,
  }) async {
    calls++;
    if (fail) throw Exception('offline');
    await gate?.future;
    return super.toggle(sessionId,
        type: type,
        answers: answers,
        project: project,
        newOwnerId: newOwnerId,
        add: add);
  }
}

void main() {
  late SampleStore store;
  late _SlowSchedule schedule;

  setUp(() async {
    await getIt.reset();
    await configureBackend();
    store = SampleStore();
    schedule = _SlowSchedule(store);
    getIt
      ..unregister<CatalogRepository>()
      ..registerSingleton<CatalogRepository>(SampleCatalogRepository(store))
      ..unregister<ScheduleRepository>()
      ..registerSingleton<ScheduleRepository>(schedule);
    // Parents and spectators add with one tap (no mode picker).
    appState.profile = UserProfile(
      id: 'p1',
      email: 'parent@example.com',
      fullName: 'Pat Parent',
      role: SummitRole.parentSpectator,
      onboarded: true,
    );
    await appState.loadCatalog();
    await appState.loadSchedule();
  });
  tearDown(() async => appState.signOut());

  Future<Session> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final session = store.allSessions.first;
    await tester.pumpWidget(MaterialApp(
      theme: EmeraldTheme.light(),
      home: SessionDetailScreen(session: session),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    return session;
  }

  Future<void> tapAdd(WidgetTester tester) async {
    final add = find.text('Add to my day');
    await tester.scrollUntilVisible(add, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(add);
    await tester.pump();
  }

  testWidgets('a backend error shows a message instead of failing silently',
      (tester) async {
    final session = await pump(tester);
    schedule.fail = true;
    await tapAdd(tester);
    await tester.pump();
    expect(find.textContaining("Couldn't update your day"), findsOneWidget);
    expect(appState.isRegistered(session.id), isFalse);
  });

  testWidgets('a second tap while saving does not undo the first',
      (tester) async {
    final session = await pump(tester);
    schedule.gate = Completer<void>();
    await tapAdd(tester);
    await tester.tap(find.text('Add to my day'));
    await tester.pump();
    schedule.gate!.complete();
    await tester.pumpAndSettle();
    expect(schedule.calls, 1);
    expect(appState.participationOf(session.id), ParticipationType.spectator);
  });

  test('a stale Remove does not re-add a session left on another device',
      () async {
    final session = store.allSessions.first;
    await appState.toggle(session, type: ParticipationType.spectator);
    store.myRegistrations.remove(session.id); // left it elsewhere
    final res = await appState.toggle(session);
    expect(res.outcome, AddOutcome.removed);
    expect(store.myRegistrations.containsKey(session.id), isFalse);
    expect(appState.isRegistered(session.id), isFalse);
  });

  test('a stale Add does not remove a session added on another device',
      () async {
    final session = store.allSessions.first;
    store.myRegistrations[session.id] = ParticipationType.spectator;
    final res =
        await appState.toggle(session, type: ParticipationType.spectator);
    expect(res.outcome, AddOutcome.added);
    expect(store.myRegistrations[session.id], ParticipationType.spectator);
    expect(appState.isRegistered(session.id), isTrue);
  });
}
