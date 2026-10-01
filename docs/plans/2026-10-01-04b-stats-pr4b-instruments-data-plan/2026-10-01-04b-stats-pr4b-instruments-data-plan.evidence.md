# Evidence — Stats PR 4b, the Instruments data

> **Companion to:** `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.md`
> **Rule:** baselines, suite output, mutation proofs and test-bump records go **here**, never into the plan.
> **Status:** created by the planner with §1's baselines and the ground truth pre-filled; the implementer
> and the reviewer fill §4…§9 as the phases run.
> **Siblings:** the Instruments list on the Stats screen is
> `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/…`; the Fuel row is
> `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/…` (NOT READY).

---

## §0 Owner decisions (2026-10-01, for the whole 4b / 4b2 series)

Recorded by the implementer from the run brief; they bind every phase of this series.

| # | Decision |
|---|---|
| OW-1 | The change indicator compares the window's value against the **immediately preceding range of the same length** (D-508's basis). |
| OW-2 | Pace's arrow follows the **raw sign** of the delta: a slower pace (a larger seconds-per-unit value) reads `↑`. No per-metric inversion (D-508). |
| OW-3 | The trend line is **hidden below 2 points** (D-510, 4b2). |
| OW-4 | A row with no readable value **still appears**, with the zero fallback (D-505). |

---

## §1 Baselines (planner-recorded, re-run by the implementer before Phase 1)

Commands are `.github/copilot/scripts/macos/gateway.sh …` from the repository root.

| Command | Recorded by the planner | Re-run by the implementer |
|---|---|---|
| `gateway.sh lint` | `199 issues found.` (4 warnings, 0 errors, 195 infos) | `199 issues found.` — 0 errors (`grep -c "error •"` → 0); matches |
| `gateway.sh test` | `+3153 ~1: All tests passed!` | `+3153 ~1: All tests passed!`; matches |

**If your numbers differ, record what you saw and say so.** A different baseline is information; a missing
baseline is a failed phase.

The analyzer bar for every phase: **0 errors** and **no more than the baseline issue count**; every file the
phase touches has **0 issues of its own**.

`~1` is a pre-existing skipped test. It is not this PR's business; do not "fix" it.

---

## §2 Ground truth the plan was written against (H-numbered)

Verified by reading `lib/` on the plan's date. If any of these is false when you start, the plan's phase
that depends on it is wrong — say so in §7 rather than working around it.

