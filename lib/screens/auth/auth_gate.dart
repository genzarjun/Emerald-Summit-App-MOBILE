import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../backend/service_locator.dart';
import '../root_nav.dart';
import '../summit_followup_screen.dart';
import 'expert_pending_screen.dart';
import 'grade_required_screen.dart';
import 'onboarding_screen.dart';
import 'phone_required_screen.dart';
import 'sign_in_screen.dart';

/// Decides what the user sees based on auth + profile state:
///
///   no session          → [SignInScreen]
///   session, no profile → [OnboardingScreen]
///   expert not yet approved by an admin → [ExpertPendingScreen]
///   volunteer/admin with no mobile number → [PhoneRequiredScreen]
///   student volunteer / ambassador with no grade → [GradeRequiredScreen]
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
  /// The post-summit question opens by itself once per launch.
  bool _followUpShown = false;

  /// The "expert request declined" note is shown once per launch until the
  /// person closes it, which clears it for good.
  bool _declineShown = false;

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
        // Expert accounts wait for an admin's approval before using the app.
        if (appState.needsExpertApproval) {
          return const ExpertPendingScreen();
        }
        // Volunteers and admins must have a number on file for the volunteer
        // hub; anyone who onboarded before that was required adds it now.
        if (appState.needsPhoneNumber) {
          return const PhoneRequiredScreen();
        }
        // Student volunteers and EAF ambassadors need a grade for the hours
        // sheet; their subtype is only known after sign-up, so ask here.
        if (appState.needsGrade) {
          return const GradeRequiredScreen();
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
        if (appState.expertRequestDeclined && !_declineShown) {
          _declineShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showExpertDeclined();
          });
        }
        // After the summit: ask experts for feedback and volunteers/admins
        // whether they'd volunteer again, once per launch until answered.
        if (appState.followUpPending && !_followUpShown) {
          _followUpShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) openSummitFollowUp(context);
          });
        }
        return const RootNav();
      },
    );
  }

  Future<void> _showExpertDeclined() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: const Text("Your expert request wasn't approved"),
        content: const Text(
          'An admin reviewed your sign-up and did not approve it as an expert '
          'account, so your account is now a participant account. If you '
          'think this is a mistake, email president@ehsacademics.org.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    try {
      await appState.acknowledgeExpertDecline();
    } catch (_) {
      // Shown again on the next launch; nothing else depends on it.
    }
  }
}
