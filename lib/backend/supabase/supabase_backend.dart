import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import 'supabase_auth_service.dart';
import 'supabase_config.dart';
import 'supabase_repositories.dart';

/// Composition root for the Supabase backend. Initializes the SDK and registers
/// every service interface against its Supabase implementation.
///
/// This is the only file that calls `Supabase.initialize`. To swap backends,
/// write a sibling `<name>_backend.dart` with the same shape and point
/// `configureBackend` at it.
class SupabaseBackend {
  const SupabaseBackend._();

  static Future<void> register(GetIt getIt) async {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      publishableKey: SupabaseConfig.supabasePublishableKey,
    );
    final client = Supabase.instance.client;

    getIt
      ..registerSingleton<BackendDescriptor>(
        const BackendDescriptor(name: 'Supabase', isLive: true),
      )
      ..registerSingleton<AuthService>(SupabaseAuthService(client))
      ..registerSingleton<CatalogRepository>(
          SupabaseCatalogRepository(client))
      ..registerSingleton<ContentRepository>(
          SupabaseContentRepository(client))
      ..registerSingleton<ScheduleRepository>(
          SupabaseScheduleRepository(client))
      ..registerSingleton<ProfileRepository>(
          SupabaseProfileRepository(client))
      ..registerSingleton<AnnouncementsRepository>(
          SupabaseAnnouncementsRepository(client))
      ..registerSingleton<AllowlistRepository>(
          SupabaseAllowlistRepository(client))
      ..registerSingleton<RoomsRepository>(SupabaseRoomsRepository(client))
      ..registerSingleton<AssignmentRepository>(
          SupabaseAssignmentRepository(client))
      ..registerSingleton<AttendanceRepository>(
          SupabaseAttendanceRepository(client));
  }
}
