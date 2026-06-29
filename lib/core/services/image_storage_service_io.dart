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
// **Reference format.** `persistPickedImage` returns the **basename**
// (e.g. `e8b3…0123.jpg`), NOT the absolute path. The state classes
// (`UserProfile.avatarPath`, `Food.imagePath`) store this basename.
// Resolving a stored reference back to a reachable file is the
// service's job — see [resolveOrRelink] below. This makes the
// reference **location-independent**: it survives the OS relocating
// the app's documents directory during an update or a reinstall,
// because the basename is a portable identifier under the managed
// directory, not a path that hard-codes the directory's current
// location.
//
// The service is a stateless file-system helper. It is constructed
// either with an explicit base directory (tests) or via the async
// `ImageStorageService.create()` factory which resolves
// `getApplicationDocumentsDirectory()` once at app start.
//
// See D-1..D-10 in
// `.github/agents/plans/image-persistence-relocation-fix-plan.md`.

import 'dart:io';
import 'dart:typed_data';

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

  /// Additional candidate directories searched by [resolveOrRelink]
  /// when a stored reference cannot be found under the managed
  /// directory. In production these are the picker's temp cache
  /// and the application support directory (set by [create]); in
  /// tests the constructor accepts a per-test injection. Search
  /// order is fixed: managed dir → literal reference → candidates
  /// in list order. See D-3 in the plan.
  final List<String> _candidateDirs;

  /// Construct from an explicit base directory. Synchronous so
  /// tests can inject a temp directory without dealing with
  /// `path_provider` mocks.
  ///
  /// [baseDirectory] is the value returned by
  /// `getApplicationDocumentsDirectory()` (or a test temp dir).
  /// The managed directory is `<baseDirectory>/omni_images/`.
  ///
  /// [extraCandidateDirs] is an optional list of additional
  /// search roots used by [resolveOrRelink]. Production callers
  /// should use [create]; tests pass per-test temp dirs to
  /// simulate relocations.
  ImageStorageService.fromBaseDirectory(
    String baseDirectory, {
    List<String>? extraCandidateDirs,
  })  : _managedDir = p.normalize(p.join(baseDirectory, _managedSubdir)),
        _candidateDirs = List.unmodifiable(extraCandidateDirs ?? const []);

  /// Async factory that resolves the app documents directory via
  /// `path_provider`. Use from `main.dart` at app start.
  ///
  /// The factory also resolves the picker's temp directory and the
  /// application support directory and seeds [extraCandidateDirs]
  /// so [resolveOrRelink] can find photos the OS relocated to one
  /// of those known locations.
  static Future<ImageStorageService> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final temp = await getTemporaryDirectory();
    final support = await getApplicationSupportDirectory();
    return ImageStorageService.fromBaseDirectory(
      docs.path,
      extraCandidateDirs: [temp.path, support.path],
    );
  }

  /// The absolute path of the managed directory. Exposed for tests
  /// and for the read-side helpers in the state classes (see
  /// INV-3 — state classes use the read-side helpers only, never
  /// mutate files themselves).
  String get managedDirectoryPath => _managedDir;

  /// Read-only view of the search candidate directories used by
  /// [resolveOrRelink]. Exposed for tests.
  List<String> get candidateDirectories => _candidateDirs;

  /// Returns `true` iff [path] resolves to a file under the
  /// managed directory. This is the sole gate for legacy
  /// "delete on replace/remove" calls that pass an absolute path
  /// (the migration path); modern basenames are by convention
  /// managed and are deleted directly via [deleteIfManaged].
  bool isManaged(String path) {
    if (path.isEmpty) return false;
    return p.isWithin(_managedDir, p.normalize(path));
  }

  /// Synchronous existence check for the file at [path]. Used by
  /// the load-time resolve in the state classes.
  bool exists(String path) {
    if (path.isEmpty) return false;
    return File(path).existsSync();
  }

  /// Synchronously resolves a stored reference to the absolute
  /// path the rendering widgets should pass to `Image.file`. Used
  /// by the UI layer (`ProfileAvatarImage`, `FoodThumbnailImage`,
  /// etc.) which cannot await `resolveOrRelink` from `build`.
  ///
  /// **Returns** the absolute path:
  ///   * `null` when [reference] is null/empty (no image).
  ///   * `<managedDir>/<reference>` when [reference] is a basename
  ///     (no path separators) — the new contract from D-1.
  ///   * [reference] itself when [reference] is an absolute path
  ///     — the legacy migration window. The widget's
  ///     `errorBuilder` will catch the case where the file has
  ///     since moved; the state's load-time `resolveOrRelink`
  ///     converges the stored reference to a basename on the
  ///     next launch.
  ///
  /// This is best-effort and **synchronous**: it does NOT do the
  /// bounded fallback search that [resolveOrRelink] does. The
  /// common case (basename under the current managed dir, or a
  /// still-valid legacy absolute path) is covered; the bounded
  /// fallback path is covered by the state classes at load time.
  String? resolvePathSync(String? reference) {
    if (reference == null || reference.isEmpty) return null;
    if (_isBasename(reference)) return p.join(_managedDir, reference);
    return reference;
  }

  /// Copies the bytes of [picked] into the managed directory and
  /// returns the **basename** `<uuid-v4>.<ext>` (NOT an absolute
  /// path — see D-1).
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
      return filename;
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

  /// Writes [bytes] to the managed directory and returns the
  /// **basename** `<uuid-v4><extension>` (NOT an absolute path —
  /// see D-1).
  ///
  /// Mirrors the persistence contract of [persistPickedImage] but
  /// accepts already-decoded bytes rather than an [XFile] — used
  /// by the avatar crop step, which captures the framed region
  /// via `RepaintBoundary.toImage` and ends up with a
  /// `Uint8List` (typically re-encoded PNG via
  /// `ImageByteFormat.png`) rather than a path on disk.
  ///
  /// [extension] is the file extension appended to the UUID-v4
  /// basename — typically `.png` for a `RepaintBoundary.toImage`
  /// capture, but callers may pass `.jpg` if they have already
  /// re-encoded to JPEG. The extension must start with a `.`;
  /// defaults to `.png`.
  ///
  /// If the write throws (disk full, permission denied) the
  /// partially-written destination is removed before the
  /// exception is rethrown (D-6 — no partial files left behind
  /// on disk). The [bytes] buffer is not mutated by this
  /// method.
  Future<String> persistImageBytes(
    Uint8List bytes, {
    String extension = '.png',
  }) async {
    assert(
      extension.startsWith('.'),
      'extension must start with "." — got "$extension"',
    );
    await _ensureManagedDir();

    final filename = '${_uuid.v4()}$extension';
    final destination = p.join(_managedDir, filename);
    final dest = File(destination);

    try {
      await dest.writeAsBytes(bytes, flush: true);
      return filename;
    } catch (e) {
      // Best-effort cleanup of a partial destination so we never
      // leave 0-byte orphans. Mirrors [persistPickedImage]'s
      // D-6 contract.
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

  /// Resolves a stored reference back to a reachable file,
  /// re-linking by copy if the file is at a fallback location.
  ///
  /// **Returns** the canonical basename `<uuid>.<ext>` if a file
  /// matching [reference] is reachable from any candidate
  /// location, else `null`. Callers (the state classes) persist
  /// the returned basename back to the record so subsequent
  /// loads hit the fast path (managed dir).
  ///
  /// **Search order** (D-3):
  ///   1. `<managedDir>/<basename>` — fast path. The common case
  ///      after an OS-driven relocation is that the data moved
  ///      along with the documents directory; the new managed
  ///      dir holds the file under the same basename.
  ///   2. The literal [reference] itself (an absolute path from a
  ///      pre-fix record, if it still exists on disk) — handles
  ///      installs where the documents directory did NOT move.
  ///   3. Each directory in [candidateDirectories] (production:
  ///      picker's temp cache and application support dir; tests
  ///      inject per-test temp dirs).
  ///
  /// **Re-link copy.** When the file is found at a non-managed
  /// location (path 2 or path 3), it is copied to
  /// `<managedDir>/<basename>` before the method returns. This
  /// makes the file a managed file under the current location,
  /// so subsequent loads / replaces / removes work the standard
  /// way (D-5). Copy failures are swallowed: the method still
  /// returns the basename so the user can see the photo at its
  /// current location for one more launch while the OS finishes
  /// its housekeeping.
  ///
  /// **Self-heal.** The method returns `null` only when no
  /// candidate location has the file. Callers clear the stored
  /// reference to `null` in that case (D-6).
  Future<String?> resolveOrRelink(String? reference) async {
    if (reference == null || reference.isEmpty) return null;
    final basename = p.basename(reference);
    if (basename.isEmpty || basename == '.' || basename == '..') return null;

    final managedCandidate = File(p.join(_managedDir, basename));
    if (managedCandidate.existsSync()) {
      return basename;
    }

    // Path 2: the literal reference (a legacy absolute path that
    // still exists on disk, e.g. a record created before the fix
    // whose documents directory did not relocate).
    if (p.isAbsolute(reference)) {
      final literalFile = File(reference);
      if (literalFile.existsSync()) {
        await _copyIntoManaged(literalFile, managedCandidate);
        return basename;
      }
    }

    // Path 3: each configured candidate dir.
    for (final dir in _candidateDirs) {
      final candidate = File(p.join(dir, basename));
      if (candidate.existsSync()) {
        await _copyIntoManaged(candidate, managedCandidate);
        return basename;
      }
    }

    return null;
  }

  /// Deletes the file at [path] iff it is a managed file.
  ///
  /// For a basename input (no path separator, the new normal
  /// after D-1) the file at `<managedDir>/<basename>` is deleted
  /// unconditionally — basenames are by convention managed
  /// (they can only have been produced by [persistPickedImage]).
  ///
  /// For an absolute-path input (legacy migration only) the
  /// delete is gated by [isManaged] so a non-managed path is
  /// never deleted.
  ///
  /// No-ops on null, empty, and already-missing files (INV-5).
  Future<void> deleteIfManaged(String? path) async {
    if (path == null || path.isEmpty) return;
    final resolved = _isBasename(path) ? p.join(_managedDir, path) : path;
    if (!_isBasename(path) && !isManaged(resolved)) return;
    final file = File(resolved);
    if (!await file.exists()) return;
    await file.delete();
  }

  // ─── private helpers ──────────────────────────────────────────────────

  Future<void> _ensureManagedDir() async {
    final dir = Directory(_managedDir);
    if (await dir.exists()) return;
    await dir.create(recursive: true);
  }

  Future<void> _copyIntoManaged(File source, File destination) async {
    if (await destination.exists()) {
      // Idempotent: if a previous migration already copied this
      // file, the destination is good and we are done. This also
      // covers the edge case where the literal-reference path
      // equals the managed path (no-op migration).
      return;
    }
    try {
      await _ensureManagedDir();
      await source.copy(destination.path);
    } catch (_) {
      // Re-link copy failures are non-fatal (D-5). The caller
      // still gets the basename; the file remains reachable at
      // its current location for one more launch. A subsequent
      // launch will try again.
    }
  }

  /// True iff [path] contains no directory separator — i.e. it is
  /// a basename under the managed directory by convention. Used
  /// to distinguish the modern reference format (basename) from
  /// the legacy absolute-path format during the migration window.
  static bool _isBasename(String path) => p.basename(path) == path;

  String _resolveExtension(XFile picked) {
    final fromName = p.extension(picked.name);
    if (fromName.isNotEmpty) return fromName;
    final fromPath = p.extension(picked.path);
    if (fromPath.isNotEmpty) return fromPath;
    return _defaultExtension;
  }
}
