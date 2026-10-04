# Feature: Cardio Efficiency Drift (Stats PR 9b — pack item 15)

> **Status:** READY (planner) — not started.
> **Next handoff:** @dba (Phase 1).
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 15
> ("Cardio Efficiency Drift (Caution)"), and the seam in
> `docs/plans/2026-10-04-09-stats-pr9-index.md`.
> **Base:** `develop` at `e86c4ad`. Five signals are registered today, in this order:
> `protein-consistency`, `fuel-vs-load`, `progression-rate`, `modality-mix-shift`,
> `cross-modality-interference`. The Mix layer, the shared load definitions, the sensor-summary
> reads, the distance pairing and the signals framework are all shipped and unchanged.
> **Depends on:** PR 9a (Sustained High Load) for the registry position and for the two whole-list
> registry guards: 9b's entry goes **first** (priority 50, below 9a's 100), and the guard count
> becomes one higher than whatever 9a left it at. Read the two guard files before editing them; the
> rename is by count, not by a fixed literal (Phase 3A step 4). Everything else in this plan is
> independent of 9a.
> **Binding conventions:** `docs/global_conventions.md`. `docs/README.md` entries to read before
> Phase 1: `docs/signals.md`, `docs/training_load.md`, `docs/distance_source.md`,
> `docs/watch_session_capture.md`, `docs/stats_screen.md`, `docs/constants_reference.md`,
> `docs/state_management/services_and_utils.md`, `docs/data_models.md`, `docs/design_system.md`.
> Budget: `.github/agents/pr_scope_budget.md`.
> **Evidence:** `2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.evidence.md` (this folder).
> Review findings: `.review.md`. Neither is written into this file.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 748 (measured by reading the file back) | 500 | 800 |
| Phases | 4 (1, 2, 3A, 3B) | >3 | >5 |
| Tracks | 1 (`lib/`, `test/`, `docs/`) | >1 | — |
| Ledger decisions | 17 (D-1801…D-1817) | >20 | — |
| Scenarios | 12 (S-2501…S-2512) | >30 | — |
| Predicted production lines | ~390 | — | ~1,500 |

**Verdict: over the soft budget on two counts, zero hard limits reached, and the split has
already happened at the series level.** Stated plainly rather than argued away:

- **Plan length 748** is above the 500 soft line and 52 below the 800 hard cap. It is
  scenario-bound: 12 fixture-enumerated scenarios with hand-computed efficiencies, exact
  cross-multiplications, window edges and pinned copy strings are the whole point of the plan, and
  this signal carries more eligibility surface than any of the shipped cautions (a distance
  source, a sensor scope and a duration grouping all decide whether an effort counts at all).
  The sibling signal plan from the previous PR, `2026-10-03-08b-…-plan.md`, is 671 lines for one
  signal with 16 scenarios and was accepted at the same soft signal.
- **Four phases** is above the soft 3, but it is the brief's own instruction, not extra scope: the
  brief requires Phase 3 of each plan to be split into part A (card, adapter, registry, guards,
  screen scenarios) and part B (structural guards, residue sweep, docs) *as two agent runs*, so no
  single run carries more than ten concerns. The two parts are one phase's work.
- **The split the rule asks for is the seam of this series.** Pack items 14 and 15 are planned as
  two independent PRs (9a and 9b), one signal each, sharing no production file except the registry
  and its two guards. A stricter reading — split 9b again — would have to cut between its data
  layer (Phases 1–2) and its signal surface (Phases 3A–3B), which would put a rule file and its
  adapter in different PRs and leave the first one unshippable. It is not proposed.

## What this PR does

It adds one caution signal: for one cardio exercise, the user's measured pace at the same average
heart rate is worse than it was four to six weeks ago, over comparable-duration efforts, with
enough of them on both sides to mean anything. When their lifting load is also up over the last
four weeks, that is added as a plain second observation, side by side, with no claim that one caused
the other.

Two surfaces change:

- a pure definition file (`lib/core/models/cardio_efficiency_drift.dart`) holding the constants,
  the windows, the grouping, the drift test and the copy;
- one read on `StatsProgressService` (`cardioEfforts`) that turns the cached history into eligible
  efforts — finished timed Cardio instances that carry a **measured** distance and an average heart
  rate;
- a thin adapter and one registry line.

Nothing else changes. No schema, no stored field, no migration, no flag, no watch code, no new
widget, no new token, no framework change. The card is the framework's own neutral caution card.

## Resolved Decisions (Ledger)

**D-1801 — One definition file, pure Dart, and the two windows.** The rule lives in
`lib/core/models/cardio_efficiency_drift.dart`; it imports only `training_load.dart` and
`signals.dart`, holds no clock, repository, service or Flutter, and takes `now` and the effort list
as parameters. The adapter is `lib/core/services/signals/cardio_efficiency_drift_signal.dart` and the
registry gains one line. The windows are local calendar arithmetic off `now`'s own date
(`DateTime(now.year, now.month, now.day - n)`), never a `Duration`, so a DST transition cannot move a
boundary:

- **recent** = `[day(kCardioEfficiencyRecentDays - 1), day(-1))` = `[day(13) 00:00, tomorrow 00:00)`
  — the last fourteen local days, today included;
- **reference** = `[day(kCardioEfficiencyReferenceWeeksFrom * 7), day(kCardioEfficiencyReferenceWeeksTo * 7))`
  = `[day(42) 00:00, day(28) 00:00)` — fourteen days, from forty-two days ago up to but not
  including twenty-eight days ago;
- **the gap** between them is days 27 down to 14, fourteen days, and holds no effort.

An effort belongs to the window its own instance start falls in, with the lower bound inclusive and
the upper bound exclusive. So `day(13) 00:00` is recent, `day(14) 23:59` is in the gap,
`day(42) 00:00` is reference, and `day(28) 00:00` is in the gap.

**D-1802 — The eligible effort, decided by the service.** An eligible effort is one **finished
timed instance** of a Cardio (`timed`) effort that carries all three of:

- a paired distance row whose value is above zero and whose source is not the watch's estimate —
  `!DistanceSource.isEstimated(row.valueSource)` and `row.valueReal > 0`. `isEstimated` is the app's
  own definition of an estimate (`EffortObservation.sourceEstimated`, `'estimated'`), so a row the
  watch wrote with no GPS fix is excluded exactly as an indoor estimate is, and a row carrying no
  source at all is not an estimate and stays eligible;
- an average heart rate from the instance's own `timed_instance` sensor summary
  (`avgHeartRateBpm != null && > 0`). A session-scope summary, a summary for another instance, or a
  summary with no heart rate does not qualify an effort;
