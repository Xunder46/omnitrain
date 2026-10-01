# Stats PR 4b3 — the Fuel row on the main Stats screen

> **Status:** READY — Iteration 1 (two phases, both `@developer`) is written against `lib/` as it stands on
> 2026-10-01. Every recorded decision and scenario was re-verified against the nutrition, session and Stats
> code before the phases were written; §Notes records where the code disagreed with the earlier notes.
> **Next handoff:** `@developer` (Phase 1 — the nutrition trend extraction).
> **No `@dba` phase.** Verified in code, not assumed: every read the Fuel row needs already exists on
> `WorkoutRepository` (`getConsumedFoodsInRange`, `getNutritionTargetForDate`, `getAllSessions`), and this
> PR adds no model and no stored field. Both phases are `@developer`.
> **Series:** Stats PR 4 → `docs/plans/2026-09-30-04-stats-pr4-index.md`.
> **Provenance:** this plan, `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/…` (the Instruments
> data) and `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/…` (the Instruments list) replace
> the superseded single 4b plan, which measured 1,016 lines against the 800-line hard limit in
> `.github/agents/pr_scope_budget.md` §1. Decisions and scenarios keep their original ids (D-5xx, S-10xx);
> nothing here is renumbered.
> **Base:** `develop`. All work happens in place on `develop`. Executors never branch, stage, commit, merge
> or push (`docs/global_conventions.md`; index §Branch policy).
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` §"5. Instruments
> Layer: Native Metric per Effort Kind, Plus a Fuel Row" — the Fuel-row half of the prompt block and
> AC-9/AC-10 of its Acceptance Criteria.
> **Evidence:** `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.evidence.md`
> — holds the planner's real baselines (§1) and, from Phase 1 on, the executors' red runs, suite output and
> mutation proofs. **Never in this file.**
> **Binding conventions:** `docs/global_conventions.md`; `docs/design_system.md` (card-header typography,
> tokens, spacing, animation rules); `docs/navigation_contract.md` (`OmniNavigator` only);
> `docs/state_management/nutrition_state.md`, `docs/data_models.md`. Read them; they are not restated here.

---

## Scope check

Measured by reading this file back (669 lines) against `.github/agents/pr_scope_budget.md` §1: hard limits
800 plan lines, 5 phases, 1,500 predicted production lines; soft limits 500 plan lines, 3 phases, 1 track,
20 decisions, 30 scenarios; **two or more soft signals ⇒ split**.

| Signal | This PR | Limit | Verdict |
|---|---|---|---|
| Plan lines | 669 | >500 soft, >800 hard | one soft signal |
| Phases | 2 (Phase 1 the extraction, Phase 2 the Fuel row) | >3 soft, >5 hard | clear |
| Tracks | 1 (the phone) | >1 soft | clear |
| Decisions | 15 (D-520…D-534) | >20 soft | clear |
| Scenarios | 12 (S-1101…S-1112) | >30 soft | clear |
| Predicted production lines | ~1,240 — ~810 of it the D-526 **move** (~740 lines leave `stats_screen.dart`, ~40 land in the new primitives file, the new screen adds ~70) and ~435 new Fuel behaviour | >1,500 hard | clear |

**One soft signal (length), no hard limit → one PR, two phases.** O-3's split is *not* taken: both phases
fit together, and splitting would leave the new trend screen reachable from nowhere for a whole PR — a dead
surface, the defect 4b's review blocked on. O-3 stays **vetoable**: if the owner prefers two PRs, the seam is
Phase 1 = 4b3a, Phase 2 = 4b3b, and the planner rewrites this file as an index plan first — an executor never
splits a PR mid-phase.

---

## What this PR will do

The Stats screen's ALL TIME card is followed by the Instruments list (4b/4b2) and the five legacy sections.
This PR adds a **Fuel section** of its own between them (D-528): one row that answers "how is eating going
this week" — the 7-day average calories and protein over **logged days only**, each compared with the user's
target where a target exists and with the previous 7 days otherwise, a `'<n>/7 days logged'` indicator, and
the same figures split across training days and rest days. Tapping the row opens a full-history nutrition
trend screen, which is the existing NUTRITION card **moved, not reimplemented** (D-526, D-532).

The row is additive, like 4b and 4b2: nothing existing changes behaviour, and 4c still owns the removal of
the five legacy sections. While 4b3 is on `develop` both the Fuel row and the old NUTRITION card exist, and
both render the same extracted card — that is the expected state 4c ends, not a defect.

**Why it is a separate PR from the Instruments list.** They share the screen and the row/header widgets and
nothing else: the Instruments list reads `SensorSummary` through a new repository read and the exercise-metric
layer, while the Fuel row reads `ConsumedFood`, `NutritionTarget` and session completion. Planned together
(the superseded single 4b plan) the union was 3 phases, ~20 decisions and 1,016 plan lines against an
800-line hard limit.

**It ships as two phases** (both `@developer`): Phase 1 extracts the NUTRITION card into the trend screen — a
pure move, proved by S-1110(a) — and Phase 2 adds the Fuel row on top of it. The order matters: the row is
the screen's only entry point, so extracting first lets Phase 2's test assert the tap it wires.

---

## Decision Ledger — PR 4b3

Numbered D-5xx, continuing the series. Immutable once written: a change is a new superseding entry, never an
edit. The first eight entries were written in the superseded single 4b plan and are carried here
**verbatim**; D-528…D-534 were added on 2026-10-01, when Iteration 1 was written against `lib/` as it then
stood, and each is marked in the entry's own text where it decides a mechanic the earlier notes left open.

| # | Decision (enforceable contract) |
|---|---|
| **D-520** | The Fuel window is the **7 calendar days ending today** (today inclusive), local midnight to local midnight, by calendar arithmetic (D-509's rule). The previous range is the 7 days before that. |
| **D-521** | A **logged day** is a day in the window with ≥1 `ConsumedFood` row (`dateMs` = that day's local midnight). Averages divide by the count of **logged days only** — never by 7. |
| **D-522** | A **training day** is a day in the window on which a session with `endedAtMs != null` starts. |
| **D-523** | The training-day / rest-day split partitions the window's **logged days**: a day that is both logged and a training day counts on the training side only. A side with no logged days shows `'—'` for its average, not `0`. |
| **D-524** | The target is `getNutritionTargetForDate(<today's local midnight>)`. Calories are compared against the target when `target.calories > 0`; protein when `target.protein > 0`; a field with no target is compared against the previous 7 days only. With no target at all the row shows the previous-7 comparison only. `isUnset` means no target. |
| **D-525** | The row is hidden when `computeNutritionTrend(days: 14)` returns no points. The zero-session empty state wins over the Fuel row: with no completed session ever, the screen shows its existing empty state and no Fuel row. |
| **D-526** | Tapping the Fuel row opens a new full-history nutrition trend screen, and the existing NUTRITION card is **moved into it, not reimplemented** (about 600 lines leave `stats_screen.dart`). Until 4c, the Stats NUTRITION card renders the same extracted widget. The new screen keeps the card's Calories / Macros toggle. |
| **D-527** | No recommendation, no new target, no time-range selector (the pack's out-of-scope list). |
| **D-528** | The Fuel row is its **own section** on the Stats screen (the pack's wording), rendered **after** the Instruments sections and **above** the `Key('stats_legacy_sections')` Column, from a new `lib/features/stats/widgets/fuel_section.dart`. It renders only when the Fuel summary exists (D-525) and never in the zero-session empty state, and it is not an exercise row, so D-507's per-section cap never applies to it. Its header is `OmniCardHeader(title: 'Fuel')` — title case, matching the four Instruments headers — with **no actions slot**: D-520's window is today-anchored while `StatsWindowChip` names the screen's selected window (D-516b), so a chip there would misstate the window. |
| **D-529** | The Fuel section's anatomy and its user-visible strings are pinned. The logged-days indicator reads `'<n>/7 days logged'`. Each figure is its window average rounded to a whole unit: calories `'<n> kcal'`, protein `'<n> g'`. Each field's previous-7-days comparison reads `'—'` when there is nothing to compare, else `'↑ +<n> kcal'` / `'↓ -<n> kcal'` (protein: `'↑ +<n> g'` / `'↓ -<n> g'`) — D-508's raw-sign arrow and `formatNativeChange`'s em-dash convention, in the figure's own unit. Each field's target appears only when that field's target is `> 0`, as `'of <n> kcal target'` / `'of <n> g target'`. The split reads `'Training <n> kcal · <n> g'` and `'Rest <n> kcal · <n> g'`, from `kFuelTrainingLabel` / `kFuelRestLabel`; a side with no logged day reads `'Training —'` / `'Rest —'` (D-523). **Absence is never zero:** a missing average, comparison or side renders `'—'`, never `'0 kcal'` / `'0 g'`. A window with no logged day but food inside the visibility range (S-1111) still renders the row, reading `'0/7 days logged'` and `'—'` in every figure position. |
| **D-530** | The Fuel computation is `StatsProgressService.computeFuelSummary()` → `Future<FuelSummary?>`, returning `null` when `computeNutritionTrend(days: kFuelVisibilityDays)` is empty — D-525's rule, applied literally. `FuelSummary` is a plain value type in `lib/core/models/fuel_summary.dart` carrying the logged-day count, the window averages, the previous-week averages, the training-side and rest-side averages (each `double?`, null when its day-set is empty) and the two target values. New constants `kFuelWindowDays = 7` and `kFuelVisibilityDays = 14` are declared beside `kNutritionTrendDays` in the service; `kNutritionTrendDays` is untouched. |
| **D-531** | The per-day values behind the Fuel averages use `computeNutritionTrend`'s per-day rule exactly — calories = Σ `ConsumedFood.caloriesConsumed`; protein = `Σ(protein × amountConsumed / referenceAmount)` rounded once per day — so the Fuel row and the NUTRITION card can never disagree about a day. The target is `getNutritionTargetForDate(todayMidnightMs())`; a field is compared with its target only when that field is `> 0` (D-524). Training days come from `getAllSessions()` through D-522's predicate. |
| **D-532** | D-526 is executed as a **move**. The NUTRITION card body becomes `NutritionTrendCard` in `lib/features/nutrition/widgets/nutrition_trend_card.dart` — its Calories / Macros toggle, both charts, the empty chart, the legend, the single-point fallbacks and the nutrition legend metrics move with it — and the new `lib/features/nutrition/nutrition_trend_screen.dart` renders the same `OmniCardHeader(title: 'NUTRITION')` + `NutritionTrendCard` over `computeNutritionTrend(days: null)` and `computeNutritionAdherence()`. The Stats NUTRITION section keeps its header and renders the same widget: one card, two hosts, until 4c deletes the Stats host. The Fuel row pushes the screen through `OmniNavigator.push` (D-515); no route constant is added. **Why the card lands under `nutrition/` and not `stats/widgets/`:** it is a nutrition chart — it joins `macro_donut_chart.dart` and `calorie_ring_card.dart` — and the dependency then runs one way only, `stats_screen.dart` → `nutrition/`, until 4c removes it. The Fuel row's own widget stays Stats-specific, in `lib/features/stats/widgets/`. |
| **D-533** | The three chart primitives the move would otherwise duplicate get one home in a new `lib/widgets/chart/chart_primitives.dart`: the bottom-axis reserved size as `kChartBottomAxisReservedSize` (replacing `_StatsScreenState._kBottomAxisReservedSize`, which both the staying legacy charts and the moving nutrition charts read), `buildLegendItem` (read by the staying cardio pace chart **and** the moving nutrition legend) and `buildSinglePointCard` (read by the staying strength cards **and** the moving calories single-point). It goes under `lib/widgets/chart/` and not under `lib/features/stats/widgets/` because it is shared across features, which is exactly what that directory already exists for — `lib/widgets/chart/edge_aware_date_label.dart` is imported by `stats_screen.dart` and by `lib/features/profile/widgets/measurement_history_chart_sheet.dart` — and because after 4c removes the Stats host the nutrition card must not depend on a Stats feature file. No copy of any of the three may remain in `lib/`; the residue sweep proves it. **Exception:** the Exercise Progress screen's single-point card is a divergent variant — it renders the label and the date in one line where the shared card takes a label and a value — so it keeps its own implementation. |
| **D-534** | Documentation: this PR updates `docs/stats_screen.md` (a `### Fuel` subsection after `### Instruments list`, the new constants in the Key Constants table, the new files in Core Files), `docs/widget_catalog.md` (the Fuel section and the extracted card) and `docs/navigation_and_screens.md` (the nutrition trend screen and the Fuel row as its entry point). It does **not** create `docs/nutrition.md`: the last nutrition-visible change in the series is 4c's deletion of the legacy NUTRITION section, so 4c writes the consolidated nutrition doc and indexes it. |

**Decisions this plan consumes but does not define** (the shared Instruments layer):

| # | Defined in | What this plan must honour |
|---|---|---|
| **D-503** | 4b2 | The Fuel row is part of the same additive boundary: it renders above the legacy sections, and the five legacy sections stay untouched. |
| **D-507** | 4b2 | The row cap and `Show all (n)` are per section. The Fuel row is not an exercise row: **resolved by D-528** — it is its own section, outside the Instruments list, so the cap never reaches it. |
| **D-509** | 4b | Calendar arithmetic, never `subtract(Duration)`: D-520 inherits the rule, so a DST transition cannot shorten the Fuel window. |
| **D-514** | 4b | One load, one window resolution: whatever the Fuel row computes is computed once in `_loadData()`, not in `build`. |
| **D-515** | 4b2 | Navigation goes through `OmniNavigator`; no new route constant is required if the trend screen is pushed directly. |
| **D-516b** | 4b2 | `StatsWindowChip` is the only window chip. **Resolved by D-528**: the Fuel header carries **no** chip, because D-520's window is today-anchored while the chip names the screen's selected window — showing it there would misstate the window. |

**Ledger entries carried forward from 4a that bind this PR:** D-401 (the split), D-402 (single release, no
migration, no flag), D-409 (an all-time best is descriptive; the PR path is untouched — the Fuel row creates
no PR event either), D-413 (`OmniNavigator`), D-416 (doc reconciliation).

---

## Feature invariants that bite in this PR

Project-wide rules live in `docs/global_conventions.md`; these are the ones this PR can break.

1. **The repository boundary.** The Fuel row reads nutrition and session data through `WorkoutRepository`
   (or the existing nutrition state that already does), never through a concrete store.
2. **The old layout is untouched.** The five legacy sections, their constants and their tests keep passing
   unmodified. The NUTRITION card is *moved* (D-526), and moving it must not change a single figure — S-1110.
3. **Absence is not zero.** An empty training or rest side shows `'—'`; a missing target shows no target
   comparison; a missing previous week shows no comparison. Never `0`, never a comparison against zero.
4. **One number, one rendering.** A figure rendered by the Fuel row and by the extracted trend screen comes
   from the same computation — the extraction is a move, not a copy.
5. **Nothing new is persisted.** No model field, no box, no schema change: `scripts/sqlite_schema.sql`,
   `scripts/sqlite_seed.sql` and `test/db_seed_test.dart` must pass **unmodified**.

---

## Requirements

R-11 (pack AC-9) The Fuel row shows the window's average calories and protein over logged days only, with a
logged-days indicator.
R-12 (pack AC-10) Each figure is compared with the user's target where a target exists for that field, and
with the previous 7 days where it does not.
R-13 (D-523) The same figures are split across training days and rest days, partitioning the window's logged
days.
R-14 (D-525) The row is hidden after 14 days without logs, and the zero-session empty state wins over it.
R-15 (D-526) Tapping the row opens a full-history nutrition trend screen holding the moved NUTRITION card,
whose figures are unchanged.
R-16 (D-527) No recommendation, no new target, no time-range selector.
R-17 (D-528) The Fuel row is a section of its own, between the Instruments sections and the legacy sections,
with a `'Fuel'` header and no window chip.
R-18 (D-529) Every figure the row cannot compute renders `'—'`; a window with no logged day renders
`'0/7 days logged'` and `'—'` everywhere rather than `0` or a crash.
R-19 (D-534) The docs the PR invalidates are updated in the same phase as the code that invalidated them.

---

## Acceptance Criteria → scenarios

| AC | Statement | Scenario(s) | PR |
|---|---|---|---|
| AC-9 | with food on 3 of the last 7 days, the averages use those 3 days only, and the logged-days count shows | S-1101, S-1102 | 4b3 |
| AC-10 | with a protein target the row compares against it; with none it compares against the previous 7 days | S-1103, S-1104 | 4b3 |
| AC-11 | the old sections no longer appear on the main Stats screen | deferred to 4c — they **must** still appear in 4b3 | 4c |
| AC-13 | the Fuel row renders as its own section between the Instruments sections and the legacy sections, with no window chip | S-1112 | 4b3 |
| AC-14 | a window with no logged day still renders the row, reading `'0/7 days logged'` and `'—'` | S-1111 | 4b3 |
| AC-15 | tapping the Fuel row opens the trend screen, whose figures equal the Stats NUTRITION card's | S-1109, S-1110(a) | 4b3 |

AC-1…AC-8 and AC-12 are 4b's and 4b2's; see those plans' tables.

---

## Scenarios — PR 4b3 (S-1101…S-1112)

Stable ids; never reused. Fixtures are stated as populations because an unstated population becomes a bug.
S-1101…S-1110 are the superseded plan's entries, carried **verbatim**; S-1111 and S-1112 are Iteration 1's
own, covering what the earlier notes left unpinned. S-1001…S-1018 are 4b's and 4b2's.

### S-1101: logged-days-only averaging
- **Fixture:** 7-day window; `ConsumedFood` rows on days 1, 3 and 5 only (1000 / 2000 / 3000 kcal,
  50 / 100 / 150 g protein); the other four days have no rows.
- **Trigger:** render the Fuel row.
- **Expected outcome:** calories `2000` and protein `100 g` — the mean of 3 logged days, not of 7 (which
  would be ~857 and ~43).
- **Edge case of:** none.

### S-1102: the logged-days indicator
- **Fixture:** S-1101, then a variant with 7 of 7 days logged.
- **Trigger:** render.
- **Expected outcome:** `'3/7 days logged'`, then `'7/7 days logged'`.
- **Edge case of:** S-1101.

### S-1103: a target on some fields only
- **Fixture:** a `NutritionTarget` with calories 2200, protein 0, carbs 0, fat 0; 5 logged days.
- **Trigger:** render.
- **Expected outcome:** calories compared with 2200 **and** with the previous 7 days; protein compared
  with the previous 7 days only. `isUnset` (all four 0.0) ⇒ no target comparison at all.
- **Edge case of:** S-1101.

### S-1104: no target, previous week only
- **Fixture:** no target row for today; logged days in both the window and the previous 7.
- **Trigger:** render.
- **Expected outcome:** both figures carry a previous-week comparison and no target comparison; no crash
  from a null target.
- **Edge case of:** S-1103.

### S-1105: the training-day / rest-day split
- **Fixture:** logged days 1, 2, 3, 4, 5, 6, 7; completed sessions starting on days 1 and 3; a session on
  day 5 that is **still running** (`endedAtMs == null`).
- **Trigger:** render.
- **Expected outcome:** the training side averages days 1 and 3 only (day 5 is not a training day —
  D-522); the rest side averages days 2, 4, 6, 7; the two sides' day counts sum to 7 with no double count.
- **Edge case of:** S-1101.

### S-1106: a side with no logged days
- **Fixture:** logged days all falling on training days, and the mirror case (no training days at all).
- **Trigger:** render.
- **Expected outcome:** the empty side shows `'—'` for its average, never `0`, and never a division by
  zero; the row still renders.
- **Edge case of:** S-1105.

### S-1107: hidden after 14 days without logs
- **Fixture:** (a) the newest `ConsumedFood` row is 13 days old; (b) it is exactly 14 days old; (c) 15 days.
- **Trigger:** render.
- **Expected outcome:** (a) the row renders; (b) and (c) it does not. The boundary is pinned to
  `computeNutritionTrend(days: 14)` returning no points.
- **Edge case of:** S-1101.

### S-1108: the previous week with no food
- **Fixture:** logged days in the window only; nothing in the previous 7.
- **Trigger:** render.
- **Expected outcome:** the current figures render with no comparison indicator (or `'—'`), never a
  comparison against zero.
- **Edge case of:** S-1104.

### S-1109: tapping the Fuel row
- **Fixture:** food logged on 20 distinct days across two months.
- **Trigger:** tap the Fuel row.
- **Flow:** `OmniNavigator.push` → the full-history nutrition trend screen.
- **Expected outcome:** the trend screen opens with the card's Calories / Macros toggle working, and the
  toggle's two states render the two datasets.
- **Edge case of:** none.

### S-1110: the extracted screen's figures are unchanged, and the empty state wins
- **Fixture:** (a) the population of the current NUTRITION card; (b) a repository with no sessions at all
  but food logged today.
- **Trigger:** render both.
- **Expected outcome:** (a) the extracted screen and the Stats NUTRITION card show identical figures for
  the same repository (a move, not a rewrite); (b) the Stats screen shows its existing empty state and no
  Fuel row (D-525).
- **Edge case of:** none.

### S-1111: food inside the visibility range, none inside the window
- **Fixture:** a `ConsumedFood` row 10 days old and nothing since; sessions on days 1 and 3 of the window
  (so the row is not hidden by D-525) and no target row.
- **Trigger:** render the Stats screen.
- **Expected outcome:** the Fuel section renders, reading `'0/7 days logged'`; the calories figure, the
  protein figure, both comparison chips and both split sides read `'—'`; nothing reads `'0 kcal'` or
  `'0 g'` and nothing throws.
- **Edge case of:** S-1107.

### S-1112: the Fuel header carries no window chip
- **Fixture:** the S-1101 population, plus an instrument section so the Instruments list renders.
- **Trigger:** render the Stats screen.
- **Expected outcome:** the screen shows exactly one `StatsWindowChip`, on the first Instruments section;
  the Fuel section's header carries none, and the Fuel figures are the same for two different selected
  windows (D-528).
- **Edge case of:** none.

---

## Iteration 1

### Executor block (read before Phase 1)

**Step 0a — read these first.** `docs/global_conventions.md`; `docs/design_system.md` (§card-header
typography, tokens, spacing, animation rules); `docs/navigation_contract.md`;
`docs/state_management/nutrition_state.md`; 4b's and 4b2's plans (the contracts this plan consumes); this
file's §Decision Ledger, §Feature invariants, §Scenarios, §Doc-claim → test table and the phase you are
implementing. Docs are claims, not truth: if `lib/` disagrees with a doc, `lib/` wins and you note the
disagreement in the evidence file.

**Step 0b — baseline before you touch anything.** Run `gateway.sh lint` and `gateway.sh test` and copy the
**verbatim** summary lines into the evidence file (§1), beside the planner's own run. The planner measured
this tree on 2026-10-01 at `199 issues found.` with 0 errors and `+3208 ~1: All tests passed!`. If your
numbers differ — they will once 4b2's tests are in the tree, and they may if the tree has moved — record what
you actually saw and say so. A different baseline is information, not a failure; a baseline you did not take
is a failure.

**Step 0c — the shell.** Only `.github/copilot/scripts/macos/gateway.sh` may be executed: `gateway.sh list`,
`lint`, `test`, `build`, `codegen`, `pub-get`, `format <paths>`, `git-status`,
`git-diff [<ref>] [--stat|--name-only|--name-status|--cached] [-- <path>...]`, `git-log [<count>] [<ref>]`,
`git-show <ref> [--stat]`. There is **no** `grep`, `cp`, `sed`, `mv`, `rm`, `/tmp` or plain `git` for you.
Use the built-in search tool for source sweeps, `view` for reads, and `gateway.sh git-diff --stat -- <path>`
for footprints. A command that fails twice the same way: stop and report.

**The nine rules.**

1. **Stay in the phase's Predicted Files.** A file not listed is out of bounds; a listed file you did not
   need to touch is a finding for the reviewer, not a silent omission.
2. **Red first.** Write the phase's tests before its production code, run them, and paste the failing output
   in the evidence file. A test that passes before the change proves nothing.
3. **Mutation proof.** Every phase ends with the inverse-edit mutations listed in its Done Criteria: note
   the file's `git-diff`, make the listed edit with the edit tool, show the named test **failing**, apply the
   exact inverse, confirm the diff is back, run again, show it passing. Record the exact output. Mutations
   target **tracked** files — an edit to an untracked new file does not appear in `gateway.sh git-diff`, so
   use the file the phase names. Each phase below names two mutations on a tracked file.
4. **Green means the suites ran.** `flutter analyze` passing is not a test run. Run `gateway.sh test`, read
   the pass/fail counts, paste them. A hang, a timeout or a killed run is a failure — say so.
5. **The analyzer bar is "none new".** 0 errors and no more than the baseline issue count.
6. **Docs trail code by zero phases.** Each phase updates the docs it invalidated and its Done Criteria
   include the claim-to-test rows from §Doc-claim → test table.
7. **Ambiguity never stops you.** Pick the option most consistent with the Ledger and the invariants, then
   log it in §Assumption Log as `A-n: decision — options considered — why`.
8. **No new dependency, no new asset, no schema change, no migration, no feature flag.**
9. **Never branch, stage, commit, merge or push.** Work in place on `develop`.

**Doc checklist for this PR** (each item names the phase that owns it):
- [x] **Phase 1** `docs/stats_screen.md` — the NUTRITION section renders the extracted `NutritionTrendCard`;
      the new files in Core Files; the constants table unchanged
- [x] **Phase 1** `docs/widget_catalog.md` — a new note paragraph beside the existing "Note on the Stats
      screen's Instruments widgets" one, listing `NutritionTrendCard` and its path, and saying the Stats
      NUTRITION section and the new nutrition trend screen render the same widget
- [x] **Phase 1** `docs/navigation_and_screens.md` — the nutrition trend screen (its entry point arrives in
      Phase 2; Phase 1 records the screen itself)
- [ ] **Phase 2** `docs/stats_screen.md` — a `### Fuel` subsection after `### Instruments list`: the window,
      the logged-days-only averages, the indicator, the target/previous-week comparison, the training/rest
      split, the `'—'` rules, the visibility rule; `kFuelWindowDays` / `kFuelVisibilityDays` in the Key
      Constants table; `fuel_summary.dart` and `fuel_section.dart` in Core Files
- [ ] **Phase 2** `docs/widget_catalog.md` — the Fuel section widget, with its keys and strings
- [ ] **Phase 2** `docs/navigation_and_screens.md` — the Fuel row as the nutrition trend screen's entry point
- [ ] **Phase 2** `docs/state_management/nutrition_state.md` — only if the row adds anything there. It is not
      expected to: the row reads the service and the repository, and D-530 puts the computation in
      `StatsProgressService`. If nothing changed, say so in the evidence file rather than editing the doc.
- [ ] **Not this PR:** `docs/nutrition.md`. Nutrition work continues after 4b3 (the pack's Tier 3 Signals
      items) and 4c deletes the Stats NUTRITION host, so 4c owns the consolidated doc (D-534). This plan does
      not create it and does not leave a dangling link to it.
- [x] No file in `docs/` exceeds 64 KiB (`test/docs_indexing_contract_test.dart`)
- [x] Every claim added above has a named test in §Doc-claim → test table (the Phase 1 rows; Phase 2's are
      ticked when its phase runs)

### Phase 1: Extract the NUTRITION card into a full-history nutrition trend screen (@developer)

**Why it is one phase:** the move is a single change surface — one widget that must render identically from
two hosts — and S-1110(a) is its proof. Splitting the screen from the move would leave a screen reachable
from nowhere, which is the dead-surface defect 4b's review blocked on.

**Prerequisite:** 4b2's Phase 1 is merged: the Stats screen has the Instruments list and the
`Key('stats_legacy_sections')` wrapper this phase's delegation sits inside.

1. [x] Create `lib/widgets/chart/chart_primitives.dart` (D-533) holding
       `const double kChartBottomAxisReservedSize = 20;`, `buildLegendItem(...)` and
       `buildSinglePointCard(...)`, moved out of `stats_screen.dart` (`_kBottomAxisReservedSize` at line 47,
       `_buildLegendItem` at 1799, `_buildSinglePointCard` at 1830) and converted from instance methods to
       top-level functions taking everything they read (theme colours and the like) as parameters. The
       nutrition legend's `24` / `8` legend metrics move with the card, not here.
2. [x] Create `lib/features/nutrition/widgets/nutrition_trend_card.dart` with `class NutritionTrendCard`, a
       `StatefulWidget` owning the `_NutritionView` enum, the `'Calories'` / `'Macros'` `SegmentedButton`,
       both charts, the empty chart, the two single-point fallbacks, the legend, and the legend
       height/gap constants — moved from `stats_screen.dart` 894–1523 and 2008–2110. Inputs: the trend
       points, the adherence data and `themeColors`. It renders the card **body only**; the header stays
       with each host.
3. [x] Create `lib/features/nutrition/nutrition_trend_screen.dart`: `Scaffold` with
       `OmniBackHeader(title: 'Nutrition', subtitle: …)`, `initState` → `addPostFrameCallback(_loadData)`,
       one `StatsProgressService` per load calling `computeNutritionTrend(days: null)` and
       `computeNutritionAdherence()`, body = `OmniCardHeader(title: 'NUTRITION')` + `NutritionTrendCard`.
       A repository with no food renders the existing empty-chart path, not an error.
4. [x] Edit `lib/features/stats/stats_screen.dart`: delete the moved members, have the NUTRITION section
       render the same `OmniCardHeader(title: 'NUTRITION')` + `NutritionTrendCard` with the same
       `_nutritionAdherence` and trend inputs it passes today, and repoint every remaining reader of the
       three moved primitives at `lib/widgets/chart/chart_primitives.dart`. **No figure may change** — S-1110(a).
5. [x] Write `test/nutrition_trend_screen_test.dart` first (Rule 2), covering S-1110(a) — the Stats card and
       the screen render the same figures for the same repository — plus S-1109's toggle and the
       empty-chart path. Seed through the repository in `setUp`, never inside a `testWidgets` body.
6. [x] Update the Phase 1 doc checklist rows above.
7. [x] Residue sweep: search `lib/` for `_kBottomAxisReservedSize`, `_buildLegendItem`,
       `_buildSinglePointCard` — no declaration and no reader outside the new primitives file. Two private
       copies survive in `lib/features/stats/exercise_progress_screen.dart`, a file **outside** this phase's
       Predicted Files and absent from `git-diff`, so they predate the move — reported in `.evidence.md`
       §2.4, not absorbed.

**Done Criteria** (run until green):
- [x] `gateway.sh test test/nutrition_trend_screen_test.dart` → all pass (`00:01 +10: All tests passed!`).
- [x] `gateway.sh test test/screen_widget_test.dart test/header_standardization_test.dart test/stats_progress_test.dart`
  → all pass (`00:09 +385: All tests passed!`), pre-existing assertions **unmodified**; no surface height moved.
- [x] `gateway.sh test` → the whole suite passes (`01:25 +3218 ~1: All tests passed!`, vs the `+3208 ~1`
  baseline — the 10 new tests).
- [x] `gateway.sh test test/navigation_contract_enforcement_test.dart test/screen_overflow_contract_test.dart test/docs_indexing_contract_test.dart`
  → all pass.
- [x] `gateway.sh lint` → 0 errors, `199 issues found.` — equal to the baseline. **Exception:** the "each of
  the four touched `lib/` files at 0 issues" half is not literally met. The three new files are clean;
  `stats_screen.dart` carries the pre-existing `_ChartSeries` warning at 1313:7, which the move neither
  created nor touched (absent from `git-diff`, referenced nowhere). Rule 5's "none new" bar holds.
- [x] Mutation **M1** on `lib/features/stats/stats_screen.dart` (tracked): `const []` as the delegated
  card's trend points ⇒ the S-1110(a) figure assertion fails (`+0 -2`, both harnesses). Inverted, diff back
  to `20 insertions(+), 833 deletions(-)`, green.
- [x] Mutation **M2** on the same file: no adherence data to the delegated card ⇒ the target-line assertion
  fails (`Expected: an object with length of <2>` / `Actual: … Which: has length of <1>`, both harnesses).
  Inverted, diff back, green.
- [x] Search `lib/` for `_kBottomAxisReservedSize`, `_buildLegendItem` and `_buildSinglePointCard` → each
  declared once, in the new primitives file, and every other occurrence is a reader (§2.4). The two
  pre-existing private copies in `exercise_progress_screen.dart` are the one exception, reported above.

**Predicted Files:** `lib/widgets/chart/chart_primitives.dart` (new),
`lib/features/nutrition/widgets/nutrition_trend_card.dart` (new),
`lib/features/nutrition/nutrition_trend_screen.dart` (new), `lib/features/stats/stats_screen.dart`,
`test/nutrition_trend_screen_test.dart` (new), `docs/stats_screen.md`, `docs/widget_catalog.md`,
`docs/navigation_and_screens.md`. Nothing else.

**Deliberately not in this phase:** the Fuel row, `FuelSummary`, `computeFuelSummary`, the two constants, the
`OmniNavigator.push` and any new route — all Phase 2. `docs/nutrition.md` — 4c.

---

### Phase 2: The Fuel row (@developer)

**Why it is one phase:** the value type, the service method, the widget and the screen wiring are one change
surface — the row cannot render without all four — and one test file proves all of S-1101…S-1108, S-1111 and
S-1112. It is also the phase that gives Phase 1's screen its entry point, which is why it must not be a
separate PR (see §Scope check).

**Prerequisite:** Phase 1 is merged (the trend screen exists to be the tap target).

1. [x] Create `lib/core/models/fuel_summary.dart` (D-530) with `class FuelSummary` carrying `loggedDays`,
       the window averages (`caloriesAverage`, `proteinAverage`), the previous-week averages
       (`previousCaloriesAverage`, `previousProteinAverage`), the split averages
       (`trainingCaloriesAverage`, `trainingProteinAverage`, `restCaloriesAverage`, `restProteinAverage`) —
       every average a `double?`, null when its day-set is empty — plus `targetCalories`, `targetProtein` and
       the `hasCalorieTarget` / `hasProteinTarget` getters (`> 0`). Plain Dart, no Hive annotations.
2. [x] Add to `lib/core/services/stats_progress_service.dart`: `const int kFuelWindowDays = 7;` and
       `const int kFuelVisibilityDays = 14;` beside `kNutritionTrendDays` (which is **not** changed), and
       `Future<FuelSummary?> computeFuelSummary()` returning `null` when
       `computeNutritionTrend(days: kFuelVisibilityDays)` is empty (D-530), otherwise partitioning that
       point list at today−6 into the window and the previous 7 (D-531's per-day rule, one trend call),
       reading training days from `getAllSessions()` through D-522's `endedAtMs != null` + start-day
       predicate, and the target from `getNutritionTargetForDate(todayMidnightMs())` (D-524).
3. [x] Create `lib/features/stats/widgets/fuel_section.dart` with `class FuelSection` (D-528, D-529): root
       `Key('fuel_section')`; `OmniCardHeader(title: 'Fuel')` and **no** `StatsWindowChip`; the
       `InkWell(key: Key('fuel_row'))` tap target; the `'<n>/7 days logged'` indicator
       (`Key('fuel_logged_days')`); the calories block (`Key('fuel_calories')`, `Key('fuel_calories_change')`,
       `Key('fuel_calories_target')`) and the protein block (`Key('fuel_protein')`,
       `Key('fuel_protein_change')`, `Key('fuel_protein_target')`); the split lines
       (`Key('fuel_split_training')`, `Key('fuel_split_rest')`) with `kFuelTrainingLabel` / `kFuelRestLabel`;
       and the `'—'` rules for every absent value. Formatting is the row's own — there is no `NativeMetric`
       for kcal or grams — but it follows `native_value_format.dart`'s conventions (whole units, `'—'` for
       nothing to compare, D-508's raw-sign arrow).
4. [x] Edit `lib/features/stats/stats_screen.dart`: hold the `FuelSummary?` in state, compute it inside
       `_loadData()`'s single `setState` (D-514), render `FuelSection` + a 24dp gap **between** the
       Instruments sections and the `Key('stats_legacy_sections')` column, only when the summary is
       non-null and never in the zero-session empty-state branch, and push `NutritionTrendScreen` through
       `OmniNavigator.push` on tap (D-515 — no new route constant, no bare `MaterialPageRoute`).
5. [x] Write `test/fuel_row_screen_test.dart` first (Rule 2), covering S-1101…S-1108, S-1111 and S-1112, and
       read the model half from `computeFuelSummary()` through the same repository the screen reads. Copy
       `test/instrument_list_screen_test.dart`'s harness (`harnessFactories`, seed in `setUp`, surface size
       set and torn down, `pumpAndSettle`).
6. [x] Update the Phase 2 doc checklist rows above.
7. [x] Residue sweep: search `lib/` for `computeFuelSummary`, `kFuelWindowDays`, `kFuelVisibilityDays`,
       `FuelSummary` — one declaration each, and `FuelSummary` is read only by the service and the section.

**Done Criteria** (run until green):
- `gateway.sh test test/fuel_row_screen_test.dart` → all pass (paste the counts).
- `gateway.sh test` → the whole suite passes (paste the counts).
- `gateway.sh test test/db_seed_test.dart` → green, with `scripts/sqlite_schema.sql`,
  `scripts/sqlite_seed.sql` and the test itself **unmodified** (nothing was persisted).
- `gateway.sh test test/navigation_contract_enforcement_test.dart test/screen_overflow_contract_test.dart test/docs_indexing_contract_test.dart`
  → all pass (the row pushes a screen, adds UI to a dense screen, and edits docs).
- `gateway.sh lint` → 0 errors, ≤ baseline issues; each of the four touched `lib/` files at 0 issues.
- Mutation **M3** on `lib/core/services/stats_progress_service.dart` (tracked): divide the window averages by
  `kFuelWindowDays` instead of the logged-day count ⇒ S-1101 fails. Invert, confirm, green.
- Mutation **M4** on the same file: make the visibility check use `kFuelWindowDays` instead of
  `kFuelVisibilityDays` ⇒ S-1107(b) fails. Invert, confirm, green.
- Mutation **M5** on the same file: drop the `endedAtMs != null` predicate from the training-day test ⇒
  S-1105 fails. Invert, confirm, green.
- Search `lib/` for `computeFuelSummary`, `kFuelWindowDays`, `kFuelVisibilityDays` and `FuelSummary` → one
  declaration each (§3.4).

**Predicted Files:** `lib/core/models/fuel_summary.dart` (new),
`lib/features/stats/widgets/fuel_section.dart` (new), `lib/core/services/stats_progress_service.dart`,
`lib/features/stats/stats_screen.dart`, `test/fuel_row_screen_test.dart` (new), `docs/stats_screen.md`,
`docs/widget_catalog.md`, `docs/navigation_and_screens.md`, and `docs/state_management/nutrition_state.md`
only if the row adds state there. Nothing else.

**Deliberately not in this phase:** removing the five legacy sections, the Stats NUTRITION host, or writing
`docs/nutrition.md` — all 4c. Any recommendation, goal-setting UI or time-range selector — D-527.

---

## Files Affected (whole PR)

Every file this PR may touch. Nothing outside this table. Line estimates are the planner's, read off the
code; they are predictions, not commitments, and the reviewer treats an out-of-bounds file as a finding.

| File | New / Edit | Phase | What changes |
|---|---|---|---|
| `lib/widgets/chart/chart_primitives.dart` | new | 1 | the three primitives the move would otherwise duplicate (D-533), ~40 lines |
| `lib/features/nutrition/widgets/nutrition_trend_card.dart` | new | 1 | the moved NUTRITION card body, toggle and legend, ~740 lines |
| `lib/features/nutrition/nutrition_trend_screen.dart` | new | 1 | the full-history host for the moved card, ~70 lines |
| `lib/features/stats/stats_screen.dart` | edit | 1, 2 | Phase 1 deletes the moved members (~740 lines) and delegates the NUTRITION section; Phase 2 adds the Fuel wiring (~40 lines) |
| `test/nutrition_trend_screen_test.dart` | new | 1 | S-1110(a) parity, S-1109's toggle, the empty chart |
| `lib/core/models/fuel_summary.dart` | new | 2 | `FuelSummary`, ~45 lines |
| `lib/core/services/stats_progress_service.dart` | edit | 2 | `kFuelWindowDays`, `kFuelVisibilityDays`, `computeFuelSummary()`, ~70 lines |
| `lib/features/stats/widgets/fuel_section.dart` | new | 2 | `FuelSection`, ~180 lines |
| `test/fuel_row_screen_test.dart` | new | 2 | S-1101…S-1108, S-1111, S-1112 |
| `docs/stats_screen.md` | edit | 1, 2 | the extracted card (Phase 1), the `### Fuel` subsection and the constants (Phase 2) |
| `docs/widget_catalog.md` | edit | 1, 2 | the extracted card and screen (Phase 1), the Fuel section (Phase 2) |
| `docs/navigation_and_screens.md` | edit | 1, 2 | the trend screen (Phase 1), its entry point (Phase 2) |
| `docs/state_management/nutrition_state.md` | edit **only if** the row adds state there | 2 | expected to be a no-op; the evidence file says so if it is |

**Known exclusions, verified rather than assumed:** no `lib/data/` change — every read the Fuel row needs
(`getConsumedFoodsInRange`, `getNutritionTargetForDate`, `getAllSessions`) already exists on
`WorkoutRepository`, and no model, box or stored field is added; therefore no `scripts/sqlite_schema.sql`,
no `scripts/sqlite_seed.sql`, no `test/db_seed_test.dart`, no migration and no `pubspec.yaml`. No new route
constant (`lib/core/navigation/` untouched, D-515). No change to `lib/state/nutrition_state.dart` unless
Phase 2 finds it genuinely needs one.

---

## Notes

**Phase dependency graph.** 4b Phase 1 → 4b Phase 2 → 4b2 Phase 1 → **4b3 Phase 1 → 4b3 Phase 2** → 4c.
Phase 2's tap target is Phase 1's screen, so the order is forced: run Phase 2 first and there is no screen to
push, and the card would have to stay in `stats_screen.dart` — the thing D-526 forbids. No cheaper
re-ordering exists.

**Predicted intermediate states.** Between the phases the nutrition trend screen exists and nothing pushes
it: reachable only from its test. That is expected for exactly one phase, and it is why they are one PR.
After Phase 1, `stats_screen.dart` is roughly 700 lines shorter and the legacy section list is unchanged;
after Phase 2 it is roughly 40 lines longer than that.

**What the code says, where the earlier notes were wrong.** Recorded because the reviewer will otherwise
treat the corrected numbers as drift.

| Earlier note | What `lib/` actually says | Consequence |
|---|---|---|
| the Stats NUTRITION card is a "10-day card" | `computeProgressData()` calls `computeNutritionTrend(days: null)` — the card is already **full history**; `kNutritionTrendDays = 10` is only a soft default for other callers | the doc's claim was right and the note was wrong; no code change, and the trend screen's `days: null` matches the card it replaces |
| the extraction moves "about 600 lines" | the nutrition members span `stats_screen.dart` 894–1523 plus 2008–2110 — roughly **700–740 lines**, and three of them are shared with the staying legacy charts | the shared three need a home (D-533); a naive move would have duplicated them and the reviewer would have called it drift |
| a repository read might be missing, needing a `@dba` phase | `getConsumedFoodsInRange`, `getNutritionTargetForDate` and `getAllSessions` all exist on `WorkoutRepository` | no `@dba` phase, no interface change, no repository parity work |
| — | `native_value_format.dart` has no `NativeMetric` for kcal or grams | D-529 pins the row's own strings instead of borrowing `formatNativeChange`'s metric path; this is the one place an implementer would otherwise invent user-visible text |
| — | no existing test asserts the Stats NUTRITION card's figures (the `'NUTRITION'` assertions in `test/` are header-text ones) | Phase 1's parity test is new coverage, not a modification — and it is the only thing that can prove the move was a move |

**Legacy handling.** None needed: this series is single-release (4a D-402). No migration, no old-data
handling, no flag.

**The one place a reasonable implementer could drift.** Whether a day that is both a training day and a
logged day is double-counted. D-523 partitions the logged days, so it is counted once, on the training side,
and the two sides' counts sum to the logged-day count — S-1105 asserts exactly that. Do not "also show the
overall average including both" without a new decision.

**Why a chip is absent, not merely different.** D-520's window is today-anchored; `StatsWindowChip` names
the window the user selected for the Instruments sections (D-516b). A chip on the Fuel header would tell the
user their Fuel figures are scoped to a period they are not. The section states its own window in words
(`'<n>/7 days logged'`) and carries no chip — S-1112 asserts the screen still shows exactly one chip.

---

## Open Items

- **O-3 (the split) — RESOLVED, vetoable.** One PR, two phases. The measured budget is one soft signal
  (§Scope check), so the 4b3a/4b3b split is not taken; and splitting it would leave Phase 1's screen
  unreachable for a whole PR. If the owner prefers two PRs, the seam is Phase 1 = 4b3a and Phase 2 = 4b3b,
  and this file becomes an index plan first. An executor never splits it mid-phase.
- **O-10 (planner's call, vetoable — the one the owner should answer).** The Fuel row's window is **not** the
  screen's selected window: D-520 is today-anchored. A user who has selected a training period in the window
  chip sees the Instruments sections scoped to that period and the Fuel row scoped to the last 7 days. That
  is defensible ("how is eating going this week" is a today-anchored question) and D-528 makes it honest on
  screen by omitting the chip, but it is a product choice, not a technical one. Answer it in §Feedback and
  the planner supersedes D-520/D-528 rather than editing them.
- **O-11 — RESOLVED.** Iteration 1 is written, against `lib/` as it stands on 2026-10-01; the handoff is
  named in the status block. Every recorded decision and scenario was re-verified against the nutrition,
  session and Stats code first, and the disagreements are in §Notes.
- **O-12 (docs) — RESOLVED by D-534.** This PR does not write `docs/nutrition.md`. Nutrition work continues
  after 4b3 (the pack's Tier 3 Signals items) and 4c deletes the Stats NUTRITION host, so 4c owns the
  consolidated doc and its `docs/README.md` entry. 4b3 updates only the docs it invalidates.
- **O-8 — not applicable here.** It belonged to the superseded plan's repository-question list; every read
  this PR needs was verified to exist on `WorkoutRepository`, so no `@dba` phase and no interface question
  remains open.

---

## Progress

| Item | Owner | State | Evidence |
|---|---|---|---|
| Iteration 1 — decisions, scenarios and both phases written | planner | done | this file |
| Planner baselines (`lint`, `test`) | planner | done | `.evidence.md` §1 |
| Phase 1 — the NUTRITION card extraction | `@developer` | **Complete** | `.evidence.md` §2 |
| Phase 2 — the Fuel row | `@developer` | **Complete** | `.evidence.md` §3 |
| Review | `@code-reviewer` | not started | — |

---

## Assumption Log

Executors append here; the planner ratifies (promotes to a D-x) or reverts (opens a remediation item). Empty
is expected at planning time: no phase has run. An empty log after a phase is *not* expected — Phase 1 moves
~700 lines and Phase 2 touches the service and the screen, so both should produce entries.

| # | Phase | Decision | Options considered | Why | Verdict |
|---|---|---|---|---|---|
| A-1 | 1 | `NutritionTrendCard` imports `../../stats/widgets/scrollable_trend_chart.dart`, so a `nutrition → stats` import exists until 4c | move `scrollable_trend_chart.dart` to `lib/widgets/chart/` too | D-532 wants the dependency one way only, but the Predicted Files do not list that move, and Rule 8 forbids adding scope | pending |
| A-2 | 1 | `NutritionTrendCard` renders the whole `OmniSurface`; "body only" was read as "not the header" | render only the inner `Column` | keeps the tree byte-identical between the two hosts, which is what S-1110(a) asserts | pending |
| A-3 | 1 | The screen's subtitle is `'Full history'` | no subtitle; `'All time'` | `OmniBackHeader`'s other hosts carry a subtitle, and this names the one difference from the Stats card | pending |
| A-4 | 1 | Dropped the unused `context` parameter from `_buildNutritionSection` and `_buildMacrosChart` | keep it for symmetry | it was already unused after the move; the analyzer would flag a kept-but-unread parameter | pending |
| A-5 | 1 | Left the pre-existing `_ChartSeries` warning in `stats_screen.dart` and the two private primitive copies in `exercise_progress_screen.dart` | fix both | both files are outside the Predicted Files; Rule 5's bar is "none new" and the total is unchanged at 199 | pending |
| A-6 | 2 | The S-1109 entry-point assertion lives in `test/fuel_row_screen_test.dart`; its toggle half stays in Phase 1's `test/nutrition_trend_screen_test.dart` (line 235) | put both halves in the new file | the toggle is Phase 1's screen, the entry point is this phase's row; splitting on the changed surface keeps each file owned by one phase | pending |
| A-7 | 2 | S-1112 asserts "no chip inside the Fuel section, screen chip count unchanged at 5", not "exactly one chip" | assert the literal one-chip reading | `StatsWindowChip` uses one constant key, so a populated screen already renders five (four legacy headers + the first Instruments header, S-1011); the literal reading is untestable and the intent is what D-528 pins | pending |
| A-8 | 2 | M4's criterion names S-1107(b) as the failing leg; the mutation actually fails S-1107(a) plus S-1103(a), S-1103(b), S-1104 and S-1111 | edit the criterion | (b) is a 14-day-old row, hidden under both constants, so it cannot fail; the mutation is still caught by the assertion that pins the boundary the constant governs. Recorded, not worked around | pending |
| A-9 | 2 | `computeFuelSummary` reads sessions through the service's own `_loadHistory()`, not `WorkoutState.getAllSessions()` | pass sessions in from the screen | step 2 names `getAllSessions()`, but that is a `WorkoutState` method the service cannot reach; `_loadHistory()` is the same repository read the rest of the service uses, and M5 proves it returns in-progress sessions so the predicate is load-bearing | pending |
| A-10 | 2 | The comparison dashes when the **whole-unit** delta is 0, stricter than `formatNativeChange`'s raw `delta == 0` | match the formatter exactly | the row prints whole units, so a raw-only test would render "↑ +0 kcal"; no register scenario covers the branch | pending |
| A-11 | 2 | The residue sweep was enumeration-based (`git-status` + directory listing + the argument that a new name in an unlisted file would show up as a change), not a text search | run the planned search | this checkout exposes no content-search primitive to the executor (`grep`/`sed`/`awk` are denied and the tool set has none), so the sweep cannot be a search here; the reviewer should re-run it with a search tool | pending |

---

## Feedback

**Review 1 — CHANGES_REQUESTED.** Findings: `2026-10-01-04b3-stats-pr4b3-fuel-row-plan.review.md`
(2 blockers, 2 majors, 4 minors, 3 nits; the code satisfies every owner-confirmed Fuel rule).

Fix in this round: (1) add the missing `S-1110(b)` test — the zero-session empty state winning over the Fuel
row, in `test/nutrition_trend_screen_test.dart`; (2) correct `docs/stats_screen.md`'s pointer to it;
(3) re-record the evidence sentence that claims it was already asserted; (4) delete the three false
soft-window comments in the nutrition screen and card; (5) swap the duplicated reserved-size constant in
`exercise_progress_screen.dart` for the shared one and amend D-533 to name the divergent single-point card;
(9) assert the absence of a window chip inside the Fuel section, not just a chip count; (10) fix M4's cited
scenario. Deferred to 4c: the `scrollable_trend_chart.dart` move, narrow-width and scaled-text coverage, the
`data_models.md` row, and the row's accessibility label.

**Round 1 applied.** (1)–(5) and (10) are done; the new `S-1110(b)` group is green on both harnesses and its
mutation proof is M6 in the evidence file. **(9) needed no edit:** the Fuel-section chip assertion the finding
asks for already exists in `test/fuel_row_screen_test.dart` (S-1112) — `find.descendant(of: _fuelSection,
matching: find.byKey(Key('stats_window_chip')))` is `findsNothing`, and that key is the `StatsWindowChip`'s own,
so the count assertion was never the only guard. The four deferred items are listed under "Carried into 4c"
in the series index.

*The owner writes here only to redirect product behaviour, contradict a D-x, or change scope; that is the only
thing that re-invokes the planner. **O-10 is the one entry the owner should answer** — it is a product choice
(whether the Fuel row follows the screen's selected period or stays today-anchored), not a technical one, and
the plan runs on the recorded default until then.*

---

## Doc-claim → test table

Every behavioural sentence the docs will gain, and the test that must prove it. Test names are the real
files and scenario ids. A claim with no test does not ship; a doc that names a type, file or constant that
does not exist is a blocker.

| Doc | Claim it will make | Test that will prove it |
|---|---|---|
| `docs/stats_screen.md` | the Fuel window is the 7 calendar days ending today, by calendar arithmetic | S-1101, S-1107 |
| `docs/stats_screen.md` | averages divide by logged days only, and the row shows `'<n>/7 days logged'` | S-1101, S-1102 |
| `docs/stats_screen.md` | a field with a target is compared with it; a field without one with the previous 7 days | S-1103, S-1104 |
| `docs/stats_screen.md` | the training/rest split partitions the logged days, and an empty side shows `'—'` | S-1105, S-1106 |
| `docs/stats_screen.md` | the row is hidden when the last 14 days have no logs, and the zero-session empty state wins | S-1107, S-1110(b) |
| `docs/stats_screen.md` | the previous week's absence is not a comparison against zero | S-1108 |
| `docs/stats_screen.md` | the Fuel section sits between the Instruments sections and the legacy sections, with no window chip | S-1112 |
| `docs/stats_screen.md` | a window with no logged day reads `'0/7 days logged'` and `'—'` everywhere | S-1111 |
| `docs/stats_screen.md` | the NUTRITION section renders the extracted `NutritionTrendCard`, unchanged | S-1110(a) |
| `docs/stats_screen.md` | `kFuelWindowDays` / `kFuelVisibilityDays` are the Fuel window and visibility constants | S-1101, S-1107 |
| `docs/widget_catalog.md` | the Fuel section widget, the extracted nutrition trend card and the trend screen, with their paths | S-1101, S-1110(a) |
| `docs/navigation_and_screens.md` | the Fuel row opens the full-history nutrition trend screen | S-1109 |
| `docs/state_management/nutrition_state.md` | only if the row adds state there; expected unchanged, and the evidence file records that | — (a no-op needs no test; a change needs one, and Phase 2 writes it) |

The scenario ids above resolve to `test/fuel_row_screen_test.dart` for S-1101…S-1108, S-1111 and S-1112, and
to `test/nutrition_trend_screen_test.dart` for S-1109 and S-1110.

---

## Open questions (defaults applied)

Each is a product choice the planner had to make to keep the recorded decisions executable. The plan runs on
the **default**; the owner can veto any of them and the plan is amended by superseding ledger entries.
Numbers in brackets are the question's number in the superseded single 4b plan. Q1–Q6 restate D-520…D-525;
Q7–Q9 are Iteration 1's.

Owner answers, 2026-10-01: Q1 (the Fuel window is the 7 calendar days ending today), Q3/Q4 (a training day is a day with a finished session; a side with no logged days shows a dash), Q9 (a window with no logged day still shows the row as '0/7 days logged' with dashes) and Q7 (the nutrition card is moved to its own screen, not reimplemented) are confirmed as written.

1. **[Q17] The Fuel window (D-520).** Default: the 7 calendar days ending today, previous range the 7 before.
2. **[Q18] A logged day (D-521).** Default: ≥1 `ConsumedFood` row for that `dateMs`; averages over logged
   days only.
3. **[Q19] A training day (D-522).** Default: a session with `endedAtMs != null` starting that day; a running
   session is not a training day.
4. **[Q20] The training/rest split (D-523).** Default: partitions the window's logged days, a both-day counts
   as training, and an empty side shows `'—'`.
5. **[Q21] The Fuel target (D-524).** Default: today's target; calories compared when `> 0`, protein when
   `> 0`; no target ⇒ previous-7 comparison only.
6. **[Q22] The Fuel row's visibility (D-525).** Default: hidden when the last 14 days have no food, and the
   zero-session empty state wins over it.
7. **[Q23] The nutrition trend extraction (D-526).** Default **taken** by D-532: a new full-history screen
   holding the moved card, pushed with `OmniNavigator.push` (no new route constant). The card is moved, not
   reimplemented, so the pack's "tapping opens the existing trend" holds without deleting the old card
   (4c's job). *Alternative:* keep the card in place and open the in-place trend.
8. **[Q24] The Fuel section's placement and chrome (D-528).** Default: **its own section**, after the
   Instruments sections and above the legacy sections, header `'Fuel'` in title case, and **no**
   `StatsWindowChip` (D-520's window is today-anchored; the chip names the screen's selected window).
   *Alternatives:* a fifth row inside the Instruments list (rejected — not an exercise, and D-507's cap is
   per exercise section); a chip showing the screen's window (rejected — it would misstate the window); no
   header (rejected — every other section has one). S-1112 asserts the choice.
9. **[Q25] A window with no logged day (D-529, S-1111).** Default: the row still renders — D-525's visibility
   test is the 14-day range, not the 7-day window — reading `'0/7 days logged'` with `'—'` everywhere, never
   `'0 kcal'` / `'0 g'` and never a division by zero. *Alternative:* hide the row when the window is empty
   (rejected — the section would blink in and out for a user who logged ten days ago, and D-525 already
   defines the hide rule).

Questions 1–16 of the superseded plan are 4b's and 4b2's; 26 (the plan/evidence layout) is obsolete.

**The owner answered Q1, Q3/Q4, Q7 and Q9 on 2026-10-01; none of the others were answered** — the brief forbids asking. Each runs on its default,
each is a product choice rather than a technical one, and each is vetoable: the planner supersedes the
affected D-x rather than editing it. O-10 (§Open Items) is the one with a visible cross-screen consequence.
