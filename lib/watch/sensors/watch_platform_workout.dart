/// The platform workout session: the watch telling the operating system that
/// training is happening.
///
/// Plan: `docs/plans/2026-07-13-11-d-watch-sensor-recording-plan.md`,
/// scenarios S-001, S-002, S-005, S-007 and S-008.
///
/// Registering the session with the platform's health service is what unlocks
/// the rest: live heart rate, correct calorie and activity attribution in the
/// store, and — most importantly — the runtime priority that keeps a workout app
/// alive while the wrist is down. It is also why a session that ends must end
/// its workout: a workout left "in progress" by a kill is a lie the health store
/// keeps telling until something closes it.
///
/// The type comes from the exercises' named Health kind first, then the
/// modality, and the modality → type table is shared with the watchOS client
/// (`watch/contract/watch_sensor_contract.json`), so both wrists register the
/// same thing. Whatever the table says, an unmapped modality is a generic
/// workout rather than no workout at all.
library;

import '../../core/constants/capability.dart';
import '../session/watch_records.dart';

/// The activity type one modality registers as, in each platform's own
/// vocabulary.
///
/// Two fields rather than one string, because the two platforms have never
/// agreed on a name for anything: watchOS speaks `HKWorkoutActivityType` and
/// Wear OS speaks Health Connect's `EXERCISE_TYPE_*`. Keeping both here means
/// neither client has to guess what the other calls a lift.
class WatchActivityType {
  const WatchActivityType({required this.watchOs, required this.wear});

  /// The `HKWorkoutActivityType` case, lower-camel.
  final String watchOs;

  /// The Health Connect exercise type, lower-snake.
  final String wear;

  @override
  bool operator ==(Object other) =>
      other is WatchActivityType &&
      other.watchOs == watchOs &&
      other.wear == wear;

  @override
  int get hashCode => Object.hash(watchOs, wear);

  @override
  String toString() => 'WatchActivityType($watchOs / $wear)';
}

/// The modality → platform workout type table.
///
/// Every seeded modality is named, including the older ones the phone's own
/// catalog no longer offers: a user's session started months ago still has to
/// open a workout of the right kind if it is replayed.
abstract final class WatchActivityTypes {
  /// What an unmapped modality registers as. A workout with the wrong type is a
  /// workout the user can correct; no workout at all loses the session, the
  /// runtime priority, and the heart-rate stream with it (S-007).
  static const WatchActivityType generic = WatchActivityType(
    watchOs: 'other',
    wear: 'exercise_type_other_workout',
  );

  static const Map<String, WatchActivityType> byModality = {
    'cardio_endurance': WatchActivityType(
      watchOs: 'running',
      wear: 'exercise_type_running',
    ),
    'resistance_lifting': WatchActivityType(
      watchOs: 'traditionalStrengthTraining',
      wear: 'exercise_type_strength_training',
    ),
    'isometric_stretching': WatchActivityType(
      watchOs: 'flexibility',
      wear: 'exercise_type_flexibility',
    ),
    'sports': generic,
    'strength_resistance': WatchActivityType(
      watchOs: 'traditionalStrengthTraining',
      wear: 'exercise_type_strength_training',
    ),
    'skill_technique': generic,
    'conditioning_mixed': WatchActivityType(
      watchOs: 'crossTraining',
      wear: 'exercise_type_cross_training',
    ),
    'mobility_flexibility': WatchActivityType(
      watchOs: 'flexibility',
      wear: 'exercise_type_flexibility',
    ),
    'recovery_rehab': WatchActivityType(
      watchOs: 'flexibility',
      wear: 'exercise_type_flexibility',
    ),
    'competition_match': generic,
  };

  static WatchActivityType forModality(String? modality) =>
      byModality[modality] ?? generic;

  /// The Health Connect name a platform that speaks [watchOs] registers (the
  /// Wear client's translation, plan 300 D-30002): the first type in the tables
  /// whose watchOS name matches, else the generic workout's.
  static String wearFor(String watchOs) {
    for (final type in [...byModality.values, ..._kindTypes.values]) {
      if (type.watchOs == watchOs) return type.wear;
    }
    return generic.wear;
  }

