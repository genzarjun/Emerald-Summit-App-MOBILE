import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme.dart';
import 'session_volunteers_screen.dart';

/// The rich "marketing page" for a single session, with the primary
/// action to add/remove it from the day plan. Enforces the schedule
/// rules (spec section 04): no double-booking, capacity caps.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.session});
  final Session session;

  Future<void> _onToggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await appState.toggle(session);
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    switch (result.outcome) {
      case AddOutcome.added:
        messenger.showSnackBar(
          SnackBar(content: Text('Added "${session.title}" to your day')),
        );
      case AddOutcome.removed:
        messenger.showSnackBar(
          SnackBar(content: Text('Removed "${session.title}" from your day')),
        );
      case AddOutcome.full:
        _showBlockedDialog(
          context,
          'Session full',
          'This session has reached its capacity of ${session.capacity}. '
              'You can still join the waitlist on the day.',
        );
      case AddOutcome.conflict:
        _showBlockedDialog(
          context,
          'Time conflict',
          'This overlaps with "${result.conflictingTitle}", which is '
              'already on your schedule. Remove that one first to add this.',
        );
    }
  }

  void _showBlockedDialog(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(session.disciplineName)),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          // Show the latest version from the live catalog so seats/enrolled
          // stay accurate; fall back to the one we were handed.
          final current = appState.allSessions.firstWhere(
            (s) => s.id == session.id,
            orElse: () => session,
          );
          final registered = appState.isRegistered(current.id);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(current.track.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    letterSpacing: 1,
                  )),
              const SizedBox(height: 6),
              Text(current.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              _InfoRow(icon: Icons.schedule, text: current.timeLabel),
              _InfoRow(icon: Icons.place, text: current.room),
              _InfoRow(
                  icon: Icons.person, text: 'Expert: ${current.expertName}'),
              _InfoRow(
                icon: Icons.groups,
                text: current.isFull
                    ? 'Full (${current.enrolled}/${current.capacity})'
                    : '${current.seatsLeft} of ${current.capacity} seats left',
              ),
              const SizedBox(height: 20),
              Text('About this session', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(current.description, style: theme.textTheme.bodyLarge),
              if (current.sponsor != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: EmeraldTheme.mist,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.handshake,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(current.sponsor!,
                            style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () {
                  _onToggle(context);
                },
                style: registered
                    ? FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      )
                    : null,
                icon: Icon(registered ? Icons.remove_circle : Icons.add),
                label: Text(
                    registered ? 'Remove from my day' : 'Add to my day'),
              ),
              if (appState.isAdmin) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SessionVolunteersScreen(session: current),
                    ),
                  ),
                  icon: const Icon(Icons.groups_2_outlined),
                  label: const Text('Manage volunteers'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
