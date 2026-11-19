# Review: 250 last-time prefill · P1–P3 · 3468a258 + working tree

Verdict: APPROVE WITH FIXES
Counts: blocker 1 · major 1 · minor 2 · tests: not run (brief forbids the full `flutter test`; lead's established facts: new tests 22 passing, analyze at baseline 178 / 0 errors)

Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (one line, see finding 4)

## Findings

1. [Blocker] `lib/core/services/last_performance_service.dart:43-44` — the new class doc claims "finished history cannot change under a running workout". That invariant is false: a wrist `session_end` import writes a finished session into the store while a phone workout is live (`lib/core/services/watch_session_importer.dart` — `createSession(TrainingSession(... endedAtMs: end.endedAtMs ...))` in the import path, plus `_catchUpEnd` moving an existing row's end). A user whose wrist workout finishes and imports while a phone workout is running, then adds an exercise on the phone, gets set 1 prefilled from the workout that was newest *before* the import, not the newest finished workout the behaviour sentence promises. The cache self-heals only on the next session (S-25012 covers a fresh session, not this window). The behaviour itself is the trade D-25003 chose, so the smallest fix is the doc, not the code: reword to state the trade (a wrist import finishing another workout mid-session is not seen until the next session; the same caveat belongs in plan 250 D-25003's wording, which is out of my write scope). Guard: a Mock-only test that seeds history, adds the exercise (cache warm), imports a newer finished session through the importer, adds the exercise again and asserts the prefill — or, if the trade is ratified, asserts the stale prefill deliberately.

2. [Major] `lib/core/services/last_performance_service.dart:46-60` (`_load`) — the cached fill is not single-flight. Two concurrent `lastSetsFor` calls on a cold cached service (two `addExerciseToSession` calls in flight — e.g. a rapid double add on the picker, or a picker add racing a routine populate) both see `_history == null` and each run the four bulk reads; the second result overwrites the first. No wrong data (both read finished rows), but the "reads them once per workout" guarantee the docs sentence and S-25010 assert is not held under concurrency — S-25010 counts sequential calls only. Smallest fix: hold a `Future<_History>?` in flight and return it (`_historyFuture ??= _loadUncached()`), clearing it when `cacheHistory` is false. Guard: extend S-25010 with two concurrent first adds and assert one `getAllSessions`.

3. [Minor] `lib/state/workout/session_core_entry.dart:58` — `addExerciseToSession` now awaits the four bulk reads before its `_notify()` and before the picker callers (`features/session/session_overview_screen.dart:107`, `features/session/workout_session_screen.dart:1740`) navigate to the logger. The plan accepts the cost ("a first add costs the four bulk reads once") and no caller was found that depends on earlier notification, so this is recorded, not a defect. The wrist picker (`lib/watch/start/watch_exercise_picker.dart:97`) goes through the watch engine's `insertExercise`, not this path — unaffected.

4. [Minor] `test/food_catalog_load_test.dart:270` — `greaterThan(byId['chicken_thigh']!.fat)` drops a redundant `!` on a non-nullable `Food.fat` (`lib/core/models/food_draft.dart:28`). The change is correct but outside the plan's Predicted Files and named nowhere in the plan; a maintainer reading the diff cannot tell why a nutrition test moved in a prefill plan. Fix: record it in the plan's "As built" (an analyzer dead-null-aware cleanup keeping the 178 baseline) or revert it.

## Answers to the brief's five questions

1. Yes — per-metric is the intended rule (D-25002, open item 2): `populateSessionFromManifest` stamps only the metrics a target names (`session_core_io.dart:418-448`), so a reps target keeps last time's load (S-25009 asserts (12, 80.0)). No path stamps a default over a prefill: a target with no value is skipped (`if (value == null) continue;`), and a target whose entry index has no row for that metric is a silent no-op in `updateEntryValue` (pre-existing behaviour, untouched).
2. The cache is dropped/rebuilt lazily on every session-id change (`session_core_entry.dart:301-308`) and a null current session short-circuits, so `clearSession`, `discardUnfinishedSession`, `discardCurrentSession`, `loadHistoricalSession` and `viewHistoricalSession`/`resumeSuspendedLiveSession` all re-read. Session ids are `session-$now`; reuse within one millisecond would still be harmless (the discarded session held no finished rows). The one real staleness window is the wrist import of finding 1. S-25011 (finished session as current excludes itself) and S-25012 (second workout re-reads) cover the id-keyed lifecycle.
3. See finding 3: callers await the id, nothing depends on notification ordering, and the only concurrency defect is the unguarded cache fill (finding 2). The `effort-$now-$index` id collision on a true double add is pre-existing, not this diff.
4. Assertions are behavioural, not presence: S-25001 pins the newest workout (s2's (5, 90) over s1's) *and* the store rows after a restart; S-25002/S-25008 pin per-index values and the clamp; S-25010 pins exercise identity (two exercises with different histories, each prefilled from its own) and the single read; S-25011 pins the self-exclusion. The oldest-workout and wrong-exercise mutants would fail S-25001 and S-25010 respectively.
5. Both changed sentences match the code and name existing things (`cacheHistory`, one instance per session id in `SessionCore` — the fields exist at `session_core.dart:115-116`; `test/last_time_prefill_test.dart` with S-25001..S-25012, all present). Other hits for `10 reps` / `previousValues` outside plans/history/releases: `docs/constants_reference.md:194` and `docs/my_routines.md:425` describe the fallback constants / the routine builder's no-history defaults — still true (the prefill only changes the with-history live-session case); `docs/modality_tracking.md:222` concerns the round kind — unaffected; `docs/stats_best_load_investigation.md` declares itself a frozen historical record at its header — excluded by its own terms.

## Assumption Log rulings

No Assumption Log entries appear in the plan — nothing to rule on. (An empty log here is not the "empty after a complex phase" case: the plan never started one.)

## Scenario coverage

S-25001 → `test/last_time_prefill_test.dart` S-25001 (Mock + Hive) · OK
S-25002 → same file S-25002 · OK
S-25003 → same file S-25003 · OK
S-25004 → same file S-25004 · OK
S-25005 → same file S-25005 · OK
S-25006 → same file S-25006 · OK
S-25007 → same file S-25007 (Mock only) · OK
S-25008 → same file S-25008 · OK
S-25009 → same file S-25009 · OK
S-25010 → same file S-25010 (Mock only) · OK
S-25011 → same file S-25011 · OK (added as built)
S-25012 → same file S-25012 · OK (added as built)
The `excludeSessionId` mutant (k) is covered at the service level by plan 249's tests (per plan, not re-derived).

## Docs delta

- `docs/state_management/workout_state.md` MODIFIED → applied (sentence true; every name in it checked against the code this run)
- `docs/state_management/services_and_utils.md` MODIFIED → applied (sentence true, modulo finding 2's concurrency caveat which the sentence does not claim)
- Doc edits the table does not name: none in the diff. `docs/constants_reference.md:194` and `docs/my_routines.md:425` were left unchanged and are still true in their contexts (see answer 5).

## Lead dispositions

1. Blocker (the class comment said finished history cannot change under a running workout): FIXED. The comment now says a workout the wrist finishes while this one is live is not seen until the next workout (accepted, plan open item 5).
2. Major (a cold cached service read the history twice for two callers arriving together, the second overwriting the first): FIXED. The cached read is single-flight and a failed read is retried; S-25013 and S-25014 prove both, mutants p and q killed.
3. Minor (`addExerciseToSession` now awaits the four bulk reads before the first entry exists): accepted, stated in the plan (cost: one history read per workout).
4. Minor `test/food_catalog_load_test.dart:270`: not this plan's change; already modified before the unit started, left unstaged.
