// ignore_for_file: avoid_print
//
// Regenerate `lib/mock/food_catalog_seed.dart` from
// `assets/data/food_catalog.json`.
//
// Run from the project root:
//   dart run scripts/generate_food_catalog_seed.dart
//
// The output is a hand-editable list of `Food` consts. The script reads
// the JSON, resolves each `category` string to the matching
// `FoodGroup.id` from `SeedData.defaultFoodGroups`, and writes
// `groupId` to the seed (the catalog's `notes` is left as `null`; the
// FK is the single source of truth for grouping).
//
// If you add a new category to the JSON, add the corresponding default
// group to `SeedData.defaultFoodGroups` first — the assertion in
// `food_catalog_load_test.dart` will fail otherwise.

import 'dart:convert';
import 'dart:io';

// Mirror of FoodCatalogLoader._categoryToGroupId. Kept local to the
// script so it can run without dragging in the Flutter project graph
// (it is a pure-dart program invoked via `dart run`).
const Map<String, String> _categoryToGroupId = {
  'proteins': 'food-group-proteins',
  'dairy': 'food-group-dairy',
  'grains & starches': 'food-group-grains-starches',
  'fruits': 'food-group-fruits',
  'vegetables': 'food-group-vegetables',
  'nuts, seeds & fats': 'food-group-nuts-seeds-fats',
  'snacks & prepared': 'food-group-snacks-prepared',
  'drinks': 'food-group-drinks',
  'condiments': 'food-group-condiments',
};

const String _seedTimestamp = '1700000000000';

String _formatNum(num? value, {bool asInt = false}) {
  if (value == null) return 'null';
  if (asInt) return value.round().toString();
  if (value is int) return value.toString();
  // Preserve the .0-free spelling for whole-valued doubles.
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toString();
}

String _renderFood(Map<String, dynamic> f) {
  final id = f['id'] as String;
  final name = f['name'] as String;
  final category = f['category'] as String;
  final groupId = _categoryToGroupId[category.toLowerCase()];
  if (groupId == null) {
    throw StateError(
      'No FoodGroup mapping for category "$category" (food: $id). '
      'Add a row to _categoryToGroupId and SeedData.defaultFoodGroups.',
    );
  }

  final unitType = (f['unitType'] as String) == 'count' ? 'count' : 'grams';
  final referenceAmount = (f['referenceAmount'] as num).toString();
  final referenceLabel = f['referenceLabel'] as String;
  final protein = _formatNum(f['protein'] as num?, asInt: true);
  final carbs = _formatNum(f['carbs'] as num?, asInt: true);
  final fiber = f['fiber'] == null
      ? 'null'
      : (f['fiber'] as num).round().toString();
  final fat = _formatNum(f['fat'] as num?, asInt: true);
  final sodium = f['sodium_mg'] == null
      ? 'null'
      : (f['sodium_mg'] as num).round().toString();

  final buf = StringBuffer();
  buf.writeln('      const Food(');
  buf.writeln("        id: '$id',");
  buf.writeln("        name: '$name',");
  buf.writeln("        groupId: '$groupId',");
  buf.writeln('        unitType: FoodUnitType.$unitType,');
  buf.writeln('        referenceAmount: $referenceAmount,');
  buf.writeln("        referenceLabel: '$referenceLabel',");
  buf.writeln('        isCatalog: true,');
  buf.writeln('        protein: $protein,');
  buf.writeln('        carbs: $carbs,');
  buf.writeln('        fiber: $fiber,');
  buf.writeln('        fat: $fat,');
  buf.writeln('        sodium: $sodium,');
  buf.writeln('        createdAtMs: $_seedTimestamp,');
  buf.writeln('        updatedAtMs: $_seedTimestamp,');
  buf.write('      ),');
  return buf.toString();
}

void main() {
  final jsonFile = File('assets/data/food_catalog.json');
  if (!jsonFile.existsSync()) {
    stderr.writeln('assets/data/food_catalog.json not found at project root.');
    exit(1);
  }

  final decoded =
      jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
  final foods = (decoded['foods'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  final buf = StringBuffer();
  buf.writeln("// GENERATED FILE — DO NOT EDIT.");
  buf.writeln(
    "// Regenerate with: dart run scripts/generate_food_catalog_seed.dart",
  );
  buf.writeln("//");
  buf.writeln("// Source: assets/data/food_catalog.json");
  buf.writeln("");
  buf.writeln("import '../data/models/models.dart';");
  buf.writeln("");
  buf.writeln("/// Hardcoded list of catalog foods for in-memory testing.");
  buf.writeln("///");
  buf.writeln(
    "/// This list mirrors the JSON asset at `assets/data/food_catalog.json` and is",
  );
  buf.writeln(
    "/// used by `MockWorkoutRepository` so unit tests do not need to load assets.",
  );
  buf.writeln("///");
  buf.writeln("/// To regenerate after editing the JSON, run:");
  buf.writeln("///   dart run scripts/generate_food_catalog_seed.dart");
  buf.writeln("/// (or paste the entries manually from the JSON).");
  buf.writeln("///");
  buf.writeln("/// All entries have `isCatalog = true` and are read-only.");
  buf.writeln("///");
  buf.writeln(
    "/// Each entry's `groupId` resolves the JSON `category` string to the",
  );
  buf.writeln(
    "/// matching `FoodGroup.id` from `SeedData.defaultFoodGroups`. The",
  );
  buf.writeln(
    "/// `notes` field is `null` (the category is now expressed solely via",
  );
  buf.writeln(
    "/// the `groupId` FK). Keep the two in lockstep with the loader map in",
  );
  buf.writeln("/// `FoodCatalogLoader._categoryToGroupId`.");
  buf.writeln("class FoodCatalogSeed {");
  buf.writeln("  /// All ${foods.length} catalog foods.");
  buf.writeln(
    "  static final List<Food> sampleCatalogFoods = _buildCatalogFoods();",
  );
  buf.writeln("");
  buf.writeln("  static List<Food> _buildCatalogFoods() {");
  buf.writeln("    return <Food>[");

  // Group by category so the file reads top-to-bottom in the same
  // category order the JSON uses.
  final byCategory = <String, List<Map<String, dynamic>>>{};
  final order = <String>[];
  for (final f in foods) {
    final cat = f['category'] as String;
    if (!byCategory.containsKey(cat)) {
      byCategory[cat] = <Map<String, dynamic>>[];
      order.add(cat);
    }
    byCategory[cat]!.add(f);
  }

  for (final cat in order) {
    buf.writeln("      // ─── $cat ─${'─' * (60 - cat.length)}");
    for (final f in byCategory[cat]!) {
      buf.writeln(_renderFood(f));
    }
  }

  buf.writeln("    ];");
  buf.writeln("  }");
  buf.writeln("}");
  buf.writeln("");

  final outPath = 'lib/mock/food_catalog_seed.dart';
  File(outPath).writeAsStringSync(buf.toString());
  print(
    'Wrote $outPath with ${foods.length} foods across ${order.length} categories.',
  );
}
