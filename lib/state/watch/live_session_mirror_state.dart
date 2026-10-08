/// The phone's live session mirror: what keeps the phone's view of a
/// watch-led session current without the watch being asked anything.
///
/// Plan: `docs/plans/2026-07-13-09-c1-live-session-mirroring-plan.md`.
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
import '../../core/sync_protocol/phone_envelope.dart';
import '../../core/sync_protocol/session_reconciler.dart';
import '../../core/sync_protocol/timer_derivation.dart';
import '../../data/models/models.dart' show WatchInboxEntry;
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

/// The `sessionId` of `watchSessionPlaceholder` in `watch_sync_wiring.dart`:
/// the phone's not-a-session, which names no wrist session and is therefore
/// never named in a reset (D-176, D-173).
///
/// The constant lives here, beside the predicate that reads it, because the
/// wiring constructs the mirror on top of this library: importing the wiring
/// back would be a cycle. Both files read this one constant.
const String watchSessionPlaceholderId = 's-phone-unjoined';

class LiveSessionMirrorState extends ChangeNotifier {
  LiveSessionMirrorState({
    required WatchMirrorTransport transport,
    required Map<String, Object?> snapshot,
    SyncProtocolValidator? validator,
    DateTime Function()? clock,
    String Function()? idFactory,
    Future<Map<String, Object?>?> Function(Map<String, Object?>? incoming)?
    projection,
  }) : _transport = transport,
       _validator = validator,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid,
       _projection = projection,
       _reconciler = SyncSessionReconciler.fromSnapshot(snapshot);

  static const Uuid _uuidV4 = Uuid();

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String _uuid() => _uuidV4.v4();

  final WatchMirrorTransport _transport;
  final SyncProtocolValidator? _validator;
  final DateTime Function() _clock;
  final String Function() _newId;
  final SyncSessionReconciler _reconciler;

  /// Composes what this phone asserts for a session it holds, from the phone's
  /// own session rather than from the copy this mirror reconciled (D-11).
  /// [incoming] is the wrist frame being answered, null for a bare request.
  /// Null means the phone has no session of its own to speak from — the mirror's
  /// own copy answers then, which is the protocol's echo. Asynchronous because
  /// the phone's own entries are read from the repository (D-31).
  final Future<Map<String, Object?>?> Function(Map<String, Object?>? incoming)?
  _projection;

  /// The session as the phone closed it. Null while it is running.
  Map<String, Object?>? _completedRecord;

  /// How each session this phone announced an end for ended, by session id.
  ///
  /// [owesResetFor]'s status is the memory for the session this mirror is
  /// holding; this is the memory for the ones it has moved off, which are
  /// exactly the ones a wrist still announcing them is owed an answer for
  /// (D-182's fourth row, S-190).
  final Map<String, String> _fates = {};

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

  /// The entry kinds that describe the session as a whole rather than
  /// something logged in it (PROTOCOL.md, "Session capture"): the wrist's
  /// session effort rating and its session end.
  static const Set<String> sessionScopedKinds = {
    WatchInboxEntry.kindEffortRating,
    WatchInboxEntry.kindSessionEnd,
  };

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
  /// message. A watch snapshot that reports a different shape of the session
  /// this phone holds is applied like any other, and the phone then re-asserts
  /// what it holds of its own, because structure is the phone's to own
  /// (authority rule 2).
  ///
  /// A snapshot that names another session is not a disagreement about this
  /// one: it is the next workout the wrist started. It replaces the held
  /// session wholesale, the record the phone closed for the old one is
  /// dropped, and nothing is answered (PROTOCOL.md, "Idempotency and
  /// reconciliation"; D-130). Re-asserting the old session there would yank
  /// the wrist back to a workout it has finished.
  Future<MirrorOutcome> receive(Map<String, Object?> envelope) async {
    final decision = SyncProtocolValidator.evaluateOrAccept(
      _validator,
      envelope,
    );
    if (!decision.accepted) {
      if (decision.respondWithSnapshot) await sendSnapshot();
      return MirrorOutcome.refused;
    }

    if (!_consumedTypes.contains(envelope['type'])) {
      return MirrorOutcome.ignored;
    }

    // A message about a session this mirror is not holding is not this mirror's
    // news. A nutrition quick-log taken with no workout running names the day it
    // was logged on, and folding it into whatever session happens to be live
    // would file a meal under a workout.
    //
    // The snapshot is the one message that may name a session this mirror does
    // not hold yet: it is how a session started on the wrist becomes renderable
    // here at all.
    if (envelope['type'] != 'session_snapshot' &&
        !_namesMirroredSession(envelope)) {
      return MirrorOutcome.ignored;
    }

    final before = state;
    final switchesSession =
        envelope['type'] == 'session_snapshot' &&
        _asObject(envelope['payload'])['sessionId'] != before['sessionId'];
    _reconciler.applyMessage(envelope);
    if (switchesSession) _completedRecord = null;
    notifyListeners();

    if (switchesSession) return MirrorOutcome.applied;

    // The watch's ladder is a reflection of the phone's, so it is normally
    // the same. When it is not, the phone has changed shape since the watch
    // last heard, and the watch's copy is the stale one: answer with what the
    // phone holds rather than adopting a ladder nobody asked for. What the
    // phone holds is its own session when it has one (D-11), and this mirror's
    // copy of the session otherwise — a session this phone is not in is not
    // answered with another session's ladder (D-10).
    //
    // A phone that holds no ladder for the session has no shape to assert,
    // and asserting an empty one would wipe the wrist's. It adopts the
    // wrist's instead. (A session started on the wrist names a session the
    // phone does not hold, so it is adopted by the switch above.)
    if (envelope['type'] == 'session_snapshot') {
      final projection = _projection;
      final answer = projection == null
          ? before
          : (await projection(envelope)) ?? before;
      if (_shapeDiffers(envelope, answer)) {
        if (_holdsLadder(answer)) {
          await sendState(answer);
        }
      }
    }
    return MirrorOutcome.applied;
  }

