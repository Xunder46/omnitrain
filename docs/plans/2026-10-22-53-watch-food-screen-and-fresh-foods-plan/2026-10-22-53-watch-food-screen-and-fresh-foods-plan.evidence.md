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

- `swift test` (full package, once, and again after the last restored mutation): **753 passed, 0 failed** —
  `Executed 753 tests, with 0 failures (0 unexpected)` (`.work/gateway/swift-test-20261022-235452-92449.log`).
  The nine new tests are `WatchNutritionFreshnessTests`, also green on their own
  (`swift-test --filter WatchNutritionFreshnessTests` → **9 passed, 0 failed**, build clean of warnings).
- `prove-red a01be76d05e6a4807b21a6a97a3dc38dc06abba0 swift-test --filter WatchNutritionFreshnessTests -- <new test file>` →
  **RED AT a01be76 (exit 1)**, but by compile errors only (`WatchNutritionState has no member 'deselect'`,
  `... no member 'onFoodsChanged'`): new APIs, so the file cannot build at the base commit. A compile
  error is not an assertion failure, so each guard is proved by the mutations below; every original was
  restored exactly and the suite re-run green.
- Mutations (original line → mutant, all in `WatchNutritionState.swift`):
  1. `        portion = WatchNutritionPortion.minServings` in `deselect()` → deleted (rest of the method intact).
  2. `        for observation in engine.nutritionLog.reversed() {` in `effectiveFood(_:)` →
     `        for observation in engine.nutritionLog.reversed().prefix(0) {` (the log is never consulted).
  3. `        onFoodsChanged?()` at the end of `restore()` → deleted.
  4. `        onFoodsChanged?()` in `applyFoodsDown`'s applied path and the same call in `logSelected()` → both deleted.
  5. `        selectedFoodId.flatMap { food($0) }` → `        selectedFoodId.flatMap { food($0) ?? syncedFoods.first }`.
  6. `        portion = Self.clampServings(food.defaultServings)` in `select(_:)` → `        portion = food.defaultServings`.
  7. `            if loggedAt <= catalog.generatedAt { return food }` in `effectiveFood(_:)` → deleted (the log
     always wins, whatever the list says).
- Red→green table:

| Scenario | Red proof (mutation) | Green |
|---|---|---|
| S-8301 | 1: `("3.5") is not equal to ("0.5")` | `testS8301LeavingAFoodClearsItAndTheNextOneOpensAtItsOwnAmount` passes |
| S-8302 | 2: `("Optional(1.0)") is not equal to ("Optional(3.0)")` on the food, the list row and the next selection | `testS8302ALogBecomesTheFoodsStartingAmount` passes |
| S-8303 | 7: `("Optional(3.0)") is not equal to ("Optional(2.0)")` after the post-log list; 2: `Optional(1.0)` where 3 was expected after the pre-log list | `testS8303ANewerListWinsAndAnOlderOneDoesNotRevertALog` passes |
| S-8304 | 2: `("Optional(1.0)") is not equal to ("Optional(3.0)")` after the relaunch | `testS8304ARelaunchKeepsTheDerivedStartingAmount` passes |
| S-8305 | 3: `("0") is not equal to ("1")` after the restore; 4: `0` where 1 after the apply, `1` where 3 after the log | `testS8305FoodChangesAreAnnouncedOnlyWhenTheListChanges` passes |
| S-8306 | 7: `("Optional(3.0)") is not equal to ("Optional(1.0)")`, then `("3.0") is not equal to ("1.0")` on the row and the next selection | `testS8306ALogOlderThanTheCatalogKeepsTheCatalogsAmount` passes |
| S-8313 | 1 does not reach it (idempotency, not the reset — as the plan states); the method's absence is the compile red above | `testS8313DeselectingNothingChangesNothing` passes |
| S-8314 | 5: `XCTAssertNil failed: "WatchFood(foodId: "food-b" …"` | `testS8314ANewerListThatDropsTheSelectedFoodClearsTheSelection` passes |
| S-8315 | 6: `("0.25") is not equal to ("0.5")` | `testS8315ASelectionClampsTheListedAmount` passes |
| `WatchNutritionQuickLogTests` (incl. `testANewSelectionStartsFromThatFoodsOwnPortion`, `testTheWristDerivesTheContractsOrder`, S-7206) | regression: unchanged files, no new failure | green in the 753-passed run |

