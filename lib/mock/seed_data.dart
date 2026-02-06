import '../data/models/models.dart';

/// Seed data for development and testing purposes
class SeedData {
  static final List<MuscleGroup> sampleMuscleGroups = [
    MuscleGroup(
      id: 'muscle-chest',
      name: 'Chest',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-back',
      name: 'Back',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-shoulders',
      name: 'Shoulders',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-biceps',
      name: 'Biceps',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-triceps',
      name: 'Triceps',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-quads',
      name: 'Quadriceps',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-hamstrings',
      name: 'Hamstrings',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-glutes',
      name: 'Glutes',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MuscleGroup(
      id: 'muscle-core',
      name: 'Core',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<Discipline> sampleDisciplines = [
    Discipline(
      id: 'discipline-powerlifting',
      categoryId: 'category-strength',
      key: 'powerlifting',
      name: 'Powerlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-bodybuilding',
      categoryId: 'category-strength',
      key: 'bodybuilding',
      name: 'Bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-weightlifting',
      categoryId: 'category-strength',
      key: 'weightlifting',
      name: 'Olympic Weightlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<Exercise> sampleExercises = [
    Exercise(
      id: 'exercise-squat',
      name: 'Barbell Squat',
      description: 'Compound lower body exercise',
      movementPattern: 'squat',
      disciplineId: 'discipline-powerlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bench',
      name: 'Bench Press',
      description: 'Compound upper body push exercise',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-powerlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-deadlift',
      name: 'Deadlift',
      description: 'Compound posterior chain exercise',
      movementPattern: 'hinge',
      disciplineId: 'discipline-powerlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-ohp',
      name: 'Overhead Press',
      description: 'Compound vertical push exercise',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-powerlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-row',
      name: 'Barbell Row',
      description: 'Compound horizontal pull exercise',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pullup',
      name: 'Pull-up',
      description: 'Bodyweight vertical pull exercise',
      movementPattern: 'vertical_pull',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dip',
      name: 'Dips',
      description: 'Bodyweight pushing exercise',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-lunge',
      name: 'Lunges',
      description: 'Unilateral lower body exercise',
      movementPattern: 'lunge',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-curl',
      name: 'Bicep Curl',
      description: 'Isolation exercise for biceps',
      movementPattern: 'curl',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tricep-extension',
      name: 'Tricep Extension',
      description: 'Isolation exercise for triceps',
      movementPattern: 'extension',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  /// Maps exercise IDs to muscle group IDs
  static final Map<String, List<String>> exerciseMuscleGroupRelationships = {
    'exercise-squat': ['muscle-quads', 'muscle-glutes', 'muscle-hamstrings'],
    'exercise-bench': ['muscle-chest', 'muscle-triceps', 'muscle-shoulders'],
    'exercise-deadlift': ['muscle-back', 'muscle-hamstrings', 'muscle-glutes'],
    'exercise-ohp': ['muscle-shoulders', 'muscle-triceps'],
    'exercise-row': ['muscle-back', 'muscle-biceps'],
    'exercise-pullup': ['muscle-back', 'muscle-biceps'],
    'exercise-dip': ['muscle-chest', 'muscle-triceps', 'muscle-shoulders'],
    'exercise-lunge': ['muscle-quads', 'muscle-glutes', 'muscle-hamstrings'],
    'exercise-curl': ['muscle-biceps'],
    'exercise-tricep-extension': ['muscle-triceps'],
  };

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
