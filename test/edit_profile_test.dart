import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/edit_profile_screen.dart';
import 'package:emerald_summit/theme.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    await configureBackend();
    appState.profile = UserProfile(
      id: 'u1',
      email: 'alex@example.com',
      fullName: 'Alex Rivera',
      role: SummitRole.participant,
      onboarded: true,
      details: {'school': 'Emerald High', 'grade': '11', 'old_answer': 'kept'},
    );
  });
  tearDown(() => appState.profile = null);

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: EmeraldTheme.light(),
        // A Scaffold underneath, like Profile, to show the saved snackbar.
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EditProfileScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('prefills the name and sign-up answers', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Alex Rivera'), findsOneWidget);
    expect(find.text('Emerald High'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('alex@example.com'), findsOneWidget);
  });

  testWidgets('saves edits and keeps answers from other roles', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(field('Full name'), 'Alex R.');
    await tester.enterText(field('Grade'), '12');
    await tester.enterText(field('Mobile number (optional)'), '925 555 0123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final p = appState.profile!;
    expect(p.fullName, 'Alex R.');
    expect(p.role, SummitRole.participant);
    expect(p.details, {
      'school': 'Emerald High',
      'grade': '12',
      'phone': '925 555 0123',
      'old_answer': 'kept',
    });
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('a required answer cannot be cleared', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(field('School'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('School is required.'), findsOneWidget);
    expect(appState.profile!.details['school'], 'Emerald High');
  });
}