- Residue sweeps: `git-diff --stat` after the last restore → the two Swift sources
  (`WatchFoodCatalog.swift` +14, `WatchNutritionState.swift` +48/−2), this evidence file and the plan's
  Progress only; the new test file is untracked (`git-status` lists it as `??`) and so absent from
  `--stat`. No `MUTATION` marker and no mutant line remains.
- `lint` re-run (no Dart file changed this phase): **180 issues, 0 errors**, unchanged from the P1
  baseline. Invariant grep (`import .*hive_workout_repository` over `lib/state lib/features
  lib/widgets lib/core`) returns nothing.
- `test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` → **42 passed, 0 failed**
  (no `lib/` UI file changed, but the plan files grew and both contract suites cover what this phase
  touched in `docs/plans/`).
- `flutter run` / the watch scheme's `xcodebuild`: not available to this role (governor's).

## Phase P3 (Swift view and host: D-4, D-5, D-6, D-10)

- Guards first, implementation second:
  - `swift-test --filter WatchNutritionWiringSourceTests` before any production edit → **7 executed,
    5 failed (14 assertion failures)**: S-7201, S-7203, S-8311, S-8312, S-8318 red; S-7202 and
    S-7205 green.
  - The same filter after the implementation → **7 executed, 0 failures**.
- `prove-red a01be76d05e6a4807b21a6a97a3dc38dc06abba0 swift-test --filter WatchNutritionWiringSourceTests --
  watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionWiringSourceTests.swift` → **RED AT a01be76
  (exit 1)**, 7 executed / 14 failures, every failure an assertion (the file compiles there): the base
  files still carry the old sheet line, the single-screen layout and the menu's inline model. Log:
  `.work/gateway/swift-test-20261022-235929-95987.log`.
- Full `swift test --package-path watch/watchos`: **756 executed, 0 failures, 0 unexpected** (was 753 in
  P2; +3 new guards). Log: `.work/gateway/swift-test-20261022-235954-96507.log`.
- `test test/ui_standards_contract_test.dart` → **29 passed, 0 failed** (no Dart or phone UI file
  changed; the scans and the allowlist self-check are clean).
- `test test/docs_indexing_contract_test.dart` (re-run after this phase's Progress and Assumption Log
  edits, which grow the plan) → **13 passed, 0 failed**; both plan files stay inside the ceiling band.
- `lint` → **180 issues, 0 errors**, unchanged from the P1/P2 baseline. The three production files are
  Swift and do not appear in the log. Log: `.work/gateway/lint-20261023-000008-96767.log`.
- Invariant grep `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core`
  → no hit; the only hit under `lib/` is `lib/main.dart` (the composition root, outside those trees).
- Red→green table:

| Scenario | Red proof | Green |
|---|---|---|
| S-8311 | prove-red at a01be76: no `let nutritionModel = WatchNutritionModel(state: nutrition)` in the host, the sheet still constructs a model (`XCTAssertFalse`), the sheet passes `host.nutrition` | `testS8311TheHostOwnsTheOneNutritionModel` passes |
| S-8312 | prove-red at a01be76: `portionRow` and `logButton` still in the list (`XCTAssertFalse` ×2), no `navigationDestination`, no `model.isShowingFood`, no `WatchFoodPortionView` (`XCTUnwrap`) | `testS8312TheListIsTheListAndTheFoodScreenEdits` passes |
| S-8318 | prove-red at a01be76: one `WatchNutritionModel(` in the menu (`("1") is not equal to ("0")`), the row still constructs it, the menu call passes `nutrition:` | `testS8318TheMenuPushesTheHostsNutritionModel` passes |
| S-7201 / S-7203 (updated guard text) | prove-red at a01be76: the old wiring fails the new text (menu handed the state; `WatchNutritionState?` parameter; inline destination) | both pass after the update |
| S-7202, S-7205 | regression: untouched, green in both the red and the green runs | green |

