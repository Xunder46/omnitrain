/// Watch↔phone sync protocol reference reconciler.
///
/// Applies protocol messages to the live session and exposes the converged
/// state — the exact semantics the fixtures in
/// `watch/sync_protocol/fixtures/` pin down, and the reference the native
/// watchOS and Wear OS clients are checked against.
///
/// Exercises are addressed by `sessionExerciseId` (the slot), never by
/// `exerciseId`: a session may hold the same exercise in two slots.
///
/// Pure Dart, no dependencies. Callers MUST gate on the protocol version before
/// applying anything (see `SyncProtocolValidator.evaluateIncoming`); this class
/// implements the apply rules of protocol v1 and assumes schema-conformant
/// payloads.
///
/// **Cross-stack conformance verified by
/// `test/watch_reconciliation_cross_stack_test.dart`.** Do not change these
/// rules without running that test: it replays every reconciliation fixture
/// through this reconciler and through the wrist's engine
/// (`lib/watch/session/watch_session_engine.dart`) and fails if the two converge
/// on different structure.
library;

/// The converged session: structure from the phone, entries from everyone.
class SyncSessionReconciler {
  SyncSessionReconciler.fromSnapshot(Map<String, Object?> snapshot) {
    _applySnapshot(snapshot);
  }

  final List<Map<String, Object?>> _exercises = [];

  /// Entries keyed by entryId — the id and the eventId that produced it are the
  /// two halves of the idempotency guarantee.
  final Map<String, Map<String, Object?>> _entries = {};

  /// Timer per kind; an explicit `null` means "this timer is cleared".
  final Map<String, Map<String, Object?>?> _timers = {};

  final Set<String> _appliedEventIds = {};
  final Set<String> _appliedChangeIds = {};

  // Assigned by `_applySnapshot`, which the only constructor calls. The
  // session id is null only until then.
  String? _sessionId;
  late String _status;
  late int _revision;
  late int _currentExerciseIndex;

  /// Applies one schema-conformant message. Applying the same message twice
  /// changes nothing.
  void applyMessage(Map<String, Object?> message) {
    final payload = _asObject(message['payload']);
    switch (message['type']) {
      case 'session_snapshot':
        _applySnapshot(payload);
      case 'observations_up':
        for (final event in payload['events']! as List) {
          _addEntry(_asObject(event));
        }
      case 'exercise_push':
        _insertExercise(
          _asObject(payload['exercise']),
          payload['insertAtIndex']! as int,
        );
      case 'structure_change':
        _applyStructureChange(payload);
      case 'timer_state':
        _applyTimers(_asObject(payload['timers']!), authoritative: false);
      case 'session_lifecycle':
        _applyLifecycle(payload);
      // routines_down carries reference data, not session state.
    }
  }

  /// The converged session, in a deterministic shape: exercises in session
  /// order, entries ordered by `loggedAt` then `entryId`, timers sorted by kind.
  /// `revision` counts applied structure changes.
  Map<String, Object?> convergedState() {
    final entries = _entries.values.toList()..sort(_byLoggedAtThenEntryId);

    final timers = <String, Object?>{};
    for (final kind in _timers.keys.toList()..sort()) {
      final timer = _timers[kind];
      if (timer != null) timers[kind] = Map<String, Object?>.of(timer);
    }

    return {
      'sessionId': _sessionId,
      'status': _status,
      'revision': _revision,
      'currentExerciseIndex': _currentExerciseIndex,
      'exercises': [
        for (final exercise in _exercises) Map<String, Object?>.of(exercise),
      ],
      'entries': [for (final entry in entries) Map<String, Object?>.of(entry)],
      'timers': timers,
    };
  }

  // ---------------------------------------------------------------------------
  // Reconciliation
  // ---------------------------------------------------------------------------

  /// A snapshot is authoritative for structure, status, position, revision, and
  /// timers. Entries are merged by entryId, so an observation the phone has not
  /// seen yet survives the snapshot that arrives before it.
  ///
  /// That merge is for one session only. A snapshot that names another session
  /// replaces the held one wholesale, entries included: a second workout
  /// started on the wrist is not a continuation of the first, and merging would
  /// file the first session's entries under the second.
  void _applySnapshot(Map<String, Object?> snapshot) {
    final sessionId = snapshot['sessionId']! as String;
    if (sessionId != _sessionId) {
      _entries.clear();
      _appliedEventIds.clear();
    }

    _sessionId = sessionId;
    _status = snapshot['status']! as String;
    _revision = snapshot['revision']! as int;
    _currentExerciseIndex = snapshot['currentExerciseIndex']! as int;

    _exercises
      ..clear()
      ..addAll((snapshot['exercises']! as List).map(_asObject));

    for (final entry in snapshot['entries']! as List) {
      _addEntry(_asObject(entry));
    }

    _applyTimers(_asObject(snapshot['timers']!), authoritative: true);
  }

  void _applyTimers(
    Map<String, Object?> timers, {
    required bool authoritative,
  }) {
    if (authoritative) _timers.clear();
    for (final entry in timers.entries) {
      final timer = entry.value;
      _timers[entry.key] = timer == null ? null : _asObject(timer);
    }
  }

