import 'package:flutter_test/flutter_test.dart';

import 'package:emerald_summit/app_state.dart';
import 'package:emerald_summit/backend/repositories.dart';
import 'package:emerald_summit/backend/sample/sample_repositories.dart';
import 'package:emerald_summit/backend/sample/sample_store.dart';
import 'package:emerald_summit/backend/service_locator.dart';
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
}
