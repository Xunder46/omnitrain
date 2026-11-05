# Feature: 51b — the rest screen says what you just did and what comes next

> Status: BUILT, PROVED AND REVIEWED 2026-10-21 (review APPROVE, no findings). Swift 713/0 (12 tests in the new file), full flutter +5416 ~2, analyze 180 (baseline); 11 mutants over the labels rule, two needed tests added, then all caught and restored. How the lines fit on the 40 mm screen is an owner check. Seeded 2026-10-21 (owner, in chat: "the rest screen should just label what's going on now and what's next, it's almost empty anyway ... no changes to mobile needed"; later "just keep going with what we agreed on": the lead builds, reviews and commits this plan without asking in between). Not built. Base commit: `.work/2026-10-21-51b/base.txt`. Team: the crew. Series: `docs/plans/2026-10-21-51a-wrist-crown-and-layout-plan/2026-10-21-51a-wrist-crown-and-layout-plan.md` (the 51 list). Binding conventions: docs/global_conventions.md; docs/rest_tracking.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

Today the rest screen shows the word "Rest", the exercise name, the count-up and a Next button, and nothing about what comes after. After 51b it shows, top to bottom: "Rest"; what you just did; the count-up; what is next; Next.

| Situation when a rest starts | What you just did | What is next |
|---|---|---|
| Bench press, the phone planned 3 sets, 2 logged | "Barbell Bench Press · Set 2 done" | "Next: Set 3 of 3" |
| Bench press, 3 of 3 logged, a later exercise still has planned sets (Squat, 2 planned, none logged) | "Barbell Bench Press · Set 3 done" | "Next: Barbell Back Squat · Set 1 of 2" |
| Plan done and the exercises after it are done, an earlier one is not | as above | "Next: <that earlier exercise>" (with its set when it has a plan) |
| Everything planned is done | as above | "Nothing planned next" |
| A free workout set with no plan, 4 logged | "<name> · Set 4 done" | "Next: Set 5" |
| A period or interval exercise (sports, cardio rounds) | the exercise name | "Next: Period 2" (the modality's own word, singular) |
| A timed or hold effort | the exercise name | the next exercise that still has work (as above), else "Nothing planned next" |
| The rest started after you jumped to an exercise that has nothing logged yet | the exercise name | "Next: Set 1 of 3" (or "Next: Set 1" without a plan) |

"Done" for another exercise means: with planned sets, every planned set is logged; without a plan, at least one effort is logged. The search for the next exercise goes forward from the current one first, then from the top. The phone's sets count the same as the wrist's. The same exercise is never named twice: the next line names an exercise only when it is a different one.

Unchanged: the count-up, the Next button, the ping, the list button, swiping (none in rest), every wire message, the phone, the Dart watch client under `lib/watch`.

## Decision Ledger

- D-1 One pure function `deriveRestLabels(sessionExercises:entries:currentIndex:effortKind:nextRound:) -> WatchRestLabels` in a new file `watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift` (platform independent, so `swift test` covers it), and one property `WatchLoggingState.restLabels` that feeds it from the engine (`engine.session.exercises`, `engine.entries`, the session's `currentExerciseIndex`, `effortKind`, and for a round effort `"<singular roundsLabel> <nextRoundNumber>"`). Same slot walk and slot id rule as `deriveMenuRows` (`WatchMenu.swift:256-283`: `WatchCatalogExercise(slot:)` rejects invalid slots; id `sessionExerciseId` else `exercise.slotId`).
- D-2 Counting: a slot's logged sets = its entries of kind `set`; its efforts = entries in `WatchObservationKind.efforts`; planned = `slot["plannedSets"]` count (the phone projects it only for set slots). "Done" = planned > 0 ? sets >= planned : efforts > 0. The current slot's "Set N done" uses its sets when the effort kind is `set`, else the name alone.
- D-3 Copy lives in `WatchRestLabelCopy` (`nextPrefix = "Next: "`, `nothingNext = "Nothing planned next"`, `noExercise = "No exercise"`), beside the labels, because the view compiles only into the watch target. `WatchRestSurfaceCopy.restCaption` stays "Rest" (pinned by `WatchTimedWorkTests` ~:789).
- D-4 View, `WatchRestView.swift` (exact text in the brief): the name line becomes `labels.now`, centered, two lines at most; a `labels.next` line (secondary colour, two lines at most) sits above the Next button. The view reads `state.restLabels` once per tick (it already re-reads every second).
- D-5 Not in scope: the Dart watch client's rest screen (`lib/watch/logging/watch_rest_screen.dart`, a twin that is not shipped on the Apple Watch; a parity gap noted in the docs), swiping, any phone file, the pager, the rest ping.

## Readers listed

- `WatchRestSurfaceCopy.restCaption`: `WatchTimedWorkTests.swift` ~:789 (unchanged).
- `WatchRestView` text readers: none in `watch/watchos/Tests` (grep); `ContentView.swift` mounts it (unchanged call, same init).
- `WatchLoggingState.exerciseName` stays (the logging screen reads it).
- Scenario ids S-7601..S-7610 checked free in `test/`, `docs/`, `watch/`.

## Core scenarios

`watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift` (new). The pure function is tested with hand-built slots and observation records; two scenarios go through the real engine and `WatchLoggingState`.
- S-7601 planned set 2 of 3 logged → now "Barbell Bench Press · Set 2 done", next "Next: Set 3 of 3" (numbers unlike any default: plan of 4, 3 logged → "Next: Set 4 of 4" as a second case).
- S-7602 plan complete, a later exercise with 2 planned and none logged → next "Next: Barbell Back Squat · Set 1 of 2".
- S-7603 two arms of the search order: (a) current done, BOTH a later and an earlier exercise unfinished → names the LATER one; (b) current done and last in the ladder, only an earlier exercise unfinished → names the earlier one.
- S-7604 everything done → next "Nothing planned next"; the current slot carries no number it should not.
- S-7605 free set (no `plannedSets`), 4 logged → now "<name> · Set 4 done", next "Next: Set 5".
- S-7606 current exercise with nothing logged (rest after a jump): now is the name alone; next "Next: Set 1 of 3" with a plan, "Next: Set 1" without.
- S-7607 round effort with `nextRound: "Period 2"` → next "Next: Period 2", now the name alone; with `nextRound` nil it falls through to the exercise search.
- S-7608 timed effort, a later exercise unlogged → "Next: <that name>"; none left → "Nothing planned next".
- S-7609 through the engine (`Harness`, a slot with `plannedSets` of 3 rows as in `WatchPlannedSetsTests`, one set logged through `WatchLoggingState.log()`): `state.restLabels` is now "… · Set 1 done", next "Next: Set 2 of 3"; after a second log "Set 2 done" / "Next: Set 3 of 3". A phone entry for the same slot (a snapshot entry) counts: arrange it like `WatchPlannedSetsTests` does, and assert the count rises.
- S-7610 source guard: `WatchRestView.swift` (comments stripped) reads `restLabels`, shows `labels.next`, no longer reads `exerciseName`, and still has the Next button and `restCaption`.

## Phases

- P1 (`crew-builder-watch`, glm, `--scope "watch/watchos/Sources/WatchSessionEngine/WatchRestLabels.swift,watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift,watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift,.work/crew/2026-10-21-51b/**"`): D-1, D-3, D-4 as EXACT TEXT in the brief. Done: `swift test --filter WatchSessionEngineTests` (the append-only guard: new function names must not start with a banned verb; `deriveRestLabels` and `restLabels` do not), `--filter WatchRestSurfaceTests`, `--filter WatchTimedWorkTests`. The lead builds the watch target with `xcodebuild` (the view is watchOS-only).
- P2 (`crew-builder-watch`, glm, after P1, `--scope "watch/watchos/Tests/WatchSessionEngineTests/WatchRestLabelsTests.swift,.work/crew/2026-10-21-51b/**"`): S-7601..S-7610; no production edit.
- P3 (`crew-docs-keeper`): `docs/state_management/watch_surface_wrist.md` (the rest screen's two new lines and the rules), `docs/rest_tracking.md` (one sentence: the wrist's rest screen names what is next), the evidence file.
- Lead after each run: diff vs the lists, `swift test` full, `flutter analyze` (unchanged count), the docs tests, the full `flutter test` once at the end, the invariant grep, `xcodebuild` of the watch scheme; then the lead's mutation pass: each branch of the next-line rule (unplanned, partial plan, plan done, forward search, backward search, nothing left, round, timed) and the current-slot count (sets vs efforts); then the reviewer; commit.

## Owner checks (owner)

- (owner) On the watch: log a set on a planned exercise, read the rest screen: the exercise and "Set N done" on top, "Next: Set N+1 of M" below the count-up; finish the last planned set of an exercise and see the next exercise named; the text fits on 40 mm without covering Next.

## Scope budget

About 90 lines of production (new file about 80, state property about 12, view about 12) and about 200 of test, docs about 20. One track, three phases.
