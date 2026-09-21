/// The phone's live session mirror: what keeps the phone's view of a
/// watch-led session current without the watch being asked anything.
///
/// Plan: `.github/agents/plans/2026-07-13-09-c1-live-session-mirroring-plan.md`.
///
/// The reconciliation itself is the protocol's reference implementation
/// (`lib/core/sync_protocol/session_reconciler.dart`); this class is the wiring
/// around it — validate first, apply, then notify, so the live session view
/// re-renders on a change rather than on a poll. A message this build cannot
/// read is refused whole and answered with the phone's own snapshot, so the
/// watch converges from what the session actually is rather than from a stream
/// nobody could interpret (PROTOCOL.md, "Versioning policy").
///
/// Authority is the protocol's: structure is the phone's to own, entries come
/// from whoever logged them, and every apply is idempotent — a transport that
/// delivers the same event twice is indistinguishable from one that delivers it
/// once.
library;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/sync_protocol/message_validator.dart';
import '../../core/sync_protocol/session_reconciler.dart';
import '../../core/sync_protocol/timer_derivation.dart';
import '../../watch/session/watch_records.dart';

/// What [LiveSessionMirrorState] needs from whatever carries messages to the
/// watch (WatchConnectivity on iOS, the Wear OS data layer, or a test double).
///
/// There is no reachability flag here on purpose: the transport is
/// fire-and-forget with retries, so a send that cannot be carried yet is the
/// transport's problem to buffer, not a decision the session logic should make.
abstract interface class WatchMirrorTransport {
  /// Hands the watch one message.
  Future<void> send(Map<String, Object?> envelope);

  /// Asks the watch for its `session_snapshot`; the reply arrives through
  /// [LiveSessionMirrorState.receive], exactly as any other message does.
  Future<void> requestSnapshot();
}

/// What [LiveSessionMirrorState.receive] did with a message.
enum MirrorOutcome {
  /// Consumed into the converged session. A re-delivered message lands here
  /// too: it was consumed, it just changed nothing.
  applied,

  /// Conformant, and nothing this mirror consumes — reference data for another
  /// surface.
  ignored,

  /// This build could not read it. Nothing was applied, and the watch was
  /// answered with the phone's snapshot.
  refused,
}

