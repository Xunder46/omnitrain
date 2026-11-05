// Metric stepping for the phone's stepper rows.
//
// Plan: `docs/plans/2026-10-15-38b-reps-screen-plan/2026-10-15-38b-reps-screen-plan.md`.
// Scenario mapping:
//   S-4240 step constants and the unit -> step mapping; pinned to the watch's
//          own table so the two wrists cannot drift.
//
// The phone row steps in the *shown* unit (2.5 kg / 5 lb), the same numbers the
// wrist turns in. `lib/watch` may only be imported here, never from `lib/`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/metric_stepping.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';

void main() {
  group('S-4240 MetricStepping', () {
    test('reps step one, weight steps follow the saved unit', () {
      expect(MetricStepping.repsPerStep, 1);
      expect(MetricStepping.kilogramsPerStep, 2.5);
      expect(MetricStepping.poundsPerStep, 5);
    });

    test('weightStepFor maps the unit string, defaulting to kilograms', () {
      expect(
        MetricStepping.weightStepFor('kg'),
        MetricStepping.kilogramsPerStep,
      );
      expect(MetricStepping.weightStepFor('lbs'), MetricStepping.poundsPerStep);
      expect(
        MetricStepping.weightStepFor(null),
        MetricStepping.kilogramsPerStep,
      );
      expect(
        MetricStepping.weightStepFor('stone'),
        MetricStepping.kilogramsPerStep,
      );
    });

    test('steps are pinned to the watch table', () {
      expect(
        MetricStepping.kilogramsPerStep,
        WatchMetricStepping.kilogramsPerDetent,
      );
      expect(MetricStepping.poundsPerStep, WatchMetricStepping.poundsPerDetent);
    });
  });
}
