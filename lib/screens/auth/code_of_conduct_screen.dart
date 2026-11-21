import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models/code_of_conduct.dart';
import '../../models/user_profile.dart';

/// The last sign-up step, and a one-time step for accounts that signed up
/// before it existed: read the role's agreement ([agreementFor]: the Guest
/// Expert Policy for experts, the Code of Conduct for everyone else) in a
/// window (Expand opens it full screen), answer the photo permission
/// question when the agreement has one, and tick the box. Shown by the auth
/// gate while [AppState.needsCodeOfConduct].
class CodeOfConductScreen extends StatefulWidget {
  const CodeOfConductScreen({super.key});

  @override
  State<CodeOfConductScreen> createState() => _CodeOfConductScreenState();
}

class _CodeOfConductScreenState extends State<CodeOfConductScreen> {
  bool _agreed = false;

  /// The photo permission answer: true grants, false does not; null until
  /// one is picked.
  bool? _photoConsent;
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await appState.agreeToCodeOfConduct(photoConsent: _photoConsent);
      // The auth gate moves on once the profile says it is agreed.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save that. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agreement = agreementFor(
      appState.profile?.role ?? SummitRole.participant,
    );
    final media = agreement.mediaChoice;
    final ready = _agreed && (media == null || _photoConsent != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(agreement.name),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Text('One last step', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  '${agreement.whoAgrees} Read it below, or expand it to '
                  'read it full screen.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                CodeOfConductWindow(agreement: agreement),
                if (media != null) ...[
                  const SizedBox(height: 20),
                  Text(media.section, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    media.prompt,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  RadioGroup<bool>(
                    groupValue: _photoConsent,
                    onChanged: (v) {
                      if (!_busy) setState(() => _photoConsent = v);
                    },
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          value: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            media.grant,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        RadioListTile<bool>(
                          value: false,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            media.doNotGrant,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _agreed,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _agreed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(agreement.checkbox),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: ready && !_busy ? _continue : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Agree and continue'),
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
    );
  }
}

/// An agreement in a bordered, scrollable window, with Expand to read it
/// full screen.
class CodeOfConductWindow extends StatefulWidget {
  const CodeOfConductWindow({
    super.key,
    required this.agreement,
    this.height = 260,
  });

  final SummitAgreement agreement;
  final double height;

  @override
  State<CodeOfConductWindow> createState() => _CodeOfConductWindowState();
}

class _CodeOfConductWindowState extends State<CodeOfConductWindow> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _expand(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(widget.agreement.name)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [CodeOfConductText(agreement: widget.agreement)],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: widget.height,
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: CodeOfConductText(agreement: widget.agreement),
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          TextButton.icon(
            onPressed: () => _expand(context),
            icon: const Icon(Icons.open_in_full, size: 18),
            label: const Text('Expand'),
          ),
        ],
      ),
    );
  }
}

/// A whole agreement as the document lays it out: title, the lines under it,
/// and each section's paragraphs and bullets. The photo question is left
/// out: [CodeOfConductScreen] asks it below the window.
class CodeOfConductText extends StatelessWidget {
  const CodeOfConductText({super.key, required this.agreement});

  final SummitAgreement agreement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.45);

    Widget block(AgreementBlock b) {
      final lead = b.lead;
      final text = Text.rich(
        TextSpan(
          children: [
            if (lead != null)
              TextSpan(
                text: b.text.isEmpty ? '$lead:' : '$lead: ',
                style: b.italicLead
                    ? const TextStyle(fontStyle: FontStyle.italic)
                    : const TextStyle(fontWeight: FontWeight.w700),
              ),
            TextSpan(text: b.text),
          ],
        ),
        style: body,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: b.bullet
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: body),
                  Expanded(child: text),
                ],
              )
            : text,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(agreement.title, style: theme.textTheme.titleMedium),
        for (final line in agreement.preamble) ...[
          const SizedBox(height: 6),
          Text(line, style: body?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        for (final section in agreement.sections) ...[
          const SizedBox(height: 16),
          Text(
            section.title,
            style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
          for (final b in section.blocks) block(b),
        ],
      ],
    );
  }
}
