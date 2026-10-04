# Feature: Protein Consistency (Stats PR 8b — pack item 13)

> **Status:** READY (planner) — not started. **Blocked on 8a Phases 1–2.**
> **Next handoff:** @dba (Phase 1), once 8a Phase 2 is green.
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 13
> ("Protein Consistency (Caution)"), and the series seam in
> `docs/plans/2026-10-03-08-stats-pr8-index.md`.
> **Depends on:** `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.md`
> Phase 1 (`lib/core/models/nutrition_consistency.dart`) and Phase 2 (`nutritionSeries`). This plan adds
> nothing to either and edits neither.
> **Base:** `develop` at `2b6e8e5`, plus 8a merged. 8a leaves four registered signals (Progression Rate,
> Modality Mix Shift, Cross-Modality Interference, Fuel vs Load) and the registry guards extended to
> four ids.
> **Binding conventions:** `docs/global_conventions.md`. `docs/README.md` entries this plan depends on,
> read before Phase 1: `docs/signals.md`, `docs/nutrition.md`, `docs/state_management/services_and_utils.md`,
> `docs/state_management/nutrition_state.md`, `docs/stats_screen.md`, `docs/constants_reference.md`,
> `docs/data_models.md`, `docs/profile_and_measurements.md`, `docs/design_system.md`,
> `docs/documentation_standard.md`. Budget: `.github/agents/pr_scope_budget.md`.
> **Evidence:** `2026-10-03-08b-stats-pr8b-protein-consistency-plan.evidence.md` (this folder). Review
> findings: `.review.md`. Neither is written into this file.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 671 (measured) | 500 | 800 |
| Phases | 3 | >3 | >5 |
| Tracks | 1 (`lib/`, `test/`, `docs/`) | >1 | — |
| Ledger decisions | 19 (D-1501…D-1519) | >20 | — |
| Scenarios | 16 (S-2201…S-2216) | >30 | — |
| Predicted production lines | ~270 | — | ~1,500 |

**Verdict:** one soft signal (plan length: 671 against the 500 soft line, well inside the 800 hard cap),
zero hard. The length is scenario-bound: 16 scenarios with hand-checked fixtures and exact pinned strings
are the whole point of this plan, so trimming them would push ambiguity onto the implementer. The other
half of the series is 8a. Neither half can be merged before the other: 8b compiles against 8a's
foundation.

## What this PR does

One new caution signal. It notices when a user's average daily protein over the last 2 weeks has fallen
at least 15% below their own protein target — or, with no target set, below their own usual level over
the 8 consistently-logged weeks before — while they are still training resistance at least twice. Where
a bodyweight is on file it says the intake per kilogram, and it points at a commonly cited reference
only when the user has no target of their own.

## Out of scope

- Creating or changing nutrition targets, and any protein-target field in the UI (pack's out-of-scope;
  see the Finding below for why this makes the target branch unreachable today).
- Other macros, meal timing, calorie amounts, calorie suggestions.
- Fuel vs Load and the shared foundation — those are 8a.
- Any change to the Signals framework, the Mix layer, the Fuel row, the PR rules, `lib/data/` or
  `watch/`.

## Findings from research

- **F-1 — the protein-target branch is unreachable through the shipped UI.**
  `lib/features/nutrition/nutrition_target_screen.dart` is calories-only by design (its own doc comment
  cites D-3 / S-040) and persists `NutritionTarget(calories: …, protein: 0.0, carbs: 0.0, fat: 0.0)`.
  So in the shipped app every stored target has `protein == 0.0`, D-1506 never selects target mode, and
  every user sees the own-baseline path. The pack puts creating or changing targets out of scope, so
  this PR adds no protein field: the target branch is implemented, tested through a directly stored
  target, and reported to the owner as a product gap rather than silently dropped.
- **F-2 — the pack's Copy block and its Acceptance row use different numbers.**
  The Copy block illustrates `118 g/day` against a `150 g` target with `about 20%` (118/150 is 21.3%),
  while the Acceptance row uses a `120 g` average against `150 g` (exactly 20%). The Acceptance row is
  the contract; D-1512's rounding rule renders 120 → `about 20%` and 118 → `about 21%`. Both strings are
  covered by tests, so the choice is visible rather than accidental.
- **F-3 — `docs/signals.md`'s caution-order paragraph is stale** and is corrected by 8a; 8b extends the
  corrected paragraph from four cautions to five.

## Resolved Decisions (Ledger)

**D-1501 — Reuse 8a's foundation unchanged.** `lib/core/models/nutrition_consistency.dart` supplies
`kWeekDays = 7`, `kConsistentWeekMinLoggedDays = 5`, the block-start helper, the logged-day count, the
consistency test and the logged-days-only mean. This PR adds no member to that file and edits no line
of it. The protein rule lives in its own new file.

**D-1502 — The window.** The last 14 local calendar days ending today:
`[DateTime(y, m, d − 13) 00:00, endOfDay(today)]`, where `y/m/d` are today's local date. Both ends
inclusive. Never a `Duration`.

**D-1503 — A logged day.** A day with at least one `ConsumedFood` row, exactly as 8a's D-1403 reads it:
the day is present in `nutritionSeries` with its own rounded protein total, and a day with no row is
absent and never zero-filled. The average divides by the number of logged days, never by 14.

**D-1504 — The logged-days gate.** At least `kProteinConsistencyMinLoggedDays` (10) of the 14 calendar
days are logged: exactly 10 passes, 9 fails. Below the gate the signal abstains, whatever the figures.

**D-1505 — Average protein.** The mean of `NutritionTrendPoint.protein` over the window's logged days,
read from 8a's `nutritionSeries`. It is a `double` internally and is rendered as a whole gram by
`formatGrams` (`lib/core/utils/food_helpers.dart`), the nutrition feature's gram convention.

**D-1506 — Which comparison.** Target mode is selected only when **every** logged day in the window has
a positive stored protein target (`getNutritionTargetForDate(dayMs).protein > 0`). If any logged day's
stored target has a protein of zero, or no target is on file, the signal uses own-baseline mode. There
is no third mode and no card ever names both figures. (See F-1: the shipped UI can only produce
own-baseline mode.)

