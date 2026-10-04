import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../backend/repositories.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';
import '../widgets/type_to_confirm_dialog.dart';

/// Create / edit a session within a discipline. Shown to admins and to mentors
/// scoped to the discipline. RLS is the real guard; this screen just gates the
/// UI. Pass [session] to edit, or leave null to create.
class SessionEditorScreen extends StatefulWidget {
  const SessionEditorScreen({
    super.key,
    required this.discipline,
    this.session,
  });

  final Discipline discipline;
  final Session? session;

  @override
  State<SessionEditorScreen> createState() => _SessionEditorScreenState();
}

class _SessionEditorScreenState extends State<SessionEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _expert;
  /// Start/end as typed in 12-hour form (`h:mm`), with their AM/PM choice.
  /// Saved as 24-hour `HH:mm`, which conflict checks and sorting rely on.
  late final TextEditingController _start;
  late final TextEditingController _end;
  late bool _startPm;
  late bool _endPm;
  late final TextEditingController _capacity;
  late final TextEditingController _description;

  /// Team size limit: 2–[kLargestTeamSizeLimit], or [kSoloOnlyTeamSize] for a
  /// solo-only session.
  late int _maxTeamSize;

  /// Wording of the built-in project question. Prefilled with the current
  /// wording; blank or the default text saves as "use the default".
  late final TextEditingController _projectPrompt;

  /// When registering to participate closes (local time); null = no deadline.
  DateTime? _participantDeadline;

  /// The session's existing teams (team id → member count), from its roster,
  /// so the editor can warn before a team setting change affects them.
  Map<String, int> _teamSizes = const {};

  bool _busy = false;
  String? _error;

  /// The rooms catalog and the currently-selected room (null = "Unassigned").
  List<Room> _rooms = const [];
  String? _roomId;

  // ---- Session page media + content -----------------------------------------
  final ImagePicker _picker = ImagePicker();
  String? _heroImageUrl;
  List<GalleryPhoto> _photos = const [];
  bool _mediaBusy = false;
  final List<_BlockControllers> _blocks = [];

  /// Participant questions (each carries a stable id preserved across edits, so
  /// existing answers keyed by id are never orphaned).
  final List<_QuestionControllers> _questions = [];

  bool get _isEditing => widget.session != null;

  /// Photo/hero editing needs the session id, which only exists after the row is
  /// created. On a brand-new session, save first, then reopen to add photos.
  String? get _sessionId => widget.session?.id;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _title = TextEditingController(text: s?.title ?? '');
    _roomId = s?.roomId;
    _expert = TextEditingController(text: s?.expertName ?? '');
    final (start, startPm) = s == null ? ('', false) : to12HourTime(s.start);
    final (end, endPm) = s == null ? ('', false) : to12HourTime(s.end);
    _start = TextEditingController(text: start);
    _end = TextEditingController(text: end);
    _startPm = startPm;
    _endPm = endPm;
    _capacity = TextEditingController(text: s != null ? '${s.capacity}' : '');
    _description = TextEditingController(text: s?.description ?? '');
    _projectPrompt = TextEditingController(
      text: s?.projectPrompt ?? DefaultQuestions.projectName,
    );
    _maxTeamSize = (s?.maxTeamSize ?? kDefaultMaxTeamSize)
        .clamp(kSoloOnlyTeamSize, kLargestTeamSizeLimit);
    _participantDeadline = s?.participantDeadline;
    _heroImageUrl = s?.heroImageUrl;
    for (final block in s?.pageBlocks ?? const <SessionPageBlock>[]) {
      _blocks.add(_BlockControllers(title: block.title, body: block.body));
    }
    for (final q in s?.participantQuestions ?? const <SessionQuestion>[]) {
      _questions.add(_QuestionControllers(id: q.id, prompt: q.prompt));
    }
    _loadRooms();
    if (_sessionId != null) {
      _loadPhotos();
      _loadTeams();
    }
  }

  Future<void> _loadPhotos() async {
    final photos = await sessionMediaRepository.fetchPhotos(_sessionId!);
    if (!mounted) return;
    setState(() => _photos = photos);
  }

  /// Best-effort: without the roster the editor just can't warn about teams.
  Future<void> _loadTeams() async {
    try {
      final roster = await attendanceRepository.fetchSessionRoster(_sessionId!);
      final sizes = <String, int>{};
      for (final e in roster) {
        final team = e.teamId;
        if (team != null) sizes[team] = (sizes[team] ?? 0) + 1;
      }
      if (mounted) setState(() => _teamSizes = sizes);
    } catch (_) {}
  }

  /// Existing teams the chosen Teams setting newly affects: all of them when
  /// teams are being turned off, or those bigger than a lowered limit. Zero
  /// when the setting hasn't changed.
  int get _affectedTeamCount {
    final original = widget.session?.maxTeamSize;
    if (original == null || _maxTeamSize == original) return 0;
    if (_maxTeamSize < 2) return original >= 2 ? _teamSizes.length : 0;
    if (_maxTeamSize > original) return 0;
    return _teamSizes.values.where((n) => n > _maxTeamSize).length;
  }

  /// What happens to those teams, or null when none are affected.
  String? get _teamsNotice {
    final n = _affectedTeamCount;
    if (n == 0) return null;
    final teams = n == 1 ? '1 team' : '$n teams';
    return _maxTeamSize < 2
        ? '$teams already registered for this session will keep their team — '
            'nobody is removed, and members can still leave to go solo. No new '
            'teams can be created or joined.'
        : '$teams already ${n == 1 ? 'has' : 'have'} more than $_maxTeamSize '
            "members. Nobody is removed, but ${n == 1 ? 'it' : 'they'} can't "
            'take new members.';
  }

  Future<void> _loadRooms() async {
    await appState.loadRooms();
    if (!mounted) return;
    setState(() {
      _rooms = appState.rooms;
      // Drop a stale selection if the room no longer exists.
      if (_roomId != null && !_rooms.any((r) => r.id == _roomId)) {
        _roomId = null;
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _expert,
      _start,
      _end,
      _capacity,
      _description,
      _projectPrompt,
    ]) {
      c.dispose();
    }
    for (final b in _blocks) {
      b.dispose();
    }
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  // ---- Photos ---------------------------------------------------------------
  /// A short, unique file name for an upload (Storage keys must be unique within
  /// the session's folder).
  String _photoFileName() => 'p_${DateTime.now().millisecondsSinceEpoch}.jpg';

  Future<XFile?> _pick() => _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );

  Future<void> _pickHero() async {
    final id = _sessionId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final file = await _pick();
    if (file == null || !mounted) return;
    setState(() => _mediaBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final photo = await sessionMediaRepository.uploadPhoto(
        id,
        bytes,
        _photoFileName(),
      );
      if (!mounted) return;
      setState(() {
        _heroImageUrl = photo.imageUrl;
        _photos = [..._photos, photo];
        _mediaBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mediaBusy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not upload. You may not manage this session.'),
        ),
      );
    }
  }

  Future<void> _addGalleryPhoto() async {
    final id = _sessionId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final file = await _pick();
    if (file == null || !mounted) return;
    setState(() => _mediaBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final photo = await sessionMediaRepository.uploadPhoto(
        id,
        bytes,
        _photoFileName(),
      );
      if (!mounted) return;
      setState(() {
        _photos = [..._photos, photo];
        _mediaBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mediaBusy = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not upload. You may not manage this session.'),
        ),
      );
    }
  }

  Future<void> _deletePhoto(GalleryPhoto photo) async {
    final id = _sessionId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _mediaBusy = true);
    try {
      await sessionMediaRepository.deletePhoto(id, photo.id);
      if (!mounted) return;
      setState(() {
        _photos = _photos.where((p) => p.id != photo.id).toList();
        // If we removed the hero, clear the pointer too.
        if (_heroImageUrl == photo.imageUrl) _heroImageUrl = null;
        _mediaBusy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mediaBusy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete the photo.')),
      );
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final start = to24HourTime(_start.text, pm: _startPm);
    final end = to24HourTime(_end.text, pm: _endPm);
    final capacity = int.tryParse(_capacity.text.trim());

    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (start == null || end == null) {
      setState(
        () => _error = 'Use times like 10:00 or 1:30, then pick AM or PM.',
      );
      return;
    }
    if (end.compareTo(start) <= 0) {
      setState(() => _error = 'End time must be after the start time.');
      return;
    }
    if (capacity == null || capacity <= 0) {
      setState(() => _error = 'Capacity must be a positive number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Keep the free-text `room` in sync with the catalog name so displays that
    // read `room` (and older rows) still show something sensible.
    final roomName = _roomId == null
        ? ''
        : _rooms.firstWhere((r) => r.id == _roomId).name;
    // `track` and `sponsor` are no longer editable (a "track" IS a session), so
    // they're omitted here — on an edit that leaves any existing values intact.
    final data = <String, dynamic>{
      'discipline_id': widget.discipline.id,
      'title': title,
      'room_id': _roomId,
      'room': roomName,
      'expert_name': _expert.text.trim(),
      'start_time': start,
      'end_time': end,
      'capacity': capacity,
      'max_team_size': _maxTeamSize,
      'participant_deadline': _participantDeadline?.toUtc().toIso8601String(),
      'project_prompt': switch (_projectPrompt.text.trim()) {
        '' || DefaultQuestions.projectName => null,
        final custom => custom,
      },
      'description': _description.text.trim(),
      'hero_image_url': _heroImageUrl,
      'page_blocks': [
        for (final b in _blocks)
          if (b.title.text.trim().isNotEmpty || b.body.text.trim().isNotEmpty)
            {'title': b.title.text.trim(), 'body': b.body.text.trim()},
      ],
      'participant_questions': [
        for (final q in _questions)
          if (q.prompt.text.trim().isNotEmpty)
            {'id': q.id, 'prompt': q.prompt.text.trim()},
      ],
    };
    // If an existing session's time is changing, warn the admin when it would
    // now clash with people already registered for it — and, after saving,
    // notify those people so they can adjust their schedule.
    final id = widget.session?.id;
    // Turning teams off (or lowering the limit) never breaks up existing
    // teams — make sure the editor knows that before it takes effect.
    final notice = _teamsNotice;
    if (notice != null) {
      final proceed = await _confirmTeamsChange(notice);
      if (!mounted) return;
      if (proceed != true) {
        setState(() => _busy = false);
        return;
      }
    }
    // Compare in the same zero-padded form the editor saves, so an old
    // "9:00" row resaved as "09:00" doesn't count as a time change.
    String? normalized(String hhmm) {
      final (time, pm) = to12HourTime(hhmm);
      return to24HourTime(time, pm: pm);
    }

    final timeChanged =
        _isEditing &&
        (start != normalized(widget.session!.start) ||
            end != normalized(widget.session!.end));
    if (timeChanged && id != null) {
      final affected = await appState.previewSessionTimeConflicts(
        id,
        start,
        end,
      );
      if (!mounted) return;
      if (affected > 0) {
        final proceed = await _confirmTimeConflict(affected);
        if (proceed != true) {
          setState(() => _busy = false);
          return;
        }
      }
    }

    try {
      await appState.saveSession(id: widget.session?.id, data: data);
      // Best-effort: tell affected registrants their session moved. A failure
      // here must not undo the (already successful) save.
      if (timeChanged && id != null) {
        try {
          await appState.notifySessionTimeConflicts(id);
        } catch (_) {}
      }
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Session updated' : 'Session created'),
          ),
        );
    } on SessionWriteDeniedException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save. You may not manage this discipline.';
      });
    } catch (e) {
      debugPrint('Session save failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save the session. Please try again.';
      });
    }
  }

  /// Confirms a Teams setting change that affects existing teams.
  Future<bool?> _confirmTeamsChange(String notice) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _maxTeamSize < 2 ? 'This session has teams' : 'Some teams are bigger',
        ),
        content: Text('$notice Save anyway?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  /// Confirms a time change that will clash with [affected] people's schedules.
  Future<bool?> _confirmTimeConflict(int affected) {
    final who = affected == 1 ? '1 person' : '$affected people';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule clash'),
        content: Text(
          'This new time overlaps another session that $who registered for it '
          'already have. If you save, they\'ll be notified to adjust their '
          'schedule. Save anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final title = widget.session!.title;
    final confirmed = await confirmByTypingName(
      context,
      title: 'Delete session?',
      message: '“$title” will be removed for everyone, along with its '
          'registrations and teams. This can\'t be undone.',
      name: title,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await appState.deleteSession(widget.session!.id);
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Session deleted')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not delete. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit session' : 'New session'),
        actions: [
          // Only admins delete sessions (backend-enforced too).
          if (_isEditing && appState.isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'In ${widget.discipline.name}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                _field(_title, 'Title'),
                _roomDropdown(),
                _field(_expert, 'Expert / speaker'),
                _timeField(
                  _start,
                  'Start time',
                  hint: '10:00',
                  pm: _startPm,
                  onPmChanged: (pm) => setState(() => _startPm = pm),
                ),
                _timeField(
                  _end,
                  'End time',
                  hint: '10:45',
                  pm: _endPm,
                  onPmChanged: (pm) => setState(() => _endPm = pm),
                ),
                _field(
                  _capacity,
                  'Capacity',
                  keyboardType: TextInputType.number,
                ),
                _deadlineField(theme),
                _field(_description, 'Description', maxLines: 4),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                _pageContentSection(theme),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isEditing ? 'Save changes' : 'Create session'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Picks the participant deadline: a date, then a time on that date.
  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final current = _participantDeadline;
    final initial = current ?? now;
    final date = await showDatePicker(
      context: context,
      helpText: 'Participant registration closes on',
      initialDate: initial,
      firstDate: DateTime(
        (current != null && current.isBefore(now) ? current : now).year - 1,
      ),
      lastDate: DateTime(now.year + 3, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      helpText: 'Closes at',
      initialTime: current != null
          ? TimeOfDay.fromDateTime(current)
          : const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;
    setState(
      () => _participantDeadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Widget _deadlineField(ThemeData theme) {
    final deadline = _participantDeadline;
    final passed = deadline != null && !DateTime.now().isBefore(deadline);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_busy_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Deadline to register as a participant',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'After this date and time, nobody can register to participate. '
              'People can still register to spectate while seats are left. '
              'Anyone already participating keeps their spot.',
              style: muted,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickDeadline,
                    icon: const Icon(Icons.event),
                    label: Text(
                      deadline == null
                          ? 'Set a deadline'
                          : formatDeadline(deadline),
                    ),
                  ),
                ),
                if (deadline != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove deadline',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _participantDeadline = null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              deadline == null
                  ? 'No deadline — people can register to participate any time '
                      'while seats are left.'
                  : passed
                      ? 'This deadline has passed: participant registration is '
                          'closed. Only spectators can register now.'
                      : 'Participant registration is open until then.',
              style: passed
                  ? theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    )
                  : muted,
            ),
          ],
        ),
      ),
    );
  }

  // Sentinel value for the "＋ Add a room…" dropdown entry.
  static const String _addRoomSentinel = '__add_room__';

  Widget _roomDropdown() {
    // Only seed the dropdown with a room the loaded catalog actually contains —
    // on the first build (before rooms load) or for a since-deleted room, fall
    // back to "Unassigned" so DropdownButtonFormField's value==item assertion
    // never trips. The key re-seeds the field once the rooms arrive.
    final selectedRoomId = _rooms.any((r) => r.id == _roomId) ? _roomId : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String?>(
        key: ValueKey('room-${_rooms.length}-$selectedRoomId'),
        initialValue: selectedRoomId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Room',
          border: OutlineInputBorder(),
        ),
        hint: const Text('Select a room'),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Unassigned'),
          ),
          for (final r in _rooms)
            DropdownMenuItem<String?>(value: r.id, child: Text(r.name)),
          DropdownMenuItem<String?>(
            value: _addRoomSentinel,
            child: Row(
              children: [
                Icon(
                  Icons.add,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Add a room…',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
        onChanged: _busy
            ? null
            : (v) {
                if (v == _addRoomSentinel) {
                  _addRoomInline();
                } else {
                  setState(() => _roomId = v);
                }
              },
      ),
    );
  }

  /// Prompts for a new room name, creates it, and selects it — without leaving
  /// the session editor. Enabled for admins and session-editing volunteers
  /// (the backend enforces who may actually insert).
  Future<void> _addRoomInline() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a room'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Room name',
            hintText: 'e.g. Room 210, Cafeteria',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.createRoom({'name': name});
      if (!mounted) return;
      setState(() {
        _rooms = appState.rooms;
        // Select the room we just added (names are unique in the catalog).
        final match = _rooms.where((r) => r.name == name);
        if (match.isNotEmpty) _roomId = match.first.id;
      });
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not add the room. It may already exist, or '
            'you may not have permission.',
          ),
        ),
      );
    }
  }

  // ---- Page content UI ------------------------------------------------------
  Widget _pageContentSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Session page', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'The hero photo, gallery, and sections below are what participants see '
          'on this session.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_sessionId == null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Save the session first, then reopen it to add photos.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )
        else ...[
          _heroPicker(theme),
          const SizedBox(height: 16),
          _galleryEditor(theme),
        ],
        const SizedBox(height: 20),
        _blocksEditor(theme),
        const SizedBox(height: 20),
        _questionsEditor(theme),
      ],
    );
  }

  Widget _questionsEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Participant questions', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          'Asked when someone adds this session as a participant. Answers show '
          'on the Participants tab, where teammates are grouped under their '
          'project.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _defaultQuestions(theme),
        const SizedBox(height: 16),
        Text('Your additional questions', style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          'Optional — asked after the default questions above.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _questions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _questions[i].prompt,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Question ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove question',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _questions.removeAt(i).dispose()),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() => _questions.add(_QuestionControllers())),
            icon: const Icon(Icons.add),
            label: const Text('Add question'),
          ),
        ),
      ],
    );
  }

  /// The app's built-in questions every participant answers. Shown read-only
  /// so editors know what's already asked (and don't duplicate it).
  Widget _defaultQuestions(ThemeData theme) {
    final prefix = teamCodePrefix(widget.discipline.id, widget.discipline.name);
    final soloOnly = _maxTeamSize < 2;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget item(String prompt, String detail) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(prompt, style: theme.textTheme.bodyMedium),
                    Text(detail, style: muted),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default questions (set by the app)',
              style: theme.textTheme.labelMedium),
          if (soloOnly) ...[
            _projectPromptItem(theme, 'Always asked.'),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.block, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Teams aren't allowed for this session.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            item(DefaultQuestions.soloOrTeam,
                'Always asked. Answer: Solo or Team.'),
            _projectPromptItem(theme,
                'Asked of solo participants and of whoever creates a team.'),
            item(DefaultQuestions.teamCode,
                'Asked when joining a team. Codes for this discipline look '
                'like ${prefix}1234; the joiner confirms the team\'s project '
                'name.'),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _maxTeamSize,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Teams',
              helperText: soloOnly
                  ? 'No new teams can be created or joined. Anyone already on '
                      'a team keeps it.'
                  : "Most people allowed on one team. Lowering it doesn't "
                      'remove anyone; full teams just stop taking new members.',
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: kSoloOnlyTeamSize,
                child: Text(
                  'No teams allowed — solo only',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (var n = 2; n <= kLargestTeamSizeLimit; n++)
                DropdownMenuItem(
                  value: n,
                  child: Text(
                    'Teams of up to $n'
                    '${n == kDefaultMaxTeamSize ? ' (default)' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _maxTeamSize = v ?? _maxTeamSize),
          ),
          if (_teamsNotice != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _teamsNotice!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The one default question editors may reword: the project question. It
  /// stays built in and required; only its wording is theirs.
  Widget _projectPromptItem(ThemeData theme, String detail) {
    final isDefault = _projectPrompt.text.trim().isEmpty ||
        _projectPrompt.text.trim() == DefaultQuestions.projectName;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Icon(Icons.edit_outlined,
                size: 16, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _projectPrompt,
                  enabled: !_busy,
                  maxLength: 200,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Project question (you can reword this)',
                    helperText: '$detail Still a default question — you can '
                        'change its wording, not remove it.',
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (!isDefault)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _projectPrompt.text =
                            DefaultQuestions.projectName),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset to default wording'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPicker(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Hero photo', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (_heroImageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: _heroImageUrl!,
                fit: BoxFit.cover,
                memCacheWidth: 1200,
                errorWidget: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _mediaBusy ? null : _pickHero,
              icon: const Icon(Icons.photo_outlined),
              label: Text(_heroImageUrl == null ? 'Set hero photo' : 'Replace'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _galleryEditor(ThemeData theme) {
    // The hero file also lives in the folder; don't list it twice.
    final gallery = [
      for (final p in _photos)
        if (p.imageUrl != _heroImageUrl) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Gallery', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in gallery)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: p.imageUrl,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      memCacheWidth: 288,
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: IconButton(
                      icon: const Icon(Icons.cancel),
                      color: theme.colorScheme.error,
                      tooltip: 'Remove',
                      onPressed: _mediaBusy ? null : () => _deletePhoto(p),
                    ),
                  ),
                ],
              ),
            InkWell(
              onTap: _mediaBusy ? null : _addGalleryPhoto,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Icon(
                  Icons.add_a_photo_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _blocksEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Content sections', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        for (var i = 0; i < _blocks.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Section ${i + 1}',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove section',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _blocks.removeAt(i).dispose()),
                    ),
                  ],
                ),
                TextField(
                  controller: _blocks[i].title,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Heading',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _blocks[i].body,
                  enabled: !_busy,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Text',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() => _blocks.add(_BlockControllers())),
            icon: const Icon(Icons.add),
            label: const Text('Add section'),
          ),
        ),
      ],
    );
  }

  /// A 12-hour time box (`h:mm`) with an AM/PM toggle beside it.
  Widget _timeField(
    TextEditingController controller,
    String label, {
    required String hint,
    required bool pm,
    required ValueChanged<bool> onPmChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !_busy,
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('AM')),
              ButtonSegment(value: true, label: Text('PM')),
            ],
            selected: {pm},
            onSelectionChanged: _busy ? null : (sel) => onPmChanged(sel.first),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        enabled: !_busy,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// The prompt controller + stable id for one editable participant question. A
/// new question gets a timestamp-based id (like uploaded photo file names); an
/// existing one keeps the id it was loaded with so answers stay linked.
class _QuestionControllers {
  _QuestionControllers({String? id, String prompt = ''})
    : id = id ?? 'q_${DateTime.now().microsecondsSinceEpoch}',
      prompt = TextEditingController(text: prompt);

  final String id;
  final TextEditingController prompt;

  void dispose() => prompt.dispose();
}

/// Title + body controllers for one editable content section.
class _BlockControllers {
  _BlockControllers({String title = '', String body = ''})
    : title = TextEditingController(text: title),
      body = TextEditingController(text: body);

  final TextEditingController title;
  final TextEditingController body;

  void dispose() {
    title.dispose();
    body.dispose();
  }
}
