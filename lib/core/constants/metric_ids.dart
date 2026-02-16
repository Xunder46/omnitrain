/// Standard metric IDs used throughout the app
/// Ensures consistency between mock and SQLite implementations
class MetricIds {
  // Strength/resistance metrics
  static const String reps = 'metric-reps';
  static const String weight = 'metric-weight';
  static const String sets = 'metric-sets';

  // Time-based metrics
  static const String duration = 'metric-duration';
  static const String distance = 'metric-distance';

  // Round/segment metrics
  static const String rounds = 'metric-rounds';
  static const String roundDuration = 'metric-round-duration';

  // Subjective metrics
  static const String rpe = 'metric-rpe'; // Rate of Perceived Exertion
  static const String rest = 'metric-rest';

  // Unit IDs
  static const String unitReps = 'unit-reps';
  static const String unitKg = 'unit-kg';
  static const String unitSeconds = 'unit-sec';
  static const String unitMeters = 'unit-m';
  static const String unitRounds = 'unit-rounds';

  /// Map of shorthand keys to metric IDs for UI value updates
  /// Used by WorkoutState.updateEntryValue() and similar state management code
  /// Allows consistent key naming across UI layers
  static const Map<String, String> keyToMetricId = {
    'reps': reps,
    'weight': weight,
    'duration': duration,
    'distance': distance,
    'rounds': rounds,
    'round-duration': roundDuration,
    'rpe': rpe,
  };

  /// Reverse map: metric IDs back to shorthand keys
  /// Used by RoutineState and other code that needs to convert metric IDs to display keys
  static const Map<String, String> metricIdToKey = {
    reps: 'reps',
    weight: 'weight',
    duration: 'duration',
    distance: 'distance',
    rounds: 'rounds',
    roundDuration: 'round-duration',
    rpe: 'rpe',
  };
}
