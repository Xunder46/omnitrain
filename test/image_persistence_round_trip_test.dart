// filepath: test/image_persistence_round_trip_test.dart
//
// State-level integration tests for the image-persistence feature.
//
// This file exercises the wired-up [ImageStorageService] +
// [ProfileState] / [FoodLibraryState] combination. Each scenario
// maps to an S-id in
// `docs/plans/image-persistence-relocation-fix-plan.md`:
//
//   S-1   (reworked) avatar resolves across a relocated managed dir
//   S-2   (reworked) food photo resolves across a relocated managed dir
//   S-3   replacing avatar deletes the old managed file (D-7)
//   S-4   replacing food photo deletes the old managed file (D-7)
//   S-R3  legacy absolute-path avatar record is re-linked, not nulled
//   S-R4  legacy absolute-path food record is re-linked, not nulled
//   S-R5a truly-absent avatar record self-heals to null on load
//   S-R5b truly-absent food record self-heals to null on load
//   S-6   Remove Photo on avatar deletes the managed file
//   S-7   clearing imagePath on a food deletes the managed file
//
// S-8 (web behavior unchanged) and S-9 (copy-failure surfaces
// snackbar) are covered at the screen / service level — S-9 is
// covered by `test/image_storage_service_test.dart`; S-8 is a
// conditional-import / kIsWeb branch in the screens that is
// exercised by the existing `profile_screen_test.dart` and
// `food_form.dart` unit tests (the screens preserve the existing
// snackbar text verbatim).
//
// All tests use [MockWorkoutRepository] (the web-safe repository
// implementation) per the developer workflow rule that tests
// must not import concrete storage classes. The Hive parity is
// covered by the existing
// `test/food_library_persistence_test.dart` regression suite.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:path/path.dart' as p;

