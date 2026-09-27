# PR 3a — Evidence (companion to `2026-09-26-03a-stats-pr3a-phone-distance-plan.md`)

Baselines, code facts the plan's decisions rest on, and the executors' red→green records live
here, per `.github/agents/pr_scope_budget.md` §2. The plan only points here.

## 1. Planning baselines (conductor-v2, observed 2026-09-26 on `develop` @ 2690d1b, clean tree)

| Check | Command | Observed |
|---|---|---|
| Flutter suite | `flutter test > <log> 2>&1` | `01:11 +3000 ~1: All tests passed!`, exit 0, 1m16s wall. The one skip is pre-existing: `test/profile_navigation_test.dart:39` (`skip: true`). |
| Analyzer | `flutter analyze > <log> 2>&1` | `242 issues found.`: 0 errors, 11 warnings, 231 infos. Exit code 1, because infos are fatal by default. Same count as PR 2's recorded baseline. |
| Swift package | `cd watch/watchos && swift test` | `Executed 242 tests, with 0 failures`, exit 0. 3a touches no Swift, so this is reference only. |

**Analyzer baseline per predicted file.** "None new" means these counts must not rise.

| File | Issues at baseline |
|---|---|
| `lib/features/session/session_summary_screen.dart` | 10 infos: 8 `deprecated_member_use` (`withOpacity`) and 2 `use_build_context_synchronously` |
| `lib/features/stats/stats_screen.dart` | 1 warning: `unused_element` (`_ChartSeries`, ~2145) |
| every other file in the plan's Predicted Files | 0 |

## 2. Code facts (file:line on `develop` @ 2690d1b)