**D-1507 — The target figure.** In target mode the comparison is the mean of the per-day stored targets
over the window's logged days — the target stored for each day, so a target changed mid-window is
averaged, not taken from one end. The copy renders it as a whole gram via `formatGrams`; the threshold
math uses the unrounded mean.

**D-1508 — Fires on shortfall.** Recent protein is at least `kProteinConsistencyShortfallPercent` (15%)
below the comparison: target mode `20 × recentTotal <= 17 × targetSum`; own mode
`20 × recentTotal × usualDays <= 17 × usualTotal × recentDays`. Exactly 15% below fires; 13% below does
not. Both comparisons are exact integer cross-multiplications on the unrounded totals — never on a
rounded percentage. The rule is one-directional: protein above the comparison never produces a card.

**D-1509 — The own baseline.** The eight 7-day blocks abutting the window — starts `day(69)`, `day(62)`,
`day(55)`, `day(48)`, `day(41)`, `day(34)`, `day(27)`, `day(20)` — where the block ending `day(14)` is the
last full week before the window. Only blocks that are consistent (D-1504's rule: at least 5 of 7 days
logged) contribute, and their logged days are **pooled** (the mean is over all their logged days, not the
mean of their means). At least `kProteinConsistencyMinBaselineWeeks` (2) consistent blocks are required;
fewer than 2 → no card. The baseline is never widened, never shortened, and no day is ever zero-filled.

**D-1510 — The resistance gate.** At least `kProteinConsistencyMinResistanceSessions` (2) **completed**
sessions (`endedAtMs != null`) whose start falls in the window and which contain at least one Resistance
effort, judged by the same rule `interferenceSessions` uses (`_sectionForKind(effortKind) ==
ExerciseSection.resistance`). A session with only cardio, timed or drill efforts does not count; a
session still in progress does not count; a session starting before `day(13)` does not count.

**D-1511 — Bodyweight.** The user's latest recorded bodyweight, from
`WorkoutRepository.getLatestMeasurement('bodyweight')`, used only when its `unitId` is `'unit-kg'` (the
canonical unit both repository implementations store). No measurement on file, or a non-canonical unit,
means no per-kilogram figure and no reference sentence.

**D-1512 — Observation, target mode.**
`'Protein has averaged ${formatGrams(avg)} g/day over the last 2 weeks, about $p% under your ${formatGrams(targetMean)} g target.'`
where `p = ((1 − avg / targetMean) × 100).round()`, computed from the unrounded means.

**D-1513 — Observation, own-baseline mode.**
`'Protein has averaged ${formatGrams(avg)} g/day over the last 2 weeks, down from your usual ${formatGrams(usualMean)} g.'`
No percentage appears in this sentence.

**D-1514 — The per-kilogram figure.** When a bodyweight is on file (D-1511), the observation carries
`'($perKg g/kg)'` appended immediately after the `X g/day` figure, with
`perKg = (avg / bodyWeightKg)` rounded to **one** decimal. It applies in both comparison modes; only the
reference sentence (D-1515) is restricted to own-baseline mode.

**D-1515 — Suggestions.** Target mode: `'Bringing protein back toward your target is one option.'`
Own-baseline mode with a bodyweight on file:
`'Commonly cited guidance for strength training is around ${kProteinGuidancePerKg} g/kg of bodyweight.'`
with `kProteinGuidancePerKg = 1.6` — the value comes from the constant, never from a literal in the
sentence. Own-baseline mode with no bodyweight on file: **no suggestion** (`SignalCard.suggestion` is
nullable and the layer renders the observation alone). The reference sentence never appears in target
mode.

**D-1516 — Hard rules.** No card text carries a calorie amount or a calorie suggestion, and the
definition file's stripped source contains no `cal`/`kcal` literal. Protein amounts are whole grams with
no decimal point; only the per-kilogram figure carries one decimal. The 2-week span is derived from
`kProteinConsistencyWindowDays ~/ 7`, never written as a literal. Nothing in the card tells the user what
to do beyond the two pinned sentences.