import 'helpers/test_image_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── S-1 (reworked): avatar resolves across a relocated managed dir ─────

  group('S-1 (reworked): avatar resolves across a relocated managed dir', () {
    test('picked file at the new managed dir is reachable by a fresh state '
        'after the base location changes', () async {
      // Pre-fix storage: avatar was persisted under baseA.
      final imageStorageA = TestImageStorage.create();
      addTearDown(imageStorageA.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      final sourceBytes = [1, 2, 3, 4, 5, 6, 7, 8];
      final sourcePath = '${imageStorageA.tempDir.path}/picker_source.jpg';
      File(sourcePath).writeAsBytesSync(sourceBytes);
      final picked = XFile(sourcePath, name: 'picker_source.jpg');

      // Persist under baseA and capture the basename.
      final state1 = ProfileState(repo, imageStorage: imageStorageA.service);
      await state1.loadProfile();
      final basename = await imageStorageA.service.persistPickedImage(picked);
      await state1.updateAvatarPath(basename);

      // Relocation: OS moved the data into a new managed dir
      // (baseB). We simulate by copying the file under baseA's
      // managed dir to baseB's managed dir, then disposing baseA.
      final imageStorageB = TestImageStorage.create();
      addTearDown(imageStorageB.dispose);
      final oldManagedFile = File(
        p.join(imageStorageA.service.managedDirectoryPath, basename),
      );
      final newManagedDir = Directory(
        imageStorageB.service.managedDirectoryPath,
      )..createSync(recursive: true);
      final newManagedFile = File(p.join(newManagedDir.path, basename));
      newManagedFile.writeAsBytesSync(oldManagedFile.readAsBytesSync());

      // "Restart" on baseB with the same repo.
      final state2 = ProfileState(repo, imageStorage: imageStorageB.service);
      await state2.loadProfile();

      // Reference was a basename (D-1); the new managed dir has
      // the file (S-R1 path 1). No normalize write needed because
      // the stored basename already matches.
      expect(
        state2.profile?.avatarPath,
        basename,
        reason: 'stored reference should remain a basename',
      );
      expect(newManagedFile.existsSync(), isTrue);
      expect(newManagedFile.readAsBytesSync(), equals(sourceBytes));

      // No stale write to the repo (the resolver returned the
      // same basename).
      final fromRepo = await repo.getProfile();
      expect(fromRepo?.avatarPath, basename);
    });
  });

  // ─── S-2 (reworked): food photo resolves across a relocated managed dir ─

  group(
    'S-2 (reworked): food photo resolves across a relocated managed dir',
    () {
      test('picked file at the new managed dir is reachable by a fresh state '
          'after the base location changes', () async {
        final imageStorageA = TestImageStorage.create();
        addTearDown(imageStorageA.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final sourceBytes = [9, 8, 7, 6, 5, 4, 3, 2, 1];
        final sourcePath = '${imageStorageA.tempDir.path}/food_source.png';
        File(sourcePath).writeAsBytesSync(sourceBytes);
        final picked = XFile(sourcePath, name: 'food_source.png');

        final state1 = FoodLibraryState(
          repo,
          imageStorage: imageStorageA.service,
        );
        await state1.loadFoods();
        final basename = await imageStorageA.service.persistPickedImage(picked);
        final id = await state1.createFood(
          _libraryFood(name: 'Test Chicken', imagePath: basename),
        );

        // Relocation: copy the file under baseB's managed dir.
        final imageStorageB = TestImageStorage.create();
        addTearDown(imageStorageB.dispose);
        final oldManagedFile = File(
          p.join(imageStorageA.service.managedDirectoryPath, basename),
        );
        final newManagedDir = Directory(
          imageStorageB.service.managedDirectoryPath,
        )..createSync(recursive: true);
        final newManagedFile = File(p.join(newManagedDir.path, basename));
        newManagedFile.writeAsBytesSync(oldManagedFile.readAsBytesSync());

        // "Restart" on baseB with the same repo.
        final state2 = FoodLibraryState(
          repo,
          imageStorage: imageStorageB.service,
        );
        await state2.loadFoods();
        final reloaded = state2.foods.firstWhere((f) => f.id == id);

        expect(reloaded.imagePath, basename);
        expect(newManagedFile.existsSync(), isTrue);
        expect(newManagedFile.readAsBytesSync(), equals(sourceBytes));
      });
    },
  );

  // ─── S-3: replacing avatar deletes the old managed file ─────────────────

  group('S-3: replacing avatar deletes the old managed file', () {
    test(
      'old file is gone, new file persists, field holds the new basename',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final firstBasename = await _pickAndPersist(
          imageStorage.service,
          'first',
          [1, 1, 1],
        );
        final secondBasename = await _pickAndPersist(
          imageStorage.service,
          'second',
          [2, 2, 2],
        );

        final firstPath = p.join(
          imageStorage.service.managedDirectoryPath,
          firstBasename,
        );
        final secondPath = p.join(
          imageStorage.service.managedDirectoryPath,
          secondBasename,
        );

        final state = ProfileState(repo, imageStorage: imageStorage.service);
        await state.loadProfile();
        await state.updateAvatarPath(firstBasename);
        expect(File(firstPath).existsSync(), isTrue);

        await state.updateAvatarPath(secondBasename);

        expect(
          File(firstPath).existsSync(),
          isFalse,
          reason: 'old managed file should be deleted by D-7',
        );
        expect(File(secondPath).existsSync(), isTrue);
        expect(state.profile?.avatarPath, secondBasename);
      },
    );
  });

  // ─── S-4: replacing food photo deletes the old managed file ──────────────

  group('S-4: replacing food photo deletes the old managed file', () {
    test(
      'old file is gone, new file persists, food holds the new basename',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final firstBasename = await _pickAndPersist(
          imageStorage.service,
          'food-first',
          [1],
        );
        final secondBasename = await _pickAndPersist(
          imageStorage.service,
          'food-second',
          [2],
        );

        final firstPath = p.join(
          imageStorage.service.managedDirectoryPath,
          firstBasename,
        );

        final state = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state.loadFoods();
        final id = await state.createFood(
          _libraryFood(name: 'Test', imagePath: firstBasename),
        );

        await state.updateCustomFood(
          id: id,
          name: 'Test',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 10,
          carbs: 0,
          fiber: 0,
          fat: 1,
          imagePath: secondBasename,
        );

        expect(File(firstPath).existsSync(), isFalse);
        final reloaded = state.foods.firstWhere((f) => f.id == id);
        expect(reloaded.imagePath, secondBasename);
        expect(
          File(
            p.join(imageStorage.service.managedDirectoryPath, secondBasename),
          ).existsSync(),
          isTrue,
        );
      },
    );
  });

  // ─── S-R3: legacy absolute-path avatar record is re-linked ──────────────

  group('S-R3: legacy absolute-path avatar record is re-linked, NOT nulled '
      '(the launch-blocker fix)', () {
    test('a record whose stored reference is an old absolute path but whose '
        'file is still present is normalized to the basename and the photo '
        'displays — the reference is NOT cleared', () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      // Simulate a pre-fix record: the avatar path is an absolute
      // path from a different documents directory, and the file
      // still exists at that legacy location (the data has not
      // been moved).
      final legacyBase = Directory.systemTemp.createTempSync('legacy_base_');
      addTearDown(() {
        if (legacyBase.existsSync()) legacyBase.deleteSync(recursive: true);
      });
      final legacyManagedDir = Directory(p.join(legacyBase.path, 'omni_images'))
        ..createSync(recursive: true);
      const basename = 'pre-fix-avatar.jpg';
      final legacyPath = p.join(legacyManagedDir.path, basename);
      File(legacyPath).writeAsBytesSync([1, 2, 3, 4]);

      await repo.saveProfile(
        UserProfile(
          id: 'local-user',
          displayName: 'Legacy',
          avatarPath: legacyPath,
          createdAtMs: 1000,
        ),
      );

      // Load: the resolver finds the file at the literal legacy
      // path (path 2), re-links it into the current managed dir,
      // and returns the basename. The state persists the
      // normalized basename.
      final state = ProfileState(repo, imageStorage: imageStorage.service);
      await state.loadProfile();

      // State exposes the normalized basename (D-4).
      expect(
        state.profile?.avatarPath,
        basename,
        reason: 'legacy absolute path must be normalized to the basename',
      );

      // Repo row was updated to the basename (one-time migration
      // write).
      final fromRepo = await repo.getProfile();
      expect(fromRepo?.avatarPath, basename);

      // The file is reachable from the current managed dir.
      final relinked = File(
        p.join(imageStorage.service.managedDirectoryPath, basename),
      );
      expect(
        relinked.existsSync(),
        isTrue,
        reason:
            're-link copy should land the file in the current '
            'managed dir',
      );
      expect(relinked.readAsBytesSync(), [1, 2, 3, 4]);

      // The legacy file is left in place (the resolver copies, it
      // does not move).
      expect(File(legacyPath).existsSync(), isTrue);

      // The reference is NOT nulled — the photo continues to
      // display. This is the regression the fix targets: a
      // reachable file's reference is never cleared.
    });
  });

  // ─── S-R4: legacy absolute-path food record is re-linked ────────────────

  group('S-R4: legacy absolute-path food record is re-linked, NOT nulled', () {
    test('a record whose stored reference is an old absolute path but whose '
        'file is still present is normalized to the basename and the photo '
        'displays', () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      final legacyBase = Directory.systemTemp.createTempSync('legacy_food_');
      addTearDown(() {
        if (legacyBase.existsSync()) legacyBase.deleteSync(recursive: true);
      });
      final legacyManagedDir = Directory(p.join(legacyBase.path, 'omni_images'))
        ..createSync(recursive: true);
      const basename = 'pre-fix-food.png';
      final legacyPath = p.join(legacyManagedDir.path, basename);
      File(legacyPath).writeAsBytesSync([0xAA, 0xBB]);

      await repo.createFood(
        _libraryFood(
          id: 'food-legacy',
          name: 'Legacy Food',
          imagePath: legacyPath,
        ),
      );

      final state = FoodLibraryState(repo, imageStorage: imageStorage.service);
      await state.loadFoods();

      final reloaded = state.foods.firstWhere((f) => f.id == 'food-legacy');
      expect(reloaded.imagePath, basename);

      final fromRepo = await repo.getFoodById('food-legacy');
      expect(fromRepo?.imagePath, basename);

      final relinked = File(
        p.join(imageStorage.service.managedDirectoryPath, basename),
      );
      expect(relinked.existsSync(), isTrue);
      expect(relinked.readAsBytesSync(), [0xAA, 0xBB]);
    });
  });

  // ─── S-R5a / S-R5b: split S-5: truly-absent files are cleared to null ────

  group('S-R5a: truly-absent avatar record self-heals to null on load '
      '(only when no candidate has the file)', () {
    test('avatar: stale path is cleared, repo row updated, no crash', () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      // A stale legacy path that does not exist on disk and whose
      // basename is not in any candidate location.
      const stalePath = '/var/folders/picker_tmp_xyz/temp.jpg';
      await repo.saveProfile(
        UserProfile(
          id: 'local-user',
          displayName: 'Stale',
          avatarPath: stalePath,
          createdAtMs: 1000,
        ),
      );

      final state = ProfileState(repo, imageStorage: imageStorage.service);
      await state.loadProfile();

      expect(state.profile?.avatarPath, isNull);

      final reloaded = await repo.getProfile();
      expect(reloaded?.avatarPath, isNull);
    });
  });

  group('S-R5b: truly-absent food record self-heals to null on load '
      '(only when no candidate has the file)', () {
    test('food: stale path is cleared, repo row updated, no crash', () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      const stalePath = '/var/folders/picker_tmp_abc/temp.jpg';
      await repo.createFood(
        _libraryFood(id: 'food-stale', name: 'Stale', imagePath: stalePath),
      );

      final state = FoodLibraryState(repo, imageStorage: imageStorage.service);
      await state.loadFoods();

      final reloaded = state.foods.firstWhere((f) => f.id == 'food-stale');
      expect(reloaded.imagePath, isNull);

      final fromRepo = await repo.getFoodById('food-stale');
      expect(fromRepo?.imagePath, isNull);
    });

    test(
      'load-time self-heal does not affect foods with valid managed paths',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final validBasename = await _pickAndPersist(
          imageStorage.service,
          'valid',
          [42],
        );
        await repo.createFood(
          _libraryFood(
            id: 'food-valid',
            name: 'Valid',
            imagePath: validBasename,
          ),
        );
        await repo.createFood(
          _libraryFood(
            id: 'food-stale-2',
            name: 'Stale',
            imagePath: '/nonexistent/picker_temp.jpg',
          ),
        );

        final state = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state.loadFoods();

        // Valid file untouched.
        expect(
          state.foods.firstWhere((f) => f.id == 'food-valid').imagePath,
          validBasename,
        );
        expect(
          File(
            p.join(imageStorage.service.managedDirectoryPath, validBasename),
          ).existsSync(),
          isTrue,
        );

        // Truly absent file cleared.
        expect(
          state.foods.firstWhere((f) => f.id == 'food-stale-2').imagePath,
          isNull,
        );
      },
    );
  });

  // ─── S-6: Remove Photo on avatar deletes the managed file ───────────────

  group('S-6: Remove Photo on avatar deletes the managed file', () {
    test('updateAvatarPath(null) deletes the previous managed file', () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      final basename = await _pickAndPersist(imageStorage.service, 'avatar', [
        7,
      ]);
      final managedPath = p.join(
        imageStorage.service.managedDirectoryPath,
        basename,
      );

      final state = ProfileState(repo, imageStorage: imageStorage.service);
      await state.loadProfile();
      await state.updateAvatarPath(basename);
      expect(File(managedPath).existsSync(), isTrue);

      // The "Remove Photo" path in profile_screen.dart calls
      // updateAvatarPath(null). The state is responsible for the
      // disk cleanup (D-7 + D-3).
      await state.updateAvatarPath(null);

      expect(
        File(managedPath).existsSync(),
        isFalse,
        reason: 'managed file must be deleted',
      );
      expect(state.profile?.avatarPath, isNull);

      final fromRepo = await repo.getProfile();
      expect(fromRepo?.avatarPath, isNull);
    });
  });

  // ─── S-7: clearing imagePath on a food deletes the managed file ─────────

  group('S-7: clearing imagePath on a food deletes the managed file', () {
    test(
      'updateCustomFood(imagePath: null) deletes the previous managed file',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final basename = await _pickAndPersist(imageStorage.service, 'food', [
          3,
        ]);
        final managedPath = p.join(
          imageStorage.service.managedDirectoryPath,
          basename,
        );

        final state = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state.loadFoods();
        final id = await state.createFood(
          _libraryFood(name: 'With photo', imagePath: basename),
        );
        expect(File(managedPath).existsSync(), isTrue);

        // The food form's "clear" affordance saves a draft with
        // imagePath: null. updateCustomFood is responsible for the
        // disk cleanup.
        await state.updateCustomFood(
          id: id,
          name: 'With photo',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 10,
          carbs: 0,
          fiber: 0,
          fat: 1,
          imagePath: null,
        );

        expect(File(managedPath).existsSync(), isFalse);
        expect(state.foods.firstWhere((f) => f.id == id).imagePath, isNull);
      },
    );

    test(
      'updateCatalogFood(imagePath: null) deletes the previous managed file',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final basename = await _pickAndPersist(imageStorage.service, 'cat', [
          4,
        ]);
        final managedPath = p.join(
          imageStorage.service.managedDirectoryPath,
          basename,
        );

        // Seed a catalog row.
        await repo.seedCatalogFood(
          _libraryFood(
            id: 'catalog-stale',
            name: 'Catalog',
            imagePath: basename,
          ).copyWith(isCatalog: true),
        );

        final state = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state.loadCatalogFoods();
        final existing = state.catalogFoods.firstWhere(
          (f) => f.id == 'catalog-stale',
        );

        // Clear imagePath via a draft.
        final draft = FoodDraft(
          name: existing.name,
          groupId: existing.groupId,
          unitType: existing.unitType,
          referenceAmount: existing.referenceAmount,
          referenceLabel: existing.referenceLabel,
          protein: existing.protein,
          carbs: existing.carbs,
          fiber: existing.fiber,
          fat: existing.fat,
          sodium: existing.sodium,
          notes: existing.notes,
          imagePath: null,
        );
        await state.updateCatalogFood(existing, draft);

        expect(File(managedPath).existsSync(), isFalse);
        expect(
          state.catalogFoods
              .firstWhere((f) => f.id == 'catalog-stale')
              .imagePath,
          isNull,
        );
      },
    );
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────

