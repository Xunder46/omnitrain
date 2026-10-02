# Stats PR 4 series — The new Stats structure (index)

> Status (2026-10-01, after the 4c split): **4a** is DONE (implemented on `develop`). Item 5 is split into
> three PRs — **4b** (the Instruments data), **4b2** (the Instruments list on the Stats screen) and **4b3**
> (the Fuel row) — and item 6 into two — **4c** (the legacy sections leave the screen) and **4c2** (the
> service and model retirement, the four carried items, and the docs). All five remaining plans are
> **READY**. Plan each remaining PR when its turn comes, against the code as it is then
> (`.github/agents/pr_scope_budget.md`).
>
> Source: `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` items 5 and 6, and the
> pack's Suggested Batching row "PR 4 = items 5 + 6". The owner delegated the split to the planner.
> Implementer: Copilot with DeepSeek V4.1 Flash, running locally in this checkout. Plans are written for a
> small model: numbered one-concern steps, exact strings, commands and greps, and rules inline.
> Next handoff: Copilot implements 4b (the data), then 4b2 (the list), then 4b3 (Phase 1 — the NUTRITION card
> extraction — then Phase 2 — the Fuel row), then 4c (the screen), then 4c2 (the service, the models, the
> carried items and the docs); each is followed by `/code-reviewer`.
> Evidence for 4a: `2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.evidence.md`.
> Evidence for 4b: `2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.evidence.md`.
> Evidence for 4b2: `2026-10-01-04b2-stats-pr4b2-instruments-list-plan/2026-10-01-04b2-stats-pr4b2-instruments-list-plan.evidence.md`.
> Evidence for 4b3: `2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.evidence.md`
> (the planner's baselines are there; executors append).
> Evidence for 4c: `2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.evidence.md`.
> Evidence for 4c2: `2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.evidence.md`.
> Each plan is a folder named after its stem, holding `<stem>.md`, `<stem>.evidence.md` and (after review)
> `<stem>.review.md`.

## Why six PRs

Items 5 and 6 together are one PR in the pack's batching table, but they are over the scope budget
(`.github/agents/pr_scope_budget.md`): the combined estimate is about 2,500 production lines across 7
phases, against hard limits of 1,500 lines and 5 phases. So the series is split, and the split is ordered
so that `develop` stays shippable after every PR.

Item 5 is itself two halves that share nothing but the screen — the Instruments list reads exercise
metrics and `SensorSummary`; the Fuel row reads `ConsumedFood`, `NutritionTarget` and session completion.
Planned as one PR the union is 5 phases and over 500 plan lines: two soft budget signals, which is a
split.

The first split attempt (4b = the Instruments list, 4b2 = the Fuel row) still produced a 4b plan of **1,016
lines** against the 800-line hard limit. It was therefore split again along the one seam it already had:

- **4b — the Instruments data.** The bulk sensor-summary read, the two value types,
  `computeInstrumentSections`, the two shared formatters. No visible change on screen.
- **4b2 — the Instruments list.** The four widgets, the cap and `Show all (n)`, the legacy wrapper key, the
  legacy test re-stabilisation. The visible half.
- **4b3 — the Fuel row.** A Fuel section of its own on the Stats screen, plus the extraction of the
  NUTRITION card into the trend screen the row opens. Two phases, both `@developer`; every phase named
  here depends on 4b2.

4b is independently shippable and green on its own (a repository read with no reader yet), which is what
makes the second split safe.

### Why item 6 is two PRs (4c + 4c2)

Item 6 planned as one PR measures **~1,770 production lines** — the screen removal (−1,104 in
`stats_screen.dart`), the service retirement (−487 in `stats_progress_service.dart`) and the model
retirement (−135 in `stats_progress.dart`) — against the 1,500-line hard limit
(`.github/agents/pr_scope_budget.md` §1). The split runs along the layer seam, which is the one seam the
work already has: nothing on screen changes in either PR, and the same user-visible outcome lands in the
same release (4a D-402).

- **4c — the screen.** The five sections, their widgets, their formatters and their empty state leave
  `stats_screen.dart` (~1,135 lines with its test churn and `docs/stats_screen.md`'s rewrite). The old
  layout becomes unreachable, proved by a new guard. Shippable on its own: the screen is complete and the
  suite is green, the service simply computes projections nothing reads.
- **4c2 — the service, the models, the carried items and the docs.** The cardio/drill/round passes, their
  projections and the nutrition-trend projection leave the service; the types and fields only they produced
  leave the model; the four items carried out of 4b3's review land; `docs/nutrition.md` is written and the
  doc set is reconciled (~1,015 lines).

The declared intermediate state (4c green, 4c2 not yet done) is invisible to the user: the service does
work whose result is never read. It is recorded in 4c2's Notes.

## Branch policy (owner)

- Only `develop` and `main` persist.
- All work happens directly on `develop`. Plans must never create, switch or delete branches.
- Executors never commit, stage, merge or push; the owner does.

## PRs in order

| PR | Scope | Depends on | Plan |
|---|---|---|---|
| **4a** | Phone, **additive**: the shared exercise-metric layer, the **Exercise Progress** view, and the **Records & Trends** screen with the Stats header's chart-icon entry point.<br>• a bulk round-instance read on the repository (there is none today);<br>• the per-exercise native value and all-time best for all four effort kinds, computed once and reused;<br>• Records & Trends: all-time totals, the existing Recent PRs moved unchanged, and a searchable list of every exercise ever logged, grouped into the four sections, each showing its all-time best and when it was last trained;<br>• Exercise Progress: the full-history chart, the all-time best, and the recent-sessions list;<br>• nothing is removed — the old Stats sections stay exactly as they are. | — | `2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.md` |
| **4b** | Phone, **invisible**: the **Instruments data** the list needs.<br>• one new repository read, `getSensorSummariesBySession()`, on the interface with a Hive implementation and a Mock twin — the first bulk read of `SensorSummary` in `lib/`;<br>• the two value types (`InstrumentSectionData`, `InstrumentRow`);<br>• `computeInstrumentSections({required StatsWindow window})`: sections ordered by distinct training days, rows ordered by training days then name then id, each row's native value, its previous-range value for the change indicator, its cadence and its average heart rate;<br>• two shared formatters (`nativeSecondaryLabel` moved with byte-identical output, `formatNativeChange`).<br>Nothing changes on screen; this PR is green and shippable on its own. | 4a | `2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.md` |
| **4b2** | Phone, **additive**: the **Instruments list** on the main Stats screen.<br>• the four sections — Resistance, Cardio, Isometric, Sports — each listing every exercise trained in the window, up to 5 rows with "Show all (n)";<br>• each row: name, native value, change against that exercise's own previous comparable value, a trend line;<br>• the list renders **between the ALL TIME card and the old sections**, wrapped legacy children and all (D-503). The old Stats sections stay for one more PR. | 4b (its Phases 1–2 merged), 4a | `2026-10-01-04b2-stats-pr4b2-instruments-list-plan/2026-10-01-04b2-stats-pr4b2-instruments-list-plan.md` |
| **4b3** | Phone, **additive**: the **Fuel section** on the main Stats screen, in **2 phases** (both `@developer`).<br>• **Phase 1** — the extraction: the NUTRITION card body moves into `NutritionTrendCard` (`lib/features/nutrition/widgets/`) with a new full-history `NutritionTrendScreen`, the three chart primitives it shares with the staying legacy charts get one home in `lib/widgets/chart/chart_primitives.dart`, and the Stats NUTRITION section renders the same extracted card. A move, not a rewrite — S-1110(a) is the proof.<br>• **Phase 2** — the row: a `Fuel` section of its own between the Instruments sections and the legacy sections, with 7-day averages over logged days only, against the user's own target (and against the previous 7 days), a `'<n>/7 days logged'` indicator and a training-day vs rest-day split; hidden after 14 days without logs, and the zero-session empty state wins over it; tapping it opens the Phase 1 screen with its Calories / Macros toggle.<br>• Nothing is removed — the old NUTRITION card stays for 4c (about 740 lines leave `stats_screen.dart`, ~810 including the new primitives and screen). | 4b2 (shares the row/header widgets and the screen edit), 4a (`computeNutritionTrend`) | `2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.md` (plan, READY) |
| **4c** | Phone, **removal**: delete the STRENGTH, CARDIO, ISOMETRIC, SPORTS and NUTRITION sections from the Stats screen — the sections, the chart series, the scale, the formatters, the section empty state and the nine imports only they used (~1,135 lines with its tests). The screen is left with the ALL TIME card, the Instruments list and the Fuel row.<br>Update or retire their tests, add a guard proving the old layout is unreachable from anywhere in the app, and rewrite `docs/stats_screen.md` for the screen that is left.<br>**Does not touch the service or the models** — that is 4c2. | 4b, 4b2, 4b3 | `2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan/2026-10-01-04c-stats-pr4c-remove-legacy-sections-plan.md` |
| **4c2** | Phone + docs, **invisible**: the service and model retirement, the four items carried out of 4b3's review, and the doc reconciliation.<br>• `computeProgressData()` keeps its name, signature and its three live outputs (`topLifts`, `recentPRs`, `window`) and loses the cardio/drill/round passes, their projections and the nutrition-trend projection; `stats_progress.dart` loses `CardioTrendPoint`, `CardioProgress`, `DrillProgress`, `RoundProgress`, the four removed fields, `.empty` and `hasData`;<br>• `scrollable_trend_chart.dart` moves byte-identically to `lib/widgets/chart/` and its four importers are repointed;<br>• the Fuel row gains a narrow-width case, a large-text-scale case and an accessibility label;<br>• `docs/nutrition.md` is written for the first time, `docs/data_models.md` gains the Fuel summary, and every doc that still describes a removed section, constant or model is reconciled. | 4c (its screen removal must land first), 4a | `2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan/2026-10-01-04c2-stats-pr4c2-followups-and-docs-plan.md` |

### Carried out of 4b3's review (now 4c2's Phase 2)

- Move `lib/features/stats/widgets/scrollable_trend_chart.dart` to `lib/widgets/chart/`, so the nutrition card no longer imports from the Stats feature (4b3 review finding 6) — 4c2 D-658.
- Add a narrow-width and a large-text-scale rendering case for the Fuel row to `test/fuel_row_screen_test.dart` (finding 7) — 4c2 D-660.
- Add `lib/core/models/fuel_summary.dart` to the `docs/data_models.md` code-reference table (finding 8) — 4c2 D-663.
- Give the Fuel row's tappable `InkWell` an explicit accessibility label and assert it (finding 11) — 4c2 D-659.

These were listed as "Carried into 4c" while item 6 was one PR; the split moved them to 4c2, whose only
production surfaces they touch.

## Shared decisions (defined once in the plans named; later PRs cite them and never restate them)

- **4a D-401: the split.** Items 5 and 6 ship as 4a → 4b → 4b2 → 4b3 → 4c (the splits are 4b D-501).
  4a, 4b, 4b2 and 4b3 add; only 4c removes.
- **4c2 D-651 supersedes D-401's split chain.** Item 6 is two PRs, not one: 4c (the screen, 4c D-601) and
  4c2 (the service, the models, the four carried items, the docs). Measured together they are ~1,770
  production lines against the 1,500-line hard limit. The chain is therefore 4a → 4b → 4b2 → 4b3 → 4c →
  4c2, and 4a's "only 4c removes" becomes "only 4c and 4c2 remove".
- **4a D-402: single release.** Inherits 3b D-332. No user data exists, so no migration, no old-data
  handling, no backward compatibility and no feature flag anywhere in this series.
- **4a D-403: one section per exercise.** Resistance / Cardio / Isometric / Sports, assigned by the effort
  kind the exercise was actually logged under (pack D-3, D-15), never by the session's modality label.
  4a evaluates this over all history; 4b over the current window.
- **4a D-405 … D-408: the native value per effort kind** — Resistance, Cardio, Isometric, Sports. These
  are the values the Instruments rows (4b2), Records & Trends (4a) and Exercise Progress (4a) all show.
- **4a D-409: an all-time best is descriptive.** It creates no PR event, no toast and no Summary row.
  The PR path is untouched by this series, so the PR parity tests stay as they are.
- **4a D-413: the header entry point.** An `OmniBackHeader` action with an accessible label, routed with
  `OmniNavigator` (`docs/navigation_contract.md`).
- **4b D-501: item 5 is split three ways.** 4b is the Instruments data, 4b2 is the Instruments list, 4b3 is
  the Fuel row. 4b, 4b2 and 4b3 add; only 4c removes. See "Why five PRs".
- **4b2 D-503: additive, with one keyed boundary.** The five old sections and their constants are unchanged;
  the whole legacy child list is wrapped in one `Column(key: Key('stats_legacy_sections'))` so tests can
  address it unambiguously while both layouts are on screen.
- **4b D-504: section ordering supersedes 4a D-403 for the Instruments list only.** The Instruments
  sections sort by distinct training days in the window, descending. Records & Trends keeps D-403's fixed
  order. Both lists still assign a section by the logged effort kind, never by the session's modality.
- **4b D-516: one label source, one chip source.** The secondary-metric label (`nativeSecondaryLabel`, part
  a, in 4b) and the window chip (`StatsWindowChip`, part b, in 4b2) are each extracted to a single shared
  widget/function with byte-identical output, so a figure never reads two ways.
- **4b3 D-520 … D-534: the Fuel row.** Recorded in 4b3's plan: the 7-day window and its previous range,
  logged-days-only averaging, the training-day definition, the split, the target rules, the 14-day
  visibility rule, and moving the NUTRITION card into a new full-history screen (D-520…D-527), plus
  Iteration 1's own entries — the Fuel section's placement and chrome (D-528), its pinned anatomy (D-529),
  `computeFuelSummary` and `FuelSummary` (D-530, D-531), how D-526 is executed (D-532), the shared chart
  primitives' one home (D-533) and the doc ownership (D-534).
- **4c D-601 … D-616: the screen removal.** Recorded in 4c's plan: 4c is the screen half (D-601), the
  exact screen the PR leaves behind (D-602), the empty state winning (D-603), the screen holding the
  window rather than the data (D-604), `computeProgressData` keeping its outputs and `topLifts` staying
  the PR scan set so the PR path is untouched (D-605), the legacy layout proven unreachable twice —
  behaviourally and by a source guard (D-606), no chart left on the screen (D-607), `RecentPRList`
  leaving (D-608), the test-retirement rule (D-609), the km↔mi source guard transcribed into the new
  guard file (D-610), `docs/stats_screen.md` describing only the live screen (D-611), the bottom-up
  chunked deletion order (D-612), what the user loses and what replaces it (D-613), 4c's single
  production file (D-614), `scrollable_trend_chart.dart` staying put until 4c2 (D-615) and the
  analyzer bar (D-616).
- **4c2 D-651 … D-666: the service, the models, the carried items and the docs.** Recorded in 4c2's plan:
  the scope (D-651), `computeProgressData`'s kept surface (D-652), the model retirement list (D-653), the
  nutrition-trend tests repointed rather than deleted (D-654), the service test-retirement list (D-655), the
  untouched SQL contract (D-656), the repointed comment (D-657), the byte-identical chart move and its pinned
  import strings (D-658), the Fuel row's label (D-659) and its rendering cases (D-660), `docs/nutrition.md`
  (D-661), the reconciliation rule (D-662), the `docs/data_models.md` row (D-663), this index's own update
  (D-664), the analyzer bar (D-665) and the residue sweep (D-666).
- **4a D-416: `docs/stats_screen.md` is reconciled in 4a**, because the pack's D-13 requires it and 4a
  already touches that doc. 4b2 extends it with the Instruments list; 4c rewrites it for the screen that is
  left; 4c2 re-checks it for claims about the retired service and models.

## Series risks

- **Temporary duplicate content on `develop`.** Until 4c lands, Recent PRs and the nutrition trend appear
  on both the Stats screen and Records & Trends. This is expected, not a defect.
- **Two rounds of doc churn on `docs/stats_screen.md`** (4a, then 4b2, then 4c). Accepted: the pack's D-13
  requires the drift fixed, and 4a is the PR that makes the doc's "what Stats shows" claim wrong in a new
  way.
- **The old SPORTS chart reads timed instances, the new Sports value reads round instances.** They can
  disagree for the same session until 4c removes the old chart. See 4a Notes.
- **Two layouts on screen at once from 4b2 until 4c.** The Instruments list sits above the five old chart
  sections, so the screen is longer and the same information can appear twice in different shapes. The
  Instrument headers are title case (`Resistance`) against the legacy uppercase ones (`STRENGTH`), which
  keeps them distinguishable on screen and in tests. Expected, not a defect.
- **Existing widget tests pump at a fixed surface height.** The taller list pushes legacy content below the
  fold, where `find.text` cannot match it. 4b2 raises those tests' surface heights and changes no assertion.
- **Small-model implementer.** Every plan must keep its rules inline and its steps mechanical.
- **A declared intermediate state between 4c and 4c2.** After 4c the service still computes the
  cardio/drill/round projections and the nutrition-trend projection that nothing reads. It is invisible and
  harmless (wasted work only), it is recorded in 4c2's Notes, and 4c2's Phase 1 removes it. If the two PRs
  are separated by more than a release, note it in the release notes; no other action is needed.
- **The analyzer bar is "none new":** 199 issues with 0 errors on the tree 4a starts from.

## Scope check (2026-09-30)

**4a** is 651 lines with 3 phases (Phase 1 is the @dba repository read; Phases 2 and 3 are @developer), one
track (the phone), 16 decisions, 16 scenarios, and about 1,000 predicted production lines. That is one soft
signal — length over 500 — and no hard limit, so it is within budget
(`.github/agents/pr_scope_budget.md` §1).

## Scope check (2026-10-01, for 4b / 4b2 / 4b3)

Measured by reading each file back. Budget: hard limits 800 plan lines, 5 phases, 1,500 predicted
production lines; soft limits 500 plan lines, 3 phases, 1 track, 20 decisions, 30 scenarios; **two or more
soft signals ⇒ split** (`.github/agents/pr_scope_budget.md` §1).

| PR | Plan lines | Phases | Decisions | Scenarios | Predicted production lines | Verdict |
|---|---|---|---|---|---|---|
| **4b** — the Instruments data | 598 | 2 | 12 (D-501, D-502, D-504…D-506, D-508, D-509, D-511…D-514, D-516a) | 11 (S-1002…S-1010, S-1013, S-1018) | ~370 | one soft signal (length); no hard limit — within budget |
| **4b2** — the Instruments list | 594 | 1 | 4 own (D-503, D-507, D-510, D-515) + 9 consumed from 4b | 7 (S-1001, S-1011, S-1012, S-1014…S-1017) | ~330 | one soft signal (length); no hard limit — within budget |
| **4b3** — the Fuel row | 666 | 2 | 15 (D-520…D-534; D-528…D-534 written with Iteration 1) | 12 (S-1101…S-1112) | ~1,240 (of which ~810 is the D-526 move) | one soft signal (length); no hard limit — within budget |

**The first split was not enough, and the second one was.** The superseded single 4b plan measured **1,016
lines** — past the 800-line hard limit — with 3 phases, 16 decisions and 18 scenarios. The second split runs
along the seam the plan already had (data before presentation), which is why nothing was renumbered and no
scenario or decision was rewritten: 4b takes the repository read, the service computation and the
formatters; 4b2 takes the widgets, the screen edit and the test re-stabilisation; 4b3 keeps the Fuel row's
recorded decisions and fixtures.

**Why 4b2 is not split further.** It is one phase with one change surface (the four widgets plus the screen
edit) and one test file that proves them; splitting it would leave two phases neither of which is
independently green. Its 594 lines are mostly verbatim scenario fixtures and the carried ledger.

**4b3's split question (O-3) — decided: one PR, two phases.** D-526 moves ~740 lines out of
`stats_screen.dart` into a new screen and 4b3 adds the Fuel row, but measured together they are **one soft
signal** (length) and no hard limit, so the split is not taken — and splitting would leave Phase 1's screen
reachable from nowhere for a whole PR (the Fuel row is its only entry point), which is the dead-surface
defect 4b's review blocked on. The seam is still named if the owner prefers two PRs: 4b3a (the extraction,
proved by S-1110(a)) and 4b3b (the row), planned as an index plan first. See the 4b3 plan's §Scope check and
§Open Items.

## Scope check (2026-10-01, for 4c / 4c2)

Measured by reading each plan back after writing it, against the same budget as above.

| PR | Plan lines | Phases | Decisions | Scenarios | Predicted production lines | Verdict |
|---|---|---|---|---|---|---|
| **4c** — the screen | 629 | 3 (all `@developer`) | 16 (D-601…D-616) | 14 (S-1201…S-1214) | ~1,135 (of which −1,104 is `stats_screen.dart`) | one soft signal (length); no hard limit — within budget |
| **4c2** — the service, the models, the carried items, the docs | 627 | 3 (1 `@dba`, 2 `@developer`) | 16 (D-651…D-666) | 13 (S-1251…S-1263) | ~1,015 (of which ~430 is the chart move) | one soft signal (length); no hard limit — within budget |

**Why item 6 is not one PR, and why the seam is the layer.** Measured together the removal is ~1,770
production lines — past the 1,500-line hard limit. The seam is the only one the work has: 4c owns
`stats_screen.dart` and its tests; 4c2 owns the service, the models, the four carried items and the docs.
Neither PR changes anything the user sees. Splitting the other way (by section: cardio in one PR, sports in
the next) would leave the screen half-removed and the old layout still reachable, which is the defect class
4c exists to close.

**Why 4c is not split further.** Its production diff is one file. Its churn is test deletions in
`test/screen_widget_test.dart` (21 tests / 1,861 lines retired, 10 kept) and the guard that makes the removal permanent —
one change surface, one phase's worth of verification. 4c2's Phase 1 is the `@dba` phase the routing rule
asks for (service and models), and Phases 2–3 are `@developer`.
