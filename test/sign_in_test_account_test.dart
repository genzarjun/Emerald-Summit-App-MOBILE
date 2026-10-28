import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/backend/auth_service.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/screens/auth/sign_in_screen.dart';

/// Signed out. `test@example.com` is the only code email, and its password is
/// either right or wrong. Records what the screen sent.
class _TestAccountAuth implements AuthService {
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
  Future<bool> isTestAccount(String email) async =>
      email.trim().toLowerCase() == 'test@example.com';
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

Future<_TestAccountAuth> _pump(WidgetTester tester, String email) async {
  await getIt.reset();
  await configureBackend();
  final auth = _TestAccountAuth();
  getIt
    ..unregister<AuthService>()
    ..registerSingleton<AuthService>(auth);
  await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
  await tester.enterText(find.byType(TextField), email);
  await tester.tap(find.text('Email me a code'));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('a real email gets a code, not a password box', (tester) async {
    final auth = await _pump(tester, 'person@example.com');
    expect(auth.otpRequests, 1);
    expect(find.widgetWithText(TextField, 'Password'), findsNothing);
    expect(find.text('Enter the code we emailed to person@example.com.'),
        findsOneWidget);
  });

  testWidgets('a test email asks for the password instead of a code', (
    tester,
  ) async {
    final auth = await _pump(tester, 'Test@Example.com');
    expect(auth.otpRequests, 0);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
  });

  testWidgets('wrong password shows the error and keeps the box', (
    tester,
  ) async {
    final auth = await _pump(tester, 'test@example.com');
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'guess',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(auth.sentEmail, 'test@example.com');
    expect(auth.sentPassword, 'guess');
    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
  });

  testWidgets('a different email goes back and clears the password', (
    tester,
  ) async {
    await _pump(tester, 'test@example.com');
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret',
    );
    await tester.tap(find.text('Use a different email'));
    await tester.pumpAndSettle();
    expect(find.text('Email me a code'), findsOneWidget);
    expect(find.text('secret'), findsNothing);
  });
}
