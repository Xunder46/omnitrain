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
otherwise it shows five sections. Every on-card chart is a
horizontally scrollable `ScrollableTrendChart` (pinned y-axis, full
history, opens scrolled to the newest point). See
[Scrollable Charts](#scrollable-charts) below.

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

For each lift:
- **e1RM trend** — estimated 1-rep-max per training day (Epley: `w × (1 + r/30)`),
  max across sets in that day; rendered as a scrollable `LineChart` when
  ≥ 2 data points. Values are converted to the user's preferred weight
  unit (`UnitFormatter.convertWeight`).
- **Volume trend** — total `weight × reps` per training day; scrollable
  `LineChart` when ≥ 2 points. Displayed in the user's preferred weight
  unit.
- Single-point fallback: inline text (no chart, no scroll).

A **Recent PRs** card follows, listing up to 5 exercises where the all-time
e1RM high was set or exceeded (first-ever session counts as a PR). PR values
are also shown in the user's preferred weight unit.

Empty state: "No strength history yet." when `topLifts` is empty.

#### Source of truth (Stats screen ↔ in-session toast)

The in-session "Congrats! New PR" toast fires from
`WorkoutSessionScreen._logSet()` (see
[`PRToast` in the widget catalog](widget_catalog.md#prtoast))
and uses the **same** Epley e1RM formula and **same** all-time-best
query as this screen:

- **Formula** — `StatsProgressService.epley1RM(weight, reps)` returns
  `weight × (1 + reps / 30)` (returns `null` when weight or reps is
  non-positive). Both the Stats PR detection loop in
  `computeProgressData` and the in-session check call this static
  helper. There is exactly one PR formula in the codebase.
- **Standing-best query** —
  `StatsProgressService.getAllTimeBestE1RM(exerciseId)` walks all
  **completed** sessions (in-progress sessions are excluded so the
  in-session toast and the Stats screen agree on the standing best
  at the moment of a new set). Only `effortKind == 'set'` efforts
  contribute, matching the "Effort-Type Keying" rule below.
- **Strict comparison** — the in-session toast fires when
  `newE1rm > standingBest` (D-3 in the plan), and the Stats PR
  detector uses the same strict `>` comparison when walking the
  per-day e1RM trend. A set equal to the standing best is **not** a
  PR on either surface.

If you change the PR formula, the standing-best query, or the
comparison operator on either side, the structural-guard test
**S-009** in
`.github/agents/plans/in-session-pr-toast-plan.md` will fail loudly.
Do not introduce a second e1RM helper or a second standing-best
query — the two surfaces must continue to share a single source of
truth.

### CARDIO
Auto-detects the top-2 most-frequently-performed exercises with at least one
`timed`-kind effort with `TimedState.finished`, ranked by distinct training days.

For each activity:
- **Pace chart** — `durationSecs / (distanceM / 1000)` per training day; shown
  when at least one day has a distance measurement and ≥ 2 data points.
  Distance is rendered as a secondary overlaid trend (converted to preferred
  distance units) so pace and distance direction can be compared in one card.
  Multi-line — pace and distance scroll together on a shared x-domain.
- **Duration chart** — total session minutes per training day; fallback when no
  distance data or only 1 data point.
- Single-point fallback: inline text.

Empty state: "No cardio history yet." when `topCardio` is empty.

### HOW DID IT FEEL
A **passive readout** of the post-session feeling captured by the summary
sheet. Surface purpose: the user reads how their feeling has drifted over
time against how much they've been training, by visual alignment on the
same time window. The HOW DID IT FEEL card never tells the user to rest.

- **Source** — `TrainingSession.sessionFeeling`.
  Aggregated by `StatsProgressService.computeFeelingTrend({required StatsWindow window})`,
  which walks all **completed** sessions inside the same
  `StatsWindow` resolved for Strength/Cardio selection. Sessions without
  a recorded feeling are omitted entirely (no zero-fill, no synthetic
  flat line, no interpolated dip between two real points).
- **Universal across modalities** — the aggregator reads only the
  session-level feeling field. It does not touch `SegmentEffort`,
  `Exercise`, or any modality / strength-specific table, so an all-running
  or all-grappling user renders identically to a lifter.
- **Window coupling** — uses the same `StatsWindow` the Strength and
  Cardio sections use. Changing the window moves the HOW DID IT FEEL trend in
  lockstep with the other trends.
- **Chart** — fixed 1..5 semantic range pinned at exactly 5 integer
  ticks (1, 2, 3, 4, 5; interval = 1). The y-axis is not auto-scaled;
  feeling is ordinal, not continuous, so no padding above 5 (which
  would produce a misleading 6th tick) and no zero-baseline below 1.
  Renders inside the same `ScrollableTrendChart` wrapper as the other
  on-card charts with `LineTouchData.enabled = false`. The connecting
  line is one fixed color (`themeColors.primary`) — the same single-
  color convention every other chart on the screen already uses — so
  the line is always legible regardless of which rating was most
  recently logged. Each point is painted in its own session's feeling
  color via `feelingColor(feeling, themeColors)`, the same shared helper
  the post-session survey tile and the day-session-list border tint
  already use; the three surfaces stay in lockstep from one palette
  source. Y-axis labels are bare integers (no unit suffix). The card
  itself carries no in-card title — the `HOW DID IT FEEL` section
  header above it is the only label. The chart renders with the
  **same width conventions every other chart on the screen already
  uses**: a 2dp line (`barWidth: 2`), 3dp-radius dots (`radius: 3`),
  1.5dp dot stroke (`strokeWidth: 1.5`), no glow shadow, no halo
  ring, straight segments (`isCurved: false`), and no area fill —
  so the feeling chart reads at the same visual weight as the
  e1RM, volume, cardio, and nutrition charts and never looks
  louder than the trends around it.
- **Empty state** — when the resolved window contains zero sessions with
  a recorded feeling, an explicit empty-state card renders
  ("No feeling logged in this window yet"). Not a chart, not a flat line
  at zero, not a crash.
- **No-sessions branch** — when the repository has zero completed
  sessions, the HOW DID IT FEEL card is not rendered at all (the global
  "No sessions yet" empty state wins, the same as for every other
  section).

#### Deliberate non-features

- No stat tile, no average-feeling scalar, no Feeling pill in the ALL TIME
  row. The summary stat grid remains Sessions / Time / Streak only.
- No rest / deload / recovery suggestion, banner, nudge, or call-to-action.
- No changes to the day-session-list feeling border tint; that stays as-is.
- The connecting line never takes its color from any session's rating.
  Only the points carry rating color. The line is `themeColors.primary`
  — a single fixed color that stays clearly legible on every theme
  background.

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

#### Per-day math (pure-Dart, in `StatsProgressService`)

```
calories = Σ ConsumedFood.caloriesConsumed          // per-row, already rounded
protein  = Σ (protein × amountConsumed / referenceAmount)  accumulated as double, rounded once per day
carbs    = Σ (carbs   × amountConsumed / referenceAmount)  accumulated as double, rounded once per day (total carbs, not net)
fat      = Σ (fat     × amountConsumed / referenceAmount)  accumulated as double, rounded once per day
```

The carbs line plots **total** carbs grams (not net carbs), matching
the home strip's "total carbs for blue" semantics. The color token
is named `netCarbs` because the donut reuses that slot, but the value
plotted here is total carbs.

The aggregation is computed by
`StatsProgressService.computeNutritionTrend({int? days})` and is the
same on Hive (web) and any future native SQLite implementation — it
depends only on `WorkoutRepository.getConsumedFoodsInRange` and the
`ConsumedFood` model, both environment-agnostic.

---

## Scrollable Charts

Every on-card line chart on this screen — strength e1RM, strength volume,
cardio pace + distance, cardio duration, nutrition calories, nutrition
macros — renders inside a `ScrollableTrendChart` wrapper
([`lib/features/stats/widgets/scrollable_trend_chart.dart`](../../lib/features/stats/widgets/scrollable_trend_chart.dart))
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
The ALL TIME pills, the 30-day Activity bar chart, the Streak, and the
Rest Time chart are unaffected.

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
| HOW DID IT FEEL trend | **Yes** | Same window as Strength/Cardio selection; sessions outside the window are omitted from the trend (no zero-fill) |
| Strength `e1RmTrend` / `volumeTrend` | No | Always full history for the selected exercise |
| Cardio pace / distance / duration trend | No | Always full history for the selected exercise |
| Recent PRs | No | Always all-time (Epley, `effortKind == 'set'`) |
| ALL TIME pills (Sessions / Time / Streak) | No | Unchanged |
| 30-day Activity bar chart | No | Unchanged |
| Rest Time chart | No | Unchanged |
| NUTRITION card | No | Always full history (`days: null`) |

### On-screen Window Label

Each section header is followed by an inline italic chip with the
window's `label`:

- Period-scoped: `"· <period.name>"` (e.g., `· Off-Season Strength Block`).
- Recent-days: `"· Last <N> training days"` (e.g., `· Last 14 training days`).

The chip explains the readout — a Strength or Cardio card that
shows the user's current focus and a label that says
`· Off-Season Strength Block` makes the scope obvious.

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

| Constant | Value | Meaning |
|----------|-------|---------|
| `kTopLiftCount` | 3 | Max lifts shown in Strength section |
| `kTopCardioCount` | 2 | Max cardio activities shown |
| `kRecentPRCount` | 5 | Max PR rows in the Recent PRs card |
| `kRecentTrainingDaysWindow` | 14 | Single tunable: number of recent "training days" used for the Strength/Cardio selection window when no period qualifies. See [Selection Window](#selection-window-current-state-window). |
| `kNutritionTrendDays` | 10 | Soft "default visible window" hint; the NUTRITION card uses `days: null` for full history |

## Key Constants (`ScrollableTrendChart`)

| Constant | Value | Meaning |
|----------|-------|---------|
| `kScrollableTrendPerPointWidth` | 48 px | Fixed horizontal slot per plotted point |
| `kScrollableTrendPinnedAxisWidth` | 64 px | Width of the static y-axis label column |
| `kScrollableTrendChartHeight` | 120 px | Standard on-card chart height |

---

## Core Files

| File | Role |
|------|------|
| `lib/features/stats/stats_screen.dart` | Full screen implementation |
| `lib/features/stats/widgets/scrollable_trend_chart.dart` | Scrollable chart wrapper (pinned y-axis, horizontal scroll, newest-first jump) |
| `lib/core/models/stats_progress.dart` | Value types: `StatsProgressData`, `LiftProgress`, `CardioProgress`, `StatsPR`, `TrendPoint`, `CardioTrendPoint`, `NutritionTrendPoint`, `FeelingTrendPoint`, `StatsWindow` |
| `lib/core/services/stats_progress_service.dart` | Pure-Dart computation service (also computes the nutrition trend via `computeNutritionTrend({int? days})` and the feeling trend via `computeFeelingTrend({required StatsWindow window})`) |
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

**Document Version**: 2.3
**Last Updated**: June 25, 2026


---

## Navigation Entry Point

```
HomeScreen
  └── Maintenance sheet (swipe up or tap hint)
        └── Stats → StatsScreen
```

---

## What the Screen Displays

The screen is organized into three sections, each rendered as an `OmniSurface` card:

### ALL TIME
A row of three stat pills:

| Stat | Source |
|------|--------|
| **Sessions** | Count of completed sessions across all time (sessions where `endedAtMs != null`) |
| **Total Time** | Sum of `endedAtMs − startedAtMs` for all completed sessions, formatted as h:mm |
| **Streak** | Current consecutive-day training streak, delegated to `CalendarState.streakDays`; a flame icon appears when streak ≥ 3 days |

### ACTIVITY
A **30-day session activity bar chart** built with `fl_chart`:

- Index 0 = 29 days ago; index 29 = today (window anchored at load time, never re-evaluated on rebuild)
- Bar height = number of completed sessions that day
- Bar color = `themeColors.primary` (current theme accent; not per-modality)
- X-axis labels appear at indices 0, 7, 14, 21, 28 in `"Mon DD"` format (short month name + day)
- Empty days render as zero-height bars

### REST TIME
A **multi-line chart** showing average rest duration (seconds) per day, one line per modality. Only visible when closed rest records exist in the 30-day window.

- Each line uses the modality accent color from `ModalityColors.forModality(modality)`
- Modalities displayed in order: `cardio_endurance`, `resistance_lifting`, `sports`, `isometric_stretching`, Free Training (`null`)
- Null-modality (Free Training) is included if rest records exist for it
- Days with no rest data for a modality are skipped (no gap-fill)

---

## Streak Calculation

Streak is not computed inside `StatsScreen`. A temporary `CalendarState` is created internally using the repository from `WorkoutState`, initialized, and its `streakDays` getter is read. The calculation logic lives in `CalendarState._computeStreak()` (up to 90 days of history). See [Calendar & Periods](calendar_periods.md) for full streak logic.

---

## How the 30-Day Chart Works

- `_dayCounts` is a 30-element `List<int>` initialized to zero, indexed `[0..29]` where 0 = 29 days ago and 29 = today
- Sessions in the 30-day window are iterated; each session contributes +1 to the `dayIndex` computed from `sessionDay.difference(thirtyDaysAgo).inDays`
- Only completed sessions (`endedAtMs != null`) are counted
- The date window is anchored at load time (`_thirtyDaysAgo`, `_today`) so that a midnight rebuild (e.g. triggered by a theme change) does not shift bar indices while `_dayCounts` still represents the original window

---

## Data Loading

All data is loaded in `_loadData()`, called once on first frame via `addPostFrameCallback`. Two repository calls are made in parallel:

```dart
final results = await Future.wait([
  widget.workoutState.getAllSessions(),           // all-time aggregates
  widget.workoutState.getSessionsByDateRange(fromMs, toMs),  // 30-day chart
]);
```

Rest averages are fetched via:
```dart
workoutState.repository.getEntryRestsByModalityInDateRange(fromMs, toMs)
```

The screen shows a `CircularProgressIndicator` while loading and an empty-state message when no completed sessions exist.

---

## What Is Intentionally Not in v1

- No per-modality session count breakdown
- No date range selector or filter controls
- No per-exercise or per-exercise-type stats
- No week / month / year toggle
- All deferred to post-launch iteration

---

## Core Files

| File | Role |
|------|------|
| `lib/features/stats/stats_screen.dart` | Full screen implementation |
| `lib/state/workout/workout_state.dart` | `getAllSessions()`, `getSessionsByDateRange()`, repository access |
| `lib/state/calendar/calendar_state.dart` | `streakDays` getter (created internally by `StatsScreen`) |
| `lib/state/settings/settings_state.dart` | Theme colors for the chart and layout |
| `lib/core/constants/modality_colors.dart` | Per-modality accent colors for the rest time chart |

---

## Related Documentation

- [Calendar & Periods](calendar_periods.md) — streak calculation details
- [State Management & Services](state_management.md)
- [Navigation & Screens](navigation_and_screens.md)

---

**Document Version**: 1.0
**Last Updated**: April 11, 2026


---

> **Doc freshness** — Last reconciled against source: 2026-06-29. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
