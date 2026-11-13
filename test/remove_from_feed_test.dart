import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/screens/announcement_detail_screen.dart';

const _post = Announcement(
  id: 'p1',
  title: 'Parking',
  body: 'Use lot B.',
  author: 'Admin',
  audience: 'Everyone',
  timeAgo: '1h ago',
);

Widget _menu() => const MaterialApp(
      home: Scaffold(body: Center(child: AnnouncementActionsMenu(item: _post))),
    );

void main() {
  setUp(() async {
    await getIt.reset();
    await configureBackend();
    appState.announcements = const [_post];
    appState.profile = null;
  });

  tearDown(() async {
    await appState.unhideAnnouncement('p1');
    appState.announcements = const [];
  });

  Future<void> openRemove(WidgetTester tester) async {
    await tester.pumpWidget(_menu());
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove this announcement from my feed'));
    await tester.pumpAndSettle();
  }

  testWidgets('removing asks first and says it can’t be undone',
      (tester) async {
    await openRemove(tester);
    expect(find.text('Remove from your feed?'), findsOneWidget);
    expect(find.textContaining("you can't get it back in your feed"),
        findsOneWidget);
    expect(appState.visibleAnnouncements.map((a) => a.id), ['p1']);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(appState.visibleAnnouncements, isEmpty);
    expect(find.text('Removed from your feed'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Cancel keeps the post', (tester) async {
    await openRemove(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(appState.visibleAnnouncements.map((a) => a.id), ['p1']);
  });

  testWidgets('only admins see Delete for everyone', (tester) async {
    await tester.pumpWidget(_menu());
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for everyone'), findsNothing);
  });
}
