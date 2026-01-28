class Workout {
  final String id;
  final String sportType;
  final DateTime startedAt;
  DateTime? endedAt;

  Workout({required this.id, required this.sportType, required this.startedAt, this.endedAt});
}

class Exercise {
  final String id;
  final String workoutId;
  final String name;
  final int order;

  Exercise({required this.id, required this.workoutId, required this.name, required this.order});
}

class SetRow {
  final String id;
  final String exerciseId;
  int reps;
  double weight;
  int duration; // seconds
  final int timestamp;

  SetRow({required this.id, required this.exerciseId, required this.reps, required this.weight, required this.duration, required this.timestamp});
}
