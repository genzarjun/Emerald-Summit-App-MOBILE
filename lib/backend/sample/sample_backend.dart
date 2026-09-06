import 'package:get_it/get_it.dart';

import '../backend.dart';
import 'sample_repositories.dart';
import 'sample_store.dart';

/// Composition root for the in-memory sample backend, used when no live backend
/// is configured so the app runs standalone on demo data.
class SampleBackend {
  const SampleBackend._();

  static void register(GetIt getIt) {
    final store = SampleStore();

    getIt
      ..registerSingleton<BackendDescriptor>(
        const BackendDescriptor(name: 'Sample data', isLive: false),
      )
      ..registerSingleton<AuthService>(SampleAuthService())
      ..registerSingleton<CatalogRepository>(SampleCatalogRepository(store))
      ..registerSingleton<ContentRepository>(SampleContentRepository())
      ..registerSingleton<ScheduleRepository>(SampleScheduleRepository(store))
      ..registerSingleton<ProfileRepository>(SampleProfileRepository(store))
      ..registerSingleton<AnnouncementsRepository>(
          SampleAnnouncementsRepository(store))
      ..registerSingleton<AllowlistRepository>(SampleAllowlistRepository());
  }
}
