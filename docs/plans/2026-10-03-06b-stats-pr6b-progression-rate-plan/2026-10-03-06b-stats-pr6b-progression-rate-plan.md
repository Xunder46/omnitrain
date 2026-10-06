# Feature: Stats PR 6b — Progression Rate (the first signal)

> **Status:** DONE
> **Next handoff:** @dba (Phase 1)
> **Series:** `docs/plans/2026-10-03-06-stats-pr6-index.md` — 6b of 6a+6b. Phase 1 may be written against 6a's interface before 6a lands, but no phase of this plan may be merged before 6a's Phase 3 is green.
> **Provenance:** owner decisions of 2026-10-03, `.work/stats-pr6/brief-plan.md`.
> **Depends on:** `docs/plans/2026-10-03-06a-stats-pr6a-signals-framework-plan/2026-10-03-06a-stats-pr6a-signals-framework-plan.md` — every framework rule lives there and is not restated here.
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 9 (Progression Rate).
> **Evidence:** `2026-10-03-06b-stats-pr6b-progression-rate-plan.evidence.md` (same folder). Review findings: `.review.md`. Neither is written into this file.
> **Binding conventions:** `docs/global_conventions.md`, plus `docs/signals.md` (6a), `docs/stats_screen.md`, `docs/constants_reference.md`, `docs/data_models.md`, `docs/state_management/services_and_utils.md`.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 536 | 500 | 800 |
| Phases | 3 | >3 | >5 |
| Tracks | 1 | >1 | — |
| Ledger decisions | 13 | >20 | — |
| Scenarios | 14 | >30 | — |
| Predicted production lines | ~270 | — | ~1,500 |

Under every hard limit. One soft signal — plan length (536 against 500) — and the rule is "split if
two or more soft signals", so no further split.

## What this PR does

Ships the first real signal: for every Resistance exercise performed in a session, the session's
best on the exercise's native metric is compared with the same exercise's previous session; the rate
over the last 28 days is compared with the 28 days before it, and a card appears only when the
recent rate is high, improving and built on enough data. It adds one signal, one service walk, one
pure math file and one registry line — no framework change.

## Out of scope

