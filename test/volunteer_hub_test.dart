import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/volunteer_hub_screen.dart';
import 'package:emerald_summit/theme.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    await configureBackend();
  });

  Future<void> pumpHub(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: EmeraldTheme.light(),
      home: const VolunteerHubScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists volunteers tagged student / parent', (tester) async {
    await pumpHub(tester);
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Priya Natarajan'), findsOneWidget);
    expect(find.text('Parent'), findsOneWidget);
    // Numbers stay off the list until a card is opened.
    expect(find.text('(925) 555-0142'), findsNothing);
  });

  testWidgets('tapping a card shows their phone number', (tester) async {
    await pumpHub(tester);
    await tester.tap(find.text('Maya Chen'));
    await tester.pumpAndSettle();
    expect(find.text('(925) 555-0142'), findsOneWidget);
    expect(find.text('Student Volunteer'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('filter chips narrow to one subtype', (tester) async {
    await pumpHub(tester);
    await tester.tap(find.text('Parents (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Priya Natarajan'), findsOneWidget);
    expect(find.text('Maya Chen'), findsNothing);
  });

  test('volunteer sign-up notes the number is shared with volunteers', () {
    final phone = SummitRole.volunteer.onboardingFields
        .firstWhere((f) => f.key == 'phone');
    expect(
        phone.helper,
        'Your phone number will be visible to other volunteers the day of '
        'for communication with them.');
  });
}