  void _applyLifecycle(Map<String, Object?> payload) {
    switch (payload['state']) {
      case 'started':
        _status = 'active';
      case 'exercise_advanced':
        _currentExerciseIndex = _validIndex(payload['exerciseIndex']! as int);
      case 'completed':
        _status = 'completed';
      case 'abandoned':
        _status = 'abandoned';
    }
  }

  void _addEntry(Map<String, Object?> entry) {
    if (_entries.containsKey(entry['entryId']! as String)) return;
    if (!_appliedEventIds.add(entry['eventId']! as String)) return;
    _entries[entry['entryId']! as String] = Map<String, Object?>.of(entry);
  }

  // ---------------------------------------------------------------------------
  // Structure — the phone's to own, the watch's to reflect
  // ---------------------------------------------------------------------------

  void _applyStructureChange(Map<String, Object?> payload) {
    if (!_appliedChangeIds.add(payload['changeId']! as String)) return;
    for (final change in payload['changes']! as List) {
      _applyChange(_asObject(change));
    }
    _revision++;
  }

  void _applyChange(Map<String, Object?> change) {
    switch (change['kind']) {
      case 'add_exercise':
        _insertExercise(
          _asObject(change['exercise']),
          change['atIndex']! as int,
        );
      case 'remove_exercise':
        _removeExercise(change['sessionExerciseId']! as String);
      case 'reorder_exercises':
        _reorderExercises((change['order']! as List).cast<String>());
      case 'swap_exercise':
        _swapExercise(
          change['sessionExerciseId']! as String,
          _asObject(change['exercise']),
        );
      case 'correct_entry':
        _entries[change['entryId']! as String]?.addAll(
          _asObject(change['correction']),
        );
      case 'delete_entry':
        _entries.remove(change['entryId']! as String);
    }
  }

  /// Adds a slot. A slot id that is already present makes this a no-op: a
  /// re-delivered `exercise_push` must not duplicate a slot, and changing what
  /// a slot holds is `swap_exercise`'s job. Because only this method and
  /// `_applySnapshot` ever add slots — and the validator rejects a snapshot
  /// whose slot ids repeat — slot ids stay unique, which is what makes
  /// `_reorderExercises` safe to key by slot id.
  void _insertExercise(Map<String, Object?> exercise, int atIndex) {
    final slotId = exercise['sessionExerciseId']! as String;
    if (_indexOfSlot(slotId) >= 0) return;

    final currentSlotId = _currentSlotId;
    _exercises.insert(atIndex.clamp(0, _exercises.length).toInt(), exercise);
    _pointAt(currentSlotId ?? slotId);
  }

  /// Removing an exercise never removes the entries logged against it — history
  /// is append-only. If it was the current one, the position moves to the next
  /// valid exercise.
  void _removeExercise(String sessionExerciseId) {
    final index = _indexOfSlot(sessionExerciseId);
    if (index < 0) return; // removing something already gone is a no-op
    _exercises.removeAt(index);
    if (index == _currentExerciseIndex) {
      _currentExerciseIndex = _validIndex(_currentExerciseIndex);
    } else if (index < _currentExerciseIndex) {
      _currentExerciseIndex--;
    }
  }

  /// Reorders the slots named by [order]; slots it does not name keep their
  /// relative order after those that it does. Safe to key by slot id because
  /// slot ids are unique — see `_insertExercise`.
  void _reorderExercises(List<String> order) {
    final currentSlotId = _currentSlotId;
    final unlisted = {
      for (final exercise in _exercises)
        exercise['sessionExerciseId']! as String: exercise,
    };

    final reordered = <Map<String, Object?>>[];
    for (final slotId in order) {
      final exercise = unlisted.remove(slotId);
      if (exercise != null) reordered.add(exercise);
    }
    reordered.addAll(unlisted.values); // unlisted exercises keep their order

    _exercises
      ..clear()
      ..addAll(reordered);
    if (currentSlotId != null) _pointAt(currentSlotId);
  }

  /// A swap replaces what the slot holds and nothing else — the slot keeps its
  /// id, so entries logged against it still point at it, and the position does
  /// not move.
  void _swapExercise(String sessionExerciseId, Map<String, Object?> exercise) {
    final index = _indexOfSlot(sessionExerciseId);
    if (index < 0) return;
    _exercises[index] = {...exercise, 'sessionExerciseId': sessionExerciseId};
  }

  /// Points the session at the slot [sessionExerciseId] names, falling back to
  /// the nearest valid position when it is gone.
  void _pointAt(String sessionExerciseId) {
    final index = _indexOfSlot(sessionExerciseId);
    _currentExerciseIndex = index >= 0
        ? index
        : _validIndex(_currentExerciseIndex);
  }

  int _indexOfSlot(String sessionExerciseId) => _exercises.indexWhere(
    (exercise) => exercise['sessionExerciseId'] == sessionExerciseId,
  );

  String? get _currentSlotId => _exercises.isEmpty
      ? null
      : _exercises[_validIndex(_currentExerciseIndex)]['sessionExerciseId']!
            as String;

  int _validIndex(int index) =>
      _exercises.isEmpty ? 0 : index.clamp(0, _exercises.length - 1).toInt();

  static int _byLoggedAtThenEntryId(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final byLoggedAt = (a['loggedAt']! as String).compareTo(
      b['loggedAt']! as String,
    );
    return byLoggedAt != 0
        ? byLoggedAt
        : (a['entryId']! as String).compareTo(b['entryId']! as String);
  }
}

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();
