import '../data/models/models.dart';

/// Seed data for development and testing purposes
class SeedData {
  static final List<SportCategory> sampleSportCategories = [
    SportCategory(
      id: 'category-cardio',
      key: 'cardio_endurance',
      name: 'Cardio / Endurance',
      description: 'Running, cycling, swimming, rowing',
      iconName: 'directions_run',
      sortOrder: 1,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-strength',
      key: 'strength_resistance',
      name: 'Strength / Resistance',
      description: 'Weightlifting, bodybuilding, powerlifting',
      iconName: 'fitness_center',
      sortOrder: 2,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-combat',
      key: 'martial_arts_combat',
      name: 'Martial Arts / Combat',
      description: 'Boxing, BJJ, Muay Thai, wrestling',
      iconName: 'sports_mma',
      sortOrder: 3,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-sports',
      key: 'sports_games',
      name: 'Sports / Games',
      description: 'Soccer, basketball, tennis, general sports',
      iconName: 'sports_soccer',
      sortOrder: 4,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-mobility',
      key: 'mobility_flexibility',
      name: 'Mobility / Flexibility',
      description: 'Yoga, stretching, mobility work',
      iconName: 'self_improvement',
      sortOrder: 5,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-recovery',
      key: 'recovery_rehab',
      name: 'Recovery / Rehab',
      description: 'Active recovery, physical therapy, rehab',
      iconName: 'spa',
      sortOrder: 6,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<Discipline> sampleDisciplines = [
    // Cardio / Endurance
    Discipline(
      id: 'discipline-running',
      categoryId: 'category-cardio',
      key: 'running',
      name: 'Running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-cycling',
      categoryId: 'category-cardio',
      key: 'cycling',
      name: 'Cycling',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-swimming',
      categoryId: 'category-cardio',
      key: 'swimming',
      name: 'Swimming',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-rowing',
      categoryId: 'category-cardio',
      key: 'rowing',
      name: 'Rowing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Strength / Resistance
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
    Discipline(
      id: 'discipline-calisthenics',
      categoryId: 'category-strength',
      key: 'calisthenics',
      name: 'Calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Martial Arts / Combat
    Discipline(
      id: 'discipline-boxing',
      categoryId: 'category-combat',
      key: 'boxing',
      name: 'Boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-bjj',
      categoryId: 'category-combat',
      key: 'bjj',
      name: 'Brazilian Jiu-Jitsu',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-muay-thai',
      categoryId: 'category-combat',
      key: 'muay_thai',
      name: 'Muay Thai',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Sports / Games
    Discipline(
      id: 'discipline-soccer',
      categoryId: 'category-sports',
      key: 'soccer',
      name: 'Soccer',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-basketball',
      categoryId: 'category-sports',
      key: 'basketball',
      name: 'Basketball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Mobility / Flexibility
    Discipline(
      id: 'discipline-yoga',
      categoryId: 'category-mobility',
      key: 'yoga',
      name: 'Yoga',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-stretching',
      categoryId: 'category-mobility',
      key: 'stretching',
      name: 'Stretching',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Recovery / Rehab
    Discipline(
      id: 'discipline-active-recovery',
      categoryId: 'category-recovery',
      key: 'active_recovery',
      name: 'Active Recovery',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

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

  static final List<Exercise> sampleExercises = [
    // Strength exercises
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
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dip',
      name: 'Dips',
      description: 'Bodyweight pushing exercise',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-calisthenics',
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
    // Cardio exercises (activity names, not exercises in traditional sense)
    Exercise(
      id: 'exercise-run',
      name: 'Run',
      description: 'Outdoor or treadmill running',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-treadmill-run',
      name: 'Treadmill Run',
      description: 'Indoor treadmill running',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cycling-outdoor',
      name: 'Cycling (Outdoor)',
      description: 'Outdoor cycling',
      disciplineId: 'discipline-cycling',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Combat exercises
    Exercise(
      id: 'exercise-heavy-bag-rounds',
      name: 'Heavy Bag Rounds',
      description: 'Boxing heavy bag work',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-shadowboxing',
      name: 'Shadowboxing',
      description: 'Boxing technique and conditioning',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Mobility exercises
    Exercise(
      id: 'exercise-couch-stretch',
      name: 'Couch Stretch',
      description: 'Hip flexor and quad stretch',
      disciplineId: 'discipline-stretching',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-plank',
      name: 'Plank',
      description: 'Isometric core exercise',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<Equipment> sampleEquipment = [
    Equipment(
      id: 'equipment-barbell',
      name: 'Barbell',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Equipment(
      id: 'equipment-dumbbell',
      name: 'Dumbbell',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Equipment(
      id: 'equipment-kettlebell',
      name: 'Kettlebell',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Equipment(
      id: 'equipment-resistance-band',
      name: 'Resistance Band',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Equipment(
      id: 'equipment-pullup-bar',
      name: 'Pull-up Bar',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Equipment(
      id: 'equipment-treadmill',
      name: 'Treadmill',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Equipment(
      id: 'equipment-heavy-bag',
      name: 'Heavy Bag',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Equipment(
      id: 'equipment-bodyweight',
      name: 'Body Weight',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<Tag> sampleTags = [
    Tag(
      id: 'tag-legs',
      name: 'Legs',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Tag(
      id: 'tag-push',
      name: 'Push',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Tag(
      id: 'tag-pull',
      name: 'Pull',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Tag(
      id: 'tag-core',
      name: 'Core',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Tag(
      id: 'tag-isometric',
      name: 'Isometric',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Tag(
      id: 'tag-stretching',
      name: 'Stretching',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Tag(
      id: 'tag-full-body',
      name: 'Full Body',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<UnitModel> defaultUnits = [
    // Weight
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
    // Time
    UnitModel(
      id: 'unit-sec',
      key: 'sec',
      name: 'Seconds',
      unitType: 'time',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    UnitModel(
      id: 'unit-min',
      key: 'min',
      name: 'Minutes',
      unitType: 'time',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Distance
    UnitModel(
      id: 'unit-m',
      key: 'm',
      name: 'Meters',
      unitType: 'distance',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    UnitModel(
      id: 'unit-km',
      key: 'km',
      name: 'Kilometers',
      unitType: 'distance',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    UnitModel(
      id: 'unit-mi',
      key: 'mi',
      name: 'Miles',
      unitType: 'distance',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Energy
    UnitModel(
      id: 'unit-cal',
      key: 'cal',
      name: 'Calories',
      unitType: 'energy',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Heart Rate
    UnitModel(
      id: 'unit-bpm',
      key: 'bpm',
      name: 'Beats per Minute',
      unitType: 'heart_rate',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Count
    UnitModel(
      id: 'unit-reps',
      key: 'reps',
      name: 'Repetitions',
      unitType: 'count',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    UnitModel(
      id: 'unit-rounds',
      key: 'rounds',
      name: 'Rounds',
      unitType: 'count',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  static final List<MetricDefinition> defaultMetrics = [
    // Strength metrics
    MetricDefinition(
      id: 'metric-reps',
      key: 'reps',
      name: 'Repetitions',
      dataType: 'int',
      defaultUnitId: 'unit-reps',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MetricDefinition(
      id: 'metric-weight',
      key: 'weight',
      name: 'Weight',
      dataType: 'real',
      defaultUnitId: 'unit-kg',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MetricDefinition(
      id: 'metric-rpe',
      key: 'rpe',
      name: 'RPE (Rate of Perceived Exertion)',
      dataType: 'int',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Time metrics
    MetricDefinition(
      id: 'metric-duration',
      key: 'duration',
      name: 'Duration',
      dataType: 'int',
      defaultUnitId: 'unit-sec',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MetricDefinition(
      id: 'metric-rest',
      key: 'rest',
      name: 'Rest Time',
      dataType: 'int',
      defaultUnitId: 'unit-sec',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Distance metrics
    MetricDefinition(
      id: 'metric-distance',
      key: 'distance',
      name: 'Distance',
      dataType: 'real',
      defaultUnitId: 'unit-m',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MetricDefinition(
      id: 'metric-pace',
      key: 'pace',
      name: 'Pace (min/km)',
      dataType: 'real',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Round-based metrics
    MetricDefinition(
      id: 'metric-rounds',
      key: 'rounds',
      name: 'Rounds',
      dataType: 'int',
      defaultUnitId: 'unit-rounds',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    MetricDefinition(
      id: 'metric-round-duration',
      key: 'round_duration',
      name: 'Round Duration',
      dataType: 'int',
      defaultUnitId: 'unit-sec',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // AMRAP metrics
    MetricDefinition(
      id: 'metric-score',
      key: 'score',
      name: 'Score',
      dataType: 'int',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Drill/Skill metrics
    MetricDefinition(
      id: 'metric-quality',
      key: 'quality',
      name: 'Quality Rating',
      dataType: 'int',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Heart rate
    MetricDefinition(
      id: 'metric-heart-rate',
      key: 'heart_rate',
      name: 'Heart Rate',
      dataType: 'int',
      defaultUnitId: 'unit-bpm',
      isCore: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  /// Maps metric IDs to effort kinds (block types)
  static final List<MetricApplicability> metricApplicability = [
    // Strength Sets (set)
    MetricApplicability(metricId: 'metric-reps', effortKind: 'set'),
    MetricApplicability(metricId: 'metric-weight', effortKind: 'set'),
    MetricApplicability(metricId: 'metric-rpe', effortKind: 'set'),
    MetricApplicability(metricId: 'metric-rest', effortKind: 'set'),
    
    // Timed Activity (timed)
    MetricApplicability(metricId: 'metric-duration', effortKind: 'timed'),
    MetricApplicability(metricId: 'metric-distance', effortKind: 'timed'),
    MetricApplicability(metricId: 'metric-heart-rate', effortKind: 'timed'),
    MetricApplicability(metricId: 'metric-rpe', effortKind: 'timed'),
    
    // Distance Intervals (interval)
    MetricApplicability(metricId: 'metric-distance', effortKind: 'interval'),
    MetricApplicability(metricId: 'metric-duration', effortKind: 'interval'),
    MetricApplicability(metricId: 'metric-pace', effortKind: 'interval'),
    MetricApplicability(metricId: 'metric-rest', effortKind: 'interval'),
    MetricApplicability(metricId: 'metric-heart-rate', effortKind: 'interval'),
    
    // Round-Based (round)
    MetricApplicability(metricId: 'metric-rounds', effortKind: 'round'),
    MetricApplicability(metricId: 'metric-round-duration', effortKind: 'round'),
    MetricApplicability(metricId: 'metric-rpe', effortKind: 'round'),
    
    // AMRAP / For Time (amrap)
    MetricApplicability(metricId: 'metric-score', effortKind: 'amrap'),
    MetricApplicability(metricId: 'metric-duration', effortKind: 'amrap'),
    MetricApplicability(metricId: 'metric-rpe', effortKind: 'amrap'),
    
    // Drill / Skill (drill)
    MetricApplicability(metricId: 'metric-duration', effortKind: 'drill'),
    MetricApplicability(metricId: 'metric-reps', effortKind: 'drill'),
    MetricApplicability(metricId: 'metric-quality', effortKind: 'drill'),
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
    'exercise-plank': ['muscle-core'],
  };

  /// Maps exercise IDs to equipment IDs
  static final Map<String, List<String>> exerciseEquipmentRelationships = {
    'exercise-squat': ['equipment-barbell'],
    'exercise-bench': ['equipment-barbell'],
    'exercise-deadlift': ['equipment-barbell'],
    'exercise-ohp': ['equipment-barbell'],
    'exercise-row': ['equipment-barbell'],
    'exercise-pullup': ['equipment-pullup-bar'],
    'exercise-dip': ['equipment-bodyweight'],
    'exercise-lunge': ['equipment-dumbbell', 'equipment-bodyweight'],
    'exercise-curl': ['equipment-dumbbell', 'equipment-barbell'],
    'exercise-tricep-extension': ['equipment-dumbbell'],
    'exercise-treadmill-run': ['equipment-treadmill'],
    'exercise-heavy-bag-rounds': ['equipment-heavy-bag'],
    'exercise-shadowboxing': ['equipment-bodyweight'],
    'exercise-couch-stretch': ['equipment-bodyweight'],
    'exercise-plank': ['equipment-bodyweight'],
  };

  /// Sample workout templates
  static final List<WorkoutTemplate> sampleTemplates = [
    WorkoutTemplate(
      id: 'template-upper-strength',
      name: 'Upper Body Strength',
      primaryDisciplineId: 'discipline-powerlifting',
      note: 'Classic upper body strength session',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    WorkoutTemplate(
      id: 'template-easy-run',
      name: 'Easy Run',
      primaryDisciplineId: 'discipline-running',
      note: 'Easy endurance run',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    WorkoutTemplate(
      id: 'template-boxing-rounds',
      name: 'Boxing Rounds',
      primaryDisciplineId: 'discipline-boxing',
      note: 'Heavy bag and shadowboxing rounds',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    WorkoutTemplate(
      id: 'template-mobility',
      name: 'Full Body Stretch',
      primaryDisciplineId: 'discipline-stretching',
      note: 'Comprehensive stretching routine',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  /// Template segments for sample templates
  static final List<TemplateSegment> sampleTemplateSegments = [
    // Upper Body Strength template segments
    TemplateSegment(
      id: 'tseg-upper-1',
      templateId: 'template-upper-strength',
      orderIndex: 0,
      segmentType: 'strength_sets',
      name: 'Main Lifts',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Easy Run template segments
    TemplateSegment(
      id: 'tseg-run-1',
      templateId: 'template-easy-run',
      orderIndex: 0,
      segmentType: 'timed_activity',
      name: 'Main Run',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing template segments
    TemplateSegment(
      id: 'tseg-boxing-1',
      templateId: 'template-boxing-rounds',
      orderIndex: 0,
      segmentType: 'round_based',
      name: 'Heavy Bag Work',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Mobility template segments
    TemplateSegment(
      id: 'tseg-mobility-1',
      templateId: 'template-mobility',
      orderIndex: 0,
      segmentType: 'drill_skill',
      name: 'Stretching Routine',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  /// Template efforts for sample template segments
  static final List<TemplateEffort> sampleTemplateEfforts = [
    // Upper Body Strength efforts
    TemplateEffort(
      id: 'teff-upper-bench',
      templateSegmentId: 'tseg-upper-1',
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: 'exercise-bench',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    TemplateEffort(
      id: 'teff-upper-ohp',
      templateSegmentId: 'tseg-upper-1',
      orderIndex: 1,
      effortKind: 'set',
      exerciseId: 'exercise-ohp',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    TemplateEffort(
      id: 'teff-upper-row',
      templateSegmentId: 'tseg-upper-1',
      orderIndex: 2,
      effortKind: 'set',
      exerciseId: 'exercise-row',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Easy Run effort
    TemplateEffort(
      id: 'teff-run-main',
      templateSegmentId: 'tseg-run-1',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'exercise-run',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing effort
    TemplateEffort(
      id: 'teff-boxing-bag',
      templateSegmentId: 'tseg-boxing-1',
      orderIndex: 0,
      effortKind: 'round',
      exerciseId: 'exercise-heavy-bag-rounds',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Mobility effort
    TemplateEffort(
      id: 'teff-mobility-stretch',
      templateSegmentId: 'tseg-mobility-1',
      orderIndex: 0,
      effortKind: 'drill',
      exerciseId: 'exercise-couch-stretch',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  /// Template targets (suggested values for template efforts)
  static final List<TemplateTarget> sampleTemplateTargets = [
    // Bench Press: 3 sets x 5 reps
    TemplateTarget(
      id: 'ttar-bench-sets',
      templateEffortId: 'teff-upper-bench',
      metricId: 'metric-reps',
      targetInt: 5,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Easy Run: 30 minutes
    TemplateTarget(
      id: 'ttar-run-duration',
      templateEffortId: 'teff-run-main',
      metricId: 'metric-duration',
      targetInt: 1800, // 30 minutes in seconds
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing: 5 rounds x 3 minutes
    TemplateTarget(
      id: 'ttar-boxing-rounds',
      templateEffortId: 'teff-boxing-bag',
      metricId: 'metric-rounds',
      targetInt: 5,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    TemplateTarget(
      id: 'ttar-boxing-duration',
      templateEffortId: 'teff-boxing-bag',
      metricId: 'metric-round-duration',
      targetInt: 180, // 3 minutes in seconds
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Stretching: 30-60 seconds per stretch
    TemplateTarget(
      id: 'ttar-stretch-duration',
      templateEffortId: 'teff-mobility-stretch',
      metricId: 'metric-duration',
      targetMin: 30.0,
      targetMax: 60.0,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];
}
