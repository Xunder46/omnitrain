# Plan 257 — Finish drops the intervals, holds and rounds nobody started

Review item 27 (owner list: "Finish keeps never-started intervals, holds and rounds. Suggested: drop them at Finish, the same way unlogged sets are dropped.").
Phone only. No wire, watch, storage or schema change. Mirrors plan 157a (Finish drops unlogged sets).

## Goal and acceptance

When the user taps Finish, the workout that is saved no longer contains the interval (`timed`), hold (`drill`) and round entries that were never started.

- A timed, hold or round entry whose timer state is `notStarted` is dropped at Finish; the entries that were started or finished keep their order and numbering (the same re-indexing the logger's delete does), and the rests that marked them stay with the right entries.
- An exercise left with no entry is removed from the workout, except in a workout the watch took part in, which keeps its exercises (a late wrist set must still have an exercise to land in), as plan 218 decided for sets.
- A running or paused entry at Finish is not dropped (it is persisted as today).
- Sets keep behaving as plan 157a decided; the "Finish would save nothing" check is unchanged (it already treats a never-started timer as no work).
- The summary, history and Stats therefore no longer show empty intervals, holds or rounds.

Acceptance: S-25701..S-25709 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Start a workout with an interval exercise and two rounds, run only the first round, tap Finish: the summary shows one round; the second, never started, is gone. An interval exercise you never ran is not in the saved workout at all.
- To SEE it: add an interval or hold exercise, do not run it, add a set exercise and log a set, Finish: the saved workout has only the set exercise.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25701 | New `_dropNeverStartedTimers({bool keepEfforts = false})` in `SessionCoreLifecycleMethods`, beside `_dropUnloggedSets`. For every effort of kind `timed`, `drill` or `round` it walks the entries from the last to the first; an entry whose instance state is `notStarted` is removed through the manager (`deleteTimedEntry` / `deleteRound`, which also re-index the entries after it and delete the entry's own rows) and then `rekeyEntryRestsAfterDelete(effortId, index)`, exactly the order `SessionCore.deleteEntry` uses. An effort that lost entries and has none left is deleted (`_repository.deleteEffort`, `_observations.remove`, `_timerManager.removeEffort`, removed from the segment list) unless `keepEfforts`. | `session_core_lifecycle.dart:130-180` (`_dropUnloggedSets`), `session_core_entry.dart:725-748` (`deleteEntry`), `timer_manager.dart:882,1232` |
| D-25702 | `endSession` calls it at every place it calls `_dropUnloggedSets`, with the same `keepEfforts` value, inside the same shielded `try` (D-10: a failing drop never turns the end into an error). | `session_core_lifecycle.dart:30-60` |
| D-25703 | Not changed: `finishWouldSaveNothing` and `completedExerciseCount` (they already count a timer only when it left `notStarted`), the wrist importer, rolling sessions' own rules (a rolling session is saved through the same `endSession`). | `session_core_lifecycle.dart:195-221` |

## Scenarios

Fixtures. A live workout on `WorkoutState(repo)` (Mock and Hive through `harnessFactories`, plain `test()`); exercises from `repo.getExercises()` (any exercise works with `effortKindOverride`). Timed/hold entries: `addExerciseToSession(exercise, effortKindOverride: 'timed' | 'drill')` creates one entry; more with `addEntry(effortId)`; one is "started and finished" by `startTimedEntry(effortId, i)` then `finishTimedEntry(effortId, i)` (look at `test/state_test.dart` for the real names); a round: `addExerciseToSession(..., effortKindOverride: 'round')`, `addEntry` for more, `startRound(...)` + `completeRound(effortId, i)` for a finished one. After `await state.endSession(writeToHealth: false)` read the saved structure through the repository (`getSegmentsBySession`/`getEffortsBySegment`, `getTimedInstancesByEffort`, `getRoundInstancesByEffort`) or `state.getExercisesWithEntries()` on a freshly loaded historical session.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25701 | one interval exercise with three entries: 0 never started, 1 finished, 2 never started | after Finish the effort holds exactly one timed instance, finished, at `entryIndex` 0 | the never-started ones are saved |
| S-25702 | one hold exercise (`drill`) with two entries, both never started, and a set exercise with a logged set | the hold exercise is gone from the saved workout (no effort row, no instances); the set exercise is kept | an empty hold exercise is saved |
| S-25703 | one round exercise with three rounds: 0 finished, 1 never started, 2 never started | one round instance left (the finished one, `roundIndex` 0) | no round drop |
| S-25704 | an interval with entries `[finished, notStarted, finished]` and rests recorded after each finished entry (`recordRestStart(effortId, 1)` and `(effortId, 3)`) | two timed instances left, indexes 0 and 1, both finished, and the rests that stay (read `getEntryRests`) are at entry indexes 1 and 2 (re-keyed with the deletion) | the delete forgets the rests |
| S-25705 | an interval entry that is `active` (started, not finished) and one never started | the active one is kept (persisted, still not finished), the never-started one is gone | a running entry would be dropped |
| S-25706 | a workout the watch took part in (the drop's `keepEfforts` path: construct the state with `wristRunsSession: (_) => true`) with a hold exercise whose only entry is never started | the effort is kept (its entry is dropped, the exercise stays with no entries) | the exercise would be removed |
| S-25707 | a workout holding only a never-started interval (nothing else) | `state.finishWouldSaveNothing()` is true before Finish (unchanged) and the `endSession` result keeps no effort for it | control for D-25703 |
| S-25708 | a failing drop: a repository subclass (Mock only) whose `deleteTimedInstance` throws | `endSession` still ends the session (stored `endedAtMs` set) and `state.error` is null | a throw would break the end |
| S-25709 | the Finish flow on a set exercise with one unlogged set and one logged set (plan 157a's own case, copy one of its fixtures) | unchanged: the unlogged set is dropped, the logged one kept | guards plan 157a from the new method |

## Input-reality checklist

1. Writers: timed and round instances are written by the logger's timers, the wrist importer and Edit Session; entries' own observation rows by `deleteTimedEntry`. Units: counts and seconds.
2. Lifecycle: a wrist-linked workout keeps its exercises (S-25706); a rolling session uses the same `endSession`; an edit of a finished workout never reaches this path (`endSession` returns early for an ended session).
3. Settings: none.
4. Time: a timer that is running at Finish is persisted and kept; only `notStarted` goes.
5. Cost: one pass over the efforts at Finish, deletes only for dropped entries.
6. Words: none.
7. Competition: the drop runs after the set drop and before the persistence of running timers; a wrist import queued behind `afterPendingWristImports` runs the same drops in the same order (S-25706 uses the keep path).

## Phases

1. **P1 builder-app**, scope `lib/state/workout/session_core_lifecycle.dart`: D-25701, D-25702 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `test/finish_drops_never_started_timers_test.dart` (new): S-25701..S-25709.
3. **P3 lead**: readers (tests that Finish with never-started timers), full suite, analyze, mutation pass, docs, reviewer.

## Readers

`test/state_test.dart`, `test/round_auto_expiry_test.dart`, `test/session_summary_*`, tests around plan 157a (`grep -rln "157a\|unlogged" test`), `test/watch_*adoption*` and `watch_session_*` tests that end sessions with timers, `test/screen_widget_test.dart`.

## Mutation list (lead)

(a) the new method not called (S-25701); (b) timed kind skipped (S-25701); (c) round kind skipped (S-25703); (d) hold kind skipped (S-25702); (e) a running entry dropped (S-25705); (f) rests not re-keyed (S-25704); (g) the empty effort kept (S-25702); (h) `keepEfforts` ignored (S-25706); (i) the call missing on the wrist-involved path (S-25706); (j) the throw not shielded (S-25708); (k) ascending walk (S-25704).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | MODIFIED | after dropping every `set` entry no rest marks logged (plan 157a): | after dropping every `set` entry no rest marks logged (plan 157a) and every interval, hold or round entry that was never started (plan 257, `test/finish_drops_never_started_timers_test.dart`): | S-25701, S-25702 |
| `docs/session_summary.md` | MODIFIED | `test/finish_drops_unlogged_sets_screen_test.dart` `S-15709`). | `test/finish_drops_unlogged_sets_screen_test.dart` `S-15709`). An interval, hold or round entry that was never started is dropped the same way (plan 257) | S-25701 |
| `docs/rest_tracking.md` | MODIFIED | and removes a `set` exercise left with no entry. | and removes a `set` exercise left with no entry; the same Finish also deletes every interval, hold or round entry whose timer was never started (plan 257) | S-25704, S-25710 |

The three sentences about Finish dropping unlogged sets are extended in place.

## As built

Scenario S-25710 added after the mutation pass (round rests re-keyed). One production line beyond D-25701: `_dropNeverStartedTimers` ends with `_clearError()`, because the manager's deletes report a failure on the error channel and D-10 says a failing drop is never an error (S-25708 caught it). Six existing tests pinned the old rule or relied on a never-started timer surviving Finish and were updated: `finish_drops_unlogged_sets_test` S-15707 (reversed, owner direction), `session_summary_distance_test` S-820 (the entry is now started and finished first), `health_yoga_kind_test` S-19311 (the poses are held), `mix_session_with_nothing_done_test` S-22403 (two: the effort is kept the way a watch-involved workout keeps it, and the finished round goes through the state), `watch_timer_adoption_test` S-6112 (an ended phone session adopts nothing: its never-started intervals are dropped, so the list is empty). The review's blocker on S-25708 misread the fixture (it holds a second, never-started entry); the test now also asserts that entry survives the failing delete. Per-delete change notifications during Finish (the review's minor) are accepted: the screen is guarded and final state is correct.

## Open items

1. (owner) An interval, hold or round exercise you added but never started is removed from the saved workout (like an unlogged set exercise).
2. A workout the watch took part in keeps such an exercise, with no entries (plan 218's rule for sets).
