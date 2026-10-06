import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models/models.dart';

/// Opens [item] full-page and marks it opened (clears its unread dot). Used by
/// the News feed and the Home "Latest news" peek.
void openAnnouncement(BuildContext context, Announcement item) {
  appState.markAnnouncementOpened(item.id);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AnnouncementDetailScreen(announcement: item),
    ),
  );
}

/// The full announcement: subject, who sent it to whom and when, the whole
/// message, and any photos (tap for full screen) and files (tap to open). The
/// feed only shows the subject and a short preview.
///
/// Watches [appState] so an admin's "delete for everyone" (from any device)
/// replaces the page with a "removed" note instead of stale content.
class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({super.key, required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final live = appState.announcements
            .where((a) => a.id == announcement.id)
            .firstOrNull;
        final removed = live == null && appState.announcements.isNotEmpty;
        final a = live ?? announcement;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Announcement'),
            actions: [if (!removed) _ActionsMenu(item: a)],
          ),
          body: removed ? const _RemovedNote() : _Body(item: a),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.item});
  final Announcement item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final oversight = appState.adminOversightLabel(item);
    final photos = item.photos;
    final files = item.files;
    final when = item.createdAt == null
        ? item.timeAgo
        : formatDeadline(item.createdAt!);

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(icon: Icons.groups_outlined, label: item.audience),
              if (item.pinned)
                const _Chip(icon: Icons.push_pin, label: 'Pinned'),
            ],
          ),
          const SizedBox(height: 14),
          Text(item.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            [item.author, when].where((s) => s.isNotEmpty).join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (oversight != null) ...[
            const SizedBox(height: 14),
            _OversightNote(text: oversight),
          ],
          const SizedBox(height: 20),
          SelectableText(
            item.body,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (var i = 0; i < photos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PhotoTile(photos: photos, index: i),
              ),
          ],
          if (files.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Attachments', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final f in files) _FileTile(file: f),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
    );
  }
}

/// Admin-only line: "X sent an announcement to the Y discipline".
class _OversightNote extends StatelessWidget {
  const _OversightNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer)),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photos, required this.index});
  final List<AnnouncementAttachment> photos;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) =>
                  _PhotoViewer(photos: photos, initialIndex: index),
            ),
          ),
          child: CachedNetworkImage(
            imageUrl: photos[index].url,
            memCacheWidth: 1200,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (_, _) => const AspectRatio(
              aspectRatio: 4 / 3,
              child: Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (_, _, _) => const AspectRatio(
              aspectRatio: 4 / 3,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-to-zoom photo viewer.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initialIndex});
  final List<AnnouncementAttachment> photos;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: count > 1 ? Text('${_index + 1} of $count') : null,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: count,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.photos[i].url,
              memCacheWidth: 1200,
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
              errorWidget: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file});
  final AnnouncementAttachment file;

  IconData get _icon {
    final t = file.contentType;
    if (t == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (t.contains('spreadsheet') || t.contains('excel') || t == 'text/csv') {
      return Icons.table_chart_outlined;
    }
    if (t.contains('presentation') || t.contains('powerpoint')) {
      return Icons.slideshow_outlined;
    }
    if (t.startsWith('video/')) return Icons.movie_outlined;
    if (t.contains('word') || t.startsWith('text/')) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await launchUrl(Uri.parse(file.url),
        mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the file")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_icon, color: theme.colorScheme.primary),
        title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: file.sizeLabel.isEmpty ? null : Text(file.sizeLabel),
        trailing: const Icon(Icons.open_in_new, size: 20),
        onTap: () => _open(context),
      ),
    );
  }
}

enum _Action { hide, deleteForEveryone }

/// Overflow menu: hide from my feed (everyone), delete for everyone (admins).
class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.item});
  final Announcement item;

  Future<void> _onSelected(BuildContext context, _Action action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    switch (action) {
      case _Action.hide:
        await appState.hideAnnouncement(item.id);
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Removed from your feed'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => appState.unhideAnnouncement(item.id),
            ),
          ),
        );
      case _Action.deleteForEveryone:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete for everyone?'),
            content: const Text(
                'This permanently removes the announcement and its '
                'attachments for all users.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await appState.deleteAnnouncementForEveryone(item.id);
          navigator.pop();
          messenger.showSnackBar(
            const SnackBar(content: Text('Announcement deleted for everyone')),
          );
        } catch (_) {
          messenger.showSnackBar(
            const SnackBar(content: Text("Couldn't delete — please try again")),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Action>(
      onSelected: (a) => _onSelected(context, a),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _Action.hide,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_off_outlined),
            title: Text('Remove from my feed'),
          ),
        ),
        if (appState.isAdmin)
          const PopupMenuItem(
            value: _Action.deleteForEveryone,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline),
              title: Text('Delete for everyone'),
            ),
          ),
      ],
    );
  }
}

class _RemovedNote extends StatelessWidget {
  const _RemovedNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('This announcement was removed.',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
