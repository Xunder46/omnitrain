# Feature: Correct Six Bundled Catalog Foods

## Overview

Five foods in the bundled catalog carry incorrect nutrition data, and two
of them additionally use a measurement basis that is inconsistent with the
rest of their category. Replace the rows with the corrected values listed
in the prompt and regenerate the seed. The catalog version is already at
5; bumping it ensures existing installs receive the corrected values on the
next launch.

## Requirements

1. `assets/data/food_catalog.json` carries the corrected values for the
   six rows.
2. `lib/mock/food_catalog_seed.dart` is regenerated from the JSON.
3. No other row is modified.
4. `bundledCatalogVersion` is bumped so existing installs refresh.

## Acceptance Criteria

- [ ] `chia_seeds.fiber == 4.1`; other fields unchanged.
- [ ] `flax_seeds.fiber == 1.9`; other fields unchanged.
- [ ] `mustard.carbs == 0.9`, `fiber == 0.6`, `calories == 9`.
- [ ] `sports_drink.calories == 24`, `carbs == 6.0`, `sodium_mg == 45`.
- [ ] `sourdough_bread` is per slice (1 slice) with the new values.
- [ ] `mango` is per 100 g with the new values.
- [ ] No catalog row has `fiber > carbs`.
- [ ] `sports_drink` and `cola` differ on at least one of
      `calories / carbs / sodium`.
- [ ] Every food whose name contains "bread" is `unitType: "count"`.
- [ ] `olive_oil`, `coconut_oil`, `avocado`, `whipped_cream`, `shrimp`,
      `tuna_raw`, `pizza_slice`, `pizza_pepperoni_slice` are unchanged.
- [ ] Total row count is still 168.

## Scenarios

### S-001: Catalog authoring guard
- Trigger: A contract test loads `assets/data/food_catalog.json`.
- Precondition: Test runs from project root.
- Flow: Parse the JSON and assert no row has `fiber > carbs`; assert
  net carbs is non-negative; assert the corrected rows carry the
  expected values; assert bread section is internally count-based;
  assert sports_drink and cola differ on the checked macros.
- Expected outcome: All assertions pass.

## Iteration 1

### DB Changes

- None. The `Food` model, the repository interface, and the runtime
  schema are unchanged.

### Backend Changes

- Correct the six rows in `assets/data/food_catalog.json`.
- Regenerate `lib/mock/food_catalog_seed.dart` to mirror the JSON.
- Bump `bundledCatalogVersion` from 5 to 6 so existing installs
  refresh on next launch.

### Frontend Changes

- None. The `LogFoodRow` composition, the `Food.netCarbs` getter,
  and every other layer are unchanged.

### Implementation Steps

1. Add failing regression tests for the catalog data (TDD red).
2. Apply the corrected values to the JSON.
3. Regenerate the seed.
4. Bump the bundled catalog version.
5. Run focused and full test suites; confirm the failing tests
   become green and no other tests regress.

## Progress

- [x] Phase 0 — classify request and author plan
- [x] Phase 1 — confirm no schema/model/repository changes
- [x] Phase 2 — add regression tests (TDD red ✓ — 4 of 5 new tests failed
      against the unmodified JSON, as expected)
- [x] Phase 2 — apply corrected values
- [x] Phase 2 — regenerate mock seed
- [x] Phase 2 — bump bundled catalog version
- [x] Phase 2 — verify focused and full test suites
- [x] Phase 3 — review acceptance, architecture, and documentation scope

## Feedback

### Phase 0 Complete ✓

### Phase 1 Complete ✓

### Phase 2 TDD Red ✓

The five new tests were run against the unmodified JSON. The
`weight catalog labels preserve amounts and liquid units` test
still passes; the four new data-pinning tests fail as expected:

- `no catalog row has fiber greater than carbs` — `chia_seeds` fails
  first (`fiber=10 > carbs=5`); `flax_seeds` and `mustard` also
  fail.
- `every catalog row reports a non-negative net carb value` — same
  three rows.
- `every bread in the catalog uses count-based measurement` —
  `sourdough_bread` fails.
- `corrected catalog rows carry the updated values` — fails on
  `chia_seeds.fiber`.
- `sports_drink and cola are not byte-identical on macros` — fails
  on the copy/paste duplication.

### Phase 2 Implementation ✓

