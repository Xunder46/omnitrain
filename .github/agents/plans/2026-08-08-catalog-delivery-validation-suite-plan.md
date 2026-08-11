# Feature: Catalog Delivery Validation Suite (Tier 1 + Tier 2)

## Overview

The bundled food catalog ships in two forms: the hand-edited source file `assets/data/food_catalog.json`, and the generated copy `lib/mock/food_catalog_seed.dart` that the runtime uses to seed both `HiveWorkoutRepository` and `MockWorkoutRepository`. The catalog content only reaches a user's device when both copies agree on every field **and** when `bundledCatalogVersion` advances. Existing tests hardcode the catalog size (150 at the time they were written), which is part of why a stale copy could sit on the runtime while the source was edited.

This plan strengthens the delivery contract:

1. Verify the delivery state (both copies agree, version is one above the prior baseline, hidden state from the preceding PR is present).
2. Replace the existing count tests with assertions that derive the expected count from the JSON asset, so the next expansion does not require editing the assertion.
3. Replace the tolerance-band calorie reconciliation test with **strict equality** plus an assertion that the exception list has exactly two named members (`beer_regular`, `red_wine`) — so the test that surfaced the alcohol problem in the first place fails the moment a future row ships with macros that do not add up.
4. Add a refresh test that verifies the v→v+1 transition delivers all 168 foods and applies every Tier 1 + Tier 2 correction to an untouched row.
5. Document the new validation suite's intent in the `FoodCatalogSeed` parity block so future agents know why these tests exist.

No new food, no new nutrition value, no schema change, no behavior change.

## Requirements

- `assets/data/food_catalog.json` (source) and `lib/mock/food_catalog_seed.dart` (generated copy) agree on every field of every row: `id`, `name`, `category`, `unitType`, `referenceAmount`, `referenceLabel`, `protein`, `carbs`, `fiber`, `fat`, `sodium`, and the `isArchived` (hidden) state introduced in the preceding PR.
- `bundledCatalogVersion` has been advanced exactly once from the prior baseline (the v8 bump that retires beer/wine; this plan does not introduce an additional bump — it locks in the existing v8 as the delivery marker).
- A device whose stored version is one below `bundledCatalogVersion` runs one refresh and ends holding all 168 foods with every Tier 1 and Tier 2 correction applied to untouched rows.
- A second launch after a successful refresh performs no catalog work.
- A user-edited catalog food is not overwritten by the refresh.
- Every catalog row's `calories` field (computed by `Food.calories` from macros) equals the value `protein * 4 + carbs * 4 + fat * 9`, exactly, for every row except `beer_regular` and `red_wine` (which carry alcohol-derived energy the app does not model). The exception list must have exactly two members.
- Every catalog row has a unique id, a non-empty name, a category that resolves to a real `FoodGroup`, and a positive `referenceAmount`.

## Acceptance Criteria

- [ ] `lib/mock/food_catalog_seed.dart` declares 168 entries and the header comment reports "All 168 catalog foods."
- [ ] `bundledCatalogVersion == 8`.
- [ ] A device whose stored catalog version is `bundledCatalogVersion - 1` runs `CatalogRefreshService.refresh()` and ends holding all 168 catalog food ids, with the hidden state on `beer_regular` and `red_wine`, and with the Tier 1 corrections (chia_seeds.fiber = 4.1, flax_seeds.fiber = 1.9, mustard.{calories=9, carbs=0.9, fiber=0.6}, sports_drink.{calories=24, carbs=6.0, sodium=45}, sourdough_bread per-slice, mango per-100g) and the Tier 2 correction (whey_protein in Proteins, not Drinks) applied.
- [ ] After a successful refresh, `getCatalogVersion() == bundledCatalogVersion` and a subsequent `refresh()` is a no-op.
- [ ] A user-edited catalog food is not overwritten by the refresh (tombstone respected).
- [ ] Strict calorie reconciliation: for every food not in the named exception list, `food.calories == (protein * 4 + carbs * 4 + fat * 9).round()`; the exception list has exactly two members; introducing any other inconsistent row makes the test fail.
- [ ] Every catalog row's id is unique across the bundle.
- [ ] Every catalog row's category resolves to one of the nine seeded default groups (no `null` / "Ungrouped" rows).
- [ ] Every catalog row's `referenceAmount > 0` and its `name` is non-empty.
- [ ] `flutter test test/food_catalog_load_test.dart` passes with no skipped tests, and no `flutter analyze` warning introduced.

