# Feature: 51a — the Crown moves one step per click, the reps/weight screen fits

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE, one minor fixed: one separator in the status line). Swift 701/0, full flutter +5416 ~2, analyze 180 (baseline), mutation pass red then restored. The Crown feel on a real watch and the position of Log on the 40 mm screen are owner checks (the Simulator was blocked by a Health permission dialog). Seeded 2026-10-21 (owner, in chat, after a real-watch check: "the Crown barely works, I need to scroll so much to move one digit; the plus and minus buttons overlap between row 1 and 2 in resistance; the Log button still pushes below the view"; owner approved "a shared stepper under two value tiles"). The phone-side ping fix the owner also approved was split into `docs/plans/2026-10-21-51g-phone-rest-pings-plan/` by the scope guard (two tracks and four phases are two soft signals). Not built. Base commit: `.work/2026-10-21-51a/base.txt`. Team: the crew. Facts from the re-audit `.work/crew/2026-10-21-51-watch-reaudit/FINDINGS.md` and the lead's own reads (every quote below was read from disk 2026-10-21).
> Series: first of 51a-51f (the re-audit's follow-up; list at the end). Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 51a |
|---|---|---|
| Turn the Crown on the logging screen (reps, weight, a drill's extra weight, a period's length), the rating screen or the food portion | one value step needs about 32 times the rotation a normal watch picker needs | one Crown click steps the value once, the way a system picker does |
| Look at a resistance set (reps and weight) on a 40 mm watch | two rows, each with its own − and +; the buttons overlap the next row and Log is pushed below the screen edge | two value tiles side by side (reps, weight), the outlined tile is the one the Crown steps, one − and one + under them, Log fully on screen |
| Tap a tile | arms that row | unchanged: the tile gets the outline, the Crown steps it |
| Tap − or + | steps that row | steps the outlined tile |
| A screen with one value (a period's length, a drill's extra weight) | one row with − and + around the value | the same row; the buttons no longer overlap anything and are 32 pt, not 36 |
| The set caption ("Set 3 of 4") and the heart-rate/distance line | two lines | one line: "Set 3 of 4 · 142 bpm" (either half alone when the other is absent) |

Unchanged: the Crown never changes exercise; the swipe pager; the rest screen; every wire message.

## Owner decisions (2026-10-21)

- O-1 Two values on one screen show as two side-by-side tiles with one shared − / + pair under them (rejected: keeping a pair per row; dropping the buttons).
- O-2 (lead's default, owner may veto) Sensitivity stays `.medium`; it is one named place per screen so a device check can move it to `.high` with a one-word edit.

## Decision Ledger

- D-1 Cause of the slow Crown: `WatchMetricStepping.pointsPerDetent = 32` (`watch/watchos/Sources/WatchSessionEngine/WatchMetricStepping.swift:56`, doc: "Points of crown travel that count as one detent on every wrist surface… the Flutter surface accumulates against the same number") is passed as the `by:` of `.digitalCrownRotation(detent:from:through:by:sensitivity:…)` on three screens (`WatchLoggingView.swift:137-145`, `WatchEffortRatingView.swift:58-67`, `WatchNutritionView.swift:157-166`). On watchOS the Crown reports value units, and one `by` step needs rotation proportional to `by`: 32 is the Flutter/Wear OS drag-points constant, not a watchOS unit. Change the Swift constant's value to 1 (one value unit per detent); the Dart client keeps its own `WatchRotaryTurn.defaultPointsPerDetent` (`lib/watch/widgets/watch_controls.dart:18`), nothing ties the two (grep of `watch/contract`, `test/`, `watch/watchos/Tests`: only symbol references). Every Swift reader uses the symbol (`WatchCrownArmingTests` 10 sites, `WatchLoggingTimersTests` 2, `WatchEffortRatingTests` `:625`, `:668`), so they keep their meaning; ranges (`crownRangeDetents` 100) become ±100 units.
- D-2 The new constant's doc says what it is: "Crown value units per detent on watchOS: `.digitalCrownRotation(by:)`'s step. The Dart client counts drag points separately." The magnitude (rotation per click at `.medium`) is verified on a device: owner check (the simulator has no Crown).
- D-3 `WatchLoggingModel.stepArmed(_ detents: Double)` (new, `WatchLoggingModel.swift`, beside `adjust`): steps the armed row (`armedMetricKey`: the row the user armed while it is still open and unmeasured, else the first open row) by `detents` and polls; no armed row (every row measured, or no rows) is a no-op. The name avoids the append-only guard's verbs (rule ac, `watch/watchos/Sources`).
- D-4 `WatchLoggingModel.statusLine: String?` (new): `[state.setCaption, sensorLine]` compact-mapped and joined with `" · "`, nil when both are nil. `sensorLine` moves from `WatchLoggingView` (`:209-217`) into the model unchanged except the join separator, so the desktop toolchain can test it. The header shows `statusLine` as one `caption2` line (`lineLimit(1)`, `minimumScaleFactor(0.7)`) in place of the two lines it replaces.
- D-5 Layout rule (view only, `WatchLoggingView.swift`): `fields.count > 1` → tiles in one `HStack` + the shared stepper; `fields.count == 1` → today's single row `[−][tile][+]` (its height must not grow: the period screen carries a 40 pt readout); `0` → nothing. The step buttons stop using `.buttonStyle(.bordered)` (its drawn size is larger than the 36 pt frame forced on it: the overlap) and become fixed-size plain-style capsules (`stepSide` 32 for the single row, `stepHeight` 32 and full width for the shared pair). Estimated worst case on 40 mm for resistance (name + set/heart-rate line + tiles + stepper + Log) is about 166 pt against about 195 pt before; these are font-metric ESTIMATES: the lead measures the real position on the 40 mm simulator (owner check if the Simulator cannot be driven).
- D-6 Not in scope: the nutrition screen's own −/+ buttons (not reported; its Crown unit does change through D-1), the rest screen (51b), the pager (51c), Always-On and accessibility (51e), anything on the wire.

## Readers listed (rule: every reader of what the seed changes)

- `WatchMetricStepping.pointsPerDetent` / `WatchLoggingModel.pointsPerDetent` / `WatchNutritionModel.pointsPerDetent`: Swift `WatchCrownArmingTests.swift` (:74, :96, :120, :124, :131, :145, :149, :156, :195), `WatchLoggingTimersTests.swift` (:509, :515), `WatchEffortRatingTests.swift` (:625, :668); views `WatchLoggingView.swift`, `WatchEffortRatingView.swift`, `WatchNutritionView.swift`; models `WatchEffortRating.swift:236-244`, `WatchNutritionView.swift:30,56-57`. Nutrition model `turn(to:)` carries a fractional position: with 1 per detent the existing arithmetic holds.
- `WatchLoggingView.swift` text readers: `WatchPagerSourceTests.swift` (:105 the shell mounts the pager; :131-140 the pager binds no Crown): neither reads the rows. `test/watch_logging_surfaces_test.dart` is the Dart client's own screen (different file, untouched).
- `sensorLine` readers: only the view (grep `sensorLine` in `watch/watchos`).

## Core scenarios (ids S-7501.. checked free in `test/`, `docs/`, `watch/`)

Swift, `watch/watchos/Tests/WatchSessionEngineTests/WatchCrownUnitTests.swift` (new; harness copied from `WatchCrownArmingTests.swift`):
- S-7501 `WatchMetricStepping.pointsPerDetent == 1`, and `WatchLoggingModel.pointsPerDetent` equals it (fails at 32).
- S-7502 a reps row at 10: `model.turn(to: 1)` makes reps 11 (value unlike a default: also assert `turn(to: 3)` from 1 gives two more steps: 13) — at 32 the same turns leave reps at 10 with a carry.
- S-7503 the rating state: `turnCrown(to: 1)` from nothing picks the lowest number, a second `turnCrown(to: 2)` picks the next (fails at 32).
- S-7504 source guard (`WatchNutritionModel` is inside `#if os(watchOS)`, so the desktop toolchain cannot build it): `WatchNutritionView.swift` declares `pointsPerDetent = WatchMetricStepping.pointsPerDetent` and no literal; fails if that line carries a number.
- S-7505 source guard: the three `digitalCrownRotation` sites pass `by:` the constant, never a literal (`by: 32`, `by: 1`): reads the three view files.

Swift, same package, `WatchLoggingStatusTests.swift` (new; harness copied from `WatchCrownArmingTests.swift`):
- S-7511 `stepArmed(1)` on a reps+weight set steps the first open row (reps) and not weight; after `arm(weight)`, `stepArmed(1)` steps weight and not reps; `stepArmed(-1)` steps down.
- S-7512 `stepArmed` with every row measured (a run's distance kept by a sensor) and with no rows changes nothing.
- S-7513 `statusLine`: caption + heart rate → "Set 2 of 4 · 142 bpm"; caption alone → "Set 2 of 4"; sensors alone (free workout, no plan) → "142 bpm"; neither → nil. Pick the numbers unlike any default (rate 143, set 3 of 5).
- S-7514 source guard on `WatchLoggingView.swift`: no `.buttonStyle(.bordered)` on the step buttons, and the shared pair exists (`stepArmed(` appears twice).


## Phases

- P1 (`crew-builder-watch`, `--scope "watch/watchos/Sources/WatchSessionEngine/WatchMetricStepping.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchCrownUnitTests.swift,.work/crew/2026-10-21-51a/**"`): D-1, D-2; S-7501..S-7505. Done: `swift test --filter WatchCrownUnitTests`, `--filter WatchCrownArmingTests`, `--filter WatchEffortRatingTests`, `--filter WatchSessionEngineTests` (the append-only guard), never the full flutter suite. Serial before P2 (one Swift package).
- P2 (`crew-builder-watch`, `--scope "watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift,watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingStatusTests.swift,.work/crew/2026-10-21-51a/**"`): D-3, D-4, D-5 as EXACT TEXT in the brief (the lead writes the replacement code into the brief; rule z), then S-7511..S-7514 as a separate run that copies a named helper block. After P1. Done adds `xcodebuild` of the watch scheme by the lead (the view compiles only in the watch target).
- P3 (`crew-docs-keeper`, after P2 and the last test-adding fix): `docs/state_management/watch_surface_wrist.md` (Crown unit, tiles + shared stepper, status line), this plan's evidence file. `watch/sync_protocol/PROTOCOL.md` untouched (no wire change).
- Lead verification after each: diff vs the lists above, `swift test`, the full `flutter test` once at the end (900 s, not while a prover runs; the Dart client's Crown tests must stay green), `flutter analyze` count vs baseline, the invariant grep, then the prover (`crew-prover`) with the lead's mutation pass: S-7501 (32), S-7502 (`by`/constant), S-7511 both arms, S-7513 each of the four cases.

## Owner checks (owner)

- (owner) On the real watch: the Crown moves a value one step per click on reps, weight, a drill's extra weight, the rating screen and the food portion; too fast or too slow → say which and the lead moves `.medium` to `.high` or `.low` (one word per screen).
- (owner) The reps+weight screen on the 40 mm watch: Log fully visible with a set caption and a heart-rate reading on; tiles and the shared pair read cleanly; one-value screens unchanged in height.

## Scope budget

About 280 changed lines in three phases (Swift view and model about 130, Swift tests about 120, docs about 30), one track. The rest of the re-audit follows as 51b-51f, and the phone ping fix as 51g.

## Series 51 (the re-audit's follow-up; each its own plan)

51a this plan · 51b rest screen Now / Next · 51c pager polish · 51d failure and sync-status visibility on the wrist · 51e haptics, Always-On, accessibility · 51f sync hardening · 51g phone rest pings (the phone cancels its pings when the watch ends a rest; Dart only). Audit: `.work/crew/2026-10-21-51-watch-reaudit/FINDINGS.md`.
