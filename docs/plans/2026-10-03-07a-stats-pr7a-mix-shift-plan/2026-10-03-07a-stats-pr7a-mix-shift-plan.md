# Feature: Modality Mix Shift (Stats PR 7a — pack item 10)

> **Status:** DONE — shipped as `b3b91fa`.
> **Next handoff:** @dba (Phase 1)
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 10
> ("Modality Mix Shift (Caution)"), and the series seam in
> `docs/plans/2026-10-03-07-stats-pr7-index.md`.
> **Base:** `develop`, Stats PR 6 DONE (`docs/plans/2026-10-03-06-stats-pr6-index.md`). The Signals
> framework is live with one registered signal; the Mix layer is in the Stats body and
> `MixLayerData.ratedBaselineWeeks` gates the layer.
> **Binding conventions:** `docs/global_conventions.md`. `docs/README.md` entries this plan depends
> on, read before Phase 1: `docs/signals.md`, `docs/training_load.md`,
> `docs/state_management/services_and_utils.md`, `docs/state_management.md`, `docs/stats_screen.md`,
> `docs/constants_reference.md`, `docs/data_models.md`, `docs/documentation_standard.md`,
> `docs/design_system.md`. Budget: `.github/agents/pr_scope_budget.md`.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 558 | 500 | 800 |
| Phases | 3 | >3 | >5 |
| Tracks | 1 (`lib/`, `test/`, `docs/`) | >1 | — |
| Ledger decisions | 18 (D-1201…D-1218) | >20 | — |
| Scenarios | 13 (S-1901…S-1913) | >30 | — |
| Predicted production lines | ~230 | — | ~1,500 |

**Verdict:** one soft signal (plan length), zero hard. The split rule is "split if two or more soft
signals", so this stays one PR. 7b (`2026-10-03-07b-stats-pr7b-interference-plan/`) is the other half.

## What this PR does

One new caution signal: a modality the user regularly trains has fallen to less than half its usual
share of their load over the last 28 days. It needs a period-scoped entry point into the Mix walk
(the existing one is window-scoped and returns a weekly strip), the pure rule and copy, and the one
registry line that puts the card on the layer.

## Out of scope

- Suggesting a modality the user does not regularly train (pack's out-of-scope).
- Targets or "ideal" mixes not derived from the user's own history (pack's out-of-scope).
- Any change to the Mix layer's rendered figures, the Signals framework, the Stats window chips, the
  PR rules, `lib/data/` or `watch/`.
- Cross-Modality Interference — that is 7b.

## Resolved Decisions (Ledger)

**D-1201 — The period.** The signal's recent period is the 28 local calendar days ending with today:
`fromMs = DateTime(now.year, now.month, now.day - (kModalityMixShiftPeriodDays - 1))` (local midnight)
and `toMs = now`. A session is in the period when `startedAtMs >= fromMs && startedAtMs <= toMs`, the
same inclusive test `_sessionInWindow` applies. The period never follows the Stats window chip: a
period-scoped or 14-training-day window does not move it. Built from calendar components, never a
`Duration`, so a DST transition cannot shift a boundary.

**D-1202 — The baseline.** The baseline is `baselineBlockStarts(localMidnightDay(fromMs))`: the
`kTrainingLoadBaselineWeeks` (12) consecutive 7-calendar-day blocks that tile the 84 days immediately
before `localMidnightDay(fromMs)`, oldest first, abutting the period with no gap and no overlap. It
reuses the shared function and constant; the signal defines no second baseline.

**D-1203 — The measure gate.** The signal shows only when the Mix layer would measure the signal's own
period in load: `ratedBaselineWeeks >= kTrainingLoadMinRatedWeeks` (4) and
`unratedTimeSeconds / periodTimeSeconds <= kTrainingLoadMaxUnratedShare` (0.25), both read over the
period and its baseline exactly as `computeMixLayer` reads them. Otherwise the signal abstains. The
framework's own gate (`signalsGateMet(mix)`) is untouched and still reads the Stats window's payload.

**D-1204 — One walk, two entry points.** `StatsProgressService.computeMixPeriod({required DateTime
fromMs, required DateTime toMs})` returns the same `MixLayerData` the window-scoped `computeMixLayer`
returns for the equivalent window, with `weeks: const <MixWeek>[]`. The existing single history walk
serves both entry points. `computeMixLayer` keeps its `startOfWeek` parameter, its weekly strip and
its behaviour, and `SignalContext` gains no member.

**D-1205 — The rule reads the payload's own segments.** `modalityMixShift` takes the period payload's
own `measure`, `segments` and `baselineSegments`. The fire test uses the segments' exact `measure`; the
copy uses their shared rounded `percent`. No second split, no re-derivation of a percentage.

**D-1206 — Regularly trained.** A modality is regularly trained when its baseline share is at least
`kModalityMixShiftMinBaselineShare` (1/10), inclusive: `10 × baselineMeasure >= baselineTotal`. A
modality absent from the baseline bar is not regularly trained.

**D-1207 — Fires.** A regularly trained modality fires when its recent share is strictly less than half
its baseline share: `2 × recentMeasure × baselineTotal < baselineMeasure × recentTotal`. Exactly half
does not fire. The comparison is on exact fractions, never on the two rounded percentages.

