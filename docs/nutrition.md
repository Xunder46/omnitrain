# Nutrition — Feature Documentation

**Scope.** The nutrition feature: daily food and water logging, the food library
and the shipped food catalog, daily nutrition targets, the full-history trend with
its adherence target line, and the first-run primer. Covers the screens in
`lib/features/nutrition/`, their state owners (`NutritionState`,
`FoodLibraryState`, `NutritionPrimerState`), the nutrition models in
`lib/data/models/models.dart`, and the nutrition outputs of
`StatsProgressService`.

Not this document: the Stats screen's Fuel row is a Stats surface (its value type
is in [Data Models](data_models.md#fuelsummary), its row in
[Stats Screen](stats_screen.md)); the persistence contract and catalog versioning
are in [DB Integration](db_integration.md); the feature's widgets are catalogued
in [Nutrition Widgets](widget_catalog/nutrition_widgets.md).

---

## Overview

Nutrition is the intake half of the app, and it is deliberately shallow: log food
and water for a day, keep a library of the foods actually eaten, set a daily
target, and look back at the trend. Nothing in the feature computes a plan or
gives advice.

Two invariants run through everything below.

**A logged food is a snapshot, not a reference.** `ConsumedFood` copies the source
food's macros and reference amount at log time, so editing or deleting the source
food never rewrites an already-logged day. Every nutrition figure that looks
backwards — the ring, the trend, the Fuel row — reads those snapshots, never the
live library row.

**Absence is never zero.** A day with nothing logged is skipped rather than
plotted as a zero point, and a window with nothing logged reports nothing rather
than an average of zeros. A gap in a trend line means no data, not fasting.

---

## Entry points and navigation

```
HomeScreen
  └── nutrition summary card ──────→ NutritionScreen
                                        ├── target action ──→ NutritionTargetScreen
                                        ├── primer help ────→ the primer sheet (reopen, no state change)
                                        └── library action ─→ AddFoodScreen
StatsScreen
  └── Fuel row ────────────────────→ NutritionTrendScreen
```

`NutritionScreen` is the feature's home. The Stats screen's Fuel row is the only
entry to the full-history trend; nothing else constructs it.

---

## Screens

### `NutritionScreen`

Today's view, and the only screen that fires the feature's loads. It starts four
independent loads — today's target, today's consumed foods, today's water and the
food library — and none gates another, so a slow library does not delay the
calorie ring. The body renders a loading state while `NutritionState` reports
one.

It owns no computation: the ring, the macro split and the water control read
`NutritionState`'s derived totals.

The primer is a first-run overlay. Its help affordance reopens the primer
**without** marking it seen, so a dismissed primer stays dismissed on the next
visit — reopening is inspection, not a reset.

Verified by `test/nutrition_test.dart`, `test/nutrition_primer_test.dart`,
`test/home_nutrition_summary_card_test.dart`.

### `AddFoodScreen`

The library's editor, in three modes: the library itself, creating a new item, and
managing groups.

The catalog is read-only. Adding a catalog row **copies** it into the library; it
does not log it. Removing a library food that is already logged today removes
today's entry first, so the library and the day's log cannot disagree about a food
that no longer exists.

Group deletion refuses to strand a shipped food: moving a group's foods to the
ungrouped bucket would silently orphan a bundled catalog food, so that case raises
`FoodGroupHasBundledFoodsError` instead. Cancel and "move to uncategorised" are
distinct outcomes of the group dialog.

Verified by `test/food_library_test.dart`, `test/food_library_edit_test.dart`,
`test/food_library_state_delete_guard_test.dart`, `test/food_group_membership_test.dart`,
`test/my_foods_unification_test.dart`.

### `EditFoodScreen`

Edits a food's own values and its photograph. An edit to a catalog food
propagates to the personal library rows linked to it through the durable
`catalogId` linkage, and never to already-logged snapshots — history stays
frozen. Clearing the photograph clears the stored path; the file on disk is left
intact.

Verified by `test/food_library_edit_test.dart`, `test/food_form_shipped_photo_test.dart`,
`test/food_form_pick_saves_test.dart`, `test/food_photo_clear_legacy_edit_test.dart`.

### `NutritionTargetScreen`

Calories-only by design (decision D-3, scenario S-040). The form loads and saves
the calorie target and nothing else: stored protein, carbs and fat are ignored on
load and written back as zero. A target that is unset or not positive shows an
empty field rather than a zero, so "no target" and "a target of zero" cannot be
confused.

Verified by `test/nutrition_test.dart` (the calories-only group) and
`test/nutrition_target_button_test.dart`.

### `NutritionTrendScreen`

