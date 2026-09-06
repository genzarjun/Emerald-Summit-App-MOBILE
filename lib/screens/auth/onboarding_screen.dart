import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../backend/service_locator.dart';
import '../../models/user_profile.dart';

/// First-run account setup, shown once after a user's first sign-in (while
/// `profiles.onboarded` is false).
///
/// Two steps:
///   1. Name + role.
///   2. Role-specific details — the questions come from the chosen role
///      (see [SummitRoleX.onboardingFields]), so a mentor is asked for full
///      contact info while an expert is asked only the essentials.
///
/// Gated roles (mentor/admin) are verified against the synced allowlist before
/// the user can continue past step 1.
///
/// On finish the profile is saved through the backend and the auth gate moves
/// the user into the app.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  final _nameController = TextEditingController();
  SummitRole _role = SummitRole.participant;

  /// One controller per role-specific field, rebuilt when the role changes.
  final Map<String, TextEditingController> _fieldControllers = {};

  bool _busy = false;
  String? _error;

  /// True when an already-onboarded user is here to change their role, rather
  /// than a first-time sign-up. Enables a close button and re-titles the screen.
  bool get _editing => appState.isOnboarded;

  @override
  void initState() {
    super.initState();
    // Prefill name + current role (e.g. changing role from Profile).
    _nameController.text = appState.profile?.fullName ?? '';
    _role = appState.profile?.role ?? SummitRole.participant;
    _syncFieldControllers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Ensures there's a controller for each field the current role asks for,
  /// seeded from any previously-entered detail.
  void _syncFieldControllers() {
    final existing = appState.profile?.details ?? const {};
    for (final field in _role.onboardingFields) {
      _fieldControllers.putIfAbsent(
        field.key,
        () => TextEditingController(text: (existing[field.key] ?? '') as String),
      );
    }
  }

  Future<void> _goToDetails() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }

    // Gated roles (mentor/admin) must be on the synced allowlist. This check is
    // advisory UX — the server trigger is the real guard — but it's what lets us
    // block ineligible sign-ups with a clear message before collecting details.
    if (_role.isGated) {
      setState(() {
        _busy = true;
        _error = null;
      });
      bool eligible;
      try {
        eligible = await allowlistRepository.isEligible(_role);
      } catch (_) {
        eligible = false;
      }
      if (!mounted) return;
      if (!eligible) {
        setState(() {
          _busy = false;
          _error = _role == SummitRole.admin
              ? "You aren't eligible to sign up as an admin."
              : "You aren't eligible to sign up as a mentor.";
        });
        return;
      }
      setState(() => _busy = false);
    }

    setState(() {
      _error = null;
      _syncFieldControllers();
      _step = 1;
    });
  }

  Future<void> _finish() async {
    // Validate required role fields.
    for (final field in _role.onboardingFields) {
      if (field.required &&
          (_fieldControllers[field.key]?.text.trim().isEmpty ?? true)) {
        setState(() => _error = '${field.label} is required.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final user = authService.currentUser;
    final details = <String, dynamic>{
      for (final field in _role.onboardingFields)
        if ((_fieldControllers[field.key]?.text.trim() ?? '').isNotEmpty)
          field.key: _fieldControllers[field.key]!.text.trim(),
    };

    final profile = UserProfile(
      id: user?.id ?? appState.profile?.id ?? '',
      email: user?.email ?? appState.profile?.email ?? '',
      fullName: _nameController.text.trim(),
      role: _role,
      details: details,
    );

    try {
      await appState.completeOnboarding(profile);
      // First-time: the auth gate rebuilds on notify and shows the app.
      // Editing from Profile: pop back to where we came from.
      if (_editing && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text('You’re now a ${appState.userRole}.')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save your profile. Please try again.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing
            ? 'Change role'
            : (_step == 0 ? 'Welcome' : 'A few details')),
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy ? null : () => setState(() => _step = 0),
              )
            : (_editing
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  )
                : null),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _step == 0 ? _stepOne(context) : _stepTwo(context),
          ),
        ),
      ),
    );
  }

  // ---- Step 1: name + role -------------------------------------------------
  Widget _stepOne(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Let's set up your account",
            style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Your name and role personalize the rest of setup.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameController,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        Text('I am a…', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        ...SummitRole.values.map(_roleCard),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _goToDetails,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _roleCard(SummitRole role) {
    final theme = Theme.of(context);
    final selected = _role == role;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => setState(() => _role = role),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : null,
          ),
          child: Row(
            children: [
              Icon(role.icon,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(role.blurb,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Step 2: role-specific details ---------------------------------------
  Widget _stepTwo(BuildContext context) {
    final theme = Theme.of(context);
    final fields = _role.onboardingFields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(_role.icon, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Setting up as ${_role.label}',
                  style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          fields.isEmpty
              ? "You're all set — no extra details needed for this role."
              : 'Just a couple of role-specific details.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        for (final field in fields) ...[
          TextField(
            controller: _fieldControllers[field.key],
            enabled: !_busy,
            keyboardType: field.keyboardType,
            decoration: InputDecoration(
              labelText: field.label,
              hintText: field.hint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: _busy ? null : _finish,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_editing ? 'Save role' : 'Finish & enter the app'),
        ),
      ],
    );
  }
}
