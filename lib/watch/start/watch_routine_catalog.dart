/// The reference data a `routines_down` message carries, in the shapes the
/// wrist reasons about.
///
/// The store keeps the phone's JSON as it arrived ([WatchRoutineCatalogRecord]);
/// these types are the view the start paths read it through — a synced routine
/// can be listed, turned into session slots, and checked for the exercises it
/// needs to stay loggable with the phone unreachable.
///
/// Nothing here is the watch's own data: routines are the phone's to own and
/// the wrist's to read (PROTOCOL.md, authority rule 2).
library;

import '../session/watch_records.dart';

/// A catalog exercise: what it is, not where it sits in a session.
class WatchCatalogExercise {
  const WatchCatalogExercise({
    required this.exerciseId,
    required this.name,
    required this.capabilities,
  });

  factory WatchCatalogExercise.fromJson(Map<String, Object?> json) =>
      WatchCatalogExercise(
        exerciseId: json['exerciseId']! as String,
        name: json['name']! as String,
        capabilities: _capabilities(json['capabilities']),
      );

  /// The exercise a session slot holds, or null when the slot is malformed.
  static WatchCatalogExercise? fromSlot(Map<String, Object?> slot) {
    final exerciseId = slot['exerciseId'];
    final name = slot['name'];
    if (exerciseId is! String || name is! String) return null;
    return WatchCatalogExercise(
      exerciseId: exerciseId,
      name: name,
      capabilities: _capabilities(slot['capabilities']),
    );
  }

  static List<String> _capabilities(Object? value) =>
      ((value as List?) ?? const []).whereType<String>().toList(
        growable: false,
      );

  final String exerciseId;
  final String name;

  /// The capability flags the effort kind and the metric rows are derived from.
  final List<String> capabilities;

  /// The slot id this exercise takes when the user picks it for a session.
  /// Distinct from the ids the phone chooses, which is what lets a pushed
  /// exercise and a picked one of the same kind sit side by side.
  String get slotId => 'sx-$exerciseId';

  /// This exercise as a protocol `sessionExercise` slot.
  ///
  /// [effortKind] is the routine's declared kind, and only a routine has one:
  /// a slot without it carries no `effortKind` at all, and the receiver
  /// resolves the kind from the capabilities (PROTOCOL.md, `sessionExercise`).
  Map<String, Object?> toSlot({
    String? sessionExerciseId,
    String? effortKind,
  }) => {
    'sessionExerciseId': sessionExerciseId ?? slotId,
    'exerciseId': exerciseId,
    'name': name,
    'capabilities': capabilities,
    'effortKind': ?effortKind,
  };

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    'name': name,
    'capabilities': capabilities,
  };
}

/// One planned effort inside a routine segment: what to do and how much of it.
class WatchRoutineEffort {
  const WatchRoutineEffort({
    required this.effortId,
    required this.exerciseId,
    required this.exerciseName,
    required this.effortKind,
    required this.capabilities,
    this.targets = const {},
  });

  factory WatchRoutineEffort.fromJson(Map<String, Object?> json) =>
      WatchRoutineEffort(
        effortId: json['effortId']! as String,
        exerciseId: json['exerciseId']! as String,
        exerciseName: json['exerciseName']! as String,
        effortKind: json['effortKind']! as String,
        capabilities: WatchCatalogExercise._capabilities(json['capabilities']),
        targets: asJsonObject(json['targets'] ?? const {}),
      );

  final String effortId;
  final String exerciseId;
  final String exerciseName;

  /// The phone's effort kind for this effort — `set`, `timed`, `round`, or
  /// `drill`.
  final String effortKind;

  final List<String> capabilities;

  /// Per-metric targets, keyed the way the protocol keys them.
  final Map<String, Object?> targets;

  /// The slot this effort becomes when the routine is started. Keyed by
  /// effort, so a routine that benches in two segments yields two slots — and
  /// carrying the routine's declared effort kind, which is the one the wrist
  /// renders (a Plank in an isometric routine is timed because the routine says
  /// so, not because a capability suggests otherwise).
  Map<String, Object?> get slot => catalogExercise.toSlot(
    sessionExerciseId: 'sx-$effortId',
    effortKind: effortKind,
  );

  /// This effort as a catalog exercise, for the fallback list.
  WatchCatalogExercise get catalogExercise => WatchCatalogExercise(
    exerciseId: exerciseId,
    name: exerciseName,
    capabilities: capabilities,
  );

  Map<String, Object?> toJson() => {
    'effortId': effortId,
    'exerciseId': exerciseId,
    'exerciseName': exerciseName,
    'effortKind': effortKind,
    'capabilities': capabilities,
    'targets': targets,
  };
}

