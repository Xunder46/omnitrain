# Feature: Prepopulate default food categories from the catalog

## Overview

The bundled food catalog (107 foods) carries a `category` string on every
entry — one of 9 values: Proteins, Dairy, Grains & Starches, Fruits,
Vegetables, Nuts/Seeds & Fats, Snacks & Prepared, Drinks, Condiments.

Until now these were display-only labels stored on `Food.notes` for catalog
rows. The user's own library was built from a blank slate, with no
predefined `FoodGroup` rows to drop foods into.

This change seeds 9 default `FoodGroup` records on app start so the
Categories tab is immediately usable. The names match the 9 catalog
categories verbatim, so a future cross-reference (auto-assigning
catalog foods to a group) is a one-step name lookup.

## Requirements

- On fresh install, populate `_foodGroups` (Mock) / `food_groups` Hive box
  with 9 default groups whose names match the catalog categories.
- On existing installs, run a one-shot idempotent migration that
  backfills any missing defaults.
- The user can rename, archive, or delete any default group. Default
  provenance does not restrict the mutator paths.
- Defaults are not auto-applied to catalog foods (`groupId` remains
  `null` on `Food.notes`-carried catalog rows). The user manually picks
  a group when adding a catalog food to the library.
- The bundle that ships with the app (catalog JSON, group list) stays
  in lockstep: if a category is added to the catalog JSON, a
  corresponding default group must be added to `SeedData.defaultFoodGroups`
  (enforced by a test).

## Acceptance Criteria

- [x] `MockWorkoutRepository.initialize()` loads all 9 default groups.
- [x] `HiveWorkoutRepository.initialize()` seeds all 9 defaults on fresh
      install; on existing installs the `_seedDefaultFoodGroups()`
      migration backfills any missing entries and is a no-op on subsequent
      launches (guarded by `default_food_groups_seeded_v1`).
- [x] Every catalog category has a matching default group
      (test-enforced in `food_catalog_load_test.dart`).
- [x] Default groups have stable, deterministic ids
      (`food-group-proteins`, `food-group-dairy`, …) so the Hive migration
      is idempotent.
- [x] A user-created group with the same name as a default is preserved;
      the seed does not overwrite it (idempotency rule).
- [x] The user can archive any default group.

## Scenarios

### S-001: Fresh install seeds 9 default food groups
- Trigger: App initialization on a brand-new install.
- Precondition: `food_groups` Hive box is empty; meta key
  `default_food_groups_seeded_v1` is absent.
- Flow:
  1. `MockWorkoutRepository.initialize()` populates `_foodGroups` from
     `SeedData.defaultFoodGroups`.
  2. `HiveWorkoutRepository.initialize()` runs `_seedDefaultFoodGroups()`,
     writes the 9 rows to `food_groups`, and sets the meta key.
- Expected outcome: `getFoodGroups()` returns 9 groups whose names match
  the 9 catalog categories verbatim.

### S-002: Existing install backfills only missing defaults
- Trigger: App initialization on a previously-installed device where
  `food_groups` already has 3 user-created groups (Proteins, My Soups,
  Snacks) and the meta key is absent.
- Precondition: `default_food_groups_seeded_v1` is null/false.
- Flow:
  1. Migration snapshots existing group names (Proteins, My Soups, Snacks).
  2. For each of the 9 defaults, skip if a row with the stable id exists
     OR a row with the same name (case-insensitive) exists.
  3. The user-created "Proteins" group blocks the seed for
     `food-group-proteins`. The other 8 defaults (Dairy, Fruits,
     Vegetables, …) are written.
  4. Meta key is set.
- Expected outcome: `getFoodGroups()` returns 11 rows: 3 user groups +
  8 newly-seeded defaults. The user's "Proteins" row is preserved as-is.

### S-003: Migration is a no-op on second run
- Trigger: App initialization on a device that has already run the
  migration.
- Precondition: `default_food_groups_seeded_v1 == true`.
- Flow: Migration reads the meta key, returns immediately.
- Expected outcome: No writes. Defaults unchanged.

### S-004: User can archive a default group
- Trigger: User taps the trash icon on the Proteins row in the
  Categories tab.
- Precondition: Default Proteins group exists with
  id = `food-group-proteins`.
