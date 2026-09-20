import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../backend/service_locator.dart';
import '../root_nav.dart';
import 'onboarding_screen.dart';
import 'sign_in_screen.dart';

/// Decides what the user sees based on auth + profile state:
///
///   no session          → [SignInScreen]
///   session, no profile → [OnboardingScreen]
///   session, onboarded  → the app ([RootNav])
///
/// Rebuilds automatically whenever the backend's auth state changes (sign-in,
/// sign-out, token refresh). Only used with a live backend; in sample mode
/// `main` shows [RootNav] directly.
///
/// Stateful so the auth-state subscription is captured ONCE in [initState] and
/// held for the gate's whole lifetime. If the stream were re-read on every
/// build, an ancestor rebuild (e.g. the iOS keyboard opening/closing) could make
/// [StreamBuilder] tear down and re-create its subscription — and a sign-in
/// event landing in that gap on a broadcast, no-replay stream would be lost,
/// stranding the user on the sign-in screen until an app resume. One stable
/// subscription, established before sign-in even happens, closes that race.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<void> _authStateChanges = authService.authStateChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<void>(
      stream: _authStateChanges,
      builder: (context, _) {
        if (!authService.isSignedIn) return const SignInScreen();
        return const _ProfileLoader();
      },
    );
  }
}

/// Loads the signed-in user's profile, then routes to onboarding or the app.
class _ProfileLoader extends StatefulWidget {
  const _ProfileLoader();

  @override
  State<_ProfileLoader> createState() => _ProfileLoaderState();
}

class _ProfileLoaderState extends State<_ProfileLoader> {
  @override
  void initState() {
    super.initState();
    // Load once for this session; the gate remounts this widget on sign-in.
    WidgetsBinding.instance.addPostFrameCallback((_) => appState.loadProfile());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.profileLoading && appState.profile == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!appState.isOnboarded) {
          return const OnboardingScreen();
        }
        // A dev-login test account was auto-assigned its role — tell the tester
        // once, as the final "sign-in step", before the app proper.
        final notice = appState.consumeTestAccountNotice();
        if (notice != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: const Icon(Icons.science_outlined),
                title: const Text('Testing account'),
                content: Text(notice),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            );
          });
        }
        return const RootNav();
      },
    );
  }
}
