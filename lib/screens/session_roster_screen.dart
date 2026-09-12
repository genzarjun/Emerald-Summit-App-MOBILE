import 'package:flutter/material.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';

/// The roster for one session — the registered participants and their
/// attendance state. Shown to a volunteer assigned to the session (or an admin);
/// marking is enforced server-side by the same assignment gate.
class SessionRosterScreen extends StatefulWidget {
  const SessionRosterScreen({super.key, required this.session});

  final Session session;

  @override
  State<SessionRosterScreen> createState() => _SessionRosterScreenState();
}

class _SessionRosterScreenState extends State<SessionRosterScreen> {
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
      setState(() {
        _roster = roster;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = _roster.where((e) => e.attended).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
                        child: Text(widget.session.title,
                            style: theme.textTheme.titleMedium),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: Text(
                          '${widget.session.timeLabel} · '
                          '${widget.session.room.isEmpty ? "Unassigned room" : widget.session.room}'
                          '  ·  $present / ${_roster.length} present',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _roster.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    'No one has registered for this session yet.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _roster.length,
                                itemBuilder: (context, i) {
                                  final e = _roster[i];
                                  return SwitchListTile(
                                    value: e.attended,
                                    onChanged: (v) => _toggle(e, v),
                                    title: Text(e.name.isEmpty ? e.email : e.name),
                                    subtitle: Text(e.attended
                                        ? 'Present'
                                        : 'Not marked'),
                                    secondary: CircleAvatar(
                                      backgroundColor: e.attended
                                          ? theme.colorScheme.primaryContainer
                                          : theme.colorScheme.surfaceContainerHighest,
                                      child: Icon(
                                        e.attended
                                            ? Icons.check
                                            : Icons.person_outline,
                                        color: e.attended
                                            ? theme.colorScheme.onPrimaryContainer
                                            : theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  );
                                },
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
