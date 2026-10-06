import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';

/// Composer for a new announcement. Admins can target Everyone or any
/// discipline; a volunteer with can_post_announcements may target only the
/// discipline(s) they manage (the server enforces this). Posting inserts a row
/// the live feed pushes to every open app (and, later, fires a push).
///
/// Photos and files can be attached (live backend only). They're held locally
/// until Post, then uploaded to Storage and listed on the row; if posting
/// fails, the uploads are removed again.
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

  /// Photos/files picked but not uploaded yet (uploaded on Post).
  final List<_PendingAttachment> _attachments = [];

  /// "Uploading 2 of 3…" while posting with attachments.
  String? _progress;

  static const int _maxAttachments = 10;
  static const int _maxBytes = 10 * 1024 * 1024; // matches the bucket limit

  int get _remaining => _maxAttachments - _attachments.length;

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
      setState(() => _error = 'Please add a subject and a message.');
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
    final uploaded = <AnnouncementAttachment>[];
    try {
      for (var i = 0; i < _attachments.length; i++) {
        setState(() =>
            _progress = 'Uploading ${i + 1} of ${_attachments.length}…');
        final a = _attachments[i];
        uploaded.add(
            await announcementsRepository.uploadAttachment(a.bytes, a.name));
      }
      if (mounted) setState(() => _progress = null);
      await announcementsRepository.create(
        title: title,
        body: body,
        author: appState.userName,
        audience: _audience?.name ?? 'Everyone',
        pinned: _pinned,
        disciplineId: _audience?.id,
        attachments: uploaded,
      );
      // Show it immediately for the author (others get it via the live feed).
      await appState.loadAnnouncements();
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Announcement posted')));
    } catch (e) {
      // Don't leave orphaned files behind a failed post.
      await announcementsRepository.deleteAttachments(uploaded);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = _attachments.isEmpty
            ? 'Could not post. Please try again.'
            : 'Could not post. If this keeps happening, try without the '
                'attachments.';
      });
    }
  }

  // ---- Attachments ----------------------------------------------------------

  void _showLimit(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addPhotos() async {
    if (_remaining <= 0) {
      _showLimit('You can attach up to $_maxAttachments items.');
      return;
    }
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(
        maxWidth: 2000,
        imageQuality: 85,
        limit: _remaining > 1 ? _remaining : null,
      );
    } catch (_) {
      _showLimit("Couldn't open your photos.");
      return;
    }
    if (picked.isEmpty) return;
    final added = <_PendingAttachment>[];
    for (final x in picked.take(_remaining)) {
      final bytes = await x.readAsBytes();
      if (bytes.length > _maxBytes) continue;
      // The picker re-encodes to JPEG; make sure the name says it's an image.
      var name = x.name;
      if (!contentTypeForFileName(name).startsWith('image/')) name = '$name.jpg';
      added.add(_PendingAttachment(bytes: bytes, name: name));
    }
    if (!mounted) return;
    setState(() => _attachments.addAll(added));
    if (added.length < picked.length) {
      _showLimit('Some photos were skipped (10 items max, 10 MB each).');
    }
  }

  Future<void> _addFiles() async {
    if (_remaining <= 0) {
      _showLimit('You can attach up to $_maxAttachments items.');
      return;
    }
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles();
    } catch (_) {
      _showLimit("Couldn't open your files.");
      return;
    }
    if (picked.isEmpty) return;
    final added = <_PendingAttachment>[];
    var skipped = 0;
    for (final f in picked) {
      if (added.length >= _remaining) {
        skipped++;
        continue;
      }
      final size = f.lengthSync() ?? await f.length() ?? 0;
      if (size > _maxBytes) {
        skipped++;
        continue;
      }
      added.add(_PendingAttachment(bytes: await f.readAsBytes(), name: f.name));
    }
    if (!mounted) return;
    setState(() => _attachments.addAll(added));
    if (skipped > 0) {
      _showLimit('Some files were skipped (10 items max, 10 MB each).');
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
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bodyController,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 12,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    helperText: 'The feed shows the subject and the first '
                        'couple of lines; tapping opens the whole thing.',
                    helperMaxLines: 2,
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
                if (backendInfo.isLive) ...[
                  const SizedBox(height: 20),
                  _attachmentsSection(theme),
                ],
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.campaign),
                  label: Text(_progress ?? 'Post announcement'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachmentsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Photos & files', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _addPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Add photos'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _addFiles,
                icon: const Icon(Icons.attach_file),
                label: const Text('Add files'),
              ),
            ),
          ],
        ),
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (var i = 0; i < _attachments.length; i++)
            _attachmentRow(theme, i),
        ],
      ],
    );
  }

  Widget _attachmentRow(ThemeData theme, int i) {
    final a = _attachments[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 8, right: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: a.isImage
                ? Image.memory(a.bytes, fit: BoxFit.cover, cacheWidth: 144)
                : ColoredBox(
                    color: theme.colorScheme.surfaceContainer,
                    child: Icon(Icons.insert_drive_file_outlined,
                        color: theme.colorScheme.primary),
                  ),
          ),
        ),
        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatFileSize(a.bytes.length)),
        trailing: IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.close),
          onPressed:
              _busy ? null : () => setState(() => _attachments.removeAt(i)),
        ),
      ),
    );
  }
}

/// A photo/file picked in the composer, not uploaded yet.
class _PendingAttachment {
  const _PendingAttachment({required this.bytes, required this.name});
  final Uint8List bytes;
  final String name;

  bool get isImage => contentTypeForFileName(name).startsWith('image/');
}
