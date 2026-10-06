# Feature: Stats PR 4c — remove the legacy Stats sections (the screen)

> Status: **READY** (Iteration 1). No code written. This file is the whole brief for its executor.
> Next handoff: **@developer (Phase 1)** → @developer (Phase 2) → @developer (Phase 3) → `/code-reviewer`.
> Then **4c2**: `../2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.md`.
> Binding conventions: `docs/global_conventions.md`. Read with this plan:
> `docs/design_system.md` (tokens, header case, contrast gates), `docs/navigation_contract.md`
> (every route push), `docs/stats_screen.md` (the doc this PR rewrites),
> `docs/modality_tracking.md` + `docs/modality_based_exercise_ui.md` (effort kinds),
> and the series index `docs/plans/2026-09-30-04-stats-pr4-index.md` — its shared decisions
> (D-401…D-534) are cited by ID here and **never restated**.
> Evidence: `2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.evidence.md` (baselines, suite
> output, red→green tables, footprints). Reviewer findings: `.review.md`. Neither is written into
> this plan.
> Agents may run **only** `.github/copilot/scripts/macos/gateway.sh` (`list`, `lint`, `test [paths]`,
> `format <paths>`, `pub-get`, `git-status`, `git-diff`, `git-log`, `git-show`). Agents **cannot**
> delete, move or copy files and cannot run plain git/grep/sed/rm. File deletions are listed under
> **Governor actions** below and are performed by the owner between phases.

## Overview

Items 5 and 6 of `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` replace the
five legacy Stats sections with the Instruments list (4b/4b2), the Fuel row (4b3), Records & Trends
(4a) and Exercise Progress (4a). 4a, 4b, 4b2 and 4b3 only **added**; the legacy sections are still
on screen, below the new ones, with `docs/stats_screen.md` describing a layout the user no longer
sees first.

4c makes the screen that the user sees match the screen the docs describe: the five sections leave
`lib/features/stats/stats_screen.dart`, the tests that asserted them are retired or repointed, a
guard makes their return impossible, and `docs/stats_screen.md` is rewritten for the screen that is
left. Nothing the user could reach before is lost — Recent PRs live in Records & Trends (4a), the
nutrition trend lives in the screen the Fuel row opens (4b3), all-time totals live in both the
`ALL TIME` card and Records & Trends.

**4c does not touch the service or the models.** `StatsProgressService.computeProgressData()` and
`lib/core/models/stats_progress.dart` keep computing and carrying the cardio / isometric / sports /
nutrition projections until **4c2**, which retires them along with the four carried items from the
4b3 review and the docs. Reason (scope check below): the combined production diff is ~1,770 lines
against the 1,500-line hard limit; split, each half is ~1,135 and ~1,015. The intermediate state
(the service computes sections nothing renders) is invisible to the user and declared in Notes.

## Scope check (`.github/agents/pr_scope_budget.md` §1)

Measured on this checkout, 2026-10-01:

| Measure | This plan | Limit |
|---|---|---|
| Plan length | 629 lines | 800 hard / 500 soft |
| Phases | 3 | 5 hard / 3 soft |
| Tracks | 1 (the phone app, `lib/`) | 1 soft |
| Ledger decisions | 16 | 20 soft |
| Scenarios | 14 | 30 soft |
| Predicted production lines | **1,135** (`stats_screen.dart` −1,104 / +31) | ~1,500 hard |

Soft signals present: **one** — the plan is over 500 lines (629). No others: phases are exactly 3
(not more than 3), one track, 16 decisions (≤20), 14 scenarios (≤30). Hard limits: none — 629 < 800,
3 phases < 5, 1,135 predicted production lines < ~1,500. One soft signal does not trigger a split;
two would (`.github/agents/pr_scope_budget.md` §1).
Tests (~2,000 lines of edits), fixtures and docs do not count toward the production budget.

**Delivered footprint (fix round 1).** As delivered the diff is 21 tracked paths plus
`test/stats_legacy_removal_test.dart` (new) and this plan folder — one production file, 8 test files
and 12 docs. The scope check is unaffected: docs and tests are outside the production budget, so the
1,135-line production measure and the one-soft-signal verdict stand.

**Why 4c is the screen only.** The brief's 4c also retires the service and the models
(`stats_progress_service.dart` −487, `stats_progress.dart` −135 → ~1,770 production lines, over the
hard limit). The split is by layer: 4c = the screen (+ its tests, its doc, its guard), 4c2 = the
service, the models, the four carried items and the docs. The screen half is the user-visible half,
so `develop` ships the intended experience at 4c.

Baselines (this checkout, before any edit): `gateway.sh lint` → `199 issues found.`;
`gateway.sh test` → `+3256 ~1: All tests passed!`. The 199 includes 3 warnings this PR deletes
(`stats_screen.dart:1336 _ChartSeries` unused, `screen_widget_test.dart:4449/4450` unused locals),
so the expected 4c count is **196**, and **≤199 is the pass bar**.

## Resolved Decisions (Ledger)

Immutable. A change is a new superseding entry, never an edit.

- **D-601 — 4c is the screen half.** PR 4c removes the five sections from the Stats screen and every
  test that asserted them, adds the unreachability guard, and rewrites `docs/stats_screen.md`. The
  service, the models and the four carried items are 4c2's (D-651). The split is technical
  (budget), not a change of user-visible outcome.
- **D-602 — what the Stats screen shows after 4c.** Exactly, in this order: the `ALL TIME` eyebrow +
  aggregate card; then, when the window resolves and the sections are non-empty, the `InstrumentList`
  followed by one `SizedBox(height: 24)`; then, when `_fuelSummary != null`, the `FuelSection` and
  **no trailing separator**; nothing else. No section, chip, chart or list may be added or reordered
  by this PR.
- **D-603 — the empty state wins.** With zero completed sessions the body is exactly
  `[_buildEmptyState(...)]` — no `ALL TIME` eyebrow, no card, no Instruments list, no Fuel row. The
  Fuel row's own zero-session rule (4b3 D-527) is unchanged; the empty state is reached first.
- **D-604 — the screen holds the window, not the data.** `StatsProgressData? _progressData` becomes
  `StatsWindow? _window`, assigned from the same `computeProgressData()` call;
  `computeInstrumentSections(window: progressData.window)` is unchanged in behaviour. `NutritionAdherence?
  _nutritionAdherence` and its `service.computeNutritionAdherence()` call leave `_loadData`
  (`computeNutritionAdherence` itself stays — its live caller is
  `lib/features/nutrition/nutrition_trend_screen.dart:47`).
- **D-605 — `computeProgressData` keeps its name, signature and its three outputs.** It still returns
  `topLifts`, `recentPRs` and `window` (the removed projections leave in 4c2). The PR-detection loop
  runs **inside** the `topLifts` build loop, so `topLifts` *is* the PR scan set and the selection
  constants govern the Recent PRs list — not just a display list. Pack item 6 requires the PR parity
  suites to pass **without modification**, so `test/in_session_pr_toast_test.dart` and
  `test/pr_toast_test.dart` are byte-identical after this PR.
