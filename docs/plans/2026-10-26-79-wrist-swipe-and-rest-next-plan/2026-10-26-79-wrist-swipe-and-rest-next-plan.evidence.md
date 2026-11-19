# Evidence — plan 79 (wrist swipe without a name card; rest Next opens the announced exercise)

Base commit 9ac47772. Docs-keeper evidence, assembled from the builders' reports and the code read this run (2026-10-26).

## Swift suite

- `swift test --package-path watch/watchos`: **1034 tests, 0 failures** (P3 lead run).
- Watch app target: `xcodebuild OmniTrain Watch App for watchOS Simulator`: **BUILD SUCCEEDED** (P3 lead run).

## Red/green (new and rewritten tests)

| Test | Red before | Green after |
|---|---|---|
| `WatchRestLabelsTests` S-9101..S-9107 (`testS9101TheAnnouncedExerciseCarriesItsSlotId` … `testS9107ASlotWithoutItsOwnIdAnnouncesTheCatalogSlotId`) | red (no `nextSlotId`) | green |
| `WatchRestAdvanceTests.testS9108TheRestsNextJumpsToTheAnnouncedExercise` (engine order: rest ended, then one `exercise_advanced` frame) | red | green |
| `WatchRestAdvanceTests.testS9109TheNextReadsTheTargetBeforeItEndsTheRest` (source guard: Next reads the target before `endRest()`, then `advance(target)`; shell wiring `advance: { await menuState.jump(to: $0) }`) | red | green |
| `WatchPagerModelTests.testS9110NeighbourIndexNamesTheAdjacentPageWithoutWrapping` | red (no `neighbourIndex`) | green |
| `WatchPagerSourceTests.testS6611ThePagerIsNoTabViewAndStillAnswersADragWhenLocked` (rewritten: no `TabView`, no `.tabViewStyle`, exactly two drags) | red (old TabView guard) | green |
| `WatchPagerSourceTests.testS9111ThePagerIsOneLoggerWithASwipe` (no `WatchExercisePreviewPage`, `.id(`, `neighbourIndex`, focus-before-selection, `.onChange`, `play(.click)`, left = next, horizontal-only guard, no Crown/`.focusable`) | red | green |
| `WatchPagerFocusTests.testS7913ThePagerViewWiresTheFocusThroughTheSwipe` (rewritten to the new focus-before-selection wiring) | red | green |

Unchanged guards stayed green: S-6610, S-6612, S-7911, S-7912, S-7914..S-7916.

## Mutation pass

12 of 12 mutants killed. The first run left two alive — the swipe direction
(left = next) and the horizontal-only guard — closed by two added source
assertions in `WatchPagerSourceTests.testS9111ThePagerIsOneLoggerWithASwipe`
(`pager.neighbourIndex(of: selection, towardsNext: across < 0)` and
`guard abs(across) > 24, abs(across) > abs(value.translation.height),`).

## Not done

- The Mac/simulator look is NOT done: the owner checks the on-device steps of
  `docs/watch-app-qa-wrist-logging.md` step 34 (swipe feel, no name card, Next
  behaviour) on a real watch.
