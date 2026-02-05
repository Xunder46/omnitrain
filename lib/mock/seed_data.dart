import '../data/models/models.dart';

/// Seed data for development and testing purposes
class SeedData {
  static final List<Exercise> sampleExercises = [
    Exercise(
      id: 'exercise-squat',
      name: 'Barbell Squat',
      description: 'Compound lower body exercise',
      movementPattern: 'squat',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bench',
      name: 'Bench Press',
      description: 'Compound upper body push exercise',
      movementPattern: 'horizontal_push',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-deadlift',
      name: 'Deadlift',
      description: 'Compound posterior chain exercise',
      movementPattern: 'hinge',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-ohp',
      name: 'Overhead Press',
      description: 'Compound vertical push exercise',
      movementPattern: 'vertical_push',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-row',
      name: 'Barbell Row',
      description: 'Compound horizontal pull exercise',
      movementPattern: 'horizontal_pull',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<UnitModel> defaultUnits = [
    UnitModel(
      id: 'unit-kg',
      key: 'kg',
      name: 'Kilograms',
      unitType: 'weight',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    UnitModel(
      id: 'unit-lbs',
      key: 'lbs',
      name: 'Pounds',
      unitType: 'weight',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    UnitModel(
      id: 'unit-reps',
      key: 'reps',
      name: 'Repetitions',
      unitType: 'count',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<MetricDefinition> defaultMetrics = [
    MetricDefinition(
      id: 'metric-weight',
      key: 'weight',
      name: 'Weight',
      dataType: 'real',
      defaultUnitId: 'unit-kg',
      isCore: true,
      appliesToEffortKind: 'strength',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MetricDefinition(
      id: 'metric-reps',
      key: 'reps',
      name: 'Repetitions',
      dataType: 'int',
      defaultUnitId: 'unit-reps',
      isCore: true,
      appliesToEffortKind: 'strength',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];
}
