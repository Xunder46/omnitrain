# Feature: Fuel vs Load + the shared nutrition foundation (Stats PR 8a — pack item 12)

> **Status:** READY (planner) — not started.
> **Next handoff:** @dba (Phase 1)
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 12
> ("Fuel vs Load (Caution)"), and the series seam in
> `docs/plans/2026-10-03-08-stats-pr8-index.md`.
> **Base:** `develop`, HEAD `2b6e8e5`. Stats PR 7 DONE: the Signals framework is live with three
> registered signals (Progression Rate positive, Modality Mix Shift and Cross-Modality Interference
> cautions) and `StatsProgressService.computeMixPeriod` is a period-scoped Mix walk.
> **Binding conventions:** `docs/global_conventions.md`. `docs/README.md` entries this plan depends
> on, read before Phase 1: `docs/signals.md`, `docs/nutrition.md`, `docs/training_load.md`,
> `docs/state_management/services_and_utils.md`, `docs/state_management/nutrition_state.md`,
> `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/data_models.md`,
> `docs/documentation_standard.md`, `docs/design_system.md`. Budget:
> `.github/agents/pr_scope_budget.md`.
> **Evidence:** `2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.evidence.md` (this folder). Review
> findings: `.review.md`. Neither is written into this file.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 576 (measured) | 500 | 800 |
| Phases | 3 | >3 | >5 |
| Tracks | 1 (`lib/`, `test/`, `docs/`) | >1 | — |
| Ledger decisions | 19 (D-1401…D-1419) | >20 | — |
| Scenarios | 13 (S-2101…S-2113) | >30 | — |
| Predicted production lines | ~285 | — | ~1,500 |

**Verdict:** one soft signal (plan length), zero hard. 8b
(`docs/plans/2026-10-03-08b-stats-pr8b-protein-consistency-plan/`) is the other half of the series and
depends on this plan's Phase 1 and Phase 2 only.

## What this PR does

One new caution signal and the small nutrition foundation both 8a and 8b stand on. The foundation is a
pure file of week-block helpers over the logged-day rule the app already applies, plus one
period-scoped entry point into the existing per-day nutrition aggregation. On top of it, the signal
compares the user's training load over the last 3 weeks with the 3 weeks before it and, when the load
rose at least 20% while their average daily intake has not risen, says so.

## Out of scope

