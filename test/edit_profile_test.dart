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

  test('saving keeps the fields the server owns', () async {
    // The sample backend has to keep these the way the live upsert does,
    // since toMap() never sends them.
    final volunteer = UserProfile(
      id: 'u2',
      email: 'sam@example.com',
      fullName: 'Sam Lee',
      role: SummitRole.volunteer,
      onboarded: true,
      notificationsEnabled: false,
      volunteerHours: 3,
      volunteerSubtype: VolunteerSubtype.eafAmbassador,
      canEditSessions: true,
      canPostAnnouncements: true,
      managedDisciplines: ['techverse'],
      details: {'grade': '10'},
    );
    await profileRepository.save(volunteer);
    appState.profile = await profileRepository.fetchMine();

    await appState.updateProfileInfo(
      fullName: 'Sam Lee-Park',
      details: {'grade': '11'},
    );

    final p = appState.profile!;
    expect(p.fullName, 'Sam Lee-Park');
    expect(p.details, {'grade': '11'});
    expect(p.volunteerSubtype, VolunteerSubtype.eafAmbassador);
    expect(p.needsGrade, isTrue);
    expect(p.canManageDiscipline('techverse'), isTrue);
    expect(p.canPostToDiscipline('techverse'), isTrue);
    expect(p.volunteerHours, 3);
    expect(appState.notificationsEnabled, isFalse);
  });

  testWidgets('prefills the name and sign-up answers', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Alex Rivera'), findsOneWidget);
    // The old typed "Emerald High" opens on the listed school.
    expect(find.text('Emerald High School'), findsOneWidget);
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
      'school': 'Emerald High School',
      'grade': '12',
      'phone': '925 555 0123',
      'old_answer': 'kept',
    });
    expect(find.text('Profile saved.'), findsOneWidget);
  });

  testWidgets('a required answer cannot be cleared', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(field('Grade'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Grade is required.'), findsOneWidget);
    expect(appState.profile!.details['grade'], '11');
  });

  testWidgets('Other opens a box for a school that is not listed', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Emerald High School'));
    await tester.pumpAndSettle();
    // The menu opens on the current school; Other is at the bottom.
    await tester.scrollUntilVisible(
      find.text('Other (not listed)'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Other (not listed)').last);
    await tester.pumpAndSettle();

    // Other with nothing typed counts as no answer.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('School is required.'), findsOneWidget);

    await tester.enterText(field('School name'), 'Irvington High School');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(appState.profile!.details['school'], 'Irvington High School');
  });

  testWidgets('a saved school that is not listed opens on Other', (
    tester,
  ) async {
    appState.profile!.details['school'] = 'Irvington High School';
    await pumpEditor(tester);
    expect(find.text('Other (not listed)'), findsOneWidget);
    expect(field('School name'), findsOneWidget);
    expect(find.text('Irvington High School'), findsOneWidget);
  });

  testWidgets('parents and spectators may leave the school blank', (
    tester,
  ) async {
    appState.profile = UserProfile(
      id: 'u2',
      email: 'pat@example.com',
      fullName: 'Pat Kim',
      role: SummitRole.parentSpectator,
      onboarded: true,
    );
    await pumpEditor(tester);
    expect(find.text('School (optional)'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(appState.profile!.details.containsKey('school'), isFalse);
  });

  testWidgets('a participant can switch to another listed school', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('Emerald High School'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dublin High School').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(appState.profile!.details['school'], 'Dublin High School');
  });

  testWidgets('a parent can set a school and later clear it', (tester) async {
    appState.profile = UserProfile(
      id: 'u2',
      email: 'pat@example.com',
      fullName: 'Pat Kim',
      role: SummitRole.parentSpectator,
      onboarded: true,
    );
    await pumpEditor(tester);
    await tester.tap(find.text('School (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amador Valley High School').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(appState.profile!.details['school'], 'Amador Valley High School');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Amador Valley High School'), findsOneWidget);
    await tester.tap(find.text('Amador Valley High School'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('None'),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(appState.profile!.details.containsKey('school'), isFalse);
  });
}
