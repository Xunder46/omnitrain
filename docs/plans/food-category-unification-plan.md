# Feature: Food category unification — resolve `notes` to `groupId` (June 2026)

## Overview

Catalog rows in `assets/data/food_catalog.json` carry a human-readable
`category` string ("Proteins", "Dairy", …). Until now, the loader
stored this string on `Food.notes` (with `groupId = null`) because the
`FoodGroup` model was seeded later. The result was that the category
label lived in two places: the JSON at build time, the
`notes` field at runtime.

This change moves the category into a proper `group_id` FK at load
time. `notes` is freed to be the free-form user "Info" field.
A Hive one-shot migration backfills any pre-existing installs.

## Requirements

- The catalog loader resolves each `category` string to a
  `FoodGroup.id` from `SeedData.defaultFoodGroups` (case-insensitive).
- Unknown categories fall through to `groupId = null` (Ungrouped).
- `Food.notes` is `null` on freshly-loaded catalog rows.
- A one-shot idempotent Hive migration
  (`food_category_groupid_migrated_v1`) backfills `group_id` and
  clears `notes` on legacy rows in BOTH `_foodsBox` (library) and
  `_foodCatalogBox` (catalog).
- The same migration semantics are documented in
  `scripts/sqlite_schema.sql` for the future SQLite importer.
- The hardcoded `FoodCatalogSeed.sampleCatalogFoods` is regenerated
  to match (carries `groupId`, no `notes`).
- `addCatalogFoodToLibrary()` carries `groupId` across via
  `Food.copyWith` (which preserves it by default).

## Acceptance Criteria

- [x] `FoodCatalogLoader._foodFromCatalogMap` resolves category → groupId
      (case-insensitive) and sets `notes = null`.
- [x] `HiveWorkoutRepository` runs `_migrateFoodCategoryToGroupId()`
      on `initialize()`, guarded by
      `food_category_groupid_migrated_v1`. Idempotent on subsequent
      launches.
- [x] `MockWorkoutRepository.initialize()` seeds the catalog with
      `groupId` set (no `notes`).
- [x] `lib/mock/food_catalog_seed.dart` regenerated — all 107 entries
      have `groupId` and `notes = null`.
- [x] `scripts/generate_food_catalog_seed.dart` writes the new
      shape; mirrors the loader's category map.
- [x] `scripts/sqlite_schema.sql` documents the equivalent SQL
      migration for the future SQLite importer.
- [x] `addCatalogFoodToLibrary()` carries `groupId` across; stale
      "category preserved in notes" comments removed.
- [x] Tests: loader mapping (S-020), Hive migration
      match/non-match/idempotency (S-021, S-022), seed audit
      (extended `nutrition_data_audit_test.dart` and
      `food_catalog_load_test.dart`), catalog seeds have groupId,
      `addCatalogFoodToLibrary` copies groupId.
- [x] `docs/db_integration.md` and `docs/data_models.md` updated.

## Scenarios

### S-020: Loader maps category → groupId
- Trigger: `FoodCatalogLoader.parseCatalogJson()` or
  `loadFromAsset()` runs.
- Precondition: JSON has rows with `category: "Proteins"`, etc.
- Flow:
  1. Loader iterates entries.
  2. For each entry, looks up the lower-cased `category` in
     `_categoryToGroupId`.
  3. Resolved id goes on `Food.groupId`; `Food.notes` is `null`.
- Expected outcome: every catalog row carries a `groupId` matching
  one of the 9 default `FoodGroup` ids.

### S-021: Hive migration — match (resolves notes → groupId)
- Trigger: Existing install with `notes: 'Proteins'`, `group_id = null`.
- Flow:
  1. `initialize()` runs `_migrateFoodCategoryToGroupId()`.
  2. Lookup `nameToGroupId` from `_foodGroupsBox` (active groups).
  3. For each catalog/library row with non-null `notes` and null
     `group_id`, look up `nameToGroupId[notes.toLowerCase()]`.
  4. On match, set `group_id` and clear `notes`.
- Expected outcome: every legacy row carries a resolved `group_id`.

### S-022: Hive migration — non-match (left as-is)
- Trigger: Existing row with `notes: 'Mystery Bucket'` (not a
  default).
- Flow: as above, but `nameToGroupId['mystery bucket']` is `null`.
- Expected outcome: row stays `group_id = null`, `notes` preserved.

### Idempotency: marker prevents re-runs
- Trigger: Second `initialize()` call on the same install.
- Precondition: marker `food_category_groupid_migrated_v1` is `true`.
- Flow: migration returns immediately.
- Expected outcome: no writes, marker honoured.

### Library-row heuristic protects user notes
- Trigger: Library row with `notes: 'My recipe — do not touch'`.
- Flow: migration checks if `notes.toLowerCase()` is in the known
  category set. It isn't, so the row is left untouched.
- Expected outcome: user's notes preserved.

### User-rename is honoured
- Trigger: User renamed default "Proteins" → "Legumes" before the
  migration ran. Catalog row carries `notes: 'Proteins'`.
- Flow: lookup is built from the LIVE `_foodGroupsBox` (renamed
  group has name "Legumes"). `nameToGroupId['proteins']` is `null`.
- Expected outcome: catalog row stays `group_id = null` (Ungrouped)
  — the user's rename wins.

## Files Affected

- `lib/data/datasources/food_catalog_loader.dart` — `_categoryToGroupId`
  map; `_foodFromCatalogMap` sets `groupId`, clears `notes`.
- `lib/data/repositories/hive_workout_repository.dart` — new
  `_migrateFoodCategoryToGroupId()` method, marker key
  `food_category_groupid_migrated_v1`,
  `@visibleForTesting rerunCategoryMigrationForTest()` helper.
- `lib/data/repositories/mock_workout_repository.dart` — comment
  refresh in `addCatalogFoodToLibrary()` (no logic change; copyWith
  already carries groupId).
- `lib/mock/food_catalog_seed.dart` — regenerated via
  `scripts/generate_food_catalog_seed.dart`; all 107 entries carry
  `groupId` and no `notes`.
- `scripts/generate_food_catalog_seed.dart` (new) — generates the
  seed file from the JSON.
- `scripts/sqlite_schema.sql` — documents the equivalent SQL
  migration block for the future SQLite importer.
- `test/food_category_groupid_migration_test.dart` (new) —
  S-021/S-022, idempotency, library heuristic, user-rename,
  no-op-when-fresh.
- `test/food_catalog_load_test.dart` — new groups for S-020 mapping,
  catalog-seed audit, `addCatalogFoodToLibrary` copies groupId.
- `docs/db_integration.md` — Hive Migration Keys
  section + Food Library & Catalog → "Catalog category → groupId
  mapping" section.
- `docs/data_models.md` — `Food.notes` field row
  marked "Info" + new "Catalog category → groupId resolution"
  subsection.

## Progress

- [x] Phase 1 Data Layer (@dba) — loader updated, Hive migration
      added, seed regenerated, generator script, addCatalogFood
      comment refresh, sqlite narrative, doc updates, tests added
      (51 new passing tests across `food_catalog_load_test.dart` and
      `food_category_groupid_migration_test.dart`).
- [ ] Phase 2 Logic/UI (@developer) — out of scope for this iteration
      (the Food Library Browse View plan handles the screen-level
      switch from `f.notes` to `groupId`).

## Feedback
[Leave empty until a specialist or reviewer adds notes]
