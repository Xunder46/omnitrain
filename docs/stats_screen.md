# Stats Screen — Feature Documentation

## Overview

`StatsScreen` is a read-only analytics screen: the work the last four weeks
contain, and how eating is going. It is reached from the
maintenance sheet on the home screen and carries no filters; its controls are
the header icon that opens [Records & Trends](records_and_trends.md) and the
Instruments rows, each an entry point to Exercise Progress.

The screen takes one optional `bool showPrimerHelp` (default `false`) that turns
on the first-use explanation surfaces — the header "?" and the empty card's
`How Stats works` button. It deliberately holds no `StatsPrimerState`: both
surfaces host the sheet with a null `onDismiss`, so the screen has no reference
through which it could mark the seen flag. Verified by
`test/stats_primer_screen_test.dart` (`S-2703: with showPrimerHelp omitted the
Stats primer feature is off` › `no help action, no empty-state button and the
chart action still renders`) and `test/stats_primer_contract_test.dart` (`the
Stats screen holds no StatsPrimerState`).

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

When `showPrimerHelp` is true the header carries a second action, the "?"
(tooltip `About Stats`), placed before the chart icon so the chart icon stays
rightmost. It opens the [primer sheet](#primer-sheet) and never marks the seen
flag: the screen holds no `StatsPrimerState`, so it has no reference through
which it could mark it. Verified by `test/stats_primer_contract_test.dart` (`the
Stats screen holds no StatsPrimerState`); the coexistence of the two header
actions is verified by `test/stats_primer_screen_test.dart` (`S-2708: the "?"
and the chart icon coexist` › `the chart icon stays the only way into Records &
Trends`).

---

## First-Use Empty State

With no completed session the body is the shared empty state — an
`OmniEmptyState` (compact) in an `OmniSurface`. Its title
`No sessions yet` and body `Complete your first session to see stats here.` are
kept verbatim; when `showPrimerHelp` is true the card adds three short lines
about what will appear and a `How Stats works` button that opens the
[primer sheet](#primer-sheet) without marking the seen flag. Verified by
`test/stats_primer_screen_test.dart` (`S-2707: the first-use card explains what
will appear` › `the empty state keeps its title and body and adds the
explanation and the button`; `the empty-state button opens the sheet without
marking it seen`), and the taller card is asserted to fit a small viewport by
`S-2714: the taller first-use card fits a small viewport` › `the card lays out
at 320x568 without an overflow`. Both tests also assert the composition with
`find.byType(OmniEmptyState)`, so the shared piece itself is pinned, not just
the copy.

---

## Primer Sheet

`StatsPrimerSheet` (`lib/features/stats/widgets/stats_primer_sheet.dart`) is a
presentation-only sheet: three labelled blocks — what the page shows, the
Signals cards, and the chart icon — over one `Got it` CTA. It imports no state
class and reads no repository; the host owns the seen flag. The sheet scrolls
when it is taller than the screen, so it stays usable at large text scale on a
short phone. Verified by `test/stats_primer_screen_test.dart` (`S-2719: the
sheet fits a small viewport` › `the sheet lays out at 320x568 without an
overflow`).

The sheet auto-opens once per install on the **first Stats tap from Home**,
hosted by `HomeScreen` exactly as the Daily Nutrition primer is: the sheet is
shown over Home, and Stats is pushed when it closes. The seen flag is marked
when the sheet's `showModalBottomSheet` future completes — by the `Got it` CTA,
a swipe-down, or a tap on the modal barrier — which is the one place Stats
deliberately differs from the Nutrition primer, whose `onDismiss` fires only
from its `Got it` button. The flag is persisted under
`StatsPrimerState.preferenceKey` (`primer_seen_stats`), distinct from the
Nutrition primer's key, and hydrated before the first frame. Reopening from the
"?" or the empty-card button never marks it. Verified by
`test/stats_primer_home_test.dart` (`S-2701: the first Stats tap from Home shows
the primer once` › `an unseen state shows the sheet on the first tap and marks
it seen when the sheet closes`; `S-2716: a second Stats tap pushes Stats
directly` › `a seen state pushes Stats with no sheet`; `S-2718: dismissing the
auto-shown sheet by an outside tap still marks it seen` › `the flag is false
while the sheet shows and true after an outside tap`), by
`test/stats_primer_state_test.dart` (`S-2705: the seen flag survives a restart` ›
`a marked-seen Stats primer is seen again after a Hive restart`; `S-2706: the
two primer keys are independent` › `marking the Stats primer seen leaves the
Nutrition primer unseen`), and by `test/stats_primer_contract_test.dart` (`the
Stats screen holds no StatsPrimerState`).

---

## What the Screen Displays

With no completed session in the repository the body is the shared empty state
alone — no Mix layer, no Signals layer, no Instruments list, no Fuel row and no Weight block,
whatever the food log holds. Otherwise it is five blocks in a fixed order: the
[Mix layer](#mix-layer) when the window holds measurable time, or its
empty-window card when the window holds no session but history does, the
[Signals layer](#signals-layer) whenever a signal speaks or its gate is met —
otherwise, when the gate is unmet but the Mix layer exists, the locked
Signals line in its slot —
the [Instruments list](#instruments-list) when the window holds work, the
[Fuel row](#fuel-row) when recent food exists, and the
[Weight block](#weight-block). Verified by
`test/stats_legacy_removal_test.dart` (`S-1208`),
`test/fuel_row_screen_test.dart` (`S-1112`),
`test/mix_layer_screen_test.dart` (`S-1601`, `S-1610`),
`test/signals_layer_screen_test.dart` (`S-1701`, `S-1702`, `S-4002`,
group `S-17505 a signal that needs no ratings speaks while the gate is
unmet`),
`test/stats_four_week_window_screen_test.dart` (group `S-17007 after a break
the card is one line` › `the empty window draws one line and no bar, strip or
list`) and `test/stats_instruments_horizon_screen_test.dart` (group `S-17307
ALL TIME is on Records & Trends only` › `Stats shows no all-time block, and
its blocks keep their order`).

Every block's heading sits above its content, on the page background and never
inside its card. Verified by `test/stats_heading_consistency_screen_test.dart`
(group `S-18701 no Stats heading sits inside a card` › `F-A: every
OmniCardHeader is on the background, above its block's first content`).

Nothing else is rendered. The screen holds no chart section, no segmented
control and no block beyond those five: `test/stats_legacy_removal_test.dart`
fails if a removed section's identifier returns to the file (`S-1209`) or if a
chart widget does (`S-1210`), and `test/screen_widget_test.dart` fails if the
Calories / Macros toggle returns. Recent PRs are not among them either: they live
in [Records & Trends](records_and_trends.md), verified by
`test/records_and_trends_screen_test.dart` (`S-913`).

### Mix layer

The Mix layer is the first block in the body, and there is exactly one of it. Every figure it draws is one `MixLayerData` supplies; the
arithmetic the layer does itself is presentation only — the flex that turns a
measure into a share of the bar, and the tallest week that sets one scale for
all eight strip columns. Verified by `test/mix_layer_screen_test.dart`
(`S-1601`, `S-1602`, `S-1609`).

**The explainer.**
One sentence at the top of the card, under the `TRAINING MIX` header above it, names the window
and says what the bars are: under the load measure it reads
`Last 4 weeks. Your training split by how hard each session felt.`, and under
the time measure it reads `Last 4 weeks. Your training split by time spent.` —
the only place the measure is named in words, and the old `by load` / `by time`
labels are gone. Verified by the same file (`S-3201 one sentence says what the
split is`, `S-3201 the twin: the time measure reads in its own words`) and by
`test/stats_mix_horizon_screen_test.dart` (groups `S-17301 the time-measure
explainer opens with the window` › `the explainer names the window and the
chip is gone` and `S-17302 the load-measure explainer opens with the window`
› `the explainer names the window and the measure`). The `TRAINING MIX`
heading sits above the card, never inside it; verified by
`test/stats_heading_consistency_screen_test.dart` (group `S-18701 no Stats
heading sits inside a card`).

**The bar.** One horizontal bar split by modality, largest share first. The
shares are the window's own measure by modality — its measured time in the time
measure, its load in the load measure. Verified by the same file (`S-1602`,
`S-1609`).

**The legend.** Under the bar, one coloured dot and the modality's rounded
share for each modality that has a share. A 0% modality is left out of the
legend, while the bar still draws its sliver and still names it in its
semantics. Verified by the same file (`S-3203 the legend drops the 0% entries
and gives each one a dot`).

**The measure.** The layer reports either the window's training load or its
time. Load is shown only when at least `kTrainingLoadMinRatedWeeks` of the
last 12 seven-day weeks — today's included — hold at least one completed
session with a rating, and the window's unrated share of time is at most
`kTrainingLoadMaxUnratedShare`; otherwise the layer reports time. Verified by
the same file (`S-1603`, `S-1605`, `S-1611`) and by
`test/stats_rated_weeks_service_test.dart` (`S-17101 rated sessions in four
different current weeks count 4`, `S-17103 an unrated session does not count
a week`, `S-17104 the 84th day back is outside the 12 weeks`) and
`test/stats_rated_weeks_screen_test.dart` (group `S-17108 four current weeks
unlock Signals` › `the load measure shows and the Signals layer renders`).

**The usual bar.** When the measure is load, a second bar shows the usual mix
the 12 baseline blocks before the window establish: the first bar is labelled
`In this window` and the second `Your usual`, and neither label renders when
there is no usual bar. The load measure can show while those baseline blocks
hold no rated work — the rated weeks are counted up to today, not before the
window — and the usual bar then simply does not draw. Verified by the same
file (`S-3202 the two bars are labelled`, `S-3202 the twin: no usual bar, no
bar labels`, `S-1606`, `S-1611`) and by
`test/stats_rated_weeks_screen_test.dart` (group `S-17108 four current weeks
unlock Signals` › `the load measure shows and the Signals layer renders`).

**The note.** Under the time measure, while fewer than
`kTrainingLoadMinRatedWeeks` of the last 12 seven-day weeks — today's
included — are rated, a note reads `Showing time for now. Effort appears once
4 weeks are rated (N of 4 so far).`. With 4 or more rated weeks the strip can
still show time, when more than a quarter of the window's time is unrated; the
note then reads `Showing time for now. Effort needs most of the last 4 weeks rated.`
Under the load measure no note renders. Verified by
`test/mix_layer_screen_test.dart` (`S-3204 the baseline note says what happens
and when`, `S-3204 the twin: no rated week at all`, `S-3204 the load measure
explains nothing`, and group `S-18601 the baseline note when effort is hidden
by unrated time`).

**The strip.** Titled `Last 8 weeks, week by week`: eight weeks of
modality-stacked columns, oldest first, with the current week marked. A week
with no work draws a 2 dp stub at the bottom of its column instead of a stack
segment, so all eight columns stay visible. A caption under the columns reads
`7 weeks ago` on the left and `This week so far` on the right, and each end
shrinks to fit large text instead of overflowing the card. When none of the
eight weeks has any training, the strip is replaced by one line:
`No training in the last 8 weeks.` with `Last session: <date>.` when the
payload knows the last completed session's day. Verified by the same file
(`S-3206 the strip is titled, captioned and shows eight columns`, `S-3206 the
twin: an all-empty strip keeps its one line`, `S-1608`, `S-4005`, `S-4006`,
`S-4015`, `S-4014`, and `Guard — the caption fits 390x844 dp and 2.0 text
scale`) and by `test/stats_mix_horizon_screen_test.dart` (group `S-17303 the
strip is titled by its horizon` › `the strip title leads with the horizon`).

**The window.** The layer reads the screen's one window — the four weeks
ending today (`StatsProgressService.statsWindow`) — the same window the
Instruments list reads, and names it in the first words of its explainer.
Verified by the same file (groups `S-1612 the window is named in words, not by
a chip` and `S-1613 the layer reads the same window as the list`) and by
`test/stats_four_week_window_screen_test.dart` (group `S-17004 a period no
longer scopes Stats` › `the bar reads the 28-day window and the explainer
never names the period`).

**The empty window.** When the window holds no completed session but a
completed session exists anywhere in history, the layer is not a card of
nothing: it draws the header and one line (key `mix_window_empty`) —
`No training in the last 4 weeks. Last session: <date>.` — and no bar, no
legend and no strip. The Instruments list is absent with it, because the
window holds no work. A window that holds a session with zero time is still a
null payload, so no Mix layer renders at all; a repository with no completed
session shows the screen's first-use empty state instead. The period signals'
`computeMixPeriod` still returns null for an empty period — the empty payload
is the window's alone. Verified by
`test/stats_four_week_window_screen_test.dart` (group `S-17007 after a break
the card is one line` › `the empty window draws one line and no bar, strip or
list`), `test/stats_mix_horizon_screen_test.dart` (group `S-17312 the
empty-window card has no chip` › `the empty line stands alone under the
header`) and `test/stats_four_week_window_service_test.dart` (groups `Mock —
four-week window` and `Hive — four-week window`: `S-17006 an empty window with
history returns the empty payload`, `S-17008 no completed session at all
returns null`, `S-17009 a zero-duration session inside the window returns
null`, `S-17010 computeMixPeriod stays null for an empty period`).

**Copy.** The layer's words are the explainer, the bar labels, the notes and
the strip's title and caption: no chart primitive, no legacy section title, and
no estimating or coaching copy.
Verified by the same file (`S-1614`).

**Fit.** The layer fits the narrowest viewport at the largest
non-accessibility text scale and the tallest at the default, with nothing it
draws wider than the card that holds it. Verified by the same file (`S-1615`,
`S-3208 the whole card fits every viewport and text scale`).

**Freshness.** The layer is refreshed by the screen's one load pass, so it is
never stale relative to the other blocks. Verified by the same file (`S-1616`).

### Signals layer

The Signals layer is the second block in the body, directly under the Mix layer
and above the Instruments list, and there is exactly one of it. Its gate, cards,
quiet line, waiting lines, dismissal and load behaviour are described in
[Stats Screen — Signals Layer](stats_screen/signals_layer.md); the framework is in
[Signals](signals.md) and each signal's definition in
[Registered Signals](signals_registered.md).

### Instruments list

The counterpart to the [Selection Window](#selection-window-current-state-window).
It enumerates everything the window contains and shows the figure the window
itself produced: one section per kind of work, and one row per exercise trained
in that window. Sections lead with the biggest block of work — ranked by the days
the window logged of that kind, with `ExerciseSection`'s declared order as the
tiebreak; the rule lives in `computeInstrumentSections`, verified by
`test/instrument_list_service_test.dart` (`S-1006`).

The section headers are `RESISTANCE`, `CARDIO`, `ISOMETRIC` and `SPORTS`, and
the caption under the first one names the window. Verified by
`test/instrument_list_screen_test.dart` (group `S-1011` › `the Instruments
list is the four-week window, named in words, whatever periods exist`) and by
`test/stats_heading_consistency_screen_test.dart` (group `S-18703 every Stats
heading is uppercase`).

The list is data-driven rather than fixed. A kind of work with nothing in the
window is absent instead of empty, and the whole list is absent when the window
has no work at all. Verified by `test/instrument_list_screen_test.dart`
(`S-1001`, `S-1012`).

Each row is one exercise: its name, the value the window produced, how that
value moved against the previous window of the same length, and the trend line
behind it. The row's own composition — the value strings, the secondary line and
what it carries — belongs to the widget catalog
([Widget Catalog](widget_catalog.md)); verified by
`test/instrument_list_screen_test.dart`
(`S-1001`).

One muted caption sits under the first section header and nowhere else, and
says what the numbers mean: `Last 4 weeks. Change is against the 4 weeks before.` — the window in words, then the window's own calendar span the change is measured against. The span is named in whole weeks when the window is a multiple of seven days (`1 week`, `4 weeks`) and in days otherwise (`1 day`, `10 days`).
Verified by `test/instrument_list_screen_test.dart` (group `S-4010 the caption
states the window's real span` › `the caption names the 4 weeks the window
holds and the 4 weeks before it`, group `S-4017 the caption counts the
comparison` › `the number is the previous range's span, and the caption names
the four weeks`, group `S-4018 one caption, under the first header`),
`test/stats_instruments_horizon_screen_test.dart` (group `S-17304 the caption
is one plain line` › `the caption names the window and its previous span, and
no chip names it`, and group `S-17306 the caption counts the window's own
span` › `a ten-day window reads the ten days before it`, `a seven-day window
reads the one week before it`, `a one-day window reads the one day before it`)
and `test/stats_window_day_count_test.dart` (group `S-4011
StatsWindow.dayCount is the previous range's own length`).

Each row's secondary line names what its figure is: `Est. 1RM` for the
estimated one-rep-max row, `Best set` for the reps row, `Total time` for the
cardio duration row and `Best pace` for the pace row; isometric and sports rows
keep their own wording. Verified by `test/instrument_list_screen_test.dart`
(`S-4012`, `S-4019`) and `test/instrument_change_format_test.dart`
(`nativePrimaryLabel`).

The change readout compares the window's value with the previous window of the
same length. With nothing comparable it reads `new` rather than a number, and
a change of exactly zero reads the dash. Its arrow follows the direction of the
raw numeric change — so a
*slower* pace reads as an increase, because pace is stored as time per distance.
A value the service derived from an estimated distance carries the `est.` mark.
Verified by `test/stats_instruments_horizon_screen_test.dart` (group `S-17305
a row with nothing to compare against reads new` › `the three rows read new,
the dash, and an arrow figure`) and `test/instrument_list_screen_test.dart`
(group `S-1001` › `the change chip compares against the previous range, and
reads new when there is nothing to compare`).

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
`test/fuel_row_screen_test.dart` (`S-1109`). It is the one block on this screen with a window of its own — the
`kFuelWindowDays` finished days ending yesterday, not the screen's four-week
window — and its first line reads `Last 7 days`. Verified by
`test/fuel_row_screen_test.dart` (group `S-1112` › `the Fuel card has no
window chip and its first line reads Last 7 days, with the window named in
words`) and `test/stats_fuel_horizon_screen_test.dart` (groups `S-17310
averages shown` › `S-17310 the Fuel card opens with its horizon` and `S-17310
too few logged days` › `S-17310 the Fuel card opens with its horizon`, and
group `S-17311` › `S-17311 the horizon is built from the window constant`).

**Window.** `StatsProgressService.kFuelWindowDays` calendar days ending
**yesterday**, by calendar arithmetic rather than elapsed hours; today is in
neither the window nor the previous range, and the previous range is the same
number of days immediately before the window. Verified by
`test/fuel_summary_window_test.dart` (`S-17201 window is the 7 finished days
ending yesterday`, `S-17201 twin previous range keeps its oldest day, d14`) and
`test/fuel_row_screen_test.dart` (`S-1101`, `S-1107`).

**Averages divide by logged days.** A logged day is a calendar day with at least
one `ConsumedFood` row. The row averages over the window's logged days only,
and states how many of the window's days were logged, so a day with no food
never reads as a zero and never dilutes the average. Verified by the same file
(`S-1101`, `S-1102`).

**Not enough logged days.** When the window holds fewer than
`kFuelMinLoggedDays` logged days (`FuelSummary.showsAverages`, declared in
`lib/core/models/fuel_summary.dart`), the row draws one sentence (key
`fuel_not_enough_days`) — `Log food on $kFuelMinLoggedDays days to see a weekly
average` — instead of the four figures,
their comparisons and the two split lines; the logged-days line always draws,
and the model still carries the averages. Verified by
`test/fuel_section_widget_test.dart` (`S-17205 Fuel with 2 logged days says so
in words and draws no figures`, `S-17205 Fuel with 3 logged days draws the
averages and no sentence`) and `test/fuel_row_screen_test.dart` (group
`S-1259/S-1260/S-1261` › group `a row with fewer than three logged days`).

**Comparison.** A figure is compared with the user's target for that field when
the target is set, and with the previous range otherwise. A field with no target
is never compared against zero, and a previous range with no food is not a
comparison either. Verified by the same file (`S-1103`, `S-1104`, `S-1108`).
A missing comparison reads muted; protein whose average reads below a set
protein target is the one comparison in the error colour; every other
comparison, target or previous-range, up or down, is neutral. Verified by
`test/fuel_section_widget_test.dart` (`S-17206 protein under its target is the
error colour; the other comparisons are neutral`, `S-17206 protein over its
target is neutral even though it rose`, `S-17206 protein with no target is
neutral even when it fell`, `S-17206 a comparison too small to survive rounding
reads as absent and muted`).

**Carbs and fat.** A second row reports the carbs and fat averages beside the
calorie and protein ones — four figures in two rows, each carrying its own
label — under the same comparison rule. Carbs are total carbs. Verified by
`test/fuel_row_screen_test.dart` (group `Fuel row — carbs and fat (plan 80)`:
`S-14040`, `S-14041`, `S-14043`).

**Training / rest split.** The window's logged days are partitioned into days
with a finished session and days without one — each logged day counts on exactly
one side, and a day that is both is a training day. The split covers the same
`kFuelWindowDays` finished days ending yesterday, so it no longer changes during
the day. A session that is still running does not make its day a training day.
A side with no logged day reads a dash rather than a zero. Verified by the same
file (`S-1105`, `S-1106`) and by `test/fuel_summary_window_test.dart`
(`S-17203 a session started today does not make a training day`).

**Absent values.** A figure with nothing to report — no logged day, no previous
range, no target — reads a dash; the Instruments rows read new instead, never
a zero and never a division by zero. The test reads each figure from the value
type and from the rendered row, so the two cannot disagree. Verified by the same
file (`S-1106`, `S-1108`, `S-1111`).

**Visibility.** The row is absent when the last
`StatsProgressService.kFuelVisibilityDays` days, today included, hold no logged
food, and the screen's zero-session empty state wins over it: a repository with
no completed session shows the empty state and no Fuel row, whatever the food
log holds. Verified by `test/fuel_row_screen_test.dart` (`S-1107`),
`test/fuel_summary_window_test.dart` (`S-17204 visibility: today alone shows,
d14 hides, d13 is previous`) and `test/nutrition_trend_screen_test.dart`
(`S-1110(b)`).

**Placement.** The row renders below the Instruments list; the Weight block
sits below it when it shows (`S-17705`). Verified by the same file
(`S-1112`).

**Formatting.** A kcal or gram figure has no `NativeMetric`, so the row formats
its own strings rather than borrowing `formatNativeChange`'s metric path; it
follows the conventions that formatter sets — whole units, the dash a zero
change reads, and an arrow carrying the raw sign of the change. Verified by the same
file (`S-1101`, `S-1103`).

### Weight block

The body weight and its four-week change, only with a completed session and
when the weigh-in rule is met, with no setting to hide it; the rule is in
[Profile & Measurements](profile_and_measurements.md#the-weight-line-on-stats).
Verified by `test/weight_trend_screen_test.dart` (`S-17705`).

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

The Instruments list **selects** from a fixed recent window rather than from
all time, so a lift trained heavily long ago cannot occupy a row while the
user's current focus never appears. The window is the same for every windowed
block on the screen; the [Fuel row](#fuel-row) sits
outside it and reads its own figures.

### Resolution Rule

`StatsProgressService.statsWindow({DateTime? now})` returns the screen's one
window, and every windowed part of the screen shares it.

1. **The four calendar weeks ending today.** `kStatsWindowDays` (28) days:
   `fromMs` is the start of the day 27 days back, `toMs` is the end of today,
   by calendar arithmetic, so a DST shift does not shrink it. The label is
   `Last 4 weeks` and `isPeriodScoped` is false. Verified by
   `test/stats_four_week_window_service_test.dart` (groups `Mock — four-week
   window` and `Hive — four-week window`: `S-17001 statsWindow is the 28
   calendar days ending today`, `S-17002 statsWindow spans a DST
   spring-forward in calendar days`, `S-17003 the day-28 session is outside
   the window`).
2. **No training period plays a part.** A period never scopes the Stats
   screen; periods keep their meaning on the calendar and period screens.
   Verified by `test/stats_four_week_window_screen_test.dart` (group
   `S-17004 a period no longer scopes Stats` › `the bar reads the 28-day
   window and the explainer never names the period`) and
   `test/instrument_list_screen_test.dart` (group `S-1011` › `the Instruments
   list is the four-week window, named in words, whatever periods exist`).
3. **No history at all.** The window is the same 28 days whether or not
   history exists; with no completed session the filter cleanly yields zero
   sessions and the screen renders its first-use empty state (the service
   does NOT silently widen to all-time). Verified by
   `test/stats_legacy_removal_test.dart` (groups `S-1208 behavioural guard —
   Mock` and `S-1208 behavioural guard — Hive` › group `zero completed
   sessions` › `the empty state renders and no legacy surface does`).

### What Is (and Isn't) Windowed

| Surface | Windowed? | Notes |
|---------|-----------|-------|
| Mix layer | **Yes** | The bar, the measure, the usual bar, the note, the strip and the empty-window card all describe the window — see [Mix layer](#mix-layer) |
| Signals layer | **Yes** | The registered signals are evaluated against the same four-week window and the same load as the Mix layer — see [Signals layer](#signals-layer) |
| Instruments sections and their rows | **Yes** | One row per exercise the window holds work for |
| Each row's figure and change readout | **Yes** | The figure is the window's; the change compares it with the previous window of the same length |
| Each row's trend line | **Yes** | Built from the window's own points |
| Fuel row | No | Anchored on the `kFuelWindowDays` finished days ending yesterday, its own window rather than the screen's four-week one — see [Fuel row](#fuel-row) |
| Exercise Progress (what a row opens) | No | Reads the exercise's full history — see [Records & Trends](records_and_trends.md) |

### Naming the Window

Each block names its own window in words, once, at the top of the card: the
[Mix layer](#mix-layer) opens its explainer with the window's label, the
Instruments list says it in the caption under the first header, and the Fuel
row's first line reads `Last 7 days`. Verified by
`test/mix_layer_screen_test.dart` (group `S-1612 the window is named in words,
not by a chip` › `the explainer and the Instruments caption each start with
the window, and no chip renders anywhere`),
`test/stats_instruments_horizon_screen_test.dart` (group `S-17304 the caption
is one plain line` › `the caption names the window and its previous span, and
no chip names it`) and `test/stats_fuel_horizon_screen_test.dart` (group
`S-17310 averages shown` › `S-17310 the Fuel card opens with its horizon`).

---

## Data Loading

All data is loaded in `_loadData()`, called once on first frame via
`addPostFrameCallback`. The screen builds one `StatsProgressService` over
`widget.workoutState.repository`, takes one
`now`, and asks the service whether any session exists (`computeTotals()`), the
Fuel summary (`computeFuelSummary()`), the Mix layer (`computeMixLayer()`) and
the Instruments list, which it builds from the one window `statsWindow(now:)`
returns (`computeInstrumentSections(window: ...)`). The list is therefore
always scoped to the four-week window the screen is showing, and the Mix layer
reads the same window — verified by `test/mix_layer_screen_test.dart`
(`S-1613`, `S-1616`) and by `test/stats_four_week_window_screen_test.dart`
(group `S-17005 the Instruments compare with the 28 days before` › `the
caption names the window length, not the period`).

The [Signals layer](#signals-layer) is evaluated in the same pass, against the
same window and the same `now` and over the same `StatsProgressService`
instance, so opening Stats adds no second walk of history; a gate-unmet screen
evaluates only the signals that need no ratings and shows the locked line when
none of them speaks. The screen holds the
load's candidates and its dismissal store, so a dismissal re-resolves the held
candidates in memory instead of reloading — verified by
`test/signals_layer_screen_test.dart` (`S-1702`, `S-4002`, `S-1709`) and
`test/signals_service_test.dart` (`S-17501 an unmet gate evaluates only the
signals that need no rated weeks`).

`StatsProgressService` is a pure-Dart service — it depends on the
`WorkoutRepository` interface only, not on any concrete implementation.

When that one load read throws, the body is `LoadFailureView` — the failure
line `Could not load your stats.` and a full-width `Try again` button that
re-runs `_loadData()` — instead of the empty state, so a failed load never
reads as "no data". Verified by `test/stats_load_failure_test.dart` (group
`S-2704: a failed load is not an empty state`: `Stats: the failure text and
Try again replace the empty state`).

---

## Key Constants (StatsProgressService)

Values live in `lib/core/services/stats_progress_service.dart` unless the row names another file; this document names them and says what each governs.

| Constant | Meaning |
|----------|---------|
| `kStatsWindowDays` | Calendar days the Stats screen describes: the four weeks ending today, the window `statsWindow()` returns |
| `kRecentTrainingDaysWindow` | Number of recent training days Records & Trends' lift selection falls back to when no period qualifies; the Stats screen no longer uses it |
| `kFuelWindowDays` | The Fuel row's window: the finished calendar days ending yesterday that its averages cover; the previous range it compares against is the same length immediately before |
| `kFuelVisibilityDays` | How many recent days, today included, the Fuel row looks at before it renders at all; wider than the window, so a window with no logged day still shows the row |
| `kInstrumentRowCap` | Max rows an Instruments section shows before offering the rest; declared in `lib/features/stats/widgets/instrument_list.dart` |
| `kMixStripWeeks` | How many weeks the Mix layer's strip covers; declared in `lib/core/models/training_load.dart` |
| `kTrainingLoadMinRatedWeeks` | How many of the last 12 seven-day weeks, today's included, must hold a rated session before the Mix layer reports load rather than time; declared in `lib/core/models/training_load.dart` |
| `kTrainingLoadMaxUnratedShare` | Largest unrated share of the window's time the Mix layer tolerates before it reports time rather than load; declared in `lib/core/models/training_load.dart` |
| `kSignalMaxCards` | Most cards the Signals layer shows at once; declared in `lib/core/models/signals.dart` |
| `kSignalDismissalDays` | Local calendar days a dismissal hides its signal, the dismissal day counted as day 1; declared in `lib/core/models/signals.dart` |

---

## Core Files

| File | Role |
|------|------|
| `lib/features/stats/stats_screen.dart` | Full screen implementation |
| `lib/features/stats/widgets/stats_primer_sheet.dart` | `StatsPrimerSheet` — the one-shot explanation sheet: three labelled blocks and a `Got it` CTA; presentation only, the host owns the seen flag |
| `lib/state/stats/stats_primer_state.dart` | `StatsPrimerState` — the `primer_seen_stats` seen flag over the repository preference API, hydrated before `runApp` |
| `lib/features/stats/widgets/stats_pill.dart` | The ALL TIME stat pill, used by Records & Trends and Exercise Progress, not by this screen |
| `lib/features/stats/widgets/mix_layer.dart` | `MixLayerSection` — the Mix layer: the explainer sentence, the modality bar and its legend, the usual bar and its two labels, the note, the week strip, the strip's title and caption, the empty-strip line and the empty-window card's one line |
| `lib/features/stats/widgets/signals_layer.dart` | `SignalsLayerSection` — the Signals layer: the header, the signal cards, the quiet line and the waiting lines; `SignalsLockedSection` — the locked line a gate-unmet screen with no unlocked card shows in the layer's slot, with the waiting lines under it |
| `lib/core/models/signals.dart` | The Signals value types (`SignalKind`, `SignalCard`, `SignalsData`), the selection, the gate and the dismissal maths; declares `kSignalMaxCards` and `kSignalDismissalDays` |
| `lib/core/services/signals_service.dart` | `SignalsService` — loads the dismissal store, evaluates the registered signals for one load, collects the waiting lines and writes a dismissal back |
| `lib/features/stats/widgets/instrument_list.dart` | The Instruments list: one section per kind of work, capped rows, the expand control; declares `kInstrumentRowCap` |
| `lib/features/stats/widgets/instrument_row.dart` | One Instruments row (name, figure, change chip, trend line) and `InstrumentChangeChip` |
| `lib/features/stats/widgets/instrument_sparkline.dart` | The row's trend line, drawn only when the window holds at least two points |
| `lib/features/stats/widgets/native_value_format.dart` | `formatNativeValue`, `formatNativeChange`, `nativeSecondaryLabel` and `nativePrimaryLabel` — the strings a row reads |
| `lib/features/stats/widgets/fuel_section.dart` | `FuelSection` — the Fuel row: the logged-days indicator, the calories, protein, carbs and fat figures (each labelled, with its comparison readout, in two rows), the training / rest split, and the not-enough-logged-days sentence that replaces the figures and the split below `kFuelMinLoggedDays` logged days |
| `lib/features/nutrition/nutrition_trend_screen.dart` | The full-history nutrition trend screen, which the Fuel row opens |
| `lib/core/models/stats_progress.dart` | Value types: `StatsProgressData`, `StatsWindow` (with `dayCount`, the window's calendar span), the per-section progress types (`LiftProgress`, `StatsPR`, `TrendPoint`) and the nutrition trend / adherence types (`NutritionTrendPoint`, `NutritionAdherenceTargetPoint`, `NutritionAdherence`) |
| `lib/core/models/exercise_metric.dart` | `ExerciseSection` and the native-value types a row's figure is built from: `NativeMetric`, `NativeValue`, `ExerciseMetricPoint`, `ExerciseMetricSummary`, `StatsTotals` |
| `lib/core/models/instrument_list.dart` | Value types behind the Instruments list: `InstrumentRow`, `InstrumentSectionData` |
| `lib/core/models/fuel_summary.dart` | `FuelSummary` — the Fuel row's value type: the window's logged-day averages (calories, protein, carbs, fat), the previous range's, the training / rest split, the targets, and `showsAverages`, the `kFuelMinLoggedDays` gate the row draws from |
| `lib/core/models/training_load.dart` | `MixLayerData` — the Mix layer's value type: the modality shares, the measure, the usual mix, the baseline note, the unrated session count (`unratedSessionCount`, which no widget reads), the strip's weeks, the last completed session's day (`lastSessionDay`) and the empty-window flag (`windowIsEmpty`); declares `kMixStripWeeks`, `kTrainingLoadMinRatedWeeks` and `kTrainingLoadMaxUnratedShare` |
| `lib/core/services/stats_progress_service.dart` | Pure-Dart computation service: `statsWindow()` (the Stats screen's four-week window), `computeTotals()`, `computeFuelSummary()`, `computeMixLayer()` and `computeInstrumentSections({required StatsWindow window})`; `computeProgressData()` and the `resolveWindow()` it calls now serve Records & Trends' lift selection only |
| `lib/state/workout/workout_state.dart` | `getAllSessions()`, repository access |
| `lib/state/settings/settings_state.dart` | Theme colors, weight/distance unit preferences |
| `lib/core/utils/date_utils.dart` | `OmniDateUtils.formatShort()` — the dates the Mix layer's empty lines and strip caption read |

---

## Related Documentation

- [Calendar & Periods](calendar_periods.md) — the calendar-day arithmetic the window and the Fuel row use
- [Stats Screen — Signals Layer](stats_screen/signals_layer.md) — the Signals layer in full, split out of this page
- [Records & Trends](records_and_trends.md) — the per-exercise screens the header icon opens
- [Widget Catalog](widget_catalog.md) — the note on the Stats screen's primer sheet
- [State Management & Services](state_management.md)
- [Navigation & Screens](navigation_and_screens.md)

---

**Document Version**: 3.4
**Last Updated**: November 3, 2026

---

> **Doc freshness** — Last reconciled against source: 2026-10-13. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
