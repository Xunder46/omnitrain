/// Records the watch appends to its own storage.
///
/// The watch store is append-only (PROTOCOL.md, authority rule 1): a record is
/// written once and never rewritten, and the newest record for a key wins when
/// state is reduced from the log. A session's position therefore advances by
/// appending a new session row and a timer is paused by appending a new timer
/// row — there is no update path, which is what makes the storage contract
/// testable as append-only (`test/watch_session_engine_test.dart`, S-004).
///
/// Field names and value sets mirror the sync protocol schemas, so a record can
/// be turned into a protocol message without translation tables.
library;

import '../../core/sync_protocol/wire_timestamps.dart';

// The protocol's wire shape for a timestamp belongs to the protocol, not to the
// watch: `lib/core/sync_protocol/wire_timestamps.dart` owns it, and the watch
// tree keeps reading it through here, where its records are built.
export '../../core/sync_protocol/wire_timestamps.dart'
    show utcIso, parseUtcIso, parseOptionalUtcIso;

/// Session status values, matching `session_snapshot.payload.status`.
abstract final class WatchSessionStatus {
  static const String active = 'active';
  static const String completed = 'completed';
  static const String abandoned = 'abandoned';
}

/// Timer kinds, matching `timer_state.payload.timers` keys.
abstract final class WatchTimerKind {
  static const String rest = 'rest';
  static const String round = 'round';
  static const String hold = 'hold';
  static const String elapsed = 'elapsed';

  static const List<String> all = [rest, round, hold, elapsed];
}

/// Derived timer states, matching the protocol's `timer.state` enum. A timer's
/// state is not stored: it follows from which timestamps a record carries.
abstract final class WatchTimerState {
  static const String running = 'running';
  static const String paused = 'paused';
  static const String stopped = 'stopped';
}

/// Session lifecycle states, matching `session_lifecycle.payload.state`. The
/// watch emits these as the session moves; the phone's mirror follows them.
abstract final class WatchLifecycleState {
  static const String started = 'started';
  static const String exerciseAdvanced = 'exercise_advanced';
  static const String completed = 'completed';
  static const String abandoned = 'abandoned';
}

/// The `kind` an observation carries, matching `observations_up`'s event enum
/// (PROTOCOL.md, "Message families").
abstract final class WatchObservationKind {
  static const String set = 'set';
  static const String timed = 'timed';
  static const String round = 'round';
  static const String hold = 'hold';

  /// A food the user quick-logged. The one kind that is not tied to a session
  /// slot: it names a food and a portion, and nothing else.
  static const String nutritionQuickLog = 'nutrition_quick_log';

  static const List<String> all = [set, timed, round, hold, nutritionQuickLog];
}

/// The session id a nutrition quick-log carries when the wrist has no session
/// to put it in.
///
/// `observations_up` requires a non-empty `sessionId`, and the quick-log
/// surface is reachable with no workout running — eating is not a training
/// event. A log taken outside a session therefore names the day's nutrition
/// log rather than inventing a training session; a log taken while a session is
/// running rides that session instead, so it is part of the workout's story.
abstract final class WatchNutritionSession {
  static const String prefix = 'nutrition-';

  /// The id standalone quick-logs logged at [loggedAt] carry, in UTC.
  static String idFor(DateTime loggedAt) {
    final utc = loggedAt.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '$prefix${utc.year}-$month-$day';
  }
}

/// What a sensor sample measures, and in which unit.
///
/// The watch stores raw readings; nothing here is derived analytics, and the
/// kinds are the vocabulary both watch clients agreed on
/// (`watch/contract/watch_sensor_contract.json`).
abstract final class WatchSensorKind {
  /// Beats per minute, at the instant the sample was taken.
  static const String heartRate = 'hr';

  /// Cumulative metres covered since the session started, as the GPS fix saw
  /// it. Each fix supersedes the one before: latest wins.
  static const String gps = 'gps';

  /// The session's distance total in metres, written when recording stops and
  /// the measurement is final.
  static const String distance = 'distance';

  /// The platform's step count since the platform workout began. Vocabulary
  /// only on this client: it keeps the kind list equal to the shared contract,
  /// and nothing here records it.
  static const String steps = 'steps';

  static const List<String> all = [heartRate, gps, distance, steps];
}

