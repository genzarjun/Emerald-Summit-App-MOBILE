import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../backend/backend.dart';
import '../../backend/service_locator.dart';
import '../../models/user_profile.dart';

/// Passwordless email sign-in (email one-time code, via the backend seam).
///
/// Opened from the "How are you joining the Summit?" screen for one [role],
/// in one of two modes, like the website:
///   * Sign in ([signUp] false) only reaches an account that already exists.
///     A new email gets "Let's create you an account!", and Continue switches
///     to Sign up and emails the code.
///   * Sign up ([signUp] true) creates the account; the sign-up questions
///     follow. An existing account that signs up just signs in.
/// [role] admin is "Organizer sign in" (admins and test accounts), which may
/// create an allowlisted admin's account. With no [role] the screen signs in
/// or creates an account as before.
///
/// Two phases: enter email → the backend emails a code; enter code →
/// verification establishes the session, and the auth gate routes onward.
///
/// TEST/DEV builds check the email first: a code email (a test account) gets a
/// password box instead of an emailed code, and the shared test-account
/// password signs straight in (see the dev-login function).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.role, this.signUp = false, this.onBack});

  final SummitRole? role;
  final bool signUp;

  /// Back to the role list; null hides the back button.
  final VoidCallback? onBack;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _codeSent = false;
  bool _testAccountMode = false;
  bool _busy = false;
  String? _error;

  /// Sign up (creates the account) rather than Sign in.
  late bool _signingUp = widget.signUp;

  /// Sign in was tried with an email that has no account.
  bool _noAccount = false;

  bool get _isOrganizer => widget.role == SummitRole.admin;

  /// Whether an email code may create a new account.
  bool get _createAccount => widget.role == null || _signingUp || _isOrganizer;

  @override
  void initState() {
    super.initState();
    // A new account starts sign-up as this role.
    if (widget.role != null) appState.pendingSignUpRole = widget.role;
  }

  void _switchMode(bool toSignUp) {
    setState(() {
      _signingUp = toSignUp;
      _noAccount = false;
      _codeSent = false;
      _codeController.clear();
      _error = null;
    });
  }

  /// "Let's create you an account!": Continue switches to Sign up and sends
  /// the code straight away.
  Future<void> _continueToSignUp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authService.sendEmailOtp(_email, createAccount: true);
      if (!mounted) return;
      setState(() {
        _signingUp = true;
        _noAccount = false;
        _codeSent = true;
        _busy = false;
      });
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
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
      _noAccount = false;
    });
    try {
      // TEST/DEV: a code email asks for the test-account password instead.
      // Always false in normal builds and for real emails.
      if (await authService.isTestAccount(_email)) {
        if (!mounted) return;
        setState(() {
          _testAccountMode = true;
          _busy = false;
        });
        return;
      }
      await authService.sendEmailOtp(_email, createAccount: _createAccount);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _busy = false;
      });
    } on NoAccountFailure {
      if (!mounted) return;
      setState(() {
        _noAccount = true;
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

  Future<void> _signInWithTestAccount() async {
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Enter the test account password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Set before the session lands: the gate reads it as soon as it loads the
    // profile, to assign the role from the allowlist instead of the picker.
    appState.markTestAccountSignIn();
    try {
      await authService.signInWithTestAccount(
        email: _email,
        password: _passwordController.text,
      );
      // The auth gate reacts to the new session and navigates; this widget is
      // about to be disposed, so leave the spinner up.
    } on AuthFailure catch (e) {
      appState.clearTestAccountSignIn();
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  void _leaveTestAccount() {
    setState(() {
      _testAccountMode = false;
      _passwordController.clear();
      _error = null;
    });
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await authService.signInWithGoogle();
      // Success (or the user cancelled): on a real session the auth gate reacts
      // and navigates; this widget is disposed. On a silent cancel, drop the
      // spinner so the screen is usable again.
      if (!mounted) return;
      if (!authService.isSignedIn) setState(() => _busy = false);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not sign in with Google. Please try again.';
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
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: widget.onBack == null
          ? null
          : AppBar(
              backgroundColor: theme.scaffoldBackgroundColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: _busy ? null : widget.onBack,
              ),
            ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The dragon badge sits on white, so clip it to a disc;
                  // that keeps it clean on the dark theme too.
                  Center(
                    child: ClipOval(
                      child: Image.asset(
                        'assets/branding/logo.png',
                        width: 112,
                        height: 112,
                        fit: BoxFit.cover,
                        semanticLabel: 'Emerald Summit logo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _heading,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _testAccountMode
                        ? '$_email is a test account. Enter the test '
                              'account password.'
                        : _codeSent
                        ? 'Enter the code we emailed to $_email.'
                        : _subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_testAccountMode)
                    _testAccountPhase()
                  else if (!_codeSent)
                    _emailPhase(theme)
                  else
                    _codePhase(theme),
                  if (_noAccount) ...[
                    const SizedBox(height: 16),
                    _noAccountCard(theme),
                  ],
                  if (widget.role != null &&
                      !_isOrganizer &&
                      !_testAccountMode) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _signingUp
                              ? 'Already have an account?'
                              : 'New to the Summit?',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _switchMode(!_signingUp),
                          child: Text(_signingUp ? 'Sign in' : 'Sign up'),
                        ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
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

  String get _heading {
    final role = widget.role;
    if (role == null) return 'Emerald Summit ’27';
    if (_isOrganizer) return 'Organizer sign in';
    return _signingUp ? 'Sign up as ${role.label}' : 'Sign in as ${role.label}';
  }

  String get _subtitle {
    if (widget.role == null) {
      return 'Sign in or create your account with your email. No password '
          'needed.';
    }
    if (_isOrganizer) return 'For Summit admins and test accounts.';
    return _signingUp
        ? 'Continue with Google or your email, then tell us a bit about '
              'yourself.'
        : 'Use the email on your account. No password needed.';
  }

  Widget _noAccountCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Let's create you an account!",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            "There's no account for $_email yet. Press Continue to enter "
            'some information and create your ${widget.role?.label ?? ''} '
            'account.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _continueToSignUp,
            child: _busy ? const _ButtonSpinner() : const Text('Continue'),
          ),
        ],
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
          child: _busy ? const _ButtonSpinner() : const Text('Email me a code'),
        ),
        if (authService.supportsGoogleSignIn) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signInWithGoogle,
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
        ],
      ],
    );
  }

  Widget _testAccountPhase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _passwordController,
          enabled: !_busy,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _signInWithTestAccount(),
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _signInWithTestAccount,
          child: _busy ? const _ButtonSpinner() : const Text('Sign in'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _leaveTestAccount,
          child: const Text('Use a different email'),
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
          child: _busy
              ? const _ButtonSpinner()
              : const Text('Verify & continue'),
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
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
