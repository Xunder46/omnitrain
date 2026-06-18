// filepath: test/image_persistence_round_trip_test.dart
//
// State-level integration tests for the image-persistence feature.
//
// This file exercises the wired-up [ImageStorageService] +
// [ProfileState] / [FoodLibraryState] combination. Each scenario
// maps to an S-id in
// `.github/agents/plans/image-persistence-fix-plan.md`:
//
//   S-1  avatar persists across state rebuild
//   S-2  food photo persists across state rebuild
//   S-3  replacing avatar deletes the old managed file
//   S-4  replacing food photo deletes the old managed file
//   S-5  stale record self-heals to null on load
//   S-6  Remove Photo on avatar deletes the managed file
//   S-7  clearing imagePath on a food deletes the managed file
//
// S-8 (web behavior unchanged) and S-9 (copy-failure surfaces
// snackbar) are covered at the screen / service level — S-9 is
// already covered by `test/image_storage_service_test.dart`; S-8
// is a conditional-import / kIsWeb branch in the screens that is
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

import 'helpers/test_image_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── S-1: avatar persists across state rebuild ─────────────────────────

  group('S-1: avatar persists across state rebuild', () {
    test(
      'picked file is reachable by a fresh state with the same repo',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        // Source file outside the managed dir.
        final sourceBytes = [1, 2, 3, 4, 5, 6, 7, 8];
        final sourcePath = '${imageStorage.tempDir.path}/picker_source.jpg';
        File(sourcePath).writeAsBytesSync(sourceBytes);
        final picked = XFile(sourcePath, name: 'picker_source.jpg');

        // First state: persist + save.
        final state1 = ProfileState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state1.loadProfile();
        final persistedPath = await imageStorage.service.persistPickedImage(
          picked,
        );
        await state1.updateAvatarPath(persistedPath);

        // "Restart": a fresh state instance against the same repo.
        final state2 = ProfileState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state2.loadProfile();

        expect(state2.profile?.avatarPath, persistedPath);
        expect(File(persistedPath).existsSync(), isTrue);
        expect(File(persistedPath).readAsBytesSync(), equals(sourceBytes));
      },
    );
  });

  // ─── S-2: food photo persists across state rebuild ──────────────────────

  group('S-2: food photo persists across state rebuild', () {
    test(
      'picked file is reachable by a fresh state with the same repo',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final sourceBytes = [9, 8, 7, 6, 5, 4, 3, 2, 1];
        final sourcePath = '${imageStorage.tempDir.path}/food_source.png';
        File(sourcePath).writeAsBytesSync(sourceBytes);
        final picked = XFile(sourcePath, name: 'food_source.png');

        // First state: persist + create food.
        final state1 = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state1.loadFoods();
        final persistedPath = await imageStorage.service.persistPickedImage(
          picked,
        );
        final id = await state1.createFood(
          _libraryFood(name: 'Test Chicken', imagePath: persistedPath),
        );

        // "Restart".
        final state2 = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );
        await state2.loadFoods();
        final reloaded = state2.foods.firstWhere((f) => f.id == id);

        expect(reloaded.imagePath, persistedPath);
        expect(File(persistedPath).existsSync(), isTrue);
        expect(File(persistedPath).readAsBytesSync(), equals(sourceBytes));
      },
    );
  });

  // ─── S-3: replacing avatar deletes the old managed file ─────────────────

  group('S-3: replacing avatar deletes the old managed file', () {
    test('old file is gone, new file persists, field holds the new path',
        () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      final firstPath = await _pickAndPersist(
        imageStorage.service,
        'first',
        [1, 1, 1],
      );
      final secondPath = await _pickAndPersist(
        imageStorage.service,
        'second',
        [2, 2, 2],
      );

      final state = ProfileState(repo, imageStorage: imageStorage.service);
      await state.loadProfile();
      await state.updateAvatarPath(firstPath);
      expect(File(firstPath).existsSync(), isTrue);

      await state.updateAvatarPath(secondPath);

      expect(File(firstPath).existsSync(), isFalse, reason: 'old file should be deleted by D-7');
      expect(File(secondPath).existsSync(), isTrue);
      expect(state.profile?.avatarPath, secondPath);
    });
  });

  // ─── S-4: replacing food photo deletes the old managed file ──────────────

  group('S-4: replacing food photo deletes the old managed file', () {
    test('old file is gone, new file persists, food holds the new path',
        () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      final firstPath = await _pickAndPersist(
        imageStorage.service,
        'food-first',
        [1],
      );
      final secondPath = await _pickAndPersist(
        imageStorage.service,
        'food-second',
        [2],
      );

      final state = FoodLibraryState(repo, imageStorage: imageStorage.service);
      await state.loadFoods();
      final id = await state.createFood(
        _libraryFood(name: 'Test', imagePath: firstPath),
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
        imagePath: secondPath,
      );

      expect(File(firstPath).existsSync(), isFalse);
      expect(File(secondPath).existsSync(), isTrue);
      expect(state.foods.firstWhere((f) => f.id == id).imagePath, secondPath);
    });
  });

  // ─── S-5: stale record self-heals to null on load ───────────────────────

  group('S-5: stale record self-heals to null on load', () {
    test('avatar: stale path is cleared, repo row updated, no crash',
        () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      // Seed: profile with a stale path that the OS has not seen
      // since the picker purge.
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

      // State reflects the healed value.
      expect(state.profile?.avatarPath, isNull);

      // Repo row was updated to null (so the next launch is a no-op).
      final reloaded = await repo.getProfile();
      expect(reloaded?.avatarPath, isNull);
    });

    test('food: stale path is cleared, repo row updated, no crash',
        () async {
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

        // One food with a valid managed file, one with a stale path.
        final validPath = await _pickAndPersist(
          imageStorage.service,
          'valid',
          [42],
        );
        await repo.createFood(
          _libraryFood(id: 'food-valid', name: 'Valid', imagePath: validPath),
        );
        await repo.createFood(
          _libraryFood(
            id: 'food-stale-2',
            name: 'Stale',
            imagePath: '/nonexistent/picker_temp.jpg',
          ),
        );

        final state = FoodLibraryState(repo, imageStorage: imageStorage.service);
        await state.loadFoods();

        // Valid file untouched.
        expect(
          state.foods.firstWhere((f) => f.id == 'food-valid').imagePath,
          validPath,
        );
        expect(File(validPath).existsSync(), isTrue);

        // Stale file cleared.
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

      final path = await _pickAndPersist(imageStorage.service, 'avatar', [7]);
      final state = ProfileState(repo, imageStorage: imageStorage.service);
      await state.loadProfile();
      await state.updateAvatarPath(path);
      expect(File(path).existsSync(), isTrue);

      // The "Remove Photo" path in profile_screen.dart calls
      // updateAvatarPath(null). The state is responsible for the
      // disk cleanup (D-7 + D-3).
      await state.updateAvatarPath(null);

      expect(File(path).existsSync(), isFalse, reason: 'managed file must be deleted');
      expect(state.profile?.avatarPath, isNull);

      final fromRepo = await repo.getProfile();
      expect(fromRepo?.avatarPath, isNull);
    });
  });

  // ─── S-7: clearing imagePath on a food deletes the managed file ─────────

  group('S-7: clearing imagePath on a food deletes the managed file', () {
    test('updateCustomFood(imagePath: null) deletes the previous managed file',
        () async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);
      final repo = MockWorkoutRepository();
      await repo.initialize();

      final path = await _pickAndPersist(imageStorage.service, 'food', [3]);
      final state = FoodLibraryState(repo, imageStorage: imageStorage.service);
      await state.loadFoods();
      final id = await state.createFood(
        _libraryFood(name: 'With photo', imagePath: path),
      );
      expect(File(path).existsSync(), isTrue);

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

      expect(File(path).existsSync(), isFalse);
      expect(state.foods.firstWhere((f) => f.id == id).imagePath, isNull);
    });

    test(
      'updateCatalogFood(imagePath: null) deletes the previous managed file',
      () async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();

        final path = await _pickAndPersist(imageStorage.service, 'cat', [4]);
        // Seed a catalog row.
        await repo.seedCatalogFood(
          _libraryFood(
            id: 'catalog-stale',
            name: 'Catalog',
            imagePath: path,
          ).copyWith(isCatalog: true),
        );

        final state = FoodLibraryState(repo, imageStorage: imageStorage.service);
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

        expect(File(path).existsSync(), isFalse);
        expect(
          state.catalogFoods.firstWhere((f) => f.id == 'catalog-stale').imagePath,
          isNull,
        );
      },
    );
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────

/// Persist a synthetic picked file into the managed dir. Returns
/// the new path. The source file is created in the test's temp
/// dir and removed with it during tearDown.
Future<String> _pickAndPersist(
  dynamic service,
  String tag,
  List<int> bytes,
) async {
  // Service is typed as `dynamic` so this file does not need to
  // import `image_storage_service_io.dart` (avoid coupling the
  // round-trip test to the IO variant — the conditional re-export
  // is the production contract).
  final tempDir = Directory.systemTemp.createTempSync('picker_src_');
  final sourcePath = '${tempDir.path}/$tag.jpg';
  File(sourcePath).writeAsBytesSync(bytes);
  final picked = XFile(sourcePath, name: '$tag.jpg');
  return await service.persistPickedImage(picked) as String;
}

/// Build a minimal library [Food] for the round-trip test. Defaults
/// match the standard `_libraryFood` helpers in the existing
/// food-library tests.
Food _libraryFood({
  String id = 'food-rt-1',
  String name = 'Test Food',
  int protein = 10,
  int carbs = 0,
  int? fiber = 0,
  int fat = 1,
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
