// filepath: test/image_storage_service_test.dart
//
// Service-level tests for [ImageStorageService] (IO variant).
//
// These tests cover the Phase 1 surface only — they verify the
// file-system contract in isolation. The end-to-end round-trip
// through `ProfileState` / `FoodLibraryState` is covered by
// `test/image_persistence_round_trip_test.dart` (Phase 2).
//
// Scenarios referenced here come from
// `docs/plans/image-persistence-relocation-fix-plan.md`:
//
//   * S-1 (service-level): persist produces a basename-shaped
//     reference whose bytes match the source.
//   * S-3 (service-level): deleting a managed file works; deleting
//     a non-managed file is a no-op (INV-3 + D-3).
//   * S-9 (service-level): a copy that throws leaves no partial
//     file at the destination (D-6).
//   * S-R1..S-R3 (service-level): resolveOrRelink finds a file at
//     the current managed dir (path 1), the literal reference
//     path (path 2 — re-link copy verified), or a configured
//     candidate dir (path 3 — re-link copy verified), and returns
//     null when no candidate has the file.
//
// Additional invariants verified:
//   * INV-5 — deleteIfManaged swallows "no such file".
//   * D-1   — persistPickedImage returns the basename, not the
//             absolute path; the file lives under the managed
//             directory.
//   * D-2   — extension preservation (basename keeps the picked
//             extension, falls back to path extension, then .jpg).
//   * D-3   — isManaged is the sole gate for absolute-path deletes.
//   * D-5   — re-link copies the file to the managed dir; the
//             copy is idempotent (no overwrite on a second call).
//
// The IO variant is imported directly (not via the conditional
// re-export in `image_storage_service.dart`) so the test always
// exercises the production code path, regardless of which
// platform the runner is on.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:omnitrain/core/services/image_storage_service_io.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageStorageService', () {
    late Directory tempDir;
    late ImageStorageService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('image_storage_test_');
      service = ImageStorageService.fromBaseDirectory(tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // ─── D-1: managed directory ────────────────────────────────────────────

    test('managedDirectoryPath is base + /omni_images', () {
      expect(service.managedDirectoryPath, p.join(tempDir.path, 'omni_images'));
    });

    test('candidateDirectories is empty by default (no create() factory)', () {
      expect(service.candidateDirectories, isEmpty);
    });

    // ─── D-1 (cont'd): persist returns the basename ────────────────────────

    test(
      'persistPickedImage returns the basename, NOT the absolute path',
      () async {
        final sourceBytes = List<int>.filled(1024, 0xAB);
        final sourcePath = p.join(tempDir.path, 'picker_source.jpg');
        File(sourcePath).writeAsBytesSync(sourceBytes);
        final picked = XFile(sourcePath, name: 'picker_source.jpg');

        final persisted = await service.persistPickedImage(picked);

        // D-1: the reference is a basename — no path separators.
        expect(
          p.dirname(persisted),
          '.',
          reason:
              'persisted reference must be a basename, not a path: '
              '$persisted',
        );
        expect(p.extension(persisted), '.jpg');

        // The basename shape is `<uuid-v4>.<ext>`.
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$',
          ).hasMatch(persisted),
          isTrue,
          reason: 'persisted basename must be <uuid>.jpg: $persisted',
        );

        // The file lives at managedDir + basename; bytes match.
        final managedPath = p.join(service.managedDirectoryPath, persisted);
        expect(File(managedPath).existsSync(), isTrue);
        expect(File(managedPath).readAsBytesSync(), equals(sourceBytes));
      },
    );

    // ─── D-2: extension preservation ────────────────────────────────────────

    test(
      'persistPickedImage preserves the picked filename extension',
      () async {
        final sourcePath = p.join(tempDir.path, 'picker_source.heic');
        File(sourcePath).writeAsBytesSync([0xDE, 0xAD, 0xBE, 0xEF]);
        final picked = XFile(sourcePath, name: 'IMG_0001.heic');

        final persisted = await service.persistPickedImage(picked);

        expect(p.extension(persisted), '.heic');
        expect(p.basename(persisted), endsWith('.heic'));
      },
    );

    test(
      'persistPickedImage falls back to path extension when name has none',
      () async {
        final sourcePath = p.join(tempDir.path, 'picker_source.png');
        File(sourcePath).writeAsBytesSync([1, 2, 3]);
        final picked = XFile(sourcePath);

        final persisted = await service.persistPickedImage(picked);

        expect(p.extension(persisted), '.png');
      },
    );

    test(
      'persistPickedImage uses default extension when name and path both lack one',
      () async {
        final sourcePath = p.join(tempDir.path, 'picker_source');
        File(sourcePath).writeAsBytesSync([1, 2, 3]);
        final picked = XFile(sourcePath);
        expect(p.extension(p.basename(picked.name)), isEmpty);

        final persisted = await service.persistPickedImage(picked);

        expect(p.extension(persisted), '.jpg');
      },
    );

    // ─── D-3: isManaged ─────────────────────────────────────────────────────

    test('isManaged returns true for paths inside the managed dir', () {
      final insidePath = p.join(service.managedDirectoryPath, 'uuid.jpg');
      expect(service.isManaged(insidePath), isTrue);
    });

    test('isManaged returns false for paths outside the managed dir', () {
      expect(service.isManaged('/some/other/dir/photo.jpg'), isFalse);
      expect(service.isManaged(p.join(tempDir.path, 'outside.jpg')), isFalse);
    });

    test('isManaged returns false for empty path', () {
      expect(service.isManaged(''), isFalse);
    });

    test('isManaged returns false for a bare basename (not under any dir)', () {
      // D-1 basenames are not "under" the managed dir; they ARE the
      // managed file. `isManaged` is only consulted for the legacy
      // absolute-path delete gate.
      expect(service.isManaged('uuid.jpg'), isFalse);
    });

    // ─── resolveOrRelink: path 1 (managed dir hit) ──────────────────────────

    test('resolveOrRelink returns the basename when the file exists in the '
        'current managed dir (path 1)', () async {
      final basename = await _writeAndGetBasename(service, 'm1', [1, 2, 3]);
      final resolved = await service.resolveOrRelink(basename);
      expect(resolved, basename);
    });

    test('resolveOrRelink normalizes a legacy absolute-path reference whose '
        'file now lives in the current managed dir (path 1)', () async {
      // Persist a file (basename now lives in the managed dir).
      final basename = await _writeAndGetBasename(service, 'm1b', [9]);
      // Construct a legacy absolute-path reference as if pre-fix.
      final legacyRef = p.join(service.managedDirectoryPath, basename);
      final resolved = await service.resolveOrRelink(legacyRef);
      expect(resolved, basename);
    });

    // ─── resolveOrRelink: path 2 (literal reference hit, re-link) ───────────

    test(
      'resolveOrRelink re-links a legacy absolute-path reference whose '
      'file still exists at the legacy path (path 2: copy into managed dir)',
      () async {
        // Simulate: a pre-fix record has an absolute path pointing
        // at a directory that is NOT the service's current managed
        // dir, and the file still exists at that legacy location.
        final legacyBase = Directory.systemTemp.createTempSync(
          'image_storage_legacy_',
        );
        addTearDown(() {
          if (legacyBase.existsSync()) legacyBase.deleteSync(recursive: true);
        });
        final legacyManagedDir = Directory(
          p.join(legacyBase.path, 'omni_images'),
        )..createSync(recursive: true);
        final legacyBytes = [42, 42, 42];
        const legacyBasename = 'legacy-uuid.jpg';
        final legacyPath = p.join(legacyManagedDir.path, legacyBasename);
        File(legacyPath).writeAsBytesSync(legacyBytes);

        // The current service's managed dir is empty.
        expect(
          File(
            p.join(service.managedDirectoryPath, legacyBasename),
          ).existsSync(),
          isFalse,
        );

        final resolved = await service.resolveOrRelink(legacyPath);
        expect(
          resolved,
          legacyBasename,
          reason: 'must normalize to basename, not the legacy absolute path',
        );

        // Re-link copy verified: the file is now under the current
        // managed dir with the original bytes.
        final relinked = File(
          p.join(service.managedDirectoryPath, legacyBasename),
        );
        expect(relinked.existsSync(), isTrue);
        expect(relinked.readAsBytesSync(), equals(legacyBytes));

        // The legacy file is left in place — the resolver copies, it
        // does not move. Subsequent loads resolve from the managed
        // dir (path 1) and never re-trigger the legacy search.
        expect(File(legacyPath).existsSync(), isTrue);
      },
    );

    // ─── resolveOrRelink: path 3 (candidate dir hit, re-link) ───────────────

    test('resolveOrRelink re-links from a configured candidate dir '
        '(path 3: copy into managed dir)', () async {
      // Simulate the picker temp / app support dir holding the file.
      final candidateBase = Directory.systemTemp.createTempSync(
        'image_storage_candidate_',
      );
      addTearDown(() {
        if (candidateBase.existsSync()) {
          candidateBase.deleteSync(recursive: true);
        }
      });
      final candidateBytes = [0xCD, 0xEF];
      const candidateBasename = 'picked-uuid.png';
      final candidatePath = p.join(candidateBase.path, candidateBasename);
      File(candidatePath).writeAsBytesSync(candidateBytes);

      // Re-construct the service with this dir as a candidate.
      final relocatedService = ImageStorageService.fromBaseDirectory(
        tempDir.path,
        extraCandidateDirs: [candidateBase.path],
      );

      final resolved = await relocatedService.resolveOrRelink(
        candidateBasename,
      );
      expect(resolved, candidateBasename);

      // Re-link copy verified.
      final relinked = File(
        p.join(relocatedService.managedDirectoryPath, candidateBasename),
      );
      expect(relinked.existsSync(), isTrue);
      expect(relinked.readAsBytesSync(), equals(candidateBytes));
    });

    test('resolveOrRelink re-link copy is idempotent (a second call does not '
        'overwrite an already-relinked file)', () async {
      final candidateBase = Directory.systemTemp.createTempSync(
        'image_storage_idem_',
      );
      addTearDown(() {
        if (candidateBase.existsSync()) {
          candidateBase.deleteSync(recursive: true);
        }
      });
      const originalBytes = [0x01, 0x02, 0x03];
      const modifiedBytes = [0xFF, 0xFF, 0xFF];
      const basename = 'idem-uuid.jpg';
      File(
        p.join(candidateBase.path, basename),
      ).writeAsBytesSync(originalBytes);

      final svc = ImageStorageService.fromBaseDirectory(
        tempDir.path,
        extraCandidateDirs: [candidateBase.path],
      );

      // First call: re-links the file into the managed dir.
      expect(await svc.resolveOrRelink(basename), basename);
      final managedPath = p.join(svc.managedDirectoryPath, basename);
      expect(File(managedPath).readAsBytesSync(), equals(originalBytes));

      // Mutate the candidate file to a different value.
      File(
        p.join(candidateBase.path, basename),
      ).writeAsBytesSync(modifiedBytes);

      // Second call: must NOT clobber the already-relinked file.
      expect(await svc.resolveOrRelink(basename), basename);
      expect(File(managedPath).readAsBytesSync(), equals(originalBytes));
    });

    // ─── resolveOrRelink: miss / null inputs ────────────────────────────────

    test(
      'resolveOrRelink returns null when no candidate has the file',
      () async {
        final resolved = await service.resolveOrRelink('does-not-exist.jpg');
        expect(resolved, isNull);
      },
    );

    test('resolveOrRelink returns null for null or empty input', () async {
      expect(await service.resolveOrRelink(null), isNull);
      expect(await service.resolveOrRelink(''), isNull);
    });

    test(
      'resolveOrRelink returns null for a literal "." or ".." reference',
      () async {
        // Defensive: a basename of '.' or '..' would join the
        // managed dir back to itself. The resolver must reject.
        expect(await service.resolveOrRelink('.'), isNull);
        expect(await service.resolveOrRelink('..'), isNull);
      },
    );

    // ─── S-3 (service-level): deleteIfManaged ───────────────────────────────

    test('deleteIfManaged removes a managed file (absolute path)', () async {
      final firstPath = await _writePickedFile(service, 'first.jpg', [1]);
      final secondPath = await _writePickedFile(service, 'second.jpg', [2]);

      await service.deleteIfManaged(firstPath);

      expect(File(firstPath).existsSync(), isFalse);
      expect(File(secondPath).existsSync(), isTrue);
    });

    test('deleteIfManaged removes a basename reference by deleting '
        '<managedDir>/<basename>', () async {
      final basename = await _writeAndGetBasename(service, 'b1', [7]);
      final managedPath = p.join(service.managedDirectoryPath, basename);
      expect(File(managedPath).existsSync(), isTrue);

      await service.deleteIfManaged(basename);

      expect(File(managedPath).existsSync(), isFalse);
    });

    test('deleteIfManaged does NOT delete a non-managed absolute path '
        '(D-3 / INV-3)', () async {
      final externalPath = p.join(tempDir.path, 'outside.jpg');
      File(externalPath).writeAsBytesSync([0xCA, 0xFE]);

      await service.deleteIfManaged(externalPath);

      expect(File(externalPath).existsSync(), isTrue);
      expect(File(externalPath).readAsBytesSync(), [0xCA, 0xFE]);
    });

    // ─── INV-5: deleteIfManaged swallows "no such file" ─────────────────────

    test('deleteIfManaged is a no-op on null, empty, missing', () async {
      // null
      await service.deleteIfManaged(null);
      // empty
      await service.deleteIfManaged('');
      // missing managed file (basename form)
      await service.deleteIfManaged('never-existed.jpg');
      // missing managed file (absolute path form)
      await service.deleteIfManaged(
        p.join(service.managedDirectoryPath, 'never-existed.jpg'),
      );
      // never throws
    });

    // ─── exists ────────────────────────────────────────────────────────────

    test('exists returns true for an existing file, false otherwise', () {
      final realPath = p.join(service.managedDirectoryPath, 'real.jpg');
      File(realPath).createSync(recursive: true);

      expect(service.exists(realPath), isTrue);
      expect(service.exists(p.join(tempDir.path, 'nope.jpg')), isFalse);
      expect(service.exists(''), isFalse);
    });

    // ─── resolvePathSync: used by rendering widgets ────────────────────────

    group('resolvePathSync (rendering widget fast path)', () {
      test('returns <managedDir>/<basename> for a basename input', () {
        const basename = 'uuid-1234.jpg';
        final resolved = service.resolvePathSync(basename);
        expect(resolved, p.join(service.managedDirectoryPath, basename));
      });

      test('returns the literal absolute path for an absolute-path input '
          '(legacy migration window)', () {
        const legacyPath = '/old/base/omni_images/legacy.jpg';
        final resolved = service.resolvePathSync(legacyPath);
        expect(resolved, legacyPath);
      });

      test('returns null for null or empty input', () {
        expect(service.resolvePathSync(null), isNull);
        expect(service.resolvePathSync(''), isNull);
      });

      test('returned basename resolves to a real file on disk', () async {
        final basename = await _writeAndGetBasename(service, 'rps', [42]);
        final resolved = service.resolvePathSync(basename);
        expect(resolved, isNotNull);
        expect(
          File(resolved!).existsSync(),
          isTrue,
          reason:
              'resolvePathSync output must point at the on-disk file '
              'so Image.file can open it',
        );
        expect(File(resolved).readAsBytesSync(), [42]);
      });
    });

    // ─── S-9 (service-level): failed copy leaves no partial file ────────────

    test(
      'persistPickedImage throws on copy failure and leaves no partial file',
      () async {
        if (!Platform.isMacOS && !Platform.isLinux) {
          return; // skip on Windows
        }

        final managedDir = Directory(service.managedDirectoryPath);
        managedDir.createSync(recursive: true);
        Process.runSync('chmod', ['0500', managedDir.path]);
        addTearDown(() {
          try {
            Process.runSync('chmod', ['0700', managedDir.path]);
          } catch (_) {
            // best-effort restore
          }
        });

        final sourcePath = p.join(tempDir.path, 'unwritable_source.jpg');
        File(sourcePath).writeAsBytesSync([1, 2, 3, 4]);
        final picked = XFile(sourcePath, name: 'unwritable_source.jpg');

        await expectLater(
          () => service.persistPickedImage(picked),
          throwsA(isA<FileSystemException>()),
        );

        final entries = managedDir.listSync();
        expect(
          entries,
          isEmpty,
          reason: 'no partial file should remain in the managed dir',
        );
      },
    );

    // ─── persistImageBytes: bytes-shaped input for the avatar crop step ─────

    group('persistImageBytes (avatar crop step)', () {
      test('writes the bytes under the managed dir and returns a UUID-v4 '
          'basename with the given extension', () async {
        final bytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x42]);
        final basename = await service.persistImageBytes(bytes);

        // D-1: the reference is a basename — no path separators.
        expect(p.dirname(basename), '.');
        expect(
          p.extension(basename),
          '.png',
          reason: 'default extension must be .png',
        );
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.png$',
          ).hasMatch(basename),
          isTrue,
          reason: 'basename must be <uuid-v4>.png',
        );

        // The file lives at managedDir + basename; bytes match.
        final managedPath = p.join(service.managedDirectoryPath, basename);
        expect(File(managedPath).existsSync(), isTrue);
        expect(File(managedPath).readAsBytesSync(), equals(bytes));
      });

      test('respects a custom extension argument', () async {
        final basename = await service.persistImageBytes(
          Uint8List.fromList([1, 2, 3]),
          extension: '.jpg',
        );
        expect(p.extension(basename), '.jpg');
        expect(
          File(p.join(service.managedDirectoryPath, basename)).existsSync(),
          isTrue,
        );
      });

      test('throws and leaves no partial file when the managed dir is '
          'unwritable (D-6 contract)', () async {
        if (!Platform.isMacOS && !Platform.isLinux) {
          return; // skip on Windows
        }
        final managedDir = Directory(service.managedDirectoryPath);
        managedDir.createSync(recursive: true);
        Process.runSync('chmod', ['0500', managedDir.path]);
        addTearDown(() {
          try {
            Process.runSync('chmod', ['0700', managedDir.path]);
          } catch (_) {
            // best-effort restore
          }
        });

        await expectLater(
          () => service.persistImageBytes(Uint8List.fromList([1, 2, 3])),
          throwsA(anything),
        );

        final entries = managedDir.listSync();
        expect(
          entries,
          isEmpty,
          reason: 'no partial file should remain after a failed write',
        );
      });

      test('two consecutive writes produce distinct basenames '
          '(UUID-v4 uniqueness)', () async {
        final a = await service.persistImageBytes(Uint8List.fromList([1]));
        final b = await service.persistImageBytes(Uint8List.fromList([1]));
        expect(a, isNot(equals(b)));
      });

      test('extension must start with a dot (asserted contract)', () async {
        // The assert fires inside the service — surfaced as an
        // AssertionError. The test documents the contract; the
        // contract is also asserted at the call site (the avatar
        // crop step always passes a leading-dot extension).
        await expectLater(
          () => service.persistImageBytes(
            Uint8List.fromList([1]),
            extension: 'png',
          ),
          throwsA(isA<AssertionError>()),
        );
      });
    });
  });
}

/// Helper: write a synthetic picked file outside the managed dir,
/// ask the service to persist it, and return the **basename** the
/// service returned (the new contract — D-1).
Future<String> _writeAndGetBasename(
  ImageStorageService service,
  String tag,
  List<int> bytes,
) async {
  final baseDir = p.dirname(service.managedDirectoryPath);
  final sourcePath = p.join(baseDir, '$tag.jpg');
  File(sourcePath).writeAsBytesSync(bytes);
  return service.persistPickedImage(XFile(sourcePath, name: '$tag.jpg'));
}

/// Helper: write a synthetic picked file and return the **absolute
/// path** the file ended up at under the managed dir. Used by the
/// delete tests that need an absolute-path input to
/// `deleteIfManaged`.
Future<String> _writePickedFile(
  ImageStorageService service,
  String filename,
  List<int> bytes,
) async {
  final baseDir = p.dirname(service.managedDirectoryPath);
  final sourcePath = p.join(baseDir, filename);
  File(sourcePath).writeAsBytesSync(bytes);
  final basename = await service.persistPickedImage(
    XFile(sourcePath, name: filename),
  );
  return p.join(service.managedDirectoryPath, basename);
}