- **D-606 — the legacy layout must be unreachable, proven twice.** (a) Behaviourally: in a pumped
  `StatsScreen`, no legacy section title and no `Key('stats_legacy_sections')` is findable in any of
  the three states (all kinds of history / sessions without food / zero sessions). (b) Structurally:
  a source-text guard over `lib/features/stats/stats_screen.dart` asserting the absence of
  `stats_legacy_sections`, `'STRENGTH'`, `'CARDIO'`, `'ISOMETRIC'`, `'SPORTS'`, `'NUTRITION'`,
  `RecentPRList`, `fl_chart` and any km↔mi conversion literal.
- **D-607 — no chart remains on the Stats screen.** `fl_chart` leaves `stats_screen.dart`, and
  `InstrumentList`/`instrument_row.dart` draw no chart, so `find.byType(LineChart)` finds nothing on
  a pumped Stats screen. The screen keeps exactly one `SegmentedButton` in the app (unchanged).
- **D-608 — `RecentPRList` leaves the Stats screen.** Its live host is Records & Trends (4a). The
  Stats screen keeps only the `OmniBackHeader` action (`Semantics(label: 'Records & Trends', button:
  true)` + `IconButton(tooltip: 'Records & Trends')`) that opens it.
- **D-609 — test retirement rule.** A test is **retired** only if every assertion it makes concerns a
  removed surface. A test that mixes removed and live assertions is **edited** to keep the live ones.
  Nothing that guards live behaviour is retired: PR parity, the PR list dedupe, the parity invariant,
  single-rep sets, bodyweight inclusion, `computeNutritionAdherence`, the banned-framings audit, the
  Instruments list, the Fuel row, the nutrition trend screen, Records & Trends, Exercise Progress,
  the all-time totals, the feeling guards, the single-`SegmentedButton` rule, the zero-session empty
  state.
- **D-610 — the km↔mi source guard survives the file it lives in.** S-836 in
  `test/stats_distance_estimate_test.dart` (a source-text guard that the screen holds no km↔mi
  literal) is transcribed into `test/stats_legacy_removal_test.dart`; the rest of that file retires
  with the cardio card it tested, and the Governor then deletes the file (Governor actions). The live
  "est." marker keeps its coverage in `test/instrument_list_screen_test.dart`.
- **D-611 — `docs/stats_screen.md` describes only the live screen.** No removed section is described,
  no removed constant is named, no removed file is listed; every factual sentence names a test that
  exists (the doc-claim table below). The file stays ≤ 64 KiB (`test/docs_indexing_contract_test.dart`).
- **D-612 — removals are in-place, in ≤100-line `edit` chunks, bottom-up.** Deleting from the bottom
  of a file first keeps the line numbers below valid. No kept test is transcribed into a new file
  (transcription risk with no gain); the only new test file is
  `test/stats_legacy_removal_test.dart`. Exception: the two `StatsScreen` test files the retirement
  would empty out are handled by D-610.
- **D-613 — what the user loses and what replaces it.** STRENGTH → the Instruments list's Resistance
  section + Exercise Progress; CARDIO/ISOMETRIC/SPORTS → the Instruments list's Cardio/Isometric/
  Sports sections + Exercise Progress; NUTRITION → the Fuel row + the nutrition trend screen;
  Recent PRs → Records & Trends; all-time totals → the `ALL TIME` card and Records & Trends. Each
  destination exists and is tested today (see Scenarios S-1204, S-1206, S-1207).
- **D-614 — no production file other than `lib/features/stats/stats_screen.dart` changes in 4c.** The
  service, the models, `lib/widgets/chart/*`, the nutrition card and the moved chart file are 4c2's.
- **D-615 — `scrollable_trend_chart.dart` stays under `lib/features/stats/widgets/` in 4c.** Its move
  to `lib/widgets/chart/` is 4c2's carried item (4b3 review finding 6, D-651); the only 4c change is
  that `stats_screen.dart` stops importing it.
- **D-616 — the analyzer bar.** `gateway.sh lint` must report **no errors** and **≤ 199** issues; the
  expected count after this PR is **196**. Any new warning (unused import, unused element, unused
  local) means a removal is incomplete: finish it rather than leaving the warning.

## Feature Invariants

Only the invariants that bite here. Project-wide rules stay in `docs/global_conventions.md`.

- **Repository parity is not in scope but must not regress.** 4c touches no repository read; if a diff
  touches `lib/data/`, the phase is out of bounds.
- **Hive is the runtime on every platform.** No `dart:io`, no platform-conditional code.
- **Mock mirrors Hive value-for-value.** 4c changes no seed and no read, so the Mock path is
  untouched; the parity suites must stay green unmodified.
- **Route pushes use `OmniNavigator`** (`docs/navigation_contract.md`). The two pushes in this file
  (Records & Trends, the nutrition trend screen) are already compliant and must not be re-plumbed.
- **`test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` are read-only.** They are the
  pack's PR parity guard and item 6 requires them to pass without modification (D-605).
- **One action per surface.** The Stats screen's only action besides rows is the header icon.

## Requirements

1. `lib/features/stats/stats_screen.dart` renders the layout of D-602 and nothing else.
2. The five section builders, their private helpers, the two chart classes, the legacy
   `Column(key: Key('stats_legacy_sections'))` and its separator are gone from the file.
3. The screen's imports contain none of: `fl_chart`, `chart_axis_helper.dart`, `unit_formatter.dart`,
   `chart_primitives.dart`, `edge_aware_date_label.dart`, `nutrition_trend_card.dart`,
   `recent_pr_list.dart`, `scrollable_trend_chart.dart`, `window_chip.dart`.
4. Every test that asserted a removed surface is retired or edited per D-609; the PR parity suites
   are untouched.
5. A guard test proves the legacy layout is unreachable (D-606) and fails if any part of it returns.
6. `docs/stats_screen.md` describes the post-4c screen and passes the docs size gate.
7. Nothing else in `lib/` changes (D-614); the full suite is green.

## Acceptance Criteria

| # | Criterion | Scenarios |
|---|---|---|
| A-1 | A pumped Stats screen shows the `ALL TIME` card, the Instruments list and the Fuel row, and no legacy section | S-1201, S-1202, S-1208, S-1214 |
| A-2 | Zero completed sessions still shows only the empty state | S-1203, S-1212 |
| A-3 | The header icon still opens Records & Trends, which still shows Recent PRs | S-1204, S-1206 |
| A-4 | The Fuel row is last and still opens the nutrition trend screen | S-1207 |
| A-5 | The PR parity suites pass unmodified | S-1205 |
| A-6 | No `LineChart`, no `fl_chart` and no km↔mi literal on the Stats screen | S-1209, S-1210 |
| A-7 | The guard fails when any legacy fragment is reintroduced (inverse mutations) | S-1209 |
| A-8 | `docs/stats_screen.md` describes only the live screen and every claim maps to a test | S-1213 |
| A-9 | Analyzer ≤199 (expected 196), full suite green, diff inside Predicted Files | all |

## Scenarios

Fixture-enumerated. A scenario without a fixture is underspecified — fix the scenario, not the
implementer. Comment references in tests use these IDs.

### S-1201: every kind of history
- Fixture: one `WorkoutSession` (completed) with a resistance set effort (3 sets, 100 kg × 5) on
  exercise A; one completed session with a timed effort (30 min) on exercise B; one completed session
  with a drill effort on C; one completed session with a round effort (5 rounds) on D; all four inside
  the current `StatsWindow`; `ConsumedFood` rows on 2 of the last 3 days with a `NutritionTarget`
  set; one `TrainingPeriod` covering today.