- A falling-rate or negative variant of the card (the pack's own out-of-scope list).
- Comparison against planned targets.
- Any change to personal record rules: `lib/core/services/`'s PR path, the in-session PR toast and
  the PR toast are untouched, and `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart`
  must pass without modification.
- Any new signal (items 10–15 of the pack are later PRs).
- Any change to the framework's selection, gating, dismissal or rendering rules.
- Any new chart, colour or theme token.

## Decision Ledger

**D-1101 — The unit is the exercise-session, valued by the existing native-metric rule.** For each
completed session and each exercise with at least one `set` effort in that session, the session's
value is the exercise's native metric read over that session's set efforts alone — estimated 1RM on
the weight axis and best reps on the reps axis — through the same helper the Instruments rows and the
progress series already use (`StatsProgressService`'s `_resistanceValue`, with `_repsAxisExercises`
and its bodyweight test deciding the axis). No second value rule and no second axis classification is
written. `epley1RM` stays the single definition of estimated 1RM.

**D-1102 — Only completed sessions count.** A session counts when its end timestamp is set — the rule
the rest of the service already applies. A closed rolling session's sets count; an open rolling
session's do not.

**D-1103 — A set logged anywhere counts.** The session's modality is irrelevant: the comparison reads
set efforts, so a set logged inside a cardio session, and a set in a session with no modality, are
both Resistance exercise-sessions. The signal does not filter by modality.

**D-1104 — A session with no readable value is not counted.** When the exercise's native value for a
session falls back to the axis's zero value (no readable row), that session enters neither the
numerator nor the denominator. The zero value exists so callers can use one strict comparison; it is
not a performance, and counting it would let an empty row lower a user's rate.

**D-1105 — The comparison is against the exercise's own previous session.** Samples are ordered by
session start; for each exercise the first-ever counted session is dropped from both the numerator
and the denominator; every later session is a progression when its value is greater than or equal to
its predecessor's, including an exact tie. A comparison is attributed to the window of the **later**
session, so a window's first sample compares against a predecessor that may sit outside the window —
which is why the sample list is built over the whole history, not over the two windows.

**D-1106 — The two windows are 28 exact days each.** The recent window is the 28 days ending at
`now`: a session is in it when its start is at or after `now − 28 days` and at or before `now`. The
prior window is the 28 days before that: `now − 56 days` at or before the start, and the start before
`now − 28 days`. Both boundaries are exact instants derived from the load's `now`, never calendar
days. The windows are fixed relative to `now` and do not follow the screen's selected `StatsWindow`
— the card states its own span in its copy.

**D-1107 — The rates are exact fractions; only the display is rounded.** The recent rate is
`recentProgressions / recentCounted` and the prior rate is `priorProgressions / priorCounted`; a rate
with zero counted sessions is 0. The percentages the card shows are whole numbers:
`(rate * 100).round()`.

**D-1108 — All three conditions, on the exact fractions, inclusive.** The card appears only when the
recent counted exercise-sessions are at least `kProgressionRateMinCounted`, the prior counted
exercise-sessions are at least `kProgressionRateMinCounted`, the recent rate is at least
`kProgressionRateMinRate`, and the recent rate exceeds the prior rate by at least
`kProgressionRateMinImprovement`. Every comparison is inclusive and every comparison uses the exact
fractions, never the rounded percentages. A period with fewer than `kProgressionRateMinCounted`
counted exercise-sessions never shows the card, whatever the rates.

**D-1109 — The copy, verbatim, with the user's numbers.** The observation is
`Resistance progression rate is <recent>% over the last 4 weeks, up from <prior>%.`, where `<recent>`
and `<prior>` are the whole-number percentages of D-1107. The suggestion is exactly
`The current approach is working.` The card's `title` is `Progression rate`, which names it for its
key, its accessibility label and the dismissal store; it is not rendered (D-1001).

**D-1110 — Kind and priority.** The signal's kind is positive and its priority is
`kProgressionRatePriority`, the highest among positives, as the pack requires.

**D-1111 — The progression measure does not share rules with the PR measure.** This signal compares a
session with the exercise's previous session; a personal record compares strictly against the
all-time best. A tie therefore counts as a progression here and is not a personal record there. The
signal calls no PR API, and the PR path's behaviour is unchanged.

**D-1112 — The service walk is one public method over the cached history.** `StatsProgressService`
gains one public method returning every `ProgressionSample` (`exerciseId`, `sessionStartMs`, `value`)
for the completed history, ordered by exercise then session start, built from the same cached history
index the other computations use so a load adds no second repository read. The pure math lives in
`lib/core/models/progression_rate.dart`: `ProgressionSample`, `ProgressionRate`, the rate
computation, the qualification test and the copy builder — pure Dart, no clock, no repository, no
Flutter.

**D-1113 — The card is relative to `now`, not to the screen's selected window.** Selecting a training
period on the Stats screen does not change, hide or rescale the card; it always describes the last
28 days against the 28 before them, and its copy says so.

## Feature invariants

- **No second native-value rule.** D-1101: the same helper, the same axis classification, the same
  estimated 1RM definition as the rest of the Stats service.
- **No second read of history.** The walk rides the existing cached index (D-1112, 6a's D-1014).
- **The framework is untouched.** This PR changes no selection, gating, dismissal or rendering rule;
  the diff into `lib/core/models/signals.dart`, `lib/core/services/signals_service.dart` and
  `lib/features/stats/widgets/signals_layer.dart` is empty.
- **The PR path is untouched.** `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart`
  pass unmodified; a tie counts as a progression and is not a PR (D-1111).
- **`docs/session_summary.md` is not touched.**

## Requirements

1. A pure, clock-free home for the sample, the two windows, the rates, the thresholds and the copy.
2. One public `StatsProgressService` method returning the whole history's samples, reusing the
   existing value rule.
3. One `Signal` implementation, registered by one line.
4. Tests for the pack's seven acceptance criteria, the three exact boundaries, the axis
   classification, the tie-not-a-PR guard and the first-ever exclusion.
5. Docs: the registered signal's definition, thresholds and copy, and the new constants and models.

## Acceptance Criteria → scenarios

| # | Acceptance criterion | Scenarios |
|---|---|---|
| AC-1 | 20 counted exercise-sessions per period, 80% recent and 65% prior, shows the card reading `80%` and `65%` | S-1801 |
| AC-2 | 80% and 75% — a 5-point improvement — shows no card | S-1802 |
| AC-3 | A 70% recent rate with a 20-point improvement shows no card | S-1803 |
| AC-4 | 7 counted exercise-sessions in either period shows no card, whatever the rates | S-1804 |
| AC-5 | An exact tie with the previous session counts as a progression | S-1806 |
| AC-6 | A bodyweight exercise is compared by reps and a weighted exercise by estimated 1RM, following the existing classification | S-1807 |
| AC-7 | An exercise's first-ever session is excluded from numerator and denominator | S-1808 |
| AC-8 | Exactly 75%, exactly +10 points and exactly 8 counted exercise-sessions all show the card | S-1805 |
| AC-9 | The comparison is independent of the PR comparison | S-1806, S-1814 |
| AC-10 | Every card states its span, is dismissible, and disappears when its condition clears | S-1811, S-1812, S-1813 |

## Scenarios

**The main fixture (F-PR).** Nine completed sessions at `daysAgo` 61, 54, 47, 40, 33, 26, 19, 12 and
5, each carrying all five exercises `ex-a`…`ex-e` as `set` efforts with one rep per set, so the
estimated 1RM is monotone in the weight. Weights per exercise, in that session order:

| Exercise | 61 | 54 | 47 | 40 | 33 | 26 | 19 | 12 | 5 |
|---|---|---|---|---|---|---|---|---|---|
| ex-a | 100 | 110 | 120 | 130 | 140 | 150 | 160 | 170 | 180 |
| ex-b | 200 | 210 | 220 | 215 | 230 | 240 | 250 | 245 | 260 |
| ex-c | 300 | 310 | 305 | 320 | 330 | 340 | 335 | 350 | 360 |
| ex-d | 400 | 410 | 405 | 420 | 415 | 430 | 425 | 440 | 450 |
| ex-e | 500 | 510 | 505 | 500 | 495 | 520 | 515 | 530 | 540 |

Hand-computed outcome: the 61-day session is each exercise's first-ever and is dropped; the prior
window holds the 54/47/40/33 sessions and the recent window the 26/19/12/5 sessions, giving 20
counted exercise-sessions per period. Progressions per exercise: ex-a 4/4 and 4/4, ex-b 3/4 and 3/4,
ex-c 3/4 and 3/4, ex-d 2/4 and 3/4, ex-e 1/4 and 3/4. Prior 13/20 = 65%, recent 16/20 = 80% — a
15-point improvement on 20 counted sessions per period, so the card shows, reading `80%` and `65%`.
No session sits on a window boundary, so the fixture is insensitive to the moment `now` is read.
The fixture also needs the rated baseline 6a's gate requires; the same sessions carry a
`sessionFeeling` on enough sessions to meet it.

**Boundary fixtures are synthesised sample lists**, not repositories: a pure list of
`(exerciseId, sessionStartMs, value)` triples passed straight to the math, so a boundary can be hit
exactly. A "counted" sample is one that survives D-1104's zero rule and D-1105's first-ever rule.

### S-1801: The card, end to end
- **Fixture:** F-PR, with 6a's gate met.
- **Trigger:** open the Stats screen.
- **Flow:** one load.
- **Expected outcome:** one card in the layer's top slot, kind label `Positive`, observation exactly
  `Resistance progression rate is 80% over the last 4 weeks, up from 65%.`, suggestion exactly
  `The current approach is working.`; the quiet line is absent; the card's key is
  `signal_card_progression-rate`.
- **Edge case of:** none.

### S-1802: A 5-point improvement shows nothing
- **Fixture:** synthesised samples giving 80% recent and 75% prior on 20 counted per period.
- **Trigger:** evaluate.
- **Flow:** one evaluation.
- **Expected outcome:** no card.
- **Edge case of:** S-1801.

### S-1803: A high improvement on a low rate shows nothing
- **Fixture:** synthesised samples giving 70% recent and 50% prior on 20 counted per period.
- **Trigger:** evaluate.
- **Flow:** one evaluation.
- **Expected outcome:** no card — the recent rate is below `kProgressionRateMinRate` although the
  improvement is 20 points.
- **Edge case of:** S-1801.

### S-1804: Too little data shows nothing
- **Fixture:** two synthesised fixtures: one with 7 counted exercise-sessions in the recent period
  and 20 in the prior, one with 20 and 7; both with rates far above every threshold.
- **Trigger:** evaluate.
- **Flow:** two evaluations.
- **Expected outcome:** no card in either case.
- **Edge case of:** S-1801.

### S-1805: Every boundary is inclusive
- **Fixture:** three synthesised fixtures: 15/20 recent against 13/20 prior (exactly 75% and exactly
  a 10-point improvement); 16/20 against 14/20 (exactly +10 points); and 8 counted exercise-sessions
  in each period with rates above the thresholds (exactly `kProgressionRateMinCounted`).
- **Trigger:** evaluate each.
- **Flow:** three evaluations.
- **Expected outcome:** a card in all three; the first reads `75%` and `65%`.
- **Edge case of:** S-1801.

### S-1806: A tie is a progression, and is not a PR
- **Fixture:** a synthesised fixture whose recent window contains an exact tie with the previous
  session, and a repository fixture in which the same exercise's session ties its all-time best.
- **Trigger:** evaluate the signal; then read the PR path's result for the same fixture.
- **Flow:** one evaluation and one read.
- **Expected outcome:** the tie counts in the numerator and the denominator; the PR path reports no
  personal record for the tied session; `test/in_session_pr_toast_test.dart` and
  `test/pr_toast_test.dart` pass unmodified.
- **Edge case of:** none.

### S-1807: The axis follows the existing classification
- **Fixture:** one exercise logged with bodyweight sets only (reps above zero, no added weight) and
  one logged with added weight, both performed across the nine sessions, the bodyweight exercise
  improving in reps while its estimated 1RM would read zero, and the weighted exercise improving in
  weight while its reps stay at one.
- **Trigger:** evaluate.
- **Flow:** one evaluation.
- **Expected outcome:** the bodyweight exercise's progressions follow its reps; the weighted
  exercise's follow its estimated 1RM; neither exercise's samples use the other axis.
- **Edge case of:** S-1801.

### S-1808: The first-ever session is excluded
- **Fixture:** an exercise performed in exactly two sessions, the first at `daysAgo` 20 with a heavier
  weight and the second at `daysAgo` 5 with a lighter one; and the F-PR fixture, whose 61-day session
  is every exercise's first.
- **Trigger:** evaluate.
- **Flow:** two evaluations.
- **Expected outcome:** the two-session exercise contributes one counted exercise-session — the
  second, which is not a progression — and never contributes a comparison for its first session; in
  F-PR the 61-day session appears in neither period's counted total.
- **Edge case of:** S-1801.

### S-1809: A worse value does not count
- **Fixture:** a synthesised fixture whose only non-first sample is lower than its predecessor.
- **Trigger:** evaluate.
- **Flow:** one evaluation.
- **Expected outcome:** the sample is counted in the denominator and not in the numerator.
- **Edge case of:** S-1806.

### S-1810: A session with no readable value is not counted
- **Fixture:** F-PR plus one extra exercise whose only `set` effort carries no readable weight or
  reps, performed in two sessions.
- **Trigger:** evaluate.
- **Flow:** one evaluation.
- **Expected outcome:** neither session of that exercise appears in either period's counted total,
  and no rate changes as a result.
- **Edge case of:** S-1801.

### S-1811: Sessions of every kind count, and the copy states the span
- **Fixture:** F-PR extended with a closed rolling session and a session carrying a non-lifting
  modality, both containing set efforts; plus an open rolling session containing set efforts.
- **Trigger:** evaluate.
- **Flow:** one evaluation.
- **Expected outcome:** the closed rolling session's and the non-lifting session's sets count; the
  open rolling session's do not; the observation contains `over the last 4 weeks` and a whole-number
  percentage for each period.
- **Edge case of:** S-1801.

### S-1812: The card disappears when the condition clears
- **Fixture:** F-PR, then a second load with three additional recent sessions whose values all fall
  below their predecessors, dropping the recent rate under `kProgressionRateMinRate`; no dismissal
  exists.
- **Trigger:** open, add the sessions, open again.
- **Flow:** two loads.
- **Expected outcome:** the card shows on the first open and not on the second, and the quiet line
  shows on the second.
- **Edge case of:** S-1801.

### S-1813: The real card is dismissible
- **Fixture:** F-PR.
- **Trigger:** open, tap the card's dismiss control, open again.
- **Flow:** two loads and one tap.
- **Expected outcome:** the card is gone in the frame after the tap; on the second open it is still
  gone, and the quiet line shows; the store holds `progression-rate` with an integer timestamp.
- **Edge case of:** S-1812.

### S-1814: The framework and the PR path are untouched
- **Fixture:** F-PR.
- **Trigger:** diff and test run.
- **Flow:** one run.
- **Expected outcome:** the diff into `lib/core/models/signals.dart`,
  `lib/core/services/signals_service.dart` and `lib/features/stats/widgets/signals_layer.dart` is
  empty; `test/in_session_pr_toast_test.dart` and `test/pr_toast_test.dart` are unmodified and pass;
  the PR helper is called nowhere in the new files.
- **Edge case of:** none.

## Iteration 1

**Executor:** @dba for Phase 1 (the model, the service walk), @developer for Phases 2–3 (the signal,
the registry line, guards). Read 6a's plan first: its Ledger binds here, and this plan restates none
of it.

**Baseline to confirm before Phase 1:** 6a is merged and green; quote your own `flutter analyze` and
`flutter test` summary lines as the baseline, and the 6a plan's Phase 3 line for comparison.

**Every phase:** update the Progress table and append to the Assumption Log. Never edit a decision.
Evidence to `.evidence.md`, never into this file. Plain `test()` for the model and the service walk;
`testWidgets` only for S-1801 and S-1812–S-1813.

## Iteration 1 — Phases

### Phase 1: The rate math and the sample walk (@dba)

1. [x] Create `lib/core/models/progression_rate.dart` (D-1101, D-1104–D-1109, D-1112, D-1113):
   `ProgressionSample {String exerciseId, int sessionStartMs, double value}`;
   `ProgressionRate {int recentCounted, int recentProgressions, int priorCounted, int
   priorProgressions, double recentRate, double priorRate, int recentPercent, int priorPercent}`;
   `ProgressionRate? progressionRate({required List<ProgressionSample> samples, required DateTime
   now})` implementing the two windows, the ordering, the first-ever drop, the zero drop and the
   rates, returning `null` when the qualification test fails; the qualification test itself
   (D-1108); and the copy builder producing the observation and the suggestion of D-1109. Constants:
   `kProgressionRateWindowDays = 28`, `kProgressionRateMinCounted = 8`,
   `kProgressionRateMinRate = 0.75`, `kProgressionRateMinImprovement = 0.10`,
   `kProgressionRatePriority = 100`. Pure Dart: no Flutter, no clock, no repository.
2. [x] Add the public sample walk to `lib/core/services/stats_progress_service.dart` (D-1112): one
   method returning every `ProgressionSample` for the completed history, ordered by exercise then
   session start, using the existing cached history index, the existing native-value helper and the
   existing axis classification. Do not add a second value rule and do not add a second history read.
3. [x] Create `test/progression_rate_test.dart` (plain `test()`), pure: S-1802, S-1803, S-1804,
   S-1805, S-1806's numerator half, S-1809; the window boundaries at exactly `now − 28 days` and
   `now − 56 days`; the zero-value drop of D-1104; the rounding of D-1107; and a case whose predecessor
   sits outside both windows (D-1105).
4. [x] Create `test/progression_samples_service_test.dart` (plain `test()`) against the repository
   harness: F-PR's 45 samples with the expected per-exercise values and ordering (D-1101), the
   first-ever exclusion (S-1808), the axis classification for a bodyweight and a weighted exercise
   (S-1807), the closed/open rolling and non-lifting cases (S-1811), the zero-value case (S-1810), and
   that the walk adds no second repository read (D-1112).
5. [x] Red run first: write step 3 before step 1 and record the failing run in the evidence file.
6. [x] Inverse-edit mutations (record both, restore after each): change D-1108's improvement test from
   `>=` to `>` — S-1805 must fail; include the first-ever sample in `progressionSamples` — S-1808 must
   fail.
7. [x] Docs: add the `progression_rate` constant group to `docs/constants_reference.md` (named, never
   restated as values); add `ProgressionSample` and `ProgressionRate` to `docs/data_models.md`; add the
   sample walk to `docs/state_management/services_and_utils.md`'s `StatsProgressService` entry; and add
   the "Registered signals" section to `docs/signals.md` with the definition, the two windows, the
   three thresholds and the copy, every behaviour sentence naming its test. Do not touch
   `docs/stats_screen.md` yet — Phase 2 owns it.

**Done Criteria** (run until green): `flutter analyze` (expect the 6a baseline, 0 errors);
`flutter test test/progression_rate_test.dart test/progression_samples_service_test.dart`;
`flutter test test/stats_progress_test.dart test/mix_layer_service_test.dart
test/records_and_trends_screen_test.dart` (the service file changed); full `flutter test`, quoting
the summary line.
**Predicted Files**: `lib/core/models/progression_rate.dart` (NEW),
`lib/core/services/stats_progress_service.dart` (EDIT — one added method),
`test/progression_rate_test.dart` (NEW), `test/progression_samples_service_test.dart` (NEW),
`docs/constants_reference.md` (EDIT), `docs/data_models.md` (EDIT),
`docs/state_management/services_and_utils.md` (EDIT), `docs/signals.md` (EDIT).
**Phase 1 verification notes (Conductor, 2026-10-03):** not yet verified.

### Phase 2: The signal and the registry line (@developer)

1. [x] Create `lib/core/services/signals/progression_rate_signal.dart` (D-1109, D-1110, D-1112):
   done — `const ProgressionRateSignal`, id `progression-rate`, positive,
   `kProgressionRatePriority`; `evaluate` asks the context's `StatsProgressService` for the samples,
   hands them to `progressionRate(samples:, now: context.now)` and returns the card, or `null`; no
   repository read and no PR API.
   `ProgressionRateSignal implements Signal` with `id = 'progression-rate'`, kind positive, priority
   `kProgressionRatePriority`, and an `evaluate` that asks the context's `StatsProgressService` for
   the samples, calls the pure math with the context's `now`, and returns the card with the title, the
   observation and the suggestion, or `null` when the math returns `null` (6a's D-1008). It calls no PR
   API (D-1111) and reads no repository.
2. [x] Add one line to `buildSignalRegistry()` (6a's D-1016). Nothing else in the framework changes.
   done — the factory now returns `const <Signal>[ProgressionRateSignal()]`; the doc comment's "empty
   in this PR" sentence became false and was corrected.
3. [x] Create `test/progression_rate_signal_screen_test.dart` (widget tests): F-PR end to end
   (S-1801 — the exact observation and suggestion strings, the `Positive` label, the key, no quiet
   line), the card's disappearance (S-1812), the real card's dismissal (S-1813), and that the card is
   in the layer's top slot and does not disturb the Mix, ALL TIME, Instruments or Fuel blocks.
4. [x] Run the Stats surface and the framework tests to prove nothing else moved:
   `flutter test test/signals_layer_screen_test.dart test/signals_framework_test.dart
   test/signals_service_test.dart test/mix_layer_screen_test.dart test/screen_widget_test.dart
   test/stats_legacy_removal_test.dart test/screen_overflow_contract_test.dart`. The layer now renders
   a card where it previously rendered the quiet line for any test with a rated baseline; only
   `test/mix_layer_screen_test.dart` has one, so a failure there is a surface-height
   re-stabilisation and a failure anywhere else is a real finding.
5. [x] Confirm the PR path is untouched: `flutter test test/in_session_pr_toast_test.dart
   test/pr_toast_test.dart test/stats_progress_test.dart` with no modification to those files
   (S-1806, S-1814).
6. [x] Red run first: assert the exact strings before wiring the registry, and record the failing run.
   done — the three Mock tests failed with `Expected: ['signal_card_progression-rate'] / Actual: []`.
7. [x] Docs: add the Progression Rate to `docs/stats_screen.md`'s Signals section as the first
   registered signal, pointing at `docs/signals.md` for its rules; confirm the copy in the docs is the
   shipped copy character for character. Done — the copy equals the source's two concatenated literals
   exactly; the section names no threshold value and links `signals.md#registered-signals`.

**Done Criteria** (run until green): `flutter analyze` (expect the 6a baseline, 0 errors);
`flutter test test/progression_rate_signal_screen_test.dart test/signals_layer_screen_test.dart
test/mix_layer_screen_test.dart test/stats_legacy_removal_test.dart
test/screen_overflow_contract_test.dart test/palette_legibility_contract_test.dart`; full
`flutter test`, quoting the summary line.
**Predicted Files**: `lib/core/services/signals/progression_rate_signal.dart` (NEW),
`lib/core/services/signals/signal_registry.dart` (EDIT — one line),
`test/progression_rate_signal_screen_test.dart` (NEW), `test/mix_layer_screen_test.dart` (EDIT —
surface heights only, if needed), `docs/stats_screen.md` (EDIT).
**Phase 2 verification notes (Conductor, 2026-10-03):** not yet verified.

### Phase 3: Guards, residue sweep and the close (@developer)

1. [x] Structural guards, each a permanent test making its defect class impossible to reintroduce:
   a guard that no signal implementation computes an estimated 1RM or a best-value read of its own
   (the new files call the shared helper, asserted by a source scan or by a value-equality test
   against the shared helper's output); a guard that the qualification test compares exact fractions,
   by asserting the rounded-percentage boundary case (a fixture whose rounded percentages would pass
   where the fractions fail) shows no card; a guard that the progression measure does not call the PR
   API (S-1806's second half, permanent); and a guard that the framework's three files show no diff
   in this PR (S-1814).
2. [x] Residue sweep: search `lib/`, `test/` and `docs/` for every name this PR introduced
   (`ProgressionRateSignal`, `progression-rate`, `progressionSamples`, `ProgressionSample`,
   `ProgressionRate`, `progressionRate`, `kProgressionRateWindowDays`, `kProgressionRateMinCounted`,
   `kProgressionRateMinRate`, `kProgressionRateMinImprovement`, `kProgressionRatePriority`, and the
   observation's opening words) and list every hit's file in the evidence file. Confirm the framework
   files are absent from the list and that the docs' copy matches the shipped copy.
3. [x] Confirm the untouched files: `docs/session_summary.md`, `test/in_session_pr_toast_test.dart`,
   `test/pr_toast_test.dart` and 6a's three framework source files show no diff.
4. [x] Full `flutter test`; quote the summary line and compare it against Phase 1's, explaining every
   delta (expected: only added tests).
5. [x] Re-read `docs/signals.md`'s registered-signal section against the shipped code and correct any
   claim that no longer matches; confirm the file is under the 64 KiB ceiling
   (`test/docs_indexing_contract_test.dart`) and every behaviour sentence names a test.
6. [x] Update the Progress table, close the Assumption Log entries, and fill in the evidence file's
   final table.

**Done Criteria** (run until green): `flutter analyze` (expect the 6a baseline, 0 errors); full
`flutter test`, quoting the summary line; `flutter test test/docs_indexing_contract_test.dart`.
**Predicted Files**: `test/progression_rate_test.dart` (EDIT), `test/progression_rate_signal_screen_test.dart`
(EDIT), `docs/signals.md` (EDIT — corrections only).
**Phase 3 verification notes (Conductor, 2026-10-03):** not yet verified.

## Governor actions

None. The card can only appear when the recent rate is high, improving and built on at least
`kProgressionRateMinCounted` counted exercise-sessions in each period, and the owner's dismissal
control is the framework's escape hatch (6a). The pack's own instruction is that the thresholds are
starting values to revisit once real data shows how often the card fires — that revisit is a
future PR, not a governor action here.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/progression_rate.dart` | NEW — the sample, the windows, the rates, the thresholds, the copy |
| `lib/core/services/stats_progress_service.dart` | EDIT — one public sample walk over the cached history |
| `lib/core/services/signals/progression_rate_signal.dart` | NEW — the signal |
| `lib/core/services/signals/signal_registry.dart` | EDIT — one registration line |
| `test/progression_rate_test.dart` | NEW — the pure math and its boundaries |
| `test/progression_samples_service_test.dart` | NEW — the walk, the axes, the exclusions |
| `test/progression_rate_signal_screen_test.dart` | NEW — the card end to end, its dismissal, its disappearance |
| `test/mix_layer_screen_test.dart` | EDIT — surface heights only, if a card moves a lower block |
| `docs/signals.md` | EDIT — the registered signal's definition, thresholds and copy |
| `docs/stats_screen.md` | EDIT — the signal listed in the Signals section |
| `docs/constants_reference.md` | EDIT — the `progression_rate` group |
| `docs/data_models.md` | EDIT — `ProgressionSample`, `ProgressionRate` |
| `docs/state_management/services_and_utils.md` | EDIT — the added service method; its watch tail moved to the new part page below |
| `docs/state_management/watch_surface.md` | NEW — the watch mirroring and sensor sections, moved verbatim to keep the page above under the docs ceiling |
| `docs/state_management.md`, `docs/README.md`, `docs/watch_session_capture.md`, `docs/state_management/nutrition_state.md`, `docs/docs-audit-2026-07-26.md` | EDIT — links retargeted to the new part page |

## Notes

- **Phase dependency graph:** 1 → 2 → 3, and 6a's Phase 3 → this plan's Phase 1. Phase 1 is
  independently green (pure code and docs, no user-visible change); Phase 2 is the first point at
  which a real card is visible anywhere. Re-ordering Phase 2 before Phase 1 is not possible: the
  signal calls the walk.
- **Agreed interface (a mechanic, not a decision).** `ProgressionSample`, `ProgressionRate`,
  `progressionRate(...)`, the qualification test, the copy builder, the service method and the
  signal class are the names the tests address; they may be renamed as long as the tests are renamed
  with them. The rules in the Ledger must not move.
- **Predicted intermediate state after Phase 1:** the rate math and the sample walk exist and are
  tested, and nothing calls them; the app is unchanged for the user.
- **The F-PR fixture's sensitivity.** Its nearest session to a window boundary is 5 days clear, so a
  few milliseconds between the fixture's `now` and the load's `now` cannot move a session across a
  boundary. A future fixture must keep that clearance or pin `now` explicitly.
- **Why the tie rule is in the ledger twice.** D-1105 (a tie is a progression) and D-1111 (a tie is
  not a PR) are the pack's explicit warning that the two measures must not be confused; they are
  separate entries so a later change to one cannot silently change the other.
- **Legacy handling:** none. Nothing is deleted, renamed or deprecated by this PR.

## Open Items

None blocking. The two judgement calls that a later PR may revisit are recorded as supersedable
ledger entries: D-1104's exclusion of a session with no readable value, and D-1113's fixed
relationship to the selected window.

Phase 1 also split `docs/state_management/services_and_utils.md` (46 bytes under the docs warning
band) into a new part page `docs/state_management/watch_surface.md`. The split is mechanical and the
contract test is green; a later PR may want to rebalance the two pages' contents.

Phase 3 found one stale claim outside its predicted files: the header comment of
`test/signals_layer_screen_test.dart` still says `buildSignalRegistry()` "is empty in this PR", which
Phase 2 made false. The file is 6a's and out of this phase's scope, so it was left alone; a later PR
should correct the sentence (the tests it explains are unaffected — they inject their own stubs).

## Progress

| # | Item | Owner | Status |
|---|---|---|---|
| 1 | Phase 1 — the rate math and the sample walk | @dba | **Complete** — `flutter analyze` 196 issues / 0 errors; full `flutter test` `+3537 ~1: All tests passed!` (+28 = the two new suites); `test/docs_indexing_contract_test.dart` `+9` |
| 2 | Phase 2 — the signal and the registry line | @developer | **Complete** — `flutter analyze` 196 issues / 0 errors; the new screen suite `+5`; step 4 `+425`; step 5 `+98`; full `flutter test` `+3542 ~1: All tests passed!` (+5 = the new tests) |
| 3 | Phase 3 — guards, residue sweep and the close | @developer | **Complete** — 4 new tests in `test/progression_rate_test.dart` (17 → 18); `flutter analyze` 196 issues / 0 errors; `test/docs_indexing_contract_test.dart` `+9`; full `flutter test` `+3546 ~1: All tests passed!` (+4 = the new tests); `docs/signals.md` 11 363 bytes |

## Assumption Log

*(Executors append here: decision made, options considered, choice and why. The Conductor marks each
RATIFIED — promoted to a D-x — or REVERT — a remediation sub-phase.)*

1. **Mutation (b) was applied in the math, not in the walk.** D-1112 and step 4 require the walk to
   return every sample including zero-value ones, so the first-ever drop lives in `progressionRate`.
   The mutation still produced the required S-1808 failure in both harnesses.
2. **The four thresholds stay `const double` with private integer mirrors.** Qualification compares
   exact fractions (`recentProgressions * 4 >= 3 * recentCounted`), because `0.75 - 0.65` is
   `0.09999999999999998` and a double comparison would reject S-1805's boundary fixture. No sixth
   constant was added; the mirrors are private.
3. **The walk reads the history once and groups with `Future.wait`.** "No `await` inside a session
   loop" is read as one concurrent pass over the cached index, not a sequential per-session read.
4. **The walk emits zero-value samples; the math drops them.** Keeps the walk a faithful projection of
   the history and the D-1104 rule in one place.
5. **`docs/state_management/services_and_utils.md` was split (unplanned).** It sat 46 bytes under the
   warning band enforced by `test/docs_indexing_contract_test.dart`, so documenting the new method
   there tripped the contract. Its watch tail moved verbatim to a new part page
   `docs/state_management/watch_surface.md`; the original path keeps an index pointer. See Open Items.
6. **Phase 3's guards are three, not four, tests.** The exact-fraction, shared-helper and no-PR-API
   guards are source scans and pure value assertions in `test/progression_rate_test.dart`; S-1814
   (the framework files unchanged) stays an evidence item, as both briefs direct, because 6a's
   framework files are untracked and git cannot show a diff for them.
7. **A fourth test pins the signal's declared contract** (id, kind, priority). `docs/signals.md`'s
   "Kind and priority" claim named no test, and the documentation standard requires a verification
   pointer per behaviour claim; the alternative was to weaken the claim to what S-1801 already
   asserts, which would have dropped the priority from the doc.
8. **All mutations were restored exactly.** Restoration is proved by the green re-run — the guards
   and the contract test assert the restored values — plus a grep for each mutation's token, which
   returns nothing.

## Feedback

*(Empty. A non-empty entry here is the only thing that re-invokes the planner.)*

## Open questions (defaults applied)

1. **Is a session whose native value falls back to zero counted?** Default applied: no — it enters
   neither the numerator nor the denominator (D-1104). The alternative (count it as a zero) would let
   a skipped row lower a user's rate.
2. **Which session timestamp places a sample in a window?** Default applied: the session's start
   (D-1106).
3. **Are the 28-day windows exact instants or calendar days?** Default applied: exact instants
   derived from `now` (D-1106), so a session is judged by elapsed time, not by the local day it fell
   on.
4. **Does the card follow the screen's selected window?** Default applied: no — it always describes
   the last 28 days against the 28 before them and says so in its copy (D-1113).
5. **Is the pack's suggestion copy kept verbatim** (`The current approach is working.`) even though
   the project's tone rules prefer concrete statements? Default applied: yes — the pack pins it as
   copy, and 6a's D-1019 forbids only rest, deload and recovery instructions.
6. **What is the card's title?** Default applied: `Progression rate` (D-1109) — not rendered, and
   used for the key, the accessibility label and the dismissal store.
7. **Is a comparison attributed to the later session's window?** Default applied: yes (D-1105),
   which is why a window's first sample may compare against a predecessor outside it and why the walk
   covers the whole history.