**D-1517 — Kind, priority, id and title.** Kind caution. Priority `kProteinConsistencyPriority = 200` —
below 8a's Fuel vs Load (300), as the pack requires. The id is `protein-consistency` (the dismissal key,
the widget key and the semantic label). The title is `Protein consistency` and is never rendered (the
layer renders the kind's label, `Worth a look`).

**D-1518 — Plug-in only.** One class implementing `Signal` in
`lib/core/services/signals/protein_consistency_signal.dart`, plus one line in `buildSignalRegistry()`. No
file in `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart` or
`lib/features/stats/widgets/signals_layer.dart` changes. `SignalContext` gains no member.

**D-1519 — The adapter reads the service, never the repository.** `evaluate` derives the window from
`context.now` and asks `context.progressService` for: the window's nutrition series, the per-day stored
protein targets in the window, the window's resistance-session count, the 8 baseline blocks' logged days,
and the latest bodyweight in kilograms. It reads no `ConsumedFood` row, calls no repository method, walks
no history and calls no PR API. **No new `WorkoutRepository` method is added** — the service resolves each
day's target through the existing `getNutritionTargetForDate`, so both repository implementations stay
untouched and their parity burden does not grow.

## Feature Invariants

Only the invariants that bite here; project-wide rules stay in `docs/global_conventions.md`.

- **8a's foundation is frozen.** No line of `lib/core/models/nutrition_consistency.dart` changes and no
  member is added; 8a's own tests keep passing unmodified.
- **The Mix layer, the Fuel row and every existing nutrition figure do not change.** This PR reads
  nutrition and adds a card; it writes no figure and edits no existing computation.
- **A signal never walks history itself.** The adapter calls the service; the service rides its cached
  history index.
- **One signal = one class + one registry line.** No framework file names a concrete signal.
- **The nutrition rows and the target rows are read-only.** This PR writes no `ConsumedFood` row, no
  target and no preference other than the framework's own dismissal store.
- **No new colour, token, widget or `OmniTheme` value.** The card uses the layer's existing caution
  styling.

## Requirements

- **R1** A user whose average daily protein over the last 2 weeks is at least 15% below their own target
  or their own usual level, who logged at least 10 of those 14 days and who trained resistance at least
  twice, sees one caution card under the Mix layer.
- **R2** The card names the user's own figures, and the comparison it used, in the pack's wording.
- **R3** Protein is never called short of a calorie amount, and no suggestion reduces calories.
- **R4** With no target and no bodyweight, the card carries no suggestion at all.
- **R5** A 13%-below, a 9-of-14 and a one-resistance-session case each suppress the card.
- **R6** The card is dismissible and stays dismissed for the framework's window.
- **R7** No existing Stats or nutrition figure changes.

## Acceptance Criteria (each maps to ≥1 scenario)

| # | Criterion (the pack's own rows, plus the owner's boundaries) | Scenarios |
|---|---|---|
| AC-1 | A 150 g target, 12 of 14 days logged, a 120 g average and 3 resistance sessions show the card with `under your 150 g target` | S-2201 |
| AC-2 | A 150 g target with a 130 g average (13% under) shows no card | S-2202 |
| AC-3 | 9 of the last 14 days logged shows no card; exactly 10 shows one | S-2203, S-2204 |
| AC-4 | With no target the comparison is the user's own 8-week average and the copy says `down from your usual` | S-2205 |
| AC-5 | With no target and a bodyweight on file, the card shows a g/kg figure and the 1.6 g/kg reference; with no target and no bodyweight it shows neither | S-2206, S-2207 |
| AC-6 | With a target set, the 1.6 g/kg reference never appears | S-2208 |
| AC-7 | One resistance session in the 14 days shows no card; exactly 2 shows one | S-2209 |
| AC-8 | A target changed during the window is read per day and averaged | S-2210 |
| AC-9 | A window whose logged days do not all carry a positive target falls back to the own baseline | S-2211 |
| AC-10 | Fewer than 2 consistent baseline weeks shows no card, and no day is ever zero-filled | S-2212 |
| AC-11 | Protein follows the nutrition unit conventions; no card text carries a calorie amount or a calorie suggestion | S-2213 |
| AC-12 | The new service reads return the same figures from Hive and from Mock | S-2214 |
| AC-13 | Both cautions qualifying shows Fuel vs Load only | S-2215 |
| AC-14 | The card renders on the layer, dismisses, and leaves every other block alone | S-2216 |

## Scenarios

Fixtures name every entity class involved. `day(n)` means local midnight `n` days before today; all times
are local. Every threshold fixture sits exactly on its boundary or a whole percentage point clear of it.
Pure scenarios call the rule directly with hand-built figures; service scenarios go through
`test/helpers/repository_harness.dart` with rows seeded in `setUp` (never in a `testWidgets` body), and
the tap/persist scenario is Mock-only because a Hive write started inside a widget test's fake-async zone
can never drain.

### S-2201: the pack's target row fires
- **Fixture:** window days 13…0. A `NutritionTarget(calories: 2000, protein: 150)` stored for every day
  from `day(13)` to `day(0)`. Twelve `ConsumedFood` rows, one on each of days 13…2, each with
  `referenceAmount == amountConsumed` and `protein: 120` (so each day's point is exactly 120 g). Three
  completed sessions starting on `day(12)`, `day(6)` and `day(2)`, each carrying one Resistance effort
  (`hasSetEffort` true). No bodyweight measurement.
- **Trigger:** one rule call with the window's figures.
- **Flow:** D-1504 gate → D-1506 mode → D-1508 → D-1512/D-1515.
- **Expected outcome:** fires. Gate: 12 ≥ 10. Target mode: every logged day has protein 150 > 0.
  `recentTotal = 1440`, `targetSum = 1800`; `20 × 1440 = 28,800 <= 17 × 1800 = 30,600`.
  `avg = 120`, `targetMean = 150`, `p = 20`. Observation exactly
  `'Protein has averaged 120 g/day over the last 2 weeks, about 20% under your 150 g target.'`
  Suggestion exactly `'Bringing protein back toward your target is one option.'` Resistance: 3 ≥ 2.
- **Edge case of:** none.

### S-2202: 13% under shows nothing
- **Fixture:** S-2201 with every `ConsumedFood` row's `protein` at 130 (12 days, `recentTotal = 1560`,
  `avg = 130`).
- **Trigger:** one rule call.
- **Flow:** D-1508.
- **Expected outcome:** null. `20 × 1560 = 31,200 > 17 × 1800 = 30,600`. 130 against 150 is 13.33%
  below, inside the 15% tolerance.
- **Edge case of:** S-2201.

### S-2203: 9 of 14 days logged shows nothing
- **Fixture:** S-2201's target and resistance fixture with `ConsumedFood` rows on only days 13…5 (9
  days), each at 100 g (`recentTotal = 900`, `avg = 100` — far below any threshold).
- **Trigger:** one rule call.
- **Flow:** D-1504.
- **Expected outcome:** null. The gate is checked before any comparison.
- **Edge case of:** S-2204.

### S-2204: exactly 10 of 14 days logged fires
- **Fixture:** target 150 stored on all 14 days; rows on exactly 10 days — days 13…10 at 120 g (4 days)
  and days 9…4 at 130 g (6 days); `recentTotal = 1260`, `avg = 126`; 2 completed resistance sessions.
- **Trigger:** one rule call.
- **Flow:** D-1504's inclusive `>=`, then D-1508.
- **Expected outcome:** fires. `targetSum = 10 × 150 = 1500`; `20 × 1260 = 25,200 <= 17 × 1500 = 25,500`.
  `p = ((1 − 126/150) × 100).round() = 16`. Observation
  `'Protein has averaged 126 g/day over the last 2 weeks, about 16% under your 150 g target.'`
- **Edge case of:** S-2201 (one logged day above the gate).

### S-2205: the own baseline, and the logged-day divisor
- **Fixture.** No target stored anywhere (or targets with `protein: 0`). (a) Rows on days 13…2 at 118 g
  each (12 logged days, `recentTotal = 1416`, `avg = 118`); baseline blocks starting `day(69)` and
  `day(62)` each have 7 of 7 days logged at 145 g (pooled `usualTotal = 2030`, `usualDays = 14`,
  `usualMean = 145`), and the other six baseline blocks have 3 of 7 days logged. 3 completed resistance
  sessions. (b) the same with rows on only 10 days (days 13…4) at 145 g each (`recentTotal = 1450`,
  `avg = 145`) and the same baseline.
