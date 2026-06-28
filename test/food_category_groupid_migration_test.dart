// filepath: test/food_category_groupid_migration_test.dart
//
// Unit tests for the one-shot Hive migration
// `food_category_groupid_migrated_v1` that backfills catalog rows
// from the legacy `notes: '<Category>'` storage into a proper
// `group_id` FK.
//
// Scenarios covered:
//   S-021: match — every catalog row carrying a known category in
//          `notes` resolves to a non-null `group_id` and a cleared
//          `notes`.
//   S-022: non-match — rows whose `notes` doesn't match any active
//          default group are left as `group_id = NULL`, `notes`
//          preserved as-is.
//   Idempotency: a second `initialize()` is a no-op; the marker
//   prevents re-runs.
//
// The migration runs against both `_foodsBox` (library) and
// `_foodCatalogBox` (catalog). The tests exercise both boxes.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';

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

Map<String, dynamic> _legacyCatalogRow({
  required String id,
  required String category,
  String? groupId,
  String? notes,
}) {
  return <String, dynamic>{
    'id': id,
    'name': 'Legacy $id',
    'group_id': groupId,
    'unit_type': 'grams',
    'reference_amount': 100.0,
    'reference_label': 'g',
    'is_catalog': 1,
    'protein': 10,
    'carbs': 5,
    'fat': 2,
    'is_archived': 0,
    'notes': notes ?? category,
    'image_path': null,
    'created_at_ms': 1000,
    'updated_at_ms': 1000,
  };
}

Map<String, dynamic> _legacyLibraryRow({
  required String id,
  required String? notes,
  String? groupId,
}) {
  return <String, dynamic>{
    'id': id,
    'name': 'Library $id',
    'group_id': groupId,
    'unit_type': 'grams',
    'reference_amount': 100.0,
    'reference_label': 'g',
    'is_catalog': 0,
    'protein': 10,
    'carbs': 5,
    'fat': 2,
    'is_archived': 0,
    'notes': notes,
    'image_path': null,
    'created_at_ms': 1000,
    'updated_at_ms': 1000,
  };
}