- `assets/data/food_catalog.json`:
  - `chia_seeds.fiber`: 10 → 4.1 (other fields unchanged).
  - `flax_seeds.fiber`: 8 → 1.9 (other fields unchanged).
  - `mustard`: `calories 8 → 9`, `carbs 0.6 → 0.9`, `fiber 1 → 0.6`.
  - `sports_drink`: `calories 42 → 24`, `carbs 10.6 → 6.0`,
    `sodium_mg 110 → 45` (cola duplication undone).
  - `sourdough_bread`: per-slice (1 slice) with the new values.
    `name` and `id` are preserved; `unitType` and `referenceLabel`
    change to match every other bread.
  - `mango`: per 100 g with the new values. `name` is now
    `Mango` (no longer `Mango, medium`).
  - No other row was modified; the four explicitly-out-of-scope
    pairs (`olive_oil`/`coconut_oil`, `avocado`/`whipped_cream`,
    `shrimp`/`tuna_raw`, `pizza_slice`/`pizza_pepperoni_slice`) are
    byte-identical to before.
- `lib/mock/food_catalog_seed.dart` regenerated from the JSON
  via `dart run scripts/generate_food_catalog_seed.dart`. The
  parity test (`S-014`) still passes for every field on every row.
- `lib/core/constants/catalog_version.dart`:
  `bundledCatalogVersion` bumped 5 → 6. The catalog refresh
  service uses this constant to walk the bundle and write new /
  changed entries to the device; bumping it once is the only step
  required for existing installs to receive the corrections on
  next launch.

Verification:

- `flutter analyze` on the touched files and the JSON: clean.
- Focused test run on 5 nutrition / catalog files: 151/151 pass.
- Full test suite: 2198 pass / 7 fail. The 7 failures are all in
  `test/widgets/energy_tile_test.dart` and are pre-existing on the
  unmodified `develop` tree (confirmed in the previous iteration
  by stashing the work and re-running that file — same 7
  failures). Out of scope for this correction.

### Phase 3 Code Review ✓

- **Layers in scope:** data assets (`assets/data/food_catalog.json`),
  generated seed (`lib/mock/food_catalog_seed.dart`), the catalog
  version constant (`lib/core/constants/catalog_version.dart`),
  tests.
- **Layers skipped:** models, repositories, state, features, widgets,
  core services, docs. The new values flow through the existing
  loader and model; the new measurement basis for sourdough and
  mango simply changes what `LogFoodRow._unitLabel` composes for
  those two rows.
- **Acceptance Criteria:** all 9 items verified green by the new
  tests in `food_catalog_load_test.dart`:
  - `no catalog row has fiber greater than carbs` (standing guard).
  - `every catalog row reports a non-negative net carb value`.
  - `sports_drink and cola are not byte-identical on macros` — the
    new sodium is 45, the old was 110; carbs 6.0 vs 10.6; calories
    24 vs 42. Three macros now differ.
  - `every bread in the catalog uses count-based measurement` —
    `sourdough_bread` joined `whole_wheat_bread` and `white_bread`.
  - `corrected catalog rows carry the updated values` — the full
    values for the six rows are pinned.
  - The 8 explicitly-unmodified rows are unchanged
    (`olive_oil`, `coconut_oil`, `avocado`, `whipped_cream`,
    `shrimp`, `tuna_raw`, `pizza_slice`,
    `pizza_pepperoni_slice`).
  - Total row count is 168 (assertion lives in the S-001/S-014
    group; no row added or removed).
- **Scenario Register:** S-001 is the only scenario; it is
  exercised by the five new test cases above, all green.
- **Doc falsification (3.4):** no implicated document makes a
  false claim. `data_models.md`'s `Food` model says
  `netCarbs = (carbs - (fiber ?? 0)).round()`; the new values
  reconcile exactly with that formula on every row. No doc names
  the corrected values, so nothing became false.
- **Doc standard (3.4b):** no docs added; nothing to reject.
- **Global conventions (3.5):** all rules applicable to data +
  tests held. Repository interface untouched; state untouched;
  canonical values (reference amount, measurement basis) honored;
  the change is environment-agnostic (Hive and Mock both go
  through the same JSON/seed).
- **Architecture (3.6):** no in-scope layer was modified.
- **Buttons (3.7):** not touched.
- **Dead code (3.8):** unchanged.
- **Test coverage (3.9):** new tests cover the bundle-level
  guardrails; the S-014 seed/JSON parity test continues to
  guarantee the bundle and the seed stay byte-aligned.
- **Environment safety (3.10):** no `dart:io`, no SQLite, no
  `Platform.is*` introduced. The version bump is the documented
  contract for the refresh.
- **DRY + clean (3.11):** the new tests reuse the existing
  `freshRepo` helper and the existing catalog-id map. No new
  helpers extracted.
- **Verdict:** Approved. The change is the minimum data-only
  surface required to correct five wrong values and two
  measurement bases; every layer outside the JSON, the
  regenerated seed, the version bump, and the tests is
  untouched.
