# Feature: Stats PR 4c2 — the service and model retirement, the carried items and the docs

> Status: **READY** (Iteration 1). No code written. This file is the whole brief for its executor.
> Next handoff: **@dba (Phase 1)** → @developer (Phase 2) → @developer (Phase 3) → `/code-reviewer`.
> Depends on **4c** (`../2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.md`),
> which removes the five legacy sections from the Stats screen. 4c2 never re-adds a screen surface.
> Binding conventions: `docs/global_conventions.md`. Read with this plan:
> `docs/db_integration.md` (the SQL contract), `docs/data_models.md`, `docs/state_management.md` and
> `docs/state_management/services_and_utils.md`, `docs/widget_catalog.md`, `docs/design_system.md`,
> `docs/nutrition.md` (created by this PR), `docs/modality_tracking.md`, and the series index
> `docs/plans/2026-09-30-04-stats-pr4-index.md` (shared decisions D-401…D-534 are cited by ID and
> never restated here). 4b3's review findings 6, 7, 8 and 11
> (`../2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.review.md`)
> are this PR's acceptance criteria for the carried items.
> Evidence: `2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.evidence.md`. Findings: `.review.md`.
> Agents may run **only** `.github/copilot/scripts/macos/gateway.sh` and cannot delete, move or copy
> files. Deletions are listed under **Governor actions** and are performed by the owner between phases.

## Overview

After 4c the Stats screen shows the `ALL TIME` card, the Instruments list and the Fuel row. The
service and the models still compute and carry everything the five removed sections used, and
`docs/stats_screen.md` was the only doc rewritten. 4c2 finishes the removal and closes the series:

1. **The service stops computing what nothing renders.** `computeProgressData()` keeps its name, its
   signature and its three live outputs (`topLifts`, `recentPRs`, `window`) and loses the cardio,
   drill and round passes, their projections and the nutrition-trend projection;
   `lib/core/models/stats_progress.dart` loses the types and fields only those passes produced.
2. **The four items carried out of the 4b3 review** (index §"Carried into 4c"):
   `scrollable_trend_chart.dart` moves to `lib/widgets/chart/` so the nutrition card and the profile
   sheet stop importing from the Stats feature; the Fuel row gains a narrow-width case, a
   large-text-scale case and an accessibility label.
3. **The docs catch up**: `docs/nutrition.md` exists for the first time, the NUTRITION card's
   behaviour owner is named, `docs/data_models.md` gains the Fuel summary, and every doc that still
   describes a removed section, constant or model is reconciled.

Why the service is here and not in 4c: the brief's 4c also retires this code, but the combined
production diff is ~1,770 lines against the 1,500-line hard limit
(`.github/agents/pr_scope_budget.md` §1). Split by layer, 4c is ~1,135 and 4c2 ~1,015. The user-visible
outcome is identical and both PRs land in the same release (4a D-402).

## Scope check (`.github/agents/pr_scope_budget.md` §1)

| Measure | This plan | Limit |
|---|---|---|
| Plan length | 627 lines | 800 hard / 500 soft |
| Phases | 3 | 5 hard / 3 soft |
| Tracks | 1 (the phone app, `lib/`) | 1 soft |
| Ledger decisions | 16 | 20 soft |
| Scenarios | 13 | 30 soft |
| Predicted production lines | **1,015** — service −487 / +18 (doc comments), model −135 / +6, `session_summary_service.dart` comment 2, the moved chart file +430 (created at the new path), Fuel row +4 | ~1,500 hard |

Soft signals: **one** — the plan is over 500 lines (627). No others: 3 phases (not more than 3), one
track, 16 decisions (≤20), 13 scenarios (≤30), no missing prerequisite found in planning. Hard limits:
none — 627 < 800, 3 phases < 5, ~1,015 predicted production lines < ~1,500. One soft signal does not
trigger a split; two would. Tests, fixtures and docs do not count toward the production budget.
Baselines (2026-10-01, before any edit): `gateway.sh lint` → `199 issues found.`;
`gateway.sh test` → `+3256 ~1: All tests passed!`. 4c brings lint to 196; **196 is this PR's expected
count and ≤199 the bar**.

## Resolved Decisions (Ledger)

- **D-651 — 4c2's scope.** (a) the service and model retirement; (b) the four carried items
  (4b3 findings 6, 7, 8, 11); (c) `docs/nutrition.md` + the cross-doc reconciliation; (d) the series
  index's 4c row (planner-owned, already done). 4c2 adds no screen surface and changes no user-visible
  behaviour.
- **D-652 — `computeProgressData()` keeps its name, signature and its three live outputs.**
  `topLifts`, `recentPRs` and `window` are returned exactly as before; the cardio, drill and round
  projections and the nutrition-trend projection are deleted. `topLifts` stays the PR scan set
  (4c D-605) — the PR-detection loop runs inside the lift loop — so `kTopLiftCount` and
  `kTopExerciseRecencyDays` **stay** and continue to govern the Recent PRs list.
- **D-653 — the model retirement list.** Delete `CardioTrendPoint`, `CardioProgress`, `DrillProgress`,
  `RoundProgress`; delete `StatsProgressData.topCardio`, `.topIsometric`, `.topSports`,
  `.nutritionTrend` (fields, constructor parameters and assertions); delete `StatsProgressData.empty`,
  `StatsWindow.hasData` and `StatsWindow.empty` (grep-verified unused in `lib/` and `test/`). Keep
  `TrendPoint`, `LiftProgress`, `StatsPR`, `NutritionTrendPoint`, `NutritionAdherence*`, `StatsWindow`.
  Doc comments that name a removed section are rewritten, not left stale: `LiftProgress`,
  `StatsProgressData` (both blocks), `StatsWindow`, `NutritionTrendPoint`, `NutritionAdherence`.
- **D-654 — the nutrition-trend tests are repointed, not deleted.** `data.nutritionTrend` in
  `test/stats_progress_test.dart` becomes `computeNutritionTrend(days: null)` — the removed projection
  *was* that call, so the expected values are identical and the coverage of the aggregation is
  preserved. No assertion is weakened.
