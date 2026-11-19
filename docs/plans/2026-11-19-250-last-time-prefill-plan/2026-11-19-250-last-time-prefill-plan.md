# Plan 250 — A new set starts from the same set of last time

Review item 11, second half (owner: "prefill from the last performance of that exercise"). Plan 249 SHOWS last time on the logger; this plan makes a new reps-and-sets entry start from it.
Phone only. No wire, watch, storage or schema change. No new `WorkoutRepository` method.

## Goal and acceptance

When an exercise is added to a workout (the picker, or a routine that starts), and the user has done it before in a finished workout, its sets no longer start at 10 reps and 0 kg:

- Set 1 starts from set 1 of last time, set 2 from set 2, and so on; a set beyond what last time held repeats last time's final set.
- A routine's own target numbers still win over last time (a routine that says 12 reps gives 12, with last time's load).
- "+ Add Set" on the logger is unchanged: it still carries forward the set the user just did (so a user who moved 80 to 85 gets 85 on the next set, not last month's 80).
- No earlier workout, a timed / hold / round / drill effort, an exercise whose lookup fails, and an effort the watch seeds: unchanged (10 reps, 0 kg, or the effort kind's own default).
- Never reads the running workout's own sets.

Acceptance: S-25001..S-25010 green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Do Bench Press 8×80, 8×80, 6×82.5 on Monday. On Thursday add Bench Press: the logger opens on set 1 with 8 reps and 80 kg; "+ Add Set" gives 8 and 80 again (carry from the set just done), as before.
- Start a routine that has Bench Press with three sets and no targets: the three sets open as 8×80, 8×80, 6×82.5.
- To SEE it: finish a workout with a set exercise, then add that exercise to a new workout.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-25001 | `SessionCore.addEntry` gets `bool fromHistory = false`. When true, `previousValues` is null and the effort is a `set` effort, the entry is seeded from `_lastTimeValues(effort, existingEntryCount)`: set number `existingEntryCount` (0-based) of the last performance, clamped to its final set, as `{'reps': int, 'weight': double (kg)}`. Everything else is untouched: the `previousValues` the screen's "+ Add Set" passes is non-null, so it wins. | `session_core_entry.dart:139-275` (`addEntry`, the `set` case reads `previousValues?['reps'] ?? 10`) |
| D-25002 | Callers that pass `fromHistory: true`: `addExerciseToSession`'s first entry and the routine loop's `for (int i = 1; i < entry.setCount; i++) addEntry(effortId)`. The wrist's `seedFirstEntry` and the logger's `_addSet` do not. A routine's target stamping (`updateEntryValue` after the loop) runs later, so an explicit target overwrites the prefilled value of that metric and set. | `session_core_entry.dart:58`, `session_core_io.dart:402-413` |
| D-25003 | `LastPerformanceService` gets `cacheHistory` (default false): when true it keeps the four bulk reads after the first call, so a routine with many exercises and sets reads the history once. `SessionCore` holds one such service per current session id (`_lastPerformance`, `_lastPerformanceSessionId`, new fields in the class: an extension cannot hold fields) and builds a new one when the session id changes. The screen's own lookup (plan 249) stays uncached. | `session_core.dart:51`, `last_performance_service.dart` |
| D-25004 | A failed or empty lookup returns null and the entry gets its normal defaults; adding an exercise never fails because of the history. | — |
| D-25005 | Only `set` efforts. Holds, intervals, rounds and drills keep their own defaults (open item 1). | `session_core_entry.dart:193-232` |

## Scenarios

Fixtures. Same history as plan 249: exercise `ex-bench` (use a real library exercise that has the `load` capability for the weight row: pick it as `exercises.firstWhere((e) => e.capabilities.contains('load') && e.capabilities.contains('reps'))` and use ITS id for every session fixture); finished `s1` (Nov 10: (8,80),(8,80),(6,82.5)), finished `s2` (Nov 12: (5,90)). `test/last_performance_service_test.dart` has the `seedBench` seeding helper: copy it. Tests run under Mock and Hive through `harnessFactories` unless marked Mock only; plain `test()`. The live workout: `final state = WorkoutState(repo); await state.createNewSession(modality: Modality.resistanceLifting);` then `await state.addExerciseToSession(exercise, effortKindOverride: 'set')`; entries are read with `state.getExercisesWithEntries()` (the effort's map: `entries` list of maps with `reps` and `weight`).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-25001 | history s1 and s2; add the exercise to a new live workout | first entry reps 5, weight 90.0 (s2 is the newest) | entries start 10 / 0 |
| S-25002 | history s1 only; a routine manifest with the exercise and `setCount: 4` (the facade `WorkoutState.addEntry` does not expose `fromHistory`: only the add-exercise path and the routine loop use it) | entries (8, 80), (8, 80), (6, 82.5), (6, 82.5) (beyond last time: its final set) | no per-index prefill, no clamp |
| S-25003 | history s1; add the exercise; then `state.addEntry(effortId, previousValues: {'reps': 7, 'weight': 85.0})` (what the logger's "+ Add Set" does) | the new entry is (7, 85.0), the first stays (8, 80) | control: guards the logger's carry (it passes either way today; the `seed == null` check is protective only, so there is no mutant for it) |
| S-25004 | no history | first entry (10, 0.0) | control: defaults stay |
| S-25005 | history s1; add the exercise with `effortKindOverride: 'timed'` | the entry holds no reps row; `timed` default duration 0 | a kind check missing |
| S-25006 | history s1; `await state.seedFirstEntry(effortId)` on an effort created with no entry (create the effort with `state.addExerciseToSession` then delete its entry, or build the effort row directly as `test/state_test.dart` does for the wrist path) | the seeded entry is (10, 0.0) | the wrist path would prefill |
| S-25007 | history s1; a repository subclass (Mock only) whose `getAllSessions` throws | `addExerciseToSession` still returns a non-empty id and the first entry is (10, 0.0) | a throw would fail the add |
| S-25008 | history s1; `state.populateSessionFromManifest(manifest)` with one segment holding the exercise (`effortKind: 'set'`, `setCount: 3`, `targets: []`) (copy the manifest shape from `test/state_test.dart` around line 3725) | three entries (8,80), (8,80), (6,82.5) | the routine loop does not prefill |
| S-25009 | as S-25008 with `targets: [TemplateTarget(...)]` for reps at set index 0 with `targetInt: 12` (see the model in `lib/data/models/models.dart` for the required fields: `setIndex: 0`, metric `MetricIds.reps`) | entry 0 is (12, 80.0): the target wins reps, last time keeps the load; entries 1 and 2 are (8,80), (6,82.5) | a target would be ignored, or last time lost |
| S-25010 | Mock only: a counting repository subclass (`getAllSessions` increments a counter) with history s1 and s2; a manifest with two different exercises of three sets each | `getAllSessions` was called exactly once during `populateSessionFromManifest` | no cache: one read per set |

## Input-reality checklist

1. Writers: set rows are written by `addEntry` (here), the logger's edits, the wrist importer. Units: reps count, load kg (the same unit as the stored last-time sets, no conversion).
2. Lifecycle: an exercise deleted after last time has no id match; a deleted last session leaves no rows; the newest finished workout wins, so the prefill changes after each Finish.
3. Settings: none read (kg stored; the logger converts at display).
4. Time: sorted by start time (plan 249); a workout finished while another is live cannot be the live one (excluded by id).
5. Cost: one history read per live workout (cached per session id), instead of one per set; a first add costs the four bulk reads once.
6. Words: no new copy.
7. Competition: the screen's carry-forward and the routine's targets both beat last time; the wrist's seeded entry is untouched (S-25006); the Last line (plan 249) shows the same numbers the prefill uses.

## Phases

1. **P1 builder-app**, scope `lib/core/services/last_performance_service.dart`, `lib/state/workout/session_core.dart`, `lib/state/workout/session_core_entry.dart`, `lib/state/workout/session_core_io.dart`: D-25001..D-25004 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `test/last_time_prefill_test.dart` (new): S-25001..S-25010.
3. **P3 lead**: readers set, full suite against the base failing set, analyze, mutation pass, docs, reviewer.

## Readers

Tests that add exercises or start routines and read entry defaults: `test/state_test.dart` (groups on `addExerciseToSession`, `addEntry`, `populateSessionFromManifest`, "exercise previousValues carry-forward"), `test/set_weight_carry_repro_test.dart`, `test/exercise_set_last_value_test.dart`, `test/routine_session_modality_test.dart`, `test/row_invariants_guard_test.dart`, `test/services_test.dart`, `test/interaction_flow_test.dart`, `test/screen_widget_test.dart`; every `extends MockWorkoutRepository` fake keeps working (no interface change). Mock seeds no finished sessions, so existing tests see no history.

## Mutation list (lead)

(a) `fromHistory` ignored in `addEntry` (S-25001); (b) per-index replaced by always the first set (S-25002, S-25008); (c) clamp removed (S-25002); (e) `effortKind == 'set'` check removed (S-25005); (f) `seedFirstEntry` passes `fromHistory: true` (S-25006); (g) the lookup's exception not caught (S-25007); (h) routine loop without `fromHistory` (S-25008); (i) targets stamped before the loop (S-25009); (j) `cacheHistory` false (S-25010); (k) the session id not excluded (a finished workout opened for editing then adds the exercise) (covered by plan 249's S-24907b at the service level).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/state_management/workout_state.md` | MODIFIED | each new set/interval/round/drill pre-fills with the prior values (June 2026, exercise-set-last-value-plan). | each new set/interval/round/drill pre-fills with the prior values (June 2026, exercise-set-last-value-plan); a new set effort's first entries (an exercise added, a routine's sets) start from the same-numbered set of the last finished workout of that exercise (plan 250). | S-25001, S-25003 |
| `docs/state_management/services_and_utils.md` | MODIFIED | It reads the four bulk repository reads on every call and caches nothing. | It reads the four bulk repository reads on every call; a live workout builds it with `cacheHistory` so a routine reads them once per workout. | S-25010 |

Stale-term sweep (lead): `grep -rIn -i "defaults to 10\|10 reps\|previousValues" docs` outside plans, history, releases: the hits are the row above and sentences about the per-kind defaults that stay true when there is no history; nothing else changes.

## As built

Two scenarios were added after the lead's mutation pass: S-25011 (a FINISHED workout loaded as the current one does not answer for itself) and S-25012 (a second workout on the same state reads the history again). The facade `WorkoutState.addEntry` does not expose `fromHistory`, so later sets of a routine are the way tests reach it (S-25002 uses a four-set routine). The review's major (a cold cached service read the history twice for two callers arriving together) was fixed: the cached read is single-flight and a failed read is retried (S-25013, S-25014). One mutant is equivalent and stays alive: dropping the `effortKind == 'set'` check, because the round, timed and drill branches return before that point. The first P1 run collapsed the routine's set loop into a single `addEntry` call (the brief said the call inside the loop "becomes"); the P2 builder reported it, the lead restored the loop.

## Open items

1. (owner) Only reps-and-sets exercises are prefilled; holds, intervals, rounds and drills start as before.
2. (owner) A routine's explicit target wins over last time per metric (a target for reps keeps last time's load).
3. (owner) Beyond the number of sets last time, the final set of last time repeats.
4. The wrist logger and the wrist's seeded entries are untouched.
5. A workout the wrist finishes while a phone workout is live is not seen by that workout's prefill (the history is read once per workout): the prefill can be one workout behind until the next one (accepted; review finding 1 corrected the code comment that claimed otherwise).
