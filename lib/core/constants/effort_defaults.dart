/// Default metrics and values for each effort kind
/// Single source of truth for which metrics belong to which effort kinds
/// Used by RoutineState and WorkoutState for consistency
library;

import 'metric_ids.dart';
import 'workout_constants.dart';

class EffortDefaults {
  /// Default metric IDs and their initial values for each effort kind.
  ///
  /// [exerciseDefaultRoundDurationSecs] — when provided, overrides the global
  /// 180 s default for `'round'` efforts. Pass
  /// `Exercise.defaultRoundDurationSecs` here when the exercise is known.
  static Map<String, dynamic> getDefaultTargets(
    String effortKind, {
    int? exerciseDefaultRoundDurationSecs,
  }) {
    switch (effortKind) {
      case 'set':
        // Resistance training: reps + weight
        return {
          MetricIds.reps: 10,
          MetricIds.weight: 0.0,
        };
      case 'timed':
        // Cardio/endurance: duration + optional distance
        return {
          MetricIds.duration: 0,
          MetricIds.distance: 0.0,
        };
      case 'round':
        // Martial arts / sports: rounds + round duration.
        // Use the exercise-specific default when available (e.g. 45-min soccer
        // half = 2700 s), otherwise fall back to the global 3-min boxing default.
        return {
          MetricIds.rounds: 1,
          MetricIds.roundDuration:
              exerciseDefaultRoundDurationSecs ??
              WorkoutConstants.defaultRoundDurationSecs,
        };
      case 'drill':
        // Isometric / holds / skill work: duration + extra weight (negative = band assist, positive = added load)
        return {
          MetricIds.duration: 0,
          MetricIds.extraWeight: 0.0,
        };
      case 'interval':
        // Distance intervals: distance + optional duration
        return {
          MetricIds.distance: 0.0,
          MetricIds.duration: 0,
        };
      default:
        // Fallback to set-based (reps + weight)
        return {
          MetricIds.reps: 10,
          MetricIds.weight: 0.0,
        };
    }
  }

  /// Get the primary metrics for a given effort kind
  /// Used to determine which metrics to display/require
  static List<String> getPrimaryMetrics(String effortKind) {
    switch (effortKind) {
      case 'set':
        return [MetricIds.reps, MetricIds.weight];
      case 'timed':
        return [MetricIds.duration];
      case 'round':
        return [MetricIds.rounds, MetricIds.roundDuration];
      case 'drill':
        return [MetricIds.duration];
      case 'interval':
        return [MetricIds.distance];
      default:
        return [MetricIds.reps, MetricIds.weight];
    }
  }

  /// Get secondary/optional metrics for a given effort kind
  /// Used for advanced tracking options
  static List<String> getSecondaryMetrics(String effortKind) {
    switch (effortKind) {
      case 'set':
        return [];
      case 'timed':
        return [MetricIds.distance]; // Optional distance for cardio
      case 'round':
        return [];
      case 'drill':
        return [MetricIds.extraWeight]; // Extra load carried/worn during the hold (negative = band assist, positive = added load)
      case 'interval':
        return [MetricIds.duration]; // Optional duration for intervals
      default:
        return [];
    }
  }
}
