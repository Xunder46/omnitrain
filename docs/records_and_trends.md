# Records & Trends and Exercise Progress — Feature Documentation

**Scope.** The two read-only per-exercise screens: the Records & Trends index
(`lib/features/stats/records_and_trends_screen.dart`), the Exercise Progress
detail page (`lib/features/stats/exercise_progress_screen.dart`), and the shared
computation and value types both read —
`StatsProgressService.computeExerciseMetrics()` in
`lib/core/services/stats_progress_service.dart`, and `ExerciseMetricSummary` and
`NativeValue` in `lib/core/models/exercise_metric.dart`.

## Overview

Two read-only screens answering per-exercise questions the
[Stats screen](stats_screen.md) cannot: *what are my bests across every exercise I
train?* and *how has one exercise moved?* Records & Trends is the index; Exercise
Progress is one exercise's page.

Both screens read one `StatsProgressService.computeExerciseMetrics()` result and
format values through the same shared formatters, so a best shown in the index and
the same best shown on the detail page cannot disagree. The service only reads: an
all-time best describes what is already stored, creates no PR event and writes
nothing. The PR list Records & Trends renders is the service's own `recentPRs` —
the same list, in the same order, as the Stats screen's.

Verified by `test/records_and_trends_screen_test.dart` (`S-913` for the totals and
the PR list, `S-914` for the shared best) and
`test/exercise_metric_service_test.dart`.

---

## Navigation Entry Point

```
StatsScreen
  ├── header chart icon → RecordsAndTrendsScreen
  │     └── entry → ExerciseProgressScreen
  └── Instruments row → ExerciseProgressScreen
```

`StatsScreen` is the only file in `lib/` that constructs
`RecordsAndTrendsScreen`, so the header chart icon is the only entry point into
Records & Trends. Exercise Progress has two entry points — an entry in Records &
Trends and a row of the Stats screen's Instruments list — and nothing else in
`lib/` pushes it. The detail screen is named exactly `Exercise Progress`.

Verified by `test/records_and_trends_screen_test.dart` (the single-entry-point
case, the Exercise Progress entry-point guard, and `S-913`) and by
`test/instrument_list_screen_test.dart` (`S-1014`).

---

## Sections and the effort-kind rule

One entry per exercise that appears in at least one **completed** session; a
session still in progress contributes nothing. Entries are grouped under one
header per `ExerciseSection`, in the enum's declaration order (Resistance →
Cardio → Isometric → Sports), and a section with no matching entry is omitted.

An exercise's section is the effort kind it was logged under most: `set` →
Resistance, `timed` → Cardio, `drill` → Isometric, `round` → Sports. A tie
resolves in that same order, so an exercise logged under two kinds sits in exactly
one section.

Entries are ordered by training-day share descending, then by name, then by id.
The tie-breaks are what keep the order independent of the order the store happened
to return rows in.

Verified by `test/records_and_trends_screen_test.dart` (`S-912` for the section
order and the entry order) and `test/exercise_metric_service_test.dart` (`S-905`
for the section rule).

---

## The native value per section

Each section reads its exercises by one number, the exercise's **native value**:

| Section | Metric | Second figure |
|---------|--------|---------------|
| Resistance | Estimated one-rep max, or the rep count for a reps-axis exercise | — |
| Cardio | Pace, or total duration when no distance qualifies | — |
| Isometric | Longest hold | Total hold time |
| Sports | Rounds completed | Total round minutes |

A sports entry counts rounds by the rule `StatsProgressService` applies rather
than by the stored `completed` flag; the rule itself is stated in
[Services and Utils](state_management/services_and_utils.md).

A resistance exercise is reps-axis when any set anywhere in its history carries
reps with no load, so the axis is a property of the exercise's history rather than
of the range being read. An isometric value also carries the added weight of the
entry the holding effort belongs to; that annotation never decides the metric. A
cardio value is marked `est.` when any distance behind its pace came from an
estimated source — the same marker rule the Stats screen's CARDIO section uses.

An exercise with no usable data reports a zero on the metric its section uses
instead of being dropped, so no entry can appear without a value.

Verified by `test/exercise_metric_service_test.dart` (`S-904`, `S-906`, `S-907`,
`S-908`) and `test/records_and_trends_screen_test.dart` (`S-915` for the rendered
label).

---

## Search

The field filters entries by `FuzzySearch.matches` against the exercise name — a
substring hit or a close-enough miss — and never reorders what survives. A query
that matches nothing leaves no section header at all, and clearing the field
restores the full list.

Verified by `test/records_and_trends_screen_test.dart` (`S-912`).

---

## Exercise Progress

One exercise over its whole history: its name, its native value, the series, and
the recent training days newest first, capped at `kRecentSessionCount`.

The series holds **one point per training day**, not one per session: two sessions
on one day are one point, carrying that day's value for the metric. A day that
yields no value contributes no point, so a series can hold fewer points than the
exercise has training days. Sessions that were never completed contribute nothing,
so a cancelled session is absent from both the series and the list.

An id with no history reaches an empty state instead of throwing. The entry list
cannot offer such an id, so that state guards against a stale id rather than being
a route a user walks.

Verified by `test/records_and_trends_screen_test.dart` (`S-910` for both empty
states, `S-915` for the series, the best and the list order).

---

## Related Documentation

- [Stats Screen](stats_screen.md) — the screen the chart icon sits in
- [Modality Tracking](modality_tracking.md) — effort kinds, capabilities and what they imply
- [Navigation & Screens](navigation_and_screens.md)
- [Data Models](data_models.md)

---

**Document Version**: 1.0
**Last Updated**: October 1, 2026
