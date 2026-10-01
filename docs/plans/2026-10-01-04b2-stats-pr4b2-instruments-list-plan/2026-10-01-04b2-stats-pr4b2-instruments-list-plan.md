# Stats PR 4b2 — the Instruments list on the main Stats screen

> **Status:** READY — defaults applied; §Open questions lists every product choice the planner had to make,
> with the default this plan runs on.
> **Next handoff:** `@developer` — Phase 1 (the Instruments list on the Stats screen).
> **Series:** Stats PR 4 → `docs/plans/2026-09-30-04-stats-pr4-index.md`.
> **Provenance:** this plan, `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/…` (the Instruments
> data) and `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/…` (the Fuel row, NOT READY) replace the
> superseded single 4b plan, which measured 1,016 lines against the 800-line hard limit in
> `.github/agents/pr_scope_budget.md` §1. Decisions and scenarios keep their original ids (D-5xx, S-10xx);
> nothing here is renumbered.
> **Base:** `develop`. All work happens in place on `develop`. Executors never branch, stage, commit, merge
> or push (`docs/global_conventions.md`; index §Branch policy).
> **Depends on:** 4b's Phases 1 and 2 **merged on `develop`**. Phase 1 here consumes
> `getSensorSummariesBySession()`, `computeInstrumentSections()` and `formatNativeChange()`. Do not start
> this PR against a tree that does not have them.
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` §"5. Instruments
> Layer: Native Metric per Effort Kind, Plus a Fuel Row" (the prompt block, its 11 Acceptance Criteria and
> its 7 Unit-Tests-Required bullets).
> **Evidence:** `docs/plans/2026-10-01-04b2-stats-pr4b2-instruments-list-plan/2026-10-01-04b2-stats-pr4b2-instruments-list-plan.evidence.md`
> — executors write baselines, suite output, mutation proofs and surface-height bumps there. **Never in this
> file.**
> **Binding conventions:** `docs/global_conventions.md`; `docs/design_system.md` (card-header typography,
> tokens, spacing, animation rules); `docs/navigation_contract.md` (`OmniNavigator` only);
> `docs/widget_catalog.md`, `docs/stats_screen.md`. Read them; they are not restated here.

---

## Scope check

Measured against `.github/agents/pr_scope_budget.md` (hard: >800 plan lines, >5 phases, >1,500 predicted
production lines; soft: >500 plan lines, >3 phases, >1 track, >20 decisions, >30 scenarios; **two or more
soft signals ⇒ split**).

| Signal | PR 4b2 as planned | Limit |
|---|---|---|
| Phases | 1 | >3 is soft |
| Tracks | 1 (the phone) | >1 is soft |
| Decisions defined here | 4 (D-503, D-507, D-510, D-515) | >20 is soft |
| Scenarios | 7 (S-1001, S-1011, S-1012, S-1014…S-1017) | >30 is soft |
| Predicted production lines | ~330 (excluding tests and docs) | >1,500 hard |
| Plan length | this file, 594 lines (measured by reading it back) | >500 soft |

**One soft signal (plan length, 594 against the 500 soft limit). No hard limit. Within budget.**

Under `pr_scope_budget.md` §1 one soft signal is a flag, not a split: two or more are required. This plan is
one phase, one track, and the length is mostly the verbatim scenario fixtures and the carried ledger — the
executable content is one phase with eleven steps.

**The split, and why (D-501, defined in 4b).** The superseded file planned the pack's item 5 as one PR: 3
phases, ~700 predicted production lines, and 1,016 plan lines against an 800-line hard limit. The split is
three plans; this one is the **visible** half — the four widgets, the cap, the screen edit and the legacy
test re-stabilisation. 4b (the data) ships first and is independently green; 4b3 (the Fuel row) is not
planned yet.

### Series index (this plan is 4b2 only)

| PR | Scope | Depends on | Plan |
|---|---|---|---|
| 4a | DONE (implemented on `develop`): the shared exercise-metric layer, Records & Trends, Exercise Progress, the bulk round-instance read. | — | `docs/plans/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.md` |
| 4b | The Instruments **data**: the bulk sensor-summary read, the two value types, `computeInstrumentSections`, the two shared formatters. No visible change. | 4a | `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.md` |
| **4b2** | The Instruments **list** on the main Stats screen: the four widgets, the section/row rendering, the cap and `Show all (n)`, the legacy wrapper key, the window-chip extraction, the legacy test re-stabilisation. Additive — the old sections stay. | 4b (its Phases 1–2 merged), 4a | this file |
| 4b3 | The **Fuel row** on the main Stats screen: 7-day averages vs the user's target and vs the previous 7 days, logged-days indicator, training-day vs rest-day split, hidden after 14 days without logs, tap-through to a full-history nutrition trend. Additive. **NOT READY** — its decisions (D-520…D-527) and scenarios (S-1101…S-1110) are recorded; its phases are written when its turn comes, against the code as it is then (`pr_scope_budget.md` §3). | 4b2 (shares the row/header widgets and the screen edit), 4a (`computeNutritionTrend`) | `docs/plans/2026-10-01-04b3-stats-pr4b3-fuel-row-plan/2026-10-01-04b3-stats-pr4b3-fuel-row-plan.md` |
| 4c | Removal of the five old chart sections, their top-N constants, their tests, and the doc rewrite. | 4b, 4b2, 4b3 | not planned |

---

## What this PR does

The Stats screen today ends its ALL TIME card and then stacks five chart sections: STRENGTH (top 3 lifts),
CARDIO, ISOMETRIC, SPORTS (top 2 each) and NUTRITION. Everything outside those top-N slots is invisible.
This PR adds, **above** those sections and below the ALL TIME card, a dense **Instruments list**: four
sections — Resistance, Cardio, Isometric, Sports — each listing **every** exercise trained in the current
window, most frequently trained first, up to 5 rows with a `Show all (n)` control. Each row shows the
exercise name, its native value (the same value Records & Trends and Exercise Progress already show), the
change against that exercise's own previous comparable value, and a small trend line. Tapping a row opens
the existing **Exercise Progress** screen (4a).

Nothing is removed and nothing existing changes behaviour: the five old sections, their constants, their
code and their tests stay exactly as they are until 4c. The only structural change to the old subtree is
one wrapper key (D-503) so tests can address it unambiguously while both layouts are on screen.

**Why the list goes above the old sections rather than below them.** The pack's product intent is that the
screen reads as dense instruments rather than a stack of charts. Putting the list first delivers that one
PR early, keeps the layout stable across 4b2 → 4c (4c only deletes what is below it), and costs one
mechanical edit in the existing widget tests: several of them pump at a fixed surface height and assert
legacy content that the taller list pushes below the fold (Step 10). Appending the list at the bottom would
avoid that churn but ship a screen whose first impression is unchanged.

---

## Decision Ledger — PR 4b2

Numbered D-5xx, continuing the series. Immutable once written: a change is a new superseding entry, never an
edit. These four entries were written in the superseded single 4b plan and are carried here **verbatim**.

| # | Decision (enforceable contract) |
|---|---|
| **D-503** | **Additive, and one keyed boundary.** The five old sections, their builders, their constants (`kTopLiftCount`, `kTopCardioCount`, …) and their tests stay exactly as they are. The Instruments list renders **between the ALL TIME card and the old sections**. In `StatsScreen.build`'s non-empty branch, the list's children are spread first, then `const SizedBox(height: 24)`, then the whole existing legacy child list is wrapped in **one** `Column(key: const Key('stats_legacy_sections'), crossAxisAlignment: CrossAxisAlignment.stretch, children: <the existing children, unchanged>)`. That key is the only structural marker this PR adds to the old subtree, and it exists so tests can address the old layout unambiguously while both layouts are on screen. |
| **D-507** | **The cap.** `const int kInstrumentRowCap = 5;` declared in `lib/features/stats/widgets/instrument_list.dart`. A section with ≤5 rows renders no control. A section with more renders a text control `'Show all (n)'` where `n` is the section's total row count; tapping it reveals every row and the control's label becomes `'Show less'`; tapping again collapses. The expanded state is per section and per mount (local UI state, which survives a reload). |
| **D-510** | **The sparkline.** One point per training day in the window on which the exercise has a readable value, oldest first, taken from `summary.points` (which already has that shape). Drawn by `CustomPaint` in `lib/features/stats/widgets/instrument_sparkline.dart`, 56 × 24 logical pixels, one polyline through the points normalised to the box's own min/max (a flat series draws a centred horizontal line), stroke `themeColors.primary`, `strokeWidth: 1.5`, no fill, no axes, no labels, no animation. **Not rendered at all** when the row has fewer than 2 points (one point is not a trend). |
| **D-515** | **The row's destination.** Tapping a row calls `OmniNavigator.push` to the existing `ExerciseProgressScreen(workoutState: …, settingsState: …, exerciseId: row.summary.exerciseId)`. `ExerciseProgressScreen` gains no parameter and no second constructor; no new route constant; no raw `MaterialPageRoute`/`PageRouteBuilder` outside `lib/core/navigation/` (`test/navigation_contract_enforcement_test.dart`). |

**Decisions this plan consumes but does not define** — they are contracts of the data this plan renders, and
they are enforced by 4b's tests:

| # | Defined in | What this plan must honour |
|---|---|---|
| **D-504** | 4b | The section order it receives is already ranked by distinct training days in the window, descending, ties in `ExerciseSection.values` order. The list **renders the order it is given**; it does not re-sort. |
| **D-505** | 4b | A section with ≥1 row renders; a zero-valued row renders with the zero figure and **no sparkline**. |
| **D-506** | 4b | The row order it receives is training days desc, then name, then id. The list does not re-sort. |
| **D-508** | 4b | The change chip renders `formatNativeChange(metric, delta, settings)`; `'—'` when there is no comparable previous value; colour and typography are `_buildGroupComparisonChip`'s; fixed `width: 92`, right-aligned. |
| **D-509** | 4b | The previous range is computed in the service by calendar arithmetic. The list computes nothing. |
| **D-511, D-512** | 4b | Cadence and average heart rate arrive on the row as optional strings. The row **joins the parts that exist** and never substitutes a zero. |
| **D-514** | 4b | The screen calls `computeInstrumentSections(window: window)` **once** in `_loadData()` inside the same `setState`; `build` does no computation. |
| **D-516a** | 4b | The secondary label comes from `nativeSecondaryLabel` in `native_value_format.dart`. This plan does not touch `native_value_format.dart`. |
| **D-516b** | this plan | `StatsWindowChip` is extracted from `StatsScreen._buildWindowChip` with the identical key and text; the four legacy headers and the first Instruments section header use it. |

**Ledger entries carried forward from 4a that bind this PR:** D-401 (the split), D-402 (single release, no
migration, no flag), D-403 (one section per exercise, by effort kind, never by session modality),
D-405…D-408 (the native values the rows show), D-409 (nothing here creates a PR event), D-413
(`OmniNavigator`), D-416 (doc reconciliation).

---

## Feature invariants that bite in this PR

Project-wide rules live in `docs/global_conventions.md`; these are the ones this PR can break. Numbers match
the series list in 4b so a cross-reference stays valid.

1. **The old layout is untouched.** No behaviour change to the five old sections, their constants or their
   tests. The only structural change to them is the D-503 wrapper key. Proven by S-1015.
2. **Navigation goes through `OmniNavigator`.** No raw `MaterialPageRoute`/`PageRouteBuilder` outside
   `lib/core/navigation/`; `test/navigation_contract_enforcement_test.dart` enforces it.
3. **One number, one rendering.** Every figure in a row is formatted by
   `lib/features/stats/widgets/native_value_format.dart`; no widget formats a number itself.
4. **Absence is not zero.** A missing cadence, heart rate, sparkline or change indicator renders nothing (or
   `'—'`), never `0`, and is never replaced by a plausible default.
5. **Nothing new is persisted, and nothing new is added to the data layer.** This PR touches no repository,
   no model, no service: `scripts/sqlite_schema.sql`, `scripts/sqlite_seed.sql` and `test/db_seed_test.dart`
   pass **unmodified**, and `test/db_seed_test.dart` is not a predicted file.

---

## Requirements

R-1 (pack AC-1, AC-12) The Stats screen shows an Instruments list of four sections — Resistance, Cardio,
Isometric, Sports — covering every exercise trained in the current window, above the old sections.
R-4 (AC-6) Up to 5 rows per section with `Show all (n)`; the list renders the row order it is given (D-506).
R-7 (AC-8) Tapping a row opens Exercise Progress for that exercise, with history older than the window.
R-8 (AC-11, deferred) The five old chart sections still appear, unchanged; they are removed in 4c.
R-10 (pack Unit Tests) The weighted/bodyweight classification tests in `test/stats_progress_test.dart` must
pass **unmodified** — this PR touches no test that guards live legacy code.

---

## Acceptance Criteria → scenarios

| AC | Statement | Scenario(s) | PR |
|---|---|---|---|
| AC-1 | squats + treadmill run + plank + BJJ → four sections with e1RM, estimated pace, cadence, longest hold, rounds and round-minutes | S-1001 (render), S-1007/S-1008 (values, 4b) | 4b2 |
| AC-5 | a user who only lifts sees only Resistance | S-1013 (model, 4b), S-1005 | 4b / 4b2 |
| AC-6 | a section with 8 exercises shows 5 rows and `Show all (8)`, revealing the other 3 | S-1016 | 4b2 |
| AC-8 | a row tap opens Exercise Progress with history older than the window | S-1014 | 4b2 |
| AC-11 | the old sections no longer appear on the main Stats screen | deferred to 4c — they **must** still appear here (S-1015) | 4c |
| AC-12 | exercises outside the old top-N now appear as rows | S-1010 (model, 4b), S-1001 (render) | 4b / 4b2 |

AC-1, AC-2, AC-3, AC-4, AC-7, AC-9, AC-10 are 4b's and 4b3's; see those plans' tables.

---

## Scenarios — PR 4b2 (S-1001, S-1011, S-1012, S-1014…S-1017)

Stable ids; never reused. Fixtures are stated as populations because an unstated population becomes a bug.
These are the superseded plan's entries, carried **verbatim**. S-1002…S-1010, S-1013 and S-1018 are 4b's;
S-1101…S-1110 are 4b3's.

### S-1001: the pack's flagship fixture — four sections in one window
- **Fixture:** one repository, 14-day window, four completed sessions inside it: (a) a resistance session
  with a `set` effort on exercise `ex-squat` named `'Back Squat'`, one entry 5 reps × 100 kg; (b) a cardio
  session with a `timed` effort on `ex-run` named `'Treadmill Run'`, one finished instance 600 s with a
  distance observation marked estimated; (c) an isometric session with a `drill` effort on `ex-plank`
  named `'Plank'`, one finished instance 90 s; (d) a sports session with a `round` effort on `ex-bjj`
  named `'BJJ'`, three round instances of 180 s. Plus, adversarially, a second exercise `ex-row` named
  `'Back Squat'` (a duplicate name, different id) with one `set` effort, and an exercise `ex-old` named
  `'Deadlift'` trained 20 days ago and never inside the window.
- **Trigger:** mount `StatsScreen` on a tall surface; allow `_loadData` to settle.
- **Flow:** none (render only).
- **Expected outcome:** exactly four Instruments sections, in the order Resistance, Cardio, Isometric,
  Sports (each one training day ⇒ D-504's tie order); `'Back Squat'` appears **twice** under Resistance
  (two ids, adjacent, id ascending); `'Deadlift'` appears nowhere; the Resistance rows carry an
  `estimatedOneRepMax` figure with the `est.` marker; the Cardio row carries a pace figure ending in
  `' est.'`; the Isometric row shows `'Total hold …'`; the Sports row shows rounds with `'Total time …'`.
- **Edge case of:** none.

### S-1011: the window is the existing window, and the chip says so
- **Fixture:** a training period that qualifies as the active window, plus training inside and outside it.
- **Trigger:** mount `StatsScreen`; settle.
- **Flow:** none.
- **Expected outcome:** the Instruments sections list exactly the exercises the existing sections' window
  yields (same `StatsWindow`, one resolution per load); the Instruments header carries the window chip with
  the text `'· <window.label>'`, identical to the legacy headers' chip text.
- **Edge case of:** S-1001.

### S-1012: an empty window with a non-empty history
- **Fixture:** completed sessions only 30+ days back; nothing in the window.
- **Trigger:** mount `StatsScreen`; settle.
- **Flow:** none.
- **Expected outcome:** no Instruments section renders, no `'Show all'` control renders, the ALL TIME card
  and the five legacy sections render exactly as they do today, and nothing throws.
- **Edge case of:** S-1005.

### S-1014: a row opens Exercise Progress for that exercise
- **Fixture:** the row's exercise has history **older than the window** (sessions 20 and 40 days back) and
  one session inside it.
- **Trigger:** tap `Key('instrument_row_<exerciseId>')`.
- **Flow:** `OmniNavigator.push` → `ExerciseProgressScreen`.
- **Expected outcome:** the Exercise Progress screen for that exercise is on screen; its chart covers the
  older sessions (a session label for a day older than the window is present); tapping a **different** row
  opens that other exercise.
- **Edge case of:** S-1001.

### S-1015: the old layout is untouched while both layouts are on screen
- **Fixture:** the population that makes all five legacy sections render (one lift, one cardio exercise,
  one isometric hold, one sports drill, one logged day of food) plus Instruments data.
- **Trigger:** run `test/screen_widget_test.dart`, `test/header_standardization_test.dart` and
  `test/stats_progress_test.dart` unmodified except for the surface-height bumps Step 10 records.
- **Flow:** none.
- **Expected outcome:** every pre-existing assertion about `'STRENGTH'`, `'CARDIO'`, `'ISOMETRIC'`,
  `'SPORTS'`, `'NUTRITION'`, `'ALL TIME'`, the window chip, the inter-section 24dp gaps, the legacy
  chart axes and the legacy empty states passes; the PR parity tests are unmodified and green.
- **Edge case of:** none.

### S-1016: the row cap and its control
- **Fixture:** (a) a section with exactly 5 exercises; (b) a section with 6; (c) a section with 8.
- **Trigger:** mount `StatsScreen`; settle; tap the control; settle; tap again; settle.
- **Flow:** expand / collapse.
- **Expected outcome:** (a) 5 rows, no control; (b) 6 rows in the model, 5 rendered, `'Show all (6)'`
  present, tapping renders the 6th row and the label becomes `'Show less'`, tapping again returns to 5 and
  `'Show all (6)'`; (c) `'Show all (8)'` and all 8 after the tap. The cap applies per section, not to the
  list.
- **Edge case of:** S-1010.

### S-1017: the sparkline's visibility rule
- **Fixture:** (a) an exercise with 3 training days in the window; (b) an exercise with exactly 1; (c) an
  exercise with 0 readable points (the zero-valued row).
- **Trigger:** mount `StatsScreen`; settle.
- **Flow:** none.
- **Expected outcome:** (a) `Key('instrument_sparkline_<id>')` is present and paints; (b) and (c) it is
  **absent** — no empty box, no placeholder line, no reserved space that shifts the row.
- **Edge case of:** S-1010.

---

## Iteration 1

### Executor block (read before Phase 1)

**Step 0a — read these first.** `docs/global_conventions.md`; `docs/design_system.md` (§card-header
typography, tokens, spacing, animation rules); `docs/navigation_contract.md`; 4b's plan (the contracts this
plan consumes); this file's §Decision Ledger, §Feature invariants, §Scenarios and the phase you are
implementing. Docs are claims, not truth: if `lib/` disagrees with a doc, `lib/` wins and you note the
disagreement in the evidence file.

**Step 0b — baseline before you touch anything.** Run `gateway.sh lint` and `gateway.sh test` and copy the
**verbatim** summary lines into the evidence file (§1). The tree this PR starts from is expected to read
`199 issues found.` with 0 errors, and `+3153 ~1: All tests passed!`. If the numbers differ — in particular
if they include 4b's new tests, which they will once 4b is merged — record what you actually saw and say so.
A different baseline is information, not a failure.

**Step 0c — the shell.** Only `.github/copilot/scripts/macos/gateway.sh` may be executed: `gateway.sh list`,
`lint`, `test`, `build`, `codegen`, `pub-get`, `format <paths>`, `git-status`,
`git-diff [<ref>] [--stat|--name-only|--name-status|--cached] [-- <path>...]`, `git-log [<count>] [<ref>]`,
`git-show <ref> [--stat]`. There is **no** `grep`, `cp`, `sed`, `mv`, `rm`, `/tmp` or plain `git` for you.
Use the built-in search tool for source sweeps, `view` for reads, and `gateway.sh git-diff --stat -- <path>`
for footprints. A command that fails twice the same way: stop and report.

**The nine rules.**

1. **Stay in the phase's Predicted Files.** A file not listed is out of bounds; a listed file you did not
   need to touch is a finding for the reviewer, not a silent omission. Record both in the evidence file.
2. **Red first.** Write the phase's tests before its production code, run them, and paste the failing output
   in the evidence file. A test that passes before the change proves nothing.
3. **Mutation proof.** Every phase with a rule to protect ends with the inverse-edit mutations listed in its
   Done Criteria: note the file's `git-diff`, make the listed edit with the edit tool, show the named test
   **failing**, apply the exact inverse, confirm the diff is back, run again, show it passing. Record the
   exact output. Mutations target **tracked** files — an edit to an untracked new file does not appear in
   `gateway.sh git-diff`, so use the file the phase names.
4. **Green means the suites ran.** `flutter analyze` passing is not a test run. Run `gateway.sh test`, read
   the pass/fail counts, paste them. A hang, a timeout or a killed run is a failure — say so.
5. **The analyzer bar is "none new".** 0 errors and no more than the baseline issue count. Every file the
   phase touches has 0 issues of its own.
6. **Docs trail code by zero phases.** This phase updates the docs it invalidated, and its Done Criteria
   include the claim-to-test rows from §Doc-claim → test table.
7. **Ambiguity never stops you.** Pick the option most consistent with the Ledger and the invariants, then
   log it in §Assumption Log of this file as `A-n: decision — options considered — why`. The planner
   ratifies or reverts it.
8. **No new dependency, no new asset, no schema change, no migration, no feature flag.**
9. **Never branch, stage, commit, merge or push.** Work in place on `develop`.

**Doc checklist for this PR** (Phase 1 owns every item):
- [x] `docs/stats_screen.md` — the Instruments list, `kInstrumentRowCap`, the extracted `StatsWindowChip`,
      the legacy-wrapper key, the row anatomy (with its exact strings)
- [x] `docs/widget_catalog.md` — the four new widgets with their paths
- [x] `docs/navigation_and_screens.md` — the `ExerciseProgressScreen` entry points
- [x] `docs/design_system.md` — the Stats card-header inventory
- [x] No file in `docs/` exceeds 64 KiB (`test/docs_indexing_contract_test.dart`)
- [x] Every claim added above has a named test in §Doc-claim → test table

---

### Phase 1: The Instruments list on the Stats screen (@developer)

**Why it is one phase:** every step is on the same change surface — the four new widgets plus the screen
edit — and the widget test is what proves the whole thing. Splitting it would produce two phases neither of
which is independently green. It is the last phase of the series' visible half; 4b3 builds on the widgets it
adds.

**Prerequisite:** 4b's Phases 1 and 2 are merged. `getSensorSummariesBySession`,
`computeInstrumentSections`, `InstrumentSectionData`, `InstrumentRow`, `nativeSecondaryLabel` and
`formatNativeChange` exist and their tests are green.

1. [x] Create `lib/features/stats/widgets/window_chip.dart`: `class StatsWindowChip extends StatelessWidget`
       taking the resolved `StatsWindow`, rendering the **identical** `Text` that
       `StatsScreen._buildWindowChip` renders today — `key: const Key('stats_window_chip')`,
       `'· ${window.label}'`, `theme.textTheme.labelSmall` + `OmniTheme.colors.textMuted` + italic,
       `maxLines: 1`, `overflow: TextOverflow.ellipsis` (D-516b).
2. [x] Create `lib/features/stats/widgets/instrument_sparkline.dart`: `class InstrumentSparkline` taking the
       row's points and the theme colours, rendering a `CustomPaint` of 56 × 24 with D-510's painter
       (normalised polyline, flat series centred, `themeColors.primary`, `strokeWidth: 1.5`, no fill, no
       axes, no labels, no animation), and rendering `const SizedBox.shrink()` when there are fewer than 2
       points.
3. [x] Create `lib/features/stats/widgets/instrument_row.dart`: `class InstrumentRowTile` rendering one row
       as
       `InkWell(key: Key('instrument_row_<exerciseId>'))` → `Row[ Expanded(Column[ Text(name, titleSmall, maxLines 1, ellipsis), if (secondary != null) Text(secondary, labelSmall + textMuted, maxLines 1, ellipsis) ]), InstrumentSparkline(key: Key('instrument_sparkline_<exerciseId>')), SizedBox(width: 12), Column(crossAxisAlignment: end)[ Text(formatNativeValue(best), titleSmall + w600), InstrumentChangeChip(key: Key('instrument_change_<exerciseId>')) ] ]`,
       where the secondary line is the parts that exist joined by `' · '` in this order: 4a's secondary
       (`nativeSecondaryLabel(best.secondaryMetric)` + `' '` + `formatNativeSecondary(best)`, omitted when
       either is null), then average heart rate (`'<n> bpm'`, D-512), then cadence
       (`'<n> steps/min'`, D-511). So a Cardio row with both reads `'145 bpm · 120 steps/min'`, a Sports row
       reads `'Total time 15 min · 148 bpm'`, an Isometric row reads `'Total hold 2:30'`, and a Resistance
       row has no secondary line (its added weight is inside the primary figure).
4. [x] Create the change chip as a small private widget in `instrument_row.dart` (or a sibling file in the
       same folder): `'—'` in `textMuted` when there is no comparable previous value, otherwise
       `'↑ +<d>'` / `'↓ -<d>'` / `'—'` from `formatNativeChange(metric, delta, settings)`, coloured and
       weighted exactly like `_buildGroupComparisonChip` in `lib/features/session/session_summary_screen.dart`
       (D-508), right-aligned in a fixed `width: 92`.
5. [x] Create `lib/features/stats/widgets/instrument_list.dart`:
       - `const int kInstrumentRowCap = 5;`
       - `class InstrumentList extends StatefulWidget` taking the ordered `List<InstrumentSectionData>`,
         the window and the callbacks the screen supplies (row tap, settings).
       - Each section renders `OmniCardHeader(title: <'Resistance'|'Cardio'|'Isometric'|'Sports'>)` with
         `StatsWindowChip` in the actions slot of the **first** section only, a `SizedBox(height: 8)`, the
         rows (capped), and, when the section has more rows than the cap, a text control keyed
         `Key('instrument_show_all_<section>')` labelled `'Show all (<n>)'` / `'Show less'`.
       - **Casing is a decision, not a detail:** the four Instrument headers are title case
         (`'Resistance'`, `'Cardio'`, `'Isometric'`, `'Sports'`), matching 4a's Records & Trends group
         labels, which keeps them visually and testably distinct from the legacy uppercase chart headers
         (`'STRENGTH'`, `'CARDIO'`, …) while both are on screen. 4c keeps the same strings after the legacy
         sections are deleted.
       - The section's expanded state is local to the section widget and keyed on the section, so expanding
         one section never expands another.
6. [x] In `lib/features/stats/stats_screen.dart`:
       - add a `List<InstrumentSectionData> _instrumentSections = const []` field;
       - in `_loadData()`, after the existing `computeTotals()` / `computeProgressData()` /
         `computeNutritionAdherence()` calls, call
         `final instrumentSections = await progress.computeInstrumentSections(window: window);` and assign
         it inside the same `setState` (one window resolution, one load — D-514);
       - in `build`'s non-empty branch, spread the `InstrumentList` (with a `SizedBox(height: 24)` after it)
         between `_buildAggregateCard` and the legacy children, and wrap the legacy children in
         `Column(key: const Key('stats_legacy_sections'), crossAxisAlignment: CrossAxisAlignment.stretch, children: <the existing children, unchanged>)` (D-503);
       - replace `_buildWindowChip` with `StatsWindowChip` in the four legacy headers and delete the private
         builder (D-516b);
       - the row tap pushes `ExerciseProgressScreen(workoutState: widget.workoutState, settingsState: widget.settingsState, exerciseId: row.summary.exerciseId)` through `OmniNavigator.push` (D-515).
7. [x] Create `test/instrument_list_screen_test.dart` on the `test/records_and_trends_screen_test.dart`
       pattern (harness factories, a tall surface constant like `const Size(400, 2400)` set in `pump` with
       `addTearDown(() => tester.binding.setSurfaceSize(null))`, and a `_textsUnder(Finder)` helper). Cover
       S-1001, S-1011, S-1012, S-1014, S-1015's Instruments half, S-1016, S-1017. For S-1001 assert the
       section headers' order and the rows' structure, and assert each row's primary text against
       `formatNativeValue(summary.best, settings)` using the value the same window's `computeExerciseMetrics`
       reports — do not hand-copy a figure the service computes.
8. [x] Add the entry-point guard to `test/records_and_trends_screen_test.dart` beside the existing
       `StatsScreen`-is-the-only-constructor guard (line ~648): a structural test asserting that the set of
       files in `lib/` constructing `ExerciseProgressScreen` is exactly
       `{lib/features/stats/records_and_trends_screen.dart, lib/features/stats/widgets/instrument_list.dart}`
       (exact list equality, like its sibling). Read the files with `dart:io`, as that guard does.
9. [x] Re-stabilise the existing widget tests. **No re-stabilisation was needed** — `test/screen_widget_test.dart`
       and `test/header_standardization_test.dart` pass unmodified (`+315`), so no `setSurfaceSize` height was
       changed anywhere (evidence §5). Every site the step predicted ran and passed as-is. The Instruments list is taller content above the legacy
       sections, and these tests pump at a fixed surface height, so legacy content can fall below the fold
       and `find.text` will not match an unmounted widget. For each failing test the fix is **one mechanical
       edit**: raise that test's `setSurfaceSize` height (600 more, or to 2400) — never change what an
       assertion means, never weaken a `findsOneWidget` to `findsWidgets`, never delete an assertion.
       Expected sites: `test/screen_widget_test.dart` — the `all-non-strength dataset` test (~3542), the
       `D-5: Inter-section gaps are uniform (24dp)` test (~3672), `S-601`…`S-605` (~4001–4308), the
       `Multi-modality` test (~4461) and `S-601/S-603: … positioned correctly` (~4618);
       `test/header_standardization_test.dart` — the `S-018` header walk (~2710, currently 1800). Record
       every bumped test and the reason in the evidence file (§5). If a test still fails for a reason that
       is not the surface height, log it as an assumption or open a remediation item — do not silently edit
       the assertion.
10. [x] Update the docs: `docs/stats_screen.md` (a new "Instruments list" subsection — the four sections,
        their title-case labels, D-504/D-506 ordering, the cap and `kInstrumentRowCap` in the Key Constants
        table, the row anatomy with its exact strings, the change chip's `'—'`/arrow semantics, the
        sparkline's ≥2-point rule, the `stats_legacy_sections` key, and that the five legacy sections are
        unchanged until 4c); `docs/widget_catalog.md` (the four new widgets with their paths);
        `docs/navigation_and_screens.md` (the `ExerciseProgressScreen` entry now includes the Stats
        Instruments rows — the current text says it is reached only from Records & Trends);
        `docs/design_system.md` (the Stats row of the canonical-header inventory gains the four title-case
        Instruments headers).

**Done Criteria** (run until green):
- `gateway.sh test test/instrument_list_screen_test.dart` → all pass (paste the counts).
- `gateway.sh test test/screen_widget_test.dart test/header_standardization_test.dart` → all pass, with
  every bumped surface height recorded in the evidence file (§5).
- `gateway.sh test` → the whole suite passes (paste the counts). Any PR-parity test must be unmodified.
- `gateway.sh test test/stats_progress_test.dart test/navigation_contract_enforcement_test.dart test/screen_overflow_contract_test.dart test/docs_indexing_contract_test.dart test/records_and_trends_screen_test.dart`
  → all pass.
- `gateway.sh lint` → 0 errors, ≤ baseline issues; the four new widget files and `stats_screen.dart` each
  0 issues.
- Search `lib/` for `Key('stats_legacy_sections')` → exactly 1 construction (`stats_screen.dart`) plus the
  test files that scope finders to it (none expected under the title-case decision).
- Search `lib/` for `_buildWindowChip` → gone; search for `StatsWindowChip` → the widget file plus five
  call sites (four legacy headers + the first Instruments header).
- Search `lib/` for `kInstrumentRowCap` → declared once, read once.
- Search `lib/` for `MaterialPageRoute(` and `PageRouteBuilder(` outside `lib/core/navigation/` → no new
  hit.
- `gateway.sh git-diff --stat -- lib test docs` → matches the Predicted Files; `gateway.sh git-status` → no
  stray file.
- **Mutation M5 (the cap):** set `kInstrumentRowCap` to 100 and run `test/instrument_list_screen_test.dart`
  → S-1016 fails; restore → passes.
- **Mutation M6 (the sparkline rule):** change the `< 2` points condition to `< 0` → S-1017 fails; restore →
  passes.
- **Mutation M7 (the legacy boundary):** remove the `stats_legacy_sections` wrapper key → any test that
  scopes to it fails; restore → passes. (If no test scopes to it — the title-case decision means none
  should — record that M7 has no failing test and treat the key as documentation-only, or drop the key and
  log the decision in §Assumption Log.)

**Predicted Files:** `lib/features/stats/widgets/instrument_list.dart` (new),
`lib/features/stats/widgets/instrument_row.dart` (new),
`lib/features/stats/widgets/instrument_sparkline.dart` (new),
`lib/features/stats/widgets/window_chip.dart` (new), `lib/features/stats/stats_screen.dart`,
`test/instrument_list_screen_test.dart` (new), `test/screen_widget_test.dart` (surface heights only),
`test/header_standardization_test.dart` (surface heights only),
`test/records_and_trends_screen_test.dart` (the entry-point guard), `docs/stats_screen.md`,
`docs/widget_catalog.md`, `docs/navigation_and_screens.md`, `docs/design_system.md`.

**Note the deliberate omission:** `lib/features/stats/widgets/native_value_format.dart` is **not** in this
list. `formatNativeChange` (D-508) and `nativeSecondaryLabel` (D-516a) land in 4b, so this PR consumes them
and does not edit them. If you find yourself needing to change a formatter, that is a 4b defect — report it,
do not patch it here.

---

## Files Affected (whole PR)

| File | Phase | Change |
|---|---|---|
| `lib/features/stats/widgets/window_chip.dart` | 1 | new — the extracted chip |
| `lib/features/stats/widgets/instrument_sparkline.dart` | 1 | new |
| `lib/features/stats/widgets/instrument_row.dart` | 1 | new — the row + the change chip |
| `lib/features/stats/widgets/instrument_list.dart` | 1 | new — sections, the cap, `kInstrumentRowCap` |
| `lib/features/stats/stats_screen.dart` | 1 | the list, the legacy wrapper key, the chip |
| `test/instrument_list_screen_test.dart` | 1 | new — S-1001, S-1011, S-1012, S-1014…S-1017 |
| `test/screen_widget_test.dart` | 1 | surface heights only |
| `test/header_standardization_test.dart` | 1 | surface heights only |
| `test/records_and_trends_screen_test.dart` | 1 | the `ExerciseProgressScreen` entry-point guard |
| `docs/stats_screen.md`, `docs/widget_catalog.md`, `docs/navigation_and_screens.md`, `docs/design_system.md` | 1 | the new surface |

**Nothing else.** In particular: no repository, no model, no service, no `scripts/sqlite_schema.sql`, no
`scripts/sqlite_seed.sql`, no `test/db_seed_test.dart`, no `lib/features/stats/widgets/native_value_format.dart`,
no PR-path file, no `pubspec.yaml`, no `watch/`, no route constant, no `lib/core/navigation/` change.

---

## Notes

**Phase dependency graph.** 4b Phase 1 → 4b Phase 2 → **this Phase 1** → 4b3 (unplanned). This phase cannot
start before 4b is merged. Nothing in 4b2 blocks 4b's greenness, so the series can stop after 4b and ship a
repository read with no reader.

**Predicted intermediate state.** After this phase both layouts are on screen at once: the Instruments list
above, the five legacy sections below, both fed by the same window. This is the expected, temporary state
that 4c ends. The `stats_legacy_sections` key is the only seam between them.

**Legacy handling.** None needed: this series is single-release (4a D-402). No migration, no old-data
handling, no flag. The old sections are not deprecated here; 4c removes them.

**The one place a reasonable implementer could drift.** The change chip's arrow for pace. A faster pace is a
*smaller* seconds-per-kilometre value, so a faster run reads `↓` and a slower one reads `↑`. That is D-508's
raw-sign rule and it matches `_buildGroupComparisonChip`; do not add a per-metric inversion. The chip
renders whatever `formatNativeChange` returns — the direction is 4b's decision, not a widget choice.

---

## Open Items

- **O-1 (deferred to 4c, deliberately).** The pack's bullet *"Update or retire the top-N selection tests in
  `test/stats_progress_test.dart`"* is **not** done in this PR. 4b2 keeps `computeProgressData` and the five
  legacy sections, so those tests must pass **unmodified**; retiring them here would delete the guard on code
  that is still live. They are retired in 4c with the code they guard.
- **O-6 (planner's call, vetoable).** S-1012 ("an empty window with a non-empty history") is filed under this
  plan rather than 4b, because its expected outcome is a statement about the rendered screen ("no Instruments
  section renders … the five legacy sections render exactly as they do today"). The model half of the same
  situation is 4b's S-1005(b). If the owner prefers all model-level scenarios in one plan, S-1012 moves to 4b
  and this plan's list becomes six.
- **O-7 (the cost of the split, accepted).** This plan carries the surface-height churn (Step 9) that the
  single 4b plan also carried, and it is now the only plan that touches those two test files. Record every
  bump in the evidence file's §5; an unexplained height change is a reviewer finding.
- **O-8 (for 4b3's planner).** Step 8's entry-point guard asserts **exact list equality** over the files in
  `lib/` that construct `ExerciseProgressScreen`. If 4b3 adds a constructor of that screen anywhere, the
  guard must be extended in that PR — a silent extension is exactly the drift the guard exists to catch.
- **O-9 (for 4c).** The five legacy sections, `kTopLiftCount` / `kTopCardioCount` / `kRecentPRCount` /
  `kRecentTrainingDaysWindow`, the `stats_legacy_sections` key and the four legacy `StatsWindowChip` call
  sites are all live after this PR. 4c must prove no reader of the old representation remains, and must
  decide whether the key is deleted with them.

---

## Progress

| Phase | Owner | State | Evidence |
|---|---|---|---|
| 1 — the Instruments list on the Stats screen | @developer | **Complete** | `.evidence.md` §1, §4, §5, §6, §7, §9 — 24 new tests green, full suite `+3208 ~1`, lint 199/0 errors (baseline), M5/M6/M7 all fail-then-restore |
| Review | @code-reviewer | not started | — |

---

## Assumption Log

Executors append here; the planner ratifies (promotes to a D-x) or reverts (opens a remediation item). Empty
is expected before Phase 1 starts.

| # | Phase | Decision | Options considered | Why | Verdict |
|---|---|---|---|---|---|
| A-1 | 1 | `StatsWindowChip` and `InstrumentList` take `themeColors` as a parameter. | Read `OmniTheme.colors.textMuted` directly (the plan's literal wording) vs take the resolved `OmniThemeColors`. | The deleted `_buildWindowChip` read the *active theme's* colours, and `StatsPill` (the sibling shared widget) already takes `themeColors`. Passing it in keeps the chip's rendering byte-identical and keeps the widgets theme-reactive. | |
| A-2 | 1 | `InstrumentList` constructs and pushes `ExerciseProgressScreen` itself. | A row-tap callback supplied by `StatsScreen` vs the list owning the push. | Step 8's guard asserts the exact list of files constructing `ExerciseProgressScreen` and expects `instrument_list.dart` as the second entry, so the push has to live there. The list already receives both states it needs. | |
| A-3 | 1 | The Instruments block is wrapped in `if (window != null && _instrumentSections.isNotEmpty)`. | Always render the block (empty or not) vs render it only when it has content. | S-1012 requires the legacy layout to render exactly as today when the window has no work; an unconditional block would add a stray 24dp gap above the legacy column. | |
| A-4 | 1 | The expand control is a `TextButton` keyed `Key('instrument_show_all_<section.name>')`, with the mandatory explicit utility-radius `shape`. | `OutlinedButton.icon` (the design-system row for an inline compact action) vs a text control. | D-507 specifies "a text control", and the key uses the enum's `name` so each section's control is distinct. `shape` is set explicitly per the button rule. | |
| A-5 | 1 | S-1012's fixture is two completed sessions dated 35 and 40 days back that carry **no efforts**. | Try to produce a genuinely empty window vs the reachable equivalent. | With any completed session, `resolveWindow` always yields a 14-most-recent-training-day window, so "nothing in the window" is only reachable when the sessions hold no efforts. The scenario's intent — no Instruments content, legacy untouched — is what the test asserts. | |
| A-6 | 1 | S-1014's day-label assertions use `findsWidgets`. | `findsOneWidget` vs `findsWidgets`. | On the pushed `ExerciseProgressScreen` the same day label appears in both the chart axis and the history row, so `findsOneWidget` was asserting an accident of the other screen's layout. The scenario's claim (the row opens that exercise's screen, back returns to the list) is unchanged. | |
| A-7 | 1 | `InstrumentChangeChip` uses `theme.colorScheme.error.withValues(alpha: 0.8)`. | `withOpacity(0.8)` vs `withValues(alpha: 0.8)`. | `withOpacity` is deprecated and made the lint count 200; `withValues` produces the identical colour and keeps the new file at 0 issues. | |
| A-8 | 1 | The new doc prose names constants, types and tests instead of restating their values or strings. | Step 10's wording asks for "the row anatomy with its exact strings" and the cap's value; `docs/documentation_standard.md` §3.4/§3.5 forbid restating values and copied implementation content. | The standard is the governing rule for `docs/`, and it explicitly says a value copied into prose is a second source of truth no test guards. The row's parts, the change chip's semantics and the ≥2-point rule are recorded with the test that proves each. | |
| A-9 | 1 | `docs/records_and_trends.md` was also updated. | Leave it vs correct the sentence. | It is not in Predicted Files, but Step 6 made its "Exercise Progress has no single-entry rule: it is reached from an entry in Records & Trends" sentence false, and the doc-hygiene rule is to fix a claim the change falsified. | |
| A-10 | 1 | The divider above `_buildAggregateCard` now reads `// ── All-time aggregate ──`. | Leave the stale `// ── Section label ──` heading vs relabel it. | It headed the deleted `_buildWindowChip`; the deletion is this phase's, so the comment is this phase's to correct. Comment only — no behaviour change. | |
| A-11 | polish | The no-change dash keeps `themeColors.textMuted`. | Derive the colour from the reference chip (a `colorScheme.onSurface` opacity, not a token) vs keep the theme token. | `docs/global_conventions.md` requires theme tokens only, and `textMuted` is a token, so D-508's "colour is `_buildGroupComparisonChip`'s" cannot be honoured literally. | |
| A-12 | polish | A section's expanded state is local UI state that survives a reload. | Add a `didUpdateWidget` reset plus a test vs keep the surviving state. | Nothing is hidden by the survival (a section stays expanded across a reload), so the code's behaviour is the intended one; D-507's parenthetical is corrected to match. | |

---

## Feedback

*Empty. The owner writes here only to redirect product behaviour, contradict a D-x, or change scope; that is
the only thing that re-invokes the planner.*

---

## Doc-claim → test table

Every behavioural sentence the docs will gain, and the test that proves it. A claim with no test does not
ship; a doc that names a type, file or constant that does not exist is a blocker.

| Doc | Claim it will make | Test that proves it |
|---|---|---|
| `docs/stats_screen.md` | the Instruments list renders between the ALL TIME card and the legacy sections | `test/instrument_list_screen_test.dart` S-1001 |
| `docs/stats_screen.md` | the four Instrument headers are title case, distinct from the legacy uppercase headers | S-1001, S-1015 |
| `docs/stats_screen.md` | a section appears only when the window has work of that kind | S-1012 (S-1005, S-1013 in 4b) |
| `docs/stats_screen.md` | the row shows the exercise name, its native value, the change chip and the sparkline, with the secondary line's exact parts | S-1001 (values: S-1007 in 4b) |
| `docs/stats_screen.md` | the cap is 5 with a `Show all (n)` / `Show less` control | S-1016 |
| `docs/stats_screen.md` | the sparkline renders only with ≥2 points | S-1017 |
| `docs/stats_screen.md` | the legacy children are wrapped in `Key('stats_legacy_sections')` and are otherwise unchanged | S-1015 |
| `docs/stats_screen.md` | `kInstrumentRowCap` is 5 | S-1016 |
| `docs/stats_screen.md` | the Instruments header carries the window chip, text-identical to the legacy headers' | S-1011 |
| `docs/widget_catalog.md` | the four new widget paths and what each renders | S-1001, S-1016, S-1017 |
| `docs/navigation_and_screens.md` | an Instruments row is an entry point to `ExerciseProgressScreen` | S-1014 + the entry-point guard test |
| `docs/design_system.md` | the Stats card-header inventory includes the four Instrument headers | S-1001 |

---

## Open questions (defaults applied)

Each of these is a product choice the planner had to make to keep the plan executable. The plan runs on the
**default**; the owner can veto any of them and the plan will be amended by superseding ledger entries.
Numbers in brackets are the question's number in the superseded single 4b plan, kept so a veto can be
addressed to the original.

1. **[Q4] The sparkline's range and visibility (D-510).** Default: the window's training days, hidden below 2
   points. *Alternative:* always visible with a flat line for a single point.
2. **[Q7] `Show all` behaviour (D-507).** Default: per section, local state, `'Show less'` to collapse.
   *Alternative:* a screen-level "show all" and no collapse.
3. **[Q12] The legacy wrapper key (D-503).** Default: one `Key('stats_legacy_sections')` Column around the
   existing children. *Alternative:* no key, and any legacy test that needs disambiguation scoped by header
   text instead.
4. **[Q13] The Instrument headers' casing.** Default: title case, matching 4a's Records & Trends labels, so
   the two layouts are distinguishable while both are on screen. *Alternative:* uppercase, matching the
   legacy chart headers, which would force every legacy header finder in the two stats widget-test files to
   be scoped to the keyed subtree.
5. **[Q14] The window chip's placement (D-516b).** Default: on the first Instrument section header only (the
   second, third and fourth would repeat the same string).
6. **[Q16] `kInstrumentRowCap`'s home.** Default: `lib/features/stats/widgets/instrument_list.dart`,
   documented in `docs/stats_screen.md`'s Key Constants table beside `kTopLiftCount`. *Alternative:* a core
   constants file, which would also require `docs/constants_reference.md`.
7. **[Q24] The legacy tests' re-stabilisation (Step 9).** Default: raise surface heights, never change an
   assertion's meaning. *Alternative:* scope every legacy finder to the keyed subtree as well — not needed
   under the title-case decision, and it would be a larger diff for the same guarantee.

Questions 1, 2, 3, 5, 6, 8, 9, 10, 11, 15 and 25 of the superseded plan are 4b's; 17–23 are 4b3's; 26 (the
plan/evidence layout) is obsolete, because the brief's folder layout now exists.