void main() {
  group('Hive food category → groupId migration (S-021, S-022)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('food_cat_mig_');
      _PathProviderChannel.install(tempDir);
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'S-021: catalog row with matching notes resolves to groupId and clears notes',
      () async {
        // Open boxes directly and seed them with LEGACY rows (notes carries
        // the category, group_id is null). This is the on-disk shape of a
        // pre-migration install.
        final catalogBox = await Hive.openBox<Map>('foods_catalog');
        catalogBox.put(
          'chicken_breast',
          _legacyCatalogRow(id: 'chicken_breast', category: 'Proteins'),
        );
        catalogBox.put(
          'milk',
          _legacyCatalogRow(id: 'milk', category: 'Dairy'),
        );
        catalogBox.put(
          'apple',
          _legacyCatalogRow(id: 'apple', category: 'Fruits'),
        );

        // Initialize runs all migrations including the new one. Default
        // groups must be seeded before the migration, which our
        // initialize() does.
        final repo = HiveWorkoutRepository();
        await repo.initialize();

        // Verify the catalog rows now carry the right group_id and have
        // notes cleared.
        final afterChicken = catalogBox.get('chicken_breast') as Map;
        expect(afterChicken['group_id'], 'food-group-proteins');
        expect(afterChicken['notes'], isNull);

        final afterMilk = catalogBox.get('milk') as Map;
        expect(afterMilk['group_id'], 'food-group-dairy');
        expect(afterMilk['notes'], isNull);

        final afterApple = catalogBox.get('apple') as Map;
        expect(afterApple['group_id'], 'food-group-fruits');
        expect(afterApple['notes'], isNull);
      },
    );

    test('S-022: non-matching notes are left untouched', () async {
      final catalogBox = await Hive.openBox<Map>('foods_catalog');
      catalogBox.put(
        'mystery',
        _legacyCatalogRow(
          id: 'mystery',
          category: 'Mystery Bucket', // not a default group
        ),
      );
      catalogBox.put(
        'renamed',
        _legacyCatalogRow(id: 'renamed', category: 'Proteins'),
      );

      final repo = HiveWorkoutRepository();
      await repo.initialize();

      // 'Mystery Bucket' has no matching default; the row stays put.
      final mystery = catalogBox.get('mystery') as Map;
      expect(mystery['group_id'], isNull);
      expect(mystery['notes'], 'Mystery Bucket');

      // 'Proteins' resolves fine.
      final renamed = catalogBox.get('renamed') as Map;
      expect(renamed['group_id'], 'food-group-proteins');
      expect(renamed['notes'], isNull);
    });

    test(
      'Library rows whose notes match a default category are backfilled',
      () async {
        // Simulate an install where the user added a catalog food to
        // their library on a previous version. The library row carries
        // the category in `notes` and `group_id = null`.
        final libraryBox = await Hive.openBox<Map>('foods');
        libraryBox.put(
          'lib_chicken',
          _legacyLibraryRow(id: 'lib_chicken', notes: 'Proteins'),
        );
        libraryBox.put(
          'lib_apple',
          _legacyLibraryRow(id: 'lib_apple', notes: 'Fruits'),
        );

        final repo = HiveWorkoutRepository();
        await repo.initialize();

        final chicken = libraryBox.get('lib_chicken') as Map;
        expect(chicken['group_id'], 'food-group-proteins');
        expect(chicken['notes'], isNull);

        final apple = libraryBox.get('lib_apple') as Map;
        expect(apple['group_id'], 'food-group-fruits');
        expect(apple['notes'], isNull);
      },
    );

    test('Library rows with user-typed notes are NOT touched', () async {
      // A user-typed note that happens to NOT be a category name
      // must be preserved.
      final libraryBox = await Hive.openBox<Map>('foods');
      libraryBox.put(
        'user_food',
        _legacyLibraryRow(
          id: 'user_food',
          notes: 'My personal recipe — do not touch',
        ),
      );

      final repo = HiveWorkoutRepository();
      await repo.initialize();

      final userFood = libraryBox.get('user_food') as Map;
      expect(userFood['group_id'], isNull);
      expect(userFood['notes'], 'My personal recipe — do not touch');
    });

    test(
      'idempotency: a second initialize() does not re-run the migration',
      () async {
        final catalogBox = await Hive.openBox<Map>('foods_catalog');
        catalogBox.put(
          'chicken_breast',
          _legacyCatalogRow(id: 'chicken_breast', category: 'Proteins'),
        );

        // First run: performs the migration.
        final repo1 = HiveWorkoutRepository();
        await repo1.initialize();
        final migrated = catalogBox.get('chicken_breast') as Map;
        expect(migrated['group_id'], 'food-group-proteins');
        expect(migrated['notes'], isNull);

        // Re-introduce a legacy state to detect a re-run.
        // (If the marker is honoured, the next initialize() is a no-op
        // and the migrated state is left alone.)
        // Mutate directly to simulate a regression.
        // ignore: avoid_dynamic_calls
        (catalogBox.get('chicken_breast') as Map)['notes'] = 'Proteins';

        final repo2 = HiveWorkoutRepository();
        await repo2.initialize();
        final afterSecond = catalogBox.get('chicken_breast') as Map;
        // The migration is a no-op: the row we tampered with is left
        // as-is. group_id is still set, but notes is back to the legacy
        // value. The migration has already run; a second pass would
        // overwrite notes back to null, but the marker prevents that.
        expect(afterSecond['group_id'], 'food-group-proteins');
        // The marker is set, so notes is left as we left it.
        expect(afterSecond['notes'], 'Proteins');
      },
    );

    test('migration honours user-renamed default groups (no match)', () async {
      // Realistic flow: a user previously installed the app, the seed
      // migration wrote the 9 default groups, and the user renamed
      // "Proteins" → "Legumes" via the UI. On the next launch the seed
      // migration's stable-id guard preserves the rename. The category
      // migration reads the LIVE group names and finds no group called
      // "Proteins", so a catalog row carrying notes='Proteins' gets
      // no match and is left as-is.
      //
      // The seed migration also re-writes the bundled catalog, so we
      // mutate the groups box + insert a legacy catalog row AFTER
      // initialize() runs, then re-run the migration via the
      // `@visibleForTesting` helper.
      final repo = HiveWorkoutRepository();
      await repo.initialize();

      // Simulate the user rename.
      final groupsBox = await Hive.openBox<Map>('food_groups');
      final proteins = Map<String, dynamic>.from(
        groupsBox.get('food-group-proteins') as Map,
      );
      proteins['name'] = 'Legumes';
      await groupsBox.put('food-group-proteins', proteins);

      // Insert a legacy catalog row (the bundled seed overwrote it
      // during initialize with the new format).
      final catalogBox = await Hive.openBox<Map>('foods_catalog');
      await catalogBox.put(
        'chicken_breast',
        _legacyCatalogRow(id: 'chicken_breast', category: 'Proteins'),
      );

      // Re-run the category migration only.
      await repo.rerunCategoryMigrationForTest();

      final after = catalogBox.get('chicken_breast') as Map;
      // No active group named "Proteins" anymore → no match.
      expect(after['group_id'], isNull);
      expect(after['notes'], 'Proteins');
    });

    test('migration is a no-op when there is nothing to migrate', () async {
      // Fresh install: catalog box is empty (the seed migration runs
      // after, populating it with correctly-formed rows). The
      // category→groupId migration should simply mark itself done.
      final repo = HiveWorkoutRepository();
      await repo.initialize();

      final catalogFoods = await repo.getCatalogFoods();
      expect(catalogFoods.length, 107);
      // All catalog rows must already carry the resolved groupId.
      for (final food in catalogFoods) {
        expect(
          food.groupId,
          isNotNull,
          reason: '${food.id} should have a groupId from the loader',
        );
        expect(
          food.notes,
          isNull,
          reason: '${food.id} should not carry the category in notes',
        );
      }
    });
  });
}