  /// The modality key when it is one the wrist knows (a non-empty [String] that is a key of
  /// [byModality]), else null. Never throws: any other value is null.
  static String? knownModality(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return byModality.containsKey(value) ? value : null;
  }

  /// The type one exercise registers as: the Health kind the phone named for
  /// it, else what it can measure (D-16803, widened by plan 170 D-17003).
  static WatchActivityType forExercise({
    required List<String> capabilities,
    String? healthActivity,
  }) =>
      _forExercise(capabilities: capabilities, healthActivity: healthActivity);

  /// The majority type of [exercises]; a tie goes to the earliest. Null for an
  /// empty list: the type is not known yet.
  static WatchActivityType? forExercises(
    List<Map<String, Object?>> exercises,
  ) => _forExercises(exercises);

  /// What [session] registers as (D-16803, superseding plan 75 D-2's precedence
  /// half; widened to every discipline's kind by plan 170 D-17003): the
  /// majority Health kind its exercises name, when any names one this table
  /// carries; otherwise its modality's own type (unchanged); otherwise, for a
  /// Free workout, the majority of its exercises. Null while none is known, so
  /// the caller registers the generic type.
  ///
  /// The wrist fixes the type once the workout opens — HealthKit cannot retype
  /// an `HKWorkoutSession` — so an exercise added later never retypes it
  /// (S-8808).
  static WatchActivityType? forSession(WatchSessionRecord session) {
    final named = _forNamedHealthKinds(session.exercises);
    if (named != null) return named;
    final modality = session.modality;
    if (modality != null) return forModality(modality);
    return _forExercises(session.exercises);
  }
}

/// Every Health kind the phone can name for an exercise, and the type it
/// registers as — plan 170 D-17001's discipline table. The contract file
/// carries the same rows, and the suites assert the two agree
/// (`watch/contract/watch_sensor_contract.json`, D-17006); mirrors the Swift
/// client's `WatchActivityTypes.kindTypes`.
const Map<String, WatchActivityType> _kindTypes = {
  'running': _running,
  'cycling': _cycling,
  'swimming': WatchActivityType(
    watchOs: 'swimming',
    wear: 'exercise_type_swimming',
  ),
  'rowing': _rowing,
  'walking': _walking,
  'hiking': _hiking,
  'traditionalStrengthTraining': _strength,
  'calisthenics': WatchActivityType(
    watchOs: 'functionalStrengthTraining',
    wear: 'exercise_type_calisthenics',
  ),
  'isometricHolds': WatchActivityType(
    watchOs: 'functionalStrengthTraining',
    wear: 'exercise_type_strength_training',
  ),
  'conditioning': WatchActivityType(
    watchOs: 'crossTraining',
    wear: 'exercise_type_cross_training',
  ),
  'mixedCardio': WatchActivityType(
    watchOs: 'mixedCardio',
    wear: 'exercise_type_other_workout',
  ),
  'preparationAndRecovery': WatchActivityType(
    watchOs: 'preparationAndRecovery',
    wear: 'exercise_type_other_workout',
  ),
  'flexibility': WatchActivityType(
    watchOs: 'flexibility',
    wear: 'exercise_type_stretching',
  ),
  'yoga': WatchActivityType(watchOs: 'yoga', wear: 'exercise_type_yoga'),
  'boxing': WatchActivityType(watchOs: 'boxing', wear: 'exercise_type_boxing'),
  'kickboxing': WatchActivityType(
    watchOs: 'kickboxing',
    wear: 'exercise_type_martial_arts',
  ),
  'martialArts': WatchActivityType(
    watchOs: 'martialArts',
    wear: 'exercise_type_martial_arts',
  ),
  'tennis': WatchActivityType(watchOs: 'tennis', wear: 'exercise_type_tennis'),
  'badminton': WatchActivityType(
    watchOs: 'badminton',
    wear: 'exercise_type_badminton',
  ),
  'tableTennis': WatchActivityType(
    watchOs: 'tableTennis',
    wear: 'exercise_type_table_tennis',
  ),
  'cricket': WatchActivityType(
    watchOs: 'cricket',
    wear: 'exercise_type_cricket',
  ),
  'hockey': WatchActivityType(
    watchOs: 'hockey',
    wear: 'exercise_type_other_workout',
  ),
  'baseball': WatchActivityType(
    watchOs: 'baseball',
    wear: 'exercise_type_baseball',
  ),
  'americanFootball': WatchActivityType(
    watchOs: 'americanFootball',
    wear: 'exercise_type_american_football',
  ),
  'rugby': WatchActivityType(watchOs: 'rugby', wear: 'exercise_type_rugby'),
  'lacrosse': WatchActivityType(
    watchOs: 'lacrosse',
    wear: 'exercise_type_other_workout',
  ),
  'soccer': WatchActivityType(
    watchOs: 'soccer',
    wear: 'exercise_type_football',
  ),
  'basketball': WatchActivityType(
    watchOs: 'basketball',
    wear: 'exercise_type_basketball',
  ),
  'volleyball': WatchActivityType(
    watchOs: 'volleyball',
    wear: 'exercise_type_volleyball',
  ),
  'squash': WatchActivityType(watchOs: 'squash', wear: 'exercise_type_squash'),
  'golf': WatchActivityType(watchOs: 'golf', wear: 'exercise_type_golf'),
  'climbing': WatchActivityType(
    watchOs: 'climbing',
    wear: 'exercise_type_rock_climbing',
  ),
};

