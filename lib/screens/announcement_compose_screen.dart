import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';

/// Composer for a new announcement. Admins can target Everyone or any
/// discipline; a volunteer with can_post_announcements may target only the
/// discipline(s) they manage (the server enforces this). Posting inserts a row
/// the live feed pushes to every open app (and, later, fires a push).
class AnnouncementComposeScreen extends StatefulWidget {
  const AnnouncementComposeScreen({super.key});

  @override
  State<AnnouncementComposeScreen> createState() =>
      _AnnouncementComposeScreenState();
}

class _AnnouncementComposeScreenState extends State<AnnouncementComposeScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  // null audience = Everyone; otherwise a specific discipline.
  Discipline? _audience;
  bool _pinned = false;
  bool _busy = false;
  String? _error;

  /// Admins may post to Everyone; scoped volunteers must pick a discipline.
  bool get _everyoneAllowed => appState.isAdmin;

  /// The disciplines this user may target: all for admins; the managed set
  /// (or all, for a '*' volunteer) otherwise.
  List<Discipline> get _allowedDisciplines {
    if (appState.isAdmin) return appState.disciplines;
    final managed = appState.profile?.managedDisciplines ?? const [];
    if (managed.contains('*')) return appState.disciplines;
    return appState.disciplines
        .where((d) => managed.contains(d.id))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    // A scoped volunteer can't post to Everyone, so default to their first
    // allowed discipline.
    if (!_everyoneAllowed) {
      final allowed = _allowedDisciplines;
      if (allowed.isNotEmpty) _audience = allowed.first;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      setState(() => _error = 'Please add a title and a message.');
      return;
    }
    if (!_everyoneAllowed && _audience == null) {
      setState(() => _error = 'Pick a discipline to post to.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await announcementsRepository.create(
        title: title,
        body: body,
        author: appState.userName,
        audience: _audience?.name ?? 'Everyone',
        pinned: _pinned,
        disciplineId: _audience?.id,
      );
      // Show it immediately for the author (others get it via the live feed).
      await appState.loadAnnouncements();
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Announcement posted')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not post. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New announcement')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleController,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bodyController,
                  enabled: !_busy,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Discipline?>(
                  initialValue: _audience,
                  decoration: const InputDecoration(
                    labelText: 'Audience',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    if (_everyoneAllowed)
                      const DropdownMenuItem<Discipline?>(
                        value: null,
                        child: Text('Everyone'),
                      ),
                    for (final d in _allowedDisciplines)
                      DropdownMenuItem<Discipline?>(
                        value: d,
                        child: Text(d.name),
                      ),
                  ],
                  onChanged:
                      _busy ? null : (v) => setState(() => _audience = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pin to top'),
                  value: _pinned,
                  onChanged:
                      _busy ? null : (v) => setState(() => _pinned = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _post,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.campaign),
                  label: const Text('Post announcement'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
