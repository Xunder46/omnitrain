# Stats Screen — Feature Documentation

## Overview

`StatsScreen` is a read-only analytics screen that surfaces aggregate training
data and progress trends for the current user. It is accessible from the
maintenance sheet on the home screen. There are no interactive controls or
filters in the current release.

---

## Navigation Entry Point

```
HomeScreen
  └── Maintenance sheet (swipe up or tap hint)
        └── Stats → StatsScreen
```

---

## What the Screen Displays

The screen renders an empty-state card when no completed sessions exist;
otherwise it shows the sections below. The exact count of sections on
screen is verified by `test/screen_widget_test.dart` (every
`OmniCardHeader` is a section) and the per-section contracts are
verified by `test/stats_progress_test.dart` (the underlying
`StatsProgressService` tests) and the screen widget tests in
`test/screen_widget_test.dart`. Every on-card chart is a horizontally
scrollable `ScrollableTrendChart` (pinned y-axis, full history, opens
scrolled to the newest point). See [Scrollable Charts](#scrollable-charts) below.

### ALL TIME
A row of three stat pills (unchanged from v1):

| Stat | Source |
|------|--------|
| **Sessions** | Count of completed sessions across all time |
| **Total Time** | Sum of `endedAtMs − startedAtMs`, formatted as h:mm |
| **Streak** | Current consecutive-day streak via `CalendarState.streakDays`; flame icon at ≥ 3 days |

### STRENGTH
Auto-detects the top-3 most-frequently-trained exercises with at least one
`set`-kind effort, ranked by distinct training days then alphabetically.

Selection is gated by two filters:

1. **Current-state window** (see [Selection Window](#selection-window-current-state-window))
   — an exercise must have a training day inside the resolved window to
   be eligible. The window is shared between Strength and Cardio and is
   surfaced on-screen.
2. **Recency floor** (`StatsProgressService.kTopExerciseRecencyDays`,
   default **30** calendar days) — an exercise whose most-recent
   training day is older than the threshold drops out of the displayed
   top slots, freeing space for exercises the user is currently training.
   The threshold is generous enough that a weekly / biweekly rotation
   does not flicker a lift in and out between sessions; dropping out
   signals genuine abandonment, not normal spacing. Trend charts and PR
   lists for exercises that DO appear are unaffected — only which
   exercises fill the top-N slots is filtered. See
   `docs/plans/stats-summary-fix-pack-plan.md` Item 3.

#### Per-exercise axes

Each lift has up to three trend axes. They render independently based on
whether the user has logged data on each axis:

- **e1RM trend** — estimated 1-rep-max per training day (Epley:
  `w × (1 + r/30)`), max across weighted sets in that day. Populated
  only when the exercise has at least one weighted set (`weight > 0`).
  Converted to the user's preferred weight unit
  (`UnitFormatter.convertWeight`). Drives the PR record on the
  weight axis.
- **Volume trend** — total `weight × reps` per training day. Populated
  only when the exercise is on the **weight axis** (see the axis
  rule below); empty for reps-axis exercises. Bodyweight sets
  contribute zero to the kilogram Total Volume — that figure stays
  load-only.
- **Reps trend** — max reps per training day across bodyweight sets
  (`weight == 0`). Populated only when the exercise is on the
  **reps axis**. Each trend point carries an optional
  `extraWeightKg` annotation: the day's max added weight when at
  least one set used a `metric-extra-weight` observation (e.g. a
  dip belt). The annotation is rendered as `"+X kg"` on the
  single-point card and as an inline note beneath the multi-point
  chart; it is **never** summed into the Total Volume figure and
  **never** flips the exercise onto a weight axis.
- Single-point fallback: inline text (no chart, no scroll).

#### Per-exercise axis rule

Each lift is classified as either **reps-axis** or **weight-axis**
based on its full history, not per-set:

- **Reps-axis** — the exercise has at least one logged set with
  `weight == 0` (bodyweight). Its Stats card is reps-only: a reps
  trend and a max-reps PR. e1RM and kg Volume sections are not
  rendered, even when some of its sets carried added weight.
  This is the rule that fixed the "Push-Up mixed-axis" bug —
  Push-Up now renders reps-only even when one session was logged
  with a weighted belt.
- **Weight-axis** — every set has `weight > 0`. Its Stats card is
  weight-based: an Estimated 1RM trend and a kg Volume trend.
  Reps-axis sections are not rendered.

The rule is per-exercise, applied by `StatsProgressService.computeProgressData`
via `isRepsAxis = repsDayMap.isNotEmpty`. A weighted set on a
reps-axis exercise contributes its reps to the day's max and its
added weight to the `extraWeightKg` annotation — that is the entire
contribution. It does **not** create a separate weight record, does
**not** switch the exercise onto a weight axis, and does **not**
contribute to the kilogram Total Volume.

#### Bodyweight inclusion rule

Inclusion is purely "the set was performed without added external
weight" (`weight == 0`). The exercise's category or equipment label
is NOT consulted — pull-ups and chin-ups in particular are NOT
labelled as bodyweight in the seed data and must NOT be excluded by
any label technicality. When a bodyweight exercise is occasionally
performed with added weight (e.g. a dip belt), the added weight is
recorded as a `metric-extra-weight` annotation on the observation
only; it does NOT create a separate weight record, does NOT switch
the exercise onto a weight axis, and does NOT contribute to the
kilogram Total Volume. The exercise stays on its reps axis so a
single exercise never splits across two units. See
`docs/plans/stats-summary-fix-pack-plan.md` Item 2.

#### Recent PRs

A **Recent PRs** card follows, listing up to 5 exercises where the
all-time high on the exercise's axis (reps or weight, per the
per-exercise axis rule) was set or exceeded (first-ever session
counts as a PR on the chosen axis). PRs are deduplicated to one
entry per exercise name; the highest verdict wins:

- `StatsPR.reps != null` → rendered as `"<n> reps"`.
- `StatsPR.e1Rm != null` → rendered as `"<value> <unit>"` in the
  user's preferred weight unit.

Loaded exercises emit weight-axis PRs; bodyweight exercises emit
reps-axis PRs. The same rep-based verdict also surfaces on the
in-session toast (when wired through the reps-axis variant of
`_maybeShowPRToast`) and the post-workout Session Summary (through
the reps-axis pass in `SessionSummaryService.computePRs`).

Empty state: "No strength history yet." when `topLifts` is empty.

#### Source of truth (Stats screen ↔ in-session toast ↔ Session Summary)

The in-session "Congrats! New PR" toast, this Stats screen's PR
detection, and the post-workout Session Summary's
`SessionSummaryService.computePRs` all use the **same** Epley e1RM
formula and **same** all-time-best query, so the same set produces
the same record verdict in every surface:

- **Formula** — `StatsProgressService.epley1RM(weight, reps)` returns
  `weight × (1 + reps / 30)` (returns `null` when weight or reps is
  non-positive). The Stats PR detection loop in
  `computeProgressData`, the in-session check, and the Session
  Summary's `computePRs` all call this static helper. There is
  exactly one PR formula in the codebase.
- **Standing-best query** —
  `StatsProgressService.getAllTimeBestE1RM(exerciseId,
  {excludeSessionId})` walks all **completed** sessions (in-progress
  sessions are excluded so the in-session toast and the Stats screen
  agree on the standing best at the moment of a new set). The
  Session Summary passes `currentSession.id` as
  `excludeSessionId` so the just-finished workout's PRs are not
  compared against themselves. Only `effortKind == 'set'` efforts
  contribute, matching the "Effort-Type Keying" rule below.
- **Strict comparison** — every surface fires when
  `newE1rm > standingBest` (D-3 in the plan); the Stats PR detector
  uses the same strict `>` comparison when walking the per-day e1RM
  trend, and the Session Summary compares
  `ExerciseSummary.bestE1RM > previousBest`. A set equal to the
  standing best is **not** a PR on any surface.
- **Cross-surface parity guard** — `S-T-001` in
  `docs/plans/summary-pr-parity-plan.md` exercises the
  same seed through all three surfaces and asserts they agree.
  `S-009` in `docs/plans/in-session-pr-toast-plan.md` is
  the toast ↔ Stats structural guard; both tests must pass
  unchanged.

If you change the PR formula, the standing-best query, or the
comparison operator on any of the three surfaces, the structural
guards will fail loudly. Do not introduce a second e1RM helper or a
second standing-best query — the three surfaces must continue to
share a single source of truth.

### CARDIO
Auto-detects the top-2 most-frequently-performed exercises with at least one
`timed`-kind effort with `TimedState.finished`, ranked by distinct training days.

For each activity:
- **Pace chart** — a day's pace counts only the finished entries that have a
  distance, so a day's walk-breaks and its untimed entries do not dilute it;
  if no entry qualifies the day has no pace. Shown
  when at least one day has a distance measurement and ≥ 2 data points.
  Distance is rendered as a secondary overlaid trend (converted to preferred
  distance units) so pace and distance direction can be compared in one card.
  Multi-line — pace and distance scroll together on a shared x-domain.
- **Duration chart** — total session minutes per training day; fallback when no
  distance data or only 1 data point.
- Single-point fallback: inline text.
- **Estimates are marked, not converted.** A day whose total counts a distance
  the watch platform estimated carries the marker on both its distance and its
  pace, in the single-point text and on the chart, and the legend gains one
  `est.` item only when the card has such a day. An estimated day's dot is
  found by the day it belongs to rather than by its position in a series, since
  a series may hold fewer spots than the trend has days (S-835). The duration
  and distance totals themselves are unchanged by the marker. A day counts only
  distances that belong to an entry: a row no entry owns counts in no total
  (D-321). Which entry a distance belongs to, and what a source means, is
  [Distance Source & Pairing](distance_source.md).

Empty state: "No cardio history yet." when `topCardio` is empty.

Verified by `test/stats_distance_estimate_test.dart` (`S-831` for the pace
inputs, `S-832` for the per-day flag, `S-833`/`S-834` for the single-point
marker in both units and its absence on a measured day, `S-835` for the dots
and the legend, `S-836` for the conversions, `S-837` for a Summary correction),
`test/entry_identity_summary_test.dart` (`S-858` for a leftover row that counts
nowhere) and `test/stats_progress_test.dart` (the `Cardio trend` group).

### RECORDS
Per-exercise best observed values with the date each was set. Aggregated by
`StatsProgressService.computeExerciseRecords()`, which walks every completed
session once and produces one `ExerciseRecord` per exercise. Verified by
`test/stats_progress_test.dart` (`computeExerciseRecords` group, scenarios
S-001…S-008). Metrics surface on the section are the ones the exercise has
ever been logged against:

- **Heaviest load** — max `load × reps` across the exercise's loaded
  sets (the set with the heaviest single `weight` value carries its
  tonnage as the record). Date is the day that set was performed.
  Null for bodyweight-only exercises (`0 × N = 0` is not a record).
- **Most reps at load** — the single set with the highest rep count,
  plus the load (kg) it was performed at and the date. Bodyweight
  sets are included with `loadKg: 0.0`.
- **Longest duration** — total `actualDurationSecs` of timed efforts on
  the longest day for this exercise. Per-day sum so a day with two
  1 km runs shows 2 km, not 1.
- **Longest distance** — same per-day-sum contract as duration but for
  the sum of `metric-distance` observations on timed efforts.

Each row renders the value in the user's preferred units
(`UnitFormatter.convertWeight` for kg, `formatDistanceValue` for km/mi)
and the date as `"Mon DD, YYYY"`. Empty state: when the service
returns an empty list, the section hides itself — the same shape
every other section uses.

### VOLUME TRENDS
Three buckets of effort, each on its own tab in a segmented toggle that
swaps the chart without re-querying the repository:

- **Tonnage** — Σ `load × reps` across load-based (`effortKind == 'set'`,
  `weight > 0`) sets, bucketed by ISO week. One line per present
  modality plus an "Overall" line; legend below the chart.
  `computeVolumeTonnage()`.
- **Time** — Σ `actualDurationSecs` across `TimedState.finished` timed
  instances, bucketed by ISO week. `computeTimedDuration()`. y-axis
  formatted as h:mm.
- **Distance** — Σ `metric-distance` observations on timed efforts,
  bucketed by ISO week. `computeTimedDistance()`. y-axis converted to
  the user's preferred distance unit (`km` / `mi`) through
  `UnitFormatter`.

All three share the same multi-line chart primitive
(`_buildMultiLineScrollableChart` in `stats_screen.dart`): one
`LineChartBarData` per present modality plus an Overall line. Unit
labels respect `SettingsState.preferredWeightUnit` /
`preferredDistanceUnit`. Empty per-tab state: "No Tonnage data yet.
Log a session to see this trend here." — descriptive only, no advice
copy. Sections with no data across all three tabs hide themselves.

### CONSISTENCY
Sessions per period, per modality + overall. Two tabs in a segmented
toggle:

- **Week** — sessions per ISO week (Monday-start), aggregated by
  `StatsProgressService.computeConsistencyWeekly()`.
- **Month** — sessions per calendar month, aggregated by
  `StatsProgressService.computeConsistencyMonthly()`.

Same multi-line chart primitive as VOLUME TRENDS (Overall + per-modality
lines). Empty per-tab state: "No Week data yet. Log a session to see
this trend here." — descriptive only. Section hides itself when both
tabs are empty.

### Effort rating (no section)
The Stats screen has no effort-rating chart, scalar or pill: the rating
is captured and edited on the Session Summary (see
[Session Summary](session_summary.md)) and shown as the calendar
day-list tint. The former feeling-trend section was removed when the
post-session survey was redefined as the effort rating (rationale:
`docs/plans/2026-09-24-01-stats-pr1-effort-rating-plan.md`).
Verified by `test/screen_widget_test.dart` (`HOW DID IT FEEL section is
removed (Phase 4)`).

#### Deliberate non-features

- No stat tile, average-rating scalar or rating pill in the ALL TIME
  row (`test/screen_widget_test.dart`, `S-005 guard: no feeling scalar /
  pill / tile appears in the ALL TIME summary stat row`).
- No rest / deload / recovery suggestion, banner, nudge, or
  call-to-action.

### NUTRITION
A **full-history** nutrition trend computed from every logged `ConsumedFood`
row in the repository (no 10-day cap). The card carries a segmented pill
toggle over the same plotted-day set:

- **Calories view (default)** — single line in `themeColors.primary`,
  one point per logged day with kcal/day. Y-axis labels use `ChartAxisHelper`
  with `' kcal'` units; tooltip shows `"<n> kcal"`.
- **Macros view** — three lines (protein, carbs, fat) on a shared grams
  scale, each in its `OmniTheme.colors.macroChart` slot:
  protein → `.protein`, carbs → `.netCarbs` (the carbs/blue slot), fat
  → `.fat`. Tooltip shows grams per series; legend rendered below the
  chart.

Both views share the same plotted-day set — any logged food makes the
day present for all series — so toggling never changes the x-domain.

- **Window** — full history (`StatsProgressService.computeNutritionTrend(days: null)`).
  A soft `kNutritionTrendDays = 10` constant remains as a default for
  callers that want a fixed window; the card itself never caps the
  range.
- **Empty days are skipped** — only logged days are plotted, sorted
  ascending by date. Matches the strength/cardio trend behavior.
- **Single-point fallback** — when exactly 1 day in history has logged
  food, the card renders an inline single-point summary instead of a
  chart (Calories view: `"<n> kcal — 1 day, log more to see a trend"`;
  Macros view: per-macro summary).
- **Hide when empty** — when 0 days have logged food, the card is
  omitted from the list entirely.
- **No-sessions branch** — when `_totalSessions == 0`, the global
  empty-state card is shown and the nutrition trend is not loaded.

#### Per-day aggregation

Computed by `StatsProgressService.computeNutritionTrend({int? days})`. The carbs line plots **total** carbs grams, not net carbs — the colour token is named `netCarbs` because the donut reuses that slot, but the plotted value is total carbs. The aggregation depends only on `WorkoutRepository.getConsumedFoodsInRange` and the `ConsumedFood` model, so it is environment-agnostic.

#### Target-line overlay

The Calories / Macros views overlay a piecewise **target line** on top
of the actuals so the user can see their consumption against the
configured macro targets. Aggregated by
`StatsProgressService.computeNutritionAdherence()`, which walks
`WorkoutRepository.getNutritionTargetForDate` for every saved target
change and projects the resulting step line onto the actuals'
x-axis. The dashed line uses `dashArray: [4, 4]` in `themeColors.primary`
at half opacity on the calories view and the matching
`macroChart.<slot>` color on the macros view. When no target has
ever been saved, the dashed line is omitted entirely. Historical
actuals are never rewritten — the target line steps at every
saved target change and extends the new value forward only.

- **Step at the change date** — the target line carries the
  post-change value from the saved date onward, so a save on day 10
  steps the line at day 10; historical days keep their earlier
  target value.
- **Empty adherence** — when no target has ever been saved, the
  target line is empty (no defaults inferred from absent data).
- **No actuals** — when no food has been logged, both actuals and
  the target line are empty and the NUTRITION card hides itself,
  matching the existing "no food logged" rule.
- **Legend** — the macros chart's legend adds a "Target" entry
  (rendered as a dashed swatch) when the target line is present;
  the calories chart's legend adds a "Target (kcal)" entry.

---

## Scrollable Charts

Every on-card line chart on this screen — strength e1RM, strength volume,
cardio pace + distance, cardio duration, nutrition calories, nutrition
macros, volume trends (tonnage / time / distance), consistency
(week / month), and the target-line overlay on the nutrition card —
renders inside a `ScrollableTrendChart` wrapper
([`lib/features/stats/widgets/scrollable_trend_chart.dart`](../../../lib/features/stats/widgets/scrollable_trend_chart.dart))
that combines:

- A **pinned y-axis label column** on the left (static; never moves
  when the user drags the plot). The column renders the same
  `min / min+interval / … / max` values the chart uses, so the labels
  stay aligned with the plot as it scrolls.
- A **horizontally scrollable plot** on the right, where `fl_chart`'s
  own `leftTitles` is hidden (the pinned column replaces it).
- A **dynamic per-point slot width** of
  `viewportWidth / maxVisiblePoints` (default `maxVisiblePoints = 8`,
  floored at `kScrollableTrendMinPerPointWidth = 28 dp` for
  readability on narrow phones). The plot's intrinsic width is
  `max(viewportWidth, points × perPointWidth)` — sparse data fills
  the card with no scroll, dense data scrolls.
- A `ScrollController` that **jumps to `maxScrollExtent`** after first
  layout so the card opens scrolled to the newest point on the right.
  `reverse: true` was rejected because it would also flip the plot's
  content direction. The jump reschedules itself on every post-frame
  pass until the controller has content dimensions, so the wrapper
  works regardless of layout timing in tests.
- **No on-card popups.** `lineTouchData` is disabled on every stats
  chart — exact values are read from the pinned y-axis labels and
  (for nutrition) the on-card legend. No GestureDetector, modal, or
  sheet widget.
- **No top headroom.** `topTitles.sideTitles.reservedSize` is `0`
  everywhere; the chart no longer reserves space above the plot for
  a popup-tooltip that no longer exists. The highest data point is
  still fully visible because `ChartAxisHelper.computeBounds` pads
  above the max by `range × 0.15 + 1.0` (≥ 2 dp on any range ≥ 7,
  ≥ 3 dp on any range ≥ 13).

### Nested scrolling

A horizontal `SingleChildScrollView` inside the screen's vertical
`ListView` is safe: the two scroll axes do not conflict. The vertical
page scroll still works while the user drags the chart.

### Why not fl_chart's built-in scroll?

`fl_chart` has no native pinned axis. The supported pattern for
"scrollable chart with labels that don't move" is a static label
column + a scrollable plot sharing the same `ChartAxisBounds` — the
exact pattern this wrapper implements.

---

## Effort-Type Keying (Critical Rule)

Effort classification uses `SegmentEffort.effortKind`, **not** the session
`modality`:

- `effortKind == 'set'` → contributes to **Strength** charts, regardless of session modality.
- `effortKind == 'timed'` → contributes to **Cardio** charts, regardless of session modality.

This means:
- A `set` effort in a null-modality (Free Training) session → Strength.
- A `timed` effort in a `resistance_lifting` session → Cardio.
- A lifting session with no `set` efforts → contributes nothing to Strength charts.

---

## Selection Window (Current-State Window)

The Strength and Cardio sections **select** their top exercises from a
"current window" rather than all-time, so a lift trained heavily long
ago can't occupy a card while the user's current focus never appears.
**Only the selection is windowed**: every selected exercise's trend
chart continues to use that exercise's FULL history, and the Recent
PRs card stays all-time (a PR's whole point is being a lifetime high).
The ALL TIME pills and the Streak are unaffected.

### Resolution Rule

`StatsProgressService.resolveWindow(periods, completedSessions, now?)`
runs once per `computeProgressData()` call and returns a
`StatsWindow` value. The Strength and Cardio sections always share
one window in a given load.

1. **Active training period.** If today is inside any
   `TrainingPeriod` that contains at least one completed session,
   use that period's date range as the window. If multiple periods
   qualify, the one with the latest `startDateMs` wins
   (deterministic tiebreak by id ascending).
2. **Recent training days (fallback).** Otherwise, take the
   `kRecentTrainingDaysWindow` (default **14**) most-recent
   *training days*. A training day is a calendar day with at
   least one completed session; rest days and breaks do not
   shrink the data. The window's `fromMs` is the start-of-day of
   the earliest selected day; `toMs` is end-of-day of today.
3. **No history at all.** When the repository has no completed
   sessions, the recent-days window reports `recentDays: 0`;
   `fromMs`/`toMs` collapse to today, the filter cleanly yields
   zero sessions, and the screen renders its existing Strength /
   Cardio empty states (the service does NOT silently widen to
   all-time).

### What Is (and Isn't) Windowed

| Surface | Windowed? | Notes |
|---------|-----------|-------|
| Strength card exercise list (top-N) | **Yes** | Same `kTopLiftCount` cap and alphabetical tiebreak; only the session set selection runs over changes |
| Cardio card exercise list (top-N) | **Yes** | Same `kTopCardioCount` cap and alphabetical tiebreak; same window as Strength |
| Strength `e1RmTrend` / `volumeTrend` | No | Always full history for the selected exercise |
| Cardio pace / distance / duration trend | No | Always full history for the selected exercise |
| Recent PRs | No | Always all-time (Epley, `effortKind == 'set'`) |
| ALL TIME pills (Sessions / Time / Streak) | No | Unchanged |
| NUTRITION card | No | Always full history (`days: null`) |

### On-screen Window Label

Each section header carries an inline chip naming the resolved window — the training period's name when one is active, otherwise the recent-training-days fallback. The chip exists so the scope of the readout is never ambiguous.

---

## Data Loading

All data is loaded in `_loadData()`, called once on first frame via
`addPostFrameCallback`. The all-time aggregates (sessions / duration / streak)
come directly from `WorkoutState`. Progress data (trends, PRs) is computed by
`StatsProgressService`:

```dart
final data = await StatsProgressService(
  widget.workoutState.repository,
).computeProgressData();
```

`StatsProgressService` is a pure-Dart service — it depends on the
`WorkoutRepository` interface only, not on any concrete implementation.

---

## Key Constants (StatsProgressService)

Values live in `lib/core/services/stats_progress_service.dart`; this document names them and says what each governs.

| Constant | Meaning |
|----------|---------|
| `kTopLiftCount` | Max lifts shown in the Strength section |
| `kTopCardioCount` | Max cardio activities shown |
| `kRecentPRCount` | Max PR rows in the Recent PRs card |
| `kRecentTrainingDaysWindow` | Number of recent training days used for the Strength/Cardio selection window when no period qualifies |
| `kTopExerciseRecencyDays` | Recency floor for top-slot selection; an exercise whose most-recent training day is older than this drops out regardless of historical frequency. Applied symmetrically to Strength and Cardio |
| `kNutritionTrendDays` | Soft default-window hint; the NUTRITION card passes `days: null` for full history |

---

## Core Files

| File | Role |
|------|------|
| `lib/features/stats/stats_screen.dart` | Full screen implementation |
| `lib/features/stats/widgets/scrollable_trend_chart.dart` | Scrollable chart wrapper (pinned y-axis, horizontal scroll, newest-first jump) |
| `lib/core/models/stats_progress.dart` | Value types: `StatsProgressData`, `LiftProgress`, `CardioProgress`, `StatsPR`, `TrendPoint`, `CardioTrendPoint`, `NutritionTrendPoint`, `ExerciseRecord`, `VolumeTrend`, `ConsistencyTrend`, `NutritionAdherence`, `StatsWindow` |
| `lib/core/services/stats_progress_service.dart` | Pure-Dart computation service (also computes the nutrition trend via `computeNutritionTrend({int? days})`, the records via `computeExerciseRecords()`, the volume / time / distance trends via `computeVolumeTonnage` / `computeTimedDuration` / `computeTimedDistance`, the consistency trends via `computeConsistencyWeekly` / `computeConsistencyMonthly`, and the nutrition adherence via `computeNutritionAdherence()`) |
| `lib/state/workout/workout_state.dart` | `getAllSessions()`, repository access |
| `lib/state/calendar/calendar_state.dart` | `streakDays` (created internally by `StatsScreen`) |
| `lib/state/settings/settings_state.dart` | Theme colors, weight/distance unit preferences |
| `lib/core/utils/unit_formatter.dart` | `weightLabel(settings)` → `'kg'`/`'lbs'`; `convertWeight(kg, settings)` → display value; `distanceLabel(settings)` → `'km'`/`'mi'` |
| `lib/core/utils/date_utils.dart` | `todayMidnightMs()`, `endOfDayMs()` — anchor the nutrition window |
| `lib/core/utils/chart_axis_helper.dart` | `computeBounds()`, `formatYAxisValue()`, `formatDateLabel()` — shared by the chart builders and the pinned y-axis column |

---

## Related Documentation

- [Calendar & Periods](calendar_periods.md) — streak calculation details
- [State Management & Services](state_management.md)
- [Navigation & Screens](navigation_and_screens.md)

---

**Document Version**: 2.4
**Last Updated**: August 10, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-08-10. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
