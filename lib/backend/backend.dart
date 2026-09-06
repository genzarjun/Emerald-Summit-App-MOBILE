/// The backend seam — one import that re-exports every backend-neutral contract
/// the app depends on, plus a descriptor of the active backend.
///
/// App code imports `backend/backend.dart` (for the types) and
/// `backend/service_locator.dart` (for the instances). Nothing outside
/// `backend/<impl>/` ever imports a backend SDK.
library;

export 'auth_service.dart';
export 'repositories.dart';

/// Human-facing description of the active backend, used for UI copy (e.g. the
/// News "Live from …" line) without leaking a backend's name into screens.
class BackendDescriptor {
  const BackendDescriptor({required this.name, required this.isLive});

  /// Display name, e.g. "Supabase". Shown only when [isLive].
  final String name;

  /// True for a real remote backend; false for the in-memory sample fallback.
  final bool isLive;
}