| # | Fact | Evidence | Used by |
|---|---|---|---|
| F1 | (Context for the superseded D-305.) Only two paths create a session whose modality is `cardio_endurance`: a Cardio tile start, and a planned (non-routine) Cardio session started from the calendar day list. | `lib/features/home/home_screen.dart:806`; `lib/features/calendar/day_session_list_screen.dart:268` | D-305 |
| F2 | Routine sessions are created with `modality: null` ("Mixed modality for routines"). Free and rolling sessions also have no modality. A rolling session opened from the Cardio tile keeps `modality: null`; the tile only passes a `preferredModality` hint. | `lib/features/routine/my_routines_screen.dart:230-236`; `day_session_list_screen.dart:256-262`; `home_screen.dart:941, 757-771` | superseded D-305 (context) |
| F3 | Inside a session with a modality, every added exercise takes the modality's effort kind. Cardio's is `timed`. The add-exercise screens only override the kind when the session modality is null. So a Cardio session contains only timed entries. | `lib/state/workout/session_core_entry.dart:23-33`; `lib/core/constants/modality_config.dart:55-67`; `lib/features/session/workout_session_screen.dart:1352-1391`; `lib/features/session/session_overview_screen.dart:65-92` | D-319 (a Cardio session is all timed) |
| F4 | A distance is an `EffortObservation` with `metric-distance`, stored in metres. Every timed entry gets one, with value 0.0 when no distance was entered, both on the phone and in the watch import. | `lib/core/utils/logged_entry_rows.dart:77-96`; `session_core_entry.dart:131`; `lib/core/services/watch_session_importer.dart:697-704` | D-301, D-311 |
| F5 | No phone surface can enter a distance. The live screen shows one dominant metric with no distance input. Edit Session shows only duration and added weight for a timed entry. "Track by Distance" only picks the `timed` kind. | `lib/widgets/session/set_metric_widget.dart:12-15`; `lib/features/session/workout_session_detail_view.dart:222-279`; `modality_config.dart:255-256` | D-304 |
| F6 | Watch-started sessions reach history with no modality (PR 2 D-135). Their distance is the wrist's hand-dialled `distanceMeters`, because GPS never starts for them (PR 2 O-8). So every distance stored today was typed or dialled by a person. | `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift:144`; `WatchStartPaths.swift:217, 226`; `watch_session_importer.dart:1349` | D-301 (null reads as entered) |
| F7 | The Summary lists no entries. Its layout is: info header and card, modality group cards, SESSION NOTE, calendar. The Edit Session menu item is at :688. On the post-workout Summary, the session is ended at Done (:395). | `lib/features/session/session_summary_screen.dart:704-717, 688, 385-400` | D-306, D-315 |
| F8 | The tap-to-edit dialog's Ok calls back even when the value is unchanged. An outside tap, or empty or unparseable text, closes it without a callback. An unknown metric type falls through to a lowercase title and an unclamped parse. | `lib/widgets/session/metric_crown_widget.dart:14-43, 48-82, 95-195` | D-307, D-316 |
| F9 | Four places copy an observation field by field: `updateEntryValue` (:245), `markSetSkipped` (:302), and `cloneSessionBlock` on both repositories. The edit-session restore re-creates rows from the snapshot's own objects, so it keeps every field `toMap` writes. | `session_core_entry.dart:245, 302`; `lib/data/repositories/hive_workout_repository.dart:2841`; `lib/data/repositories/mock_workout_repository.dart:2029`; `lib/state/workout/session_core_lifecycle.dart:273-320` | D-311, S-804 |
| F10 | Distances are paired with timed entries by list position: the i-th instance with the i-th distance row, in raw list order (builder :356-368, `updateEntryValue` :228-241). Hive iterates rows in sorted key order, so `obs-X-10-distance` comes before `obs-X-2-distance`. An effort may hold 12 entries. A reloaded session with 11 or more timed entries of one exercise therefore pairs differently from the live one. | `lib/state/workout/session_summary_builder.dart:346-368`; `hive_workout_repository.dart:1333-1350`; `lib/core/constants/workout_constants.dart:4` | D-312, S-808 |
| F11 | Pre-existing id drift. Deleting a timed entry re-numbers the remaining instances but deletes companion rows by the current index's id prefix. Adding an entry mints its ids from the current count, so after a deletion it can reuse, and overwrite, an existing row's id. | `lib/state/workout/timer_manager.dart:549-575`; `session_core_entry.dart:68-131, 342-392` | Open Item O-3 |
| F12 | The Stats day pace divides all finished time by all distances. Distance only sums values greater than 0. km↔mi conversion is inlined in three places. A fresh `StatsProgressService` is built on every Stats load, so a write shows on the next open. | `lib/core/services/stats_progress_service.dart:476-490, 634-678`; `lib/features/stats/stats_screen.dart:1901, 2011, 2018, 84` | D-309, D-314, S-837 |
| F13 | Chart dots are `FlDotCirclePainter` instances (radius 3, series-colour fill, surface stroke 1.5). Pace spots skip days without pace, so a spot's `x` is its trend index. | `stats_screen.dart:1674-1690, 1782-1812` | D-317 |
| F14 | Pre-existing schema/model drift. `EffortObservation.toMap` writes `value_bool: 0` for null, but `app_effort_observation`'s CHECK requires exactly one non-null value column. So a `toMap` row can't be inserted as-is, and no test inserts one. | `lib/data/models/models.dart:603`; `scripts/sqlite_schema.sql:356-380` | Phase 1 SQL test design; Open Item O-4 |
| F15 | Hive stores raw maps with no adapters, so a new nullable key needs no migration and an absent key reads as null. | `hive_workout_repository.dart:35`; `models.dart:579-593` | D-311 |
| F17 | Each tracking modality maps to exactly one effort kind, and only Cardio yields `timed`. `configs` holds the four modalities plus `null` (which gives `set`). Legacy modalities have no config and fall back to `set`. Every add-exercise path turns the picked or inherited modality into its kind: the session's modality, the rolling tile hint, the modality picker in Free Training, the overview, and routines (which use a Cardio focus modality, or the picker per exercise). | `lib/core/constants/modality_config.dart:55-116, 142-144`; `session_core_entry.dart:23-33`; `workout_session_screen.dart:1366-1391`; `session_overview_screen.dart:79-92`; `lib/features/routine/routine_setup_screen.dart:722-736, 803-812` | D-319 |
| F18 | The picked modality is never stored.<br>• `SegmentEffort` has no modality field, and routine setup writes `TemplateEffort.modality: null`. So `timed` is the stored record of Cardio tracking.<br>• No UI passes `chosenMetric` to `addExerciseToSession`; only the pass-through at `workout_state.dart:139` does. The "Track by …" chooser survives only in the Summary's Save-as-Routine sheet for a no-modality session: Time and Distance → `timed`, Hold Time → `drill`.<br>• Seeded `timed` efforts are all runs.<br>• The `interval` kind is defined, but nothing creates it. | `models.dart:415-472`; `lib/state/routine/routine_state.dart:584-592`; `session_summary_screen.dart:497-512`; `modality_config.dart:243-258`; `lib/mock/seed_data.dart:5550, 5691`; `lib/mock/demo_routines_seed.dart:420`; `lib/core/constants/block_types.dart:19` | D-319, I-3 |
| F19 | Watch-started entries. The wrist uses the kind the routine declared for the slot. Otherwise it resolves the kind from the exercise's capabilities, in the order hold, rounds, reps, sets, load, time, distance: time or distance gives `timed`, and hold gives `drill`. The importer maps timed → `timed`, hold → `drill` and round → `round`. | `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift:272-292`; `lib/watch/logging/watch_logging_state.dart:291`; `watch_session_importer.dart:87-92` | D-319 (watch-started sessions) |
| F16 | Harnesses to reuse. Hive in tests: `test/watch_capture_repository_parity_test.dart:26-120` (path_provider stub, open, restart). Historical Summary: `test/calendar_summary_screen_bugs_test.dart:31-90` (`_settingsWithoutFeelingSheet`, `_pumpHistoricalSummary`, `workoutState.loadHistoricalSession`). Stats seeding: `test/screen_widget_test.dart:2589-2690`. Dialog parse tests: `test/crown_control_tap_to_edit_test.dart:268+`. | as listed | all phases |