**D-1208 — Absent from the recent bar.** When a modality has no recent segment its recent measure is 0
and its recent percent is 0. It can still fire (0 is less than half of anything positive).

**D-1209 — Which modality is reported.** Among the firing modalities, the reported one has the largest
relative drop — the smallest exact `recentShare / baselineShare`, compared as
`recentMeasure × baselineMeasure' × recentTotal' × baselineTotal` cross-multiplication or an equivalent
exact ratio. An exact tie resolves in `ExerciseSection` declaration order: resistance, cardio,
isometric, sports.

**D-1210 — Abstention.** The signal returns null when the period's measure is time, when the baseline
bar is empty, when `recentTotal <= 0`, or when no modality fires.

**D-1211 — Observation, sentence one.**
`'${section.label} is ${recentPercent}% of your load over the last 4 weeks, down from its usual ${baselinePercent}%.'`
— `section` is the reported modality; `recentPercent` and `baselinePercent` are that modality's `percent`
from the period's own `segments` and `baselineSegments`. The sentence always names its span
("over the last 4 weeks"), because the period is fixed and not the window's.

**D-1212 — Observation, sentence two.** Appended as
`' ${largest.label} has grown to ${largestPercent}%.'` only when the largest recent share belongs to a
modality other than the reported one. `largest` is the recent segment with the greatest exact
`measure`, an exact tie resolving in declaration order. When the reported modality is itself the
largest recent share, the second sentence is omitted.

**D-1213 — Suggestion.** `'${article} ${noun} session this week would bring your mix back toward usual.'`
with `noun` = `lifting` (resistance), `cardio` (cardio), `isometric` (isometric), `sports` (sports) and
`article` = `An` for isometric, `A` otherwise. *(Derived from the pack's single example — owner to
confirm; see Open questions.)*

**D-1214 — Kind, priority and the caution order.** Kind caution. Priority
`kModalityMixShiftPriority = 400`: below 7b's Cross-Modality Interference and above every later
caution. The planned order, recorded here because this PR ships only its second entry and
`docs/signals.md` records shipped state only: Interference 500 > Mix Shift 400 > Fuel vs Load 300 >
Protein Consistency 200 > Sustained High Load 100 > Cardio Efficiency Drift 50. The positive stays `kProgressionRatePriority`;
priorities are comparable only within a kind.

**D-1215 — Plug-in only.** The signal is one class implementing `Signal` in
`lib/core/services/signals/modality_mix_shift_signal.dart` plus one line in `buildSignalRegistry()`.
No file in `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart` or
`lib/features/stats/widgets/signals_layer.dart` changes.

**D-1216 — Id and title.** The id is `modality-mix-shift` — the dismissal key, the widget key and the
semantic label. The title is `Modality mix shift` and is never rendered (the layer renders the kind's
label).

**D-1217 — The pure file.** `lib/core/models/modality_mix_shift.dart` holds the constants, the result
type and the copy builder. It imports `lib/core/models/exercise_metric.dart` (for `ExerciseSection`)
and `lib/core/models/training_load.dart` (for `MixMeasure`, `MixSegment`) — no Flutter, no repository,
no clock, no service.

**D-1218 — Dismissal is the framework's.** The signal adds no dismissal rule and no preference key;
the framework's 14-local-day window applies unchanged.

## Feature Invariants

Only the invariants that bite here; project-wide rules stay in `docs/global_conventions.md`.

- **The Mix layer's rendered figures do not change.** The D-1204 extraction is behaviour-preserving:
  same measure, same segments, same percents, same counts, same strip for the window entry point.
  Proven by the existing Mix suites, which are read-only in this PR.
- **A signal never walks history itself.** The signal calls the service; the service rides its cached
  history index. One repository read per screen evaluation.
- **One signal = one class + one registry line.** No framework file names a concrete signal, and this
  signal names no framework file's contents.
- **No new colour, token, widget or `OmniTheme` value.** The card uses the layer's existing caution
  styling.
- **The PR path is untouched.** No PR API is read, no all-time best is compared.

## Requirements

- **R1** A user whose recent mix has shrunk a modality they regularly train sees one caution card under
  the Mix layer.
- **R2** The card names the modality, its recent share, its usual share and the modality that grew.
- **R3** The card never appears for a modality the user does not regularly train.
- **R4** The card never appears while the Mix layer measures time for the same period.
- **R5** The card is dismissible and stays dismissed for the framework's window.
- **R6** No existing Stats figure changes.

## Acceptance Criteria (each maps to ≥1 scenario)

| # | Criterion (from the pack) | Scenarios |
|---|---|---|
| AC-1 | Baseline isometric share 12%, recent share 5% fires, naming Isometric and the modality with the largest recent share | S-1901 |
| AC-2 | Baseline 12%, recent 6% (exactly half) shows no card | S-1902 |
| AC-3 | Baseline 8% (not regularly trained) never fires, even at a 0% recent share | S-1903 |
| AC-4 | In time mode the card does not appear | S-1904 |
| AC-5 | With two modalities qualifying, only the larger relative drop is reported | S-1905 |
| AC-6 | The regularly-trained threshold is exactly 10% | S-1906 |
| AC-7 | The signal uses the same load and baseline figures as the Mix layer (shared source) | S-1907 |
| AC-8 | The fire test is exact-fraction, not rounded-percentage | S-1908 |
| AC-9 | The card renders on the layer, dismisses, and leaves every other block alone | S-1909 |
| AC-10 | Sentence two is omitted when the reported modality is itself the largest recent share | S-1910 |
| AC-11 | An exact ratio tie resolves in declaration order | S-1911 |
| AC-12 | The framework and the PR path are untouched | S-1912 |
| AC-13 | The period's bounds and the abutting baseline blocks are exact | S-1913 |

