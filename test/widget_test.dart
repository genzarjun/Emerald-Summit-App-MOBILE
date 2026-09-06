import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/main.dart';

void main() {
  // Register a backend before each test. With no credentials in the test
  // environment, [configureBackend] selects the in-memory sample backend —
  // exactly the standalone/demo path. Reset first so re-registration is safe.
  setUp(() async {
    await getIt.reset();
    await configureBackend();
  });

  testWidgets('Starts on My Day with an empty plan',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EmeraldSummitApp());

    expect(find.text('Your day is a blank slate'), findsOneWidget);
    expect(find.text('Browse sessions'), findsOneWidget);
  });

  testWidgets('Discover tab shows the six disciplines',
      (WidgetTester tester) async {
    await tester.pumpWidget(const EmeraldSummitApp());

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();

    expect(find.text('TechVerse'), findsOneWidget);
    expect(find.text('RoboSphere'), findsOneWidget);
    expect(find.text('MathVerse'), findsOneWidget);
  });
}
