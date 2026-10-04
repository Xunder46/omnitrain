# Feature: Sustained High Load (Stats PR 9a — pack item 14)

> **Status:** READY (planner) — not started.
> **Next handoff:** @dba (Phase 1).
> **Source of scope:** `docs/plans/2026-09-24-stats-redesign-modality-lens-prompt-pack.md` item 14
> ("Sustained High Load (Caution)"), and the seam in
> `docs/plans/2026-10-04-09-stats-pr9-index.md`.
> **Base:** `develop` at `e86c4ad`. Five signals are registered today, in this order:
> `protein-consistency`, `fuel-vs-load`, `progression-rate`, `modality-mix-shift`,
> `cross-modality-interference`. The Mix layer, the shared load definitions and the signals
> framework (gate, cap, dismissal, selection) are all shipped and unchanged by this plan.
> **Depends on:** nothing unshipped. This plan is independent of 9b (Cardio Efficiency Drift);
> either may land first. If both land, 9b's registry entry goes before this one.
> **Binding conventions:** `docs/global_conventions.md`. `docs/README.md` entries to read before
> Phase 1: `docs/signals.md`, `docs/training_load.md`, `docs/stats_screen.md`,
> `docs/constants_reference.md`, `docs/state_management/services_and_utils.md`,
> `docs/navigation_and_screens.md`, `docs/design_system.md`. Budget:
> `.github/agents/pr_scope_budget.md`.
> **Evidence:** `2026-10-04-09a-stats-pr9a-sustained-high-load-plan.evidence.md` (this folder).
> Review findings: `.review.md`. Neither is written into this file.

## Scope check

| Measure | This plan | Soft | Hard |
|---|---|---|---|
| Plan lines | 756 (measured by reading the file back) | 500 | 800 |
| Phases | 4 (1, 2, 3A, 3B) | >3 | >5 |
| Tracks | 1 (`lib/`, `test/`, `docs/`) | >1 | — |
| Ledger decisions | 15 (D-1701…D-1715) | >20 | — |
| Scenarios | 14 (S-2401…S-2414) | >30 | — |
| Predicted production lines | ~400 | — | ~1,500 |

**Verdict: over the soft budget on two counts, zero hard limits reached, and the split has
already happened at the series level.** Stated plainly rather than argued away:

- **Plan length 756** is above the 500 soft line and 44 below the 800 hard cap. It is
  scenario-bound: 14 fixture-enumerated scenarios with hand-computed weekly loads, exact
  cross-multiplications and pinned copy strings are the whole point of the plan, and trimming them
  pushes ambiguity onto the implementer — the failure mode this plan exists to prevent. The
  sibling signal plan from the previous PR, `2026-10-03-08b-…-plan.md`, is 671 lines for one signal
  with 16 scenarios and was accepted at the same soft signal, so 756 is in line with the
  established size for this series.
- **Four phases** is above the soft 3, but it is the brief's own instruction, not extra scope: the
  brief requires Phase 3 of each plan to be split into part A (card, adapter, registry, guards,
  screen scenarios) and part B (structural guards, residue sweep, docs) *as two agent runs*, so no
  single run carries more than ten concerns. The two parts are one phase's work; the production
  change is the same either way.
- **The split the rule asks for is the seam of this series.** Pack items 14 and 15 are planned as
  two independent PRs (9a and 9b), one signal each, sharing no production file except the registry
  and its two guards. A stricter reading — split 9a again — would have to cut between its data
  layer (Phases 1–2) and its signal surface (Phases 3A–3B), which would put a rule file and its
  adapter in different PRs and leave the first one unshippable; that is the split the brief's
  "one signal = one pure file + one adapter + one registry line" rule exists to avoid. It is not
  proposed. If a reviewer requires it anyway, that is the seam, and the index records it.

## What this PR does

It adds one caution signal: a user who has put together five or more consecutive completed weeks
above their usual weekly training load, with no easier week in the run, sees one neutral card
naming the streak against their own history. It also adds, as a plain fact about their history,
the sentence that they usually took an easier week every *k* weeks — only when that habit is
actually visible in their history.

Three surfaces change:

- a pure definition file (`lib/core/models/sustained_high_load.dart`) holding the constants, the
  stages and the copy;
- one read on `StatsProgressService` (`weeklyLoads`) that turns the cached history into completed
  calendar weeks, plus one preference read (`startOfWeekSetting`);
- a thin adapter and one registry line.

Nothing else changes. No schema, no stored field, no migration, no flag, no watch code, no new
widget, no new token, no framework change. The card is the framework's own neutral caution card:
kind label `Worth a look`, the two-card cap, the fourteen-day dismissal window and the quiet line
are all the shipped framework's behaviour.

## Resolved Decisions (Ledger)

**D-1701 — One definition file, pure Dart.** The rule lives in
`lib/core/models/sustained_high_load.dart`. It imports only `training_load.dart` and
`signals.dart`, holds no clock, no repository, no service and no Flutter, and takes `now` and the
week list as parameters. The adapter is
`lib/core/services/signals/sustained_high_load_signal.dart` and the registry gains one line. The
framework (`lib/core/models/signals.dart`, `lib/core/services/signals/signal.dart`) is not
edited, and `SignalContext` gains no member (D-1714).

**D-1702 — The weekly-load payload.** `lib/core/models/training_load.dart` gains

```dart
class WeeklyLoad {
  final DateTime weekStart;      // local midnight, first day of the week
  final double loadMinutes;      // the week's summed session load
  final bool hasRatedSession;    // a completed rated session starts in it
}
```

`loadMinutes` is the sum of the week's sessions' `sessionLoadMinutes`, so the load definition is
shared with the Mix layer, never re-derived. A session counts in the week its own start falls in,
so no session is counted twice.

**D-1703 — The service read.** `StatsProgressService.weeklyLoads({required DateTime now})`
returns every **completed** calendar week from the week of the earliest completed session through
the last completed week, oldest first, with empty weeks present as
`loadMinutes: 0, hasRatedSession: false`. The week containing `now` is never returned, whatever it
holds. No completed session in history yields an empty list. The method reuses the existing cached
history read — it is a second reader of the same snapshot, not a second walk (D-1714).

