# Evidence — plan 53 (watch food screen and fresh foods)

Implementers append here: baselines, suite outputs, red→green tables, footprints.
One section per phase, in order. Paste pass/fail counts, never a claim of success.

## Baselines (planning run, 2026-10-22, base commit a01be76d05e6a4807b21a6a97a3dc38dc06abba0)

- No suites were run at planning (the governor runs the full set after P4). The first
  implementer run establishes each baseline and records it here:
  - `flutter analyze`: **180 issues, all `info`, 0 errors, 0 warnings** (P1 run,
    `.work/gateway/lint-20261022-234200-80891.log`). None of the five files this phase touched
    appears in the log (grep over the log for `watch_sync_request_handler`, `watch_nutrition_state`,
    `watch_food_catalog`, both test files: 0 hits), so the change adds no notice and 180 is the
    baseline. The command still exits non-zero on the pre-existing notices.
  - `flutter test test/watch_sync_request_handler_test.dart test/watch_nutrition_quick_log_test.dart`:
    **54 passed, 0 failed** after the phase's change (no pre-change count is meaningful: the twin
    group cannot compile at the base commit, new APIs). Regression evidence is the untouched
    S-7101..S-7105 and S-001..S-006 groups inside those two files plus the full suite below.
  - `swift test --package-path watch/watchos`: **N/A this phase** — no `.swift` file changed, so the
    watch suite was not run (standing rule: run it only when this run changed Swift sources).
  - Full `flutter test test`: **5434 passed, 2 skipped, 0 failed** — `03:18 +5434 ~2: All tests passed!`
    (`.work/gateway/test-20261022-234213-81042.log`).

