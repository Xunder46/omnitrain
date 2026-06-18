// filepath: lib/core/services/image_storage_service_io.dart
//
// Native implementation of [ImageStorageService].
//
// All persisted image files live under
// `<applicationDocumentsDirectory>/omni_images/`. Each file is
// named `<uuid-v4>.<ext>` where `<ext>` is preserved from the
// picked `XFile.name` (with a fallback chain to the source path
// and finally `.jpg` for unnamed picker results).
//
// The service is a stateless file-system helper. It is constructed
// either with an explicit base directory (tests) or via the async
// `ImageStorageService.create()` factory which resolves
// `getApplicationDocumentsDirectory()` once at app start.
//
// See D-1, D-2, D-3, D-6, D-7 in
// `.github/agents/plans/image-persistence-fix-plan.md`.

import 'dart:io';

import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Subdirectory under the app's documents directory that owns
/// every persisted image. Constant — do not parameterize; the
/// `isManaged` contract relies on a single, stable name.
const String _managedSubdir = 'omni_images';

/// Generic fallback extension for picked files where the source
/// name has no extension. Picked photos are almost always JPEG;
/// `Image.file` reads bytes regardless of extension, so this is
/// only a default for filesystem-friendliness, not correctness.
const String _defaultExtension = '.jpg';

const _uuid = Uuid();

/// File-system helper that owns the managed image directory. See
/// the library doc on `image_storage_service.dart` for the
/// conditional-import contract.
class ImageStorageService {
  /// Already-resolved managed directory path. Computed once at
  /// construction; the service never re-queries the platform
  /// during normal use.
  final String _managedDir;

  /// Construct from an explicit base directory. Synchronous so
  /// tests can inject a temp directory without dealing with
  /// `path_provider` mocks.
  ///
  /// [baseDirectory] is the value returned by
  /// `getApplicationDocumentsDirectory()` (or a test temp dir).
  /// The managed directory is `<baseDirectory>/omni_images/`.
  ImageStorageService.fromBaseDirectory(String baseDirectory)
      : _managedDir = p.normalize(p.join(baseDirectory, _managedSubdir));

  /// Async factory that resolves the app documents directory via
  /// `path_provider`. Use from `main.dart` at app start.
  static Future<ImageStorageService> create() async {
    final docs = await getApplicationDocumentsDirectory();
    return ImageStorageService.fromBaseDirectory(docs.path);
  }

  /// The absolute path of the managed directory. Exposed for tests
  /// and for the self-heal path in `ProfileState` /
  /// `FoodLibraryState` (see INV-3 — state classes use the
  /// read-side helpers only, never mutate files themselves).
  String get managedDirectoryPath => _managedDir;

  /// Returns `true` iff [path] resolves to a file under the
  /// managed directory. This is the sole gate for "delete on
  /// replace/remove" (INV-3 + D-3): the service never deletes a
  /// file outside the directory it owns.
  bool isManaged(String path) {
    if (path.isEmpty) return false;
    return p.isWithin(_managedDir, p.normalize(path));
  }

  /// Synchronous existence check for the file at [path]. Used by
  /// the load-time self-heal in the state classes.
  bool exists(String path) {
    if (path.isEmpty) return false;
    return File(path).existsSync();
  }

  /// Convenience for the load-time self-heal: returns [path]
  /// when the file exists, else `null`. Never throws.
  Future<String?> resolveOrNull(String? path) async {
    if (path == null || path.isEmpty) return null;
    if (!exists(path)) return null;
    return path;
  }

  /// Copies the bytes of [picked] into the managed directory and
  /// returns the new absolute path.
  ///
  /// The destination filename is `<uuid-v4>.<ext>`. If the
  /// picked file has no extension, [path]'s extension is tried,
  /// then `.jpg` as a generic fallback.
  ///
  /// If the copy throws (disk full, permission denied, source
  /// missing) the partially-written destination is removed
  /// before the exception is rethrown (D-6 — no partial files
  /// left behind on disk).
  Future<String> persistPickedImage(XFile picked) async {
    await _ensureManagedDir();

    final extension = _resolveExtension(picked);
    final filename = '${_uuid.v4()}$extension';
    final destination = p.join(_managedDir, filename);

    final source = File(picked.path);
    final dest = File(destination);

    try {
      await source.copy(destination);
      return destination;
    } catch (e) {
      // Best-effort cleanup of a partial destination so we never
      // leave 0-byte orphans. Swallow secondary errors — the
      // primary failure is the one the caller needs to see.
      if (await dest.exists()) {
        try {
          await dest.delete();
        } catch (_) {
          // Ignore — primary error is rethrown below.
        }
      }
      rethrow;
    }
  }

  /// Deletes the file at [path] iff it lives under the managed
  /// directory. No-ops on null, empty, non-managed, and
  /// already-missing paths (INV-5 — never errors on a missing
  /// file).
  Future<void> deleteIfManaged(String? path) async {
    if (path == null || path.isEmpty) return;
    if (!isManaged(path)) return;
    final file = File(path);
    if (!await file.exists()) return;
    await file.delete();
  }

  // ─── private helpers ──────────────────────────────────────────────────

  Future<void> _ensureManagedDir() async {
    final dir = Directory(_managedDir);
    if (await dir.exists()) return;
    await dir.create(recursive: true);
  }

  String _resolveExtension(XFile picked) {
    final fromName = p.extension(picked.name);
    if (fromName.isNotEmpty) return fromName;
    final fromPath = p.extension(picked.path);
    if (fromPath.isNotEmpty) return fromPath;
    return _defaultExtension;
  }
}