## Scenarios

Fixtures name every entity class involved. `day(n)` means local midnight `n` days before today; all
times are local. Pure scenarios call `modalityMixShift` directly with hand-built `MixSegment` lists.

### S-1901: the pack's own example fires
- **Fixture:** `measure: MixMeasure.load`. Baseline segments (exact measure, and the percent
  `mixSegments` gives): `{resistance: 88 → 88%, isometric: 12 → 12%}` (total 100). Recent segments:
  `{resistance: 68 → 68%, isometric: 5 → 5%, sports: 27 → 27%}` (total 100).
- **Trigger:** one `modalityMixShift(measure: load, recent: recent, baseline: baseline)` call.
- **Flow:** regularity and fire tests per D-1206/D-1207; report per D-1209; copy per D-1211/D-1212/D-1213.
- **Expected outcome:** fires. Isometric: `10 × 12 = 120 >= 100` (regular), `2 × 5 × 100 = 1000 <
  12 × 100 = 1200` (fires). Resistance: `2 × 68 × 100 = 13600 < 88 × 100 = 8800` false (no fire).
  Sports: absent from the baseline → not regular. Reported: Isometric. Observation
  `'Isometric is 5% of your load over the last 4 weeks, down from its usual 12%. Resistance has grown to 68%.'`
  Suggestion `'An isometric session this week would bring your mix back toward usual.'`
- **Edge case of:** none.

### S-1902: exactly half does not fire
- **Fixture:** baseline `{resistance: 88 → 88%, isometric: 12 → 12%}`; recent `{resistance: 94 → 94%,
  isometric: 6 → 6%}`; `measure: load`.
- **Trigger:** one call.
- **Flow:** D-1207's strict `<`.
- **Expected outcome:** null. `2 × 6 × 100 = 1200 < 12 × 100 = 1200` is false. (A `<=` implementation
  fires here — this is mutation (a) in Phase 1.)
- **Edge case of:** S-1901.

### S-1903: below the regularly-trained floor never fires
- **Fixture:** baseline `{resistance: 92 → 92%, isometric: 8 → 8%}`; recent `{resistance: 100 → 100%}`
  — isometric is absent from the recent bar, so its recent measure is 0 and its percent is 0
  (D-1208); `measure: load`.
- **Trigger:** one call.
- **Flow:** D-1206 first: `10 × 8 = 80 >= 100` is false.
- **Expected outcome:** null, even though `2 × 0 × 100 = 0 < 8 × 100 = 800` would fire on the fire
  test alone.
- **Edge case of:** S-1901.

### S-1904: time mode suppresses the card
- **Fixture (F-TIME):** five rated sessions, each one timed effort, at `day(10)`, `day(17)`, `day(24)`,
  `day(31)`, `day(38)`, each at 09:00, each `endedAtMs` covering the effort so the session carries
  cardio time. The Stats window passed to the screen is period-scoped over the last 14 days
  (`fromMs = day(14)`, `toMs = todayEnd`).
- **Trigger:** (a) `computeMixPeriod` over `[day(27), now]`; (b) the Stats screen with that window.
- **Flow:** the period's baseline blocks are the 12 blocks before `day(27)` → `day(28)…day(111)`, which
  hold rated sessions only at `day(31)` and `day(38)` → `ratedBaselineWeeks = 2 < 4` → D-1203 abstains
  and the period payload reports `measure: time` with `baselineSegments: const []`. The window's own
  baseline is the 12 blocks before `day(14)` → `day(15)…day(98)`, which hold rated sessions at
  `day(17)`, `day(24)`, `day(31)`, `day(38)` → 4 rated blocks, and the window holds the `day(10)`
  session → its payload is non-null with `ratedBaselineWeeks = 4`, so `signalsGateMet` is true and the
  layer renders.
- **Expected outcome:** (a) `measure == MixMeasure.time` and `baselineSegments.isEmpty`; (b) the
  Signals layer renders the quiet line and no card whose key is `signal_card_modality-mix-shift`.
- **Edge case of:** S-1907.

### S-1905: the larger relative drop wins
- **Fixture:** baseline `{resistance: 60 → 60%, cardio: 28 → 28%, isometric: 12 → 12%}`; recent
  `{resistance: 60 → 60%, cardio: 8 → 8%, isometric: 5 → 5%, sports: 27 → 27%}`; `measure: load`.
- **Trigger:** one call.
- **Flow:** D-1209.
- **Expected outcome:** fires, reported Isometric. Isometric `10 × 12 = 120 >= 100` regular and
  `2 × 5 × 100 = 1000 < 1200` fires, ratio `5/12 = 0.4167`. Cardio `10 × 28 = 280 >= 100` regular and
  `2 × 8 × 100 = 1600 < 2800` fires, ratio `8/28 = 0.2857`. Resistance does not fire. Isometric's ratio
  is *larger*, so Cardio is reported: observation `'Cardio is 8% of your load over the last 4 weeks,
  down from its usual 28%. Resistance has grown to 60%.'` — the fixture is deliberately built so the
  naive "biggest absolute drop" reading (Isometric: 12 → 5) picks the wrong modality.
