import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/user_profile.dart';

/// Profile → Edit profile: change the name and the role's sign-up answers
/// (phone, school, grade, expertise, bio…) without re-running onboarding. The
/// fields come from [SummitRoleX.onboardingFields], so each role edits what
/// it was asked at sign-up, with the same required rules and notes. Changing
/// the role itself stays under "Change role".
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final SummitRole _role = appState.profile!.role;
  late final _nameController = TextEditingController(
    text: appState.profile!.fullName,
  );
  late final Map<String, TextEditingController> _fieldControllers = {
    for (final f in _role.onboardingFields)
      f.key: TextEditingController(
        text: '${appState.profile!.details[f.key] ?? ''}',
      ),
  };

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    for (final f in _role.onboardingFields) {
      if (f.required && _fieldControllers[f.key]!.text.trim().isEmpty) {
        setState(() => _error = '${f.label} is required.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    // Start from what's saved so answers this role isn't asked (e.g. from a
    // previous role) survive; clearing an optional field removes it.
    final details = {...appState.profile!.details};
    for (final f in _role.onboardingFields) {
      final value = _fieldControllers[f.key]!.text.trim();
      if (value.isEmpty) {
        details.remove(f.key);
      } else {
        details[f.key] = value;
      }
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.updateProfileInfo(fullName: name, details: details);
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save your profile. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = appState.profile!;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final f in _role.onboardingFields) ...[
                    TextField(
                      controller: _fieldControllers[f.key],
                      enabled: !_busy,
                      keyboardType: f.keyboardType,
                      minLines: f.lines,
                      maxLines: f.lines,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: f.label,
                        hintText:
                            f.hint ?? (f.hints.isEmpty ? null : f.hints.first),
                        hintMaxLines: f.lines,
                        helperText: f.helper,
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _ReadOnlyRow(label: 'Email', value: profile.email),
                  _ReadOnlyRow(
                    label: 'Role',
                    value: [
                      profile.role.label,
                      if (profile.volunteerSubtype != null)
                        profile.volunteerSubtype!.label,
                    ].join(' · '),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 16),
                    child: Text(
                      'Your email is tied to your account. To switch roles, '
                      'use Change role on your profile.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
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

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
