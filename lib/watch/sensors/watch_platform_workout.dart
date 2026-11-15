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
import '../../core/constants/modality_config.dart';
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

  /// The modality key when it is one the wrist knows (a non-empty [String] that is a key of
  /// [byModality]), else null. Never throws: any other value is null.
  static String? knownModality(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return byModality.containsKey(value) ? value : null;
  }

  /// The type one exercise registers as, from what it can measure (D-16803).
  static WatchActivityType forExercise({
    required List<String> capabilities,
    String? healthActivity,
  }) =>
      _forExercise(capabilities: capabilities, healthActivity: healthActivity);

  /// The majority type of [exercises]; a tie goes to the earliest. Null for an
  /// empty list: the type is not known yet.
  static WatchActivityType? forExercises(List<Map<String, Object?>> exercises) =>
      _forExercises(exercises);

  /// What [session] registers as (D-16803, superseding plan 75 D-2's precedence
  /// half): the majority Health kind its exercises name, when any names one;
  /// otherwise its modality's own type (unchanged); otherwise, for a Free
  /// workout, the majority of its exercises. Null while none is known, so the
  /// caller registers the generic type.
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

/// The activity type the Health kind the phone named for an exercise registers
/// as, when the table maps it to one of its own (D-16803); anything else —
/// null, "running", a kind this table does not carry — stays running.
/// Mirrors the Swift client's `WatchActivityTypes.distanceType`.
WatchActivityType _distanceType(String? activity) {
  switch (activity) {
    case 'cycling':
      return _cycling;
    case 'rowing':
      return _rowing;
    case 'walking':
      return _walking;
    case 'hiking':
      return _hiking;
    default:
      return _running;
  }
}

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

/// The Health kinds the phone may name for an exercise and the table maps to a
/// type of their own (D-16803).
const Set<String> _namedHealthKinds = {
  'cycling',
  'rowing',
  'walking',
  'hiking',
  'running',
};

/// The type one exercise registers as, from what it can measure: a hold is
/// tested first (a plank has `hold` and `sets`), then distance — refined by the
/// Health kind the phone named, when it named one — then reps/sets/load;
/// anything else is the generic type.
WatchActivityType _forExercise({
  required List<String> capabilities,
  String? healthActivity,
}) {
  if (capabilities.contains('hold')) return _flexibility;
  if (capabilities.contains(WatchGpsPolicy.distanceCapability)) {
    return _distanceType(healthActivity);
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
/// one. Null when no exercise names one — an exercise that names nothing must
/// not vote, or a Cardio routine's unnamed lift would tie every named walk
/// (D-16803).
WatchActivityType? _forNamedHealthKinds(List<Map<String, Object?>> exercises) {
  final named = [
    for (final exercise in exercises)
      if (exercise['healthActivity'] case final String kind
          when _namedHealthKinds.contains(kind))
        _distanceType(kind),
  ];
  return _majority(named);
}

/// Whether a session's modality calls for GPS.
///
/// The answer is read from the modality's capability profile and never from its
/// name: a lift and a run are told apart by what they can measure, so a modality
/// added tomorrow is handled without touching this file, and one that merely
/// *sounds* like distance work does not wake the radio (S-008).
abstract final class WatchGpsPolicy {
  static const String distanceCapability = ExerciseCapability.distance;

  /// True when [modality] can cover distance — as a capability it carries, not
  /// as one it rules out. Free training has no profile, so it never records GPS:
  /// the user picks the exercise after the session starts, too late to decide,
  /// and the distance row stays theirs to fill.
  static bool isRequired(String? modality) {
    final config = ModalityConfig.forModality(modality);
    if (config == null) return false;

    return config.primaryCapabilities.contains(distanceCapability) ||
        config.secondaryCapabilities.contains(distanceCapability);
  }

  /// True when an exercise's capabilities include distance — the exercise, not
  /// its name. The wrist decides GPS by the exercise the user is on as well as
  /// by the session's modality (the Swift client's `WatchGpsPolicy.coversDistance`).
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