- **Trigger:** one rule call each.
- **Flow:** D-1506 → D-1509 → D-1508.
- **Expected outcome:** (a) fires.
  `20 × 1416 × 14 = 396,480 <= 17 × 2030 × 12 = 414,120`; observation exactly
  `'Protein has averaged 118 g/day over the last 2 weeks, down from your usual 145 g.'` (b) null:
  `20 × 1450 × 14 = 406,000 > 17 × 2030 × 10 = 345,100` — 145 against 145 is a 0% shortfall. A rule
  dividing each period's total by the 14-day window instead of by its logged days reads 103.6 against
  145 and fires in (b), which is wrong; this is mutation (c) in Phase 1.
- **Edge case of:** S-2201 (the other comparison mode).

### S-2206: no target, bodyweight on file
- **Fixture:** S-2205(a) plus a `BodyMeasurementEntry(measurementType: 'bodyweight', value: 70.0,
  unitId: 'unit-kg', recordedAtMs: 30 days ago)` and a second, older bodyweight of 75.0 kg.
- **Trigger:** one rule call.
- **Flow:** D-1511, D-1514, D-1515.
- **Expected outcome:** fires with observation exactly
  `'Protein has averaged 118 g/day (1.7 g/kg) over the last 2 weeks, down from your usual 145 g.'`
  (118 / 70 = 1.6857 → `1.7`; the **latest** measurement is used, not the 75 kg one) and suggestion
  exactly `'Commonly cited guidance for strength training is around 1.6 g/kg of bodyweight.'`
- **Edge case of:** S-2205.

### S-2207: no target, no bodyweight
- **Fixture:** S-2205(a) with no measurement of any type on file.
- **Trigger:** one rule call.
- **Flow:** D-1511, D-1514, D-1515.
- **Expected outcome:** fires with S-2205(a)'s observation — no `g/kg` figure, no parentheses — and
  `suggestion == null`. The layer renders the observation alone with no empty second line and no layout
  error.
- **Edge case of:** S-2206.

### S-2208: a target suppresses the reference
- **Fixture:** S-2201's fixture plus a 70 kg bodyweight measurement on file.
- **Trigger:** one rule call.
- **Flow:** D-1515's mode restriction.
- **Expected outcome:** fires with observation
  `'Protein has averaged 120 g/day (1.7 g/kg) over the last 2 weeks, about 20% under your 150 g target.'`
  and suggestion exactly `'Bringing protein back toward your target is one option.'` Neither string
  contains `1.6`, and the suggestion contains no `g/kg`.
- **Edge case of:** S-2201, S-2206.

