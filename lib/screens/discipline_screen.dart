import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../widgets/type_to_confirm_dialog.dart';
import 'session_detail_screen.dart';
import 'session_editor_screen.dart';

/// Lists the sessions within one discipline. Admins and mentors scoped to this
/// discipline also get controls to create and edit sessions; admins can also
/// delete the whole discipline.
class DisciplineScreen extends StatelessWidget {
  const DisciplineScreen({super.key, required this.discipline});
  final Discipline discipline;

  Future<void> _delete(BuildContext context, Discipline current) async {
    final count = current.sessions.length;
    final confirmed = await confirmByTypingName(
      context,
      title: 'Delete discipline?',
      message: '“${current.name}” will be removed for everyone, along with '
          '${count == 1 ? 'its 1 session' : 'all $count of its sessions'} '
          'and their registrations and teams. This can\'t be undone.',
      name: current.name,
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await appState.deleteDiscipline(current.id);
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Discipline deleted')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Could not delete. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        // Resolve the latest version from the live catalog so session lists and
        // enrolled counts stay fresh after adds/removes/edits; fall back to the
        // one we were handed if it's no longer in the catalog.
        final current = appState.disciplines.firstWhere(
          (d) => d.id == discipline.id,
          orElse: () => discipline,
        );
        final canManage = appState.canManageDiscipline(current.id);
        final sessions = current.sessions;

        return Scaffold(
          appBar: AppBar(
            title: Text(current.name),
            actions: [
              if (appState.isAdmin)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete discipline',
                  onPressed: () => _delete(context, current),
                ),
            ],
          ),
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  heroTag: 'fab-new-session',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SessionEditorScreen(discipline: current),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('New session'),
                )
              : null,
          body: sessions.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No sessions in this discipline yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _SessionTile(
                    session: sessions[i],
                    discipline: current,
                    canManage: canManage,
                  ),
                ),
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.discipline,
    required this.canManage,
  });
  final Session session;
  final Discipline discipline;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registered = appState.isRegistered(session.id);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(session: session),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(session.title,
                        style: theme.textTheme.titleMedium),
                  ),
                  if (registered)
                    Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 20),
                  if (canManage)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit session',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SessionEditorScreen(
                            discipline: discipline,
                            session: session,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _MetaChip(icon: Icons.schedule, label: session.timeLabel),
                  _MetaChip(icon: Icons.place, label: session.room),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                session.isFull
                    ? 'Full · waitlist only'
                    : '${session.seatsLeft} seats left',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: session.isFull
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
