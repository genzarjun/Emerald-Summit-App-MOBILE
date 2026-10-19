import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_state.dart';

/// Shown by the auth gate when a student volunteer or EAF ambassador has no
/// grade on file. Their subtype only arrives from the allowlist after sign-up,
/// so this is where they're asked. The grade goes on the volunteer hours
/// sheet. The app opens once they save one.
class GradeRequiredScreen extends StatefulWidget {
  const GradeRequiredScreen({super.key});

  @override
  State<GradeRequiredScreen> createState() => _GradeRequiredScreenState();
}

class _GradeRequiredScreenState extends State<GradeRequiredScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final grade = _controller.text.trim();
    if (grade.isEmpty) {
      setState(() => _error = 'Grade is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the gate rebuilds (needsGrade is now false) and shows the
      // app.
      await appState.saveGrade(grade);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save your grade. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtype = appState.volunteerSubtypeLabel ?? 'Student Volunteer';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add your grade'),
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
                    "You're signed up as a $subtype. What grade are you in? "
                    'It goes on your volunteer hours record.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autofocus: true,
                    enabled: !_busy,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: 'Grade',
                      hintText: 'e.g. 11',
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
