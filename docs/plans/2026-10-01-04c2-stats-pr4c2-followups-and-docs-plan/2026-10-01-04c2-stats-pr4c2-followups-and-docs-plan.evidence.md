# Evidence — Stats PR 4c2

Owner of this file: the **executors** (append-only). The reviewer writes to
`2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.review.md` instead.
Never write evidence into the plan itself. Baselines below were measured by the planner on
2026-10-01, before any edit in the 4c / 4c2 series.

## 1. Planner baselines (verbatim)

```
$ .github/copilot/scripts/macos/gateway.sh lint
199 issues found. (ran in 3.1s)

$ .github/copilot/scripts/macos/gateway.sh test
01:21 +3256 ~1: All tests passed!
```

Four warnings in the baseline, none of them in this PR's files:

| Location | Message | Dies where |
|---|---|---|
| `lib/features/stats/stats_screen.dart:1336:7` | `_ChartSeries` is unused | **4c Phase 1** |
| `test/screen_widget_test.dart:4449:13` | `isometricWindow` is unused | **4c Phase 1** (inside the retired 4001–4913 range) |
| `test/screen_widget_test.dart:4450:13` | `sportsWindow` is unused | **4c Phase 1** (same range) |
| `lib/features/routine/routine_setup_screen.dart:1046:12` | unused local | pre-existing, **out of bounds** |

Expected analyzer count after 4c: **196**. 4c2 deletes no warning and must create none, so 4c2's
expected count is also **196**; the bar for both PRs is ≤199 with no errors.

## 2. File measurements (planner, 2026-10-01)

| File | Lines / bytes | Role in 4c2 |
|---|---|---|
| `lib/core/services/stats_progress_service.dart` | 2,342 lines | −487 / +18 |
| `lib/core/models/stats_progress.dart` | 356 lines | −135 / +6 |
| `lib/features/stats/widgets/scrollable_trend_chart.dart` | 15,306 bytes (~430 lines) | moved byte-identically to `lib/widgets/chart/` |
| `test/stats_progress_test.dart` | 3,940 lines | retire ~950 lines of tests; repoint the nutrition-trend group |
| `test/fuel_row_screen_test.dart` | — | +2 cases, +1 label assertion |
| `docs/stats_screen.md` | 679 lines / 37,999 bytes | rewritten by 4c; 4c2 only re-checks |
| `docs/nutrition.md` | does not exist | created in 4c2 Phase 3 |

## 3. The service's retirement map (planner, verified by reading)

Delete:

- Constants `kTopCardioCount` (141 + doc 139–140), `kTopIsometricCount` (145 + doc 143–144),
  `kTopSportsCount` (149 + doc 147–148).
- Accumulators 228–236; the `'timed'` / `'drill'` / `'round'` switch cases 258–267 (keep `'set'`);
  three keys from the `nameCache` set literal 277–279.
- The three projections + three `_selectTopNWithRecencyFloor` calls (308–346); the three
  `_buildFull*ForExercises` calls (358–369); the three build loops (512–598); the `nutritionTrend`
  computation (~584–588) and its return argument.
- `_processTimedEffort` 1337–1409, `_processDrillEffort` 1410–1439, `_processRoundEffort` 1440–1483,
  `_buildFullCardioForExercises` 2072–2105, `_buildFullDrillForExercises` 2106–2139,
  `_buildFullRoundForExercises` 2140–2181, `_CardioDay` 2286–2315, `_DrillDay` 2317–2322,
  `_RoundDay` 2325–2328.

All nine callers were verified closed — every reference sits inside `computeProgressData` or another
member on this list.

Keep (readers exist outside the deleted set):

| Member | Reader |
|---|---|
| `topLifts` / `LiftProgress` / `_processSetEffort` | the PR scan (4c D-605); `test/in_session_pr_toast_test.dart`, `test/pr_toast_test.dart`, the e1RM group of `test/stats_progress_test.dart` |
| `kTopLiftCount`, `kTopExerciseRecencyDays` | the PR scan set's cap and floor |
| `computeNutritionTrend` | `test/stats_progress_test.dart`, `lib/features/nutrition/nutrition_trend_screen.dart` |
| `computeNutritionAdherence` | `lib/features/nutrition/nutrition_trend_screen.dart:47` |
| `computeFuelSummary`, `FuelSummary`, `FuelDay` | `lib/features/stats/widgets/fuel_section.dart` |
| `computeInstrumentSections`, `computeTotals`, `computeExerciseMetrics` | the Instruments list and the `ALL TIME` card |
| | `resolveWindow`, `_sessionInWindow`, `previousRangeFor` | the live window resolution |