- **Edge case of:** S-1901.

### S-1906: the regularly-trained threshold is exactly 10%
- **Fixture:** baseline `{resistance: 90 → 90%, isometric: 10 → 10%}` (10.0% exactly, inclusive);
  recent `{resistance: 96 → 96%, isometric: 4 → 4%}`; `measure: load`.
- **Trigger:** one call.
- **Flow:** D-1206 inclusive; D-1207.
- **Expected outcome:** fires. `10 × 10 = 100 >= 100` regular; `2 × 4 × 100 = 800 < 10 × 100 = 1000`
  fires. Observation `'Isometric is 4% of your load over the last 4 weeks, down from its usual 10%.
  Resistance has grown to 96%.'` Suggestion `'An isometric session this week would bring your mix back
  toward usual.'` (the pack's own example copy, with the pack's own numbers).
- **Edge case of:** S-1903 (one point below the floor).

### S-1907: the period payload is the Mix layer's own figures (shared source)
- **Fixture (F-MIX):** a mixed history — rated sessions spread across the last 4 months carrying
  resistance, cardio, isometric and sports work, at least 4 rated baseline blocks for the last 28 days,
  and a period (`[day(27), now]`) whose bar has at least two non-zero modalities. Built once and shared
  by S-1907, S-1909 and S-1913.
- **Trigger:** `computeMixPeriod(fromMs: day(27), toMs: now)` and
  `computeMixLayer(window: periodScoped(day(27), todayEnd), now: now, startOfWeek: 'monday')`.
- **Flow:** field-by-field comparison.
- **Expected outcome:** identical `measure`, `segments` (same order, same `section`, same exact
  `measure`, same `percent`), `baselineSegments`, `unratedSessionCount` and `ratedBaselineWeeks`; the
  period call's `weeks` is empty and the window call's `weeks` is not.
- **Edge case of:** none.

### S-1908: the fire test is exact-fraction, not rounded-percentage
- **Fixture:** baseline `{resistance: 894 → 89%, isometric: 106 → 11%}` (total 1000: exact 89.4% and
  10.6% → `mixSegments` floors 89 and 10, one remainder unit to the larger fraction 0.6 → isometric
  11%); recent `{resistance: 947 → 95%, isometric: 53 → 5%}` (exact 94.7% and 5.3% → floors 94 and 5,
  remainder to 0.7 → resistance 95%, isometric 5%); `measure: load`.
- **Trigger:** one call.
- **Flow:** D-1207 on the exact measures.
- **Expected outcome:** null. Exact: `2 × 53 × 1000 = 106000 < 106 × 1000 = 106000` is false. A
  rounded-percent implementation (`2 × 5 = 10 < 11`) fires — this is mutation (b) in Phase 1, and the
  fixture is made of integers so the comparison is exact in binary floating point.
- **Edge case of:** S-1902.

### S-1909: the card on the layer, and its dismissal
- **Fixture:** F-MIX seeded on the repository, the Stats window scoped so the Mix layer renders above
  the Signals layer, and the Signals layer otherwise qualifying for no other card.
- **Trigger:** open the Stats screen; read the layer; then tap the card's dismiss control.
- **Flow:** one evaluation; then the framework's dismissal write.
- **Expected outcome:** the layer shows the caution card with the exact observation and suggestion from
  S-1901's rule applied to F-MIX, the `Worth a look` kind label, the widget key
  `signal_card_modality-mix-shift`, no quiet line; it sits below the Mix layer; the ALL TIME,
  Instruments and Fuel blocks are unchanged. After one tap the card is gone in the next frame, the
  quiet line appears, and the dismissal store holds `modality-mix-shift` with an integer timestamp;
  a fresh screen build keeps it hidden.
- **Edge case of:** none. **Mock only for the tap** — a Hive write inside `FakeAsync` never drains.

### S-1910: the second sentence is omitted when the reported modality is the largest
- **Fixture:** baseline `{cardio: 60 → 60%, resistance: 30 → 30%, isometric: 10 → 10%}`; recent
  `{cardio: 20, resistance: 18, isometric: 8}` (total 46: exact 43.4783%, 39.1304%, 17.3913% → floors
  43, 39, 17 = 99, remainder to 0.4783 → cardio **44%**, resistance 39%, isometric 17%); `measure:
  load`.
- **Trigger:** one call.
- **Flow:** D-1207 then D-1212.
- **Expected outcome:** fires, reported Cardio (the only firing modality: resistance `2 × 18 × 100 =
  3600 < 30 × 100 = 3000` false; isometric `2 × 8 × 100 = 1600 < 10 × 100 = 1000` false). Cardio is
  also the largest recent share (20 of 46), so sentence two is omitted and the observation is exactly
  `'Cardio is 44% of your load over the last 4 weeks, down from its usual 60%.'` — note 44, not 43:
  the copy reads the shared rounded percent.
- **Edge case of:** S-1901.

