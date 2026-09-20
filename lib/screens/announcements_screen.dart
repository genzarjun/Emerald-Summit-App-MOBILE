import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../theme.dart';
import '../models/models.dart';
import 'announcement_compose_screen.dart';

/// "News" tab — the announcement feed (spec section 04 — Announcements).
///
/// Reads from [appState], which loads the feed from the backend (or sample data)
/// and keeps it live via the backend's event stream — a new announcement appears
/// here the instant an admin posts it, alongside the in-app banner. Admins get
/// a "New announcement" button.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  @override
  void initState() {
    super.initState();
    // Load if the feed hasn't been primed yet (e.g. opened before the auth gate
    // finished, or a direct sample-mode open).
    if (appState.announcements.isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => appState.loadAnnouncements());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final items = appState.visibleAnnouncements;
        final loading = appState.announcementsLoading;
        final error = appState.announcementsError;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Announcements'),
            actions: [
              if (backendInfo.isLive)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload from backend',
                  onPressed: loading ? null : appState.loadAnnouncements,
                ),
            ],
          ),
          floatingActionButton: appState.canComposeAnnouncement
              ? FloatingActionButton.extended(
                  heroTag: 'fab-new-announcement',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AnnouncementComposeScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                )
              : null,
          body: _body(items, loading, error),
        );
      },
    );
  }

  Widget _body(List<Announcement> items, bool loading, Object? error) {
    final live = backendInfo.isLive;

    if (loading && items.isEmpty && error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && items.isEmpty) {
      return _buildError(error.toString());
    }

    return Column(
      children: [
        _SourceBanner(
          live: live,
          text: live
              ? 'Live from ${backendInfo.name} · ${items.length} '
                  'announcement${items.length == 1 ? '' : 's'}'
              : 'Sample data — no backend configured yet',
        ),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: appState.loadAnnouncements,
            child: items.isEmpty
                ? _emptyState()
                : _list(items, alwaysScrollable: true),
          ),
        ),
      ],
    );
  }

  Widget _list(List<Announcement> items, {bool alwaysScrollable = false}) {
    return ListView.separated(
      physics:
          alwaysScrollable ? const AlwaysScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _SwipeableAnnouncement(item: items[i]),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: Center(
            child: Text(
              'No announcements yet. Pull down to refresh.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError(String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 56, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text("Couldn't reach the backend",
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: appState.announcementsLoading
                ? null
                : appState.loadAnnouncements,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// Small banner showing where the data came from.
class _SourceBanner extends StatelessWidget {
  const _SourceBanner({required this.live, required this.text});
  final bool live;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = live ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    return Container(
      width: double.infinity,
      color: EmeraldTheme.mist,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(live ? Icons.cloud_done : Icons.storage, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: theme.textTheme.labelMedium?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// What a swipe-to-delete should do.
enum _DeleteScope { everyone, mine }

/// Wraps an announcement card in a swipe-left ([Dismissible]) gesture.
///
/// Everyone can swipe to "delete from my view" (a per-user hide, with Undo).
/// Admins additionally get to choose "Delete for everyone" (a permanent delete
/// that propagates to all devices) via a choice sheet.
///
/// The list is driven by [appState], so each action mutates app state and the
/// parent rebuild removes the card — we always return `false` from
/// `confirmDismiss` and never let [Dismissible] remove the widget itself.
class _SwipeableAnnouncement extends StatelessWidget {
  const _SwipeableAnnouncement({required this.item});
  final Announcement item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('announcement-${item.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) => _onSwipe(context),
      child: _AnnouncementCard(item: item),
    );
  }

  /// Handles the swipe. Returns `false` in every path — app state drives removal.
  Future<bool> _onSwipe(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    if (appState.isAdmin) {
      final scope = await _pickDeleteScope(context);
      if (scope == null) return false; // cancelled
      if (scope == _DeleteScope.everyone) {
        try {
          await appState.deleteAnnouncementForEveryone(item.id);
          messenger.showSnackBar(
            const SnackBar(content: Text('Announcement deleted for everyone')),
          );
        } catch (_) {
          messenger.showSnackBar(
            const SnackBar(content: Text("Couldn't delete — please try again")),
          );
        }
        return false;
      }
      // scope == mine → fall through to the per-user hide below.
    }

    await _hideForMe(messenger);
    return false;
  }

  Future<void> _hideForMe(ScaffoldMessengerState messenger) async {
    await appState.hideAnnouncement(item.id);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Removed from your feed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => appState.unhideAnnouncement(item.id),
        ),
      ),
    );
  }

  /// Admin choice sheet: delete for everyone vs. just hide from my feed.
  Future<_DeleteScope?> _pickDeleteScope(BuildContext context) {
    final theme = Theme.of(context);
    return showModalBottomSheet<_DeleteScope>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text(
                item.title,
                style: theme.textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            ListTile(
              leading: Icon(Icons.visibility_off_outlined,
                  color: theme.colorScheme.primary),
              title: const Text('Remove from my feed'),
              subtitle: const Text('Hidden only for you'),
              onTap: () => Navigator.of(sheetContext).pop(_DeleteScope.mine),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: theme.colorScheme.error),
              title: Text('Delete for everyone',
                  style: TextStyle(color: theme.colorScheme.error)),
              subtitle: const Text('Permanently removes it for all users'),
              onTap: () => Navigator.of(sheetContext).pop(_DeleteScope.everyone),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item});
  final Announcement item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Unread dot persists until this specific card is opened (tapped), even
    // after the News tab's red badge has cleared.
    final unopened = appState.isAnnouncementUnopened(item.id);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => appState.markAnnouncementOpened(item.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (unopened) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (item.pinned) ...[
                    Icon(Icons.push_pin,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(item.title, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(item.body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: EmeraldTheme.mist,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(item.audience,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    [item.author, item.timeAgo]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}
