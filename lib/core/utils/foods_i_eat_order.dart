/// The phone's Foods I Eat ordering, as a pure function.
///
/// The daily nutrition card and the wrist show the same list in the same order:
/// active categories alphabetically, "Uncategorized" last, and the foods inside
/// each section alphabetically. The card renders [foodsIEatSections] directly;
/// the watch applies the same rule to the food list the phone syncs
/// (`lib/watch/nutrition/watch_food_catalog.dart`), and
/// `test/watch_nutrition_quick_log_test.dart` (S-003) proves the two agree
/// against a shared fixture.
library;

import '../../data/models/models.dart';

/// The heading the card prints for foods whose category is missing from the
/// active set — never grouped, or archived since they were filed.
const String foodsIEatUncategorisedTitle = 'Uncategorized';

/// One section of the Foods I Eat list: the heading the card prints and the
/// foods under it, already in the order the card prints them.
class FoodsIEatSection {
  const FoodsIEatSection({required this.title, required this.foods});

  final String title;
  final List<Food> foods;
}

/// [foods] as the Foods I Eat card lays them out.
///
/// Foods whose [Food.groupId] names no active category bucket into the
/// [foodsIEatUncategorisedTitle] section rather than being dropped: a food the
/// user just deleted a category out from under is still a food they eat.
List<FoodsIEatSection> foodsIEatSections({
  required List<Food> foods,
  required List<FoodGroup> groups,
}) {
  final activeGroups = _sortedByName(groups, (group) => group.name);
  final activeGroupIds = {for (final group in activeGroups) group.id};

  final byGroupId = <String, List<Food>>{};
  for (final food in foods) {
    final groupId = food.groupId;
    final key = groupId != null && activeGroupIds.contains(groupId)
        ? groupId
        : '';
    byGroupId.putIfAbsent(key, () => []).add(food);
  }

  final sections = <FoodsIEatSection>[
    for (final group in activeGroups)
      if (byGroupId.containsKey(group.id))
        FoodsIEatSection(
          title: group.name,
          foods: _sortedByName(byGroupId[group.id]!, (food) => food.name),
        ),
  ];

  final uncategorised = byGroupId[''];
  if (uncategorised != null) {
    sections.add(
      FoodsIEatSection(
        title: foodsIEatUncategorisedTitle,
        foods: _sortedByName(uncategorised, (food) => food.name),
      ),
    );
  }

  return sections;
}

/// Case-insensitive alphabetical sort by a `name` accessor. Pure; does not
/// mutate the input list.
List<T> _sortedByName<T>(List<T> items, String Function(T) nameOf) {
  final copy = [...items];
  copy.sort((a, b) => compareFoodNames(nameOf(a), nameOf(b)));
  return copy;
}

/// The phone's name order: case-insensitive alphabetical, the tie-break the
/// card, the wrist and the synced list all use.
int compareFoodNames(String left, String right) =>
    left.toLowerCase().compareTo(right.toLowerCase());