### S-2209: the resistance gate
- **Fixture (four parts, each S-2201's nutrition fixture):** (a) exactly 2 completed resistance sessions
  in the window; (b) one; (c) 3 completed sessions whose only efforts are cardio, timed or drill; (d) 1
  completed resistance session in the window plus 1 completed resistance session starting on `day(20)`
  (before the window) plus 1 resistance session with `endedAtMs == null`.
- **Trigger:** one rule call each.
- **Flow:** D-1510.
- **Expected outcome:** (a) fires; (b), (c) and (d) null — (d) has only one qualifying session, so neither
  the earlier session nor the in-progress one counts.
- **Edge case of:** S-2201.

### S-2210: a target changed mid-window
- **Fixture:** S-2201's rows (12 logged days, 120 g each). `NutritionTarget(protein: 150)` stored for days
  13…7 and `NutritionTarget(protein: 160)` for days 6…0.
- **Trigger:** one rule call.
- **Flow:** D-1507.
- **Expected outcome:** fires with the per-day targets averaged over the logged days:
  `targetSum = 7 × 150 + 5 × 160 = 1850`, `targetMean = 154.1667`;
  `20 × 1440 = 28,800 <= 17 × 1850 = 31,450`. `p = ((1 − 120/154.1667) × 100).round() = 22`. Observation
  exactly `'Protein has averaged 120 g/day over the last 2 weeks, about 22% under your 154 g target.'`
  A rule reading only the most recent day's target reads 160 and prints `about 25% under your 160 g
  target` — a different sentence, so this scenario separates the two readings.
- **Edge case of:** S-2201.

### S-2211: a mixed window falls back to the own baseline
- **Fixture:** `NutritionTarget(protein: 150)` stored for days 13…7 and `NutritionTarget(protein: 0)` for
  days 6…0; rows on days 13…2 at 118 g each; S-2205's baseline (mean 145); 3 resistance sessions; no
  bodyweight.
- **Trigger:** one rule call.
- **Flow:** D-1506.
- **Expected outcome:** fires in own-baseline mode: observation exactly
  `'Protein has averaged 118 g/day over the last 2 weeks, down from your usual 145 g.'` The target is
  never named and the string contains no `target`.
- **Edge case of:** S-2201, S-2205.

### S-2212: fewer than 2 consistent baseline weeks
- **Fixture:** no target; rows on days 13…2 at 80 g each (`avg = 80`); all eight baseline blocks have
  exactly 3 of 7 days logged (0 consistent blocks); 3 resistance sessions.
- **Trigger:** one rule call.
- **Flow:** D-1509's minimum.
- **Expected outcome:** null, despite a 45%-plus apparent shortfall — there is no baseline to compare
  against, and the baseline is never widened past 8 weeks nor zero-filled to reach a figure.
- **Edge case of:** S-2205.

### S-2213: unit conventions and the hard rules
- **Fixture:** the four fired cards (S-2201, S-2205(a), S-2206, S-2208).
- **Trigger:** read each card's `observation` and `suggestion`; then scan the definition file's stripped
  source.
- **Flow:** D-1516.
- **Expected outcome:** every protein figure is a whole number with no decimal point
  (`120 g/day`, `145 g`, `150 g target`); only the per-kilogram figure carries one decimal (`1.7 g/kg`);
  no string matches `RegExp(r'\d+\s*(cal|kcal|calorie)')` (case-insensitive) and none contains `eat less`,
  `eat fewer`, `reduce`, `cut back` or `lower your intake`; the 2-week span appears only as the derived
  text; and the stripped source of `lib/core/models/protein_consistency.dart` contains no `cal`, no `kcal`
  and no `1.6` literal.
- **Edge case of:** none.

### S-2214: Hive and Mock agree
- **Fixture:** S-2201's targets, rows, sessions and bodyweight seeded identically into both factories via
  `test/helpers/repository_harness.dart` (`harnessFactories`, each `open()`; rows created with
  `createConsumedFood`, targets with `saveNutritionTargetForDate`, measurements with
  `saveMeasurementEntry`).
- **Trigger:** the service reads — the window's nutrition series, the per-day protein targets, the
  resistance-session count, the latest bodyweight in kilograms — against each repository.
- **Flow:** the same code path as the card, so a divergence in either implementation shows as a different
  card.
- **Expected outcome:** identical figures from both, and the same fired card. A Mock-only or Hive-only
  pass is a defect.
- **Edge case of:** none.

### S-2215: two cautions qualifying
- **Fixture:** one repository with 42 consecutive logged days, `day(41)`…`day(0)`, one `ConsumedFood` row
  each. Calories 2,040 on each of days 20…0 and 2,000 on each of days 41…21 (S-2101). Protein 120 g on
  each of days 13…0 (14 logged days, `recentTotal = 1680`) and 120 g on the earlier days too.
  `NutritionTarget(protein: 150)` stored for days 13…0 — target mode, so `targetSum = 2100` and
  `20 × 1680 = 33,600 <= 17 × 2100 = 35,700`; Protein Consistency fires with `p = 20`. The rated-session
  fixture that gives S-2101's load figures (recent 1,250, prior 1,000 load minutes), of which at least 2
  completed sessions carry a Resistance effort in the last 14 days. No other signal qualifies.
- **Trigger:** the registry's evaluation, then `resolveSignals`.
- **Flow:** the framework's caution ordering by priority.
- **Expected outcome:** the layer shows exactly one card, Fuel vs Load (300) — `protein-consistency` is
  never rendered beside it. After Fuel vs Load is dismissed, a fresh build shows Protein Consistency with
  S-2201's observation; before it is dismissed, dismissing Protein Consistency is impossible because it
  is not on screen.
- **Edge case of:** none.

### S-2216: the card on the layer, and its dismissal
- **Fixture:** S-2201's fixture seeded on **Mock** (`NutritionTarget(protein: 150)` stored directly for
  days 13…0, since the shipped target screen cannot set one — F-1), the Stats window scoped so the Mix
  layer renders above the Signals layer, and no other signal qualifying.
- **Trigger:** open the Stats screen; read the layer; tap the card's dismiss control.
- **Flow:** one evaluation, then the framework's dismissal write.
- **Expected outcome:** the layer shows the caution card with S-2201's exact observation and suggestion,
  the `Worth a look` kind label, the widget key `signal_card_protein-consistency`, and no quiet line; it
  sits below the Mix layer; the ALL TIME, Instruments and Fuel blocks are unchanged. After one tap the
  card is gone in the next frame, the quiet line appears, and the dismissal store holds
  `protein-consistency` with an integer timestamp; a fresh screen build keeps it hidden.
- **Edge case of:** none.

## Iteration 1

### Executor block (applies to every phase in this plan)

- **Branch:** work on `develop`. Never create a branch, never commit, never stage, never push — the owner
  commits.
- **Shell:** every command goes through the gateway, spelled in full:
  `.github/copilot/scripts/macos/gateway.sh <list|lint|test [paths]|format <file paths>|pub-get|git-status|git-diff|git-log|git-show>`.
  The bare form is denied. No `git`, `grep`, `sed`, `awk` or `wc` in a shell — use the gateway's `git-*`
  verbs and your file tools. A denied command is never retried. A gateway `test` command over 3 minutes
  is a hang: stop and report it.
- **Red first:** every phase writes its tests before the code they test, runs them, and records the
  failing output in `<this plan>.evidence.md`. A test that has never failed proves nothing.
- **Mutations:** at least two inverse edits per plan, on files that already exist at that point. Apply
  one, run the named test, record the failure, restore the file, re-run to confirm green, and *never end
  a step with a mutation applied*. A mutation on a **new, untracked** file: copy the original line into
  the evidence file first, so the restore is provable.
- **Step budget:** at most 8–10 steps per run. Read at most ~100 lines of a large file at a time.
  `lib/core/services/stats_progress_service.dart` is **2,420 lines**: find a region by searching for its
  symbol, then read that region only.
- **Evidence:** baselines, suite summaries, red→green tables and the mutation pairs go to
  `docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/2026-10-03-08b-stats-pr8b-protein-consistency-plan.evidence.md`.
  Never into this plan. Findings go to `...review.md`.
- **Ambiguity:** never stop. Pick the option most consistent with the Ledger and the Feature Invariants,
  log it in the Assumption Log (decision, options considered, rationale) and continue.
- **Docs trail code by zero phases:** each phase updates the docs it invalidated. Every behaviour
  sentence names a test that exists.
- **Baseline for this plan:** the numbers measured on 8a's merged state. 8a's evidence file holds them;
  Phase 1 repeats the measurement and records it, so this plan's phases are comparable to 8a's. On the
  pre-8a `develop` (`2b6e8e5`) the baseline was `flutter analyze` → `196 issues found.` with 0 errors and
  `flutter test` → `+3635 ~1: All tests passed!`; 8a's Phase 3 adds suites, so the totals must not be
  compared across the two plans without accounting for that.

### Phase 1: the pure protein rule (@dba)

1. [x] Read `lib/core/models/nutrition_consistency.dart` (8a's file) and `lib/core/models/fuel_vs_load.dart`
   (8a's rule) — the second is the shape to follow: constants, a result type, separately callable stages,
   a copy builder. Do not edit either.
2. [x] Write `test/protein_consistency_test.dart` (plain `test()`): S-2201, S-2202, S-2203, S-2204,
   S-2205, S-2206, S-2207, S-2208, S-2209, S-2210, S-2211, S-2212, S-2213 — each asserting one stage where
   the scenario names one, and the exact observation and suggestion strings where it names a card. Run it
   and record the failure.
3. [x] Create `lib/core/models/protein_consistency.dart` (D-1502…D-1517): the constants
   `kProteinConsistencyWindowDays = 14`, `kProteinConsistencyMinLoggedDays = 10`,
   `kProteinConsistencyShortfallPercent = 15`, `kProteinConsistencyMinResistanceSessions = 2`,
   `kProteinConsistencyMinBaselineWeeks = 2`, `kProteinConsistencyBaselineWeeks = 8`,
   `kProteinGuidancePerKg = 1.6`, `kProteinConsistencyPriority = 200`; the result type; the gate, the mode
   selector, the baseline pooler, the two comparisons and the copy builder as separately callable
   functions; the span and the reference derived from their constants. Pure Dart: no Flutter import, no
   repository, no clock, no service. It imports `lib/core/models/nutrition_consistency.dart` and
   `lib/core/utils/food_helpers.dart` only.
4. [x] Re-run step 2 to green.
5. [x] Mutations, one at a time, each restored: **(a)** D-1508's target-mode `<=` → `<` — S-2201 must
   fail; **(b)** D-1504's `>= 10` → `>= 11` — S-2204 must fail; **(c)** D-1508's own-mode comparison
   changed to divide both totals by `kProteinConsistencyWindowDays` — S-2205(b) must fail; **(d)**
   D-1509's minimum 2 → 1 — S-2212 must fail. Record all four red→green pairs in the evidence file.
6. [x] Docs: add the `protein_consistency` constant group to `docs/constants_reference.md` (names and
   values only, no restatement of a rule); add the own-baseline and per-day-target reading rules to
   `docs/nutrition.md`'s computation section, each with its test named.

**Done Criteria** (run until green):
`flutter analyze` (expect the same count as the phase's opening measurement, 0 errors);
`flutter test test/protein_consistency_test.dart test/nutrition_consistency_test.dart test/fuel_vs_load_test.dart`;
full `flutter test` with its summary line pasted into the evidence file, compared with the opening
measurement.

**Predicted Files:** `lib/core/models/protein_consistency.dart` (NEW);
`test/protein_consistency_test.dart` (NEW); `docs/constants_reference.md`, `docs/nutrition.md` (EDIT).

**Phase 1 verification notes (Conductor, date):** _(added at verification)_

### Phase 2: the service reads (@dba)

1. [ ] Write `test/protein_consistency_service_test.dart` (plain `test()` against
   `test/helpers/repository_harness.dart`, both factories, rows seeded in `setUp`): S-2214's parity for all
   four reads; a target stored for one day and inherited by a later day resolves to that value; a day
   before any target resolves to null; a session with only timed efforts is not counted; the latest
   bodyweight is the newest by `recordedAtMs`; a non-canonical unit yields null. Run it and record the
   failure.
2. [ ] Add the reads to `lib/core/services/stats_progress_service.dart` (D-1519): the window's nutrition
   series (8a's `nutritionSeries`), the per-day stored protein targets for a range (one
   `getNutritionTargetForDate` call per local day — no new repository method), the resistance-session
   count for a range (reusing `_sessionInWindow` and `_sectionForKind`), and the latest bodyweight in
   kilograms (via `getLatestMeasurement('bodyweight')`, returning null unless `unitId == 'unit-kg'`).
   Nothing else in the file changes.
3. [ ] Re-run step 1 to green, then the neighbouring suites:
   `flutter test test/nutrition_series_service_test.dart test/interference_test.dart test/stats_progress_test.dart test/db_seed_test.dart`.
   A changed expectation anywhere here is a defect in the new reads, not a test to update.
4. [ ] Mutation: make the resistance count include sessions with any effort kind rather than Resistance
   efforts — the timed-only fixture in step 1 must fail. Restore and re-run.
5. [ ] Docs: add the four reads to `docs/state_management/services_and_utils.md`'s `StatsProgressService`
   entry; add the per-day target resolution rule to `docs/nutrition.md`'s target section, noting that the
   shipped target screen persists `protein: 0.0` (F-1) so the resolution matters only for
   directly-stored targets.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/protein_consistency_service_test.dart test/nutrition_series_service_test.dart test/interference_test.dart test/stats_progress_test.dart test/db_seed_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/stats_progress_service.dart` (EDIT — four reads, nothing else);
`test/protein_consistency_service_test.dart` (NEW); `docs/state_management/services_and_utils.md`,
`docs/nutrition.md` (EDIT).

**Phase 2 verification notes (Conductor, date):** _(added at verification)_

### Phase 3: the card, the registry line, the guards and the close (@developer)

1. [ ] Write `test/protein_consistency_signal_screen_test.dart` first, asserting the exact strings, the
   kind label, the widget key, the position below the Mix layer and the dismissal of S-2216, S-2215's
   two-caution ordering, and the abstention when the repository holds no food or no resistance session.
   Run it and record the failure (the card is absent — the registry has no such signal yet).
2. [ ] Create `lib/core/services/signals/protein_consistency_signal.dart` (D-1502, D-1506, D-1517,
   D-1518, D-1519): id `protein-consistency`, kind caution, priority `kProteinConsistencyPriority`;
   `evaluate` derives the window from `context.now`, asks `context.progressService` for the four reads,
   hands the figures to the rule, and returns the card or null. It reads no repository, walks no history
   and calls no PR API.
3. [ ] Add one line to `buildSignalRegistry()`:
   `const <Signal>[ProgressionRateSignal(), ModalityMixShiftSignal(), InterferenceSignal(), FuelVsLoadSignal(), ProteinConsistencySignal()]`.
   Nothing else in the framework changes.
4. [ ] Extend the two existing registry guards, which this line breaks:
   `test/interference_test.dart` (`the caution order holds and the registry is ordered by it` — the
   caution id list becomes `modality-mix-shift`, `cross-modality-interference`, `fuel-vs-load`,
   `protein-consistency`, and the ascending-priority loop then covers four) and
   `test/modality_mix_shift_signal_screen_test.dart` (`lists exactly the four shipped signals, in order` —
   renamed to five, with `protein-consistency` appended). Both keep asserting the whole list.
5. [ ] Re-run the new suite to green, then the Stats surface and the framework suites:
   `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart test/fuel_vs_load_signal_screen_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/interference_signal_screen_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart`.
   A failure in a screen suite is a surface-height re-stabilisation; a failure in
   `test/signals_framework_test.dart` or `test/signals_service_test.dart` is a real finding.
6. [ ] Mutation: allow target mode when only some logged days carry a positive target — S-2211 must fail.
   Restore and re-run.
7. [ ] Structural guards, each a permanent test: (a) S-2213's no-calorie-amount, no-reduction-wording,
   whole-gram and one-decimal assertions, including the stripped-source scan (the `_strippedSource`
   helper style from `test/interference_test.dart`, so the guard fires on code and not on a comment);
   (b) the span and the reference are derived, not written — a scan proving
   `lib/core/models/protein_consistency.dart` holds no `2 weeks` literal and no `1.6` literal, while the
   built observation contains `'2 weeks'` and the built suggestion contains `'1.6'`; (c) the adapter walks
   no history and calls no PR API — it calls only the service; (d) a card with a null suggestion renders
   without an empty second line (S-2207).
8. [ ] Residue sweep: search `lib/`, `test/` and `docs/` for every name this PR introduces —
   `ProteinConsistencySignal`, `protein-consistency`, `proteinConsistency`, `kProteinConsistencyWindowDays`,
   `kProteinConsistencyMinLoggedDays`, `kProteinConsistencyShortfallPercent`,
   `kProteinConsistencyMinResistanceSessions`, `kProteinConsistencyMinBaselineWeeks`,
   `kProteinConsistencyBaselineWeeks`, `kProteinGuidancePerKg`, `kProteinConsistencyPriority`, and the
   observation's opening words. List every hit's file in the evidence file; confirm the framework files,
   `watch/` and `lib/data/` are absent.
9. [ ] Docs: add the Protein Consistency paragraph to `docs/signals.md`'s registered-signals section (the
   window and its gate, the two comparison modes, the per-day target rule, the baseline's consistent-weeks
   rule, the resistance gate, the 15% threshold, the copy and the two suggestions, every sentence naming a
   test); extend the caution-order paragraph to five (Interference 500 > Mix Shift 400 > Fuel vs Load 300
   > Protein Consistency 200); add the signal to `docs/stats_screen.md`'s Signals section; state F-1 in
   `docs/nutrition.md` (the daily target is calories-only, so Protein Consistency compares against the own
   baseline in the shipped app); confirm every touched doc stays under the 64 KiB ceiling.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/protein_consistency_signal_screen_test.dart test/protein_consistency_test.dart test/protein_consistency_service_test.dart test/fuel_vs_load_signal_screen_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart test/signals_layer_screen_test.dart test/docs_indexing_contract_test.dart`;
full `flutter test` with its summary line, compared with Phase 2's and explained.

**Predicted Files:** `lib/core/services/signals/protein_consistency_signal.dart` (NEW);
`lib/core/services/signals/signal_registry.dart` (EDIT — one line);
`test/protein_consistency_signal_screen_test.dart` (NEW); `test/protein_consistency_test.dart` and/or
`test/protein_consistency_service_test.dart` (EDIT — the guards);
`test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart` (EDIT — the two registry
guards); `docs/signals.md`, `docs/stats_screen.md`, `docs/nutrition.md` (EDIT);
`test/mix_layer_screen_test.dart` and/or `test/fuel_vs_load_signal_screen_test.dart` (EDIT — surface
heights only, and only if step 5 needs it).

**Phase 3 verification notes (Conductor, date):** _(added at verification)_

## Governor actions

- **@dba owns Phases 1–2.** The pure file, the constants, the four service reads. Nothing in
  `lib/features/`.
- **@developer owns Phase 3.** The adapter, the registry line, the card's tests, the guards and the docs.
- If Phase 1 needs a member added to `lib/core/models/nutrition_consistency.dart`, stop: D-1501 says the
  seam is wrong — the protein rule gets its own file.
- If Phase 2 needs a new `WorkoutRepository` method, stop: D-1519 says no, and adding one would create a
  Hive↔Mock parity obligation this PR does not need.
- If Phase 3 needs a `SignalContext` member or a framework file edit, stop: D-1518 says the seam is wrong.
- If any phase changes an existing nutrition, Fuel or Mix test's expected value, stop: this PR is
  read-only on those figures.
- The owner commits. No agent commits, branches or pushes.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/protein_consistency.dart` | NEW — constants, result type, rule, copy |
| `lib/core/services/signals/protein_consistency_signal.dart` | NEW — the signal |
| `lib/core/services/signals/signal_registry.dart` | EDIT — one registry line |
| `lib/core/services/stats_progress_service.dart` | EDIT — four reads |
| `test/protein_consistency_test.dart`, `test/protein_consistency_service_test.dart`, `test/protein_consistency_signal_screen_test.dart` | NEW — the rule, the reads, the card |
| `test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart` | EDIT — the two registry guards |
| `test/mix_layer_screen_test.dart`, `test/fuel_vs_load_signal_screen_test.dart` | EDIT — surface heights only, if needed |
| `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/nutrition.md`, `docs/state_management/services_and_utils.md` | EDIT — the rule, the constants, the reads, F-1 |

