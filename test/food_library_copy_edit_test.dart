// filepath: test/food_library_copy_edit_test.dart
//
// Plan 77a P1 — state tests for `editLibraryFood`, `canResetLibraryFood`,
// `resetLibraryFood`, `libraryFoodFor` and `foodServingLabel`
// (scenarios S-12701..S-12709, S-12718).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/core/utils/food_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'helpers/test_image_storage.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Food _libraryFood({
  String id = 'food-edit-1',
  String name = 'Edit Me',
  String? groupId,
  double protein = 10,
  double carbs = 20,
  double? fiber = 0,
  double fat = 5,
  String? imagePath,
  FoodUnitType unitType = FoodUnitType.grams,
  double referenceAmount = 100,
  String referenceLabel = 'g',
}) {
  return Food(
    id: id,
    name: name,
    groupId: groupId,
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

FoodDraft _draft({
  String name = 'My almond',
  double protein = 99,
  String? imagePath,
  String? notes,
}) {
  return FoodDraft(
    name: name,
    groupId: null,
    unitType: FoodUnitType.count,
    referenceAmount: 1,
    referenceLabel: 'tbsp',
    protein: protein,
    carbs: 3,
    fiber: 1.6,
    fat: 9,
    sodium: 36,
    notes: notes,
    imagePath: imagePath,
  );
}

/// Stand-in for the path_provider platform channel used during tests.
/// Copied from `test/food_library_persistence_test.dart` (plan 77a P1
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

void main() {
  group('FoodLibraryState edit own copy (Mock)', () {
    test('editLibraryFood changes only the library copy (S-12701)', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final copy = state.foods.firstWhere((f) => f.id == libId);

      await state.editLibraryFood(copy, _draft());

      final edited = state.foods.firstWhere((f) => f.id == libId);
      expect(edited.protein, 99);
      expect(edited.name, 'My almond');

      final catalog = await repo.getCatalogFoodById('almond_butter');
      expect(catalog, isNotNull);
      expect(catalog!.name, 'Almond butter');
      expect(catalog.protein, 3.4);
      expect(
        await repo.isSeedEntryTouched(
          SeedEntryType.foodCatalog,
          'almond_butter',
        ),
        isFalse,
      );
    });

    test(
      'lastAmountConsumed and catalogId survive an edit (S-12702)',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.loadCatalogFoods();
        final libId = await state.addCatalogFoodToLibrary('almond_butter');
        final copy = state.foods.firstWhere((f) => f.id == libId);
        await state.updateFood(copy.copyWith(lastAmountConsumed: 250.0));

        final before = state.foods.firstWhere((f) => f.id == libId);
        await state.editLibraryFood(before, _draft());

        final edited = state.foods.firstWhere((f) => f.id == libId);
        expect(edited.lastAmountConsumed, 250);
        expect(edited.catalogId, 'almond_butter');
      },
    );

    test('canResetLibraryFood lifecycle (S-12703)', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final copy = state.foods.firstWhere((f) => f.id == libId);

      // Untouched copy: not resettable.
      expect(state.canResetLibraryFood(copy), isFalse);

      // After an edit: resettable.
      await state.editLibraryFood(copy, _draft());
      final edited = state.foods.firstWhere((f) => f.id == libId);
      expect(state.canResetLibraryFood(edited), isTrue);

      // After a reset: not resettable again.
      await state.resetLibraryFood(libId);
      final reset = state.foods.firstWhere((f) => f.id == libId);
      expect(state.canResetLibraryFood(reset), isFalse);

      // A copy of a user-created (non-bundled) catalog food: never resettable.
      final customCatalogId = await state.createCatalogFood(
        _draft(name: 'My custom'),
      );
      final customLibId = await state.addCatalogFoodToLibrary(customCatalogId);
      final customCopy = state.foods.firstWhere((f) => f.id == customLibId);
      expect(state.canResetLibraryFood(customCopy), isFalse);

      // A legacy library-only row (no catalogId): never resettable.
      await state.createFood(_libraryFood(id: 'legacy-1'));
      final legacy = state.foods.firstWhere((f) => f.id == 'legacy-1');
      expect(state.canResetLibraryFood(legacy), isFalse);
    });

    test('S-12703b canResetLibraryFood is false for a changed copy of a '
        'user-created food', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final id = await state.createCatalogFood(_draft(name: 'My custom'));
      await state.addCatalogFoodToLibrary(id);
      final copy = state.libraryFoodFor(id)!;

      // Edit the copy so it differs from its catalog row: the fields
      // really differ, but the food is not bundled, so it is still
      // never resettable.
      await state.editLibraryFood(
        copy,
        _draft(name: 'Differs 77', protein: 71),
      );
      final changed = state.libraryFoodFor(id)!;
      expect(changed.name, 'Differs 77');
      expect(changed.catalogId, id);
      expect(state.canResetLibraryFood(changed), isFalse);
      await expectLater(
        state.resetLibraryFood(changed.id),
        throwsA(isA<StateError>()),
      );
    });

    test('resetLibraryFood restores the shipped values (S-12704)', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final copy = state.foods.firstWhere((f) => f.id == libId);
      await state.updateFood(copy.copyWith(lastAmountConsumed: 250.0));
      final before = state.foods.firstWhere((f) => f.id == libId);
      await state.editLibraryFood(
        before,
        _draft(
          name: 'My almond',
          protein: 99,
          imagePath: 'custom.jpg',
          notes: 'mine',
        ),
      );

      await state.resetLibraryFood(libId);

      final reset = state.foods.firstWhere((f) => f.id == libId);
      expect(reset.id, libId);
      expect(reset.name, 'Almond butter');
      expect(reset.protein, 3.4);
      expect(reset.imagePath, isNull);
      expect(reset.notes, isNull);
      expect(reset.fiber, 1.6);
      expect(reset.sodium, 36);
      expect(reset.lastAmountConsumed, 250);
    });

    test('updateCatalogFood still propagates to the copy (S-12705)', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final catalogId = await state.createCatalogFood(
        _draft(name: 'My custom'),
      );
      await state.addCatalogFoodToLibrary(catalogId);

      final catalogRow = state.catalogFoods.firstWhere(
        (f) => f.id == catalogId,
      );
      await state.updateCatalogFood(catalogRow, _draft(name: 'Renamed custom'));

      final copy = state.foods.firstWhere((f) => f.catalogId == catalogId);
      expect(copy.name, 'Renamed custom');
    });

    test('image delete rules on edit (S-12706)', () async {
      final img = TestImageStorage.create();
      addTearDown(img.dispose);
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo, imageStorage: img.service);
      await state.loadCatalogFoods();

      // Case 1: clearing a managed image the catalog row does not hold
      // deletes the file.
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final copy = state.foods.firstWhere((f) => f.id == libId);
      final managedDir = Directory(img.service.managedDirectoryPath)
        ..createSync(recursive: true);
      final file = File('${managedDir.path}/copy_photo.jpg')
        ..writeAsStringSync('photo');
      await state.updateFood(copy.copyWith(imagePath: 'copy_photo.jpg'));
      final before = state.foods.firstWhere((f) => f.id == libId);
      await state.editLibraryFood(before, _draft(imagePath: null));
      expect(file.existsSync(), isFalse);

      // Case 2: editing when the copy's path equals the catalog row's
      // path deletes nothing.
      final shared = File('${managedDir.path}/shared.jpg')
        ..writeAsStringSync('shared');
      final customCatalogId = await state.createCatalogFood(
        _draft(name: 'My custom', imagePath: 'shared.jpg'),
      );
      final customLibId = await state.addCatalogFoodToLibrary(customCatalogId);
      final customCopy = state.foods.firstWhere((f) => f.id == customLibId);
      await state.editLibraryFood(customCopy, _draft(imagePath: 'other.jpg'));
      expect(shared.existsSync(), isTrue);
    });

    test('two edits from one stale snapshot still clean up the photo '
        '(S-12706b)', () async {
      final img = TestImageStorage.create();
      addTearDown(img.dispose);
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo, imageStorage: img.service);
      await state.loadCatalogFoods();
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final stale = state.foods.firstWhere((f) => f.id == libId);
      final managedDir = Directory(img.service.managedDirectoryPath)
        ..createSync(recursive: true);
      final first = File('${managedDir.path}/first_pick.jpg')
        ..writeAsStringSync('a');
      File('${managedDir.path}/second_pick.jpg').writeAsStringSync('b');

      await state.editLibraryFood(stale, _draft(imagePath: 'first_pick.jpg'));
      expect(first.existsSync(), isTrue);
      // Same stale snapshot (imagePath null) passed again, as the edit
      // screen's second auto-save does.
      await state.editLibraryFood(stale, _draft(imagePath: 'second_pick.jpg'));

      expect(first.existsSync(), isFalse);
      expect(
        state.foods.firstWhere((f) => f.id == libId).imagePath,
        'second_pick.jpg',
      );
    });

    test('foodServingLabel table (S-12707)', () {
      Food food(double referenceAmount, String referenceLabel) => Food(
        id: 'f',
        name: 'f',
        unitType: FoodUnitType.grams,
        referenceAmount: referenceAmount,
        referenceLabel: referenceLabel,
        protein: 0,
        carbs: 0,
        fat: 0,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

      expect(foodServingLabel(food(100, 'ml')), '100 ml');
      expect(foodServingLabel(food(100, 'per 100 g')), '100 g');
      expect(foodServingLabel(food(100, 'per 100g')), '100 100g');
      expect(foodServingLabel(food(1, 'tbsp')), '1 tbsp');
    });

    test('edited copy keeps identity fields (S-12708)', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final copy = state.foods.firstWhere((f) => f.id == libId);

      await state.editLibraryFood(copy, _draft());

      final edited = state.foods.firstWhere((f) => f.id == libId);
      expect(edited.isCatalog, isFalse);
      expect(edited.catalogId, 'almond_butter');
      expect(edited.updatedAtMs, greaterThan(1000));
    });

    test('ghost catalogId cannot reset (S-12709)', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      await state.createFood(_libraryFood(id: 'ghost-copy'));
      final created = state.foods.firstWhere((f) => f.id == 'ghost-copy');
      await state.updateFood(created.copyWith(catalogId: 'ghost_food'));
      final copy = state.foods.firstWhere((f) => f.id == 'ghost-copy');

      expect(state.canResetLibraryFood(copy), isFalse);
      await expectLater(
        state.resetLibraryFood('ghost-copy'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'libraryFoodFor returns the copy, null before add (S-12718)',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);
        await state.loadCatalogFoods();

        expect(state.libraryFoodFor('almond_butter'), isNull);

        final libId = await state.addCatalogFoodToLibrary('almond_butter');
        final copy = state.libraryFoodFor('almond_butter');
        expect(copy, isNotNull);
        expect(copy!.id, libId);

        await state.editLibraryFood(copy, _draft());
        final edited = state.libraryFoodFor('almond_butter');
        expect(edited!.name, 'My almond');
        expect(edited.protein, 99);
      },
    );
  });

  group('FoodLibraryState edit own copy (Hive)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('food_lib_copy_edit_');
      _PathProviderChannel.install(tempDir);
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('editLibraryFood changes only the library copy (S-12701)', () async {
      final repo = HiveWorkoutRepository();
      await repo.initialize();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final copy = state.foods.firstWhere((f) => f.id == libId);

      await state.editLibraryFood(copy, _draft());

      final edited = state.foods.firstWhere((f) => f.id == libId);
      expect(edited.protein, 99);
      expect(edited.name, 'My almond');
      final catalog = await repo.getCatalogFoodById('almond_butter');
      expect(catalog!.name, 'Almond butter');
      expect(
        await repo.isSeedEntryTouched(
          SeedEntryType.foodCatalog,
          'almond_butter',
        ),
        isFalse,
      );
    });

    test('canResetLibraryFood lifecycle (S-12703)', () async {
      final repo = HiveWorkoutRepository();
      await repo.initialize();
      final state = FoodLibraryState(repo);
      await state.loadCatalogFoods();
      final libId = await state.addCatalogFoodToLibrary('almond_butter');
      final copy = state.foods.firstWhere((f) => f.id == libId);

      expect(state.canResetLibraryFood(copy), isFalse);

      await state.editLibraryFood(copy, _draft());
      final edited = state.foods.firstWhere((f) => f.id == libId);
      expect(state.canResetLibraryFood(edited), isTrue);

      await state.resetLibraryFood(libId);
      final reset = state.foods.firstWhere((f) => f.id == libId);
      expect(state.canResetLibraryFood(reset), isFalse);
    });
  });
}
