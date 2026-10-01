# Feature: Food catalog validation follow-ups (calorie tolerance + fiber guard extension)

## Overview

Two follow-ups to the 2026-08-08 catalog delivery validation suite
(`2026-08-08-catalog-delivery-validation-suite-plan.md`):

1. **Loosen S-002 (calorie reconciliation) to ±1 kcal.** Seven rows
   (`black_beans`, `brown_rice`, `raisins`, `kidney_beans`, `dates`,
   `asparagus`, `sour_cream`) have macros whose raw energy lands exactly
   on a `.5` kcal boundary (e.g. 136.5). The JSON was authored with a
   rounding rule that picks the lower whole number at `.5`; the
   `Food.calories` getter uses Dart's `round()`, which rounds `.5`
   half-away-from-zero and so picks the upper whole number. The
   recorded figure and the derived figure therefore differ by exactly
   one calorie on these seven rows — there is no single correct
   rounding, and rewriting the JSON to satisfy the strict rule would
   hide a real disagreement rather than settle it. A ±1 kcal tolerance
   admits all seven while still catching the alcohol exceptions (27 and
   72 kcal off) and any future author error of comparable size.

   The test must also pin the tolerance itself: a separate assertion
   verifies that a 2-calorie discrepancy fails and a 1-calorie
   discrepancy passes, so the tolerance cannot drift wider later.

2. **Extend the fiber guard to flag `fiber == carbs`.** `almond_butter`
   records fiber = 3 and carbs = 3, so net carbs is exactly zero — not
   right for a nut butter. Set fiber to 1.6 per tbsp; every other field
   stays unchanged. `peanut_butter` records fiber = 2 — USDA FoodData
   Central reports ~1 g per 16 g tablespoon, so the current value is
   ~2× the reference. This is clearly wrong (not borderline) and the
   task authorizes the correction; set it to 1.0 per tbsp. Every other
   peanut_butter field stays unchanged.

   The catalog-level fiber guard currently uses
   `lessThanOrEqualTo(carbs)`, which lets `fiber == carbs` pass.
   Equality produces the same zero-net-carbs result as excess and the
   user is right to flag it. Replace the guard with a stricter rule:
   `fiber < carbs` whenever `carbs > 0`; for `carbs == 0`, the natural
   default is `fiber == 0` (an `oil` or `butter` with non-zero fiber
   is impossible by nutrition). A net-carbs test then asserts
   `netCarbs > 0` for every row with `carbs > 0`, closing the loop on
   the derived value too.

No schema change, no new state, no new screens, no new
repositories, no new routes. The catalog JSON and its generated seed
are the only data carriers that move; everything else is test changes
in `food_catalog_load_test.dart`.

## Requirements

- `food_catalog_load_test.dart > group('Validation suite')`:
  - S-002 compares the JSON-recorded calorie to
    `(protein*4 + carbs*4 + fat*9).round()` from the same JSON row,
    with tolerance ≤ 1 kcal. `beer_regular` and `red_wine` remain the
    only exempted ids.
  - A separate test (S-002 tolerance boundary) constructs two synthetic
    rows — one with a 1-calorie discrepancy, one with a 2-calorie
    discrepancy — and asserts the 1 passes, the 2 fails.
- `food_catalog_load_test.dart > group('MockWorkoutRepository catalog
  loading')`:
  - Fiber guard catches equality as well as excess. Existing wording
    `'no catalog row has fiber greater than carbs'` is updated; the
    `almond_butter` row now fails it before the seed change (regression
    case for the equality extension).
  - A new test asserts `netCarbs > 0` for every row with `carbs > 0`.
- `assets/data/food_catalog.json`:
  - `almond_butter.fiber: 3 → 1.6`.
  - `peanut_butter.fiber: 2 → 1.0`.
  - `almond_butter.calories: 107` stays. The macros still sum to the
    same recorded figure; fiber does not enter the calorie formula.
  - `peanut_butter.calories: 100` stays, for the same reason.
