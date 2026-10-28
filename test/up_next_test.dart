import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';

void main() {
  // s1 runs 10:00–10:45 and s3 10:45–11:45 in the sample catalog.
  final day = DateTime(2027, 1, 23);
  DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);

  setUp(() async {
    await getIt.reset();
    await configureBackend();
    await appState.loadCatalog();
    await appState.loadSchedule();
    for (final id in ['s1', 's3']) {
      await appState.toggle(appState.allSessions.firstWhere((s) => s.id == id),
          type: ParticipationType.spectator);
    }
  });
  tearDown(() async => appState.signOut());

  test('before summit day it shows the first session of the day', () {
    appState.summitStatus = SummitStatus(date: day);
    final earlier = at(8, 0).subtract(const Duration(days: 3));
    expect(appState.upNext(earlier)?.id, 's1');
  });

  test('on summit day it skips sessions that have ended', () {
    appState.summitStatus = SummitStatus(date: day);
    expect(appState.upNext(at(9, 0))?.id, 's1');
    expect(appState.upNext(at(10, 30))?.id, 's1'); // still running
    expect(appState.upNext(at(10, 50))?.id, 's3');
    expect(appState.upNext(at(12, 0)), isNull);
  });

  test('nothing is up next once the summit is over', () {
    appState.summitStatus = SummitStatus(date: day);
    expect(appState.upNext(at(9, 0).add(const Duration(days: 1))), isNull);
  });

  test('without a summit date it shows the first session', () {
    appState.summitStatus = SummitStatus.unknown;
    expect(appState.upNext(at(12, 0))?.id, 's1');
  });

  test('a session the user manages counts', () async {
    await appState.signOut();
    await appState.loadCatalog();
    appState.myAssignedSessionIds = {'s3'};
    appState.summitStatus = SummitStatus(date: day);
    expect(appState.upNext(at(9, 0))?.id, 's3');
  });
}
