/// Metric stepping for the phone's stepper rows.
///
/// Plan: `docs/plans/2026-10-15-38b-reps-screen-plan/2026-10-15-38b-reps-screen-plan.md`,
/// scenario S-4240 — one tap moves a value by an amount that follows from the
/// metric and the saved unit preference, never from the surface. The values are
/// pinned to the watch's own table (`WatchMetricStepping`) in
/// `test/metric_stepping_test.dart` so a crown detent and a phone tap stay the
/// same size.
///
/// Unlike the watch, the phone row works in the *shown* unit: the step is 2.5 kg
/// or 5 lb, and the caller converts the resulting value back to canonical
/// kilograms through `UnitFormatter.toCanonicalWeight`.
library;

import 'unit_formatter.dart';

/// What one tap on a stepper moves, per metric.
abstract final class MetricStepping {
  /// Load moves in the saved increment: 2.5 kg, or the 5 lb plate the user
  /// thinks in — the same numbers a watch crown detent uses.
  static const double kilogramsPerStep = 2.5;
  static const double poundsPerStep = 5;

  /// Reps move by one.
  static const int repsPerStep = 1;

  /// The weight step in the shown unit for [weightUnit] (`kg` or `lbs`).
  ///
  /// The input is the unit string (`settings.preferredWeightUnit`), so this
  /// stays free of `SettingsState`; anything that is not `lbs` steps in
  /// kilograms, as `UnitFormatter.normalizeWeightUnit` decides.
  static double weightStepFor(String? weightUnit) {
    return UnitFormatter.normalizeWeightUnit(weightUnit) == 'lbs'
        ? poundsPerStep
        : kilogramsPerStep;
  }
}