/// Base of every stored record — the single shape the store accepts.
///
/// Sealed on purpose: the store has exactly one mutation entry point, and it
/// takes a [WatchRecord], so no caller can smuggle in a record type the
/// append-only guard has never seen.
sealed class WatchRecord {
  const WatchRecord({
    required this.recordId,
    required this.sessionId,
    required this.recordedAt,
    this.sequence = 0,
  });

  /// Identity of this row. Appending the same id twice is a no-op, never a
  /// second row — that is what makes appends idempotent.
  final String recordId;

  final String sessionId;

  /// When the watch wrote this row, in UTC.
  final DateTime recordedAt;

  /// Append order, assigned by the store. Orders rows written in the same
  /// millisecond; it carries no other meaning.
  final int sequence;

  /// Discriminator used by the store's JSON encoding.
  String get recordType;

  /// Copy carrying the store-assigned [sequence].
  WatchRecord withSequence(int sequence);

  Map<String, Object?> toJson();

  static WatchRecord fromJson(Map<String, Object?> json) {
    final type = json['recordType'];
    return switch (type) {
      WatchSessionRecord.type => WatchSessionRecord.fromJson(json),
      WatchObservationRecord.type => WatchObservationRecord.fromJson(json),
      WatchTimerRecord.type => WatchTimerRecord.fromJson(json),
      WatchSensorSampleRecord.type => WatchSensorSampleRecord.fromJson(json),
      WatchConfirmationRecord.type => WatchConfirmationRecord.fromJson(json),
      WatchRoutineCatalogRecord.type => WatchRoutineCatalogRecord.fromJson(
        json,
      ),
      WatchFoodCatalogRecord.type => WatchFoodCatalogRecord.fromJson(json),
      _ => throw FormatException('unknown watch record type: $type'),
    };
  }
}

/// One version of a session's state. Position and status change by appending a
/// newer row; the newest row for a session id is the session.
final class WatchSessionRecord extends WatchRecord {
  const WatchSessionRecord({
    required super.recordId,
    required super.sessionId,
    required super.recordedAt,
    required this.startedAt,
    required this.modality,
    required this.source,
    required this.status,
    required this.currentExerciseIndex,
    this.exercises = const [],
    this.revision = 0,
    this.deletedEntryIds = const [],
    super.sequence,
  });

  static const String type = 'session';

  /// When the session was started — set once, on the row that created it.
  final DateTime startedAt;

  /// Modality key, or null for free training.
  final String? modality;

  /// Which device started the session: `watch` or `phone`.
  final String source;

  /// One of [WatchSessionStatus].
  final String status;

  /// Position in [exercises].
  final int currentExerciseIndex;

  /// The session's exercise slots, as the protocol's `sessionExercise` objects.
  final List<Map<String, Object?>> exercises;

  /// The phone's structure counter — bumped by one per applied structure
  /// change, so the two devices can tell at a glance whether they are looking
  /// at the same session shape. Zero until a snapshot says otherwise.
  final int revision;

  /// The entry ids the phone deleted, as the newest row knows them: the durable
  /// half of the deletion lens (plan D-113), so a relaunch rebuilds it from
  /// storage instead of forgetting it. Ids the newest snapshot carries are not
  /// in it — an entry the phone still sends exists.
  final List<String> deletedEntryIds;

  Map<String, Object?>? get currentExercise => exercises.isEmpty
      ? null
      : exercises[currentExerciseIndex.clamp(0, exercises.length - 1)];

  @override
  String get recordType => type;

  @override
  WatchSessionRecord withSequence(int sequence) => WatchSessionRecord(
    recordId: recordId,
    sessionId: sessionId,
    recordedAt: recordedAt,
    startedAt: startedAt,
    modality: modality,
    source: source,
    status: status,
    currentExerciseIndex: currentExerciseIndex,
    exercises: exercises,
    revision: revision,
    deletedEntryIds: deletedEntryIds,
    sequence: sequence,
  );

  /// The same row carrying [deletedEntryIds] as its deletion lens.
  WatchSessionRecord withDeletedEntryIds(List<String> deletedEntryIds) =>
      WatchSessionRecord(
        recordId: recordId,
        sessionId: sessionId,
        recordedAt: recordedAt,
        startedAt: startedAt,
        modality: modality,
        source: source,
        status: status,
        currentExerciseIndex: currentExerciseIndex,
        exercises: exercises,
        revision: revision,
        deletedEntryIds: deletedEntryIds,
        sequence: sequence,
      );

