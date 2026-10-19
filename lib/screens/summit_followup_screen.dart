import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';

/// Opens the right post-summit question for the signed-in user: the feedback
/// form for experts, or "volunteer for EAF again?" for volunteers and admins.
/// Shown once per launch by the auth gate while unanswered, and from Profile.
Future<void> openSummitFollowUp(BuildContext context) async {
  if (appState.isExpert) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SummitFeedbackScreen()),
    );
  } else if (appState.isVolunteer || appState.isAdmin) {
    await showEafInterestDialog(context);
  }
}

/// "Would you like to volunteer for EAF in the future?" Yes / No. The answer
/// goes in the last column of the person's summit-day rows on the hours sheet.
Future<void> showEafInterestDialog(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Thank you for volunteering'),
      content: const Text('Would you like to volunteer for EAF in the future?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  if (answer == null) return;
  try {
    await appState.setEafInterest(answer);
    messenger.showSnackBar(
      const SnackBar(content: Text('Thanks, your answer is saved.')),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Couldn't save your answer. Try again from Profile."),
      ),
    );
  }
}

/// Post-summit feedback from an expert: a 1 to 5 rating and an optional
/// comment for the app, the summit overall, and each session they served in.
/// Session feedback goes on the volunteer hours sheet next to the volunteers
/// who managed that session. Opening it again lets the expert edit.
class SummitFeedbackScreen extends StatefulWidget {
  const SummitFeedbackScreen({super.key});

  @override
  State<SummitFeedbackScreen> createState() => _SummitFeedbackScreenState();
}

/// One question on the form.
class _Item {
  _Item(this.kind, this.title, {this.session, ExpertFeedback? saved})
    : rating = saved?.rating,
      comment = TextEditingController(text: saved?.comment ?? '');

  final FeedbackKind kind;
  final String title;
  final Session? session;
  int? rating;
  final TextEditingController comment;
}

class _SummitFeedbackScreenState extends State<SummitFeedbackScreen> {
  late final List<_Item> _items;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ExpertFeedback? saved(FeedbackKind kind, [String? sessionId]) {
      for (final f in appState.myFeedback) {
        if (f.kind == kind && f.sessionId == sessionId) return f;
      }
      return null;
    }

    _items = [
      for (final s in appState.myExpertSessions)
        _Item(
          FeedbackKind.session,
          s.title,
          session: s,
          saved: saved(FeedbackKind.session, s.id),
        ),
      _Item(
        FeedbackKind.summit,
        'The summit overall',
        saved: saved(FeedbackKind.summit),
      ),
      _Item(
        FeedbackKind.app,
        'The Emerald Summit app',
        saved: saved(FeedbackKind.app),
      ),
    ];
  }

  @override
  void dispose() {
    for (final i in _items) {
      i.comment.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_items.any((i) => i.rating == null)) {
      setState(() => _error = 'Pick a rating for each one.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await appState.submitFeedback([
        for (final i in _items)
          ExpertFeedback(
            kind: i.kind,
            sessionId: i.session?.id,
            rating: i.rating!,
            comment: i.comment.text.trim(),
          ),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your feedback.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            "Couldn't send your feedback. Check your connection and try "
            'again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Summit feedback')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Thank you for serving as an expert. Rate each one from 1 to 5 '
              'and add a comment if you like. Your feedback on your session '
              'goes on the volunteer hours record of the students who ran '
              'it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in _items) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.session != null)
                        Text(
                          'Your session',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      Text(item.title, style: theme.textTheme.titleMedium),
                      if (item.session != null)
                        Text(
                          '${item.session!.disciplineName} · '
                          '${item.session!.timeLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 8),
                      _RatingRow(
                        label: item.title,
                        value: item.rating,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() {
                                item.rating = v;
                                _error = null;
                              }),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: item.comment,
                        enabled: !_saving,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Comment (optional)',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Sending…' : 'Send feedback'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Five stars; tapping star n sets the rating to n.
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.label, this.value, this.onChanged});

  final String label;
  final int? value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (var n = 1; n <= 5; n++)
          IconButton(
            tooltip: '$n of 5 for $label',
            onPressed: onChanged == null ? null : () => onChanged!(n),
            icon: Icon(
              (value ?? 0) >= n ? Icons.star : Icons.star_border,
              color: color,
              size: 32,
            ),
          ),
      ],
    );
  }
}
