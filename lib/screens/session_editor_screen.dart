import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';

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
  late final TextEditingController _track;
  late final TextEditingController _expert;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _capacity;
  late final TextEditingController _description;
  late final TextEditingController _sponsor;

  bool _busy = false;
  String? _error;

  /// The rooms catalog and the currently-selected room (null = "Unassigned").
  List<Room> _rooms = const [];
  String? _roomId;

  bool get _isEditing => widget.session != null;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _title = TextEditingController(text: s?.title ?? '');
    _track = TextEditingController(text: s?.track ?? '');
    _roomId = s?.roomId;
    _expert = TextEditingController(text: s?.expertName ?? '');
    _start = TextEditingController(text: s?.start ?? '');
    _end = TextEditingController(text: s?.end ?? '');
    _capacity = TextEditingController(text: s != null ? '${s.capacity}' : '');
    _description = TextEditingController(text: s?.description ?? '');
    _sponsor = TextEditingController(text: s?.sponsor ?? '');
    _loadRooms();
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
      _title, _track, _expert, _start, _end, _capacity,
      _description, _sponsor,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static final _timeRe = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$');

  Future<void> _save() async {
    final title = _title.text.trim();
    final start = _start.text.trim();
    final end = _end.text.trim();
    final capacity = int.tryParse(_capacity.text.trim());

    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (!_timeRe.hasMatch(start) || !_timeRe.hasMatch(end)) {
      setState(() => _error = 'Use 24-hour times like 10:00 and 10:45.');
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
    final sponsor = _sponsor.text.trim();
    // Keep the free-text `room` in sync with the catalog name so displays that
    // read `room` (and older rows) still show something sensible.
    final roomName = _roomId == null
        ? ''
        : _rooms.firstWhere((r) => r.id == _roomId).name;
    final data = <String, dynamic>{
      'discipline_id': widget.discipline.id,
      'title': title,
      'track': _track.text.trim(),
      'room_id': _roomId,
      'room': roomName,
      'expert_name': _expert.text.trim(),
      'start_time': start,
      'end_time': end,
      'capacity': capacity,
      'description': _description.text.trim(),
      'sponsor': sponsor.isEmpty ? null : sponsor,
    };
    try {
      await appState.saveSession(id: widget.session?.id, data: data);
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(_isEditing ? 'Session updated' : 'Session created')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save. You may not manage this discipline.';
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text('“${widget.session!.title}” will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
          if (_isEditing)
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
                Text('In ${widget.discipline.name}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 16),
                _field(_title, 'Title'),
                _field(_track, 'Track', hint: 'e.g. Mobile Track'),
                _roomDropdown(),
                _field(_expert, 'Expert / speaker'),
                Row(
                  children: [
                    Expanded(
                        child: _field(_start, 'Start (HH:mm)', hint: '10:00')),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_end, 'End (HH:mm)', hint: '10:45')),
                  ],
                ),
                _field(_capacity, 'Capacity',
                    keyboardType: TextInputType.number),
                _field(_description, 'Description', maxLines: 4),
                _field(_sponsor, 'Sponsor (optional)'),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
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

  Widget _roomDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String?>(
        initialValue: _roomId,
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
        ],
        onChanged: _busy ? null : (v) => setState(() => _roomId = v),
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