/// The type a named Health kind registers as, or null for a name this table
/// does not carry — a kind from a newer phone is treated as absent (D-17003).
WatchActivityType? _kindType(String? activity) =>
    activity == null ? null : _kindTypes[activity];

const WatchActivityType _running = WatchActivityType(
  watchOs: 'running',
  wear: 'exercise_type_running',
);
const WatchActivityType _cycling = WatchActivityType(
  watchOs: 'cycling',
  wear: 'exercise_type_biking',
);
const WatchActivityType _rowing = WatchActivityType(
  watchOs: 'rowing',
  wear: 'exercise_type_rowing',
);
const WatchActivityType _walking = WatchActivityType(
  watchOs: 'walking',
  wear: 'exercise_type_walking',
);
const WatchActivityType _hiking = WatchActivityType(
  watchOs: 'hiking',
  wear: 'exercise_type_hiking',
);
const WatchActivityType _strength = WatchActivityType(
  watchOs: 'traditionalStrengthTraining',
  wear: 'exercise_type_strength_training',
);
const WatchActivityType _flexibility = WatchActivityType(
  watchOs: 'flexibility',
  wear: 'exercise_type_flexibility',
);

/// The type one exercise registers as, from what it can measure and the Health
/// kind the phone named for it: the kind is the exercise's own claim and is
/// consulted first (D-17003); then a hold (a plank has `hold` and `sets`), then
/// distance, then reps/sets/load; anything else is the generic type. An unknown
/// kind resolves to nothing and falls through.
WatchActivityType _forExercise({
  required List<String> capabilities,
  String? healthActivity,
}) {
  final named = _kindType(healthActivity);
  if (named != null) return named;
  if (capabilities.contains('hold')) return _flexibility;
  if (capabilities.contains(WatchGpsPolicy.distanceCapability)) {
    return _running;
  }
  if (capabilities.any(const {'reps', 'sets', 'load'}.contains)) {
    return _strength;
  }
  return WatchActivityTypes.generic;
}

/// The majority type of [exercises]; a tie goes to the type of the earliest
/// exercise that reaches the highest count. Null for an empty list: the type is
/// not known yet.
WatchActivityType? _forExercises(List<Map<String, Object?>> exercises) {
  if (exercises.isEmpty) return null;
  final types = [
    for (final exercise in exercises)
      _forExercise(
        capabilities:
            (exercise['capabilities'] as List?)?.cast<String>() ?? const [],
        healthActivity: exercise['healthActivity'] as String?,
      ),
  ];
  return _majority(types);
}