- **D-655 — the service test churn rule.** A test retires only when **every** assertion in it reads a
  removed output (`topCardio`, `topIsometric`, `topSports`, `nutritionTrend`, or a removed type). A test
  that mixes removed and live assertions keeps its live half and loses the removed one; its title is
  reworded to match. The verdict for `test/stats_progress_test.dart` (pre-edit lines, group boundaries
  verified by reading):

  | Group | Lines | Verdict |
  |---|---|---|
  | `Top-N auto-detection` | 430–588 | keep the two `topLifts` tests (431, 501); retire the cardio test (530–588) |
  | `Trend aggregation` | 589–674 | **keep whole** — both tests read `topLifts` only |
  | `Effort-type keying` | 675–800 | keep the lift assertion in 676–706 (reworded); retire 707–745 and 746–800 |
  | `Empty states` | 801–870 | keep the `topLifts`/`recentPRs` assertions in 802–829 and 858–870 (reworded); retire 830–857 |
  | `Cardio trend` | 1182–1300 | retire whole |
  | `Nutrition trend aggregation` | 1301–1612 | **repoint** per D-654 |
  | `Windowed selection (current-state window)` | 1756–2317 | **keep whole** — it is about `window` and `topLifts`; only S-007 (2098) and S-008 (2201) lose their cardio assertions and the cardio words in their titles |
  | `Recency floor on Strength/Cardio selection (Item 3)` | 2792–3103 | keep 2793, 2860, 2933, 2987 (all `topLifts`); retire S-205 (3050–3103) and rename the group to drop "Cardio" |
  | `Isometric drill aggregation (Phase D)` | 3268–3427 | retire whole |
  | `Sports round aggregation (Phase D)` | 3428–3599 | retire whole |
  | `Exercise selection: isometric and sports (Phase D)` | 3600–3862 | retire whole |
  | `e1RM calculation` (358), `PR detection` (871), `PR list dedupe` (929), `Session-summary vs stats PR invariant` (1130), `Single-rep set` (1152), `computeNutritionTrend (full history)` (1613), `Bodyweight inclusion` (2318), `computeNutritionAdherence` (3104), `Banned-framings audit` (3863) | — | keep untouched |

  Never delete a whole group by line range without checking it for live assertions: the Windowed
  selection and Trend aggregation groups sit inside ranges that look removable and are not.
- **D-656 — no schema, seed or repository change.** The removed types are derived, never persisted, so
  `scripts/sqlite_schema.sql` and `scripts/sqlite_seed.sql` are unchanged and `test/db_seed_test.dart`
  stays green as the proof. A diff to `scripts/` or `lib/data/` is out of bounds for this PR.
- **D-657 — one stale comment is repointed.**
  `lib/core/services/session_summary_service.dart:204` says its axis rule "mirrors
  `StatsProgressService.computeProgressData`"; the rule now lives in `_processSetEffort` /
  `topLifts`, so the comment names the live function. Comments only — no behaviour change.
- **D-658 — `scrollable_trend_chart.dart` moves to `lib/widgets/chart/`.** A move, not a rewrite: the
  new file's content is byte-identical to the old file's, and the four live importers (plus the tests)
  are repointed in the same phase:
  - `lib/features/stats/exercise_progress_screen.dart:17` → `import '../../widgets/chart/scrollable_trend_chart.dart';`
  - `lib/features/nutrition/widgets/nutrition_trend_card.dart:10` → `import '../../../widgets/chart/scrollable_trend_chart.dart';`
  - `lib/features/profile/widgets/measurement_history_chart_sheet.dart:9` → `import '../../../widgets/chart/scrollable_trend_chart.dart';`
  - `test/screen_widget_test.dart:37`, `test/nutrition_trend_screen_test.dart:24`, `test/scrollable_trend_chart_test.dart:8`,
    `test/records_and_trends_screen_test.dart:24` → `import 'package:omnitrain/widgets/chart/scrollable_trend_chart.dart';`
  The old path is deleted by the Governor after the phase is green. `stats_screen.dart`'s import died
  in 4c. Reason (4b3 D-533): a widget shared across features belongs under `lib/widgets/chart/`.
- **D-659 — the Fuel row gets an accessibility label.** The tappable row
  (`lib/features/stats/widgets/fuel_section.dart:86–87`, already carrying `Key('fuel_row')`) is wrapped
  in `Semantics(label: 'Nutrition trend', button: true)` — the label names the destination, mirroring
  the header icon's `'Records & Trends'`. The assertion follows the repo pattern:
  `find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Nutrition trend')`, plus the
  existing tap-through.
- **D-660 — the Fuel row's new rendering cases live in `test/fuel_row_screen_test.dart`.** Two cases:
  320×568 dp at 1.0 text scale and 390×844 dp at 2.0 text scale, each asserting no overflow
  (`tester.takeException()` is null) and that the row's figures and its label are still present.
  `test/screen_overflow_contract_test.dart` is **not** touched: it renders the Stats screen but seeds
  no food, so the Fuel row never enters the tree (4b3 review finding 7). If a case reveals an
  overflow, the fix is in scope for this phase (see Open questions).
- **D-661 — `docs/nutrition.md` is the nutrition feature doc.** It is the behaviour owner of the
  NUTRITION card's host (4b3 D-534) and must be ≤ 64 KiB (`test/docs_indexing_contract_test.dart`).
  Every factual sentence names a file and a test. Required outline: Overview and scope (only what
  `lib/features/nutrition/` actually does); Entry points and navigation; Screens
  (`nutrition_screen`, `add_food_screen`, `edit_food_screen`, `nutrition_target_screen`,
  `nutrition_trend_screen`); Widgets (`lib/features/nutrition/widgets/`, including
  `nutrition_trend_card.dart` and the ring/donut/thumbnail controls); State (`NutritionState`,
  `FoodLibraryState`, `NutritionPrimerState`); Data (the models, the repository reads and writes, the
  food catalog loader, the "foods I eat" ordering); Services (`computeNutritionTrend`,
  `computeNutritionAdherence`, `computeFuelSummary`, `food_photo_service`); the Stats **Fuel row**
  (rules referenced from 4b3 D-520…D-531, not restated); Persistence (pointer to
  `docs/db_integration.md`); Related documentation; a doc-claim → test table.
- **D-662 — the cross-doc reconciliation rule.** Every mention of a removed section, constant, type or
  file is either deleted or repointed at its live host. `docs/docs-audit-2026-07-26.md` is a dated
  audit record and is **not** rewritten. `docs/stats_best_load_investigation.md` gets a 1–2 line
  superseded banner (its findings stay as written). The files: `docs/README.md`,
  `docs/widget_catalog.md`, `docs/design_system.md`, `docs/state_management/services_and_utils.md`,
  `docs/records_and_trends.md`, `docs/profile_and_measurements.md`, `docs/navigation_and_screens.md`,
  `docs/app_philosophy.md`, `docs/stats_best_load_investigation.md`, `docs/data_models.md`,
  `docs/stats_screen.md` (re-check only — 4c rewrote it).
- **D-663 — `docs/data_models.md` gains the Fuel summary.** Add the `lib/core/models/fuel_summary.dart`
  row to the code-reference table and the model rows for the types that file defines, following the
  table's existing pattern (4b3 review finding 8). If the section lists a test per model, add
  `test/fuel_row_screen_test.dart` / `test/services_test.dart` as the pattern requires.
