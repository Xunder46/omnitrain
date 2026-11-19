# Plan 249 — The logger shows what you did last time for a set exercise

Review item 11, first half (owner: "No last time numbers. Prefill from the last performance of that exercise and show it on the logging screen"). This plan SHOWS it. Prefilling the inputs from it is plan 250 (a separate change: it decides what wins between a routine target, the in-session carry-forward and last time).
Phone only. No wire, watch, storage or schema change. No new `WorkoutRepository` method (the service reads through the four existing bulk reads, as `StatsProgressService` does).

## Goal and acceptance

When the user opens the logger for a reps-and-sets exercise (effort kind `set`) that they have done before in a finished workout, one muted line above the reps controls says when and what: `Last (Nov 12): 8×80 · 8×80 · 6×82.5 kg`.

- Weights follow the weight unit setting (stored kg, shown kg or lb with the app's formatter, one decimal, trailing zero trimmed).
- A set with no load shows its reps only; when no set had a load the line ends `reps`: `Last (Nov 12): 12 · 10 · 9 reps`; when some did the unit follows the last weight: `Last (Nov 12): 8×80 · 8 · 6×82.5 kg`.
- More than 6 sets: the first 6, then the unit, then ` (+2 more)`: `Last (Nov 12): 10×50 · 10×50 · 10×50 · 10×50 · 10×50 · 10×50 kg (+2 more)`.
- No line when the exercise has no earlier finished workout, when the effort is not a `set` effort (timed, hold, round, drill), or while the history is still loading.
- "Last" = the newest finished workout (by start time) that holds a non-skipped set with reps above 0 for that exercise, not the running workout. If the same exercise sits in two blocks of that workout, the sets are listed block by block.

Acceptance: S-24901..S-24907 (service/state) and S-24911..S-24916 (screen) green, the "fails without" ones red at the base commit; `flutter analyze` not above 178 issues, 0 errors; no new red in the full suite against the base failing set; Docs delta applied.

## What the user sees

- Add Bench Press to a workout after doing it last Tuesday: above the reps controls, `Last (Nov 12): 8×80 · 8×80 · 6×82.5 kg`. A brand-new exercise: nothing extra. A hold or an interval: nothing extra (not in this plan).
- To SEE it: finish a workout with a set exercise, start another and add the same exercise.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-24901 | New service `LastPerformanceService(WorkoutRepository)` in `lib/core/services/last_performance_service.dart` with `Future<LastSets?> lastSetsFor(String exerciseId, {String? excludeSessionId})`. It reads `getAllSessions()`, `getSegmentsBySession()`, `getEffortsBySegment()`, `getObservationsByEffort()` once per call and answers from those maps (no caching: a finished workout can change after a Finish, so every screen asks fresh). Data classes `LastSets {int startedAtMs; List<LastSet> sets}` and `LastSet {int reps; double weightKg}`. | `stats_progress_service.dart:2452` (same reads), `workout_repository.dart:22,58,74,100` |
| D-24902 | Finished = `endedAtMs != null`; the running workout is excluded by `excludeSessionId`; recency = `startedAtMs` descending (sorted here, the store order is not relied on); efforts = `effortKind == 'set'` with the exercise id, in (segment `orderIndex`, effort `orderIndex`) order; sets come from `EntryRows.setEntries(observations)`; a set is kept when `skipped != true` and `reps > 0`; the first session with at least one kept set wins. | `entry_rows.dart:233-243` (`setEntries`), `models.dart:373,422` |
| D-24903 | `WorkoutState.lastSetsFor(String exerciseId)` builds the service from its own `_repository` and passes the current session's id as `excludeSessionId`; no other state change. | `workout_state.dart:22,60` |
| D-24904 | The screen keeps `Map<String, Future<LastSets?>> _lastSetsByExercise` in `_WorkoutSessionScreenState`: one lookup per exercise per screen lifetime (history cannot change while the logger is open). The line is a `FutureBuilder` in the detail body of a `set` effort, placed first in the column above the reps controls (the column is `metricBody` then a 24 dp gap then the sets stepper). While the future is pending, on error and on null it renders nothing (`SizedBox.shrink`). | `workout_session_list_view.dart:885-941` |
| D-24905 | New widget `LastSetsLine(lastSets, settingsState)` in `lib/widgets/session/last_sets_line.dart`, key `last_sets_line`, a single `Text` in the muted theme colour (`OmniTheme.colors.textMuted`), `labelMedium`-sized, centred, one line with ellipsis. Formatting is a pure static `LastSetsLine.describe(LastSets, SettingsState)` so tests can read it. Date via `OmniDateUtils.formatShort`; load via `UnitFormatter.formatWeightValue`; unit via `UnitFormatter.weightLabel`. | `unit_formatter.dart:46-70`, `date_utils.dart` |
| D-24906 | Wrist logger, summary and routine paths are untouched. | scout sheet |

## Scenarios

Fixtures. Exercise `ex-bench`, other exercise `ex-squat`. Sessions (all `ownerUserId: 'user-1'`): `s1` started Nov 10 12:00, ended Nov 10 13:00; `s2` started Nov 12 12:00, ended Nov 12 13:00; `s3` running (ended null) started Nov 13 12:00. Each session has one segment `seg-<id>` (order 0) with one `set` effort `eff-<id>-bench` for `ex-bench` (order 0). Stored sets (reps, weight kg): `s1` (8, 80), (8, 80), (6, 82.5); `s2` (5, 90); `s3` (1, 100). Observations are written the way `test/entry_rows_test.dart` writes set rows (reps row `valueInt`, weight row `valueReal`, ids carry the entry number: copy its helper). Service tests run under Mock AND Hive through `harnessFactories` (`test/helpers/repository_harness.dart`).

Level A (new `test/last_performance_service_test.dart`, plain `test()`):

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24901 | all three sessions stored; `lastSetsFor('ex-bench')` | `startedAtMs` is `s2`'s, sets `[(5, 90.0)]` (not `s3`, which is running; not `s1`, which is older) | no service |
| S-24902 | same; `lastSetsFor('ex-bench', excludeSessionId: 's2')` | `s1`'s sets `[(8,80),(8,80),(6,82.5)]` | the exclude is ignored |
| S-24903 | `s2` has a skipped set (reps row `valueBool: true`, reps 5) and a set with reps 0 added before the (5, 90) set; `s1` has its three sets | `s2` entries are 3 rows but only (5, 90) is kept: `sets == [(5, 90)]`; with `s2`'s only set skipped the answer is `s1`'s | skipped and empty sets would show |
| S-24904 | no session holds the exercise (`lastSetsFor('ex-squat')`); and a session whose only effort for `ex-bench` has `effortKind: 'timed'` | both null | a kind check missing returns a timed effort |
| S-24905 | `s2` holds a second segment `seg-s2-b` (order 1) with a second `set` effort for `ex-bench` with (4, 92.5) | sets `[(5,90),(4,92.5)]` in block order | only the first effort is read |
| S-24906 | store order: add `s2` BEFORE `s1` in the repository | still `s2` | relies on store order |
| S-24907 | Mock only: `WorkoutState` with a live session (`createNewSession`) whose id is not any fixture id and which holds an `ex-bench` set effort with a logged set; `state.lastSetsFor('ex-bench')` | the answer is `s2`'s, not the live session's | the live session would answer itself |

Level B (new `test/last_sets_line_test.dart`, Mock only, `testWidgets`): S-24911..S-24913 are `LastSetsLine.describe` unit checks (no pump); S-24914..S-24916 pump the logger.

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-24911 | `LastSets(Nov 12 2026, [(8,80),(8,80),(6,82.5)])` with kg | `Last (Nov 12): 8×80 · 8×80 · 6×82.5 kg` | no widget |
| S-24912 | the same with lb (`SettingsState` weight unit `lbs`) | `Last (Nov 12): 8×176.4 · 8×176.4 · 6×181.9 lbs` (80 kg = 176.37 lb, 82.5 kg = 181.88 lb: re-derive with the formatter) | kg shown to a lb user |
| S-24913 | no loads `[(12,0),(10,0),(9,0)]`; mixed `[(8,80),(8,0),(6,82.5)]`; 8 sets all `(10,50)` | `Last (Nov 12): 12 · 10 · 9 reps`; `Last (Nov 12): 8×80 · 8 · 6×82.5 kg`; `Last (Nov 12): 10×50 · 10×50 · 10×50 · 10×50 · 10×50 · 10×50 kg (+2 more)` | formats |
| S-24914 | the logger opened on a bench effort with `s2` stored | `find.byKey(Key('last_sets_line'))` once, its text `Last (Nov 12): 5×90 kg` | no wiring |
| S-24915 | the logger on an exercise with no history; and on a timed (hold) effort whose exercise has history | no `last_sets_line` in both | shows a line anyway |
| S-24916 | history present, logger opened, no overflow at 360x640 with text scale 1.3 (the screen's set group) | `tester.takeException()` is null; the line sits above the reps controls (its dy less than the `+ Add Set`/stepper dy) | layout |

## Input-reality checklist

1. Writers: set rows are written by the logger (`updateEntryValue`), the wrist importer (`watch_session_importer.dart`, its own entry numbering) and Edit Session; all end as `EffortObservation` rows read by `EntryRows`. Units: reps count, load kg.
2. Lifecycle: a deleted exercise leaves no id match; a deleted session leaves no rows; sessions finished before unlogged-set pruning (plan 157a) may hold never-logged default sets: only `reps > 0` and not skipped are kept, so an old unlogged default (10 reps, 0 kg) can show as `10` (accepted, open item 2).
3. Settings: the weight unit setting is read at build (the screen rebuilds when settings change); date format is the app short form.
4. Time: sorted by start time, not by store order (S-24906); a workout finished while the logger is open is the running one and is excluded; two workouts the same day are told apart by start time.
5. Cost: four bulk reads per exercise per screen lifetime; nothing on Home or the lists. A very long history costs one pass; no cap in this plan.
6. Words: new copy `Last (Nov 12): ...` (owner to read).
7. Competition: the line shares the column with the reps controls and the sets stepper; the column is already scrollable and anchored (plan 44), so a 20 dp line cannot push the controls off screen (S-24916).

## Phases

1. **P1 builder-app**, scope `lib/core/services/last_performance_service.dart` (new), `lib/state/workout/workout_state.dart`: D-24901..D-24903 (exact code in the brief). No full suite.
2. **P2 builder-app** (after P1), scope `test/last_performance_service_test.dart` (new): S-24901..S-24907. After P3a they can run beside it (disjoint scopes).
3. **P3a builder-app** (after P1), scope `lib/widgets/session/last_sets_line.dart` (new): D-24905 (exact code in the brief).
4. **P3b builder-app** (after P3a), scope `lib/features/session/workout_session_screen.dart`, `lib/features/session/workout_session_list_view.dart`: D-24904 (exact code in the brief).
5. **P4 builder-app** (after P3b), scope `test/last_sets_line_test.dart` (new): S-24911..S-24916.
6. **P5 lead**: layout probe (S-24916 and 320x568), readers set, full suite against the base failing set, analyze, mutation pass, docs, reviewer.

## Readers

`workout_session_screen` tests that pump the logger: `test/exercise_set_last_value_test.dart`, `test/screen_widget_test.dart` (group on the session screen), `test/interaction_flow_test.dart`, `test/session_toolbar_rework_test.dart`, `test/screen_overflow_contract_test.dart`, `test/state_test.dart` (WorkoutState), `ui_standards_contract_test`, `docs_indexing_contract_test`; any test with `extends MockWorkoutRepository` is untouched (no interface change).

## Mutation list (lead)

(a) the exclude ignored (S-24902); (b) finished filter removed (S-24901); (c) skipped kept (S-24903); (d) reps 0 kept (S-24903); (e) kind check removed (S-24904); (f) only first effort (S-24905); (g) store order instead of start time (S-24906); (h) kg shown to a lb user (S-24912); (i) cap at 6 removed (S-24913); (j) line shown for non-set efforts (S-24915); (k) the current session id not passed (S-24907).

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/widget_catalog/session_widgets.md` | ADDED | - | `LastSetsLine` | S-24911, S-24914 |
| `docs/state_management/workout_state.md` | ADDED | - | `lastSetsFor` | S-24907 |
| `docs/state_management/services_and_utils.md` | ADDED | - | `LastPerformanceService` | S-24901 |

The keeper adds one row per marker in the nearest table of each doc (no new section; `docs/modality_based_exercise_ui.md` is in the size band and is NOT touched) and cites the tests. Stale-term sweep (lead): `grep -rIn -i "last time\|last performance" docs` outside plans, history, releases returned nothing current.

## As built

Two scenarios changed shape: S-24904b seeds the `timed` effort WITH set rows (otherwise the kind check is invisible), and S-24907b was added: a finished workout loaded as the current one is excluded (the running-workout case is already covered by the finished filter). The formatter prints `lbs` (not `lb`) for the pound unit, so S-24912 reads `... 6×181.9 lbs`.

## Open items

1. (owner) Only reps-and-sets exercises show the line; holds, intervals, rounds and distance exercises show nothing yet.
2. (owner) A workout saved before unlogged sets were dropped at Finish may show a bare default (`10`) as its last set.
3. Plan 250 (next): fill the reps and load from the last performance when the exercise is added, with routine targets and the in-session carry-forward ranked against it.
4. Wrist logger untouched.
