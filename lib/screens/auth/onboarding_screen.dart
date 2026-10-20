import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';
import '../../backend/repositories.dart';
import '../../backend/service_locator.dart';
import '../../models/user_profile.dart';
import '../../widgets/school_picker.dart';

/// First-run account setup, shown once after a user's first sign-in (while
/// `profiles.onboarded` is false).
///
/// Two steps:
///   1. Name + role.
///   2. Role-specific details — the questions come from the chosen role
///      (see [SummitRoleX.onboardingFields]); some roles have none.
///
/// Gated roles (volunteer/admin) are verified against the synced allowlist before
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

  /// When changing role: what the switch does to the person's sessions
  /// (participating / expert / managing moved down to spectating). Null when
  /// not loaded or not a change.
  List<RoleChangeItem>? _roleChanges;

  /// True when an existing account is switching to a different role.
  bool get _changingRole => _editing && _role != appState.profile?.role;

  /// Advances every few seconds so fields with several example [ProfileField.hints]
  /// cycle through them.
  int _hintTick = 0;
  Timer? _hintTimer;

  /// True when an already-onboarded user is here to change their role, rather
  /// than a first-time sign-up. Enables a close button and re-titles the screen.
  ///
  /// Fixed when the screen opens: saving flips `isOnboarded` to true, and a
  /// live check would then treat a first-time sign-up as an edit and pop the
  /// app's only route, leaving a blank screen.
  late final bool _editing;

  @override
  void initState() {
    super.initState();
    _editing = appState.isOnboarded;
    // Prefill name + current role (e.g. changing role from Profile).
    _nameController.text = appState.profile?.fullName ?? '';
    _role = appState.profile?.role ?? SummitRole.participant;
    _syncFieldControllers();
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_step == 1 && _role.onboardingFields.any((f) => f.hints.isNotEmpty)) {
        setState(() => _hintTick++);
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
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

    // Gated roles (volunteer/admin) must be on the synced allowlist. This check is
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
              : "You aren't eligible to sign up as a volunteer.";
        });
        return;
      }
      setState(() => _busy = false);
    }

    // Show exactly what the switch does to their sessions before they save.
    List<RoleChangeItem>? changes;
    if (_changingRole) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        changes = await appState.previewRoleChange(_role);
      } catch (_) {
        changes = null;
      }
      if (!mounted) return;
      _busy = false;
    }

    setState(() {
      _error = null;
      _roleChanges = changes;
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
        // A new expert goes straight to the waiting screen: close everything
        // opened on top of the app so the auth gate's screen shows.
        if (appState.needsExpertApproval) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
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

  /// Spells out what switching role does: an expert needs approval, and each
  /// session the new role can't keep the same way moves down to spectating.
  Widget _roleChangeNotice(ThemeData theme) {
    final changes = _roleChanges ?? const <RoleChangeItem>[];
    final toExpert = _role == SummitRole.expert;
    if (changes.isEmpty && !toExpert) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onTertiaryContainer,
    );
    Widget line(String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: body),
              Expanded(child: Text(text, style: body)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.tertiary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, color: scheme.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Switching to ${_role.label}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (toExpert) ...[
            const SizedBox(height: 10),
            Text(
                'Expert accounts need an admin to approve them. Until then, '
                "you'll only see a screen saying your account is awaiting "
                'approval.',
                style: body),
          ],
          if (changes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
                _role == SummitRole.parentSpectator
                    ? 'As a ${_role.label}, you can only spectate. These '
                        'sessions change:'
                    : 'Some of your sessions change, because '
                        "${_rolePlural(_role)} can't take part in them the "
                        'way you do now:',
                style: body),
            for (final c in changes) line(describeRoleChange(c)),
          ],
        ],
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
        if (_changingRole) ...[
          _roleChangeNotice(theme),
          const SizedBox(height: 20),
        ],
        for (final field in fields) ...[
          if (field.schoolPicker)
            SchoolPicker(
              // Keyed by role so a role switch rebuilds it from the answer.
              key: ValueKey('school-${_role.id}'),
              field: field,
              controller: _fieldControllers[field.key]!,
              enabled: !_busy,
            )
          else
          TextField(
            controller: _fieldControllers[field.key],
            enabled: !_busy,
            keyboardType: field.keyboardType,
            inputFormatters: field.digitsOnly
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            minLines: field.lines,
            maxLines: field.lines,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: field.label,
              hintText: field.hints.isEmpty ? field.hint : null,
              hint: field.hints.isEmpty
                  ? null
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        field.hints[_hintTick % field.hints.length],
                        key: ValueKey(_hintTick % field.hints.length),
                        maxLines: field.lines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
              // Keep the label up so rotating examples show before focus.
              floatingLabelBehavior: field.hints.isEmpty
                  ? null
                  : FloatingLabelBehavior.always,
              helperText: field.helper,
              helperMaxLines: 3,
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_editing ? 'Save role' : 'Finish & enter the app'),
        ),
      ],
    );
  }
}

/// The role as a plain plural noun for sentences ("experts can't…").
String _rolePlural(SummitRole role) => switch (role) {
      SummitRole.participant => 'participants',
      SummitRole.expert => 'experts',
      SummitRole.parentSpectator => 'parents and spectators',
      SummitRole.volunteer => 'volunteers',
      SummitRole.admin => 'admins',
    };

/// One plain sentence for what a role change does to a session.
String describeRoleChange(RoleChangeItem c) {
  final title = '"${c.title}"';
  final base = switch ((c.from, c.to)) {
    ('managing', 'dropped') =>
      "$title: you'll stop managing it. It's full, so it will be removed "
          'from your day.',
    ('managing', 'unchanged') =>
      "$title: you'll stop managing it. You stay registered for it.",
    ('managing', _) => "$title: you'll stop managing it and spectate instead.",
    ('expert', _) =>
      "$title: you'll go from serving as an expert to spectating.",
    _ => "$title: you'll go from participating to spectating.",
  };
  final team = c.team;
  if (team == null) return base;
  final project = '"${team.projectName}"';
  return switch (team.action) {
    'handed_off' =>
      '$base Your team $project goes to ${team.toName ?? 'a teammate'}.',
    'deleted' => '$base Nobody else has joined your team $project, so it '
        'will be deleted and its code '
        '${team.code == null ? '' : '${team.code} '}will stop working.',
    _ => "$base You'll leave the team $project.",
  };
}