- **D-664 — the index records two PRs.** `docs/plans/2026-09-30-04-stats-pr4-index.md`'s 4c row becomes
  a 4c row (the screen) and a 4c2 row (the service, the models, the carried items, the docs), with the
  status header and the scope paragraph updated. Done by the planner in this pass; the executor does
  not re-edit it.
- **D-665 — the analyzer bar.** `gateway.sh lint` reports no errors and ≤ 199 issues; the expected
  count is **196** (4c's result — this PR deletes no warning and must create none). An increase means
  the retirement orphaned an import, a helper or a local: finish the removal instead.
- **D-666 — the residue sweep closes the series.** No `lib/` reader of the removed names remains:
  `kTopCardioCount`, `kTopIsometricCount`, `kTopSportsCount`, `_processTimedEffort`, `_processDrillEffort`,
  `_processRoundEffort`, `_buildFullCardioForExercises`, `_buildFullDrillForExercises`,
  `_buildFullRoundForExercises`, `_CardioDay`, `_DrillDay`, `_RoundDay`, `CardioTrendPoint`,
  `CardioProgress`, `DrillProgress`, `RoundProgress`, `topCardio`, `topIsometric`, `topSports`,
  `nutritionTrend`, `StatsWindow.empty`, `hasData`. Expected residuals: the guard's string literals in
  `test/stats_legacy_removal_test.dart` and the history notes in the docs.

## Feature Invariants

- **Repository parity.** No repository read changes; Mock must keep mirroring Hive value-for-value. A
  diff to `lib/data/` is out of bounds (D-656).
- **Hive is the runtime on every platform.** No `dart:io`, no platform-conditional code.
- **Effort kinds are the only discriminator** (4a D-403, 4b D-504). Removing the cardio/drill/round
  *projections* must not remove the `_cardioValue` / `_isometricValue` / `_sportsValue` /
  `_resistanceValue` functions the Instruments list uses.
- **The PR path is untouched.** `topLifts`, `recentPRs` and the toast/Session Summary behaviour stay
  bit-for-bit; `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` are read-only.
- **No user-visible change.** 4c2 is invisible: same screens, same figures, less work.

## Requirements

1. `computeProgressData()` returns `topLifts`, `recentPRs` and `window` only, with unchanged values.
2. The cardio/drill/round constants, passes, projections, builders and day types are gone from
   `stats_progress_service.dart`; the removed fields and types are gone from `stats_progress.dart`.
3. `test/stats_progress_test.dart` retires only the tests D-655 lists, keeps the live halves of the
   mixed ones, and repoints the nutrition-trend group per D-654.
4. The four carried items are done: the move (D-658), the two Fuel-row cases (D-660), the Fuel
   summary in `docs/data_models.md` (D-663), the Fuel row's label (D-659).
5. `docs/nutrition.md` exists and passes the docs gates (D-661); every other doc is reconciled (D-662).
6. The guard (`test/stats_legacy_removal_test.dart`) covers the service and model names, and fails
   when any of them returns.
7. Analyzer ≤ 199 (expected 196); the full suite green; the PR parity suites byte-identical.

## Acceptance Criteria

| # | Criterion | Scenarios |
|---|---|---|
| A-1 | `computeProgressData()` produces the same `topLifts` / `recentPRs` / `window` as before | S-1251, S-1256 |
| A-2 | The nutrition-trend aggregation is still covered, via `computeNutritionTrend` | S-1252 |
| A-3 | Empty, few-session and all-time-only histories still behave | S-1253, S-1254, S-1255 |
| A-4 | The PR parity suites pass unmodified | S-1257 |
| A-5 | The chart lives at its new path, every importer resolves, the old path is gone | S-1258 |
| A-6 | The Fuel row survives 320 dp and 2.0 text scale without overflowing | S-1259, S-1260 |
| A-7 | The Fuel row exposes its label and still opens the trend screen | S-1261 |
| A-8 | `docs/nutrition.md` exists, is indexed, and every claim maps to a test | S-1262 |
| A-9 | No `lib/` reader of a removed name remains | S-1263 |
| A-10 | Analyzer ≤199 (expected 196), full suite green, diff inside Predicted Files | all |

## Scenarios

### S-1251: every kind of history, service-level
- Fixture: the S-1201 fixture (a set effort, a timed effort, a drill effort, a round effort, food on
  2 of the last 3 days, a target, a training period covering today), driven through
  `computeProgressData()` directly.
- Trigger: call `computeProgressData()` before and after the retirement (capture the "before" values
  in the evidence file from the pre-change checkout).
- Flow: compare `topLifts.length`, each `LiftProgress.e1RmTrend.length`, `recentPRs.length` and
  `window`.
- Expected outcome: identical values. Any difference is a defect: the retirement must be a pure
  subtraction.
- Edge case of: none.

### S-1252: the nutrition trend aggregation survives the move
- Fixture: `ConsumedFood` on 3 days (one over target, one under, one with no food logged), a
  `NutritionTarget` set, plus the S-1251 sessions.
- Trigger: `computeNutritionTrend(days: null)`.
- Flow: compare against the values the removed `StatsProgressData.nutritionTrend` produced for the same
  fixture.
- Expected outcome: identical points and the same adherence overlay; the repointed tests pass with
  unchanged expectations.
- Edge case of: S-1251.

### S-1253: empty repository
- Fixture: no sessions, no food, no target.
- Trigger: `computeProgressData()`.
- Flow: none.
- Expected outcome: `topLifts` empty, `recentPRs` empty, `window` non-null (the window resolves from
  an empty history without throwing); no exception.
- Edge case of: S-1251.

### S-1254: few sessions
- Fixture: 2 completed sessions with set efforts, no food.
- Trigger: `computeProgressData()`.
- Flow: none.
- Expected outcome: `topLifts` holds both exercises, `recentPRs` follows the PR rules, `window`
  resolves; nothing throws.
- Edge case of: S-1251.

### S-1255: an exercise trained only outside the window
- Fixture: exercise E trained once 60 days ago; one recent session on A.
- Trigger: `computeProgressData()`.
- Flow: none.
- Expected outcome: E is absent from `topLifts` (out of the recency floor / window) and absent from
  `recentPRs`; A is present. Unchanged from before the retirement.
- Edge case of: S-1251.

### S-1256: adversarial twins and mixed kinds
- Fixture: two exercises named "Bench Press" — one logged as a set effort, one as a timed effort; a
  third exercise logged as a set effort in one session and as a timed effort in another; a completed
  session with no efforts.
- Trigger: `computeProgressData()`.
- Flow: none.
- Expected outcome: `topLifts` contains only the set-effort exercises (a timed effort is not a lift);
  the empty session contributes nothing; no duplicate-key or null-dereference exception; the values
  match the pre-retirement run.
- Edge case of: S-1251.

### S-1257: PR parity, unmodified
- Fixture: whatever the two toast suites seed.
- Trigger: run both suites.
- Flow: none.
- Expected outcome: green with zero edits; `gateway.sh git-diff` shows no change to either file.
- Edge case of: none.

### S-1258: the moved chart
- Fixture: the tree after the move.
- Trigger: `gateway.sh test test/scrollable_trend_chart_test.dart` and the suites that render the
  chart (Records & Trends, the nutrition trend screen, the measurement history sheet).
- Flow: none.
- Expected outcome: every importer resolves, the widget behaves identically (the test file's
  assertions are unchanged apart from its import line), and the old path no longer exists.
- Edge case of: none.

### S-1259: the Fuel row at 320 dp
- Fixture: food logged today + a target + one completed session; a 320×568 dp surface.
- Trigger: pump the Stats screen.
- Flow: none.
- Expected outcome: no overflow exception, no `RenderFlex overflowed`; the row's figures, its
  `'<n>/7 days logged'` indicator and its label are present.
- Edge case of: none.

### S-1260: the Fuel row at 2.0 text scale
- Fixture: the S-1259 fixture; 390×844 dp at 2.0 text scale.
- Trigger: pump the Stats screen.
- Flow: none.
- Expected outcome: no overflow; the row stays tappable (target ≥ 44 dp) and the figures are still
  found by their text.
- Edge case of: S-1259.

### S-1261: the Fuel row's label
- Fixture: the S-1259 fixture.
- Trigger: pump; then tap the row.
- Flow: find the `Semantics` node with label `Nutrition trend`; tap.
- Expected outcome: the label exists with `button: true`, and the tap still opens the nutrition trend
  screen.
- Edge case of: none.

### S-1262: the docs hold
- Fixture: the doc set after this PR.
- Trigger: `gateway.sh test test/docs_indexing_contract_test.dart`, plus the doc-claim tables by hand.
- Flow: none.
- Expected outcome: `docs/nutrition.md` exists, is ≤ 64 KiB, is linked from `docs/README.md` and
  `docs/widget_catalog.md`; no doc describes a removed section, constant or model; every claim in the
  doc-claim table maps to an existing test.
- Edge case of: none.

### S-1263: the residue sweep
- Fixture: the tree after this PR.
- Trigger: the guard test plus `gateway.sh git-diff`.
- Flow: none.
- Expected outcome: none of D-666's names has a reader in `lib/`; the only occurrences are the guard's
  literals and the docs' history notes; the diff touches only the Predicted Files.
- Edge case of: none.

## Iteration 1

Phase graph: Phase 1 → Phase 2 → Phase 3 (strict). Phase 2 needs Phase 1's green suite because the
Governor deletes the old chart path between them. Phase 3 is docs and needs both.

### Phase 1: the service and the models stop computing the removed sections (@dba)

One change surface: the service, the model and the tests that read them. Work bottom-up inside each
file (D-612 of 4c). Line numbers are pre-edit.

1. [x] `lib/core/services/stats_progress_service.dart` — delete the constants and their doc blocks:
   `kTopCardioCount` (141 + doc 139–140), `kTopIsometricCount` (145 + doc 143–144), `kTopSportsCount`
   (149 + doc 147–148). **Keep** `kTopLiftCount` (137), `kRecentPRCount` (152),
   `kRecentTrainingDaysWindow` (159), `kTopExerciseRecencyDays` (175), `kNutritionTrendDays` (183),
   `kFuelWindowDays` (188), `kFuelVisibilityDays` (198).
2. [x] Rewrite the surviving constants' doc comments so they describe the live rule only:
   `kTopLiftCount` (136) — the cap on the lifts the PR scan covers, not a display list;
   `kTopExerciseRecencyDays` (163–174) — drop "Strength and Cardio top-slot selection" and "Applies
   symmetrically"; `kNutritionTrendDays` (177–182) — stop naming the NUTRITION card (the host is the
   nutrition trend screen).
