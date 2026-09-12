import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/backend.dart';
import '../../backend/service_locator.dart';
import '../../theme.dart';

/// Passwordless email sign-in (email one-time code, via the backend seam).
///
/// Two phases in one screen:
///   1. Enter email  → the backend emails a 6-digit code (creating the account
///      on first sign-in — same screen handles sign-up and sign-in).
///   2. Enter code    → verification establishes the session.
///
/// No password is ever created or stored. On success the auth gate reacts to
/// the new session and routes onward.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim();

  bool get _emailLooksValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email);

  Future<void> _sendCode() async {
    if (!_emailLooksValid) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // TEST/DEV: a registered "code email" signs in instantly (no OTP). A no-op
      // that returns false in normal builds and for real emails, so this is
      // transparent in production.
      if (await authService.tryDevLogin(_email)) {
        // The auth gate reacts to the new session and navigates; this widget is
        // about to be disposed, so leave the spinner up.
        return;
      }
      await authService.sendEmailOtp(_email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
      });
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not send the code. Please try again.';
        _busy = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authService.verifyEmailOtp(email: _email, code: code);
      // Success: the auth gate's stream picks up the new session and navigates.
      // This widget will be disposed, so nothing more to do here.
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'That code did not work. Check it and try again.';
        _busy = false;
      });
    }
  }

  void _useDifferentEmail() {
    setState(() {
      _codeSent = false;
      _codeController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: EmeraldTheme.mist,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.eco, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Emerald Summit ’27',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _codeSent
                        ? 'Enter the code we emailed to $_email.'
                        : 'Sign in or create your account with your email — '
                            'no password needed.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  if (!_codeSent) _emailPhase(theme) else _codePhase(theme),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailPhase(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _sendCode(),
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.alternate_email),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _sendCode,
          child: _busy
              ? const _ButtonSpinner()
              : const Text('Email me a code'),
        ),
      ],
    );
  }

  Widget _codePhase(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeController,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          // The email OTP length can vary by backend (6–10); cap generously so
          // a longer-than-expected code is never silently truncated.
          maxLength: 10,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _busy ? null : _verifyCode(),
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: 'Verification code',
            counterText: '',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verifyCode,
          child:
              _busy ? const _ButtonSpinner() : const Text('Verify & continue'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _sendCode,
          child: const Text('Resend code'),
        ),
        TextButton(
          onPressed: _busy ? null : _useDifferentEmail,
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}
