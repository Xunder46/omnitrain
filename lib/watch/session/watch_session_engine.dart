/// The watch session engine: one training session, no phone required.
///
/// Plan: `.github/agents/plans/2026-07-13-06-a1-watch-session-engine-plan.md`.
///
/// Two invariants shape this class:
///
/// 1. **A logged set is never lost.** Every observation reaches storage before
///    anything is emitted, and everything the engine needs to continue —
///    session, position, entries, timers — is read back from storage by
///    [restore]. Nothing authoritative lives only in memory, so a suspension,
///    an OS kill, or a reboot costs the user nothing (S-001, S-002).
/// 2. **The watch never edits or deletes.** The engine appends new rows; it
///    cannot rewrite one. Position and timer state advance by appending, and
///    data is dropped only through [pruneConfirmed], which is gated on the
///    phone's receipt (S-004, S-005, S-006).
///
/// Messages are built from persisted rows, not from transient state, which is
/// why a replay after a crash re-sends the same events — the identifiers the
/// phone deduplicates on (PROTOCOL.md, "Idempotency and reconciliation").
library;

import 'package:uuid/uuid.dart';

import '../../core/sync_protocol/message_validator.dart';
import 'watch_records.dart';
import 'watch_session_store.dart';

/// Where the engine hands the messages the watch owes the phone.
typedef WatchMessageSink = void Function(Map<String, Object?> envelope);

/// Thrown when a message fails protocol conformance. Nothing was persisted and
/// nothing was emitted: the message never existed.
class WatchEmissionRejected implements Exception {
  WatchEmissionRejected({required this.message, required this.rejections});

  final String message;
  final List<SyncProtocolRejection> rejections;

  /// The protocol's own verdict, in the shape a receiver would return.
  SyncMessageDecision get decision => SyncMessageDecision(
    decision: SyncProtocolValidator.rejectDecision,
    reason: message,
    respondWithSnapshot: true,
    rejections: rejections,
  );

  @override
  String toString() => message;
}

class WatchSessionEngine {
  WatchSessionEngine(
    this._store, {
    this.onEmit,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
    String Function()? idFactory,
    String Function()? sessionIdFactory,
  }) : _validator = validator,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid,
       _newSessionId = sessionIdFactory ?? _uuid;

  static const Uuid _uuidV4 = Uuid();

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String _uuid() => _uuidV4.v4();

  final WatchSessionStore _store;

  /// Called once per message the engine emits, after the recording row is
  /// already stored.
  final WatchMessageSink? onEmit;

  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;
  final String Function() _newId;
  final String Function() _newSessionId;

  final List<WatchSessionRecord> _sessionRows = [];
  final List<WatchObservationRecord> _observations = [];
  final List<WatchTimerRecord> _timers = [];

  WatchSessionRecord? _session;

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Rebuilds the in-progress session from storage.
  ///
  /// Call this on launch and after any suspension: what comes back is what the
  /// watch knew at kill time, because nothing else was ever authoritative.
  Future<void> restore() async {
    final contents = await _store.readAll();

    _sessionRows
      ..clear()
      ..addAll(contents.sessions);
    _observations
      ..clear()
      ..addAll(contents.observations);
    _timers
      ..clear()
      ..addAll(contents.timers);

    _session = contents.sessions.isEmpty
        ? null
        : contents.sessions.reduce(
            (latest, row) => row.sequence > latest.sequence ? row : latest,
          );
  }

  // ---------------------------------------------------------------------------
  // Session state
  // ---------------------------------------------------------------------------

  /// The session as last persisted, or null when nothing has been logged yet.
  WatchSessionRecord? get session => _session;

  /// The exercise the session is currently on, when the session has any.
  Map<String, Object?>? get currentExercise => _session?.currentExercise;

  /// The current session's observations, in the order they were logged.
  List<WatchObservationRecord> get observations => List.unmodifiable([
    for (final observation in _observations)
      if (observation.sessionId == _session?.sessionId) observation,
  ]);