3. [x] `computeProgressData` (204–606), bottom-up: delete the cardio/drill/round accumulators
   (228–236); delete the `'timed'`, `'drill'` and `'round'` switch cases (258–267) keeping `'set'`;
   delete the three cardio/drill/round names from the `nameCache` set literal (277–279); delete the
   training-day projections and the three `_selectTopNWithRecencyFloor` calls (the block from the
   `// Cardio training days come from` comment at 308 through the `topSportsIds` call ~346); delete
   the three `_buildFull*ForExercises` calls (358–369); delete the three build loops (512–598, from
   `// Build CardioProgress.` to the end of the `topSports.add` loop); delete the `nutritionTrend`
   computation (~584–588) and its return argument. Rewrite the doc comment (200–203), the window
   comment (208–211) and the `repsByExercise` doc (216–223) so they describe what the function does
   now.
4. [x] Delete `_processTimedEffort` (1337–1409), `_processDrillEffort` (1410–1439),
   `_processRoundEffort` (1440–1483), `_buildFullCardioForExercises` (2072–2105),
   `_buildFullDrillForExercises` (2106–2139), `_buildFullRoundForExercises` (2140–2181), `_CardioDay`
   (2286–2315), `_DrillDay` (2317–2322) and `_RoundDay` (2325–2328) — with their doc comments
   (2316 and 2324 belong to `_DrillDay`/`_RoundDay`). Every one of these had its only readers inside
   `computeProgressData` or the other deleted members, so nothing is left dangling.
5. [x] **Keep** everything else, in particular `_HistoryIndex`, `_loadHistory`, `_exerciseById`,
   `computeTotals`, `computeExerciseMetrics`, `computeInstrumentSections`, `previousRangeFor`,
   `_sectionTrainingDayCounts`, `_sensorStats`, `_repsAxisExercises`, `_hasBodyweightEntry`,
   `_sectionForLogs`, `_sectionForKind`, `_nativeValueFor`, `_zeroValueFor`, `_resistanceValue`,
   `_cardioValue`, `_isometricValue`, `_sportsValue`, `_processSetEffort`, `_selectTopNWithRecencyFloor`,
   `computeNutritionTrend`, `computeFuelSummary`, `_averageOf`, `_trainingDayKeys`, `epley1RM`,
   `getAllTimeBestE1RM`, `getAllTimeBestReps`, `resolveWindow`, `_sessionInWindow`,
   `_buildFullSetsForExercises`, `_buildFullRepsForExercises`, `computeNutritionAdherence`,
   `_SetTuple`, `_ExerciseLog`, `_RepsDay`.
