/// UI-specific set data structure for presentation-layer tracking
/// Not a persistence model - observations are persisted via EffortObservation entities
/// Used by WorkoutSessionScreen and RoutineSetupScreen for human-friendly set management
library;

class UiSetData {
  final String id;
  final String exerciseId;
  int reps;
  double weight;
  int duration; // seconds
  final int timestamp;

  UiSetData({
    required this.id,
    required this.exerciseId,
    required this.reps,
    required this.weight,
    required this.duration,
    required this.timestamp,
  });
}