  @override
  Map<String, Object?> toJson() => {
    'recordType': type,
    'recordId': recordId,
    'sessionId': sessionId,
    'recordedAt': utcIso(recordedAt),
    'sequence': sequence,
    'startedAt': utcIso(startedAt),
    'modality': modality,
    'source': source,
    'status': status,
    'currentExerciseIndex': currentExerciseIndex,
    'exercises': exercises,
    'revision': revision,
    'deletedEntryIds': deletedEntryIds,
  };

  static WatchSessionRecord fromJson(Map<String, Object?> json) =>
      WatchSessionRecord(
        recordId: json['recordId']! as String,
        sessionId: json['sessionId']! as String,
        recordedAt: parseUtcIso(json['recordedAt']),
        startedAt: parseUtcIso(json['startedAt']),
        modality: json['modality'] as String?,
        source: json['source']! as String,
        status: json['status']! as String,
        currentExerciseIndex: json['currentExerciseIndex']! as int,
        exercises: ((json['exercises'] as List?) ?? const [])
            .map(asJsonObject)
            .toList(growable: false),
        revision: (json['revision'] as int?) ?? 0,
        deletedEntryIds: [
          for (final id in (json['deletedEntryIds'] as List?) ?? const [])
            id! as String,
        ],
        sequence: (json['sequence'] as int?) ?? 0,
      );
}

/// One observation the watch logged. The payload is the protocol's
/// `observations_up` event verbatim, so emission needs no reconstruction.
final class WatchObservationRecord extends WatchRecord {
  const WatchObservationRecord({
    required super.recordId,
    required super.sessionId,
    required super.recordedAt,
    required this.kind,
    required this.payload,
    this.confirmedAt,
    super.sequence,
  });

  static const String type = 'observation';

  /// Effort kind: one of [WatchObservationKind] — `set`, `timed`, `round`,
  /// `hold`, or `nutrition_quick_log`.
  final String kind;

  /// The protocol event, exactly as it will be sent.
  final Map<String, Object?> payload;

  /// When the phone confirmed receipt. Set only by a
  /// [WatchConfirmationRecord]; an unconfirmed observation is retained
  /// indefinitely.
  final DateTime? confirmedAt;

  String get entryId => payload['entryId']! as String;

  String get eventId => payload['eventId']! as String;

  @override
  String get recordType => type;

  @override
  WatchObservationRecord withSequence(int sequence) =>
      _copy(sequence: sequence);

  /// The same observation, carrying the phone's [confirmedAt] receipt.
  WatchObservationRecord withConfirmation(DateTime confirmedAt) =>
      _copy(confirmedAt: confirmedAt, sequence: sequence);

  /// The same observation carrying [payload] — how a correction the phone sent
  /// reaches the surface without rewriting the stored row.
  WatchObservationRecord withPayload(Map<String, Object?> payload) =>
      WatchObservationRecord(
        recordId: recordId,
        sessionId: sessionId,
        recordedAt: recordedAt,
        kind: kind,
        payload: payload,
        confirmedAt: confirmedAt,
        sequence: sequence,
      );

  WatchObservationRecord _copy({DateTime? confirmedAt, int? sequence}) =>
      WatchObservationRecord(
        recordId: recordId,
        sessionId: sessionId,
        recordedAt: recordedAt,
        kind: kind,
        payload: payload,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        sequence: sequence ?? this.sequence,
      );

  @override
  Map<String, Object?> toJson() => {
    'recordType': type,
    'recordId': recordId,
    'sessionId': sessionId,
    'recordedAt': utcIso(recordedAt),
    'sequence': sequence,
    'kind': kind,
    'payload': payload,
  };

  static WatchObservationRecord fromJson(Map<String, Object?> json) =>
      WatchObservationRecord(
        recordId: json['recordId']! as String,
        sessionId: json['sessionId']! as String,
        recordedAt: parseUtcIso(json['recordedAt']),
        kind: json['kind']! as String,
        payload: asJsonObject(json['payload']),
        sequence: (json['sequence'] as int?) ?? 0,
      );
}

