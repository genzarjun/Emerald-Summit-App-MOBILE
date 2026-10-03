import 'package:flutter/material.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';

/// Standalone attendance screen — a thin wrapper around [SessionRosterView] used
/// when a volunteer opens a managed session from "Sessions I'm managing"
/// (my_assignments_screen). On the session page itself the same view is embedded
/// as the "Participants" tab.
class SessionRosterScreen extends StatelessWidget {
  const SessionRosterScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: SafeArea(child: SessionRosterView(session: session)),
    );
  }
}

/// The roster for one session — the registered people and their attendance
/// state. Shown to a volunteer assigned to the session (or an admin); marking is
/// enforced server-side by the same assignment gate. Renders just the body (no
/// Scaffold/AppBar) so it can be embedded as a tab or wrapped by
/// [SessionRosterScreen].
///
/// [types] optionally restricts the list to certain participation types — the
/// session page uses it to split the full roster into a **Participants** tab
/// (participant + spectator) and an **Experts** tab (expert). Null shows
/// everyone (the standalone attendance screen).
class SessionRosterView extends StatefulWidget {
  const SessionRosterView({
    super.key,
    required this.session,
    this.types,
    this.emptyMessage,
  });

  final Session session;
  final Set<ParticipationType>? types;
  final String? emptyMessage;

  @override
  State<SessionRosterView> createState() => _SessionRosterViewState();
}

class _SessionRosterViewState extends State<SessionRosterView> {
  bool _loading = true;
  String? _error;
  List<RosterEntry> _roster = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final roster =
          await attendanceRepository.fetchSessionRoster(widget.session.id);
      if (!mounted) return;
      final types = widget.types;
      setState(() {
        _roster = types == null
            ? roster
            : roster.where((e) => types.contains(e.participationType)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load the roster. You may not be assigned here.";
        _loading = false;
      });
    }
  }

  Future<void> _toggle(RosterEntry entry, bool value) async {
    // Optimistic update; revert on failure.
    final i = _roster.indexWhere((e) => e.userId == entry.userId);
    if (i < 0) return;
    setState(() => _roster[i] = _roster[i].copyWith(attended: value));
    try {
      await attendanceRepository.markSessionAttendance(
          widget.session.id, entry.userId, value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _roster[i] = _roster[i].copyWith(attended: !value));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save attendance.')));
    }
  }

  /// The roster row subtitle: attendance state, the participation type, and any
  /// participant answers rendered as "Prompt: answer" (prompts resolved from the
  /// session's questions by id).
  Widget _rosterSubtitle(ThemeData theme, RosterEntry e) {
    final questions = {
      for (final q in widget.session.participantQuestions) q.id: q.prompt,
    };
    final lines = <String>[
      for (final entry in e.answers.entries)
        '${questions[entry.key] ?? 'Answer'}: ${entry.value}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${e.attended ? 'Present' : 'Not marked'} · ${e.participationType.chipLabel}',
        ),
        for (final line in lines)
          Text(
            line,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = _roster.where((e) => e.attended).length;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_error!,
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
          child: Text(widget.session.title, style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            '${widget.session.timeLabel} · '
            '${widget.session.room.isEmpty ? "Unassigned room" : widget.session.room}'
            '  ·  $present / ${_roster.length} present',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _roster.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.emptyMessage ??
                          'No one has registered for this session yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _roster.length,
                  itemBuilder: (context, i) {
                    final e = _roster[i];
                    return SwitchListTile(
                      isThreeLine: e.answers.isNotEmpty,
                      value: e.attended,
                      onChanged: (v) => _toggle(e, v),
                      title: Text(e.name.isEmpty ? e.email : e.name),
                      subtitle: _rosterSubtitle(theme, e),
                      secondary: CircleAvatar(
                        backgroundColor: e.attended
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          e.attended ? Icons.check : Icons.person_outline,
                          color: e.attended
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const Divider(height: 1),
                ),
        ),
      ],
    );
  }
}
