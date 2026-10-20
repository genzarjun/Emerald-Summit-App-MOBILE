import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import 'onboarding_screen.dart';

/// Shown by the auth gate while an expert account waits for an admin's
/// approval. It's the only screen such an account sees. The profile is
/// re-read on "Check again" and whenever the app comes back to the
/// foreground, so an approval opens the app without signing out.
class ExpertPendingScreen extends StatefulWidget {
  const ExpertPendingScreen({super.key});

  /// Who to email about expert approval.
  static const contactEmail = 'nysha.singhal@ehsacademics.org';

  @override
  State<ExpertPendingScreen> createState() => _ExpertPendingScreenState();
}

class _ExpertPendingScreenState extends State<ExpertPendingScreen>
    with WidgetsBindingObserver {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      await appState.refreshProfile();
    } catch (_) {
      // Offline or similar: stay on this screen and try again later.
    }
  }

  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    await _refresh();
    if (!mounted) return;
    setState(() => _checking = false);
    // Approved: the gate swaps this screen for the app on its own.
    if (appState.needsExpertApproval) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Not approved yet.')),
        );
    }
  }

  Future<void> _email() async {
    final ok = await launchUrl(
      Uri(scheme: 'mailto', path: ExpertPendingScreen.contactEmail),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open your email app."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = appState.profile;
    final expertise = '${profile?.details['expertise'] ?? ''}'.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Awaiting approval'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your expert account is awaiting approval',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'An admin checks every expert sign-up to make sure the '
                    "person is who they say they are. You'll be able to use "
                    'the app as soon as your account is approved.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (profile != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile.fullName,
                              style: theme.textTheme.titleSmall),
                          if (expertise.isNotEmpty)
                            Text(expertise, style: theme.textTheme.bodyMedium),
                          Text(
                            profile.email,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    "If your account isn't approved within 48 hours, email "
                    'us at:',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  TextButton.icon(
                    onPressed: _email,
                    icon: const Icon(Icons.mail_outline),
                    label: const Text(ExpertPendingScreen.contactEmail),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _checking ? null : _checkAgain,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Check again'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _checking
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const OnboardingScreen(),
                              ),
                            ),
                    child: const Text('Sign up as something else'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _checking ? null : appState.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