- Known environment facts (from the repo's run notes): full `flutter test` takes minutes
  (900 s timeout); a `testWidgets` that opens the Hive harness or awaits a real
  `Future.delayed` hangs forever — run widget tests Mock-first, seed Hive in `setUp`;
  a red Mock group can leave its Hive group hanging behind it — fix the red group first.
- Doc sizes at planning (untruncated reads, inside the 52 KB band):
  `docs/state_management/watch_surface_wrist.md`, `watch_surface.md`, `nutrition_state.md`
  each under 20 KB.

## Phase P1 (Dart: D-7, D-9)

- Suite outputs:
  - `test test/watch_sync_request_handler_test.dart test/watch_nutrition_quick_log_test.dart` →
    **54 passed, 0 failed**.
  - the same two files together with `test/ui_standards_contract_test.dart` → **83 passed,
    0 failed** (`S-2601`…`allowlist self-check` all green; no `lib/` UI file was touched).
  - `lint` → 180 issues, 0 errors (see Baselines).
  - full `test test` → **5434 passed, 2 skipped, 0 failed**.
  - `prove-red HEAD test test/watch_sync_request_handler_test.dart` → **RED AT HEAD (exit 1)**, with
    real assertion failures on S-8308, S-8309, S-8310 and S-8316 (the handler tests do compile at
    HEAD; only the behavior is missing). The twin group in
    `test/watch_nutrition_quick_log_test.dart` cannot compile at HEAD (`deselect()`,
    `copyWithDefaultServings` are new), so it is proved by the two mutations below.
- Red→green table:

| Scenario | Red proof (stub / mutation) | Green |
|---|---|---|
| S-8308 | prove-red at HEAD: empty cache sends no `foods_down` → assertion failure | `S-8308 a library nobody loaded still answers with the repository's …` passes |
| S-8309 | prove-red at HEAD: frame carries `defaultServings` 1 after the row moved to 3 | `S-8309 a log written through to the repository reaches the next …` passes (`closeTo(3 / 120, 1e-9)`) |
| S-8310 | prove-red at HEAD: without the try/catch `handle` rethrows | `S-8310 a throwing food read still answers with the rest` passes |
| S-8316 | prove-red at HEAD: without the try/catch `handle` rethrows | `S-8316 a throwing group read still sends the foods, uncategorised` passes |
| S-8307 | twin: does not compile without `deselect()`; mutation 1 below for the portion reset, mutation 2 for the derived default | `S-8307 (S-8301) deselecting clears the selection and the next food …` and `S-8307 (S-8302, S-8303) the wrist's own log is the starting amount …` pass |
| S-8317 | mutation 2 below: the default reverts to the catalog's value after relaunch (`Actual: <1.5>`, expected 3) | `S-8317 a relaunch keeps the derived starting amount` passes |
| S-7101..S-7105 | regression: still green — they seed the repository via `libraryWithFoods()` (`test/watch_sync_request_handler_test.dart:150-186`), so the per-request reload finds exactly the rows the cache held; none of them seeds the cache only | green in the 54-passed run |

Mutations used for the twin (the file cannot compile at HEAD, so `prove-red` is unusable there):

1. `lib/watch/nutrition/watch_nutrition_state.dart`, `deselect()` — original line
   `_servings = WatchNutritionPortion.minServings;` deleted (the rest of `deselect()` intact):
   `S-8307 (S-8301)` failed, `Actual: <3.5>` where 0.5 was expected. Line restored, re-run green.
2. `lib/watch/nutrition/watch_nutrition_state.dart`, `_effectiveFood` — original line
   `return food.copyWithDefaultServings(servings.toDouble());` replaced by `return food;`:
   `S-8307 (S-8302, S-8303)` and `S-8317 a relaunch keeps the derived starting amount` failed,
   `Actual: <1.5>` where 3 was expected. Original restored exactly, re-run green.

Footprint: `git-diff --stat` → the five predicted files only
(`watch_sync_request_handler.dart` +12, `watch_food_catalog.dart` +13,
`watch_nutrition_state.dart` +39/-4, `watch_nutrition_quick_log_test.dart` +147,
`watch_sync_request_handler_test.dart` +218), plus this evidence file and the plan's Progress.

## Phase P2 (Swift state: D-1, D-2, D-3)

- `swift test` output: _to fill_
- Red→green table:

| Scenario | Red proof | Green |
|---|---|---|
| S-8301 | does not compile without `deselect()` | _to fill_ |
| S-8302 | without D-2 the default stays 1 | _to fill_ |
| S-8303 | mutation: apply the log's servings regardless of `generatedAt` → the older-down assertion fails | _to fill_ |
| S-8304 | mutation: an in-memory override instead of derivation → the relaunch loses it | _to fill_ |
| S-8305 | mutation: fire `onFoodsChanged` on dropped/refused messages too → the count fails | _to fill_ |
| S-8306 | mutation: the log always wins regardless of `generatedAt` → the catalog-newer assertion fails | _to fill_ |
| S-8313 | does not compile without `deselect()` | _to fill_ |
| S-8314 | mutation: `selected` returns a stale food for an unknown id | _to fill_ |
| S-8315 | mutation: `select` skips `clampServings` → 0.25 stands | _to fill_ |
| `WatchNutritionQuickLogTests` (incl. `testANewSelectionStartsFromThatFoodsOwnPortion`, `testTheWristDerivesTheContractsOrder`, S-7206) | regression: must stay green | _to fill_ |

## Phase P3 (Swift view and host: D-4, D-5, D-6, D-10)

- `swift test` (source guards) output: _to fill_
- Governor's `xcodebuild` (watch scheme): _to fill by the governor_
- Red→green table:

| Scenario | Red proof | Green |
|---|---|---|
| S-8311 | reverting D-6: the sheet's inline `WatchNutritionModel(` construction | _to fill_ |
| S-8312 | reverting D-5: `portionRow`/`logButton` back in the list body; no `navigationDestination` | _to fill_ |
| S-8318 | reverting D-10: the menu row's inline construction | _to fill_ |
| S-7201 / S-7203 (updated guard text) | old text fails against the new wiring | _to fill_ |
| S-7202, S-7205 | regression: untouched, must stay green | _to fill_ |

## Phase P4 (docs)

- `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`: _to fill_
- Grep records:
  - `WatchNutrition` in `docs/widget_catalog/nutrition_widgets.md`: 0 hits at planning.
  - `WatchNutrition` in `docs/navigation_and_screens.md`: 0 hits at planning.
  - Re-run both greps after the doc edits and record the result here.
- Doc sizes after edits: _to fill_ (must stay inside the 52 KB band).

## Assumption Log detail

Any assumption logged in the plan gets its options-considered detail here.