- Guard texts rewritten in this phase (the only places that encoded the old wiring):
  S-7201's `menu.contains("nutrition: host.nutrition")` → `nutritionModel: host.nutritionModel`;
  S-7203's optional-parameter text → `nutritionModel: WatchNutritionModel? = nil`, and its destination
  text → `WatchNutritionView(model: nutritionModel)`.
- Footprint: `git-diff --stat` → the four predicted files only (`ContentView.swift` 15 changed lines,
  `WatchMenuView.swift` 25, `WatchNutritionView.swift` 97, `WatchNutritionWiringSourceTests.swift` 147;
  238 insertions / 46 deletions in total), plus this evidence file and the plan's Progress. No mutation
  marker left, no scratch file created.
- The views compile only under `xcodebuild` (watch scheme), which this role cannot run: the governor's
  run pastes the result. `flutter run` is the governor's for the same reason.

## Phase P4 (docs)

- Docs edited (three; the plan's two conditional docs were not touched):
  - `docs/state_management/watch_surface_wrist.md` § "Food is reachable with or without a workout":
    the one host-owned `WatchNutritionModel` for the sheet and the menu row (S-8311, S-8318), the
    food screen and the back that deselects (S-8312, S-8301, S-8313, S-8314), the derived starting
    amount (S-8302, S-8303, S-8304, S-8306, S-8315), `foods_down` redrawing an open surface (S-8305),
    and the Dart screen's single-screen layout as a stated UI parity gap (D-9).
  - `docs/state_management/watch_surface.md` § `WatchNutritionState`: `deselect()`, the
    `loggedAt` vs `generatedAt` comparison, and `onFoodsChanged`'s three call sites; the section's
    Verified-by line now names `WatchNutritionFreshnessTests`.
  - `docs/state_management/nutrition_state.md`, the watch bridge bullet: the per-request reload (D-7)
    and why (`_writeThroughLastAmount` writes the repository row only), citing the S-8308…S-8316
    group.
- `test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` → **42 passed,
  0 failed** (13 docs-indexing tests + 29 UI-standards tests).
- Grep records (`WatchNutrition`), re-run after the doc edits:
  - `docs/widget_catalog/nutrition_widgets.md`: **0 hits** before and after — unchanged.
  - `docs/navigation_and_screens.md`: **0 hits** before and after — unchanged.
  - `docs/`: hits only in `state_management/watch_surface.md`, `watch_surface_wrist.md`,
    `state_management.md`, `state_management/nutrition_state.md`, `watch_session_capture.md` and the
    plan folders.
- Doc sizes: all three edited docs read untruncated after the edits (each well under 20 KB, inside the
  52 KB band); `test/docs_indexing_contract_test.dart`'s ceiling test is green. Exact byte counts are
  not obtainable in this role (shell denied).
- `lint` → **180 issues, 0 errors**, unchanged from the P1–P3 baseline. Log:
  `.work/gateway/lint-20261023-000700-12256.log`.
- Footprint: `git-diff --stat` → exactly the five predicted files (three docs, the plan, this evidence
  file), 89 insertions / 12 deletions. No Dart, Swift, test or other doc file changed; no scratch file
  created.
- The full `flutter test`, the watch scheme's `xcodebuild` and `flutter run` are the governor's (P4's
  Done Criteria are the two contract suites above; this phase changes no Dart source).



## Assumption Log detail

Any assumption logged in the plan gets its options-considered detail here.
