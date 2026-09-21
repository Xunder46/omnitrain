// filepath: lib/core/services/image_storage_service_stub.dart
//
// Web stub for [ImageStorageService].
//
// Selected by the conditional import in
// `image_storage_service.dart` when `dart.library.io` is not
// available (i.e. the web target). Every method throws
// `UnsupportedError` so that the only callers — which already
// early-return on `kIsWeb` with the existing user-facing snackbar
// per D-8 — never reach the service in practice.
//
// On web, the existing call-site snackbar text is preserved
// verbatim:
//   "Photo selection works on web, but avatar persistence is not
//    supported there yet."
//   "Photo selection works on web, but food photo persistence is
//    not supported there yet."
//
// See D-8 in
// `.github/agents/plans/image-persistence-relocation-fix-plan.md`.

import 'dart:typed_data';

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
  /// variant. The arguments are intentionally unused on web
  /// (the stub throws on every operation).
  // ignore: unused_element_parameter
  ImageStorageService.fromBaseDirectory(
    String baseDirectory, {
    List<String>? extraCandidateDirs,
  });

  /// Mirror of `ImageStorageService.create` in the IO variant.
  /// Always throws on web.
  static Future<ImageStorageService> create() async => _unsupported();

  String get managedDirectoryPath => _unsupported();

  List<String> get candidateDirectories => _unsupported();

  bool isManaged(String path) => _unsupported();

  bool exists(String path) => _unsupported();

  /// Web stub. Always returns `null` (no managed images on web).
  /// The web path returns the fallback widget before any image
  /// rendering happens, so this method is never actually exercised
  /// in the production render path. It exists so the cross-platform
  /// widget API stays uniform.
  String? resolvePathSync(String? reference) => null;

  Future<String?> resolveOrRelink(String? reference) async => _unsupported();

  Future<String> persistPickedImage(XFile picked) async => _unsupported();

  /// Mirror of `ImageStorageService.persistImageBytes` in the IO
  /// variant. Always throws on web — the call site already
  /// early-returns on `kIsWeb` with the user-facing snackbar.
  Future<String> persistImageBytes(
    Uint8List bytes, {
    String extension = '.png',
  }) async => _unsupported();

  Future<void> deleteIfManaged(String? path) async => _unsupported();
}
