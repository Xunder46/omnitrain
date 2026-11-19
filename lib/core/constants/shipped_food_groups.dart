/// Ids of the nine food categories the app ships with — the same ids as
/// `SeedData.defaultFoodGroups` in `lib/mock/seed_data.dart` (state may not
/// import `lib/mock`; `test/shipped_food_groups_lock_test.dart` S-13701 asserts
/// the two lists stay equal).
///
/// A shipped category can be renamed but never deleted or archived: default
/// foods cannot be moved out of it (editing a default food makes a copy), so
/// removing it would only strand them under "Uncategorized" (plan 137).
const Set<String> shippedFoodGroupIds = {
  'food-group-proteins',
  'food-group-dairy',
  'food-group-grains-starches',
  'food-group-fruits',
  'food-group-vegetables',
  'food-group-nuts-seeds-fats',
  'food-group-snacks-prepared',
  'food-group-drinks',
  'food-group-condiments',
};

/// True when [id] names a category the app ships with.
bool isShippedFoodGroupId(String id) => shippedFoodGroupIds.contains(id);
