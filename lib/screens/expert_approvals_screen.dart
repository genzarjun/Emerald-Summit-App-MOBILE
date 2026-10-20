import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/repositories.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';

/// Admins approve or decline expert accounts here. An expert account can't
/// use the app until it's approved; a declined one becomes a participant.
/// `fetch_expert_requests` / `review_expert` enforce admin-only server-side.
class ExpertApprovalsScreen extends StatefulWidget {
  const ExpertApprovalsScreen({super.key});

  @override
  State<ExpertApprovalsScreen> createState() => _ExpertApprovalsScreenState();
}

class _ExpertApprovalsScreenState extends State<ExpertApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<ExpertRequest> _requests = const [];

  /// Requests with a review in flight, so their buttons can't be hit twice.
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _requests.isEmpty;
      _error = null;
    });
    try {
      final list = await expertsRepository.fetchRequests();
      appState.expertRequests = list;
      if (!mounted) return;
      setState(() {
        _requests = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load expert sign-ups. Check your connection and "
            'try again.';
        _loading = false;
      });
    }
  }

  Future<void> _review(ExpertRequest r, {required bool approve}) async {
    final name = r.fullName.isEmpty ? r.email : r.fullName;
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Decline $name?'),
          content: const Text(
            'Their account becomes a participant account, and any sessions '
            "they signed up for as an expert are removed. They'll see a note "
            'saying their expert request was not approved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Decline'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(r.userId));
    try {
      final done = await expertsRepository.review(r.userId, approve: approve);
      // Keeps the counts on Profile and the Home avatar in step.
      appState.loadExpertRequests();
      if (!mounted) return;
      setState(() {
        _busy.remove(r.userId);
        _requests = [
          for (final x in _requests)
            if (x.userId != r.userId) x,
        ];
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              !done
                  ? '$name was already reviewed or changed roles.'
                  : approve
                      ? 'Approved $name.'
                      : 'Declined $name.',
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(r.userId));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't save that. Try again.")),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Expert approvals')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _Message(
                    text: _error!,
                    action: FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        Text(
                          'Expert accounts stay on a waiting screen until '
                          'you approve them. Check that each person is who '
                          'they say they are before approving.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_requests.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: Text(
                              'No one is waiting for approval.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        for (final r in _requests)
                          _RequestCard(
                            request: r,
                            busy: _busy.contains(r.userId),
                            onApprove: () => _review(r, approve: true),
                            onDecline: () => _review(r, approve: false),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
  });

  final ExpertRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final r = request;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              r.fullName.isEmpty ? 'No name given' : r.fullName,
              style: theme.textTheme.titleMedium,
            ),
            if (r.expertise != null)
              Text(
                r.expertise!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            if (r.bio != null) line(Icons.format_quote_outlined, r.bio!),
            line(Icons.mail_outline, r.email),
            if (r.phone != null) line(Icons.phone_outlined, r.phone!),
            if (r.requestedAt != null) ...[
              const SizedBox(height: 6),
              Text('Signed up ${formatDeadline(r.requestedAt!)}',
                  style: muted),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onApprove,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            action,
          ],
        ),
      ),
    );
  }
}