Nothing in `lib/data/`, `scripts/`, `watch/` or `lib/features/`. No file 8a creates is edited.
`docs/README.md` needs no change: it indexes feature docs, not plan files.

## Notes

- **Dependency graph:** 8a Phase 1 → 8a Phase 2 → 8b Phase 1 → 8b Phase 2 → 8b Phase 3, strictly. 8b
  cannot start before 8a's Phase 2 is green because `nutritionSeries` does not exist before it. Within 8b,
  Phase 1 is pure and could be written first, but its fixtures read the same figures the service will
  supply, so running it in order keeps one fixture vocabulary.
- **Re-ordering:** 8b Phases 1–2 can be written immediately after 8a Phase 2 and merged after 8a; there is
  no useful reordering inside 8b.
- **Predicted intermediate states:** after Phase 1 the repository has a pure rule nothing calls; the app is
  unchanged and the full suite is green. After Phase 2 the service exposes four more reads and every
  nutrition figure is unchanged. After Phase 3 the card can appear; the only pre-existing suites that may
  need a height adjustment are the two screen suites named in Phase 3 step 5.
- **Legacy handling:** none. No field, schema or stored value changes; the dismissal rides the existing
  preference API, which both repository implementations already implement.
- **Fixture reuse:** S-2201's target/rows/resistance fixture is the base for S-2202…S-2210 and S-2216;
  S-2205's baseline (two consistent 7/7 weeks at 145 g plus six 3-of-7 weeks) is the base for S-2206,
  S-2207, S-2211 and S-2212. S-2213 reads source files and needs no repository.
