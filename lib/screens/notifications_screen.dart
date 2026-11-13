import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';
import 'announcement_detail_screen.dart';
import 'session_detail_screen.dart';

/// Opens the bell's Notifications list.
void openNotificationsScreen(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
  );
}

/// The bell's list: short notes about you (a new post that reaches you, a
/// personal notice, a session starting within the hour). Separate from News,
/// which holds the organizers' posts. Tapping a note marks it read and opens
/// the post or session it's about; "Mark all as read" clears the bell.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => appState.loadNotifications());
  }

  void _open(AppNotification n) {
    appState.markNotificationRead(n.id);
    final postId = n.announcementId;
    if (n.kind == NotificationKind.announcement && postId != null) {
      final post = appState.announcements.where((a) => a.id == postId).firstOrNull;
      if (post != null) {
        openAnnouncement(context, post);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That post was removed.')),
        );
      }
      return;
    }
    final sessionId = n.sessionId;
    if (sessionId != null) {
      final session =
          appState.allSessions.where((s) => s.id == sessionId).firstOrNull;
      if (session != null) {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SessionDetailScreen(session: session),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final items = appState.notifications;
        final unread = appState.unreadNotificationCount;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (unread > 0)
                TextButton(
                  onPressed: appState.markAllNotificationsRead,
                  child: const Text('Mark all as read'),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: appState.loadNotifications,
            child: items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      if (appState.notificationsLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (appState.notificationsError != null)
                        Text(
                          "Couldn't load your notifications. Pull down to try again.",
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        )
                      else
                        Text(
                          'Nothing yet. Session reminders, new posts for you and '
                          'changes to your sessions or team show up here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _NotificationTile(item: items[i], onTap: _open),
                  ),
          ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final void Function(AppNotification) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (item.kind) {
      NotificationKind.reminder => Icons.alarm_outlined,
      NotificationKind.announcement => Icons.campaign_outlined,
      NotificationKind.notice => Icons.person_outline,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(icon, color: theme.colorScheme.primary, size: 20),
      ),
      title: Text(
        item.title,
        style: TextStyle(
            fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w700),
      ),
      subtitle: Text(
        [if (item.body.isNotEmpty) item.body, item.timeAgo]
            .where((t) => t.isNotEmpty)
            .join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: item.body.isNotEmpty,
      trailing: item.isRead
          ? null
          : Semantics(
              label: 'Unread',
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
      onTap: () => onTap(item),
    );
  }
}
