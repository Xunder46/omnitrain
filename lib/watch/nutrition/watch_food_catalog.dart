/// The food list the phone sends down, in the shapes the wrist reasons about.
///
/// Plan: `.github/agents/plans/2026-07-13-12-e-watch-nutrition-quick-log-plan.md`,
/// scenarios S-001 to S-004.
///
/// The store keeps the phone's JSON as it arrived ([WatchFoodCatalogRecord]);
/// these types are the view the quick-log surface reads it through — a list the
/// user can scan and a portion that means something.
///
/// The order the list is shown in is the phone's, not the wrist's: the phone
/// owns the food catalog and the cut of it the user eats, and
/// `lib/core/utils/foods_i_eat_order.dart` is where that rule lives for the
/// phone. [deriveWatchFoodList] applies the same rule to the synced rows, then
/// lifts what the wrist itself logged most recently to the front — the same
/// shape the fallback exercise list uses (`watch_fallback_list.dart`), so the
/// two offline lists behave alike.
library;

import '../session/watch_records.dart';

/// One food the wrist may quick-log. A serving is the food's reference amount,
/// which is why a portion is a number of servings.
class WatchFood {
  const WatchFood({
    required this.foodId,
    required this.name,
    required this.referenceAmount,
    required this.referenceLabel,
    required this.caloriesPerServing,
    required this.defaultServings,
    this.categoryId,
  });

  factory WatchFood.fromJson(Map<String, Object?> json) => WatchFood(
    foodId: json['foodId']! as String,
    name: json['name']! as String,
    categoryId: json['categoryId'] as String?,
    referenceAmount: (json['referenceAmount']! as num).toDouble(),
    referenceLabel: json['referenceLabel']! as String,
    caloriesPerServing: (json['caloriesPerServing']! as num).toDouble(),
    defaultServings: (json['defaultServings']! as num).toDouble(),
  );

  final String foodId;
  final String name;

  /// The phone's category for this food, or null when the phone groups it
  /// under nothing (its category was archived, or it never had one).
  final String? categoryId;

  final double referenceAmount;
  final String referenceLabel;

  /// What one serving costs, in kcal.
  final double caloriesPerServing;

  /// The portion the phone pre-fills: the amount the user logged last, in
  /// servings.
  final double defaultServings;

  /// The kcal in [servings] of this food, in the phone's own arithmetic.
  int caloriesAt(double servings) => (caloriesPerServing * servings).round();

  Map<String, Object?> toJson() => {
    'foodId': foodId,
    'name': name,
    'categoryId': categoryId,
    'referenceAmount': referenceAmount,
    'referenceLabel': referenceLabel,
    'caloriesPerServing': caloriesPerServing,
    'defaultServings': defaultServings,
  };

  @override
  String toString() => 'WatchFood($foodId: $name)';
}

/// One of the user's active food categories, as the phone named it.
class WatchFoodCategory {
  const WatchFoodCategory({required this.categoryId, required this.name});

  factory WatchFoodCategory.fromJson(Map<String, Object?> json) =>
      WatchFoodCategory(
        categoryId: json['categoryId']! as String,
        name: json['name']! as String,
      );

  final String categoryId;
  final String name;

  Map<String, Object?> toJson() => {'categoryId': categoryId, 'name': name};
}

/// A `foods_down` message, parsed as the wrist reads it.
class WatchFoodsDown {
  const WatchFoodsDown({
    required this.generatedAt,
    required this.foods,
    required this.categories,
  });

  factory WatchFoodsDown.fromEnvelope(Map<String, Object?> envelope) =>
      WatchFoodsDown.fromPayload(asJsonObject(envelope['payload']));

  factory WatchFoodsDown.fromPayload(Map<String, Object?> payload) =>
      WatchFoodsDown(
        generatedAt: parseUtcIso(payload['generatedAt']),
        foods: [
          for (final food in payload['foods']! as List)
            WatchFood.fromJson(asJsonObject(food)),
        ],
        categories: [
          for (final category in payload['categories']! as List)
            WatchFoodCategory.fromJson(asJsonObject(category)),
        ],
      );

  /// The catalog as the store kept it, which is the message's payload.
  factory WatchFoodsDown.fromCatalog(WatchFoodCatalogRecord catalog) =>
      WatchFoodsDown.fromPayload({
        'generatedAt': utcIso(catalog.generatedAt),
        'foods': catalog.foods,
        'categories': catalog.categories,
      });

  /// When the phone generated this list.
  final DateTime generatedAt;

  final List<WatchFood> foods;
  final List<WatchFoodCategory> categories;
}

/// The wrist's list: the phone's Foods I Eat order, with what the wrist logged
/// recently lifted to the front.
///
/// The base order is the phone's own — categories alphabetically, foods the
/// phone files under nothing last, foods alphabetically inside each — so a user
/// who never quick-logs anything on the wrist sees the list the phone shows
/// them. [recentFoodIds] is the wrist's own usage, newest first; ids the synced
/// list does not know are skipped, because a food deleted on the phone is not a
/// food the wrist can log.
List<WatchFood> deriveWatchFoodList({
  required List<WatchFood> foods,
  required List<WatchFoodCategory> categories,
  required List<String> recentFoodIds,
}) {
  final categoryNames = {
    for (final category in categories) category.categoryId: category.name,
  };

  String? sectionOf(WatchFood food) {
    final categoryId = food.categoryId;
    return categoryId == null ? null : categoryNames[categoryId];
  }

  final ordered = [...foods]
    ..sort((a, b) {
      final bySection = _compareSections(sectionOf(a), sectionOf(b));
      if (bySection != 0) return bySection;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  final byId = {for (final food in foods) food.foodId: food};
  final seen = <String>{};

  final recents = <WatchFood>[];
  for (final foodId in recentFoodIds) {
    final food = byId[foodId];
    if (food != null && seen.add(foodId)) recents.add(food);
  }

  return List.unmodifiable([
    ...recents,
    for (final food in ordered)
      if (seen.add(food.foodId)) food,
  ]);
}

/// Categories alphabetically, and a food the phone files under nothing after
/// every food it files somewhere — the phone prints that group last
/// (`foodsIEatSections`), so the wrist lists it last too.
int _compareSections(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}
