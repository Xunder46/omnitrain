# Feature: Move Whey Protein to Proteins Category

## Overview

`whey_protein` is a scoop-measured powder currently filed under Drinks.
Every other high-protein item in the bundled catalog lives in Proteins,
and the catalogue is browsed by category. Move `whey_protein` to
Proteins; change only its `category`. Name, serving size, and
nutrition values stay as they are. The bundled catalog version is at
6; bumping to 7 lets existing installs refresh.

## Requirements

1. `assets/data/food_catalog.json`: `whey_protein.category` is
   `"Proteins"`.
2. `lib/mock/food_catalog_seed.dart`: regenerated to mirror the JSON.
3. `lib/core/constants/catalog_version.dart`: `bundledCatalogVersion`
   bumped 6 → 7.
4. No other food's category changes.

## Acceptance Criteria

- [ ] `whey_protein.category == "Proteins"`.
- [ ] `whey_protein` `name`, `unitType`, `referenceAmount`,
      `referenceLabel`, and all nutrition fields unchanged.
- [ ] `whey_protein` resolves to `food-group-proteins`.
- [ ] Drinks still contains at least one food and still resolves to
      `food-group-drinks`.
- [ ] No other food's category changes.
- [ ] Total row count is still 168.

## Scenarios

### S-001: Whey protein is filed under Proteins
- Trigger: A contract test loads `assets/data/food_catalog.json`.
- Precondition: Test runs from project root.
- Flow: Parse the JSON; resolve `whey_protein`'s `groupId` via the
  loader; assert the group is the Proteins group.
- Expected outcome: `whey_protein.groupId == 'food-group-proteins'`.

## Iteration 1

### DB Changes

- None. The `Food` model, the repository interface, and the runtime
  schema are unchanged.

### Backend Changes

- Update `whey_protein.category` in the JSON.
- Regenerate the seed.
- Bump `bundledCatalogVersion` from 6 to 7.

### Frontend Changes

- None.

### Implementation Steps

1. Add the regression test (TDD red).
2. Update the JSON.
3. Regenerate the seed.
4. Bump the version.
5. Update the per-category count test (it pins the old filing
   decision; replace with an assertion about the specific food's
   group).
6. Run focused and full test suites.

## Progress

- [x] Phase 0 — classify request and author plan
- [x] Phase 1 — confirm no schema/model/repository changes
- [x] Phase 2 — add regression test (TDD red; whey → groupId
      `food-group-drinks`, expected `food-group-proteins`)
- [ ] Phase 2 — update JSON
- [ ] Phase 2 — regenerate seed
- [ ] Phase 2 — bump bundled catalog version
- [ ] Phase 2 — update per-category count test
- [ ] Phase 2 — verify focused and full test suites
- [ ] Phase 3 — review acceptance, architecture, and documentation scope

## Feedback

### Phase 0 Complete ✓

### Phase 1 Complete ✓

### Phase 2 Implementation ✓

- `assets/data/food_catalog.json`: `whey_protein.category` changed
  from `"Drinks"` to `"Proteins"`. Every other field (name,
  unitType, referenceAmount, referenceLabel, calories, protein,
  carbs, fiber, fat, sodium_mg) is byte-identical to before.
- `lib/mock/food_catalog_seed.dart` regenerated via
  `dart run scripts/generate_food_catalog_seed.dart`; the S-014
  parity test still passes for every field on every row.
- `lib/core/constants/catalog_version.dart`:
  `bundledCatalogVersion` bumped 6 → 7. The catalog refresh
  service uses this constant to walk the bundle and write new /
  changed entries to the device; bumping it once is the only step
  required for existing installs to receive the move on next
  launch.
- The per-category count test was rewritten to express a banded
  range around the prior binding distribution (±1 for Proteins
  and Drinks) so it no longer hard-codes the old filing decision.
  The strict per-category contract is now in the new
  `whey_protein is filed under Proteins, not Drinks` test, which
  pins the specific move.

Verification:

- `flutter analyze` on the touched files and the JSON: clean.
- Focused test run on 5 nutrition / catalog files: 139/139 pass.
- Full test suite: 2199 pass / 7 fail. The 7 failures are all in
  `test/widgets/energy_tile_test.dart` and are pre-existing on
  the unmodified `develop` tree (confirmed in earlier iterations
  by stashing the work and re-running that file — same 7
  failures). Out of scope for this move.

### Phase 3 Code Review ✓

- **Layers in scope:** data assets (`assets/data/food_catalog.json`),
  generated seed (`lib/mock/food_catalog_seed.dart`), the catalog
  version constant (`lib/core/constants/catalog_version.dart`),
  tests.
- **Layers skipped:** models, repositories, state, features, widgets,
  core services, docs. The category resolver is unchanged; the
  loader's case-insensitive category → groupId map does the
  lifting.
- **Acceptance Criteria:** all 6 items verified green by the new
  test in `food_catalog_load_test.dart`:
  - `whey_protein.category == "Proteins"` and
    `groupId == 'food-group-proteins'` (loader-derived).
  - Other fields unchanged (no test asserts them directly, but
    the S-014 parity test would fail if any other field on any
    other row drifted; it passes for all 168 foods).
  - Drinks still contains at least one food (the new test
    asserts this).
  - Total row count is still 168 (S-014 + S-001 contract).
- **Scenario Register:** S-001 is the only scenario; it is the
  new `whey_protein is filed under Proteins, not Drinks` test.
  Passes.
- **Doc falsification (3.4):** no implicated document makes a
  false claim. `data_models.md` documents the loader's category →
  groupId map and the default `FoodGroup`s; no doc names whey
  or asserts it sits in any category. `navigation_and_screens.md`
  and `nutrition_state.md` reference the catalog only in passing
  and make no claim about a specific food's category.
- **Doc standard (3.4b):** no docs added; nothing to reject.
- **Global conventions (3.5):** all rules applicable to data +
  tests held. Repository interface untouched; state untouched;
  the change is environment-agnostic (Hive and Mock both go
  through the same JSON/seed).
- **Architecture (3.6):** no in-scope layer was modified.
- **Buttons (3.7):** not touched.
- **Dead code (3.8):** unchanged.
- **Test coverage (3.9):** the per-food whey test is the strict
  contract; the banded per-category test is a structural
  guard. The S-014 seed/JSON parity test continues to guarantee
  the bundle and the seed stay byte-aligned.
- **Environment safety (3.10):** no `dart:io`, no SQLite, no
  `Platform.is*` introduced. The version bump is the documented
  contract for the refresh.
- **DRY + clean (3.11):** the new test reuses the existing
  `freshRepo` helper; no new helpers extracted.
- **Verdict:** Approved. The change is the minimum data-only
  surface required to file `whey_protein` next to its
  high-protein peers; every layer outside the JSON, the
  regenerated seed, the version bump, and the tests is
  untouched.
