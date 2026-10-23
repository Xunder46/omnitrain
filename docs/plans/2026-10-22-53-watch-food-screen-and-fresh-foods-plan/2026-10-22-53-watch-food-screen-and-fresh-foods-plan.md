# Feature: 53 — a food opens its own screen on the watch, and the food list is fresh

> Status: PLANNED 2026-10-22 (conductor-v2) — seeded Ledger, scenarios and phase outline kept verbatim; D-10, S-8313..S-8318 and the phase items appended. Owner: watch testing round 2026-10-22 items 1-3, in chat. Owner decisions: a food keeps opening at the amount last logged of it (not forced to 1 serving); the quantity bug is "the phone only syncs foods when Nutrition is open" (the owner's own theory, confirmed in code). Base commit: `.work/2026-10-22-53/base.txt`. Series: PR 1 of 3 (53 food, then the running-effort lock, then the sync spinner: not in this plan). Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md. Working branch: the one checked out (`claude_develop`); never create or switch branches.

## Goal and acceptance

| What you do | Now | After 53 |
|---|---|---|
| Tap a food in the watch's Foods I Eat list | the quantity row and Log button appear under the list on the same screen, over the foods | the food opens its own screen: name, quantity row (− / count / +, Crown), kcal, Log, and the confirmation line; the back button returns to the list with nothing selected |
| Log 3 servings of a food on the watch | the phone's macros update; the watch still shows the old starting amount for that food until you leave and re-enter | the watch's starting amount for that food is 3 straight away (list kcal and the next open of that food) |
| A new food list arrives from the phone while a food screen or the list is open | the open screen keeps the old numbers until re-entered | the open screen redraws with the new numbers |
| Press Sync (or the wrist catches up) before ever opening Nutrition on the phone | the phone sends no food list (its food library is empty until the Nutrition screen loads it), or a list with old "last amounts" | the phone loads its foods from storage first, so the watch always gets the current list and last-logged amounts |
| Go back from one food and open another | the previous selection lingers in the state | leaving a food clears the selection; the next food opens at its own starting amount |

Not changed: a food opens at the amount last logged of it; the Log button, Crown stepping (half-serving detents), the 0.5-10 bounds, the success tap, the list order and the recents.

## Decision Ledger

- D-1 `WatchNutritionState` (`watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift`) gets `deselect()`: `selectedFoodId = nil`, `portion` back to `minServings`, `lastConfirmation = nil`. The view calls it when the food screen is left. `select(_:)` is unchanged (it already sets `portion` from the food's own default and clears the confirmation).
- D-2 The wrist's own last log is the food's starting amount until the phone's list says otherwise. A food's effective `defaultServings` = `servings` of the newest `engine.nutritionLog` observation for that `foodId` WHEN that observation's `loggedAt` is later than the held catalog's `generatedAt`; otherwise the catalog's value. Derived on every read from the log and the catalog (no stored override), so a relaunch cannot lose it, in the style of `recentFoodIds` (`WatchNutritionState.recentFoodIds`). Applied inside `food(_:)` and `foods` (and so `selected`, `select`, the list's kcal): one place. A foods_down generated after the log wins (it carries the phone's own last amount); one generated before the log does not revert it. `WatchFood` is a struct of `let`s: add a copying method that changes only `defaultServings`.
- D-3 `WatchNutritionState` gets `public var onFoodsChanged: (() -> Void)?`, called after `restore()` and after an `applyFoodsDown` that returned `applied: true` (never for a dropped, refused or unreadable one), and after `logSelected()` succeeds (a new default). It may be called off the main thread; the SwiftUI model hops to the main queue.
- D-4 `WatchNutritionModel` (`WatchNutritionView.swift`, watchOS-only) sets `state.onFoodsChanged` to a closure that does `DispatchQueue.main.async { objectWillChange.send() }`, gets `deselect()` (state `deselect()` plus `crownPosition = 0`) and `var isShowingFood: Bool { state.selected != nil }`.
- D-5 `WatchNutritionView` is split into the list and a food screen (`WatchFoodPortionView`, same file, watchOS-only). The list shows only the foods and, when empty, the existing empty-state text. A tap calls `model.select(foodId)`; the push is driven by selection: `.navigationDestination(isPresented:)` bound to `Binding(get: { model.isShowingFood }, set: { if !$0 { model.deselect() } })`. The food screen holds the existing `portionRow`, `logButton` and the confirmation text (moved, not rewritten: Crown binding, 51e success tap, `watchProminent()` stay as they are). The list no longer marks one row selected.
- D-6 The watch app host (`ios/OmniTrain Watch App/ContentView.swift`) owns ONE `WatchNutritionModel`, created next to `nutrition` in `WatchAppHost.init` (line ~99) and stored as `let nutritionModel`; the sheet (line ~330) passes `host.nutritionModel`. Today the sheet builds a new model on every body evaluation, which resets `crownPosition` and the observer.
- D-7 Phone: `WatchSyncRequestHandler._sendRoutines` (`lib/state/watch/watch_sync_request_handler.dart:121`) awaits `_foodLibrary.loadFoodGroups(includeArchived: true)` and `_foodLibrary.loadFoods()` (the same two calls `lib/features/nutrition/nutrition_screen.dart:68-69` makes) BEFORE the `foods.isNotEmpty` check, every request. Reloading each request is required, not just on first use: `NutritionState._writeThroughLastAmount` writes `lastAmountConsumed` to the repository row only, so a once-loaded cache goes stale after every log. A throw from either load is caught and the cache as it stands is used; routines and the batches are still sent. A phone whose repository holds no foods still sends no foods frame (S-7104 stands).
- D-8 No wire, schema, contract-JSON or protocol change: `foods_down` keeps its shape.
- D-9 Dart twin (`lib/watch/nutrition/watch_nutrition_state.dart`, not shipped on the Apple Watch): state parity only for D-1 and D-2 (`deselect()`, the derived default), no screen change (`watch_nutrition_screen.dart` stays), stated in the docs as a UI parity gap.
- D-10 (appended by planning; derived from D-6's "ONE `WatchNutritionModel`", vetoable — see Open questions) The session menu's Log food row stops building its own model. `WatchMenuView` (`watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`) swaps its `nutrition: WatchNutritionState?` parameter (line ~34, init ~l.63) for `nutritionModel: WatchNutritionModel?` — nil keeps the row off, the same rule — and `logFoodRow` (~l.182) pushes `WatchNutritionView(model: nutritionModel)` instead of constructing one. `ContentView.menuSheet` (~l.419-422) passes `host.nutritionModel`. Without this the menu-pushed surface has no `onFoodsChanged` observer and shows stale numbers while open — the same defect class as owner item 2. The S-7201 guard that reads `nutrition: host.nutrition` in the menu call and the S-7203 guard text `WatchNutritionView(model: WatchNutritionModel(state: nutrition))` are updated in the same phase (Readers listed allows exactly this).

## Readers listed

- `WatchNutritionState.food(_:)`, `foods`, `selected`, `select`: callers are `WatchNutritionView`, `WatchNutritionModel`, `WatchSyncOrchestrator` (routes foods_down only), `WatchNutritionQuickLogTests.swift`, `WatchNutritionWiringSourceTests.swift`; the Dart twin has the same readers in `lib/watch/nutrition/` and `test/watch_nutrition_quick_log_test.dart`. Existing test `testANewSelectionStartsFromThatFoodsOwnPortion` (`WatchNutritionQuickLogTests.swift:522`) must stay green.
- `WatchNutritionWiringSourceTests.swift` reads `ContentView.swift` and `WatchNutritionView.swift` as text (S-7201..S-7205): any guard that names the old sheet line or the old single-screen layout must be updated in the same phase and listed.
- `test/watch_sync_request_handler_test.dart` S-7101..S-7105 build the handler with a `FoodLibraryState`: they must keep passing when the handler reloads from the repository (the foods have to be in the mock repository, not only in the cache); list any that seed only the cache.
- `docs/state_management/watch_surface_wrist.md`, `docs/state_management/nutrition_state.md`, `docs/widget_catalog/nutrition_widgets.md`, `docs/navigation_and_screens.md` (grep `WatchNutrition`).
- Scenario ids S-8301..S-8312 checked free: the builder re-greps `test/`, `docs/`, `watch/` before using them.

## Core scenarios

Swift, `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift` (new; harness copied from `WatchNutritionQuickLogTests.swift`):
- S-8301 select food A (default 2), step to 3.5, `deselect()`: `selected == nil`, `servings == 0.5`, `confirmation == nil`; select food B (default 1): `servings == 1`. Without D-1 it does not compile (no `deselect`).
- S-8302 catalog holds A with `defaultServings` 1; select A, step to 3, `logSelected()`: `food("A")?.defaultServings == 3`, the `foods` row for A has it, `deselect()`, `select("A")`: `servings == 3`. Without D-2 the default stays 1.
- S-8303 after S-8302's log, apply a `foods_down` whose `generatedAt` is BEFORE the log's `loggedAt` and A's default 1: A still 3. Apply one AFTER the log with A's default 2: A is 2.
- S-8304 a relaunch (new state over the same store, `restore()`): A's default is still 3 when the held catalog is older than the log.
- S-8305 `onFoodsChanged` is called once by `applyFoodsDown` that applies, once by `restore()`, once by a successful `logSelected()`, and not by an older (dropped) foods_down nor by a message the validator refuses.
- S-8306 a food whose last wrist log is older than the catalog keeps the catalog's default (the catalog wins when newer).

Dart:
- S-8307 `test/watch_nutrition_quick_log_test.dart`: the Dart twin of S-8301 and S-8302/8303 (`deselect()`, the derived default).
- S-8308 `test/watch_sync_request_handler_test.dart`: the library never loaded, the repository holds food F with `lastAmountConsumed` 1: the request sends a foods_down containing F. Without D-7 no foods frame is sent (empty cache).
- S-8309 the library loaded once with F at 1, then the repository row is updated to 3 (as the write-through does): the next request's foods_down carries `defaultServings` 3. Without D-7 it carries 1.
- S-8310 a throwing `loadFoods` (a repository that throws once): routines and preferences are still sent and the request returns true.

Watch app wiring (source guards in `WatchNutritionWiringSourceTests.swift`, comment-stripped text):
- S-8311 `ContentView.swift` constructs `WatchNutritionModel(` exactly once, in the host, and the sheet passes `host.nutritionModel`; no `WatchNutritionModel(` inside a view body.
- S-8312 `WatchNutritionView.swift`: the list body contains neither `portionRow` nor `logButton`; the food screen type contains both; a `navigationDestination` bound to `model.isShowingFood` exists; the model calls `deselect`.

Edge scenarios (appended by planning; numbering continues):

- S-8313 (Swift, `WatchNutritionFreshnessTests.swift`) `deselect()` with nothing selected is a no-op: on a state whose foods are empty, `deselect()` does not throw and leaves `selected == nil`, `servings == WatchNutritionPortion.minServings`, `confirmation == nil`; a second `deselect()` after a real one changes nothing (idempotent). Red: without D-1 it does not compile (no `deselect`).
- S-8314 (Swift) while food A is selected, a newer `foods_down` that no longer contains A is applied: `selected == nil` (the id no longer resolves — `selected` is derived, nothing is held), and `select("B")` then starts at B's own default. Red: mutation "`selected` returns a stale food for an unknown id" — the assertion `XCTAssertNil(watch.nutrition.selected)` fails.
- S-8315 (Swift) the derived default is clamped when it seeds a selection: a `foods_down` carrying A with `defaultServings` 0.25 (below the contract's `minServings`), no wrist log: `select("A")` → `servings == 0.5`. Red: mutation "`select` uses the raw value without `clampServings`" — 0.25 stands.
- S-8316 (Dart, `test/watch_sync_request_handler_test.dart`) a repository whose `getFoodGroups` throws once (a `MockWorkoutRepository` subclass overriding `getFoodGroups`): the request still returns true, `preferences_down` and `routines_down` travel, and the `foods_down` still travels — `loadFoodGroups`' catch empties the groups cache, so every row carries `categoryId: null` and the frame validates. Red: without D-7's try/catch `handle` rethrows.
- S-8317 (Dart, `test/watch_nutrition_quick_log_test.dart`) the twin of S-8304: log A at 3, rebuild engine and state over the same store, `restore()`: `food('A')!.defaultServings == 3` while the held catalog is older than the log. Red: without the twin's derived default it stays at the catalog's value.
- S-8318 (Swift, source guard in `WatchNutritionWiringSourceTests.swift`, comment-stripped text) `WatchMenuView.swift` contains no `WatchNutritionModel(` construction; its `logFoodRow` pushes `WatchNutritionView(model: nutritionModel)` over the handed model; `ContentView.swift`'s `menuSheet` passes `nutritionModel: host.nutritionModel`. Red: reverting D-10 — the row's old inline construction is exactly what the guard forbids.

## Phases

- P1 `developer` — Dart: D-7 and its tests S-8308..S-8310 in `test/watch_sync_request_handler_test.dart`; D-9 twin state with S-8307. Done: `flutter test test/watch_sync_request_handler_test.dart test/watch_nutrition_quick_log_test.dart`, `flutter analyze` (issue count vs baseline, 0 errors).

### Phase P1: the phone answers a sync with fresh foods (D-7, D-9) — independent of P2

1. [ ] `lib/state/watch/watch_sync_request_handler.dart` · `WatchSyncRequestHandler._sendRoutines` (~l.121): immediately before the `if (_foodLibrary.foods.isNotEmpty)` check, reload from the repository every request — `try { await _foodLibrary.loadFoodGroups(includeArchived: true); await _foodLibrary.loadFoods(); } catch (_) { /* the cache as it stands is used */ }` (D-7). No other line of the method changes: the preferences, routines, foods-then-batches order and the version early return stay as S-7101..S-7105 pin them.
2. [ ] `lib/watch/nutrition/watch_nutrition_state.dart` · new `void deselect()`: `_selectedFoodId = null`, `_servings = WatchNutritionPortion.minServings`, `_confirmation = null` (D-9, twin of D-1).
3. [ ] `lib/watch/nutrition/watch_nutrition_state.dart` · `food(String foodId)` (~l.150) + `foods`: one private helper, e.g. `_effectiveFood`, applying D-2's rule — scan `_engine.nutritionLog` from newest for the newest observation whose `payload['foodId']` is the id; when its `payload['loggedAt']` (`parseUtcIso`, from `../session/watch_records.dart`) is later than `_catalog?.generatedAt`, its `payload['servings']` is the food's `defaultServings`; otherwise the catalog's value stands. `foods` maps `_syncedFoods` through the helper before `deriveWatchFoodList`, so the list's kcal and the recents read the same values.
4. [ ] `lib/watch/nutrition/watch_food_catalog.dart` · `WatchFood` (~l.23): add `WatchFood copyWithDefaultServings(double defaultServings)` — the twin of D-2's copying method; nothing else on the type changes.
5. [ ] `test/watch_sync_request_handler_test.dart` · new group `S-8308…S-8310, S-8316 the handler reloads the food library per request`, reusing `_food`, `handlerFor`, `_RecordingTransport`:
   - S-8308: repository holds food F (`repository.createFood(_food('food-f', 'F', 'food-group-x', lastAmountConsumed: 1))`), the `FoodLibraryState` is never loaded (`FoodLibraryState(repository)` bare, as `setUp` builds it) → the `foods_down` frame contains F. Red: without D-7 the cache is empty and no foods frame is sent.
   - S-8309: `libraryWithFoods()`-style load once with F at `lastAmountConsumed` 1, then `repository.updateFood(food.copyWith(lastAmountConsumed: 3))` directly on the repository (bypassing the cache, as `NutritionState._writeThroughLastAmount` does, `lib/state/nutrition_state.dart:474`) → the next request's `foods_down` carries `defaultServings` 3 (referenceAmount 120 → assert the exact quotient). Red: without D-7 it carries 1.
   - S-8310: a `_ThrowingOnceRepository extends MockWorkoutRepository` whose `getFoods` throws exactly once → `handle` still returns true and `preferences_down` + `routines_down` + the batches travel. Red: without the try/catch `handle` rethrows.
   - S-8316: the same stub shape over `getFoodGroups` → true, and the `foods_down` still travels with every row's `categoryId` null. Red: without the try/catch `handle` rethrows.
6. [ ] `test/watch_nutrition_quick_log_test.dart` · new group `S-8307, S-8317 the Dart twin deselects and derives the starting amount`, over `_Harness` (`_Harness().nutritionState(_Harness().runningEngine())`, `_foodsDown()`):
   - the twin of S-8301: select A, `stepPortion`, `deselect()`, select B — exact assertions as S-8301 states. Red: does not compile without `deselect()`.
   - the twins of S-8302/S-8303: log A at 3 → `food('A')!.defaultServings == 3` and the `foods` row carries it; an older `foods_down` (generatedAt before the log) does not revert it, a newer one with default 2 does. Red: the default stays the catalog's value.
   - S-8317 (relaunch twin of S-8304). Red: the default reverts to the catalog's value after the rebuild.
7. [ ] Keep S-7101..S-7105 green and say why in the evidence file: they seed the repository through `libraryWithFoods()` (`test/watch_sync_request_handler_test.dart:150-186`), so the per-request reload finds the same rows the cache held; none seeds the cache only.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/watch_sync_request_handler_test.dart test/watch_nutrition_quick_log_test.dart`; `.github/copilot/scripts/macos/gateway.sh lint` (issue count vs the baseline this run establishes, 0 errors); paste pass/fail counts in the evidence file.
**Predicted Files**: `lib/state/watch/watch_sync_request_handler.dart`, `lib/watch/nutrition/watch_nutrition_state.dart`, `lib/watch/nutrition/watch_food_catalog.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_nutrition_quick_log_test.dart`, the evidence file. Nothing else.

- P2 `developer` — Swift state: D-1, D-2, D-3 and S-8301..S-8306. Done: `swift test` in `watch/watchos` (all green, count pasted).

### Phase P2: the Swift state deselects, derives the starting amount, and announces changes (D-1, D-2, D-3) — independent of P1

1. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchFoodCatalog.swift` · `WatchFood`: add `public func withDefaultServings(_ defaultServings: Double) -> WatchFood` — a copying method that changes only `defaultServings` (D-2; the struct's other `let`s are copied as they are).
2. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift` · new `public func deselect()`: `selectedFoodId = nil`, `portion = WatchNutritionPortion.minServings`, `lastConfirmation = nil` (D-1).
3. [ ] `WatchNutritionState.swift` · `food(_:)` (~l.70) and `foods` (~l.57): one private helper, e.g. `effectiveFood(_:)`, applying D-2's rule — the newest `engine.nutritionLog` observation for that `foodId` (scan reversed, first hit) whose `payload["loggedAt"]` (`parseUtcIso`) is later than `catalog?.generatedAt` lends its `payload["servings"]` (`as? NSNumber`) as the effective `defaultServings`; otherwise the catalog's value. `foods` maps `syncedFoods` through the helper before `deriveWatchFoodList`, so `selected`, `select`, the list's kcal and the recents all read one derivation.
4. [ ] `WatchNutritionState.swift` · new `public var onFoodsChanged: (() -> Void)?` (D-3), called: at the end of `restore()` (unconditionally, S-8305), in `applyFoodsDown` only on the path that returns `applied: true` (never for a dropped, refused or unreadable one), and after `logSelected()` stores its record (a new default).
5. [ ] New `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift`, harness copied from `WatchNutritionQuickLogTests.NutritionHarness` (same store/engine/validator/clock wiring; custom `foods_down` envelopes built the way `testAnOlderViewOfTheListIsNotANewerTruth` builds them): S-8301, S-8302, S-8303, S-8304, S-8305 (a counting closure installed as `onFoodsChanged`), S-8306, S-8313, S-8314, S-8315 — each test's comment names the mutation that turns it red (listed in the scenarios above).
6. [ ] Keep `WatchNutritionQuickLogTests` green — in particular `testANewSelectionStartsFromThatFoodsOwnPortion` (`WatchNutritionQuickLogTests.swift:522`), `testTheWristDerivesTheContractsOrder` (the contract's `expected` order must not move) and `testS7206ARestoreCannotPutTheStoredListOverANewerOne`; paste their pass in the evidence file.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` — all green, executed-test count pasted in the evidence file.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchFoodCatalog.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift` (new), the evidence file. Nothing else.

- P3 `developer` — Swift view and host: D-4, D-5, D-6 and S-8311, S-8312. The views compile only under `xcodebuild`: the agent cannot check that; the governor runs `xcodebuild` for the watch scheme and pastes the result. Done: `swift test`.

### Phase P3: the watch's food screen and the one model (D-4, D-5, D-6, D-10) — needs P2

1. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchNutritionView.swift` · `WatchNutritionModel.init`: install the observer — `state.onFoodsChanged = { [weak self] in DispatchQueue.main.async { self?.objectWillChange.send() } }` (D-4; the state may call it off the main thread, the model hops).
2. [ ] `WatchNutritionView.swift` · `WatchNutritionModel`: add `public func deselect()` — `objectWillChange.send()`, `state.deselect()`, `crownPosition = 0` — and `public var isShowingFood: Bool { state.selected != nil }` (D-4).
3. [ ] `WatchNutritionView.swift` · `WatchNutritionView.body`: the list only — the foods `ScrollView` (rows lose the `isSelected` branch and the prominent style; every row shows `food.calories(at: food.defaultServings)`, which D-2's derivation already makes the last-logged amount), the existing empty-state `Text` when `model.foods.isEmpty`, and `.navigationDestination(isPresented:)` bound to `Binding(get: { model.isShowingFood }, set: { if !$0 { model.deselect() } })` (D-5). A tap calls `model.select(food.foodId)`.
4. [ ] `WatchNutritionView.swift` · new `struct WatchFoodPortionView: View` (same file, watchOS-only): holds the existing `portionRow`, `logButton` and the confirmation `Text` — moved, not rewritten: the Crown `digitalCrownRotation` binding, the 51e `.success` tap in `logButton`, `watchProminent()` stay exactly as they are (D-5).
5. [ ] `ios/OmniTrain Watch App/ContentView.swift` · `WatchAppHost.init` (~l.99, right after `let nutrition = WatchNutritionState(...)`): `let nutritionModel = WatchNutritionModel(state: nutrition)`, stored as a new `let nutritionModel` property beside `nutrition`; the sheet (~l.328-332) becomes `WatchNutritionView(model: host.nutritionModel)` (D-6 — today the sheet builds a new model on every body evaluation, resetting `crownPosition` and dropping the observer).
6. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift` · `WatchMenuView` (~l.34, init ~l.63, `logFoodRow` ~l.182): the `nutrition: WatchNutritionState?` parameter becomes `nutritionModel: WatchNutritionModel?` (nil keeps the row off, same rule) and the row pushes `WatchNutritionView(model: nutritionModel)` (D-10); `ContentView.swift` · `menuSheet` (~l.419-422) passes `nutritionModel: host.nutritionModel`.
7. [ ] `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionWiringSourceTests.swift`: add the S-8311 guard (`ContentView.swift` constructs `WatchNutritionModel(` exactly once, in the host; the sheet passes `host.nutritionModel`; no construction inside a view body) and the S-8312 guard (list body free of `portionRow`/`logButton`; `WatchFoodPortionView` contains both; a `navigationDestination` bound to `model.isShowingFood`; the model calls `deselect`); add the S-8318 guard (no `WatchNutritionModel(` construction anywhere in `WatchMenuView.swift`; the row uses the handed model). Update the two guards that name the old wiring, in the same phase: S-7201's `menu.contains("nutrition: host.nutrition")` → the new `nutritionModel: host.nutritionModel` line, and S-7203's `row.contains("WatchNutritionView(model: WatchNutritionModel(state: nutrition))")` → the new row text.
8. [ ] Keep S-7202 and S-7205 untouched and green (the copy and the start-screen order do not change).

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test` (the source guards run there; count pasted). The views themselves compile only under `xcodebuild` — the governor runs it for the watch scheme and pastes the result; it is not an agent check.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchNutritionView.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionWiringSourceTests.swift`, the evidence file. Nothing else.

- P4 `developer` — docs: the five docs in Readers listed, plus the plan's Progress and a note in `docs/state_management/watch_surface_wrist.md` that the Dart screen keeps its old single-screen layout (UI parity gap). Done: `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`.

### Phase P4: docs and progress — needs P1, P2, P3

1. [ ] `docs/state_management/watch_surface_wrist.md` (§ "Food is reachable with or without a workout…", ~l.388): the food screen push and the back that deselects, the one host-owned `WatchNutritionModel` (sheet and menu alike), the derived starting amount (D-2's rule in one sentence), `onFoodsChanged` redrawing an open surface, and the note that the Dart screen (`lib/watch/nutrition/watch_nutrition_screen.dart`) keeps its single-screen layout — a stated UI parity gap (D-9).
2. [ ] `docs/state_management/watch_surface.md` (§ `WatchNutritionState`, ~l.260): `deselect()`, the derived-default comparison (log `loggedAt` vs catalog `generatedAt`), and `onFoodsChanged`'s three call sites.
3. [ ] `docs/state_management/nutrition_state.md` (~l.166-171, the watch bridge bullet): `WatchSyncRequestHandler._sendRoutines` reloads the food library from the repository on every routines request (D-7), and why — `NutritionState._writeThroughLastAmount` (`lib/state/nutrition_state.dart:474`) writes the row only, so a once-loaded cache goes stale after every log.
4. [ ] `docs/widget_catalog/nutrition_widgets.md` and `docs/navigation_and_screens.md`: grep `WatchNutrition` — zero hits in both at planning (verified this run); touch them only if the implementer's grep names the old layout, and record the grep result either way in the evidence file.
5. [ ] This plan's `## Progress`: one line per phase item, stating its result.
6. [ ] Doc sizes: all three edited docs read untruncated at planning (each under 20 KB, inside the 52 KB band of `test/docs_indexing_contract_test.dart`); re-check after the edits.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`.
**Predicted Files**: the three docs in items 1-3, this plan file, the evidence file (items 1-3 of `docs/widget_catalog/nutrition_widgets.md` and `docs/navigation_and_screens.md` only if item 4's grep names them). Nothing else.

- Governor after P4: full `swift test`, `xcodebuild` (watch scheme), `flutter analyze`, full `flutter test` once, `prove-red` for S-8301..S-8312, review.

## Owner checks (owner)

- (owner) On the watch: open Foods I Eat, tap a food: it opens its own screen; Back returns to the list with no quantity row; log 2 servings, go Back: that food now shows the 2-serving kcal in the list without re-entering; open another food: it starts at its own last amount.
- (owner) On the phone, kill and relaunch the app WITHOUT opening Nutrition, press Sync on the watch: the foods list appears on the watch.

## Scope budget

About 60 production lines Swift, about 50 Dart (phone ~15, twin ~35), about 450 of test, docs about 40. Two tracks (watch client, phone request handler), four phases, no contract change.

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchNutritionState.food(_:)`, `foods`, `selected`, `select` (Swift) | `WatchNutritionView.swift`, `WatchMenuView.swift:185`, `WatchSyncOrchestrator` (routes `foods_down` only), `WatchNutritionQuickLogTests.swift`, `WatchNutritionWiringSourceTests.swift` | every `WatchFood` the state hands out now carries the derived `defaultServings`; no signature changes | S-8302, S-8303, S-8306, S-8313..S-8315; existing `testANewSelectionStartsFromThatFoodsOwnPortion` (`WatchNutritionQuickLogTests.swift:522`) and `testTheWristDerivesTheContractsOrder` stay green (P2 item 6) |
| `WatchNutritionView` single-screen layout | `WatchMenuView.swift:185` (`logFoodRow`), `ContentView.swift:330` (sheet), source guards S-7201/S-7203 in `WatchNutritionWiringSourceTests.swift` | split into list + `WatchFoodPortionView` push; the two guard texts that name the old wiring are updated in the same phase (P3 item 7) | S-8311, S-8312, S-8318; S-7202/S-7205 untouched (P3 item 8) |
| `WatchMenuView` init signature (`nutrition:` → `nutritionModel:`) | `ContentView.swift:419-422` (`menuSheet`), S-7201/S-7203 guards | one model everywhere; nil-keeps-row-off rule unchanged | S-8318, updated S-7201/S-7203 (P3 items 6-7) |
| `FoodLibraryState` cache as `_sendRoutines`' source | `watch_sync_request_handler.dart:121` (`_sendRoutines`), `test/watch_sync_request_handler_test.dart` S-7101..S-7105 | the handler reloads from the repository before every send; S-7101..S-7105 seed the repository (`libraryWithFoods()`, lines 150-186), so they keep passing | S-8308, S-8309; S-7101..S-7105 re-pasted green (P1 item 7) |
| `FoodLibraryState.loadFoods` / `loadFoodGroups` throw path (clear cache, rethrow) | now also the handler (D-7) | a foods-load throw leaves an empty cache → no foods frame that request; a groups-load throw sends foods with `categoryId` null | S-8310, S-8316 |
| `NutritionState._writeThroughLastAmount` (`lib/state/nutrition_state.dart:474`) | the reason a once-loaded cache goes stale; unchanged itself | read-only dependency of D-7's rationale | S-8309 reproduces its effect |
| Dart twin `WatchNutritionState` + its readers (`lib/watch/nutrition/watch_nutrition_screen.dart`, `test/watch_nutrition_quick_log_test.dart`) | same reader set as the Swift state | `deselect()` + derived default added; the screen is untouched (D-9) | S-8307, S-8317 |
| Wire, schema, contract JSON | `watch/contract/watch_nutrition_contract.json`, `watch/sync_protocol/` | none — `foods_down` keeps its shape (D-8); the contract's `portion` block and order rules are untouched | S-8302's frame still validates; `testTheEventMatchesTheShapeTheProtocolFixturePins` stays green |

## UI Standards Impact

None new. The watch views reuse the pieces they already wear — `watchProminent()`, `.bordered`, the `surfaceInset` spacing, the Crown binding — moved, not restyled (D-5). No phone UI changes; `docs/design_system.md` governs the phone and is not touched. The list row loses its selected-state prominent style, which is a removal, not a new exception.

## Requirements

- R-1 A tapped food opens its own screen (name, portion row, kcal, Log, confirmation); leaving it — back button or swipe — returns to the list with nothing selected (D-1, D-5, D-6).
- R-2 Logging a food updates that food's starting amount on the wrist at once: the list's kcal column and the next open of that food (D-2, D-3).
- R-3 A `foods_down` arriving while the list or a food screen is open redraws it (D-3, D-4, D-6, D-10).
- R-4 Every routines request makes the phone reload its foods from storage first, so the wrist never gets an empty or stale list (D-7).
- R-5 Unchanged: a food opens at the amount last logged of it; the Log button, Crown detents and bounds, the success tap, the list order, the recents, the `foods_down` shape (D-8).

## Acceptance Criteria

| Criterion | Scenario(s) |
|---|---|
| Tap opens a food screen; back clears the selection; the next food opens at its own amount | S-8301, S-8313, S-8314, S-8311, S-8312 |
| A log becomes the food's starting amount immediately, on list and screen | S-8302, S-8307 |
| The phone's newer list wins; the wrist's newer log is not reverted by an older list | S-8303, S-8306, S-8317 |
| A relaunch keeps the derived amount | S-8304, S-8317 |
| Open surfaces redraw when a new list lands | S-8305 (state fires; the model hop is guarded by S-8312's source scan and the governor's `xcodebuild`) |
| The phone answers a sync with fresh foods even when Nutrition was never opened | S-8308, S-8309, S-8310, S-8316 |
| Nothing else regresses | S-7101..S-7105, S-7201..S-7205, S-7206, the contract-order tests |

## Files Affected (whole feature)

Production:
- `lib/state/watch/watch_sync_request_handler.dart` (P1, D-7)
- `lib/watch/nutrition/watch_nutrition_state.dart`, `lib/watch/nutrition/watch_food_catalog.dart` (P1, D-9)
- `watch/watchos/Sources/WatchSessionEngine/WatchNutritionState.swift`, `WatchFoodCatalog.swift` (P2, D-1..D-3)
- `watch/watchos/Sources/WatchSessionEngine/WatchNutritionView.swift`, `WatchMenuView.swift`, `ios/OmniTrain Watch App/ContentView.swift` (P3, D-4..D-6, D-10)

Tests:
- `test/watch_sync_request_handler_test.dart`, `test/watch_nutrition_quick_log_test.dart` (P1)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionFreshnessTests.swift` (new, P2), `WatchNutritionWiringSourceTests.swift` (P3)
- `WatchNutritionQuickLogTests.swift` — read-only dependent: must stay green, no edits planned

Docs:
- `docs/state_management/watch_surface_wrist.md`, `watch_surface.md`, `nutrition_state.md` (P4); `docs/widget_catalog/nutrition_widgets.md`, `docs/navigation_and_screens.md` only if P4's grep names them

## Notes

- Phase graph: P1 ⊥ P2 (different tracks, no shared file); P3 needs P2 (the view binds `deselect`/`isShowingFood`/`onFoodsChanged`); P4 needs P1..P3. P1 could run after P3 with no change to either.
- Intermediate state after P1: the phone sends fresh foods, but the watch still shows one screen — the owner's items 1-2 are not visible yet. After P2: the state has `deselect` and the derived default, but no view calls `deselect` yet — harmless dead code until P3.
- Legacy handling: the S-7201/S-7203 guard texts are the only places that encode the old sheet/menu wiring in test form; they are updated inside P3, never left red across a phase boundary.
- The `xcodebuild` watch-scheme build is the governor's, always (brief constraint); P3's agent-side proof is the source guards plus `swift test`.
- The Dart twin is not shipped on the Apple Watch; its parity exists so the two suites keep asserting the same state rules (D-9).

## Progress

- [x] P1 — Dart: handler reload (D-7) + twin state (D-9), S-8307..S-8310, S-8316, S-8317 — **Complete**
  1. [x] `watch_sync_request_handler.dart` reload before the `foods.isNotEmpty` check — Result: groups then foods reloaded in one `try`, throw swallowed with a comment; the rest of `_sendRoutines` untouched (diff +12).
  2. [x] twin `deselect()` — Result: clears the id, sets `minServings`, clears the confirmation; mutation-proved.
  3. [x] `_effectiveFood` behind `food(String)` and `foods` — Result: newest log newer than `_catalog!.generatedAt` wins, else the catalog value; `foods` maps `_syncedFoods` before `deriveWatchFoodList`.
  4. [x] `WatchFood.copyWithDefaultServings` — Result: added, copies every other field.
  5. [x] handler test group S-8308…S-8316 — Result: 4 tests (S-8308, S-8309, S-8310, S-8316), S-8310 strengthened with a second request; `_ThrowingOnceRepository` with armable `throwOnFoods`/`throwOnGroups`.
  6. [x] twin test group S-8307, S-8317 — Result: 3 tests (S-8301/S-8302/S-8303 twins, S-8317 relaunch) over `_foodsDownAt`.
  7. [x] S-7101..S-7105 green — Result: green in the 54-passed run; reason recorded in the evidence file (they seed the repository, so the reload finds the same rows).
  - Done Criteria: `test <two files>` 54/54, `lint` 180 info / 0 errors with none of the five touched files in the log, full suite 5434 passed / 2 skipped / 0 failed. Evidence: `<plan>.evidence.md` § Phase P1. `flutter run` is the governor's (not available to this role).
- [ ] P2 — Swift state: D-1, D-2, D-3, S-8301..S-8306, S-8313..S-8315
- [ ] P3 — Swift view and host: D-4, D-5, D-6, D-10, S-8311, S-8312, S-8318
- [ ] P4 — docs and Progress
- [ ] Governor: full `swift test`, `xcodebuild`, `flutter analyze`, full `flutter test`, `prove-red` S-8301..S-8312, review

## Assumption Log

(empty at planning — executors append: decision made, options considered, choice + why. Conductor ratifies or reverts each.)

- **P1 / S-8309 assertion shape.** Plan says "referenceAmount 120 → assert the exact quotient". Options: `closeTo(3/120)` or a tolerance-free double compare. Chose `closeTo(3 / 120, 1e-9)` — `buildFoodsDown` divides doubles, so an exact `==` would be a float-equality trap. Baseline 1/120 is asserted the same way in the same test.
- **P1 / S-8310 strengthened.** A first version asserted only "handle returns true + the other frames travel", which passed at HEAD: without D-7 the handler never touches the repository, so a throwing read is unreachable. Added an assertion that the failed read sends no foods frame and a second request after `createFood` carries the new food. Options: leave it weak, or pin both halves. Chose both — a green-at-base test proves nothing.
- **P1 / twin proved by mutation, not `prove-red`.** `test/watch_nutrition_quick_log_test.dart` cannot compile at HEAD (`deselect()`, `copyWithDefaultServings` are new), so `prove-red` can only report a build failure. Options: accept an unprovable group, or mutate. Chose two mutations (portion reset deleted; `_effectiveFood` returning the catalog food) with the original lines restored and re-run green — recorded in the evidence file.
- **P1 / `deselect()` resets the portion to `minServings`.** The Swift twin (P2 item 2) does the same and S-8301 asserts 0.5 after a deselect. Options: keep the last portion, or reset. Chose reset — one twin rule, and the next selection re-derives its own amount anyway.
- **P1 / `select`'s doc comment.** Its sentence said the portion starts "where the phone left it — the amount the user logged last". With D-9's derivation the newest source can be the wrist's own log, so the sentence became false; rewrote it to name both sources (comment only, no behavior).

## Open questions

1. **D-10 (vetoable, derived).** D-6 says the host owns ONE `WatchNutritionModel`, but the session menu builds a second one inline (`WatchMenuView.swift:185`, guarded as correct by S-7203 today). I read D-6's intent as "one model everywhere" and planned the menu onto the host's model. If the owner meant only the sheet, drop D-10 and S-8318 and keep the menu as-is — the menu path then keeps the pre-53 redraw gap. Evidence: `WatchMenuView.swift:182-189`, `ContentView.swift:419-422`.
2. **S-8316's pinned behavior.** After a `loadFoods` throw, `FoodLibraryState` clears `_foods` before rethrowing (`lib/state/food_library_state.dart:474-477`), so "the cache as it stands" is empty and no foods frame travels that request; after a `loadFoodGroups` throw the foods still travel with `categoryId` null. D-7's wording covers both readings; I pinned the code's actual behavior. Confirm this is the intended fallback.
3. **P4's two conditional docs.** `docs/widget_catalog/nutrition_widgets.md` and `docs/navigation_and_screens.md` have zero `WatchNutrition` mentions today (grep, this run), so P4 likely changes only three docs. The seeded P4 names five; kept as "grep and record".
4. **Doc sizes.** `wc`/shell is denied for this role; sizes were taken from untruncated file reads — all three edited docs are under 20 KB, inside the 52 KB band. The governor may want exact numbers at review.

## Feedback

[empty — fold into a new Iteration block when non-empty, then clear]
