/// Metric stepping for the watch logging surfaces.
///
/// Plan: `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`,
/// scenario S-007 — one rotary detent moves a value by an amount that follows
/// from the metric and the saved unit preference, never from the surface. The
/// watchOS client mirrors this table so a crown turn means the same thing on
/// both wrists.
///
/// Values are canonical (reps, kilograms, seconds, metres) and converted for
/// display through `UnitFormatter`, which owns the conversion constants.
library;

import '../../core/sync_protocol/wire_limits.dart';
import '../../core/utils/unit_formatter.dart';
import '../../state/settings/settings_state.dart';

/// The metric keys a logging surface can edit, matching
/// `MetricIds.keyToMetricId` — the vocabulary the rest of the app already
/// speaks. [all] is asserted against that map in
/// `test/watch_logging_stepping_test.dart`.
abstract final class WatchMetricKey {
  static const String reps = 'reps';
  static const String weight = 'weight';
  static const String duration = 'duration';
  static const String distance = 'distance';
  static const String rounds = 'rounds';
  static const String roundDuration = 'round-duration';
  static const String extraWeight = 'extra-weight';

  /// Extra load is a hold's companion metric: `EffortDefaults` gives a drill
  /// duration plus optional extra weight.
  static const List<String> all = [
    reps,
    weight,
    duration,
    distance,
    rounds,
    roundDuration,
    extraWeight,
  ];
}

/// The units a logging surface is set to. Weight and distance are the two
/// preferences that change what a detent means. It also carries the Rest Ping
/// interval the rest surface taps on, so no screen reads the setting itself.
class WatchUnitPreferences {
  const WatchUnitPreferences({
    this.weightUnit = 'kg',
    this.distanceUnit = 'km',
    this.restPingSeconds = 0,
  });

  /// The preferences the user has saved, read through their canonical owner so
  /// the wrist reads in the unit the phone does.
  factory WatchUnitPreferences.fromSettings(SettingsState settings) =>
      WatchUnitPreferences(
        weightUnit: settings.preferredWeightUnit,
        distanceUnit: settings.preferredDistanceUnit,
        restPingSeconds: settings.restPingInterval,
      );

  /// `kg` or `lbs`.
  final String weightUnit;

  /// `km` or `miles`.
  final String distanceUnit;

  /// The phone's Rest Ping interval in seconds, 0 when it is Off (or a wrist
  /// that has not heard from the phone yet).
  final int restPingSeconds;
}

/// What one rotary detent does, per metric.
abstract final class WatchMetricStepping {
  /// Load moves in the saved increment: 2.5 kg, or the 5 lb plate the user
  /// thinks in — converted once here, so the display reads exactly 5 lb.
  static const double kilogramsPerDetent = 2.5;
  static const double poundsPerDetent = 5;

  /// Duration moves in five-second steps, the granularity the phone uses for
  /// timed and held work.
  static const double secondsPerDetent = 5;

  /// Distance moves in a tenth of the display unit.
  static const double tenthsOfDistanceUnitPerDetent = 0.1;

  /// Counts move by one.
  static const double countPerDetent = 1;

  /// The canonical change one detent applies to [metricKey].
  static double stepFor(
    String metricKey, {
    WatchUnitPreferences units = const WatchUnitPreferences(),
  }) {
    switch (metricKey) {
      case WatchMetricKey.reps:
      case WatchMetricKey.rounds:
        return countPerDetent;
      case WatchMetricKey.weight:
      case WatchMetricKey.extraWeight:
        return UnitFormatter.toKilograms(
          UnitFormatter.normalizeWeightUnit(units.weightUnit) == 'lbs'
              ? poundsPerDetent
              : kilogramsPerDetent,
          units.weightUnit,
        );
      case WatchMetricKey.duration:
      case WatchMetricKey.roundDuration:
        return secondsPerDetent;
      case WatchMetricKey.distance:
        return tenthsOfDistanceUnitPerDetent *
            UnitFormatter.metresPerUnit(units.distanceUnit);
      default:
        return 0;
    }
  }

  /// [value] after [detents] rotations of the crown — positive is clockwise.
  static double adjust(
    double value, {
    required String metricKey,
    required double detents,
    WatchUnitPreferences units = const WatchUnitPreferences(),
  }) {
    return clampTo(
      metricKey,
      _quantize(value + detents * stepFor(metricKey, units: units)),
    );
  }

  /// Holds [value] inside the range the metric's own semantics allow: counts
  /// start at one, load is floored at the wire's own `-200 kg` (band assist,
  /// D-58/D-62), distance never goes negative, and extra load is signed because
  /// negative is band assist.
  static double clampTo(String metricKey, double value) {
    switch (metricKey) {
      case WatchMetricKey.reps:
      case WatchMetricKey.rounds:
        return value < countPerDetent ? countPerDetent : value;
      case WatchMetricKey.extraWeight:
        return value;
      case WatchMetricKey.weight:
        return value < WireLimits.minLoadKg ? WireLimits.minLoadKg : value;
      case WatchMetricKey.duration:
      case WatchMetricKey.distance:
      case WatchMetricKey.roundDuration:
        return value < 0 ? 0 : value;
      default:
        return value;
    }
  }

  /// Keeps repeated stepping from leaving float dust behind: a tenth of a
  /// millimetre of precision is not a value anyone entered.
  static double _quantize(double value) =>
      (value * 1000).roundToDouble() / 1000;
}