  static bool _holdsLadder(Map<String, Object?> state) =>
      _objects(state['exercises']).isNotEmpty;

  /// True when [envelope] names the session this mirror holds. An envelope that
  /// names none at all is not a session's news either, and is equally not this
  /// mirror's to fold.
  bool _namesMirroredSession(Map<String, Object?> envelope) {
    final sessionId = envelope['sessionId'];
    return sessionId is String && sessionId == state['sessionId'];
  }

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

  /// The phone's own session as a protocol state, composed on demand from the
  /// bound session state (D-11) — the ladder a wrist snapshot is answered with.
  ///
  /// Composed for the place the receiver last reported: the projection reads
  /// that place out of the payload of the frame it is handed, and this is the
  /// frame — the receiver's own position and nothing else, which is what the
  /// account below carries. A phone that answered with slot 0 would yank a wrist
  /// on exercise 3 back to exercise 1, and the payload composed here is also
  /// what the phone pushes on its own (D-77). It names no session: a frame
  /// without one is not the D-10 disagreement case, so a phone in its own
  /// session still speaks for it.
  ///
  /// Null when the phone has no session of its own to speak from; the caller
  /// falls back to what this mirror holds, which is all a phone with no bound
  /// session has.
  Future<Map<String, Object?>?> projectedSession() async {
    final projection = _projection;
    if (projection == null) return null;
    return projection(<String, Object?>{
      'payload': <String, Object?>{'currentExerciseIndex': currentExerciseIndex},
    });
  }