6. [x] `lib/core/models/stats_progress.dart` — delete `CardioTrendPoint`, `CardioProgress`,
   `DrillProgress`, `RoundProgress`; in `StatsProgressData` delete the `topCardio`, `topIsometric`,
   `topSports` and `nutritionTrend` fields with their constructor parameters and assertions; delete
   `StatsProgressData.empty`, `StatsWindow.hasData` and `StatsWindow.empty`. Rewrite the doc comments
   on `LiftProgress`, `StatsProgressData` (both blocks — `topLifts` is the PR scan set, and the window
   doc must not name the "Strength and Cardio sections"), `StatsWindow`, `NutritionTrendPoint` and
   `NutritionAdherence`.
7. [x] `lib/core/services/session_summary_service.dart:204` — repoint the comment that names
   `StatsProgressService.computeProgressData` at the live rule (D-657). Comments only.
8. [x] `test/stats_progress_test.dart` — apply D-655's verdict table exactly. Work bottom-up and in
   ≤100-line chunks. Retire whole: `Cardio trend` (1182–1300), `Isometric drill aggregation (Phase D)`
   (3268–3427), `Sports round aggregation (Phase D)` (3428–3599), `Exercise selection: isometric and
   sports (Phase D)` (3600–3862), the cardio test of `Top-N auto-detection` (530–588), the cardio and
   drill tests of `Effort-type keying` (707–800), the timed-only test of `Empty states` (830–857) and
   S-205 of the recency-floor group (3050–3103). **Repoint** the `Nutrition trend aggregation` group
   (1301–1612) from `data.nutritionTrend` to `computeNutritionTrend(days: null)` per D-654 — same
   expectations. **Keep** the groups D-655 lists, including `Trend aggregation` (589–674) and
   `Windowed selection` (1756–2317) — do not delete them by line range: they read `topLifts`/`window`,
   which survive. In the kept groups, delete only the assertions that name a removed output (the
   `topCardio` / `topIsometric` / `topSports` expectations in 676–706, 802–829, 858–870, 2098–2196,
   2201–2245, and the cardio wording in those titles) and reword the affected titles. Rename the
   recency-floor group to drop "Cardio". The `topLifts` reads in the e1RM group (394–424) stay valid
   because `topLifts` survives.
9. [x] `test/stats_legacy_removal_test.dart` — append the service/model guard group (D-666): read
   `lib/core/services/stats_progress_service.dart` and `lib/core/models/stats_progress.dart` as text
   and assert the absence of every name in D-666's list. Do not weaken 4c's groups.
10. [x] **Red proof (mandatory, evidence file).** M-3: temporarily re-add `const int kTopCardioCount = 5;`
    to the service → the new guard group must FAIL → revert; confirm green again. Paste both outputs
    into the evidence file.
11. [x] Run the Done Criteria.

**Done Criteria** (run until green):
- `gateway.sh format` on every file this phase touched.
- `gateway.sh lint` → no errors, total **196** (≤199 is the bar).
- `gateway.sh test test/stats_progress_test.dart test/db_seed_test.dart test/services_test.dart test/in_session_pr_toast_test.dart test/pr_toast_test.dart`
  → `All tests passed!` (`test/db_seed_test.dart` is the SQL contract's proof that nothing persisted
  changed — D-656).
- `gateway.sh test` → the whole suite green; record the final `+N ~1` line.
- `gateway.sh git-diff` → only the Predicted Files.

**Predicted Files**: `lib/core/services/stats_progress_service.dart`,
`lib/core/models/stats_progress.dart`, `lib/core/services/session_summary_service.dart`,
`test/stats_progress_test.dart`, `test/stats_legacy_removal_test.dart`. Nothing else — `scripts/` and
`lib/data/` are out of bounds.

**Phase 1 verification notes (Conductor):** _added after the phase is reported complete._

### Phase 2: the carried items — the move, the Fuel row's cases and its label (@developer)

12. [x] Create `lib/widgets/chart/scrollable_trend_chart.dart` with the **byte-identical** content of
    `lib/features/stats/widgets/scrollable_trend_chart.dart` (15,306 bytes). A move, not a rewrite:
    no rename, no reformat, no import change inside the file unless its own relative imports need it
    (they resolve identically at the new depth only if they were `package:` imports or `../../../` —
    check each and adjust the path only).
13. [x] Repoint the importers to the exact strings pinned in D-658 (three in `lib/`, four in `test/`).
    `lib/features/stats/stats_screen.dart`'s import died in 4c; if it is still present, 4c is
    incomplete — stop and report.
14. [x] `lib/features/stats/widgets/fuel_section.dart:86–87` — wrap the tappable `InkWell` in
    `Semantics(label: 'Nutrition trend', button: true, child: …)` (D-659). Keep `Key('fuel_row')`
    where it is so every existing `find.byKey` keeps working.
15. [x] `test/fuel_row_screen_test.dart` — add the two cases of D-660 (320×568 @1.0, 390×844 @2.0 text
    scale) asserting no overflow and the row's presence, and the label assertion of S-1261
    (`find.byWidgetPredicate` on the `Semantics` label) plus the tap-through. Do **not** touch
    `test/screen_overflow_contract_test.dart` (it seeds no food).
16. [x] **Red proof (mandatory, evidence file).** Two inverse mutations on tracked files:
    M-4 remove the `Semantics` wrapper → the label assertion FAILS → revert.
    M-5 temporarily give the Fuel row's inner `Row` a fixed `width: 900` → the 320 dp case FAILS →
    revert. Paste both outputs and the green re-run into the evidence file.
17. [x] Run the Done Criteria.

**Done Criteria** (run until green):
- `gateway.sh format` on every file this phase touched.
- `gateway.sh lint` → no errors, total 196 (≤199 is the bar).
- `gateway.sh test test/fuel_row_screen_test.dart test/scrollable_trend_chart_test.dart test/records_and_trends_screen_test.dart test/nutrition_trend_screen_test.dart test/screen_widget_test.dart`
  → green.
- `gateway.sh test` → the whole suite green; record the final line.
- `gateway.sh git-diff` → only the Predicted Files (plus the new chart file).

**Predicted Files**: `lib/widgets/chart/scrollable_trend_chart.dart` (new),
`lib/features/stats/exercise_progress_screen.dart`,
`lib/features/nutrition/widgets/nutrition_trend_card.dart`,
`lib/features/profile/widgets/measurement_history_chart_sheet.dart`,
`lib/features/stats/widgets/fuel_section.dart`, `test/fuel_row_screen_test.dart`,
`test/screen_widget_test.dart`, `test/nutrition_trend_screen_test.dart`,
`test/scrollable_trend_chart_test.dart`, `test/records_and_trends_screen_test.dart`.

**Governor action (after Phase 2 is green):** delete
`lib/features/stats/widgets/scrollable_trend_chart.dart`. Its content now lives at
`lib/widgets/chart/scrollable_trend_chart.dart` and every importer resolves to the new path; no agent
may delete or move files.

