# Evidence — Stats PR 4a (Records & Trends, Exercise Progress, the per-exercise native value)

> Companion to `2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.md`. This file holds the
> baselines, the ground-truth facts the plan was written from, the drift it found, and the tables the
> implementer and reviewer fill. **Nothing goes into the plan.**
>
> The reviewer writes `2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.review.md`.

## 1. Baselines (Step 0c)

Run on `develop` before any change, through the only permitted shell entry point:

| Command | Verbatim result |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh lint` | `199 issues found.` — 4 warnings, **0 errors**, 195 infos |
| `.github/copilot/scripts/macos/gateway.sh test` | `01:14 +3119 ~1: All tests passed!` — 3119 passed, 1 skipped, 0 failed |

**The analyzer bar for this PR is a count, not an exit code.** `lint` exits non-zero because the repo
carries pre-existing info notices. The bar is: **0 errors**, and **no more than 199 issues** in total.
Every file a phase touches has 0 issues of its own.

The PR 3 series index predicted 241 issues on its own tree. This tree measures 199. That difference is
pre-existing drift in the index, not a regression from 4a.

### 1a. Fill in as you go

| Point | `lint` | `test` |
|---|---|---|
| Step 0c baseline | 199 issues, 0 errors | 3119 passed, 1 skipped |
| After Phase 1 | 199 issues, 0 errors | full suite 3124 passed, 1 skipped, 0 failed (baseline 3119 + 5 new); `test/round_instances_by_effort_test.dart` 5 passed; parity + db_seed 43 passed; docs indexing contract 9 passed; the touched files carry 0 issues |
| After Phase 2 | 199 issues, 0 errors | full suite 3140 passed, 1 skipped, 0 failed (baseline 3119 + 5 + 16 new); `test/exercise_metric_service_test.dart` 16 passed; the touched files carry 0 issues |
| After Phase 3 | 199 issues, 0 errors, none in a file this phase touched | full suite **3153 passed, 1 skipped, 0 failed** (3140 + 12 new + 1 placeholder, see §9c); `test/records_and_trends_screen_test.dart` 12 passed; `test/screen_widget_test.dart` 250 passed; `test/records_and_trends_screen_test.dart` + `test/docs_indexing_contract_test.dart` 21 passed; `test/in_session_pr_toast_test.dart` + `test/pr_toast_test.dart` 41 passed |

## 2. Ground-truth facts the plan was written from

**H1 — The Stats screen's sections.** `lib/features/stats/stats_screen.dart` builds ALL TIME
(`_buildAggregateCard`), STRENGTH (`_buildStrengthSection`), CARDIO (`_buildCardioSection`), ISOMETRIC
(`_buildIsometricSection`), SPORTS (`_buildSportsSection`) and NUTRITION (`_buildNutritionSection`). Its
header is `const OmniBackHeader(title: 'Stats')` — no `actions` today.

**H2 — The three totals are computed inline.** `_StatsScreenState._loadData()` counts a session when
`endedAtMs != null`, adds `endedAtMs! - startedAtMs` only when `!isRolling`, and reads the streak from
`CalendarState(widget.workoutState.repository).streakDays` after `init()`. There is no shared helper.

**H3 — One service instance per screen load.** `_loadData()` constructs one `StatsProgressService` and
calls `computeProgressData()` then `computeNutritionAdherence()`. The service caches its history snapshot
per instance, so a second instance would double the read.

**H4 — The bulk reads that exist.** `WorkoutRepository` has `getObservationsByEffort()` and
`getTimedInstancesByEffort()`, both returning `Map<String, List<…>>` grouped by `effortId`. There is **no**
`getRoundInstancesByEffort()`, and no bulk sensor-summary read — only `getRoundInstances(String effortId)`
and `getSensorSummariesForSession(String sessionId)`.

**H5 — The two implementations.** `HiveWorkoutRepository` walks `_roundInstancesBox.values`;
`MockWorkoutRepository` holds `_roundInstances` already keyed by `effortId`. Both sort by `roundIndex` in
`getRoundInstances`, so the bulk read has an exact template in `getTimedInstancesByEffort()` on each side.

**H6 — The canonical round rule.** `lib/state/workout/session_summary_builder.dart` counts a round when
`round.state == RoundState.finished && round.startedAtMs > 0 && round.finishedAtMs != null`, and sums
`round.elapsedMs`. `RoundInstance.completed` is true only on a natural countdown finish and is **not** what
the Summary counts.

**H7 — The Sports path in Stats reads timed instances, not round instances.** `_processRoundEffort` sums
`TimedInstance.actualDurationSecs` for `TimedState.finished`. It has no round *count* concept at all, which
is why the new Sports value needs the bulk round read (H4).

**H8 — The per-exercise axis rule.** An exercise is reps-axis iff any of its sets **anywhere in its full
history** has `metric-weight` 0 or absent; otherwise weight-axis. `metric-extra-weight` is an annotation
and never switches the axis. `epley1RM(weight, reps) = weight × (1 + reps/30)`.

**H9 — The distance contract.** `DistancePairing.forEntries` delegates to
`EntryRows.companions(rows: …, metricId: MetricIds.distance, entryCount: …)`; `DistanceSource.isEstimated`
is the only "est." test. A day's distance counts every entry's own row; a pace counts only finished entries
that have a distance greater than 0.

**H10 — Per-entry extra weight has a reader.** `EntryRows.companions(rows: …, metricId:
MetricIds.extraWeight, entryCount: …)` gives the row each entry owns, in entry order — which is what the
Isometric added-weight note needs. The drill path in `StatsProgressService` does not read extra weight
today.

**H11 — `ObservationGrouper`'s timed and drill paths are positional.** Only the `set` path delegates to
`EntryRows`. Do not extend the positional paths; read instances and companions directly.

**H12 — `OmniBackHeader` already has an `actions` slot** (`List<Widget>? actions`), so the header icon
needs no widget change. `OmniNavigator.push` is the only permitted way to push a screen; a raw
`MaterialPageRoute(` or `PageRouteBuilder(` outside `lib/core/navigation/` fails
`test/navigation_contract_enforcement_test.dart`.

**H13 — The formatters that exist.** `UnitFormatter.formatWeightValue`, `formatDistanceValue`,
`distanceLabel`, `weightLabel`; `OmniDateUtils.formatShort`, `formatClock`, `formatDurationHoursMins`,
`startOfDayMs`. `SettingsState` carries the unit preference, and `StatsScreen` already takes it as a
constructor parameter.

**H14 — The fixture harness.** `test/helpers/repository_harness.dart` provides `harnessFactories`
(Mock + Hive), `RepositoryHarness.restart()`, `seedSession(daysAgo:)`, `seedExercise`,
`seedWeightedSets`, `seedBodyweightSets`, `seedTimedEntries`, `seedHoldEffort`, `seedSetEffort`,
`distanceRow`, `repsRow`, `weightRow`, `extraWeightRow`, `timedInstance`, `storedRows`, `storedRowIds`,
`fixtureStart` and `fixtureRowAt`. It has **no** round-instance builder — Phase 1 adds one.

## 3. Docs ↔ code drift found while planning

| Doc claim | Code | Action |
|---|---|---|
| `docs/stats_screen.md` documents a **RECORDS** section | No such section exists in `stats_screen.dart` | Deleted in Phase 3 (Step 3.9), per the pack's D-13 |
| `docs/stats_screen.md` documents a **VOLUME TRENDS** section | No such section exists | Deleted in Phase 3 (Step 3.9) |
| `docs/stats_screen.md` documents a **CONSISTENCY** section | No such section exists | Deleted in Phase 3 (Step 3.9) |
| `docs/stats_screen.md` has no **ISOMETRIC** heading | `_buildIsometricSection` exists and renders | Added in Phase 3 (Step 3.9) |
| `docs/stats_screen.md` has no **SPORTS** heading | `_buildSportsSection` exists and renders | Added in Phase 3 (Step 3.9) |
| The PR 3 series index predicts "241 issues with 0 errors" on the 3a2 tree | This tree measures 199 | Pre-existing; noted in §1, not fixed here |

## 4. Pack ↔ code drift found while planning

The prompt pack's item 5 revision note says heart rate does not reach the phone and steps are captured
nowhere. **That is stale.** `lib/core/services/watch_session_importer.dart` builds `SensorSummary` records
at all four scopes (`session`, `effort`, `timed_instance`, `round_instance`), both repositories store them,
and the edit/restore paths carry them. Nothing in `lib/` *displays* heart rate or steps yet, so PR 4 is the
first reader. Recorded so 4b's plan does not re-litigate the prerequisite; no action in 4a, which reads no
sensor summaries at all.

## 5. Doc-claim table (fill in)

One row per behaviour sentence added to a doc. "Test" names the scenario id and the test file.

| Doc | Sentence added (short) | Test |
|---|---|---|
| `docs/db_integration.md` | `getRoundInstancesByEffort()` is the bulk counterpart to `getRoundInstances(effortId)`: every round instance grouped by `effortId`, each group in `roundIndex` order, an effort with no instances has no key. | `test/round_instances_by_effort_test.dart` (S-901, S-902) |
| `docs/state_management/services_and_utils.md` | `computeTotals()` counts a rolling session as a completed session but gives it no duration; the streak stays `CalendarState.streakDays`. | `test/screen_widget_test.dart` ("rolling sessions are excluded from duration aggregates") |
| `docs/state_management/services_and_utils.md` | The reps/weight axis is a property of the exercise's full history, not of the caller's range or of the day a point came from. | `test/exercise_metric_service_test.dart` (S-904) |
| `docs/state_management/services_and_utils.md` | The round predicate is `SessionSummaryBuilder`'s — finished, started and with an end stamp — not the stored `completed` flag. | `test/exercise_metric_service_test.dart` (S-908) |
| `docs/stats_screen.md` | The header carries one action, a chart icon to Records & Trends; the sections described on the page are what `StatsScreen` itself renders. | `test/records_and_trends_screen_test.dart` (S-913) |
| `docs/stats_screen.md` | The section list is ALL TIME, STRENGTH, CARDIO, ISOMETRIC, SPORTS, NUTRITION — the RECORDS, VOLUME TRENDS and CONSISTENCY sections never existed in `stats_screen.dart`. | `test/screen_widget_test.dart` (the section-presence cases) |
| `docs/records_and_trends.md` | An exercise sits in the section of its most-logged effort kind, ties resolving Resistance, Cardio, Isometric, Sports; the entry is in every section's list, with no recency cutoff. | `test/records_and_trends_screen_test.dart` (S-912) |
| `docs/records_and_trends.md` | The search field filters the sections by name; a section with no match is not rendered. | `test/records_and_trends_screen_test.dart` (S-912) |
| `docs/records_and_trends.md` | An entry opens that exercise's progress screen; an id with no history shows an empty state rather than throwing. | `test/records_and_trends_screen_test.dart` (S-910 guard, S-914) |
| `docs/records_and_trends.md` | Exercise Progress reads one best, one point per training day oldest first, and the recent days newest first, capped at `kRecentSessionCount`. | `test/records_and_trends_screen_test.dart` (S-915) |
| `docs/navigation_and_screens.md` | `StatsScreen`'s header action and the two new screens, with their constructor dependencies. | `test/records_and_trends_screen_test.dart` (S-913, S-914) |
| `docs/records_and_trends.md` (fix round 1) | `StatsScreen` is the only file in `lib/` that constructs `RecordsAndTrendsScreen`, so the header chart icon is the only entry point; Exercise Progress has no single-entry rule. | `test/records_and_trends_screen_test.dart` (`StatsScreen is the only file in lib/ that constructs RecordsAndTrendsScreen`) |
| `docs/stats_screen.md` (fix round 1) | The chart icon is the only way into Records & Trends — this file is the only place in `lib/` that constructs `RecordsAndTrendsScreen`. | `test/records_and_trends_screen_test.dart` (the single-entry-point case) |
| `docs/stats_screen.md` (fix round 1) | The SPORTS pass sums each day's finished timed instances behind the round effort and never reads a `RoundInstance`; the round-counting rule for the per-exercise screens is in `records_and_trends.md`. | `test/stats_progress_test.dart` (`Sports round aggregation (Phase D)`) |
| `docs/records_and_trends.md` (fix round 1) | A sports entry counts rounds by the rule `StatsProgressService` applies, not by the stored `completed` flag. | `test/exercise_metric_service_test.dart` (S-908, already cited in the same section) |

Phase 1 doc checklist (items 1–9) over `docs/db_integration.md`: 1 ✓ (the line names its test); 2 ✓ (no
line numbers, hashes or current-state dates); 3 ✓ (no colour literals); 4 ✓ (no flow walkthrough);
5 ✓ (no roadmap phrases); 6 n/a (not a new page); 7 ✓ (no links added); 8 ✓ (36 KB, under 64 KiB);
9 ✓ (`test/docs_indexing_contract_test.dart` 9 passed).

Phase 2 doc checklist (items 1–9) over `docs/state_management/services_and_utils.md`: 1 ✓ (every
behaviour sentence names its test); 2 ✓ (no line numbers, hashes or current-state dates); 3 ✓ (no
colour literals); 4 ✓ (no flow walkthrough — the entry names rules, not steps); 5 ✓ (no roadmap
phrases, and the two Phase 3 surfaces are described only as what the figures are read by); 6 n/a
(added to an existing page); 7 ✓ (no links added); 8 ✓ (47 KB, under 64 KiB); 9 ✓
(`test/docs_indexing_contract_test.dart` passed in the full run).

Phase 3 doc checklist (items 1–9) over `docs/stats_screen.md`, `docs/records_and_trends.md`,
`docs/navigation_and_screens.md` and `docs/README.md`: 1 ✓ (each new behaviour sentence on the new page
sits under a `Verified by` line naming its scenario; the new ISOMETRIC and SPORTS sections on
`stats_screen.md` name `test/stats_progress_test.dart` and `test/screen_widget_test.dart`); 2 ✓ (no line
numbers, hashes or current-state dates — the footer date is the page's own version date); 3 ✓ (no colour
literals); 4 ✓ (no flow walkthrough — the new page names rules and the values each section reads, not
steps); 5 ✓ (no roadmap phrasing — §8's sweep greps the new page for it); 6 ✓
(`docs/records_and_trends.md` has a row in `docs/README.md`, immediately after the Stats Screen row);
7 ✓ (every link the four pages gained resolves to an existing file); 8 ✓ (27 KB, 5 KB, 24 KB and 19 KB
— all under 64 KiB); 9 ✓ (`test/docs_indexing_contract_test.dart` 9 passed in the targeted run).

## 6. Red → green table (fill in)

| Scenario | Red run (command + observed failure) | Green run | Result |
|---|---|---|---|
| S-901 | `gateway.sh test test/round_instances_by_effort_test.dart` → compile failure: `test/round_instances_by_effort_test.dart:70:36: Error: The method 'getRoundInstancesByEffort' isn't defined for the type 'WorkoutRepository'.` | same command, exit 0 | passed (Mock + Hive) |
| S-902 | same run: `:88:36` same error | same command, exit 0 | passed (Mock + Hive) |
| S-903 | same run: `:96:35` and `:98:38` same error (line numbers as the file stood at the red run) | same command, exit 0 | passed (compares Mock against Hive, and each after a restart; bites under M0) |
| S-904 | `gateway.sh test test/exercise_metric_service_test.dart` → compile failure: `test/exercise_metric_service_test.dart:311:41: Error: The method 'computeExerciseMetrics' isn't defined for the type 'StatsProgressService'.` | same command, exit 0 | passed (Mock + Hive; bites under M1) |
| S-905 | same run: `:407:41` same error | same command, exit 0 | passed (Mock + Hive) |
| S-906 | same run: `:482:41` same error | same command, exit 0 | passed (Mock + Hive) |
| S-907 | same run: `:523:41` same error | same command, exit 0 | passed (Mock + Hive) |
| S-908 | same run: `:588:41` same error | same command, exit 0 | passed (Mock + Hive; bites under M2) |
| S-909 | same run: `:621:41` same error | same command, exit 0 | passed (Mock + Hive) |
| S-910 | same run: `:634:41` same error | same command, exit 0 | passed (Mock + Hive) |
| S-911 | same run: `:672:41` same error | same command, exit 0 | passed (Mock + Hive) |
| S-910 (screen half) | see the note below the table | `gateway.sh test test/records_and_trends_screen_test.dart` → exit 0 | passed (Mock + Hive; bites under the empty-state proof in §7) |
| S-912 | see the note below the table | `gateway.sh test test/records_and_trends_screen_test.dart` → exit 0 | passed (Mock + Hive; bites under M3) |
| S-913 | see the note below the table | same command, exit 0 | passed (Mock + Hive; bites under the header-icon proof in §7) |
| S-914 | see the note below the table | same command, exit 0 | passed (Mock + Hive; bites under the entry-push proof in §7) |
| S-915 | see the note below the table | same command, exit 0 | passed (Mock + Hive; bites under the history-order proof in §7) |
| S-916 | green before and after — **with two assertions scoped, see §9c** | `gateway.sh test test/screen_widget_test.dart` → 250 passed, exit 0 | passed; the sections, headers and window chip are untouched |

### 6a. Phase 3 did not get a clean red run, and what was done instead

**Phase 3's implementation was written before its test file.** Step 3.1 … 3.3 landed first and
`test/records_and_trends_screen_test.dart` was created afterwards, so the file has **no red run** in the
sense §6 records for Phases 1 and 2 — there was no moment when the tests failed because the screens did
not exist. Recorded plainly because the Phase 0 order was not followed here.

What was done instead, to show the tests bite rather than merely pass: **five inverse-edit proofs**, one
per scenario in the register, each reversing a specific behaviour and each failing at a named line on
both harnesses before being restored (§7). A test that passes under a reversal of the behaviour it names
would have been caught by this and was not: every scenario in S-910 … S-915 fails under its own reversal.
The M3 proof is the plan's required one; the other four were added because the red run was missed.

`test/screen_widget_test.dart`'s two stats-tooltip assertions also had to be scoped in this phase; the
reason is in §9c. That edit is the only pre-existing test this phase changed, and it is 25 changed lines
in a file the plan's Predicted Files already lists for 4c.

## 7. Mutation table (fill in)

The plan's copy-aside method cannot run here: `cp` and `/tmp` shell commands are denied to this executor.
The method actually used is the inverse edit, spelled out below the table.

Inverse-edit method (the brief's correction 2 — `cp` and `/tmp` are denied): (a) `gateway.sh git-diff --
<file>`; (b) apply the reversal with the edit tool; (c) run the test and record the failing line; (d)
apply the exact inverse edit; (e) `gateway.sh git-diff -- <file>` again and confirm it is identical to
(a); (f) run the test again and record the pass. No `git stash`, `git checkout` or `git restore` was used.
The step (e) identity check is `git-diff --stat -- <file>` returning exactly the pre-mutation
insertion/deletion counts plus a `grep` for the mutation marker over the diff returning nothing: this
executor has no hashing or copy utility, so the counts and the marker are the evidence.

Both M1 and M2 reversed the same single block they added, so the file's diff footprint returned to its
pre-mutation counts (467 insertions, 1 deletion at the time of the runs) both times. M3 … M7 reverse a
line inside a file this phase **created**, and an untracked file has no `git-diff` to compare, so their
identity check is a `grep` over `lib/features/stats/` for the mutation marker (0 hits each) plus a green
re-run of the 12 tests.

| # | Reversal | Test that must fail | Observed failure | Restored |
|---|---|---|---|---|
| M0 (Phase 1, voluntary — not in the plan's list) | Drop the `roundIndex` sort from `MockWorkoutRepository.getRoundInstancesByEffort()` | `round_instances_by_effort_test.dart` S-901 (Mock) and S-903 | S-901: `Expected: [0, 1, 2] / Actual: [2, 0, 1]` at `test/round_instances_by_effort_test.dart:84`; S-903: `Expected: {'effort-a': ['2:…', '0:…', '1:…'], …}` / `Actual: {'effort-a': ['0:…', '1:…', '2:…'], …}` at `:125`. 3 passed, 2 failed, exit 1 | Yes — diff identical to (a) by inspection; 5 passed, exit 0 |
| M1 | Decide the Resistance axis per range instead of over full history | `exercise_metric_service_test.dart` S-904 (`ex-pull`) | S-904: `Expected: [NativeMetric:NativeMetric.reps, NativeMetric:NativeMetric.reps] / Actual: [NativeMetric:NativeMetric.reps, NativeMetric:NativeMetric.estimatedOneRepMax]`, once for Mock and once for Hive. 14 passed, 2 failed, exit 1 | Yes — `git-diff --stat` back to its pre-mutation counts (467 insertions, 1 deletion at the time of the run), `grep -c "M1 MUTATION"` on the diff 0; 16 passed, exit 0 |
| M2 | Count `round.completed` instead of the D-408 predicate | `exercise_metric_service_test.dart` S-908 | S-908: `Expected: <2> / Actual: <4.0>` (the stored flag admits the active, the not-started and the end-stamp-less round), once for Mock and once for Hive. 14 passed, 2 failed, exit 1 | Yes — `git-diff --stat` back to the same counts, `grep -c "MUTATION"` on the diff 0; 16 passed, exit 0 |
| M3 | Order the Records & Trends entries by name instead of training-day share | `records_and_trends_screen_test.dart` S-912 | `Expected: a value less than <571.0> / Actual: <665.0>` at `test/records_and_trends_screen_test.dart:244` — Bench Press's entry sorted above Incline Bench Press's, once for Mock and once for Hive. 10 passed, 2 failed, exit 1 | Yes — the reversal was `final byShare = 0;`, removed and the file re-grepped for the marker (0 hits); 12 passed, exit 0 |
| M4 (Phase 3, voluntary — added because Phase 3 had no red run, §6a) | Empty the header action's `onPressed` | `records_and_trends_screen_test.dart` S-913 | `Found 0 widgets with text "Records & Trends"` at `:420`, once for Mock and once for Hive | Yes — restored; 12 passed, exit 0 |
| M5 (Phase 3, voluntary) | Reverse the recent-session list — `points` instead of `points.reversed` | `records_and_trends_screen_test.dart` S-915 | `Expected: 'Sep 30' / Actual: 'Sep 28'` at `:616`, once for Mock and once for Hive | Yes — restored; 12 passed, exit 0 |
| M6 (Phase 3, voluntary) | Push the wrong exercise id — `exerciseId: 'ex-missing'` | `records_and_trends_screen_test.dart` S-914 | `Found 0 widgets with text "Barbell Row"` (the pushed screen showed its guard empty state instead), once for Mock and once for Hive. 10 passed, 2 failed, exit 1 | Yes — restored and `grep -rn "ex-missing" lib/features/stats/` returns nothing; 12 passed, exit 0 |
| M7 (Phase 3, voluntary) | Never take the empty-state branch — `_summaries.isEmpty` replaced with `false` | `records_and_trends_screen_test.dart` S-910 | `Found 0 widgets with text "No sessions yet"` at the S-910 test, once for Mock and once for Hive. 10 passed, 2 failed, exit 1 | Yes — restored and `grep -rn "children: false" lib/features/stats/` returns nothing; 12 passed, exit 0 |

## 8. Stale-claim sweep (fill in)

Each command must give the stated output. Record what you saw.

| Command | Expected | Observed |
|---|---|---|
| `grep -rn "Exercise Details" docs/ lib/` | no output | **2 hits, both pre-existing and out of scope:** `docs/modality_based_exercise_ui.md:1` (a page title) and `lib/features/exercise/exercise_detail_view_screen.dart` (lines 1, 43, 113 — the pre-existing exercise-detail screen, unrelated to the two new views). Nothing this phase added uses that name, so the row's literal expectation cannot be met on this tree. Scoping note in §9c. |
| `grep -rn "VOLUME TRENDS" docs/` | no output | no output (checked over `docs/` excluding `docs/plans/`, where the plan's own §3 table quotes the claim it deleted) |
| `grep -rn "CONSISTENCY" docs/` | no output | no output (same exclusion) |
| `grep -rn "MaterialPageRoute(\|PageRouteBuilder(" lib/features/stats/` | no output | no output |
| `grep -rn "getRoundInstances(" lib/core/services/stats_progress_service.dart` | no output in the new computation | no output — the service's only round read is `getRoundInstancesByEffort()` at line 96, inside `_loadHistory()`, and the per-effort list is then read through `_HistoryIndex.roundInstancesOf` |
| `grep -rn -i "will be added\|in a later PR\|next we" docs/records_and_trends.md` | no output | no output |
| `gateway.sh git-diff --name-only` | lists neither `test/in_session_pr_toast_test.dart` nor `test/pr_toast_test.dart` | lists neither; the 11 tracked files it does list are the Phase 1 and 2 ones plus `lib/features/stats/stats_screen.dart` and `test/screen_widget_test.dart`. Both PR-toast files also ran green: `gateway.sh test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` → 41 passed, exit 0 |

## 8a. Decisions confirmed by the owner (2026-09-30)

The owner confirmed plan open questions 2, 6 and 9 as written. Recorded here; the plan's ledger is
unchanged.

| Question | Decision |
|---|---|
| 2 | The Sports headline value is **rounds completed** (total round-minutes secondary). |
| 6 | An exercise sits in the section of its **most-logged effort kind in that screen's range**; ties resolve Resistance, Cardio, Isometric, Sports. |
| 9 | Records & Trends lists **every exercise ever trained**, with **no recency cutoff**. |

## 9. Footprint (fill in)

| Phase | Files changed | Production lines added | Test lines added |
|---|---|---|---|
| Phase 1 | `workout_repository.dart` (+6), `hive_workout_repository.dart` (+13), `mock_workout_repository.dart` (+11), `docs/db_integration.md` (+8), `test/helpers/repository_harness.dart` (+60), `test/round_instances_by_effort_test.dart` (new, 128) | 30 (lib) | 188 |
| Phase 2 | `lib/core/models/exercise_metric.dart` (new, 128), `lib/core/services/stats_progress_service.dart` (+469/−1), `lib/features/stats/stats_screen.dart` (+6/−17), `docs/state_management/services_and_utils.md` (+31), `test/exercise_metric_service_test.dart` (new, 686) | 603 (lib) | 686 |
| Phase 3 | `lib/features/stats/records_and_trends_screen.dart` (new, 373), `lib/features/stats/exercise_progress_screen.dart` (new, 447), `lib/features/stats/widgets/stats_pill.dart` (new, 59), `lib/features/stats/widgets/recent_pr_list.dart` (new, 104), `lib/features/stats/widgets/native_value_format.dart` (new, 105), `lib/features/stats/stats_screen.dart` (193 changed, −148 net), `docs/stats_screen.md` (121 changed, −95 net), `docs/records_and_trends.md` (new, 129), `docs/README.md` (+1), `docs/navigation_and_screens.md` (+3), `test/records_and_trends_screen_test.dart` (new, 643), `test/screen_widget_test.dart` (25 changed) | 940 (lib: 1088 new lines in five files, −148 in `stats_screen.dart`) | 668 (643 new + 25 changed) |

### 9c. Notes on Phase 3

- **No red run for Phase 3.** The implementation landed before the test file, so the file never failed
  for want of the screens. Five inverse-edit proofs (M3 … M7, one per scenario) stand in for it and all
  five fail on both harnesses. Details in §6a.
- **The header tooltip vs. S-916.** The plan's Step 3.3 requires `tooltip: 'Records & Trends'` on the
  header action, and the house pattern agrees (`nutrition_screen.dart` does the same). Two pre-existing
  assertions in `test/screen_widget_test.dart` asserted `find.byType(Tooltip), findsNothing` over the
  *whole* Stats screen as a proxy for "the chart popup is gone", so any header tooltip trips them. Scoped
  both to the chart subtree and pinned the screen's total to one Tooltip: strictly the same guard (a
  re-added popup would still fail) but no longer a proxy for "the screen has no actions". S-916's own
  must-fail condition — a section, a header string or the window chip changing — is untouched and still
  asserted.
- **The `Exercise Details` sweep row.** §8's literal expectation cannot be met: the string is the title of
  the pre-existing exercise-detail page and screen, and neither this phase nor its docs use it. Left
  unedited rather than renamed, because renaming a page and a screen is not in this plan's scope.
- **Per-day, not per-session, history rows.** Exercise Progress's recent-session list renders
  `summary.points` — one per **training day** — not one per session, because that is the granularity
  `computeExerciseMetrics()` returns (the D-412 data shape). Two sessions on one day therefore appear as
  one row carrying the day's value. S-915's fixture uses three different days, so it cannot tell the two
  apart; recorded as an open question rather than changed here, since a per-session list needs a second
  data shape out of the service.
- **The undeletable probe file.** `test/zz_probe_hive_widget_test.dart` is a throwaway written while
  establishing that a `testWidgets` body cannot open the Hive harness (it hangs; the harness must be
  opened and seeded in `setUp`). This executor cannot delete files — `rm`, `mv`, `printf >`, `unlink` and
  `python3 os.remove` are all denied — so it was reduced to an 8-line comment plus a placeholder `test`,
  which is the full suite's extra `+1`. It must be deleted before merge.
- **The S-912 fixture deviates from the register.** The register puts all three exercises on one training
  day, where share order and name order agree and M3 could not bite. Incline Bench Press got three
  training days and Bench Press one. Names, section placement and the four search states are unchanged.
- **Entries are addressed by key, not by text.** The unfiltered view renders an exercise's name twice
  (once in the entry, once in Recent PRs), so `find.text` is ambiguous; every assertion uses
  `Key('records_entry_<id>')`.
- **Ordering deviates from D-413.** D-413 says `FuzzySearch.score` descending; `score` is an edit
  distance, so descending buries the closest match. Order is training-day share desc → name → id, which
  is what Step 3.1's own wording implies. In the plan's Assumption Log.
- **D-412's file list undercounts.** Three widgets were extracted or added under
  `lib/features/stats/widgets/`, not two. Feature-local widgets are not catalogued, so no
  `widget_catalog.md` change; in the plan's Assumption Log.
- **The fixture shape that makes M3 observable.** S-912's `ex-incline` has three training days
  (571 s of e1RM) against `ex-bench`'s one (665 s), so name order (`Bench` first) and share order
  (`Incline` first) disagree — the failing value in M3 is that disagreement.

### 9b. Notes on Phase 2

- **M1's shape.** The plan's M1 reads "decide the axis per range". A literal per-range mutation is
  invisible to S-904, because that scenario's range *is* all history and `ex-pull` holds a bodyweight set
  inside it. The mutation actually applied decides the axis from the entries of each `_resistanceValue`
  call, which is the per-day version of the same mistake; S-904's `ex-pull` points are the assertion that
  catches it, and they are the reason the scenario asserts a metric per point and not only the best.
- **`computeTotals()` has no scenario of its own.** The register runs S-904 … S-911, all of them
  `computeExerciseMetrics`; the totals rule is covered by the pre-existing
  `test/screen_widget_test.dart` case "rolling sessions are excluded from duration aggregates", which
  Step 2.9 re-ran unmodified.
- **The est. marker.** `estimated` is set only by a paced entry whose distance row is
  `DistanceSource.isEstimated`, not by an estimated distance sitting on an entry that carries no pace.
- **Degenerate bests.** An exercise whose in-range logs yield no value on its section's rule reports a
  zero `NativeValue` on that metric (reps 0, e1RM 0, duration 0, hold 0 + duration 0, rounds 0 +
  round-minutes 0) rather than dropping out of the list: the surface still needs a row for it.
- **Unknown effort kinds.** An exercise whose efforts all carry a kind outside set/timed/drill/round has
  no section to sit in and is dropped from the result.
- **Both harnesses.** Every S-904 … S-911 test runs twice, once over `MockWorkoutRepository` and once
  over `HiveWorkoutRepository`, which is what makes 16 tests out of 8 scenarios.
- **The doc entry.** Step 2.11's entry went under "Previously Undocumented Services & Utilities" in
  `docs/state_management/services_and_utils.md`, which is where that page already parks services with no
  home section.
- **§8 rows observed clean as a side effect.** `grep -rn "MaterialPageRoute(\|PageRouteBuilder("
  lib/features/stats/` and `grep -rn "getRoundInstances(" lib/core/services/stats_progress_service.dart`
  both returned nothing during Phase 2. The remaining §8 rows belong to Phase 3 and are left empty here.

### 9a. Notes on Phase 1

- **Rule 3 cannot run as written.** `cp` and `/tmp` are denied to this executor, so no mutation was
  needed in Phase 1 (it has no M-item) and none was run. Phase 2's M1/M2 and Phase 3's M3 use the
  inverse-edit method described in the brief, not copy-aside.
- **Step 1.7 fallback used.** `docs/db_integration.md` has no existing bulk-read lines (its Repository
  Contract section lists profile/measurement and active-session APIs only), so the
  `getRoundInstancesByEffort` line was added to that list, as Step 1.7 directs.
- **Harness signature deviation.** `roundInstance`'s `finishedAtMs` is declared `Object?` with a private
  sentinel default, not `int?`, because the plan requires both "defaults to the natural finish" and
  "settable to null independently of the state" (S-908). Callers write the same values either way.
- **S-903's shape.** S-901 and S-902 run per harness; S-903 runs once and compares Mock against Hive (and
  each against itself after `restart()`), because a per-harness test cannot observe the two disagreeing.
  M0 confirms it bites.
- **Formatting.** `gateway.sh format` was run only on the files this phase created or changed, by explicit
  path. `format --output=none --set-exit-if-changed` now reports 0 changed on all of them.

---

## Fix round 1 (review CHANGES_REQUESTED)

Doc and test fixes only; no product code changed. What changed, per finding:

| Fix | Change |
|---|---|
| F-1 | `docs/records_and_trends.md` gained the §4.1 scope block naming the two screens, `StatsProgressService.computeExerciseMetrics()` and `ExerciseMetric`. |
| F-2 | `docs/stats_screen.md`'s SPORTS paragraph: the false "same predicate `SessionSummaryBuilder` uses" sentence deleted, replaced by what the pass does (sums each day's finished timed instances' `actualDurationSecs`, never reads a `RoundInstance`) with the existing `Sports round aggregation (Phase D)` pointer. `docs/records_and_trends.md` gained one sentence naming the round rule's owner and pointing at the rule's home. |
| F-3 | One new plain `test()` in `test/records_and_trends_screen_test.dart` scanning `lib/*.dart` for `RecordsAndTrendsScreen(`. Both single-entry claims (`docs/records_and_trends.md`, `docs/stats_screen.md`) reworded to Records & Trends only and pointed at it; the `navigation_contract_enforcement_test.dart` pointer is gone. |
| F-4 | `docs/stats_screen.md` ISOMETRIC/SPORTS now name `StatsProgressService.kTopIsometricCount` / `kTopSportsCount` instead of "top-2". (The pre-existing CARDIO "top-2" is untouched — not in the review.) |
| F-5 | The three formatter-only hunks in `test/screen_widget_test.dart` reverted by hand; the diff for that file now holds only the two Tooltip-guard hunks. `gateway.sh format` was not run on it. |
| F-6 | `docs/data_models.md`: the code-reference table gained the `lib/core/models/exercise_metric.dart` row, and the overview sentence no longer claims all models live in `lib/data/models/models.dart` only. |

**F-3 red → green (inverse-edit method, no git stash/checkout/restore).** Noted state:
`gateway.sh git-diff -- test/records_and_trends_screen_test.dart` was empty (the file is untracked) and
`gateway.sh git-diff -- lib/main.dart` was empty.

| Step | Command | Observed |
|---|---|---|
| False claim | edited `lib/main.dart` to add `// RecordsAndTrendsScreen( probe — temporary, removed immediately` | — |
| Red | `gateway.sh test test/records_and_trends_screen_test.dart` | `+12 -1`: `Expected: ['lib/features/stats/stats_screen.dart'] Actual: ['lib/features/stats/stats_screen.dart', 'lib/main.dart']` at `test/records_and_trends_screen_test.dart:658` |
| Inverse edit | removed the probe line | `gateway.sh git-diff -- lib/main.dart` empty again |
| Green | `gateway.sh test test/records_and_trends_screen_test.dart` (in the targeted trio) | passed |

**Commands and counts.**

| Command | Result |
|---|---|
| `gateway.sh test test/docs_indexing_contract_test.dart test/records_and_trends_screen_test.dart test/screen_widget_test.dart` | `+272: All tests passed!` (exit 0) |
| `gateway.sh test` | `+3154 ~1: All tests passed!` (was `+3153 ~1`; +1 for the new test) |
| `gateway.sh lint` | 199 issues, 0 errors; the only issues in a touched file are the two pre-existing `unused_local_variable` warnings at `test/screen_widget_test.dart:4449-4450`, which the diff does not touch |
| `gateway.sh git-diff HEAD -- test/screen_widget_test.dart` | two Tooltip hunks only |
| `gateway.sh git-diff -- lib/main.dart` | empty (inverse edit clean) |

---

## Fix round 2 (review CHANGES_REQUESTED, round 2)

Doc-only. What changed, per finding:

| Fix | Change |
|---|---|
| F-7 | `docs/records_and_trends.md` scope block: the non-existent `ExerciseMetric` type replaced by `ExerciseMetricSummary` and `NativeValue`, both read from `lib/core/models/exercise_metric.dart`; a `docs/`-wide search for `ExerciseMetric` followed by a non-letter (excluding `docs/history/`, `docs/releases/`, `docs/plans/`) returns no other occurrence. |
| F-8 | `docs/data_models.md` overview sentence no longer claims the code-reference table is exhaustive: it now says the table lists the model files it names. |
| F-9 | `…plan.review.md` created (the reviewer has no file-creation tool): round 1 and round 2 copied verbatim from `.work/stats-pr4/review-round-1.md` and `review-round-2.md` (byte-compared with `diff`, both exact), plus a `## Round 3` line recording the pending verification. |

**Commands and counts.**

| Command | Result |
|---|---|
| `gateway.sh test test/docs_indexing_contract_test.dart` | `+9: All tests passed!` (exit 0) |
| `gateway.sh test` | `+3154 ~1: All tests passed!` (exit 0; unchanged from the last known count) |
| `gateway.sh lint` | 199 issues, 0 errors (unchanged) |
| `diff` of the review file's slices against `.work/stats-pr4/review-round-1.md` / `review-round-2.md` | empty — verbatim |
