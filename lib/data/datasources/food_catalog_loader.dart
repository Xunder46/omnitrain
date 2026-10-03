import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

/// Loader for the bundled food catalog JSON asset.
///
/// The catalog is a fixed, read-only collection of common foods shipped with the
/// app. Users can browse, search, and copy catalog foods into their personal
/// library, but they cannot edit or delete catalog foods themselves.
///
/// This loader is the single point of truth for converting the JSON asset into
/// [Food] models. The Hive-backed repository loads the asset through
/// [loadFromAsset]; the Mock repository reads the generated
/// `lib/mock/food_catalog_seed.dart`.
class FoodCatalogLoader {
  /// Path to the catalog asset.
  static const String assetPath = 'assets/data/food_catalog.json';

  /// Load the catalog from the bundled asset and convert to [Food] models.
  ///
  /// All loaded foods are marked with `isCatalog = true` to distinguish them
  /// from user-owned library foods.
  ///
  /// Throws if the asset cannot be loaded or parsed.
  static Future<List<Food>> loadFromAsset() async {
    final raw = await rootBundle.loadString(assetPath);
    return parseCatalogJson(raw);
  }

  /// Parse a catalog JSON string into a list of [Food] models.
  ///
  /// Exposed for tests (`test/food_catalog_load_test.dart`).
  /// All loaded foods are marked with `isCatalog = true`.
  static List<Food> parseCatalogJson(String jsonString) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final foods = decoded['foods'] as List<dynamic>;

    return foods
        .map((entry) {
          final map = entry as Map<String, dynamic>;
          return _foodFromCatalogMap(map);
        })
        .toList(growable: false);
  }

  static Food _foodFromCatalogMap(Map<String, dynamic> map) {
    final id = map['id'] as String;
    final name = map['name'] as String;
    final category = map['category'] as String;
    final unitTypeStr = map['unitType'] as String;
    final referenceAmount = (map['referenceAmount'] as num).toDouble();
    final referenceLabel = map['referenceLabel'] as String;
    final protein = (map['protein'] as num?)?.toDouble() ?? 0;
    final carbs = (map['carbs'] as num?)?.toDouble() ?? 0;
    final fiber = (map['fiber'] as num?)?.toDouble();
    final fat = (map['fat'] as num?)?.toDouble() ?? 0;
    final sodium = (map['sodium_mg'] as num?)?.toDouble();

    // Validate unit type
    final unitType = unitTypeStr == 'count'
        ? FoodUnitType.count
        : FoodUnitType.grams;

    // Optional `hidden` flag. Absent or `false` means the row loads
    // visible; `true` means the row is published hidden so the
    // display paths (Library tab on `AddFoodScreen`, catalog search,
    // and the default `getCatalogFoods(includeArchived: false)`
    // reader) all skip it. The model uses `isArchived` for this
    // because the existing display / search / refresh-diff layers
    // already filter on it; the JSON's `hidden` is the authoring
    // vocabulary, `Food.isArchived` is the runtime vocabulary.
    final hidden = map['hidden'] == true;

    // Macro values are stored as `double` on Food (S-001 — see
    // `docs/plans/food-form-decimals-and-autofocus-plan.md`).
    // The catalog JSON's `protein` / `carbs` / `fat` values are integers
    // in the bundled v1 dataset; we pass them through without
    // rounding so the underlying precision is preserved if a future
    // catalog revision ships fractional grams. Calories are computed,
    // not stored, so the `calories` field in the JSON is
    // informational only.
    final now = DateTime.now().millisecondsSinceEpoch;

    // Resolve the catalog's human-readable category ("Proteins", "Dairy", …)
    // to the deterministic FoodGroup.id seeded in SeedData.defaultFoodGroups.
    // The map is case-insensitive and covers all 9 bundled categories.
    // Unknown categories fall through to `groupId: null` (Ungrouped).
    final groupId = _categoryToGroupId[category.toLowerCase()];

    return Food(
      id: id,
      name: name,
      groupId: groupId,
      unitType: unitType,
      referenceAmount: referenceAmount,
      referenceLabel: referenceLabel,
      isCatalog: true,
      protein: protein,
      carbs: carbs,
      fiber: fiber,
      fat: fat,
      sodium: sodium,
      isArchived: hidden,
      // Catalog rows no longer carry their category in notes; the
      // group_id is the single source of truth for the grouping.
      notes: null,
      createdAtMs: now,
      updatedAtMs: now,
    );
  }

  /// Static map from lower-cased category name (as it appears in the
  /// `assets/data/food_catalog.json` `category` field) to the
  /// deterministic `FoodGroup.id` defined in
  /// `SeedData.defaultFoodGroups`.
  ///
  /// Keep this list in lockstep with the 9 default groups: if a new
  /// category is added to the JSON, a corresponding default group
  /// must be added to `SeedData.defaultFoodGroups` and a row here.
  /// (The `food_catalog_load_test.dart` "every catalog category has
  /// a matching default FoodGroup" test enforces this.)
  static const Map<String, String> _categoryToGroupId = {
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

  /// Test-only escape hatch: the category → groupId map is private
  /// because the loader's runtime contract is "resolve on parse" —
  /// callers do not ask the loader for an id lookup at runtime. The
  /// seed-vs-JSON parity test (`food_catalog_load_test.dart` S-001)
  /// does need to resolve the JSON's `category` to the same
  /// FoodGroup.id the loader would write to `Food.groupId`, so the
  /// map is exposed under a `FoodCatalogLoaderTestAccess` alias to
  /// keep the symbol unambiguous in test code.
  static const Map<String, String> testCategoryToGroupId = _categoryToGroupId;
}

/// Convenience wrapper used by the seed-vs-JSON parity test
/// (`food_catalog_load_test.dart` S-001) to resolve a JSON category
/// to the `FoodGroup.id` the loader would write. Production code
/// must not depend on this — the loader resolves the category as
/// part of `parseCatalogJson`; runtime callers see `Food.groupId`.
class FoodCatalogLoaderTestAccess {
  FoodCatalogLoaderTestAccess._();

  /// Resolves a JSON `category` string (case-insensitive) to the
  /// `FoodGroup.id` the production loader would write.
  /// Returns `null` for unknown categories — same as the loader.
  static String? resolveCategoryToGroupId(String category) {
    return FoodCatalogLoader.testCategoryToGroupId[category.toLowerCase()];
  }
}