/// Persist a synthetic picked file into the managed dir. Returns
/// the new basename (D-1 — the modern reference format).
Future<String> _pickAndPersist(
  dynamic service,
  String tag,
  List<int> bytes,
) async {
  final tempDir = Directory.systemTemp.createTempSync('picker_src_');
  final sourcePath = '${tempDir.path}/$tag.jpg';
  File(sourcePath).writeAsBytesSync(bytes);
  final picked = XFile(sourcePath, name: '$tag.jpg');
  return await service.persistPickedImage(picked) as String;
}

/// Build a minimal library [Food] for the round-trip test. Defaults
/// match the standard `_libraryFood` helpers in the existing
/// food-library tests. Macros are `double` to match the [Food]
/// model.
Food _libraryFood({
  String id = 'food-rt-1',
  String name = 'Test Food',
  double protein = 10,
  double carbs = 0,
  double? fiber = 0,
  double fat = 1,
  String? imagePath,
  FoodUnitType unitType = FoodUnitType.grams,
  double referenceAmount = 100,
  String referenceLabel = 'g',
}) {
  return Food(
    id: id,
    name: name,
    groupId: null,
    unitType: unitType,
    referenceAmount: referenceAmount,
    referenceLabel: referenceLabel,
    isCatalog: false,
    protein: protein,
    carbs: carbs,
    fiber: fiber,
    fat: fat,
    imagePath: imagePath,
    createdAtMs: 1700000000000,
    updatedAtMs: 1700000000000,
  );
}