- `lib/mock/food_catalog_seed.dart`: same fiber changes as the JSON.
  After editing the seed, the row content matches what the generator
  would produce from the JSON — no `Regenerate seed` step is required
  because the seed file is hand-mirrored and the test enforces the
  parity on every field.
- `scripts/generate_food_catalog_seed.dart`: untouched. It re-derives
  the seed from the JSON, so the next regeneration will produce the
  same hand-edited values.
- Out of scope: changing calorie derivation, changing the alcohol
  exemptions, reviewing any other nutrition value, regenerating the
  seed as a release step.

## Acceptance Criteria

- [ ] `food_catalog_load_test.dart > S-002` compares the JSON-recorded
      `calories` to the JSON-derived value `(protein*4+carbs*4+fat*9).round()`
      with `|recorded - derived| ≤ 1`. The exception list still contains
      exactly `beer_regular` and `red_wine`.
- [ ] A dedicated tolerance test asserts a 1-calorie discrepancy passes
      and a 2-calorie discrepancy fails, so the tolerance cannot drift
      wider without breaking CI.
- [ ] The fiber guard asserts `fiber < carbs` whenever `carbs > 0`, and
      `fiber == 0` whenever `carbs == 0`. Before the seed change, the
      unmodified catalog must fail this test on `almond_butter` —
      `almond_butter` is the regression case for the equality extension.
- [ ] A net-carbs test asserts `netCarbs > 0` for every catalog row with
      `carbs > 0`. `almond_butter` (carbs = 3) and `peanut_butter`
      (carbs = 3) both pass after the fiber correction.
- [ ] `assets/data/food_catalog.json` shows `almond_butter.fiber: 1.6`
      and `peanut_butter.fiber: 1.0`. No other field on either row
      changes; `almond_butter.calories` stays at 107 and
      `peanut_butter.calories` stays at 100.
- [ ] The seven calorie-edge rows
      (`black_beans`, `brown_rice`, `raisins`, `kidney_beans`, `dates`,
      `asparagus`, `sour_cream`) keep their existing recorded calorie
      values exactly as they were. No change to their `protein`,
      `carbs`, `fat`, `fiber`, or `sodium` either.
- [ ] `lib/mock/food_catalog_seed.dart` shows the same fiber changes.
- [ ] `flutter test` is green; `flutter analyze` reports no new errors.

## Scenarios

This is a TRIVIAL feature — no new screens, state, routes, or
schemas. Per the agent brief, a lean plan with no scenario Q&A applies.
The two halves below substitute for the scenario register.

### Calibration — calorie reconciliation (1 kcal tolerance)

- **Trigger:** `S-002` runs after `MockWorkoutRepository.initialize()`
  loads the bundled catalog.
- **Precondition:** The JSON asset and the generated seed agree on
  every field (the existing S-001 parity test enforces this).
- **Flow:** For each catalog row not in the exception list, the test
  reads the JSON's recorded `calories` and compares to
  `(protein*4+carbs*4+fat*9).round()` computed from the same JSON row
  with tolerance ≤ 1. `beer_regular` and `red_wine` are skipped.
- **Expected outcome:** All 166 non-alcohol rows pass. The seven
  `.5`-boundary rows pass with a 1-calorie discrepancy. The two
  alcohol rows are skipped.
- **Tolerance pin:** A separate test asserts that a 2-calorie
  discrepancy fails the comparison — the tolerance cannot drift wider
  without breaking CI.
- **Edge case of:** none.

### Calibration — fiber guard extension (equality as well as excess)

- **Trigger:** The fiber guard runs after
  `MockWorkoutRepository.initialize()` loads the bundled catalog.
- **Precondition:** The catalog row count is 168; the
  default non-archived read returns 166 (`beer_regular` and `red_wine`
  are hidden).
- **Flow:** For each catalog row, the test asserts:
  - `carbs > 0 → fiber < carbs` (strict).
  - `carbs == 0 → fiber == 0` (natural default).
- **Expected outcome:** After the seed change, no row fails. Before
  the seed change, `almond_butter` (fiber=3, carbs=3) fails — the
  regression case for the equality extension.
