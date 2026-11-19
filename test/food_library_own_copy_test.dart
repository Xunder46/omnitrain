// filepath: test/food_library_own_copy_test.dart
//
// Plan 133 b1 — state tests for `FoodLibraryState.createOwnCopyOfDefault`
// (scenarios S-13314 and S-13317) and the `isDefaultFood` reader (D-13310).
//
// Mock-first: a `Mock` group runs the copy flow on the in-memory
// repository; an `Hive` group runs the same three state tests against
// `HiveWorkoutRepository` with rows really stored. The photo tests are
// Mock-only and use `TestImageStorage` (real IO implementation against
// a per-test temp directory).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/core/services/image_storage_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'helpers/test_image_storage.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A draft with values unlike every default (plan 133 b1: a value a
/// hard-coded mutant cannot satisfy): protein 31.5, name `Zed 133 bird`.
FoodDraft _draft({String? imagePath}) {
  return FoodDraft(
    name: 'Zed 133 bird',
    groupId: null,
    unitType: FoodUnitType.count,
    referenceAmount: 1,
    referenceLabel: 'tbsp',
    protein: 31.5,
    carbs: 12,
    fiber: 2,
    fat: 13,
    sodium: 51,
    notes: 'Notes from own-copy run',
    imagePath: imagePath,
  );
}

/// Stand-in for the path_provider platform channel used during tests.
/// Copied from `test/food_library_copy_edit_test.dart` (plan 133 b1
/// brief): `HiveWorkoutRepository.initialize()` calls `Hive.initFlutter()`,
/// which delegates to `path_provider` — that channel has no implementation
/// under `flutter_test`, so we route it to a temp directory we control.
class _PathProviderChannel {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  static late Directory _root;

  static void install(Directory root) {
    _root = root;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
        return _root.path;
      case 'getApplicationSupportDirectory':
        return _root.path;
      case 'getTemporaryDirectory':
        return _root.path;
      default:
        return null;
    }
  }
}

String _managedFile(String managedDir, String basename) {
  return '$managedDir/$basename';
}

Future<(MockWorkoutRepository, FoodLibraryState)> _mockState() async {
  final repo = await _freshRepo();
  final state = FoodLibraryState(repo);
  await state.loadCatalogFoods();
  return (repo, state);
}

Future<void> _notInListAddsNothing(
  FoodLibraryState state,
  WorkoutRepository repo,
) async {
  final chicken = state.catalogFoods.firstWhere(
    (f) => f.id == 'chicken_breast',
  );
  expect(state.isDefaultFood(chicken), isTrue);

  final newId = await state.createOwnCopyOfDefault(
    chicken,
    _draft(),
    addToList: false,
  );

  // The returned id IS the new catalog id...
  final created = state.catalogFoods.firstWhere((f) => f.id == newId);
  expect(newId, isNot('chicken_breast'));
  expect(created.isCatalog, isTrue);
  expect(created.name, 'Zed 133 bird');
  expect(created.protein, 31.5);
  expect(created.carbs, 12);
  expect(created.fiber, 2);
  expect(created.fat, 13);
  expect(created.sodium, 51);
  expect(created.unitType, FoodUnitType.count);
  expect(created.referenceAmount, 1);
  expect(created.referenceLabel, 'tbsp');
  expect(created.notes, 'Notes from own-copy run');
  // ...a plain user-created row (never matched as the default's copy).
  expect(state.isBundledCatalogFood(newId), isFalse);
  expect(newId.contains('chicken_breast'), isFalse);
  // ...no library row.
  expect(state.libraryIdFor(newId), isNull);
  // ...and the default's seed marker is untouched.
  expect(
    await repo.isSeedEntryTouched(SeedEntryType.foodCatalog, 'chicken_breast'),
    isFalse,
  );
}