  /// The newest row for [kind], which is the timer that applies.
  WatchTimerRecord? timerFor(String kind) => _newestTimer(kind: kind);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts a session that needs no phone to run.
  ///
  /// [exercises] are the protocol's `sessionExercise` slots — delivered by the
  /// phone when it can reach the watch, or supplied by the start paths. They are
  /// persisted with the session so a relaunch knows what the position means.
  Future<WatchSessionRecord> createSession({
    required String? modality,
    String source = 'watch',
    List<Map<String, Object?>> exercises = const [],
  }) async {
    final now = _clock();
    final stored = await _store.append(
      WatchSessionRecord(
        recordId: _newId(),
        sessionId: _newSessionId(),
        recordedAt: now,
        startedAt: now,
        modality: modality,
        source: source,
        status: WatchSessionStatus.active,
        currentExerciseIndex: 0,
        exercises: exercises,
      ),
    );

    _session = stored;
    return stored;
  }

  /// Moves to the next exercise. The last exercise is the end of the ladder.
  Future<WatchSessionRecord> advanceExercise() async {
    final session = _requireSession();
    final lastIndex = session.exercises.isEmpty
        ? 0
        : session.exercises.length - 1;
    return _transitionTo(
      currentExerciseIndex: (session.currentExerciseIndex + 1).clamp(
        0,
        lastIndex,
      ),
    );
  }

  /// Closes the session as done.
  Future<WatchSessionRecord> finishSession() =>
      _transitionTo(status: WatchSessionStatus.completed);

  /// Closes the session as given up on. Entries already logged stay logged.
  Future<WatchSessionRecord> abandonSession() =>
      _transitionTo(status: WatchSessionStatus.abandoned);

  /// Writes a new session row carrying [status] and [currentExerciseIndex].
  ///
  /// A state change appends rather than updates, which is what both keeps the
  /// store append-only and makes the position survive a kill.
  Future<WatchSessionRecord> _transitionTo({
    String? status,
    int? currentExerciseIndex,
  }) async {
    final session = _requireSession();
    final stored = await _store.append(
      WatchSessionRecord(
        recordId: _newId(),
        sessionId: session.sessionId,
        recordedAt: _clock(),
        startedAt: session.startedAt,
        modality: session.modality,
        source: session.source,
        status: status ?? session.status,
        currentExerciseIndex:
            currentExerciseIndex ?? session.currentExerciseIndex,
        exercises: session.exercises,
      ),
    );

    _session = stored;
    return stored;
  }

  // ---------------------------------------------------------------------------
  // Observations
  // ---------------------------------------------------------------------------

  /// Persists [event] and emits it as an `observations_up` message.
  ///
  /// The event is stored before anything is emitted, so a crash in between
  /// costs nothing: [pendingObservations] rebuilds the message from the stored
  /// row. Logging the same event twice is a no-op — the phone deduplicates on
  /// `eventId`, and so does the watch's own storage.
  Future<WatchObservationRecord> appendObservation(
    Map<String, Object?> event,
  ) async {
    final session = _requireSession();
    final eventId = event['eventId'];
    final recordId = eventId is String && eventId.isNotEmpty
        ? eventId
        : _newId();
    final now = _clock();

    final record = WatchObservationRecord(
      recordId: recordId,
      sessionId: session.sessionId,
      recordedAt: now,
      kind: (event['kind'] as String?) ?? '',
      payload: event,
    );

    final envelope = _observationsUp(
      session.sessionId,
      record,
      sentAt: now,
      messageId: _messageIdFor(recordId),
    );
    _requireConformant(envelope);

    final existing = _observations.any((row) => row.recordId == recordId);
    final stored = await _store.append(record);
    if (!existing) {
      _observations.add(stored);
      _emit(envelope);
    }
    return stored;
  }

