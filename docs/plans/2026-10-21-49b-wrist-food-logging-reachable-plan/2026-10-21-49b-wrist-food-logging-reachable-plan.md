# Feature: 49b — the watch app opens the food quick-log

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE, both minors fixed: restore() no longer overwrites a newer list, S-7206; doc citation). Start-screen button seen on the 40 mm simulator (moved right under Free workout); the food screen itself and a log reaching the phone's day log are owner checks. Swift 688/0, Flutter +5411 (one unrelated flaky test, S-5115, fails in some full runs and passes alone), analyze 180 (baseline). Series: `docs/plans/2026-10-21-49-watch-food-and-rest-series.md`. Scout: `.work/crew/2026-10-21-49/scout-food.md` Q1, Q4 (its claim that no watch app target exists is wrong: the shell is `ios/OmniTrain Watch App/ContentView.swift`).

## Decision Ledger
- D-1 `WatchAppHost.init` (`ContentView.swift`) builds a `WatchNutritionState` over the same engine and store (read its `init` at `WatchNutritionState.swift:53` and the way `WatchNutritionQuickLogTests.swift` builds it), keeps it as `let nutrition`, passes `nutrition: nutrition` to `WatchSyncOrchestrator(...)` and calls `await nutrition.restore()` in `restore()` (after `engine.restore()`), then `revision += 1` as today.
- D-2 Start screen: `ContentView` passes `onOpenNutrition: { showingFood = true }` to `WatchStartView` and hosts one `.sheet(isPresented: $showingFood)` containing `NavigationStack { WatchNutritionView(model: WatchNutritionModel(state: host.nutrition)) }` with a close affordance the system provides (the sheet's own dismiss), titled by `WatchStartSurfaceCopy.logFoodLabel`? Use `WatchStartView.logFoodLabel` = "Log food".
- D-3 Session menu: `WatchMenuView` gets a row "Log food" (`WatchMenuCopy.logFoodLabel = "Log food"`) between Add Exercise and End Session that pushes the same nutrition screen with a `NavigationLink` (like Add Exercise); `WatchMenuView` receives the nutrition state through a new optional `nutrition: WatchNutritionState?` parameter (nil keeps the row off); `ContentView.menuSheet` passes `host.nutrition`. The row is never disabled (food is independent of the effort).
- D-4 After a food is logged the screen shows the state's `confirmation` (existing). Nothing else changes in `WatchNutritionView`; the foods arrive through the existing `foods_down` path (49a).
- D-5 Out of scope: search or letter jump in the food list, the phone, the wire.

## Readers listed
- Source guards reading `ContentView.swift`: `WatchMenuTests` S-3103 (one `WatchMenuState(` construction, list button on the rest branch), `WatchSensorSourceSourceTests` (`viewSource()`), `WatchHostHopSourceTests`, `WatchPagerSourceTests`; keep each green.
- `WatchMenuView(` constructors: `ContentView.swift` only (grep); `WatchMenuState`/menu tests use the state, not the view.

## Scenarios (ids S-7201.. checked free)
- S-7201 (source scan, new `WatchNutritionWiringSourceTests.swift`, helper style of `WatchHostHopSourceTests`): `ContentView.swift` contains `WatchNutritionState(` exactly once, `nutrition: nutrition` inside the `WatchSyncOrchestrator(` call, `nutrition.restore()`, `onOpenNutrition:` and `WatchNutritionView(`.
- S-7202 `WatchMenuCopy.logFoodLabel == "Log food"` and equals `WatchStartView.logFoodLabel`.
- S-7203 (source scan) `WatchMenuView.swift` contains a `NavigationLink` whose destination is `WatchNutritionView(` and the label `WatchMenuCopy.logFoodLabel`, placed after the Add Exercise row and before the finish row (index order), and the row has no `.disabled(`.
- S-7204 (existing behaviour kept, run not rewritten) `WatchNutritionQuickLogTests` and the S-3103 guards stay green.
- The lead builds the watch target and screenshots the start screen on the simulator (Log food button visible) and the empty food screen text.
Mutation list: remove `onOpenNutrition:` argument, drop `nutrition:` from the orchestrator call, row `.disabled(true)`.

## Phases
P1 (crew-builder-watch, 5 items): tests first, `WatchMenu.swift` copy, `WatchMenuView.swift`, `ContentView.swift`. Scope: those three files + `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionWiringSourceTests.swift`. Needs xcodebuild (lead).
