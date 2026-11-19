# Review: 2026-10-20-46a-wrist-logging-basics-plan · P1–P4 · claude_develop..working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 1 · minor 1 · tests: governor-run, not re-run (Swift package 644/0 after phase 2; Dart watch files +83; docs contract tests +42 per brief — the evidence records +40 −1, the −1 the `watch_surface.md` size-band warning, whose rulebook fix — the `watch_surface_wrist.md` split — is in this diff; mutation pass on the model: 9 of 11 mutants red, the 2 green ones unreachable today)
Diff vs Predicted Files: conforms (outside the brief's scope list: only `docs/plans/2026-10-20-46*` — the plan, evidence and series files, the planner's own writes; brief says ignore other paths)

## Findings

1. [Major] `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:818` and `lib/watch/logging/watch_logging_state.dart:644` — the Log clears whichever slot is current *after* its awaits, not the slot it logged. `log()` awaits `endRest` (:812) and `engine.appendObservation` (:817) before `dialled[dialledKey] = nil` (:818); `dialledKey` (:537) re-reads `engine.currentExercise` on every read, and `WatchLoggingState` is a plain class (:160) with async engine methods (`WatchSessionEngine.swift:326,1196`), so a menu pick that lands inside the await window makes the clear wipe the *new* exercise's dialled numbers and leave the logged exercise's dialled values displayed as unconfirmed. Same shape in Dart (`await _engine.appendObservation(event)` then `_dialled.remove(_dialledKey)`). A user would see the 60 kg they dialled on bench vanish because the session jumped during the log's write. Fix: clear by the logged event's own `sessionExerciseId` (built before any await, :790) — `dialled[event["sessionExerciseId"] as? String ?? ""] = nil` — or capture `let loggedKey = dialledKey` before the first await; mirror in Dart. Guard: none pins the key across the await; a test that changes the slot between the event and the clear (a seam or a captured-key assertion) would fail today. 46c's serialisation does not cover this: the fix is local to `log()`.
2. [Minor] `docs/state_management.md:1-159` — the three content edits (the 2026-10-20 split note, the Pages-table link, the `WatchLoggingState` lookup row) rewrote every line of the file (diff +159/−158; the old and new text is otherwise identical, so an invisible-character normalisation, most likely line endings). A maintainer gets `git blame` pointing at this change for lines it did not touch. Fix: none worth making now (content is right); keep future edits to this file line-ending-preserving.

## Brief questions

1. `turn(to:)` divergence — no path found in the changed code. Every event writes `crownPoint` before any guard (`WatchLoggingModel.swift:69-70`: `let moved = position - crownPoint; crownPoint = position`), the binding's `get` returns that same `crownPoint` (`WatchLoggingView.swift:141`), and `arm` deliberately leaves it (`WatchLoggingModel.swift:60-66`), so model and binding always agree and a repeated identical position yields `moved == 0` — no double-applied detent. The ±3200 figure is the view's own range: `crownRangeDetents = 100` (`WatchLoggingView.swift:50`) × `pointsPerDetent = 32`. A wrap at ±3200 would have to come from SwiftUI's `isContinuous: true` semantics, not from this code; if the platform ever reported a reset position, `turn(to:)` re-bases `crownPoint` on that one event and self-corrects — one large jump, never a repeated detent. Guard: the plan's owner check on the real watch (unproven by any unit test, as the plan says).
2. See Finding 1. Awaits between the read (event build, :790) and the clear (:818): `await endRest(at:)` :812, `try await engine.appendObservation(event)` :817.
3. No remaining reader. Grep over `ios/`, `lib/`, `test/`, `docs/`, `watch/` for `crownPosition(for:` / `turn(_…to:` matches only the plan's own description of the removal; the one caller, `WatchLoggingTimersTests.swift:509,515`, is rewritten to `turn(to:)` in this diff.
4. Every name in the new wrist-page paragraphs and QA steps 16–17 resolves: `WatchLoggingModel.armedMetricKey` / `arm(_:)` / `turn(to:)` (model diff), `WatchCrownArmingTests.swift` S-6401..S-6406, S-6408 (read), `WatchLoggingTimersTests.testCrownTurnsAccumulateIntoWholeDetents` (diff), `WatchLoggingState.dialled` / `_dialled` (diffs), `WatchDialledPerExerciseTests.swift` (read), `test/watch_dialled_per_exercise_test.dart` (read), `WatchLoggingView.titleClearance` (view :58–60), the 36 pt buttons (`stepSide`, view :66). No false names.
5. None. `_dialled` in `lib/watch/` appears only at :158 (declaration), :352 (`_dialledKey`), :410 (read), :594 (write), :644 (clear) — the three edited lines plus declaration/getter. Swift `dialled` likewise only at :180, :537, :573, :765, :818. `roundLengthOverrideSecs` is untouched (the D-3404 block at :766–769 is intact and still keyed by slot id).

