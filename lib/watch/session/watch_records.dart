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