**D-1704 — The saved start-of-week, through the service.** The weeks are the user's calendar
weeks: the first day of the week is the saved start-of-week setting. `SettingsState` persists it
under the repository preference key `preferred_start_of_week`, normalizing `sunday`/`sun` to
Sunday and everything else to Monday. The service reads that same key through the repository's
preference API and normalizes identically, exposed as
`Future<String> StatsProgressService.startOfWeekSetting()`. The adapter calls the service; it
never touches the repository.

**D-1705 — The streak is the largest qualifying candidate, each against its own baseline.** Let `W`
be the completed weeks oldest first, `N = W.length`. For each `m` from 1 to `N − 12`, the
**candidate** `m` is the last `m` weeks of `W`, and its **baseline** is the twelve weeks immediately
before the candidate's first week (`W[N−m−12 .. N−m−1]`), so the baseline always lies strictly before
the candidate and the streak can never inflate its own baseline. The candidate's **usual** is the
baseline's sum ÷ 12, an empty week counting as zero — never the mean of the rated weeks only.
`baselineBlockStarts` (the Mix layer's day-anchored seven-day blocks) is **not** used;
`kTrainingLoadBaselineWeeks` (12) is the baseline length, so "at least twelve weeks before" is
implied — a candidate with fewer than twelve earlier weeks does not exist. The weeks inherit the
saved start-of-week from the same `weeklyLoads` list.

**D-1706 — The rated-history floor.** `kSustainedHighLoadMinRatedWeeks = 8`: a candidate qualifies
only when at least eight of its own twelve baseline weeks have `hasRatedSession` true. Fewer → that
candidate does not qualify. The baseline is never widened, extended or re-anchored to reach the
floor.

**D-1707 — Higher, easier, and the qualifying candidate.** On the exact totals, never a rounded
percentage: a **higher-load week** is `loadMinutes * 100 >= usual * kSustainedHighLoadHigherPercent`
(110) — exactly 110% is higher; an **easier week** is
`loadMinutes * 100 <= usual * kSustainedHighLoadEasierPercent` (80) — exactly 80% is easier, and that
boundary is kept for the history fact only (D-1710). A candidate **qualifies** when (a) every one of
its `m` weeks satisfies the higher-load comparison against that candidate's own usual and (b) its
baseline meets the rated floor (D-1706). Because a qualifying week is at least 110% of its usual, an
easier week can never sit inside a qualifying candidate, so the pack's "no easier week among them"
is implied and an easier week simply ends the run at that point (S-2406). A week that is neither —
105% of usual is the pack's own example — is not higher-load, so no candidate containing it
qualifies.

**D-1708 — The streak and the fire floor.** The **streak** is the largest qualifying `m` (D-1707),
`weekCount` 0 when none qualifies. `kSustainedHighLoadMinStreakWeeks = 5`: the card shows when the
streak is five or more weeks. `sustainedHighLoadStreak({required List<WeeklyLoad> weeks})` returns
`{weekCount, firstWeekStart, usualLoadMinutes, ratedBaselineWeeks}`, all read from the winning
candidate, so the copy and the history fact read the same usual; `weekCount` may be 0 and
`firstWeekStart` is null when it is, and the stage applies no floor, so a scenario about the floor or
about a reset asserts on it directly. `sustainedHighLoad({required List<WeeklyLoad> weeks, required
bool mixShowsLoad})` applies the floor itself. A rule-level scenario therefore never has to reach the
card to be checkable.

**D-1709 — The Mix gate is the streak's own period.** The adapter asks
`computeMixPeriod(fromMs: streak.firstWeekStart, toMs: context.now)` — the streak's own weeks, the
period the Mix layer would show for them — and the card fires only when that payload is non-null
and its `measure == MixMeasure.load`. A payload measured in time abstains, so a streak whose weeks
are mostly unrated time never fires. The adapter may skip the query when the run is shorter than
the floor; the rule re-applies the floor regardless, so the optimisation can never change the
outcome.

**D-1710 — The history fact's easier weeks.** The fact is computed over the completed weeks
**strictly before the winning candidate's first week**, against that candidate's own
`usualLoadMinutes` (D-1708). An easier week there is a week with `loadMinutes * 100 <= usual * 80` —
the pack's definition, with no extra rated requirement, so an empty week is an easier week here as
it is anywhere else.

**D-1711 — The recurrence rule.** Gaps are the differences between consecutive easier weeks'
indices in that older span, oldest first. The fact needs at least
`kSustainedHighLoadMinEasierGaps` (2) gaps, **every** gap within
`kSustainedHighLoadGapMinWeeks`..`kSustainedHighLoadGapMaxWeeks` (3..5 inclusive), and reports
`k` = the median of the gaps — the sorted list's element at index `(n - 1) ~/ 2`, so an even count
takes the lower median. Any gap outside 3..5, or fewer than two gaps, omits the sentence entirely
(the card still shows).

**D-1712 — The copy.** Built by `sustainedHighLoadCopy(result)`, with `n` the streak's week count
and `k` the reported interval:

- observation: `You've had <n> consecutive weeks above your usual training load, with no easier week.`
- optional second sentence: `Earlier in your history, you usually had an easier week every <k> weeks.`
- suggestion: `An easier week is one option.`

No causal claim, no recommended amount, no medical language, no load-ratio score. The pack's
longer suggestion (`Accumulated fatigue is a common reason for this; an easier week is one
option.`) asserts a cause the app cannot observe, so the first clause is dropped — owner to
confirm (Open Items 1).

**D-1713 — Kind, priority, and the registry position.** Kind is `SignalKind.caution`. The priority
is `kSustainedHighLoadPriority = 100`, below Protein Consistency (200) and above Cardio Efficiency
Drift (50, PR 9b only). The registry lists cautions in **ascending** priority, so the entry is
inserted **first** in `buildSignalRegistry()`:

```dart
const List<Signal> Function() buildSignalRegistry = _build;
List<Signal> _build() => const [
  SustainedHighLoadSignal(),      // 100
  ProteinConsistencySignal(),     // 200
  FuelVsLoadSignal(),             // 300
  ProgressionRateSignal(),        // 100 (positive)
  ModalityMixShiftSignal(),       // 400
  InterferenceSignal(),           // 500
];
```

The card's label comes from the framework (`kSignalCautionLabel`, `Worth a look`); no colour, token
or widget is added, and the cap (two cards) and the dismissal window (fourteen local calendar
days) stay the framework's.

**D-1714 — One walk, no new framework surface.** `weeklyLoads` is the only history walker; the
rule is pure; the adapter reads only `context.now` and `context.progressService`. Nothing is
cached, stored or persisted, so there is no migration, no legacy path, no flag and no
back-compatibility shim to write. `MockWorkoutRepository` and `HiveWorkoutRepository` both reach
`weeklyLoads` through the same service, so the two stores must produce the same weeks and the same
card value-for-value (repository parity).

**D-1715 — The two registry guards are extended, minimally.** Both whole-list registry guards are
extended in place, in the same style, without reformatting either file:

- `test/interference_test.dart`, test `the caution order holds and the registry is ordered by it`:
  the expected caution list gains `'sustained-high-load'` **first**.
- `test/modality_mix_shift_signal_screen_test.dart`, test `lists exactly the five shipped signals,
  in order`: renamed to `lists exactly the six shipped signals, in order` and the expected id list
  gains `'sustained-high-load'` **first**.

A third representation of the whole list is prose in `docs/signals.md` (the caution-order
paragraph and the Protein Consistency bullet's cross-reference); both are updated in Phase 3B.

## Feature Invariants

Only the invariants that bite here:

- **Repository parity.** Every read this plan adds goes through `StatsProgressService`, so the
  Hive and Mock stores must return identical weekly loads and an identical card. S-2414 proves it
  on both factories.
- **The load definition is shared, never copied.** Weekly load is `sessionLoadMinutes` summed;
  higher/easier are exact integer comparisons on those totals. No second formula for load is
  introduced anywhere.
- **The streak never inflates its own baseline.** Each candidate's baseline is the twelve weeks
  strictly before that candidate's first week (D-1705), and no scenario may read a usual load that
  includes a candidate week.
- **The current, incomplete week is never counted** — not in the streak, not in the baseline, not
  in the fact (D-1703, D-1705).
- **No new user-facing surface beyond one card.** No new screen, no new token, no new label, no new
  setting, and nothing new stored.
- **`SignalContext` gains no member** and the framework files are untouched.

## Requirements

1. A caution card appears when the most recent five or more completed weeks are each at least 110%
   of the usual load of the twelve weeks immediately before that run's first week, and those twelve
   weeks hold at least eight rated weeks.
2. It does not appear below five weeks, below the rated-history floor, or when the Mix layer's
   payload for the streak's own period is measured in time.
3. The card's observation names the streak count; an optional second sentence states the easier-week
   habit when the history shows it at a 3–5 week interval at least twice; the suggestion is
   `An easier week is one option.`
4. The current, incomplete week is never counted.
5. The signal is a caution with priority 100, registered first in the caution order, rendering the
   framework's neutral card.
6. Hive and Mock agree value-for-value.
7. `docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`,
   `docs/state_management/services_and_utils.md` and `docs/training_load.md` describe the shipped
   behaviour, each sentence naming the test that proves it.

## Acceptance Criteria

Each maps to at least one scenario.

| # | Acceptance criterion (pack item 14) | Scenario |
|---|---|---|
| AC-1 | Five completed consecutive weeks each at 115% of usual, with ten weeks of rated history before them, shows "5 consecutive weeks" | S-2401 |
| AC-2 | Four such weeks shows no card | S-2403 |
| AC-3 | A streak containing one week at 105% of usual resets the count at that week | S-2405 |
| AC-4 | The current, incomplete week is never counted | S-2411 |
| AC-5 | The history fact appears only when easier weeks recurred at a 3–5 week interval at least twice; otherwise the sentence is absent | S-2407, S-2408, S-2409 |
| AC-6 | Seven weeks of rated history before the streak shows no card | S-2404 |
| AC-7 | The 110% and 20%-below boundaries are inclusive | S-2402, S-2406 |
| AC-8 | The Mix layer must be showing load for the streak's period | S-2410 |
| AC-9 | The card is a neutral caution: label `Worth a look`, cap, dismissal | S-2412 |
| AC-10 | Hive and Mock agree value-for-value | S-2414 |

## Scenarios

Fixtures are stated as the weeks the rule sees, oldest first, with `L` = load minutes and
`R` = has a rated session. A rated week's load is `minutes × rating`; a week written `240` is a
60-minute session rated 4.

### S-2401: the pack's row — five weeks at 115% shows the card
- **Fixture:** 17 completed weeks, oldest first:
  `W1…W12 = 240,240,240,240,240,240,240,240,240,240,0,0` — ten rated weeks at `L = 240`
  (`60 min × 4`) then two adjacent empty weeks (`L = 0`, `R = false`) — and
  `W13…W17 = 230,230,230,230,230` (five rated weeks at `L = 230`, `46 min × 5`). A current,
  incomplete week holds `L = 300` in the store and is never in the list. The Mix payload for weeks
  13–17 is `measure: MixMeasure.load`.
- **Trigger:** the rule at `now` = the last completed week's end, and the adapter with a stubbed
  Mix payload.
- **Flow:** `sustainedHighLoadStreak` walks the candidates; the baseline stage divides 2400 by 12;
  the composed rule passes the floor and the gate.
- **Expected outcome:** the winning candidate is `m = 5` (`W13…W17`), whose baseline is `W1…W12`:
  `usual = 2400 ÷ 12 = 200`, ten rated baseline weeks (≥ 8), and every week
  `230 * 100 = 23000 >= 200 * 110 = 22000`, so `weekCount == 5` exactly. `m = 6` cannot qualify —
  it would need twelve weeks before `W12` and only eleven exist (`N − 12 = 5`). The card shows,
  observation `You've had 5 consecutive weeks above your usual training load, with no easier week.`,
  no second sentence (the only earlier easier weeks are the two adjacent empty baseline weeks `W11`
  and `W12` → one gap, below the two-gap floor), suggestion `An easier week is one option.`
- **Edge case of:** none (the pack's own row).

### S-2402: the 110% boundary is inclusive
- **Fixture:** S-2401's baseline, `W1…W12 = 240,240,240,240,240,240,240,240,240,240,0,0`; then
  `W13 = 220` (`44 min × 5`, exactly 110% of 200) and `W14…W17 = 230,230,230,230`; and the same
  fixture with `W13 = 219` (`73 min × 3 = 219`, 109.5%).
- **Trigger:** `sustainedHighLoadStreak` on each list.
- **Expected outcome:** with `W13 = 220` the candidate `m = 5` qualifies — `usual = 200`,
  `220 * 100 = 22000 >= 200 * 110 = 22000` — so the streak is 5 and the card shows. With
  `W13 = 219` the candidate `m = 5` fails (`21900 < 22000`), while `m = 4` qualifies: its baseline
  is `W2…W13`, sum `2160 + 219 = 2379`, `usual = 198.25`, and
  `230 * 100 = 23000 >= 198.25 * 110 = 21807.5`; so the streak is 4 and the composed rule returns
  `null`.
- **Edge case of:** S-2401.

### S-2403: four weeks is not five
- **Fixture:** S-2401's baseline (`W1…W12 =
  240,240,240,240,240,240,240,240,240,240,0,0`), then `W13…W16 = 230,230,230,230` (four rated
  weeks, `46 min × 5`) — sixteen weeks in all, so the longest candidate is `m = 4` (`N − 12 = 4`).
- **Trigger:** `sustainedHighLoad` with `mixShowsLoad: true`.
- **Expected outcome:** `null` — no card. The winning candidate is `m = 4`, baseline `W1…W12`,
  `usual = 2400 ÷ 12 = 200`, so `sustainedHighLoadStreak` reports `weekCount == 4` and the assertion
  does not depend on the card.
- **Edge case of:** S-2401.

### S-2404: the rated-history floor, and the twelve-week requirement
- **Fixture A:** `W1…W12 = 240,240,240,240,240,240,240,240,0,0,0,0` (eight rated weeks at
  `L = 240`, then four empty), then `W13…W17 = 184,184,184,184,184` (`46 min × 4`, exactly 115% of
  the `usual = 1920 ÷ 12 = 160`). **Fixture B:** `W1…W12 =
  240,240,240,240,240,240,240,0,0,0,0,0` (seven rated, five empty), then
  `W13…W17 = 154,154,154,154,154` (`77 min × 2`, exactly 110% of the `usual = 1680 ÷ 12 = 140`).
  **Fixture C:** S-2401's first eleven weeks
  (`W1…W11 = 240,240,240,240,240,240,240,240,240,240,0`) followed by
  `W12…W16 = 230,230,230,230,230` — only eleven completed weeks before the five `230` weeks.
- **Trigger:** `sustainedHighLoad(weeks: …, mixShowsLoad: true)` on each.
- **Expected outcome:** A shows the card with `n = 5`: the winning candidate `m = 5` has baseline
  `W1…W12`, `usual = 160`, eight rated baseline weeks (the floor exactly), and
  `184 * 100 = 18400 >= 160 * 110 = 17600`. B and C return `null`: in B every candidate's baseline
  holds at most seven rated weeks, and in C every candidate's baseline includes at least one `230`
  week, pushing its usual above `230 ÷ 1.1 = 209.09`, so no candidate qualifies (`weekCount == 0` in
  both).
- **Edge case of:** S-2401 (AC-6).

### S-2405: a 105% week resets the count at that week
- **Fixture:** S-2401's baseline, `W1…W12 =
  240,240,240,240,240,240,240,240,240,240,0,0`; then `W13…W18 = 230,230,210,230,230,230`, where
  `W15 = 210` is `42 min × 5` = 105% of the `m = 6` usual (200). Eighteen weeks in all
  (`N − 12 = 6`).
- **Trigger:** `sustainedHighLoadStreak` and then the composed rule.
- **Expected outcome:** candidates `m = 6`, `m = 5` and `m = 4` all contain `W15 = 210`, and
  `210 * 100 = 21000` is below 110% of each of their usuals (`200`, `2390 ÷ 12 = 199.17`,
  `2380 ÷ 12 = 198.33`), so all three fail. `m = 3` (candidate `W16…W18 = 230,230,230`) qualifies:
  baseline `W4…W15`, sum `1680 + 230 + 230 + 210 = 2350`, `usual = 195.83`,
  `230 * 100 = 23000 >= 195.83 * 110 = 21541.67`, ten rated baseline weeks. The streak is therefore
  3 (`weekCount == 3`), so the composed rule returns `null`.
- **Edge case of:** S-2401 (AC-3).

### S-2406: the easier boundary, and an ordinary week that is neither
- **Fixture:** S-2401's baseline (`W1…W12 =
  240,240,240,240,240,240,240,240,240,240,0,0`), then `W13…W18 = 160,230,230,230,230,230`, where
  `W13 = 160` is `32 min × 5` = exactly 80% of 200; and the same list with `W13 = 162`
  (`54 min × 3`).
- **Trigger:** `sustainedHighLoadStreak`, then the composed rule.
- **Expected outcome:** with `W13 = 160` the candidate `m = 6` fails
  (`160 * 100 = 16000 < 200 * 110 = 22000`) and `m = 5` qualifies — baseline `W2…W13`, sum
  `2160 + 160 = 2320`, `usual = 193.33`, `230 * 100 = 23000 >= 21266.67` — so the streak is 5 and
  the card shows. With `W13 = 162` the same holds (`m = 6` fails, `m = 5` qualifies with
  `usual = 2322 ÷ 12 = 193.5`), but 162 is **not** an easier week
  (`162 * 100 = 16200 > 200 * 80 = 16000`), so it can never contribute to the history fact.
- **Edge case of:** S-2401 (AC-7).

### S-2407: the history fact shows the interval
- **Fixture:** 29 completed weeks, oldest first:
  `W1…W12 = 200,250,250,200,250,250,250,250,200,250,250,200` (all rated; the `200` weeks are
  easier against the `usual = 250` that follows), `W13…W24 = 250` (twelve rated weeks at `250`),
  `W25…W29 = 280,280,280,280,280` (five rated weeks at `280`, `56 min × 5`). Easier weeks sit at
  `W1`, `W4`, `W9`, `W12` → gaps `3, 5, 3`.
- **Trigger:** `sustainedHighLoad(weeks: …, mixShowsLoad: true)`.
- **Expected outcome:** the winning candidate is `m = 5` (`W25…W29`): baseline `W13…W24`, sum
  `12 × 250 = 3000`, `usual = 250`, `280 * 100 = 28000 >= 250 * 110 = 27500`, twelve rated weeks.
  Every longer candidate contains at least one `250` week against a usual above `250 ÷ 1.1`, so
  `m = 6` upward all fail (`m = 6`: baseline `W12…W23` sums `200 + 11 × 250 = 2950`,
  `usual = 245.83`, `25000 < 27041.67`). The card shows with `n = 5` **and** the second sentence
  `Earlier in your history, you usually had an easier week every 3 weeks.` (three gaps, all inside
  3..5, median of `[3, 3, 5]` = 3).
- **Edge case of:** S-2401 (AC-5).

### S-2408: the even-count median is the lower one
- **Fixture:** S-2407 with the `W12` easier week removed: `W1…W12 =
  200,250,250,200,250,250,250,250,200,250,250,250` (easier weeks at `W1`, `W4`, `W9` → gaps
  `3, 5`), then the same `W13…W24 = 250` and `W25…W29 = 280,280,280,280,280`.
- **Trigger:** `sustainedHighLoad(weeks: …, mixShowsLoad: true)`.
- **Expected outcome:** the winning candidate is `m = 5` as in S-2407 (`usual = 250`,
  `weekCount == 5`) and the card shows with the sentence naming **3** weeks — the lower median of
  the two gaps `[3, 5]`, the sorted list's element at index `(2 − 1) ~/ 2 = 0` — not 4.
- **Edge case of:** S-2407.

### S-2409: the fact is absent when the habit is not there
- **Fixture A:** S-2401 (`W1…W12 = 240,240,240,240,240,240,240,240,240,240,0,0`, then
  `W13…W17 = 230`; the two empty baseline weeks give one gap). **Fixture B:** S-2407 with the `W9`
  easier week moved to `W10` — `W1…W12 = 200,250,250,200,250,250,250,250,250,200,250,250`, easier
  weeks at `W1`, `W4`, `W10`, gaps `3, 6` — before the same `W13…W24 = 250` and `W25…W29 = 280`.
  **Fixture C:** S-2407 with no easier week at all (`W1…W24 = 250`, then `W25…W29 = 280`).
- **Trigger:** `sustainedHighLoad(weeks: …, mixShowsLoad: true)`.
- **Expected outcome:** each has the winning candidate `m = 5` with `weekCount == 5` — A at
  `usual = 200`, B and C at `usual = 250` — so each shows the card with `n = 5` and **no** second
  sentence: A has only one gap, B has a gap of 6 outside 3..5, C has no easier week at all.
- **Edge case of:** S-2407 (AC-5).

### S-2410: the Mix gate
- **Fixture:** S-2401's weeks with (a) a payload whose `measure == MixMeasure.load`, (b) the same
  payload with `measure == MixMeasure.time`, (c) a null payload. For the adapter-level version of
  (b): the five streak weeks each hold one 60-minute rated session (`L = 240`) **and** one
  300-minute unrated session, so the period's unrated time share is `300 ÷ 360 = 0.83`, above
  `kTrainingLoadMaxUnratedShare` (0.25), and `computeMixPeriod` returns `time`.
- **Trigger:** `sustainedHighLoad(weeks: …, mixShowsLoad: …)` for the rule; the adapter against the
  seeded service for (b).
- **Expected outcome:** (a) shows the card; (b) and (c) show nothing.
- **Edge case of:** S-2401 (AC-8).

### S-2411: the incomplete week is never counted
- **Fixture:** the store holds S-2401's seventeen weeks plus a current, incomplete week whose
  rated session alone would put it at `L = 300`; and a variant where the current week holds nothing
  at all.
- **Trigger:** `StatsProgressService.weeklyLoads(now: …)` then the rule.
- **Expected outcome:** both produce the identical list of seventeen completed weeks and the
  identical card; the last element's `weekStart` is the week before `now`'s week.
- **Edge case of:** S-2401 (AC-4).

### S-2412: the card on the Stats screen
- **Fixture:** S-2401 seeded through the Mock store, opened on `StatsScreen` with the real
  registry, plus a variant seeding a qualifying Protein Consistency card as well.
- **Trigger:** the screen builds, then the dismissal control for the card is tapped.
- **Expected outcome:** one card with key `signal_card_sustained-high-load`, kind label
  `Worth a look`, the observation above and the suggestion above; with two qualifying cautions the
  cap still renders two cards, in ascending priority (Sustained High Load first); after the tap the
  card is gone and `signal_dismiss_<id>`-style state is stored, and it stays gone after a reopen.
  The dismissal tap is Mock-only (a Hive write inside the widget test's fake-async zone never
  drains).
- **Edge case of:** S-2401 (AC-9).

### S-2413: the saved start-of-week moves the boundaries
- **Fixture:** sessions placed on a Sunday and on a Monday either side of a week boundary, seeded
  twice: once with `preferred_start_of_week = 'monday'` and once with `'sunday'` (and once with
  `'sun'`, which normalizes to Sunday).
- **Trigger:** `StatsProgressService.weeklyLoads(now: …)` and `startOfWeekSetting()`.
- **Expected outcome:** the Sunday session lands in different weeks for the two settings; the
  Sunday and Monday variants agree; and the value the service reads is the value `SettingsState`
  writes for the same key (proved in one test that writes through `SettingsState` and reads through
  the service).
- **Edge case of:** none.

### S-2414: the two stores agree
- **Fixture:** S-2401 and S-2407 seeded through both `harnessFactories`.
- **Trigger:** `weeklyLoads` and the composed rule on each repository.
- **Expected outcome:** identical week lists (start, load, rated flag, in order) and identical card
  copy on Hive and Mock.
- **Edge case of:** S-2401 (AC-10).

## Iteration 1

Phase order is 1 → 2 → 3A → 3B. Phase 2 needs Phase 1's `WeeklyLoad` type; Phase 3A needs Phase 2's
`weeklyLoads`; Phase 3B needs Phase 3A's card. Nothing here depends on 9b. Commands in Done
Criteria run through the repo's gateway wrapper in Copilot sessions.

### Phase 1: the pure rule and its constants (@dba)

1. [ ] Write `test/sustained_high_load_test.dart` **first**, importing
       `package:omnitrain/core/models/sustained_high_load.dart` and `…/training_load.dart`, with the
       S-2402, S-2403, S-2404, S-2405, S-2406, S-2407, S-2408, S-2409 fixtures and a
       `the constant contracts` group asserting every `kSustainedHighLoad…` value. Run it: it must
       fail to compile. Record that red run in the evidence file.
2. [ ] Add `WeeklyLoad` (D-1702) to `lib/core/models/training_load.dart` beside `MixWeek`, with a
       doc comment naming the week's own start and the shared `sessionLoadMinutes` definition. Add
       its contract test to `test/training_load_test.dart` (a week's load is the sum of its
       sessions' load; an empty week is `0.0` and not rated).
3. [ ] Create `lib/core/models/sustained_high_load.dart` with the constants of D-1706…D-1713:
       `kSustainedHighLoadPriority = 100`, `kSustainedHighLoadMinStreakWeeks = 5`,
       `kSustainedHighLoadMinRatedWeeks = 8`, `kSustainedHighLoadHigherPercent = 110`,
       `kSustainedHighLoadEasierPercent = 80`, `kSustainedHighLoadMinEasierGaps = 2`,
       `kSustainedHighLoadGapMinWeeks = 3`, `kSustainedHighLoadGapMaxWeeks = 5`. Reuse
       `kTrainingLoadBaselineWeeks` (12) from `training_load.dart`; do not declare a second
       twelve-week constant.
4. [ ] Add the result types `SustainedHighLoadStreak{firstWeekStart, weekCount, usualLoadMinutes,
       ratedBaselineWeeks}`, `SustainedHighLoadBaseline{usualLoadMinutes, ratedWeeks}`,
       `SustainedHighLoad{streakWeeks, easierGapWeeks}` and
       `SustainedHighLoadCopy{observation, suggestion}`.
5. [ ] Add the separately callable stages: `sustainedHighLoadStreak({required weeks})` (the largest
       qualifying candidate of D-1705/D-1707, returning `{weekCount, firstWeekStart,
       usualLoadMinutes, ratedBaselineWeeks}` — all from the winning candidate, `weekCount` possibly
       0), `sustainedHighLoadBaseline({required weeks, required int beforeIndex})` (the helper that
       computes one candidate's twelve entries before `beforeIndex`, their pooled mean and their
       rated count, or null when fewer than twelve exist), and
       `sustainedHighLoadEasierGapWeeks({required weeks, required int beforeIndex,
       required double usual})` (the median interval, or null when the rule of D-1711 is not met).
6. [ ] Add the composed `sustainedHighLoad({required List<WeeklyLoad> weeks, required bool
       mixShowsLoad})` — gate, baseline, floor, streak, fact — and `sustainedHighLoadCopy(result)`
       with the exact strings of D-1712 (the second sentence present only when the fact fired).
7. [ ] Green: run the Phase 1 suites and paste the summary lines into the evidence file.
8. [ ] **Mutation check 1** (must fail if the boundary is wrong): change
       `kSustainedHighLoadHigherPercent` comparison from `>=` to `>` in the higher-load test, run
       S-2402's exact-110% case, confirm it fails, revert. **Mutation check 2**: swap the median's
       `(n - 1) ~/ 2` for `n ~/ 2`, run S-2408, confirm it fails (it would report 5 instead of 3),
       revert. Record both in the evidence file.

**Done Criteria** (run until green): `flutter analyze` (0 errors);
`flutter test test/sustained_high_load_test.dart test/training_load_test.dart`;
full `flutter test` with its summary line pasted into the evidence file.

**Predicted Files:** `lib/core/models/sustained_high_load.dart` (NEW);
`lib/core/models/training_load.dart` (EDIT — `WeeklyLoad` only); `test/sustained_high_load_test.dart`
(NEW); `test/training_load_test.dart` (EDIT — the `WeeklyLoad` contract).

### Phase 2: the service read (@dba)

1. [ ] Write `test/sustained_high_load_service_test.dart` **first**, plain `test()` (never
       `testWidgets`), over `test/helpers/repository_harness.dart` with **both** `harnessFactories`
       where the assertion is store-independent: S-2401's seventeen weeks plus a strong current
       week, S-2411, S-2413 and S-2414. Run it: it must fail (the method does not exist). Record
       the red run.
2. [ ] Add `Future<String> startOfWeekSetting()` to `lib/core/services/stats_progress_service.dart`:
       read `preferred_start_of_week` through the repository preference API and normalize
       `'sunday'`/`'sun'` → `'sunday'`, everything else → `'monday'`, matching `SettingsState`.
3. [ ] Add `Future<List<WeeklyLoad>> weeklyLoads({required DateTime now})` to the same file: reuse
       `_loadHistory` and the existing session split; walk the completed sessions once; bucket each
       by the week of its start (`OmniDateUtils.startOfWeek`); return oldest first, from the
       earliest completed session's week to the last completed week, with empty weeks present. Do
       **not** add a second history walk and do not touch the sensor or PR paths.
4. [ ] Green on the new suite, then on the neighbouring service suites, then the full suite; paste
       all three summary lines.
5. [ ] **Mutation check 3** (must fail if the incomplete week leaks in): make the last week's
       boundary include the week containing `now`, run S-2411, confirm it fails, revert.
       **Mutation check 4**: drop the empty weeks from the returned list, run S-2401's service case,
       confirm the card's `usual` changes and the test fails, revert. Record both.

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/sustained_high_load_service_test.dart test/training_load_test.dart
test/mix_layer_service_test.dart test/modality_mix_period_service_test.dart test/stats_progress_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/stats_progress_service.dart` (EDIT — two methods, nothing
else); `test/sustained_high_load_service_test.dart` (NEW).

### Phase 3A: the card, the registry and the guards (@developer)

Run this phase in one pass; it is deliberately small so the adapter, the registry and the two
guards land together and no half-registered state is left behind.

1. [ ] Write `test/sustained_high_load_signal_screen_test.dart` **first**, Mock-first
       (`--plain-name "Mock"`), following `test/fuel_vs_load_signal_screen_test.dart`: a tall
       viewport, `_day(daysAgo)`/`_at(daysAgo, hour)` local helpers, a local `_seedSession` that
       writes `TrainingSession(…, sessionFeeling: rating, …)` because the harness's own seeder
       cannot set a rating, S-2401, S-2403, S-2410 and S-2412, and the dismissal tap in a
       Mock-only case. Run it: it must fail. Record the red run.
2. [ ] Create `lib/core/services/signals/sustained_high_load_signal.dart` after
       `fuel_vs_load_signal.dart`: private `const String _kSustainedHighLoadTitle = 'Sustained high
       load';`, `id => 'sustained-high-load'`, `kind => SignalKind.caution`, `priority =>
       kSustainedHighLoadPriority`, and an `evaluate` that reads `context.now`, calls
       `context.progressService.weeklyLoads(now: …)`, derives the streak, asks
       `computeMixPeriod(fromMs: streak.firstWeekStart, toMs: context.now)` when the run reaches the
       floor, calls the rule and builds the card from `sustainedHighLoadCopy`. It reads no
       repository and no PR API.
3. [ ] Insert `SustainedHighLoadSignal()` **first** in `buildSignalRegistry()` in
       `lib/core/services/signals/signal_registry.dart` (D-1713) — one line, no reformat.
4. [ ] Extend `test/interference_test.dart`'s `the caution order holds and the registry is ordered
       by it`: add `'sustained-high-load'` first to its expected caution list. No reformat.
5. [ ] Extend `test/modality_mix_shift_signal_screen_test.dart`'s
       `lists exactly the five shipped signals, in order`: rename it to `lists exactly the six
       shipped signals, in order` and add `'sustained-high-load'` first to its expected list. No
       reformat.
6. [ ] Green: the new screen suite (Mock-first), then the two guard suites, then the full suite.
       Paste the summary lines.
7. [ ] **Mutation check 5** (must fail if the registry position is wrong): move the new entry to the
       end of the registry, run both guards, confirm both fail, revert. **Mutation check 6**: pass
       `mixShowsLoad: true` unconditionally in the adapter, run S-2410(b), confirm the card wrongly
       appears, revert. Record both.

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/sustained_high_load_signal_screen_test.dart --plain-name "Mock"`;
`flutter test test/interference_test.dart test/modality_mix_shift_signal_screen_test.dart`;
`flutter test test/sustained_high_load_test.dart test/sustained_high_load_service_test.dart`;
full `flutter test` with its summary line.

**Predicted Files:** `lib/core/services/signals/sustained_high_load_signal.dart` (NEW);
`lib/core/services/signals/signal_registry.dart` (EDIT — one line);
`test/sustained_high_load_signal_screen_test.dart` (NEW); `test/interference_test.dart` (EDIT — one
list); `test/modality_mix_shift_signal_screen_test.dart` (EDIT — one name, one list).

### Phase 3B: structural guards, the residue sweep and the docs (@developer)

1. [ ] Add the structural guard for the priority order to `test/sustained_high_load_test.dart`: the
       caution constants, read off the registry itself, are strictly ascending — so a future signal
       added in the wrong position fails a test rather than a review.
2. [ ] Add the structural guard for the copy: the observation, the optional sentence and the
       suggestion are compared with the exact strings, so no rewording can land silently; and a
       guard that the copy contains no amount, no percentage and no causal word from the banned set
       (`fatigue`, `because`, `due to`, `cause`).
3. [ ] Residue sweep, recorded in the evidence file: `lib/core/models/sustained_high_load.dart`
       imports only `training_load.dart` and `signals.dart`; no file outside
       `lib/core/models/sustained_high_load.dart`, `lib/core/services/signals/sustained_high_load_signal.dart`
       and `lib/core/services/signals/signal_registry.dart` mentions `sustainedHighLoad`; and
       `stats_progress_service.dart` gains no reader of the replaced representation. Do **not**
       introduce the literal `nutritionTrend` anywhere in `stats_progress_service.dart` — the
       retired-name sweep (`S-1263`) rejects it.
4. [ ] `docs/signals.md`: add the Sustained High Load bullets to `## Registered signals` in the
       style of the existing signals (definitions, the baseline, the floor, the fact, kind and
       priority, copy), each bullet naming its test; change `Four cautions are registered today`
       to `Five cautions…` and add Sustained High Load first in the caution-order paragraph; change
       the Protein Consistency bullet's `the five shipped signals, in order` to `the six shipped
       signals, in order`. Keep the file below 52,428 bytes (the indexing contract's warning band)
       — measure it and record the byte count in the evidence file.
5. [ ] `docs/stats_screen.md`: add the signal's paragraph as the sixth, in the style of the
       existing five, naming its test.
6. [ ] `docs/constants_reference.md`: add `## Sustained High Load Constants` in the style of
       `## Protein Consistency Constants`, one row per constant with its rule and its test.
7. [ ] `docs/state_management/services_and_utils.md`: document `weeklyLoads` and
       `startOfWeekSetting` — what they read, what they return, and that they reuse the cached
       history read.
8. [ ] `docs/training_load.md`: document `WeeklyLoad` and the shared weekly-load definition, and
       state that the weekly baseline is twelve *calendar* weeks taken from the same list (not
       `baselineBlockStarts`).
9. [ ] Write the doc-claim-to-test table into the evidence file: every behavioural sentence added
       to `docs/` in steps 4–8, with the exact test name that proves it. Any sentence with no test
       is deleted, not kept.
10. [ ] Full `flutter test`, `flutter analyze`, and
        `flutter test test/docs_indexing_contract_test.dart`; paste the summary lines.

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/sustained_high_load_test.dart test/sustained_high_load_service_test.dart test/sustained_high_load_signal_screen_test.dart test/signals_framework_test.dart test/signals_service_test.dart test/docs_indexing_contract_test.dart`;
full `flutter test` with its summary line, compared with Phase 3A's and explained.

**Predicted Files:** `test/sustained_high_load_test.dart` (EDIT — the two guards);
`docs/signals.md`, `docs/stats_screen.md`, `docs/constants_reference.md`,
`docs/state_management/services_and_utils.md`, `docs/training_load.md` (EDIT — documentation only).

## Governor actions

The conductor's job, per phase, is compiled here so a non-planner agent can execute it:

1. **Diff vs Predicted Files.** Out-of-bounds files and untouched predicted files are both
   findings. The two guard files are the only pre-existing test files this PR may edit.
2. **Re-run the two registry guards** and the new suites; a phase is not closed on a claim.
3. **Evidence file.** Every Done Criteria run pasted with its summary line, every mutation check
   with its red→green table, the `docs/signals.md` byte count, and the doc-claim-to-test table.
4. **Hive↔Mock parity** on the touched data (S-2414) — the standing invariant.
5. **Assumption Log adjudication.** Ratify (promote to a new `D-17xx` by supersedure) or revert with
   a remediation sub-phase; a remediation sub-phase must ship a structural guard.
6. **Doc-claim check.** Every doc sentence added names a test that exists in the tree, and no doc
   names a surface this PR does not ship.
7. **Budget.** If the plan grows more than 150 lines past handoff, evidence is leaking into it —
   move it to the evidence file. If a phase uncovers a missing prerequisite, a new model, or a
   second round of review would be needed, stop and re-plan rather than growing this plan.

## Files Affected (whole feature)

| File | Change |
|---|---|
| `lib/core/models/sustained_high_load.dart` | NEW — the rule, constants, stages and copy |
| `lib/core/models/training_load.dart` | EDIT — `WeeklyLoad` |
| `lib/core/services/stats_progress_service.dart` | EDIT — `weeklyLoads`, `startOfWeekSetting` |
| `lib/core/services/signals/sustained_high_load_signal.dart` | NEW — the adapter |
| `lib/core/services/signals/signal_registry.dart` | EDIT — one line, inserted first |
| `test/sustained_high_load_test.dart` | NEW |
| `test/sustained_high_load_service_test.dart` | NEW |
| `test/sustained_high_load_signal_screen_test.dart` | NEW |
| `test/training_load_test.dart` | EDIT — the `WeeklyLoad` contract |
| `test/interference_test.dart` | EDIT — the caution list |
| `test/modality_mix_shift_signal_screen_test.dart` | EDIT — one test name, one list |
| `docs/signals.md` | EDIT — the signal, the caution order, the count |
| `docs/stats_screen.md` | EDIT — the sixth signal |
| `docs/constants_reference.md` | EDIT — the constants section |
| `docs/state_management/services_and_utils.md` | EDIT — the two methods |
| `docs/training_load.md` | EDIT — `WeeklyLoad`, the weekly baseline |

No file is deleted. No schema file changes: the SQL files document the stored model, and this PR
stores nothing.

## Progress

One line per item, filled as it lands.

| Phase | Item | Result |
|---|---|---|
| 1 | `test/sustained_high_load_test.dart` written, red run recorded | not started |
| 1 | `WeeklyLoad` in `training_load.dart` + contract test | not started |
| 1 | `sustained_high_load.dart`: constants, types, stages | not started |
| 1 | `sustainedHighLoad` and `sustainedHighLoadCopy` | not started |
| 1 | Phase 1 suites green, evidence pasted | not started |
| 1 | Mutation checks 1–2 (boundary, median) | not started |
| 2 | Service test written, red run recorded | not started |
| 2 | `startOfWeekSetting()` | not started |
| 2 | `weeklyLoads()` | not started |
| 2 | Phase 2 suites green, evidence pasted | not started |
| 2 | Mutation checks 3–4 (incomplete week, empty weeks) | not started |
| 3A | Screen test written, red run recorded | not started |
| 3A | The adapter | not started |
| 3A | The registry line, first | not started |
| 3A | Guard 1 extended (`interference_test.dart`) | not started |
| 3A | Guard 2 extended and renamed (`modality_mix_shift_signal_screen_test.dart`) | not started |
| 3A | Phase 3A suites green, evidence pasted | not started |
| 3A | Mutation checks 5–6 (registry order, the gate) | not started |
| 3B | Priority-order structural guard | not started |
| 3B | Copy structural guard | not started |
| 3B | Residue sweep recorded | not started |
| 3B | `docs/signals.md` | not started |
| 3B | `docs/stats_screen.md` | not started |
| 3B | `docs/constants_reference.md` | not started |
| 3B | `docs/state_management/services_and_utils.md` | not started |
| 3B | `docs/training_load.md` | not started |
| 3B | Doc-claim-to-test table | not started |
| 3B | Final suites green | not started |

## Assumption Log

Executors append here — decision, options considered, choice and why, at most three lines each.
The conductor ratifies (promote to a new `D-17xx` by supersedure) or reverts with a remediation
sub-phase. An empty log after Phase 3A or 3B is itself suspicious.

_(empty)_

## Feedback

Review findings live in
`2026-10-04-09a-stats-pr9a-sustained-high-load-plan.review.md` (this folder). This section holds
only the pointer and the fix checklist; when it becomes non-empty the conductor folds it into a
new Iteration block and clears it.

_(empty)_

## Open Items

Each is a defaulted choice, marked **owner to confirm**. None blocks Phase 1.

1. **The suggestion text.** Default: `An easier week is one option.` — the pack's sentence with its
   causal clause (`Accumulated fatigue is a common reason for this;`) dropped, because the app
   cannot observe a cause. **Owner to confirm** whether the longer sentence is wanted.
2. **The easier-week requirement in the history fact.** Default: the pack's own definition, so an
   empty week counts as an easier week there (D-1710). The alternative — requiring a rated session
   — would show the sentence less often. **Owner to confirm.**
3. **"At least twice"** is read as at least two gaps between consecutive easier weeks (three easier
   weeks), not two easier weeks. **Owner to confirm.**
4. **The gap interval** is the difference between consecutive easier weeks' indices, so easier
   weeks three weeks apart report `every 3 weeks`. **Owner to confirm.**
5. **The 8-week rated floor** is read as eight of the twelve baseline weeks carrying a rated
   session, not eight rated weeks anywhere in history. **Owner to confirm.**
6. **The card is silent about how much easier** an easier week should be, and carries no
   percentage. **Owner to confirm.**
7. **The candidate-by-candidate baseline.** Default: each candidate is measured against the twelve
   weeks immediately before it (D-1705), so the usual moves with the candidate. The alternative — a
   fixed baseline taken once from the twelve weeks before the last five weeks — would let a long run
   hide a week that is not high against a later usual. **Owner to confirm.**
