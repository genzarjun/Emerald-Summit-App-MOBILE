import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/backend/auth_service.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/screens/auth/sign_in_screen.dart';

/// Signed out; test accounts on or off, and a password that is either right or
/// wrong. Records what the screen sent.
class _TestAccountAuth implements AuthService {
  _TestAccountAuth({required this.supportsTestAccounts});

  @override
  final bool supportsTestAccounts;

  String? sentEmail;
  String? sentPassword;
  int otpRequests = 0;

  @override
  Stream<void> get authStateChanges => const Stream.empty();
  @override
  AuthUser? get currentUser => null;
  @override
  bool get isSignedIn => false;
  @override
  Future<void> sendEmailOtp(String email) async => otpRequests++;
  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String code,
  }) async {}
  @override
  Future<void> signInWithTestAccount({
    required String email,
    required String password,
  }) async {
    sentEmail = email;
    sentPassword = password;
    if (password != 'right-password') {
      throw const AuthFailure('Wrong email or password.');
    }
  }

  @override
  bool get supportsGoogleSignIn => false;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signOut() async {}
}

Future<_TestAccountAuth> _pump(WidgetTester tester, {required bool on}) async {
  await getIt.reset();
  await configureBackend();
  final auth = _TestAccountAuth(supportsTestAccounts: on);
  getIt
    ..unregister<AuthService>()
    ..registerSingleton<AuthService>(auth);
  await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
  return auth;
}

void main() {
  testWidgets('no test-account link unless the build allows it', (tester) async {
    await _pump(tester, on: false);
    expect(find.text('Sign in to a test account'), findsNothing);
  });

  testWidgets('a normal email never goes to the test sign-in', (tester) async {
    final auth = await _pump(tester, on: true);
    await tester.enterText(find.byType(TextField), 'admin@example.com');
    await tester.tap(find.text('Email me a code'));
    await tester.pumpAndSettle();
    expect(auth.otpRequests, 1);
    expect(auth.sentEmail, isNull);
  });

  testWidgets('wrong password shows the error and keeps the form', (
    tester,
  ) async {
    final auth = await _pump(tester, on: true);
    await tester.tap(find.text('Sign in to a test account'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Test account email'),
      'Admin@Example.com ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'guess',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(auth.sentEmail, 'Admin@Example.com');
    expect(auth.sentPassword, 'guess');
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('back returns to email sign-in and clears the password', (
    tester,
  ) async {
    await _pump(tester, on: true);
    await tester.tap(find.text('Sign in to a test account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret',
    );
    await tester.tap(find.text('Back to email sign-in'));
    await tester.pumpAndSettle();
    expect(find.text('Email me a code'), findsOneWidget);
    expect(find.text('secret'), findsNothing);
  });
}