| # | Fact | Where | Used by |
|---|---|---|---|
| H-1 | `enum ExerciseSection { resistance, cardio, isometric, sports }` — this declaration order is D-504's tie-break | `lib/core/models/exercise_metric.dart` | D-504, Phase 2 |
| H-2 | `enum NativeMetric { estimatedOneRepMax, reps, pace, duration, hold, rounds, roundMinutes }` | same | D-508, Phase 2 |
| H-3 | `NativeValue { metric, value, secondaryMetric?, secondaryValue?, estimated = false, addedWeightKg? }` | same | D-508, Phase 2 |
| H-4 | `ExerciseMetricSummary { exerciseId, name, section, best, points (oldest first), lastTrainedMs, sessionCount }` | same | D-506, D-514 |
| H-5 | `computeExerciseMetrics({fromMs, toMs})` counts sessions by `startedAtMs` inclusive, skips efforts with a null `exerciseId`, picks the section from the most-logged effort kind with ties in declaration order, and **falls back to `_zeroValueFor`** — a row can carry a zero value with zero points | `lib/core/services/stats_progress_service.dart` (~599) | D-505, D-506 |
| H-6 | Cardio builds `pace` (with `estimated` from `DistanceSource.isEstimated`) or `duration`, and **no secondary**; Isometric builds `hold` + `secondaryMetric: duration`; Sports builds `rounds` + `secondaryMetric: roundMinutes`; Resistance builds e1RM/reps with `addedWeightKg` | same | D-508, S-1007 |
| H-7 | `_secondaryLabel` maps `duration` → `'Total hold'`, `roundMinutes` → `'Total time'`, else null | `lib/features/stats/exercise_progress_screen.dart` (~195) | D-516a |
| H-8 | `native_value_format.dart` exports `formatNativeMetric`, `formatNativeValue` (appends `'(+<weight>)'` then `' est.'`), `formatNativeSecondary`, `nativeMetricDisplayValue`, `nativeMetricUnitLabel`; pace conversion uses `UnitFormatter.metresPerUnit` | `lib/features/stats/widgets/native_value_format.dart` | D-516a, Phase 2 Step 8 |
| H-9 | `SensorSummary { id, sessionId, scope, targetId, windowStartMs, windowEndMs, avgHeartRateBpm?, maxHeartRateBpm?, steps?, source, createdAtMs }`; the scope constants are `SensorSummary.scopeSession` / `scopeEffort` / `scopeTimedInstance` / `scopeRoundInstance` | `lib/data/models/models.dart` (~2420) | D-511…D-513 |
| H-10 | `getSensorSummariesForSession` sorts by `scopes.indexOf(scope)`, then `windowStartMs`, then `targetId`; **the comparator is duplicated** in Hive and Mock | `lib/data/repositories/hive_workout_repository.dart` (~3164), `mock_workout_repository.dart` (~2311) | D-513, Phase 1 Steps 5/6 |
| H-11 | Nothing in `lib/` reads `SensorSummary` today, and there is no bulk read | whole-tree search | Phase 1 |
| H-12 | `test/helpers/repository_harness.dart` exposes `harnessFactories` (Mock, Hive), `fixtureStart`, `fixtureRowAt`, `seedSession({sessionId, modality, isRolling, daysAgo})`, `seedExercise`, `seedWeightedSets`, `seedBodyweightSets`, `seedTimedEntries({metresBase})`, `seedHoldEffort({effortKind})`, `seedRoundEffort`, `seedSetEffort`, `loadState`, `storedRows`, `storedRowIds` — and **no sensor helper** | `test/helpers/repository_harness.dart` | Phase 1 Step 1 |
| H-13 | `test/records_and_trends_screen_test.dart` is the structural template for a harness-factory test file (`for (final factory in harnessFactories)`, harness open/close in `setUp`/`tearDown`), and it already holds the "`StatsScreen` is the only constructor of `RecordsAndTrendsScreen`" source-scan guard (~line 648) | same | Phase 1 Step 2, Phase 2 Step 2 |
| H-14 | `StatsScreen._loadData()` builds one `CalendarState` and one `StatsProgressService`; `build()` renders `OmniCardHeader('ALL TIME')` → `_buildAggregateCard` → five legacy sections separated by 24dp | `lib/features/stats/stats_screen.dart` | 4b2 only |
| H-15 | `_buildWindowChip` renders `Text(key: Key('stats_window_chip'), '· ${window.label}', labelSmall + textMuted + italic, maxLines 1, ellipsis)` and is used by the four legacy headers | same (~172) | 4b2 only (D-516b) |
| H-16 | `docs/design_system.md`'s canonical-header inventory lists Stats as `ALL TIME`, `STRENGTH`/`CARDIO`, `NUTRITION` (~line 180) | `docs/design_system.md` | 4b2 only |
| H-17 | `docs/stats_screen.md`'s Key Constants table is at ~line 499 (`kTopLiftCount`, `kTopCardioCount`, `kRecentPRCount`, `kRecentTrainingDaysWindow`) | `docs/stats_screen.md` | 4b2 only |
| H-18 | `docs/db_integration.md` lists the repository reads, with `getRoundInstancesByEffort()` at ~line 48 under "Bulk per-effort read" | `docs/db_integration.md` | Phase 1 Step 8 |
| H-19 | `docs/` files over 64 KiB are skipped by the indexing tools; `docs/plans/` is an exempt record folder | `test/docs_indexing_contract_test.dart` | doc checklist |
| H-20 | `ExerciseProgressScreen({required workoutState, required settingsState, required exerciseId})` — no other constructor | `lib/features/stats/exercise_progress_screen.dart` (~26) | 4b2 only (D-515) |

