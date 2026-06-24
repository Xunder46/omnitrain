// filepath: test/food_library_persistence_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';

/// Stand-in for the path_provider platform channel used during tests.
/// `HiveWorkoutRepository.initialize()` calls `Hive.initFlutter()`, which
/// delegates to `path_provider.getApplicationDocumentsDirectory()`. In
/// `flutter_test` that platform channel has no implementation, so we route
/// the call to a temporary directory we control.
class _PathProviderChannel {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  static late Directory _root;

  static void install(Directory root) {
    _root = root;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
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

/// Helper to create a library food for testing. Macros are `double`
/// to match the [Food] model.
Food _testFood({
  String id = 'food-test-1',
  String name = 'Test Chicken',
  double protein = 31,
  double carbs = 0,
  double fat = 3,
}) {
  return Food(
    id: id,
    name: name,
    unitType: FoodUnitType.grams,
    referenceAmount: 100.0,
    referenceLabel: 'g',
    isCatalog: false,
    protein: protein,
    carbs: carbs,
    fat: fat,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

void main() {
  group('FoodLibraryState persistence', () {
    late Directory tempDir;

    setUp(() async {
      // Initialize Hive for testing. `HiveWorkoutRepository.initialize()`
      // calls `Hive.initFlutter()` which in turn asks the `path_provider`
      // platform channel for a documents directory — that channel has no
      // implementation under `flutter_test`, so we install a mock that
      // points at a per-test temp directory.
      tempDir = await Directory.systemTemp.createTemp('food_lib_persist_');
      _PathProviderChannel.install(tempDir);
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      // Hard-reset Hive so the next setUp starts with a clean registry.
      // Hive.close() alone leaves the type registry intact, which can
      // cause "type adapter already registered" errors when the next
      // test's setUp() re-initializes against a new directory.
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('library persists across restart', () async {
      // Create first repository and add a food
      final repo1 = HiveWorkoutRepository();
      await repo1.initialize();

      final state1 = FoodLibraryState(repo1);
      await state1.loadFoods();

      // Library should start empty
      expect(state1.foods, isEmpty);

      // Create a food
      final food = _testFood(
        id: 'food-persist-1',
        name: 'Persistence Chicken',
        protein: 31,
        carbs: 0,
        fat: 3,
      );
      await state1.createFood(food);

      // Verify food is in state
      expect(state1.foods.length, 1);
      expect(state1.foods[0].id, 'food-persist-1');
      expect(state1.foods[0].name, 'Persistence Chicken');
      expect(state1.foods[0].protein, 31);
      expect(state1.foods[0].isCatalog, false);
      expect(state1.foods[0].isArchived, false);

      // Create a new repository pointing to the same storage
      final repo2 = HiveWorkoutRepository();
      await repo2.initialize();

      // Load foods into new state
      final state2 = FoodLibraryState(repo2);
      await state2.loadFoods();

      // Verify the food persisted across restart
      expect(state2.foods.length, 1);
      expect(state2.foods[0].id, 'food-persist-1');
      expect(state2.foods[0].name, 'Persistence Chicken');
      expect(state2.foods[0].protein, 31);
      expect(state2.foods[0].carbs, 0);
      expect(state2.foods[0].fat, 3);
      expect(state2.foods[0].isCatalog, false);
      expect(state2.foods[0].isArchived, false);

      // Clean up
      await repo2.clear();
    });

    test('library persists with multiple foods across restart', () async {
      // Create first repository and add multiple foods
      final repo1 = HiveWorkoutRepository();
      await repo1.initialize();

      final state1 = FoodLibraryState(repo1);
      await state1.loadFoods();

      // Create multiple foods
      final food1 = _testFood(id: 'food-1', name: 'Chicken Breast', protein: 31);
      final food2 = _testFood(id: 'food-2', name: 'Brown Rice', protein: 3, carbs: 23, fat: 1);
      final food3 = _testFood(id: 'food-3', name: 'Broccoli', protein: 3, carbs: 7, fat: 0);

      await state1.createFood(food1);
      await state1.createFood(food2);
      await state1.createFood(food3);

      expect(state1.foods.length, 3);

      // Drop the in-memory handles — the on-disk boxes stay open via the
      // static Hive registry, so a brand-new repository can re-attach to
      // the same data without us calling `clear()` (which would wipe it).
      await Hive.close();

      final repo2 = HiveWorkoutRepository();
      await repo2.initialize();

      final state2 = FoodLibraryState(repo2);
      await state2.loadFoods();

      // Verify all foods persisted
      expect(state2.foods.length, 3);
      expect(state2.foods.map((f) => f.name).toList(),
          containsAll(['Chicken Breast', 'Brown Rice', 'Broccoli']));

      await repo2.clear();
    });

    test('removing food removes it from persisted storage', () async {
      // Create repository and add a food
      final repo = HiveWorkoutRepository();
      await repo.initialize();

      final state = FoodLibraryState(repo);
      await state.loadFoods();

      final food = _testFood(id: 'food-to-remove', name: 'Remove Me');
      await state.createFood(food);

      expect(state.foods.length, 1);

      // Remove the food
      await state.removeFood('food-to-remove');

      // Verify removed from state
      expect(state.foods, isEmpty);

      // Verify removed from storage by creating new state
      await repo.clear();

      final repo2 = HiveWorkoutRepository();
      await repo2.initialize();

      final state2 = FoodLibraryState(repo2);
      await state2.loadFoods();

      // Should still be empty
      expect(state2.foods, isEmpty);

      await repo2.clear();
    });
  });
}
