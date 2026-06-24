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
/// [Food] models. Both the Hive-backed production repository and the in-memory
/// Mock repository go through this loader (Mock uses a hardcoded list generated
/// from the same JSON data to avoid asset I/O in unit tests).
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
  /// Exposed for testing and for the Mock repository's hardcoded list generator.
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

    // Macro values are stored as `double` on Food (S-001 — see
    // `.github/agents/plans/food-form-decimals-and-autofocus-plan.md`).
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
      isArchived: false,
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
}
