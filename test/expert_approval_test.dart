import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/expert_approvals_screen.dart';
import 'package:emerald_summit/screens/session_detail_screen.dart';
import 'package:emerald_summit/theme.dart';

UserProfile _profile(SummitRole role, String? status) => UserProfile.fromMap({
      'id': 'u1',
      'email': 'expert@example.com',
      'full_name': 'Dana Expert',
      'role': role.id,
      'onboarded': true,
      'expert_status': status,
    });

void main() {
  tearDown(() => appState.profile = null);

  group('expert status', () {
    test('is read from the profile row', () {
      expect(_profile(SummitRole.expert, 'pending').expertStatus,
          ExpertStatus.pending);
      expect(_profile(SummitRole.expert, 'approved').expertStatus,
          ExpertStatus.approved);
      expect(_profile(SummitRole.participant, 'declined').expertStatus,
          ExpertStatus.declined);
      expect(_profile(SummitRole.participant, null).expertStatus, isNull);
    });

    test('only an approved expert gets past the waiting screen', () {
      appState.profile = _profile(SummitRole.expert, 'pending');
      expect(appState.needsExpertApproval, isTrue);
      // No status yet (e.g. the database change hasn't run) still waits.
      appState.profile = _profile(SummitRole.expert, null);
      expect(appState.needsExpertApproval, isTrue);
      appState.profile = _profile(SummitRole.expert, 'approved');
      expect(appState.needsExpertApproval, isFalse);
      appState.profile = _profile(SummitRole.participant, null);
      expect(appState.needsExpertApproval, isFalse);
    });

    test('a declined account is a participant with a note to show', () {
      appState.profile = _profile(SummitRole.participant, 'declined');
      expect(appState.needsExpertApproval, isFalse);
      expect(appState.expertRequestDeclined, isTrue);
    });

    test('the server refusal reads as a plain message', () {
      expect(projectProblemMessage('expert_not_approved'),
          'Only approved expert accounts can serve as an expert.');
    });
  });

  group('expert approvals screen', () {
    late SampleExpertsRepository repo;

    setUp(() async {
      await getIt.reset();
      await configureBackend();
      repo = SampleExpertsRepository(requests: [
        const ExpertRequest(
          userId: 'a',
          fullName: 'Ana Rivera',
          email: 'ana@example.com',
          expertise: 'Robotics',
          bio: 'I build warehouse robots',
        ),
        const ExpertRequest(
          userId: 'b',
          fullName: 'Ben Cho',
          email: 'ben@example.com',
        ),
      ]);
      getIt
        ..unregister<ExpertsRepository>()
        ..registerSingleton<ExpertsRepository>(repo);
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: EmeraldTheme.light(),
        home: const ExpertApprovalsScreen(),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lists who is waiting, with what they told us',
        (tester) async {
      await pump(tester);
      expect(find.text('Ana Rivera'), findsOneWidget);
      expect(find.text('Robotics'), findsOneWidget);
      expect(find.text('I build warehouse robots'), findsOneWidget);
      expect(find.text('Ben Cho'), findsOneWidget);
    });

    testWidgets('approve removes the card and records the approval',
        (tester) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
      await tester.pumpAndSettle();
      expect(repo.reviewed, {'a': true});
      expect(find.text('Ana Rivera'), findsNothing);
      expect(find.text('Approved Ana Rivera.'), findsOneWidget);
    });

    testWidgets('decline asks first, then records it', (tester) async {
      await pump(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Decline').last);
      await tester.pumpAndSettle();
      expect(find.text('Decline Ben Cho?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();
      expect(repo.reviewed, {'b': false});
      expect(find.text('Ben Cho'), findsNothing);
    });

    testWidgets('says so when nobody is waiting', (tester) async {
      repo.requests.clear();
      await pump(tester);
      expect(find.text('No one is waiting for approval.'), findsOneWidget);
    });
  });

  group('session page expert line', () {
    late SampleStore store;

    setUp(() async {
      await getIt.reset();
      await configureBackend();
      store = SampleStore();
      getIt
        ..unregister<CatalogRepository>()
        ..registerSingleton<CatalogRepository>(SampleCatalogRepository(store));
      await appState.loadCatalog();
    });

    Future<void> pump(WidgetTester tester, List<String> experts) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final session = store.allSessions.first;
      getIt
        ..unregister<ExpertsRepository>()
        ..registerSingleton<ExpertsRepository>(
            SampleExpertsRepository(sessionExperts: {session.id: experts}));
      await tester.pumpWidget(MaterialApp(
        theme: EmeraldTheme.light(),
        home: SessionDetailScreen(session: session),
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('is hidden until an expert registers', (tester) async {
      await pump(tester, const []);
      expect(find.textContaining('Expert:'), findsNothing);
      expect(find.textContaining('Experts:'), findsNothing);
    });

    testWidgets('names the registered expert', (tester) async {
      await pump(tester, const ['Ana Rivera']);
      expect(find.text('Expert: Ana Rivera'), findsOneWidget);
    });

    testWidgets('names every registered expert', (tester) async {
      await pump(tester, const ['Ana Rivera', 'Ben Cho']);
      expect(find.text('Experts: Ana Rivera, Ben Cho'), findsOneWidget);
    });
  });
}