---

## §3 Drift found while planning

| # | Kind | Finding | Disposition |
|---|---|---|---|
| DR-2 | pack ↔ code | The pack's bullet "update or retire the top-N selection tests in `test/stats_progress_test.dart`" cannot be honoured in 4b: `computeProgressData` and the five legacy sections are still live, so those tests must pass **unmodified**. Retiring them here would delete the guard on live code. | O-1 defers it to 4c. |
| DR-4 | code ↔ code | The sensor-summary comparator is duplicated in Hive and Mock. A new bulk read must not add a third copy. | D-513 + Phase 1 Steps 5/6 extract one comparator. |

Drift that belongs to the sibling plans (the header inventory, the `ExerciseProgressScreen` entry-point
doc, the legacy test surface heights) is recorded in 4b2's evidence file.

---

## §4 Per-phase evidence (implementer fills)

### Phase 1 — the bulk sensor-summary read (@dba)

| Item | Output (verbatim) |
|---|---|
| Red run (`test/sensor_summaries_by_session_test.dart` before the implementation) | `flutter test` → `00:00 +0 -1: loading …/sensor_summaries_by_session_test.dart [E]` — `Failed to load … Compilation failed … Error: The method 'getSensorSummariesBySession' isn't defined for the type 'WorkoutRepository'.` at `test/sensor_summaries_by_session_test.dart:114:38`, `:129:38`, `:137:38`. `00:00 +0 -1: Some tests failed.` |
| Green run — the new file | `00:00 +6: All tests passed!` (Mock S-1002, S-1003, S-1004; Hive S-1002, S-1003, S-1004) |
| Green run — `test/watch_capture_repository_parity_test.dart test/db_seed_test.dart` | `00:00 +49: All tests passed!` (with the new file in the same run) |
| Full suite | `01:18 +3159 ~1: All tests passed!` — baseline `+3153 ~1` plus the 6 new tests; 0 failures |
| `gateway.sh lint` | `199 issues found.` — 0 errors; equal to the 199 baseline; `grep` for the three touched Dart files and the new test file in the analyzer output → no hits |
| Search sweep — `getSensorSummariesBySession` in `lib/` | exactly 3: `workout_repository.dart:790` (declaration), `hive_workout_repository.dart:3192`, `mock_workout_repository.dart:2337`. No caller. |
| Search sweep — `UnimplementedError` / `TODO` in `lib/data/repositories/` | no matches |
| Mutation M0 (grouping removed) — failing output | `(grouped[''] ??= …)` in the Hive bulk read → `Hive S-1002 … [E]` / `Expected: Set:['s-x', 's-z']` / `Actual: Set:['']` / `Which: does not contain 's-x'` at `test/sensor_summaries_by_session_test.dart:120:9`; also `Hive S-1004 … [E]` at `:143:9`. `00:00 +4 -2: Some tests failed.` |
| M0 restored — passing output | `git-diff -- lib/data/repositories/hive_workout_repository.dart` back to the pre-mutation blob (`index 031f574..7a79f00`, 29 insertions / 9 deletions); `00:00 +6: All tests passed!` |
| `gateway.sh git-diff --stat -- lib/data test/helpers test/sensor_summaries_by_session_test.dart docs/db_integration.md` | `docs/db_integration.md 13 +`; `hive_workout_repository.dart 38`; `mock_workout_repository.dart 37`; `workout_repository.dart 7`; `test/helpers/repository_harness.dart 33`. `test/sensor_summaries_by_session_test.dart` is new and therefore untracked, so it does not appear — 5 files changed, 110 insertions, 18 deletions. Matches the Predicted Files exactly. |
| Assumption-log entries opened this phase | A-1 (the harness `sensorSummary` helper fills `maxHeartRateBpm` from `avgHeartRateBpm`) |

