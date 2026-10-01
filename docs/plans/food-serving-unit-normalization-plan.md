# Feature: Normalize Bundled Food Serving Units

## Overview

The bundled food catalog stores a serving quantity separately from its unit, but
weight-based rows currently repeat the quantity in `referenceLabel`. The
catalog source and generated mock seed will be corrected so the existing food
logging row composes one quantity and one unit without changing nutrition,
identity, category, or scaling data. Regression tests will guard both catalog
authoring and the rendered serving line.

## Requirements

- Change only weight-based catalog `referenceLabel` values: `100 g` → `g`,
  `100 ml` → `ml`, and `28 g` → `g` for `beef_jerky`.
- Preserve every weight row's `referenceAmount`, including `beef_jerky`'s 28.
- Leave every count-based catalog row byte-for-byte unchanged.
- Regenerate `lib/mock/food_catalog_seed.dart` from the normalized JSON.
- Add standing guards for digit-free weight and count unit labels.
- Pin rendered serving lines for a 100-gram catalog food and `beef_jerky`.
- Update the parser fixture and all test `Food` fixtures that model `100 g` as
  a unit label; do not change test expectations unrelated to this convention.
- Preserve nutrition scaling and totals when logging 150 g.

## Acceptance Criteria

- [ ] All 92 rows formerly labelled `100 g` carry `g`; each keeps
      `referenceAmount == 100`.
- [ ] All 12 rows formerly labelled `100 ml` carry `ml`; each keeps
      `referenceAmount == 100`.
- [ ] `beef_jerky` carries `g` and keeps `referenceAmount == 28`.
- [ ] No `count` catalog row changes.
- [ ] No nutrition, name, id, or category value changes.
- [ ] The logging row renders `100 g`, `28 g`, and `100 ml` exactly once per
      serving line for the corresponding catalog foods.
- [ ] Logging 150 g produces the same calorie and macro totals; the existing
      scaling contract remains green.
- [ ] Unit tests guard digit-free weight/count labels and parser/seed parity.

## Scenarios

### S-001: Catalog units render without duplicated quantities
- Trigger: A catalog food is loaded into the nutrition logging row.
- Precondition: The bundled catalog and generated mock seed are initialized.
- Flow: Render a 100-gram food and `beef_jerky`; inspect the serving text under
  each amount field.
- Expected outcome: The rows display `100 g` and `28 g` respectively, while a
  100-millilitre row displays `100 ml`; nutrition scaling is unchanged.
- Edge case of: none

## Iteration 1

### DB Changes

- None. No model, repository interface, runtime schema, or migration changes.

### Backend Changes

- Normalize `assets/data/food_catalog.json` as the authoritative bundled data.
- Regenerate `lib/mock/food_catalog_seed.dart` and verify JSON/seed parity.

### Frontend Changes

- None. The existing `LogFoodRow` composition is in scope only through a
  regression test; changing its display logic is explicitly out of scope.

### Implementation Steps

1. Add failing catalog-unit and serving-line regression tests.
2. Run the focused tests and record the expected red result.
3. Normalize the JSON and regenerate the mock seed.
4. Update stale `Food` fixtures across the test suite.
5. Run focused tests, the full suite, analyzer, and the review checklist.

## Progress

- [x] Phase 0 — classify request and author plan
- [x] Phase 1 — confirm no schema/model/repository changes
- [x] Phase 2 — add regression tests and record red run
- [x] Phase 2 — normalize catalog and generated seed
- [x] Phase 2 — update stale test fixtures
- [x] Phase 2 — verify focused and full test suites
- [x] Phase 3 — review acceptance, architecture, and documentation scope

## Feedback

### Phase 0 Complete ✓

### Phase 1 Complete ✓

### Phase 2 TDD Red ✓

The new catalog-unit and rendered-serving-line tests were run before the
catalog change. The focused run had 102 passing tests and 2 expected failures:
`chicken_breast` still loaded as `100 g`, and the logging row did not render
`100 g`/`28 g`/`100 ml` from the unchanged catalog seed.

### Phase 2 Implementation ✓

- `assets/data/food_catalog.json`: 93 `"100 g"` → `"g"`, 12 `"100 ml"` →
  `"ml"`, and `beef_jerky` `"28 g"` → `"g"`. Every weight row's
  `referenceAmount` is unchanged; every count row is byte-identical to
  before.
- `lib/mock/food_catalog_seed.dart` regenerated from the JSON via
  `dart run scripts/generate_food_catalog_seed.dart`; the S-014
  field-for-field parity test still passes.
