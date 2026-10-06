import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/user_profile.dart';

void main() {
  group('Announcement.fromMap attachments', () {
    test('splits photos from files and keeps their details', () {
      final a = Announcement.fromMap({
        'id': 1,
        'title': 'Parking',
        'body': 'Map attached',
        'created_at': '2026-10-05T18:30:00Z',
        'attachments': [
          {
            'url': 'https://x/p.jpg',
            'path': 'u1/a_1.jpg',
            'name': 'lot.jpg',
            'type': 'image/jpeg',
            'size': 2048,
          },
          {
            'url': 'https://x/f.pdf',
            'path': 'u1/a_2.pdf',
            'name': 'map.pdf',
            'type': 'application/pdf',
            'size': 1572864,
          },
        ],
      });
      expect(a.photos.map((p) => p.name), ['lot.jpg']);
      expect(a.files.map((f) => f.name), ['map.pdf']);
      expect(a.files.single.sizeLabel, '1.5 MB');
      expect(a.createdAt, isNotNull);
    });

    test('a row without the column has no attachments', () {
      final a = Announcement.fromMap({'id': 2, 'title': 't', 'body': 'b'});
      expect(a.attachments, isEmpty);
    });

    test('content types come from the extension', () {
      expect(contentTypeForFileName('IMG_1.JPG'), 'image/jpeg');
      expect(contentTypeForFileName('schedule.pdf'), 'application/pdf');
      expect(contentTypeForFileName('noext'), 'application/octet-stream');
    });
  });

  group('admin oversight label', () {
    tearDown(() => appState.profile = null);

    const leadPost = Announcement(
      id: 'a1',
      title: 'Bring laptops',
      body: 'Charged, please.',
      author: 'Priya Shah',
      audience: 'TechVerse',
      timeAgo: '1m ago',
      disciplineId: 'techverse',
      createdBy: 'lead-1',
    );

    test('admins see who sent a discipline announcement where', () {
      appState.profile =
          UserProfile(id: 'admin-1', email: 'a@b.com', role: SummitRole.admin);
      expect(appState.adminOversightLabel(leadPost),
          'Priya Shah sent an announcement to the TechVerse discipline');
    });

    test("an admin's own discipline post reads 'You sent…'", () {
      appState.profile =
          UserProfile(id: 'lead-1', email: 'a@b.com', role: SummitRole.admin);
      expect(appState.adminOversightLabel(leadPost),
          startsWith('You sent an announcement'));
    });

    test('no label for non-admins, Everyone posts, or personal notices', () {
      appState.profile = UserProfile(
          id: 'p1', email: 'p@b.com', role: SummitRole.participant);
      expect(appState.adminOversightLabel(leadPost), isNull);

      appState.profile =
          UserProfile(id: 'admin-1', email: 'a@b.com', role: SummitRole.admin);
      const everyone = Announcement(
          id: 'a2',
          title: 't',
          body: 'b',
          author: 'Admin',
          audience: 'Everyone',
          timeAgo: '');
      expect(appState.adminOversightLabel(everyone), isNull);
      const personal = Announcement(
          id: 'a3',
          title: 't',
          body: 'b',
          author: 'Summit',
          audience: 'TechVerse',
          timeAgo: '',
          disciplineId: 'techverse',
          targetUserId: 'someone');
      expect(appState.adminOversightLabel(personal), isNull);
    });
  });
}
