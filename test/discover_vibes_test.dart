import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/screens/discipline_screen.dart';
import 'package:emerald_summit/screens/discover_screen.dart';
import 'package:emerald_summit/screens/schedule_screen.dart';
import 'package:emerald_summit/theme.dart';
import 'package:emerald_summit/widgets/discipline_vibe.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    await configureBackend();
    await appState.loadCatalog();
  });

  Widget host(Widget child) =>
      MaterialApp(theme: EmeraldTheme.light(), home: child);

  testWidgets('every live discipline id has its own personality', (_) async {
    const ids = [
      'techverse',
      'ventureverse',
      'biosphere',
      'novasphere',
      'civicverse',
      'imaginex',
    ];
    final vibes = {for (final id in ids) DisciplineVibe.forKey(id)};
    expect(vibes.length, ids.length);
    expect(vibes.contains(DisciplineVibe.emerald), isFalse);
    expect(DisciplineVibe.forKey('something-new'), DisciplineVibe.emerald);
  });

  testWidgets('Discover lays out the portal cards and finds sessions', (
    tester,
  ) async {
    await tester.pumpWidget(host(const DiscoverScreen()));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('TechVerse'), findsWidgets);

    final session = appState.disciplines.first.sessions.first;
    await tester.enterText(find.byType(TextField), session.title);
    await tester.pump();
    expect(find.text(session.title), findsWidgets);

    await tester.enterText(find.byType(TextField), 'zzzz no match');
    await tester.pump();
    expect(find.textContaining('No sessions match'), findsOneWidget);
  });

  testWidgets('each discipline page renders and filters without errors', (
    tester,
  ) async {
    for (final Discipline d in appState.disciplines) {
      await tester.pumpWidget(host(DisciplineScreen(discipline: d)));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: d.name);
      expect(find.text('Open seats'), findsOneWidget);

      await tester.tap(find.text('Afternoon'));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: '${d.name} afternoon');
    }
  });

  testWidgets('My Day sums up the day above the sessions', (
    tester,
  ) async {
    final session = appState.disciplines.first.sessions.first;
    await appState.toggle(session);
    await tester.pumpWidget(host(const ScheduleScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1 session', findRichText: true), findsOneWidget);
    expect(find.text('First up'), findsNothing);
    await appState.toggle(session); // tidy up
  });
}