- Trigger: open Stats from the home screen.
- Flow: pump, scroll to the bottom.
- Expected outcome: `ALL TIME` eyebrow + aggregate card; the Instruments list with one section per
  logged kind, rows for A/B/C/D; the Fuel row as the last child with no separator after it; none of
  `STRENGTH`, `CARDIO`, `ISOMETRIC`, `SPORTS`, `NUTRITION` findable; `Key('stats_legacy_sections')`
  absent; no `LineChart` in the tree.
- Edge case of: none (the parent scenario of this PR).

### S-1202: sessions but no food
- Fixture: 2 completed sessions with set efforts in the window; no `ConsumedFood`, no target.
- Trigger: open Stats.
- Flow: pump.
- Expected outcome: `ALL TIME` card + Instruments list only; no Fuel row (`_fuelSummary == null`);
  the last child is the Instruments list; no legacy key.
- Edge case of: S-1201.

### S-1203: zero completed sessions
- Fixture: repository with exercises and a template but no completed session; no food.
- Trigger: open Stats.
- Flow: pump.
- Expected outcome: exactly the empty state (`No sessions yet`); `ALL TIME` not findable; no
  Instruments list; no Fuel row; no legacy key; no exception.
- Edge case of: S-1201.

### S-1204: an exercise trained only outside the window
- Fixture: exercise E trained once 60 days ago (a set effort), nothing since; one recent session on
  exercise A so the window resolves and the screen is not empty.
- Trigger: open Stats; tap the header's Records & Trends action; open E's Exercise Progress.
- Flow: pump each screen.
- Expected outcome: E is absent from the Instruments list (out of window) and present in Records &
  Trends' list with its all-time best; Exercise Progress opens with its chart. Nothing E-related is
  shown on the Stats screen.
- Edge case of: S-1201 (the "nothing lost" proof, D-613).

### S-1205: PR parity after the removal
- Fixture: whatever `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` already seed
  (they read `statsData.topLifts` and `recentPRs`).
