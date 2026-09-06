/// Dependency wiring for the backend seam.
///
/// [configureBackend] picks and registers ONE backend implementation at
/// startup. It is the single switch point in the whole app: to move to a
/// different backend, add its `register()` and select it here — no other file
/// changes.
library;

import 'package:get_it/get_it.dart';

import 'backend.dart';
import 'sample/sample_backend.dart';
import 'supabase/supabase_backend.dart';
import 'supabase/supabase_config.dart';

/// The service locator. Registrations are done once in [configureBackend].
final GetIt getIt = GetIt.instance;

/// Registers the active backend's services. Called once from `main` before
/// `runApp`. Chooses the live backend when its credentials are present,
/// otherwise the in-memory sample backend so the app still runs standalone.
Future<void> configureBackend() async {
  if (SupabaseConfig.isConfigured) {
    await SupabaseBackend.register(getIt);
  } else {
    SampleBackend.register(getIt);
  }
}

// ---- Ergonomic typed accessors -------------------------------------------
// So call sites read as `catalogRepository.fetchAll()` rather than repeating
// `getIt<CatalogRepository>()` everywhere.

AuthService get authService => getIt<AuthService>();
CatalogRepository get catalogRepository => getIt<CatalogRepository>();
ContentRepository get contentRepository => getIt<ContentRepository>();
ScheduleRepository get scheduleRepository => getIt<ScheduleRepository>();
ProfileRepository get profileRepository => getIt<ProfileRepository>();
AnnouncementsRepository get announcementsRepository =>
    getIt<AnnouncementsRepository>();
AllowlistRepository get allowlistRepository => getIt<AllowlistRepository>();

/// Description of the active backend, for UI copy.
BackendDescriptor get backendInfo => getIt<BackendDescriptor>();
