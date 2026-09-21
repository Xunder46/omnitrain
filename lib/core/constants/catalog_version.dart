/// Catalog content version constants.
///
/// The bundled app-authored catalog (exercises, capability / muscle-group /
/// equipment relationships, and the food catalog) is versioned with an integer
/// that advances every time the bundled catalog changes. At app start, the
/// device compares its stored version against [bundledCatalogVersion]; when
/// the bundled version is newer, [CatalogRefreshService] walks the bundled
/// catalog and writes any new / changed entries to the device in place.
///
/// Versioning rules:
/// - Bumping [bundledCatalogVersion] by 1 is the ONLY step required for a
///   catalog change to reach existing users.
/// - Versions are monotonically increasing integers. There is no schema
///   compatibility story across non-contiguous jumps because the refresh
///   always reads the bundled catalog directly and writes it to the device.
/// - The first published version is `1`. When this refresh mechanism shipped,
///   we bumped to `2` so every existing install runs a one-time refresh on
///   next launch (catching everyone who installed at v1). When the bundled
///   demo routines shipped, we bumped to `3` so existing installs receive
///   them exactly once on next launch. When the food catalog expanded from 107
///   to 150 items (adding 43 new foods to close high-traffic gaps), we bumped
///   to `4` to deliver all new foods to existing users on next launch. When
///   the food catalog expanded from 150 to 166 items (adding 16 new foods to
///   close high-frequency gaps that force hand-entry: wings, ground chicken,
///   beef patty, roast beef deli,5cabbage, jalapeño, green onion, sourdough,
///   croissant, blueberry muffin, pepperoni pizza, vanilla ice cream,
///   California roll, half and half, whipped cream, diet cola), we bumped to
///   `5` to deliver all new foods to existing users on next launch.
///   When `beer_regular` and `red_wine` were retired (published with
///   `hidden: true` because the calorie-derivation model does not represent
///   alcohol — see `food_catalog_load_test.dart` S-007), we bumped to `8`
///   so existing installs receive the new hidden state on next launch.
///   When the HIT Full Body routine shipped and the muscle-group taxonomy was
///   completed (calves, forearms, adductors, neck, traps added; `muscle-arms`
///   and `muscle-legs` finally defined rather than only referenced; the
///   exercise→muscle mappings swept), we bumped to `9` so existing installs
///   pick up the new groups and corrected mappings on next launch.
///   When rest intervals were removed from HIT Full Body we bumped to `10`.
///   That bump only reaches the routine because the same change taught
///   `_refreshDemoRoutines` to rewrite an *untouched* demo's segments /
///   efforts / targets; before it, the refresh patched the template row
///   alone, so no version bump could ever deliver a change below it.
library;

const int bundledCatalogVersion = 10;

/// Entity-type identifiers used in the seed-entry tombstone markers.
///
/// Stored under the meta-box key `seed_entry_touched_<entityType>_<id>`.
/// Keep these strings stable — they live across app upgrades in the user's
/// Hive meta box.
class SeedEntryType {
  SeedEntryType._();

  /// A bundled `Exercise` (the [SeedData.sampleExercises] list).
  static const String exercise = 'exercise';

  /// A bundled food-catalog row (the [FoodCatalogSeed.sampleCatalogFoods]
  /// list, or equivalent JSON-backed asset).
  static const String foodCatalog = 'food_catalog';

  /// A bundled demo `WorkoutTemplate` (the
  /// [SeedData.sampleDemoRoutineBundles] list).
  static const String routineTemplate = 'routine_template';
}
