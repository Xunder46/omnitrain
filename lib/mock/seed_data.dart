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
      description:
          'Weightlifting, bodybuilding, powerlifting, strength training',
      iconName: 'fitness_center',
      sortOrder: 2,
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
      description:
          'Boxing, BJJ, Muay Thai, wrestling, soccer, basketball, tennis, team sports',
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
    // Combat Sports (under Sports)
    Discipline(
      id: 'discipline-boxing',
      categoryId: 'category-sports',
      key: 'boxing',
      name: 'Boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-bjj',
      categoryId: 'category-sports',
      key: 'bjj',
      name: 'Brazilian Jiu-Jitsu',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-muay-thai',
      categoryId: 'category-sports',
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
    // New sports disciplines (Phase 4)
    Discipline(
      id: 'discipline-squash',
      categoryId: 'category-sports',
      key: 'squash',
      name: 'Squash',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-padel',
      categoryId: 'category-sports',
      key: 'padel',
      name: 'Padel',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-mma',
      categoryId: 'category-sports',
      key: 'mma',
      name: 'MMA',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-karate',
      categoryId: 'category-sports',
      key: 'karate',
      name: 'Karate',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-judo',
      categoryId: 'category-sports',
      key: 'judo',
      name: 'Judo',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
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
    Discipline(
      id: 'discipline-golf',
      categoryId: 'category-sports',
      key: 'golf',
      name: 'Golf',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Discipline(
      id: 'discipline-climbing',
      categoryId: 'category-sports',
      key: 'climbing',
      name: 'Climbing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Isometric / Stretching
    Discipline(
      id: 'discipline-isometric-holds',
      categoryId: 'category-isometric',
      key: 'isometric_holds',
      name: 'Isometric Holds',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
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
    // Walking / Hiking
    Discipline(
      id: 'discipline-walking',
      categoryId: 'category-cardio',
      key: 'walking',
      name: 'Walking & Hiking',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Machine Cardio
    Discipline(
      id: 'discipline-machine-cardio',
      categoryId: 'category-cardio',
      key: 'machine_cardio',
      name: 'Machine Cardio',
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
      description:
          'A low-intensity, conversational-pace run that forms the backbone of any endurance program. Most of your weekly running volume should live here.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Run at a pace where you could hold a full conversation — if you can only speak in short phrases, you\'re going too hard.',
        'Heart rate should sit in Zone 2, roughly 65–75% of max.',
        'Effort should feel like a 4 out of 10.',
        'Don\'t chase pace — let it come to you. If you feel fast on an easy day, you\'re doing it wrong.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-long-run',
      name: 'Long Run',
      description:
          'The weekly endurance-builder. A sustained easy-to-moderate effort longer than your other runs, designed to develop aerobic capacity and fatigue resistance.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Start at a conversational pace and hold it — don\'t progress into tempo territory.',
        'Fuel and hydrate during anything over 90 minutes.',
        'The goal is time on your feet, not pace. Going too hard here costs you the rest of the week.',
        'Expect to feel fatigued by the end — that\'s the point.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tempo-run',
      name: 'Tempo Run',
      description:
          'A sustained effort at lactate threshold pace — "comfortably hard." Trains the body to clear lactate efficiently and raises the speed you can hold without blowing up.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Effort is 7–8 out of 10: you can speak in short phrases but not hold a conversation.',
        'Pace is roughly what you could hold for a 1-hour race.',
        'Include a proper 10–15 minute warm-up and cool-down — tempo efforts start cold at your peril.',
        'Don\'t start too fast. Tempo is about sustained discomfort, not early-rep hero pace.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-interval-run',
      name: 'Interval Run',
      description:
          'Repeated hard efforts with recovery between, performed above threshold pace. Builds VO2 max and raw speed.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Work intervals are hard — 8–9 out of 10 effort, too hard to speak more than a word or two.',
        'Recovery should be easy jogging or walking, not standing still.',
        'Every rep should be roughly the same pace — if the last rep is way slower, you started too hot.',
        'Always warm up thoroughly before the first hard rep.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-hill-repeats',
      name: 'Hill Repeats',
      description:
          'Repeated uphill efforts with recovery on the way back down. Builds leg strength, running economy, and VO2 max with reduced impact compared to flat intervals.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Pick a hill with a 4–8% grade — steep enough to feel it, not so steep you can\'t run.',
        'Push hard on the way up, at 85–90% effort.',
        'Recover fully on the walk or jog back down.',
        'Focus on form: short strides, driving knees, arms pumping.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-fartlek',
      name: 'Fartlek',
      description:
          'Swedish for "speed play" — an unstructured run mixing surges of fast running with easy sections, played by feel rather than a stopwatch.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Pick landmarks on the fly: "hard to that lamppost, easy to the next tree."',
        'Vary the surges — some short and fast, some longer and moderate.',
        'Recovery between surges is easy running, not walking.',
        'The point is play and variation, not hitting target paces.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-recovery-run',
      name: 'Recovery Run',
      description:
          'A very slow, short run performed the day after a hard session. Promotes blood flow and aids recovery without adding meaningful training stress.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Slower than your easy pace — embarrassingly slow if it needs to be.',
        'Keep it short: 20–40 minutes.',
        'If you finish feeling tired, you went too hard. This is for feeling better, not worse.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-track-repeats',
      name: 'Track Repeats',
      description:
          'Measured interval efforts on a running track, typically 400m to 1600m repeats. Precise pace control makes this a favorite for serious training.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Know your target pace before you step on the track — winging it defeats the purpose.',
        'Run the first rep slightly conservative; negative-split the set if you can.',
        'Recovery is usually a standing rest or easy lap depending on the session.',
        'Stay in lane 1 unless other runners are working — and check before stepping on.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-progression-run',
      name: 'Progression Run',
      description:
          'A run that starts easy and gradually increases pace, finishing at or near tempo effort. Teaches pacing discipline and builds late-run strength.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Start truly easy — Zone 2, conversational.',
        'Build pace in thirds or halves, not in one sudden shift.',
        'The final segment should feel like a tempo effort, not a sprint.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-time-trial',
      name: 'Time Trial',
      description:
          'An all-out effort over a fixed distance or duration. A benchmark for current fitness and a useful hard day when you need to measure yourself.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Warm up thoroughly — 15–20 minutes including a few strides at target pace.',
        'Pace evenly. Most time trials are lost in the first mile.',
        'Don\'t do these too often — once every 4–6 weeks is plenty.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Squat Pattern
    Exercise(
      id: 'exercise-barbell-squat',
      name: 'Barbell Back Squat',
      description:
          'The foundational compound lift for developing lower-body strength and size. The bar rests across the upper back while the lifter squats to depth and drives back up.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the bar across your upper traps, not your neck, and grip it tight with elbows pulled down.',
        'Brace your core hard, unrack, and walk back with two or three controlled steps.',
        'Sit down and back at the same time, keeping knees tracking over your toes.',
        'Descend until your hip crease is at or below the top of your knee.',
        'Drive through your midfoot and stand up without letting your chest collapse forward.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-front-squat',
      name: 'Barbell Front Squat',
      description:
          'A squat variation with the bar racked across the front delts, emphasizing the quads and demanding an upright torso.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Rack the bar across your front delts with elbows pointed high and fingertips under the bar.',
        'Keep your elbows up throughout the lift — if they drop, you lose the bar.',
        'Sit straight down with a vertical torso, not back like a low-bar squat.',
        'Drive up through your midfoot and keep your chest tall.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-goblet-squat',
      name: 'Goblet Squat',
      description:
          'A dumbbell or kettlebell squat held at chest height, excellent for learning depth, posture, and bracing.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hold the weight vertically against your chest, cupping the top head with both hands.',
        'Brace your core and pull your elbows down inside your knees on the descent.',
        'Squat until your elbows graze the inside of your knees at the bottom.',
        'Stand up driving through your whole foot, keeping the weight tight to your chest.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dumbbell-split-squat',
      name: 'Dumbbell Split Squat',
      description:
          'A split-stance single-leg squat with dumbbells held at the sides, building unilateral leg strength and stability.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Step into a long split stance with your front foot flat and back heel raised.',
        'Hold a dumbbell in each hand at your sides, arms relaxed.',
        'Lower straight down until your back knee is just above the floor.',
        'Drive up through the front heel, keeping your torso upright.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bulgarian-split-squat',
      name: 'Bulgarian Split Squat',
      description:
          'A rear-foot elevated split squat that loads the front leg heavily and punishes hip and ankle mobility limitations.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Place your rear foot laces-down on a bench roughly knee height.',
        'Step your front foot far enough forward that your knee doesn\'t cave inward at the bottom.',
        'Lower your back knee toward the floor with a slight forward lean.',
        'Push straight up through the front foot without bouncing out of the bottom.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-hack-squat',
      name: 'Hack Squat',
      description:
          'A machine-based squat with the back supported against an angled pad, isolating the quads with minimal spinal load.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Position your feet shoulder-width on the platform with your back flat against the pad.',
        'Unlock the safeties and lower under control until your thighs are parallel to the platform.',
        'Drive up through your heels without locking out your knees aggressively.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-leg-press',
      name: 'Leg Press',
      description:
          'A seated or angled machine squat that loads the legs while supporting the torso, allowing heavy loads with low technical demand.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Plant your feet shoulder-width on the platform, heels flat.',
        'Keep your lower back pressed firmly into the pad — never let it round.',
        'Lower the sled until your knees reach roughly 90 degrees, no deeper if it causes your lower back to lift.',
        'Press through your whole foot and stop just short of locking out.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pistol-squat',
      name: 'Pistol Squat',
      description:
          'A bodyweight single-leg squat to a full depth, the benchmark for unilateral lower-body strength and mobility.',
      movementPattern: 'squat',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand on one leg with the other extended straight out in front of you.',
        'Reach your arms forward as a counterbalance and sit back slowly into the working leg.',
        'Descend as low as you can while keeping your heel down and working knee tracking over your toes.',
        'Drive up through the standing foot without the free leg touching down.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Hinge Pattern
    Exercise(
      id: 'exercise-deadlift',
      name: 'Conventional Deadlift',
      description:
          'The benchmark pull from the floor — hinge, grip, and lift. The most complete test of posterior chain strength.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set your feet hip-width with the bar directly over your mid-foot.',
        'Hinge down, grip the bar just outside your shins, and pull the slack out.',
        'Take a big breath, brace your core, and push the floor away.',
        'Keep the bar in contact with your legs the entire way up.',
        'Lock out by squeezing your glutes — don\'t lean back past neutral.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-sumo-deadlift',
      name: 'Sumo Deadlift',
      description:
          'A deadlift with a wide stance and hands inside the knees, shortening the range of motion and emphasizing the hips and inner thighs.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set your feet wide with toes angled out roughly 30 degrees.',
        'Grip the bar with your hands inside your knees, arms vertical.',
        'Drop your hips, spread the floor with your feet, and pull the slack out of the bar.',
        'Push your knees out as you drive up, keeping the bar tight to your body.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-romanian-deadlift-barbell',
      name: 'Romanian Deadlift (Barbell)',
      description:
          'A hip-hinge pull from the top down, stopping just below the knees. Loads the hamstrings and glutes under a long stretch.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Start standing with the bar at your hips, knees slightly bent.',
        'Push your hips straight back while keeping the bar sliding down your thighs.',
        'Lower until you feel a strong stretch in your hamstrings — this is usually just below the kneecap.',
        'Drive your hips forward to stand back up, squeezing your glutes at the top.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-romanian-deadlift-dumbbell',
      name: 'Romanian Deadlift (Dumbbell)',
      description:
          'A hip hinge performed with dumbbells at the sides, offering a friendlier entry point to the movement pattern and more freedom of motion.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hold a dumbbell in each hand with your palms facing your thighs.',
        'Soften your knees slightly and push your hips back, letting the dumbbells slide down your legs.',
        'Stop when you feel your hamstrings stretch, not when the dumbbells touch the floor.',
        'Return by driving your hips forward, not by pulling with your arms.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-good-morning',
      name: 'Good Morning',
      description:
          'A hip-hinge with the barbell on the upper back, isolating the posterior chain without grip or arm involvement.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Rack the bar across your upper back like a low-bar squat.',
        'Take a small step out, feet under your hips, knees slightly bent.',
        'Hinge forward at the hips until your torso is roughly parallel to the floor.',
        'Drive your hips forward to return — don\'t round your back to get up.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-barbell-hip-thrust',
      name: 'Barbell Hip Thrust',
      description:
          'A glute-dominant hip extension performed with the upper back on a bench and a loaded bar across the hips.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Sit with your upper back against a bench and roll the bar over your hips, using a pad.',
        'Plant your feet flat, hip-width, close enough that your shins are vertical at the top.',
        'Drive your hips up until your torso is parallel to the floor.',
        'Squeeze your glutes hard at the top and lower with control.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-kettlebell-swing',
      name: 'Kettlebell Swing',
      description:
          'A dynamic two-handed hip hinge that uses the kettlebell\'s momentum to train explosive hip extension.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the kettlebell a foot in front of you and hinge to grab it with both hands.',
        'Hike it back between your legs like a football snap.',
        'Snap your hips forward hard — the bell floats up, you don\'t lift it with your arms.',
        'Let gravity bring the bell back down, catching it with another hinge.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-back-extension',
      name: 'Back Extension',
      description:
          'A posterior-chain exercise performed on a 45-degree bench or GHD, extending the hips against gravity with optional load.',
      movementPattern: 'hinge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Lock your heels under the pads and set your thighs on the main pad so your hips can fully flex.',
        'Cross your arms or hold a plate at your chest.',
        'Hinge down until you feel a stretch in your hamstrings.',
        'Extend back up by squeezing your glutes — stop at a straight line, don\'t hyperextend.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Horizontal Push
    Exercise(
      id: 'exercise-bench-press',
      name: 'Barbell Bench Press',
      description:
          'The benchmark horizontal press — a barbell press from the chest while lying flat, training chest, shoulders, and triceps.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set your feet flat, arch your upper back slightly, and squeeze your shoulder blades together.',
        'Grip the bar just wider than shoulder-width and unrack it over your chest.',
        'Lower the bar to your lower chest with your elbows at roughly 45 degrees from your sides.',
        'Press up and slightly back toward your face, not straight up.',
        'Lock out without letting your shoulder blades come off the bench.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-incline-bench-press',
      name: 'Incline Barbell Bench Press',
      description:
          'A bench press performed on a 30–45 degree incline, shifting emphasis to the upper chest and front delts.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the bench to roughly 30 degrees — steeper turns it into an overhead press.',
        'Plant your feet, arch your upper back, and retract your shoulder blades.',
        'Lower the bar to your upper chest, just below the collarbone.',
        'Press up and slightly back without flaring your elbows.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-decline-bench-press',
      name: 'Decline Barbell Bench Press',
      description:
          'A bench press on a decline bench, emphasizing the lower chest with a shorter range of motion than flat bench.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Lock your feet under the roller pads before unracking the bar.',
        'Unrack with straight arms and lower the bar to your lower chest.',
        'Press straight up over your shoulders — not toward your face.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dumbbell-bench-press',
      name: 'Flat Dumbbell Bench Press',
      description:
          'A horizontal press with dumbbells, allowing a deeper stretch and independent arm paths. Great for pec development and shoulder-friendly pressing.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Kick the dumbbells up onto your thighs, then lie back to get them into position.',
        'Start with the dumbbells just above your chest, palms facing your feet.',
        'Lower them with control until your elbows break the line of your torso.',
        'Press up and slightly in, stopping just before the dumbbells clang together.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-incline-dumbbell-bench-press',
      name: 'Incline Dumbbell Bench Press',
      description:
          'An incline press with dumbbells, combining upper-chest emphasis with a fuller range of motion than the barbell version.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the bench to 30 degrees and kick the dumbbells up to the starting position.',
        'Start with the dumbbells level with your upper chest, palms forward.',
        'Lower until you feel a stretch across your upper chest.',
        'Press back up without letting the dumbbells drift forward over your face.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-push-up',
      name: 'Push-Up',
      description:
          'The foundational bodyweight horizontal press. Trains the chest, shoulders, triceps, and core under a plank position.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set your hands just wider than shoulder-width, directly under your shoulders at the top.',
        'Squeeze your glutes and brace your core so your body forms a straight line.',
        'Lower your chest to within a fist\'s height of the floor.',
        'Press back up without letting your hips sag or pike.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dip',
      name: 'Dip',
      description:
          'A bodyweight press between parallel bars, heavily loading the chest and triceps. Can be weighted with a belt for progression.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Start in a supported position with straight arms and shoulders down away from your ears.',
        'Lean your torso slightly forward for chest emphasis, stay upright for triceps.',
        'Lower until your upper arms are roughly parallel to the floor.',
        'Press back up without locking the elbows violently.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-machine-chest-press',
      name: 'Machine Chest Press',
      description:
          'A seated chest press on a plate-loaded or selectorized machine, offering a controlled press path with lower stability demands.',
      movementPattern: 'horizontal_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Adjust the seat so the handles line up with your mid-chest.',
        'Keep your back flat against the pad and feet planted.',
        'Press out until your arms are almost straight, stopping just short of lockout.',
        'Return under control — don\'t let the stack slam.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Horizontal Pull
    Exercise(
      id: 'exercise-barbell-row',
      name: 'Barbell Bent-Over Row',
      description:
          'A compound horizontal pull with the torso hinged forward, loading the entire back. Demands strict posture to avoid the lower back.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hinge forward until your torso is roughly 45 degrees above parallel, knees soft.',
        'Grip the bar just wider than shoulder-width with an overhand grip.',
        'Pull the bar to your lower ribs by driving your elbows back.',
        'Lower under control without letting your torso pop up.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pendlay-row',
      name: 'Pendlay Row',
      description:
          'A strict barbell row performed with the torso parallel to the floor, resetting the bar on the ground between each rep.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set up like a deadlift, then hinge until your torso is parallel to the floor.',
        'Pull the bar explosively from the floor to your lower chest.',
        'Lower it all the way back to the floor and dead-stop before the next rep.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dumbbell-row',
      name: 'Dumbbell Row',
      description:
          'A single-arm row braced against a bench, isolating one side of the back at a time with a long range of motion.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Place one knee and the same-side hand on the bench, other foot planted on the floor.',
        'Let the dumbbell hang straight down, shoulder stretched forward.',
        'Pull the dumbbell to your hip by driving your elbow back toward the ceiling.',
        'Lower it fully, letting the shoulder blade protract at the bottom.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-seated-cable-row',
      name: 'Seated Cable Row',
      description:
          'A seated row with a cable and handle attachment, providing constant tension across the full range of the pull.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Sit tall with your feet braced and a slight bend in your knees.',
        'Grip the handle and pull your shoulder blades back before starting the row.',
        'Pull the handle to your lower ribs by driving your elbows behind you.',
        'Return under control, letting your arms extend fully but without slumping forward.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-chest-supported-row',
      name: 'Chest-Supported Row',
      description:
          'A row performed face-down on an incline bench, removing the lower back from the equation so the back muscles do all the work.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the bench to about 30–45 degrees and lie chest-down with dumbbells hanging below.',
        'Start with your arms fully extended and shoulder blades relaxed forward.',
        'Row the dumbbells up by driving your elbows toward the ceiling.',
        'Squeeze your shoulder blades at the top before lowering.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-t-bar-row',
      name: 'T-Bar Row',
      description:
          'A heavy-loadable row using a landmine or dedicated T-bar station, pulled from a hinged position with a neutral grip.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Straddle the bar and hinge forward until your torso is 45 degrees from vertical.',
        'Grip the handle with a neutral grip and pull the slack out.',
        'Row the handle into your lower chest, squeezing your mid-back.',
        'Lower under control without letting your torso stand up.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-inverted-row',
      name: 'Inverted Row',
      description:
          'A bodyweight horizontal pull performed under a fixed bar, the rowing equivalent of a push-up. Scales easily by adjusting foot position.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set a bar at roughly hip height and lie under it with an overhand grip.',
        'Straighten your body into a rigid plank from heels to shoulders.',
        'Pull your chest to the bar by driving your elbows down and back.',
        'Lower yourself until your arms are straight before the next rep.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-face-pull',
      name: 'Face Pull',
      description:
          'A high-cable row with a rope, pulled toward the forehead. Trains the rear delts and upper back — a staple for shoulder health.',
      movementPattern: 'horizontal_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the cable to just above eye height and grip the rope with palms facing down.',
        'Step back until your arms are fully extended and under tension.',
        'Pull the rope toward your forehead, ending with your hands beside your ears.',
        'Squeeze your rear delts and upper back at the end position.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Vertical Push
    Exercise(
      id: 'exercise-overhead-press',
      name: 'Barbell Overhead Press',
      description:
          'A standing press of a barbell from the front rack to overhead — the benchmark test of upper-body pressing strength.',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set your feet hip-width, grip just outside shoulder-width, bar resting on your front delts.',
        'Brace your core hard and squeeze your glutes to prevent lower-back hyperextension.',
        'Press the bar straight up, pulling your head back slightly so it travels past your face.',
        'Push your head through at the top until the bar is over your mid-foot.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dumbbell-shoulder-press',
      name: 'Standing Dumbbell Shoulder Press',
      description:
          'An overhead press with dumbbells, performed standing. Demands more stability than the seated or barbell version.',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Clean the dumbbells to your shoulders, palms facing forward.',
        'Brace your core and glutes to lock your torso in place.',
        'Press up until the dumbbells touch overhead, without arching your lower back.',
        'Lower under control to ear height before the next rep.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-seated-dumbbell-shoulder-press',
      name: 'Seated Dumbbell Shoulder Press',
      description:
          'A supported overhead press with dumbbells and a vertical bench, reducing lower-back demand for cleaner shoulder isolation.',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the bench upright and sit with your back flat against the pad.',
        'Kick the dumbbells up to shoulder height, palms forward.',
        'Press up until the dumbbells meet overhead.',
        'Lower under control, stopping when your elbows pass your torso.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-landmine-press',
      name: 'Landmine Press',
      description:
          'A single-arm press using a barbell anchored at one end, pressed at an upward angle. Shoulder-friendly alternative to a vertical overhead press.',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand in a staggered or split stance holding the bar end at your shoulder.',
        'Brace your core and press the bar up and slightly forward along a diagonal path.',
        'Extend until your arm is straight, keeping your shoulder packed down.',
        'Return slowly along the same path.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-arnold-press',
      name: 'Arnold Press',
      description:
          'A dumbbell overhead press that rotates through the lift, starting with palms toward you and finishing with palms forward. Hits all three deltoid heads.',
      movementPattern: 'vertical_push',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Start seated with the dumbbells at shoulder height, palms facing you.',
        'As you press up, rotate your wrists so palms face forward at the top.',
        'Press to full extension overhead.',
        'Reverse the rotation on the way down.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Vertical Pull
    Exercise(
      id: 'exercise-pullup',
      name: 'Pull-Up',
      description:
          'A bodyweight vertical pull from a bar with an overhand grip. The benchmark upper-body pulling movement.',
      movementPattern: 'vertical_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Grip the bar just wider than shoulder-width, palms facing away.',
        'Hang with shoulders engaged — don\'t start from a dead relaxed position.',
        'Pull your chest toward the bar by driving your elbows down and back.',
        'Lower under control to a full hang without swinging.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-chin-up',
      name: 'Chin-Up',
      description:
          'A vertical pull-up performed with a supinated (palms-toward-you) grip, shifting emphasis to the biceps while still heavily training the back.',
      movementPattern: 'vertical_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Grip the bar shoulder-width with your palms facing you.',
        'Pull until your chin clears the bar, keeping your chest up.',
        'Lower under control without kipping or swinging.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-lat-pulldown',
      name: 'Lat Pulldown',
      description:
          'A cable machine vertical pull that mimics the pull-up pattern, letting the lifter load below bodyweight for volume work.',
      movementPattern: 'vertical_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Grip the bar wider than shoulder-width with palms facing forward.',
        'Lock your thighs under the pad and lean back slightly from the hips.',
        'Pull the bar to your upper chest by driving your elbows down.',
        'Control the bar back up without letting your shoulders shrug to your ears.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-neutral-grip-pulldown',
      name: 'Neutral-Grip Pulldown',
      description:
          'A lat pulldown with a parallel-grip handle, placing the shoulders in a stronger, more comfortable position than overhand.',
      movementPattern: 'vertical_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Attach a neutral-grip V-bar or parallel handle to the cable.',
        'Sit tall, lock your thighs down, and grip with palms facing each other.',
        'Pull the handle to your upper chest, focusing on squeezing your lats.',
        'Return under control with full arm extension.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-straight-arm-pulldown',
      name: 'Straight-Arm Pulldown',
      description:
          'A cable isolation for the lats performed with straight arms, driving the bar from overhead down to the thighs.',
      movementPattern: 'vertical_pull',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand facing a high cable with a straight bar attached, arms overhead.',
        'Keep a soft bend in the elbows and lock that angle for the entire set.',
        'Pull the bar down to your thighs by driving your hands down in an arc.',
        'Control the bar back to the start without letting it pull your shoulders into a shrug.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Lunge / Single-Leg
    Exercise(
      id: 'exercise-walking-lunge',
      name: 'Walking Lunge',
      description:
          'A forward-stepping lunge performed continuously, challenging balance, coordination, and single-leg strength with every step.',
      movementPattern: 'lunge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hold dumbbells at your sides or a barbell on your back.',
        'Step forward into a long lunge, lowering your back knee toward the floor.',
        'Drive up through the front heel and step directly into the next lunge.',
        'Keep your torso tall throughout — don\'t lean forward to push off.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-reverse-lunge',
      name: 'Reverse Lunge',
      description:
          'A backward-stepping lunge that\'s easier on the knees than a forward lunge, emphasizing the glutes and front-leg quad.',
      movementPattern: 'lunge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand tall holding dumbbells or with a bar on your back.',
        'Step one foot straight back and lower your rear knee toward the floor.',
        'Drive up through the front heel and bring the back foot in to meet it.',
        'Alternate legs or finish all reps on one side before switching.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-step-up',
      name: 'Dumbbell Step-Up',
      description:
          'A single-leg exercise stepping onto a raised surface, emphasizing the glute and quad of the working leg.',
      movementPattern: 'lunge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set a box or bench at roughly knee height.',
        'Hold a dumbbell in each hand at your sides.',
        'Plant your whole foot on the box and drive up to full extension.',
        'Lower under control — don\'t push off the back foot to cheat.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-single-leg-rdl',
      name: 'Single-Leg Romanian Deadlift',
      description:
          'A unilateral hip hinge balanced on one leg, training the hamstrings, glutes, and hip stabilizers.',
      movementPattern: 'lunge',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand on one leg with a soft bend in the knee, holding a dumbbell in the opposite hand.',
        'Hinge forward, letting the free leg extend straight back as a counterbalance.',
        'Keep your hips square to the floor — don\'t let the free hip rotate open.',
        'Return to standing by driving the standing foot into the ground.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Shoulder Isolation
    Exercise(
      id: 'exercise-lateral-raise',
      name: 'Dumbbell Lateral Raise',
      description:
          'An isolation exercise lifting dumbbells out to the sides, targeting the side delt for shoulder width.',
      movementPattern: 'shoulder_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand tall with a slight forward lean, dumbbells at your sides.',
        'Raise your arms out to the sides with a slight bend in the elbows.',
        'Stop when your hands reach shoulder height — don\'t lift higher.',
        'Lower under control, resisting the drop.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cable-lateral-raise',
      name: 'Cable Lateral Raise',
      description:
          'A lateral raise performed from a low cable, offering constant tension through the full range of the lift.',
      movementPattern: 'shoulder_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand sideways to a low cable with the handle in your outside hand.',
        'Step out until the cable is under tension at the bottom.',
        'Raise your arm out to the side to shoulder height with a slight elbow bend.',
        'Lower slowly, fighting the cable on the way down.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-rear-delt-fly',
      name: 'Rear Delt Fly',
      description:
          'A reverse fly performed with dumbbells or a reverse pec-deck, isolating the rear delts and upper back.',
      movementPattern: 'shoulder_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hinge forward with dumbbells hanging below your chest, elbows softly bent.',
        'Raise your arms out to the sides until they reach shoulder level.',
        'Squeeze your rear delts at the top — don\'t use momentum to get there.',
        'Lower under control.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-front-raise',
      name: 'Front Raise',
      description:
          'A frontal-plane shoulder raise with a dumbbell or plate, isolating the front delt.',
      movementPattern: 'shoulder_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hold a dumbbell in each hand at the front of your thighs, palms facing in.',
        'Raise one or both arms straight out in front of you to shoulder height.',
        'Pause briefly at the top, then lower without swinging.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-upright-row',
      name: 'Upright Row',
      description:
          'A vertical pull to the chest with a barbell or dumbbells, hitting the side delts and traps. Use a wider grip if shoulders complain.',
      movementPattern: 'shoulder_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Grip the bar slightly wider than shoulder-width, hanging at arm\'s length.',
        'Pull the bar up by driving your elbows out and up.',
        'Stop when your elbows reach shoulder height — higher compresses the shoulder.',
        'Lower under control.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Arm Isolation
    Exercise(
      id: 'exercise-barbell-curl',
      name: 'Barbell Curl',
      description:
          'The benchmark bicep exercise — a standing curl of a barbell with a shoulder-width grip.',
      movementPattern: 'arm_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Grip the bar shoulder-width, standing tall with elbows tucked to your sides.',
        'Curl the bar up by flexing at the elbow, keeping your upper arms still.',
        'Lower the bar under control to a full stretch without locking out hard.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dumbbell-curl',
      name: 'Dumbbell Curl',
      description:
          'A bicep curl with dumbbells, allowing each arm to work independently and the wrists to rotate through the movement.',
      movementPattern: 'arm_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Start with dumbbells at your sides, palms facing in.',
        'Curl up, rotating your palms to face you as the dumbbells pass your thighs.',
        'Squeeze at the top and lower under control to a full stretch.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-hammer-curl',
      name: 'Hammer Curl',
      description:
          'A curl with a neutral grip, emphasizing the brachialis and forearm alongside the biceps.',
      movementPattern: 'arm_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hold the dumbbells with palms facing each other throughout the set.',
        'Curl up without rotating your wrists, keeping palms facing in.',
        'Lower fully before the next rep.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-preacher-curl',
      name: 'Preacher Curl',
      description:
          'A curl performed on a preacher bench, locking the upper arm in place to isolate the biceps with no momentum.',
      movementPattern: 'arm_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the pad so your armpit is snug against the top edge.',
        'Start with the arms fully extended, a slight bend in the elbows.',
        'Curl the bar or dumbbells up, keeping your upper arm pinned to the pad.',
        'Lower under strict control — the stretch at the bottom is the whole point.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-triceps-pressdown',
      name: 'Triceps Pressdown',
      description:
          'A cable isolation for the triceps, pressing a bar or rope down from chest height to full extension.',
      movementPattern: 'arm_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Stand facing a high cable with a bar or rope attachment.',
        'Pin your upper arms to your sides and keep them there for the whole set.',
        'Extend your arms until the bar reaches your thighs.',
        'Return slowly until your forearms are just above parallel.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-overhead-triceps-extension',
      name: 'Overhead Triceps Extension',
      description:
          'A triceps extension performed with the arm overhead, emphasizing the long head of the triceps under stretch.',
      movementPattern: 'arm_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hold a dumbbell with both hands overhead, arms fully extended.',
        'Lower the dumbbell behind your head by bending at the elbows only.',
        'Extend back to the top by driving your hands up, keeping your upper arms vertical.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-skullcrusher',
      name: 'Skullcrusher',
      description:
          'A lying triceps extension with a barbell or EZ-bar, lowered toward the forehead and pressed back up. A classic triceps mass-builder.',
      movementPattern: 'arm_isolation',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Lie flat on a bench holding the bar above your chest with a close grip.',
        'Keep your upper arms vertical as you bend at the elbows.',
        'Lower the bar toward your forehead or just past it.',
        'Extend back up by squeezing the triceps — don\'t drift the elbows out.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Posterior Chain / Glutes
    Exercise(
      id: 'exercise-cable-pull-through',
      name: 'Cable Pull-Through',
      description:
          'A cable-loaded hip hinge, pulled between the legs from behind. Teaches the hinge pattern with less technical demand than a deadlift.',
      movementPattern: 'posterior_chain',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Face away from a low cable, straddle it, and grab the rope between your legs.',
        'Step forward until the cable is under tension.',
        'Hinge your hips back, letting the rope travel between your legs.',
        'Drive your hips forward to stand, squeezing your glutes at the top.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-glute-kickback',
      name: 'Glute Kickback',
      description:
          'A single-leg hip extension against cable or machine resistance, isolating the glute on the working side.',
      movementPattern: 'posterior_chain',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Attach an ankle strap to a low cable and stand facing the machine.',
        'Keep a slight bend in the working leg and extend it straight back.',
        'Squeeze your glute at full extension — don\'t arch your lower back to get more range.',
        'Return under control.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-nordic-curl',
      name: 'Nordic Curl',
      description:
          'A brutal bodyweight hamstring curl performed from a kneeling position with anchored feet, lowering under eccentric control.',
      movementPattern: 'posterior_chain',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Anchor your feet under a pad or have a partner hold your ankles.',
        'Start kneeling upright with your torso and thighs in a straight line.',
        'Lower yourself forward as slowly as possible by resisting with your hamstrings.',
        'Catch yourself with your hands when you can\'t hold any longer, then push back up.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Calves
    Exercise(
      id: 'exercise-standing-calf-raise',
      name: 'Standing Calf Raise',
      description:
          'A loaded calf raise performed standing, emphasizing the gastrocnemius with the knee straight.',
      movementPattern: 'calves',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the balls of your feet on a raised platform with heels hanging off.',
        'Drop into a full stretch at the bottom of each rep.',
        'Press up onto your toes as high as you can go.',
        'Pause at the top, then lower back into the stretch.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-seated-calf-raise',
      name: 'Seated Calf Raise',
      description:
          'A calf raise performed seated with the knees bent, shifting emphasis to the soleus beneath the gastrocnemius.',
      movementPattern: 'calves',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the pad across your lower thighs, balls of the feet on the platform.',
        'Let your heels drop into a full stretch.',
        'Press up as high as you can.',
        'Lower slowly back to the stretched position.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Carries & Loaded Core
    Exercise(
      id: 'exercise-farmers-carry',
      name: "Farmer's Carry",
      description:
          'A loaded walk with heavy dumbbells or trap bar, training grip, core, and whole-body stability. Time- or distance-based.',
      movementPattern: 'loaded_core',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Pick up a heavy dumbbell in each hand with a flat back and neutral spine.',
        'Stand tall with shoulders pulled back and down.',
        'Walk with controlled steps, not letting your torso sway side to side.',
        'Set the weights down with a controlled hinge, not a drop.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pallof-press',
      name: 'Pallof Press',
      description:
          'An anti-rotation core exercise performed at a cable, pressing a handle straight out while resisting the cable\'s pull to one side.',
      movementPattern: 'loaded_core',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set a cable at chest height and stand sideways to the stack.',
        'Grip the handle with both hands at your sternum.',
        'Press the handle straight out in front of you and resist the cable pulling you toward the stack.',
        'Hold briefly at full extension, then return to your chest.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cable-woodchop',
      name: 'Cable Woodchop',
      description:
          'A rotational core exercise on a cable, pulling a handle diagonally across the body. Trains rotation and anti-rotation together.',
      movementPattern: 'loaded_core',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Set the cable high and stand sideways to the stack.',
        'Grip the handle with both hands and pull it diagonally down across your body.',
        'Rotate through your torso, not your arms — keep your arms nearly straight.',
        'Return under control along the same path.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Resistance / Lifting exercises — Abs
    Exercise(
      id: 'exercise-hanging-leg-raise',
      name: 'Hanging Leg Raise',
      description:
          'A hanging abdominal exercise lifting the legs from vertical to horizontal or higher. Trains the entire anterior core.',
      movementPattern: 'abs',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Hang from a pull-up bar with shoulders engaged, not dead relaxed.',
        'Brace your core and lift your legs with control.',
        'Raise until your thighs are at least parallel to the floor — higher is better.',
        'Lower slowly without swinging.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cable-crunch',
      name: 'Cable Crunch',
      description:
          'A loaded crunch performed kneeling in front of a high cable with a rope attachment, letting you progressively overload the abs.',
      movementPattern: 'abs',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Kneel in front of a high cable with the rope pulled to the sides of your head.',
        'Hinge forward by flexing your spine, not your hips.',
        'Curl your ribs toward your pelvis — think of a crunching motion, not a bow.',
        'Return under control without using your hips to lift.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-ab-wheel-rollout',
      name: 'Ab Wheel Rollout',
      description:
          'An anti-extension core exercise rolling an ab wheel forward while holding a rigid body. Punishing and highly effective.',
      movementPattern: 'abs',
      disciplineId: 'discipline-bodybuilding',
      howToSteps: [
        'Kneel with the wheel directly under your shoulders.',
        'Brace your core hard — think of pulling your ribs down toward your hips.',
        'Roll the wheel forward as far as you can hold a rigid torso.',
        'Pull yourself back by contracting your abs, not your hip flexors.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing exercises
    Exercise(
      id: 'exercise-heavy-bag-rounds',
      name: 'Heavy Bag Rounds',
      description:
          'Timed rounds on the heavy bag — combinations, power work, and conditioning at moderate-to-high intensity.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Hands back to the guard after every punch — no hanging.',
        'Turn the hip and shoulder into straight punches; don\'t arm-punch.',
        'Move around the bag between combinations, don\'t stand square.',
        'Breathe out on every strike.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-shadowboxing',
      name: 'Shadowboxing',
      description:
          'Timed rounds of punching in open space — footwork, head movement, and combination rehearsal without resistance.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Watch yourself in a mirror or film one round to audit form.',
        'Throw every punch with the intent you would against a bag.',
        'Include defense — slips, rolls, pulls — not just offense.',
        'Finish every combination with movement off line.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pad-work',
      name: 'Pad Work',
      description:
          'Timed rounds with a coach or partner holding focus mitts or Thai pads — called combinations, reactive work, and counters.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Respond to the call, don\'t anticipate it.',
        'Reset the guard between combinations — don\'t drift.',
        'Hit the pad, don\'t slap it — turn punches over at contact.',
        'Footwork moves first, then the hands.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-speed-bag',
      name: 'Speed Bag',
      description:
          'Timed rounds on the speed bag — rhythm, hand speed, and shoulder endurance.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Strike with the side of the fist on the downswing, not a punch.',
        'Keep elbows up at bag height — don\'t let them drop.',
        'Find the three-beat rhythm: bag hits front wall, back wall, front wall.',
        'Switch lead hand every round.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-double-end-bag',
      name: 'Double-End Bag',
      description:
          'Timed rounds on a tethered reflex bag — timing, accuracy, and defensive reactions against a moving target.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Stay in range — close enough to hit, far enough to slip.',
        'Don\'t chase the bag; let it come back to you.',
        'Work in combinations of two or three, not singles.',
        'Slip or pull after every shot — the bag is swinging back at you.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-sparring',
      name: 'Sparring',
      description:
          'Live rounds with a partner at an agreed intensity. Technique-focused light sparring or harder competition-prep rounds.',
      disciplineId: 'discipline-boxing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-defensive-drills',
      name: 'Defensive Drills',
      description:
          'Timed rounds of slipping, rolling, parrying, and blocking against a partner\'s feed or shadowed in open space.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Move the head off the centerline, not just back.',
        'Hands don\'t drop when the head moves.',
        'Slip short — enough to miss the punch, not more.',
        'Counter out of every defensive movement.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-footwork-drills',
      name: 'Footwork Drills',
      description:
          'Timed rounds of movement patterns — pivots, cuts, in-and-out rhythm, lateral steps. Done on floor markings, ladder, or open space.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Stay in stance — the feet never cross.',
        'Push off the back foot moving forward, front foot moving back.',
        'Small, fast steps — not long strides.',
        'Reset stance after every pivot.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-conditioning-rounds',
      name: 'Conditioning Rounds',
      description:
          'High-output rounds — bag work, pads, or shadow — run at competition intensity to build round-specific conditioning.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Throw in volume — don\'t pace.',
        'Nasal breathing between exchanges where possible.',
        'Keep form honest when tired; collapsing form is the drill failing.',
        'Log how you feel at minute 2:30 of each round — that\'s the true signal.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-technical-rounds',
      name: 'Technical Rounds',
      description:
          'Low-intensity rounds focused on one technical element — a specific combination, footwork pattern, or defensive sequence.',
      disciplineId: 'discipline-boxing',
      howToSteps: [
        'Pick one thing to work on before the round starts.',
        'Slow is fast — technique first, speed later.',
        'If form breaks, stop and reset rather than push through.',
        'Finish every round with a clean rep of the focus technique.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Isometric Holds exercises (migrated from discipline-calisthenics)
    Exercise(
      id: 'exercise-plank-hold',
      name: 'Plank Hold',
      description:
          'Front-facing isometric hold supported on forearms and toes, targeting the anterior core, shoulders, and glutes. A baseline test of full-body bracing.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Stack elbows directly under shoulders, forearms parallel.',
        'Squeeze glutes and brace the abs — ribs tucked, no sag at the hips.',
        'Hold a neutral neck, eyes on the floor just ahead of the hands.',
        'Breathe shallow through the nose; don\'t hold your breath.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-side-plank',
      name: 'Side Plank',
      description:
          'Lateral isometric hold on one forearm and the side of one foot, targeting the obliques, quadratus lumborum, and shoulder stabilizers.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Stack shoulder over elbow, feet stacked or staggered for balance.',
        'Drive the hips up so the body forms one straight line from head to heels.',
        'Reach the top arm skyward or rest it on the hip — pick one and keep it still.',
        'Keep the bottom shoulder packed, not collapsed toward the ear.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-wall-sit',
      name: 'Wall Sit',
      description:
          'Isometric squat hold with the back flat against a wall and thighs parallel to the floor. Targets the quads, with secondary glute and calf engagement.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Slide down until thighs are parallel to the floor — knees at roughly 90 degrees.',
        'Knees stacked over ankles, not forward over the toes.',
        'Press the full back flat against the wall, no gap at the low back.',
        'Breathe steadily; the burn will spike around 30 seconds in.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dead-hang',
      name: 'Dead Hang',
      description:
          'Passive isometric hang from a pull-up bar with arms fully extended. Trains grip endurance and decompresses the shoulders and spine.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Grip the bar at roughly shoulder width, thumbs wrapped.',
        'Let the body hang fully — don\'t actively shrug the shoulders up.',
        'Keep the ribcage down and core lightly engaged so you\'re not swaying.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-hollow-body-hold',
      name: 'Hollow Body Hold',
      description:
          'Supine isometric hold with arms overhead and legs extended, pressing the low back firmly into the floor. Trains anterior core tension used in gymnastics and Olympic lifting.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Press the low back flat — no daylight between the floor and your spine.',
        'Lift shoulders and legs just enough that lockout is maintained, not higher.',
        'Arms by the ears, legs straight, toes pointed.',
        'If the low back arches, raise the legs higher until you can flatten it again.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-glute-bridge-hold',
      name: 'Glute Bridge Hold',
      description:
          'Supine hip-extension hold with shoulders on the floor, knees bent, hips driven up. Targets the glutes and hamstrings.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Feet flat, heels close enough that a brushed fingertip barely touches them.',
        'Drive through the heels and squeeze the glutes to lift the hips.',
        'Ribs stay down — don\'t hyperextend the low back to get higher.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-l-sit-hold',
      name: 'L-Sit Hold',
      description:
          'Seated isometric hold with the body supported on straight arms, legs extended straight out parallel to the floor. Trains the anterior core, hip flexors, and tricep lockout.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Press down hard through straight arms to lift the hips clear of the floor.',
        'Extend legs straight forward — lock the knees, point the toes.',
        'If straight legs are impossible, bend the knees (tuck L-sit) as a regression.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-isometric-pushup-hold',
      name: 'Isometric Push-Up Hold',
      description:
          'Paused hold at the bottom of a push-up, typically with the chest an inch off the floor. Targets the chest, triceps, and anterior core.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Lower to the bottom of a push-up and hold — chest hovering just off the floor.',
        'Elbows at roughly 45 degrees to the torso, not flared wide.',
        'Maintain full plank body line; don\'t let the hips sag.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-calf-raise-hold',
      name: 'Calf Raise Hold',
      description:
          'Isometric hold at the top of a calf raise, up on the balls of the feet. Trains calf endurance and ankle stability.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Rise to the top of a calf raise on both feet.',
        'Hold the highest point — don\'t settle into a mid-range position.',
        'Keep the ankles tracking straight, not rolling outward.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-split-squat-hold',
      name: 'Split Squat Hold',
      description:
          'Unilateral isometric lunge hold in the bottom position. Targets the front-leg quad and glute, with a long-lever stretch on the rear-leg hip flexor.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Front knee stacked over the front ankle, rear knee hovering an inch off the floor.',
        'Torso tall, front heel planted.',
        'Shift weight onto the front leg — the rear leg is a kickstand, not a driver.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // New Isometric Holds — Core
    Exercise(
      id: 'exercise-rkc-plank',
      name: 'RKC Plank',
      description:
          'Maximum-tension variant of the standard plank. Same position, but every muscle — glutes, quads, abs, lats — contracts as hard as possible throughout the hold.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Set up in a standard plank, then actively pull elbows toward toes without moving them.',
        'Squeeze glutes and quads hard enough that they shake.',
        'Cap holds at 10–20 seconds — this is an intensity drill, not a duration one.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-long-lever-plank',
      name: 'Long-Lever Plank',
      description:
          'Plank variant with the elbows placed further forward than the shoulders, increasing the lever arm and anti-extension demand on the core.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Start in a standard plank, then walk the elbows 4–6 inches forward.',
        'Fight hard to keep the lower back from arching — ribs stay pulled down.',
        'Expect to hold significantly less time than a standard plank.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-dead-bug-hold',
      name: 'Dead Bug Hold',
      description:
          'Supine anti-extension hold with opposite arm and opposite leg extended, low back pinned to the floor. A more accessible alternative to the hollow body hold.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Pin the low back down before extending anything.',
        'Lower one arm overhead and the opposite leg toward the floor, holding short of contact.',
        'Don\'t let the ribs flare or the back arch as the limbs extend.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-copenhagen-plank',
      name: 'Copenhagen Plank',
      description:
          'Side plank variant with the top leg elevated on a bench, targeting the adductors of the top leg alongside the obliques. A groin-resilience staple.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Place the inside of the top ankle or knee on the bench; shorter lever (knee) is the regression.',
        'Drive the top leg down into the bench to lift the hips.',
        'Keep the hips square, shoulder stacked over elbow.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // New Isometric Holds — Lower-Body
    Exercise(
      id: 'exercise-single-leg-glute-bridge-hold',
      name: 'Single-Leg Glute Bridge Hold',
      description:
          'Unilateral version of the glute bridge hold, performed with one leg extended. Exposes side-to-side glute asymmetries.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Set up in a glute bridge, then extend one leg straight out.',
        'Keep the hips level — don\'t let the extended-leg side drop.',
        'Drive through the heel of the planted foot, squeeze the working glute.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-single-leg-calf-raise-hold',
      name: 'Single-Leg Calf Raise Hold',
      description:
          'Unilateral calf raise hold. Doubles the load on the working calf and exposes ankle-stability deficits.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Rise to the top of a single-leg calf raise, using fingertips against a wall for balance if needed.',
        'Keep the standing ankle tracking straight.',
        'If the ankle wobbles, drop the non-working foot and scale back to a two-leg hold.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pistol-squat-hold',
      name: 'Pistol Squat Hold',
      description:
          'Advanced unilateral hold at the bottom of a pistol squat — one leg folded deep, the other extended forward. Requires significant ankle mobility and single-leg strength.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Plant the working foot flat, extend the free leg forward.',
        'Keep arms extended forward as a counterbalance.',
        'If ankle mobility fails, hold a wall or rack for assistance.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cossack-squat-hold',
      name: 'Cossack Squat Hold',
      description:
          'Bottom-position hold of a deep lateral squat — one leg bent underneath, the other extended to the side. Trains adductor length and hip mobility under load.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Sit the hips down and back over the bent leg.',
        'Extended leg stays straight, heel down, toes up if possible.',
        'Chest up, don\'t collapse forward.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // New Isometric Holds — Upper-Body
    Exercise(
      id: 'exercise-active-hang',
      name: 'Active Hang',
      description:
          'Hang from a pull-up bar with shoulders actively pulled down and packed — a scapular-retraction hold. The starting position for any pull-up.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Start from a dead hang, then pull the shoulder blades down and back without bending the elbows.',
        'Chest rises slightly, shoulders move away from the ears.',
        'Hold the packed position without letting elbows bend.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tuck-front-lever-hold',
      name: 'Tuck Front Lever Hold',
      description:
          'Entry-level front lever progression hung from a bar with knees tucked tight to the chest and the torso pulled horizontal. Trains the lats, core, and scapular depressors.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'From an active hang, pull the knees to the chest and the hips up until the torso is horizontal.',
        'Drive the arms straight down — don\'t bend the elbows.',
        'Keep the tuck tight; opening up too soon collapses the position.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-advanced-tuck-front-lever-hold',
      name: 'Advanced Tuck Front Lever Hold',
      description:
          'Progression between tuck front lever and straddle front lever, with the hips opened so the thighs are roughly parallel to the floor but knees still bent.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Start in a tuck front lever, then open the hips until thighs are parallel to the floor.',
        'Knees stay bent at roughly 90 degrees.',
        'Lats pulled down hard; torso stays horizontal.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tuck-back-lever-hold',
      name: 'Tuck Back Lever Hold',
      description:
          'Entry-level back lever progression with the body inverted and tucked, facing away from the bar. Trains the biceps, anterior delts, and core anti-extension.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Invert into a tucked inverted hang first, then lower the torso away from the bar until the back is horizontal and facing down.',
        'Knees tucked tight to the chest, hips at bar level.',
        'Keep arms straight and locked throughout.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-ring-support-hold',
      name: 'Ring Support Hold',
      description:
          'Straight-arm support hold on gymnastic rings at the top of a ring dip. Trains pressing stability, scapular control, and wrist strength. Highly unstable.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Press to full lockout on the rings, arms straight, body vertical.',
        'Turn the rings slightly outward (external rotation) to lock out the shoulders.',
        'Hollow body shape — ribs tucked, glutes squeezed.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-handstand-hold-wall',
      name: 'Handstand Hold (Wall-Supported)',
      description:
          'Inverted isometric hold against a wall with hands shoulder-width, heels against the wall. Trains shoulder stability, wrist strength, and full-body tension upside down.',
      disciplineId: 'discipline-isometric-holds',
      howToSteps: [
        'Kick up with hands roughly six inches from the wall, heels resting against it.',
        'Push the floor away — shoulders fully shrugged up by the ears.',
        'Squeeze glutes and abs; don\'t let the low back arch off into a "banana."',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Static Stretches
    Exercise(
      id: 'exercise-standing-hamstring-stretch',
      name: 'Standing Hamstring Stretch',
      description:
          'Static stretch for the hamstrings, performed by hinging at the hips and folding forward over straight legs.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Hinge from the hips, not the low back.',
        'Let the head and arms hang heavy.',
        'Bend the knees slightly if the low back rounds aggressively.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-seated-forward-fold',
      name: 'Seated Forward Fold',
      description:
          'Seated hamstring and low-back stretch with legs extended, reaching toward the toes.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Sit tall first, then hinge forward from the hips.',
        'Reach for the toes or shins — wherever the hands naturally land.',
        'Don\'t force a rounded back to go deeper.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-standing-quad-stretch',
      name: 'Standing Quad Stretch',
      description:
          'Stretch for the front of the thigh, pulling one heel toward the glute while standing on the opposite leg.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Pull the heel toward the glute, knee pointing straight down.',
        'Keep the knees close together — don\'t let the working knee drift forward.',
        'Squeeze the glute on the stretched side to deepen the hip-flexor stretch.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-couch-stretch',
      name: 'Couch Stretch',
      description:
          'Deep hip-flexor and quad stretch with the rear foot elevated against a wall or couch and the front leg in a lunge position.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Rear shin vertical against the wall, rear knee on a pad.',
        'Tuck the pelvis under — squeeze the rear glute to intensify the hip-flexor stretch.',
        'Stay tall through the torso; don\'t lean forward.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-kneeling-hip-flexor-stretch',
      name: 'Kneeling Hip Flexor Stretch',
      description:
          'Classic hip-flexor stretch in a half-kneeling position, shifting the hips forward over the front foot.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Half-kneeling, front foot flat, rear knee on a pad.',
        'Tuck the pelvis and squeeze the rear glute before shifting forward.',
        'Don\'t just push the hips forward — the stretch comes from the posterior pelvic tilt.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-pigeon-pose',
      name: 'Pigeon Pose',
      description:
          'Deep stretch for the glutes, piriformis, and outer hip, with the front leg folded under the torso and the rear leg extended straight back.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Front shin angled across the body, rear leg extended straight back with the top of the foot down.',
        'Square the hips as much as possible — use a block under the front-side hip if it floats.',
        'Walk the hands forward to deepen; keep the breath steady.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-seated-piriformis-stretch',
      name: 'Seated Piriformis Stretch (Figure-4)',
      description:
          'Seated stretch for the piriformis and deep hip rotators, crossing one ankle over the opposite knee and folding forward.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Cross the ankle over the opposite knee, foot flexed to protect the knee.',
        'Hinge from the hips and fold forward.',
        'If the knee of the crossed leg sits high, support it with a cushion rather than forcing it down.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-doorway-chest-stretch',
      name: 'Doorway Chest Stretch',
      description:
          'Stretch for the pecs and anterior shoulder, with the forearm pressed against a doorframe and the body rotated away.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Forearm flat against the doorframe, elbow at roughly shoulder height.',
        'Step the front foot through and rotate the torso away.',
        'Try elbow heights above and below shoulder level to hit different pec fibers.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-lat-stretch',
      name: 'Lat Stretch (Overhead Reach)',
      description:
          'Stretch for the lats and lateral torso, reaching one arm overhead and bending sideways, often assisted by holding a rack or doorframe.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Grip a rack or doorframe with one hand overhead.',
        'Sink the hips back and away from the grip.',
        'Rotate the torso slightly to aim the stretch into the lat.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-overhead-triceps-stretch',
      name: 'Overhead Triceps Stretch',
      description:
          'Stretch for the triceps and lats, reaching one arm overhead with the elbow bent and the hand reaching down the back.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Reach one arm overhead, bend the elbow so the hand drops behind the head.',
        'Use the opposite hand to gently pull the elbow across and down.',
        'Keep ribs tucked — don\'t arch the back to cheat depth.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-neck-side-stretch',
      name: 'Neck Side Stretch',
      description:
          'Gentle lateral neck stretch, tilting the head toward one shoulder to stretch the upper trap and levator scapulae.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Tilt the ear toward the shoulder — don\'t raise the shoulder to meet the ear.',
        'Anchor the opposite shoulder down by sitting on the opposite hand.',
        'Gentle pressure with the same-side hand only; no forceful pulls.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-standing-calf-stretch',
      name: 'Standing Calf Stretch',
      description:
          'Stretch for the gastrocnemius, performed with the rear leg straight and heel pressed down, front leg bent forward.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Rear leg straight, heel firmly planted.',
        'Front leg bent, lean forward from the ankle, not the waist.',
        'Toes of the rear foot point straight forward.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-soleus-stretch',
      name: 'Soleus Stretch (Bent-Knee Calf Stretch)',
      description:
          'Variant of the calf stretch targeting the soleus, performed with the rear knee bent rather than straight.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Same setup as a calf stretch, but bend the rear knee.',
        'Keep the rear heel planted.',
        'Sink straight down into the rear ankle.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-childs-pose',
      name: 'Child\'s Pose',
      description:
          'Kneeling rest position with hips sitting back onto the heels and arms extended forward. Gentle stretch for the low back, lats, and shoulders.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Knees wide, big toes together, hips sinking back to the heels.',
        'Reach the arms long in front, chest heavy toward the floor.',
        'Breathe into the low back.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Mobility Holds
    Exercise(
      id: 'exercise-90-90-hip-hold',
      name: '90/90 Hip Hold',
      description:
          'Seated hold with both hips at 90 degrees — front leg bent in front, rear leg bent to the side. Stretches internal rotation of the front hip and external rotation of the rear.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Sit with front shin parallel to the body, rear shin parallel to the body on the other side.',
        'Keep the torso upright; hinge forward over the front leg to deepen.',
        'Swap sides evenly — this asymmetry exposes mobility imbalances.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-frog-stretch',
      name: 'Frog Stretch',
      description:
          'Quadruped stretch with knees wide and feet flared, pressing the hips back toward the heels. Stretches the adductors and inner groin.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Knees wide, shins aligned with thighs, feet flared outward.',
        'Rock the hips back toward the heels; find the first meaningful resistance and hold there.',
        'Keep the torso supported on forearms.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-deep-squat-hold',
      name: 'Deep Squat Hold',
      description:
          'Bottom-position squat hold with feet flat, hips dropped as low as possible, elbows inside the knees pressing them open. Trains ankle, hip, and thoracic mobility simultaneously.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Feet roughly shoulder-width, toes turned slightly out.',
        'Heels stay planted — elevate them on a plate if they lift.',
        'Elbows inside the knees, gently pressing them open; chest up.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-thoracic-rotation-hold',
      name: 'Thoracic Rotation Hold',
      description:
          'Quadruped hold rotating one arm up toward the ceiling, threading the thoracic spine. Targets mid-back rotation.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Start in quadruped, place one hand behind the head.',
        'Rotate the elbow up toward the ceiling, opening the chest.',
        'Hips stay square — the rotation comes from the mid-back, not the low back.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cat-cow-hold',
      name: 'Cat-Cow Hold',
      description:
          'Quadruped spinal mobility drill alternating between full flexion (cat) and full extension (cow), holding each end-range briefly. Not a flowing sequence — hold each position for time.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Quadruped, wrists under shoulders, knees under hips.',
        'Hold each end-range position for the programmed duration before switching.',
        'Move the whole spine — not just the low back.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-worlds-greatest-stretch-hold',
      name: 'World\'s Greatest Stretch Hold',
      description:
          'Multi-joint mobility hold in a deep lunge position with the same-side hand reaching up toward the ceiling, opening the thoracic spine. Held for time rather than flowed through.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Step one foot forward into a deep lunge, opposite hand planted inside the foot.',
        'Reach the same-side arm up, rotating the torso open.',
        'Hold the end position; don\'t flow between sides until the duration ends.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-seated-butterfly-hold',
      name: 'Seated Butterfly Hold',
      description:
          'Seated adductor and groin stretch with soles of the feet together and knees dropped out to the sides.',
      disciplineId: 'discipline-stretching',
      howToSteps: [
        'Sit tall, soles of the feet together, hands on the ankles.',
        'Let the knees drop under their own weight — don\'t force them down.',
        'Hinge forward from the hips to deepen, keeping the back long.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Sports exercises
    // defaultRoundDurationSecs = real-world period/half/set length for the sport.
    // Boxing exercises omit this field and fall back to the 180s app-wide default.
    Exercise(
      id: 'exercise-tennis-match',
      name: 'Tennis Match',
      description:
          'A full singles or doubles match, or an internal practice match. Use periods as sets.',
      disciplineId: 'discipline-tennis',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 1200, // 20-min set
    ),
    Exercise(
      id: 'exercise-tennis-drill',
      name: 'Tennis Drill',
      description:
          'Technique and footwork drill blocks — groundstrokes, volleys, approach shots, or movement patterns fed by a partner, coach, or ball machine.',
      disciplineId: 'discipline-tennis',
      howToSteps: [
        'Split-step the moment the feeder makes contact.',
        'Take the racquet back on the turn, not after the bounce.',
        'Contact point in front of the body, not beside it.',
        'Recover to the center after every shot, even in drill mode.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 600, // 10-min drill block
    ),
    Exercise(
      id: 'exercise-volleyball-match',
      name: 'Volleyball Match',
      description:
          'A full match or scrimmage, indoor or beach. Use periods as sets.',
      disciplineId: 'discipline-volleyball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 1500, // 25-min set
    ),
    Exercise(
      id: 'exercise-volleyball-drill',
      name: 'Volleyball Drill',
      description:
          'Drill blocks — passing, setting, hitting, blocking, or serve-receive patterns fed by a coach or partner.',
      disciplineId: 'discipline-volleyball',
      howToSteps: [
        'Low, balanced platform on every pass — don\'t swing the arms.',
        'Square shoulders to the target before contact.',
        'Jump off two feet on attacks, not one.',
        'Call every ball, even in drills.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 600, // 10-min drill block
    ),
    Exercise(
      id: 'exercise-badminton-match',
      name: 'Badminton Match',
      description:
          'A full singles or doubles match played to standard game format, or a rally-based practice game.',
      disciplineId: 'discipline-badminton',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 1200, // 20-min game segment
    ),
    Exercise(
      id: 'exercise-table-tennis-match',
      name: 'Table Tennis Match',
      description:
          'A full match played to standard game format, or a practice game against a partner or robot.',
      disciplineId: 'discipline-table-tennis',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min game
    ),
    Exercise(
      id: 'exercise-cricket-match',
      name: 'Cricket Match',
      description:
          'A full match — T20, ODI, multi-day, or club — or a practice match. Use periods as innings or sessions.',
      disciplineId: 'discipline-cricket',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 1800, // 30-min innings segment
    ),
    Exercise(
      id: 'exercise-ice-hockey-match',
      name: 'Ice Hockey Match',
      description: 'A full game or scrimmage. Use periods as game periods.',
      disciplineId: 'discipline-ice-hockey',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 1200, // 20-min period
    ),
    Exercise(
      id: 'exercise-baseball-game',
      name: 'Baseball Game',
      description: 'A full game or scrimmage. Use periods as innings.',
      disciplineId: 'discipline-baseball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 1800, // ~30-min inning estimate
    ),
    Exercise(
      id: 'exercise-american-football-game',
      name: 'American Football Game',
      description: 'A full game or scrimmage. Use periods as quarters.',
      disciplineId: 'discipline-american-football',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min quarter
    ),
    Exercise(
      id: 'exercise-rugby-match',
      name: 'Rugby Match',
      description:
          'A full match — 15s, 10s, or 7s — or a practice match. Use periods as halves.',
      disciplineId: 'discipline-rugby',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 2400, // 40-min half
    ),
    Exercise(
      id: 'exercise-lacrosse-game',
      name: 'Lacrosse Game',
      description:
          'A full game or scrimmage — men\'s field, women\'s field, or box. Use periods as quarters.',
      disciplineId: 'discipline-lacrosse',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 720, // 12-min quarter
    ),
    // -------------------------------------------------------------------------
    // Sports Library — Phase 4
    // -------------------------------------------------------------------------
    // Tennis (new entries)
    Exercise(
      id: 'exercise-tennis-serve-practice',
      name: 'Tennis Serve Practice',
      description:
          'Dedicated serving session — baskets of balls from one or both sides, flats, slices, and kicks.',
      disciplineId: 'discipline-tennis',
      howToSteps: [
        'Same ball toss every time — in front, slightly to the right for a righty.',
        'Trophy position before the drop — don\'t rush the load.',
        'Hit up and out, not down on the ball.',
        'Land inside the baseline with the hitting leg.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tennis-return-practice',
      name: 'Tennis Return Practice',
      description:
          'Return-of-serve reps against a live server or ball machine. Focus on read, split, and short swing.',
      disciplineId: 'discipline-tennis',
      howToSteps: [
        'Split-step earlier than you think — before the server makes contact.',
        'Keep the takeback short — no full loop on a first serve.',
        'Neutralize first, attack second serves.',
        'Pick a target before the ball is tossed.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Badminton (new entries)
    Exercise(
      id: 'exercise-badminton-drill',
      name: 'Badminton Drill',
      description:
          'Targeted drill blocks — clears, drops, smashes, net play, or multi-shuttle footwork patterns fed by a partner or coach.',
      disciplineId: 'discipline-badminton',
      howToSteps: [
        'Ready position with racquet up, weight on the balls of the feet.',
        'Recover to center court after every shot.',
        'Wrist and forearm do the work on overheads, not the shoulder.',
        'Lunge and push back — don\'t step and stop at the net.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 600, // 10-min drill block
    ),
    // Table Tennis (new entries)
    Exercise(
      id: 'exercise-table-tennis-drill',
      name: 'Table Tennis Drill',
      description:
          'Multi-ball or partner-fed drill blocks — forehand/backhand loops, blocks, pushes, or footwork patterns.',
      disciplineId: 'discipline-table-tennis',
      howToSteps: [
        'Bent knees, weight forward, paddle up at all times.',
        'Rotate from the waist on loops — don\'t arm the ball.',
        'Recover to neutral after every stroke.',
        'Read the opponent\'s paddle angle, not the ball off the bounce.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 600, // 10-min drill block
    ),
    // Squash
    Exercise(
      id: 'exercise-squash-match',
      name: 'Squash Match',
      description:
          'A full match played to 11 or 15, or a practice game against a regular partner. Use periods as games.',
      disciplineId: 'discipline-squash',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min game
    ),
    Exercise(
      id: 'exercise-squash-drill',
      name: 'Squash Drill',
      description:
          'Solo or partner drill blocks — length, boasts, volleys, or ghosting patterns.',
      disciplineId: 'discipline-squash',
      howToSteps: [
        'Keep the T — every shot should aim to return you there.',
        'Swing through the ball on a straight line parallel to the side wall.',
        'Watch the ball onto the strings, not off them.',
        'Stay low on the split — don\'t stand tall between rallies.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 600, // 10-min drill block
    ),
    // Padel
    Exercise(
      id: 'exercise-padel-match',
      name: 'Padel Match',
      description:
          'A full doubles match, or a practice game with a regular pairing. Use periods as sets.',
      disciplineId: 'discipline-padel',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 1200, // 20-min set equivalent
    ),
    Exercise(
      id: 'exercise-padel-drill',
      name: 'Padel Drill',
      description:
          'Partner-fed drill blocks — wall plays, volleys at the net, lobs, and bandeja/víbora patterns.',
      disciplineId: 'discipline-padel',
      howToSteps: [
        'Hold the net position — don\'t retreat unless lobbed.',
        'Let the ball come off the wall before playing defensively.',
        'Flat, short swings — no topspin loops.',
        'Communicate on every ball with your partner — "mine," "yours," "out."',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 600, // 10-min drill block
    ),
    // BJJ
    Exercise(
      id: 'exercise-bjj-class',
      name: 'BJJ Class',
      description:
          'A full scheduled class — warm-up, technique instruction, drilling, and rolling. Log as one session; use periods for class segments if desired.',
      disciplineId: 'discipline-bjj',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bjj-drilling',
      name: 'BJJ Drilling',
      description:
          'Partner drilling blocks — repping a specific technique, transition, or sequence without resistance.',
      disciplineId: 'discipline-bjj',
      howToSteps: [
        'Drill the movement, not the outcome — no muscling reps.',
        'Switch partners regularly for different body types.',
        'Keep a count — quality reps per round matter more than time.',
        'If the technique fails, ask before repeating it wrong.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bjj-rolling',
      name: 'BJJ Rolling',
      description:
          'Live rolling rounds with rotating partners — open sparring at a negotiated intensity.',
      disciplineId: 'discipline-bjj',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bjj-positional-sparring',
      name: 'BJJ Positional Sparring',
      description:
          'Rolling rounds starting from a fixed position — guard, side control, mount, back — reset to the starting position on escape or submission.',
      disciplineId: 'discipline-bjj',
      howToSteps: [
        'Pick a position and stick to it for the whole round.',
        'Lose the position before you reset — don\'t bail early.',
        'Track what works and what doesn\'t during the round, not after.',
        'Alternate top and bottom between rounds.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bjj-guard-retention-practice',
      name: 'BJJ Guard Retention Practice',
      description:
          'Partner drill — the bottom player defends the guard against systematic passing attempts, reset when passed.',
      disciplineId: 'discipline-bjj',
      howToSteps: [
        'Hips first, legs second — frame with the hips before the knees.',
        'Keep at least one point of connection with the passer at all times.',
        'Re-guard before recovering offense — don\'t scramble to attack.',
        'Breathe through the tight positions, don\'t hold breath.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bjj-guard-passing-practice',
      name: 'BJJ Guard Passing Practice',
      description:
          'Partner drill — the top player works through a passing sequence against a defending guard, reset on pass or sweep.',
      disciplineId: 'discipline-bjj',
      howToSteps: [
        'Control grips or frames before moving the hips.',
        'Kill one leg before trying to pass around or over.',
        'Stay heavy through the shoulder, not the hands.',
        'If the pass stalls, reset pressure instead of forcing.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-bjj-submission-practice',
      name: 'BJJ Submission Practice',
      description:
          'Targeted drilling of specific submissions from a fixed position — entries, finishes, and common defenses.',
      disciplineId: 'discipline-bjj',
      howToSteps: [
        'Drill the setup, not just the finish.',
        'Control the posture and grips before committing to the submission.',
        'Finish with technique — no cranking for leverage.',
        'Drill both the attack and the common escape.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Muay Thai
    Exercise(
      id: 'exercise-muay-thai-class',
      name: 'Muay Thai Class',
      description:
          'A full scheduled class — shadow, pads, bag work, clinch, and optional sparring. Log as one session.',
      disciplineId: 'discipline-muay-thai',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-muay-thai-pad-work',
      name: 'Muay Thai Pad Work',
      description:
          'Timed rounds on Thai pads with a coach — kicks, knees, elbows, and punch-kick combinations.',
      disciplineId: 'discipline-muay-thai',
      howToSteps: [
        'Turn the hip fully on every kick — the shin follows the hip.',
        'Return to stance on the same line you left, not wider.',
        'Step, then strike — never the other way around.',
        'Close combinations with a defensive movement.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-muay-thai-bag-work',
      name: 'Muay Thai Bag Work',
      description:
          'Timed rounds on a banana bag — full toolkit of punches, kicks, knees, and elbows with movement between combinations.',
      disciplineId: 'discipline-muay-thai',
      howToSteps: [
        'Hit hard once, then reset — no spammed kicks.',
        'Check into every kick — balance on landing matters more than power.',
        'Include knees and elbows, not only kicks and punches.',
        'Work around the bag — don\'t stand square.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-muay-thai-clinch-practice',
      name: 'Muay Thai Clinch Practice',
      description:
          'Timed rounds of clinch work with a partner — hand fighting, posture control, knees, sweeps, and turns.',
      disciplineId: 'discipline-muay-thai',
      howToSteps: [
        'Fight for the inside position on the head and neck.',
        'Stay tall — don\'t let the partner bend you forward.',
        'Short, snapping knees from the hip, not full extensions.',
        'Reset posture after every exchange.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-muay-thai-sparring',
      name: 'Muay Thai Sparring',
      description:
          'Live rounds with a partner at agreed intensity — technical sparring or harder prep rounds with shin guards and control.',
      disciplineId: 'discipline-muay-thai',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // MMA
    Exercise(
      id: 'exercise-mma-class',
      name: 'MMA Class',
      description:
          'A full scheduled class — mixed striking, grappling, and transition work. Log as one session.',
      disciplineId: 'discipline-mma',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-mma-pad-work',
      name: 'MMA Pad Work',
      description:
          'Timed rounds on pads with striking plus takedown entries, cage work, or ground transitions mixed in.',
      disciplineId: 'discipline-mma',
      howToSteps: [
        'Treat every strike as a setup for the next phase — takedown, clinch, or exit.',
        'Hands back to guard after every combination — the fight isn\'t over.',
        'Level change realistically — don\'t fake shots.',
        'Finish combinations with a distance reset.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-mma-sparring',
      name: 'MMA Sparring',
      description:
          'Live rounds with a partner covering all phases — striking, clinch, takedowns, and ground — at agreed intensity.',
      disciplineId: 'discipline-mma',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-mma-situational-sparring',
      name: 'MMA Situational Sparring',
      description:
          'Live rounds starting from a fixed situation — back against the cage, bottom guard, in the clinch — reset to the starting position.',
      disciplineId: 'discipline-mma',
      howToSteps: [
        'Pick the situation before the round, don\'t drift between them.',
        'Both partners fight honestly from the position — no easing off.',
        'Reset the instant the situation ends — don\'t keep rolling past it.',
        'Alternate which role you start in between rounds.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Karate
    Exercise(
      id: 'exercise-karate-class',
      name: 'Karate Class',
      description:
          'A full scheduled class — kihon, kata, and kumite. Log as one session.',
      disciplineId: 'discipline-karate',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-karate-kumite',
      name: 'Karate Kumite',
      description:
          'Sparring rounds — point sparring, continuous sparring, or controlled full-contact depending on style.',
      disciplineId: 'discipline-karate',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-karate-kata-practice',
      name: 'Karate Kata Practice',
      description:
          'Solo practice of prescribed forms — timed blocks of kata repetitions at varying intensities.',
      disciplineId: 'discipline-karate',
      howToSteps: [
        'Full kime on every technique — no throwaway reps.',
        'Breathe with the technique, not against it.',
        'Stances drop as low as they do in the first rep; don\'t ride high when tired.',
        'Visualize the opponent at every count.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Judo
    Exercise(
      id: 'exercise-judo-class',
      name: 'Judo Class',
      description:
          'A full scheduled class — ukemi, uchi-komi, drilling, and randori. Log as one session.',
      disciplineId: 'discipline-judo',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-judo-randori',
      name: 'Judo Randori',
      description:
          'Live sparring rounds with rotating partners — standing, ground, or combined depending on the session\'s focus.',
      disciplineId: 'discipline-judo',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-judo-uchi-komi',
      name: 'Judo Uchi-Komi',
      description:
          'Repetitive throw entries with a partner — no follow-through, focused on grip, kuzushi, and entry position.',
      disciplineId: 'discipline-judo',
      howToSteps: [
        'Break the partner\'s balance before stepping in.',
        'Get under the center of gravity on every entry — don\'t reach.',
        'Match tempo to your partner — don\'t rush.',
        'Alternate sides between rounds.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-judo-nage-komi',
      name: 'Judo Nage-Komi',
      description:
          'Partner drilling of full throws with follow-through, typically onto a crash mat. Technique reps at varying intensities.',
      disciplineId: 'discipline-judo',
      howToSteps: [
        'Commit fully to the throw — half-throws build bad habits.',
        'Maintain grip through the landing, don\'t release early.',
        'Alternate who throws between rounds.',
        'Drill breakfalls as part of the rep, not as an afterthought.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Soccer
    Exercise(
      id: 'exercise-soccer-match',
      name: 'Soccer Match',
      description:
          'A full match — competitive, small-sided, or internal — played at standard or reduced duration. Use periods as halves or quarters.',
      disciplineId: 'discipline-soccer',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 2700, // 45-min half
    ),
    Exercise(
      id: 'exercise-soccer-training',
      name: 'Soccer Training',
      description:
          'A full team training session — warm-up, technical work, tactical phases, and scrimmages.',
      disciplineId: 'discipline-soccer',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min phase
    ),
    Exercise(
      id: 'exercise-soccer-shooting-practice',
      name: 'Soccer Shooting Practice',
      description:
          'Dedicated finishing drill blocks — shots from distance, inside the box, one-touch finishes, or set-piece rehearsal.',
      disciplineId: 'discipline-soccer',
      howToSteps: [
        'Plant foot next to the ball, not behind it.',
        'Strike through the middle of the ball for power, under for lift.',
        'Follow through toward the target, don\'t cut the swing short.',
        'Finish into the corners, not down the goalkeeper\'s center.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-soccer-passing-practice',
      name: 'Soccer Passing Practice',
      description:
          'Drill blocks focused on passing patterns — short, long, switches, or combination play under varying pressure.',
      disciplineId: 'discipline-soccer',
      howToSteps: [
        'Open the body before receiving — don\'t square up to the passer.',
        'Weight of pass first, accuracy second.',
        'Scan before the ball arrives, not after.',
        'Receive across the body into the next action.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Basketball
    Exercise(
      id: 'exercise-basketball-game',
      name: 'Basketball Game',
      description:
          'A full game — full court or half-court, competitive or pickup. Use periods as quarters or halves.',
      disciplineId: 'discipline-basketball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 720, // 12-min quarter (NBA)
    ),
    Exercise(
      id: 'exercise-basketball-practice',
      name: 'Basketball Practice',
      description:
          'A full team or solo practice session — skill work, plays, and scrimmage.',
      disciplineId: 'discipline-basketball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min block
    ),
    Exercise(
      id: 'exercise-basketball-shooting-practice',
      name: 'Basketball Shooting Practice',
      description:
          'Dedicated shooting session — catch-and-shoot, off-the-dribble, spot-up, or free throw reps.',
      disciplineId: 'discipline-basketball',
      howToSteps: [
        'Feet set before the catch — jump from a balanced base.',
        'Elbow under the ball, not out to the side.',
        'Follow through with a full wrist snap — hold it until the ball lands.',
        'Same form on every rep, regardless of distance.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-basketball-free-throw-practice',
      name: 'Basketball Free Throw Practice',
      description:
          'Dedicated free throw reps — same routine every shot, tracked as made/missed.',
      disciplineId: 'discipline-basketball',
      howToSteps: [
        'Use the same pre-shot routine on every attempt.',
        'Align the shooting foot with the center of the rim.',
        'Eyes on the back of the rim, not the front.',
        'Shoot with arc — flat shots have no margin.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-basketball-ball-handling-practice',
      name: 'Basketball Ball Handling Practice',
      description:
          'Solo dribbling drill blocks — stationary, moving, two-ball, or cone patterns.',
      disciplineId: 'discipline-basketball',
      howToSteps: [
        'Keep the dribble at or below the hip.',
        'Eyes up — use peripheral vision for the ball.',
        'Push the ball, don\'t slap it.',
        'Change pace within the drill — not just speed but rhythm.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Rugby (new entries)
    Exercise(
      id: 'exercise-rugby-training',
      name: 'Rugby Training',
      description:
          'A full team training session — fitness, skills, phase play, and contact work.',
      disciplineId: 'discipline-rugby',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min phase
    ),
    // Ice Hockey (new entries)
    Exercise(
      id: 'exercise-ice-hockey-practice',
      name: 'Ice Hockey Practice',
      description:
          'A full team practice — skating, passing, shooting, systems, and scrimmage.',
      disciplineId: 'discipline-ice-hockey',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min block
    ),
    // American Football (new entries)
    Exercise(
      id: 'exercise-american-football-practice',
      name: 'American Football Practice',
      description:
          'A full team practice — individual drills, position work, and team periods.',
      disciplineId: 'discipline-american-football',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min block
    ),
    // Baseball (new entries)
    Exercise(
      id: 'exercise-baseball-practice',
      name: 'Baseball Practice',
      description:
          'A full team practice — batting, fielding, pitching, and situational work.',
      disciplineId: 'discipline-baseball',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min block
    ),
    // Cricket (new entries)
    Exercise(
      id: 'exercise-cricket-practice',
      name: 'Cricket Practice',
      description:
          'A net or field practice session — batting, bowling, and fielding work.',
      disciplineId: 'discipline-cricket',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min block
    ),
    // Lacrosse (new entries)
    Exercise(
      id: 'exercise-lacrosse-practice',
      name: 'Lacrosse Practice',
      description:
          'A full team practice — stick work, shooting, defense, and team periods.',
      disciplineId: 'discipline-lacrosse',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 900, // 15-min block
    ),
    // Golf
    Exercise(
      id: 'exercise-golf-round',
      name: 'Golf Round',
      description:
          'A full round — 9 or 18 holes — stroke play, match play, or casual. Use periods as nines or sets of holes.',
      disciplineId: 'discipline-golf',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 5400, // 90-min per 9 holes
    ),
    Exercise(
      id: 'exercise-golf-range-practice',
      name: 'Golf Range Practice',
      description:
          'A driving range session — full swings, club-by-club work, or targeted shot shaping.',
      disciplineId: 'discipline-golf',
      howToSteps: [
        'Go through a full pre-shot routine on every ball, not just the first few.',
        'Hit to specific targets, not just out into the range.',
        'Change clubs every few shots rather than bucket-bashing one.',
        'Log misses as left/right/thin/fat — track patterns, not just outcomes.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-golf-short-game-practice',
      name: 'Golf Short Game Practice',
      description:
          'Dedicated session around the green — chipping, pitching, and bunker work from varied lies and distances.',
      disciplineId: 'discipline-golf',
      howToSteps: [
        'Land the ball on a chosen spot, not at the flag.',
        'Weight forward on chips — don\'t try to scoop the ball up.',
        'Accelerate through contact on bunker shots.',
        'Vary the club for chips — don\'t default to one.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-golf-putting-practice',
      name: 'Golf Putting Practice',
      description:
          'Dedicated putting session — distance control, lag putting, short putts, or breaking putts.',
      disciplineId: 'discipline-golf',
      howToSteps: [
        'Read the putt, pick a line, commit — no second-guessing over the ball.',
        'Match stroke length to distance, not swing speed.',
        'Keep the head still through contact — don\'t track the ball.',
        'Drill short putts at the end when tired, not at the start.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Climbing
    Exercise(
      id: 'exercise-climbing-session',
      name: 'Climbing Session',
      description:
          'An open-ended climbing session — gym or outdoor, bouldering or roped. Use periods as problem/route attempts if tracking.',
      disciplineId: 'discipline-climbing',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      defaultRoundDurationSecs: 600, // 10-min block
    ),
    Exercise(
      id: 'exercise-climbing-projecting',
      name: 'Climbing Projecting',
      description:
          'Working a specific problem or route at or near the limit — attempts interspersed with rest.',
      disciplineId: 'discipline-climbing',
      howToSteps: [
        'Rest fully between attempts — 3–5 minutes minimum on hard projects.',
        'Work the project in sections before trying it linked.',
        'Rehearse the sequence mentally before each attempt.',
        'Call it after 4–5 quality attempts — diminishing returns after that.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-climbing-volume',
      name: 'Climbing Volume',
      description:
          'High-quantity climbing at sub-maximal grades — mileage for technique, capacity, and movement literacy.',
      disciplineId: 'discipline-climbing',
      howToSteps: [
        'Stay 2–3 grades below limit — this isn\'t projecting.',
        'Focus on footwork — silent feet, weight through the toe.',
        'Climb efficiently, not fast — static where possible.',
        'Stop before form breaks down, not after.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-climbing-hangboard-session',
      name: 'Climbing Hangboard Session',
      description:
          'Structured hangboard protocol — max hangs, repeaters, or specific grip work.',
      disciplineId: 'discipline-climbing',
      howToSteps: [
        'Warm up fully before touching the board — no cold max hangs.',
        'Shoulders engaged, not shrugged — active hang only.',
        'Stop the set before form degrades, not when time expires.',
        'Do not hangboard on fatigued fingers — reschedule if needed.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // -------------------------------------------------------------------------
    // Cardio Library — Phase 4
    // -------------------------------------------------------------------------
    // Running (new)
    Exercise(
      id: 'exercise-sprint-intervals',
      name: 'Sprint Intervals',
      description:
          'Short, all-out efforts of 10–30 seconds with long recovery between. Develops raw top-end speed and anaerobic power.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Every rep is maximum effort — if rep 4 is as fast as rep 1, recovery is long enough.',
        'Recovery between reps is 2–4 minutes of walking or very easy jogging.',
        'Always warm up thoroughly — cold sprints injure hamstrings.',
        'Quality over quantity. When pace drops, end the session.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-strides',
      name: 'Strides',
      description:
          'Short accelerations of 80–100 meters at roughly 5K race pace, performed after easy runs. Maintains neuromuscular sharpness without adding training stress.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Build pace smoothly over the first 20 meters, hold it, then decelerate.',
        'Focus on relaxed form — shoulders down, tall posture, quick feet.',
        'Full recovery between each stride — walk back, don\'t rush.',
        '4–8 strides is plenty. This is sharpening, not a workout.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-trail-run',
      name: 'Trail Run',
      description:
          'An easy-to-moderate effort run on dirt, gravel, or technical singletrack. Lower impact than road running, with added demand on ankle stability and footing awareness.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Pace by effort, not by watch — hills and technical sections will mess with your numbers.',
        'Shorten your stride on descents and technical ground.',
        'Look ahead, not at your feet, on uneven terrain.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-treadmill-run',
      name: 'Treadmill Run',
      description:
          'Any run performed on a treadmill. Useful when weather or time doesn\'t cooperate, and lets you control pace and incline precisely.',
      disciplineId: 'discipline-running',
      howToSteps: [
        'Set a 1% incline to approximate outdoor effort.',
        'Pick the session type first — easy, tempo, intervals — and set the pace accordingly.',
        'Don\'t grip the rails. If the pace is too hard, slow it down.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Cycling
    Exercise(
      id: 'exercise-zone-2-ride',
      name: 'Zone 2 Ride',
      description:
          'A long, easy-to-moderate ride at aerobic endurance pace. The cycling equivalent of the easy run — the foundation of cycling fitness.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Ride at a conversational pace — you should be able to speak in full sentences.',
        'Target roughly 65–75% of max heart rate or 55–75% of FTP if you ride with a power meter.',
        'Duration is the point, not intensity. 60–180 minutes is typical.',
        'Resist the urge to chase riders or Strava segments. Keep it easy.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-tempo-ride',
      name: 'Tempo Ride',
      description:
          'A sustained ride at moderately hard intensity, above endurance but below threshold. Builds aerobic capacity and muscular endurance.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Effort is 7 out of 10 — comfortably uncomfortable.',
        'Target roughly 76–90% of FTP or 80–90% of threshold heart rate.',
        'Typical duration is 20–60 minutes of continuous tempo work, or broken into blocks.',
        'You should be breathing heavily but not gasping.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-sweet-spot-intervals',
      name: 'Sweet Spot Intervals',
      description:
          'Intervals at 88–94% of FTP — the maximum intensity you can sustain for long durations. High training stimulus with manageable recovery cost.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Work intervals are typically 10–20 minutes long.',
        'Focus on smooth, steady power — not surging and fading.',
        'Rest intervals are short: 3–5 minutes of easy pedaling.',
        'Common session: 3 x 15 minutes at 90% FTP with 5-minute recovery.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-threshold-intervals',
      name: 'Threshold Intervals',
      description:
          'Intervals held at or near FTP — the hardest intensity sustainable for about an hour. Raises your ceiling for sustained effort.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Work intervals are typically 8–20 minutes at 95–105% of FTP.',
        'These hurt. Rate of perceived exertion is 8–9 out of 10.',
        'Rest intervals are 4–8 minutes of easy pedaling.',
        'Don\'t start too hard — negative-split the intervals if anything.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-vo2-max-intervals',
      name: 'VO2 Max Intervals',
      description:
          'Short, very hard efforts above threshold — 3 to 5 minutes of suffering per rep. Develops maximum aerobic capacity and raises ceiling for hard efforts.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Work intervals are typically 3–5 minutes at 110–120% FTP.',
        'Effort is 9 out of 10 — you can count reps, not sentences.',
        'Recovery is equal to or slightly shorter than the work interval.',
        'These sessions are brutal. Limit to once per week in-season.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-cycling-sprint-intervals',
      name: 'Cycling Sprint Intervals',
      description:
          'All-out sprints of 10–30 seconds with long recovery. Builds peak power and anaerobic capacity.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Each sprint is maximum effort — 100% gas.',
        'Get out of the saddle and attack the start of the sprint.',
        'Recovery is 3–5 minutes of easy spinning.',
        'Stop the session when peak power drops significantly.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-long-ride',
      name: 'Long Ride',
      description:
          'The cyclist\'s long run — an extended ride at mostly easy intensity, occasionally spicier. Builds aerobic durability and tests fueling and pacing.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Keep the bulk of the ride in Zone 2.',
        'Fuel every 30–45 minutes — 60–90g of carbs per hour for rides over 2 hours.',
        'Don\'t try to "make it a workout." Consistency of easy riding is what builds durability.',
        'Plan your route — bonking 40km from home is a long walk.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-recovery-ride',
      name: 'Recovery Ride',
      description:
          'A very easy spin after a hard session or race. Promotes blood flow and active recovery without adding training stress.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Effort is 3 out of 10 or lower.',
        'Keep it short: 30–60 minutes is plenty.',
        'Stay in the small ring and let the legs turn over.',
        'If it feels like a workout, ease off further.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-stationary-bike',
      name: 'Stationary Bike',
      description:
          'Any indoor cycling effort on a stationary, spin, or smart bike. Zero traffic, zero weather, full pace control.',
      disciplineId: 'discipline-cycling',
      howToSteps: [
        'Set up position first — saddle height, reach, handlebar — before starting.',
        'Pick the session type (Zone 2, tempo, intervals) and hold to it.',
        'Indoor cycling runs hot. Fans and hydration matter more than outdoors.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Rowing
    Exercise(
      id: 'exercise-steady-state-row',
      name: 'Steady State Row',
      description:
          'A sustained, moderate-intensity erg session at aerobic pace. The foundation of rowing training and an efficient full-body aerobic workout.',
      disciplineId: 'discipline-rowing',
      howToSteps: [
        'Target a stroke rate of 20–24 strokes per minute.',
        'Effort is conversational — 5 or 6 out of 10.',
        'Focus on a long, smooth stroke rather than a fast, choppy one.',
        'Typical duration is 30–60 minutes.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-rowing-intervals',
      name: 'Rowing Intervals',
      description:
          'Repeated hard erg efforts with rest between. Builds power and anaerobic capacity for rowing and general conditioning.',
      disciplineId: 'discipline-rowing',
      howToSteps: [
        'Common intervals: 500m, 750m, 1000m repeats.',
        'Work intervals should be paced to match — don\'t blow up on rep 1.',
        'Stroke rate climbs with intensity: typically 28–34 for intervals.',
        'Rest is typically equal to or slightly longer than work time.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-2k-row-test',
      name: '2K Test',
      description:
          'The rowing benchmark — an all-out 2000-meter effort. The gold-standard test of rowing fitness and a brutal measure of anaerobic capacity.',
      disciplineId: 'discipline-rowing',
      howToSteps: [
        'Warm up thoroughly — 15–20 minutes including pace work.',
        'Have a plan: target split, stroke rate per segment, and when you\'ll push.',
        'The third 500 is always the hardest. Hold form through it.',
        'Don\'t do these often — once every 8–12 weeks is plenty.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-long-row',
      name: 'Long Row',
      description:
          'An extended low-intensity erg session, typically 60–90 minutes. Builds aerobic base with minimal impact.',
      disciplineId: 'discipline-rowing',
      howToSteps: [
        'Stroke rate stays low: 18–22.',
        'Focus on relaxed, efficient form — fatigue will expose technique breakdowns.',
        'Break up the monotony with podcasts, audiobooks, or film.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-power-strokes',
      name: 'Power Strokes',
      description:
          'Short bursts of maximum-power rowing within a longer steady piece. Trains peak force production without full interval structure.',
      disciplineId: 'discipline-rowing',
      howToSteps: [
        'Typical structure: 10 hard strokes every minute during a 10–20 minute piece.',
        'Hard strokes are full-power, same stroke rate — not faster, harder.',
        'Return to steady-state pace immediately after each set of power strokes.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Swimming
    Exercise(
      id: 'exercise-easy-swim',
      name: 'Easy Swim',
      description:
          'A low-intensity continuous swim focused on technique and aerobic base. The swimming equivalent of an easy run.',
      disciplineId: 'discipline-swimming',
      howToSteps: [
        'Focus on feel and stroke mechanics, not pace.',
        'Breathing should be relaxed and controlled.',
        'Typical duration is 20–45 minutes, continuous or with short rest.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-swim-intervals',
      name: 'Swim Intervals',
      description:
          'Repeated pool lengths or sets at hard pace with structured rest. The bread and butter of swim training.',
      disciplineId: 'discipline-swimming',
      howToSteps: [
        'Common sets: 10 x 100m on a fixed send-off time.',
        'Pace is aggressive but sustainable across the whole set.',
        'Rest is determined by the send-off — faster swims buy more rest.',
        'Technique should hold even as fatigue builds.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-swim-sprints',
      name: 'Swim Sprints',
      description:
          'All-out short efforts, typically 25m to 100m, with long recovery. Builds raw speed and anaerobic capacity.',
      disciplineId: 'discipline-swimming',
      howToSteps: [
        'Each sprint is maximum effort from push-off.',
        'Rest 1–3 minutes between sprints — full recovery is the point.',
        'Quality over quantity. 6–10 sprints is plenty.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-long-swim',
      name: 'Long Swim',
      description:
          'An extended continuous swim, typically 1500m or longer. Builds aerobic capacity and mental toughness in the water.',
      disciplineId: 'discipline-swimming',
      howToSteps: [
        'Pace easier than you think — the back half is the test.',
        'Sight-breathing if you\'re training for open water.',
        'Break the distance into chunks mentally: halves, quarters, or lap counts.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-swim-drills',
      name: 'Drill Set',
      description:
          'A technique-focused set using single-arm, catch-up, fist drill, or kickboard work. Improves stroke mechanics without high aerobic demand.',
      disciplineId: 'discipline-swimming',
      howToSteps: [
        'Slow down and focus — drill work is about quality, not effort.',
        'Mix drills: single-arm, catch-up, fist, fingertip drag, 6-3-6.',
        'Use a kickboard or pull buoy to isolate the upper or lower body.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-swim-kick-set',
      name: 'Swim Kick Set',
      description:
          'Kickboard-based swimming focused entirely on leg work. Builds leg endurance and kick power without upper-body recovery issues.',
      disciplineId: 'discipline-swimming',
      howToSteps: [
        'Kick from the hips, not the knees.',
        'Keep the kick narrow and steady — big splashing kicks waste energy.',
        'Typical set: 4–8 x 50m or 100m kick with short rest.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Walking & Hiking
    Exercise(
      id: 'exercise-brisk-walk',
      name: 'Brisk Walk',
      description:
          'A fast-paced walk that elevates heart rate without the impact of running. An underrated foundation for any fitness program.',
      disciplineId: 'discipline-walking',
      howToSteps: [
        'Pace is one where holding a conversation is possible but not effortless.',
        'Swing your arms naturally and stay tall.',
        'Aim for 30–60 minutes.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-incline-walk',
      name: 'Incline Walk',
      description:
          'A sustained walk on a treadmill incline or uphill outdoors. Builds aerobic fitness and leg strength with minimal impact — great cross-training for runners.',
      disciplineId: 'discipline-walking',
      howToSteps: [
        'Incline is 8–15% on a treadmill, or a meaningful uphill gradient outdoors.',
        'Don\'t hold the rails on a treadmill — it defeats the purpose.',
        'Heart rate should climb into low Zone 2 or 3.',
        'Typical duration is 30–60 minutes.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-rucking',
      name: 'Rucking',
      description:
          'Walking with a weighted pack on the back. A low-impact strength-and-cardio combination used by military, hikers, and anyone who wants to build work capacity without running.',
      disciplineId: 'discipline-walking',
      howToSteps: [
        'Start with 10–15% of your bodyweight in the pack.',
        'Wear shoes with good support — rucking exposes weak footwear fast.',
        'Stay tall and don\'t hunch under the load.',
        'Build duration before adding weight.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-hike',
      name: 'Hike',
      description:
          'An extended outdoor walk over trails, often with elevation gain. Mix of aerobic work, leg strength, and time in nature.',
      disciplineId: 'discipline-walking',
      howToSteps: [
        'Pace by terrain, not by time — hills dictate the effort.',
        'Fuel and hydrate on anything over 2 hours.',
        'Pack for conditions: layers, water, navigation.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Machine Cardio
    Exercise(
      id: 'exercise-elliptical-steady',
      name: 'Elliptical Steady',
      description:
          'A sustained effort on an elliptical machine at moderate intensity. Low-impact alternative to running for aerobic work or injury recovery.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Target Zone 2 — conversational pace.',
        'Use the arms actively, not just the legs.',
        'Resistance should be meaningful — spinning the handle on low resistance isn\'t a workout.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-elliptical-intervals',
      name: 'Elliptical Intervals',
      description:
          'Hard efforts on the elliptical alternated with easy recovery. Low-impact interval training that spares the joints.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Work intervals of 1–3 minutes at hard effort.',
        'Increase resistance, stride rate, or both to raise intensity.',
        'Recovery at easy resistance, matching the work interval in length.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-stair-climber',
      name: 'Stair Climber',
      description:
          'Sustained effort on a stair climbing machine. Brutal on the legs, great for glutes and lungs, low impact.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Don\'t hold the rails — lean in and let your legs do the work.',
        'Stand tall, don\'t slouch over the console.',
        'Target Zone 2–3 for steady sessions.',
        '20–40 minutes is a full session for most.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-stair-intervals',
      name: 'Stair Intervals',
      description:
          'Hard efforts on a stair climber alternated with recovery. Builds leg-specific aerobic capacity and work tolerance.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Work intervals of 1–3 minutes at a high step rate.',
        'Recovery at slow climbing pace, not standing rest.',
        'Hands off the rails on work intervals.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-ski-erg',
      name: 'Ski Erg',
      description:
          'A standing upper-body-dominant machine mimicking cross-country ski poling. Full-body aerobic work with heavy emphasis on back, core, and shoulders.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Drive through the hips and core, not just the arms.',
        'Stroke rate varies by session: lower for steady, higher for intervals.',
        'Stand close enough to the machine to pull straight down and through.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-assault-bike',
      name: 'Assault Bike',
      description:
          'A fan bike with moving handles that becomes harder the harder you work. A staple of CrossFit and conditioning work — punishing and efficient.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Resistance scales with effort — there\'s no easy gear.',
        'Use arms and legs together for maximum power output.',
        'Common workouts: 30 seconds on, 30 seconds off, repeated.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-assault-bike-sprints',
      name: 'Assault Bike Sprints',
      description:
          'All-out short efforts on the fan bike, typically 10–30 seconds, with long recovery. Peak power and conditioning in a low-impact format.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Every sprint is maximum effort.',
        'Rest 2–4 minutes of easy spinning between sprints.',
        'These are miserable. Keep the session short — 6 to 10 sprints is enough.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-jump-rope-steady',
      name: 'Jump Rope Steady',
      description:
          'Sustained skipping at a steady pace. Deceptively hard aerobic work that doubles as coordination and foot-speed training.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Stay on the balls of the feet, barely leaving the ground.',
        'Turn the rope with the wrists, not the whole arm.',
        'Break up rounds if unbroken is unrealistic — 60 seconds on, 30 off works well.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-jump-rope-intervals',
      name: 'Jump Rope Intervals',
      description:
          'Hard skipping efforts alternated with rest. Used by boxers and athletes for conditioning and footwork.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Work intervals at high pace — double-unders if you have them.',
        'Rest as long as needed to keep the quality high.',
        'Protect the wrists with good rope technique and don\'t let it become a shoulder workout.',
      ],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    Exercise(
      id: 'exercise-rowing-sprints',
      name: 'Rowing Erg Sprints',
      description:
          'All-out short erg efforts, typically 100m to 500m. Builds peak power and anaerobic capacity.',
      disciplineId: 'discipline-machine-cardio',
      howToSteps: [
        'Drive hard with the legs — rowing power comes from below the waist.',
        'Stroke rate climbs to 32–38 on sprints.',
        'Rest fully between reps to maintain intensity.',
      ],
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
    UnitModel(
      id: 'unit-cm',
      key: 'cm',
      name: 'Centimeters',
      unitType: 'length',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    UnitModel(
      id: 'unit-pct',
      key: 'pct',
      name: 'Percent',
      unitType: 'ratio',
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

  /// Default food group categories seeded on first install and via
  /// migration on existing installs.
  ///
  /// Names match the 8 `category` values in
  /// `assets/data/food_catalog.json` so the bundled catalog can be
  /// cross-referenced with user library groups in future iterations.
  /// IDs are deterministic so re-seeding is idempotent (skip if
  /// already present, regardless of display name).
  ///
  /// The user can rename, archive, or delete these groups — none of
  /// the mutator paths check for seed provenance, so user actions
  /// always take precedence.
  static final List<FoodGroup> defaultFoodGroups = [
    FoodGroup(
      id: 'food-group-proteins',
      name: 'Proteins',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-dairy',
      name: 'Dairy',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-grains-starches',
      name: 'Grains & Starches',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-fruits',
      name: 'Fruits',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-vegetables',
      name: 'Vegetables',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-nuts-seeds-fats',
      name: 'Nuts, Seeds & Fats',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-snacks-prepared',
      name: 'Snacks & Prepared',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-drinks',
      name: 'Drinks',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    FoodGroup(
      id: 'food-group-condiments',
      name: 'Condiments',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
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
    // Isometric / drill companion metric
    MetricDefinition(
      id: 'metric-extra-weight',
      key: 'extra-weight',
      name: 'Extra Weight',
      dataType: 'real',
      defaultUnitId: 'unit-kg',
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
    MetricApplicability(metricId: 'metric-extra-weight', effortKind: 'timed'),

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
    MetricApplicability(metricId: 'metric-extra-weight', effortKind: 'drill'),
  ];

  /// Maps exercise IDs to muscle group IDs
  static final Map<String, List<String>> exerciseMuscleGroupRelationships = {
    // Resistance / Lifting exercises
    'exercise-barbell-squat': [
      'muscle-quads',
      'muscle-glutes',
      'muscle-hamstrings',
    ],
    'exercise-front-squat': ['muscle-quads', 'muscle-glutes'],
    'exercise-goblet-squat': ['muscle-quads', 'muscle-glutes'],
    'exercise-dumbbell-split-squat': ['muscle-quads', 'muscle-glutes'],
    'exercise-bulgarian-split-squat': ['muscle-quads', 'muscle-glutes'],
    'exercise-hack-squat': ['muscle-quads', 'muscle-glutes'],
    'exercise-leg-press': [
      'muscle-quads',
      'muscle-glutes',
      'muscle-hamstrings',
    ],
    'exercise-pistol-squat': ['muscle-quads', 'muscle-glutes'],
    'exercise-bench-press': [
      'muscle-chest',
      'muscle-triceps',
      'muscle-shoulders',
    ],
    'exercise-incline-bench-press': [
      'muscle-chest',
      'muscle-shoulders',
      'muscle-triceps',
    ],
    'exercise-decline-bench-press': ['muscle-chest', 'muscle-triceps'],
    'exercise-dumbbell-bench-press': [
      'muscle-chest',
      'muscle-triceps',
      'muscle-shoulders',
    ],
    'exercise-incline-dumbbell-bench-press': [
      'muscle-chest',
      'muscle-shoulders',
      'muscle-triceps',
    ],
    'exercise-push-up': ['muscle-chest', 'muscle-triceps', 'muscle-shoulders'],
    'exercise-dip': ['muscle-chest', 'muscle-triceps'],
    'exercise-machine-chest-press': [
      'muscle-chest',
      'muscle-triceps',
      'muscle-shoulders',
    ],
    'exercise-deadlift': ['muscle-back', 'muscle-hamstrings', 'muscle-glutes'],
    'exercise-sumo-deadlift': [
      'muscle-back',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-romanian-deadlift-barbell': [
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-romanian-deadlift-dumbbell': [
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-good-morning': [
      'muscle-hamstrings',
      'muscle-glutes',
      'muscle-back',
    ],
    'exercise-barbell-hip-thrust': ['muscle-glutes', 'muscle-hamstrings'],
    'exercise-kettlebell-swing': [
      'muscle-glutes',
      'muscle-hamstrings',
      'muscle-back',
    ],
    'exercise-back-extension': [
      'muscle-glutes',
      'muscle-hamstrings',
      'muscle-back',
    ],
    'exercise-overhead-press': ['muscle-shoulders', 'muscle-triceps'],
    'exercise-dumbbell-shoulder-press': ['muscle-shoulders', 'muscle-triceps'],
    'exercise-seated-dumbbell-shoulder-press': [
      'muscle-shoulders',
      'muscle-triceps',
    ],
    'exercise-landmine-press': ['muscle-shoulders', 'muscle-triceps'],
    'exercise-arnold-press': ['muscle-shoulders', 'muscle-triceps'],
    'exercise-pullup': ['muscle-back', 'muscle-biceps'],
    'exercise-chin-up': ['muscle-back', 'muscle-biceps'],
    'exercise-lat-pulldown': ['muscle-back', 'muscle-biceps'],
    'exercise-neutral-grip-pulldown': ['muscle-back', 'muscle-biceps'],
    'exercise-straight-arm-pulldown': ['muscle-back'],
    'exercise-barbell-row': ['muscle-back', 'muscle-biceps'],
    'exercise-pendlay-row': ['muscle-back', 'muscle-biceps'],
    'exercise-dumbbell-row': ['muscle-back', 'muscle-biceps'],
    'exercise-seated-cable-row': ['muscle-back', 'muscle-biceps'],
    'exercise-chest-supported-row': ['muscle-back', 'muscle-biceps'],
    'exercise-t-bar-row': ['muscle-back', 'muscle-biceps'],
    'exercise-inverted-row': ['muscle-back', 'muscle-biceps'],
    'exercise-face-pull': ['muscle-shoulders', 'muscle-back'],
    'exercise-walking-lunge': ['muscle-quads', 'muscle-glutes'],
    'exercise-reverse-lunge': ['muscle-quads', 'muscle-glutes'],
    'exercise-step-up': ['muscle-quads', 'muscle-glutes'],
    'exercise-single-leg-rdl': ['muscle-hamstrings', 'muscle-glutes'],
    'exercise-lateral-raise': ['muscle-shoulders'],
    'exercise-cable-lateral-raise': ['muscle-shoulders'],
    'exercise-rear-delt-fly': ['muscle-shoulders', 'muscle-back'],
    'exercise-front-raise': ['muscle-shoulders'],
    'exercise-upright-row': ['muscle-shoulders', 'muscle-back'],
    'exercise-barbell-curl': ['muscle-biceps'],
    'exercise-dumbbell-curl': ['muscle-biceps'],
    'exercise-hammer-curl': ['muscle-biceps'],
    'exercise-preacher-curl': ['muscle-biceps'],
    'exercise-triceps-pressdown': ['muscle-triceps'],
    'exercise-overhead-triceps-extension': ['muscle-triceps'],
    'exercise-skullcrusher': ['muscle-triceps'],
    'exercise-cable-pull-through': ['muscle-glutes', 'muscle-hamstrings'],
    'exercise-glute-kickback': ['muscle-glutes'],
    'exercise-nordic-curl': ['muscle-hamstrings'],
    'exercise-standing-calf-raise': ['muscle-hamstrings'],
    'exercise-seated-calf-raise': ['muscle-hamstrings'],
    'exercise-farmers-carry': ['muscle-back', 'muscle-core'],
    'exercise-pallof-press': ['muscle-core'],
    'exercise-cable-woodchop': ['muscle-core'],
    'exercise-hanging-leg-raise': ['muscle-core'],
    'exercise-cable-crunch': ['muscle-core'],
    'exercise-ab-wheel-rollout': ['muscle-core'],
    // Calisthenics exercises
    'exercise-plank-hold': ['muscle-core'],
    'exercise-side-plank': ['muscle-core', 'muscle-shoulders'],
    'exercise-wall-sit': ['muscle-quads', 'muscle-glutes'],
    'exercise-dead-hang': ['muscle-back', 'muscle-biceps'],
    'exercise-hollow-body-hold': ['muscle-core'],
    'exercise-glute-bridge-hold': ['muscle-glutes', 'muscle-core'],
    'exercise-l-sit-hold': ['muscle-core'],
    'exercise-isometric-pushup-hold': [
      'muscle-chest',
      'muscle-triceps',
      'muscle-shoulders',
    ],
    'exercise-calf-raise-hold': ['muscle-hamstrings'],
    'exercise-split-squat-hold': [
      'muscle-quads',
      'muscle-glutes',
      'muscle-hamstrings',
    ],
    // New Isometric Holds — Core
    'exercise-rkc-plank': ['muscle-core', 'muscle-glutes'],
    'exercise-long-lever-plank': ['muscle-core'],
    'exercise-dead-bug-hold': ['muscle-core'],
    'exercise-copenhagen-plank': ['muscle-core'],
    // New Isometric Holds — Lower-Body
    'exercise-single-leg-glute-bridge-hold': ['muscle-glutes', 'muscle-core'],
    'exercise-single-leg-calf-raise-hold': ['muscle-hamstrings'],
    'exercise-pistol-squat-hold': ['muscle-quads', 'muscle-glutes'],
    'exercise-cossack-squat-hold': ['muscle-quads', 'muscle-glutes'],
    // New Isometric Holds — Upper-Body
    'exercise-active-hang': ['muscle-back', 'muscle-shoulders'],
    'exercise-tuck-front-lever-hold': ['muscle-back', 'muscle-core'],
    'exercise-advanced-tuck-front-lever-hold': ['muscle-back', 'muscle-core'],
    'exercise-tuck-back-lever-hold': [
      'muscle-chest',
      'muscle-shoulders',
      'muscle-core',
    ],
    'exercise-ring-support-hold': [
      'muscle-chest',
      'muscle-shoulders',
      'muscle-triceps',
    ],
    'exercise-handstand-hold-wall': ['muscle-shoulders', 'muscle-core'],
    // Static Stretches
    'exercise-standing-hamstring-stretch': ['muscle-hamstrings'],
    'exercise-seated-forward-fold': ['muscle-hamstrings', 'muscle-back'],
    'exercise-standing-quad-stretch': ['muscle-quads'],
    'exercise-couch-stretch': ['muscle-quads', 'muscle-glutes'],
    'exercise-kneeling-hip-flexor-stretch': ['muscle-quads', 'muscle-glutes'],
    'exercise-pigeon-pose': ['muscle-glutes'],
    'exercise-seated-piriformis-stretch': ['muscle-glutes'],
    'exercise-doorway-chest-stretch': ['muscle-chest', 'muscle-shoulders'],
    'exercise-lat-stretch': ['muscle-back'],
    'exercise-overhead-triceps-stretch': ['muscle-triceps', 'muscle-back'],
    'exercise-neck-side-stretch': ['muscle-shoulders'],
    'exercise-standing-calf-stretch': ['muscle-hamstrings'],
    'exercise-soleus-stretch': ['muscle-hamstrings'],
    'exercise-childs-pose': ['muscle-back', 'muscle-shoulders'],
    // Mobility Holds
    'exercise-90-90-hip-hold': ['muscle-glutes'],
    'exercise-frog-stretch': ['muscle-glutes'],
    'exercise-deep-squat-hold': ['muscle-quads', 'muscle-glutes'],
    'exercise-thoracic-rotation-hold': ['muscle-back'],
    'exercise-cat-cow-hold': ['muscle-back', 'muscle-core'],
    'exercise-worlds-greatest-stretch-hold': [
      'muscle-quads',
      'muscle-glutes',
      'muscle-back',
    ],
    'exercise-seated-butterfly-hold': ['muscle-glutes'],
    // Sports exercises - full body engagement
    'exercise-tennis-match': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
    'exercise-tennis-drill': ['muscle-legs', 'muscle-shoulders', 'muscle-core'],
    'exercise-volleyball-match': [
      'muscle-shoulders',
      'muscle-arms',
      'muscle-core',
      'muscle-legs',
    ],
    'exercise-volleyball-drill': [
      'muscle-shoulders',
      'muscle-arms',
      'muscle-core',
    ],
    'exercise-badminton-match': [
      'muscle-legs',
      'muscle-shoulders',
      'muscle-core',
    ],
    'exercise-table-tennis-match': ['muscle-core', 'muscle-shoulders'],
    'exercise-cricket-match': [
      'muscle-legs',
      'muscle-shoulders',
      'muscle-core',
    ],
    'exercise-ice-hockey-match': [
      'muscle-legs',
      'muscle-core',
      'muscle-shoulders',
    ],
    'exercise-baseball-game': [
      'muscle-shoulders',
      'muscle-core',
      'muscle-legs',
    ],
    'exercise-american-football-game': [
      'muscle-legs',
      'muscle-shoulders',
      'muscle-core',
    ],
    'exercise-rugby-match': ['muscle-legs', 'muscle-core', 'muscle-shoulders'],
    'exercise-lacrosse-game': [
      'muscle-legs',
      'muscle-shoulders',
      'muscle-core',
    ],
    // Cardio library — Phase 4
    'exercise-sprint-intervals': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-strides': ['muscle-quads', 'muscle-hamstrings'],
    'exercise-trail-run': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-treadmill-run': ['muscle-quads', 'muscle-hamstrings'],
    'exercise-zone-2-ride': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-tempo-ride': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-sweet-spot-intervals': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-threshold-intervals': ['muscle-quads', 'muscle-hamstrings'],
    'exercise-vo2-max-intervals': ['muscle-quads', 'muscle-hamstrings'],
    'exercise-cycling-sprint-intervals': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-long-ride': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-recovery-ride': ['muscle-quads', 'muscle-glutes'],
    'exercise-stationary-bike': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-steady-state-row': [
      'muscle-back',
      'muscle-hamstrings',
      'muscle-glutes',
      'muscle-core',
    ],
    'exercise-rowing-intervals': [
      'muscle-back',
      'muscle-hamstrings',
      'muscle-glutes',
      'muscle-core',
    ],
    'exercise-2k-row-test': [
      'muscle-back',
      'muscle-hamstrings',
      'muscle-glutes',
      'muscle-core',
    ],
    'exercise-long-row': [
      'muscle-back',
      'muscle-hamstrings',
      'muscle-glutes',
      'muscle-core',
    ],
    'exercise-power-strokes': [
      'muscle-back',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-easy-swim': ['muscle-shoulders', 'muscle-back', 'muscle-core'],
    'exercise-swim-intervals': [
      'muscle-shoulders',
      'muscle-back',
      'muscle-core',
    ],
    'exercise-swim-sprints': ['muscle-shoulders', 'muscle-back', 'muscle-core'],
    'exercise-long-swim': ['muscle-shoulders', 'muscle-back', 'muscle-core'],
    'exercise-swim-drills': ['muscle-shoulders', 'muscle-back'],
    'exercise-swim-kick-set': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-brisk-walk': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-incline-walk': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-rucking': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
      'muscle-back',
    ],
    'exercise-hike': ['muscle-quads', 'muscle-hamstrings', 'muscle-glutes'],
    'exercise-elliptical-steady': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-elliptical-intervals': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-stair-climber': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-stair-intervals': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-glutes',
    ],
    'exercise-ski-erg': ['muscle-back', 'muscle-shoulders', 'muscle-core'],
    'exercise-assault-bike': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-shoulders',
    ],
    'exercise-assault-bike-sprints': [
      'muscle-quads',
      'muscle-hamstrings',
      'muscle-shoulders',
    ],
    'exercise-jump-rope-steady': ['muscle-quads', 'muscle-hamstrings'],
    'exercise-jump-rope-intervals': ['muscle-quads', 'muscle-hamstrings'],
    'exercise-rowing-sprints': [
      'muscle-back',
      'muscle-hamstrings',
      'muscle-glutes',
      'muscle-core',
    ],
  };

  /// Maps exercise IDs to equipment IDs
  static final Map<String, List<String>> exerciseEquipmentRelationships = {
    // Resistance / Lifting exercises
    'exercise-barbell-squat': ['equipment-barbell'],
    'exercise-front-squat': ['equipment-barbell'],
    'exercise-goblet-squat': ['equipment-dumbbell'],
    'exercise-dumbbell-split-squat': ['equipment-dumbbell'],
    'exercise-bulgarian-split-squat': ['equipment-dumbbell'],
    'exercise-hack-squat': [],
    'exercise-leg-press': [],
    'exercise-pistol-squat': ['equipment-bodyweight'],
    'exercise-deadlift': ['equipment-barbell'],
    'exercise-sumo-deadlift': ['equipment-barbell'],
    'exercise-romanian-deadlift-barbell': ['equipment-barbell'],
    'exercise-romanian-deadlift-dumbbell': ['equipment-dumbbell'],
    'exercise-good-morning': ['equipment-barbell'],
    'exercise-barbell-hip-thrust': ['equipment-barbell'],
    'exercise-kettlebell-swing': [],
    'exercise-back-extension': ['equipment-bodyweight'],
    'exercise-bench-press': ['equipment-barbell'],
    'exercise-incline-bench-press': ['equipment-barbell'],
    'exercise-decline-bench-press': ['equipment-barbell'],
    'exercise-dumbbell-bench-press': ['equipment-dumbbell'],
    'exercise-incline-dumbbell-bench-press': ['equipment-dumbbell'],
    'exercise-push-up': ['equipment-bodyweight'],
    'exercise-dip': ['equipment-bodyweight'],
    'exercise-machine-chest-press': [],
    'exercise-barbell-row': ['equipment-barbell'],
    'exercise-pendlay-row': ['equipment-barbell'],
    'exercise-dumbbell-row': ['equipment-dumbbell'],
    'exercise-seated-cable-row': [],
    'exercise-chest-supported-row': ['equipment-dumbbell'],
    'exercise-t-bar-row': ['equipment-barbell'],
    'exercise-inverted-row': ['equipment-bodyweight'],
    'exercise-face-pull': [],
    'exercise-overhead-press': ['equipment-barbell'],
    'exercise-dumbbell-shoulder-press': ['equipment-dumbbell'],
    'exercise-seated-dumbbell-shoulder-press': ['equipment-dumbbell'],
    'exercise-landmine-press': ['equipment-barbell'],
    'exercise-arnold-press': ['equipment-dumbbell'],
    'exercise-pullup': ['equipment-pullup-bar'],
    'exercise-chin-up': ['equipment-pullup-bar'],
    'exercise-lat-pulldown': [],
    'exercise-neutral-grip-pulldown': [],
    'exercise-straight-arm-pulldown': [],
    'exercise-walking-lunge': ['equipment-dumbbell'],
    'exercise-reverse-lunge': ['equipment-dumbbell'],
    'exercise-step-up': ['equipment-dumbbell'],
    'exercise-single-leg-rdl': ['equipment-dumbbell'],
    'exercise-lateral-raise': ['equipment-dumbbell'],
    'exercise-cable-lateral-raise': [],
    'exercise-rear-delt-fly': ['equipment-dumbbell'],
    'exercise-front-raise': ['equipment-dumbbell'],
    'exercise-upright-row': ['equipment-barbell'],
    'exercise-barbell-curl': ['equipment-barbell'],
    'exercise-dumbbell-curl': ['equipment-dumbbell'],
    'exercise-hammer-curl': ['equipment-dumbbell'],
    'exercise-preacher-curl': ['equipment-barbell'],
    'exercise-triceps-pressdown': [],
    'exercise-overhead-triceps-extension': ['equipment-dumbbell'],
    'exercise-skullcrusher': ['equipment-barbell'],
    'exercise-cable-pull-through': [],
    'exercise-glute-kickback': [],
    'exercise-nordic-curl': ['equipment-bodyweight'],
    'exercise-standing-calf-raise': ['equipment-bodyweight'],
    'exercise-seated-calf-raise': [],
    'exercise-farmers-carry': ['equipment-dumbbell'],
    'exercise-pallof-press': [],
    'exercise-cable-woodchop': [],
    'exercise-hanging-leg-raise': ['equipment-pullup-bar'],
    'exercise-cable-crunch': [],
    'exercise-ab-wheel-rollout': [],
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
    // New Isometric Holds — Core
    'exercise-rkc-plank': ['equipment-bodyweight'],
    'exercise-long-lever-plank': ['equipment-bodyweight'],
    'exercise-dead-bug-hold': ['equipment-bodyweight'],
    'exercise-copenhagen-plank': ['equipment-bodyweight'],
    // New Isometric Holds — Lower-Body
    'exercise-single-leg-glute-bridge-hold': ['equipment-bodyweight'],
    'exercise-single-leg-calf-raise-hold': ['equipment-bodyweight'],
    'exercise-pistol-squat-hold': ['equipment-bodyweight'],
    'exercise-cossack-squat-hold': ['equipment-bodyweight'],
    // New Isometric Holds — Upper-Body
    'exercise-active-hang': ['equipment-pullup-bar'],
    'exercise-tuck-front-lever-hold': ['equipment-pullup-bar'],
    'exercise-advanced-tuck-front-lever-hold': ['equipment-pullup-bar'],
    'exercise-tuck-back-lever-hold': ['equipment-pullup-bar'],
    'exercise-ring-support-hold': [],
    'exercise-handstand-hold-wall': ['equipment-bodyweight'],
    // Static Stretches
    'exercise-standing-hamstring-stretch': ['equipment-bodyweight'],
    'exercise-seated-forward-fold': ['equipment-bodyweight'],
    'exercise-standing-quad-stretch': ['equipment-bodyweight'],
    'exercise-couch-stretch': ['equipment-bodyweight'],
    'exercise-kneeling-hip-flexor-stretch': ['equipment-bodyweight'],
    'exercise-pigeon-pose': ['equipment-bodyweight'],
    'exercise-seated-piriformis-stretch': ['equipment-bodyweight'],
    'exercise-doorway-chest-stretch': [],
    'exercise-lat-stretch': [],
    'exercise-overhead-triceps-stretch': ['equipment-bodyweight'],
    'exercise-neck-side-stretch': ['equipment-bodyweight'],
    'exercise-standing-calf-stretch': ['equipment-bodyweight'],
    'exercise-soleus-stretch': ['equipment-bodyweight'],
    'exercise-childs-pose': ['equipment-bodyweight'],
    // Mobility Holds
    'exercise-90-90-hip-hold': ['equipment-bodyweight'],
    'exercise-frog-stretch': ['equipment-bodyweight'],
    'exercise-deep-squat-hold': ['equipment-bodyweight'],
    'exercise-thoracic-rotation-hold': ['equipment-bodyweight'],
    'exercise-cat-cow-hold': ['equipment-bodyweight'],
    'exercise-worlds-greatest-stretch-hold': ['equipment-bodyweight'],
    'exercise-seated-butterfly-hold': ['equipment-bodyweight'],
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
    // Cardio library — Phase 4 (running, cycling, rowing, swimming, walking, machine)
    'exercise-sprint-intervals': ['equipment-bodyweight'],
    'exercise-strides': ['equipment-bodyweight'],
    'exercise-trail-run': ['equipment-bodyweight'],
    'exercise-treadmill-run': [],
    'exercise-zone-2-ride': [],
    'exercise-tempo-ride': [],
    'exercise-sweet-spot-intervals': [],
    'exercise-threshold-intervals': [],
    'exercise-vo2-max-intervals': [],
    'exercise-cycling-sprint-intervals': [],
    'exercise-long-ride': [],
    'exercise-recovery-ride': [],
    'exercise-stationary-bike': [],
    'exercise-steady-state-row': [],
    'exercise-rowing-intervals': [],
    'exercise-2k-row-test': [],
    'exercise-long-row': [],
    'exercise-power-strokes': [],
    'exercise-easy-swim': ['equipment-bodyweight'],
    'exercise-swim-intervals': ['equipment-bodyweight'],
    'exercise-swim-sprints': ['equipment-bodyweight'],
    'exercise-long-swim': ['equipment-bodyweight'],
    'exercise-swim-drills': ['equipment-bodyweight'],
    'exercise-swim-kick-set': ['equipment-bodyweight'],
    'exercise-brisk-walk': ['equipment-bodyweight'],
    'exercise-incline-walk': ['equipment-bodyweight'],
    'exercise-rucking': [],
    'exercise-hike': ['equipment-bodyweight'],
    'exercise-elliptical-steady': [],
    'exercise-elliptical-intervals': [],
    'exercise-stair-climber': [],
    'exercise-stair-intervals': [],
    'exercise-ski-erg': [],
    'exercise-assault-bike': [],
    'exercise-assault-bike-sprints': [],
    'exercise-jump-rope-steady': [],
    'exercise-jump-rope-intervals': [],
    'exercise-rowing-sprints': [],
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
    'exercise-sprint-intervals': ['time', 'distance', 'rounds'],
    'exercise-strides': ['time', 'distance'],
    'exercise-trail-run': ['time', 'distance'],
    'exercise-treadmill-run': ['time', 'distance'],
    // Cycling exercises
    'exercise-zone-2-ride': ['time', 'distance'],
    'exercise-tempo-ride': ['time', 'distance'],
    'exercise-sweet-spot-intervals': ['time', 'distance', 'rounds'],
    'exercise-threshold-intervals': ['time', 'distance', 'rounds'],
    'exercise-vo2-max-intervals': ['time', 'distance', 'rounds'],
    'exercise-cycling-sprint-intervals': ['time', 'distance', 'rounds'],
    'exercise-long-ride': ['time', 'distance'],
    'exercise-recovery-ride': ['time', 'distance'],
    'exercise-stationary-bike': ['time', 'distance'],
    // Rowing exercises
    'exercise-steady-state-row': ['time', 'distance'],
    'exercise-rowing-intervals': ['time', 'distance', 'rounds'],
    'exercise-2k-row-test': ['time', 'distance'],
    'exercise-long-row': ['time', 'distance'],
    'exercise-power-strokes': ['time', 'distance'],
    // Swimming exercises
    'exercise-easy-swim': ['time', 'distance'],
    'exercise-swim-intervals': ['time', 'distance', 'rounds'],
    'exercise-swim-sprints': ['time', 'distance', 'rounds'],
    'exercise-long-swim': ['time', 'distance'],
    'exercise-swim-drills': ['time', 'distance'],
    'exercise-swim-kick-set': ['time', 'distance'],
    // Walking & Hiking exercises
    'exercise-brisk-walk': ['time', 'distance'],
    'exercise-incline-walk': ['time', 'distance'],
    'exercise-rucking': ['time', 'distance'],
    'exercise-hike': ['time', 'distance'],
    // Machine Cardio exercises
    'exercise-elliptical-steady': ['time', 'distance'],
    'exercise-elliptical-intervals': ['time', 'distance', 'rounds'],
    'exercise-stair-climber': ['time'],
    'exercise-stair-intervals': ['time', 'rounds'],
    'exercise-ski-erg': ['time', 'distance'],
    'exercise-assault-bike': ['time', 'distance'],
    'exercise-assault-bike-sprints': ['time', 'distance', 'rounds'],
    'exercise-jump-rope-steady': ['time'],
    'exercise-jump-rope-intervals': ['time', 'rounds'],
    'exercise-rowing-sprints': ['time', 'distance'],

    // Resistance / Lifting exercises - reps/sets/load primary, also support time for cardio-context
    'exercise-barbell-squat': ['reps', 'sets', 'load', 'time'],
    'exercise-front-squat': ['reps', 'sets', 'load', 'time'],
    'exercise-goblet-squat': ['reps', 'sets', 'load', 'time'],
    'exercise-dumbbell-split-squat': ['reps', 'sets', 'load', 'time'],
    'exercise-bulgarian-split-squat': ['reps', 'sets', 'load', 'time'],
    'exercise-hack-squat': ['reps', 'sets', 'load', 'time'],
    'exercise-leg-press': ['reps', 'sets', 'load', 'time'],
    'exercise-pistol-squat': ['reps', 'sets', 'time'],
    'exercise-deadlift': ['reps', 'sets', 'load', 'time'],
    'exercise-sumo-deadlift': ['reps', 'sets', 'load', 'time'],
    'exercise-romanian-deadlift-barbell': ['reps', 'sets', 'load', 'time'],
    'exercise-romanian-deadlift-dumbbell': ['reps', 'sets', 'load', 'time'],
    'exercise-good-morning': ['reps', 'sets', 'load', 'time'],
    'exercise-barbell-hip-thrust': ['reps', 'sets', 'load', 'time'],
    'exercise-kettlebell-swing': ['reps', 'sets', 'load', 'time'],
    'exercise-back-extension': ['reps', 'sets', 'load', 'time'],
    'exercise-bench-press': ['reps', 'sets', 'load', 'time'],
    'exercise-incline-bench-press': ['reps', 'sets', 'load', 'time'],
    'exercise-decline-bench-press': ['reps', 'sets', 'load', 'time'],
    'exercise-dumbbell-bench-press': ['reps', 'sets', 'load', 'time'],
    'exercise-incline-dumbbell-bench-press': ['reps', 'sets', 'load', 'time'],
    'exercise-push-up': ['reps', 'sets', 'time'],
    'exercise-dip': ['reps', 'sets', 'load', 'time'],
    'exercise-machine-chest-press': ['reps', 'sets', 'load', 'time'],
    'exercise-barbell-row': ['reps', 'sets', 'load', 'time'],
    'exercise-pendlay-row': ['reps', 'sets', 'load', 'time'],
    'exercise-dumbbell-row': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-seated-cable-row': ['reps', 'sets', 'load', 'time'],
    'exercise-chest-supported-row': ['reps', 'sets', 'load', 'time'],
    'exercise-t-bar-row': ['reps', 'sets', 'load', 'time'],
    'exercise-inverted-row': ['reps', 'sets', 'time'],
    'exercise-face-pull': ['reps', 'sets', 'load', 'time'],
    'exercise-overhead-press': ['reps', 'sets', 'load', 'time'],
    'exercise-dumbbell-shoulder-press': [
      'reps',
      'sets',
      'load',
      'bilateral',
      'time',
    ],
    'exercise-seated-dumbbell-shoulder-press': [
      'reps',
      'sets',
      'load',
      'bilateral',
      'time',
    ],
    'exercise-landmine-press': ['reps', 'sets', 'load', 'time'],
    'exercise-arnold-press': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-pullup': ['reps', 'sets', 'load', 'time'],
    'exercise-chin-up': ['reps', 'sets', 'load', 'time'],
    'exercise-lat-pulldown': ['reps', 'sets', 'load', 'time'],
    'exercise-neutral-grip-pulldown': ['reps', 'sets', 'load', 'time'],
    'exercise-straight-arm-pulldown': ['reps', 'sets', 'load', 'time'],
    'exercise-walking-lunge': ['reps', 'sets', 'load', 'time'],
    'exercise-reverse-lunge': ['reps', 'sets', 'load', 'time'],
    'exercise-step-up': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-single-leg-rdl': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-lateral-raise': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-cable-lateral-raise': [
      'reps',
      'sets',
      'load',
      'bilateral',
      'time',
    ],
    'exercise-rear-delt-fly': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-front-raise': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-upright-row': ['reps', 'sets', 'load', 'time'],
    'exercise-barbell-curl': ['reps', 'sets', 'load', 'time'],
    'exercise-dumbbell-curl': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-hammer-curl': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-preacher-curl': ['reps', 'sets', 'load', 'bilateral', 'time'],
    'exercise-triceps-pressdown': ['reps', 'sets', 'load', 'time'],
    'exercise-overhead-triceps-extension': ['reps', 'sets', 'load', 'time'],
    'exercise-skullcrusher': ['reps', 'sets', 'load', 'time'],
    'exercise-cable-pull-through': ['reps', 'sets', 'load', 'time'],
    'exercise-glute-kickback': ['reps', 'sets', 'load', 'time'],
    'exercise-nordic-curl': ['reps', 'sets', 'time'],
    'exercise-standing-calf-raise': ['reps', 'sets', 'load', 'time'],
    'exercise-seated-calf-raise': ['reps', 'sets', 'load', 'time'],
    'exercise-farmers-carry': ['time', 'distance', 'load'],
    'exercise-pallof-press': ['reps', 'sets', 'load', 'time'],
    'exercise-cable-woodchop': ['reps', 'sets', 'load', 'time'],
    'exercise-hanging-leg-raise': ['reps', 'sets', 'time'],
    'exercise-cable-crunch': ['reps', 'sets', 'load', 'time'],
    'exercise-ab-wheel-rollout': ['reps', 'sets', 'time'],

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
    // New Isometric Holds — Core
    'exercise-rkc-plank': ['hold', 'time', 'sets'],
    'exercise-long-lever-plank': ['hold', 'time', 'sets'],
    'exercise-dead-bug-hold': ['hold', 'time', 'sets'],
    'exercise-copenhagen-plank': ['hold', 'time', 'sets'],
    // New Isometric Holds — Lower-Body
    'exercise-single-leg-glute-bridge-hold': ['hold', 'time', 'sets'],
    'exercise-single-leg-calf-raise-hold': ['hold', 'time', 'sets'],
    'exercise-pistol-squat-hold': ['hold', 'time', 'sets'],
    'exercise-cossack-squat-hold': ['hold', 'time', 'sets'],
    // New Isometric Holds — Upper-Body
    'exercise-active-hang': ['hold', 'time', 'sets'],
    'exercise-tuck-front-lever-hold': ['hold', 'time', 'sets'],
    'exercise-advanced-tuck-front-lever-hold': ['hold', 'time', 'sets'],
    'exercise-tuck-back-lever-hold': ['hold', 'time', 'sets'],
    'exercise-ring-support-hold': ['hold', 'time', 'sets'],
    'exercise-handstand-hold-wall': ['hold', 'time', 'sets'],
    // Static Stretches
    'exercise-standing-hamstring-stretch': ['hold', 'time', 'sets'],
    'exercise-seated-forward-fold': ['hold', 'time', 'sets'],
    'exercise-standing-quad-stretch': ['hold', 'time', 'sets'],
    'exercise-couch-stretch': ['hold', 'time', 'sets'],
    'exercise-kneeling-hip-flexor-stretch': ['hold', 'time', 'sets'],
    'exercise-pigeon-pose': ['hold', 'time', 'sets'],
    'exercise-seated-piriformis-stretch': ['hold', 'time', 'sets'],
    'exercise-doorway-chest-stretch': ['hold', 'time', 'sets'],
    'exercise-lat-stretch': ['hold', 'time', 'sets'],
    'exercise-overhead-triceps-stretch': ['hold', 'time', 'sets'],
    'exercise-neck-side-stretch': ['hold', 'time', 'sets'],
    'exercise-standing-calf-stretch': ['hold', 'time', 'sets'],
    'exercise-soleus-stretch': ['hold', 'time', 'sets'],
    'exercise-childs-pose': ['hold', 'time', 'sets'],
    // Mobility Holds
    'exercise-90-90-hip-hold': ['hold', 'time', 'sets'],
    'exercise-frog-stretch': ['hold', 'time', 'sets'],
    'exercise-deep-squat-hold': ['hold', 'time', 'sets'],
    'exercise-thoracic-rotation-hold': ['hold', 'time', 'sets'],
    'exercise-cat-cow-hold': ['hold', 'time', 'sets'],
    'exercise-worlds-greatest-stretch-hold': ['hold', 'time', 'sets'],
    'exercise-seated-butterfly-hold': ['hold', 'time', 'sets'],

    // Sports exercises - time and rounds based
    'exercise-tennis-match': ['time', 'rounds'],
    'exercise-tennis-drill': ['time', 'rounds'],
    'exercise-tennis-serve-practice': ['time', 'rounds'],
    'exercise-tennis-return-practice': ['time', 'rounds'],
    'exercise-volleyball-match': ['time', 'rounds'],
    'exercise-volleyball-drill': ['time', 'rounds'],
    'exercise-badminton-match': ['time', 'rounds'],
    'exercise-badminton-drill': ['time', 'rounds'],
    'exercise-table-tennis-match': ['time', 'rounds'],
    'exercise-table-tennis-drill': ['time', 'rounds'],
    'exercise-squash-match': ['time', 'rounds'],
    'exercise-squash-drill': ['time', 'rounds'],
    'exercise-padel-match': ['time', 'rounds'],
    'exercise-padel-drill': ['time', 'rounds'],
    'exercise-cricket-match': ['time', 'rounds'],
    'exercise-cricket-practice': ['time', 'rounds'],
    'exercise-ice-hockey-match': ['time', 'rounds'],
    'exercise-ice-hockey-practice': ['time', 'rounds'],
    'exercise-baseball-game': ['time', 'rounds'],
    'exercise-baseball-practice': ['time', 'rounds'],
    'exercise-american-football-game': ['time', 'rounds'],
    'exercise-american-football-practice': ['time', 'rounds'],
    'exercise-rugby-match': ['time', 'rounds'],
    'exercise-rugby-training': ['time', 'rounds'],
    'exercise-lacrosse-game': ['time', 'rounds'],
    'exercise-lacrosse-practice': ['time', 'rounds'],
    // BJJ exercises
    'exercise-bjj-class': ['time', 'rounds'],
    'exercise-bjj-drilling': ['time', 'rounds'],
    'exercise-bjj-rolling': ['time', 'rounds'],
    'exercise-bjj-positional-sparring': ['time', 'rounds'],
    'exercise-bjj-guard-retention-practice': ['time', 'rounds'],
    'exercise-bjj-guard-passing-practice': ['time', 'rounds'],
    'exercise-bjj-submission-practice': ['time', 'rounds'],
    // Muay Thai exercises
    'exercise-muay-thai-class': ['time', 'rounds'],
    'exercise-muay-thai-pad-work': ['time', 'rounds'],
    'exercise-muay-thai-bag-work': ['time', 'rounds'],
    'exercise-muay-thai-clinch-practice': ['time', 'rounds'],
    'exercise-muay-thai-sparring': ['time', 'rounds'],
    // MMA exercises
    'exercise-mma-class': ['time', 'rounds'],
    'exercise-mma-pad-work': ['time', 'rounds'],
    'exercise-mma-sparring': ['time', 'rounds'],
    'exercise-mma-situational-sparring': ['time', 'rounds'],
    // Karate exercises
    'exercise-karate-class': ['time', 'rounds'],
    'exercise-karate-kumite': ['time', 'rounds'],
    'exercise-karate-kata-practice': ['time', 'rounds'],
    // Judo exercises
    'exercise-judo-class': ['time', 'rounds'],
    'exercise-judo-randori': ['time', 'rounds'],
    'exercise-judo-uchi-komi': ['time', 'rounds'],
    'exercise-judo-nage-komi': ['time', 'rounds'],
    // Soccer exercises
    'exercise-soccer-match': ['time', 'rounds'],
    'exercise-soccer-training': ['time', 'rounds'],
    'exercise-soccer-shooting-practice': ['time', 'rounds'],
    'exercise-soccer-passing-practice': ['time', 'rounds'],
    // Basketball exercises
    'exercise-basketball-game': ['time', 'rounds'],
    'exercise-basketball-practice': ['time', 'rounds'],
    'exercise-basketball-shooting-practice': ['time', 'rounds'],
    'exercise-basketball-free-throw-practice': ['time', 'rounds'],
    'exercise-basketball-ball-handling-practice': ['time', 'rounds'],
    // Golf exercises
    'exercise-golf-round': ['time', 'rounds'],
    'exercise-golf-range-practice': ['time', 'rounds'],
    'exercise-golf-short-game-practice': ['time', 'rounds'],
    'exercise-golf-putting-practice': ['time', 'rounds'],
    // Climbing exercises
    'exercise-climbing-session': ['time', 'rounds'],
    'exercise-climbing-projecting': ['time', 'rounds'],
    'exercise-climbing-volume': ['time', 'rounds'],
    'exercise-climbing-hangboard-session': ['time', 'rounds'],
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
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Easy Run template segments
    TemplateSegment(
      id: 'tseg-run-1',
      templateId: 'template-easy-run',
      orderIndex: 0,
      segmentType: 'timed_activity',
      name: 'Main Run',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing template segments
    TemplateSegment(
      id: 'tseg-boxing-1',
      templateId: 'template-boxing-rounds',
      orderIndex: 0,
      segmentType: 'round_based',
      name: 'Heavy Bag Work',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Mobility template segments
    TemplateSegment(
      id: 'tseg-mobility-1',
      templateId: 'template-mobility',
      orderIndex: 0,
      segmentType: 'drill_skill',
      name: 'Stretching Routine',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
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
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Easy Run: 30 minutes
    TemplateTarget(
      id: 'ttar-run-duration',
      templateEffortId: 'teff-run-main',
      metricId: 'metric-duration',
      setIndex: 0,
      targetInt: 1800, // 30 minutes in seconds
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    // Boxing: 5 rounds x 3 minutes
    TemplateTarget(
      id: 'ttar-boxing-rounds',
      templateEffortId: 'teff-boxing-bag',
      metricId: 'metric-rounds',
      setIndex: 0,
      targetInt: 5,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    TemplateTarget(
      id: 'ttar-boxing-duration',
      templateEffortId: 'teff-boxing-bag',
      metricId: 'metric-round-duration',
      setIndex: 0,
      targetInt: 180, // 3 minutes in seconds
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
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
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  // Calendar features intentionally start empty.
  static final List<PlannedSession> samplePlannedSessions = [];

  // Calendar period demo data was removed; user-created periods only.
  static final List<TrainingPeriod> sampleTrainingPeriods = [];

  // ─── Standard session with blocks (development / testing fixture) ─────────
  // Provides a completed non-rolling session with two named blocks and one
  // standalone exercise for testing the standard session list and summary UI.

  static final List<TrainingSession> sampleTrainingSessions = [
    TrainingSession(
      id: 'seed-session-standard',
      ownerUserId: 'local-user',
      startedAtMs: 1744012800000, // 2025-04-07 08:00 UTC
      endedAtMs: 1744016400000, // 2025-04-07 09:00 UTC
      title: 'Strength Day',
      modality: 'resistance_lifting',
      intent: 'open',
      sessionFeeling: 4,
      isRolling: false,
      createdAtMs: 1744012800000,
      updatedAtMs: 1744016400000,
    ),
  ];

  static final List<SessionSegment> sampleSessionSegments = [
    SessionSegment(
      id: 'seed-segment-standard',
      sessionId: 'seed-session-standard',
      orderIndex: 0,
      segmentType: 'mixed',
      name: 'Main',
      createdAtMs: 1744012800000,
      updatedAtMs: 1744012800000,
    ),
  ];

  static final List<SessionBlock> sampleSessionBlocks = [
    SessionBlock(
      id: 'seed-block-warmup',
      sessionId: 'seed-session-standard',
      name: 'Warm-Up',
      orderIndex: 0,
      createdAtMs: 1744012860000,
      updatedAtMs: 1744012860000,
    ),
    SessionBlock(
      id: 'seed-block-main',
      sessionId: 'seed-session-standard',
      name: 'Main Work',
      orderIndex: 1,
      createdAtMs: 1744012920000,
      updatedAtMs: 1744012920000,
    ),
  ];

  static final List<SegmentEffort> sampleSegmentEfforts = [
    // Warm-Up block: easy run + barbell squat warm-up
    SegmentEffort(
      id: 'seed-effort-warmup-run',
      segmentId: 'seed-segment-standard',
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: 'exercise-easy-run',
      blockId: 'seed-block-warmup',
      createdAtMs: 1744012860000,
      updatedAtMs: 1744012860000,
    ),
    SegmentEffort(
      id: 'seed-effort-warmup-squat',
      segmentId: 'seed-segment-standard',
      orderIndex: 1,
      effortKind: 'set',
      exerciseId: 'exercise-barbell-squat',
      blockId: 'seed-block-warmup',
      createdAtMs: 1744012900000,
      updatedAtMs: 1744012900000,
    ),
    // Main Work block: bench press + deadlift
    SegmentEffort(
      id: 'seed-effort-main-bench',
      segmentId: 'seed-segment-standard',
      orderIndex: 2,
      effortKind: 'set',
      exerciseId: 'exercise-bench-press',
      blockId: 'seed-block-main',
      createdAtMs: 1744012920000,
      updatedAtMs: 1744012920000,
    ),
    SegmentEffort(
      id: 'seed-effort-main-deadlift',
      segmentId: 'seed-segment-standard',
      orderIndex: 3,
      effortKind: 'set',
      exerciseId: 'exercise-deadlift',
      blockId: 'seed-block-main',
      createdAtMs: 1744012980000,
      updatedAtMs: 1744012980000,
    ),
    // Standalone: pull-up (no block)
    SegmentEffort(
      id: 'seed-effort-standalone-pullup',
      segmentId: 'seed-segment-standard',
      orderIndex: 4,
      effortKind: 'set',
      exerciseId: 'exercise-pullup',
      blockId: null,
      createdAtMs: 1744015200000,
      updatedAtMs: 1744015200000,
    ),
  ];

  /// Now-relative seed nutrition log used by the Stats screen's
  /// Nutrition Trend card. Each row is a frozen [ConsumedFood]
  /// snapshot that reuses the bundled catalog's macro values so the
  /// totals line up with what the user would see if they logged
  /// these foods from the library.
  ///
  /// Spans the last 45 days. Several days are intentionally
  /// skipped (no rows) so QA can verify the "skip empty days"
  /// behavior of the trend (S-001 / S-005). Macros and calories
  /// vary across days so the three macro lines and the calorie
  /// line show visible movement in both the Calories and Macros
  /// views. The chart now scrolls through the full history, so
  /// the seed needs enough logged days to engage the horizontal
  /// scroll on a phone-width card (≥ ~8 days at 48 px per point).
  static List<ConsumedFood> sampleConsumedFoods() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int dayMs(int daysAgo) =>
        today.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch;

    // Frozen snapshots — every field is populated so the rows are
    // self-contained and survive food/target edits later.
    // Macros match the bundled catalog entries (per 100 g or per
    // serving) so the displayed totals are realistic.
    final rows = <ConsumedFood>[];

    // Helper to build a frozen snapshot at a given day offset.
    ConsumedFood row({
      required String id,
      required int daysAgo,
      required String name,
      required FoodUnitType unitType,
      required double referenceAmount,
      required String referenceLabel,
      required int protein,
      required int carbs,
      required int? fiber,
      required int fat,
      required double amountConsumed,
      String? sourceFoodId,
      String? groupIdSnapshot,
      String? groupNameSnapshot,
    }) {
      final loggedAtMs = dayMs(daysAgo) + (12 * 60 * 60 * 1000); // 12:00 local
      return ConsumedFood(
        id: id,
        loggedAtMs: loggedAtMs,
        dateMs: dayMs(daysAgo),
        sourceFoodId: sourceFoodId,
        name: name,
        unitType: unitType,
        referenceAmount: referenceAmount,
        referenceLabel: referenceLabel,
        protein: protein,
        carbs: carbs,
        fiber: fiber,
        fat: fat,
        sodium: null,
        amountConsumed: amountConsumed,
        groupIdSnapshot: groupIdSnapshot,
        groupNameSnapshot: groupNameSnapshot,
        // Frozen daily targets (typical intermediate-user values).
        targetCalories: 2400,
        targetProtein: 160,
        targetCarbs: 280,
        targetFat: 80,
        createdAtMs: loggedAtMs,
        updatedAtMs: loggedAtMs,
      );
    }

    // Day 0 (today): 150 g chicken_breast (catalog: 31P/0C/4F 100 g)
    rows.add(
      row(
        id: 'seed-consumed-d0-chicken',
        daysAgo: 0,
        name: 'Chicken breast, skinless',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 31,
        carbs: 0,
        fiber: 0,
        fat: 4,
        amountConsumed: 150,
        sourceFoodId: 'chicken_breast',
        groupIdSnapshot: 'food-group-proteins',
        groupNameSnapshot: 'Proteins',
      ),
    );
    // Day 0: 100 g white_rice (catalog: 3P/28C/0F 100 g)
    rows.add(
      row(
        id: 'seed-consumed-d0-rice',
        daysAgo: 0,
        name: 'White rice, cooked',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 3,
        carbs: 28,
        fiber: 0,
        fat: 0,
        amountConsumed: 100,
        sourceFoodId: 'white_rice',
        groupIdSnapshot: 'food-group-grains-starches',
        groupNameSnapshot: 'Grains & Starches',
      ),
    );
    // Day 0: 1 tbsp olive_oil (catalog: 0P/0C/14F tbsp)
    rows.add(
      row(
        id: 'seed-consumed-d0-oil',
        daysAgo: 0,
        name: 'Olive oil',
        unitType: FoodUnitType.count,
        referenceAmount: 1,
        referenceLabel: 'tbsp',
        protein: 0,
        carbs: 0,
        fiber: 0,
        fat: 14,
        amountConsumed: 1,
        sourceFoodId: 'olive_oil',
        groupIdSnapshot: 'food-group-nuts-seeds-fats',
        groupNameSnapshot: 'Nuts, Seeds & Fats',
      ),
    );

    // Day 1: lighter day — 2 large eggs (catalog: 6P/1C/5F egg)
    rows.add(
      row(
        id: 'seed-consumed-d1-eggs',
        daysAgo: 1,
        name: 'Egg, large',
        unitType: FoodUnitType.count,
        referenceAmount: 1,
        referenceLabel: 'egg',
        protein: 6,
        carbs: 1,
        fiber: 0,
        fat: 5,
        amountConsumed: 2,
        sourceFoodId: 'egg',
        groupIdSnapshot: 'food-group-proteins',
        groupNameSnapshot: 'Proteins',
      ),
    );
    // Day 1: 1 medium banana (catalog: 1P/27C/0F)
    rows.add(
      row(
        id: 'seed-consumed-d1-banana',
        daysAgo: 1,
        name: 'Banana, medium',
        unitType: FoodUnitType.count,
        referenceAmount: 1,
        referenceLabel: 'medium',
        protein: 1,
        carbs: 27,
        fiber: 3,
        fat: 0,
        amountConsumed: 1,
        sourceFoodId: 'banana',
        groupIdSnapshot: 'food-group-fruits',
        groupNameSnapshot: 'Fruits',
      ),
    );

    // Day 2: SKIPPED (no rows) — verifies the skip-empty behavior.

    // Day 3: 200 g greek_yogurt (catalog: 10P/4C/0F 100 g)
    rows.add(
      row(
        id: 'seed-consumed-d3-yogurt',
        daysAgo: 3,
        name: 'Greek yogurt, plain nonfat',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 10,
        carbs: 4,
        fiber: 0,
        fat: 0,
        amountConsumed: 200,
        sourceFoodId: 'greek_yogurt',
        groupIdSnapshot: 'food-group-dairy',
        groupNameSnapshot: 'Dairy',
      ),
    );
    // Day 3: 2 tbsp peanut_butter (catalog: 4P/3C/8F tbsp)
    rows.add(
      row(
        id: 'seed-consumed-d3-pb',
        daysAgo: 3,
        name: 'Peanut butter',
        unitType: FoodUnitType.count,
        referenceAmount: 1,
        referenceLabel: 'tbsp',
        protein: 4,
        carbs: 3,
        fiber: 2,
        fat: 8,
        amountConsumed: 2,
        sourceFoodId: 'peanut_butter',
        groupIdSnapshot: 'food-group-nuts-seeds-fats',
        groupNameSnapshot: 'Nuts, Seeds & Fats',
      ),
    );

    // Day 4: 120 g oats (catalog: 13P/67C/7F 100 g) — high-carb day
    rows.add(
      row(
        id: 'seed-consumed-d4-oats',
        daysAgo: 4,
        name: 'Oats, dry',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 13,
        carbs: 67,
        fiber: 10,
        fat: 7,
        amountConsumed: 120,
        sourceFoodId: 'oats',
        groupIdSnapshot: 'food-group-grains-starches',
        groupNameSnapshot: 'Grains & Starches',
      ),
    );

    // Day 5: 150 g salmon (catalog: 25P/0C/13F 100 g) — high-fat day
    rows.add(
      row(
        id: 'seed-consumed-d5-salmon',
        daysAgo: 5,
        name: 'Salmon, cooked',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 25,
        carbs: 0,
        fiber: 0,
        fat: 13,
        amountConsumed: 150,
        sourceFoodId: 'salmon',
        groupIdSnapshot: 'food-group-proteins',
        groupNameSnapshot: 'Proteins',
      ),
    );
    // Day 5: 100 g brown_rice (catalog: 3P/23C/1F 100 g)
    rows.add(
      row(
        id: 'seed-consumed-d5-rice',
        daysAgo: 5,
        name: 'Brown rice, cooked',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 3,
        carbs: 23,
        fiber: 2,
        fat: 1,
        amountConsumed: 100,
        sourceFoodId: 'brown_rice',
        groupIdSnapshot: 'food-group-grains-starches',
        groupNameSnapshot: 'Grains & Starches',
      ),
    );

    // Day 6: SKIPPED (no rows).

    // Day 7: 200 g chicken_breast
    rows.add(
      row(
        id: 'seed-consumed-d7-chicken',
        daysAgo: 7,
        name: 'Chicken breast, skinless',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 31,
        carbs: 0,
        fiber: 0,
        fat: 4,
        amountConsumed: 200,
        sourceFoodId: 'chicken_breast',
        groupIdSnapshot: 'food-group-proteins',
        groupNameSnapshot: 'Proteins',
      ),
    );

    // Day 8: 100 g pasta (catalog: 5P/25C/1F 100 g)
    rows.add(
      row(
        id: 'seed-consumed-d8-pasta',
        daysAgo: 8,
        name: 'Pasta, cooked',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 5,
        carbs: 25,
        fiber: 2,
        fat: 1,
        amountConsumed: 100,
        sourceFoodId: 'pasta',
        groupIdSnapshot: 'food-group-grains-starches',
        groupNameSnapshot: 'Grains & Starches',
      ),
    );
    // Day 8: 100 g ground_beef (catalog: 26P/0C/15F 100 g)
    rows.add(
      row(
        id: 'seed-consumed-d8-beef',
        daysAgo: 8,
        name: 'Ground beef, 85% lean, cooked',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: '100 g',
        protein: 26,
        carbs: 0,
        fiber: 0,
        fat: 15,
        amountConsumed: 100,
        sourceFoodId: 'ground_beef',
        groupIdSnapshot: 'food-group-proteins',
        groupNameSnapshot: 'Proteins',
      ),
    );

    // Day 9: SKIPPED (no rows).

    // ── Older history (days 10..45) ────────────────────────────────────────
    // The chart now scrolls through full history, so we seed a
    // handful of older days to engage the horizontal scroll on a
    // phone-width card. Every other day is logged; some days
    // intentionally empty to exercise the skip-empty behavior.
    // Macros vary day-to-day so the three macro lines and the
    // calorie line show visible movement across history.
    final olderDayMeals = <int, List<({String name, String sourceFoodId, String groupId, String groupName, int protein, int carbs, int? fiber, int fat, double amountConsumed, double referenceAmount, String referenceLabel, FoodUnitType unitType})>>{
      // 10: 100 g ground_beef + 1 tbsp olive oil (high-fat day)
      10: [
        (
          name: 'Ground beef, 85% lean, cooked',
          sourceFoodId: 'ground_beef',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 26, carbs: 0, fiber: 0, fat: 15,
          amountConsumed: 100, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
        (
          name: 'Olive oil',
          sourceFoodId: 'olive_oil',
          groupId: 'food-group-nuts-seeds-fats',
          groupName: 'Nuts, Seeds & Fats',
          protein: 0, carbs: 0, fiber: 0, fat: 14,
          amountConsumed: 1, referenceAmount: 1,
          referenceLabel: 'tbsp', unitType: FoodUnitType.count,
        ),
      ],
      // 12: 150 g chicken + 100 g white_rice
      12: [
        (
          name: 'Chicken breast, skinless',
          sourceFoodId: 'chicken_breast',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 31, carbs: 0, fiber: 0, fat: 4,
          amountConsumed: 150, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
        (
          name: 'White rice, cooked',
          sourceFoodId: 'white_rice',
          groupId: 'food-group-grains-starches',
          groupName: 'Grains & Starches',
          protein: 3, carbs: 28, fiber: 0, fat: 0,
          amountConsumed: 100, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 14: 100 g oats
      14: [
        (
          name: 'Oats, dry',
          sourceFoodId: 'oats',
          groupId: 'food-group-grains-starches',
          groupName: 'Grains & Starches',
          protein: 13, carbs: 67, fiber: 10, fat: 7,
          amountConsumed: 100, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 16: 200 g greek_yogurt
      16: [
        (
          name: 'Greek yogurt, plain nonfat',
          sourceFoodId: 'greek_yogurt',
          groupId: 'food-group-dairy',
          groupName: 'Dairy',
          protein: 10, carbs: 4, fiber: 0, fat: 0,
          amountConsumed: 200, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 18: 200 g salmon + 100 g brown_rice
      18: [
        (
          name: 'Salmon, cooked',
          sourceFoodId: 'salmon',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 25, carbs: 0, fiber: 0, fat: 13,
          amountConsumed: 200, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
        (
          name: 'Brown rice, cooked',
          sourceFoodId: 'brown_rice',
          groupId: 'food-group-grains-starches',
          groupName: 'Grains & Starches',
          protein: 3, carbs: 23, fiber: 2, fat: 1,
          amountConsumed: 100, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 20: 3 eggs + 1 banana
      20: [
        (
          name: 'Egg, large',
          sourceFoodId: 'egg',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 6, carbs: 1, fiber: 0, fat: 5,
          amountConsumed: 3, referenceAmount: 1,
          referenceLabel: 'egg', unitType: FoodUnitType.count,
        ),
        (
          name: 'Banana, medium',
          sourceFoodId: 'banana',
          groupId: 'food-group-fruits',
          groupName: 'Fruits',
          protein: 1, carbs: 27, fiber: 3, fat: 0,
          amountConsumed: 1, referenceAmount: 1,
          referenceLabel: 'medium', unitType: FoodUnitType.count,
        ),
      ],
      // 22: 100 g ground_beef + 1 tbsp olive oil
      22: [
        (
          name: 'Ground beef, 85% lean, cooked',
          sourceFoodId: 'ground_beef',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 26, carbs: 0, fiber: 0, fat: 15,
          amountConsumed: 100, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
        (
          name: 'Olive oil',
          sourceFoodId: 'olive_oil',
          groupId: 'food-group-nuts-seeds-fats',
          groupName: 'Nuts, Seeds & Fats',
          protein: 0, carbs: 0, fiber: 0, fat: 14,
          amountConsumed: 1, referenceAmount: 1,
          referenceLabel: 'tbsp', unitType: FoodUnitType.count,
        ),
      ],
      // 24: 100 g pasta
      24: [
        (
          name: 'Pasta, cooked',
          sourceFoodId: 'pasta',
          groupId: 'food-group-grains-starches',
          groupName: 'Grains & Starches',
          protein: 5, carbs: 25, fiber: 2, fat: 1,
          amountConsumed: 100, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 26: 200 g chicken_breast
      26: [
        (
          name: 'Chicken breast, skinless',
          sourceFoodId: 'chicken_breast',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 31, carbs: 0, fiber: 0, fat: 4,
          amountConsumed: 200, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 28: 2 tbsp peanut butter
      28: [
        (
          name: 'Peanut butter',
          sourceFoodId: 'peanut_butter',
          groupId: 'food-group-nuts-seeds-fats',
          groupName: 'Nuts, Seeds & Fats',
          protein: 4, carbs: 3, fiber: 2, fat: 8,
          amountConsumed: 2, referenceAmount: 1,
          referenceLabel: 'tbsp', unitType: FoodUnitType.count,
        ),
      ],
      // 30: 120 g oats + 1 banana
      30: [
        (
          name: 'Oats, dry',
          sourceFoodId: 'oats',
          groupId: 'food-group-grains-starches',
          groupName: 'Grains & Starches',
          protein: 13, carbs: 67, fiber: 10, fat: 7,
          amountConsumed: 120, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
        (
          name: 'Banana, medium',
          sourceFoodId: 'banana',
          groupId: 'food-group-fruits',
          groupName: 'Fruits',
          protein: 1, carbs: 27, fiber: 3, fat: 0,
          amountConsumed: 1, referenceAmount: 1,
          referenceLabel: 'medium', unitType: FoodUnitType.count,
        ),
      ],
      // 33: 100 g white_rice + 150 g chicken
      33: [
        (
          name: 'White rice, cooked',
          sourceFoodId: 'white_rice',
          groupId: 'food-group-grains-starches',
          groupName: 'Grains & Starches',
          protein: 3, carbs: 28, fiber: 0, fat: 0,
          amountConsumed: 100, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
        (
          name: 'Chicken breast, skinless',
          sourceFoodId: 'chicken_breast',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 31, carbs: 0, fiber: 0, fat: 4,
          amountConsumed: 150, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 36: 2 eggs + 1 tbsp olive oil
      36: [
        (
          name: 'Egg, large',
          sourceFoodId: 'egg',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 6, carbs: 1, fiber: 0, fat: 5,
          amountConsumed: 2, referenceAmount: 1,
          referenceLabel: 'egg', unitType: FoodUnitType.count,
        ),
        (
          name: 'Olive oil',
          sourceFoodId: 'olive_oil',
          groupId: 'food-group-nuts-seeds-fats',
          groupName: 'Nuts, Seeds & Fats',
          protein: 0, carbs: 0, fiber: 0, fat: 14,
          amountConsumed: 1, referenceAmount: 1,
          referenceLabel: 'tbsp', unitType: FoodUnitType.count,
        ),
      ],
      // 40: 200 g greek_yogurt
      40: [
        (
          name: 'Greek yogurt, plain nonfat',
          sourceFoodId: 'greek_yogurt',
          groupId: 'food-group-dairy',
          groupName: 'Dairy',
          protein: 10, carbs: 4, fiber: 0, fat: 0,
          amountConsumed: 200, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
      // 43: 200 g salmon
      43: [
        (
          name: 'Salmon, cooked',
          sourceFoodId: 'salmon',
          groupId: 'food-group-proteins',
          groupName: 'Proteins',
          protein: 25, carbs: 0, fiber: 0, fat: 13,
          amountConsumed: 200, referenceAmount: 100,
          referenceLabel: '100 g', unitType: FoodUnitType.grams,
        ),
      ],
    };

    for (final entry in olderDayMeals.entries) {
      final daysAgo = entry.key;
      for (var i = 0; i < entry.value.length; i++) {
        final m = entry.value[i];
        rows.add(
          row(
            id: 'seed-consumed-d$daysAgo-${m.sourceFoodId}-$i',
            daysAgo: daysAgo,
            name: m.name,
            unitType: m.unitType,
            referenceAmount: m.referenceAmount,
            referenceLabel: m.referenceLabel,
            protein: m.protein,
            carbs: m.carbs,
            fiber: m.fiber,
            fat: m.fat,
            amountConsumed: m.amountConsumed,
            sourceFoodId: m.sourceFoodId,
            groupIdSnapshot: m.groupId,
            groupNameSnapshot: m.groupName,
          ),
        );
      }
    }

    return rows;
  }
}

/// Helper class for metric-to-effort-kind relationships
class MetricApplicability {
  final String metricId;
  final String effortKind;

  const MetricApplicability({required this.metricId, required this.effortKind});
}