## 3b. `test/stats_progress_test.dart` — group map (planner, read group by group)

The group list was read from the file, not assumed. The line ranges look like contiguous retirement
ranges and are **not**: `Trend aggregation` and `Windowed selection` sit inside them and read `topLifts`
/ `window`, which survive.

| Group | Lines | Removed-output refs | Verdict |
|---|---|---|---|
| `e1RM calculation (Epley formula)` | 358–429 | — | keep |
| `Top-N auto-detection` | 430–588 | 580–582 (the test at 530) | keep 431, 501; retire 530–588 |
| `Trend aggregation` | 589–674 | — | **keep whole** |
| `Effort-type keying` | 675–800 | 701, 737, 794 | keep the lift assertion in 676–706; retire 707–800 |
| `Empty states` | 801–870 | 826, 854, 864 | keep the `topLifts`/`recentPRs` assertions in 802–829, 858–870; retire 830–857 |
| `PR detection` | 871–928 | — | keep |
| `PR list dedupe` | 929–1129 | — | keep |
| `Session-summary vs stats PR invariant` | 1130–1151 | — | keep |
| `Single-rep set` | 1152–1181 | — | keep |
| `Cardio trend` | 1182–1300 | 1206, 1207, 1234 | retire whole |
| `Nutrition trend aggregation` | 1301–1612 | 1319…1601 (`nutritionTrend`) | **repoint** to `computeNutritionTrend(days: null)` |
| `computeNutritionTrend (full history)` | 1613–1755 | — | keep |
| `Windowed selection (current-state window)` | 1756–2317 | 2191, 2195, 2245 | **keep whole**; drop the cardio assertions in 2098–2196 (S-007) and 2201–2245 (S-008) and the cardio words in their titles |
| `Bodyweight inclusion (Item 2)` | 2318–2791 | — | keep |
| `Recency floor on Strength/Cardio selection (Item 3)` | 2792–3103 | 3093, 3098 | keep 2793, 2860, 2933, 2987; retire S-205 (3050–3103); rename the group to drop "Cardio" |
| `computeNutritionAdherence` | 3104–3267 | — | keep |
| `Isometric drill aggregation (Phase D)` | 3268–3427 | 3330–3422 | retire whole |
| `Sports round aggregation (Phase D)` | 3428–3599 | 3487–3594 | retire whole |
| `Exercise selection: isometric and sports (Phase D)` | 3600–3862 | 3602–3849 | retire whole |
| `Banned-framings audit` | 3863–end | — | keep |

Retired total ≈ 950 lines. The lesson for the reviewer: a line range is not a group.

## 4. The model's retirement map (planner, grep-verified unused)

Delete: `CardioTrendPoint` 33–57, `CardioProgress` 92–100, `DrillProgress` 102–111,
`RoundProgress` 113–122; `StatsProgressData` fields `topCardio` 196–197, `topIsometric` 199–200,
`topSports` 202–203, `nutritionTrend` 208–212 (+ their constructor args); `StatsProgressData.empty`
232–239; `StatsWindow.hasData` 303–304; `StatsWindow.empty` 306–316.

## 5. Importers of the moved chart (planner, verbatim lines)