- **Net carbs closure:** A separate test asserts `netCarbs > 0` for
  every row with `carbs > 0`, so a row with non-zero carbs and a
  fiber value ≥ carbs cannot slip through.
- **Edge case of:** none.

## Iteration 1

### DB Changes

None. The catalog JSON is data, not schema; the SQLite runtime is
retired.

### Backend Changes

None. No state, no repository, no service, no UI.

### Frontend Changes

None.

### Implementation Steps

1. **Update `assets/data/food_catalog.json`:**
   - `almond_butter.fiber: 3 → 1.6`.
   - `peanut_butter.fiber: 2 → 1.0`.

2. **Update `lib/mock/food_catalog_seed.dart`:**
   - Same fiber changes as the JSON (seed is hand-mirrored; parity test
     catches drift if a step is missed).

3. **Update `food_catalog_load_test.dart`:**
   - **S-002:** Compare JSON-recorded calories to JSON-derived
     `(protein*4+carbs*4+fat*9).round()` with tolerance ≤ 1 kcal.
     Keep the exception list and its length-of-2 assertion.
   - **S-002 tolerance boundary:** New test — build two synthetic
     `Food` records that round-trip through the loader with the
     recorded calorie 1 and 2 above the derived value; assert that the
     1 passes and the 2 fails. The simplest construction is to write
     inline JSON for both rows and exercise the same `_calorieMatches`
     helper the S-002 test will extract.
   - **Fiber guard:** Change the existing assertion from
     `fiber, lessThanOrEqualTo(food.carbs)` to a stricter rule that
     catches equality. The cleanest form is
     `(fiber < carbs) || (carbs == 0 && fiber == 0)`. Update the test
     name to reflect that equality is now flagged too.
   - **Net carbs > 0:** New test — for every catalog row with
     `carbs > 0`, assert `(carbs - fiber) > 0`.

4. **Verify:** Run `flutter test test/food_catalog_load_test.dart` and
   the full suite. Run `flutter analyze`.

## Assumption Log

- **Peanut butter fiber correction.** The task authorizes "correct it
  only if it is clearly wrong." USDA FoodData Central reports ~6 g
  fiber per 100 g of smooth peanut butter, i.e. ~0.96 g per 16 g
  tablespoon; the current value of 2 g per tbsp is ~2× the reference
  (and commercial brands report ~0.5–1 g per tbsp). This is a clear
  deviation, not a borderline one, so the correction is in-scope.
  The other peanut_butter fields (protein=4, carbs=3, fat=8) stay
  unchanged because the task explicitly puts other nutrition values
  out of scope and because changing them would break the existing
  calorie reconciliation (calories=100 is computed from those macros).

- **Tolerance test construction.** The tolerance pin uses inline JSON
  parsed through `FoodCatalogLoader.parseCatalogJson` so the test
  exercises the same loader the production runtime uses. There is no
  need to touch the catalog asset itself for the tolerance test; two
  small JSON snippets parsed in-place are sufficient and keep the
  test scoped to the rule, not to catalog rows.

- **Fiber guard wording.** The user requirement is "No catalog row
  has `fiber` greater than or equal to `carbs`, except where carbs is
  0 and fiber is 0." This is equivalent to
  `(fiber < carbs) || (carbs == 0 && fiber == 0)`. The existing
  natural-default rows (oils, butter, meats with carbs=0/fiber=0) keep
  passing; only the equality case and the fiber-without-carbs case
  fail.

- **Scope.** No new screens, no new state, no schema change, no
  service, no repository, no route. Phase 1 (Data) is hand-edits to
  two files; Phase 2 (Logic & UI) is test changes only; Phase 3
  (Review) verifies the test suite.

## Progress

- [x] Phase 0 complete (plan written)
- [x] Phase 1 complete (JSON + seed fiber edits)
- [x] Phase 2 complete (S-002 tolerance, fiber guard, net carbs tests)
- [x] Phase 3 complete (review)

### Phase 0 Complete ✓

### Phase 1 Complete ✓

### Phase 2 Complete ✓

### Phase 3 Complete ✓