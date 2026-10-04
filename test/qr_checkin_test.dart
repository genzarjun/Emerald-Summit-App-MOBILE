import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/models/models.dart';
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

      expect(parse({'attendee_found': false}).outcome,
          ScanCheckinOutcome.notFound);

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
          ScanCheckinOutcome.alreadyCheckedIn);
    });

    test('my_summit_checkin rows map to a status', () {
      final s = MyCheckinStatus.fromMap(
          {'present': true, 'checked_in_at': '2027-01-23T16:05:00Z'});
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
      store.attendees.add(const Attendee(
          id: _id, name: 'Grace Hopper', email: 'grace@e.com',
          role: 'participant', present: false));
    });

    test('an unknown pass is not found and changes nothing', () async {
      final r = await repo.scanSummitCheckin(
          '00000000-0000-0000-0000-000000000000');
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

  testWidgets('the profile pass card shows a QR of the user id',
      (tester) async {
    await getIt.reset();
    await configureBackend(); // sample backend: status reads "not checked in"

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CheckinPassCard(userId: _id)),
    ));
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