/// One version of a timer's state. Timestamps only: remaining time is never
/// stored, because a stored countdown is wrong the moment the watch sleeps.
final class WatchTimerRecord extends WatchRecord {
  const WatchTimerRecord({
    required super.recordId,
    required super.sessionId,
    required super.recordedAt,
    required this.kind,
    required this.startedAt,
    this.pausedAt,
    this.stoppedAt,
    this.accumulatedPauseMs = 0,
    this.plannedDurationMs,
    super.sequence,
  });

  static const String type = 'timer';

  /// One of [WatchTimerKind].
  final String kind;

  final DateTime startedAt;

  /// When the current pause began, or null while the timer runs.
  final DateTime? pausedAt;

  final DateTime? stoppedAt;

  /// Total length of every pause that has already ended.
  final int accumulatedPauseMs;

  /// Planned length, when the timer counts down. Null for elapsed timers.
  final int? plannedDurationMs;

  /// One of [WatchTimerState], derived from which timestamps are present.
  String get state {
    if (stoppedAt != null) return WatchTimerState.stopped;
    if (pausedAt != null) return WatchTimerState.paused;
    return WatchTimerState.running;
  }

  @override
  String get recordType => type;

  @override
  WatchTimerRecord withSequence(int sequence) => WatchTimerRecord(
    recordId: recordId,
    sessionId: sessionId,
    recordedAt: recordedAt,
    kind: kind,
    startedAt: startedAt,
    pausedAt: pausedAt,
    stoppedAt: stoppedAt,
    accumulatedPauseMs: accumulatedPauseMs,
    plannedDurationMs: plannedDurationMs,
    sequence: sequence,
  );

  /// The protocol's `timer` object for this record.
  Map<String, Object?> toTimerJson() => {
    'kind': kind,
    'state': state,
    'startedAt': utcIso(startedAt),
    if (pausedAt != null) 'pausedAt': utcIso(pausedAt!),
    if (stoppedAt != null) 'stoppedAt': utcIso(stoppedAt!),
    'accumulatedPauseMs': accumulatedPauseMs,
    if (plannedDurationMs != null) 'plannedDurationMs': plannedDurationMs,
  };

  @override
  Map<String, Object?> toJson() => {
    'recordType': type,
    'recordId': recordId,
    'sessionId': sessionId,
    'recordedAt': utcIso(recordedAt),
    'sequence': sequence,
    'kind': kind,
    'startedAt': utcIso(startedAt),
    'pausedAt': pausedAt == null ? null : utcIso(pausedAt!),
    'stoppedAt': stoppedAt == null ? null : utcIso(stoppedAt!),
    'accumulatedPauseMs': accumulatedPauseMs,
    'plannedDurationMs': plannedDurationMs,
  };

  static WatchTimerRecord fromJson(Map<String, Object?> json) =>
      WatchTimerRecord(
        recordId: json['recordId']! as String,
        sessionId: json['sessionId']! as String,
        recordedAt: parseUtcIso(json['recordedAt']),
        kind: json['kind']! as String,
        startedAt: parseUtcIso(json['startedAt']),
        pausedAt: parseOptionalUtcIso(json['pausedAt']),
        stoppedAt: parseOptionalUtcIso(json['stoppedAt']),
        accumulatedPauseMs: (json['accumulatedPauseMs'] as int?) ?? 0,
        plannedDurationMs: json['plannedDurationMs'] as int?,
        sequence: (json['sequence'] as int?) ?? 0,
      );
}

/// One reading a platform sensor produced during a session.
///
/// Samples are records like any other: appended once, never rewritten, and read
/// back by [WatchSessionEngine.sensorSamples] after a relaunch. A reading is
/// therefore a fact with a timestamp, not a value held in memory — the watch can
/// be killed mid-run and the distance it had measured is still there.
///
/// Nothing here is emitted to the phone as a message of its own. The distance a
/// session covers travels as the `distanceMeters` of the effort that was logged,
/// which is the protocol's own field, so the phone needs no new message type and
/// no second source of truth for how far the user went.
final class WatchSensorSampleRecord extends WatchRecord {
  const WatchSensorSampleRecord({
    required super.recordId,
    required super.sessionId,
    required super.recordedAt,
    required this.kind,
    required this.value,
    super.sequence,
  });

