import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';

/// Volunteer hours for volunteers and admins, opened from Profile → "Track
/// volunteer hours". Two sources add up to the total:
///   * summit-day hours, counted automatically from the sessions the person
///     manages (each session's end minus its start) once that session has
///     ended on the summit date (`summit_settings`). Until the date is set they're listed, not
///     counted; and
///   * manual logs the person adds for everything else (planning meetings,
///     setup, outreach), each with a start, an end, and a description.
class VolunteerHoursScreen extends StatefulWidget {
  const VolunteerHoursScreen({super.key});

  @override
  State<VolunteerHoursScreen> createState() => _VolunteerHoursScreenState();
}

class _VolunteerHoursScreenState extends State<VolunteerHoursScreen> {
  bool _loading = true;
  String? _error;
  List<VolunteerHourLog> _logs = const [];

  @override
  void initState() {
    super.initState();
    // After the first frame: loadCatalog notifies appState listeners right
    // away, which would rebuild widgets mid-build if called from here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = _logs.isEmpty;
      _error = null;
    });
    try {
      await appState.loadCatalog();
      await appState.loadMyAssignments();
      await appState.loadSummitStatus();
      final logs = await volunteerHoursRepository.fetchMine();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            "Couldn't load your hours. Check your connection and try "
            'again.';
        _loading = false;
      });
    }
  }

  Future<void> _openEditor([VolunteerHourLog? log]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => HourLogEditorScreen(log: log)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Volunteer hours')),
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
            : ListenableBuilder(
                listenable: appState,
                builder: (context, _) => RefreshIndicator(
                  onRefresh: _load,
                  child: _buildList(Theme.of(context)),
                ),
              ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    final sessions = appState.myAssignedSessions
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final summitDate = appState.summitStatus.date;
    final now = DateTime.now();
    bool counted(Session s) => summitSessionCounted(s, summitDate, now);
    final summitMinutes = sessions
        .where(counted)
        .fold<int>(0, (sum, s) => sum + summitDayMinutes(s));
    final loggedMinutes = _logs.fold<int>(0, (sum, l) => sum + l.minutes);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatHours(summitMinutes + loggedMinutes),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      summitMinutes + loggedMinutes == 60 ? 'hour' : 'hours',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatHours(loggedMinutes)} logged by you · '
                  '${formatHours(summitMinutes)} on summit day',
                  style: muted,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Add hours'),
        ),
        const _SectionHeader(
          title: 'Summit day',
          subtitle: 'Tracked for you. No need to log it.',
        ),
        _InfoNote(
          summitDate == null
              ? 'Each session you manage on summit day is added to your '
                    'total after it ends, counted from its start time to its '
                    'end time. They will start counting once the summit date '
                    'is set.'
              : 'Each session you manage on ${formatDay(summitDate)} is '
                    'added to your total after it ends, counted from its start '
                    'time to its end time.',
        ),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          _EmptyNote(
            "You aren't managing any sessions yet. When an admin assigns you "
            'one, its hours show up here.',
          )
        else
          Card(
            child: Column(
              children: [
                for (final s in sessions)
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text(s.title),
                    subtitle: Text('${s.timeLabel} · ${s.disciplineName}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMinutes(summitDayMinutes(s)),
                          style: theme.textTheme.labelLarge,
                        ),
                        if (!counted(s))
                          Text(
                            'Not counted yet',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const _SectionHeader(
          title: 'Your logs',
          subtitle: 'Planning, setup, and anything else outside summit day.',
        ),
        if (_logs.isEmpty)
          _EmptyNote('Nothing logged yet. Tap Add hours to log your first one.')
        else
          Card(
            child: Column(
              children: [
                for (final log in _logs)
                  ListTile(
                    title: Text(
                      log.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatDay(log.startedAt)} · '
                      '${formatClock(log.startedAt)} – '
                      '${formatClock(log.endedAt)}',
                    ),
                    trailing: Text(
                      formatMinutes(log.minutes),
                      style: theme.textTheme.labelLarge,
                    ),
                    onTap: () => _openEditor(log),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Adds a new manual log, or edits / deletes [log]. Pops `true` when anything
/// was saved or deleted so the list reloads.
class HourLogEditorScreen extends StatefulWidget {
  const HourLogEditorScreen({super.key, this.log});

  final VolunteerHourLog? log;

  @override
  State<HourLogEditorScreen> createState() => _HourLogEditorScreenState();
}

class _HourLogEditorScreenState extends State<HourLogEditorScreen> {
  late DateTime _day;
  TimeOfDay? _start;
  TimeOfDay? _end;
  late final TextEditingController _description;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.log != null;

  @override
  void initState() {
    super.initState();
    final log = widget.log;
    final now = DateTime.now();
    _day = log == null
        ? DateTime(now.year, now.month, now.day)
        : DateTime(log.startedAt.year, log.startedAt.month, log.startedAt.day);
    if (log != null) {
      _start = TimeOfDay.fromDateTime(log.startedAt);
      _end = TimeOfDay.fromDateTime(log.endedAt);
    }
    _description = TextEditingController(text: log?.description ?? '');
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  DateTime? _at(TimeOfDay? t) => t == null
      ? null
      : DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  /// End minus start in minutes, or null until both times are picked.
  int? get _minutes {
    final start = _at(_start);
    final end = _at(_end);
    if (start == null || end == null) return null;
    return end.difference(start).inMinutes;
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isAfter(now) ? now : _day,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  String? _validate() {
    final start = _at(_start);
    final end = _at(_end);
    if (start == null || end == null) return 'Pick a start and end time.';
    if (!end.isAfter(start)) return 'The end time has to be after the start.';
    if (end.isAfter(DateTime.now())) {
      return "You can't log hours that haven't happened yet.";
    }
    if (_description.text.trim().isEmpty) {
      return 'Add a short description of what you did.';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final start = _at(_start)!;
    final end = _at(_end)!;
    final description = _description.text.trim();
    try {
      if (_editing) {
        await volunteerHoursRepository.update(
          widget.log!.id,
          start,
          end,
          description,
        );
      } else {
        await volunteerHoursRepository.add(start, end, description);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't save. Check your connection and try again.";
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this log?'),
        content: Text(
          '${formatMinutes(widget.log!.minutes)} will come off your total.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await volunteerHoursRepository.delete(widget.log!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't delete. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _minutes;
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit hours' : 'Add hours'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Date'),
                    trailing: Text(formatDay(_day)),
                    onTap: _pickDay,
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Start'),
                    trailing: Text(_start?.format(context) ?? 'Pick'),
                    onTap: () => _pickTime(start: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('End'),
                    trailing: Text(_end?.format(context) ?? 'Pick'),
                    onTap: () => _pickTime(start: false),
                  ),
                ],
              ),
            ),
            if (minutes != null && minutes > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  'Length: ${formatMinutes(minutes)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What did you do?',
                hintText: 'Planning meeting for the Techverse exhibits',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted box with an info icon, for how-it-works notes.
class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
