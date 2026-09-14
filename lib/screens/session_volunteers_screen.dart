import 'package:flutter/material.dart';

import '../backend/repositories.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';

/// Admin-only screen to assign/unassign volunteers to a session. Being assigned
/// is what lets a volunteer see the session's roster and mark its attendance.
/// The assign path is server-guarded: an overlap with the volunteer's other
/// commitments is refused and surfaced here.
class SessionVolunteersScreen extends StatefulWidget {
  const SessionVolunteersScreen({super.key, required this.session});

  final Session session;

  @override
  State<SessionVolunteersScreen> createState() =>
      _SessionVolunteersScreenState();
}

class _SessionVolunteersScreenState extends State<SessionVolunteersScreen> {
  bool _loading = true;
  List<VolunteerRef> _assigned = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final assigned =
          await assignmentRepository.fetchSessionVolunteers(widget.session.id);
      if (!mounted) return;
      setState(() {
        _assigned = assigned;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndAssign() async {
    final messenger = ScaffoldMessenger.of(context);
    List<VolunteerRef> all;
    try {
      all = await assignmentRepository.fetchVolunteers();
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not load the volunteer list.')));
      return;
    }
    if (!mounted) return;
    final assignedIds = _assigned.map((v) => v.id).toSet();
    final available =
        all.where((v) => !assignedIds.contains(v.id)).toList();
    if (available.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Every volunteer is already assigned here.')));
      return;
    }
    final picked = await showModalBottomSheet<VolunteerRef>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VolunteerPicker(volunteers: available),
    );
    if (picked == null || !mounted) return;
    await _assign(picked);
  }

  Future<void> _assign(VolunteerRef v, {bool confirmRegistered = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await assignmentRepository.assign(widget.session.id, v.id,
          confirmRegistered: confirmRegistered);
      if (!mounted) return;
      switch (result.outcome) {
        case AssignmentOutcome.conflict:
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Schedule conflict'),
              content: Text(
                '${v.name} has a schedule conflict and can\'t be added to this '
                'session — it overlaps with "${result.conflictingTitle}".',
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Got it')),
              ],
            ),
          );
          return;
        case AssignmentOutcome.registeredConfirm:
          // The volunteer already registered for this session (as a
          // participant) — confirm before assigning them to manage it.
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Already registered'),
              content: Text(
                '${v.name} is registered for this session. Do you want to '
                'assign them to manage it?',
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Assign')),
              ],
            ),
          );
          if (proceed == true && mounted) {
            await _assign(v, confirmRegistered: true);
          }
          return;
        case AssignmentOutcome.assigned:
          await _load();
          messenger.showSnackBar(
              SnackBar(content: Text('Assigned ${v.name} to this session')));
      }
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not assign. Admins only.')));
    }
  }

  Future<void> _unassign(VolunteerRef v) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await assignmentRepository.unassign(widget.session.id, v.id);
      await _load();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Removed ${v.name}')));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not remove.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Session volunteers')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-assign-volunteer',
        onPressed: _pickAndAssign,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Assign volunteer'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(widget.session.title,
                        style: theme.textTheme.titleMedium),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      '${widget.session.timeLabel} · '
                      '${widget.session.room.isEmpty ? "Unassigned room" : widget.session.room}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _assigned.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'No volunteers assigned yet. Assign volunteers '
                                'so they can see this session\'s roster and mark '
                                'attendance.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: _assigned.length,
                            itemBuilder: (context, i) {
                              final v = _assigned[i];
                              return ListTile(
                                leading:
                                    const Icon(Icons.volunteer_activism_outlined),
                                title: Text(v.name.isEmpty ? v.email : v.name),
                                subtitle: Text(_subtypeLabel(v.subtype)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  tooltip: 'Remove',
                                  onPressed: () => _unassign(v),
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

String _subtypeLabel(String? subtype) => switch (subtype) {
      'eaf_ambassador' => 'EAF Ambassador',
      'parent_volunteer' => 'Parent Volunteer',
      'student_volunteer' => 'Student Volunteer',
      _ => 'Volunteer',
    };

/// A searchable bottom-sheet picker over the available volunteers.
class _VolunteerPicker extends StatefulWidget {
  const _VolunteerPicker({required this.volunteers});

  final List<VolunteerRef> volunteers;

  @override
  State<_VolunteerPicker> createState() => _VolunteerPickerState();
}

class _VolunteerPickerState extends State<_VolunteerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = [
      for (final v in widget.volunteers)
        if (q.isEmpty ||
            v.name.toLowerCase().contains(q) ||
            v.email.toLowerCase().contains(q))
          v,
    ];
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search volunteers',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final v = filtered[i];
                  return ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(v.name.isEmpty ? v.email : v.name),
                    subtitle: Text(v.email),
                    onTap: () => Navigator.pop(context, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