- Flow: `archiveFoodGroup('food-group-proteins')` runs. The mutator path
  is unaware of seed provenance.
- Expected outcome: Row is archived. `getFoodGroups()` (active) no longer
  returns it; `getFoodGroups(includeArchived: true)` does. The id is
  preserved.

## Data Asset

The 9 default groups are defined in `SeedData.defaultFoodGroups` in
`lib/mock/seed_data.dart`. Names match the 9 `category` values in
`assets/data/food_catalog.json` (8 from the data, but the JSON actually
contains 9: Proteins, Dairy, Grains & Starches, Fruits, Vegetables,
Nuts, Seeds & Fats, Snacks & Prepared, Drinks, Condiments).

Stable ids:
- `food-group-proteins`
- `food-group-dairy`
- `food-group-grains-starches`
- `food-group-fruits`
- `food-group-vegetables`
- `food-group-nuts-seeds-fats`
- `food-group-snacks-prepared`
- `food-group-drinks`
- `food-group-condiments`

## Plan

### Phase 1: Data Layer (@dba)

1. **Add `defaultFoodGroups` to `SeedData`**: a static `List<FoodGroup>`
   with stable ids and timestamps.
2. **Wire into `MockWorkoutRepository.initialize()`**: after catalog
   load, populate `_foodGroups` from `SeedData.defaultFoodGroups`.
3. **Wire into `HiveWorkoutRepository.initialize()`**: new migration
   method `_seedDefaultFoodGroups()` guarded by
   `default_food_groups_seeded_v1`, called after `_seedFoodCatalog()`.
   Idempotency rules:
   - Skip if stable-id row already exists.
   - Skip if a row with the same name (case-insensitive) exists.
   - Otherwise insert.
4. **No new repository methods**: `getFoodGroups()` is the only reader;
   no mutator changes are needed (existing `archiveFoodGroup` and
   `updateFoodGroup` are provenance-agnostic).

### Phase 2: Unit Tests (@developer)

1. **Test**: every catalog category has a matching default group.
   - File: `test/food_catalog_load_test.dart` (new group appended)
2. **Test**: `MockWorkoutRepository.initialize()` seeds all 9 default
   groups.
3. **Test**: default food groups have stable, deterministic ids.
4. **Test**: default food groups are not archived and have no color.
5. **Test**: user can archive a default group (provenance-agnostic
   mutator path).

## Files Affected

- `lib/mock/seed_data.dart` — add `defaultFoodGroups`
- `lib/data/repositories/mock_workout_repository.dart` — populate
  `_foodGroups` from `SeedData.defaultFoodGroups` in `initialize()`
- `lib/data/repositories/hive_workout_repository.dart` — new migration
  method `_seedDefaultFoodGroups()` + meta key constant
- `test/food_catalog_load_test.dart` — 5 new tests
- `test/food_library_test.dart` — update 2 tests to be aware of seeded
  defaults (load `loadFoodGroups()` first when testing post-load state)
- `test/food_library_state_test.dart` — update 6 tests to call
  `loadFoodGroups()` and use unique group names ("My Proteins", etc.)
- `test/nutrition_test.dart` — update 3 tests: rename collision-prone
  group names to "Browse Proteins" / "Log Proteins"; archive defaults
  in the empty-library test; scroll into view in the LogFoodRow test

## Idempotency contract

The Hive migration uses **two** safety checks per default row:

1. **Stable-id check**: if `_foodGroupsBox.containsKey(group.id)` is
   `true`, the row is already populated (either by the seed itself or
   by a user action that wrote to that exact id). Skip.
2. **Name-collision check**: if any existing row in
   `_foodGroupsBox.values` has a name (case-insensitive) equal to the
   default's name, the user has already created a "Proteins" group.
   Skip the seed for that category — the user's row wins.

Both checks happen inside the same `for` loop, so the work is
O(N×M) where N=9 defaults and M=existing rows. Negligible cost on real
data.

## Progress

- [x] Phase 1 Data Layer (@dba) — SeedData added, Mock + Hive wired
- [x] Phase 2 Tests (@developer) — 5 new tests pass; full suite green
      (1317 passed, 5 pre-existing skips)

## Feedback
[Leave empty until a specialist or reviewer adds notes]