  /// The phone's live session as a protocol message — the answer to a snapshot
  /// request, and what brings a watch that drifted back to the phone's shape.
  ///
  /// [state] overrides the converged session: an answer composed from the
  /// phone's own session ([projectedSession]) is sent through here, and so is a
  /// re-assertion the mirror's copy composes.
  Map<String, Object?> snapshotEnvelope({
    Map<String, Object?>? state,
    String? messageId,
  }) {
    final converged = state ?? this.state;
    return phoneEnvelope(
      type: 'session_snapshot',
      messageId: messageId ?? _newId(),
      sentAt: _clock(),
      sessionId: converged['sessionId'] as String?,
      payload: converged,
    );
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
  Future<void> sendSnapshot() => sendState(state);

  /// Hands the watch [state] as this phone's snapshot, over the same transport
  /// every other outgoing message uses.
  Future<void> sendState(Map<String, Object?> state) =>
      _transport.send(snapshotEnvelope(state: state));

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

  /// Applies [changes] to the live session and tells the watch.
  ///
  /// [changes] are the protocol's change objects — `add_exercise`,
  /// `remove_exercise`, `reorder_exercises`, `swap_exercise`, `correct_entry`,
  /// `delete_entry`. The `changeId` is minted here unless the caller names one,
  /// which is what makes the watch's application of a re-delivered change a
  /// no-op.
  Future<Map<String, Object?>> applyStructureChange(
    List<Map<String, Object?>> changes, {
    String? changeId,
  }) async {
    final envelope = _envelope('structure_change', {
      'changeId': changeId ?? _newId(),
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

  /// Deletes the entry [entryId] of the session [sessionId], under a [changeId]
  /// the caller names rather than a fresh one.
  ///
  /// [deleteEntry] mints a new id per call and names whatever session this
  /// mirror holds, so a caller that has to say the same deletion twice — the
  /// auto-push announcing a set gone (D-110) — would look like a new change
  /// each time. A named id makes a re-delivered frame a no-op on the wrist: its
  /// `appliedChangeIds` drops the repeat and the row the frame writes has the
  /// same record id (D-116, S-120).
  ///
  /// [sessionId] is named the way [reportLifecycleFor] names one, because the
  /// session the caller is deleting in is not necessarily the one this mirror
  /// holds: the entries the auto-push composes for are the composed session's,
  /// and applying the frame here would hide an entry of a session this frame
  /// does not name. The name travels on the frame either way, and the wrist
  /// applies it to the session it holds under that name.
  Future<Map<String, Object?>> deleteEntryAs(
    String sessionId,
    String entryId, {
    required String changeId,
  }) async {
    final envelope = _envelopeFor(sessionId, 'structure_change', {
      'changeId': changeId,
      'changes': [
        {'kind': 'delete_entry', 'entryId': entryId},
      ],
    });
    if (sessionId == this.sessionId) {
      _reconciler.applyMessage(envelope);
      notifyListeners();
    }
    await _transport.send(envelope);
    return envelope;
  }

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
  ///
  /// An end announced here is remembered against the session it names, so the
  /// wrist still holding that session is told how it ended rather than being
  /// offered the session back (D-182, S-190).
  Future<Map<String, Object?>> reportLifecycle(
    String state, {
    int? exerciseIndex,
  }) async {
    final envelope = _envelope('session_lifecycle', {
      'state': state,
      'at': utcIso(_clock()),
      'exerciseIndex': ?exerciseIndex,
    });
    _recordFate(sessionId, state);
    await _sendOwn(envelope);
    return envelope;
  }

  /// Reports a lifecycle change for [sessionId] **by name** — the session the
  /// caller is speaking about, which is not necessarily the one this mirror
  /// holds.
  ///
  /// [reportLifecycle] names whatever session this mirror holds, which is the
  /// same session only while the two agree: a wrist that starts its own session
  /// moves the mirror onto one this phone never held (D-10), and an end
  /// announced under that name would close a workout the wrist is still
  /// running. The local apply happens only when this mirror is the one holding
  /// [sessionId]; the frame reaches the transport either way.
  ///
  /// The merged record a closed session leaves behind is [completeSession]'s to
  /// make, and is not made here.
  ///
  /// The end is remembered against [sessionId] — not against whatever this
  /// mirror holds — for the same reason the frame names it: the wrist it is
  /// owed to is the one still announcing that session (D-182, S-190).
  Future<Map<String, Object?>> reportLifecycleFor(
    String sessionId,
    String state,
  ) async {
    final envelope = _envelopeFor(sessionId, 'session_lifecycle', {
      'state': state,
      'at': utcIso(_clock()),
    });
    _recordFate(sessionId, state);
    if (sessionId == this.sessionId) {
      _reconciler.applyMessage(envelope);
      notifyListeners();
    }
    await _transport.send(envelope);
    return envelope;
  }

  /// Whether this mirror's session is owed a reset before the phone asserts
  /// the session [composedId] — D-176's one shared step.
  ///
  /// Owed when the phone composes a session `P` and this mirror holds a
  /// different session `W` that is a wrist session: the placeholder is not one
  /// (D-173), and a phone holding nothing has no structure to assert (D-11).
  ///
  /// Deliberately not conditioned on [isActive]: a first reset applies locally
  /// and leaves this mirror's id on `W` — the wrist never confirmed it — so an
  /// `isActive` test would drop the retry after the first pass while the
  /// wrist's answer is what actually clears the debt (D-176, D-178).
  ///
  /// A `W` this phone already announced as `completed` is not reset either: the
  /// wrist has been told how that session ended, and an `abandoned` under the
  /// same name would rewrite a finished workout as a discarded one (S-85). An
  /// `abandoned` `W` still is — the retry after a failed send has nothing but
  /// the status to show for it, and that retry is what S-180 pins.
  bool owesResetFor(String? composedId) {
    final held = sessionId;
    return composedId != null &&
        held != null &&
        held != composedId &&
        held != watchSessionPlaceholderId &&
        status != WatchSessionStatus.completed;
  }

  /// How this phone ended the session [sessionId], or null when it has no
  /// record of ending it (D-182's fourth row).
  ///
  /// The announced fates come first: a session this mirror has since moved off
  /// still owes its end to a wrist that is still announcing it, and that is the
  /// case this memory exists for (S-190). A session this mirror is holding
  /// answers with its own status, which is how a fate that arrived as a frame
  /// rather than from one of the two senders above is still found. `active` is
  /// not a fate.
  ///
  /// Memory only, like the rest of the mirror: a relaunched phone is the
  /// placeholder again and adopts what the wrist announces (Open question 10).
  String? rememberedFateOf(String sessionId) {
    final announced = _fates[sessionId];
    if (announced != null) return announced;
    if (sessionId != this.sessionId) return null;
    final held = status;
    return held == WatchSessionStatus.active ? null : held;
  }

  /// Remembers that [sessionId] was announced as ended — the only two ends a
  /// wrist is ever told about (D-182). Any other lifecycle leaves the memory as
  /// it is; nothing an incoming frame does clears one.
  void _recordFate(String? sessionId, String state) {
    if (sessionId == null) return;
    if (state != WatchLifecycleState.completed &&
        state != WatchLifecycleState.abandoned) {
      return;
    }
    _fates[sessionId] = state;
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

  Map<String, Object?> _envelope(String type, Map<String, Object?> payload) =>
      _envelopeFor(state['sessionId'] as String?, type, payload);

  /// An envelope this phone originates, naming [sessionId] — which a caller can
  /// take from anywhere, where [_envelope] names the session this mirror holds.
  Map<String, Object?> _envelopeFor(
    String? sessionId,
    String type,
    Map<String, Object?> payload,
  ) => phoneEnvelope(
    type: type,
    messageId: _newId(),
    sentAt: _clock(),
    sessionId: sessionId,
    payload: payload,
  );

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