| File:line | Current | After |
|---|---|---|
| `lib/features/stats/exercise_progress_screen.dart:17` | `import 'widgets/scrollable_trend_chart.dart';` | `import '../../widgets/chart/scrollable_trend_chart.dart';` |
| `lib/features/nutrition/widgets/nutrition_trend_card.dart:10` | `import '../../stats/widgets/scrollable_trend_chart.dart';` | `import '../../../widgets/chart/scrollable_trend_chart.dart';` |
| `lib/features/profile/widgets/measurement_history_chart_sheet.dart:9` | `import '../../stats/widgets/scrollable_trend_chart.dart';` | `import '../../../widgets/chart/scrollable_trend_chart.dart';` |
| `test/screen_widget_test.dart:37` | `import 'package:omnitrain/features/stats/widgets/scrollable_trend_chart.dart';` | `import 'package:omnitrain/widgets/chart/scrollable_trend_chart.dart';` |
| `test/nutrition_trend_screen_test.dart:24` | same | same |
| `test/scrollable_trend_chart_test.dart:8` | same | same |
| `test/records_and_trends_screen_test.dart:24` | same | same |

`lib/features/stats/stats_screen.dart:27` also imports it — that import dies with 4c.

## 6. SQL contract (planner, checked)

`scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` contain no removed type name: "cardio"
appears only as modality / effort-kind prose and as `totalCardioDurationMs` (which stays). The removed
types are computed, never persisted → **no SQL change predicted**. `test/db_seed_test.dart` is the
proof and runs in Phase 1's Done Criteria.

## 7. Executor evidence

### Phase 1 (@dba)

- `gateway.sh lint` output:
  ```
  196 issues found. (ran in 2.6s)
  ```
  No `error •` line; the count equals D-665's expectation (baseline 199 minus the three warnings 4c
  removed; 4c2 creates none). Bar ≤199 with no errors — met.

- `gateway.sh test` (full suite) final line:
  ```
  +3219 ~1: All tests passed!
  ```
  Post-4c baseline was `+3233 ~1`; the delta of 14 is exactly the retired test count (D-655: Top-N
  cardio, Effort-type timed + drill, Empty-states timed-only, 2 Cardio-trend tests, S-205, and the
  8 Phase D tests), and the new `S-1263` group adds 9 of its own.

- Targeted suites (`test/stats_progress_test.dart test/db_seed_test.dart test/services_test.dart
  test/in_session_pr_toast_test.dart test/pr_toast_test.dart`):
  ```
  +160: All tests passed!
  ```
  `test/stats_progress_test.dart` alone: `+55: All tests passed!` (16 kept groups);
  `test/stats_legacy_removal_test.dart` alone: `+9: All tests passed!`. `test/db_seed_test.dart`
  green → §6's "no SQL change" prediction holds.

- `gateway.sh format` on the five touched files: `Formatted 5 files (2 changed)`, re-run
  `Formatted 5 files (0 changed)` (idempotent).

- `gateway.sh git-diff --stat`:
  ```
  lib/core/models/stats_progress.dart            |  139 +--
  lib/core/services/session_summary_service.dart |    4 +-
  lib/core/services/stats_progress_service.dart  |  487 +-------
  test/stats_legacy_removal_test.dart            |   57 +
  test/stats_progress_test.dart                  | 1418 +++---------------------
  5 files changed, 261 insertions(+), 1844 deletions(-)
  ```
  Exactly the plan's Predicted Files for Phase 1; no file created, moved or deleted.

- **M-3 red→green** (re-add `kTopCardioCount`, expect the guard to fail):

  | Run | Command | Result |
  |---|---|---|
  | red (mutation present) | `gateway.sh test test/stats_legacy_removal_test.dart` | `+8 -1: Some tests failed.` — `Expected: false / Actual: <true>` / ``D-666: `kTopCardioCount` was deleted by 4c2 and must not come back to lib/core/services/stats_progress_service.dart`` |
  | green (reverted) | `gateway.sh test test/stats_legacy_removal_test.dart` | `+9: All tests passed!` |

  The mutation was the single line `static const int kTopCardioCount = 5;` after `kRecentPRCount`;
  it was reverted with the exact inverse edit and `git-diff --stat` returned to the five-file list
  above. So the guard fails without the retirement and passes with it — it is not a test that passes
  both ways.

- Before/after value capture for S-1251 (pre-change checkout vs post-change): **not executable in this
  run.** The gateway exposes no `git checkout` / `git stash` / `git restore`, and no agent may create
  or delete files, so pre-change output cannot be produced. Substitute evidence, recorded as an
  Assumption Log entry: every kept expectation in `test/stats_progress_test.dart` is byte-identical to
  HEAD (`git-diff` shows only removals, the `data.nutritionTrend` → local `trend` repoint, and
  reworded titles), so the HEAD expectations are the before values and their passing in this run
  (`+55`) is the after values. No expectation value was changed to accommodate the retirement.

