# Plan 225 — The exercise picker ignores a workout the wrist has ended

Series: watch integration review on a 40 mm watchOS 26.4 simulator (2026-11-17), a bug found beside plan 223. Watch package only (`WatchStartPaths.swift`), one builder run, then docs. Status: BUILT, verified, uncommitted. Seeded by the lead; no architect run (the seed carries exact code, precedent plans 58-60).

> Base commit: `9e1e5a65` on `claude_develop`. Plan 223 is uncommitted in the same tree (view files, `WatchStartView.swift`, `ContentView.swift`, three docs); this plan touches none of its files.

## Goal and acceptance

Seen on the simulator: the wrist's newest workout had been discarded. After a relaunch, tapping the Cardio tile opened the exercise picker with the discarded workout's three exercises (Barbell Bench Press, Standing Overhead Press, Plank) as prominent "in this session" rows above Recommended. Tapping one wrote another `abandoned` row to the discarded workout, sent the phone two frames about it, and closed the picker without starting anything.

Cause: the engine keeps reporting the ended workout as `engine.session` (after a discard or Finish, and after a relaunch, because `WatchSessionEngine.restore()` restores the newest row whatever its status). The start paths read that session's ladder with no status check: `WatchSessionStartPaths.pickerRows`, `availablePickerExercises` and `listModality`; and `selectExercise(_:)` moves or adds inside it. The picker view sends an in-session tap to `selectExercise`, so the tap lands in the ended workout.

Reproduced by the lead on the base commit, before any build: `swift test --filter WatchEndedSessionPickerTests` → `Executed 3 tests, with 28 failures`; S-22501 and S-22503 red in all four cases (discarded / finished × with / without relaunch), S-22502 green (a regression guard: the start itself already creates a new workout).

Acceptance: S-22501 and S-22503 red at the base commit (observed), all three green after the build; `swift test` whole target green with observed counts; the watch app target builds (`xcodebuild`, lead); the lead's mutation pass kills each mutant in the list.

## What the user sees