### S-1911: an exact ratio tie resolves in declaration order
- **Fixture:** baseline `{resistance: 60 → 60%, cardio: 20 → 20%, isometric: 20 → 20%}`; recent
  `{resistance: 40, cardio: 4, isometric: 4}` (total 48: exact 83.3333%, 8.3333%, 8.3333% → floors 83,
  8, 8 = 99, remainder to the largest exact measure 83.3333 → resistance **84%**, cardio 8%,
  isometric 8%); `measure: load`.
- **Trigger:** one call.
- **Flow:** D-1209's tie rule.
- **Expected outcome:** fires, reported Cardio. Cardio and Isometric both fire with the identical ratio
  `4 × 100 / (20 × 48) = 400/960`; resistance does not fire (`2 × 40 × 100 = 8000 < 6000` false).
  `ExerciseSection` order is resistance, cardio, isometric, sports, so Cardio precedes Isometric.
  Observation `'Cardio is 8% of your load over the last 4 weeks, down from its usual 20%. Resistance
  has grown to 84%.'`
- **Edge case of:** S-1905.

### S-1912: the framework and the PR path are untouched
- **Fixture:** the repository at the Phase 2 tip.
- **Trigger:** `git diff --name-only` against the PR base, and the full suite.
- **Flow:** the residue sweep in Phase 3.
- **Expected outcome:** `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart`,
  `lib/features/stats/widgets/signals_layer.dart`, `lib/features/stats/widgets/signals/*`,
  `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` show no diff;
  `test/signals_framework_test.dart`, `test/signals_service_test.dart`,
  `test/signals_layer_screen_test.dart`, `test/in_session_pr_toast_test.dart` and
  `test/pr_toast_test.dart` pass unmodified.
- **Edge case of:** none.

### S-1913: the period's bounds and the abutting baseline
- **Fixture:** F-MIX plus three extra sessions: one starting exactly at `day(27)` 00:00 (the period's
  first instant), one starting at `day(27) 00:00 − 1 ms`, and one at `day(28) 00:00`.
