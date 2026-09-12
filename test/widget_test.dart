import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/main.dart';

void main() {
  // Register a backend before each test. With no credentials in the test
  // environment, [configureBackend] selects the in-memory sample backend —
  // exactly the standalone/demo path. Reset first so re-registration is safe,
  // then prime the catalog the way `main()` does in sample mode.
  setUp(() async {
    await getIt.reset();
    await configureBackend();
    await appState.loadCatalog();
  });

  /// Boots the app and skips past the animated splash (tap-to-skip), then lets
  /// the fade transition finish — without pumpAndSettle, which would hang on the
  /// dashboard's looping accent animations.
  Future<void> bootPastSplash(WidgetTester tester) async {
    await tester.pumpWidget(const EmeraldSummitApp());
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(); // begin the pushReplacement transition
    await tester.pump(const Duration(seconds: 1)); // finish it
  }

  testWidgets('boots past the splash into the five-tab shell',
      (WidgetTester tester) async {
    await bootPastSplash(tester);
    // The bottom navigation of the real app is now showing.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Discover'), findsWidgets);
  });

  testWidgets('Discover tab shows the disciplines',
      (WidgetTester tester) async {
    await bootPastSplash(tester);
    await tester.tap(find.text('Discover').first);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('TechVerse'), findsWidgets);
    expect(find.text('MathVerse'), findsWidgets);
  });
}
