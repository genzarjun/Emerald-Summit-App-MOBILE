import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';

Announcement _post(String id, DateTime at, {bool pinned = false}) =>
    Announcement(
      id: id,
      title: id,
      body: '',
      author: 'Admin',
      audience: 'Everyone',
      timeAgo: '',
      pinned: pinned,
      createdAt: at,
    );

void main() {
  final t0 = DateTime(2026, 11, 22, 9);

  setUp(() async {
    await getIt.reset();
    await configureBackend();
    appState.profile = null;
    appState.announcementsLoading = false;
    appState.announcements = [
      _post('pinned', t0, pinned: true),
      _post('older', t0.add(const Duration(hours: 1))),
    ];
  });

  tearDown(() => appState.announcements = const []);

  test('a live post with its full row is added in place, no reload', () {
    final added = _post('new', t0.add(const Duration(hours: 2)));
    appState.handleAnnouncementEvent(AnnouncementEvent(
      id: 'new',
      title: 'new',
      body: '',
      createdBy: 'someone-else',
      announcement: added,
    ));
    expect(appState.announcementsLoading, isFalse);
    expect(appState.announcements.map((a) => a.id), ['pinned', 'new', 'older']);
  });

  test('the same post arriving twice is kept once', () {
    final added = _post('older', t0.add(const Duration(hours: 1)));
    appState.handleAnnouncementEvent(AnnouncementEvent(
      id: 'older',
      title: 'older',
      body: '',
      createdBy: 'someone-else',
      announcement: added,
    ));
    expect(appState.announcements.map((a) => a.id), ['pinned', 'older']);
  });

  test('a cut-short live message falls back to reloading the feed', () {
    appState.handleAnnouncementEvent(const AnnouncementEvent(
      id: 'big',
      title: 'big',
      body: '',
      createdBy: 'someone-else',
    ));
    expect(appState.announcementsLoading, isTrue);
  });
}