  static const String type = 'sensor_sample';

  /// One of [WatchSensorKind]. [value]'s unit follows from it.
  final String kind;

  /// Beats per minute, cumulative metres, or the settled total — see
  /// [WatchSensorKind].
  final double value;

  /// The record id for a reading of [kind] taken at [at].
  ///
  /// Derived rather than random so that a reading delivered twice — a replay, a
  /// duplicate callback from the sensor — is the same row and not a second one.
  static String sampleId({
    required String sessionId,
    required String kind,
    required DateTime at,
  }) => 'sen-$sessionId-$kind-${at.toUtc().millisecondsSinceEpoch}';

  @override
  String get recordType => type;

  @override
  WatchSensorSampleRecord withSequence(int sequence) => WatchSensorSampleRecord(
    recordId: recordId,
    sessionId: sessionId,
    recordedAt: recordedAt,
    kind: kind,
    value: value,
    sequence: sequence,
  );

  @override
  Map<String, Object?> toJson() => {
    'recordType': type,
    'recordId': recordId,
    'sessionId': sessionId,
    'recordedAt': utcIso(recordedAt),
    'sequence': sequence,
    'kind': kind,
    'value': value,
  };

  static WatchSensorSampleRecord fromJson(Map<String, Object?> json) =>
      WatchSensorSampleRecord(
        recordId: json['recordId']! as String,
        sessionId: json['sessionId']! as String,
        recordedAt: parseUtcIso(json['recordedAt']),
        kind: json['kind']! as String,
        value: (json['value']! as num).toDouble(),
        sequence: (json['sequence'] as int?) ?? 0,
      );
}

/// The phone's receipt for observations it has already recorded.
///
/// Confirmation is appended rather than written onto the observation row: the
/// watch must remember what it may drop across a relaunch, and it must do so
/// without rewriting a synced record.
final class WatchConfirmationRecord extends WatchRecord {
  const WatchConfirmationRecord({
    required super.recordId,
    required super.sessionId,
    required super.recordedAt,
    required this.observationIds,
    super.sequence,
  });

  static const String type = 'confirmation';

  /// Record ids of the observations the phone acknowledged.
  final List<String> observationIds;

  /// The receipt's instant — the store hands it to each named observation as
  /// its `confirmedAt`.
  DateTime get confirmedAt => recordedAt;

  @override
  String get recordType => type;

  @override
  WatchConfirmationRecord withSequence(int sequence) => WatchConfirmationRecord(
    recordId: recordId,
    sessionId: sessionId,
    recordedAt: recordedAt,
    observationIds: observationIds,
    sequence: sequence,
  );

  @override
  Map<String, Object?> toJson() => {
    'recordType': type,
    'recordId': recordId,
    'sessionId': sessionId,
    'recordedAt': utcIso(recordedAt),
    'sequence': sequence,
    'observationIds': observationIds,
  };

  static WatchConfirmationRecord fromJson(Map<String, Object?> json) =>
      WatchConfirmationRecord(
        recordId: json['recordId']! as String,
        sessionId: json['sessionId']! as String,
        recordedAt: parseUtcIso(json['recordedAt']),
        observationIds: ((json['observationIds'] as List?) ?? const [])
            .cast<String>(),
        sequence: (json['sequence'] as int?) ?? 0,
      );
}

/// The reference data the phone sends down: the user's routines and the
/// fallback exercise list the wrist may log without reaching the phone.
///
/// A catalog row carries no session, which is why its `sessionId` is empty — it
/// belongs to the watch, not to any one workout. Like every other row it is
/// append-only: a sync writes a new catalog and the newest one wins, so the
/// version the user had before a sync is still readable afterwards.
///
/// What the wrist itself used recently is *not* stored here: it is derived from
/// the sessions the watch already kept, which is one less thing that can drift.
final class WatchRoutineCatalogRecord extends WatchRecord {
  const WatchRoutineCatalogRecord({
    required super.recordId,
    required super.recordedAt,
    required this.generatedAt,
    this.routines = const [],
    this.fallbackExercises = const [],
    super.sequence,
  }) : super(sessionId: '');

  static const String type = 'routine_catalog';

