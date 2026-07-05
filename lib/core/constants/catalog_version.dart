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
///   next launch (catching everyone who installed at v1).
library;

const int bundledCatalogVersion = 2;

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
}