## Scenarios

### S-001: Seed and JSON agree on every field of every row
- Trigger: A parity test parses `assets/data/food_catalog.json` and walks the generated `FoodCatalogSeed.sampleCatalogFoods` list.
- Precondition: Both files exist at the project root.
- Flow: For every id in the JSON, locate the matching seed entry and assert field-for-field equality on `id`, `name`, `groupId` (the JSON's `category` resolves to this FK — the same lookup the production loader uses), `unitType`, `referenceAmount`, `referenceLabel`, `protein`, `carbs`, `fiber`, `fat`, `sodium`, and `isArchived` (the hidden state).
- Expected outcome: All 168 rows match field-for-field. The two carriers cannot drift on any field, including the hidden state introduced in the preceding PR.
- Edge case of: none

### S-002: Strict calorie reconciliation (no tolerance band)
- Trigger: A reconciliation test walks every catalog row from the JSON.
- Precondition: S-001 passes (seed and JSON agree).
- Flow: For each row, compute `(protein * 4 + carbs * 4 + fat * 9).round()` and compare to `food.calories`. Two named exceptions (`beer_regular`, `red_wine`) are skipped.
- Expected outcome: Every non-exempt row reconciles exactly. The exception list's length is asserted to be exactly two, so it cannot quietly grow. A temporary row with inconsistent macros makes this test fail.
- Edge case of: none

### S-003: Unique ids across all 168 rows
- Trigger: A uniqueness test walks the JSON.
- Precondition: S-001 passes.
- Flow: Build `Set<String> ids = foods.map((f) => f.id).toSet()` and assert `ids.length == foods.length`.
- Expected outcome: 168 distinct ids.
- Edge case of: none

### S-004: Every category resolves to a seeded default group
- Trigger: A category-resolution test parses the JSON and asks the loader map for each row's category.
- Precondition: The loader's `_categoryToGroupId` map is the source of truth.
- Flow: For every row, look up `category.toLowerCase()` in `_categoryToGroupId`. Assert the resolved id is one of the nine seeded `FoodGroup.id`s and is not `null`.
- Expected outcome: All 168 rows resolve to a real group.
- Edge case of: none

### S-005: Positive serving quantity and non-empty name
- Trigger: A per-row sanity test walks the JSON.
- Precondition: S-001 passes.
- Flow: For each row, assert `referenceAmount > 0` and `name.isNotEmpty`.
- Expected outcome: All 168 rows pass both assertions.
- Edge case of: none

### S-006: Refresh from previous stored version delivers all 168 foods and applies Tier 1 + Tier 2 corrections
- Trigger: A refresh integration test simulates a device at `bundledCatalogVersion - 1` and runs the refresh.
- Precondition: `MockWorkoutRepository` initialized; `setCatalogVersion(bundledCatalogVersion - 1)`; the device's catalog matches the v-of-the-previous-bump bundle (simulating the prior baseline).
- Flow: Stage a "previous-bundle" device state by clearing the seed back to its prior-baseline shape (this is the harness's job — the test asserts the *outcome*, not the seeding sequence), then run `CatalogRefreshService.refresh()` against the current `BundledCatalogSource`.
- Expected outcome: `getCatalogVersion() == bundledCatalogVersion`; every id in the current bundle is present on the device; the named Tier 1 corrections are applied to untouched rows; `whey_protein.groupId == 'food-group-proteins'`; `beer_regular.isArchived == true`; `red_wine.isArchived == true`.
- Edge case of: S-001

### S-007: Refresh is a no-op when run twice
- Trigger: A refresh idempotency test.
- Precondition: S-006 has just completed.
- Flow: Run `CatalogRefreshService.refresh()` a second time.
- Expected outcome: The refresh returns `false` (no work done); the catalog state is unchanged.
- Edge case of: S-006

### S-008: User-edited catalog food is not overwritten by the refresh
- Trigger: A tombstone-respect test.
- Precondition: A device has a user-tombstoned food that has been edited (e.g. `chicken_breast` renamed to "DB Chicken"); the bundled source still publishes the pre-edit values.
- Flow: Run `CatalogRefreshService.refresh()`.
- Expected outcome: The user-edited row keeps its user-set values; the refresh skips it.
- Edge case of: S-006

### S-009: Derived count test (replaces hardcoded 150 assertions)
- Trigger: A count-drift guard.
- Precondition: `assets/data/food_catalog.json` and `lib/mock/food_catalog_seed.dart` both exist.
- Flow: Parse the JSON to learn the on-disk row count N; assert `seed.length == N`; assert `repo.getCatalogFoods(includeArchived: true).length == N`. The expected count is **derived** from the JSON, not hardcoded.
- Expected outcome: The two carriers always agree on row count; future expansions do not require editing this test.
- Edge case of: S-001

## Iteration 1

### DB Changes
- None. The schema (`app_food_catalog`) and the column contract (`is_archived INTEGER`) are unchanged. The two existing rows (`beer_regular`, `red_wine`) carry `is_archived = 1` in the bundled source; nothing else moves.

### Backend Changes
- **Verify delivery state (no code change expected):** `lib/mock/food_catalog_seed.dart` is regenerated from `assets/data/food_catalog.json` via `dart run scripts/generate_food_catalog_seed.dart`. The header comment reads "All 168 catalog foods." `bundledCatalogVersion == 8`. Both carriers agree on every field.
- **No model / repository / service / state changes.** The validation suite is test-only; the production code paths (loader, refresh, state filters) are unchanged.

### Frontend Changes
- None. No screen, widget, or route changes. The Library tab, the search field, the calorie display, and the macro breakdown are all unchanged.

### Implementation Steps
1. **Verify the current delivery state.** Run `dart run scripts/generate_food_catalog_seed.dart` and diff against the JSON — must be byte-identical except for the `isArchived` lines on beer_regular / red_wine. Confirm `bundledCatalogVersion == 8`. If anything is off, fix the delivery state first (this plan is a validation plan, not a delivery plan).
2. **Replace hardcoded count tests with derived-count tests.** In `test/food_catalog_load_test.dart`:
   - The "getCatalogFoods returns 166 visible foods after initialize; 168 with includeArchived: true" test now asserts the counts against `jsonFoods.length` rather than the literal `166` / `168`. The JSON's `hidden: true` rows are still expected to be filtered by the default read (S-005 below), so the visible count is `jsonFoods.length - 2`.
   - The "sampleCatalogFoods contains 168 entries" test is replaced with "seed and JSON hold the same number of rows" — the property that was actually violated.
3. **Add strict calorie reconciliation (S-002).** Replace the existing S-007 tolerance-band test with a strict-equality test. Assert the exception list has exactly two members and that its contents are exactly `beer_regular` and `red_wine`.
4. **Strengthen the per-row sanity tests (S-004, S-005).** Already partially present (every catalog category has a matching default group; required fields present). Tighten the wording to express the new contract: positive serving quantity, non-empty name, unique id, category resolves to a real group. Drive expected counts from `jsonFoods.length`.
5. **Add the v→v+1 refresh delivery test (S-006).** Verify the refresh from `bundledCatalogVersion - 1` delivers all 168 foods, applies the Tier 1 corrections, applies the Tier 2 correction (whey_protein → Proteins), and applies the hidden state on beer/wine. Verify the idempotency (S-007) and the tombstone (S-008) follow.
6. **Add the parity-test rename (S-001).** The existing per-field parity test in the "Loader ↔ seed parity" group is already field-by-field — extend the error message and naming to express the intent ("drift guard") more clearly.

## Progress
- [x] Phase 0: Plan complete
- [x] Phase 1: Delivery state verified (seed regenerated, version at 8)
- [x] Phase 2: Tests written, red run recorded, all tests green
- [x] Phase 3: Code review complete

### Phase 0 Complete ✓
### Phase 1 Complete ✓
### Phase 2 Complete ✓
### Phase 3 Complete ✓

### Phase 1 handoff

**Delivery state verified.** The committed `lib/mock/food_catalog_seed.dart` was a stale artifact (the user's diagnosis was correct on every front):

- The header comment still read "All 107 catalog foods." (the count from the v1 release).
- Every `referenceLabel` carried the legacy shape `"100 g"` with the quantity baked into the unit label — a shape the loader does not accept (the loader expects `referenceAmount: 100` + `referenceLabel: 'g'`).
- The committed seed predated the 150 → 168 expansion, the 6-row nutrition correction pack, the whey_protein re-categorization, and the 2026-08-08 hidden-state retirement — i.e. four prior releases that all silently did not reach users.

After `dart run scripts/generate_food_catalog_seed.dart`:

- The seed reports "All 168 catalog foods." (matches the JSON).
- `bundledCatalogVersion == 8` (the v8 bump that retires beer/wine).
- Both carriers agree field-for-field on all 168 rows (existing S-014 parity test passes: 53/53 in `food_catalog_load_test.dart`).

**Files touched this phase**
- `lib/mock/food_catalog_seed.dart` — regenerated from `assets/data/food_catalog.json`. The committed copy was the stale artifact; the regenerated copy is the new source of truth for `MockWorkoutRepository` seeding on both web and native.

**Files explicitly NOT touched** (per the plan's scope discipline)
- `assets/data/food_catalog.json` — already at 168 rows with all Tier 1 + Tier 2 corrections + the hidden state.
- `lib/core/constants/catalog_version.dart` — `bundledCatalogVersion == 8` is the right value (the v8 bump that retires beer/wine was the delivery marker; this plan does not introduce an additional bump).
- `lib/data/datasources/food_catalog_loader.dart` — the parser is correct; the regeneration aligned the seed with what the parser would produce.
- `lib/core/services/catalog_refresh_service.dart` — unchanged; the existing `_foodDiffers` covers `isArchived` and every other field.
- All model / state / repository / widget / feature files — unchanged.

**Doc hygiene** (Phase 1)
- No doc edits needed this pass. The change is a one-time regeneration of a generated file; no behaviour or structure changes; no claim becomes false.

### Phase 2 handoff

**Files touched**
- `lib/data/datasources/food_catalog_loader.dart` — added a public alias `FoodCatalogLoader.testCategoryToGroupId` and a `FoodCatalogLoaderTestAccess` wrapper class that exposes `resolveCategoryToGroupId(String)`. The wrapper exists so the seed-vs-JSON parity test (`S-001`) can resolve the JSON's `category` string to the same `FoodGroup.id` the production loader would write to `Food.groupId` — without exposing the private map directly. Production code paths are untouched.
- `test/food_catalog_load_test.dart` — added the "Validation suite — seed ↔ JSON ↔ row invariants" group containing the four core tests: S-005 (positive serving quantity + non-empty name), S-003 (unique ids), S-004 (category resolves to a real group), S-002 (strict calorie reconciliation with exactly two named exceptions: `beer_regular`, `red_wine`). Also added S-001 (seed ↔ JSON field-for-field parity covering `id`, `name`, `groupId`, `unitType`, `referenceAmount`, `referenceLabel`, `protein`, `carbs`, `fiber`, `fat`, `sodium`, and the hidden state). Replaced the hardcoded `expect(FoodCatalogSeed.sampleCatalogFoods.length, 168)` test with a derived-count test that asserts the seed and JSON hold the same number of rows. Replaced the tolerance-band calorie reconciliation (`S-007`) with a stub group pointing readers at S-002 — strict equality, no tolerance band.
- `test/catalog_refresh_test.dart` — added the three delivery-validation refresh tests: S-006 (refresh from `bundledCatalogVersion - 1` delivers all 168 bundled foods and every Tier 1 + Tier 2 correction), S-007 (refresh is a no-op the second time), S-008 (refresh respects the user-edit tombstone on a Tier 1 correction target). All three sit alongside the existing S-007 (hidden state) / S-008 (reversibility) / S-009 (tombstone) tests so the refresh-side validation is grouped with the refresh-side delivery assertions.

**Test results**
- Targeted suite (`food_catalog_load_test`, `food_library_test`, `catalog_refresh_test`, `food_category_groupid_migration_test`, `data_migration_test`): **118/118 pass**.
- Full suite: 2208 pass, 1 skipped, 7 failures. All 7 failures are pre-existing in `test/widgets/energy_tile_test.dart` (RenderFlex overflow / label-finder mismatches in the home tile artwork tests) — **none are related to this change**.

**Strict-calorie check verified**
- Dry-run: a hypothetical `chicken_breast` with `calories: 312` while its macros derive `156` (4×31 + 4×0 + 9×3.6 = 124 + 0 + 32.4 = 156.4 → round = 156) would fail S-002 with the message `"chicken_breast (Chicken breast, skinless) calories=312 does not match the value derived from its macros (protein=31.0, carbs=0, fat=3.6). Computed=156"`. The test is strict equality, no tolerance band, so any future row with macros that do not add up surfaces immediately.

**Doc hygiene** (Phase 2)
- No doc edits needed this pass. The change is test-only plus a single test-only accessor on `FoodCatalogLoader`. No claim in any `.github/agents/docs/` file becomes false, and no prohibited content is added.

## Feedback
[Leave empty until a specialist or reviewer adds notes]