- a duration above zero.

The instance's own `startedAtMs` places it, its `actualDurationSecs` is its duration, and its
exercise's id and name are carried for the copy. Distances pair with instances through the shipped
`DistancePairing.forEntries` (D-324), the same pairing the Stats pace uses — never a second pairing.

**D-1803 — Efficiency.** `distanceMetres * 60 / (avgHeartRateBpm * durationSecs)` — metres per
heartbeat-minute, distance per unit of heart-rate exposure, larger is better. The arithmetic is
exact on the stored values: with an average heart rate of 150 and an 8-minute (480-second) effort
the divisor is 72000, so 3000 m reads 2.5, 2850 m reads 2.375 and 2400 m reads 2.0.

**D-1804 — Comparable duration, grouped deterministically.** The grouping runs on windowed efforts
only: `cardioEfficiencyDriftFor` keeps the efforts in D-1801's recent or reference window before it
partitions by exercise and groups, so `cardioEffortGroups` receives only windowed efforts and a gap
effort (days 27 down to 14) can never become an anchor. Within one exercise, all its eligible
efforts are sorted by duration ascending (ties by start, then by id), and grouped greedily: take the
shortest ungrouped effort as the group's **anchor**, and the group is that effort plus every
ungrouped effort whose duration is within the anchor's
`kCardioEfficiencyDurationTolerancePercent` (10) — `dur * 10 <= anchor * 11`, inclusive. There is no
chaining: every member is within ±10% of the anchor, and the anchor is always the shortest member,
so a 30-minute and a 45-minute effort can never share a group. A group qualifies when it holds at
least `kCardioEfficiencyMinEffortsPerWindow` (3) efforts **in the recent window and** at least three
**in the reference window**.

**D-1805 — The drift.** For a qualifying group, `recentMean` and `referenceMean` are the arithmetic
means of its members' efficiencies in each window, and the group fires when
`recentMean * 100 <= referenceMean * (100 - kCardioEfficiencyDriftPercent)` — exactly 5% worse
fires, 4% does not — never on a rounded percentage, and never when `referenceMean <= 0`. The
reported figure is `p = ((1 - recentMean / referenceMean) * 100).round()`.

**D-1806 — Selection across groups.** Every qualifying group of every exercise is evaluated. The
card reports the group with the **largest** `p`; ties are broken by exercise id ascending, and two
groups of the same exercise with the same `p` are broken by the shorter anchor duration. Exactly one
card is produced, whatever the number of qualifying groups: the exercise's own name is the card's
subject (D-1808).

**D-1807 — The lifting sentence's inputs.** The adapter asks
`computeMixPeriod(fromMs: day(kCardioEfficiencyLiftLoadWindowDays - 1), toMs: context.now)` — the
last twenty-eight local days — and reads two figures off that one payload:

- `liftRecentLoad` = the summed measures of `payload.segments` for `ExerciseSection.resistance`;
- `liftUsualLoad` = the summed measures of `payload.baselineSegments` for `ExerciseSection.resistance`.

The payload's baseline spans `kTrainingLoadBaselineWeeks` (12) seven-day blocks — eighty-four days —
while the period spans twenty-eight, so the two are compared **per day**, as exact integer
arithmetic: the sentence needs `payload.measure == MixMeasure.load`, `liftUsualLoad > 0`, and

```
liftRecentLoad * 84 * 100 >= liftUsualLoad * 28 * (100 + kCardioEfficiencyLiftLoadRisePercent)
```

which is exactly +15%. Comparing the raw totals instead would compare twenty-eight days with
eighty-four and could never fire; that is the reason the per-day form is pinned here. The reported
figure is `q = ((liftRecentLoad * 84) / (liftUsualLoad * 28) - 1) * 100).round()`.

**D-1808 — The copy.** Built by `cardioEfficiencyDriftCopy(result)`, with `p` the drift percentage
and `q` the lifting figure:

- observation:
  `At similar durations, your <exercise name> efforts are about <p>% less efficient (slower pace at the same heart rate) than 4–6 weeks ago.`
- optional second observation, present only when D-1807 fires:
  `Lifting load is <q>% above your usual over the same period.`
- suggestion: `An easier week is one option.`

The span is built from `kCardioEfficiencyReferenceWeeksTo` and `kCardioEfficiencyReferenceWeeksFrom`
(`4–6`), never written as a literal. The noun is the exercise's **own name**, exactly as the user
wrote it, followed by `efforts` — the pack's example reads `your runs`, but a generic noun would
misname a ride or a row and would hide which exercise drifted, so the user's own name is used.
**Owner to confirm** (Open Items 1). The suggestion is the pack's sentence with its causal clause
(`Accumulated fatigue is a common reason for this;`) dropped: the app cannot observe a cause.
**Owner to confirm** (Open Items 2). No amount, no pace figure, no zone, no calorie and no medical
language anywhere in the copy.

**D-1809 — Kind, priority, and the registry position.** Kind is `SignalKind.caution`. The priority
is `kCardioEfficiencyDriftPriority = 50` — the lowest caution, below Sustained High Load (100). The
registry lists cautions in **ascending** priority, so the entry is inserted **first** in
`buildSignalRegistry()`:

```dart
List<Signal> _build() => const [
  CardioEfficiencyDriftSignal(),  //  50
  SustainedHighLoadSignal(),      // 100  (PR 9a; absent until 9a lands)
  ProteinConsistencySignal(),     // 200
  FuelVsLoadSignal(),             // 300
  ProgressionRateSignal(),        // 100 (positive)
  ModalityMixShiftSignal(),       // 400
  InterferenceSignal(),           // 500
];
```

The card's label comes from the framework (`kSignalCautionLabel`, `Worth a look`); no colour, token
or widget is added, and the cap (two cards) and the dismissal window (fourteen local calendar days)
stay the framework's.

**D-1810 — One walk, no new framework surface.** `cardioEfforts` is the only history walker; it
reuses the cached history read, the shipped distance pairing and the shipped sensor-summary reads.
The rule is pure; the adapter reads only `context.now` and `context.progressService`, never a
repository. `SignalContext` gains no member and the framework files are not edited. Nothing is
stored, so there is no migration, no legacy path, no flag and no back-compatibility shim.

**D-1811 — The comparison never crosses exercises.** A group holds efforts of one exercise only,
because grouping partitions by exercise id before anything else, and the card names that exercise.
A run is never compared with a ride, a row or a walk, whatever their durations.

