# Feature: 52d — a push-up or an ab wheel rollout has a weight row on the watch, like the phone

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE, one minor accepted: the carry-over skips a set logged at 0, as the Dart twin does). Swift 744/0, full flutter +5427 ~2, analyze 180 (baseline); mutants caught (the distance-filter removal is equivalent). A real push-up on a watch is an owner check. Seeded 2026-10-21 (owner, in chat: "plank has weight adjustment but push up or wheel rollout don't, on the phone they do"; "keep going without asking"). Not built. Base commit: `.work/2026-10-21-52d/base.txt`. Team: the crew. The phone half is plan 52c (committed): the phone keeps such a set's `loadKg` in the set's extra-weight row and projects it back. Series: `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md`. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 52d |
|---|---|---|
| Open a push-up or ab wheel rollout set on the watch (exercise without the `load` capability) | one row: reps | two tiles, reps and weight, with the shared − / + and the Crown, exactly like a bench set |
| Dial +10 and log | nothing to dial; the set carries no load | the set carries `loadKg` 10; on the phone it appears as the set's added weight (plan 52c) |
| Dial -20 (a band assist) and log | n/a | `loadKg` -20, kept with its sign down to the wire's floor |
| Leave the weight at 0 and log | n/a | no `loadKg` (as a bench set at 0) |
| The phone planned 5 kg added on that exercise's sets | the wrist ignores it | the weight tile starts at 5 for that set (plan 52c sends it in `plannedSets`) |
| A plank (hold) or a run | unchanged | unchanged (a hold keeps its extra weight row; a run has no weight) |

## Decision Ledger

- D-1 `WatchLoggingState.capability(for:)` (`WatchLoggingState.swift:618`) stops tying `weight` to the `load` capability: the `case WatchMetricKey.weight: return "load"` line goes, so every set effort offers `reps` and `weight`. `distance` keeps its capability. Its doc and the `metricKeys` doc (`:601`, "a bodyweight movement has no load row") are corrected. Everything downstream already follows: the payload (`metricPayload` set case sends `loadKg` when non-zero), the carry-over (`lastLogged`), the planned-row dial-in, the clamp at -200 kg, the units.
- D-2 No wire, phone or Dart watch-client change (the Dart twin under `lib/watch` is not shipped on the Apple Watch: a parity gap, stated in the docs).
- D-3 Existing tests that pin "no weight row for an exercise without load" change meaning: `WatchCrownArmingTests.swift` (~:205-230, "a bodyweight movement has no load row"), `WatchPagerFocusTests.swift` (:220, :391, "the push-up has no load, so no weight row": the focused-slot tests used the missing weight row to tell the exercises apart; use the exercise name and, where fields must differ, a timed/hold slot), and whatever the full run lists.

## Readers listed

- `capability(for:)` has one reader (`metricKeys` filter). `metricKeys` readers: `fields`, `field(for:)`, and the armed-row logic through `fields`.
- Tests: the three above plus any the full `swift test` flags (the builder lists them).
- `watch/contract/*.json` (the capture contract) describes the phone's import of the wrist's sets with and without `load` (`F-CAP`: `extraWeightObservations`); the wrist's own contract tests (`WatchCaptureContractTests`) replay those events through `surface.adjust`: they pass a catalog with load only; the builder confirms by running them.
- Scenario ids S-8101..S-8105 checked free in `test/`, `docs/`, `watch/`.

## Core scenarios

`watch/watchos/Tests/WatchSessionEngineTests/WatchBodyweightLoadTests.swift` (new; harness copied from `WatchCrownUnitTests.swift`):
- S-8101 a push-up slot (`capabilities ["reps","sets"]`) has fields `[reps, weight]` in that order; a hold (`["time","hold"]`) still has only the extra-weight row; a cardio slot (`["time","distance"]`) none.
- S-8102 dial and log: push-up, `model.arm(weight)`, `model.adjust(weight, detents: 4)` (quick 2.5 kg steps -> 10.0), `try await state.log()` -> the stored payload has `reps` and `loadKg == 10`; with the weight left at 0 the payload has no `loadKg` key.
- S-8103 an assist: `adjust(weight, detents: -8)` -> -20.0; the payload `loadKg == -20`; and the -200 floor holds (a huge negative adjust stops at -200).
- S-8104 planned rows: a push-up slot whose `plannedSets` rows carry `loadKg` 5 and 7.5 (build it as `WatchPlannedSetsTests.swift` does, with capabilities `["reps","sets"]` and the phone's rows): the weight tile starts at 5 for set 1 and 7.5 for set 2 after one is logged.
- S-8105 carry-over: after logging a push-up set at 10, the next set's weight tile starts at 10 (last logged).
Plus the D-3 test updates.

## Phases

- P1 (`crew-builder-watch`, glm, `--scope "watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift,.work/crew/2026-10-21-52d/**"`): D-1 as exact text. Done: the full `swift test`, listing every failing test by name and assertion (do not edit tests in this run).
- P2 (same builder, tests): D-3 updates and S-8101..S-8105.
- P3 docs keeper (`watch_surface_wrist.md`). Lead: full `swift test`, `xcodebuild`, analyze, docs tests, full `flutter test` once, mutations (the filter removed/kept, the payload, the clamp, carry-over, planned dial-in), reviewer, commit.

## Owner checks (owner)

- (owner) On the watch: a push-up now has the weight tile; dial +10, log, and the phone shows 10 as the set's added weight; log one on the phone with +5 and the next watch set starts at 5.

## Scope budget

About 10 production lines, about 200 of test, docs about 10. One track, three phases.
