# Feature: 52 — the Crown is the fine control, the buttons the quick one; no card flashing when you swipe to another exercise

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE WITH FIXES: two Majors fixed, a focus that outlived its landing and a clock started against an exercise the engine had not reached; one minor, the plan text about holds, corrected). Swift 739/0, full flutter +5416 ~2, analyze 180 (baseline); 22 mutants caught and restored. How the Crown and the swipe feel on a watch are owner checks. Seeded 2026-10-21 (owner, in chat after using the watch: "1) can we make the crown granular control, 1 digit per click, vs plus and minus as quick stepper? 3) we don't need this middle screen flashing for a second when switching the exercise"; and earlier "keep going without asking"). Not built. Base commit: `.work/2026-10-21-52/base.txt`. Team: the crew. The owner's point 2 (push-up and ab wheel have no weight row on the watch, the phone has one) is plan 52c, not this plan. Series: `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md`. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 52 |
|---|---|---|
| Turn the Crown on a weight | one click = one plate step (2.5 kg, or 5 lb) | one click = 1 kg (1 lb) |
| Turn the Crown on a period's length | one click = 5 s | one click = 1 s |
| Turn the Crown on reps, rounds, distance | 1 rep / 1 round / a tenth of the unit | unchanged (they are already one digit per click) |
| Press the − / + under the tiles or beside a single value | the plate step, 5 s, 1 rep | unchanged: the quick step |
| Swipe to another exercise | the new page shows a card with the name and "N logged" for a moment (the engine is still moving), then becomes the logger | the new page shows the logger of the new exercise at once; the name-only card is seen only while the page is sliding in |
| Swipe while an effort clock runs, or swipe back after a refusal | notice / snap back | unchanged |

Weights are 1 kg or 1 lb per Crown click whatever the display unit; "42.5" goes to "43.5". Distance keeps its tenth. The rating screen and the food portion keep their own steps (one rating number, half a serving).

## Decision Ledger

- D-1 `WatchMetricStepping` (`watch/watchos/Sources/WatchSessionEngine/WatchMetricStepping.swift`) gains the Crown's step: `fineStep(for:units:)` = 1 kg (1 lb converted) for `weight` and `extraWeight`, 1 s for `duration` and `roundDuration`, and for every other key exactly `step(for:units:)` (reps, rounds, distance). `adjust(_:metricKey:detents:units:)` gets a last parameter `fine: Bool = false` that picks the step. `step(for:)` and every existing caller are unchanged (the buttons, tests of the table, the capture contract).
- D-2 `WatchMetricField` (`WatchLoggingState.swift:84`) gains `fineStep: Double` (init parameter last, `fineStep: Double? = nil`, stored as `fineStep ?? step`); `field(for:)` (`:590`) passes `WatchMetricStepping.fineStep(for: metricKey, units: units)`. `WatchLoggingState.adjust(_ metricKey:, detents:, fine: Bool = false)` (`:775`) passes `fine` through.
- D-3 `WatchLoggingModel.turn(to:)` (`WatchLoggingModel.swift:67-77`), the Crown's path, calls `state.adjust(key, detents: detents, fine: true)`. `WatchLoggingModel.adjust` and `stepArmed` (the buttons) stay quick.
- D-4 Existing Crown tests that read the step after a Crown turn must read `fineStep`: `WatchCrownArmingTests.swift` (:88-89, :117, :142 and what they assert), `WatchLoggingTimersTests.swift` (~:509-515 reps, unchanged value), `WatchCrownUnitTests.swift` (reps, unchanged). Tests that use the buttons or `WatchMetricStepping.step(for:)` stay as they are.
- D-5 No flash: `WatchLoggingState.focusSlotId: String?` (new, plain stored property, `WatchLoggingState.swift`). The private `slot` (`:533`, `engine.currentExercise`) becomes: the session exercise whose id (`sessionExerciseId`, else `WatchCatalogExercise(slot:)?.slotId`) equals `focusSlotId`, else `engine.currentExercise`. So the logging surface can show the exercise the user swiped to before the engine has moved to it.
- D-6 `WatchPagerModel.focusSlotId(for index: Int) -> String?` (new, `WatchPagerModel.swift`): nil when the index is out of range, the page is the engine's current exercise, or the session is locked; else that row's `slotId`. In the pager view: the `TabView`'s selection binding sets `state.focusSlotId = pager.focusSlotId(for: newValue)` synchronously when a swipe settles; the page at the selected index renders the logger (not the card) and its counter reads `selection + 1` of the count; `land(on:)` clears `state.focusSlotId` when it finishes whether it moved or was refused. The preview card stays for the pages that are not selected (what slides in).
- D-7 Not in scope: the preview card's content, the menu sheet's jump (it already lands with the engine), the Dart client, the quick steps.

