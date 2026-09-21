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
      WatchConfirmationRecord.type => WatchConfirmationRecord.fromJson(json),
      WatchRoutineCatalogRecord.type => WatchRoutineCatalogRecord.fromJson(json),
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

  /// Effort kind: `set`, `timed`, `round`, `hold`, or `nutrition_quick_log`.
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
  WatchRoutineCatalogRecord withSequence(int sequence) => WatchRoutineCatalogRecord(
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

/// A UTC timestamp in the protocol's wire shape: `YYYY-MM-DDTHH:MM:SS(.sss)Z`.
String utcIso(DateTime instant) {
  final iso = instant.toUtc().toIso8601String();
  return iso.endsWith('Z') ? iso : '${iso}Z';
}

DateTime parseUtcIso(Object? value) => DateTime.parse(value! as String).toUtc();

DateTime? parseOptionalUtcIso(Object? value) =>
    value == null ? null : parseUtcIso(value);

/// Narrows a decoded JSON value to a string-keyed map.
Map<String, Object?> asJsonObject(Object? value) =>
    (value as Map).cast<String, Object?>();
