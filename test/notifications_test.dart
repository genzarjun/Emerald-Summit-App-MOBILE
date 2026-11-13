import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/user_profile.dart';
import 'package:emerald_summit/screens/notifications_screen.dart';

/// Records what the app asks of the bell's backend.
class _FakeNotifications implements NotificationsRepository {
  _FakeNotifications(this.items);

  List<AppNotification> items;
  final List<List<String>?> markedRead = [];
  int reminderCalls = 0;

  @override
  Future<List<AppNotification>> fetch({int limit = 100}) async => items;

  @override
  Future<void> markRead([Iterable<String>? ids]) async =>
      markedRead.add(ids?.toList());

  @override
  Future<void> queueMyReminders() async => reminderCalls++;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<void> stopChanges() async {}
}

AppNotification _note(String id, {bool read = false, String title = 'Note'}) =>
    AppNotification(
      id: id,
      kind: NotificationKind.notice,
      title: title,
      createdAt: DateTime.now(),
      readAt: read ? DateTime.now() : null,
    );

void main() {
  group('AppNotification.fromMap', () {
    test('reads the row and its kind', () {
      final n = AppNotification.fromMap({
        'id': 'n1',
        'kind': 'reminder',
        'title': 'Coming up at 10:30 AM: AI Playground',
        'body': 'Your session starts within the hour.',
        'session_id': 's1',
        'created_at': '2027-01-23T17:30:00Z',
        'read_at': null,
      });
      expect(n.kind, NotificationKind.reminder);
      expect(n.sessionId, 's1');
      expect(n.isRead, isFalse);
      expect(NotificationKind.parse('announcement'),
          NotificationKind.announcement);
      expect(NotificationKind.parse('anything else'), NotificationKind.notice);
    });
  });

  group('News leaves personal notices to the bell', () {
    tearDown(() {
      appState.announcements = const [];
      appState.profile = null;
      appState.notificationsAvailable = false;
    });

    const feed = [
      Announcement(
          id: 'post',
          title: 'Parking',
          body: 'b',
          author: 'Admin',
          audience: 'Everyone',
          timeAgo: ''),
      Announcement(
          id: 'notice',
          title: 'You have been assigned to manage Robot Showcase',
          body: 'b',
          author: 'Summit',
          audience: 'Everyone',
          timeAgo: '',
          targetUserId: 'me'),
    ];

    test('until the bell has loaded, News still shows my own notices', () {
      appState.profile = UserProfile(
          id: 'me', email: 'me@b.com', role: SummitRole.participant);
      appState.announcements = feed;
      expect(appState.visibleAnnouncements.map((a) => a.id),
          ['post', 'notice']);
    });

    test('a targeted notice is not in News; a post to everyone is', () {
      appState.profile = UserProfile(
          id: 'me', email: 'me@b.com', role: SummitRole.participant);
      appState.notificationsAvailable = true;
      appState.announcements = const [
        Announcement(
            id: 'post',
            title: 'Parking',
            body: 'b',
            author: 'Admin',
            audience: 'Everyone',
            timeAgo: ''),
        Announcement(
            id: 'notice',
            title: 'You have been assigned to manage Robot Showcase',
            body: 'b',
            author: 'Summit',
            audience: 'Everyone',
            timeAgo: '',
            targetUserId: 'me'),
      ];
      expect(appState.visibleAnnouncements.map((a) => a.id), ['post']);
    });
  });

  group('the bell', () {
    late _FakeNotifications fake;

    setUp(() async {
      await getIt.reset();
      await configureBackend();
      fake = _FakeNotifications([
        _note('a', title: 'Maya joined your team'),
        _note('b', read: true, title: 'Old note'),
      ]);
      getIt
        ..unregister<NotificationsRepository>()
        ..registerSingleton<NotificationsRepository>(fake);
      await appState.loadNotifications();
    });

    test('counts unread notes, and Mark all as read clears them', () async {
      expect(appState.unreadNotificationCount, 1);
      await appState.markAllNotificationsRead();
      expect(appState.unreadNotificationCount, 0);
      expect(fake.markedRead, [null]);
      // Nothing left to mark: no second call.
      await appState.markAllNotificationsRead();
      expect(fake.markedRead, hasLength(1));
    });

    test('marking one read sends just that id, once', () async {
      await appState.markNotificationRead('a');
      await appState.markNotificationRead('a');
      expect(fake.markedRead, [
        ['a']
      ]);
    });

    testWidgets('the list shows notes and Mark all as read', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Maya joined your team'), findsOneWidget);
      expect(find.text('Old note'), findsOneWidget);
      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();
      expect(find.text('Mark all as read'), findsNothing);
      expect(appState.unreadNotificationCount, 0);
    });

    testWidgets('an empty list says what will show up', (tester) async {
      fake.items = [];
      await appState.loadNotifications();
      await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Session reminders'), findsOneWidget);
    });
  });
}