  /// When the phone generated this view of the routines. A message older than
  /// the cached one is not a newer truth, so it is ignored.
  final DateTime generatedAt;

  /// The routines as `routines_down` carried them: routine → segments →
  /// efforts → per-metric targets.
  final List<Map<String, Object?>> routines;

  /// The phone's fallback exercise list, in the phone's order.
  final List<Map<String, Object?>> fallbackExercises;

  @override
  String get recordType => type;

  @override
  WatchRoutineCatalogRecord withSequence(int sequence) =>
      WatchRoutineCatalogRecord(
        recordId: recordId,
        recordedAt: recordedAt,
        generatedAt: generatedAt,
        routines: routines,
        fallbackExercises: fallbackExercises,
        sequence: sequence,
      );

  @override
  Map<String, Object?> toJson() => {
    'recordType': type,
    'recordId': recordId,
    'sessionId': sessionId,
    'recordedAt': utcIso(recordedAt),
    'sequence': sequence,
    'generatedAt': utcIso(generatedAt),
    'routines': routines,
    'fallbackExercises': fallbackExercises,
  };

  static WatchRoutineCatalogRecord fromJson(Map<String, Object?> json) =>
      WatchRoutineCatalogRecord(
        recordId: json['recordId']! as String,
        recordedAt: parseUtcIso(json['recordedAt']),
        generatedAt: parseUtcIso(json['generatedAt']),
        routines: ((json['routines'] as List?) ?? const [])
            .map(asJsonObject)
            .toList(growable: false),
        fallbackExercises: ((json['fallbackExercises'] as List?) ?? const [])
            .map(asJsonObject)
            .toList(growable: false),
        sequence: (json['sequence'] as int?) ?? 0,
      );
}

/// The reference data a `foods_down` message carries: the foods the wrist may
/// quick-log, and the categories that order them.
///
/// The same shape of row as [WatchRoutineCatalogRecord] and for the same
/// reason: it is the phone's data, the watch only reads it, and it belongs to
/// no session — so its `sessionId` is empty and a sync appends a new row rather
/// than editing the one before it. What the wrist itself logged recently is
/// *not* stored here either: it is derived from the observations the store
/// already holds.
final class WatchFoodCatalogRecord extends WatchRecord {
  const WatchFoodCatalogRecord({
    required super.recordId,
    required super.recordedAt,
    required this.generatedAt,
    this.foods = const [],
    this.categories = const [],
    super.sequence,
  }) : super(sessionId: '');

  static const String type = 'food_catalog';

  /// When the phone generated this view of the food list. A message older than
  /// the cached one is not a newer truth, so it is ignored.
  final DateTime generatedAt;

  /// The foods as `foods_down` carried them, in the phone's own array order —
  /// which is not the order the wrist shows: the derivation reorders them.
  final List<Map<String, Object?>> foods;

  /// The phone's active food categories, in the phone's own array order.
  final List<Map<String, Object?>> categories;

  @override
  String get recordType => type;

  @override
  WatchFoodCatalogRecord withSequence(int sequence) => WatchFoodCatalogRecord(
    recordId: recordId,
    recordedAt: recordedAt,
    generatedAt: generatedAt,
    foods: foods,
    categories: categories,
    sequence: sequence,
  );

  @override
  Map<String, Object?> toJson() => {
    'recordType': type,
    'recordId': recordId,
    'sessionId': sessionId,
    'recordedAt': utcIso(recordedAt),
    'sequence': sequence,
    'generatedAt': utcIso(generatedAt),
    'foods': foods,
    'categories': categories,
  };

  static WatchFoodCatalogRecord fromJson(Map<String, Object?> json) =>
      WatchFoodCatalogRecord(
        recordId: json['recordId']! as String,
        recordedAt: parseUtcIso(json['recordedAt']),
        generatedAt: parseUtcIso(json['generatedAt']),
        foods: ((json['foods'] as List?) ?? const [])
            .map(asJsonObject)
            .toList(growable: false),
        categories: ((json['categories'] as List?) ?? const [])
            .map(asJsonObject)
            .toList(growable: false),
        sequence: (json['sequence'] as int?) ?? 0,
      );
}

/// Narrows a decoded JSON value to a string-keyed map.
Map<String, Object?> asJsonObject(Object? value) =>
    (value as Map).cast<String, Object?>();
