import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/volunteer_hub_screen.dart';
import 'package:emerald_summit/theme.dart';

/// Records every URL the app asks the OS to open instead of opening it.
class _FakeLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final launched = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

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

  testWidgets('lists volunteers and admins with clear tags', (tester) async {
    await pumpHub(tester);
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('Student Volunteer'), findsOneWidget);
    expect(find.text('Priya Natarajan'), findsOneWidget);
    expect(find.text('Parent Volunteer'), findsOneWidget);
    expect(find.text('Sam Okafor'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    // Section headers.
    expect(find.text('Student Volunteers · 1'), findsOneWidget);
    expect(find.text('Parent Volunteers · 1'), findsOneWidget);
    expect(find.text('Admins · 1'), findsOneWidget);
    // Numbers stay off the list until a card is opened.
    expect(find.text('(925) 555-0142'), findsNothing);
  });

  testWidgets('tapping a card shows their phone number', (tester) async {
    await pumpHub(tester);
    await tester.tap(find.text('Maya Chen'));
    await tester.pumpAndSettle();
    expect(find.text('(925) 555-0142'), findsOneWidget);
    // Once on the card, once in the sheet.
    expect(find.text('Student Volunteer'), findsNWidgets(2));
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('filter chips narrow to one subtype', (tester) async {
    await pumpHub(tester);
    await tester.tap(find.text('Parent Volunteers (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Priya Natarajan'), findsOneWidget);
    expect(find.text('Maya Chen'), findsNothing);

    await tester.tap(find.text('Admins (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Sam Okafor'), findsOneWidget);
    expect(find.text('Priya Natarajan'), findsNothing);
  });

  test('volunteer sign-up notes the number is shared with volunteers', () {
    final phone = SummitRole.volunteer.onboardingFields
        .firstWhere((f) => f.key == 'phone');
    expect(
        phone.helper,
        'Your phone number will be visible to other volunteers the day of '
        'for communication with them.');
  });

  test('admin sign-up requires a phone number', () {
    final phone = SummitRole.admin.onboardingFields
        .firstWhere((f) => f.key == 'phone');
    expect(phone.required, isTrue);
    expect(phone.helper, contains('visible to volunteers and other admins'));
  });

  test('only volunteers and admins must have a phone on file', () {
    expect(SummitRole.admin.requiresPhone, isTrue);
    expect(SummitRole.volunteer.requiresPhone, isTrue);
    expect(SummitRole.participant.requiresPhone, isFalse);
    expect(SummitRole.expert.requiresPhone, isFalse);
  });

  test('an onboarded admin with no number is asked for one', () {
    addTearDown(() => appState.profile = null);
    UserProfile admin(Map<String, dynamic> details) => UserProfile(
        id: 'a1',
        email: 'a@b.com',
        role: SummitRole.admin,
        onboarded: true,
        details: details);

    appState.profile = admin({});
    expect(appState.needsPhoneNumber, isTrue);
    appState.profile = admin({'phone': '  '});
    expect(appState.needsPhoneNumber, isTrue);
    appState.profile = admin({'phone': '925 555 0100'});
    expect(appState.needsPhoneNumber, isFalse);
    appState.profile = UserProfile(
        id: 'p1', email: 'p@b.com', onboarded: true);
    expect(appState.needsPhoneNumber, isFalse);
  });

  testWidgets('Call and Text open the dialer and messages with the number',
      (tester) async {
    final launcher = _FakeLauncher();
    final original = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = original);

    await pumpHub(tester);
    await tester.tap(find.text('Maya Chen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call'));
    await tester.pump();
    await tester.tap(find.text('Text'));
    await tester.pump();

    // '(925) 555-0142' is stripped to digits so every dialer accepts it.
    expect(launcher.launched, ['tel:9255550142', 'sms:9255550142']);
  });
}