/// The majority of [types]; a tie goes to the earliest one.
WatchActivityType? _majority(List<WatchActivityType> types) {
  if (types.isEmpty) return null;
  final counts = <String, int>{};
  for (final type in types) {
    counts[type.watchOs] = (counts[type.watchOs] ?? 0) + 1;
  }
  final best = counts.values.reduce((a, b) => a > b ? a : b);
  return types.firstWhere((type) => counts[type.watchOs] == best);
}

/// The majority Health kind [exercises] name; a tie goes to the earliest named
/// one. Null when no exercise names a kind this table carries — an exercise that
/// names nothing must not vote, or a Cardio routine's unnamed lift would tie
/// every named walk (D-16803), and neither must a name the wrist does not know,
/// which is treated as absent (plan 170 D-17003).
WatchActivityType? _forNamedHealthKinds(List<Map<String, Object?>> exercises) {
  final named = [
    for (final exercise in exercises)
      ?_kindType(exercise['healthActivity'] as String?),
  ];
  return _majority(named);
}

/// Whether the session's current exercise calls for GPS.
///
/// The answer is read from the exercise's capabilities and never from a name:
/// a lift and a run are told apart by what they can measure, so an exercise
/// added tomorrow is handled without touching this file, and one that merely
/// *sounds* like distance work does not wake the radio (S-008; plan 205).
abstract final class WatchGpsPolicy {
  static const String distanceCapability = ExerciseCapability.distance;

  /// True when an exercise's capabilities include distance — the exercise, not
  /// its name (the Swift client's `WatchGpsPolicy.coversDistance`).
  static bool coversDistance(Iterable<String> capabilities) =>
      capabilities.contains(distanceCapability);
}

/// The health service's own view of workouts: the OS-level surface, which is the
/// part that cannot be tested off-device.
///
/// Deliberately three calls and no state. The watch holds one workout at a time —
/// that is what the platform grants — so `end` needs no identifier, and
/// [inProgressActivityTypes] exists for exactly one purpose: finding out what a
/// previous process left running.
abstract interface class WatchPlatformWorkoutStore {
  Future<void> begin(String activityType);

  Future<void> end();

  /// The activity types the health store still reports as in progress, oldest
  /// first. Anything here belongs to a process that is gone.
  Future<List<String>> inProgressActivityTypes();
}

/// The watch's platform workout, over whatever store the platform provides.
class WatchPlatformWorkout {
  WatchPlatformWorkout({required WatchPlatformWorkoutStore store})
    : _store = store;

  final WatchPlatformWorkoutStore _store;

  WatchActivityType? _running;

  /// The workout currently registered, or null when the watch has none open.
  WatchActivityType? get running => _running;

  /// Registers [session]'s modality as a platform workout and returns what it
  /// was registered as.
  ///
  /// Starting a session while one is already open ends the old workout first:
  /// the platform grants one at a time, and a dangling one is exactly the stuck
  /// state recovery exists to clear.
  Future<WatchActivityType> start(WatchSessionRecord session) async {
    if (_running != null) await end();

    final activityType =
        WatchActivityTypes.forSession(session) ?? WatchActivityTypes.generic;
    await _store.begin(activityType.watchOs);
    _running = activityType;
    return activityType;
  }

  /// Closes the workout the watch opened, if any.
  Future<void> end() async {
    if (_running == null) return;
    await _store.end();
    _running = null;
  }

  /// Ends whatever the health store still reports as in progress and returns the
  /// activity types it closed.
  ///
  /// Run at launch. A kill cannot be caught, so the only reliable moment to
  /// notice an orphaned workout is the next start — and the honest thing to do
  /// with one is end it: the session it belonged to is already over as far as
  /// this process is concerned, and its logged entries are in storage regardless
  /// of whether the workout was open (S-005).
  Future<List<String>> recoverInProgress() async {
    final stranded = await _store.inProgressActivityTypes();
    final ended = <String>[];

    for (final activityType in stranded) {
      await _store.end();
      ended.add(activityType);
    }

    _running = null;
    return ended;
  }
}
