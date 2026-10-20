import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/auth_service.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/auth/auth_gate.dart';
import 'package:emerald_summit/screens/auth/onboarding_screen.dart';
import 'package:emerald_summit/screens/root_nav.dart';
import 'package:emerald_summit/theme.dart';

/// A signed-in session on the sample backend, so the gate runs its live path.
class _SignedInAuth implements AuthService {
  @override
  Stream<void> get authStateChanges => const Stream.empty();
  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'u1', email: 'new@example.com');
  @override
  bool get isSignedIn => true;
  @override
  Future<void> sendEmailOtp(String email) async {}
  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {}
  @override
  Future<bool> tryDevLogin(String email) async => false;
  @override
  bool get supportsGoogleSignIn => false;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async {}
}

void main() {
  setUp(() async {
    await getIt.reset();
    await configureBackend();
    getIt
      ..unregister<AuthService>()
      ..registerSingleton<AuthService>(_SignedInAuth());
    // A brand-new account: the blank profile row sign-up leaves behind.
    await profileRepository.save(
      UserProfile(
        id: 'u1',
        email: 'new@example.com',
        fullName: '',
        role: SummitRole.participant,
      ),
    );
    appState.profile = null;
  });
  tearDown(() => appState.profile = null);

  testWidgets('finishing onboarding lands in the app', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: EmeraldTheme.light(), home: const AuthGate()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, 'Sam Lee');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Pick your school'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emerald High School').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Grade'), '11');
    await tester.ensureVisible(find.text('Finish & enter the app'));
    await tester.tap(find.text('Finish & enter the app'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(RootNav), findsOneWidget);
  });

  testWidgets('changing role from Profile closes back to Profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    appState.profile = UserProfile(
      id: 'u1',
      email: 'new@example.com',
      fullName: 'Sam Lee',
      role: SummitRole.parentSpectator,
      onboarded: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: EmeraldTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnboardingScreen(),
                ),
              ),
              child: const Text('profile'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('profile'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save role'));
    await tester.tap(find.text('Save role'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('profile'), findsOneWidget);
  });
}