**D-1812 — Both stores agree.** Every read goes through `StatsProgressService`, so
`HiveWorkoutRepository` and `MockWorkoutRepository` must return the same eligible efforts and the
same card value-for-value (S-2512).

**D-1813 — The constants.**

```dart
const int kCardioEfficiencyDriftPriority = 50;
const int kCardioEfficiencyRecentDays = 14;
const int kCardioEfficiencyReferenceWeeksFrom = 6;
const int kCardioEfficiencyReferenceWeeksTo = 4;
const int kCardioEfficiencyDurationTolerancePercent = 10;
const int kCardioEfficiencyMinEffortsPerWindow = 3;
const int kCardioEfficiencyDriftPercent = 5;
const int kCardioEfficiencyLiftLoadRisePercent = 15;
const int kCardioEfficiencyLiftLoadWindowDays = 28;
```

`kTrainingLoadBaselineWeeks` (12) is reused for the lifting baseline's span; no second twelve-week
constant is declared.

**D-1814 — The card fires on the efficiency drift alone.** The lifting sentence is an addition to a
card the efficiency drift has already earned; a lift rise with no drift shows nothing, and a drift
with no lift rise shows the observation with no second sentence. The two facts are shown side by
side and the copy never links them causally.

**D-1815 — The two whole-list registry guards are extended, minimally.** In the same style, without
reformatting either file: `test/interference_test.dart`'s
`the caution order holds and the registry is ordered by it` gains `'cardio-efficiency-drift'`
**first** in its expected caution list, and
`test/modality_mix_shift_signal_screen_test.dart`'s
`lists exactly the N shipped signals, in order` gains the same id first and has its name's count
raised by one. A third representation of the whole list is prose in `docs/signals.md`; it is updated
in Phase 3B.

**D-1816 — Eligibility is the service's, the windows are the rule's.**
`StatsProgressService.cardioEfforts({required DateTime fromMs, required DateTime toMs})` returns
every eligible effort whose instance start falls in the window, ordered by start; it applies
D-1802's three eligibility tests and **no** window decision of its own beyond the span the caller
asks for. The adapter asks for the whole span the comparison needs —
`fromMs: day(42)`, `toMs: context.now` — and the rule applies D-1801's windows, so every window
boundary scenario asserts on a stage of the rule rather than through a service span.

**D-1817 — The rule's stages are separately callable.** `cardioEfficiencyDriftFor` keeps only the
efforts in the recent or the reference window (D-1801) before it partitions and groups, so
`cardioEffortGroups` receives windowed efforts only (D-1804). `cardioEfficiencyWindows(now)`,
`cardioEffortGroups(efforts)`, `cardioEfficiencyDriftFor({efforts, now})` (the efficiency half
alone), `cardioEfficiencyDrift({efforts, now, liftRecentLoad, liftUsualLoad, liftMeasure})` (the
whole rule, including the optional lifting figure) and `cardioEfficiencyDriftCopy(result)`. A
scenario about grouping, about the ±10% boundary or about the window edges asserts on the stage that
owns the decision, so no scenario depends on the composed rule's other floors.

## Feature Invariants

Only the invariants that bite here:

- **Repository parity.** Every read goes through `StatsProgressService`, so Hive and Mock must
  return the same eligible efforts and the same card (S-2512).
- **One distance pairing and one sensor read.** Eligibility reads the shipped
  `DistancePairing.forEntries` and the shipped `timed_instance` sensor summaries. No second pairing,
  no second sensor index, no re-derivation of either.
- **Estimated distances are never used**, whether the effort was indoor or an outdoor effort that
  fell back to the estimate; the only way such an effort becomes eligible is a correction that
  changes its stored source (S-2504).
- **No comparison crosses exercises**, and no comparison mixes durations more than ±10% apart
  (D-1804, D-1811).
- **Nothing is stored, and `SignalContext` gains no member.** The framework files are untouched.
- **No medical, causal or prescriptive language** in the copy.

## Requirements

1. A caution card appears when one cardio exercise's eligible, comparable efforts show the recent
   window's mean efficiency at least 5% worse than the reference window's, with at least three
   eligible comparable efforts in each window.
2. Efforts with an estimated distance or no average heart rate never contribute, in either window.
3. Efforts more than 10% apart in duration are never compared, and efforts of different exercises
   are never compared.
4. When resistance load over the last twenty-eight days is at least 15% above the usual level and
   the Mix layer's payload for that period is measured in load, the card carries the second
   observation sentence; otherwise it does not.
5. The card is a caution with priority 50, registered first in the caution order, rendering the
   framework's neutral card and its fourteen-day dismissal.
6. Hive and Mock agree value-for-value.
7. `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`,
   `docs/state_management/services_and_utils.md`, `docs/distance_source.md` and
   `docs/training_load.md` describe the shipped behaviour, each sentence naming the test that proves
   it.

## Acceptance Criteria

| # | Acceptance criterion (pack item 15) | Scenario |
|---|---|---|
| AC-1 | Four comparable GPS runs with heart rate in each window, 7% worse recently, shows the card | S-2501 |
| AC-2 | 4% worse shows nothing; exactly 5% shows the card | S-2502 |
| AC-3 | Two eligible efforts in either window shows nothing; exactly three shows the card | S-2503 |
| AC-4 | An estimated-distance treadmill run is never counted, and is counted after the user corrects its distance | S-2504 |
| AC-5 | An outdoor run that fell back to the estimate is never counted unless corrected | S-2504 |
| AC-6 | A run without heart rate is never counted | S-2505 |
| AC-7 | Runs of 30 and 45 minutes are never compared with each other | S-2506 |
| AC-8 | The ±10% duration boundary groups inclusively | S-2506 |
| AC-9 | Different cardio exercises are never compared with each other | S-2507 |
| AC-10 | The windows are the last 14 days and days 28–42 ago, by local calendar day | S-2508 |
| AC-11 | The lifting-load sentence appears only at 15% or more above the usual level | S-2509 |
| AC-12 | One card, naming the largest drift | S-2510 |
| AC-13 | The card is a neutral caution: label `Worth a look`, cap, dismissal | S-2511 |
| AC-14 | Hive and Mock agree value-for-value | S-2512 |

## Scenarios

Fixtures are stated as eligible efforts: one exercise, a duration, a distance and an average heart
rate. Efficiency is `distance × 60 ÷ (heart rate × duration seconds)` (D-1803), so with an average
heart rate of 150 and 480-second efforts the divisor is 72000 and a 3000 m effort reads 2.5.

