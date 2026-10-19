import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/summit_followup_screen.dart';
import 'package:emerald_summit/theme.dart';

UserProfile _volunteer(VolunteerSubtype subtype, {String? grade}) =>
    UserProfile.fromMap({
      'id': 'v',
      'email': 'v@e.com',
      'role': 'volunteer',
      'onboarded': true,
      'volunteer_subtype': subtype.id,
      'details': {'phone': '555', 'grade': ?grade},
    });

void main() {
  group('grade', () {
    tearDown(() => appState.profile = null);

    test('student volunteers and ambassadors must give one', () {
      for (final s in [
        VolunteerSubtype.studentVolunteer,
        VolunteerSubtype.eafAmbassador,
      ]) {
        appState.profile = _volunteer(s);
        expect(appState.needsGrade, isTrue, reason: s.name);
        expect(appState.profile!.formFields.any((f) => f.key == 'grade'),
            isTrue);
        appState.profile = _volunteer(s, grade: '11');
        expect(appState.needsGrade, isFalse);
      }
    });

    test('parent volunteers are never asked', () {
      appState.profile = _volunteer(VolunteerSubtype.parentVolunteer);
      expect(appState.needsGrade, isFalse);
      expect(appState.profile!.formFields.any((f) => f.key == 'grade'),
          isFalse);
    });

    test('admins get an optional grade at sign-up', () {
      final f = SummitRole.admin.onboardingFields
          .firstWhere((f) => f.key == 'grade');
      expect(f.required, isFalse);
      appState.profile = UserProfile(
          id: 'a', email: 'a@e.com', role: SummitRole.admin, onboarded: true);
      expect(appState.needsGrade, isFalse);
    });
  });

  group('follow-ups', () {
    late SampleStore store;

    setUp(() async {
      await getIt.reset();
      await configureBackend();
      store = SampleStore();
      getIt
        ..unregister<SummitRepository>()
        ..registerSingleton<SummitRepository>(SampleSummitRepository(store));
    });

    tearDown(() {
      appState.profile = null;
      appState.summitStatus = SummitStatus.unknown;
      appState.myFeedback = const [];
      appState.myEafInterest = null;
    });

    test('nothing is pending before feedback opens', () async {
      appState.profile = UserProfile(
          id: 'e', email: 'e@e.com', role: SummitRole.expert, onboarded: true);
      await appState.loadSummitStatus();
      expect(appState.followUpPending, isFalse);
    });

    test('experts are asked until they send feedback', () async {
      store.summitStatus =
          SummitStatus(date: DateTime(2026, 1, 10), feedbackOpen: true);
      appState.profile = UserProfile(
          id: 'e', email: 'e@e.com', role: SummitRole.expert, onboarded: true);
      await appState.loadSummitStatus();
      expect(appState.followUpPending, isTrue);
      await appState.submitFeedback(const [
        ExpertFeedback(kind: FeedbackKind.app, rating: 4),
      ]);
      expect(appState.followUpPending, isFalse);
    });

    test('volunteers are asked until they answer', () async {
      store.summitStatus =
          SummitStatus(date: DateTime(2026, 1, 10), feedbackOpen: true);
      appState.profile = _volunteer(VolunteerSubtype.parentVolunteer);
      await appState.loadSummitStatus();
      expect(appState.followUpPending, isTrue);
      await appState.setEafInterest(false);
      expect(appState.followUpPending, isFalse);
      expect(store.eafInterest, isFalse);
    });

    test('participants are never asked', () async {
      store.summitStatus =
          SummitStatus(date: DateTime(2026, 1, 10), feedbackOpen: true);
      appState.profile = UserProfile(id: 'p', email: 'p@e.com', onboarded: true);
      await appState.loadSummitStatus();
      expect(appState.followUpPending, isFalse);
    });

    Future<void> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(375 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(theme: EmeraldTheme.light(), home: home));
      await tester.pumpAndSettle();
    }

    testWidgets('feedback form needs every rating, then saves',
        (tester) async {
      store.summitStatus =
          SummitStatus(date: DateTime(2026, 1, 10), feedbackOpen: true);
      appState.profile = UserProfile(
          id: 'e', email: 'e@e.com', role: SummitRole.expert, onboarded: true);
      await pump(tester, const SummitFeedbackScreen());

      expect(find.text('The summit overall'), findsOneWidget);
      expect(find.text('The Emerald Summit app'), findsOneWidget);

      await tester.tap(find.byTooltip('5 of 5 for The summit overall'));
      await tester.pump();
      await tester.tap(find.text('Send feedback'));
      await tester.pump();
      expect(find.text('Pick a rating for each one.'), findsOneWidget);
      expect(store.expertFeedback, isEmpty);

      await tester.tap(find.byTooltip('3 of 5 for The Emerald Summit app'));
      await tester.enterText(
          find.widgetWithText(TextField, 'Comment (optional)').last,
          'Schedule was easy to follow');
      await tester.tap(find.text('Send feedback'));
      await tester.pumpAndSettle();

      expect(store.expertFeedback, hasLength(2));
      final app =
          store.expertFeedback.firstWhere((f) => f.kind == FeedbackKind.app);
      expect(app.rating, 3);
      expect(app.comment, 'Schedule was easy to follow');
    });

    testWidgets('volunteer yes/no dialog saves the answer', (tester) async {
      store.summitStatus =
          SummitStatus(date: DateTime(2026, 1, 10), feedbackOpen: true);
      appState.profile = _volunteer(VolunteerSubtype.studentVolunteer,
          grade: '11');
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openSummitFollowUp(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Would you like to volunteer for EAF in the future?'),
          findsOneWidget);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(store.eafInterest, isTrue);
    });
  });
}