The full-history trend, reached from the Stats screen's Fuel row. It builds one
`StatsProgressService` per load over the workout repository and computes both the
trend over the repository's whole food history and the adherence target line in
that same load. It is *not* scoped to the Fuel row's window or to the Stats
screen's selected training period.

The screen is theme-reactive through the settings state rather than through an
ambient theme lookup.

Verified by `test/nutrition_trend_screen_test.dart`.

---

## Widgets

The feature's presentation lives in `lib/features/nutrition/widgets/` and is
catalogued in [Nutrition Widgets](widget_catalog/nutrition_widgets.md). All of it
is presentation-only: no widget in that directory touches a repository or the
database, and all writes go through the state owners; the trend card's behaviour is
owned by this document.

Two widgets are platform-shaped rather than feature-shaped and are worth naming
here: `FoodThumbnail` has a conditional implementation behind a stub/IO split, so
the same call site works on web and native, and `NutritionTrendCard` is the trend
screen's entire body (its toggle, both charts, its empty chart and its legend).

---

## State

### `NutritionState`

The day's cache. Single-day and local-time, cleared on rollover; it exists so the
calorie ring can rebuild without re-querying on every keystroke. Its per-macro
totals accumulate as doubles and round once at the end, so a day of fractional
servings does not drift from the per-row figures. The field-by-field contract is
in [Nutrition State](state_management/nutrition_state.md).

Verified by `test/state_test.dart` (the `NutritionState` group) and
`test/nutrition_test.dart`.

### `FoodLibraryState`

Owns the library: its groups, its foods and the shipped catalog, each cached and
reloaded on demand. It takes an optional image storage service; when none is
injected (as in tests) no file work happens at all, and when one is, the state
self-heals a food whose stored photograph path no longer resolves and deletes a
photograph it has replaced.

It is also the feature's guard rail: `deleteFoodGroupReassigningFoods` is the only
group-deletion path, and it refuses the bundled-food case described above rather
than reassigning.

Verified by `test/food_library_state_test.dart`, `test/food_library_state_delete_guard_test.dart`,
`test/food_library_persistence_test.dart`, `test/food_orphan_category_integration_test.dart`.

### `NutritionPrimerState`

One persisted boolean, hydrated from preferences by its `init()`. A failed read
leaves the primer *unseen* rather than seen — the safe direction, since the cost
of showing it twice is lower than never showing it. Marking it seen is
idempotent, notifies once, and persists.

Verified by `test/nutrition_primer_test.dart`.

---

## Data

### Models

