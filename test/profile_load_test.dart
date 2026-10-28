import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
import 'package:emerald_summit/models/models.dart';
import 'package:emerald_summit/models/user_profile.dart';

/// Fails the first [failures] profile reads, like a phone with no signal.
class _FlakyProfiles extends SampleProfileRepository {
  _FlakyProfiles(super.store, this.failures);
  int failures;

  @override
  Future<UserProfile?> fetchMine() async {
    if (failures > 0) {
      failures--;
      throw Exception('network down');
    }
    return super.fetchMine();
  }
}

/// Holds the registrations read until [gate] completes.
class _SlowSchedule extends SampleScheduleRepository {
  _SlowSchedule(super.store);
  final gate = Completer<void>();

  @override
  Future<Map<String, ParticipationType>> fetchMyRegistrations() async {
    await gate.future;
    return super.fetchMyRegistrations();
  }
}

void main() {
  late SampleStore store;

  setUp(() async {
    await getIt.reset();
    await configureBackend();
    store = SampleStore()
      ..profile = UserProfile(
        id: 'u1',
        email: 'alex@example.com',
        fullName: 'Alex Rivera',
        onboarded: true,
        details: {'school': 'Emerald High School'},
      );
    getIt
      ..unregister<ProfileRepository>()
      ..registerSingleton<ProfileRepository>(_FlakyProfiles(store, 1));
  });
  tearDown(() async => appState.signOut());

  test('a failed profile load is reported, not treated as a new account',
      () async {
    await appState.loadProfile();
    expect(appState.profileLoadFailed, isTrue);
    expect(appState.profile, isNull);
    expect(appState.profileLoading, isFalse);

    // Retry once the connection is back.
    await appState.loadProfile();
    expect(appState.profileLoadFailed, isFalse);
    expect(appState.isOnboarded, isTrue);
    expect(appState.profile!.details['school'], 'Emerald High School');
  });

  test('signing out mid-load keeps the old account out of the app', () async {
    store.myRegistrations['s1'] = ParticipationType.spectator;
    final schedule = _SlowSchedule(store);
    getIt
      ..unregister<ProfileRepository>()
      ..registerSingleton<ProfileRepository>(_FlakyProfiles(store, 0))
      ..unregister<ScheduleRepository>()
      ..registerSingleton<ScheduleRepository>(schedule);

    final loading = appState.loadProfile();
    await pumpEventQueue();
    expect(appState.profile, isNotNull);

    await appState.signOut();
    schedule.gate.complete();
    await loading;

    expect(appState.profile, isNull);
    expect(appState.isRegistered('s1'), isFalse);
    expect(appState.scheduleEntries, isEmpty);
  });
}
