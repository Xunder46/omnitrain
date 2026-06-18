// filepath: lib/core/services/image_storage_service_stub.dart
//
// Web stub for [ImageStorageService].
//
// Selected by the conditional import in
// `image_storage_service.dart` when `dart.library.io` is not
// available (i.e. the web target). Every method throws
// `UnsupportedError` so that the only callers — which already
// early-return on `kIsWeb` with the existing user-facing snackbar
// per D-5 — never reach the service in practice.
//
// On web, the existing call-site snackbar text is preserved
// verbatim:
//   "Photo selection works on web, but avatar persistence is not
//    supported there yet."
//   "Photo selection works on web, but food photo persistence is
//    not supported there yet."
//
// See D-5 in `.github/agents/plans/image-persistence-fix-plan.md`.

import 'package:image_picker/image_picker.dart' show XFile;

Never _unsupported() => throw UnsupportedError(
      'ImageStorageService is not available on web. '
      'Image persistence is native-only in this iteration; '
      'see .github/agents/plans/image-persistence-fix-plan.md (D-5).',
    );

/// Web stub. Mirrors the IO variant's public surface. Every
/// method throws `UnsupportedError` — see file-level doc.
class ImageStorageService {
  /// Mirror of `ImageStorageService.fromBaseDirectory` in the IO
  /// variant. The argument is intentionally unused on web
  /// (the stub throws on every operation).
  // ignore: unused_element_parameter
  ImageStorageService.fromBaseDirectory(String baseDirectory);

  /// Mirror of `ImageStorageService.create` in the IO variant.
  /// Always throws on web.
  static Future<ImageStorageService> create() async => _unsupported();

  String get managedDirectoryPath => _unsupported();

  bool isManaged(String path) => _unsupported();

  bool exists(String path) => _unsupported();

  Future<String?> resolveOrNull(String? path) async => _unsupported();

  Future<String> persistPickedImage(XFile picked) async => _unsupported();

  Future<void> deleteIfManaged(String? path) async => _unsupported();
}