## 3. Executor records (append below; one block per phase)

### Phase 1: Stored distance source (state and data). Copilot, 2026-09-27

- Baseline at phase start (own runs, `develop` @ 2690d1b + uncommitted plan docs):
  `flutter test` → `01:11 +3000 ~1: All tests passed!`, exit 0 ·
  `flutter analyze` → `242 issues found.`, 0 errors.
- Branch: `feature/stats-pr3a-phone-distance`, cut from `develop`.

**Red run.** The plan's own red recipe: item 1 alone, with item 2's four
`valueSource:` copy lines removed by `sed` (files copied to `/tmp/p1_backup`
first; no `git stash`). `flutter test test/distance_source_test.dart` → exit 1,
`00:00 +15 -3: Some tests failed.`

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `distance_source_test.dart` › `S-804 (c) source guard every observation copy forwards valueSource` | S-804 (c) | `Expected: empty Actual: [ D-311: these EffortObservation copies drop valueSource, so a distance loses its source whenever the row is copied: lib/state/workout/session_core_entry.dart:245, lib/state/workout/session_core_entry.dart:460, lib/data/repositories/mock_workout_repository.dart:2029, lib/data/repositories/hive_workout_repository.dart:2841 ]` — exactly the four predicted sites | pass |
| `distance_source_test.dart` › `Mock S-804 copies keep the source` | S-804 (a) | `Expected: 'estimated' Actual: <null>` | pass |
| `distance_source_test.dart` › `Hive S-804 copies keep the source` | S-804 (b) | `Expected: 'estimated' Actual: <null>` | pass |

The other Phase 1 tests (S-801, S-802, S-803, S-805–S-808) are green with item 1
present, so their red state is the compile failure of an unfixed tree — no
`valueSource` field, no `DistancePairing`, no `setEntryDistance`. Item 1's own
red is the guard above; items 2–4's red is the same guard plus S-804.

