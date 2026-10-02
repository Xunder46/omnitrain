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
alone — no ALL TIME card, no Instruments list and no Fuel row, whatever the food
log holds. Otherwise it is three blocks in a fixed order:
the [ALL TIME card](#all-time-card), the [Instruments list](#instruments-list)
when the window holds work, and the [Fuel row](#fuel-row) when recent food
exists. Verified by `test/stats_legacy_removal_test.dart` (`S-1208`) and
`test/fuel_row_screen_test.dart` (`S-1112`).

Nothing else is rendered. The screen holds no chart section, no segmented
control and no block beyond those three: `test/stats_legacy_removal_test.dart`
fails if a removed section's identifier returns to the file (`S-1209`) or if a
chart widget does (`S-1210`), and `test/screen_widget_test.dart` fails if the
Calories / Macros toggle returns. Recent PRs are not among them either: they live
in [Records & Trends](records_and_trends.md), verified by
`test/records_and_trends_screen_test.dart` (`S-913`).

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
| Instruments sections and their rows | **Yes** | One row per exercise the window holds work for |
| Each row's figure and change readout | **Yes** | The figure is the window's; the change compares it with the previous window of the same calendar length |
| Each row's trend line | **Yes** | Built from the window's own points |
| ALL TIME card (Sessions / Time / Streak) | No | All-time |
| Fuel row | No | Today-anchored over `kFuelWindowDays`, never the screen's selected window — see [Fuel row](#fuel-row) |
| Exercise Progress (what a row opens) | No | Reads the exercise's full history — see [Records & Trends](records_and_trends.md) |

### On-screen Window Label

The first Instruments header carries an inline chip naming the resolved window —
the training period's name when one is active, otherwise the recent-training-days
fallback. The chip exists so the scope of the readout is never ambiguous, and the
Instruments list is its only host on this screen: it is one widget,
`StatsWindowChip` in `lib/features/stats/widgets/window_chip.dart`. Verified by
`test/instrument_list_screen_test.dart` (`S-1011`).

---

## Data Loading

All data is loaded in `_loadData()`, called once on first frame via
`addPostFrameCallback`. The screen builds one `CalendarState` and one
`StatsProgressService` over `widget.workoutState.repository`, then asks it for
the all-time totals (`computeTotals()`), the windowed progress data
(`computeProgressData()`), the Fuel summary (`computeFuelSummary()`) and the
Instruments list, which it builds from the window `computeProgressData()`
resolved (`computeInstrumentSections(window: ...)`). The list is therefore always
scoped to the window the screen is showing.

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

---

## Core Files

| File | Role |
|------|------|
| `lib/features/stats/stats_screen.dart` | Full screen implementation |
| `lib/features/stats/widgets/stats_pill.dart` | The ALL TIME stat pill, shared with Records & Trends |
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
| `lib/core/services/stats_progress_service.dart` | Pure-Dart computation service: `computeTotals()`, `computeProgressData()` (and the `resolveWindow()` it calls), `computeFuelSummary()` and `computeInstrumentSections({required StatsWindow window})` |
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

**Document Version**: 3.0
**Last Updated**: October 1, 2026

---

> **Doc freshness** — Last reconciled against source: 2026-10-01. This doc is derived from source, not hand-maintained. Source of truth: the `lib/` tree as it exists on the reconciliation date. If you find a claim here that disagrees with `lib/`, `lib/` wins — please flag the drift in a fresh chat with the Coordinator agent.
