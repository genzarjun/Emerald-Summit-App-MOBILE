import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/screens/root_nav.dart';
import 'package:emerald_summit/theme.dart';

void main() {
  late SampleStore store;

  setUp(() async {
    await getIt.reset();
    await configureBackend();
    await appState.loadCatalog();
    store = SampleStore();
    getIt
      ..unregister<SummitRepository>()
      ..registerSingleton<SummitRepository>(SampleSummitRepository(store));
  });

  tearDown(() => appState.summitStatus = SummitStatus.unknown);

  testWidgets('coming back to the app re-checks the summit status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: EmeraldTheme.light(), home: const RootNav()),
    );
    await tester.pump();
    expect(appState.summitStatus.feedbackOpen, isFalse);

    // Feedback opens while the app sits in the background.
    store.summitStatus =
        SummitStatus(date: DateTime(2026, 1, 10), feedbackOpen: true);
    // Lifecycle states must change one step at a time.
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();

    expect(appState.summitStatus.feedbackOpen, isTrue);
    expect(appState.summitStatus.date, DateTime(2026, 1, 10));
  });
}
