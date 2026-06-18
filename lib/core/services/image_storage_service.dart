// filepath: lib/core/services/image_storage_service.dart
//
// Public entry point for the managed image storage helper.
//
// The concrete implementation is selected at compile time via a
// conditional import that mirrors the existing pattern used by
// `lib/features/profile/widgets/profile_avatar_image*.dart` and
// `lib/features/nutrition/widgets/food_thumbnail*.dart`:
//
//   * On native targets (iOS, Android, macOS, Windows, Linux, the
//     host VM) the IO variant is selected. It uses `dart:io` and
//     `path_provider` to copy every picked image into a managed
//     directory inside the app's documents storage.
//   * On web the stub variant is selected. It throws
//     `UnsupportedError` from every method so that the call sites
//     — which already early-return on `kIsWeb` with the existing
//     user-facing snackbar — never reach the service.
//
// See D-1, D-5, D-8 in
// `.github/agents/plans/image-persistence-fix-plan.md` for the
// full design contract.

export 'image_storage_service_stub.dart'
    if (dart.library.io) 'image_storage_service_io.dart';
