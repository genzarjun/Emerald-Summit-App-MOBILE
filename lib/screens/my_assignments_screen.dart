import 'package:flutter/material.dart';

import '../app_state.dart';
import 'session_roster_screen.dart';

/// A volunteer's own session assignments. Tapping one opens its roster so they
/// can mark attendance. Admins assign volunteers to sessions from the session
/// detail page.
class MyAssignmentsScreen extends StatefulWidget {
  const MyAssignmentsScreen({super.key});

  @override
  State<MyAssignmentsScreen> createState() => _MyAssignmentsScreenState();
}

class _MyAssignmentsScreenState extends State<MyAssignmentsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await appState.loadCatalog();
    await appState.loadMyAssignments();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sessions I'm managing")),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListenableBuilder(
                listenable: appState,
                builder: (context, _) {
                  final theme = Theme.of(context);
                  final sessions = appState.myAssignedSessions
                    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
                  if (sessions.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          "You're not assigned to any sessions yet. An admin "
                          'assigns volunteers to sessions — once you are, they '
                          'show up here with their rosters.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: sessions.length,
                      itemBuilder: (context, i) {
                        final s = sessions[i];
                        return ListTile(
                          leading: const Icon(Icons.event_available_outlined),
                          title: Text(s.title),
                          subtitle: Text(
                            '${s.timeLabel} · '
                            '${s.room.isEmpty ? "Unassigned room" : s.room}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SessionRosterScreen(session: s),
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (_, _) => const Divider(height: 1),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
