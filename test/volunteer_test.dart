import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/user_profile.dart';

void main() {
  group('SummitRole', () {
    test('volunteer replaces mentor with the right id/label and is gated', () {
      expect(SummitRole.volunteer.id, 'volunteer');
      expect(SummitRole.volunteer.label, 'Volunteer');
      expect(SummitRole.volunteer.isGated, isTrue);
      expect(SummitRole.admin.isGated, isTrue);
      expect(SummitRole.participant.isGated, isFalse);
    });

    test('fromId maps the stored string, falling back to participant', () {
      expect(SummitRoleX.fromId('volunteer'), SummitRole.volunteer);
      expect(SummitRoleX.fromId('mentor'), SummitRole.participant); // legacy gone
      expect(SummitRoleX.fromId(null), SummitRole.participant);
    });
  });

  group('VolunteerSubtype', () {
    test('id / label / fromId round-trip', () {
      expect(VolunteerSubtype.eafAmbassador.id, 'eaf_ambassador');
      expect(VolunteerSubtype.eafAmbassador.label, 'EAF Ambassador');
      expect(VolunteerSubtypeX.fromId('parent_volunteer'),
          VolunteerSubtype.parentVolunteer);
      expect(VolunteerSubtypeX.fromId('student_volunteer'),
          VolunteerSubtype.studentVolunteer);
      expect(VolunteerSubtypeX.fromId('nonsense'), isNull);
      expect(VolunteerSubtypeX.fromId(null), isNull);
    });
  });

  group('UserProfile.fromMap', () {
    test('parses subtype + capability flags', () {
      final p = UserProfile.fromMap({
        'id': 'u1',
        'email': 'a@b.com',
        'role': 'volunteer',
        'volunteer_subtype': 'eaf_ambassador',
        'can_edit_sessions': true,
        'can_post_announcements': true,
        'can_check_in_front_desk': false,
        'managed_disciplines': ['techverse'],
      });
      expect(p.role, SummitRole.volunteer);
      expect(p.volunteerSubtype, VolunteerSubtype.eafAmbassador);
      expect(p.canEditSessions, isTrue);
      expect(p.canPostAnnouncements, isTrue);
      expect(p.canCheckInFrontDesk, isFalse);
    });

    test('capability flags default to false when absent', () {
      final p = UserProfile.fromMap({
        'id': 'u2',
        'email': 'c@d.com',
        'role': 'participant',
      });
      expect(p.canEditSessions, isFalse);
      expect(p.canPostAnnouncements, isFalse);
      expect(p.canCheckInFrontDesk, isFalse);
      expect(p.volunteerSubtype, isNull);
    });
  });

  group('canManageDiscipline', () {
    UserProfile volunteer({
      required bool canEdit,
      List<String> scope = const ['techverse'],
    }) =>
        UserProfile(
          id: 'v',
          email: 'v@e.com',
          role: SummitRole.volunteer,
          canEditSessions: canEdit,
          managedDisciplines: scope,
        );

    test('admins manage everything', () {
      final admin = UserProfile(id: 'a', email: 'a@e.com', role: SummitRole.admin);
      expect(admin.canManageDiscipline('anything'), isTrue);
    });

    test('a volunteer needs can_edit_sessions AND scope', () {
      expect(volunteer(canEdit: true).canManageDiscipline('techverse'), isTrue);
      expect(volunteer(canEdit: true).canManageDiscipline('mathverse'), isFalse);
      // Same scope but no edit capability → cannot manage.
      expect(volunteer(canEdit: false).canManageDiscipline('techverse'), isFalse);
    });

    test('the * wildcard scopes to every discipline (with edit)', () {
      final wild = volunteer(canEdit: true, scope: const ['*']);
      expect(wild.canManageDiscipline('anything'), isTrue);
    });

    test('participants never manage', () {
      final p = UserProfile(id: 'p', email: 'p@e.com');
      expect(p.canManageDiscipline('techverse'), isFalse);
    });
  });

  group('canPostToDiscipline', () {
    test('volunteer needs can_post_announcements AND scope; admin always', () {
      final admin = UserProfile(id: 'a', email: 'a@e.com', role: SummitRole.admin);
      expect(admin.canPostToDiscipline('x'), isTrue);

      final poster = UserProfile(
        id: 'v', email: 'v@e.com', role: SummitRole.volunteer,
        canPostAnnouncements: true, managedDisciplines: const ['techverse'],
      );
      expect(poster.canPostToDiscipline('techverse'), isTrue);
      expect(poster.canPostToDiscipline('mathverse'), isFalse);

      final noPost = UserProfile(
        id: 'v2', email: 'v2@e.com', role: SummitRole.volunteer,
        canPostAnnouncements: false, managedDisciplines: const ['techverse'],
      );
      expect(noPost.canPostToDiscipline('techverse'), isFalse);
    });
  });

  group('Sample repositories', () {
    late SampleStore store;

    setUp(() => store = SampleStore());

    test('rooms are seeded from sample sessions and support CRUD', () async {
      final repo = SampleRoomsRepository(store);
      final seeded = await repo.fetchAll();
      expect(seeded, isNotEmpty); // sample sessions carry room strings

      await repo.create({'name': 'New Hall'});
      expect((await repo.fetchAll()).any((r) => r.name == 'New Hall'), isTrue);

      final hall = (await repo.fetchAll()).firstWhere((r) => r.name == 'New Hall');
      await repo.update(hall.id, {'name': 'Renamed Hall'});
      expect((await repo.fetchAll()).any((r) => r.name == 'Renamed Hall'), isTrue);

      await repo.delete(hall.id);
      expect((await repo.fetchAll()).any((r) => r.name == 'Renamed Hall'), isFalse);
    });

    test('assignment succeeds, then a time-overlap is refused', () async {
      final repo = SampleAssignmentRepository(store);
      final sessions = store.allSessions;
      // Two sessions that overlap in time (share the same start slot).
      final a = sessions.first;
      final overlapping = sessions.firstWhere(
        (s) => s.id != a.id && s.overlaps(a),
        orElse: () => a,
      );

      final r1 = await repo.assign(a.id, 'vol-1');
      expect(r1.outcome, AssignmentOutcome.assigned);

      if (overlapping.id != a.id) {
        final r2 = await repo.assign(overlapping.id, 'vol-1');
        expect(r2.outcome, AssignmentOutcome.conflict);
        expect(r2.conflictingTitle, a.title);
      }

      // A different volunteer with no commitments can still take it.
      final r3 = await repo.assign(a.id, 'vol-2');
      expect(r3.outcome, AssignmentOutcome.assigned);

      await repo.unassign(a.id, 'vol-1');
      final after = await repo.fetchSessionVolunteers(a.id);
      expect(after.any((v) => v.id == 'vol-1'), isFalse);
    });

    test('assigning a volunteer registered for the session asks to confirm',
        () async {
      final repo = SampleAssignmentRepository(store);
      final s = store.allSessions.first;
      // The volunteer is registered for this very session.
      store.mySessionIds.add(s.id);

      final first = await repo.assign(s.id, 'vol-9');
      expect(first.outcome, AssignmentOutcome.registeredConfirm);

      // Confirming proceeds with the assignment.
      final confirmed =
          await repo.assign(s.id, 'vol-9', confirmRegistered: true);
      expect(confirmed.outcome, AssignmentOutcome.assigned);
    });

    test('session attendance can be marked on a seeded roster', () async {
      final repo = SampleAttendanceRepository(store);
      const sid = 's1';
      store.rosters[sid] = [
        const RosterEntry(
            userId: 'p1', name: 'Ada', email: 'ada@e.com', attended: false),
      ];
      await repo.markSessionAttendance(sid, 'p1', true);
      final roster = await repo.fetchSessionRoster(sid);
      expect(roster.single.attended, isTrue);
    });

    test('front-desk directory filters and marks check-in', () async {
      final repo = SampleAttendanceRepository(store);
      store.attendees.addAll(const [
        Attendee(
            id: 'a1', name: 'Grace Hopper', email: 'grace@e.com',
            role: 'participant', present: false),
        Attendee(
            id: 'a2', name: 'Alan Turing', email: 'alan@e.com',
            role: 'participant', present: false),
      ]);
      final filtered = await repo.fetchAttendeeDirectory('grace');
      expect(filtered.single.id, 'a1');

      await repo.markSummitCheckin('a2', true);
      final all = await repo.fetchAttendeeDirectory('');
      expect(all.firstWhere((a) => a.id == 'a2').present, isTrue);
    });

    test('announcement: hide-from-my-view tracks dismissals; undo clears them',
        () async {
      final repo = SampleAnnouncementsRepository(store);
      final id = (await repo.fetch()).first.id;

      expect(await repo.fetchDismissed(), isEmpty);

      await repo.hideForMe(id);
      expect(await repo.fetchDismissed(), contains(id));
      // The row itself is untouched — a hide is per-user only.
      expect((await repo.fetch()).any((a) => a.id == id), isTrue);

      await repo.unhideForMe(id);
      expect(await repo.fetchDismissed(), isEmpty);
    });

    test('announcement: delete-for-everyone removes the row', () async {
      final repo = SampleAnnouncementsRepository(store);
      final id = (await repo.fetch()).first.id;

      await repo.deleteForEveryone(id);
      expect((await repo.fetch()).any((a) => a.id == id), isFalse);
    });
  });
}
