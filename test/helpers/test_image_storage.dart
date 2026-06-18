// filepath: test/helpers/test_image_storage.dart
//
// Lightweight test helper for [ImageStorageService]. Creates a
// fresh temp-dir-backed service per test and tracks the temp
// directory for teardown.
//
// Why a helper: Phase 2 of
// `.github/agents/plans/image-persistence-fix-plan.md` makes the
// `ImageStorageService` a required constructor argument on
// `ProfileState` and `FoodLibraryState`. ~100 test sites construct
// those states; the helper keeps the per-test setup to a single
// `final imageStorage = TestImageStorage.create();
// addTearDown(imageStorage.dispose);` pair.
//
// The helper is the test-side mirror of the `imageStorageService`
// singleton constructed in `lib/main.dart`. It does not mock —
// it uses the real IO implementation against a per-test temp
// directory. This keeps the round-trip tests honest: a file
// written by the service is a file on disk that survives a fresh
// state load.

import 'dart:io';

import 'package:omnitrain/core/services/image_storage_service_io.dart';

class TestImageStorage {
  /// The per-test temp directory the service operates in. The
  /// managed directory is `<tempDir>/omni_images/`. Tests that
  /// need to inspect raw files use this path.
  final Directory tempDir;

  /// The real [ImageStorageService] backed by [tempDir]. Pass to
  /// state constructors via `imageStorage:`.
  final ImageStorageService service;

  TestImageStorage._(this.tempDir, this.service);

  /// Build a fresh fixture. Sync because `createTempSync` is sync
  /// and the [ImageStorageService] constructor is sync (the async
  /// `create()` factory exists for production use, where
  /// `getApplicationDocumentsDirectory()` must be awaited).
  factory TestImageStorage.create() {
    final tempDir = Directory.systemTemp.createTempSync('image_storage_test_');
    final service = ImageStorageService.fromBaseDirectory(tempDir.path);
    return TestImageStorage._(tempDir, service);
  }

  /// Remove the temp directory. Safe to call when the dir has
  /// already been removed (no-op).
  void dispose() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