Future<void> _inListSwapsTheRow(
  FoodLibraryState state,
  WorkoutRepository repo,
) async {
  final libId = await state.addCatalogFoodToLibrary('chicken_breast');

  // Edit the copy so the replaced row is visibly user-owned.
  final copy = state.foods.firstWhere((f) => f.id == libId);
  await state.updateFood(copy.copyWith(name: 'First edit 133'));

  final returnedId = await state.createOwnCopyOfDefault(
    copy,
    _draft(),
    addToList: true,
  );

  // The returned id is the NEW library row id (D-13318).
  expect(returnedId, isNot(libId));
  expect(state.foods.any((f) => f.id == returnedId), isTrue);

  // The old row id is gone.
  expect(state.foods.any((f) => f.id == libId), isFalse);

  // The new library row's catalogId names the NEW catalog row, a plain
  // user-created one.
  final newLibraryRow = state.foods.firstWhere((f) => f.id == returnedId);
  final newCatalogId = newLibraryRow.catalogId!;
  expect(newCatalogId, isNot('chicken_breast'));
  expect(newLibraryRow.name, 'Zed 133 bird');
  expect(newLibraryRow.protein, 31.5);
  final newCatalogRow = state.catalogFoods.firstWhere(
    (f) => f.id == newCatalogId,
  );
  expect(newCatalogRow.isCatalog, isTrue);
  expect(state.isBundledCatalogFood(newCatalogId), isFalse);

  // The bundled catalog row is unchanged byte-equal.
  final catalog = state.catalogFoods.firstWhere(
    (f) => f.id == 'chicken_breast',
  );
  expect(catalog.name, 'Chicken breast, skinless');
  expect(catalog.protein, 31);
  expect(catalog.carbs, 0);
  expect(catalog.fat, 3.6);
  expect(catalog.sodium, 74);
  expect(catalog.groupId, 'food-group-proteins');
  expect(
    await repo.isSeedEntryTouched(SeedEntryType.foodCatalog, 'chicken_breast'),
    isFalse,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FoodLibraryState create own copy (Mock)', () {
    test('createOwnCopyOfDefault not in list adds nothing (S-13317)', () async {
      final (repo, state) = await _mockState();
      await _notInListAddsNothing(state, repo);
    });

    test('createOwnCopyOfDefault in list swaps the row (S-13317)', () async {
      final (repo, state) = await _mockState();
      await _inListSwapsTheRow(state, repo);
    });

    test(
      'createOwnCopyOfDefault (source not a default) throws (D-13310)',
      () async {
        final (_, state) = await _mockState();
        final userFoodId = await state.createCatalogFood(_draft());
        await state.addCatalogFoodToLibrary(userFoodId);
        final copy = state.foods.firstWhere((f) => f.catalogId == userFoodId);
        expect(state.isDefaultFood(copy), isFalse);

        await expectLater(
          state.createOwnCopyOfDefault(copy, _draft(), addToList: false),
          throwsStateError,
        );
      },
    );

    test(
      'isDefaultFood: bundled row and copy true, user food false (D-13310)',
      () async {
        final (_, state) = await _mockState();
        final chicken = state.catalogFoods.firstWhere(
          (f) => f.id == 'chicken_breast',
        );
        expect(state.isDefaultFood(chicken), isTrue);

        await state.addCatalogFoodToLibrary('chicken_breast');
        final copy = state.libraryFoodFor('chicken_breast')!;
        expect(state.isDefaultFood(copy), isTrue);

        final userFoodId = await state.createCatalogFood(_draft());
        final userFood = state.catalogFoods.firstWhere(
          (f) => f.id == userFoodId,
        );
        expect(state.isDefaultFood(userFood), isFalse);

        await state.addCatalogFoodToLibrary(userFoodId);
        final userCopy = state.libraryFoodFor(userFoodId)!;
        expect(state.isDefaultFood(userCopy), isFalse);
      },
    );

    test(
      'S-13329 a failing add keeps the old copy, leaves no new catalog '
      'food and no photo file',
      () async {
        final img = TestImageStorage.create();
        addTearDown(img.dispose);
        final repo = _FlaggedAddRepo();
        await repo.initialize();
        final state = FoodLibraryState(repo, imageStorage: img.service);
        await state.loadCatalogFoods();

        // Setup: the default in the list. The failing subclass must only
        // THROW once the flag is set, so this setup add runs on the
        // passing implementation.
        await state.addCatalogFoodToLibrary('chicken_breast');
        final copy = state.libraryFoodFor('chicken_breast')!;
        repo.failAdd = true;

        await expectLater(
          state.createOwnCopyOfDefault(copy, _draft(), addToList: true),
          throwsStateError,
        );

        // The old copy is still in the list.
        expect(state.foods.any((f) => f.id == copy.id), isTrue);
        // No new catalog food was left behind.
        expect(
          state.catalogFoods.where((f) => f.name == 'Zed 133 bird'),
          isEmpty,
        );
        // The managed directory holds no file at all: the shipped-photo
        // copy written for the abandoned swap was discarded.
        final managedDir = Directory(img.service.managedDirectoryPath);
        expect(
          managedDir.existsSync() ? managedDir.listSync() : <FileSystemEntity>[],
          isEmpty,
        );
      },
    );

    test('S-13330 a failing catalog create leaves no photo file', () async {
      final img = TestImageStorage.create();
      addTearDown(img.dispose);
      final repo = _FlaggedCreateRepo();
      await repo.initialize();
      final state = FoodLibraryState(repo, imageStorage: img.service);
      await state.loadCatalogFoods();
      final chicken = state.catalogFoods.firstWhere(
        (f) => f.id == 'chicken_breast',
      );
      repo.failCreate = true;

      await expectLater(
        state.createOwnCopyOfDefault(chicken, _draft(), addToList: false),
        throwsStateError,
      );

      // The managed directory holds no file at all: the fresh
      // shipped-photo copy was discarded with the failed save.
      final managedDir = Directory(img.service.managedDirectoryPath);
      expect(
        managedDir.existsSync() ? managedDir.listSync() : <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('S-13333 an in-list swap keeps exactly one row for the food', () async {
      final (_, state) = await _mockState();
      final libId = await state.addCatalogFoodToLibrary('chicken_breast');
      final copy = state.foods.firstWhere((f) => f.id == libId);

      await state.createOwnCopyOfDefault(copy, _draft(), addToList: true);

      // Exactly one library row for the new food (the old copy was
      // removed, not duplicated against it).
      expect(state.foods.where((f) => f.name == 'Zed 133 bird').length, 1);
      expect(state.libraryFoodFor('chicken_breast'), isNull);
    });
  });

  group('FoodLibraryState create own copy (Mock) — photo (S-13314)', () {
    // Mock-only: the photo bytes come from a real temp-dir
    // `TestImageStorage` service; asset loading goes through
    // `rootBundle` (binding initialized at the top of `main`).
    test('S-13314 (a) null draft + shipped asset: new managed basename, '
        'bytes equal the asset bytes', () async {
      final img = TestImageStorage.create();
      addTearDown(img.dispose);
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo, imageStorage: img.service);
      await state.loadCatalogFoods();
      final chicken = state.catalogFoods.firstWhere(
        (f) => f.id == 'chicken_breast',
      );

      final assetBytes = (await rootBundle.load(
        'assets/images/food_chicken_breast.webp',
      )).buffer.asUint8List();

      final newId = await state.createOwnCopyOfDefault(
        chicken,
        _draft(),
        addToList: false,
      );

      final created = state.catalogFoods.firstWhere((f) => f.id == newId);
      final path = created.imagePath;
      expect(path, isNotNull);
      expect(path!.contains('/'), isFalse, reason: 'basename contract (D-1)');
      final file = File(_managedFile(img.service.managedDirectoryPath, path));
      expect(file.existsSync(), isTrue);
      expect(listEquals(file.readAsBytesSync(), assetBytes), isTrue);
    });

    test('S-13314 (b) draft carries a managed file: fresh basename, bytes '
        'equal, the replaced copy file is deleted after the swap', () async {
      final img = TestImageStorage.create();
      addTearDown(img.dispose);
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo, imageStorage: img.service);
      await state.loadCatalogFoods();

      // The replaced copy's own managed file - the draft's
      // picked photo re-carried by the form (D-13315).
      final managedBytes = Uint8List.fromList([9, 8, 7, 6, 5]);
      final managedBasename = await img.service.persistImageBytes(
        managedBytes,
        extension: '.jpg',
      );
      final managedFile = File(
        _managedFile(img.service.managedDirectoryPath, managedBasename),
      );
      expect(managedFile.existsSync(), isTrue);

      final libId = await state.addCatalogFoodToLibrary('chicken_breast');
      final copy = state.foods.firstWhere((f) => f.id == libId);
      await state.updateFood(copy.copyWith(imagePath: managedBasename));

      final returnedId = await state.createOwnCopyOfDefault(
        state.foods.firstWhere((f) => f.id == libId),
        _draft(imagePath: managedBasename),
        addToList: true,
      );

      final newLibraryRow = state.foods.firstWhere((f) => f.id == returnedId);
      final newPath = newLibraryRow.imagePath;
      expect(newPath, isNotNull);
      // The new copy never shares a managed basename with the source
      // (INV-133-B).
      expect(newPath, isNot(managedBasename));
      expect(newPath!.contains('/'), isFalse);
      // Bytes equal: the new file is an independent copy, not a link.
      final newFile = File(
        _managedFile(img.service.managedDirectoryPath, newPath),
      );
      expect(newFile.existsSync(), isTrue);
      expect(listEquals(newFile.readAsBytesSync(), managedBytes), isTrue);
      // The replaced copy's own managed file is gone
      expect(managedFile.existsSync(), isFalse);
      // ...while the new copy's file is NOT deleted (D-13315).
      expect(newFile.existsSync(), isTrue);
    });

    test('S-13314 (c) photo-resolution failure: save succeeds, no photo, '
        'no throw', () async {
      final img = TestImageStorage.create();
      addTearDown(img.dispose);
      final repo = await _freshRepo();
      // A service whose managed directory cannot be created: the base
      // directory is an existing FILE, so persistImageBytes throws
      // (S-13324 shape). D-13315 third leg: the failure is swallowed
      // and the save still succeeds.
      final blockerBase = img.tempDir.createTempSync('blocker_');
      final blockerFile = File('${blockerBase.path}/leaf');
      blockerFile.writeAsBytesSync(const [1]);
      final throwingService = ImageStorageService.fromBaseDirectory(
        blockerFile.path,
      );
      final state = FoodLibraryState(repo, imageStorage: throwingService);
      await state.loadCatalogFoods();
      final chicken = state.catalogFoods.firstWhere(
        (f) => f.id == 'chicken_breast',
      );

      final newId = await state.createOwnCopyOfDefault(
        chicken,
        _draft(),
        addToList: false,
      );

      final created = state.catalogFoods.firstWhere((f) => f.id == newId);
      expect(created.imagePath, isNull);
      expect(created.name, 'Zed 133 bird');
    });
  });

  group('FoodLibraryState create own copy (Hive)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('food_lib_own_copy_');
      _PathProviderChannel.install(tempDir);
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('createOwnCopyOfDefault not in list adds nothing (S-13317)', () async {
      final repo = HiveWorkoutRepository();
      await repo.initialize();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      await _notInListAddsNothing(state, repo);
    });

    test('createOwnCopyOfDefault in list swaps the row (S-13317)', () async {
      final repo = HiveWorkoutRepository();
      await repo.initialize();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      await _inListSwapsTheRow(state, repo);
    });

    test(
      'createOwnCopyOfDefault (source not a default) throws (D-13310)',
      () async {
        final repo = HiveWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);
        await state.loadCatalogFoods();
        final userFoodId = await state.createCatalogFood(_draft());
        await state.addCatalogFoodToLibrary(userFoodId);
        final copy = state.foods.firstWhere((f) => f.catalogId == userFoodId);
        expect(state.isDefaultFood(copy), isFalse);

        await expectLater(
          state.createOwnCopyOfDefault(copy, _draft(), addToList: false),
          throwsStateError,
        );
      },
    );
  });
}

/// S-13329: fails ONLY once [failAdd] is set, so the fixture's own
/// setup `addCatalogFoodToLibrary` still succeeds.
class _FlaggedAddRepo extends MockWorkoutRepository {
  bool failAdd = false;

  @override
  Future<String> addCatalogFoodToLibrary(String catalogFoodId) async {
    if (failAdd) {
      throw StateError('library add failed (S-13329)');
    }
    return super.addCatalogFoodToLibrary(catalogFoodId);
  }
}

/// S-13330: fails ONLY once [failCreate] is set.
class _FlaggedCreateRepo extends MockWorkoutRepository {
  bool failCreate = false;

  @override
  Future<String> createCatalogFood(Food food) async {
    if (failCreate) {
      throw StateError('catalog create failed (S-13330)');
    }
    return super.createCatalogFood(food);
  }
}
