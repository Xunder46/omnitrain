# Evidence — plan 49b (the watch app opens the food quick-log)

Proof date: 2026-10-21 (lead: unit tests, watch build, simulator screenshot). Docs and evidence: docs keeper, 2026-10-21.

## Test table (scenario → test → file)

| Scenario | Test | File |
|---|---|---|
| S-7201 the host builds one `WatchNutritionState`, hands it to the orchestrator, restores it, and wires `onOpenNutrition:` to `WatchNutritionView` from both entry points | `WatchNutritionWiringSourceTests.testS7201TheHostOwnsTheNutritionStateAndRestoresIt` | `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionWiringSourceTests.swift` |
| S-7202 `WatchMenuCopy.logFoodLabel == "Log food"` and equals `WatchStartView.logFoodLabel` | `…testS7202TheLogFoodCopyIsTheStartScreens` | same file |
| S-7203 the menu's Log food row sits between Add Exercise and End Session, pushes `WatchNutritionView`, and is never disabled | `…testS7203TheMenuRowSitsBetweenAddExerciseAndFinish` | same file |
| S-7205 the start screen's Log food button sits directly under Free workout and before Sync | `…testS7205LogFoodSitsRightUnderFreeWorkout` | same file |
| S-7204 existing behaviour kept: `WatchNutritionQuickLogTests` and the S-3103 menu guards stay green (run, not rewritten) | existing suites | `WatchNutritionQuickLogTests.swift`, `WatchMenuTests.swift` |

Count: 4 new source-scan tests (S-7201, S-7202, S-7203, S-7205) plus the kept suites.

## Verified

- The watch app builds and its start screen shows the new Log food button on the 40 mm simulator (lead, 2026-10-21). The screen itself is verified by that screenshot, not by a unit test — the source scans above pin the wiring.
- Governor mutation pass over the series: 12 of 12 mutants red.

## Not verified

- The two devices live: the Simulator could not be driven. Owner checks: the food list arriving on the watch, and a watch log reaching the phone's day log.

## Docs

- `docs/state_management/watch_surface_wrist.md`: new paragraph — the host's `nutrition` state, the start screen's Log food button, the menu row, and the S-7201..S-7205 source scans.