`NutritionTarget`, `Food`, `FoodGroup`, `FoodUnitType` and `ConsumedFood` live in
`lib/data/models/models.dart`; their fields and round-trip contracts are in
[Data Models](data_models.md#nutrition-models). The only invariant this document
adds is the snapshot rule from the overview: `ConsumedFood` is frozen at log time
and is never re-derived from its source food.

Verified by `test/models_test.dart`, `test/nutrition_data_audit_test.dart`.

### Foods I Eat ordering

`foodsIEatSections` in `lib/core/utils/foods_i_eat_order.dart` is the single
ordering rule for the "Foods I Eat" list: active groups in alphabetical order, the
uncategorised bucket last, and foods alphabetical within each group.

It is a shared rule rather than a screen-local sort because the same ordering
feeds the phone list and the watch quick-log. One rule, two surfaces, so a food
cannot be in a different place on the wrist than on the phone.

Verified by `test/watch_nutrition_quick_log_test.dart` (scenario S-003) and
`test/nutrition_test.dart`.

### Catalog loading

The shipped catalog's rows are identical on web and native, asserted by the
`FoodCatalogSeed parity` and `Loader ↔ seed parity (drift guard)` groups in
`test/food_catalog_load_test.dart`.

The catalog's human-readable category is resolved to a seeded group id at load
time; a category the seed map does not know falls through to no group rather than
inventing one. Pre-existing installs are backfilled once by the
`food_category_groupid_migrated_v1` Hive migration, whose equivalent SQL contract
is in `scripts/sqlite_schema.sql`.

Verified by `test/food_catalog_load_test.dart`, `test/food_category_groupid_migration_test.dart`,
`test/bundled_food_asset_contract_test.dart`.

### Photographs

`FoodPhotoService` is the single place a shipped food photograph's asset path is
built, and it is what keeps a library copy of a catalog food showing the shipped
image: a copy resolves its photograph through the catalog id it came from rather
than through its own id.

Verified by `test/food_photo_service_test.dart`, `test/bundled_food_photographs_test.dart`.

---

## Computation

### `computeNutritionTrend`

Sums one day's consumed-food snapshots into a `NutritionTrendPoint`: calories from
each row's own rounded figure, and macro grams scaled by the row's serving factor
and rounded **once** per day rather than per row. The carbs figure is total carbs,
not net carbs, so the trend's line colour matches the carbs the rest of the app
shows.

The `days` argument defaults to the service's trend constant; passing no limit
computes the whole history, which is what the trend screen does. Days with nothing
logged are skipped rather than zero-filled.

Verified by `test/stats_progress_test.dart` and `test/nutrition_trend_screen_test.dart`.

### `computeNutritionAdherence`

Companion to the trend, and it reuses it: the actuals are the same series computed
over the whole history, and the target line is built by walking every saved target
change and carrying each value forward to the next one. The line is therefore a
step function, and saving a new target adds a step — it never rewrites historical
actuals.

The target line is empty when no target has ever been saved or nothing has been
logged, and the screen omits the line in that case rather than drawing a flat
zero.

Verified by `test/stats_progress_test.dart`, `test/nutrition_trend_screen_test.dart`.

### `computeFuelSummary`

The only nutrition figure on the Stats screen. Its value type and its logged-days
averaging rule are documented in [Data Models](data_models.md#fuelsummary); its
row is documented in [Stats Screen](stats_screen.md). It averages over the
service's own window, never the Stats screen's selected training period.

Verified by `test/fuel_row_screen_test.dart` (S-1101–S-1108, the entry-point half
of S-1109, S-1111, S-1112, and S-1259–S-1261).

### Logged-day consistency

`lib/core/models/nutrition_consistency.dart` is the shared foundation the
nutrition signals read, and it owns one rule: a week block counts as consistent
only when at least `kConsistentWeekMinLoggedDays` distinct local calendar days
inside it carry a logged day. A day with more than one row counts once, a day
outside the block counts not at all, and a day with nothing logged is absent
rather than present as a zero — the window is never widened to reach the floor.

The block boundaries are calendar days, computed from the anchor day and never
from a `Duration`, so a DST transition cannot shift a boundary. The constants are
in [Constants Reference](constants_reference.md#nutrition-consistency-constants).

Verified by `test/nutrition_consistency_test.dart` (the block starts, the
month-end block, the 5-of-7 boundary and the logged-days-only mean).

---

## Persistence

The nutrition tables, the catalog's data versioning and the daily target rollover
contract are in [DB Integration](db_integration.md). The runtime is Hive on every
platform; `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` are the schema
contract, not a live persistence path.

---

## Related documentation

- [Data Models](data_models.md#nutrition-models) — nutrition model fields and round trips
- [Nutrition State](state_management/nutrition_state.md) — `NutritionState` field contract
- [Nutrition Widgets](widget_catalog/nutrition_widgets.md) — the feature's widgets
- [Home Screen & Nutrition Cards](widget_catalog/home_screen.md) — the home summary card
- [Stats Screen](stats_screen.md) — the Fuel row and its window
- [Navigation & Screens](navigation_and_screens.md) — where the screens sit in the app
- [DB Integration](db_integration.md) — schema, seed and catalog versioning

---

## Where these claims are verified

| Claim | Verified by |
|---|---|
| The screen's four loads are independent and the body has one loading state | `test/nutrition_test.dart` |
| The primer's help affordance reopens it without marking it seen | `test/nutrition_primer_test.dart` |
| The home summary card opens the feature | `test/home_nutrition_summary_card_test.dart` |
| Adding a catalog row copies it into the library instead of logging it | `test/nutrition_log_from_library_test.dart` |
| Group deletion refuses to strand a bundled food | `test/food_library_state_delete_guard_test.dart` |
| The target form is calories-only (D-3 / S-040) | `test/nutrition_test.dart`, `test/nutrition_target_button_test.dart` |
| The trend screen plots the repository's full food history | `test/nutrition_trend_screen_test.dart` |
| Foods I Eat ordering is shared with the watch quick-log | `test/watch_nutrition_quick_log_test.dart` |
| Catalog rows load identically on every platform | `test/food_catalog_load_test.dart`, `test/bundled_food_asset_contract_test.dart` |
| A library copy shows the shipped photograph | `test/food_photo_service_test.dart`, `test/bundled_food_photographs_test.dart` |
| Trend days are summed and rounded once per day, gaps skipped | `test/stats_progress_test.dart` |
| The target line steps at each saved target change | `test/stats_progress_test.dart`, `test/nutrition_trend_screen_test.dart` |
| The Fuel summary averages over logged days only | `test/fuel_row_screen_test.dart` |