**One implementation note worth recording.** The new test file's population is built **once** as a top-level `final`, not by a function: `fixtureStart` in the harness is a clock reading, so a second construction stamps `createdAtMs` one millisecond later and S-1004's `toMap` comparison fails on the stamp alone. The first green attempt showed exactly that (`created_at_ms` `1790787021076` against `1790787021075`).

### Phase 2 — the Instruments computation (@developer)

| Item | Output (verbatim) |
|---|---|
| Red run (`test/instrument_list_service_test.dart`, `test/instrument_change_format_test.dart`) | The two test files were written before the implementation by the interrupted run, which the runner stopped before its red output was captured. Red-ness is re-established by M1–M3 below: each removes one behaviour the tests guard and shows the named test failing. |
| Green run — the two new files + `test/records_and_trends_screen_test.dart` | `00:01 +37: All tests passed!` (18 service + 6 change-format + 13 records-and-trends). The plan's Step 9 also names `test/exercise_progress_screen_test.dart`; that file does not exist — running it gives `Failed to load …: Does not exist.` 4a's `ExerciseProgressScreen` assertions live in `test/records_and_trends_screen_test.dart` (S-913…S-915), which this run covers. |
| Full suite | `01:14 +3183 ~1: All tests passed!` — baseline `+3159 ~1` plus the 24 new tests; 0 failures |
| `gateway.sh lint` (per-file: 0 issues for the three touched lib files) | `199 issues found.` — 0 errors, equal to the 199 baseline. Filtering the analyzer output for `instrument_list`, `stats_progress_service`, `native_value_format`, `exercise_progress_screen`, `instrument_list_service_test`, `instrument_change_format_test` → no hits (grep exit 1). |
| Search sweep — `SensorSummary` in `lib/` | Readers: `stats_progress_service.dart` plus the two repositories. No file under `lib/features/` or `lib/widgets/` references it (`grep -l` exit 1). Pre-existing non-reader references remain in `models.dart`, `session_edit_snapshot.dart`, `watch_session_importer.dart` and the three `session_core*.dart` files. |
| Search sweep — `_secondaryLabel` in `lib/features/stats/` | No matches (grep exit 1). |
| Mutation M1 (section order) — failing output | Replaced D-504's sort with `sections.sort((a, b) => a.section.index.compareTo(b.section.index));` → Mock and Hive S-1005 `[E]`; `Which: at location [0] is ExerciseSection:<ExerciseSection.resistance> instead of ExerciseSection:<ExerciseSection.cardio>`; `00:00 +16 -2: Some tests failed.` |
| M1 restored — passing output | Diff back to the pre-mutation content (`245 insertions(+), 1 deletion(-)` at that moment; `243` after the final `dart format`); `00:00 +18: All tests passed!` |
| Mutation M2 (cadence denominator) — failing output | Moved `stepsDurationSecs += instance.actualDurationSecs;` above the `instanceSteps == null` guard, so every timed instance's minutes count → Mock and Hive S-1008 `[E]`; `Expected: null` / `Actual: <0>`; `00:00 +16 -2: Some tests failed.` |
| M2 restored — passing output | Diff back to the pre-mutation content; `00:00 +18: All tests passed!` |
| Mutation M3 (the comparison) — failing output | `final previousSummary = summary;` (the window's own summary instead of the previous range's) → Mock and Hive S-1009 `[E]`; `Expected: a value greater than <0>` / `Actual: <0.0>`, and the calendar test `Expected: null` / `Actual: <Instance of 'NativeValue'>`; `00:00 +14 -4: Some tests failed.` |
| M3 restored — passing output | Diff back to the pre-mutation content; `00:00 +18: All tests passed!` |
| Mutation M4 (calendar vs `Duration`) — host `TZ` and observed result | Host `TZ` unset; local zone `EDT` (America/New_York). Mutated `previousRangeFor` to `from.subtract(Duration(days: dayCount))` → `00:00 +18: All tests passed!` — **no red run observed**, and none is claimed. The 2026-03-08 US transition is at 02:00 local, after the local-midnight boundary the fixture uses, so both forms resolve to the same instant and S-1009's calendar assertion cannot distinguish them. The calendar form is kept because D-509 requires it. |
| `gateway.sh git-diff --stat -- lib/core lib/features/stats test docs` | `docs/data_models.md 5 +`; `docs/db_integration.md 13 +` (Phase 1); `docs/plans/2026-09-30-04-stats-pr4-index.md 106 +` (pre-existing working-tree change, not this run's); `docs/state_management/services_and_utils.md 41 +`; `lib/core/services/stats_progress_service.dart 244 +`; `lib/features/stats/exercise_progress_screen.dart 20 +-`; `lib/features/stats/widgets/native_value_format.dart 38 +`; `test/helpers/repository_harness.dart 31 +` (Phase 1). The three new files (`lib/core/models/instrument_list.dart`, `test/instrument_list_service_test.dart`, `test/instrument_change_format_test.dart`) are untracked and do not appear. |
| Assumption-log entries opened this phase | A-2 (the formatter claim's home), A-3 (the value types' doc entry) |

---

## §5 Surface-height bumps

Not applicable to this PR: it changes no widget. 4b2's evidence file holds the bumps.

---

## §6 Doc updates (each phase, checked off as done)

| Doc | Phase | Claim added | Test named in the plan's table |
|---|---|---|---|
| `docs/db_integration.md` | 1 | New "Bulk per-session read" entry: `getSensorSummariesBySession()` returns every summary grouped by `sessionId`, each group in `getSensorSummariesForSession`'s order (scope, `windowStartMs`, `targetId`), one comparator per implementation; a session with no summaries has no key; Mock mirrors Hive value for value; no model, schema or seed file changed. | `test/sensor_summaries_by_session_test.dart` (S-1002, S-1003, S-1004); `test/db_seed_test.dart` green, unmodified | |
| `docs/state_management/services_and_utils.md` | 2 | `computeInstrumentSections` — its two `computeExerciseMetrics` calls (window + the preceding range of the same calendar length), section ordering by distinct training days descending with declaration-order ties (supersedes `computeProgressData`'s fixed order for this list only), row ordering by training days then name then id, the change indicator's absence on a missing or different-metric previous value, the calendar-arithmetic previous range, and cadence/heart rate from the window's `SensorSummary` rows. Plus `formatNativeChange`'s arrow/`'—'` contract and `nativeSecondaryLabel` as the single label source. | `test/instrument_list_service_test.dart` (S-1005, S-1007, S-1008, S-1009, S-1010); `test/instrument_change_format_test.dart` |
| `docs/data_models.md` | 2 | New "The Instruments list value types" section: `InstrumentSectionData`/`InstrumentRow` are derived and never persisted; a section owns its ordered rows and the distinct-training-day rank, a row owns one `ExerciseMetricSummary` plus the preceding-range value and the sensor figures; built by `computeInstrumentSections`. New Code References row for `lib/core/models/instrument_list.dart`. | `test/instrument_list_service_test.dart` (S-1007) |

Also confirm: no file in `docs/` outside `docs/plans/` exceeds 64 KiB
(`test/docs_indexing_contract_test.dart` green).

---

## §7 Deviations from the plan

Anything done that the plan did not say, and anything the plan said that was not done. The reviewer reads
this list first; an empty list after a complex phase is itself suspicious.

| Phase | Deviation | Why |
|---|---|---|
| 1 | S-1002's fixture writes the session-scope summary with `targetId: 's-x'`, not the empty target the plan's notation shows. | `SensorSummary._checkInvariants` requires `targetId == sessionId` for `scopeSession` and rejects an empty `targetId`; the read's order is unaffected. |
| 1 | The new test file's population is a top-level `final` list rather than a builder function. | `fixtureStart` is a clock reading; a second construction would stamp different `createdAtMs` values and S-1004's `toMap` comparison would fail on the stamp alone. |
| 1 | S-1004 is asserted against one shared literal expectation (`_expected()`), which both harness groups compare their read to. | The plan's file structure is one group per harness, so a single test body cannot hold both stores; a shared storage-independent expectation proves the same thing — neither implementation may deviate from it. |
| 2 | S-1013's expected row order corrected to `['ex-squat', 'ex-row']` (was `['ex-row', 'ex-squat']`). | Both exercises are trained on the same two days, so D-506's tie falls to the name: `'Back Squat'` sorts before `'Barbell Row'`. The service's sort was not changed. |
| 2 | Phase 2 Step 9 names `test/exercise_progress_screen_test.dart`, which does not exist. | 4a's `ExerciseProgressScreen` assertions live in `test/records_and_trends_screen_test.dart` (S-913…S-915), so the green run covers that file. Running the named path fails to load (`Does not exist.`). |
| 2 | The plan's §Doc-claim table assigns the `formatNativeChange` claim to `docs/state_management/services_and_utils.md`, but the function lives in `lib/features/stats/widgets/native_value_format.dart`, outside that document's stated scope. | The document's scope line now names that file; the claim is stated as an output contract with its test pointer. |
| 2 | The plan's §Doc-claim table says `docs/data_models.md` will record the two types' "fields"; the entry records their relationships and lifecycle instead. | `docs/documentation_standard.md` §6.2 forbids per-class field tables in that document — the model source owns them. |
| 2 | `docs/plans/2026-09-30-04-stats-pr4-index.md` shows as modified in the working tree (106 lines). | It is in neither phase's Predicted Files and was not touched by this run; it is a pre-existing working-tree change from the planning/earlier run. |
| 2 | `gateway.sh format` was run on the four Phase 2 Dart files; it reflowed two added lines of `stats_progress_service.dart` (246 → 244 diff lines) and both new test files. | The formatter is the repository's own; the reflow is whitespace only and the suites were re-run green afterwards. |

---

## §8 Reviewer findings

Filled by `@code-reviewer` against the plan's checklist. Quantify every defect: count, examples, and the
root-cause line. Each defect that becomes a remediation phase must carry a structural guard.

| # | Severity | Finding | Count / examples | Root cause | Disposition |
|---|---|---|---|---|---|
| | | | | | |

**Parity check (Hive ↔ Mock) for every touched data path:**

| Path | Result |
|---|---|
| `getSensorSummariesBySession` | |

**Predicted-Files audit:**

| Phase | Out-of-bounds files touched | Predicted files untouched |
|---|---|---|
| 1 | | |
| 2 | | |

---

## §9 Scenario conformance

One row per scenario this plan owns, with the test that covers it and the fixture-population check. A
scenario whose fixture was not populated as stated is a defect, not a passing test. S-1001, S-1011,
S-1012, S-1014…S-1017 are 4b2's; S-1101…S-1110 are 4b3's.

| Scenario | Test | Fixture as specified? | Result |
|---|---|---|---|
| S-1002 | `test/sensor_summaries_by_session_test.dart` — `S-1002 groups by session and orders like the single-session read` | Yes: `s-x` holds the four summaries written out of display order (timed_instance/t2 @2000, timed_instance/t1 @1000, session @500, effort/e1 @1000); `s-y` holds none and is never written; `s-z` holds one round_instance summary. The session-scope target is `s-x` (the model requires `targetId == sessionId`). | Pass (Mock, Hive) |
| S-1003 | same file — `S-1003 no summaries at all is an empty map` | Yes: a session and an exercise, zero summaries. | Pass (Mock, Hive) |
| S-1004 | same file — `S-1004 Hive and Mock agree value-for-value` | Yes: the S-1002 population, seeded identically in each store; compared by `toMap` against one shared expectation, so both stores must match it. | Pass (Mock, Hive) |
| S-1005 | `test/instrument_list_service_test.dart` — `S-1005 sections are ordered by training days in the window` | Yes: `ex-run` timed on days 1, 2, 3; `ex-squat` set on day 2. Part (b) uses a 2-day window, which excludes the day-2 resistance session. | Pass (Mock, Hive) |
| S-1006 | same file — `S-1006 the section comes from the effort kind, not the session modality` | Yes: (a) `modality: null` session with a `set`; (b) `resistance_lifting` with a `timed`; (c) `timed` on `ex-plank-timed`; (d) `drill` on the second `'Plank'` exercise `ex-plank-hold`; (e) `round` in a `sports` session. Two distinct exercise ids named `'Plank'` land in Cardio and Isometric. | Pass (Mock, Hive) |
| S-1007 | same file — `S-1007 the native value per row is 4a's, formatted by 4a's formatter` | Yes: weighted 5×100 kg, a bodyweight pull-up with an added-weight row, a cardio run with distance, a cardio walk without, a `hold`, a `timed` isometric, and a sports round effort; every row is compared to `computeExerciseMetrics`' own value and formatted through 4a's formatter. | Pass (Mock, Hive) |
| S-1008 | same file — `S-1008 cadence and average heart rate` | Yes: (a) 300 s + 600 s instances with steps 600/1200 and HR 140/150; (b) a second cardio exercise with no summaries; (c) two round summaries at HR 146/150; (d) an isometric and a resistance exercise that do carry summaries. | Pass (Mock, Hive) |
| S-1009 | same file — `S-1009 the change indicator, and when it must not appear` and `S-1009 the previous range is calendar arithmetic` | Yes: a 7-day window with `ex-a` up, `ex-b` down, `ex-c` window-only, `ex-d` `drill` now vs `timed` before, `ex-e` identical, `ex-f` previous-range-only; the calendar half asserts `previousRangeFor` directly for a `DateTime(2026, 3, 8)` window. | Pass (Mock, Hive) |
| S-1010 | same file — `S-1010 row ordering, duplicate names and a zero-valued row` | Yes: `ex-3` on 3 days, `ex-2` on 2, `ex-1` on 1, `ex-0` with no readable value, and two exercises both named `'Custom Press'` on 2 days each. | Pass (Mock, Hive) |
| S-1013 | same file — `S-1013 a lifter-only user` | Yes: `ex-squat` and `ex-row`, both `set` efforts on days 1 and 2. | Pass (Mock, Hive) |
| S-1018 | same file — `S-1018 an exercise with a single session` | Yes: one `set` effort, one session, no previous-range history. | Pass (Mock, Hive) |

---

## Fix round 1 (review verdict CHANGES_REQUESTED — doc-only)

Review: `…-plan.review.md`. Scope: findings F-1…F-4 only; findings 5 and 7 untouched.

| Finding | Edit | Check |
|---|---|---|
| F-1 (blocker) | `docs/data_models.md` — dropped the clause asserting an Instruments list the Stats screen renders, and fixed "A `InstrumentSectionData`" → "An" | Observed the paragraph; `docs_indexing_contract_test.dart` green |
| F-2 | `docs/state_management/services_and_utils.md` — "It is the Instruments list's read" → "It is the window's sections-and-rows read" | Observed the paragraph; no rendered surface asserted |
| F-3 | same file — row rank stated as the count of days carrying a readable value, with the zero-fallback row sorting last; S-1010 pointer retained | Cross-checked `stats_progress_service.dart` sort key (`points.length` desc) and `S-1010`'s expected order (`ex-0` last) |
| F-4 | `docs/db_integration.md` — restated as the durable contract (the read adds no schema or seed requirement); `test/db_seed_test.dart` pointer kept | Observed the bullet |

Checks run (observed):

- `gateway.sh test test/docs_indexing_contract_test.dart` → `+9: All tests passed!`
- `gateway.sh test` → `+3183 ~1: All tests passed!` (no change from baseline)
- `gateway.sh lint` → `199 issues found`, `grep -c "error •"` = 0