## Assumption Log rulings

The plan has no Assumption Log section; nothing to rule on. The Decision Ledger holds: D-1..D-5 are implemented exactly as written (ratified by the code read this run); D-6's exclusions held — the pager, `WatchNutritionView`/`WatchEffortRatingView` crown code and the wire are untouched in the diff.

## Scenario coverage

- S-6401 -> `WatchCrownArmingTests.swift · testS6401AFreshSurfaceArmsTheFirstRow`
- S-6402 -> `WatchCrownArmingTests.swift · testS6402ArmingTheWeightRowStepsOnlyTheWeight`
- S-6403 -> `WatchCrownArmingTests.swift · testS6403ArmingDoesNotStepByTheDistanceAlreadyTravelled`
- S-6404 -> `WatchCrownArmingTests.swift · testS6404ArmingDropsTheTravelThatWasShortOfADetent`
- S-6405 -> `WatchCrownArmingTests.swift · testS6405AMeasuredRowIsNeverArmedAndCrownTravelWithoutRowsDoesNothing`
- S-6406 -> `WatchCrownArmingTests.swift · testS6406AnArmedRowIsReCheckedWhenTheExerciseChanges`
- S-6407 -> `WatchLoggingTimersTests.swift · testCrownTurnsAccumulateIntoWholeDetents` (rewritten to `turn(to:)`)
- S-6408 (extra, not in the plan's list) -> `WatchCrownArmingTests.swift · testS6408ArmingAnOpenRowNotifiesTheViewAndARefusedArmDoesNot`
- S-6410 -> `WatchDialledPerExerciseTests.swift · testS6410ADialledValueStaysWithItsExercise`; Dart `test/watch_dialled_per_exercise_test.dart · S-6410 bench reps do not follow the session to squat`
- S-6411 -> `WatchDialledPerExerciseTests.swift · testS6411ALogClearsOnlyTheExerciseItConfirms`; Dart `S-6411 logging squat clears squat and leaves bench dialled`
- S-6412 -> `WatchDialledPerExerciseTests.swift · testS6412AWeightDialledOnOneExerciseDoesNotAppearOnAnother`; Dart `S-6412 squat reads its own initial weight`
- S-6413 -> `WatchDialledPerExerciseTests.swift · testS6413AFreeStartBeforeAnyExerciseHasNoRowsAndDialsNothing`; Dart `S-6413 fields and adjust do not throw`
- S-6414 -> existing `WatchTimedWorkTests · testS3406ARunningPeriodHasNoLengthRowAndKeepsTheDialledLength`, run unchanged (covered by the governor's 644/0)
- D-3 layout (40 mm) -> no unit test by design; screenshots on the simulator, owner check on the real watch (already established, not re-checked)

## Disposition (governor, 2026-10-20)

- Finding 1 (Major): fixed. `log()` now reads the slot key once before its awaits (`loggedKey`), Swift and Dart; test S-6415 in both suites, shown red by the governor's mutation (clear by the current key again: red in both).
- Finding 2 (Minor): fixed. `docs/state_management.md` was CRLF; the edit was redone byte-safely (diff +4 -3).