- Stale test fixtures across `food_catalog_load_test.dart`,
  `header_standardization_test.dart`, `home_nutrition_summary_card_test.dart`,
  `nutrition_log_from_library_test.dart`, and `nutrition_test.dart` updated
  to the corrected `g`/`ml` convention. The loader fixture's `"100 g"` was
  changed to `"g"`.
- New tests guard the new convention:
  - `weight-based catalog units contain no digits` (105 foods).
  - `count-based catalog units are non-empty and digit-free`.
  - `weight catalog labels preserve amounts and liquid units` — pins
    `chicken_breast`, `beef_jerky`, and `orange_juice` end-to-end.
  - `LogFoodRow — log from library … catalog serving lines contain one
    quantity and unit` — renders `100 g`, `28 g`, `100 ml` from the catalog.
- The existing `S-001: log grams food at 150` group continues to assert
  150 g of chicken → 226/227 kcal; 1.5x scaling semantics are
  preserved.
- `flutter analyze` on the touched layers and the JSON: clean.
- Full test suite: 2193 pass / 7 fail. The 7 failures are all in
  `test/widgets/energy_tile_test.dart` and are pre-existing on the
  unmodified `develop` tree (confirmed by stashing this work and
  re-running that file on the baseline — same 7 failures). Out of
  scope for this normalization.

### Phase 3 Code Review ✓

- **Layers in scope:** data assets (`assets/data/food_catalog.json`),
  generated seed (`lib/mock/food_catalog_seed.dart`), tests.
- **Layers skipped:** models, repositories, state, features, widgets,
  core. The `LogFoodRow` rendering is unchanged — the bundle catalog
  change is what flipped the displayed line.
- **Acceptance Criteria:** all 6 items verified green. The bundle now
  carries 93 `g` / 12 `ml` weight labels; every `referenceAmount` is
  preserved; `beef_jerky` keeps 28; count rows are untouched; no
  nutrition / name / id / category value changed; 150 g of chicken
  still yields 226/227 kcal via the `S-001` group; the new widget
  test renders `100 g`, `28 g`, `100 ml` beneath the amount field for
  catalog rows.
- **Scenario Register:** S-001 mapped to the new
  `LogFoodRow — log from library (S-001 / S-008) catalog serving lines
  contain one quantity and unit` widget test, which passes.
- **Doc falsification (3.4):** `data_models.md` still describes the
  catalog `FoodUnitType` enum with `e.g. "per 100 g"` for the grams
  value and an example `FoodUnitType.count` of `"per 1 egg"` / `"per
  1 slice"`. The `per 1 X` examples remain correct; the `per 100 g`
  example is no longer representative of how the bundled catalog
  stores the label, but the `FoodUnitType` enum itself is a code
  constant that pre-dates this change. The example illustrates the
  *concept* of a per-100g food, not a specific row. No assertion in
  the doc claims the bundled catalog uses `"100 g"` as the label, so
  no claim became false. The same applies to `nutrition_state.md` —
  it documents state methods; no example labels there. No
  documents under the doc tree state the bundled `referenceLabel`
  convention for weight rows, so no doc needed to change. No
  prohibited content was added.
- **Doc standard (3.4b):** no docs were added; this change touches no
  Markdown under `docs/`.
- **Global conventions (3.5):** all rules applicable to data + tests
  held. Repository interface untouched; state untouched; canonical
  values (reference amount) preserved; the change is environment-
  agnostic (Hive and Mock both consume the JSON via the loader, and
  Mock via the regenerated seed).
- **Architecture (3.6):** no in-scope layer was modified.
- **Buttons (3.7):** not touched (no screen / widget changes).
- **Dead code (3.8):** the Phase 1 audit already flags `AppState`
  (`lib/state/app_state.dart`) for removal/wiring; not introduced by
  this work.
- **Test coverage (3.9):** new tests map to the documented mapping
  (`food_catalog_load_test.dart` for the catalog layer, `nutrition_test.dart`
  for the `LogFoodRow` widget, with the S-001 sub-scenario landing in
  the existing `LogFoodRow — log from library` group).
- **Environment safety (3.10):** no `dart:io`, no SQLite imports, no
  `Platform.is*` introduced. Hive web + Mock stay in sync because
  both go through the same JSON/seed.
- **DRY + clean (3.11):** no new helper extracted; the existing
  `LogFoodRow._unitLabel` already composes the display from
  `referenceAmount` + `referenceLabel`. The fix is purely data-side.
- **Verdict:** Approved. The change is the minimum surface needed to
  correct a bundled-data defect; every layer outside `data/assets/`
  + `lib/mock/food_catalog_seed.dart` + tests is untouched; the new
  tests pin the convention going forward.

### Phase 3 Complete ✓