## Readers listed

- `WatchMetricStepping.adjust` callers: `WatchLoggingState.adjust` (`:780`), `WatchLoggingTimersTests` (many, default `fine` false: unchanged), `WatchTimedWorkTests:744`.
- `WatchLoggingState.adjust` callers: `WatchLoggingModel.adjust`, `stepArmed`, `turn` (now fine), `WatchCaptureContractTests:170` (`detents: (value - field.value) / field.step`, quick: unchanged), `WatchDialledPerExerciseTests:164`.
- `WatchMetricField(` constructed only in `field(for:)`.
- `slot` readers inside `WatchLoggingState` (exerciseName, effortKind, observations, dialledKey, plannedSets, log): all follow the override; grep `slot` before building. `focusSlotId` is read nowhere else.
- `WatchPagerSourceTests` (`:105`, `:131-140`): the pager still binds no Crown and takes no focus.
- Scenario ids S-7901.. checked free in `test/`, `docs/`, `watch/`.

## Core scenarios

`watch/watchos/Tests/WatchSessionEngineTests/WatchFineCrownTests.swift` (new):
- S-7901 the table: `fineStep` weight kg 1, weight lb (units pounds) = `toKilograms(1, "lbs")`, extraWeight 1 kg, duration 1, roundDuration 1, reps 1, rounds 1, distance = `step(for: distance)`; and `step(for: weight) == 2.5` still (the quick step is untouched).
- S-7902 a Crown click on a weight steps it by 1 kg: bench set (weight 0), `model.arm(weight)`, `model.turn(to: 1)` -> 1.0; `turn(to: 3)` -> 3.0 (value unlike the 2.5 plate); the − / + path (`model.adjust(weight, detents: 1)`) from 3.0 -> 5.5.
- S-7903 a Crown click on a period's length (a round effort's duration row) steps 1 s while `adjust` steps 5 s; a hold carries no dialled duration row (only its extra weight), so no hold row is claimed.
- S-7904 pounds: units pounds, one Crown click on weight moves the DISPLAYED weight by 1.0 (`displayValue` "1.0" then "2.0"), the buttons by 5.0.
- S-7905 `WatchMetricField.fineStep` equals `fineStep(for:)` and defaults to `step` when not given.

`watch/watchos/Tests/WatchSessionEngineTests/WatchPagerFocusTests.swift` (new; harness copied from `WatchPagerModelTests.swift`: three slots A, B, C, current A):
- S-7911 `focusSlotId` on the state: set to B's id -> `exerciseName` is B's, `fields` are B's (B has a different capability set than A: a push-up with no `load` vs a bench), `log()` stores an entry whose `sessionExerciseId` is B's; set back to nil -> A's; an unknown id -> A's (falls back).
- S-7912 `pager.focusSlotId(for:)`: index of the current page -> nil; index of B -> B's id; out of range -> nil; locked (a running work clock) -> nil.
- S-7913 source guards (comment lines stripped): the pager view's `TabView` selection binding calls `focusSlotId(for:`; the page choice uses `index == selection`; `land` clears `focusSlotId`; the counter uses `selection`.

## Phases

- P1 (`crew-builder-watch`, glm, `--scope "watch/watchos/Sources/WatchSessionEngine/WatchMetricStepping.swift,watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift,watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift,.work/crew/2026-10-21-52/**"`): D-1..D-3 as exact text. Done: `swift test --filter WatchSessionEngineTests` (the append-only guard; new names `fineStep`, `fineKilogramsPerDetent` start with `fine`, not a banned verb), listing the existing tests that now fail because they read `step` after a Crown turn (do not edit tests in this run).
- P2 (same builder, tests): D-4 (update the existing Crown tests to `fineStep`) and S-7901..S-7905.
- P3 (same builder, exact text): D-5, D-6 in `WatchLoggingState.swift`, `WatchPagerModel.swift`, `WatchLoggingPagerView.swift`. The lead builds the watch target.
- P4 (same builder, tests): S-7911..S-7913.
- P5 docs keeper (`watch_surface_wrist.md`). Lead: full `swift test`, `xcodebuild`, analyze, docs tests, full `flutter test` once, mutations (each fine step, the `fine` flag path in the model, `focusSlotId` fallback, the locked/current/out-of-range arms of `focusSlotId(for:)`, the view guards), reviewer, commit.

## Owner checks (owner)

- (owner) Crown on a weight: one click is 1 kg (1 lb); the − / + still jump the plate step. Crown on a period's length: 1 s per click.
- (owner) Swipe between exercises: the new exercise's logger is there immediately, no name card lingering; swipe again quickly; swipe during a running clock still refuses.

## Scope budget

About 90 production lines, about 250 of test, docs about 15. One track, five phases (the last is docs).