- Trigger: run both suites.
- Flow: none.
- Expected outcome: both pass with **zero** edits to those files; `git-diff` shows no change to them.
- Edge case of: none (item 6's guard).

### S-1206: the Records & Trends entry point, and no Recent PRs on Stats
- Fixture: sessions producing at least 2 PRs (two exercises whose e1RM improves twice).
- Trigger: open Stats; find the header action; tap it.
- Flow: pump, tap, pump.
- Expected outcome: the action is findable by its `Semantics` label `Records & Trends` and its
  tooltip; tapping opens Records & Trends, which shows the PR list; the Stats screen itself contains
  no `RecentPRList`.
- Edge case of: S-1201.

### S-1207: the Fuel row is the last section and still navigates
- Fixture: `ConsumedFood` logged today; a target; one completed session.
- Trigger: open Stats; scroll to the bottom; tap the Fuel row.
- Flow: pump, scroll, tap, pump.
- Expected outcome: the Fuel row is the last child; tapping opens the nutrition trend screen with its
  Calories / Macros toggle; no legacy section below it.
- Edge case of: S-1201.

### S-1208: the legacy titles are absent in every state
- Fixture: the three fixtures of S-1201, S-1202 and S-1203, in one parameterised test.
- Trigger: pump each.
- Flow: none.
- Expected outcome: for each state, `find.text` for all five titles finds nothing and the legacy key
  is absent; `tester.takeException()` is null.
- Edge case of: S-1201.

### S-1209: the source guard (structural)
- Fixture: the source text of `lib/features/stats/stats_screen.dart` read at test time.
- Trigger: run the guard test.
- Flow: none.
- Expected outcome: the text contains none of `stats_legacy_sections`, `'STRENGTH'`, `'CARDIO'`,
  `'ISOMETRIC'`, `'SPORTS'`, `'NUTRITION'`, `RecentPRList`, `fl_chart`, `_ChartSeries`, `_LinearScale`;
  and no km↔mi conversion literal (S-836 transcribed).
- Edge case of: none (the structural guard of D-606).

### S-1210: no chart widget on the Stats screen
- Fixture: S-1201's fixture.
- Trigger: pump Stats.
- Flow: none.
- Expected outcome: `find.byType(LineChart)` finds nothing; `find.byType(ScrollableTrendChart)` finds
  nothing; the Instruments rows still render (the list itself is present).
- Edge case of: S-1201.

### S-1211: the app still has exactly one SegmentedButton
- Fixture: the existing test's fixture.
- Trigger: run the kept test.
- Flow: none.
- Expected outcome: unchanged from before this PR (the removed sections owned no toggle).
- Edge case of: none.

### S-1212: the feeling guard is unaffected
- Fixture: sessions that previously produced the feeling rows the guard forbids.
- Trigger: run the kept feeling tests.
- Flow: none.
- Expected outcome: no feeling scalar, pill or tile is rendered, before and after the removal.
- Edge case of: S-1201.

### S-1213: the rewritten doc holds
- Fixture: `docs/stats_screen.md` on disk.
- Trigger: run `test/docs_indexing_contract_test.dart` plus the doc-claim table below by hand.
- Flow: none.
- Expected outcome: ≤ 64 KiB, no removed section described, every claim mapped to an existing test.
- Edge case of: none.

### S-1214: adversarial twins and mixed kinds
- Fixture: two exercises with the **same name** ("Bench Press"), one trained as a set effort and one
  as a timed effort; a third exercise logged as a set effort in one session and as a timed effort in
  another; a completed session with no efforts at all.
- Trigger: open Stats.
- Flow: pump.
- Expected outcome: the Instruments list assigns each row by the **logged effort kind** (4a D-403,
  4b D-504), never by modality; no legacy section appears for any of them; the empty-effort session
  contributes nothing and breaks nothing; no duplicate-key exception.
- Edge case of: S-1201.

## Iteration 1

Phase dependency graph: Phase 1 → Phase 2 → Phase 3 (strict). Phase 2 depends on Phase 1's deletions
and on nothing else; Phase 3 depends on both. The Governor action between Phase 2 and Phase 3 must
run after Phase 2 is green.

### Phase 1: the screen stops rendering the legacy sections (@developer)

One change surface: `lib/features/stats/stats_screen.dart` and the two test files that assert the
screen's own layout. Work **bottom-up** inside each file (D-612) so earlier line numbers stay valid.
Line numbers below are the **pre-edit** numbers.

1. [ ] Delete the legacy child block: the `const SizedBox(height: 24),` at line 184 and the whole
   `Column(key: const Key('stats_legacy_sections'), …)` at 186–200 (17 lines), so the `children:`
   list ends with the Fuel block's `],` and the Fuel row is the last child (D-602).
2. [ ] Delete the two chart classes: `_ChartSeries` (1336–1344, with its doc comment from 1334) and
   `_LinearScale` (1347–1391). This removes the file's `unused_element` warning.
3. [ ] Delete the cardio display helpers `_formatNumber` (1311–1320), `_paceForDisplay` (1321–1325)
   and `_distanceForDisplay` (1326–1328). **Keep** `_buildEmptyState` (1270–1304) and
   `_formatDuration` (1305–1310) — `_formatDuration` is read by `_buildAggregateCard` at line 233.
4. [ ] Delete `_buildSectionEmptyState` (1249–1269) — all four readers (278, 580, 616, 839) are in
   deleted sections.
5. [ ] Delete the cardio / isometric / sports builders and helpers (563–1248), in ≤100-line chunks:
   `_buildCardioSection` (563–598), `_buildIsometricSection` (599–632), `_buildDrillCard` (633–679),
   `_buildDurationChart` (680–785), `_buildSingleDurationPointCard` (786–821), `_buildSportsSection`
   (822–855), `_buildRoundCard` (856–906), `_buildNutritionSection` (907–918), `_buildCardioCard`
   (919–1011), `_buildCardioPaceChart` (1012–1167), `_hasEstimatedDay` (1168–1176),
   `_cardioDotPainter` (1177–1193), `_buildSingleCardioPointCard` (1194–1248).
6. [ ] Delete the STRENGTH builders and helpers (261–562), in ≤100-line chunks: `_buildStrengthSection`
   (261–300), `_buildLiftCard` (301–425), `_formatRepsValue` (426–440), `_buildAddedWeightNote`
   (441–458), `_buildTrendChart` (459–562).
7. [ ] Delete the section header comment for the removed group if it is left dangling (the `// ── …`
   banner above `_buildStrengthSection`); the remaining banners must still name something real.
8. [ ] State (D-604): replace `StatsProgressData? _progressData;` with `StatsWindow? _window;`; delete
   `NutritionAdherence? _nutritionAdherence;`; delete `final adherence = await
   service.computeNutritionAdherence();` (line 81) and `_nutritionAdherence = adherence;`; assign
   `_window = progressData.window;` in the same `setState`; in `build`, `final window = _window;`.
   Keep the `computeProgressData()` call and the `computeInstrumentSections(window:
   progressData.window)` call exactly as they are.
9. [ ] Rewrite the `_loadData` comment at 75–77: it currently lists "e1RM trends, cardio trends,
   isometric trends, sports trends, PRs, and the nutrition trend". It must name what the call is now
   used for (the window and the PR data the Records & Trends path shares) without naming removed
   sections.
10. [ ] Prune the imports listed in Requirement 3. Keep `stats_progress.dart` (it supplies
   `StatsWindow`), `date_utils.dart`, `stats_pill.dart`, `fuel_summary.dart`, `instrument_list.dart`,
   `nutrition_trend_screen.dart`, `records_and_trends_screen.dart`, `fuel_section.dart`, the `omni_*`
   layout/widget imports and the three state imports.
11. [ ] `test/screen_widget_test.dart` — retire the 21 tests that assert removed surfaces, in ≤100-line
   `edit` chunks, **bottom-up**: 4001–4913 (913 lines), then 3827–3973 (147), then 3672–3826 (155),
   then 3542–3591 (50), then 2863–3458 (596) — 1,861 lines total. Keep the 10 tests listed in the
   evidence file's retirement table (2750, 2760, 2778, 2824, 3459, 3510, 3592, 3624, 3640, 3974). The
   helpers above 2749 and the group's other members stay; if a helper loses its last reader, delete
   it too (D-616).
11a. [ ] Reword the kept test at 3974: it currently reads `app: only one SegmentedButton exists (all
   toggles except Nutrition deleted)` and passes vacuously once the NUTRITION card is gone. Retitle it
   to `Stats renders no SegmentedButton` and assert `find.byType(SegmentedButton<dynamic>)`,
   `findsNothing`. If it fails, a surviving surface renders a toggle — find it and remove it (that is
   exactly the defect this test exists to catch). Record the outcome in the Assumption Log.
12. [ ] `test/stats_distance_estimate_test.dart` — retire S-831 (183–232), S-832 (235–288), the
   single-point-card group (289–342), S-835 (343–496) and S-837 (508–end); **keep S-836** (497–507)
   for Phase 2 to transcribe (D-610) and prune the imports the retirements orphaned.
13. [ ] Decide-and-Log: if a kept test turns out to assert a removed surface (the nutrition-toggle
   tests at 3827/3906 are the candidates — they must be about the trend screen or the Fuel row, not
   the deleted NUTRITION card), retire it and record the finding in the Assumption Log. Do not edit a
   test to make a removed surface pass.
14. [ ] Run the Done Criteria.

**Done Criteria** (run until green):
- `gateway.sh format lib/features/stats/stats_screen.dart test/screen_widget_test.dart test/stats_distance_estimate_test.dart`
- `gateway.sh lint` → no errors, and the total is **197** (199 − `_ChartSeries` − the two unused
  locals in `screen_widget_test.dart:4449/4450`). **≤199 is the bar**; anything higher means a
  removal is incomplete.
- `gateway.sh test test/screen_widget_test.dart test/stats_distance_estimate_test.dart` →
  `All tests passed!`
- `gateway.sh git-diff` → the diff touches only the three Predicted Files.

**Predicted Files (this phase)**: `lib/features/stats/stats_screen.dart`,
`test/screen_widget_test.dart`, `test/stats_distance_estimate_test.dart` — the phase's own diff, and
the only paths it wrote.

**Delivered Files (whole feature, 22 paths)** — restated in fix round 1 to match the diff. Phase 1:
the three above. Phase 2: `test/header_standardization_test.dart`,
`test/instrument_list_screen_test.dart`, `test/fuel_row_screen_test.dart`,
`test/records_and_trends_screen_test.dart`, `test/nutrition_trend_screen_test.dart`,
`test/stats_legacy_removal_test.dart` (new), plus `test/entry_identity_summary_test.dart` — outside
the Predicted Files and disclosed in the log (entry 8): its S-858 Stats half asserted the deleted
cardio card's `Distance:` / `Pace:` rows, so both assertions flip to `findsNothing` and no production
file changed for it. Phase 3: the eleven docs the doc-falsification sweep corrected, each because it
carried a claim that a removed Stats section still renders — `docs/stats_screen.md` and
`docs/README.md` (the rewritten feature doc and its index row), plus `docs/app_philosophy.md`,
`docs/data_models.md`, `docs/design_system.md`, `docs/distance_source.md`,
`docs/navigation_and_screens.md`, `docs/profile_and_measurements.md`, `docs/records_and_trends.md`,
`docs/session_summary.md` and `docs/widget_catalog.md`. No `lib/` file beyond `stats_screen.dart`;
an out-of-bounds file is a finding.

**Predicted intermediate state (declared, not a defect):** five test files still assert the legacy
sections and therefore fail until Phase 2 — `test/header_standardization_test.dart`,
`test/instrument_list_screen_test.dart`, `test/fuel_row_screen_test.dart`,
`test/records_and_trends_screen_test.dart`, `test/nutrition_trend_screen_test.dart`. Do not "fix"
them by editing the screen back. Phase 1's Done Criteria name the two suites that must be green.

**Phase 1 verification notes (Conductor):** _added after the phase is reported complete._

### Phase 2: the rest of the test churn + the unreachability guard (@developer)

15. [ ] `test/header_standardization_test.dart` — retire 2643–2688 (S-005's STRENGTH header-chip
   assertions; the chip's live coverage is `test/instrument_list_screen_test.dart:562` and
   `test/fuel_row_screen_test.dart:744–757`). Update S-018 (2689–2738): its expected eyebrow list
   `['ALL TIME','STRENGTH','CARDIO','NUTRITION']` becomes exactly the eyebrow labels the fixture's
   data produces — `'ALL TIME'` plus one `OmniCardHeader(title: section.section.label)` per
   Instruments section (`instrument_list.dart:75`). Derive the list from the fixture, not from this
   plan, and record the derivation in the Assumption Log. Keep S-004 (2626–2641) — its
   `find.text('STRENGTH')`/`'CARDIO'`/`'NUTRITION'` `findsNothing` assertions are still true.
16. [ ] `test/instrument_list_screen_test.dart` — at ~600–613 flip `Key('stats_legacy_sections')` from
   `findsOneWidget` to `findsNothing`, flip all five legacy section titles to `findsNothing`, and keep
   `ALL TIME` `findsOneWidget`. At 685–705 (S-1015, "both layouts on screen at once"): rename the test
   to the Instruments-only premise, keep the ordering assertion between live neighbours (the
   Instruments list above `ALL TIME`… read the file and re-target to the live pair), and replace the
   legacy-header loop with an absence loop. Line 562 (the header-chip coverage) stays.
17. [ ] `test/fuel_row_screen_test.dart:539–542` and `:558–561` — replace
   `expect(find.byKey(const Key('stats_legacy_sections')), findsOneWidget)` with `findsNothing` **plus**
   `expect(find.text('ALL TIME'), findsOneWidget)` so the test still proves "the screen is not empty,
   the row is absent". Lines 768/786 read `computeProgressData()).window` — unchanged.
18. [ ] `test/records_and_trends_screen_test.dart` — in S-913 (group at 297) delete the Stats-side
   `RecentPRList` drag/assertions (~410–444) and the final `_textsUnder(find.byType(RecentPRList))`
   assertion, keeping the header tooltip/label assertions, the SESSIONS/TIME/STREAK pill assertions
   and the tap-through; assert the Records & Trends PR list inline instead. Reason: `RecentPRList` was
   rendered by the deleted STRENGTH section.
19. [ ] `test/nutrition_trend_screen_test.dart` — in the `S-1110(a)` group (203–236) both tests (209
   and 221) call `pumpStats` and then read the Stats screen's chart via `_chartData`, which the deleted
   NUTRITION card owned. Delete both tests and replace them with **one** test that pumps only the trend
   screen (`pumpTrend`) and asserts what the pair proved about it: `_chartData(tester, 'kcal')` has two
   line bars and `find.text('Target (kcal)')` is found. Keep `pumpStats` and the `stats_screen.dart`
   import — the S-1110(b) test at 260 uses them to prove the zero-session empty state wins over the Fuel
   row, and that stays live. Update the stale comments at line 1 and line 31 (they describe the Stats
   NUTRITION card as a host). If `_actuals` or `_seedNutrition` loses its last reader, delete it too.
20. [ ] **Create `test/stats_legacy_removal_test.dart`** — the guard (D-606, D-610). Two groups:
   - `S-1209 source guard`: read `lib/features/stats/stats_screen.dart` with `File(...).readAsStringSync()`
     (the S-836 pattern) and assert the absence of every string in D-606's list, plus no km↔mi
     conversion literal.
   - `S-1208 behavioural guard`: pump the Stats screen for S-1201's and S-1203's fixtures and assert
     every legacy title and the key are absent, and `find.byType(LineChart)` finds nothing (S-1210).
   Transcribe S-836's assertions into this file verbatim.
21. [ ] **Red proof (mandatory, evidence file).** A guard that has never failed proves nothing. Before
   the Done Criteria, run two inverse-edit mutations and record the exact output of each:
   - M-1: temporarily re-add `Column(key: const Key('stats_legacy_sections'), children: const [])` to
     the screen's children → the source guard and the behavioural guard must both FAIL → revert.
   - M-2: temporarily add a `const _miPerKm = 0.621371;` literal to the screen → the source guard must
     FAIL → revert.
   Confirm after each revert that the suite is green again. Record both in the evidence file's
   red→green table.
22. [ ] Run the Done Criteria.

**Done Criteria** (run until green):
- `gateway.sh format` on every file this phase touched.
- `gateway.sh lint` → no errors, total **196** (≤199 is the bar).
- `gateway.sh test` → the whole suite, `All tests passed!`. Record the final `+N ~1` line in the
  evidence file and reconcile N against the retirement list at the **name level**; the current line
  and the name-level reconciliation after both fix rounds are in the evidence file's "Fix round 1"
  table.
- `gateway.sh test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` → green, and
  `gateway.sh git-diff -- test/in_session_pr_toast_test.dart test/pr_toast_test.dart` → empty.
- `gateway.sh git-diff` → the diff touches only the Predicted Files.

**Predicted Files**: `test/header_standardization_test.dart`, `test/instrument_list_screen_test.dart`,
`test/fuel_row_screen_test.dart`, `test/records_and_trends_screen_test.dart`,
`test/nutrition_trend_screen_test.dart`, `test/stats_legacy_removal_test.dart` (new), plus
`test/entry_identity_summary_test.dart` — the fifth file the retirement reached, whose S-858 Stats
half asserted the deleted cardio card (log entry 8); the eleven doc corrections are Phase 3's and the
whole delivered set is declared under Phase 1. No production file changes in this phase.

**Governor action (after Phase 2 is green):** delete `test/stats_distance_estimate_test.dart` — its
remaining content is S-836, transcribed into `test/stats_legacy_removal_test.dart` in step 20; every
other test in it asserted the deleted cardio card. No agent may delete it.

**Phase 2 verification notes (Conductor):** _added after the phase is reported complete._

### Phase 3: the doc, the sweep, the plan bookkeeping (@developer)

23. [x] Rewrite `docs/stats_screen.md` (679 lines / 37,999 bytes today) as the description of the
   post-4c screen (D-611). Required shape — Overview; Navigation Entry Point; What the Screen
   Displays; the `ALL TIME` card; the Instruments list (delegating detail to
   `docs/modality_based_exercise_ui.md` and `docs/widget_catalog.md` rather than restating it); the
   Fuel row; the empty state; the loading state; the Records & Trends entry point; Effort-Type Keying
   (kept — 4a D-403); Selection Window (kept — the window is still resolved once and shared); Data
   Loading (which service calls remain: `computeTotals`, `computeProgressData` for the window,
   `computeFuelSummary`, `computeInstrumentSections`); Key Constants (only constants a live path
   uses — verify each by reading the code); Core Files; Related Documentation. Delete the STRENGTH,
   CARDIO, ISOMETRIC, SPORTS, NUTRITION, Scrollable Charts and any other section that describes
   removed surface. Keep it ≤ 64 KiB (`test/docs_indexing_contract_test.dart`).
24. [x] `docs/README.md` — rewrite the Stats Screen row (~line 69) to the new one-line summary. Leave
   the "**Nutrition** — no dedicated feature doc yet ⚠️" row alone: 4c2 creates that doc (D-652).
25. [x] Residue sweep: prove no reader of the removed representation remains. Because agents cannot
   grep, the sweep is (a) the source guard's assertions, and (b) `gateway.sh git-diff` showing no
   change outside the Predicted Files, and (c) `gateway.sh test` green. Expected residual matches for
   the names `stats_legacy_sections`, `_buildStrengthSection`, `_buildCardioSection`,
   `_buildIsometricSection`, `_buildSportsSection`, `_buildNutritionSection`, `_ChartSeries`,
   `_LinearScale` in `lib/` and `test/`: **only** the string literals inside
   `test/stats_legacy_removal_test.dart` (the guard must name what it forbids).
26. [x] Fill the doc-claim table below by confirming each claim against its named test; fix the doc if
   a claim has no test (and never the reverse).
27. [x] Update this plan's Progress table and Assumption Log, and write the phase's evidence
   (suite output, doc size, the sweep's expected residuals) into the evidence file.

**Done Criteria** (run until green):
- `gateway.sh lint` → no errors, total 196 (≤199 is the bar).
- `gateway.sh test test/docs_indexing_contract_test.dart test/stats_legacy_removal_test.dart test/screen_widget_test.dart`
  → green.
- `gateway.sh git-diff` → `docs/stats_screen.md`, `docs/README.md`, this plan folder, and the nine
  further docs the doc-falsification sweep corrected, each because it carried a claim that a removed
  Stats section still renders: `docs/app_philosophy.md`, `docs/data_models.md`,
  `docs/design_system.md`, `docs/distance_source.md`, `docs/navigation_and_screens.md`,
  `docs/profile_and_measurements.md`, `docs/records_and_trends.md`, `docs/session_summary.md`,
  `docs/widget_catalog.md`.

**Predicted Files**: `docs/stats_screen.md`, `docs/README.md`, the nine docs named above, this plan
and its evidence file. No `lib/` or `test/` file is touched this phase.

**Phase 3 verification notes (Conductor):** _added after the phase is reported complete._

## Doc-claim → test table (`docs/stats_screen.md`)

| Claim in the rewritten doc | Test that proves it |
|---|---|
| The screen shows the `ALL TIME` card, the Instruments list and the Fuel row, and nothing else | `test/stats_legacy_removal_test.dart` (S-1208), `test/instrument_list_screen_test.dart` (absence + presence) |
| Zero completed sessions shows only the empty state | `test/screen_widget_test.dart` (zero-state test), `test/fuel_row_screen_test.dart` |
| The Fuel row is the last section and opens the nutrition trend screen | `test/fuel_row_screen_test.dart`, `test/nutrition_trend_screen_test.dart` |
| The header's chart action is labelled `Records & Trends` and opens it | `test/records_and_trends_screen_test.dart` (S-913) |
| No chart is drawn on the Stats screen | `test/stats_legacy_removal_test.dart` (S-1210) |
| No km↔mi conversion happens on this screen | `test/stats_legacy_removal_test.dart` (S-1209, S-836 transcribed) |
| Sections are assigned by the logged effort kind | `test/instrument_list_screen_test.dart`, `test/instrument_list_service_test.dart` (4b D-504) |
| The window is resolved once per load and shared | `test/screen_widget_test.dart` (kept tests), `test/instrument_list_screen_test.dart` |
| The app has exactly one `SegmentedButton` | `test/screen_widget_test.dart` (the kept test) |
| PRs are not shown on this screen; they live in Records & Trends | `test/records_and_trends_screen_test.dart`, `test/pr_toast_test.dart`, `test/in_session_pr_toast_test.dart` |

**Confirmed (Phase 3, step 26).** Every row was checked against the named test's assertions; each
claim in `docs/stats_screen.md` carries its test citation inline, and no claim lacked a test. One gap
was found and closed rather than recorded: the doc did not state that PRs are absent from this screen,
so the "nothing else is rendered" paragraph gained a sentence citing
`test/records_and_trends_screen_test.dart` (S-913).

## Files Affected (whole feature, as delivered — 22 paths)

| File | Phase | Change |
|---|---|---|
| `lib/features/stats/stats_screen.dart` | 1 | −1,104 / +~31: five sections, two chart classes, the legacy column, the adherence call, nine imports |
| `test/screen_widget_test.dart` | 1 | retire 21 tests (1,861 lines) in place; reword the one kept toggle test |
| `test/stats_distance_estimate_test.dart` | 1 | retire 5 groups; keep S-836 |
| `test/header_standardization_test.dart` | 2 | retire S-005's chip block; update S-018's label list |
| `test/instrument_list_screen_test.dart` | 2 | flip the legacy assertions to absence; rename S-1015 |
| `test/fuel_row_screen_test.dart` | 2 | flip the legacy key assertions |
| `test/records_and_trends_screen_test.dart` | 2 | S-913: drop the Stats-side PR list, assert Records & Trends inline |
| `test/nutrition_trend_screen_test.dart` | 2 | retire the Stats-side halves of S-1110(a) |
| `test/entry_identity_summary_test.dart` | 2 | **outside the Predicted Files** (log entry 8): its S-858 Stats half asserted the deleted cardio card's `Distance:` / `Pace:` rows, so both flip to `findsNothing` |
| `test/stats_legacy_removal_test.dart` | 2 | **new** — the guard |
| `docs/stats_screen.md` | 3 | rewritten for the post-4c screen |
| `docs/README.md` | 3 | Stats Screen row rewritten to the post-4c summary |
| `docs/app_philosophy.md` | 3 | the nutrition note named a `NUTRITION` card on the Stats screen |
| `docs/data_models.md` | 3 | `PRAchievement` was called a shared source of truth with the Stats screen |
| `docs/design_system.md` | 3 | the header-case table listed `STRENGTH` / `CARDIO` / `NUTRITION` on the Stats screen |
| `docs/distance_source.md` | 3 | the estimate-mark and pairing claims cited the removed Stats reader |
| `docs/navigation_and_screens.md` | 3 | the `StatsScreen` row listed the removed sections; the trend screen's row called itself the NUTRITION card |
| `docs/profile_and_measurements.md` | 3 | the Stats tile summary and a `ScrollableTrendChart` host claim |
| `docs/records_and_trends.md` | 3 | the PR list was called "the same list, in the same order, as the Stats screen's"; the `est.` marker rule cited the CARDIO section |
| `docs/session_summary.md` | 3 | two PR-definition claims named the Stats screen as a shared source |
| `docs/widget_catalog.md` | 3 | the nutrition card's Stats host, the Fuel row rename, the chart's doc pointer |
| `test/stats_distance_estimate_test.dart` | Governor | deleted after Phase 2 |
| `docs/plans/2026-09-30-04-stats-pr4-index.md` | planner | 4c row → 4c + 4c2 |

## Governor actions

| Path | When | Why |
|---|---|---|
| `test/stats_distance_estimate_test.dart` | after Phase 2 is green, before Phase 3 | The only test it still holds (S-836) was transcribed into `test/stats_legacy_removal_test.dart`; everything else tested the deleted cardio card. No agent may delete files. |

## Notes

- **Intermediate state (declared).** After 4c and before 4c2, `StatsProgressService.computeProgressData()`
  still computes the cardio / isometric / sports projections and the nutrition trend, and
  `StatsProgressData` still carries them. Nothing renders them; the cost is a wasted pass over the
  history during the Stats load. 4c2 removes them (D-651). This is why 4c can be the screen half
  alone without leaving the app broken.
- **Optional finer seam inside 4c** (if Phase 1 proves too large for one executor turn): STRENGTH
  first, then CARDIO + ISOMETRIC + SPORTS + NUTRITION. Trade-off: the same five test files are edited
  twice, and the tests that iterate over "all Stats charts" straddle the two halves. Recorded here so
  the owner can choose it without re-planning; **do not** grow this plan to absorb it.
- **Large test files: the approach chosen, per file, with line counts** (D-612). Each file keeps live
  tests, so no file is emptied and no placeholder is needed; the retirement is in-place, bottom-up,
  in ≤100-line `edit` chunks.

  | File | Total lines | Retired | Kept | Approach |
  |---|---|---|---|---|
  | `test/screen_widget_test.dart` | 12,018 | 1,861 lines / 21 tests (five ranges: 4001–4913, 3827–3973, 3672–3826, 3542–3591, 2863–3458) | 10 `StatsScreen` tests + six other groups | in-place; the file is 3× the Stats group and six unrelated groups share it — a new file would mean retyping ~2,700 lines of unrelated test code for no coverage gain |
  | `test/stats_distance_estimate_test.dart` | 553 | 10 tests (everything but S-836) | S-836, transcribed into the new guard | the file's subject (the km↔mi source guard) outlives it; the one live test moves to `test/stats_legacy_removal_test.dart` and the **Governor deletes** the emptied file (D-610) |
  | `test/header_standardization_test.dart` | 2,783 | 1 test (S-005, 2643–2688) | 2 in the group (S-004, S-018 — S-018 updated) | in-place |
  | `test/instrument_list_screen_test.dart` | 892 | 0 (2 assertions flipped to `findsNothing`) | all | in-place |
  | `test/fuel_row_screen_test.dart` | 798 | 0 (2 assertions flipped) | all | in-place |
  | `test/records_and_trends_screen_test.dart` | 681 | 0 (S-913 loses its Stats-side block) | all | in-place |
  | `test/nutrition_trend_screen_test.dart` | 354 | 0 (S-1110(a) rewritten `pumpStats` → `pumpTrend`) | all | in-place |

  Why not "empty the file and let the Governor delete it" anywhere: only `test/stats_distance_estimate_test.dart`
  is wholly about the removed surface, and its single live test (S-836) is transcribed first. Every
  other file guards live behaviour, so deleting it would delete coverage.
- **`test/navigation_contract_enforcement_test.dart`** asserts routes, not Stats section content; it
  must pass untouched. If it fails, the removal changed something it should not have — that is a
  finding, not an edit target.
- **`test/screen_overflow_contract_test.dart`** renders the Stats screen at three phone sizes and
  seeds no food, so the Fuel row never enters the tree; the removal only shortens the screen. It must
  pass untouched. (The Fuel row's own narrow/large-text coverage is 4c2's carried item.)
- **Legacy handling**: none. D-402 (series) — no user data exists, so no migration and no feature flag.

## Progress

| # | Item | Phase | Result |
|---|---|---|---|
| 1 | The five sections, the legacy column, the two chart classes and the nine imports leave `stats_screen.dart` | 1 | done |
| 2 | `_progressData` → `_window`; `_nutritionAdherence` deleted | 1 | done |
| 3 | 21 `StatsScreen` tests retired in place; 10 kept (one reworded) | 1 | done |
| 4 | `test/stats_distance_estimate_test.dart` reduced to S-836 | 1 | done |
| 5 | The five other test files converted to absence assertions | 2 | done |
| 6 | S-913 re-pointed at Records & Trends | 2 | done |
| 7 | `test/stats_legacy_removal_test.dart` created, red-proven by M-1 and M-2 | 2 | done |
| 8 | Full suite green; lint 196; PR parity files untouched | 2 | done |
| 9 | `test/stats_distance_estimate_test.dart` deleted (Governor) | between 2 and 3 | done (file absent from the tree and from `git-diff`) |
| 10 | `docs/stats_screen.md` rewritten; README row updated | 3 | done |
| 11 | Doc-claim table confirmed; residue sweep clean | 3 | done |

**Phase 1 status: Complete.** Steps 1–14 done; step 13 is N/A (see the log). Lint 196 / 0 errors,
the two in-scope suites green, the diff inside the three Predicted Files. The full suite is red until
Phase 2 by design — five test files still assert the removed sections.

**Phase 2 status: Complete.** Steps 15–22 done. `gateway.sh test` → `+3233 ~1: All tests passed!`
(the line after both fix rounds; the name-level reconciliation is the evidence file's "Fix round 1"
table), lint 196 / 0 errors, the PR-toast parity files untouched. One file outside the Predicted
Files was edited — `test/entry_identity_summary_test.dart` (see log entry 8); no production file
changed.

**Phase 3 status: Complete.** Steps 23–27 done. `docs/stats_screen.md` rewritten to version 3.0 and
under the 64 KiB ceiling, `docs/README.md`'s Stats row rewritten, the doc-claim table confirmed, and
the residue sweep clean (the eight forbidden names survive only as string literals inside
`test/stats_legacy_removal_test.dart`). One deviation: the sweep widened the diff beyond Phase 3's
Predicted Files — nine further docs carried claims that the removed sections still render, and each
was corrected (see log entry 10). No `lib/` or `test/` file was touched this phase.

## Assumption Log

Executors append here (decision, options considered, choice + why; ≤3 lines each). The Conductor
marks each RATIFIED (promoted to a D-x) or REVERT (remediation) at verification. An empty log after a
phase this size is itself a finding.

**1. Orphaned test helpers (D-616).** Deleting the 2863–3458 range orphaned `seedStrengthDays` and
`seedCardioDays`; once the whole group went, `seedTimedEffort` and `seedSetEffort` lost their only
callers too. Choice: delete all four, so the file carries no `unused_element` warning.

**2. Retirement range 2863–3458 stopped at 3427.** Lines 3429–3457 are the Effort-rating banner plus
`seedFeelingSession`, read by the five kept feeling-guard tests (3459/3510/3592/3624/3640). Kept;
every test in the range still retires, so the item's intent is unchanged.

**3. Step 11a assertion strengthened.** `find.byType(SegmentedButton<dynamic>)` compares exact runtime
types and cannot match a `SegmentedButton<T>`. The reworded test also asserts
`find.byWidgetPredicate((widget) => widget is SegmentedButton)` findsNothing. Both pass — no surviving
surface renders a toggle, so S-1211's premise holds.

**4. Dangling banners deleted with their ranges.** The `// ── Phase E: Isometric and Sports sections`,
`// Plan: unify-chart-scrolling-popup — Phase 1 scenarios` and `// D-1: Segmented toggle label width
contract verification` banners each named a removed surface. Deleted rather than left pointing at
nothing.

**5. S-018's eyebrow list derived from the fixture: `['ALL TIME']`.** Step 15 asks for the eyebrow
labels the fixture's data produces. `seedCompletedStrengthSession` logs a session and no effort, so
the Instruments list has no section to draw and `ALL TIME` is the screen's only eyebrow
(`OmniCardHeader(title: section.label)` is the section-header form — `instrument_list.dart:75`).
Choice: assert the single live label rather than seed an effort the plan did not ask for.

**6. S-1012 / S-1015 and the two chip counts changed beyond the plan's wording.** S-1012's title named
a layout the screen no longer has, so it is retitled to the absence premise; S-1015's ordering pair
re-targeted to the live neighbours (`ALL TIME` above `Resistance`); the `stats_window_chip` count in
`instrument_list_screen_test.dart` and `fuel_row_screen_test.dart` went 5 → 1. All are consequences
of Phase 1, not new assertions.

**7. Guard fixture simplifications.** The guard seeds the three states (all kinds of history; sessions
but no food; zero sessions) directly and omits S-1201's `TrainingPeriod` — the absence assertions do
not depend on the window label. Mock seeds food and sessions on `initialize()`, so the "no food" and
"zero sessions" fixtures delete both; `seedTimedEntries` would overwrite a capability-rich exercise,
so the guard writes its timed effort through `createEffort` + `createTimedInstance` instead.

**8. FINDING — `test/entry_identity_summary_test.dart` (S-858) also asserted a removed surface.** Its
Stats half asserted `Distance: 5.50 km` and `Pace: 327 s/km`, both built by the cardio card Phase 1
deleted (`git-diff` shows the two removed `'Distance: ${…}'` / `'Pace: ${…} s/$distUnit'` lines), so
the full suite could not be green. The file is not in this phase's Predicted Files. Choice: apply
steps 15–19's method — flip both to `findsNothing`, retitle the test and keep the Summary half and
the leftover-row assertion intact. The `Stats` import and `_pumpStats` stay used.

**9. Finder quirk observed during M-1.** A zero-height widget as the **leading** child of the Stats
`ListView` is not reported by `find.byKey` (the sliver onstage filter skips it); the same widget at the
end of the list, or a non-zero-height widget at the front, is found. So the first M-1 form — the key on
a `Column` carrying the five legacy titles — failed 7 of 8 tests (`+1 -7`: the fragment source guard and
all six behavioural absence loops) while its key check passed; the minimal form (the key on an empty
`Column`) fails 5 of 8 (`+3 -5`). The mutation was re-applied in the minimal form so that the key check
itself fails on both harnesses, and the source guard catches the leading case regardless. Recorded as a
note, not a defect.

**5. Step 13 is N/A.** The two candidate tests (3827/3906) build their own `SegmentedButton` inside an
isolated `MaterialApp` and assert on Flutter's built-in; the planner's correction retires both. No
kept test asserts a removed surface, so there was nothing to decide.

**6. `test/stats_distance_estimate_test.dart` header rewritten.** The old header described S-831–S-837
behaviour (pace counting, estimated markers) that no longer exists. Replaced with the surviving S-836
guard and a note that Phase 2 transcribes it.

**7. Lint 196, not the predicted 197.** The plan's own subtraction is `199 − _ChartSeries − the two
unused locals = 196`, and the run reports 196 with 0 errors. The ≤199 bar holds; no removal was skipped.

**10. The sweep widened the diff past Phase 3's Predicted Files.** Step 25's residue sweep is a docs
sweep as much as a code sweep: nine docs outside the Predicted Files asserted that a removed Stats
section still renders (`distance_source.md`, `records_and_trends.md`, `widget_catalog.md`,
`navigation_and_screens.md`, `design_system.md`, `app_philosophy.md`, `profile_and_measurements.md`,
`session_summary.md`, `stats_screen.md`'s own inbound anchors). Choice: correct each stale claim —
leaving them is exactly the residue the step exists to remove — and disclose the widened diff here and
in the final response rather than silently exceeding the Done Criterion.

**11. What left the doc with the sections.** The rewrite drops the nutrition-trend card's internals
(target-line stepping, single-point fallbacks, legend, `kNutritionTrendDays`), the Scrollable Charts
wrapper internals, the effort-rating subsection with its "Deliberate non-features" list, and the
PR-parity subsection. The PR-parity invariant survives in `docs/session_summary.md`; the Instruments
list delegates row internals to `docs/widget_catalog.md` per step 23.

**12. `docs/distance_source.md`'s three verification claims re-pointed.** Each cited the Stats screen
as a reader of the km↔mi conversion; that reader is gone. Choice: narrow each to the live surfaces
and cite the test that shipped — `test/instrument_list_screen_test.dart` (`S-1001`), whose `est.`
assertion proves the live estimate mark — rather than delete the claims; the conversion still has
real readers. (Amended in fix round 1: this entry first named the S-1209 guard, which proves absence,
not the live readout — review finding 6.)

**13. `docs/stats_best_load_investigation.md` left unchanged.** It is a dated, investigation-only
record of a one-off analysis, not a description of current screen behaviour, so its references to
removed sections are history rather than a stale claim. Flagged for the reviewer to overturn if they
disagree.

**14. The Stats loading state stays undocumented.** The screen renders a spinner while its data
loads, but no test asserts it, and the documentation standard forbids prose describing untested
behaviour. Choice: leave the loading state out of `docs/stats_screen.md` rather than add an
unverified claim or a new test outside this round's scope.

## Feedback

Findings: `2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.review.md` (review 1, 6 substantive).

Fix checklist:
- [x] Restate the three scope declarations (finding 1) to match the delivered 21-path diff.
- [x] Correct the recorded final test line to `+3229 ~1` and the residual to 2 (finding 2).
- [x] Delete the false clause in the Stats screen's progress-data comment (finding 3).
- [x] Remove the icon and restated streak threshold from `docs/stats_screen.md` (finding 4).
- [x] Replace or test-back the new loading-state prose in `docs/stats_screen.md` (finding 5).
- [x] Amend Assumption 12 to the citation that shipped (finding 6).
- [x] Lost guard 1: re-add the Records & Trends PR weight-unit test retired with the Stats card.
- [x] Lost guard 2: re-add the Calories / Macros single-line label test retired with the NUTRITION card.
- Carry to 4c2: finding 8. Accept as-is: finding 7.

Round 2 (re-review after fix round 1): `2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.review.md`
→ `## Round 2` — 1 warning, 1 nit. F-1 and F-3…F-8 verified; lint 0 errors / 196 issues, tests
`+3233 ~1`.

Fix checklist (Round 2):
- [x] Restate the recorded suite line and the name-level reconciliation to `+3233 ~1` (3,234 cases) in
      the Phase 2 status and the Phase 2 Done Criteria, or point them at the evidence's fix-round table
      (Round 2 finding 1 — F-7/F-8 landed after the Round 1 correction, so the plan's only recorded line
      is now four runs short).
- [x] Drop the "one of two shapes" count in `docs/stats_screen.md` (or scope it to the settled body), or
      record that the loading state stays undocumented because no test covers it (Round 2 finding 2, nit).

## Open questions (with defaults — proceed on the defaults unless the owner says otherwise)

1. **Is 4c allowed to be the screen only?** Default: yes (D-601) — the brief's 4c also retires the
   service and the models, which pushes the production diff to ~1,770 lines, over the 1,500-line hard
   limit; the split puts the service, the models, the carried items and the docs in 4c2. The user-visible
   outcome and the ship order are unchanged.
2. **The PR scan set.** Default: keep `topLifts` as the PR scan set (D-605, Option A′), because the
   `allPRs` loop runs inside the lift loop and pack item 6 requires the PR parity suites to pass
   unmodified. Alternative (B): recompute PRs over every exercise in full history — changes what the
   user sees in Records & Trends (an all-time-only exercise would start producing PRs), so it needs an
   owner decision and a separate plan.
3. **Deleting `StatsWindow.hasData` and `StatsWindow.empty`** (unused anywhere in `lib/` and `test/`).
   Default: delete them in 4c2 with the rest of the model retirement; if the owner prefers to keep the
   public surface, they stay and nothing else changes.