- Macro-level versions of the signal (pack's out-of-scope).
- Any suggestion involving specific amounts, any calorie number, any change to nutrition targets.
- Protein Consistency — that is 8b, which reuses this plan's foundation.
- Any change to the Signals framework (`Signal`, `SignalContext`, `resolveSignals`, `signalsGateMet`,
  `SignalCard`, the dismissal store), the Mix layer's rendered figures, the Fuel row, the PR rules,
  `lib/data/` or `watch/`.

## Resolved Decisions (Ledger)

**D-1401 — The shared foundation.** `lib/core/models/nutrition_consistency.dart` is a new pure file
holding `kWeekDays = 7`, `kConsistentWeekMinLoggedDays = 5`, the block-start helper, the logged-day
count in a block, the consistency test and the logged-days-only mean. It imports no Flutter, no
repository, no service and reads no clock. 8b reuses this file unchanged.

**D-1402 — One per-day aggregation.** The per-day body of
`StatsProgressService.computeNutritionTrend` is extracted into ONE private helper that takes explicit
bounds, and a new public `nutritionSeries({required DateTime fromMs, required DateTime toMs})`
exposes it to a caller that carries its own `now`. `computeNutritionTrend` keeps its signature, its
real-clock anchor and its return value. No second aggregation of `ConsumedFood` rows exists anywhere.

**D-1403 — A logged day.** A day with at least one `ConsumedFood` row in the range, exactly as
`computeNutritionTrend` reads it today. Its calories and protein are that point's own rounded totals.
A day with no row is absent from the series and is never zero-filled.

**D-1404 — The consistent week.** A 7-calendar-day block is consistent when at least
`kConsistentWeekMinLoggedDays` (5) of its 7 days are logged: exactly 5 passes, 4 fails. Block starts
are `DateTime(y, m, d − n)` calendar arithmetic anchored on today's local midnight, oldest first,
abutting (no gap, no overlap). Never a `Duration`, so a DST transition cannot shift a boundary.

**D-1405 — The two periods.** Recent = the 21 local calendar days ending today:
`[DateTime(y, m, d − 20) 00:00, endOfDay(today)]`. Prior = the 21 days immediately before:
`[DateTime(y, m, d − 41) 00:00, DateTime(y, m, d − 20) 00:00 − 1 ms]` — an inclusive end, the millisecond
before the recent period's first instant, so the whole of `day(21)`, the prior period's last day, is
inside it. They abut with no gap and no overlap. Each is exactly 3 consecutive 7-day blocks — recent
starts `day(20)`, `day(13)`, `day(6)`; prior starts `day(41)`, `day(34)`, `day(27)`.

**D-1406 — The consistency gate.** The card needs all six blocks consistent (D-1404). One block at
4 of 7 logged days abstains, whatever the other figures say. The window is never widened and no day is
ever zero-filled.

**D-1407 — Load is the Mix layer's definition.** A period's load is the sum of that period's
`MixLayerData.segments[].measure` (the payload's own exact measures, in load minutes). The signal asks
`StatsProgressService.computeMixPeriod` once per period. The card shows only when both payloads are
non-null and both report `measure == MixMeasure.load`; a period measuring time abstains (the pack's
"the Mix layer is showing load (not time) for these weeks").

**D-1408 — Fires on load.** `priorLoad > 0 && 5 × recentLoad >= 6 × priorLoad`. Exactly +20% fires;
+19% does not. The comparison is on the two exact totals, never on a rounded percentage.

**D-1409 — Intake is logged-days-only.** `recentIntake` is the mean of the recent period's logged
days' calories and `priorIntake` the same for the prior period — divided by the number of logged days,
never by the window length. The gate (D-1406) guarantees at least 15 logged days per period, so both
means exist.

**D-1410 — Fires on intake.** `priorIntake > 0 && 100 × recentIntake <= 105 × priorIntake`, compared
as an exact fraction on the two periods' totals and logged-day counts:
`20 × recentCalorieTotal × priorLoggedDays <= 21 × priorCalorieTotal × recentLoggedDays`. Exactly +5%
fires; +6% does not; any lower value passes.

**D-1411 — No reverse version.** A load that fell never produces a card, whatever the intake did. The
rule is one-directional and there is no second signal for the reverse.

**D-1412 — Observation.** One sentence for both the lower and the unchanged case (owner answer 1):
`'Training load is up $p% over the last ${kFuelVsLoadWindowDays ~/ 7} weeks; your average daily intake has not risen with it.'`
with `p = ((recentLoad / priorLoad) − 1) × 100` rounded to a whole number. The span is derived from
the constant, never written as a literal.

**D-1413 — Suggestion.** `'Worth checking that intake is keeping up with training.'` — verbatim from
the pack.

**D-1414 — Hard rules.** No card text carries a calorie amount, a calorie target, or any wording that
suggests eating less. The observation names no intake figure at all — only the load percentage and the
fact that intake has not risen. The definition file contains no `cal`/`kcal` literal.

**D-1415 — Kind, priority, id and title.** Kind caution. Priority `kFuelVsLoadPriority = 300`, below
7a's Modality Mix Shift (400) and above 8b's Protein Consistency (200). The id is `fuel-vs-load` — the
dismissal key, the widget key and the semantic label. The title is `Fuel vs load` and is never rendered
(the layer renders the kind's label, `Worth a look`).

**D-1416 — Plug-in only.** One class implementing `Signal` in
`lib/core/services/signals/fuel_vs_load_signal.dart` plus one line in `buildSignalRegistry()`. No file
in `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart` or
`lib/features/stats/widgets/signals_layer.dart` changes.

**D-1417 — The pure file.** `lib/core/models/fuel_vs_load.dart` holds the constants, the result type,
the rule and the copy builder. It imports `lib/core/models/nutrition_consistency.dart` only — no
Flutter, no repository, no clock, no service. The gate, the load test, the intake test and the copy
builder are separately callable, so a scenario can assert one stage without composing the rule.

**D-1418 — The adapter reads the service, never the repository.** `evaluate` derives both periods from
`context.now`, asks `context.progressService` for the two Mix payloads and the nutrition series, and
hands the figures to the rule. It reads no `ConsumedFood` row, walks no history and calls no PR API.
`SignalContext` gains no member.

**D-1419 — `computeMixPeriod` is reused unchanged.** It is already period-generic: its baseline is
`baselineBlockStarts(localMidnightDay(fromMs))` and its measure gate is the layer's own, so a 21-day
call needs no new code. Its doc comment's "the last `kModalityMixShiftPeriodDays` days" sentence
describes its 7a caller and is corrected to describe the caller, not the method. Proven by a test that
the 21-day call equals the equivalent window call and by 7a's suite passing unmodified.

## Feature Invariants

Only the invariants that bite here; project-wide rules stay in `docs/global_conventions.md`.

- **The Mix layer's rendered figures do not change.** `computeMixPeriod` and `_mixPayload` are not
  edited at all in this PR; 7a's suites pass unmodified.
- **One per-day aggregation.** `computeNutritionTrend`'s output is byte-for-byte what it was; the
  extraction is behaviour-preserving and the Fuel row's figures do not move.
- **A signal never walks history itself.** The adapter calls the service; the service rides its cached
  history index.
- **One signal = one class + one registry line.** No framework file names a concrete signal.
- **No new colour, token, widget or `OmniTheme` value.** The card uses the layer's existing caution
  styling.
- **The nutrition rows are read-only.** This PR writes no `ConsumedFood` row, no target and no
  preference other than the framework's own dismissal store.

## Requirements

- **R1** A user whose load rose at least 20% over the last 3 weeks while their average daily intake has
  not risen sees one caution card under the Mix layer.
- **R2** The card names the user's own load percentage and the 3-week span, and never a calorie figure.
- **R3** A week that is not consistently logged anywhere in the six blocks suppresses the card.
- **R4** A load rise below 20%, or an intake rise above 5%, suppresses the card.
- **R5** A falling load never produces a card.
- **R6** The card is dismissible and stays dismissed for the framework's window.
- **R7** No existing Stats figure changes.

## Acceptance Criteria (each maps to ≥1 scenario)

| # | Criterion (from the pack, plus the owner's boundaries) | Scenarios |
|---|---|---|
| AC-1 | With all 6 weeks consistently logged, load up 25% and intake up 2%, the card shows with the user's load percentage | S-2101 |
| AC-2 | One of the 6 weeks logged on only 4 of 7 days shows no card, whatever the other figures | S-2102 |
| AC-3 | Load up 19% shows no card; exactly +20% shows one | S-2103, S-2104 |
| AC-4 | Intake up 6% shows no card; exactly +5% shows one | S-2105, S-2106 |
| AC-5 | Intake averages count logged days only | S-2107 |
| AC-6 | No card text anywhere contains a calorie amount or suggests reducing intake | S-2108 |
| AC-7 | A user whose load dropped 30% while intake stayed flat sees no card | S-2109 |
| AC-8 | The consistent-logging gate is exactly 5 of 7 days | S-2110 |
| AC-9 | A period the Mix layer measures in time suppresses the card | S-2111 |
| AC-10 | The two 21-day periods abut, and 7a's 28-day figures do not move | S-2112 |
| AC-11 | The card renders on the layer, dismisses, and leaves every other block alone | S-2113 |

## Scenarios

Fixtures name every entity class involved. `day(n)` means local midnight `n` days before today; all
times are local. Pure scenarios call the rule directly with hand-built figures — the pack's own
acceptance rows are S-2101…S-2109. Every scenario below has been checked against its own threshold
before being written: each one either sits exactly on a boundary or a whole percentage point clear of
it, never "roughly" on it.

### S-2101: the pack's own row fires
- **Fixture:** 42 consecutive logged days, `day(41)`…`day(0)`, one `ConsumedFood` row each (7 of 7 per
  block, so all six blocks consistent). Recent period (days 20…0): calories 2,040 on each of its 21
  days. Prior period (days 41…21): calories 2,000 on each of its 21 days. Recent load total 1,250
  load minutes; prior load total 1,000; both payloads `measure: MixMeasure.load`.
- **Trigger:** one rule call with the two periods' figures.
- **Flow:** D-1406 gate, then D-1408 and D-1410, then D-1412/D-1413.
- **Expected outcome:** fires. Load: `5 × 1250 = 6250 >= 6 × 1000 = 6000`. Intake:
  `20 × 42840 × 21 = 17,992,800 <= 21 × 42000 × 21 = 18,522,000`. `p = 25`. Observation
  `'Training load is up 25% over the last 3 weeks; your average daily intake has not risen with it.'`
  Suggestion `'Worth checking that intake is keeping up with training.'`
- **Edge case of:** none.

### S-2102: one week at 4 of 7 days suppresses everything
- **Fixture:** S-2101's figures unchanged, except the block starting `day(13)` has food on only four of
  its seven days (`day(13)`, `day(12)`, `day(11)`, `day(10)`).
- **Trigger:** one rule call.
- **Flow:** D-1406 first.
- **Expected outcome:** null — the card never appears "whatever the other figures" are. (A rule that
  gates on the *total* logged days rather than per block fires here; this is mutation (c) in Phase 1.)
- **Edge case of:** S-2101.

### S-2103: +19% load shows nothing
- **Fixture:** all six blocks 7 of 7 logged, intake flat at 2,000/day both periods, recent load 1,190,
  prior load 1,000.
- **Trigger:** one rule call.
- **Flow:** D-1408.
- **Expected outcome:** null. `5 × 1190 = 5950 < 6000`.
- **Edge case of:** S-2104 (one point below the boundary).

### S-2104: exactly +20% load fires
- **Fixture:** as S-2103 with recent load 1,200.
- **Trigger:** one rule call.
- **Flow:** D-1408's inclusive `>=`.
- **Expected outcome:** fires, `p = 20`, observation `'Training load is up 20% over the last 3 weeks;
  your average daily intake has not risen with it.'`
- **Edge case of:** S-2101.

### S-2105: exactly +5% intake still fires
- **Fixture:** all six blocks 7 of 7 logged; recent load 1,250, prior load 1,000; recent calories
  2,100/day, prior calories 2,000/day.
- **Trigger:** one rule call.
- **Flow:** D-1410's inclusive `<=`.
- **Expected outcome:** fires. `20 × 2100 × 21 = 882,000 <= 21 × 2000 × 21 = 882,000`. Observation
  `'Training load is up 25% over the last 3 weeks; your average daily intake has not risen with it.'`
- **Edge case of:** S-2106 (one point above the boundary).

### S-2106: +6% intake shows nothing
- **Fixture:** as S-2105 with recent calories 2,120/day.
- **Trigger:** one rule call.
- **Flow:** D-1410.
- **Expected outcome:** null. `20 × 2120 × 21 = 890,400 > 882,000`.
- **Edge case of:** S-2101.

### S-2107: the intake mean divides by logged days, not by the window
- **Fixture (two parts).** (a) Recent period: 5 of 7 days logged in each of its three blocks (15 logged
  days), 2,500 kcal on each of them (total 37,500); prior period: 7 of 7 logged, 2,000 kcal on each of
  its 21 days (total 42,000); recent load 1,250, prior load 1,000. (b) the same with the recent days at
  2,000 kcal (total 30,000).
- **Trigger:** one rule call each.
- **Flow:** D-1409's divisor, then D-1410.
- **Expected outcome:** (a) null — the logged-day means are 2,500 against 2,000, a 25% rise, above the
  5% tolerance. A rule dividing by the 21-day window length reads 1,785.7 against 2,000 and fires,
  which is wrong. (b) fires — 2,000 against 2,000 is a 0% rise, and the smaller logged-day count must
  not read as a smaller intake.
- **Edge case of:** S-2101.

### S-2108: no calorie number and no reduction wording
- **Fixture:** S-2101's fired card.
- **Trigger:** read the card's `observation` and `suggestion`; then scan the definition file's stripped
  source.
- **Flow:** D-1414.
- **Expected outcome:** neither string matches `RegExp(r'\d+\s*(cal|kcal|calorie)')`
  (case-insensitive), neither contains `eat less`, `eat fewer`, `reduce`, `cut back` or `lower your
  intake`, and the observation's only digits are the load percentage and the span's `3`. The stripped
  source of `lib/core/models/fuel_vs_load.dart` contains no `cal` and no `kcal`.
- **Edge case of:** none.

### S-2109: a falling load never produces a card
- **Fixture:** all six blocks 7 of 7 logged; recent load 700, prior load 1,000 (−30%); intake flat at
  2,000/day both periods.
- **Trigger:** one rule call.
- **Flow:** D-1411.
- **Expected outcome:** null. There is no reverse version and no second signal for it.
- **Edge case of:** S-2101.

### S-2110: the gate is exactly 5 of 7
- **Fixture:** a block starting `day(20)` with logged days on exactly five of its seven days
  (`day(20)`…`day(16)`), and a second block starting `day(13)` with logged days on four
  (`day(13)`…`day(10)`).
- **Trigger:** the gate helper and the consistency helper, one call each.
- **Flow:** D-1404.
- **Expected outcome:** the first block's logged-day count is 5 and it is consistent; the second's is 4
  and it is not. A rule using `> 5` or `>= 6` fails the first; one using `>= 4` passes the second.
- **Edge case of:** S-2102.

### S-2111: a period measuring time suppresses the card
- **Fixture (F-TIME21):** rated sessions placed so the recent period's baseline holds at least 4 rated
  weeks and the prior period's baseline holds 3, with every session's work timed so the Mix layer
  measures time. Both periods are otherwise S-2101's figures.
- **Trigger:** the rule with the prior payload's `measure` set to `MixMeasure.time`, and the service
  call that produced it.
- **Flow:** D-1407.
- **Expected outcome:** null — a payload measuring time is not "the Mix layer showing load".
- **Edge case of:** S-2101.

### S-2112: the two periods abut, and 7a's figures do not move
- **Fixture (F-MIX42):** a mixed rated history spanning the last 6 months, with at least 4 rated
  baseline weeks for a period starting `day(20)` and for one starting `day(41)`.
- **Trigger:** `computeMixPeriod(fromMs: day(20), toMs: now)`,
  `computeMixLayer(window: periodScoped(day(20), todayEnd), now: now, startOfWeek: 'monday')` and
  `computeMixPeriod(fromMs: day(41), toMs: day(20) 00:00 − 1 ms)`.
- **Flow:** D-1419 and D-1405.
- **Expected outcome:** the 21-day period call is field-for-field equal to the equivalent window call
  (`measure`, `segments`, `baselineSegments`, `unratedSessionCount`, `ratedBaselineWeeks`, and an empty
  `weeks`); the prior call's last instant is the millisecond before the recent call's first; a session
  starting exactly at `day(20) 00:00` is in the recent period and not in the prior one, and one starting
  at `day(21) 00:00` is in the prior period. A session or a logged day at `day(21) 23:59` is in the prior
  period (not dropped), and one at `day(20) 00:00` is in the recent period. The existing 7a test
  (`test/modality_mix_period_service_test.dart`) passes unmodified.
- **Edge case of:** none.

### S-2113: the card on the layer, and its dismissal
- **Fixture:** S-2101's food and load fixtures seeded on the repository, the Stats window scoped so the
  Mix layer renders above the Signals layer, and no other signal qualifying.
- **Trigger:** open the Stats screen; read the layer; then tap the card's dismiss control.
- **Flow:** one evaluation, then the framework's dismissal write.
- **Expected outcome:** the layer shows the caution card with S-2101's exact observation and suggestion,
  the `Worth a look` kind label, the widget key `signal_card_fuel-vs-load`, and no quiet line; it sits
  below the Mix layer; the ALL TIME, Instruments and Fuel blocks are unchanged. After one tap the card
  is gone in the next frame, the quiet line appears, and the dismissal store holds `fuel-vs-load` with
  an integer timestamp; a fresh screen build keeps it hidden.
- **Edge case of:** none. **Mock only for the tap** — a Hive write started inside a widget test's
  fake-async zone can never drain, so the Hive round trip belongs to the plain service test in
  Phase 2.

## Iteration 1

### Executor block (applies to every phase in this plan)

- **Branch:** work on `develop`. Never create a branch, never commit, never stage, never push — the
  owner commits.
- **Shell:** every command goes through the gateway, spelled in full:
  `.github/copilot/scripts/macos/gateway.sh <list|lint|test [paths]|format <file paths>|pub-get|git-status|git-diff|git-log|git-show>`.
  The bare form is denied. No `git`, `grep`, `sed`, `awk` or `wc` in a shell — use the gateway's
  `git-*` verbs and your file tools. A denied command is never retried. A gateway `test` command over
  3 minutes is a hang: stop and report it.
- **Red first:** every phase writes its tests before the code they test, runs them, and records the
  failing output in `<this plan>.evidence.md`. A test that has never failed proves nothing.
- **Mutations:** at least two inverse edits per plan, on files that already exist at that point. Apply
  one, run the named test, record the failure, restore the file, re-run to confirm green, and *never
  end a step with a mutation applied*. A mutation on a **new, untracked** file: copy the original line
  into the evidence file first, so the restore is provable.
- **Step budget:** at most 8–10 steps per run. Read at most ~100 lines of a large file at a time.
  `lib/core/services/stats_progress_service.dart` is **2,420 lines**: find a region by searching for
  its symbol, then read that region only.
- **Evidence:** baselines, suite summaries, red→green tables and the mutation pairs go to
  `docs/plans/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan/2026-10-03-08a-stats-pr8a-fuel-vs-load-plan.evidence.md`.
  Never into this plan. Findings go to `...review.md`.
- **Ambiguity:** never stop. Pick the option most consistent with the Ledger and the Feature
  Invariants, log it in the Assumption Log (decision, options considered, rationale) and continue.
- **Docs trail code by zero phases:** each phase updates the docs it invalidated. Every behaviour
  sentence names a test that exists.
- **Baseline for this plan (measured on `develop` at `2b6e8e5`):** `flutter analyze` →
  `196 issues found.` with 0 errors; `flutter test` → `+3635 ~1: All tests passed!`.

### Phase 1: the pure foundation and the Fuel vs Load rule (@dba)

1. [ ] Write `test/nutrition_consistency_test.dart` (plain `test()`, no widget, no repository): S-2110
   (exactly 5 passes, 4 fails), the block-start arithmetic (eight starts for an 8-week range, oldest
   first, abutting, `day(n)`-exact), a month boundary (a block spanning a month end keeps 7 days), and
   the logged-days-only mean (empty → `null`, never `0`). Run it and record the failure.
2. [ ] Create `lib/core/models/nutrition_consistency.dart` (D-1401, D-1403, D-1404): the two constants,
   the block-start helper, the logged-day count, the consistency test and the mean. Pure Dart only —
   no Flutter import, no clock, no repository.
3. [ ] Re-run step 1's suite to green.
4. [ ] Write `test/fuel_vs_load_test.dart` (plain `test()`): S-2101, S-2102, S-2103, S-2104, S-2105,
   S-2106, S-2107, S-2108, S-2109, S-2111, each asserting one stage where the scenario names one. Run
   it and record the failure.
5. [ ] Create `lib/core/models/fuel_vs_load.dart` (D-1405…D-1415, D-1417): the constants
   `kFuelVsLoadWindowDays = 21`, `kFuelVsLoadLoadRisePercent = 20`,
   `kFuelVsLoadIntakeTolerancePercent = 5`, `kFuelVsLoadPriority = 300`; the result type; the gate, the
   load test and the intake test as separately callable functions; the copy builder with the span
   derived from the constant. Exact integer cross-multiplication in the two boundary tests, no rounding
   in either test, no Flutter.
6. [ ] Re-run steps 1 and 4 to green.
7. [ ] Mutations, one at a time, each restored: **(a)** D-1408's `>=` → `>` — S-2104 must fail;
   **(b)** D-1410's `<=` → `<` — S-2105 must fail; **(c)** D-1404's `>= 5` → `> 5` — S-2110's first
   assertion must fail. Record all three red→green pairs in the evidence file.
8. [ ] Docs: add the `fuel_vs_load` and `nutrition_consistency` constant groups to
   `docs/constants_reference.md` (names and values only, no restatement of a rule); add the
   logged-day/consistent-week rule to `docs/nutrition.md`'s computation section with its test named.

**Done Criteria** (run until green):
`flutter analyze` (expect `196 issues found.`, 0 errors);
`flutter test test/nutrition_consistency_test.dart test/fuel_vs_load_test.dart`;
full `flutter test` with its summary line pasted into the evidence file.

**Predicted Files:** `lib/core/models/nutrition_consistency.dart` (NEW);
`lib/core/models/fuel_vs_load.dart` (NEW); `test/nutrition_consistency_test.dart` (NEW);
`test/fuel_vs_load_test.dart` (NEW); `docs/constants_reference.md`, `docs/nutrition.md` (EDIT).

**Phase 1 verification notes (Conductor, date):** _(added at verification)_

### Phase 2: the period-scoped per-day series (@dba)

1. [ ] Write `test/nutrition_series_service_test.dart` (plain `test()` against
   `test/helpers/repository_harness.dart`, both factories, rows seeded in `setUp`): the new read returns
   the same points `computeNutritionTrend(days: …)` returns for the equivalent span; a range's logged
   days are the rows' own days; a day with no row is absent; the same figures come back from Mock and
   Hive; and S-2112 (the 21-day Mix period equals the equivalent window call, the two periods abut, the
   boundary sessions land in the right period). Run it and record the failure.
2. [ ] Add `nutritionSeries({required DateTime fromMs, required DateTime toMs})` to
   `lib/core/services/stats_progress_service.dart` (D-1402, D-1403). Find `computeNutritionTrend` by
   searching for `Future<List<NutritionTrendPoint>> computeNutritionTrend`, read that region, lift its
   aggregation into ONE private helper taking explicit bounds, and have `computeNutritionTrend` compute
   its own bounds and delegate. Its signature, its real-clock anchor and its output do not change.
3. [ ] Correct the `computeMixPeriod` doc comment's caller sentence (D-1419): it currently says the
   period "is the last `kModalityMixShiftPeriodDays` days", which describes 7a's caller. The method
   itself takes the bounds it is given.
4. [ ] Re-run step 1 to green, then the nutrition, Fuel and Mix suites:
   `flutter test test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart`.
   (`test/stats_progress_test.dart` is where the existing `computeNutritionTrend` and
   `computeFuelSummary` service tests live — groups "Nutrition trend aggregation" and
   "computeNutritionTrend (full history)".)
   A changed expectation in `test/modality_mix_period_service_test.dart` is a defect in the doc-only
   edit, not a test to update.
5. [ ] Mutation: anchor the new read on the real clock (`OmniDateUtils.todayMidnightMs()`) instead of
   the bounds it is given — the fixture's own past dates must stop matching and step 1 must fail.
   Restore and re-run.
6. [ ] Docs: add `nutritionSeries` to `docs/state_management/services_and_utils.md`'s
   `StatsProgressService` entry; add the period entry point's 21-day use to `docs/training_load.md`'s
   entry-point section; note the shared per-day source in `docs/nutrition.md`'s
   `computeNutritionTrend` entry.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/nutrition_series_service_test.dart test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/db_seed_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/stats_progress_service.dart` (EDIT — the aggregation extraction,
the new method and one doc comment, nothing else); `test/nutrition_series_service_test.dart` (NEW);
`docs/state_management/services_and_utils.md`, `docs/training_load.md`, `docs/nutrition.md` (EDIT).

**Phase 2 verification notes (Conductor, date):** _(added at verification)_

### Phase 3: the card, the registry line, the guards and the close (@developer)

1. [ ] Write `test/fuel_vs_load_signal_screen_test.dart` first, asserting the exact strings, the kind
   label, the widget key, the position below the Mix layer and the dismissal of S-2113, and the
   abstention when the repository holds no food. Run it and record the failure (the card is absent —
   the registry has no such signal yet).
2. [ ] Create `lib/core/services/signals/fuel_vs_load_signal.dart` (D-1405, D-1407, D-1415, D-1416,
   D-1418): id `fuel-vs-load`, kind caution, priority `kFuelVsLoadPriority`; `evaluate` derives both
   periods from `context.now`, asks `context.progressService` for the two Mix payloads and the nutrition
   series, hands the figures to the rule, and returns the card or null. It reads no repository, walks no
   history and calls no PR API.
3. [ ] Add one line to `buildSignalRegistry()`:
   `const <Signal>[ProgressionRateSignal(), ModalityMixShiftSignal(), InterferenceSignal(), FuelVsLoadSignal()]`.
   Nothing else in the framework changes.
4. [ ] Extend the two existing registry guards, which this line breaks:
   `test/interference_test.dart` (`the caution order holds and the registry is ordered by it` — the
   caution id list becomes `modality-mix-shift`, `cross-modality-interference`, `fuel-vs-load`, and the
   ascending-priority loop then covers three) and
   `test/modality_mix_shift_signal_screen_test.dart` (`lists exactly the three shipped signals, in
   order` — renamed to four, with `fuel-vs-load` appended). Both keep asserting the whole list.
5. [ ] Re-run the new suite to green, then the Stats surface and the framework suites:
   `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/interference_signal_screen_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart`.
   A failure in a screen suite is a surface-height re-stabilisation; a failure in
   `test/signals_framework_test.dart` or `test/signals_service_test.dart` is a real finding.
6. [ ] Mutation: drop D-1407's `measure == MixMeasure.load` requirement — S-2111 must fail. Restore and
   re-run.
7. [ ] Structural guards, each a permanent test: (a) S-2108's no-calorie-number and no-reduction-wording
   assertions, including the stripped-source scan (use the `_strippedSource` helper style from
   `test/interference_test.dart`, so the guard fires on code and not on a comment); (b) the span is
   derived, not written — a scan proving `lib/core/models/fuel_vs_load.dart` holds no `3 weeks` literal
   while the built observation contains `'3 weeks'`; (c) the adapter walks no history and calls no PR
   API — it calls only `computeMixPeriod` and `nutritionSeries`.
8. [ ] Residue sweep: search `lib/`, `test/` and `docs/` for every name this PR introduces —
   `FuelVsLoadSignal`, `fuel-vs-load`, `fuelVsLoad`, `kFuelVsLoadWindowDays`,
   `kFuelVsLoadLoadRisePercent`, `kFuelVsLoadIntakeTolerancePercent`, `kFuelVsLoadPriority`,
   `nutritionSeries`, `nutrition_consistency`, and the observation's opening words. List every hit's
   file in the evidence file; confirm the framework files, `watch/` and `lib/data/` are absent.
9. [ ] Docs: add the Fuel vs Load paragraph to `docs/signals.md`'s registered-signals section (the two
   periods, the six-block gate, the measure gate, the two thresholds, the copy and the suggestion, every
   sentence naming a test); rewrite the stale "The only caution registered today is Modality Mix Shift"
   paragraph in `docs/signals.md` into the shipped caution order (Interference 500 > Mix Shift 400 >
   Fuel vs Load 300), naming the order test; add the signal to `docs/stats_screen.md`'s Signals section;
   confirm both docs stay under the 64 KiB ceiling.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/fuel_vs_load_signal_screen_test.dart test/fuel_vs_load_test.dart test/nutrition_consistency_test.dart test/nutrition_series_service_test.dart test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart test/signals_layer_screen_test.dart test/docs_indexing_contract_test.dart`;
full `flutter test` with its summary line, compared with Phase 2's and explained.

**Predicted Files:** `lib/core/services/signals/fuel_vs_load_signal.dart` (NEW);
`lib/core/services/signals/signal_registry.dart` (EDIT — one line);
`test/fuel_vs_load_signal_screen_test.dart` (NEW); `test/fuel_vs_load_test.dart` and/or
`test/nutrition_consistency_test.dart` (EDIT — the guards);
`test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart` (EDIT — the two
registry guards); `docs/signals.md`, `docs/stats_screen.md` (EDIT);
`test/mix_layer_screen_test.dart` and/or `test/progression_rate_signal_screen_test.dart` (EDIT — surface
heights only, and only if step 5 needs it).

**Phase 3 verification notes (Conductor, date):** _(added at verification)_

## Governor actions

- **@dba owns Phases 1–2.** The pure files, the constants, the service read. Nothing in
  `lib/features/`.
- **@developer owns Phase 3.** The adapter, the registry line, the card's tests, the guards and the docs.
- If Phase 2 changes any existing nutrition, Fuel or Mix test's expected value, stop: D-1402 and D-1419
  are behaviour-preserving, so a changed expectation is a defect in the extraction, not a test to
  update.
- If Phase 3 needs a `SignalContext` member or a framework file edit, stop: D-1416 says the seam is
  wrong.
- The owner commits. No agent commits, branches or pushes.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/nutrition_consistency.dart` | NEW — the shared week-block and logged-day helpers |
| `lib/core/models/fuel_vs_load.dart` | NEW — constants, result type, rule, copy |
| `lib/core/services/signals/fuel_vs_load_signal.dart` | NEW — the signal |
| `lib/core/services/signals/signal_registry.dart` | EDIT — one registry line |
| `lib/core/services/stats_progress_service.dart` | EDIT — `nutritionSeries`, the shared aggregation, one doc comment |
| `test/nutrition_consistency_test.dart`, `test/fuel_vs_load_test.dart`, `test/nutrition_series_service_test.dart`, `test/fuel_vs_load_signal_screen_test.dart` | NEW — the rule, the gate, the service read, the card |
| `test/interference_test.dart`, `test/modality_mix_shift_signal_screen_test.dart` | EDIT — the two registry guards |
| `test/mix_layer_screen_test.dart`, `test/progression_rate_signal_screen_test.dart` | EDIT — surface heights only, if needed |
| `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/nutrition.md`, `docs/training_load.md`, `docs/state_management/services_and_utils.md` | EDIT — the rule, the constants, the entry point |

Nothing in `lib/data/`, `scripts/`, `watch/` or `lib/features/` outside the Stats screen's existing
Signals layer. `docs/README.md` needs no change: it indexes feature docs, not plan files.

## Notes

- **Dependency graph:** Phase 1 → Phase 2 → Phase 3, strictly. Phase 2's service read needs Phase 1's
  helper only as a consumer; Phase 3's adapter needs both. There is no useful reordering.
- **Predicted intermediate states:** after Phase 1 the repository has a pure rule nothing calls; the app
  is unchanged and the full suite is green. After Phase 2 the service exposes one more read and every
  nutrition figure is unchanged. After Phase 3 the card can appear; the only pre-existing suites that
  may need a height adjustment are the two screen suites named in Phase 3 step 5.
- **Legacy handling:** none. No field, schema or stored value changes; the dismissal rides the existing
  preference API, which both repository implementations already implement.
- **Fixture reuse:** S-2101's food and load figures are the base for S-2102…S-2109 (pure) and S-2113
  (seeded, Mock). F-TIME21 and F-MIX42 are Phase 2's service fixtures. S-2108's scan reads the source
  file, so it needs no fixture.
- **8b's dependency:** 8b consumes `lib/core/models/nutrition_consistency.dart` and
  `nutritionSeries` exactly as this plan leaves them; it adds no method to that file.

## Open questions

| # | Item | Owner | Status |
|---|---|---|---|
| O-1 | D-1412's single observation sentence for both the lower-intake and the unchanged case, and the phrase `your average daily intake has not risen with it` | Owner | **Answered** 2026-10-03 (owner answer 1); the suggestion is the pack's verbatim text |
| O-2 | D-1412's `p` is a whole-number percentage rounded from the exact ratio (`25` for 1,250/1,000) | Owner | Defaulted — **owner to confirm**; the alternative is truncation |
| O-3 | D-1407 requires `measure == load` for **both** periods; a period the layer measures in time abstains | Owner | Defaulted — **owner to confirm**; the alternative is to read only the recent period's measure |
| O-4 | D-1409's intake mean divides by logged days, and D-1410's tolerance is on that mean rather than on the two totals directly | Owner | Defaulted — **owner to confirm**; S-2107(a) is the case that separates the two readings |
| O-5 | D-1415's priority 300 and the caution order | Owner | Defaulted — **owner to confirm**; matches 7a's D-1214 and 7b's D-1315 |
| O-6 | Whether the card should also fire when the user logged food on fewer than 5 of 7 days in a week but a lot of days overall | Owner | Defaulted — **no**; D-1406 is the pack's own gate, per block |

## Progress

| Item | Status | Evidence |
|---|---|---|
| Plan lines re-measured | not started | this file, read back after Phase 3 |
| Phase 1 | **Complete** | `.evidence.md` § Phase 1 — red→green for both suites, three mutation pairs, `lint` `196 issues found.` (0 errors), full suite `01:37 +3654 ~1: All tests passed!`; § Phase 1 — Fix 1 — the two "the constant contracts" tests the docs name, mutation (f), full suite `01:36 +3656 ~1: All tests passed!` |
| Phase 2 | **Complete** | `.evidence.md` § Phase 2 — red run (compile: `nutritionSeries` not defined) → green `00:00 +11: All tests passed!`; extraction defect found by the full suite (`S-1263` residue sweep) and fixed; mutation (d) `+2 -9: Some tests failed.` → restored green; `lint` `196 issues found.` (0 errors); full suite `01:46 +3667 ~1: All tests passed!` |
| Phase 3 | not started | — |

## Assumption Log

_Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED (promoted to a D-x) or REVERT (remediation)._

- **A-1 (Phase 1, step 5) —** D-1417 says `lib/core/models/fuel_vs_load.dart` "imports
  `nutrition_consistency.dart` only". The file also imports `training_load.dart`, for `MixMeasure`.
  Options: (i) take the measure as a local enum or a bool; (ii) import `training_load.dart` as the
  sibling `modality_mix_shift.dart` does. Chose (ii) — S-2111 requires the rule to see
  `MixMeasure.time`, and a parallel enum would be a second source of truth for the same vocabulary.
  The brief's own restatement of the constraint forbids only Flutter, repository, service and clock
  imports, all of which still hold.
- **A-2 (Phase 1, step 8) —** the plan's step 8 asks for "names and values only" in
  `docs/constants_reference.md`, but `docs/documentation_standard.md` §3.4 forbids restating a numeric
  value defined in source. Chose the standard: both new groups use the established sibling form (a
  "Constant | Rule it governs" table plus a "Verified by …" line), matching Training Load, Modality Mix
  Shift, Progression Rate and Interference. No value is written in prose.
- **A-3 (Phase 2, step 2) —** D-1402 names the extracted helper only as "ONE private helper". The
  name must not contain the literal `nutritionTrend`: `test/stats_legacy_removal_test.dart`'s S-1263
  sweep is a case-sensitive `contains` over `_kRetiredNames`, which lists it (`computeNutritionTrend`
  is safe — capital `N`). Chose `_nutritionPointsInRange`; the first name, `_nutritionTrendInRange`,
  tripped the sweep and was fixed rather than the test.
- **A-4 (Phase 2, step 3) —** the corrected `computeMixPeriod` sentence must describe the caller, not
  the method. Chose to name the two callers by rule (the Modality Mix Shift rule's shift period, the
  Fuel vs Load rule's 21-day period) rather than by the plan's `7a`/`8a` series labels, which are
  plan vocabulary and not app vocabulary.

## Feedback

[empty — the Conductor folds non-empty entries into a new Iteration block and clears this one]