/// One segment of a routine: a named run of efforts.
class WatchRoutineSegment {
  const WatchRoutineSegment({
    required this.segmentId,
    required this.name,
    required this.efforts,
  });

  factory WatchRoutineSegment.fromJson(Map<String, Object?> json) =>
      WatchRoutineSegment(
        segmentId: json['segmentId']! as String,
        name: json['name']! as String,
        efforts: ((json['efforts'] as List?) ?? const [])
            .map(asJsonObject)
            .map(WatchRoutineEffort.fromJson)
            .toList(growable: false),
      );

  final String segmentId;
  final String name;
  final List<WatchRoutineEffort> efforts;

  Map<String, Object?> toJson() => {
    'segmentId': segmentId,
    'name': name,
    'efforts': [for (final effort in efforts) effort.toJson()],
  };
}

/// A reusable workout template, as the phone sent it.
class WatchRoutine {
  const WatchRoutine({
    required this.routineId,
    required this.name,
    required this.updatedAt,
    required this.segments,
  });

  factory WatchRoutine.fromJson(Map<String, Object?> json) => WatchRoutine(
    routineId: json['routineId']! as String,
    name: json['name']! as String,
    updatedAt: parseUtcIso(json['updatedAt']),
    segments: ((json['segments'] as List?) ?? const [])
        .map(asJsonObject)
        .map(WatchRoutineSegment.fromJson)
        .toList(growable: false),
  );

  final String routineId;
  final String name;

  /// When the phone last edited it. The cache is replaced wholesale, so this is
  /// what tells the user which version they are looking at.
  final DateTime updatedAt;

  final List<WatchRoutineSegment> segments;

  /// Every effort in the routine, in the order the session will run them.
  Iterable<WatchRoutineEffort> get efforts =>
      segments.expand((segment) => segment.efforts);

  /// The session slots starting this routine creates, in order.
  List<Map<String, Object?>> get slots => [
    for (final effort in efforts) effort.slot,
  ];

  /// The catalog exercises this routine cannot run without, in routine order,
  /// deduplicated. Every one of them must be in the fallback list, or the watch
  /// would hold a routine it cannot log offline.
  List<WatchCatalogExercise> get referencedExercises {
    final seen = <String>{};
    return [
      for (final effort in efforts)
        if (seen.add(effort.exerciseId)) effort.catalogExercise,
    ];
  }

  Map<String, Object?> toJson() => {
    'routineId': routineId,
    'name': name,
    'updatedAt': utcIso(updatedAt),
    'segments': [for (final segment in segments) segment.toJson()],
  };
}

/// A parsed `routines_down` payload: the routines, the fallback list, and when
/// the phone generated them.
class WatchRoutinesDown {
  const WatchRoutinesDown({
    required this.generatedAt,
    required this.routines,
    required this.fallbackExercises,
  });

  /// Reads the payload out of an envelope the validator has already approved.
  factory WatchRoutinesDown.fromEnvelope(Map<String, Object?> envelope) {
    final payload = asJsonObject(envelope['payload']);
    return WatchRoutinesDown(
      generatedAt: parseUtcIso(payload['generatedAt']),
      routines: ((payload['routines'] as List?) ?? const [])
          .map(asJsonObject)
          .map(WatchRoutine.fromJson)
          .toList(growable: false),
      fallbackExercises: ((payload['fallbackExercises'] as List?) ?? const [])
          .map(asJsonObject)
          .map(WatchCatalogExercise.fromJson)
          .toList(growable: false),
    );
  }

  /// The same view, read back out of the row the watch stored.
  factory WatchRoutinesDown.fromCatalog(WatchRoutineCatalogRecord record) =>
      WatchRoutinesDown(
        generatedAt: record.generatedAt,
        routines: record.routines
            .map(WatchRoutine.fromJson)
            .toList(growable: false),
        fallbackExercises: record.fallbackExercises
            .map(WatchCatalogExercise.fromJson)
            .toList(growable: false),
      );

  final DateTime generatedAt;
  final List<WatchRoutine> routines;
  final List<WatchCatalogExercise> fallbackExercises;

  /// The row that stores this message, so a relaunch holds the same routines
  /// without the phone.
  WatchRoutineCatalogRecord toRecord({
    required String recordId,
    required DateTime recordedAt,
  }) => WatchRoutineCatalogRecord(
    recordId: recordId,
    recordedAt: recordedAt,
    generatedAt: generatedAt,
    routines: [for (final routine in routines) routine.toJson()],
    fallbackExercises: [
      for (final exercise in fallbackExercises) exercise.toJson(),
    ],
  );
}
