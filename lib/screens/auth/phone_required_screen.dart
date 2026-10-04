import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models/user_profile.dart';

/// Shown by the auth gate when a volunteer or admin has no mobile number on
/// file (e.g. they onboarded before it was required). The app opens once
/// they save one; it's how the rest of the team reaches them in the
/// volunteer hub.
class PhoneRequiredScreen extends StatefulWidget {
  const PhoneRequiredScreen({super.key});

  @override
  State<PhoneRequiredScreen> createState() => _PhoneRequiredScreenState();
}

class _PhoneRequiredScreenState extends State<PhoneRequiredScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _controller.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Mobile number is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the gate rebuilds (needsPhoneNumber is now false) and
      // shows the app.
      await appState.savePhoneNumber(phone);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save your number. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = appState.profile?.role ?? SummitRole.volunteer;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add your number'),
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
                  Text(
                    '${role.label}s need a mobile number on file so the '
                    'summit team can reach you.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: 'Mobile number',
                      hintText: 'For day-of coordination',
                      helperText: role.phoneNote,
                      helperMaxLines: 3,
                      errorText: _error,
                      errorMaxLines: 3,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save and continue'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : appState.signOut,
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