class LiveSessionMirrorState extends ChangeNotifier {
  LiveSessionMirrorState({
    required WatchMirrorTransport transport,
    required Map<String, Object?> snapshot,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) : _transport = transport,
       _validator = validator,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid,
       _reconciler = SyncSessionReconciler.fromSnapshot(snapshot);

  static const Uuid _uuidV4 = Uuid();

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String _uuid() => _uuidV4.v4();

  final WatchMirrorTransport _transport;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;
  final String Function() _newId;
  final SyncSessionReconciler _reconciler;

  /// The session as the phone closed it. Null while it is running.
  Map<String, Object?>? _completedRecord;

  // ---------------------------------------------------------------------------
  // What the surface reads
  // ---------------------------------------------------------------------------

  /// The converged session: structure from this phone, entries from everyone,
  /// timers as wall-clock state.
  Map<String, Object?> get state => _reconciler.convergedState();

  /// The session's identity, as both devices know it.
  String? get sessionId => state['sessionId'] as String?;

  /// The protocol's status for the session — `active`, `completed`, or
  /// `abandoned`.
  String? get status => state['status'] as String?;

  /// Whether the session is still running on the wrist.
  bool get isActive => status == WatchSessionStatus.active;

  /// Where in the ladder the session is.
  int get currentExerciseIndex => (state['currentExerciseIndex'] as int?) ?? 0;

  /// The ladder, in session order.
  List<Map<String, Object?>> get exercises => _objects(state['exercises']);

  /// Every entry either device logged, ordered by wall-clock `loggedAt` then
  /// `entryId`.
  List<Map<String, Object?>> get entries => _objects(state['entries']);

  /// The exercise the session is on, or null when the ladder is empty.
  Map<String, Object?>? get currentExercise {
    final ladder = exercises;
    if (ladder.isEmpty) return null;
    return ladder[currentExerciseIndex.clamp(0, ladder.length - 1)];
  }

  /// The one merged record the session closed with: every observation from both
  /// devices, in wall-clock order, whoever logged it. Null until the phone
  /// closes the session — [completeSession] is what makes it.
  Map<String, Object?>? get completedRecord => _completedRecord;

  /// The wall-clock instant the timer of [kind] reaches zero, or null when
  /// there is no such timer or it counts up.
  ///
  /// Derived, never stored: a countdown sent over the wire would be wrong the
  /// moment it arrived (PROTOCOL.md, "Timer state").
  DateTime? timerEnd(String kind) {
    final timers = state['timers'];
    if (timers is! Map) return null;
    final timer = timers[kind];
    if (timer is! Map) return null;
    return timerCompletionInstant(timer.cast<String, Object?>());
  }

  // ---------------------------------------------------------------------------
  // Incoming
  // ---------------------------------------------------------------------------

  /// Applies one message from the watch and tells the live view.
  ///
  /// Returns [MirrorOutcome.refused] — with nothing applied and the phone's
  /// snapshot on its way to the watch — when this build cannot read the
  /// message. A watch snapshot that reports a different session shape is
  /// applied like any other, and the phone then re-asserts what it holds of its
  /// own, because structure is the phone's to own (authority rule 2).
  Future<MirrorOutcome> receive(Map<String, Object?> envelope) async {
    final validator = _validator;
    if (validator != null) {
      final decision = validator.evaluateIncoming(
        envelope,
        receiverVersion: SyncProtocolValidator.protocolVersion,
      );
      if (!decision.accepted) {
        if (decision.respondWithSnapshot) await sendSnapshot();
        return MirrorOutcome.refused;
      }
    }

    if (!_consumedTypes.contains(envelope['type'])) {
      return MirrorOutcome.ignored;
    }

    final before = state;
    _reconciler.applyMessage(envelope);
    notifyListeners();

    if (envelope['type'] == 'session_snapshot' &&
        _shapeDiffers(envelope, before)) {
      // The watch's ladder is a reflection of the phone's, so it is normally
      // the same. When it is not, the phone has changed shape since the watch
      // last heard, and the watch's copy is the stale one: answer with what the
      // phone holds rather than adopting a ladder nobody asked for.
      //
      // A phone that has never held a ladder has no shape to assert, and
      // asserting an empty one would wipe the wrist's. It adopts the wrist's
      // instead, which is what makes a session started on the wrist renderable
      // here at all.
      if (_holdsLadder(before)) {
        await _transport.send(snapshotEnvelope(state: before));
      }
    }
    return MirrorOutcome.applied;
  }

  static bool _holdsLadder(Map<String, Object?> state) =>
      _objects(state['exercises']).isNotEmpty;

  /// The message types that carry live session state. Everything else the
  /// protocol defines is another surface's news: conformant, and none of this
  /// mirror's business.
  static const Set<Object?> _consumedTypes = {
    'session_snapshot',
    'structure_change',
    'observations_up',
    'session_lifecycle',
    'timer_state',
    'exercise_push',
  };

  // ---------------------------------------------------------------------------
  // Outgoing
  // ---------------------------------------------------------------------------

  /// The phone's live session as a protocol message — the answer to a snapshot
  /// request, and what brings a watch that drifted back to the phone's shape.
  ///
  /// [state] overrides the converged session, which is how a re-assertion sends
  /// the shape the phone held *before* it applied the peer's snapshot.
  Map<String, Object?> snapshotEnvelope({
    Map<String, Object?>? state,
    String? messageId,
  }) {
    final converged = state ?? this.state;
    return {
      'protocolVersion': SyncProtocolValidator.protocolVersion,
      'messageId': messageId ?? _newId(),
      'sessionId': converged['sessionId'],
      'type': 'session_snapshot',
      'origin': 'phone',
      'sentAt': utcIso(_clock()),
      'payload': converged,
    };
  }

  /// The phone's answer to a snapshot that reports a different session.
  ///
  /// Structure is the phone's to own (PROTOCOL.md, authority rule 2), so when
  /// the two devices disagree about the shape of a session — or the phone holds
  /// entries the watch has not seen — the phone re-asserts its own state rather
  /// than accepting the watch's. An identical snapshot is left unanswered, or
  /// two connected devices would answer each other for ever.
  ///
  /// Verified by `test/live_mirroring_test.dart` (`S-008 a snapshot the phone
  /// disagrees with is answered with its own`).
  Future<void> sendSnapshot() => _transport.send(snapshotEnvelope());

  /// Asks the watch for its snapshot — the phone's half of joining a session
  /// that was started on the wrist.
  Future<void> requestSnapshot() => _transport.requestSnapshot();

  /// The connect sequence: hand the watch the phone's state, then ask for the
  /// watch's, so a pair that drifted while apart converges.
  Future<void> sync() async {
    await sendSnapshot();
    await requestSnapshot();
  }

  /// Inserts [slot] at [atIndex] and tells the watch — the phone's "send to
  /// watch session".
  Future<Map<String, Object?>> pushExercise(
    Map<String, Object?> slot, {
    required int atIndex,
  }) async {
    final envelope = _envelope('exercise_push', {
      'exercise': slot,
      'insertAtIndex': atIndex,
    });
    await _sendOwn(envelope);
    return envelope;
  }

  /// The id a slot gets when a searched exercise joins the ladder.
  ///
  /// The phone chooses slot ids (PROTOCOL.md, "Exercise identity"), and the id
  /// has to be stable for the life of the session: entries point at the slot,
  /// not at the exercise in it.
  String mintSlotId() => 'sx-${_newId()}';

  /// Applies [changes] to the live session and tells the watch.
  ///
  /// [changes] are the protocol's change objects — `add_exercise`,
  /// `remove_exercise`, `reorder_exercises`, `swap_exercise`, `correct_entry`,
  /// `delete_entry`. The `changeId` is minted here, which is what makes the
  /// watch's application of a re-delivered change a no-op.
  Future<Map<String, Object?>> applyStructureChange(
    List<Map<String, Object?>> changes,
  ) async {
    final envelope = _envelope('structure_change', {
      'changeId': _newId(),
      'changes': changes,
    });
    await _sendOwn(envelope);
    return envelope;
  }

  /// Adds [slot] to the ladder — the phone's own management of the session.
  ///
  /// Structure is the phone's to own (PROTOCOL.md, authority rule 2), so this
  /// is the one device that may do it. [atIndex] is where the user put it;
  /// null appends, which is where an exercise nobody placed goes.
  ///
  /// An exercise the user found by searching the catalog is [pushExercise]
  /// instead: `exercise_push` carries the position with the slot, and the
  /// protocol forbids following it with an `add_exercise` for the same slot.
  Future<Map<String, Object?>> addExercise(
    Map<String, Object?> slot, {
    int? atIndex,
  }) => applyStructureChange([
    {
      'kind': 'add_exercise',
      'exercise': slot,
      'atIndex': atIndex ?? exercises.length,
    },
  ]);

  /// Takes the slot [sessionExerciseId] out of the ladder.
  ///
  /// Entries already logged against it stay: history records what happened, not
  /// what the ladder holds now (PROTOCOL.md, authority rule 5).
  Future<Map<String, Object?>> removeExercise(String sessionExerciseId) =>
      applyStructureChange([
        {'kind': 'remove_exercise', 'sessionExerciseId': sessionExerciseId},
      ]);

  /// Puts the ladder in [order].
  ///
  /// Slots [order] does not name keep their relative order after the ones it
  /// does, and the session stays on the exercise it was on — a reorder does not
  /// move the user.
  Future<Map<String, Object?>> reorderExercises(List<String> order) =>
      applyStructureChange([
        {'kind': 'reorder_exercises', 'order': order},
      ]);

  /// Moves the slot at [index] by [delta] places.
  ///
  /// A move is a whole order, not a pair of indices: `reorder_exercises`
  /// carries the ladder, so both devices end up with the order the user asked
  /// for rather than inferring it from a swap. A move that would leave the
  /// ladder, or that starts off it, is not an error — it is a move that cannot
  /// happen, and nothing is sent.
  Future<void> moveExercise(int index, int delta) {
    final order = [
      for (final slot in exercises) slot['sessionExerciseId']! as String,
    ];
    final target = index + delta;
    if (index < 0 || index >= order.length) return Future<void>.value();
    if (target < 0 || target >= order.length) return Future<void>.value();

    order.insert(target, order.removeAt(index));
    return reorderExercises(order);
  }

  /// Replaces what the slot [sessionExerciseId] holds.
  ///
  /// [exercise] is catalog reference data — what the exercise *is*, not where
  /// it sits — so it carries no slot id. The slot keeps its own, which is what
  /// leaves entries logged against it pointing at it and the position unmoved.
  Future<Map<String, Object?>> swapExercise(
    String sessionExerciseId,
    Map<String, Object?> exercise,
  ) => applyStructureChange([
    {
      'kind': 'swap_exercise',
      'sessionExerciseId': sessionExerciseId,
      'exercise': exercise,
    },
  ]);

  /// Fixes an entry the wrist logged — a fat-fingered set, say.
  ///
  /// [correction] carries only the metrics being corrected, and the entry
  /// travels by `entryId`, never by the slot: correcting what was logged must
  /// not depend on what the slot holds now.
  Future<Map<String, Object?>> correctEntry(
    String entryId,
    Map<String, Object?> correction,
  ) => applyStructureChange([
    {'kind': 'correct_entry', 'entryId': entryId, 'correction': correction},
  ]);

  /// Deletes an entry the wrist logged.
  Future<Map<String, Object?>> deleteEntry(String entryId) =>
      applyStructureChange([
        {'kind': 'delete_entry', 'entryId': entryId},
      ]);

  /// Closes the session from the phone and hands back the merged record.
  ///
  /// The record is made once: the wrist is told the session completed a single
  /// time, and a second tap on Finish returns the same record rather than
  /// producing a second session. Entries are ordered by wall-clock `loggedAt`,
  /// so the record reads the same whichever device logged what.
  Future<Map<String, Object?>> completeSession() async {
    final closed = _completedRecord;
    if (closed != null) return closed;

    await reportLifecycle(WatchLifecycleState.completed);
    _completedRecord = Map<String, Object?>.of(state);
    notifyListeners();
    return _completedRecord!;
  }

  /// Reports a lifecycle change — the session completed on the phone, say.
  ///
  /// The index travels only with `exercise_advanced`, because the schema allows
  /// it nowhere else.
  Future<Map<String, Object?>> reportLifecycle(
    String state, {
    int? exerciseIndex,
  }) async {
    final envelope = _envelope('session_lifecycle', {
      'state': state,
      'at': utcIso(_clock()),
      'exerciseIndex': ?exerciseIndex,
    });
    await _sendOwn(envelope);
    return envelope;
  }

  /// A message the phone originates: applied here first, then handed to the
  /// transport.
  ///
  /// Applying locally is not an optimisation — the session the user is looking
  /// at has to be the session the watch is told about, and a watch observation
  /// arriving in the meantime lands in the new shape rather than in a stale one.
  /// Every apply is idempotent, so a transport that retries cannot double-edit.
  Future<void> _sendOwn(Map<String, Object?> envelope) async {
    _reconciler.applyMessage(envelope);
    notifyListeners();
    await _transport.send(envelope);
  }

  Map<String, Object?> _envelope(String type, Map<String, Object?> payload) => {
    'protocolVersion': SyncProtocolValidator.protocolVersion,
    'messageId': _newId(),
    'sessionId': state['sessionId'],
    'type': type,
    'origin': 'phone',
    'sentAt': utcIso(_clock()),
    'payload': payload,
  };

  // ---------------------------------------------------------------------------
  // Disagreement
  // ---------------------------------------------------------------------------

  /// Whether the watch's snapshot reports a session shape this phone does not
  /// hold: a different status, revision, position, or ladder.
  ///
  /// Entries are deliberately not compared. A snapshot's entries *merge* by
  /// `entryId`, so an entry the phone is missing is not a disagreement — and a
  /// comparison that called it one would answer a converging peer with noise.
  ///
  /// Compared field by field rather than by encoding the whole payload, because
  /// two devices build the same shape in different orders — and a comparison
  /// that disagreed about key order would answer a snapshot with an identical
  /// one, for ever.
  bool _shapeDiffers(
    Map<String, Object?> envelope,
    Map<String, Object?> local,
  ) {
    final payload = _asObject(envelope['payload']);
    for (final field in const [
      'sessionId',
      'status',
      'revision',
      'currentExerciseIndex',
    ]) {
      if (payload[field] != local[field]) return true;
    }
    return !_sameSlots(payload['exercises'], local['exercises']) ||
        !_sameTimers(payload['timers'], local['timers']);
  }

  static bool _sameSlots(Object? a, Object? b) {
    final left = _objects(a);
    final right = _objects(b);
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      for (final field in const ['sessionExerciseId', 'exerciseId', 'name']) {
        if (left[index][field] != right[index][field]) return false;
      }
    }
    return true;
  }

  static bool _sameTimers(Object? a, Object? b) {
    final left = _asObject(a ?? const <String, Object?>{});
    final right = _asObject(b ?? const <String, Object?>{});
    if (left.length != right.length) return false;
    for (final kind in left.keys) {
      final mine = left[kind];
      final theirs = right[kind];
      if (mine is! Map || theirs is! Map) return false;
      for (final field in const [
        'state',
        'startedAt',
        'accumulatedPauseMs',
        'plannedDurationMs',
      ]) {
        if (mine[field] != theirs[field]) return false;
      }
    }
    return true;
  }

  static List<Map<String, Object?>> _objects(Object? value) => [
    for (final element in (value as List?) ?? const []) _asObject(element),
  ];

  static Map<String, Object?> _asObject(Object? value) =>
      (value as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
}