- **Trigger:** `computeMixPeriod(fromMs: day(27), toMs: now)`.
- **Flow:** D-1201's inclusive lower bound; D-1202's block tiling.
- **Expected outcome:** the `day(27) 00:00` session is in the period; the `− 1 ms` session is not, and
  it falls in the last baseline block; the `day(28) 00:00` session is in the first baseline block (the
  baseline abuts the period's start day with no gap and no overlap).
- **Edge case of:** S-1907.

## Iteration 1

### Executor block (applies to every phase in this plan)

- **Branch:** work on `develop`. Never create a branch, never commit — the owner commits.
- **Shell:** every command goes through the gateway, spelled in full:
  `.github/copilot/scripts/macos/gateway.sh <list|lint|test [paths]|format <paths>|pub-get|build|codegen|git-status|git-diff|git-log|git-show>`.
  The bare form is denied. No `git`, `grep`, `sed`, `awk` or `wc` in a shell — use the gateway's
  `git-*` verbs and your file tools. A denied command is never retried.
- **Red first:** every phase writes its tests before the code they test, runs them, and records the
  failing output in `<this plan>.evidence.md`. A test that has never failed proves nothing.
- **Mutations:** at least two inverse edits per plan, on files that already exist at that point. Apply
  one, run the named test, record the failure, restore the file, re-run to confirm green, and *never
  end a step with a mutation applied*.
- **Step budget:** at most 8–10 steps per run. Read at most ~100 lines of a large file at a time —
  `lib/core/services/stats_progress_service.dart` is 2,247 lines; find a region by searching for its
  symbol, then read that region.
- **Evidence:** baselines, suite summaries, red→green tables and the mutation pairs go to
  `docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.evidence.md`.
  Never into this plan. Findings go to `...review.md`.
- **Ambiguity:** never stop. Pick the option most consistent with the Ledger and the Feature
  Invariants, log it in the Assumption Log (decision, options considered, rationale) and continue.
- **Docs trail code by zero phases:** each phase updates the docs it invalidated.
- **Baseline for this plan (measured on `develop`):** `flutter analyze` → `196 issues found.` with 0
  errors; `flutter test` → `+3548 ~1: All tests passed!`.

### Phase 1: the pure rule, the copy and the shared period (@dba)

1. [x] Write `test/modality_mix_shift_test.dart` (plain `test()`, no widget, no repository): S-1901,
   S-1902, S-1903, S-1905, S-1906, S-1908, S-1910, S-1911, plus the abstention cases (empty baseline;
   `recentTotal == 0`; a modality absent from the recent bar reads 0% and fires) and the empty-baseline
   percent rule. Run it and record the failure.
2. [x] Create `lib/core/models/modality_mix_shift.dart` (D-1205…D-1213, D-1217): the three constants
   `kModalityMixShiftPeriodDays = 28`, `kModalityMixShiftMinBaselineShare = 0.10`,
   `kModalityMixShiftPriority = 400`; the result type carrying the reported section, its recent and
   baseline percents, and the optional grown section and percent; the rule; the copy builder and the
   article/noun helper. Exact integer cross-multiplication in the two tests, no rounding, no Flutter.
3. [x] Re-run step 1's suite to green.
4. [x] Write `test/modality_mix_period_service_test.dart` (plain `test()`) against
   `test/helpers/repository_harness.dart` on both factories: S-1907 (field-by-field equality with
   `computeMixLayer` for the equivalent window, `weeks` empty for the period call), S-1904(a) (F-TIME
   reports time), S-1913 (the bounds and the abutting blocks). Run it and record the failure.
5. [x] Add `computeMixPeriod({required DateTime fromMs, required DateTime toMs})` to
   `lib/core/services/stats_progress_service.dart` (D-1204). Find `computeMixLayer` by searching for
   `Future<MixLayerData?> computeMixLayer`, read that region, and lift its walk into a private helper
   that takes the window bounds; `computeMixLayer` keeps its `startOfWeek` strip, its null-on-no-time
   rule and its counts. Nothing else in the file changes.
6. [x] Re-run steps 1, 4 and the Mix suites to green:
   `flutter test test/mix_layer_service_test.dart test/mix_layer_screen_test.dart`.
7. [x] Mutations, one at a time, each restored: **(a)** D-1207's `<` → `<=` — S-1902 must fail;
   **(b)** read the rounded `percent` instead of the exact `measure` in the fire test — S-1908 must
   fail. Record both red→green pairs in the evidence file.
8. [x] Docs: add the `modality_mix_shift` constant group to `docs/constants_reference.md` (names and
   values only, no restatement of the rule); add `computeMixPeriod` to
   `docs/state_management/services_and_utils.md`'s `StatsProgressService` entry; add the period entry
   point to `docs/training_load.md`'s entry-point section; write the caution order from D-1214 into
   `docs/signals.md`. Every behaviour sentence names its test.

**Done Criteria** (run until green):
`flutter analyze` (expect `196 issues found.`, 0 errors);
`flutter test test/modality_mix_shift_test.dart test/modality_mix_period_service_test.dart`;
`flutter test test/mix_layer_service_test.dart test/mix_layer_screen_test.dart`;
full `flutter test` with its summary line pasted into the evidence file.

**Predicted Files:** `lib/core/models/modality_mix_shift.dart` (NEW);
`lib/core/services/stats_progress_service.dart` (EDIT — the walk extraction and the new method, nothing
else); `test/modality_mix_shift_test.dart` (NEW); `test/modality_mix_period_service_test.dart` (NEW);
`docs/constants_reference.md`, `docs/state_management/services_and_utils.md`, `docs/training_load.md`,
`docs/signals.md` (EDIT).

**Phase 1 verification notes (Conductor, date):** _(added at verification)_

### Phase 2: the signal, the registry line and the card (@developer)

1. [x] Write `test/modality_mix_shift_signal_screen_test.dart` first, asserting the exact strings,
   label, key, position and dismissal of S-1909, and S-1904(b) (the quiet line, no Mix Shift card).
   Run it and record the failure (the card is absent — the registry has no such signal yet).
2. [x] Create `lib/core/services/signals/modality_mix_shift_signal.dart` (D-1201, D-1203, D-1215,
   D-1216, D-1218): id `modality-mix-shift`, kind caution, priority `kModalityMixShiftPriority`;
   `evaluate` derives the period from `context.now`, asks `context.progressService.computeMixPeriod`,
   hands the payload's own `measure`, `segments` and `baselineSegments` to the rule, and returns the
   card or null. It reads no repository and walks no history.
3. [x] Add one line to `buildSignalRegistry()`: `const <Signal>[ProgressionRateSignal(),
   ModalityMixShiftSignal()]`. Nothing else in the framework changes.
4. [x] Re-run the new suite to green, then the Stats surface and the framework suites:
   `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/mix_layer_screen_test.dart test/progression_rate_signal_screen_test.dart test/screen_widget_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart`.
   A failure in `test/mix_layer_screen_test.dart` or `test/progression_rate_signal_screen_test.dart` is
   a surface-height re-stabilisation; a failure anywhere else is a real finding.
5. [x] Confirm the PR path is untouched:
   `flutter test test/in_session_pr_toast_test.dart test/pr_toast_test.dart` — with no edit to those
   files.
6. [x] Mutation: change the signal's `toMs` from `context.now` to the window's end and run S-1907's
   period assertions plus S-1904(b) — the period would follow the window chip and both must fail.
   Restore and re-run.
7. [x] Docs: add Modality Mix Shift to `docs/stats_screen.md`'s Signals section as the second
   registered signal, pointing at `docs/signals.md`; add its paragraph to `docs/signals.md`'s
   registered-signals section — the period, the baseline, the measure gate, the two thresholds, the
   two sentences and the suggestion — with every behaviour sentence naming a test.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/modality_mix_shift_signal_screen_test.dart test/signals_layer_screen_test.dart test/mix_layer_screen_test.dart test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart test/palette_legibility_contract_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/signals/modality_mix_shift_signal.dart` (NEW);
`lib/core/services/signals/signal_registry.dart` (EDIT — one line);
`test/modality_mix_shift_signal_screen_test.dart` (NEW); `docs/signals.md`, `docs/stats_screen.md`
(EDIT); `test/mix_layer_screen_test.dart` and/or `test/progression_rate_signal_screen_test.dart`
(EDIT — surface heights only, and only if step 4 needs it).

**Phase 2 verification notes (Conductor, date):** _(added at verification)_

### Phase 3: guards, residue sweep and the close (@developer)

1. [x] Structural guards, each a permanent test: (a) the fire test is exact-fraction — S-1908's integer
   fixture, with a comment naming the rounded-percent reading it rules out; (b) the signal reads the
   period payload's own segments and re-derives no percentage — a value-equality test against the
   payload's `segments`/`baselineSegments`; (c) the signal walks no history — it calls only
   `computeMixPeriod`; (d) the framework files are unchanged (S-1912).
2. [x] Residue sweep: search `lib/`, `test/` and `docs/` for every name this PR introduces —
   `ModalityMixShiftSignal`, `modality-mix-shift`, `computeMixPeriod`, `modalityMixShift`,
   `ModalityMixShift`, `kModalityMixShiftPeriodDays`, `kModalityMixShiftMinBaselineShare`,
   `kModalityMixShiftPriority`, and the observation's opening words. List every hit's file in the
   evidence file; confirm the framework files and `watch/` are absent.
3. [x] Confirm the untouched files show no diff: 6a's three framework source files, `watch/`, and
   `test/in_session_pr_toast_test.dart` / `test/pr_toast_test.dart`.
4. [x] Full `flutter test`; paste the summary line and compare it with Phase 1's, explaining every
   delta in the evidence file.
5. [x] Re-read `docs/signals.md`'s Mix Shift paragraph and `docs/stats_screen.md`'s Signals section
   against the shipped code and correct any claim that no longer matches. Confirm the shipped copy and
   the documented copy match character for character, that both files are under the 64 KiB ceiling, and
   that every behaviour sentence names a test.
6. [x] Close the Progress table and the Assumption Log; fill the evidence file's final table.

**Done Criteria** (run until green):
`flutter analyze`;
`flutter test test/modality_mix_shift_test.dart test/modality_mix_period_service_test.dart test/modality_mix_shift_signal_screen_test.dart test/signals_framework_test.dart test/docs_indexing_contract_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `test/modality_mix_shift_test.dart`, `test/modality_mix_period_service_test.dart`,
`test/modality_mix_shift_signal_screen_test.dart` (EDIT — the guards);
`docs/plans/2026-10-03-07a-stats-pr7a-mix-shift-plan/2026-10-03-07a-stats-pr7a-mix-shift-plan.evidence.md`
(EDIT); `docs/signals.md` and/or `docs/stats_screen.md` (EDIT — only if step 5 finds drift).

**Phase 3 verification notes (Conductor, date):** _(added at verification)_

## Governor actions

- **@dba owns Phase 1.** The pure model, the copy and the service method. Nothing in `lib/features/`.
- **@developer owns Phases 2–3.** The signal, the registry line, the card's tests and the guards.
- If Phase 1's extraction changes any existing Mix test's expected value, stop: D-1204 is a
  behaviour-preserving extraction, so a changed expectation is a defect in the extraction, not a
  test to update.
- If Phase 2 needs a `SignalContext` member or a framework file edit, stop: D-1215 says the seam is
  wrong.
- The owner commits. No agent commits, branches or pushes.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/modality_mix_shift.dart` | NEW — constants, result type, rule, copy |
| `lib/core/services/stats_progress_service.dart` | EDIT — `computeMixPeriod`, the shared walk |
| `lib/core/services/signals/modality_mix_shift_signal.dart` | NEW — the signal |
| `lib/core/services/signals/signal_registry.dart` | EDIT — one registry line |
| `test/modality_mix_shift_test.dart` | NEW — the pure rule, the copy, the guards |
| `test/modality_mix_period_service_test.dart` | NEW — the shared source and the period bounds |
| `test/modality_mix_shift_signal_screen_test.dart` | NEW — the card and the dismissal |
| `test/mix_layer_screen_test.dart`, `test/progression_rate_signal_screen_test.dart` | EDIT — surface heights only, if needed |
| `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/training_load.md`, `docs/state_management/services_and_utils.md` | EDIT — the new rule, entry point and constants |

Nothing in `lib/data/`, `scripts/`, `watch/` or `lib/features/` outside the Stats screen's existing
Signals layer.

## Notes

- **Dependency graph:** Phase 1 → Phase 2 → Phase 3, strictly. Phase 2's signal cannot compile before
  Phase 1's rule and service method exist. Phase 3's guards need both. There is no useful reordering.
- **Predicted intermediate states:** after Phase 1 the repository has a rule, a copy builder and a
  service method that nothing calls; the Stats screen is unchanged and the full suite is green. After
  Phase 2 the card can appear; the only pre-existing suites that may need a height adjustment are the
  two screen suites named in Phase 2 step 4.
- **Legacy handling:** none. No field, schema or stored value changes; a dismissal rides the existing
  preference API, which both repository implementations already implement.
- **Fixture reuse:** F-MIX is built once in Phase 1's service test file and reused by S-1907, S-1913
  and (rebuilt on the Mock harness) S-1909. F-TIME is Phase 1's, reused by S-1904(b) in Phase 2.

## Open questions

| # | Item | Owner | Status |
|---|---|---|---|
| O-1 | D-1213's modality nouns (`lifting`/`cardio`/`isometric`/`sports`) and the suggestion wording | Owner | **Answered 2026-10-03: owner kept the shipped wording** |
| O-2 | D-1212's "statement vs option" tone — the second sentence is a statement, the suggestion is an option | Owner | **Answered 2026-10-03: owner kept the shipped wording** |
| O-3 | D-1214's caution order for items 12–15 (300/200/100/50) | Owner | Defaulted — **owner to confirm**; 7b's Interference is 500 and this PR's Mix Shift is 400 |
| O-4 | Which PR writes the caution order into `docs/signals.md` | Planner | Decided here — this PR creates the order's second entry |
| O-5 | Step 7(b)'s mutation produced no red: the rounded `percent` and the exact `measure` agree on every fixture in `test/modality_mix_shift_test.dart`, so no assertion separates them. A fixture whose exact share and floored share straddle the half-share boundary is the missing coverage. | Owner | **Closed in Phase 3** — the guard `D-1207 the half-share test compares exact fractions, not the two rounded percentages` adds that fixture (exact 5.3% / floored 5% against a baseline of 10.6% / 11%) and fails under the rounded-percent mutation |

## Progress

| Item | Status | Evidence |
|---|---|---|
| Plan lines re-measured | done | 598 lines (was 577 after Phase 2; the delta is Phase 3's ticks and the A-8 entry) — under the 800 hard ceiling |
| Phase 1 | Complete | `test/modality_mix_shift_test.dart` +13; `test/modality_mix_period_service_test.dart` +6; Mix suites +96; two mutation pairs in the evidence file |
| Phase 2 | Complete | `test/modality_mix_shift_signal_screen_test.dart` +7 (Mock 4, Hive 3); framework + surface suites +432; PR path +41; one mutation pair in the evidence file; `flutter analyze` 196 issues; full suite `+3574 ~1: All tests passed!` |
| Phase 3 | Complete | guards +8 (rule +5, screen +3); two mutation pairs in the evidence file; residue sweep clean; framework/`watch/`/PR-path no diff; `flutter analyze` 196 issues; full suite `+3582 ~1: All tests passed!` |

## Assumption Log

_Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED (promoted to a D-x) or REVERT (remediation)._

- **A-1 (Phase 1, step 1) — S-1910's fixture was arithmetically impossible.** The scenario asks for a
  reported modality that is *not* the largest recent one, but its baseline (60/30/10) put the reported
  modality's half-share at 30% while the recent bar gave it 44%. Options: keep the fixture and drop the
  assertion, or re-baseline the fixture. Chose a baseline of 88/10/2 with the observation reading
  "usual 88%", which keeps the scenario's intent (a reported modality that is not the largest) and
  makes the arithmetic satisfiable. No rule changed.
- **A-2 (Phase 1, step 1) — S-1911's tie was broken by floating-point noise.** The scenario wants an
  exact ratio tie resolved in declaration order, but `mixSegments`' largest-remainder pass on doubles
  gave the leftover point to cardio (9/83) rather than resistance (8/84). Options: assert the
  declaration-order winner and accept a flaky tie, or move the fixture off the tie. Chose recent
  resistance 40 → 42, which makes the tie exact in the integers the rule compares. The rule's
  tie-break is unchanged and still covered.
- **A-3 (Phase 1, step 5) — the walk helper is an instance method, not `static`.** `_mixPayload` calls
  `_measuredSecsFor` and `_dominantSectionFor`, which are instance members; `static` produced
  `instance_member_access_from_static`. Chose an instance method. No interface change.
- **A-4 (Phase 1, step 5) — `_sessionInWindow` now takes explicit bounds.** The period call has no
  `StatsWindow`, so the predicate takes `fromMs`/`toMs`; its one other caller passes
  `window.fromMs, window.toMs`. Behaviour is unchanged and the Mix suites stay green.
- **A-5 (Phase 2, step 6) — the plan's named mutation is undetectable; the equivalent one was used.**
  The plan names `toMs` = the window's end. The window's `toMs` is today's end-of-day
  (`23:59:59.999`), which is *after* `context.now`, so that edit only widens the period and no
  fixture can separate the two. Options: keep the named edit and record a green run, or apply the
  same defect in its detectable form. Chose `fromMs` = the window's start, which is the same
  "period follows the chip" defect and does go red. No rule changed.
- **A-6 (Phase 2, step 6) — F-MIX's window was re-scoped from 10 days to 3.** The mutation above is
  only detectable when the window is narrower than the signal's own 28-day period, so the fixture's
  period-scoped window moved to `day(3)` and its isometric session to `day(2)`. The fixture still
  meets the gate, still reads load, and still fires; the change is fixture geometry, not a rule.
- **A-7 (Phase 2, step 1) — a dedicated guard was added for D-1201.** The plan's step 6 asks for the
  mutation to be caught by S-1907's period assertions and S-1904(b). S-1904(b) asserts an absence, so
  it cannot catch it, and S-1907 is a service-level test the signal does not touch. Added
  `S-1909 the period does not follow the window chip` to the screen suite, which is the assertion
  that actually fails under the mutation.
- **A-8 (Phase 3, step 5) — the docs pointed at a test that did not exist.** `docs/constants_reference.md`
  and `docs/signals.md` both cited `test/modality_mix_shift_test.dart` ("the constant contracts"), but
  Phase 1 never added such a test. Options: delete the pointer from the docs, or add the test. Chose to
  add it — the three constants are a rule, and a doc pointer to a non-existent test is worse than no
  pointer. No doc prose changed.

## Feedback

[empty — the Conductor folds non-empty entries into a new Iteration block and clears this one]