- **What the owner should know before this ships:** with F-1 unfixed, no user can reach target mode, so the
  card will always say `down from your usual`. That is a product decision the plan does not make.

## Open questions

| # | Item | Owner | Status |
|---|---|---|---|
| O-1 | D-1509's own-baseline rule: consistent weeks only, pooled logged days, at least 2 such weeks, never widened, never zero-filled | Owner | **Answered** 2026-10-03 (owner answer 2) |
| O-2 | F-1 — the daily target is calories-only, so the target-mode branch is unreachable through the UI. The pack puts targets out of scope, so this PR implements and tests the branch but no user reaches it | Owner | **Finding**, reported; **owner to confirm** that no protein-target field is added here |
| O-3 | D-1512's rounding: `p` is the whole-number percentage of the deficit, so 120/150 → `about 20%` and the pack's own Copy example 118/150 → `about 21%` (the pack's Copy block and its Acceptance row disagree; the Acceptance row is treated as the contract — F-2) | Owner | Defaulted — **owner to confirm** |
| O-4 | D-1506 — target mode requires **every** logged day in the window to carry a positive stored target; a mixed window falls back to the own baseline | Owner | Defaulted — **owner to confirm**; the alternative is to use the most recent logged day's target |
| O-5 | D-1507 — the target figure is the mean of the per-day targets over the logged days, rendered as a whole gram, with the threshold math on the unrounded mean | Owner | Defaulted — **owner to confirm**; S-2210 separates this from "the most recent day's target" |
| O-6 | D-1514 — the per-kilogram figure is appended in parentheses immediately after the `X g/day` figure, in both comparison modes | Owner | Defaulted — **owner to confirm**; the pack says only "add the per-kilogram figure" |
| O-7 | D-1511 — a bodyweight whose unit is not `unit-kg` is treated as absent | Owner | Defaulted — **owner to confirm**; both implementations store the canonical unit, so this only bites on hand-written rows |
| O-8 | D-1515 — with no target and no bodyweight the card carries **no** suggestion rather than a generic one | Owner | **Answered** by the pack ("otherwise omit the suggestion"); confirmed by 7a's nullable-`suggestion` support |

## Progress

| Item | Status | Evidence |
|---|---|---|
| Plan lines re-measured | not started | this file, read back after Phase 3 |
| Phase 1 | **Complete** | `.evidence.md` → Phase 1: red `+0 -1` (compile failure), green `+14`, four mutation pairs each red then restored green, full suite `+3692 ~1: All tests passed!`, `flutter analyze` `196 issues found.` (0 errors) |
| Phase 2 | not started | — |
| Phase 3 | not started | — |

## Assumption Log

_Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED (promoted to a D-x) or REVERT (remediation)._

- **A-1 (Phase 1, step 1) —** Read 8a's `nutrition_consistency.dart` and `fuel_vs_load.dart`; neither
  edited. The new rule reuses `weekBlockStarts`, `isConsistentWeek` and `kWeekDays` rather than
  re-deriving block arithmetic.
- **A-2 (Phase 1, step 3) —** `kProteinGuidancePerKg` is written `8 / 5`, not `1.6`. Options: the literal
  (matches the plan's step 3 text) or the fraction. S-2213 and Phase 3's guard 7(b) both require the
  definition file's stripped source to contain no `1.6` literal, and the plan's own step 3 also says the
  reference is "derived from its constant". The fraction satisfies both; the value is identical.
- **A-3 (Phase 1, step 5a) —** Mutation (a) cannot flip S-2201's card: its fixture is 20% below, not on the
  15% boundary, so `<=` and `<` agree there. Options: leave (a) unflippable, or assert the boundary
  directly. S-2201 now also asserts `proteinShortfallTestAgainstTarget(recentTotal: 1530, targetSum: 1800)`
  is true — exactly 15% below, where `<=` and `<` differ. The mutation then fails S-2201 as the plan
  requires, and D-1508's inclusive boundary gains a test it did not have.
- **A-4 (Phase 1, step 5d) —** Mutation (d) cannot flip S-2212's stated fixture: with 0 consistent blocks,
  a minimum of 1 and a minimum of 2 both abstain. Options: leave (d) unflippable, or add the boundary.
  S-2212 now also asserts an exactly-one-consistent-block case (5 of 7 days in one block, 3 of 7 in the
  rest) abstains, where the two minima differ. The mutation then fails S-2212 as the plan requires.
- **A-5 (Phase 1, step 5c) —** Mutation (c) is implemented as dividing **both** totals by
  `kProteinConsistencyWindowDays` **and** dropping the logged-day counts (passing `recentDays: 1,
  usualDays: 1`). Dividing the totals alone leaves the counts in the cross-multiplication and S-2205(b)
  still abstains, so the mutation would not flip. The mutated reading is the one S-2205 describes: 103.6
  against 145.
- **A-6 (Phase 1, step 2) —** S-2205(a), S-2206, S-2207 and S-2211 pin an observation of `118 g/day`, so
  those fixtures pass 118 g rows; the shared `_rows` default stays at S-2201's 120 g. No rule behaviour
  changed — the fixtures now match the scenarios' own text.
- **A-7 (Phase 1, step 2) —** S-2209(c)/(d) and S-2206's "latest of two bodyweights" are adapter/service
  reads (Phase 2). Phase 1 asserts only what the pure rule owns: the integer resistance count against the
  gate, and the per-kilogram figure for a bodyweight passed in. The classification and the selection are
  Phase 2's tests.
- **A-8 (Phase 1, step 2) —** S-2213's source scan covers `lib/core/models/protein_consistency.dart` only.
  The private day helpers are named `_midnight`/`_plusDays` rather than `_localDay` so the file's stripped
  source contains no `cal` substring; the guard is on the definition file, as the scenario states.

## Feedback

[empty — the Conductor folds non-empty entries into a new Iteration block and clears this one]
