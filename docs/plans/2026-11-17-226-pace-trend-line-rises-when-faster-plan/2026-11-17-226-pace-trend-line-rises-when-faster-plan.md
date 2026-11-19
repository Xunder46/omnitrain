# Plan 226 — A faster pace rises on the trend line

Series: second Stats review (Fable, 2026-11-17) small item 5, after plan 209 (the pace change arrow reads faster = up in the good colour, owner decision 2026-11-15). Phone only (`lib/features/stats`), one builder run, then docs. Status: COMMITTED (built, mutation-checked, verified; no separate review run: small presentation change, 5 mutants killed).

## Goal and acceptance

Pace is seconds per kilometre, so a faster pace is a smaller number and its trend line slopes DOWN while the change arrow beside it says up in the good colour. The two now disagree. After this change the pace trend is drawn flipped, so getting faster goes up on both the Instruments sparkline and the Exercise Progress chart.

Acceptance: S-22601..S-22604 green, the ones marked "fails without" red at the base commit; the chart readers (`exercise_progress*`, `instrument_sparkline*`, `instrument_list_screen_test`, `records_and_trends_screen_test`, `scrollable_trend_chart*`) green or reported; `flutter analyze` at baseline (181, 0 errors); full suite no new red.

## What the user sees

- Pace (and only pace, the one metric where lower is better): the little trend line beside an Instruments row and the chart on Exercise Progress rise as the runner gets faster. The y-axis ticks still read true clock values (`5:30` /km), with the faster paces at the top.
- Every other metric (e1RM, reps, duration, distance, rounds) is drawn exactly as before.
- Nothing else changes: values, change arrows, best, day list.
- To SEE it: a run history that gets faster week over week; look at the row's line and open the exercise.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | `InstrumentSparkline` (`instrument_sparkline.dart`) paints `plottedValues(points)`: a new `@visibleForTesting static List<double> plottedValues(List<ExerciseMetricPoint> points)` returning each value, negated when `point.value.metric == NativeMetric.pace` (the painter normalises min-max, so a negation flips the line). | `instrument_sparkline.dart:22-48` |
| D-2 | Exercise Progress `_buildChart` (`exercise_progress_screen.dart:210-300`): when `metric == NativeMetric.pace` the plotted y is the reflection `bounds.min + bounds.max - value` for every spot (bounds are still computed on the true values), `minY`/`maxY` stay `bounds.min`/`bounds.max`, and the left-axis label formatter maps a plotted value back with the same reflection before formatting as a clock. Reflection (not negation) keeps the existing nice-tick bounds and clock formatter. | `exercise_progress_screen.dart:236-254` |
| D-3 | A line with one point is unchanged (single-point card). | `exercise_progress_screen.dart:230-236` |
| D-4 | The direction is the lead's default, following the owner's plan 209 ruling (faster reads up). | scope |

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-22601 | `InstrumentSparkline.plottedValues` over three pace points 330, 320, 310 s/km (improving). | `[-330, -320, -310]` (rising). | the base plots `[330, 320, 310]` (falling) |
| S-22602 | The same over e1RM points 100, 110, 120. | `[100, 110, 120]`. | passes with and without the change on purpose: a non-pace metric is untouched (mutation: the flip applies to every metric) |
| S-22603 | Exercise Progress (Mock widget test) for a cardio exercise with a pace series that improves over three days (use the fixtures of `test/exercise_metric_service_test.dart` / `records_and_trends_screen_test.dart` S-915 for a distance + duration pace). | the `LineChart`'s first line has spot ys strictly rising left to right; the axis label formatter given `maxY` returns the clock of the fastest pace and given `minY` the slowest. | the base's spots fall |
| S-22604 | Exercise Progress for a lifting exercise with rising e1RM. | spot ys equal the displayed values (rising), unchanged. | passes both ways on purpose (mutation: the reflection applies to every metric) |

## Input-reality checklist

1. Writers and units: none; presentation. Pace units follow the settings (`nativeMetricDisplayValue`), still lower-is-better.
2. Lifecycle: none.
3. Settings: unit (km/mi) changes the numbers, not the direction.
4. Time: none.
5. Cost: none.
6. Words: none.
7. Slot competition: none.

## Phases

1. **P1 builder-app**, scope `lib/features/stats/widgets/instrument_sparkline.dart`, `lib/features/stats/exercise_progress_screen.dart`, `test/pace_trend_direction_test.dart` (new): exact approach in the brief. No full suite.
2. **P2 lead**: docs, mutation pass, full suite.

## Readers

`test/instrument_list_screen_test.dart` (sparkline cases), `test/records_and_trends_screen_test.dart` (S-915 series/chart), any test that reads `LineChart` spots or the axis formatter for a pace (`grep -rln "LineChart\|plottedValues\|yLabelFormatter" test`). A reader that pins a falling pace line is reported, not edited.

## Mutation list (lead)

(a) the flip is removed; (b) the flip applies to every metric; (c) the axis label formatter is not reflected (labels read wrong); (d) only the sparkline flips.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/records_and_trends.md` | ADDED | - | the line is drawn flipped | S-22603 |

Stale-term sweep: none expected (`grep -rIn "slopes\|sparkline" docs` outside plans).

## Open items

1. (owner) A look at a real run history: faster rising, axis labels true.
2. Pace is the only lower-is-better metric (`exercise_metric.dart:33`); if another is added it needs the same flip.

## Predicted files

`instrument_sparkline.dart` (+12), `exercise_progress_screen.dart` (+20), one new test file, one doc.

## Progress

- [x] Seeded
- [x] P1 build
- [x] Docs, mutation pass (5 mutants killed), full suite

## Assumption Log

- 2026-11-17: base commit `9990601c` on `claude_develop`; other sessions' files (plans 223/225, watch Swift, plan 208, gallery test) are outside this plan. Plan number 225 belongs to another session.
- 2026-11-17: scenario ids S-226xx: none found.

## Feedback

(none yet)