**Phase 2 verification notes (Conductor):** _added after the phase is reported complete._

### Phase 3: the docs (@developer)

18. [x] Create `docs/nutrition.md` per D-661's outline. Sources to read first: `lib/features/nutrition/`
    (5 screens), `lib/features/nutrition/widgets/` (11 widgets), `lib/state/nutrition_state.dart`,
    `lib/state/food_library_state.dart`, `lib/state/nutrition/nutrition_primer_state.dart`,
    `lib/core/models/food_draft.dart`, `lib/core/models/fuel_summary.dart`,
    `lib/core/utils/food_helpers.dart`, `lib/core/utils/foods_i_eat_order.dart`,
    `lib/core/services/food_photo_service.dart`, `lib/data/datasources/food_catalog_loader.dart`, and
    the nutrition functions in `stats_progress_service.dart`. Every named file must exist; every
    behavioural sentence must name a test. ≤ 64 KiB.
19. [x] `docs/README.md` — replace the "**Nutrition** — no dedicated feature doc yet ⚠️" row with the
    link to `docs/nutrition.md` (and drop the ⚠️).
20. [x] `docs/widget_catalog.md:30–31` — the NUTRITION card's host and behaviour owner become
    `docs/nutrition.md`; if the row still describes the removed Stats NUTRITION section, rewrite it for
    the trend screen's host.
21. [x] `docs/data_models.md` — add the `fuel_summary.dart` row and its model rows (D-663).
22. [x] Reconcile the rest per D-662: `docs/design_system.md:180` (the header-case table must list the
    live eyebrows — `ALL TIME` and the Instruments section headers — not STRENGTH/CARDIO/NUTRITION);
    `docs/state_management/services_and_utils.md:258,280` (read 250–285 first; the
    `computeProgressData` description must name the live outputs); `docs/records_and_trends.md:94`;
    `docs/profile_and_measurements.md:21`; `docs/navigation_and_screens.md:182,196`;
    `docs/app_philosophy.md:23`; `docs/stats_best_load_investigation.md:113,123` (superseded banner
    only); re-read `docs/stats_screen.md` for any claim about a constant or model this PR removed.
23. [x] Confirm the doc-claim table below against the named tests; fix the doc when a claim has no
    test.
24. [x] Residue sweep (D-666) and update this plan's Progress table + Assumption Log; write the
    phase's evidence (suite output, doc sizes, the sweep's residuals) into the evidence file.

**Done Criteria** (run until green):
- `gateway.sh lint` → no errors, total 196 (≤199 is the bar).
- `gateway.sh test test/docs_indexing_contract_test.dart test/stats_legacy_removal_test.dart test/nutrition_trend_screen_test.dart`
  → green.
- `gateway.sh test` → the whole suite green.
- `gateway.sh git-diff` → only `docs/` and this plan folder.

**Predicted Files**: `docs/nutrition.md` (new), `docs/README.md`, `docs/widget_catalog.md`,
`docs/data_models.md`, `docs/design_system.md`, `docs/state_management/services_and_utils.md`,
`docs/records_and_trends.md`, `docs/profile_and_measurements.md`, `docs/navigation_and_screens.md`,
`docs/app_philosophy.md`, `docs/stats_best_load_investigation.md`, `docs/stats_screen.md` (only if a
claim died here), this plan + its evidence file.

**Phase 3 verification notes (Conductor):** _added after the phase is reported complete._

## Doc-claim → test table

| Claim | Test |
|---|---|
| The nutrition trend screen shows the extracted card with the Calories / Macros toggle | `test/nutrition_trend_screen_test.dart` (S-1110(a)) |
| The Fuel row shows 7-day averages over logged days against the target, and its logged-days indicator | `test/fuel_row_screen_test.dart` |
| The Fuel row hides after 14 days without logs and loses to the empty state | `test/fuel_row_screen_test.dart` |
| The Fuel row opens the trend screen and exposes the label `Nutrition trend` | `test/fuel_row_screen_test.dart` (S-1261) |
| `computeFuelSummary` averages over logged days only and resolves the window itself | `test/fuel_row_screen_test.dart` (corrected — `test/services_test.dart` has no fuel group) |
| `computeNutritionTrend(days: null)` aggregates all history; `days: n` windows it | `test/stats_progress_test.dart` (the repointed group + `computeNutritionTrend`) |
| `computeNutritionAdherence` anchors the target step to the actuals | `test/stats_progress_test.dart` (`computeNutritionAdherence`) |
| Nutrition rows live in Hive behind `WorkoutRepository` | `test/db_seed_test.dart` (the contract), the repository tests |
| The chart widget is shared from `lib/widgets/chart/` | `test/scrollable_trend_chart_test.dart` |

## Files Affected (whole feature)

| File | Phase | Change |
|---|---|---|
| `lib/core/services/stats_progress_service.dart` | 1 | −487 / +18 |
| `lib/core/models/stats_progress.dart` | 1 | −135 / +6 |
| `lib/core/services/session_summary_service.dart` | 1 | comment only |
| `test/stats_progress_test.dart` | 1 | retire ~950 lines of tests; repoint the nutrition-trend group |
| `test/stats_legacy_removal_test.dart` | 1 | append the service/model guard group |
| `lib/widgets/chart/scrollable_trend_chart.dart` | 2 | new — the moved file, byte-identical |
| `lib/features/stats/exercise_progress_screen.dart` | 2 | import |
| `lib/features/nutrition/widgets/nutrition_trend_card.dart` | 2 | import |
| `lib/features/profile/widgets/measurement_history_chart_sheet.dart` | 2 | import |
| `lib/features/stats/widgets/fuel_section.dart` | 2 | +4 — the `Semantics` label |
| `test/fuel_row_screen_test.dart` | 2 | +2 cases, +1 label assertion |
| `test/screen_widget_test.dart`, `test/nutrition_trend_screen_test.dart`, `test/scrollable_trend_chart_test.dart`, `test/records_and_trends_screen_test.dart` | 2 | import lines |
| `docs/nutrition.md` | 3 | **new** |
| `docs/README.md`, `docs/widget_catalog.md`, `docs/data_models.md`, `docs/app_philosophy.md`, `docs/stats_screen.md`, `docs/docs-audit-2026-07-26.md`, `docs/stats_best_load_investigation.md` | 3 | reconciliation |
| `lib/features/stats/widgets/scrollable_trend_chart.dart` | Governor | deleted after Phase 2 |

## Governor actions

| Path | When | Why |
|---|---|---|
| `lib/features/stats/widgets/scrollable_trend_chart.dart` | after Phase 2 is green, before Phase 3 | The file was re-created byte-identically at `lib/widgets/chart/scrollable_trend_chart.dart` and every importer was repointed; leaving the old path behind would keep a cross-feature import possible. No agent may delete or move files. |