### S-2501: the pack's row — four comparable runs, 7% worse
- **Fixture:** one exercise (`Treadmill Run`), four recent efforts at 480 s and 2790 m each with an
  average heart rate of 150, and four reference efforts at 480 s and 3000 m each with the same
  heart rate. The recent efforts start 3, 6, 9 and 12 days ago; the reference efforts 30, 33, 36 and
  39 days ago. The Mix payload for the last 28 days is measured in load with no resistance rise.
- **Trigger:** `cardioEfficiencyDriftFor({efforts, now})` and the composed rule.
- **Flow:** the grouping anchors at 480 s and takes all four in each window; the means are 2.325
  (2790 ÷ 1200) and 2.5 (3000 ÷ 1200).
- **Expected outcome:** `p = 7`, and the card's observation reads
  `At similar durations, your Treadmill Run efforts are about 7% less efficient (slower pace at the same heart rate) than 4–6 weeks ago.`,
  with no second sentence and the suggestion `An easier week is one option.`
  (`(1 - 2.325 / 2.5) * 100 = 7.0`).
- **Edge case of:** none (the pack's own row).

### S-2502: the 5% boundary is inclusive
- **Fixture:** S-2501 with the recent efforts at 2850 m each — a recent mean of 2.375 against 2.5,
  exactly 5% worse — and the same fixture with the recent efforts at 2880 m each — a recent mean of
  2.4, exactly 4% worse.
- **Trigger:** `cardioEfficiencyDriftFor({efforts, now})`.
- **Expected outcome:** at 2850 m the result is non-null with `p = 5`
  (`2.375 * 100 = 237.5 <= 2.5 * 95 = 237.5`); at 2880 m it is null
  (`2.4 * 100 = 240 > 237.5`).
- **Edge case of:** S-2501.

### S-2503: three efforts per window is the floor
- **Fixture:** S-2501 with two recent efforts and four reference efforts, and the same fixture with
  exactly three recent efforts.
- **Trigger:** `cardioEfficiencyDriftFor({efforts, now})` and `cardioEffortGroups`.
- **Expected outcome:** the group is formed in both cases (grouping has no minimum); with two recent
  efforts it does not qualify and the result is null; with three it qualifies and `p = 7`.
- **Edge case of:** S-2501.

### S-2504: estimated distances, and what a correction does
- **Fixture:** S-2501 with one recent effort's distance row stored with
  `EffortObservation.sourceEstimated` — first as an indoor treadmill effort, then as an outdoor
  effort that fell back to the estimate for lack of a GPS fix (the same stored source). Both leave
  two eligible recent efforts. Then the row is re-stored through the repository's observation write
  path with `source: EffortObservation.sourceEntered`, which makes three.
- **Trigger:** `StatsProgressService.cardioEfforts(…)`, then the rule.
- **Expected outcome:** with the estimate the effort is absent from the list and no card shows (two
  recent efforts); after the correction it is present, three recent efforts qualify and the card
  shows with `p = 7`. A row with a `'gps'` source and a row with no source at all both stay
  eligible, while an `'estimated'` row never does.
- **Edge case of:** S-2501 (AC-4, AC-5).

### S-2505: a run without heart rate is never counted
- **Fixture:** S-2501 with one recent effort carrying no `timed_instance` sensor summary at all; and
  a variant where the summary exists but its `avgHeartRateBpm` is null; and a variant where the
  heart rate is stored on a **session**-scope summary instead of the instance's.
- **Trigger:** `StatsProgressService.cardioEfforts(…)`, then the rule.
- **Expected outcome:** in all three variants the effort is absent and no card shows (two recent
  efforts remain); seeding the instance's own summary restores it and the card shows with `p = 7`.
- **Edge case of:** S-2501 (AC-6).

### S-2506: the ±10% duration boundary, and 30 against 45 minutes
- **Fixture A:** one exercise with three recent and three reference efforts at 480 s, plus three
  recent and three reference efforts at 528 s (`480 * 11 = 5280 = 528 * 10`, exactly +10%): the
  boundary case. **Fixture B:** the same with 529 s instead of 528 s, and only two efforts at 480 s,
  so the 480 s group is below the floor. **Fixture C:** three recent and three reference efforts at
  1800 s (30 minutes) and three recent and three reference at 2700 s (45 minutes).
- **Trigger:** `cardioEffortGroups(efforts)` and the rule.
- **Expected outcome:** A forms one group of six efforts per window and the card reports the largest
  drift; B forms two groups (529 s is not within 10% of 480 s: `529 * 10 = 5290 > 5280`) so the 480 s
  group has two recent efforts and the 529 s group has three — the 529 s group must itself carry the
  drift for a card to show, and with no drift on it nothing shows; C forms two groups that never
  merge (`2700 * 10 = 27000 > 1800 * 11 = 19800`) and shows nothing while each group holds fewer
  than three drifting efforts.
- **Edge case of:** S-2501 (AC-7, AC-8).

### S-2507: different exercises are never compared
- **Fixture:** two exercises, each with three recent and three reference efforts at 480 s: the run's
  recent mean is 5% worse (2850 m against 3000 m) and the ride's is 20% worse in the *other*
  direction (its recent efforts are **faster**, so it never fires). Then the reverse fixture, where
  the ride is 5% worse and the run is not.
- **Trigger:** `cardioEffortGroups(efforts)` and the rule.
- **Expected outcome:** the groups never hold both exercises; the card reports the exercise that
  drifted, and pooling the two exercises into one group would give a different (non-firing) figure —
  which the assertion pins by checking the reported exercise's name.
- **Edge case of:** S-2501 (AC-9).

### S-2508: the window edges
- **Fixture:** one exercise with eligible efforts started at exactly `day(13) 00:00`,
  `day(14) 23:59`, `day(27) 23:59`, `day(28) 00:00`, `day(42) 00:00` and `day(43) 00:00`, each with
  a duration and distance that would fire the card if it were counted.
- **Trigger:** `cardioEfficiencyWindows(now)` and `cardioEfficiencyDriftFor({efforts, now})`.
- **Expected outcome:** `day(13) 00:00` is in the recent window; `day(14) 23:59`, `day(27) 23:59`,
  `day(28) 00:00` and `day(43) 00:00` are in neither window; `day(42) 00:00` is in the reference
  window. The card's figures change only when a counted effort changes. A gap effort whose duration
  would, as an anchor, have absorbed a recent effort into the wrong group changes nothing, so the
  card's figures equal those without it.
- **Edge case of:** S-2501 (AC-10).

### S-2509: the lifting sentence
- **Fixture:** S-2501 plus resistance load: four rated resistance sessions in the last 28 days at
  `69 min × rating 5 = 345` load each (`liftRecentLoad = 1380`), and twelve rated resistance
  sessions in the twelve baseline blocks at `60 min × rating 5 = 300` each
  (`liftUsualLoad = 3600`), all with the period's payload measured in load. Variants: recent load at
  1350 (12.5%), the payload measured in time, and no baseline resistance at all.
- **Trigger:** the composed rule with each payload's figures, then the adapter against the seeded
  service.
- **Expected outcome:** at 1380 the card carries
  `Lifting load is 15% above your usual over the same period.`
  (`1380 * 84 * 100 = 11592000 >= 3600 * 28 * 115 = 11592000`); at 1350, with a time measure, and
  with no baseline resistance, the card shows with **no** second sentence.
- **Edge case of:** S-2501 (AC-11).

### S-2510: one card, the largest drift
- **Fixture A:** two exercises, both qualifying, one at 5% and one at 12% → the 12% one is
  reported. **Fixture B:** two exercises, both at exactly 5% → the lower exercise id is reported.
  **Fixture C:** one exercise with two qualifying groups at the same `p`, anchored at 480 s and
  720 s → the 480 s group's figures are reported.
- **Trigger:** `cardioEfficiencyDrift({…})`.
- **Expected outcome:** exactly one card in each case, carrying the pinned exercise's name and the
  pinned figure.
- **Edge case of:** S-2501 (AC-12).

### S-2511: the card on the Stats screen
- **Fixture:** S-2501 seeded through the Mock store, opened on `StatsScreen` with the real registry,
  plus a variant seeding a qualifying Sustained High Load streak as well (when 9a has landed).
- **Trigger:** the screen builds, then the dismissal control for the card is tapped.
- **Expected outcome:** one card with key `signal_card_cardio-efficiency-drift`, kind label
  `Worth a look`, the observation above and the suggestion above; with two qualifying cautions the
  cap renders two cards in ascending priority (Cardio Efficiency Drift first); after the tap the
  card is gone and stays gone after a reopen. The dismissal tap is Mock-only (a Hive write inside
  the widget test's fake-async zone never drains).
- **Edge case of:** S-2501 (AC-13).

### S-2512: the two stores agree
- **Fixture:** S-2501, S-2504's corrected variant and S-2509 seeded through both
  `harnessFactories`.
- **Trigger:** `cardioEfforts` and the composed rule on each repository.
- **Expected outcome:** identical eligible efforts (exercise, start, duration, distance, heart rate,
  in order) and identical card copy on Hive and Mock.
- **Edge case of:** S-2501 (AC-14).

## Iteration 1

Phase order is 1 → 2 → 3A → 3B. Phase 2 needs Phase 1's `CardioEffort` type; Phase 3A needs Phase
2's `cardioEfforts`; Phase 3B needs Phase 3A's card. If 9a has landed, its registry entry sits
second and its two guards already list six ids. Commands in Done Criteria run through the repo's
gateway wrapper in Copilot sessions.

### Phase 1: the pure rule and its constants (@dba)

1. [x] Write `test/cardio_efficiency_drift_test.dart` **first**, importing
       `package:omnitrain/core/models/cardio_efficiency_drift.dart`, with the S-2501, S-2502,
       S-2503, S-2506, S-2507, S-2508, S-2509, S-2510 fixtures, small local builders for an
       `CardioEffort`, and a `the constant contracts` group asserting every
       `kCardioEfficiency…` value. Run it: it must fail to compile. Record that red run in the
       evidence file.
2. [x] Create `lib/core/models/cardio_efficiency_drift.dart` with the constants of D-1813, the
       `CardioEffort{exerciseId, exerciseName, start, durationSecs, distanceMetres, avgHeartRateBpm}`
       payload (D-1802), `CardioEfficiencyWindows{recentStart, recentEnd, referenceStart,
       referenceEnd}`, `CardioEffortGroup{anchorSecs, efforts}`, `CardioEfficiencyDriftResult{…}`
       and `CardioEfficiencyDriftCopy{observation, suggestion}`.
3. [x] Add `cardioEfficiency(…effort)` (D-1803) and `cardioEfficiencyWindows(now)` (D-1801), each
       with the exact arithmetic in its doc comment.
4. [x] Add `cardioEffortGroups(efforts)` (D-1804) — partition by exercise, sort by
       (duration, start, id), anchor greedily, no chaining — and
       `cardioEfficiencyDriftFor({efforts, now})` (D-1805, D-1806) applying the windows, the
       per-window floor and the largest-drift selection.
5. [x] Add the composed `cardioEfficiencyDrift({required List<CardioEffort> efforts, required
       DateTime now, required double liftRecentLoad, required double liftUsualLoad, required
       MixMeasure liftMeasure})` (D-1807, D-1814) and `cardioEfficiencyDriftCopy(result)` with the
       exact strings of D-1808 (the span built from the two week constants; the second sentence only
       when the lifting test fired).
6. [x] Green: run the Phase 1 suite and paste the summary line into the evidence file.
7. [x] **Mutation check 1** (must fail if the boundary is wrong): change the drift test to
       `recentMean * 100 < referenceMean * 95` (strict), run S-2502's exactly-5% case, confirm it
       fails, revert. **Mutation check 2** (must fail if grouping chains): change the ±10% bound to
       compare each member with the group's *previous* member instead of the anchor, run S-2506's
       529-second case, confirm the two groups merge and the test fails, revert. Record both.

**Done Criteria** (run until green): `flutter analyze` (0 errors);
`flutter test test/cardio_efficiency_drift_test.dart test/training_load_test.dart`;
full `flutter test` with its summary line pasted into the evidence file.

**Predicted Files:** `lib/core/models/cardio_efficiency_drift.dart` (NEW);
`test/cardio_efficiency_drift_test.dart` (NEW).

### Phase 2: the service read (@dba)

1. [ ] Write `test/cardio_efficiency_service_test.dart` **first**, plain `test()` (never
       `testWidgets`), over `test/helpers/repository_harness.dart` with **both** `harnessFactories`
       where the assertion is store-independent: S-2504's four variants, S-2505's three variants,
       S-2508's edge placements and S-2512's parity case. Seed instances and distances directly with
       `timedInstance`, `distanceRow` and `seedSensorSummary` where `seedTimedEntries`' own
       arithmetic (`(n + 1) × metresBase`) does not give the values the scenario needs. Run it: it
       must fail (the method does not exist). Record the red run.
2. [ ] Add `Future<List<CardioEffort>> cardioEfforts({required DateTime fromMs, required DateTime
       toMs})` to `lib/core/services/stats_progress_service.dart`: reuse `_loadHistory`; walk
       completed sessions in the window; for each `timed` effort take its finished timed instances,
       pair distances with `DistancePairing.forEntries` (D-324, the shipped pairing), keep an
       instance whose paired row is above zero and not `DistanceSource.isEstimated`, read its
       `timed_instance` summary's `avgHeartRateBpm`, and return the payloads ordered by instance
       start. No new history walk, no second pairing, no sensor re-index.
3. [ ] Green on the new suite, then on the neighbouring service suites, then the full suite; paste
       all three summary lines.
4. [ ] **Mutation check 3** (must fail if estimates leak in): drop the
       `!DistanceSource.isEstimated(...)` test, run S-2504, confirm the estimated effort becomes
       eligible and the test fails, revert. **Mutation check 4**: read the heart rate from the
       session-scope summary instead of the instance scope, run S-2505's third variant, confirm it
       fails, revert. Record both.

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/cardio_efficiency_service_test.dart test/stats_progress_test.dart test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/distance_source_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/stats_progress_service.dart` (EDIT — one method, nothing
else); `test/cardio_efficiency_service_test.dart` (NEW).

### Phase 3A: the card, the registry and the guards (@developer)

1. [ ] Write `test/cardio_efficiency_drift_signal_screen_test.dart` **first**, Mock-first
       (`--plain-name "Mock"`), following `test/fuel_vs_load_signal_screen_test.dart`: a tall
       viewport, `_day(daysAgo)`/`_at(daysAgo, hour)` local helpers, the S-2501, S-2503 and S-2511
       fixtures seeded through the harness plus the screen's real registry, and the dismissal tap in
       a Mock-only case. Run it: it must fail. Record the red run.
2. [ ] Create `lib/core/services/signals/cardio_efficiency_drift_signal.dart` after
       `fuel_vs_load_signal.dart`: private
       `const String _kCardioEfficiencyDriftTitle = 'Cardio efficiency drift';`,
       `id => 'cardio-efficiency-drift'`, `kind => SignalKind.caution`,
       `priority => kCardioEfficiencyDriftPriority`, and an `evaluate` that reads `context.now`,
       asks `cardioEfforts(fromMs: day(42), toMs: context.now)`, asks
       `computeMixPeriod(fromMs: day(27), toMs: context.now)`, derives the two resistance figures off
       that one payload (D-1807), calls the rule and builds the card from
       `cardioEfficiencyDriftCopy`. It reads no repository and no PR API.
3. [ ] Insert `CardioEfficiencyDriftSignal()` **first** in `buildSignalRegistry()` in
       `lib/core/services/signals/signal_registry.dart` (D-1809) — one line, no reformat.
4. [ ] Extend the two whole-list registry guards (D-1815), in place and without reformatting:
       `test/interference_test.dart`'s caution list gains `'cardio-efficiency-drift'` first, and
       `test/modality_mix_shift_signal_screen_test.dart`'s whole-list test gains the same id first
       and has its name's count raised by one (read the name before editing: it says `five` if 9a
       has not landed and `six` if it has).
5. [ ] Green: the new screen suite (Mock-first), then the two guard suites, then the full suite.
       Paste the summary lines.
6. [ ] **Mutation check 5** (must fail if the registry position is wrong): move the new entry to the
       end of the registry, run both guards, confirm both fail, revert. **Mutation check 6**: pass
       `liftMeasure: MixMeasure.load` unconditionally in the adapter, run S-2509's time-measure
       variant, confirm the sentence wrongly appears, revert. Record both.

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/cardio_efficiency_drift_signal_screen_test.dart --plain-name "Mock"`;
`flutter test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart`;
`flutter test test/cardio_efficiency_drift_test.dart test/cardio_efficiency_service_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/signals/cardio_efficiency_drift_signal.dart` (NEW);
`lib/core/services/signals/signal_registry.dart` (EDIT — one line);
`test/cardio_efficiency_drift_signal_screen_test.dart` (NEW); `test/interference_test.dart` (EDIT —
one list); `test/modality_mix_shift_signal_screen_test.dart` (EDIT — one name, one list).

### Phase 3B: structural guards, the residue sweep and the docs (@developer)

1. [ ] Add the structural guard for eligibility to `test/cardio_efficiency_service_test.dart`: a
       table over every stored distance source (`'gps'`, `'entered'`, `'estimated'`, and no source)
       crossed with the presence of an instance heart rate, asserting the eligible/absent verdict for
       each — so a future change to eligibility fails a test rather than a review.
2. [ ] Add the structural guard for the copy to `test/cardio_efficiency_drift_test.dart`: the
       observation, the optional sentence and the suggestion compared with the exact strings; the
       span proved to come from the two week constants (changing either constant changes the
       sentence); and a guard that the copy carries no banned word (`fatigue`, `because`, `due to`,
       `cause`, `zone`, `calorie`).
3. [ ] Residue sweep, recorded in the evidence file: `cardio_efficiency_drift.dart` imports only
       `training_load.dart` and `signals.dart`; no file outside
       `lib/core/models/cardio_efficiency_drift.dart`,
       `lib/core/services/signals/cardio_efficiency_drift_signal.dart` and
       `lib/core/services/signals/signal_registry.dart` mentions `cardioEfficiencyDrift` or
       `cardioEfforts`; `stats_progress_service.dart` gains no second distance pairing (one
       `DistancePairing.forEntries` caller is added, not a copy) and no reader of a replaced
       representation. Do **not** introduce the literal `nutritionTrend` in
       `stats_progress_service.dart` — the retired-name sweep (`S-1263`) rejects it.
4. [ ] `docs/signals.md`: add the Cardio Efficiency Drift bullets to `## Registered signals` in the
       style of the existing signals (eligibility, the two windows, the grouping, the drift test,
       the lifting sentence, kind and priority, copy), each bullet naming its test; raise the
       caution count in the caution-order paragraph and add Cardio Efficiency Drift first; raise the
       shipped-signal count in the Protein Consistency bullet. **Then measure the file's size**: it
       stands at 34,099 bytes today and this PR's additions are projected to leave it near 38 KB,
       below the 52,428-byte warning band (0.80 of the indexing contract's 64 KiB ceiling), so no
       split is expected — but if the file would reach **52,428 bytes**, split the registered-signals
       section into a part page under `docs/signals/`, keep `docs/signals.md` as an index, and link
       the part page so the indexing contract's orphan and broken-link tests pass. Record the byte
       count either way.
5. [ ] `docs/stats_screen.md`: add the signal's paragraph as the next in order, in the style of the
       existing ones, naming its test.
6. [ ] `docs/constants_reference.md`: add `## Cardio Efficiency Drift Constants` in the style of
       `## Protein Consistency Constants`, one row per constant with its rule and its test.
7. [ ] `docs/state_management/services_and_utils.md`: document `cardioEfforts` — what it reads, what
       it returns, and that it reuses the cached history read, the shipped distance pairing and the
       instance sensor summaries.
8. [ ] `docs/distance_source.md`: state that an eligible cardio-efficiency effort needs a distance
       whose stored source is not the watch's estimate, and that a correction changes eligibility —
       naming the test that proves it. Touch `docs/training_load.md` only if the lifting sentence's
       per-day comparison needs a sentence there (it reads the Mix payload's own segments and
       baseline segments); if it does, name the test.
9. [ ] Write the doc-claim-to-test table into the evidence file: every behavioural sentence added to
       `docs/` in steps 4–8, with the exact test name that proves it. Any sentence with no test is
       deleted, not kept.
10. [ ] Full `flutter test`, `flutter analyze`, and
        `flutter test test/docs_indexing_contract_test.dart`; paste the summary lines.

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/cardio_efficiency_drift_test.dart test/cardio_efficiency_service_test.dart test/cardio_efficiency_drift_signal_screen_test.dart test/distance_source_test.dart test/signals_framework_test.dart test/docs_indexing_contract_test.dart`;
full `flutter test` with its summary line, compared with Phase 3A's and explained.

**Predicted Files:** `test/cardio_efficiency_drift_test.dart` (EDIT — the copy guard);
`test/cardio_efficiency_service_test.dart` (EDIT — the eligibility table);
`docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`,
`docs/state_management/services_and_utils.md`, `docs/distance_source.md` (EDIT — documentation only);
`docs/training_load.md` (EDIT — only if step 8 needs it).

## Governor actions

The conductor's job, per phase, is compiled here so a non-planner agent can execute it:

1. **Diff vs Predicted Files.** Out-of-bounds files and untouched predicted files are both findings.
   The two guard files are the only pre-existing test files this PR may edit.
2. **Re-run the two registry guards** and the new suites; a phase is not closed on a claim.
3. **Evidence file.** Every Done Criteria run pasted with its summary line, every mutation check with
   its red→green table, the `docs/signals.md` byte count, and the doc-claim-to-test table.
4. **Hive↔Mock parity** on the touched data (S-2512).
5. **Assumption Log adjudication.** Ratify (promote to a new `D-18xx` by supersedure) or revert with
   a remediation sub-phase; a remediation sub-phase must ship a structural guard.
6. **Doc-claim check.** Every doc sentence added names a test that exists in the tree, and no doc
   names a surface this PR does not ship.
7. **Budget.** If the plan grows more than 150 lines past handoff, evidence is leaking into it. If a
   phase uncovers a missing prerequisite (the most likely here: a stored distance source the walk
   cannot see, or a heart rate that lives somewhere other than the instance summary), stop and
   re-plan rather than growing this plan.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/cardio_efficiency_drift.dart` | NEW — the rule, constants, stages and copy |
| `lib/core/services/stats_progress_service.dart` | EDIT — `cardioEfforts` |
| `lib/core/services/signals/cardio_efficiency_drift_signal.dart` | NEW — the adapter |
| `lib/core/services/signals/signal_registry.dart` | EDIT — one line, inserted first |
| `test/cardio_efficiency_drift_test.dart` | NEW |
| `test/cardio_efficiency_service_test.dart` | NEW |
| `test/cardio_efficiency_drift_signal_screen_test.dart` | NEW |
| `test/interference_test.dart` | EDIT — the caution list |
| `test/modality_mix_shift_signal_screen_test.dart` | EDIT — one test name, one list |
| `docs/signals.md` | EDIT — the signal, the caution order, the counts |
| `docs/stats_screen.md` | EDIT — the next signal paragraph |
| `docs/constants_reference.md` | EDIT — the constants section |
| `docs/state_management/services_and_utils.md` | EDIT — the method |
| `docs/distance_source.md` | EDIT — eligibility and correction |
| `docs/training_load.md` | EDIT — only if the per-day lifting comparison is documented there |

No file is deleted. No schema file changes: the SQL files document the stored model, and this PR
stores nothing.

## Progress

One line per item, filled as it lands.

| Phase | Item | Result |
|---|---|---|
| 1 | `test/cardio_efficiency_drift_test.dart` written, red run recorded | done — 14 tests; red run was a compile failure (the rule file did not exist) |
| 1 | Constants, payload and result types | done — D-1813 constants; `kTrainingLoadBaselineWeeks` reused, not redeclared |
| 1 | `cardioEfficiency` and `cardioEfficiencyWindows` | done — `DateTime(y, m, d − n)`, never a `Duration` |
| 1 | `cardioEffortGroups` and `cardioEfficiencyDriftFor` | done — windowed before grouping; anchored, no chaining; largest drift wins |
| 1 | `cardioEfficiencyDrift` and `cardioEfficiencyDriftCopy` | done — per-day 84-vs-28 lift test; span built from the two week constants |
| 1 | Phase 1 suite green, evidence pasted | done — `+64` with the neighbour; full run `+3789 ~1` |
| 1 | Mutation checks 1–2 (strict boundary, chaining) | done — both caught; S-2506 D added because B and C had no bridging duration |
| 2 | Service test written, red run recorded | done — 27 tests; red run was a compile failure (`cardioEfforts` undefined) |
| 2 | `cardioEfforts()` | done — one method; `_loadHistory` + `DistancePairing.forEntries` + instance-scope summary |
| 2 | Phase 2 suites green, evidence pasted | done — new `+27`; neighbours `+128`; full run `+3816 ~1` |
| 2 | Mutation checks 3–4 (estimates, sensor scope) | done — both caught (3: 6 failures; 4: all 27) |
| 3A | Screen test written, red run recorded | done — 13 tests; red run `+2 -5` (five card cases on the missing key, one on the fixture's own count) |
| 3A | The adapter | done — one `evaluate`, one payload, two resistance sums; no repository, no PR API |
| 3A | The registry line, first | done — one line plus its import, alphabetical |
| 3A | Both registry guards extended | done — one id each, one name count raised to `seven` |
| 3A | Phase 3A suites green, evidence pasted | done — new `+13`; guards `+45`; full run `+3829 ~1`; analyze 196, 0 errors |
| 3A | Mutation checks 5–6 (registry order, the lift measure) | done — 5 caught by both guards; 6 not caught by the original fixtures, re-run and **caught** by the resume run's relabelled-payload case (evidence: Mutation check 6, re-run) |
| 3A | Mutation check 6 re-run (resume run) | done — two new screen cases (an unrated history, and a real payload relabelled to `time`); Mock 7 → 9, file 13 → 17; the mutant now fails the second case; line restored |
| 3B | Eligibility structural guard table | not started |
| 3B | Copy structural guard | not started |
| 3B | Residue sweep recorded | not started |
| 3B | `docs/signals.md` (and its size measured) | not started |
| 3B | `docs/stats_screen.md` | not started |
| 3B | `docs/constants_reference.md` | not started |
| 3B | `docs/state_management/services_and_utils.md` | not started |
| 3B | `docs/distance_source.md` (and `training_load.md` if needed) | not started |
| 3B | Doc-claim-to-test table | not started |
| 3B | Final suites green | not started |

## Assumption Log

Executors append here — decision, options considered, choice and why, at most three lines each.
The conductor ratifies (promote to a new `D-18xx` by supersedure) or reverts with a remediation
sub-phase. An empty log after Phase 3A or 3B is itself suspicious.

1. **`CardioEffort` carries no per-effort id, so D-1804's third sort key is inert.** The payload
   has `{exerciseId, exerciseName, start, durationSecs, distanceMetres, avgHeartRateBpm}`. Options:
   add an instance id, or sort by (duration, start). Choice: (duration, start) — within one
   exercise's partition the id key could only order two efforts sharing both a duration and a start,
   and either order yields the same group. Phase 2 can widen the payload if that ever matters.
2. **S-2506 C is read literally.** Both its groups (1800 s and 2700 s) get equal recent and reference
   efficiency, so neither drifts and the rule returns null. Option: give one group a drift and assert
   the other is untouched. Choice: literal — AC-7 is about the two durations never being compared,
   which the group assertions already prove, and S-2506 D now carries the chaining guard.
3. **S-2506 D was added as test design, not from the plan.** Mutation check 2 could not fail against
   B or C: neither fixture has a duration that bridges 480 s to 529 s, so comparing a candidate with
   the previous member rather than the anchor changes nothing there. Choice: add a 500 s bridge so
   the anchored bound is observable. Recorded in the evidence file.
4. **`cardioEfforts` skips an effort whose `exerciseId` is null.** `SegmentEffort.exerciseId` is
   nullable and the payload's `exerciseId` is not. Options: skip, or fall back to the effort id.
   Choice: skip — every other walk in the service does the same (`_sensorFiguresFor`,
   `computeExerciseMetrics`), and an effort with no exercise has no name to show.
5. **The test's `recentSource` applies to the first recent effort only.** The plan's S-2504 variants
   need one estimated effort among four, not four. Choice: the parameter names the first effort's
   source; the other three stay measured. Recorded in the evidence file.
6. **The "session in progress" variant re-seeds the session via `updateSession`, not `deleteSession`.**
   Deleting the session would also remove the effort, its distance and its summary, so the test would
   pass for the wrong reason. Choice: clear `endedAtMs` only, leaving the rest of the fixture intact.
7. **S-2511's "ascending priority" is a plan defect; the layer renders descending.** `resolveSignals`
   sorts a kind by `b.priority.compareTo(a.priority)`, so with Sustained High Load (100) and Cardio
   Efficiency Drift (50) the higher-priority caution renders **first**. The plan's S-2511 wording
   ("ascending priority (Cardio Efficiency Drift first)") is wrong; the test asserts the observed
   order and the evidence file records the arithmetic. No code change.
8. **Mutation check 6 is equivalent through the adapter, and is now killed from outside it.** Passing
   `liftMeasure: MixMeasure.load` unconditionally left the suite green because `_mixPayload` returns
   `const []` for `baselineSegments` whenever the measure is time (D-908), so `liftUsualLoad` is 0 and
   the rule stops at its `liftUsualLoad <= 0` guard before it ever reads the measure. Choice: keep the
   line, and add one screen case that hands the adapter a real payload relabelled to `time` with its
   baseline intact — the one shape the service cannot emit and the only one that fails under the
   mutant. Recorded in the evidence file.
9. **The screen suite's service case asserts 8 efforts, not 12.** The four rated baseline sessions
   are cardio but sit outside `day(42)`, so `cardioEfforts` returns the eight S-2501 efforts. The
   case now also calls the rule directly and asserts `driftPercent == 7`, so it pins the arithmetic
   rather than only the count.

## Feedback

Review findings live in
`2026-10-04-09b-stats-pr9b-cardio-efficiency-drift-plan.review.md` (this folder). This section holds
only the pointer and the fix checklist; when it becomes non-empty the conductor folds it into a new
Iteration block and clears it.

_(empty)_

## Open Items

Each is a defaulted choice, marked **owner to confirm**. None blocks Phase 1.

1. **The noun in the observation.** Default: the exercise's own name followed by `efforts`
   (`your Treadmill Run efforts`), where the pack's example reads `your runs`. The pack's generic
   noun would misname a ride or a row. **Owner to confirm.**
2. **The suggestion text.** Default: `An easier week is one option.` — the pack's sentence with its
   causal clause (`Accumulated fatigue is a common reason for this;`) dropped, because the app
   cannot observe a cause. **Owner to confirm.**
3. **The reference window's edges.** Default: `[day(42), day(28))`, read literally as "28–42 days
   ago", so days 27 down to 14 form the gap. **Owner to confirm.**
4. **The lifting comparison is per day** (the payload's 28-day period against its 84-day baseline),
   pinned in D-1807. **Owner to confirm.**
5. **A distance row with no stored source is eligible** (only the watch's own estimate is excluded).
   **Owner to confirm.**
6. **The ±10% grouping is anchored, not chained**, so a 30-minute and a 45-minute effort can never
   share a group even through a chain of intermediate durations. **Owner to confirm.**
7. **One card, not one per exercise**, with the largest drift reported (D-1806). **Owner to
   confirm.**
8. **The lifting sentence's measure guard — closed in the resume run.** Mutation check 6 left the
   suite green because the mutant is equivalent on every payload the shipped service can emit
   (`baselineSegments` is `const []` in the time measure, so `liftUsualLoad` is 0 and the rule stops
   before it reads the measure). One screen case now relabels a real payload to `time` with its
   baseline intact — the one shape the service cannot emit — and mutation 6 fails it. The choice left
   for the owner: that case reaches the adapter through a `StatsProgressService` subclass overriding
   `computeMixPeriod`, and if that seam is unwelcome the alternative is to accept the rule-level
   S-2509 case alone as the pin. **Owner to confirm.**
