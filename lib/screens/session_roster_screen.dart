import 'package:flutter/material.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';
import '../theme.dart';

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
///
/// Participants are grouped under their project: teammates share one team
/// group (with its code), each solo participant gets their own. With
/// [canMarkAttendance] false (a session editor who isn't taking attendance)
/// the roster is read-only.
class SessionRosterView extends StatefulWidget {
  const SessionRosterView({
    super.key,
    required this.session,
    this.types,
    this.emptyMessage,
    this.canMarkAttendance = true,
  });

  final Session session;
  final Set<ParticipationType>? types;
  final String? emptyMessage;
  final bool canMarkAttendance;

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

  /// Splits the roster into project groups (teams, then solo projects, by
  /// name), then participants who haven't shared a project yet, then
  /// spectators and experts. Returns an empty list when there are no
  /// participants to group by (e.g. the Experts tab) — the roster is then shown
  /// flat.
  List<_RosterGroup> _groups() {
    if (!_roster.any((e) => e.participationType == ParticipationType.participant)) {
      return const [];
    }
    final teams = <String, List<RosterEntry>>{};
    final projects = <_RosterGroup>[];
    final unshared = <RosterEntry>[];
    final spectators = <RosterEntry>[];
    final experts = <RosterEntry>[];
    for (final e in _roster) {
      switch (e.participationType) {
        case ParticipationType.spectator:
          spectators.add(e);
        case ParticipationType.expert:
          experts.add(e);
        case ParticipationType.participant:
          if (e.isTeam == true && e.teamId != null) {
            (teams[e.teamId!] ??= []).add(e);
          } else if (e.isTeam == false) {
            projects.add(_RosterGroup.solo(e));
          } else {
            unshared.add(e);
          }
      }
    }
    projects
      ..addAll(teams.values.map(_RosterGroup.team))
      ..sort((a, b) {
        if (a.isTeam != b.isTeam) return a.isTeam ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return [
      ...projects,
      if (unshared.isNotEmpty)
        _RosterGroup(
          title: 'Project not shared yet',
          icon: Icons.help_outline,
          members: unshared,
          detail: 'Registered before the team question, or still deciding',
        ),
      if (spectators.isNotEmpty)
        _RosterGroup(
          title: 'Spectators',
          icon: Icons.visibility_outlined,
          members: spectators,
        ),
      if (experts.isNotEmpty)
        _RosterGroup(
          title: 'Experts',
          icon: Icons.workspace_premium_outlined,
          members: experts,
        ),
    ];
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
    final groups = _groups();
    final projectCount = groups.where((g) => g.isProject).length;
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
            '  ·  $present / ${_roster.length} present'
            '${projectCount > 0 ? '  ·  $projectCount project${projectCount == 1 ? '' : 's'}' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        if (!widget.canMarkAttendance)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'View only — attendance is marked by the volunteers assigned to '
              'this session.',
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
              : groups.isEmpty
                  ? ListView.separated(
                      itemCount: _roster.length,
                      itemBuilder: (context, i) => _entryTile(theme, _roster[i]),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        for (final g in groups) ...[
                          _GroupHeader(group: g),
                          for (var i = 0; i < g.members.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 72),
                            _entryTile(theme, g.members[i]),
                          ],
                        ],
                      ],
                    ),
        ),
      ],
    );
  }

  /// One person's row: an attendance switch for attendance takers, or a
  /// read-only present/not-marked indicator for editors.
  Widget _entryTile(ThemeData theme, RosterEntry e) {
    final avatar = CircleAvatar(
      backgroundColor: e.attended
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        e.attended ? Icons.check : Icons.person_outline,
        color: e.attended
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
    );
    final title = Text(e.name.isEmpty ? e.email : e.name);
    if (!widget.canMarkAttendance) {
      return ListTile(
        isThreeLine: e.answers.isNotEmpty,
        leading: avatar,
        title: title,
        subtitle: _rosterSubtitle(theme, e),
      );
    }
    return SwitchListTile(
      isThreeLine: e.answers.isNotEmpty,
      value: e.attended,
      onChanged: (v) => _toggle(e, v),
      title: title,
      subtitle: _rosterSubtitle(theme, e),
      secondary: avatar,
    );
  }
}

/// A heading on the grouped roster: one project (team or solo), or a bucket
/// like Spectators.
class _RosterGroup {
  const _RosterGroup({
    required this.title,
    required this.icon,
    required this.members,
    this.detail,
    this.isProject = false,
    this.isTeam = false,
  });

  factory _RosterGroup.team(List<RosterEntry> members) {
    final first = members.first;
    members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _RosterGroup(
      title: (first.projectName ?? '').isEmpty
          ? 'Untitled project'
          : first.projectName!,
      icon: Icons.groups_outlined,
      members: members,
      isProject: true,
      isTeam: true,
      detail: 'Team ${first.teamCode ?? ''} · ${members.length} '
          'member${members.length == 1 ? '' : 's'}',
    );
  }

  factory _RosterGroup.solo(RosterEntry e) => _RosterGroup(
        title: (e.projectName ?? '').isEmpty ? 'Untitled project' : e.projectName!,
        icon: Icons.person_outline,
        members: [e],
        detail: 'Solo',
        isProject: true,
      );

  final String title;
  final IconData icon;
  final List<RosterEntry> members;
  final String? detail;

  /// A real project (team or solo), as opposed to a bucket like Spectators.
  final bool isProject;
  final bool isTeam;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});
  final _RosterGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = group.members.where((e) => e.attended).length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      color: EmeraldTheme.mist,
      child: Row(
        children: [
          Icon(group.icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: EmeraldTheme.ink,
                  ),
                ),
                Text(
                  [
                    ?group.detail,
                    '$present/${group.members.length} present',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: EmeraldTheme.deepEmerald,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