## Notes

- **Intermediate state (declared).** Between 4c and 4c2 the service computes projections nothing
  renders. 4c2 Phase 1 removes them; the user sees no change in either direction.
- **Phase dependency graph.** 4c → 4c2 Phase 1 → Phase 2 → Phase 3. 4c2 starts only after 4c is
  green and committed: Phase 1's deletions are safe because 4c removed the only readers, Phase 2's
  step 9 appends to `test/stats_legacy_removal_test.dart` (created by 4c Phase 2), and Phase 3's doc
  reconciliation assumes `docs/stats_screen.md` already describes the post-4c screen. Phases 1–3 are
  strictly ordered; there is no re-ordering that yields a partial user-visible win (nothing in 4c2
  is user-visible except the Fuel row's label and its rendering cases).
- **The move is a move.** Do not "improve" the widget while moving it: a diff inside the moved file
  makes the review unreviewable and breaks the byte-identical claim the plan relies on.
- **`test/screen_overflow_contract_test.dart` is deliberately out of scope** — it seeds no food, so
  the Fuel row never enters its tree. If a future change seeds food there, the Fuel row's cases
  (S-1259/S-1260) are the coverage it needs.
- **Docs trail code by zero phases**: Phase 3 runs after both code phases, so no doc describes a
  removed surface for even one phase.
- **The one large test file: approach and why.** `test/stats_progress_test.dart` is 3,940 lines and
  retires ~950 of them, so it is edited in place (bottom-up, ≤100-line `edit` chunks) rather than
  emptied and recreated. It cannot be emptied: the groups D-655 keeps — `e1RM calculation`,
  `Trend aggregation`, `PR detection`, `PR list dedupe`, `Session-summary vs stats PR invariant`,
  `Single-rep set`, `computeNutritionTrend (full history)`, `Windowed selection`, `Bodyweight
  inclusion`, `computeNutritionAdherence`, `Banned-framings audit` — are the coverage for the
  service that survives, and transcribing them into a new file would retype ~2,600 lines of live
  tests for no gain. The other four touched test files (`test/fuel_row_screen_test.dart`,
  `test/nutrition_trend_screen_test.dart`, `test/screen_overflow_contract_test.dart` untouched,
  `test/stats_legacy_removal_test.dart` appended) are edited in place as well; nothing in this PR
  needs a Governor deletion except the old chart path (D-658).
- **Legacy handling**: none (series D-402 — no user data, no migration, no feature flag).

## Progress

| # | Item | Phase | Result |
|---|---|---|---|
| 1 | The three cardio/isometric/sports constants leave the service | 1 | done — `kTopCardioCount` / `kTopIsometricCount` / `kTopSportsCount` and their doc blocks deleted; lint 0 errors |
| 2 | `computeProgressData` returns `topLifts` / `recentPRs` / `window` only | 1 | done — accumulators, switch cases, nameCache keys, projections and build calls/loops all gone |
| 3 | Nine helpers and three day types leave the service | 1 | done — `_processTimed/Drill/RoundEffort`, `_buildFullCardio/Drill/RoundForExercises`, `_CardioDay` / `_DrillDay` / `_RoundDay` |
| 4 | The model loses four types and six members | 1 | done — four types, four `StatsProgressData` fields + params, `empty`, `hasData`, `StatsWindow.empty` |
| 5 | `test/stats_progress_test.dart` retired + the nutrition group repointed | 1 | done — 16 kept groups, 55 tests green; nutrition group repointed to `computeNutritionTrend(days: null)` (D-654) |
| 6 | The service/model guard group added to 4c's guard file and red-proven (M-3) | 1 | done — `S-1263 residue sweep` (9 tests); M-3 red `+8 -1`, green `+9` |
| 7 | The chart moved; four importers repointed | 2 | done — byte-identical (369 lines; 15,306 → 15,300 bytes, the 6-byte delta is the two relative imports at the new depth); **eight** importers repointed, not four (the plan's D-658 list missed `test/stats_legacy_removal_test.dart`) |
| 8 | The Fuel row's two rendering cases + label, red-proven (M-4, M-5) | 2 | done — `Semantics(label: 'Nutrition trend', button: true)` wraps the `InkWell`; three cases on both harnesses (`+42`); M-4 red `Found 0 widgets…` → green; M-5 red `RenderFlex overflowed by 678 pixels` → green |
| 9 | `lib/features/stats/widgets/scrollable_trend_chart.dart` deleted (Governor) | between 2 and 3 | done — the old path is absent from `lib/features/stats/widgets/`; every importer resolves to `lib/widgets/chart/` |
| 10 | `docs/nutrition.md` created and indexed | 3 | done — created (14 KB), linked from `README.md`, `widget_catalog.md`, `app_philosophy.md` and the audit record |
| 11 | Ten docs reconciled; the doc-claim table confirmed | 3 | done — of the ten regions step 22 names, only `docs/stats_screen.md` carried a stale claim (the four removed value types); the other nine's reconcile regions were read and left unchanged because they were already conformant (four of them gained only a link or an anchor to the new page). Two governor additions landed: the chart's line-1 comment and the audit record's banner. One doc-claim row was corrected (see Assumption Log 8) |
| 12 | Residue sweep clean; full suite green; lint 196 | 3 | done — the sweep is clean (D-666). The Done-Criteria commands were first reported unrun because each invocation was wrapped (a `cd … &&` prefix, a `sh`/`bash` wrapper, or an absolute path) and every wrapper was refused; the literal relative form `.github/copilot/scripts/macos/gateway.sh <check>` runs. The governor then ran `gateway.sh lint` (196 issues, 0 errors) and `gateway.sh test` (`+3225 ~1: All tests passed!`) green, and the reviewer re-ran both with the same result |
| 13 | Fix round 1 (review findings 1–3 and the record items 4–7) | fix 1 | done — F-1 restored the two timed-effort `topLifts` guards (red `+0 -2` under the inverse edit → green `+57`); F-2/F-3/F-5 corrected the three doc claims; F-4 and F-7 are record fixes in this file and the evidence file. Both gates re-run green: lint 196 / 0 errors, suite `+3227 ~1` |

**Phase 3 status: Complete.** All doc work is written and both Done-Criteria gates were observed
green (lint 196 with 0 errors; suite `+3225 ~1`) — first by the governor, then by the reviewer in
`…-plan.review.md`. The refusals recorded here earlier came from the invocation form, not the
environment. Fix round 1 adds the two restored guards and the three doc corrections; its evidence is
in `…-plan.evidence.md` (Fix round 1) and its checklist is in `## Feedback` below.

## Assumption Log

Executors append here (decision, options considered, choice + why; ≤3 lines each). The Conductor
marks each RATIFIED (promoted to a D-x) or REVERT (remediation) at verification.

1. **Two comments beyond the plan's list were rewritten.** `_selectTopNWithRecencyFloor` and
   `resolveWindow` doc comments named the removed cardio/drill sections. Options: leave them naming
   deleted code, or rewrite. Chose rewrite — D-653's rule is that comments naming removed sections go.
2. **Deletion seams cost two extra edits.** Removing a test that ends a group also removes the
   group's closing `});`, and emptying a set literal makes `dart format` collapse it to one line.
   Chose to re-add the closers and accept the collapsed literal as legitimate formatting, not churn.
3. **S-1251's "before" values could not be executed.** The gateway permits no `git checkout`/`stash`,
   so pre-change output cannot be produced in this run. Chose to pin the unmodified HEAD expectations
   as the before values — `git-diff` shows no kept expectation changed, only repointed/reworded.
4. **D-655's keep-list was checked by group name, not by count.** All 16 groups D-655 says to keep are
   present and every removed title is on the retire list; the full-suite delta (`+3233 ~1` → `+3219 ~1`)
   matches the 14 retired tests exactly.
5. **An eighth importer existed.** `test/stats_legacy_removal_test.dart` (line 29) imports and reads
   `ScrollableTrendChart` but is not in D-658's list. Options: leave it pointing at the old path, or
   repoint. Chose repoint — the old path dies after Phase 2, so leaving it would break the suite.
6. **The `Semantics` wrapper re-indents its subtree.** Nesting the `InkWell` one level deeper shifts
   ~75 lines of `fuel_section.dart`, so the file's diff is 154 lines, not the plan's predicted "+4".
   The change is the wrapper only; no line's content changed.
7. **Nine of the ten reconcile regions were already conformant.** `design_system.md`,
   `services_and_utils.md`, `records_and_trends.md`, `profile_and_measurements.md`,
   `navigation_and_screens.md` and `app_philosophy.md` already described the post-4c screen. Chose to
   read each region once and leave it unchanged rather than invent edits for them.
8. **The doc-claim table's `computeFuelSummary` row named the wrong test.** `test/services_test.dart`
   has no fuel group at all; the claim is asserted in `test/fuel_row_screen_test.dart`. Chose to
   repoint the row at the test that does assert it (step 23) instead of leaving a citation with no test.
9. **The Done Criteria were first reported unrun.** Each `gateway.sh` invocation was wrapped (a
   `cd … &&` prefix, a `sh`/`bash` wrapper, or an absolute path) and every wrapper was refused; the
   literal relative form runs. Chose to record the refusals as an invocation-form problem and re-run
   both gates in that form — they are green (lint 196 / 0 errors; suite `+3225 ~1`).
10. **The best-load banner went to the top of the file, not to its lines 113/123.** Step 22 fixes no
   location for it. Chose to extend the file's existing top-of-file status blockquote, which is what a
   reader sees first and what the audit record's banner mirrors.
11. **`docs/nutrition.md` omits two things the outline implied.** No `food_helpers` section (no test
   asserts its output) and no `EditFoodScreen` edge in the navigation tree (nothing verified it).
   Chose the brief's rule — leave out what has no test — over a complete-looking outline.
12. **M-5's literal mutation cannot go red.** `SizedBox(width: 900, child: Row(…))` is clamped by the
   Column's `maxWidth`, so the 320 dp case still passed (observed). Chose to keep the same intent —
   the row's content pinned to a fixed 900 dp — as a rigid `const SizedBox(width: 900)` child, which
   overflows for real; reverted after the red run.

## Feedback

Empty. When non-empty, the planner folds it into a new Iteration block and clears this section.
Reviewer findings go in `2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.review.md`, with only a
pointer and a fix checklist here.

Review 1 (CHANGES_REQUESTED, 2 major / 2 minor / 3 nits) is in
`2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.review.md`. The one bounded fix round is done:

- [x] Finding 1 — `test/stats_progress_test.dart`: the timed-effort guard on `topLifts` is restored in
      both groups (`Effort-type keying`, `Empty states`); red under the inverse edit, green after.
- [x] Finding 2 — `docs/nutrition.md`: the loader mechanism sentence is gone; the paragraph now claims
      only the parity outcome and points at the two parity groups in `test/food_catalog_load_test.dart`.
- [x] Finding 3 — `docs/nutrition.md`: the widget rule is now "touch no repository or storage directly;
      writes go through the state owners".
- [x] Findings 4–7 — folded in: one `## Feedback` section, Assumption Log renumbered, the `Files
      Affected` Phase-3 row corrected, the Phase-3 "Blocked (verification)" cause and status corrected,
      and the evidence file states the method behind the 25/11/−14 count.
- [x] Both gates re-run: lint 196 / 0 errors; suite `+3227 ~1: All tests passed!`.

## Open questions (with defaults — proceed on the defaults unless the owner says otherwise)

1. **Is the service/model retirement allowed to sit in 4c2 rather than 4c?** Default: yes (D-651) —
   together they are ~1,770 production lines against the 1,500-line hard limit; split by layer, each
   PR is under. The user-visible outcome and the release are unchanged.
2. **The Fuel row's accessibility label wording.** Default: `Nutrition trend` (it names the
   destination, mirroring the header's `Records & Trends`). Alternative: `Log food` — wrong, the row
   opens the trend screen, not a logging screen.
3. **If S-1259/S-1260 find an overflow**, the fix is in scope for Phase 2 and must be recorded in the
   Assumption Log with the measured overflow. Default: fix it in the Fuel row's layout, not by
   loosening the test.
4. **Deleting `StatsWindow.hasData` and `StatsWindow.empty`** (grep-verified unused). Default: delete
   them with the rest of the model retirement (D-653). If the owner wants the public surface kept,
   they stay and nothing else changes.
5. **Does `docs/nutrition.md` need its own split?** Default: no — one doc, ≤ 64 KiB, with
   `docs/widget_catalog.md` keeping the widget inventory (the size gate fails loudly if it grows).
6. **Phase 2 leaves one live doc line stale (for Phase 3).** `docs/widget_catalog.md:112` still gives
   `ScrollableTrendChart`'s path as `lib/features/stats/widgets/scrollable_trend_chart.dart`. Phase 3
   step 20 owns that file but only the NUTRITION-card row; the path row needs the new
   `lib/widgets/chart/` path in the same pass. Left untouched here to respect the phase boundary.
7. **The moved file's line-1 comment still names the old path.** `// filepath:
   lib/features/stats/widgets/scrollable_trend_chart.dart` is content, so byte-identity kept it. The
   Governor's deletion of the old path makes it a stale pointer; it is out of Phase 2's scope to edit.