### Phase 2 (@developer)

- The move (step 12) — `wc -l -c` on both paths, then `diff`:
  ```
  369   15306 lib/features/stats/widgets/scrollable_trend_chart.dart
  369   15300 lib/widgets/chart/scrollable_trend_chart.dart
  $ diff lib/features/stats/widgets/scrollable_trend_chart.dart lib/widgets/chart/scrollable_trend_chart.dart
  4,5c4,5
  < import '../../../core/constants/omni_theme.dart';
  < import '../../../core/utils/chart_axis_helper.dart';
  ---
  > import '../../core/constants/omni_theme.dart';
  > import '../../core/utils/chart_axis_helper.dart';
  ```
  Same line count; the 6-byte delta is exactly the two `../` removed from the two relative imports
  (2 × 3 chars). No other byte differs, so the transcription is byte-identical as the plan requires.
  The line-1 `// filepath:` comment still names the old path — it is content, so it was left alone
  (see Open questions in the plan's sibling review, if any).

- Importers (step 13): **eight**, not the plan's seven. `grep -rln
  "widgets/chart/scrollable_trend_chart" lib test` → `lib/features/nutrition/widgets/nutrition_trend_card.dart`,
  `lib/features/profile/widgets/measurement_history_chart_sheet.dart`,
  `lib/features/stats/exercise_progress_screen.dart`, `test/nutrition_trend_screen_test.dart`,
  `test/records_and_trends_screen_test.dart`, `test/screen_widget_test.dart`,
  `test/scrollable_trend_chart_test.dart`, `test/stats_legacy_removal_test.dart`. The eighth —
  `test/stats_legacy_removal_test.dart:29` — is not in D-658's table and reads `ScrollableTrendChart`
  at line 421; it was repointed too (Assumption Log 5). No reference to the old path remains except
  the two `// filepath:` comments (line 1 of each file). `lib/features/stats/stats_screen.dart` has no
  such import, so 4c is complete.

- `gateway.sh lint` (after the repointing, and again after step 17's format):
  ```
  196 issues found. (ran in 2.3s)
  ```
  `gateway.sh lint | grep -c "error •"` → `0`. Count equals the bar exactly.

- Named suites (step 17):
  ```
  $ gateway.sh test test/fuel_row_screen_test.dart test/scrollable_trend_chart_test.dart test/records_and_trends_screen_test.dart test/nutrition_trend_screen_test.dart test/screen_widget_test.dart
  +307: All tests passed!
  ```
  `test/fuel_row_screen_test.dart` alone: `+42: All tests passed!` (21 cases × the Mock and Hive
  harnesses) — 6 more than the 18 it had before this phase.

- `gateway.sh test` (full suite) final line:
  ```
  +3225 ~1: All tests passed!
  ```
  Phase 1 ended at `+3219 ~1`; the delta of 6 is exactly the three new cases × two harnesses.

- `gateway.sh format` on the ten touched files, by explicit path, **excluding** the moved chart file:
  ```
  Formatted test/fuel_row_screen_test.dart
  Formatted 10 files (1 changed) in 0.12 seconds.
  ```
  Only the new test code was reflowed: `git-diff` on that file shows exactly two hunks (the header
  comment and the appended group) and no other line of the file moved.

- `gateway.sh git-diff --stat` (tracked files; the new chart file is untracked):
  ```
  lib/core/models/stats_progress.dart                |  139 +-
  lib/core/services/session_summary_service.dart     |    4 +-
  lib/core/services/stats_progress_service.dart      |  487 +------
  .../nutrition/widgets/nutrition_trend_card.dart    |    2 +-
  .../widgets/measurement_history_chart_sheet.dart   |    2 +-
  lib/features/stats/exercise_progress_screen.dart   |    2 +-
  lib/features/stats/widgets/fuel_section.dart       |  154 +--
  test/fuel_row_screen_test.dart                     |  102 +-
  test/nutrition_trend_screen_test.dart              |    2 +-
  test/records_and_trends_screen_test.dart           |    2 +-
  test/screen_widget_test.dart                       |    2 +-
  test/scrollable_trend_chart_test.dart              |    2 +-
  test/stats_legacy_removal_test.dart                |   59 +-
  test/stats_progress_test.dart                      | 1418 +++-----------------
  14 files changed, 446 insertions(+), 1929 deletions(-)
  ```
  `gateway.sh git-status` adds `?? lib/widgets/chart/scrollable_trend_chart.dart` and
  `?? docs/plans/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/`, and lists nothing else. That is
  Phase 1's five files + Phase 2's nine + the new chart file + this plan's folder — the Predicted Files,
  and nothing else. `lib/features/stats/widgets/scrollable_trend_chart.dart` is untouched and still
  present (the Governor deletes it after this phase).

- **M-4 red→green** (remove the `Semantics` wrapper; the label assertion must fail). `git-diff --stat`
  before the mutation: `fuel_section.dart | 154 ++++----` / `79 insertions(+), 75 deletions(-)`.

  | Run | Command | Result |
  |---|---|---|
  | red (mutation present) | `gateway.sh test test/fuel_row_screen_test.dart --plain-name "exposes its label and still opens the trend screen"` | `+0 -2: Some tests failed.` on both harnesses — `Expected: exactly one matching candidate / Actual: _WidgetPredicateWidgetFinder:<Found 0 widgets with widget matching predicate: []>` at `test/fuel_row_screen_test.dart:885` |
  | green (reverted) | `gateway.sh test test/fuel_row_screen_test.dart` | `+42: All tests passed!` |

  The mutation removed the wrapper's opener and its closer; the revert re-inserted both, and
  `git-diff --stat -- lib/features/stats/widgets/fuel_section.dart` returned to `154 ++++----`
  (79/75) exactly.

- **M-5 red→green** (the Fuel row's inner `Row` pinned to 900 dp; the 320 dp case must fail).

  | Run | Command | Result |
  |---|---|---|
  | attempt 1, `SizedBox(width: 900, child: Row(…))` | `gateway.sh test test/fuel_row_screen_test.dart` | `+42: All tests passed!` — **no red**: the Column clamps the `SizedBox` to its `maxWidth`, so nothing overflows. The literal mutation is a no-op (Assumption Log 7) |
  | red (rigid 900 dp child) | `gateway.sh test test/fuel_row_screen_test.dart --plain-name "renders at 320x568 dp without overflowing"` | `+0 -2: Some tests failed.` on both harnesses — `Expected: null / Actual: FlutterError:<A RenderFlex overflowed by 678 pixels on the right.>` at `test/fuel_row_screen_test.dart:849` |
  | green (reverted) | `gateway.sh test test/fuel_row_screen_test.dart` | `+42: All tests passed!` |

  The red mutation was `const SizedBox(width: 900),` as the inner `Row`'s first child (same intent —
  the row's content pinned to a fixed 900 dp — in a form the constraints cannot clamp). It was removed
  with the exact inverse edit and `git-diff --stat -- lib/features/stats/widgets/fuel_section.dart`
  returned to `154 ++++----` (79/75). The 320 dp and 2.0-scale cases were never weakened: both passed
  unmutated, so no fix inside `fuel_section.dart` was needed (D-660).

- Governor deletion of `lib/features/stats/widgets/scrollable_trend_chart.dart`: _(pending)_

### Phase 3 (@developer)

- **The four Done-Criteria commands were first reported unrun.** Every invocation was *wrapped* — a
  `cd … &&` prefix, a `sh`/`bash` wrapper, or an absolute path — and every wrapper was refused:

  | Command form | Observed |
  |---|---|
  | `bash .github/copilot/scripts/macos/gateway.sh lint` | `Permission denied and could not request permission from user` |
  | `./.github/copilot/scripts/macos/gateway.sh lint` | same |
  | `<abs path>/.github/copilot/scripts/macos/gateway.sh list` | same |
  | `flutter test test/docs_indexing_contract_test.dart` | same |

  The cause is the invocation form, not the environment: the literal relative form
  `.github/copilot/scripts/macos/gateway.sh <check>` runs, and both gates were then observed green
  (governor, re-confirmed by the reviewer):

  | Command | Observed |
  |---|---|
  | `gateway.sh test test/docs_indexing_contract_test.dart test/stats_legacy_removal_test.dart test/nutrition_trend_screen_test.dart` | green |
  | `gateway.sh test` (full suite) | `+3225 ~1: All tests passed!` — Phase 3 changes no test file, so this is Phase 2's endpoint, re-observed |
  | `gateway.sh lint` | `196 issues found.` with 0 `error •` |
  | `gateway.sh git-diff --name-only` | the doc set below, plus this plan's folder |

- Doc sizes (`wc -c`; the ceiling is 64 KiB):

  | File | Bytes |
  |---|---|
  | `docs/nutrition.md` (new) | 14,320 |
  | `docs/data_models.md` | 37,279 |
  | `docs/stats_screen.md` | 17,005 |
  | `docs/README.md` | 19,308 |
  | `docs/widget_catalog.md` | 12,326 |
  | `docs/docs-audit-2026-07-26.md` | 15,777 |
  | `docs/stats_best_load_investigation.md` | 35,138 |
  | `docs/app_philosophy.md` | 7,774 |
  | `lib/widgets/chart/scrollable_trend_chart.dart` | 15,291 |

  The chart's 9-byte drop from Phase 2's 15,300 is exactly the line-1 comment's shortened path
  (`lib/features/stats/widgets/` → `lib/widgets/chart/`), so this phase's only code edit is that one
  comment line and nothing else in the file moved.

- Residue sweep (D-666), re-run against the tree and **clean**. All 22 names in the guard's
  `_kRetiredNames` (`kTopCardioCount`, `kTopIsometricCount`, `kTopSportsCount`, `_processTimedEffort`,
  `_processDrillEffort`, `_processRoundEffort`, `_buildFullCardioForExercises`, `_buildFullDrillForExercises`,
  `_buildFullRoundForExercises`, `_CardioDay`, `_DrillDay`, `_RoundDay`, `CardioTrendPoint`,
  `CardioProgress`, `DrillProgress`, `RoundProgress`, `topCardio`, `topIsometric`, `topSports`,
  `nutritionTrend`, `StatsWindow.empty`, `hasData`) swept over `lib/`: exactly **one** line matches, and
  it is a false positive — `snapshot.hasData` in `lib/features/profile/widgets/measurement_sparkline.dart`
  is an `AsyncSnapshot` read, not the retired `StatsProgressData.hasData`. Swept over `test/`, the same
  single false positive appears in `test/profile_cleanup_test.dart`; everything else is the guard's own
  string literal in `test/stats_legacy_removal_test.dart`.
  `lib/features/stats/widgets/scrollable_trend_chart.dart` is gone (Governor, after Phase 2);
  `lib/features/stats/widgets/recent_pr_list.dart` is still live — `records_and_trends_screen.dart`
  reads it — so it stays.

- `gateway.sh test test/docs_indexing_contract_test.dart test/stats_legacy_removal_test.dart test/nutrition_trend_screen_test.dart`: green (governor, re-confirmed by the reviewer).

- `gateway.sh test` (full suite) final line: `+3225 ~1: All tests passed!` — unchanged from Phase 2,
  as expected, since this phase changes no test file.

- `gateway.sh lint`: `196 issues found.` with 0 `error •`. The only `lib/` byte this phase touches is a
  comment, so the count is unchanged from Phase 2.

- `gateway.sh git-diff --name-only` (governor, re-confirmed by the reviewer): `docs/nutrition.md` (new),
  `docs/README.md`, `docs/widget_catalog.md`, `docs/data_models.md`, `docs/stats_screen.md`,
  `docs/docs-audit-2026-07-26.md`, `docs/stats_best_load_investigation.md`, `docs/app_philosophy.md`,
  `lib/widgets/chart/scrollable_trend_chart.dart`, and this plan's folder. The five docs step 22 also
  named are absent because they were left unchanged — see the next bullet.

- Step 22's reconcile targets that were **not** edited, each re-read and already conformant, so the
  absent `git-diff` entries are intentional: `docs/design_system.md` (the header-case table already
  lists `ALL TIME`, the four Instruments headers and `Fuel` with its tests), `docs/state_management/services_and_utils.md`
  (already names the live outputs and marks `computeProgressData`'s fixed order superseded for the
  Instruments list only), `docs/records_and_trends.md`, `docs/profile_and_measurements.md` (already
  names the all-time aggregates, the Instruments list and the Fuel row) and
  `docs/navigation_and_screens.md` (already carries the Fuel row and the trend screen's entry point).
  `docs/stats_screen.md` was the one target that still carried a stale claim, and it was fixed.

- Links added by this phase, all resolved against the tree by reading it: `docs/README.md`,
  `docs/widget_catalog.md`, `docs/app_philosophy.md` and `docs/docs-audit-2026-07-26.md` → `nutrition.md`;
  `docs/nutrition.md` → `data_models.md#nutrition-models`, `data_models.md#fuelsummary`,
  `state_management/nutrition_state.md`, `widget_catalog/nutrition_widgets.md`,
  `widget_catalog/home_screen.md`, `stats_screen.md`, `navigation_and_screens.md`,
  `db_integration.md`. Every target exists and no link to the removed Stats NUTRITION surface remains.

- Independently of the gate, every rule `test/docs_indexing_contract_test.dart` enforces was checked by
  hand over the files this phase touched:
  - **Ceiling and warning band.** No touched file exceeds 64 KiB (table above), and none reaches the
    80% warning band (52,429 B) — the largest is `docs/data_models.md` at 37,279 B (57%).
  - **Link resolution.** Every relative link in `docs/nutrition.md` resolves to a file that exists (7
    targets, all confirmed present). The gate ignores fragments (`([^)#]+?)(?:#[^)]*)?`), so the two
    `data_models.md` anchors are cosmetic — both headings (`## Nutrition Models`, `### FuelSummary`) do
    exist.
  - **Reachability.** The new page is linked from four live docs (`README.md`, `widget_catalog.md`,
    `app_philosophy.md`, `docs-audit-2026-07-26.md`), so it is not an orphan.
  - **Hex colours.** No touched file contains a hex literal or an `0x…` colour.
  - **Flow/roadmap prohibitions.** No touched file gained a flow heading, a user-action arrow chain
    (`docs/nutrition.md`'s only arrows are inside its fenced nav block, which the gate strips), a
    "not yet implemented" / "will be removed" phrase, or a roadmap heading. The audit record's banner
    is outside all of these guards anyway: `docs-audit-<date>.md` is a frozen record.
  - All 28 test files cited by `docs/nutrition.md` were confirmed to exist on disk, and the four
    behavioural claims with no prior verification in this run were re-read against source:
    `NutritionScreen.initState` fires exactly four un-gated loads (`nutrition_screen.dart`),
    `foodsIEatSections` is the single ordering rule shared by the phone card and the wrist sync,
    `NutritionTrendCard` does hold the toggle, both charts, the empty chart and the legend, and no file
    in `lib/features/nutrition/widgets/` reads a repository (the only matches for "repository"/"hive"
    there are comments asserting its absence, plus "archived").

## 8. Fix round 1 (review 1: CHANGES_REQUESTED)

### F-1 — the two restored `topLifts` guards (@developer)

- `test/stats_progress_test.dart` gained `_addTimedEffort` (next to `_addSetEffort`) and one plain
  `test()` in each group the retired cases came from: `timed effort in lifting-modality session → not in
  topLifts` (`Effort-type keying`) and `only timed efforts → topLifts is empty` (`Empty states`). Both
  seed through `MockWorkoutRepository` only and assert only the surviving `topLifts` half.
- The helper seeds a `timed` effort *carrying* `metric-weight` and `metric-reps` observations. That
  detail is what makes the red proof real: `_processSetEffort` reaches `EntryRows.setEntries`, which
  emits an entry only for a group holding both `metric-reps` and `metric-weight`, so a pure timed
  instance (reps 0) is skipped whatever the filter does and the mutation below would stay green.
- Red→green by the inverse-edit method on the tracked file (no stash, checkout or restore):

  | Run | Edit | Command | Result |
  |---|---|---|---|
  | before | none | `git-diff --stat -- lib/core/services/stats_progress_service.dart` | `1 file changed, 24 insertions(+), 463 deletions(-)` |
  | red | the `'set'`-only `switch (effort.effortKind)` in `computeProgressData` also accepts `'timed'` | `gateway.sh test test/stats_progress_test.dart --plain-name "timed"` | `+0 -2: Some tests failed.` — `test/stats_progress_test.dart:582:9` `Expected: false / Actual: <true>`; `test/stats_progress_test.dart:638:7` `Expected: empty / Actual: [Instance of 'LiftProgress']` |
  | green | the exact inverse | `gateway.sh test test/stats_progress_test.dart` | `+57: All tests passed!` (was `+55` before this round) |
  | after | none | `git-diff --stat -- lib/core/services/stats_progress_service.dart` | `1 file changed, 24 insertions(+), 463 deletions(-)` — identical to "before" |

- `test/stats_progress_test.dart` at the end of this round: `1 file changed, 171 insertions(+), 1133
  deletions(-)`.

### F-2 / F-3 / F-5 — doc corrections (@developer)

- `docs/nutrition.md` (Catalog loading): the mechanism sentence claiming every environment goes through
  `FoodCatalogLoader` is deleted. The paragraph now claims only the parity outcome and names the tests
  that assert it — the `FoodCatalogSeed parity` and `Loader ↔ seed parity (drift guard)` groups in
  `test/food_catalog_load_test.dart`. The loader's own class comment was left alone (pre-existing drift).
- `docs/nutrition.md` (Widgets): the rule is now the checkable half — widgets touch no repository or
  storage directly and writes go through the state owners. The `foodLibraryState` and `log_food_row`
  call sites that made the old "mutates state" clause false are what the new wording accommodates.
- `docs/data_models.md` (`FuelSummary`): the literal-default restatement is gone; the field and its
  has-flag are named only.

### F-4 — plan record hygiene

- (a) One `## Feedback` section remains (the reviewer pointer plus the now-ticked checklist); the
  executor's Phase-3 report moved here and into the plan's Progress table.
- (b) The Assumption Log's repeated number is resolved (11 → 12), and the orphaned sentence about the
  `Semantics` wrapper re-indent is back in entry 6, the entry it describes.
- (c) The `Files Affected` Phase-3 row now names the real set: `docs/nutrition.md` (new),
  `docs/README.md`, `docs/widget_catalog.md`, `docs/data_models.md`, `docs/app_philosophy.md`,
  `docs/stats_screen.md`, `docs/docs-audit-2026-07-26.md`, `docs/stats_best_load_investigation.md`. The
  five docs it wrongly listed were read and left unchanged (Phase 3 bullet above).
- (d) Progress item 12 and the Phase-3 status now record the real cause — the invocation form, not the
  environment — and the green gates. The Assumption Log entry carrying the same claim was corrected too.

### F-7 — the method behind "25 removed / 11 added / net −14" (governor)

The governor ran the full suite at HEAD in a scratch worktree and again on the working tree with the JSON
reporter, then compared **executed test-case names**. That is a different measurement from a count of
source declarations, which reads 20 removed / 9 added / net −11: a declaration inside a loop that runs
over both repository implementations executes twice while counting once in source, so the same diff gains
executed cases without gaining declarations. The executed net is −14, and this file's own Phase-1 lines
carry the suite numbers it is drawn from — the post-4c baseline `+3233 ~1` and the Phase-1 close
`+3219 ~1: All tests passed!`. The conclusion is unaffected either way: the change is net-negative and the
removals are the retired surfaces.

### Gates after fix round 1

| Command | Observed |
|---|---|
| `gateway.sh test test/stats_progress_test.dart test/docs_indexing_contract_test.dart` | `+66: All tests passed!` |
| `gateway.sh test` (full suite) | `+3227 ~1: All tests passed!` — two more than Phase 2's `+3225 ~1`, exactly the two restored cases |
| `gateway.sh lint` | `196 issues found.` — 0 `error •`, 1 `warning •` |