  /// The messages the phone still owes a receipt for, rebuilt from storage.
  ///
  /// Emission is not a hand-off of state: it is a projection of the stored
  /// rows, so replaying after a kill sends the same events with the same
  /// identifiers.
  List<Map<String, Object?>> pendingObservations() {
    final session = _session;
    if (session == null) return const [];
    return [
      for (final observation in observations)
        if (observation.confirmedAt == null)
          _observationsUp(
            session.sessionId,
            observation,
            sentAt: observation.recordedAt,
            messageId: _messageIdFor(observation.recordId),
          ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Timers
  // ---------------------------------------------------------------------------

  /// Starts [kind], replacing any timer of that kind that was already running.
  Future<WatchTimerRecord> startTimer(
    String kind, {
    int? plannedDurationMs,
  }) async {
    _requireTimerKind(kind);
    final now = _clock();
    final stored = await _appendTimer(
      WatchTimerRecord(
        recordId: _newId(),
        sessionId: _requireSession().sessionId,
        recordedAt: now,
        kind: kind,
        startedAt: now,
        plannedDurationMs: plannedDurationMs,
      ),
    );
    return stored;
  }

  /// Pauses the newest timer, or the newest one of [kind].
  Future<WatchTimerRecord?> pauseTimer({String? kind}) async {
    final timer = _activeTimer(kind);
    if (timer == null || timer.state != WatchTimerState.running) return timer;

    final now = _clock();
    return _appendTimer(_timerRowFrom(timer, recordedAt: now, pausedAt: now));
  }

  /// Resumes a paused timer, folding the finished pause into its bookkeeping.
  Future<WatchTimerRecord?> resumeTimer({String? kind}) async {
    final timer = _activeTimer(kind);
    if (timer == null || timer.state != WatchTimerState.paused) return timer;

    final now = _clock();
    return _appendTimer(
      _timerRowFrom(
        timer,
        recordedAt: now,
        clearPause: true,
        accumulatedPauseMs:
            timer.accumulatedPauseMs +
            now.difference(timer.pausedAt!).inMilliseconds,
      ),
    );
  }

  /// Ends the newest timer, or the newest one of [kind]. A stopped timer keeps
  /// the time it had reached.
  Future<WatchTimerRecord?> stopTimer({String? kind}) async {
    final timer = _activeTimer(kind);
    if (timer == null || timer.state == WatchTimerState.stopped) return timer;

    final now = _clock();
    return _appendTimer(_timerRowFrom(timer, recordedAt: now, stoppedAt: now));
  }

  /// Copies [timer]'s identity into a new row — timers advance by append too.
  WatchTimerRecord _timerRowFrom(
    WatchTimerRecord timer, {
    required DateTime recordedAt,
    DateTime? pausedAt,
    bool clearPause = false,
    int? accumulatedPauseMs,
    DateTime? stoppedAt,
  }) => WatchTimerRecord(
    recordId: _newId(),
    sessionId: timer.sessionId,
    recordedAt: recordedAt,
    kind: timer.kind,
    startedAt: timer.startedAt,
    pausedAt: clearPause ? null : (pausedAt ?? timer.pausedAt),
    stoppedAt: stoppedAt ?? timer.stoppedAt,
    accumulatedPauseMs: accumulatedPauseMs ?? timer.accumulatedPauseMs,
    plannedDurationMs: timer.plannedDurationMs,
  );

  Future<WatchTimerRecord> _appendTimer(WatchTimerRecord row) async {
    final stored = await _store.append(row);
    _timers.add(stored);
    _emit(
      _timerState(
        stored.sessionId,
        stored,
        sentAt: stored.recordedAt,
        messageId: _messageIdFor(stored.recordId),
      ),
    );
    return stored;
  }

  /// The most recently started timer of [kind], or of any kind when [kind] is
  /// null — which is the timer the user is looking at.
  WatchTimerRecord? _activeTimer(String? kind) => _newestTimer(kind: kind);

  WatchTimerRecord? _newestTimer({String? kind}) {
    WatchTimerRecord? newest;
    for (final timer in _timers) {
      if (timer.sessionId != _session?.sessionId) continue;
      if (kind != null && timer.kind != kind) continue;
      if (newest == null || timer.sequence > newest.sequence) newest = timer;
    }
    return newest;
  }

  void _requireTimerKind(String kind) {
    if (!WatchTimerKind.all.contains(kind)) {
      throw ArgumentError.value(
        kind,
        'kind',
        'is not one of ${WatchTimerKind.all.join(', ')}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Confirmation and retention
  // ---------------------------------------------------------------------------

  /// Records the phone's receipt of the observations behind [entryIds].
  ///
  /// A receipt is an append of its own: the watch must remember what it may
  /// drop across a relaunch, without rewriting an observation.
  Future<List<String>> confirmObservations(Iterable<String> entryIds) async {
    final session = _requireSession();
    final wanted = entryIds.toSet();
    final acknowledged = [
      for (final observation in _observations)
        if (wanted.contains(observation.entryId) &&
            observation.confirmedAt == null)
          observation,
    ];
    if (acknowledged.isEmpty) return const [];

    final now = _clock();
    await _store.append(
      WatchConfirmationRecord(
        recordId: _newId(),
        sessionId: session.sessionId,
        recordedAt: now,
        observationIds: [
          for (final observation in acknowledged) observation.recordId,
        ],
      ),
    );

    final acknowledgedIds = {
      for (final observation in acknowledged) observation.recordId,
    };
    for (var index = 0; index < _observations.length; index++) {
      final observation = _observations[index];
      if (acknowledgedIds.contains(observation.recordId)) {
        _observations[index] = observation.withConfirmation(now);
      }
    }

    return [for (final observation in acknowledged) observation.recordId];
  }

  /// Drops confirmed observations. Unconfirmed ones stay until the phone
  /// acknowledges them.
  Future<List<String>> pruneConfirmed() async {
    final pruned = await _store.pruneConfirmed();
    final dropped = pruned.toSet();
    _observations.removeWhere(
      (observation) => dropped.contains(observation.recordId),
    );
    return pruned;
  }

  // ---------------------------------------------------------------------------
  // Emission
  // ---------------------------------------------------------------------------

  Map<String, Object?> _observationsUp(
    String sessionId,
    WatchObservationRecord record, {
    required DateTime sentAt,
    required String messageId,
  }) => {
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': messageId,
    'sessionId': sessionId,
    'type': 'observations_up',
    'origin': 'watch',
    'sentAt': utcIso(sentAt),
    'payload': {
      'events': [record.payload],
    },
  };

  Map<String, Object?> _timerState(
    String sessionId,
    WatchTimerRecord timer, {
    required DateTime sentAt,
    required String messageId,
  }) => {
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': messageId,
    'sessionId': sessionId,
    'type': 'timer_state',
    'origin': 'watch',
    'sentAt': utcIso(sentAt),
    'payload': {
      'timers': {timer.kind: timer.toTimerJson()},
    },
  };

  /// The delivery key is derived from the row, not minted per attempt: a
  /// replay after a crash re-sends the same message for the same record.
  String _messageIdFor(String recordId) => 'msg-$recordId';

  void _emit(Map<String, Object?> envelope) => onEmit?.call(envelope);

  /// Refuses to hand out anything the protocol would reject — the watch must
  /// not be the source of a message the phone cannot read.
  void _requireConformant(Map<String, Object?> envelope) {
    final rejections =
        _validator?.validateEnvelope(envelope) ??
        const <SyncProtocolRejection>[];
    if (rejections.isEmpty) return;

    throw WatchEmissionRejected(
      message: 'refusing to emit a non-conformant message: ${rejections.first}',
      rejections: rejections,
    );
  }

  WatchSessionRecord _requireSession() {
    final session = _session;
    if (session == null) {
      throw StateError(
        'no session: create one, or restore the in-progress session first',
      );
    }
    return session;
  }
}