- Suites at phase end (own runs):
  - `flutter test test/distance_source_test.dart test/db_seed_test.dart test/docs_indexing_contract_test.dart` → exit 0, `+34: All tests passed!`
  - `flutter test` → exit 0, `01:38 +3020 ~1: All tests passed!` (3000 baseline + 20 new; skip count still 1)
  - `flutter analyze` → `242 issues found.`, `grep -c "^ *error •"` = 0 — unchanged from baseline.
- Analyzer per-file counts for predicted files: `session_core.dart` carries one
  pre-existing info (`curly_braces_in_flow_control_structures`, :161, untouched
  code — this phase's diff to that file is one import line). Every other
  predicted file is at or below its baseline count; models.dart,
  session_core_entry.dart, both repositories, sqlite_schema.sql and
  db_seed_test.dart add none.
- Diff vs Predicted Files, `git status --porcelain`: every planned file, plus
  the evidence file itself. `lib/core/utils/distance_source.dart` and
  `test/distance_source_test.dart` are new and were both predicted.
  **One file outside the list, one line: `lib/state/workout/session_core.dart`**
  — `session_core_entry.dart` is a `part of` it, so the new
  `distance_source.dart` import had to go in the library file. Nothing else in
  that file changed. The two plan docs already modified before this phase began
  (`.github/agents/plans/2026-09-24-01-stats-pr1-effort-rating-plan.md` and
  `…-02-stats-pr2-watch-capture-plan.md`) are still in the working tree and this
  phase did not touch them. Nothing under `watch/` changed.
- Assumption Log detail:
  - The D-312 pairing takes an `effortId`-free row list, so `_compare` reads the
    entry number from the id suffix alone (`-<n>-distance$`) rather than from
    `obs-<effortId>-`. Rows in one effort's list share the prefix, so the two
    forms agree; `entryNumberInId(id, effortId)` keeps the effort-scoped check
    for callers that have the effort id.
  - `setEntryDistance` / `confirmEntryDistance` report through the existing
    `_setError` channel and return void, rather than returning a status: every
    other `SessionCore` write behaves this way, and D-307's rules are about what
    gets stored, not about what the caller learns.
  - `confirmEntryDistance` is a no-op when the entry has no paired row. D-307
    defines a confirm as recording the value the dialog pre-filled; with no
    row, `0.00` was pre-filled and a confirm would be a value the user did not
    type.

### Phase 2: The Summary's DISTANCE section. Copilot, 2026-09-27

- Baseline at phase start: the Phase 1 end state (suite `+3020 ~1`, analyzer
  242 issues / 0 errors).

**Red run.** The production files copied to `/tmp/p2_backup` first, then each
item was reverted in place with the file restored afterwards; no `git stash`.

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `session_summary_distance_test.dart` › the row/section tests, with `..._buildDistanceSection()` removed from the render site | S-811 | `Expected: exactly one matching candidate Actual: _TextWidgetFinder:<Found 0 widgets with text "DISTANCE": []>` | pass |
| same run | S-812, S-813–S-817, S-818 (a, c, d) | `Expected: [ … ] Actual: [] Which: at location [0] is [] which shorter than expected` | pass |
| `crown_control_tap_to_edit_test.dart` › `MetricStepCalc parseAndClamp distance clamps 1500 to 999.99`, with the `distance` case removed from `parseAndClamp` | D-314 | `Expected: <999.99> Actual: <1500.0>` | pass |
| `crown_control_tap_to_edit_test.dart` › `parseAndClamp distance clamps -3 to 0.0` | D-314 | `Expected: <0.0> Actual: <-3.0>` | pass |
| `crown_control_tap_to_edit_test.dart` › `parseAndClamp distance rounds 4.876 to 4.88` | D-314 | `Expected: <4.88> Actual: <4.876>` | pass |
| `crown_control_tap_to_edit_test.dart` › `the distance dialog is titled Edit Distance …`, with the `distance` case removed from `_titleForMetric` | D-316 | `Expected: exactly one matching candidate Actual: _TextWidgetFinder:<Found 0 widgets with text "Edit Distance": []>` (the fall-through rendered `Edit distance`) | pass |

The guards that must pass both before and after: `S-818b` (a resistance session
shows no `DISTANCE` header) and `S-822`'s `Plank` absence did pass in the red
run above; `S-814` (confirming a value that is not an estimate) and
`test/session_summary_effort_row_test.dart` are unaffected by any of it.
S-820/S-823's own red is the same missing section, since their first assertion
is the section's row.

- Suites at phase end (own runs):
  - `flutter test test/session_summary_distance_test.dart test/crown_control_tap_to_edit_test.dart` → exit 0, `+16: All tests passed!` for the new file alone; `+65` with `session_summary_effort_row_test.dart` added.
  - `flutter test` → exit 0, `01:25 +3041 ~1: All tests passed!` (Phase 1's 3020 + 21 new; skip count still 1)
  - `flutter analyze` → `242 issues found.`, `grep -c "^ *error •"` = 0 — unchanged from baseline.
- Analyzer per-file counts for predicted files: `session_summary_screen.dart`
  holds 10 infos — the baseline's 8 `withOpacity` and 2
  `use_build_context_synchronously`, at new line numbers but the same count, and
  none of them on the added code (`:504`, `:646` are pre-existing call sites).
  `metric_crown_widget.dart` and `session_distance_card.dart` add none.
- Diff vs Predicted Files: all Phase 2 files are planned ones. Two files outside
  the list remain the two plan docs already modified before the phase began.
- Assumption Log detail:
  - The estimates must be marked even where the value is not a number of
    display units, so the marker is a suffix of the unit label the card renders
    (`KM EST.`) rather than a separate flag. `DistanceRowModel` therefore
    carries no `isEstimated`; the screen decides the label.
  - `_applyDistance` compares the dialog's answer with the value that was
    pre-filled, rounded to the same two decimals, to choose between a confirm
    and a set. Comparing unrounded units would call a `4.87` entry from a
    `4.8736` store a change and overwrite the stored metres with `4870.0`.
  - The section is built from `getExercisesWithEntries()` rather than from a
    second read of the session, so the Summary's own effort order is the one
    source of row order and no second ordering can disagree with it.

### Phase 3: Stats marks estimates; pace counts only entries with a distance. Copilot, 2026-09-27

- Baseline at phase start: the Phase 2 end state (suite `+3041 ~1`, analyzer
  242 issues / 0 errors).

**Red run.** Each item reverted in place from a copy in `/tmp/p3_backup` and
restored afterwards; no `git stash`.

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|
| `stats_distance_estimate_test.dart` › `(a) an entry with no distance contributes no time and no pace`, with the pace reverted to `durationSecs / (distanceM / 1000)` | S-831 | `Expected: a numeric value within <0.01> of <300.0> Actual: <600.0>` | pass |
| same run › `(b) an unfinished entry counts its distance but no pace time` | S-831 | `Expected: a numeric value within <0.01> of <300.0> Actual: <200.0>` | pass |
| same run › `S-837 a Summary correction reaches the Stats card` | S-837 | `Expected: exactly one matching candidate Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing Pace: 231 s/km: []>` (the old figure divides 1800 s by 5.2 km, 346 s/km) | pass |
| same run, with `estimateSuffix` forced empty | S-833 | `Expected: exactly one matching candidate Actual: _TextContainingWidgetFinder:<Found 0 widgets with text containing Distance: 4.87 km est.:` (and `Distance: 3.03 mi est.`) | pass |
| same run, with the trend's `distanceEstimated` forced false | S-832 | `Expected: [true, false, true] Actual: [false, false, false]` | pass |
| same run › `S-835 … an estimated day is hollow, and the legend gains est.` | S-835 | `Expected: exactly one matching candidate Actual: _TextWidgetFinder:<Found 0 widgets with text "est.": []>` | pass |
| same run, with `0.621371` / `1.609344` inlined into `_paceForDisplay` / `_distanceForDisplay` | S-836 | `Expected: false Actual: <true>` (the file contains two of the literals) | pass |

The guards that pass both before and after: `S-834` (a measured day carries no
marker) and `test/stats_progress_test.dart`'s `timed effort without distance →
paceSecPerKm is null`, plus `test/screen_widget_test.dart`'s
`cardio single-day pace respects miles preference` (no source — 360 s/km, 579
s/mi, unchanged by D-309). They guard against over-marking and against the pace
running short where there is no entry to exclude.

- Suites at phase end (own runs):
  - `flutter test test/stats_distance_estimate_test.dart test/stats_progress_test.dart test/screen_widget_test.dart` → exit 0, `+330: All tests passed!`
  - `flutter test` → exit 0, `+3051 ~1: All tests passed!` (Phase 2's 3041 + 10 new; skip count still 1)
  - `flutter analyze` → `242 issues found.`, `grep -c "^ *error •"` = 0 — the baseline count, with `stats_screen.dart` still at its single pre-existing `_ChartSeries` warning.
- Analyzer per-file counts for predicted files: `stats_screen.dart` 1
  (baseline), `stats_progress.dart`, `stats_progress_service.dart` and
  `stats_distance_estimate_test.dart` 0.
- Diff vs Predicted Files: all Phase 3 files are planned ones.
  **One file outside the whole-feature list: `.github/agents/docs/state_management/workout_state.md`**
  — the standing doc queue marks it "update if a new state class or method was
  added", and Phase 1 added two `WorkoutState` methods; the row for
  `updateEntryValue` also gained `valueSource` in its preserved-field list.
  The two plan docs already modified before Phase 1 began are still in the
  working tree and are untouched by this PR.
- Assumption Log detail:
  - `_CardioDay` carries the pace's two sums (`paceDurationSecs`,
    `paceDistanceM`) alongside the day's totals, rather than the day carrying a
    finished pace. A day is built from several efforts, so the pace can only be
    a ratio of the merged sums; keeping the inputs makes that merge exact and
    leaves nothing to recompute from a rounded pace.
  - The estimate flag merges with OR across everything that feeds the day, so
    one estimated distance marks the whole day — the alternative, marking only
    the affected series, is not expressible in a card whose pace and distance
    share a point.
  - An unfinished entry still contributes its distance to the day's total,
    because the total is "distance recorded that day" and the marker must not
    change it. It contributes no pace time, because its `actualDurationSecs` is
    a target rather than a measurement.

### Final verification (all three phases). Copilot, 2026-09-27

- `flutter test` (whole suite, current source) → exit 0, `01:32 +3051 ~1: All tests passed!`
  (baseline 3000 tests, the same 1 pre-existing skip at `test/profile_navigation_test.dart:39`).
- `flutter analyze` → `242 issues found.`, `error •` count 0 — the recorded baseline.
  `lib/features/session/session_summary_screen.dart` stays at its 10-infos baseline
  (8 `withOpacity`, 2 `use_build_context_synchronously`); `session_core.dart:161`
  (`curly_braces_in_flow_control_structures`) and `stats_screen.dart` (`unused_element`,
  `_ChartSeries`) are unchanged pre-existing issues.
- Footprint: `git status --porcelain` → 23 modified + 6 new; `git diff --stat` → 871
  insertions, 75 deletions. Two files outside the plan's Predicted Files, both listed in
  the phase blocks above: `lib/state/workout/session_core.dart` (one import line;
  `session_core_entry.dart` is a `part of` it) and
  `.github/agents/docs/state_management/workout_state.md` (standing doc queue). Nothing
  under `watch/` changed, so the contract fixture is untouched.
- Pre-existing working-tree changes this PR did not make: the two earlier plan documents
  (`2026-09-24-01-…`, `2026-09-25-02-…`) and the untracked series index.

### Review round: F-1–F-4. Copilot, 2026-09-27

Review: `…plan.review.md` (CHANGES REQUESTED; docs plus one test, no production code).

- **F-1 (doc falsification).** Deleted the exclusivity claims (`distance_source.md`
  "nothing else touches a distance", "the only place that says which distance row belongs
  to which entry", "owns the only write", "the writers and the Stats reader agree";
  `workout_state.md` "The one write that changes a distance") and the no-row confirm
  clause, which S-806 does not cover. Added the structural line naming the raw-order
  writers: `updateEntryValue` (Edit Session, live screen, routine pre-fill) and
  `SessionSummaryBuilder`, pointing at O-3.
  - One location beyond the finding's list, same defect: `session_summary.md`'s opening
    line read "the one phone surface that enters or corrects a distance". The live screen
    does write a distance row, through `updateEntryValue('distance', …)` at
    `workout_session_screen.dart:999`, so the line now says a person types here and names
    the other writers instead.
- **F-2 (prohibited doc content).** Removed the stroke/fill rendering sentence
  (`stats_screen.md`), the corrected pace formula (now a one-line contract with the S-831
  pointer), the `DistanceRowModel` prop table and field list, the `metricType` addition,
  the keyboard bullet, and the Summary layout-table row. Added a
  `test/crown_control_tap_to_edit_test.dart` pointer to the popup section.
- **F-4 (incomplete indexes).** `SessionDistanceCard` added to the `widget_catalog.md`
  lookup; `DISTANCE` added to the `design_system.md` header list; distance entry added to
  the `SessionSummaryScreen` row in `navigation_and_screens.md`.
- **F-3 (test gap).** New case `S-835 … a day with no distance does not shift the estimated
  dot`: day one is a duration with no distance, so it holds a trend point and no spot, and
  the estimated day is each bar's *first* dot at `x == 1`.
  - Red: mutated the two `getDotPainter` call sites in `stats_screen.dart` to look a day up
    by its position in the series, then `flutter test test/stats_distance_estimate_test.dart`
    → exit 1, `00:00 +8 -1: Some tests failed!`; the failing case is the new one, with
    `Expected: Color:<… red: 0.0627, green: 0.1569, blue: 0.2588 …>` (surface) vs
    `Actual: Color:<… red: 0.1059, green: 0.6039, blue: 0.6667 …>` (the series colour) —
    the estimated dot drawn filled. The group's other case stayed green, so the new case is
    the one that discriminates.
  - Green: restored `stats_screen.dart` from `/tmp/p4_backup` (grep for the mutation: 0) →
    exit 0, `00:00 +11: All tests passed!` (the file had 10 cases).
- Doc guards after the edits: `flutter test test/docs_indexing_contract_test.dart
  test/navigation_contract_enforcement_test.dart test/pr2_launch_quality_hotfix_test.dart`
  → exit 0, `00:04 +22: All tests passed!`.
- Whole suite after the fixes: `flutter test` → exit 0, `01:21 +3052 ~1: All tests passed!`
  (3051 at handoff + the new F-3 case). `flutter analyze` → `242 issues found.`, 0 errors.
- Production code in this round: none. The only `lib/` change is a doc comment
  (`session_distance_card.dart`: `_absentValue` → `absentValue`, N-1).
- **N-3 recorded.** A training day's distance now counts paired rows only, so an orphan row
  left by an Edit Session delete+delete no longer inflates the total. D-309 asked for the
  totals to stay unchanged; this is a deliberate consequence of reading through
  `DistancePairing`, and it is covered by the `S-831`/`S-832` fixtures.

### Phase N: <name>. <agent>, <date>

- Baseline at phase start: `flutter test` <tail line> · `flutter analyze` <tail line>
- Red run: each new test on unfixed code, with its failure line.

| Test (file › name) | S-id | Red on unfixed code (quoted failure) | Green after change |
|---|---|---|---|

- Suites at phase end: <tail lines, exit codes>
- Analyzer per-file counts for predicted files: <table>
- Diff vs Predicted Files: `git diff --name-only <phase base>`: <list; any extra file is a finding>
- Assumption Log detail (entries longer than 3 lines):
