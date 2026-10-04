import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/screens/session_detail_screen.dart';
import 'package:emerald_summit/screens/session_volunteers_screen.dart';
import 'package:emerald_summit/theme.dart';

void main() {
  late SampleStore store;
  late Session session;

  setUp(() async {
    await getIt.reset();
    await configureBackend();
    store = SampleStore();
    getIt
      ..unregister<CatalogRepository>()
      ..registerSingleton<CatalogRepository>(SampleCatalogRepository(store))
      ..unregister<AssignmentRepository>()
      ..registerSingleton<AssignmentRepository>(
          SampleAssignmentRepository(store));
    session = store.allSessions.first;
    store.sessionVolunteers[session.id] = [
      const VolunteerRef(
          id: 'co-1',
          name: 'Maya Chen',
          email: '',
          role: 'volunteer',
          subtype: 'student_volunteer',
          phone: '(925) 555-0142'),
      const VolunteerRef(
          id: 'co-2',
          name: 'Sam Okafor',
          email: '',
          role: 'admin',
          phone: '(925) 555-0100'),
    ];
    await appState.loadCatalog();
  });

  tearDown(() => appState.myAssignedSessionIds = const {});

  void sizePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpView(WidgetTester tester, {required bool canAssign}) async {
    sizePhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: EmeraldTheme.light(),
      home: SessionVolunteersView(session: session, canAssign: canAssign),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('organizers see their co-workers read-only', (tester) async {
    await pumpView(tester, canAssign: false);
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('Sam Okafor'), findsOneWidget);
    expect(find.text('Assign volunteer'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing);
  });

  testWidgets('tapping a co-worker shows their number', (tester) async {
    await pumpView(tester, canAssign: false);
    await tester.tap(find.text('Maya Chen'));
    await tester.pumpAndSettle();
    expect(find.text('(925) 555-0142'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
  });

  testWidgets('admins can still assign and remove', (tester) async {
    await pumpView(tester, canAssign: true);
    expect(find.text('Assign volunteer'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsNWidgets(2));
  });

  Future<void> pumpPage(WidgetTester tester) async {
    sizePhone(tester);
    await tester.pumpWidget(MaterialApp(
      theme: EmeraldTheme.light(),
      home: SessionDetailScreen(session: session),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a volunteer managing the session gets the Volunteers tab',
      (tester) async {
    appState.myAssignedSessionIds = {session.id};
    await pumpPage(tester);
    expect(find.widgetWithText(Tab, 'Volunteers'), findsOneWidget);
  });

  testWidgets('a plain participant gets no Volunteers tab', (tester) async {
    await pumpPage(tester);
    expect(find.widgetWithText(Tab, 'Volunteers'), findsNothing);
  });
}
