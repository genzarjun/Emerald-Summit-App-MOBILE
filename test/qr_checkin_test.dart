import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/screens/front_desk_screen.dart';
import 'package:emerald_summit/widgets/checkin_pass_card.dart';

const _id = '3f2b8c1e-9a4d-4e6f-8b2a-1c3d5e7f9a0b';

void main() {
  group('parseCheckinPass', () {
    test('accepts a bare user id, normalizing case and whitespace', () {
      expect(parseCheckinPass(_id), _id);
      expect(parseCheckinPass('  ${_id.toUpperCase()}\n'), _id);
    });

    test('rejects anything that is not a user id', () {
      expect(parseCheckinPass(null), isNull);
      expect(parseCheckinPass(''), isNull);
      expect(parseCheckinPass('https://emeraldsummit.org'), isNull);
      expect(parseCheckinPass('p8'), isNull);
      expect(parseCheckinPass('$_id-extra'), isNull);
      expect(parseCheckinPass("$_id'; drop table profiles;--"), isNull);
    });
  });

  group('RPC row parsing', () {
    test('scan_summit_checkin rows map to an outcome', () {
      ScanCheckinResult parse(Map<String, dynamic> row) =>
          ScanCheckinResult.fromMap(_id, row);

      expect(
        parse({'attendee_found': false}).outcome,
        ScanCheckinOutcome.notFound,
      );

      final fresh = parse({
        'attendee_found': true,
        'already_checked_in': false,
        'full_name': 'Grace Hopper',
        'email': 'grace@e.com',
        'role': 'participant',
        'checked_in_at': '2027-01-23T16:05:00+00:00',
      });
      expect(fresh.outcome, ScanCheckinOutcome.checkedIn);
      expect(fresh.name, 'Grace Hopper');
      expect(fresh.checkedInAt!.toUtc(), DateTime.utc(2027, 1, 23, 16, 5));

      expect(
        parse({'attendee_found': true, 'already_checked_in': true}).outcome,
        ScanCheckinOutcome.alreadyCheckedIn,
      );
    });

    test('my_summit_checkin rows map to a status', () {
      final s = MyCheckinStatus.fromMap({
        'present': true,
        'checked_in_at': '2027-01-23T16:05:00Z',
      });
      expect(s.present, isTrue);
      expect(s.checkedInAt, isNotNull);
      expect(MyCheckinStatus.fromMap({'present': false}).present, isFalse);
    });
  });

  group('SampleAttendanceRepository.scanSummitCheckin', () {
    late SampleStore store;
    late SampleAttendanceRepository repo;

    setUp(() {
      store = SampleStore();
      repo = SampleAttendanceRepository(store);
      store.attendees.add(
        const Attendee(
          id: _id,
          name: 'Grace Hopper',
          email: 'grace@e.com',
          role: 'participant',
          present: false,
        ),
      );
    });

    test('an unknown pass is not found and changes nothing', () async {
      final r = await repo.scanSummitCheckin(
        '00000000-0000-0000-0000-000000000000',
      );
      expect(r.outcome, ScanCheckinOutcome.notFound);
      expect(store.attendees.single.present, isFalse);
    });

    test('first scan checks in; a rescan keeps the original time', () async {
      final first = await repo.scanSummitCheckin(_id);
      expect(first.outcome, ScanCheckinOutcome.checkedIn);
      expect(first.name, 'Grace Hopper');
      expect(store.attendees.single.present, isTrue);

      final again = await repo.scanSummitCheckin(_id);
      expect(again.outcome, ScanCheckinOutcome.alreadyCheckedIn);
      expect(again.checkedInAt, first.checkedInAt);
      expect(store.attendees.single.present, isTrue);
    });

    test('undo un-checks them so the next scan checks in again', () async {
      await repo.scanSummitCheckin(_id);
      await repo.markSummitCheckin(_id, false);
      expect(store.attendees.single.present, isFalse);

      final r = await repo.scanSummitCheckin(_id);
      expect(r.outcome, ScanCheckinOutcome.checkedIn);
    });
  });

  group('CheckinStats', () {
    test('sums roles from fetch_checkin_stats rows', () {
      final stats = CheckinStats.fromRows([
        {'role': 'participant', 'total': 120, 'checked_in': 40},
        {'role': 'volunteer', 'total': 20, 'checked_in': 15},
        {'role': 'admin', 'total': 3, 'checked_in': 3},
      ]);
      expect(stats.everyone, (checkedIn: 58, total: 143));
      expect(stats.participants, (checkedIn: 40, total: 120));
      expect(stats.volunteers, (checkedIn: 15, total: 20));
    });

    test('missing roles count as zero', () {
      const stats = CheckinStats({});
      expect(stats.everyone, (checkedIn: 0, total: 0));
      expect(stats.volunteers, (checkedIn: 0, total: 0));
    });
  });

  group('sample check-in sync', () {
    test('stats follow check-ins and every change is announced', () async {
      final store = SampleStore();
      final repo = SampleAttendanceRepository(store);
      store.attendees.addAll(const [
        Attendee(
          id: _id,
          name: 'Grace',
          email: 'g@e.com',
          role: 'participant',
          present: false,
        ),
        Attendee(
          id: 'v1',
          name: 'Vol',
          email: 'v@e.com',
          role: 'volunteer',
          present: true,
        ),
      ]);
      var changes = 0;
      final sub = repo.checkinChanges().listen((_) => changes++);

      await repo.scanSummitCheckin(_id);
      await repo.markSummitCheckin('v1', false);
      await pumpEventQueue();
      expect(changes, 2);

      final stats = await repo.fetchCheckinStats();
      expect(stats.participants, (checkedIn: 1, total: 1));
      expect(stats.volunteers, (checkedIn: 0, total: 1));
      await sub.cancel();
    });
  });

  testWidgets('front desk stats update live when another desk checks in', (
    tester,
  ) async {
    await getIt.reset();
    await configureBackend();
    final store = SampleStore();
    final repo = SampleAttendanceRepository(store);
    getIt
      ..unregister<AttendanceRepository>()
      ..registerSingleton<AttendanceRepository>(repo);
    store.attendees.addAll(const [
      Attendee(
        id: _id,
        name: 'Grace Hopper',
        email: 'g@e.com',
        role: 'participant',
        present: false,
      ),
      Attendee(
        id: 'v1',
        name: 'Vera Volunteer',
        email: 'v@e.com',
        role: 'volunteer',
        present: false,
      ),
    ]);

    Finder tile(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
    );

    await tester.pumpWidget(const MaterialApp(home: FrontDeskScreen()));
    await tester.pump();
    expect(tile('Checked in: 0 of 2'), findsOneWidget);
    expect(tile('Volunteers: 0 of 1'), findsOneWidget);

    // Another device checks Vera in.
    await repo.scanSummitCheckin('v1');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(tile('Checked in: 1 of 2'), findsOneWidget);
    expect(tile('Volunteers: 1 of 1'), findsOneWidget);
    expect(tile('Participants: 0 of 1'), findsOneWidget);
    // The list re-synced too.
    final row = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('Vera Volunteer'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(row.value, isTrue);

    await tester.pumpWidget(const SizedBox()); // dispose: cancels the poll
  });

  testWidgets('the profile pass card shows a QR of the user id', (
    tester,
  ) async {
    await getIt.reset();
    await configureBackend(); // sample backend: status reads "not checked in"

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CheckinPassCard(userId: _id)),
      ),
    );
    await tester.pump();

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr, isNotNull);
    expect(find.text('Check-in pass'), findsOneWidget);
    expect(find.text('Not checked in yet'), findsOneWidget);

    await tester.tap(find.text('Show full screen'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('front-desk volunteer'), findsOneWidget);
  });
}