- After a workout ends (discarded or finished), tapping a modality tile opens the picker with no "in this session" rows: the whole list, ranked by the tile tapped (Recommended for that modality first).
- Picking any exercise, including one the ended workout held, starts a new workout with that tile's modality and that exercise. The ended workout is never written to again from the picker, and the phone hears nothing about it.
- Same with or without a relaunch in between.
- To SEE it: start a workout with two exercises, open the menu, Discard Session, then tap Cardio: the picker shows no prominent rows; pick Bench Press and the logging screen opens a new workout.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-22501 | `WatchSessionStartPaths` gains one private read, `liveSession`: `engine.session` when its `status == WatchSessionStatus.active`, otherwise nil. `pickerRows`, `availablePickerExercises` and `listModality` read `liveSession` instead of `engine.session`. An ended workout is no ladder to offer rows from, to remove exercises from the list for, or to rank by. | `WatchStartPaths.swift` `pickerRows` (~854), `availablePickerExercises` (~868), `listModality` (~767) |
| D-22502 | `selectExercise(_:)` returns nil and writes nothing when there is no `liveSession`, for both row kinds. A tap that reaches it after the workout ended changes nothing; in a modality start the view already sends `.available` picks to `startModalityWorkout`, which creates a new workout over an ended one (S-20113). | `WatchStartPaths.swift` `selectExercise(_:)` (~916); `WatchStartView.swift` `WatchExercisePickerView.select` (~512, unchanged) |
| D-22503 | The engine is unchanged: `engine.session` keeps reporting the ended workout (the summary, rating and recovery read it), and `engine.selectExercise(slotId:)` stays as it is (the phone's jump path calls it, `WatchSessionEngine.swift:597`, `:1042`). The fix is in the start paths, the picker's only source. | `WatchSessionEngine.swift` `session`, `restore()`, `selectExercise(slotId:)` |
| D-22504 | `addExerciseToSession`, `addExerciseToEnd`, `startModalityWorkout`, the menu and the views are unchanged (the menu exists only over a live workout; the start already handles an ended one). No wire, phone or copy change. | scope |

## Scenarios

All in the new `watch/watchos/Tests/WatchSessionEngineTests/WatchEndedSessionPickerTests.swift` (written by the lead before the build). Fixture: `WatchModalityStartFixture.wrist()` (synced `routines_down`: Barbell Bench Press, Goblet Squat, Plank); a `resistance_lifting` workout gets Bench Press then Plank through `addExerciseToSession`, then ends by `abandonSession()` or `finishSession()`, optionally followed by `harness.launch()` (a relaunch over the same store). Each test loops the four cases.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22501 | Ended workout, then `beginModalityStart("cardio_endurance")`. | `pickerRows` has no in-session row; `availablePickerExercises` is `[bench, goblet, plank]`; `listModality == "cardio_endurance"`. | the base offers Bench and Plank as in-session rows, offers only Goblet Squat as available, and ranks by `resistance_lifting` (observed: 12 failures) |
| S-22502 | Ended workout, start mode, `startModalityWorkout("cardio_endurance", with: bench)`. | a new `active` row, not the ended record, modality `cardio_endurance`, exercises `[bench]`; the ended rows in the store are exactly those before the pick. | passes on the base on purpose: pins that the pick starts a new workout and writes nothing to the ended one (mutation (d) breaks it) |
| S-22503 | Ended workout; `paths.selectExercise(.inSession(slot 0))`, then `paths.selectExercise(.available(bench))`. | both nil; no session row appended; no frame emitted. | the base moves and adds inside the ended workout: 2 rows appended, 2 frames sent, both calls return the ended record (observed: 16 failures) |

## Input-reality checklist

1. **Writers.** The only writer of the ended rows here is the picker's `selectExercise`; after D-22502 it writes nothing without a live workout. The phone's pushes and jumps go through the engine and are unchanged.
2. **Lifecycle.** The engine holds the ended record from the moment of Discard/Finish until the next `createSession`; the picker can open in that window with or without a relaunch (both cases are in every scenario). A workout started from the phone while the picker is open makes `liveSession` non-nil on the next read, so its ladder appears as before.
3. **Settings.** None.
4. **Time.** None.
5. **Cost.** One status comparison per read.
6. **Words.** None.
7. **Readers.** `pickerRows`, `availablePickerExercises`: `WatchStartView.swift` (`WatchExercisePickerView`), tests in `WatchSessionStartPathsTests`, `WatchModalityStartTests`, `WatchMenuTests`. `listModality`: `WatchStartView.swift:487`, `WatchMenu.swift:323` (menu, live only), `WatchSessionStartPathsTests` S-19911/S-19922 (live or no session only: unaffected). `selectExercise(_:)`: `WatchStartView.swift:519`, `WatchMenu.swift:251` (live only). The append-only source guard: the new name `liveSession` is a property, no banned verb.

## Phases

1. **P1 crew-builder-watch**, scope `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, `watch/watchos/Tests/**`, the run's report path: apply the exact code in the brief; run the new test file and the whole package target. No full Flutter suite.
2. **P2 crew-docs-keeper**: the Docs delta row.
3. **P3 lead**: mutation pass, `xcodebuild` of the watch app target, review.

## Mutation list (lead)

(a) `liveSession` ignores the status (returns `engine.session`); (b) `pickerRows` reads `engine.session` again; (c) `listModality` reads `engine.session` again; (d) `selectExercise` drops its guard; (e) `availablePickerExercises` reads `engine.session` again.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/watch_reference_data.md` | ADDED | — | A workout the wrist has ended is no live ladder | S-22501, S-22503, D-22501 |

Stale-term sweep (`grep -rIn "in-session row\|pickerRows\|listModality" docs`, outside plans and history): `watch_reference_data.md:134-160` only; its sentences say "the live ladder" and "the live session's own modality", which stay true once "live" means an active workout.

## Open items

1. (owner) Simulator or device check: discard a workout, tap a tile, see no prominent rows; pick an exercise and a new workout opens.

## Predicted files

`WatchStartPaths.swift` (~+15), `WatchEndedSessionPickerTests.swift` (new, lead), one doc sentence.

## Progress

- [x] Repro on the base commit (lead): 3 tests, 28 failures
- [x] Seeded
- [x] P1 build (crew-builder-watch, 2 min; diff exactly the brief: +17 -4)
- [x] P2 docs (crew-docs-keeper, 45 s; plan-lint after clean)
- [x] P3 lead: whole target 1,594 tests 0 failures; mutation pass 6/6 killed; watch app `xcodebuild` BUILD SUCCEEDED; lead review, no findings

## Assumption Log

- 2026-11-17: scenario/decision ids S-225xx/D-225xx: none found in `docs`, `watch`, `test`, `lib`.
- 2026-11-17: no owner question: the behaviour (an ended workout offers nothing and takes nothing) follows D-171 ("a session the wrist already ended does not hold the slot") and S-20113.

## Feedback

(none yet)
