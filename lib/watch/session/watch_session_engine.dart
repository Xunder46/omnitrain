/// The watch session engine: one training session, no phone required.
///
/// Plan: `docs/plans/2026-07-13-06-a1-watch-session-engine-plan.md`.
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

/// Thrown when a message fails protocol conformance. The watch refuses both
/// halves of the exchange: a message it cannot emit, and a message from the
/// phone it cannot read. Nothing was persisted and nothing was emitted — the
/// message never existed.
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

  /// Record-id prefixes for the rows a message from the phone writes. The id is
  /// derived from the `changeId` (or `messageId`) that caused the row, which is
  /// what makes re-delivery a store no-op *and* what lets [restore] rebuild
  /// "already applied" from storage instead of from memory.
  static const String _changePrefix = 'chg-';
  static const String _snapshotPrefix = 'snap-';
  static const String _timerPrefix = 'tms-';
  static const String _lifecyclePrefix = 'life-';

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
  final List<WatchSensorSampleRecord> _sensorSamples = [];

  /// The structure changes this watch has already applied, by `changeId`.
  /// Rebuilt from storage by [restore], so a relaunch cannot apply one twice
  /// (PROTOCOL.md, authority rule 6).
  final Set<String> _appliedChangeIds = {};

  /// The phone's corrections to entries the watch holds, keyed by `entryId`,
  /// and the ones it deleted. The stored row is never rewritten — these are
  /// what [entries] folds in.
  final Map<String, Map<String, Object?>> _entryCorrections = {};
  final Set<String> _deletedEntryIds = {};

  /// The ids whose held row the phone **replaced** rather than corrected: its
  /// snapshot re-stated the id with a different `loggedAt`, which is a
  /// different entry reusing a minted number (D-113.3). A correction merges
  /// into the held payload; a replacement is the whole payload.
  final Set<String> _replacedEntryIds = {};

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
    _sensorSamples
      ..clear()
      ..addAll(contents.sensorSamples);

    _session = contents.sessions.isEmpty
        ? null
        : contents.sessions.reduce(
            (latest, row) => row.sequence > latest.sequence ? row : latest,
          );

    _appliedChangeIds
      ..clear()
      ..addAll([
        for (final row in contents.sessions)
          if (row.recordId.startsWith(_changePrefix))
            row.recordId.substring(_changePrefix.length),
      ]);

    // D-113.1: the deletion lens is read back from the newest row, so a
    // relaunch hides the same entries the killed process hid.
    _deletedEntryIds
      ..clear()
      ..addAll(_session?.deletedEntryIds ?? const []);
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

  /// The readings the platform sensors produced for the current session, in the
  /// order they arrived.
  ///
  /// Read back from storage, never from a live subscription: the newest heart
  /// rate on the wrist is the newest row that reached the store, so a relaunch
  /// shows what the watch measured instead of starting from nothing.
  List<WatchSensorSampleRecord> get sensorSamples => List.unmodifiable([
    for (final sample in _sensorSamples)
      if (sample.sessionId == _session?.sessionId) sample,
  ]);

  /// The newest reading of [kind] for the current session, or null when there
  /// has been none.
  WatchSensorSampleRecord? newestSensorSample(String kind) =>
      newestSensorSamples()[kind];

  /// The newest reading of each kind, keyed by [WatchSensorKind] — one pass over
  /// the session's samples.
  ///
  /// A readout needs several kinds at once (the beat, the distance, the pace
  /// that divides them) and it is rebuilt on a one-second tick, so the caller
  /// resolves the session's measurements once rather than scanning per value.
  Map<String, WatchSensorSampleRecord> newestSensorSamples() {
    final sessionId = _session?.sessionId;
    final newest = <String, WatchSensorSampleRecord>{};

    for (final sample in _sensorSamples) {
      if (sample.sessionId != sessionId) continue;
      final current = newest[sample.kind];
      if (current == null || sample.sequence > current.sequence) {
        newest[sample.kind] = sample;
      }
    }

    return newest;
  }

  /// The newest row for [kind], which is the timer that applies.
  WatchTimerRecord? timerFor(String kind) => _newestTimer(kind: kind);

  /// The session's entries as the wrist shows them: the watch's own log plus
  /// the entries the phone sent, with the phone's corrections folded in and its
  /// deletions dropped, in the order they were logged.
  ///
  /// [observations] is the log as appended — nothing in it is ever rewritten.
  /// A correction is therefore a projection, not an edit, which is what keeps
  /// the store append-only and the phone the only side that can edit history.
  List<WatchObservationRecord> get entries {
    final projected = <WatchObservationRecord>[
      for (final observation in observations)
        if (!_deletedEntryIds.contains(observation.entryId))
          switch (_entryCorrections[observation.entryId]) {
            null => observation,
            final correction when _replacedEntryIds.contains(
              observation.entryId,
            ) =>
              // D-113.3: a re-stated id with a new stamp **is** the whole entry,
              // so the held row's keys it does not carry are gone with it.
              observation.withPayload(correction),
            final correction => observation.withPayload({
              ...observation.payload,
              ...correction,
            }),
          },
    ];
    projected.sort(_byLoggedAtThenEntryId);
    return List.unmodifiable(projected);
  }

  /// The watch's live session as the phone's mirror reads it — the answer to a
  /// snapshot request. Null when the watch has no session to report.
  ///
  /// Entries travel as [entries], so a correction the phone sent is not echoed
  /// back as the original, and timers travel as wall-clock state: the phone
  /// derives remaining time from its own clock (PROTOCOL.md, "Timer state").
  Map<String, Object?>? sessionSnapshot({String? messageId}) {
    final session = _session;
    if (session == null) return null;

    final envelope = <String, Object?>{
      'protocolVersion': SyncProtocolValidator.protocolVersion,
      'messageId': messageId ?? _messageIdFor('snapshot-${session.recordId}'),
      'sessionId': session.sessionId,
      'type': 'session_snapshot',
      'origin': 'watch',
      'sentAt': utcIso(_clock()),
      'payload': <String, Object?>{
        'sessionId': session.sessionId,
        'revision': session.revision,
        'status': session.status,
        'currentExerciseIndex': session.currentExerciseIndex,
        'exercises': session.exercises,
        'entries': [for (final entry in entries) entry.payload],
        'timers': _timersJson(),
      },
    };
    _requireConformant(envelope);
    return envelope;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts a session that needs no phone to run, and announces it.
  ///
  /// [exercises] are the protocol's `sessionExercise` slots — delivered by the
  /// phone when it can reach the watch, or supplied by the start paths (a
  /// routine's efforts, or the exercises the user just picked). They are
  /// persisted with the session so a relaunch knows what the position means.
  ///
  /// The session-started lifecycle event leaves through the same sink as every
  /// other message, so the phone's live mirror learns about a wrist-started
  /// session without being asked (S-006). The snapshot follows that lifecycle
  /// frame, carrying the session's shape (D-91, S-100).
  Future<WatchSessionRecord> createSession({
    required String? modality,
    String source = 'watch',
    List<Map<String, Object?>> exercises = const [],
  }) async {
    // The wrist runs one session at a time: a start that arrives while a live
    // session is held is refused and the held session is what the caller gets
    // back — same row, no lifecycle, no snapshot (D-171, D-177). A session the
    // wrist already ended does not hold the slot, so the next start is free.
    final held = _session;
    if (held != null && held.status == WatchSessionStatus.active) {
      return held;
    }

    final now = _clock();
    final live = await _appendSessionRow(
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
      lifecycle: WatchLifecycleState.started,
    );
    _emitSnapshotIfConformant();
    return live;
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
      lifecycle: WatchLifecycleState.exerciseAdvanced,
    );
  }

  /// Closes the session as done.
  Future<WatchSessionRecord> finishSession() => _transitionTo(
    status: WatchSessionStatus.completed,
    lifecycle: WatchLifecycleState.completed,
  );

  /// Closes the session as given up on. Entries already logged stay logged.
  Future<WatchSessionRecord> abandonSession() => _transitionTo(
    status: WatchSessionStatus.abandoned,
    lifecycle: WatchLifecycleState.abandoned,
  );

  /// Puts [slot] into the session's exercise ladder.
  ///
  /// A slot id already present is dropped rather than added twice, which is
  /// what makes a re-delivered push harmless (PROTOCOL.md, "Exercise
  /// identity"). [moveTo] decides where the position lands: the user's own pick
  /// moves the session to the new exercise, while a structure change the phone
  /// initiated leaves the user on the exercise they were logging — the rule the
  /// phone's reconciler applies to its own pushes.
  ///
  /// [announce] separates the wrist's own add from the phone's (D-91, D-101): the
  /// watch announces a ladder change it made itself with a snapshot and a moved
  /// revision, while a push the phone sent is applied silently.
  Future<WatchSessionRecord> insertExercise(
    Map<String, Object?> slot, {
    int? atIndex,
    bool moveTo = false,
    bool announce = true,
  }) async {
    final session = _requireSession();
    final slotId = slot['sessionExerciseId'];
    if (slotId is String &&
        session.exercises.any((row) => row['sessionExerciseId'] == slotId)) {
      return session;
    }

    final index = _insertionIndex(
      atIndex ?? session.exercises.length,
      session.exercises.length,
    );
    final exercises = [...session.exercises]..insert(index, slot);

    final live = await _transitionTo(
      currentExerciseIndex: _positionAfterInsert(
        currentIndex: session.currentExerciseIndex,
        insertedAt: index,
        moveTo: moveTo,
        wasEmpty: session.exercises.isEmpty,
      ),
      exercises: exercises,
      lifecycle: null,
      revision: announce ? session.revision + 1 : null,
    );
    if (announce) _emitSnapshotIfConformant();
    return live;
  }

  /// Applies an `exercise_push` from the phone: the slot it names lands at the
  /// position it names, and the user stays on the exercise they were logging.
  ///
  /// A message the watch cannot read is refused whole — no half-applied edit.
  /// A readable push that names a session the watch does not hold is dropped
  /// (D-79): it is not queued, and nothing is created for it.
  Future<WatchSessionRecord?> applyExercisePush(
    Map<String, Object?> envelope,
  ) async {
    _requireConformingIncoming(envelope);
    if (!_guardSession(envelope)) return null;
    final payload = asJsonObject(envelope['payload']);
    return insertExercise(
      asJsonObject(payload['exercise']),
      atIndex: payload['insertAtIndex']! as int,
      announce: false,
    );
  }

  // ---------------------------------------------------------------------------
  // Messages from the phone
  // ---------------------------------------------------------------------------

  /// Applies one message from the phone to the live session.
  ///
  /// This is the watch's half of the reconciliation contract: the same messages
  /// the phone's reference reconciler
  /// (`lib/core/sync_protocol/session_reconciler.dart`) applies, applied to the
  /// append-only store instead of to memory. Applying the same message twice
  /// changes nothing — structure changes are keyed by `changeId`, and every
  /// row a message writes carries an id derived from the message itself.
  ///
  /// Cross-stack conformance verified by
  /// `test/watch_reconciliation_cross_stack_test.dart`. Do not change these
  /// rules without running that test: it replays every reconciliation fixture
  /// through this engine and through the phone's reconciler and fails if the two
  /// converge on different structure.
  ///
  /// Returns true when the message changed something the watch holds, false
  /// when it had nothing for this session (reference data, or an observation —
  /// which only ever travels the other way). A message the watch cannot read is
  /// refused whole: [WatchEmissionRejected] is thrown and nothing is applied.
  Future<bool> applyMessage(Map<String, Object?> envelope) async {
    switch (envelope['type']) {
      case 'session_snapshot':
        _requireConformingIncoming(envelope);
        return _applySnapshot(envelope);
      case 'structure_change':
        _requireConformingIncoming(envelope);
        return _applyStructureChange(envelope);
      case 'session_lifecycle':
        _requireConformingIncoming(envelope);
        return _applyLifecycle(envelope);
      case 'timer_state':
        _requireConformingIncoming(envelope);
        return _applyTimerState(envelope);
      case 'exercise_push':
        final before = _session;
        final after = await applyExercisePush(envelope);
        return after != null && !identical(before, after);
      case 'receipt':
        _requireConformingIncoming(envelope);
        return _applyReceipt(envelope);
      case 'observations_up':
        // The watch's own product; a phone has no business sending one. It is
        // still read, so a peer speaking another version is refused here rather
        // than quietly ignored (PROTOCOL.md, "Versioning policy").
        _requireConformingIncoming(envelope);
        return false;
      default:
        return false;
    }
  }

  /// A snapshot replaces structure, status, position, revision, and timer state;
  /// entries merge by `entryId` (PROTOCOL.md, "Idempotency and reconciliation").
  ///
  /// Merging is what makes a wrist log survive the phone's snapshot: an
  /// observation the phone has not seen is still the watch's, and the entries
  /// the snapshot carries are the phone's — stored here as confirmed, because
  /// the phone obviously has them. The snapshot is also the receipt for
  /// observations it does carry: the watch may drop them.
  Future<bool> _applySnapshot(Map<String, Object?> envelope) async {
    final payload = asJsonObject(envelope['payload']);
    final sessionId = payload['sessionId']! as String;
    final exercises = [
      for (final slot in payload['exercises']! as List) asJsonObject(slot),
    ];
    final entryMaps = [
      for (final entry in payload['entries']! as List) asJsonObject(entry),
    ];
    final sentAt = parseUtcIso(envelope['sentAt']);
    final messageId = envelope['messageId']! as String;
    final existing = _session?.sessionId == sessionId ? _session : null;

    // A snapshot naming another session is refused whole while the wrist is
    // running a workout of its own: the user is in the middle of it, and
    // nothing — no row, no message — may come of a frame that is not about it
    // (D-78). The same snapshot still applies when the wrist holds nothing, or
    // holds a session that has already ended: that is the ordinary case of the
    // phone's next workout arriving.
    final held = _session;
    if (held != null &&
        held.status == WatchSessionStatus.active &&
        held.exercises.isNotEmpty &&
        held.sessionId != sessionId) {
      return false;
    }

    // D-113.2: an entry the snapshot carries exists, so its tombstone is
    // cleared — here, before the row that records this state is written, since
    // that row is what [restore] reads the lens back from.
    for (final entry in entryMaps) {
      _unhideTheIdTheSnapshotNames(entry);
    }

    final row = WatchSessionRecord(
      recordId: '$_snapshotPrefix$messageId',
      sessionId: sessionId,
      recordedAt: sentAt,
      startedAt:
          existing?.startedAt ?? _startedAtOf(entryMaps, fallback: sentAt),
      modality: existing?.modality,
      source: existing?.source ?? 'phone',
      status: payload['status']! as String,
      currentExerciseIndex: _clampIndex(
        payload['currentExerciseIndex']! as int,
        exercises.length,
      ),
      exercises: exercises,
      revision: payload['revision']! as int,
    );
    await _appendSessionRow(row, lifecycle: null);

    for (final entry in entryMaps) {
      await _storeSnapshotEntry(sessionId, entry);
    }
    await confirmObservations([
      for (final entry in entryMaps) entry['entryId']! as String,
    ]);
    await _adoptTimers(
      asJsonObject(payload['timers']),
      sessionId: sessionId,
      messageId: messageId,
      recordedAt: sentAt,
      authoritative: true,
    );
    return true;
  }

  /// Applies one structure change: the ladder, the position that follows from
  /// it, and the phone's corrections to entries the watch holds.
  ///
  /// A slot that is already present is left alone (a re-delivered push must not
  /// duplicate it), a removed slot never takes its entries with it, and a swap
  /// keeps the slot's id so entries logged against it still point at it.
  Future<bool> _applyStructureChange(Map<String, Object?> envelope) async {
    final payload = asJsonObject(envelope['payload']);
    final changeId = payload['changeId']! as String;
    final session = _session;
    if (!_guardSession(envelope)) return false;
    if (session == null) return false; // structure without a session is nothing
    if (!_appliedChangeIds.add(changeId)) return false;

    final ladder = _ladderAfter(
      session.exercises,
      session.currentExerciseIndex,
      [for (final change in payload['changes']! as List) asJsonObject(change)],
    );

    await _appendSessionRow(
      WatchSessionRecord(
        recordId: '$_changePrefix$changeId',
        sessionId: session.sessionId,
        recordedAt: _clock(),
        startedAt: session.startedAt,
        modality: session.modality,
        source: session.source,
        status: session.status,
        currentExerciseIndex: ladder.index,
        exercises: ladder.exercises,
        revision: session.revision + 1,
      ),
      lifecycle: null,
    );
    return true;
  }

  /// Applies a lifecycle message from the phone: the most recent status wins,
  /// and an advanced position clamps to the ladder (PROTOCOL.md, "Idempotency
  /// and reconciliation").
  ///
  /// Nothing is echoed back — the phone is telling the watch what it decided,
  /// and answering it with the same news would be noise.
  Future<bool> _applyLifecycle(Map<String, Object?> envelope) async {
    final session = _session;
    if (!_guardSession(envelope)) return false;
    if (session == null) return false;

    final payload = asJsonObject(envelope['payload']);
    final state = payload['state']! as String;
    final status = switch (state) {
      WatchLifecycleState.started => WatchSessionStatus.active,
      WatchLifecycleState.completed => WatchSessionStatus.completed,
      WatchLifecycleState.abandoned => WatchSessionStatus.abandoned,
      _ => session.status,
    };
    final index = state == WatchLifecycleState.exerciseAdvanced
        ? _clampIndex(
            payload['exerciseIndex']! as int,
            session.exercises.length,
          )
        : session.currentExerciseIndex;

    await _appendSessionRow(
      WatchSessionRecord(
        recordId: '$_lifecyclePrefix${envelope['messageId']}',
        sessionId: session.sessionId,
        recordedAt: parseUtcIso(envelope['sentAt']),
        startedAt: session.startedAt,
        modality: session.modality,
        source: session.source,
        status: status,
        currentExerciseIndex: index,
        exercises: session.exercises,
        revision: session.revision,
      ),
      lifecycle: null,
    );
    return true;
  }

  /// Applies an incremental timer update: the kinds it names are adopted or
  /// cleared, the kinds it does not name are left alone (PROTOCOL.md, "Timer
  /// state"). Only a snapshot is authoritative for timer state as a whole.
  Future<bool> _applyTimerState(Map<String, Object?> envelope) async {
    if (!_guardSession(envelope)) return false;
    final payload = asJsonObject(envelope['payload']);
    return _adoptTimers(
      asJsonObject(payload['timers']),
      sessionId: envelope['sessionId']! as String,
      messageId: envelope['messageId']! as String,
      recordedAt: parseUtcIso(envelope['sentAt']),
      authoritative: false,
    );
  }

  /// Adopts [timers] as the rows that apply. A kind the message names as `null`
  /// is cleared; a kind it does not name keeps whatever it had, unless the
  /// message is a snapshot and the newest row of that kind is the sender's —
  /// only a snapshot speaks for timer state as a whole, and even then only for
  /// the countdowns it wrote itself (D-80) (PROTOCOL.md, "Timer state").
  ///
  /// Every row's id is derived from the message that named it, so re-delivery is
  /// a no-op and a relaunch cannot tell the difference.
  Future<bool> _adoptTimers(
    Map<String, Object?> timers, {
    required String sessionId,
    required String messageId,
    required DateTime recordedAt,
    required bool authoritative,
  }) async {
    var changed = false;
    for (final kind in WatchTimerKind.all) {
      final recordId = '$_timerPrefix$messageId-$kind';
      final action = _timerActionFor(
        timers,
        kind: kind,
        authoritative: authoritative,
      );
      switch (action) {
        case _TimerAction.leaveAlone:
          continue;
        case _TimerAction.stop:
          changed |= await _stopTimerFromMessage(
            kind,
            sessionId: sessionId,
            recordId: recordId,
            stoppedAt: recordedAt,
          );
        case _TimerAction.adopt:
          changed |= await _adoptTimer(
            asJsonObject(timers[kind]),
            sessionId,
            recordId: recordId,
            recordedAt: recordedAt,
          );
      }
    }
    return changed;
  }

  /// What [timers] says about one kind: unnamed means "leave it" unless the
  /// message is a snapshot and the row it would stop is the sender's own, and a
  /// named `null` means "stop it" either way.
  _TimerAction _timerActionFor(
    Map<String, Object?> timers, {
    required String kind,
    required bool authoritative,
  }) {
    if (!timers.containsKey(kind)) {
      return authoritative && _senderWroteTimer(kind)
          ? _TimerAction.stop
          : _TimerAction.leaveAlone;
    }
    return timers[kind] == null ? _TimerAction.stop : _TimerAction.adopt;
  }

  /// Whether a phone's session-scoped frame applies at all (D-79): it must name
  /// the session the watch holds. A frame that names none, or names another
  /// one, is refused whole — nothing applied, nothing stored, nothing emitted.
  bool _guardSession(Map<String, Object?> envelope) {
    final held = _session;
    final sessionId = envelope['sessionId'];
    if (held == null || sessionId is! String) return false;
    return sessionId == held.sessionId;
  }

  /// Whether the newest row of [kind] is one a phone message wrote — the rows
  /// whose id is derived from the message that named them (D-80).
  bool _senderWroteTimer(String kind) =>
      _newestTimer(kind: kind)?.recordId.startsWith(_timerPrefix) ?? false;

  /// A timer the phone told the watch about. It is not news back to the phone,
  /// so nothing is emitted: the phone already decided this.
  Future<bool> _adoptTimer(
    Map<String, Object?> timer,
    String sessionId, {
    required String recordId,
    required DateTime recordedAt,
  }) async {
    if (_timers.any((row) => row.recordId == recordId)) return false;

    final stored = await _store.append(
      WatchTimerRecord(
        recordId: recordId,
        sessionId: sessionId,
        recordedAt: recordedAt,
        kind: timer['kind']! as String,
        startedAt: parseUtcIso(timer['startedAt']),
        pausedAt: parseOptionalUtcIso(timer['pausedAt']),
        stoppedAt: parseOptionalUtcIso(timer['stoppedAt']),
        accumulatedPauseMs: (timer['accumulatedPauseMs'] as int?) ?? 0,
        plannedDurationMs: timer['plannedDurationMs'] as int?,
      ),
    );
    _timers.add(stored);
    return true;
  }

  /// Stops the newest timer of [kind] by appending its stopped version — the
  /// row that was running is never rewritten.
  ///
  /// The protocol calls this clearing a timer, but nothing here clears
  /// anything: a timer advances by append like every other synced record, and a
  /// store whose contract forbids mutation deserves method names that say so.
  Future<bool> _stopTimerFromMessage(
    String kind, {
    required String sessionId,
    required String recordId,
    required DateTime stoppedAt,
  }) async {
    final timer = _newestTimer(kind: kind);
    if (timer == null || timer.state == WatchTimerState.stopped) return false;
    if (timer.sessionId != sessionId) return false;
    if (_timers.any((row) => row.recordId == recordId)) return false;

    final stored = await _store.append(
      _timerRowFrom(
        timer,
        recordId: recordId,
        recordedAt: stoppedAt,
        stoppedAt: stoppedAt,
      ),
    );
    _timers.add(stored);
    return true;
  }

  /// Stores an entry the phone sent, in the shape the wrist shows it. Nothing
  /// is emitted: the phone is the source, and the receipt is [entries].
  ///
  /// An `entryId` the wrist already holds is **re-stated**: when the snapshot
  /// carries the same `loggedAt`, its payload folds into the projection
  /// [entries] reads, exactly as a `correct_entry` does, and the stored
  /// observation row is left alone — the log stays append-only, so re-stating a
  /// set the phone edited neither rewrites the row nor doubles it. The phone,
  /// receiving, keeps the first value it stored for an id it holds; only the
  /// wrist re-states.
  ///
  /// A re-stated id whose `loggedAt` **differs** is a different entry wearing a
  /// reused number, and replaces the held one outright (D-113.3). An id a
  /// deletion had hidden is shown again, because the phone saying it is there
  /// outranks the phone having said it was gone (D-113.2) — unless the snapshot
  /// only repeats the entry the wrist already holds, stamp and all.
  Future<void> _storeSnapshotEntry(
    String sessionId,
    Map<String, Object?> entry,
  ) async {
    final entryId = entry['entryId']! as String;
    // D-113.2: the phone is the structure authority, so an entry its snapshot
    // carries exists — whatever this watch was told about that id before.
    _unhideTheIdTheSnapshotNames(entry);
    if (_observations.any((row) => row.recordId == entryId)) {
      final held = _heldPayload(entryId);
      if (held != null && !_sameStamp(held['loggedAt'], entry['loggedAt'])) {
        // D-113.3: the phone mints the highest number + 1, so deleting the
        // newest set of a slot and logging another reuses its id for a
        // different entry. A merge would keep a field the new entry does not
        // carry — the dead entry's Load. The correction is the whole entry.
        _entryCorrections[entryId] = entry;
        _replacedEntryIds.add(entryId);
        return;
      }
      _entryCorrections[entryId] = {
        ...?_entryCorrections[entryId],
        ...entry,
      };
      _replacedEntryIds.remove(entryId);
      return;
    }

    final stored = await _store.append(
      WatchObservationRecord(
        recordId: entryId,
        sessionId: sessionId,
        recordedAt: parseUtcIso(entry['loggedAt']),
        kind: entry['kind']! as String,
        payload: entry,
      ),
    );
    _observations.add(stored);
  }

  /// Shows [entry]'s id again — the tombstone it carried no longer stands —
  /// when this snapshot entry outranks what the wrist holds (D-113.2).
  ///
  /// The phone is the structure authority, so an id its snapshot carries exists
  /// — but a snapshot entry that only repeats the row the wrist already holds,
  /// stamp and all, is the stale answer D-115 says the phone stops sending, and
  /// the deletion the wrist was told about is newer than it: the tombstone
  /// stays, and the projection keeps hiding the id (S-35 `a re-statement of a
  /// deleted id stays deleted`, `test/watch_session_projection_test.dart`). An
  /// id the wrist holds no row for, or one whose `loggedAt` differs — D-113.3's
  /// replacement — is the phone saying something new, and is shown again.
  void _unhideTheIdTheSnapshotNames(Map<String, Object?> entry) {
    final entryId = entry['entryId']! as String;
    final held = _heldPayload(entryId);
    if (held != null && _sameStamp(held['loggedAt'], entry['loggedAt'])) return;
    _deletedEntryIds.remove(entryId);
  }

  /// Whether two `loggedAt` values name the same instant (F5): both absent, or
  /// both a wire instant spelled the same.
  ///
  /// The Swift twin's `sameStamp` reads exactly this — `nil, nil` is the same
  /// stamp, and anything that is not a string on either side is not — so
  /// comparing the values with `==` would let a non-string stamp on one side
  /// answer differently in the two engines: this one would call two equal
  /// non-strings the same entry and hide the row D-113.3 replaces. Wire stamps
  /// are strings, so the rule is unchanged for them.
  static bool _sameStamp(Object? a, Object? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a is! String || b is! String) return false;
    return a == b;
  }

  /// The payload [entries] shows for [entryId] right now, before any deletion —
  /// the held row with the phone's correction folded in, or null when the wrist
  /// holds no row for it.
  Map<String, Object?>? _heldPayload(String entryId) {
    for (final row in _observations) {
      if (row.recordId != entryId) continue;
      final correction = _entryCorrections[entryId];
      return correction == null
          ? row.payload
          : {...row.payload, ...correction};
    }
    return null;
  }

  /// The session's entries in [entryMaps], oldest first — the moment the session
  /// began, as far as a snapshot can say. Falls back to when the snapshot was
  /// sent when it carries no entries.
  static DateTime _startedAtOf(
    List<Map<String, Object?>> entryMaps, {
    required DateTime fallback,
  }) {
    DateTime? earliest;
    for (final entry in entryMaps) {
      final loggedAt = parseUtcIso(entry['loggedAt']);
      if (earliest == null || loggedAt.isBefore(earliest)) earliest = loggedAt;
    }
    return earliest ?? fallback;
  }

  /// The ladder and position the changes so far have left behind.
  ///
  /// One change kind touches the ladder and the rest touch entries, so the pair
  /// travels together and only the ladder kinds rebuild it.
  ({List<Map<String, Object?>> exercises, int index}) _ladderAfter(
    List<Map<String, Object?>> exercises,
    int index,
    List<Map<String, Object?>> changes,
  ) {
    var ladder = (exercises: exercises, index: index);
    for (final change in changes) {
      switch (change['kind']) {
        case 'add_exercise':
          ladder = _insertSlotFromChange(ladder, change);
        case 'remove_exercise':
          ladder = _removeSlotFromChange(ladder, change);
        case 'reorder_exercises':
          ladder = _reorderSlotsFromChange(ladder, change);
        case 'swap_exercise':
          ladder = _swapSlotFromChange(ladder, change);
        case 'correct_entry':
          _applyCorrection(change);
        case 'delete_entry':
          _applyDeletion(change);
      }
    }
    return (
      exercises: ladder.exercises,
      index: _clampIndex(ladder.index, ladder.exercises.length),
    );
  }

  /// Adds the slot an `add_exercise` change names, at the index it names.
  ///
  /// A slot id that is already present makes this a no-op: a re-delivered change
  /// must not duplicate a slot, and replacing what a slot holds is
  /// `swap_exercise`'s job.
  static ({List<Map<String, Object?>> exercises, int index})
  _insertSlotFromChange(
    ({List<Map<String, Object?>> exercises, int index}) ladder,
    Map<String, Object?> change,
  ) {
    final slot = asJsonObject(change['exercise']);
    final slotId = slot['sessionExerciseId'];
    final exercises = ladder.exercises;
    if (slotId is String && _indexOfSlotId(exercises, slotId) >= 0) {
      return ladder;
    }

    final at = _insertionIndex(change['atIndex']! as int, exercises.length);
    return (
      exercises: [...exercises]..insert(at, slot),
      index: _positionAfterInsert(
        currentIndex: ladder.index,
        insertedAt: at,
        moveTo: false,
        wasEmpty: exercises.isEmpty,
      ),
    );
  }

  /// Removes the slot a `remove_exercise` change names. Entries logged against
  /// it are untouched — history is append-only — and the position stays on the
  /// exercise the user was on, which is the slot that followed when the removed
  /// one was the current one.
  static ({List<Map<String, Object?>> exercises, int index})
  _removeSlotFromChange(
    ({List<Map<String, Object?>> exercises, int index}) ladder,
    Map<String, Object?> change,
  ) {
    final at = _indexOfSlotId(
      ladder.exercises,
      change['sessionExerciseId']! as String,
    );
    if (at < 0) return ladder; // removing something already gone is a no-op

    final currentSlotId = _slotIdAt(ladder.exercises, ladder.index);
    final exercises = [...ladder.exercises]..removeAt(at);
    return (
      exercises: exercises,
      index: _positionOf(currentSlotId, exercises, fallback: ladder.index),
    );
  }

  /// Applies the order a `reorder_exercises` change names, leaving the position
  /// on the exercise the user was on.
  static ({List<Map<String, Object?>> exercises, int index})
  _reorderSlotsFromChange(
    ({List<Map<String, Object?>> exercises, int index}) ladder,
    Map<String, Object?> change,
  ) {
    final currentSlotId = _slotIdAt(ladder.exercises, ladder.index);
    final exercises = _reordered(
      ladder.exercises,
      (change['order']! as List).cast<String>(),
    );
    return (
      exercises: exercises,
      index: _positionOf(currentSlotId, exercises, fallback: ladder.index),
    );
  }

  /// Replaces what the slot a `swap_exercise` change names holds, and nothing
  /// else: the slot keeps its id, so the position does not move and entries
  /// logged against it still point at it.
  static ({List<Map<String, Object?>> exercises, int index})
  _swapSlotFromChange(
    ({List<Map<String, Object?>> exercises, int index}) ladder,
    Map<String, Object?> change,
  ) {
    final slotId = change['sessionExerciseId']! as String;
    final at = _indexOfSlotId(ladder.exercises, slotId);
    if (at < 0) return ladder;

    final exercises = [...ladder.exercises];
    exercises[at] = {
      ...asJsonObject(change['exercise']),
      'sessionExerciseId': slotId,
    };
    return (exercises: exercises, index: ladder.index);
  }

  /// Folds a `correct_entry` change into the projection [entries] reads. The
  /// stored observation is not touched — the phone owns history, and a correction
  /// is a lens over it rather than a rewrite.
  void _applyCorrection(Map<String, Object?> change) {
    final entryId = change['entryId']! as String;
    _entryCorrections[entryId] = {
      ...?_entryCorrections[entryId],
      ...asJsonObject(change['correction']),
    };
  }

  /// Drops a deleted entry from the projection, and any correction that pointed
  /// at it.
  void _applyDeletion(Map<String, Object?> change) {
    final entryId = change['entryId']! as String;
    _entryCorrections.remove(entryId);
    _replacedEntryIds.remove(entryId);
    _deletedEntryIds.add(entryId);
  }

  /// Where the position lands once the ladder has changed shape: on the slot it
  /// was on, when that slot survived, and clamped into range when it did not.
  static int _positionOf(
    String? sessionExerciseId,
    List<Map<String, Object?>> exercises, {
    required int fallback,
  }) {
    final at = sessionExerciseId == null
        ? -1
        : _indexOfSlotId(exercises, sessionExerciseId);
    return at >= 0 ? at : _clampIndex(fallback, exercises.length);
  }

  /// [exercises] reordered as [order] names them; slots it does not name keep
  /// their relative order after those it does.
  static List<Map<String, Object?>> _reordered(
    List<Map<String, Object?>> exercises,
    List<String> order,
  ) {
    final remaining = {
      for (final slot in exercises) slot['sessionExerciseId']! as String: slot,
    };

    final reordered = <Map<String, Object?>>[];
    for (final slotId in order) {
      final slot = remaining.remove(slotId);
      if (slot != null) reordered.add(slot);
    }
    reordered.addAll(remaining.values);
    return reordered;
  }

  static int _indexOfSlotId(
    List<Map<String, Object?>> exercises,
    String slotId,
  ) => exercises.indexWhere((slot) => slot['sessionExerciseId'] == slotId);

  static String? _slotIdAt(List<Map<String, Object?>> exercises, int index) =>
      exercises.isEmpty
      ? null
      : exercises[_clampIndex(index, exercises.length)]['sessionExerciseId']
            as String?;

  /// The position after inserting a slot: the position follows the exercise,
  /// not the index, so a slot inserted at or before the current one pushes the
  /// current one along with it. Computed rather than searched for, so there is
  /// no not-found case to fall back from.
  static int _positionAfterInsert({
    required int currentIndex,
    required int insertedAt,
    required bool moveTo,
    required bool wasEmpty,
  }) => moveTo || wasEmpty
      ? insertedAt
      : (currentIndex >= insertedAt ? currentIndex + 1 : currentIndex);

  /// Where an inserted slot lands: anywhere from the front of the ladder to
  /// after its last exercise — there is one more valid insertion point than
  /// there are exercises.
  static int _insertionIndex(int index, int length) => index.clamp(0, length);

  /// Where a position lands: always on an exercise that exists.
  static int _clampIndex(int index, int length) =>
      length == 0 ? 0 : index.clamp(0, length - 1).toInt();

  /// The order the wrist reads entries in: when they were logged, and by id when
  /// two share an instant — the same deterministic order the phone's reconciler
  /// uses.
  static int _byLoggedAtThenEntryId(
    WatchObservationRecord a,
    WatchObservationRecord b,
  ) {
    final byLoggedAt = (a.payload['loggedAt']! as String).compareTo(
      b.payload['loggedAt']! as String,
    );
    return byLoggedAt != 0 ? byLoggedAt : a.entryId.compareTo(b.entryId);
  }

  /// The timers that apply, as the protocol's `timers` object: the newest of
  /// each kind, and only while it is running or paused.
  Map<String, Object?> _timersJson() {
    final timers = <String, Object?>{};
    for (final kind in WatchTimerKind.all) {
      final timer = _newestTimer(kind: kind);
      if (timer != null && timer.state != WatchTimerState.stopped) {
        timers[kind] = timer.toTimerJson();
      }
    }
    return timers;
  }

  /// Writes a new session row carrying [status] and [currentExerciseIndex].
  ///
  /// A state change appends rather than updates, which is what both keeps the
  /// store append-only and makes the position survive a kill. [revision] moves
  /// the structure counter when a shape change the wrist made itself needs
  /// announcing; a change that is not the shape (a status or a position) keeps
  /// the session's own revision (D-101).
  Future<WatchSessionRecord> _transitionTo({
    String? status,
    int? currentExerciseIndex,
    List<Map<String, Object?>>? exercises,
    int? revision,
    required String? lifecycle,
  }) async {
    final session = _requireSession();
    return _appendSessionRow(
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
        exercises: exercises ?? session.exercises,
        revision: revision ?? session.revision,
      ),
      lifecycle: lifecycle,
    );
  }

  /// Appends [row], and announces the lifecycle change through the message sink.
  ///
  /// A status change is not an observation: the state is the product and the
  /// message is its mirror, so an announcement this build could not send is
  /// dropped rather than blocking the session the user is in the middle of. The
  /// suites pin the shape, so a drift fails there instead of going quiet.
  Future<WatchSessionRecord> _appendSessionRow(
    WatchSessionRecord row, {
    required String? lifecycle,
  }) async {
    // Every row carries the lens as it stands, not only the row a structure
    // change writes: a lifecycle row appended after a delete would otherwise be
    // the newest one, and [restore] would read an empty lens back from it
    // (D-113.1).
    final carried = {
      ...row.deletedEntryIds,
      ..._deletedEntryIds,
    }.toList(growable: false);

    final existing = _sessionRows.any(
      (stored) => stored.recordId == row.recordId,
    );
    final stored = await _store.append(row.withDeletedEntryIds(carried));
    if (!existing) _sessionRows.add(stored);
    _session = stored;
    if (lifecycle != null) _emitLifecycleIfConformant(stored, lifecycle);
    return stored;
  }

  void _emitLifecycleIfConformant(WatchSessionRecord row, String state) {
    final envelope = _lifecycle(row, state);
    final rejections =
        _validator?.validateEnvelope(envelope) ??
        const <SyncProtocolRejection>[];
    if (rejections.isNotEmpty) return;
    _emit(envelope);
  }

  /// Announces the session's current shape to the phone (D-90): the snapshot
  /// [sessionSnapshot] already builds. A snapshot this build cannot send is
  /// dropped rather than blocking the session the user is in.
  void _emitSnapshotIfConformant() {
    final Map<String, Object?>? envelope;
    try {
      envelope = sessionSnapshot(); // throws on a non-conformant envelope
    } on Exception {
      return;
    }
    if (envelope == null) return;
    _emit(envelope);
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
    return _appendObservation(event, sessionId: session.sessionId);
  }

  /// Persists a food the user quick-logged, and emits it for the phone.
  ///
  /// The one entry point on the wrist that does not need a session: eating is
  /// not a training event, and the surface is reachable with no workout
  /// running (S-006). A log taken while a session is running rides it — a snack
  /// mid-workout is part of that session's story — and one taken without a
  /// session carries the nutrition log's own id, because `observations_up`
  /// requires a session id and the wrist will not invent a workout
  /// ([WatchNutritionSession]).
  ///
  /// [servings] is the portion as a multiple of the food's reference amount,
  /// and [calories] what the phone quoted for it — the event is
  /// self-contained, so the phone materialises the entry without asking the
  /// wrist a question.
  Future<WatchObservationRecord> logNutrition({
    required String foodId,
    required double servings,
    double? calories,
    DateTime? loggedAt,
  }) {
    final now = loggedAt ?? _clock();
    final entryId = _newId();
    return _appendObservation({
      'entryId': entryId,
      'eventId': entryId,
      'kind': WatchObservationKind.nutritionQuickLog,
      'loggedAt': utcIso(now),
      'foodId': foodId,
      'servings': servings,
      'calories': ?calories,
    }, sessionId: _session?.sessionId ?? WatchNutritionSession.idFor(now));
  }

  /// The nutrition quick-logs the wrist has taken, oldest first — every
  /// session's, because the surface is reachable with none.
  ///
  /// Read back out of the rows storage already held, which is what makes the
  /// food that moves to the top of the wrist's list survive a relaunch.
  List<WatchObservationRecord> get nutritionLog => List.unmodifiable([
    for (final observation in _observations)
      if (observation.kind == WatchObservationKind.nutritionQuickLog)
        observation,
  ]);

  /// Storage first, emission second — the order every log on the watch follows.
  Future<WatchObservationRecord> _appendObservation(
    Map<String, Object?> event, {
    required String sessionId,
  }) async {
    final eventId = event['eventId'];
    final recordId = eventId is String && eventId.isNotEmpty
        ? eventId
        : _newId();
    final now = _clock();

    final record = WatchObservationRecord(
      recordId: recordId,
      sessionId: sessionId,
      recordedAt: now,
      kind: (event['kind'] as String?) ?? '',
      payload: event,
    );

    final envelope = _observationsUp(
      sessionId,
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

  /// Persists a reading the platform sensors produced.
  ///
  /// Storage first, and nothing emitted: a sensor reading is the watch's own
  /// measurement, and the distance that reaches the phone travels as the
  /// `distanceMeters` of the effort logged against it. Appending the same
  /// reading twice — same kind, same instant — is a store no-op, which is what
  /// keeps a duplicated sensor callback from becoming a second row.
  Future<WatchSensorSampleRecord> appendSensorSample({
    required String kind,
    required double value,
    DateTime? recordedAt,
  }) async {
    final session = _requireSession();
    final now = recordedAt ?? _clock();

    final record = WatchSensorSampleRecord(
      recordId: WatchSensorSampleRecord.sampleId(
        sessionId: session.sessionId,
        kind: kind,
        at: now,
      ),
      sessionId: session.sessionId,
      recordedAt: now,
      kind: kind,
      value: value,
    );

    final existing = _sensorSamples.any(
      (row) => row.recordId == record.recordId,
    );
    final stored = await _store.append(record);
    if (!existing) _sensorSamples.add(stored);
    return stored;
  }

  /// The messages the phone still owes a receipt for, rebuilt from storage.
  ///
  /// Emission is not a hand-off of state: it is a projection of the stored
  /// rows, so replaying after a kill sends the same events with the same
  /// identifiers. A nutrition quick-log taken with no session (S-006) is owed
  /// just like an in-session one, and carries the id it was stored under.
  List<Map<String, Object?>> pendingObservations() {
    final session = _session;
    return [
      if (session != null)
        for (final observation in observations)
          if (observation.confirmedAt == null)
            _observationsUp(
              session.sessionId,
              observation,
              sentAt: observation.recordedAt,
              messageId: _messageIdFor(observation.recordId),
            ),
      for (final observation in nutritionLog)
        if (observation.confirmedAt == null &&
            observation.sessionId != session?.sessionId)
          _observationsUp(
            observation.sessionId,
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
  ///
  /// [recordId] is supplied when the row comes from a message rather than from
  /// the wrist, so the id can be derived from the message and be replayable.
  WatchTimerRecord _timerRowFrom(
    WatchTimerRecord timer, {
    required DateTime recordedAt,
    String? recordId,
    DateTime? pausedAt,
    bool clearPause = false,
    int? accumulatedPauseMs,
    DateTime? stoppedAt,
  }) => WatchTimerRecord(
    recordId: recordId ?? _newId(),
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
        // A receipt names the session it belongs to; a standalone nutrition
        // quick-log has none, so the row's own id stands in.
        sessionId: _session?.sessionId ?? acknowledged.first.sessionId,
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
    // D-52: a pruned row takes its projection lens with it. A correction or
    // deletion marker left behind would override or hide the fresh row when the
    // same id is re-carried.
    for (final recordId in dropped) {
      _entryCorrections.remove(recordId);
      _replacedEntryIds.remove(recordId);
      _deletedEntryIds.remove(recordId);
    }
    return pruned;
  }

  /// Drops the raw sensor log of every session that is over and whose entries
  /// the phone has recorded in full.
  ///
  /// Raw readings are not gated on a receipt of their own — the phone never
  /// receives one, and its mirror has no field for them. What gates them is the
  /// session: once a finished session's entries have all been acknowledged, the
  /// readings that produced them have done their job, and the distance they
  /// measured has already crossed as the logged effort's `distanceMeters`. A
  /// session still running, or one with an entry still awaiting a receipt, keeps
  /// its log — which is what makes the live readout and the settled distance
  /// survive a kill.
  Future<List<String>> pruneSettledSensorSamples() async {
    final settled = [
      for (final session in _newestSessionRows().values)
        if (session.status != WatchSessionStatus.active &&
            !_awaitsReceipt.contains(session.sessionId) &&
            _sensorSamples.any((row) => row.sessionId == session.sessionId))
          session.sessionId,
    ];
    if (settled.isEmpty) return const [];

    final pruned = await _store.pruneSensorSamples(settled);
    final dropped = pruned.toSet();
    _sensorSamples.removeWhere((row) => dropped.contains(row.recordId));
    return pruned;
  }

  /// The session ids with an observation the phone has not acknowledged. A
  /// session on this list has not reached the phone in full, so nothing of it
  /// may be dropped.
  Set<String> get _awaitsReceipt => {
    for (final observation in _observations)
      if (observation.confirmedAt == null) observation.sessionId,
  };

  /// The current version of each session the store holds, by session id — the
  /// newest row wins, exactly as [restore] reduces the session the watch is on.
  Map<String, WatchSessionRecord> _newestSessionRows() {
    final newest = <String, WatchSessionRecord>{};
    for (final row in _sessionRows) {
      final current = newest[row.sessionId];
      if (current == null || row.sequence > current.sequence) {
        newest[row.sessionId] = row;
      }
    }
    return newest;
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

  /// The session's own state change, as the phone's mirror reads it. The index
  /// travels only with `exercise_advanced` — the schema allows it nowhere else.
  Map<String, Object?> _lifecycle(WatchSessionRecord row, String state) => {
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': _messageIdFor(row.recordId),
    'sessionId': row.sessionId,
    'type': 'session_lifecycle',
    'origin': 'watch',
    'sentAt': utcIso(row.recordedAt),
    'payload': {
      'state': state,
      'at': utcIso(row.recordedAt),
      if (state == WatchLifecycleState.exerciseAdvanced)
        'exerciseIndex': row.currentExerciseIndex,
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

  /// Refuses to apply anything this watch cannot read — version first, then
  /// conformance. A message from a peer speaking another version is rejected
  /// without being interpreted (PROTOCOL.md, "Versioning policy").
  void _requireConformingIncoming(Map<String, Object?> envelope) {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (decision.accepted) return;

    throw WatchEmissionRejected(
      message: 'refusing to apply a non-conformant message: ${decision.reason}',
      rejections: decision.rejections,
    );
  }

  /// Applies the phone's acknowledgement of the observations it has taken on.
  ///
  /// A receipt is the one message about entries that is not session state: a
  /// quick-log taken with no workout running names a session the phone does not
  /// hold, so the snapshot — the other way the watch learns an entry arrived —
  /// can never carry it back. Without this the wrist would owe those rows for
  /// the life of the install and could never prune them.
  ///
  /// Only the ids it names are confirmed; an id the watch does not hold is not
  /// an error, it is news about another client's log.
  Future<bool> _applyReceipt(Map<String, Object?> envelope) async {
    final payload = asJsonObject(envelope['payload']);
    final entryIds = [
      for (final id in payload['entryIds']! as List) id! as String,
    ];
    return (await confirmObservations(entryIds)).isNotEmpty;
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

/// What a `timer_state` or snapshot message asks of one timer kind.
enum _TimerAction {
  /// Adopt the timer the message names.
  adopt,

  /// Stop the kind's timer — either the message named it as `null`, or the
  /// message is a snapshot and left the kind out.
  stop,

  /// An incremental message said nothing about this kind: leave it running.
  leaveAlone,
}
