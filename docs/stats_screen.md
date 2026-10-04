# Stats Screen — Feature Documentation

## Overview

`StatsScreen` is a read-only analytics screen: the all-time totals, the work the
current window contains, and how eating is going. It is reached from the
maintenance sheet on the home screen and carries no filters; its controls are
the header icon that opens [Records & Trends](records_and_trends.md) and the
Instruments rows, each an entry point to Exercise Progress.

---

## Navigation Entry Point

```
HomeScreen
  └── Maintenance sheet (swipe up or tap hint)
        └── Stats → StatsScreen
              └── header chart icon → RecordsAndTrendsScreen
```

The chart icon in the screen's header is the only way into
[Records & Trends](records_and_trends.md): this file is the only place in `lib/`
that constructs `RecordsAndTrendsScreen`. Verified by
`test/records_and_trends_screen_test.dart` (the single-entry-point case).

---

## What the Screen Displays

With no completed session in the repository the body is the empty-state card
alone — no Mix layer, no Signals layer, no ALL TIME card, no Instruments list
and no Fuel row, whatever the food log holds. Otherwise it is five blocks in a
fixed order: the [Mix layer](#mix-layer) when the window holds measurable time,
the [Signals layer](#signals-layer) when its gate is met, the
[ALL TIME card](#all-time-card), the [Instruments list](#instruments-list)
when the window holds work, and the [Fuel row](#fuel-row) when recent food
exists. Verified by `test/stats_legacy_removal_test.dart` (`S-1208`),
`test/fuel_row_screen_test.dart` (`S-1112`),
`test/mix_layer_screen_test.dart` (`S-1601`, `S-1610`) and
`test/signals_layer_screen_test.dart` (`S-1701`, `S-1702`).

Nothing else is rendered. The screen holds no chart section, no segmented
control and no block beyond those five: `test/stats_legacy_removal_test.dart`
fails if a removed section's identifier returns to the file (`S-1209`) or if a
chart widget does (`S-1210`), and `test/screen_widget_test.dart` fails if the
Calories / Macros toggle returns. Recent PRs are not among them either: they live
in [Records & Trends](records_and_trends.md), verified by
`test/records_and_trends_screen_test.dart` (`S-913`).

### Mix layer

The Mix layer is the first block in the body, above the ALL TIME card, and there
is exactly one of it. Every figure it draws is one `MixLayerData` supplies; the
arithmetic the layer does itself is presentation only — the flex that turns a
measure into a share of the bar, and the tallest week that sets one scale for
all eight strip columns. Verified by `test/mix_layer_screen_test.dart`
(`S-1601`, `S-1602`, `S-1609`).

**The bar.** One horizontal bar split by modality, largest share first, with a
legend reading each modality's rounded share. The shares are the window's own
measure by modality — its measured time in the time measure, its load in the
load measure. Verified by the same file (`S-1602`, `S-1609`).

**The measure.** The layer reports either the window's training load or its
time, and labels which one it is reporting. Load is shown only when the rated
baseline behind the window is at least `kTrainingLoadMinRatedWeeks` weeks and
the window's unrated share of time is at most `kTrainingLoadMaxUnratedShare`;
otherwise the layer reports time. Verified by the same file (`S-1603`,
`S-1605`, `S-1611`).

**The usual bar.** When the measure is load, a second bar shows the usual mix
the rated baseline establishes, labelled `usual`. Verified by the same file
(`S-1606`, `S-1611`).

**The note and the unrated line.** A note states the baseline the measure rests
on, and an unrated line states how much of the window carried no rating. Both
are absent when they have nothing to report. Verified by the same file
(`S-1605`, `S-1606`, `S-1607`).

**The strip.** Eight weeks of modality-stacked columns, oldest first, with the
current week marked. A week with no work draws its column with no stack segment
in it. Verified by the same file (`S-1608`, `S-1609`).

**The window.** The layer reads the same resolved window as the Instruments
list, and carries its own `StatsWindowChip` naming it — the second of the
screen's two chips. Verified by the same file (`S-1612`, `S-1613`).

**Copy.** The layer renders figures and modality names only: no chart
primitive, no legacy section title, and no estimating or coaching copy.
Verified by the same file (`S-1614`).

**Fit.** The layer fits the narrowest viewport at the largest
non-accessibility text scale and the tallest at the default, with nothing it
draws wider than the card that holds it. Verified by the same file (`S-1615`).

**Freshness.** The layer is refreshed by the screen's one load pass, so it is
never stale relative to the other blocks. Verified by the same file (`S-1616`).

### Signals layer

The Signals layer is the second block in the body, directly under the Mix layer
and above the ALL TIME card, and there is exactly one of it. It renders only
when its gate is met — `signalsGateMet(mix)`, the Mix layer's rated baseline
(`ratedBaselineWeeks`) against `kTrainingLoadMinRatedWeeks` — so a user without
a rated baseline sees the screen without it, and when the gate is unmet the
screen evaluates no signal at all. Verified by `test/signals_layer_screen_test.dart`
(`S-1701`, `S-1702`) and `test/signals_framework_test.dart`
(`D-1006 the quiet-line gate`).

**The cards.** A load shows at most `kSignalMaxCards` cards: one caution above
one positive when both kinds qualify, otherwise the top cards of the surviving
kind. A card is a neutral surface carrying its kind's label and icon, the
observation and, when the signal supplies one, a suggestion. Kind is carried by
the label and the icon, never by a colour, and the layer adds no theme token.
Verified by `test/signals_layer_screen_test.dart` (`S-1704`–`S-1708`) and
`test/signals_framework_test.dart` (`D-1004 at most two cards`,
`D-1005 priority order within a kind`).

**The quiet line.** When the gate is met and no card qualifies, the layer shows
its header and `kSignalQuietLine` and nothing else. The layer is never hidden
once the gate is met, because "nothing to say" is a state the user can see.
Verified by `test/signals_layer_screen_test.dart` (`S-1703`, `S-1708`).

**Dismissing a card.** A card's dismiss control removes the card in the frame of
the tap: the screen resolves the held candidates against the new store with
`signalDismissalsWith`, updates the view, and only then writes the store through
`persistDismissals`, with no reload and no second walk of history. Verified by
`test/signals_layer_screen_test.dart` (`S-1709`) and, for the store write on
both repositories, `test/signals_service_test.dart` (`S-1712 Mock and Hive
parity`).

**The dismissal window.** A dismissal hides its signal for
`kSignalDismissalDays` **local calendar days**, with the dismissal day counted
as day 1; the signal is eligible again the day after the window. Verified by
`test/signals_framework_test.dart` (`S-1710 the 14-day window`, `S-1711 the
daylight-saving boundary`) and `test/signals_layer_screen_test.dart` (`S-1710`,
`S-1711`).

**Not coaching.** A signal is a rule-based observation against the user's own
history, never a rest, deload or recovery instruction, and every observation
carries its own time span. An earlier revision of this document recorded "no
rest / deload / recovery suggestion" as a deliberate non-feature; this section
deliberately replaces that, limited to these signal rules, rather than leaving
it as a gap. Verified by `test/signals_layer_screen_test.dart` (`S-1716`) and
`test/stats_legacy_removal_test.dart` (`S-1210`, no chart primitive).

**The registered signals.** `buildSignalRegistry()` lists seven, described here in the order they shipped rather than in registry order (the registry order is in [Signals](signals.md#selection-and-the-card-cap)). The first is the
Progression Rate: it compares each exercise's own metric across two adjacent
windows and proposes a positive card only when the recent window improves on the
prior one. Its rules — the two windows, what a sample is, the zero fallback, the
three thresholds, the kind and the priority — live in
[Signals](signals.md#registered-signals) and are not restated here. The card's
copy and its suggestion are built by `progressionRateCopy`
(`lib/core/models/progression_rate.dart`) so that the copy and the qualification
test cannot disagree. Verified by `test/progression_rate_signal_screen_test.dart`
(`S-1801` the card end to end, `S-1812` its disappearance when the condition
clears, `S-1813` its dismissal) and, for the definition itself,
`test/progression_rate_test.dart`.

The second is the Modality Mix Shift: it reports a modality the user regularly
trains whose share of their load has fallen to less than half its usual share
over its own `kModalityMixShiftPeriodDays`-day period, and proposes a caution
card. Its rules — the period, the
baseline, the measure gate, the two thresholds, the two sentences and the
suggestion — live in [Signals](signals.md#registered-signals) and are not
restated here. The card's copy is built by `modalityMixShiftCopy`
(`lib/core/models/modality_mix_shift.dart`) so that the copy and the fire test
cannot disagree. Verified by `test/modality_mix_shift_signal_screen_test.dart`
(`S-1909` the card on the layer and its dismissal, `S-1904b` its absence while
the period measures time) and, for the definition itself,
`test/modality_mix_shift_test.dart`.

The third is the Cross-Modality Interference: it reports that the user's next
lifting day after a hard sports session has come in below their own usual level
on the same lifts, at least `kInterferenceMinDippedFollowUps` times in the
pattern window, and proposes a caution card. Its rules — the hard window and its rated population, the follow-up, the
per-exercise dip against its own average, the pattern window and the optional
second sentence — live in [Signals](signals.md#registered-signals) and are not
restated here. The card's copy is built by `crossModalityInterferenceCopy`
(`lib/core/models/interference.dart`) so that the copy and the fire test cannot
disagree. Verified by `test/interference_signal_screen_test.dart` (`S-2013` the
card on the layer and its dismissal) and, for the definition itself,
`test/interference_test.dart`.

The fourth is the Fuel vs Load: it reports that the user's training load rose
over the last three weeks while their average daily intake did not rise with it,
and proposes a caution card. Its rules — the two periods, the six-block
consistency gate, the measure gate, the two thresholds, the copy and the
suggestion — live in [Signals](signals.md#registered-signals) and are not
restated here. The card's copy is built by `fuelVsLoadCopy`
(`lib/core/models/fuel_vs_load.dart`) so that the copy and the fire test cannot
disagree. Verified by `test/fuel_vs_load_signal_screen_test.dart` (`S-2113` the
card on the layer and its dismissal, and the abstention when the repository
holds no food) and, for the definition itself, `test/fuel_vs_load_test.dart`.

The fifth is the Protein Consistency: it reports that the user's protein has
averaged short of the level they usually manage, or short of their own daily
target, over its own `kProteinConsistencyWindowDays`-day window, and proposes a
caution card. Its rules — the window, the logged-days and resistance gates, the
two comparison modes, the per-day target mean, the baseline's consistent weeks,
the threshold, the copy and the priority — live in
[Signals](signals.md#registered-signals) and are not restated here. The card's
copy is built by `proteinConsistencyCopy`
(`lib/core/models/protein_consistency.dart`) so that the copy and the fire test
cannot disagree. Verified by `test/protein_consistency_signal_screen_test.dart`
(`S-2216 the card on the layer the caution card shows with S-2201's copy, the
caution label and its key, below the Mix layer`, `S-2216 the card is dismissible
one tap removes the card in the tap frame, the store holds the id, and the next
open is still quiet`, `S-2207 with no bodyweight drops the g/kg figure and
renders no second line at all`) and, for the definition itself,
`test/protein_consistency_test.dart`.

The sixth is the Sustained High Load: it reports that the user's completed weeks
ran above their usual load with no easier week in the run, and proposes a caution
card. Its rules — the weeks, the twelve-week baseline, the rated-history floor,
the higher-load line, the streak, the measure gate, the history fact, the copy
and the priority — live in [Signals](signals.md#registered-signals) and are not
restated here. The card's copy is built by `sustainedHighLoadCopy`
(`lib/core/models/sustained_high_load.dart`) so that the copy and the fire test
cannot disagree. Verified by `test/sustained_high_load_signal_screen_test.dart`
(`S-2412 the card on the layer` › `the caution card shows with S-2401's copy, the
caution label and its key, below the Mix layer`, `S-2412 the card is dismissible`
› `one tap removes the card in the tap frame, the store holds the id, and the
next open is still quiet`) and, for the definition itself,
`test/sustained_high_load_test.dart`.

The seventh is the Cardio Efficiency Drift: it reports that one cardio exercise's
measured pace at the same average heart rate is worse than it was four to six
weeks ago, over efforts of comparable duration, and proposes a caution card. Its
rules — the two windows, the eligible effort, the duration grouping, the drift
test, the one-card selection, the lifting sentence, the copy and the priority —
live in [Signals](signals.md#registered-signals) and are not restated here. The
card's copy is built by `cardioEfficiencyDriftCopy`
(`lib/core/models/cardio_efficiency_drift.dart`) so that the copy and the fire
test cannot disagree. Verified by
`test/cardio_efficiency_drift_signal_screen_test.dart` (`S-2501 the card on the
layer` › `the caution card shows with S-2501's copy, the caution label and its
key, below the Mix layer`, `S-2511 the card is dismissible` › `one tap removes
the card in the tap frame, the store holds the id, and the next open is still
quiet`) and, for the definition itself,
`test/cardio_efficiency_drift_test.dart`.

### ALL TIME card

One surface holding three pills:

| Pill | Source |
|------|--------|
| **Sessions** | Count of completed sessions across all time |
| **Time** | Total training time, formatted by `OmniDateUtils.formatDurationHoursMins` |
| **Streak** | Current consecutive-day streak via `CalendarState.streakDays` |

The pills and their figures are verified by `test/screen_widget_test.dart`, which
asserts the `STREAK` pill inside the `ALL TIME` card; the `ALL TIME` header is
verified by `test/stats_legacy_removal_test.dart` (`S-1208`).

### Instruments list

The counterpart to the [Selection Window](#selection-window-current-state-window).
It enumerates everything the window contains and shows the figure the window
itself produced: one section per kind of work, and one row per exercise trained
in that window. Sections lead with the biggest block of work — ranked by the days
the window logged of that kind, with `ExerciseSection`'s declared order as the
tiebreak; the rule lives in `computeInstrumentSections`, verified by
`test/instrument_list_service_test.dart` (`S-1006`).

The section headers are `Resistance`, `Cardio`, `Isometric` and `Sports` — the
first of them carries the window chip, so the scope of the readout is never
ambiguous. Verified by `test/instrument_list_screen_test.dart` (`S-1011`).

The list is data-driven rather than fixed. A kind of work with nothing in the
window is absent instead of empty, and the whole list is absent when the window
has no work at all. Verified by `test/instrument_list_screen_test.dart`
(`S-1001`, `S-1012`).

Each row is one exercise: its name, the value the window produced, how that
value moved against the previous window of the same length, and the trend line
behind it. The row's own composition — the value strings, the secondary line and
what it carries — belongs to the widget catalog
([Widget Catalog](widget_catalog.md)); verified by
`test/instrument_list_screen_test.dart` (`S-1001`).

The change readout compares the window's value with the previous window of the
same length. With nothing comparable it reads the no-change dash rather than a
number, and its arrow follows the direction of the raw numeric change — so a
*slower* pace reads as an increase, because pace is stored as time per distance.
A value the service derived from an estimated distance carries the `est.` mark.
Verified by the same file (`S-1001`).

A section past the row cap offers to show the rest; the cap is per section, so a
busy kind of work never hides a quiet one. Verified by the same file (`S-1016`).
The trend line is drawn only when the exercise has at least two points in the
window and takes no space otherwise, verified by the same file (`S-1017`). A row
whose window produced nothing readable still appears, with no trend line at all —
verified by `test/instrument_list_service_test.dart` (`S-1018`).

A row is an entry point to Exercise Progress, the second one in `lib/` alongside
Records & Trends. Verified by `S-1014` in that file and by the entry-point guard
in `test/records_and_trends_screen_test.dart`.

### Fuel row

The Fuel row reports how eating is going over a fixed recent window, and tapping
it opens the full-history nutrition trend screen (see
[Navigation & Screens](navigation_and_screens.md)); verified by
`test/fuel_row_screen_test.dart` (`S-1109`). It is the one block on this screen
whose window is **not** the screen's selected window, so it carries no
`StatsWindowChip` — a chip names the window the user selected for the
Instruments list, and a chip here would tell the user the figures were scoped to
a period they are not. Verified by the same file (`S-1112`).

**Window.** `StatsProgressService.kFuelWindowDays` calendar days ending today,
by calendar arithmetic rather than elapsed hours; the previous range is the same
number of days immediately before it. Verified by the same file (`S-1101`,
`S-1107`).

**Averages divide by logged days.** A logged day is a calendar day with at least
one `ConsumedFood` row. The row averages over the window's logged days only,
and states how many of the window's days were logged, so a day with no food
never reads as a zero and never dilutes the average. Verified by the same file
(`S-1101`, `S-1102`).

**Comparison.** A figure is compared with the user's target for that field when
the target is set, and with the previous range otherwise. A field with no target
is never compared against zero, and a previous range with no food is not a
comparison either. Verified by the same file (`S-1103`, `S-1104`, `S-1108`).

**Training / rest split.** The window's logged days are partitioned into days
with a finished session and days without one — each logged day counts on exactly
one side, and a day that is both is a training day. A session that is still
running does not make its day a training day. A side with no logged day reads a
dash rather than a zero. Verified by the same file (`S-1105`, `S-1106`).

**Absent values.** A figure with nothing to report — no logged day, no previous
range, no target — reads the same no-change dash the Instruments rows use, never
a zero and never a division by zero. The test reads each figure from the value
type and from the rendered row, so the two cannot disagree. Verified by the same
file (`S-1106`, `S-1108`, `S-1111`).

**Visibility.** The row is absent when the last
`StatsProgressService.kFuelVisibilityDays` days hold no logged food, and the
screen's zero-session empty state wins over it: a repository with no completed
session shows the empty state and no Fuel row, whatever the food log holds.
Verified by `test/fuel_row_screen_test.dart` (`S-1107`) and
`test/nutrition_trend_screen_test.dart` (`S-1110(b)`).

**Placement.** The row renders last, below the Instruments list, so the readout
that is not the window's own sits at the bottom of the screen. Verified by the
same file (`S-1112`).

**Formatting.** A kcal or gram figure has no `NativeMetric`, so the row formats
its own strings rather than borrowing `formatNativeChange`'s metric path; it
follows the conventions that formatter sets — whole units, the no-change dash,
and an arrow carrying the raw sign of the change. Verified by the same
file (`S-1101`, `S-1103`).

---

## Effort-Type Keying (Critical Rule)

Which [Instruments](#instruments-list) section an exercise lands in is decided
by `SegmentEffort.effortKind`, **not** by the session's `modality`:

| `effortKind` | Section | The figure its rows carry |
|--------------|---------|---------------------------|
| `set` | Resistance | estimated one-rep max, or reps |
| `timed` | Cardio | pace, or duration |
| `drill` | Isometric | hold |
| `round` | Sports | rounds |

So a `set` effort in a null-modality (Free Training) session is Resistance work,
a `timed` effort inside a `resistance_lifting` session is Cardio work, and a
lifting session with no `set` efforts contributes nothing to Resistance. The
section decides the metric its rows carry, so a row is read without asking what
kind of effort produced it (`ExerciseSection` in
`lib/core/models/exercise_metric.dart`). Verified by
`test/instrument_list_service_test.dart` (`S-1006`, the section contents and
their order) and `test/instrument_list_screen_test.dart` (`S-1001`, the figures
the rows read).

---

## Selection Window (Current-State Window)

The Instruments list **selects** from a current window rather than from all
time, so a lift trained heavily long ago cannot occupy a row while the user's
current focus never appears. **Only the selection and what follows from it is
windowed** — the ALL TIME card and the [Fuel row](#fuel-row) sit outside the
window and read the same figures whatever it is.

### Resolution Rule

`StatsProgressService.resolveWindow(periods, completedSessions, now?)`
runs once per load and returns a `StatsWindow` value. Every windowed
part of the screen shares the one window it returns.

1. **Active training period.** If today is inside any
   `TrainingPeriod` that contains at least one completed session,
   use that period's date range as the window. If multiple periods
   qualify, the one with the latest `startDateMs` wins
   (deterministic tiebreak by id ascending).
2. **Recent training days (fallback).** Otherwise, take the
   `kRecentTrainingDaysWindow` most-recent
   *training days*. A training day is a calendar day with at
   least one completed session; rest days and breaks do not
   shrink the data. The window's `fromMs` is the start-of-day of
   the earliest selected day; `toMs` is end-of-day of today.
3. **No history at all.** When the repository has no completed
   sessions, the recent-days window reports `recentDays: 0`;
   `fromMs`/`toMs` collapse to today, the filter cleanly yields
   zero sessions, and the screen renders its empty state (the
   service does NOT silently widen to all-time).

### What Is (and Isn't) Windowed

| Surface | Windowed? | Notes |
|---------|-----------|-------|
| Mix layer | **Yes** | The bar, the measure, the usual bar, the note, the unrated line and the strip all describe the window — see [Mix layer](#mix-layer) |
| Signals layer | **Yes** | The registered signals are evaluated against the same resolved window and the same load as the Mix layer — see [Signals layer](#signals-layer) |
| Instruments sections and their rows | **Yes** | One row per exercise the window holds work for |
| Each row's figure and change readout | **Yes** | The figure is the window's; the change compares it with the previous window of the same calendar length |
| Each row's trend line | **Yes** | Built from the window's own points |
| ALL TIME card (Sessions / Time / Streak) | No | All-time |
| Fuel row | No | Today-anchored over `kFuelWindowDays`, never the screen's selected window — see [Fuel row](#fuel-row) |
| Exercise Progress (what a row opens) | No | Reads the exercise's full history — see [Records & Trends](records_and_trends.md) |

### On-screen Window Label

The [Mix layer](#mix-layer) and the first Instruments header each carry an
inline chip naming the resolved window — the training period's name when one is
active, otherwise the recent-training-days fallback. The chip exists so the
scope of the readout is never ambiguous, and those two are its only hosts on
this screen: it is one widget, `StatsWindowChip` in
`lib/features/stats/widgets/window_chip.dart`. Verified by
`test/instrument_list_screen_test.dart` (`S-1011`) and
`test/mix_layer_screen_test.dart` (`S-1612`).

---

## Data Loading

All data is loaded in `_loadData()`, called once on first frame via
`addPostFrameCallback`. The screen builds one `CalendarState` and one
`StatsProgressService` over `widget.workoutState.repository`, then asks it for
the all-time totals (`computeTotals()`), the windowed progress data
(`computeProgressData()`), the Fuel summary (`computeFuelSummary()`), the Mix
layer (`computeMixLayer()`) and the Instruments list, which it builds from the
window `computeProgressData()` resolved
(`computeInstrumentSections(window: ...)`). The list is therefore always
scoped to the window the screen is showing, and the Mix layer reads the same
resolved window — verified by `test/mix_layer_screen_test.dart` (`S-1613`,
`S-1616`).

The [Signals layer](#signals-layer) is evaluated in the same pass, against the
same window and the same `now` and over the same `StatsProgressService`
instance, so opening Stats adds no second walk of history. The screen holds the
load's candidates and its dismissal store, so a dismissal re-resolves the held
candidates in memory instead of reloading — verified by
`test/signals_layer_screen_test.dart` (`S-1702`, `S-1709`) and
`test/signals_service_test.dart` (`S-1702 an unmet gate returns nothing and
evaluates nothing`).

`StatsProgressService` is a pure-Dart service — it depends on the
`WorkoutRepository` interface only, not on any concrete implementation.

---

## Key Constants (StatsProgressService)

Values live in `lib/core/services/stats_progress_service.dart` unless the row names another file; this document names them and says what each governs.

| Constant | Meaning |
|----------|---------|
| `kRecentTrainingDaysWindow` | Number of recent training days used for the selection window when no period qualifies |
| `kFuelWindowDays` | The Fuel row's window: the calendar days ending today that its averages cover, and the length of the range it compares against |
| `kFuelVisibilityDays` | How many recent days the Fuel row looks at before it renders at all; wider than the window, so a window with no logged day still shows the row |
| `kInstrumentRowCap` | Max rows an Instruments section shows before offering the rest; declared in `lib/features/stats/widgets/instrument_list.dart` |
| `kMixStripWeeks` | How many weeks the Mix layer's strip covers; declared in `lib/core/models/training_load.dart` |
| `kTrainingLoadMinRatedWeeks` | Rated baseline weeks the Mix layer needs before it reports load rather than time; declared in `lib/core/models/training_load.dart` |
| `kTrainingLoadMaxUnratedShare` | Largest unrated share of the window's time the Mix layer tolerates before it reports time rather than load; declared in `lib/core/models/training_load.dart` |
| `kSignalMaxCards` | Most cards the Signals layer shows at once; declared in `lib/core/models/signals.dart` |
| `kSignalDismissalDays` | Local calendar days a dismissal hides its signal, the dismissal day counted as day 1; declared in `lib/core/models/signals.dart` |

---

## Core Files

| File | Role |
|------|------|
| `lib/features/stats/stats_screen.dart` | Full screen implementation |
| `lib/features/stats/widgets/stats_pill.dart` | The ALL TIME stat pill, shared with Records & Trends |
| `lib/features/stats/widgets/mix_layer.dart` | `MixLayerSection` — the Mix layer: the modality bar, the measure and its label, the usual bar, the note, the unrated line and the week strip |
| `lib/features/stats/widgets/signals_layer.dart` | `SignalsLayerSection` — the Signals layer: the header, the signal cards and the quiet line |
| `lib/core/models/signals.dart` | The Signals value types (`SignalKind`, `SignalCard`, `SignalsData`), the selection, the gate and the dismissal maths; declares `kSignalMaxCards` and `kSignalDismissalDays` |
| `lib/core/services/signals_service.dart` | `SignalsService` — loads the dismissal store, evaluates the registered signals for one load and writes a dismissal back |
| `lib/features/stats/widgets/instrument_list.dart` | The Instruments list: one section per kind of work, capped rows, the expand control; declares `kInstrumentRowCap` |
| `lib/features/stats/widgets/instrument_row.dart` | One Instruments row (name, figure, change chip, trend line) and `InstrumentChangeChip` |
| `lib/features/stats/widgets/instrument_sparkline.dart` | The row's trend line, drawn only when the window holds at least two points |
| `lib/features/stats/widgets/native_value_format.dart` | `formatNativeValue`, `formatNativeChange` and `nativeSecondaryLabel` — the strings a row reads |
| `lib/features/stats/widgets/fuel_section.dart` | `FuelSection` — the Fuel row: the logged-days indicator, the calories and protein figures with their comparison readouts, and the training / rest split |
| `lib/features/stats/widgets/window_chip.dart` | `StatsWindowChip` — the header chip naming the resolved window |
| `lib/features/nutrition/nutrition_trend_screen.dart` | The full-history nutrition trend screen, which the Fuel row opens |
| `lib/core/models/stats_progress.dart` | Value types: `StatsProgressData`, `StatsWindow`, the per-section progress types (`LiftProgress`, `StatsPR`, `TrendPoint`) and the nutrition trend / adherence types (`NutritionTrendPoint`, `NutritionAdherenceTargetPoint`, `NutritionAdherence`) |
| `lib/core/models/exercise_metric.dart` | `ExerciseSection` and the native-value types a row's figure is built from: `NativeMetric`, `NativeValue`, `ExerciseMetricPoint`, `ExerciseMetricSummary`, `StatsTotals` |
| `lib/core/models/instrument_list.dart` | Value types behind the Instruments list: `InstrumentRow`, `InstrumentSectionData` |
| `lib/core/models/fuel_summary.dart` | `FuelSummary` — the Fuel row's value type: the window's logged-day averages, the previous range's, the training / rest split and the targets |
| `lib/core/models/training_load.dart` | `MixLayerData` — the Mix layer's value type: the modality shares, the measure and its label, the usual mix, the baseline note, the unrated line and the strip's weeks; declares `kMixStripWeeks`, `kTrainingLoadMinRatedWeeks` and `kTrainingLoadMaxUnratedShare` |
| `lib/core/services/stats_progress_service.dart` | Pure-Dart computation service: `computeTotals()`, `computeProgressData()` (and the `resolveWindow()` it calls), `computeFuelSummary()`, `computeMixLayer()` and `computeInstrumentSections({required StatsWindow window})` |
| `lib/state/workout/workout_state.dart` | `getAllSessions()`, repository access |
| `lib/state/calendar/calendar_state.dart` | `streakDays` (created internally by `StatsScreen`) |
| `lib/state/settings/settings_state.dart` | Theme colors, weight/distance unit preferences |
| `lib/core/utils/date_utils.dart` | `formatDurationHoursMins()` — formats the ALL TIME Time pill |

---

## Related Documentation

- [Calendar & Periods](calendar_periods.md) — streak calculation details
- [Records & Trends](records_and_trends.md) — the per-exercise screens the header icon opens
- [State Management & Services](state_management.md)
- [Navigation & Screens](navigation_and_screens.md)

---

**Document Version**: 3.1
**Last Updated**: October 2, 2026

---

> **Doc freshness** — Last reconciled against source: 2026-10-01. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
