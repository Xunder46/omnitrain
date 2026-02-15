import '../data/models/models.dart';

/// Seed data for development and testing purposes
class SeedData {
  static final List<SportCategory> sampleSportCategories = [
    // Primary home screen tiles (aligned with 6-tile layout)
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
      id: 'category-resistance',
      key: 'resistance_lifting',
      name: 'Resistance / Lifting',
      description: 'Weightlifting, bodybuilding, powerlifting, strength training',
      iconName: 'fitness_center',
      sortOrder: 2,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-martial-arts',
      key: 'martial_arts',
      name: 'Martial Arts',
      description: 'Boxing, BJJ, Muay Thai, wrestling, karate - part of unified Sports tile',
      iconName: 'sports_mma',
      sortOrder: 3,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-isometric',
      key: 'isometric_stretching',
      name: 'Isometric / Stretching',
      description: 'Yoga, static holds, stretching, flexibility work',
      iconName: 'self_improvement',
      sortOrder: 4,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    SportCategory(
      id: 'category-sports',
      key: 'sports',
      name: 'Sports',
      description: 'Boxing, BJJ, Muay Thai, wrestling, soccer, basketball, tennis, team sports',
      iconName: 'sports_soccer',
      sortOrder: 5,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Legacy categories (kept for backward compatibility)
    SportCategory(
      id: 'category-recovery',
      key: 'recovery_rehab',
      name: 'Recovery / Rehab',
      description: 'Active recovery, physical therapy, rehab',
      iconName: 'spa',
      sortOrder: 10,
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
    // Resistance / Lifting
    Discipline(
      id: 'discipline-powerlifting',
      categoryId: 'category-resistance',
      key: 'powerlifting',
      name: 'Powerlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-bodybuilding',
      categoryId: 'category-resistance',
      key: 'bodybuilding',
      name: 'Bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-weightlifting',
      categoryId: 'category-resistance',
      key: 'weightlifting',
      name: 'Olympic Weightlifting',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-calisthenics',
      categoryId: 'category-resistance',
      key: 'calisthenics',
      name: 'Calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Martial Arts
    Discipline(
      id: 'discipline-boxing',
      categoryId: 'category-martial-arts',
      key: 'boxing',
      name: 'Boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-bjj',
      categoryId: 'category-martial-arts',
      key: 'bjj',
      name: 'Brazilian Jiu-Jitsu',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-muay-thai',
      categoryId: 'category-martial-arts',
      key: 'muay_thai',
      name: 'Muay Thai',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Sports
    Discipline(
      id: 'discipline-tennis',
      categoryId: 'category-sports',
      key: 'tennis',
      name: 'Tennis',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-volleyball',
      categoryId: 'category-sports',
      key: 'volleyball',
      name: 'Volleyball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-badminton',
      categoryId: 'category-sports',
      key: 'badminton',
      name: 'Badminton',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-table-tennis',
      categoryId: 'category-sports',
      key: 'table_tennis',
      name: 'Table Tennis',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-cricket',
      categoryId: 'category-sports',
      key: 'cricket',
      name: 'Cricket',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-ice-hockey',
      categoryId: 'category-sports',
      key: 'ice_hockey',
      name: 'Ice Hockey',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-baseball',
      categoryId: 'category-sports',
      key: 'baseball',
      name: 'Baseball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-american-football',
      categoryId: 'category-sports',
      key: 'american_football',
      name: 'American Football',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-rugby',
      categoryId: 'category-sports',
      key: 'rugby',
      name: 'Rugby',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-lacrosse',
      categoryId: 'category-sports',
      key: 'lacrosse',
      name: 'Lacrosse',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Isometric / Stretching
    Discipline(
      id: 'discipline-yoga',
      categoryId: 'category-isometric',
      key: 'yoga',
      name: 'Yoga',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-stretching',
      categoryId: 'category-isometric',
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
    // Running exercises
    Exercise(
      id: 'exercise-easy-run',
      name: 'Easy Run',
      description: 'Low intensity steady run',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-long-run',
      name: 'Long Run',
      description: 'Extended endurance run',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tempo-run',
      name: 'Tempo Run',
      description: 'Sustained threshold pace run',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-interval-run',
      name: 'Interval Run',
      description: 'Repeated fast efforts with rest',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-hill-repeats',
      name: 'Hill Repeats',
      description: 'Uphill running intervals',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-fartlek',
      name: 'Fartlek',
      description: 'Unstructured pace variation run',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-recovery-run',
      name: 'Recovery Run',
      description: 'Very easy recovery pace run',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-track-repeats',
      name: 'Track Repeats',
      description: 'Measured distance intervals on track',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-progression-run',
      name: 'Progression Run',
      description: 'Run with gradually increasing pace',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-time-trial',
      name: 'Time Trial',
      description: 'Max effort over fixed distance or time',
      disciplineId: 'discipline-running',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Bodybuilding exercises
    Exercise(
      id: 'exercise-barbell-squat',
      name: 'Barbell Squat',
      description: 'Back squat with barbell',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bench-press',
      name: 'Bench Press',
      description: 'Barbell bench press',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-deadlift',
      name: 'Deadlift',
      description: 'Conventional barbell deadlift',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-overhead-press',
      name: 'Overhead Press',
      description: 'Standing barbell shoulder press',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pullup',
      name: 'Pull-Up',
      description: 'Bodyweight vertical pull',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-lat-pulldown',
      name: 'Lat Pulldown',
      description: 'Cable vertical pull',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dumbbell-row',
      name: 'Dumbbell Row',
      description: 'Single-arm dumbbell row',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-leg-press',
      name: 'Leg Press',
      description: 'Machine-based squat pattern',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-lateral-raise',
      name: 'Lateral Raise',
      description: 'Dumbbell shoulder isolation',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-triceps-pressdown',
      name: 'Triceps Pressdown',
      description: 'Cable triceps extension',
      disciplineId: 'discipline-bodybuilding',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing exercises
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
      description: 'Footwork and technique without equipment',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pad-work',
      name: 'Pad Work',
      description: 'Striking drills with pads',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-speed-bag',
      name: 'Speed Bag',
      description: 'Hand speed and rhythm training',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-double-end-bag',
      name: 'Double-End Bag',
      description: 'Timing and accuracy training',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-sparring',
      name: 'Sparring',
      description: 'Live boxing rounds',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-defensive-drills',
      name: 'Defensive Drills',
      description: 'Slips, rolls, and blocks practice',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-footwork-drills',
      name: 'Footwork Drills',
      description: 'Movement and positioning drills',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-conditioning-rounds',
      name: 'Conditioning Rounds',
      description: 'High intensity boxing rounds',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-technical-rounds',
      name: 'Technical Rounds',
      description: 'Low intensity skill-focused rounds',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Calisthenics/Isometric exercises
    Exercise(
      id: 'exercise-plank-hold',
      name: 'Plank Hold',
      description: 'Isometric core hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-side-plank',
      name: 'Side Plank',
      description: 'Lateral core isometric hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-wall-sit',
      name: 'Wall Sit',
      description: 'Isometric leg hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dead-hang',
      name: 'Dead Hang',
      description: 'Grip and shoulder isometric hang',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-hollow-body-hold',
      name: 'Hollow Body Hold',
      description: 'Anterior core isometric hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-glute-bridge-hold',
      name: 'Glute Bridge Hold',
      description: 'Hip extension isometric hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-l-sit-hold',
      name: 'L-Sit Hold',
      description: 'Advanced seated isometric hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-isometric-pushup-hold',
      name: 'Isometric Push-Up Hold',
      description: 'Paused push-up position hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-calf-raise-hold',
      name: 'Calf Raise Hold',
      description: 'Isometric calf contraction',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-split-squat-hold',
      name: 'Split Squat Hold',
      description: 'Unilateral leg isometric hold',
      disciplineId: 'discipline-calisthenics',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Sports exercises
    Exercise(
      id: 'exercise-tennis-match',
      name: 'Tennis Match',
      description: 'Full tennis match or practice game',
      disciplineId: 'discipline-tennis',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tennis-drill',
      name: 'Tennis Drill',
      description: 'Targeted tennis technique and footwork drills',
      disciplineId: 'discipline-tennis',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-volleyball-match',
      name: 'Volleyball Match',
      description: 'Full volleyball game or scrimmage',
      disciplineId: 'discipline-volleyball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-volleyball-drill',
      name: 'Volleyball Drill',
      description: 'Passing, setting, and spiking drills',
      disciplineId: 'discipline-volleyball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-badminton-match',
      name: 'Badminton Match',
      description: 'Full badminton game or rally practice',
      disciplineId: 'discipline-badminton',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-table-tennis-match',
      name: 'Table Tennis Match',
      description: 'Full table tennis game or practice',
      disciplineId: 'discipline-table-tennis',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cricket-match',
      name: 'Cricket Match',
      description: 'Cricket match or practice session',
      disciplineId: 'discipline-cricket',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-ice-hockey-match',
      name: 'Ice Hockey Match',
      description: 'Full ice hockey game or scrimmage',
      disciplineId: 'discipline-ice-hockey',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-baseball-game',
      name: 'Baseball Game',
      description: 'Full baseball game or practice',
      disciplineId: 'discipline-baseball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-american-football-game',
      name: 'American Football Game',
      description: 'Full American football game or scrimmage',
      disciplineId: 'discipline-american-football',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-rugby-match',
      name: 'Rugby Match',
      description: 'Full rugby game or practice match',
      disciplineId: 'discipline-rugby',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-lacrosse-game',
      name: 'Lacrosse Game',
      description: 'Full lacrosse game or scrimmage',
      disciplineId: 'discipline-lacrosse',
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
    // Bodybuilding exercises
    'exercise-barbell-squat': ['muscle-quads', 'muscle-glutes', 'muscle-hamstrings'],
    'exercise-bench-press': ['muscle-chest', 'muscle-triceps', 'muscle-shoulders'],
    'exercise-deadlift': ['muscle-back', 'muscle-hamstrings', 'muscle-glutes'],
    'exercise-overhead-press': ['muscle-shoulders', 'muscle-triceps'],
    'exercise-pullup': ['muscle-back', 'muscle-biceps'],
    'exercise-lat-pulldown': ['muscle-back', 'muscle-biceps'],
    'exercise-dumbbell-row': ['muscle-back', 'muscle-biceps'],
    'exercise-leg-press': ['muscle-quads', 'muscle-glutes', 'muscle-hamstrings'],
    'exercise-lateral-raise': ['muscle-shoulders'],
    'exercise-triceps-pressdown': ['muscle-triceps'],
    // Calisthenics exercises
    'exercise-plank-hold': ['muscle-core'],
    'exercise-side-plank': ['muscle-core', 'muscle-shoulders'],
    'exercise-wall-sit': ['muscle-quads', 'muscle-glutes'],
    'exercise-dead-hang': ['muscle-back', 'muscle-biceps'],
    'exercise-hollow-body-hold': ['muscle-core'],
    'exercise-glute-bridge-hold': ['muscle-glutes', 'muscle-core'],
    'exercise-l-sit-hold': ['muscle-core'],
    'exercise-isometric-pushup-hold': ['muscle-chest', 'muscle-triceps', 'muscle-shoulders'],
    'exercise-calf-raise-hold': ['muscle-hamstrings'],
    'exercise-split-squat-hold': ['muscle-quads', 'muscle-glutes', 'muscle-hamstrings'],
    // Sports exercises - full body engagement
    'exercise-tennis-match': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
    'exercise-tennis-drill': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
    'exercise-volleyball-match': ['muscle-shoulders', 'muscle-arms', 'muscle-core', 'muscle-legs'],
    'exercise-volleyball-drill': ['muscle-shoulders', 'muscle-arms', 'muscle-core'],
    'exercise-badminton-match': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
    'exercise-table-tennis-match': ['muscle-core', 'muscle-shoulders'],
    'exercise-cricket-match': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
    'exercise-ice-hockey-match': ['muscle-legs', 'muscle-core', 'muscle-shoulders'],
    'exercise-baseball-game': ['muscle-shoulders', 'muscle-core', 'muscle-legs'],
    'exercise-american-football-game': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
    'exercise-rugby-match': ['muscle-legs', 'muscle-core', 'muscle-shoulders'],
    'exercise-lacrosse-game': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
  };

  /// Maps exercise IDs to equipment IDs
  static final Map<String, List<String>> exerciseEquipmentRelationships = {
    // Bodybuilding exercises
    'exercise-barbell-squat': ['equipment-barbell'],
    'exercise-bench-press': ['equipment-barbell'],
    'exercise-deadlift': ['equipment-barbell'],
    'exercise-overhead-press': ['equipment-barbell'],
    'exercise-pullup': ['equipment-pullup-bar'],
    'exercise-lat-pulldown': [],
    'exercise-dumbbell-row': ['equipment-dumbbell'],
    'exercise-leg-press': [],
    'exercise-lateral-raise': ['equipment-dumbbell'],
    'exercise-triceps-pressdown': [],
    // Boxing exercises
    'exercise-heavy-bag-rounds': ['equipment-heavy-bag'],
    'exercise-shadowboxing': ['equipment-bodyweight'],
    'exercise-pad-work': [],
    'exercise-speed-bag': [],
    'exercise-double-end-bag': [],
    'exercise-sparring': ['equipment-bodyweight'],
    'exercise-defensive-drills': ['equipment-bodyweight'],
    'exercise-footwork-drills': ['equipment-bodyweight'],
    'exercise-conditioning-rounds': ['equipment-bodyweight'],
    'exercise-technical-rounds': ['equipment-bodyweight'],
    // Calisthenics exercises
    'exercise-plank-hold': ['equipment-bodyweight'],
    'exercise-side-plank': ['equipment-bodyweight'],
    'exercise-wall-sit': ['equipment-bodyweight'],
    'exercise-dead-hang': ['equipment-pullup-bar'],
    'exercise-hollow-body-hold': ['equipment-bodyweight'],
    'exercise-glute-bridge-hold': ['equipment-bodyweight'],
    'exercise-l-sit-hold': ['equipment-bodyweight'],
    'exercise-isometric-pushup-hold': ['equipment-bodyweight'],
    'exercise-calf-raise-hold': ['equipment-bodyweight'],
    'exercise-split-squat-hold': ['equipment-bodyweight'],
    // Sports exercises
    'exercise-tennis-match': ['equipment-bodyweight'],
    'exercise-tennis-drill': ['equipment-bodyweight'],
    'exercise-volleyball-match': ['equipment-bodyweight'],
    'exercise-volleyball-drill': ['equipment-bodyweight'],
    'exercise-badminton-match': ['equipment-bodyweight'],
    'exercise-table-tennis-match': ['equipment-bodyweight'],
    'exercise-cricket-match': ['equipment-bodyweight'],
    'exercise-ice-hockey-match': ['equipment-bodyweight'],
    'exercise-baseball-game': ['equipment-bodyweight'],
    'exercise-american-football-game': ['equipment-bodyweight'],
    'exercise-rugby-match': ['equipment-bodyweight'],
    'exercise-lacrosse-game': ['equipment-bodyweight'],
  };

  /// Maps exercise IDs to capability flags
  /// Hand-curated for seed data - each exercise declares which metrics it supports
  static final Map<String, List<String>> exerciseCapabilityRelationships = {
    // Running exercises - continuous time + distance tracking
    'exercise-easy-run': ['time', 'distance'],
    'exercise-long-run': ['time', 'distance'],
    'exercise-tempo-run': ['time', 'distance'],
    'exercise-interval-run': ['time', 'distance', 'rounds'],
    'exercise-hill-repeats': ['time', 'distance', 'rounds'],
    'exercise-fartlek': ['time', 'distance'],
    'exercise-recovery-run': ['time', 'distance'],
    'exercise-track-repeats': ['time', 'distance', 'rounds'],
    'exercise-progression-run': ['time', 'distance'],
    'exercise-time-trial': ['time', 'distance'],
    
    // Bodybuilding exercises - reps/sets/load primary, also support time for cardio-context
    'exercise-barbell-squat': ['reps', 'sets', 'load', 'time'],
    'exercise-bench-press': ['reps', 'sets', 'load', 'time'],
    'exercise-deadlift': ['reps', 'sets', 'load', 'time'],
    'exercise-overhead-press': ['reps', 'sets', 'load', 'time'],
    'exercise-pullup': ['reps', 'sets', 'load', 'time'],
    'exercise-lat-pulldown': ['reps', 'sets', 'load', 'time'],
    'exercise-dumbbell-row': ['reps', 'sets', 'load', 'time'],
    'exercise-leg-press': ['reps', 'sets', 'load', 'time'],
    'exercise-lateral-raise': ['reps', 'sets', 'load', 'time'],
    'exercise-triceps-pressdown': ['reps', 'sets', 'load', 'time'],
    
    // Boxing exercises - time and rounds based
    'exercise-heavy-bag-rounds': ['time', 'rounds'],
    'exercise-shadowboxing': ['time', 'rounds'],
    'exercise-pad-work': ['time', 'rounds'],
    'exercise-speed-bag': ['time', 'rounds'],
    'exercise-double-end-bag': ['time', 'rounds'],
    'exercise-sparring': ['time', 'rounds'],
    'exercise-defensive-drills': ['time', 'rounds'],
    'exercise-footwork-drills': ['time', 'rounds'],
    'exercise-conditioning-rounds': ['time', 'rounds'],
    'exercise-technical-rounds': ['time', 'rounds'],
    
    // Calisthenics/Isometric - hold time primary, also support regular time and sets for dynamic variations
    'exercise-plank-hold': ['hold', 'time', 'sets'],
    'exercise-side-plank': ['hold', 'time', 'sets'],
    'exercise-wall-sit': ['hold', 'time', 'sets'],
    'exercise-dead-hang': ['hold', 'time', 'sets'],
    'exercise-hollow-body-hold': ['hold', 'time', 'sets'],
    'exercise-glute-bridge-hold': ['hold', 'time', 'sets'],
    'exercise-l-sit-hold': ['hold', 'time', 'sets'],
    'exercise-isometric-pushup-hold': ['hold', 'time', 'sets'],
    'exercise-calf-raise-hold': ['hold', 'time', 'sets'],
    'exercise-split-squat-hold': ['hold', 'time', 'sets'],
    
    // Sports exercises - time and rounds based
    'exercise-tennis-match': ['time', 'rounds'],
    'exercise-tennis-drill': ['time', 'rounds'],
    'exercise-volleyball-match': ['time', 'rounds'],
    'exercise-volleyball-drill': ['time', 'rounds'],
    'exercise-badminton-match': ['time', 'rounds'],
    'exercise-table-tennis-match': ['time', 'rounds'],
    'exercise-cricket-match': ['time', 'rounds'],
    'exercise-ice-hockey-match': ['time', 'rounds'],
    'exercise-baseball-game': ['time', 'rounds'],
    'exercise-american-football-game': ['time', 'rounds'],
    'exercise-rugby-match': ['time', 'rounds'],
    'exercise-lacrosse-game': ['time', 'rounds'],
  };

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
      exerciseId: 'exercise-bench-press',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    TemplateEffort(
      id: 'teff-upper-ohp',
      templateSegmentId: 'tseg-upper-1',
      orderIndex: 1,
      effortKind: 'set',
      exerciseId: 'exercise-overhead-press',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    TemplateEffort(
      id: 'teff-upper-row',
      templateSegmentId: 'tseg-upper-1',
      orderIndex: 2,
      effortKind: 'set',
      exerciseId: 'exercise-dumbbell-row',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Easy Run effort
    TemplateEffort(
      id: 'teff-run-main',
      templateSegmentId: 'tseg-run-1',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'exercise-easy-run',
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
      exerciseId: 'exercise-plank-hold',
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
      setIndex: 0,
      targetInt: 5,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Easy Run: 30 minutes
    TemplateTarget(
      id: 'ttar-run-duration',
      templateEffortId: 'teff-run-main',
      metricId: 'metric-duration',
      setIndex: 0,
      targetInt: 1800, // 30 minutes in seconds
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing: 5 rounds x 3 minutes
    TemplateTarget(
      id: 'ttar-boxing-rounds',
      templateEffortId: 'teff-boxing-bag',
      metricId: 'metric-rounds',
      setIndex: 0,
      targetInt: 5,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    TemplateTarget(
      id: 'ttar-boxing-duration',
      templateEffortId: 'teff-boxing-bag',
      metricId: 'metric-round-duration',
      setIndex: 0,
      targetInt: 180, // 3 minutes in seconds
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Stretching: 30-60 seconds per stretch
    TemplateTarget(
      id: 'ttar-stretch-duration',
      templateEffortId: 'teff-mobility-stretch',
      metricId: 'metric-duration',
      setIndex: 0,
      targetMin: 30.0,
      targetMax: 60.0,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];
}

/// Helper class for metric-to-effort-kind relationships
class MetricApplicability {
  final String metricId;
  final String effortKind;

  const MetricApplicability({
    required this.metricId,
    required this.effortKind,
  });
}
