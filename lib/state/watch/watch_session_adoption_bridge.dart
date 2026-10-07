/// Adopts the session the wrist is running into the phone's own session state.
///
/// The mirror (`live_session_mirror_state.dart`) reconciles what the wrist sends
/// into the phone's protocol projection; this bridge is the layer above it, and
/// turns that projection into rows and into `WorkoutState` (D-2). What the phone
/// ends up with is a real in-progress session: the regular session screen logs
/// into it, and its rows are the ones an imported session has. The ids, though,
/// are the protocol's (D-3) — the session is `sessionId`, an effort is its slot
/// — so the ladder the wrist is looking at and the ladder the phone is looking
/// at are one session by identity, and a second snapshot updates the same one.
///
/// One rule lives here rather than in the reconciler (D-10): the phone keeps the
/// session it is already running. The wrist's session is not adopted, and the
/// skip is reported through `onSkipped` — once per (held, offered) pair, as one
/// line in a debug log. Refusing is the rule working, so it is not a failure and
/// carries no stack.
library;

import 'package:flutter/foundation.dart';

import '../../core/constants/block_types.dart';
import '../../core/constants/capability.dart';
import '../../core/constants/modality_config.dart';
import '../../core/services/watch_session_importer.dart';
import '../../core/sync_protocol/phone_entries.dart';
import '../../core/utils/entry_rows.dart';
import '../../core/utils/logged_entry_rows.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';
import '../../watch/session/watch_records.dart'
    show WatchLifecycleState, WatchSessionStatus;
import '../workout/workout_state.dart';

/// What one converged snapshot did to the phone's session state.
enum WatchSessionAdoption {
  /// The phone now holds the wrist's session (D-2).
  adopted,

  /// The phone already held this session; nothing was written.
  alreadyHeld,

  /// The phone is running a different session and kept it (D-10).
  refusedConflict,

  /// The named session's row is already history — ended. Nothing was written
  /// and nothing was loaded back (G1): a session the phone has finished does
  /// not become live again because the wrist is still looking at it. The phone
  /// answers the snapshot with the session's end instead.
  alreadyEnded,

  /// There was no `WorkoutState` bound to adopt into.
  unbound,

  /// The snapshot is not of a session the wrist is running.
  notRunning,
}

/// Every kind a slot may declare — the protocol's `effortKind` values, which a
/// wrist record spells exactly as the data layer does.
const List<String> _declaredKinds = [
  BlockTypes.set,
  BlockTypes.timed,
  BlockTypes.round,
  BlockTypes.drill,
];

/// The capabilities that decide a kind, most decisive first: the order the wrist
/// resolves a slot's kind by.
const List<String> _kindPrecedence = [
  ExerciseCapability.hold,
  ExerciseCapability.rounds,
  ExerciseCapability.reps,
  ExerciseCapability.sets,
  ExerciseCapability.load,
  ExerciseCapability.time,
  ExerciseCapability.distance,
];

void _report(Object error, StackTrace stack) {
  debugPrint('Watch session adoption: $error');
  debugPrintStack(stackTrace: stack);
}

/// The default D-10 report: one line in the debug log. A skip is the rule
/// working — the phone kept the session it was already running — so it is not
/// an error and there is no stack to print.
void _reportSkipped(String heldSessionId, String offeredSessionId) {
  debugPrint(
    'Watch session sync: kept $heldSessionId, did not adopt '
    '$offeredSessionId (this phone already has a session in progress)',
  );
}

/// Turns the session a wrist is running into the phone's own session.
class WatchSessionAdoptionBridge {
  WatchSessionAdoptionBridge({
    required WorkoutRepository repository,
    DateTime Function()? clock,
    void Function(Object error, StackTrace stack)? onFailure,
    void Function(String heldSessionId, String offeredSessionId)? onSkipped,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now,
       _onFailure = onFailure ?? _report,
       _onSkipped = onSkipped ?? _reportSkipped;

  final WorkoutRepository _repository;
  final DateTime Function() _clock;
  final void Function(Object error, StackTrace stack) _onFailure;

  /// Where a refused adoption (D-10) is reported — the one observation of a
  /// skip the app has, so tests can see it without reading the debug log.
  final void Function(String heldSessionId, String offeredSessionId) _onSkipped;

  WorkoutState? _workoutState;

  /// The (held, offered) pair the last skip was reported for, or null while
  /// none has been. A wrist that has not converged repeats the snapshot it
  /// holds, so the same pair arrives frame after frame; the log says it once.
  String? _skippedHeldSessionId;
  String? _skippedOfferedSessionId;

  /// The revision this bridge last stated for the phone's ladder (D-11). The
  /// protocol's revision belongs to the session, and the phone's own versions
  /// are not persisted: they exist to be higher than what the wrist holds, and
  /// the wrist's own count arrives on every frame it sends.
  int _projectedRevision = 0;

  /// The ladder [_projectedRevision] was counted for. A projection of the same
  /// ladder states the same revision, so a peer that has converged stays quiet.
  String? _projectedLadder;

  /// Every slot id each held session has ever carried, by session (D-93): the
  /// union of the ladders of the snapshots the phone has applied for it and of
  /// the phone's own ladder at each [consider].
  ///
  /// A slot that leaves the phone's ladder stays in the set, so a stale wrist
  /// snapshot carrying it appends nothing back. An entry lives only while the
  /// phone holds the session; a session it has moved on from keeps none.
  final Map<String, Set<String>> _everSeen = {};

  /// Binds the state an adopted session is published into. Until this is called
  /// [consider] adopts nothing: a build with no session state has nowhere to put
  /// one.
  void bindWorkoutState(WorkoutState workoutState) {
    _workoutState = workoutState;
  }

  /// Whether [sessionId] is the session this phone is holding as its own —
  /// adopted off the wrist, still running or already finished.
  ///
  /// The same question the D-10 conflict guard asks, and the one the watch
  /// session inbox asks before importing anything for that session (G3).
  bool holdsSession(String sessionId) {
    final target = _workoutState;
    return target != null && target.currentSession?.id == sessionId;
  }

  /// Re-reads the efforts a merge wrote into the session this phone holds, so
  /// the regular session screen shows the merged rows at once (D-17).
  ///
  /// A session the phone does not hold is not refreshed: those efforts belong
  /// to a session that is not the phone's live one, or to none. Writes nothing
  /// and notifies nothing for such a session, and for a phone with no session
  /// state bound.
  Future<void> refreshHeldEfforts(
    String sessionId,
    Iterable<String> effortIds,
  ) async {
    final target = _workoutState;
    if (target == null || !holdsSession(sessionId)) return;
    await target.refreshEfforts(effortIds);
  }

  /// The phone's own session as a protocol state — the answer to a wrist
  /// snapshot (D-11). Composed from `WorkoutState` at the moment it is asked
  /// for, never cached: the answer is the ladder the regular session screen
  /// holds now, not a copy of what the mirror last reconciled.
  ///
  /// [incoming] is the wrist's frame when this answers a re-assertion, and null
  /// when the wrist asked with a `snapshot` request. It carries the two facts
  /// the phone's own state does not: where in the ladder the wrist now is, and
  /// the revision it holds.
  ///
  /// Null when this phone has no session of its own to speak from. That
  /// includes the wrist naming a session this phone is not in (D-10): the phone
  /// does not answer another session's snapshot with its own ladder, and the
  /// mirror's copy of that session is what answers instead.
  ///
  /// The answer carries the entries this phone logged **itself** (`entries`,
  /// D-31/D-33/D-34): the sets the regular session screen wrote into the slots
  /// of this session, so the wrist's logging screen shows them like its own.
  /// That is a repository read, so this composes asynchronously — and it is
  /// still composed per call, never cached (D-11).
  Future<Map<String, Object?>?> projectSession(
    Map<String, Object?>? incoming,
  ) async {
    final target = _workoutState;
    if (target == null) return null;

    final session = target.currentSession;
    if (session == null || !target.hasActiveSession) return null;
    if (incoming != null) {
      final named = _namedSession(incoming);
      if (named != null && named != session.id) return null;
    }

    final wristStamps = await _wristRowStamps(session.id);

    final slots = <Map<String, Object?>>[];
    final entries = <Map<String, Object?>>[];
    for (final segment in target.segments) {
      for (final effort in target.getEffortsForSegment(segment.id)) {
        final slot = _slotFor(effort, target);
        if (slot == null) continue;
        slots.add(slot);
        entries.addAll(await _entriesFor(effort, slot, wristStamps));
      }
    }
    // A ladder with nothing the wrist can render is not a state to send: an
    // empty one would replace the ladder the wrist is working through. The
    // phone's session may still be running — a session that is only invalid
    // exercises is one this projection cannot speak for.
    if (slots.isEmpty) return null;

    _countRevision(incoming, session.id, slots);

    return <String, Object?>{
      'sessionId': session.id,
      'status': WatchSessionStatus.active,
      'revision': _projectedRevision,
      'currentExerciseIndex': _indexFor(incoming, slots.length),
      'exercises': slots,
      'entries': PhoneEntries.ordered(entries),
      'timers': const <String, Object?>{},
    };
  }

  /// One slot's own entries, in the protocol's order.
  ///
  /// None for a kind with no wire entry yet (D-39): a `timed`, `hold` or `round`
  /// effort's rows are its instances' companions, and their window and round
  /// fields are not carried. `set` is the kind the wire can spell today.
  Future<List<Map<String, Object?>>> _entriesFor(
    SegmentEffort effort,
    Map<String, Object?> slot,
    Map<String, List<int>> wristStamps,
  ) async {
    if (effort.effortKind != BlockTypes.set) return const [];

    return PhoneEntries.project(
      sessionExerciseId: effort.id,
      exerciseId: slot['exerciseId']! as String,
      groups: EntryRows.setGroups(
        await _repository.getEffortObservations(effort.id),
      ),
      wristLoggedAtMs: wristStamps[effort.id] ?? const [],
    );
  }

  /// The entry ids the wrist is expected to hold for [sessionId]: the ones its
  /// own inbox rows carry while their stamp still claims a group on their slot
  /// (D-112).
  ///
  /// The ids the wrist logged and the phone still holds. A row whose group the
  /// user deleted on the phone claims no group and stops being held, which is
  /// the deletion the phone has to announce (S-122, `_wristRowStamps` +
  /// `PhoneEntries.claimedBy` — the same claim rule the projection uses, not a
  /// second one).
  ///
  /// Scope: `kindSet` rows only. A non-set entry has no wire entry to delete
  /// until 17d projects those kinds, so the phone cannot name one here (D-112,
  /// 17d D-137).
  Future<Set<String>> heldWristEntryIds(String sessionId) async {
    final rows = await _repository.getWatchInboxEntriesForSession(sessionId);
    final groupsBySlot = <String, List<SetRows>>{};
    final held = <String>{};
    for (final row in rows) {
      if (row.origin != WatchInboxEntry.originWatch) continue;
      if (row.kind != WatchInboxEntry.kindSet) continue;

      final payload = row.payload;
      final slot = payload['sessionExerciseId'];
      final loggedAtMs = _loggedAtMs(payload['loggedAt']);
      if (slot is! String || slot.isEmpty || loggedAtMs == null) continue;

      final groups = groupsBySlot[slot] ??= EntryRows.setGroups(
        await _repository.getEffortObservations(slot),
      );
      // Does this row's stamp still claim a group? One stamp, the existing
      // predicate: a row claims the first group on its slot carrying its stamp.
      final claims = PhoneEntries.claimedBy(
        groups: groups,
        wristLoggedAtMs: [loggedAtMs],
      );
      if (claims.isEmpty) continue;
      held.add(row.entryId);
    }
    return held;
  }

  /// The `loggedAt` of every watch-inbox row that carries a set the wrist
  /// logged in [sessionId], by slot (D-34).
  ///
  /// A row claims its group whether or not the phone has marked it applied:
  /// the importer writes an entry's rows *before* it marks the inbox row
  /// applied, so an interrupted import leaves the session's groups on a staged
  /// row. Reading only applied rows would leave those groups unclaimed and send
  /// the wrist its own set back under a phone id — a duplicate that never goes
  /// away, since staged rows are never deleted (the repository's contract).
  /// `originWatch` means the wrist wrote the row rather than this phone
  /// annotating one, so a phone-annotated row never claims its own group.
  Future<Map<String, List<int>>> _wristRowStamps(String sessionId) async {
    final stamps = <String, List<int>>{};
    final rows = await _repository.getWatchInboxEntriesForSession(sessionId);
    for (final row in rows) {
      if (row.origin != WatchInboxEntry.originWatch) continue;
      if (row.kind != WatchInboxEntry.kindSet) continue;

      final payload = row.payload;
      final slot = payload['sessionExerciseId'];
      final loggedAtMs = _loggedAtMs(payload['loggedAt']);
      if (slot is! String || slot.isEmpty || loggedAtMs == null) continue;
      (stamps[slot] ??= []).add(loggedAtMs);
    }
    for (final slot in stamps.keys) {
      stamps[slot]!.sort();
    }
    return stamps;
  }

  /// A wire instant in epoch ms, or null when the payload carries none.
  ///
  /// The importer reads `loggedAt` the same way, which is why the value is the
  /// shared identity of an imported entry: it is the `createdAtMs` the importer
  /// stamps on every row it writes for that entry.
  static int? _loggedAtMs(Object? value) => value is String
      ? DateTime.tryParse(value)?.toUtc().millisecondsSinceEpoch
      : null;

  /// One slot, as the protocol's `sessionExercise`.
  ///
  /// Null when the effort's exercise is not known here, or carries no
  /// capability: the schema refuses a slot with an empty capability list, and a
  /// wrist could not render one. The effort's row id IS the slot id (D-3), which
  /// is what lets a projection and the wrist's own ladder be the same session.
  Map<String, Object?>? _slotFor(SegmentEffort effort, WorkoutState target) {
    final exerciseId = effort.exerciseId;
    final exercise = target.getExercise(exerciseId);
    final capabilities = exercise?.capabilities ?? const <String>[];
    if (exerciseId == null || capabilities.isEmpty) return null;

    return <String, Object?>{
      'sessionExerciseId': effort.id,
      'exerciseId': exerciseId,
      'name': exercise?.name ?? exerciseId,
      if (_declaredKinds.contains(effort.effortKind))
        'effortKind': effort.effortKind,
      'capabilities': [...capabilities],
    };
  }

  /// Where the wrist is in the phone's ladder. A request reports no position, so
  /// it is the ladder's opening slot; a position the phone's shorter ladder no
  /// longer reaches is the last one it has.
  int _indexFor(Map<String, Object?>? incoming, int length) {
    final reported = incoming == null
        ? null
        : _asObject(incoming['payload'])['currentExerciseIndex'];
    if (reported is! int || reported < 0) return 0;
    return reported.clamp(0, length - 1);
  }

  /// States a revision for the ladder [slots] describe, so a ladder that has not
  /// changed keeps the revision already stated and a changed one is newer than
  /// anything the wrist holds.
  void _countRevision(
    Map<String, Object?>? incoming,
    String sessionId,
    List<Map<String, Object?>> slots,
  ) {
    final reported = incoming == null
        ? null
        : _asObject(incoming['payload'])['revision'];
    if (reported is int && reported > _projectedRevision) {
      _projectedRevision = reported;
    }

    final ladder = _ladderOf(sessionId, slots);
    if (ladder == _projectedLadder) return;
    _projectedLadder = ladder;
    _projectedRevision += 1;
  }

  /// The identity of a ladder as the wrist can see it: the facts a change to
  /// would make the wrist's copy stale.
  static String _ladderOf(
    String sessionId,
    List<Map<String, Object?>> slots,
  ) => [
    sessionId,
    for (final slot in slots)
      '${slot['sessionExerciseId']}:${slot['exerciseId']}:${slot['name']}:'
          '${(slot['capabilities']! as List).join(',')}:'
          '${slot['effortKind'] ?? ''}',
  ].join('|');

  /// The session a wrist frame names, or null when it names none.
  static String? _namedSession(Map<String, Object?> envelope) {
    final topLevel = envelope['sessionId'];
    if (topLevel is String) return topLevel;
    return envelope['payload'] is Map
        ? (envelope['payload']! as Map)['sessionId'] as String?
        : null;
  }

  /// A frame's payload, or an empty map when it carries none — a request frame
  /// has no payload at all, and a projection is composed for both kinds.
  static Map<String, Object?> _asObject(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

  /// Reports a refused adoption (D-10) once per (held, offered) pair.
  ///
  /// The pair is what the rule acted on, so a repeat of the same pair — the
  /// wrist re-sending a snapshot it has not converged — is the same decision
  /// again and says nothing new.
  void _reportSkipOnce(String heldSessionId, String offeredSessionId) {
    if (heldSessionId == _skippedHeldSessionId &&
        offeredSessionId == _skippedOfferedSessionId) {
      return;
    }
    _skippedHeldSessionId = heldSessionId;
    _skippedOfferedSessionId = offeredSessionId;
    _onSkipped(heldSessionId, offeredSessionId);
  }

  /// Adopts the converged snapshot the mirror holds, if it should be adopted.
  ///
  /// [converged] is `LiveSessionMirrorState.state` — the reconciler's own output
  /// for the session the wrist is running.
  Future<WatchSessionAdoption> consider(Map<String, Object?> converged) async {
    final target = _workoutState;
    if (target == null) return WatchSessionAdoption.unbound;

    final sessionId = converged['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      return WatchSessionAdoption.notRunning;
    }

    // D-2 adopts the session the wrist is *running*. A snapshot of one it has
    // ended is history, and history is the importer's business (`session_end`).
    if (converged['status'] != WatchSessionStatus.active) {
      return WatchSessionAdoption.notRunning;
    }

    // G1: a row that is already history is not adopted back into the phone's
    // live state. The phone ended this session — its own finish, or an earlier
    // import — and the wrist has not heard yet; loading it again would put a
    // finished session on the phone, and a second finish on it would land
    // nowhere. Nothing is written, nothing is loaded, and the router answers
    // the snapshot with the session's end so the wrist catches up.
    final existing = await _repository.getSession(sessionId);
    if (existing != null && existing.endedAtMs != null) {
      return WatchSessionAdoption.alreadyEnded;
    }

    final held = target.currentSession;
    if (held != null && held.id == sessionId) {
      // D-92: this phone holds the session, so the snapshot is not a fresh
      // adoption — but a slot the wrist added since the adoption is one the
      // phone's ladder grows by, add-only (D-92/D-93). Nothing else about the
      // snapshot is acted on: no deletion, no reorder, no rename, and no move
      // of the position or the status.
      final additions = _reconcile(sessionId, converged);
      if (additions.isNotEmpty) {
        await target.appendSessionSlots(additions, sessionId: sessionId);
      }
      return WatchSessionAdoption.alreadyHeld;
    }

    // D-93: the ever-seen set belongs to a session the phone holds. Once it
    // holds another one, nothing of the old session's set is worth keeping —
    // the phone is not reconciling snapshots for it any more.
    _everSeen.removeWhere((seenSessionId, _) => seenSessionId != held?.id);

    // D-10: only work logged in the session the phone holds makes the wrist's
    // one a conflict. An empty session is nothing to protect — the same way the
    // phone's own "not yet active" session (`hasActiveSession`) is nothing to
    // protect.
    if (held != null && target.hasActiveSession) {
      _reportSkipOnce(held.id, sessionId);
      return WatchSessionAdoption.refusedConflict;
    }

    // A row that is already there is an earlier adoption of this same session:
    // adopt it again by loading it. Once the phone holds the session it is the
    // structure authority for it (D-2), so a snapshot never rewrites its rows.
    try {
      if (existing == null) {
        await _adopt(sessionId, converged);
      }
      await target.loadHistoricalSession(sessionId);
    } catch (error, stack) {
      // Adoption is the one thing here that can fail for a reason that is not
      // the rule working — a row that cannot be written. That is a failure, and
      // it goes to the graph's hook; a refused adoption (D-10) is not, and goes
      // to `onSkipped`. The error still reaches whoever asked for the adoption.
      _onFailure(error, stack);
      rethrow;
    }
    return WatchSessionAdoption.adopted;
  }

  /// Routes a wrist `session_lifecycle` to the phone's own session (D-5).
  ///
  /// The wrist is the authority on when *its* session is over, so its end
  /// reaches the phone's copy through the ordinary finish: `completed` ends the
  /// session, `abandoned` discards it. Only the session the phone is holding is
  /// the wrist's to end — a lifecycle naming any other session, or none,
  /// changes nothing here, which is what keeps a stale or crossed message from
  /// closing a session the wrist never ran.
  ///
  /// A session this phone already finished is left alone: its end is the phone's
  /// own, and finishing it twice is not a second end (G1).
  Future<void> onLifecycle(Map<String, Object?> envelope) async {
    final target = _workoutState;
    if (target == null) return;

    final sessionId = _namedSession(envelope);
    if (sessionId == null || sessionId.isEmpty) return;

    final held = target.currentSession;
    if (held == null || held.id != sessionId) return;
    if (held.endedAtMs != null) return;

    switch (_asObject(envelope['payload'])['state']) {
      case WatchLifecycleState.completed:
        await _catchUpSessionRow(sessionId);
        await target.endSession();
      case WatchLifecycleState.abandoned:
        await target.discardCurrentSession();
    }
  }

  /// Brings the phone's own copy of [sessionId] up to the row before its finish
  /// writes that copy back (D-8).
  ///
  /// A wrist rating is applied to the session's row by the inbox, and the row
  /// is where a rating lands first; the phone's copy of the session is what the
  /// ordinary finish writes back, so a copy read before the rating arrived would
  /// take its end over it and drop the rating. Only the rating is carried over:
  /// it is the one field the wrist alone knows about a session this phone owns.
  Future<void> _catchUpSessionRow(String sessionId) async {
    final rating = (await _repository.getSession(sessionId))?.sessionFeeling;
    if (rating == null ||
        rating == _workoutState?.currentSession?.sessionFeeling) {
      return;
    }
    await _workoutState!.updateSessionFeeling(sessionId, rating);
  }

  /// Writes the adopted session: its row, its one segment, and one effort per
  /// slot — under the protocol's ids (D-3).
  Future<void> _adopt(String sessionId, Map<String, Object?> converged) async {
    final atMs = _clock().millisecondsSinceEpoch;
    await _repository.createSession(
      TrainingSession(
        id: sessionId,
        ownerUserId: LoggedEntryRows.ownerUserId,
        // A snapshot carries no start time, so the session starts when the phone
        // adopts it. That is also the stamp its rows carry, which keeps the
        // session's timeline readable without inventing a wrist timestamp.
        startedAtMs: atMs,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );

    final segment = LoggedEntryRows.defaultSegment(
      id: WatchSessionImporter.segmentIdFor(sessionId),
      sessionId: sessionId,
      atMs: atMs,
    );
    await _repository.createSegment(segment);

    var orderIndex = 0;
    for (final slot in _slots(converged)) {
      await _repository.createEffort(
        _effort(slot, segmentId: segment.id, orderIndex: orderIndex, atMs: atMs),
      );
      orderIndex += 1;
    }

    // The ladder the snapshot carries is one the phone now takes as its own, so
    // every slot in it counts as seen (D-93).
    _everSeen[sessionId] = _slotIds(converged);
  }

  /// The efforts [converged] adds to the session [sessionId] the phone holds,
  /// in the snapshot's order — the append D-92 asks for, and nothing else.
  ///
  /// Add-only: nothing is removed, reordered or renamed, the position and the
  /// status are not moved, and no timer is cleared — the phone's own rest and
  /// timed timers keep running while its ladder grows. An empty result means
  /// nothing is written and nothing is notified, which is what makes a
  /// redelivery, a converged projection and a stale ladder reintroducing a slot
  /// the phone already saw all silent.
  ///
  /// A slot is new when its id is not in the phone's ladder and no ladder the
  /// phone has taken for this session carried it (D-93): the ladder of every
  /// snapshot it has already applied, plus its own at each of these checks. That
  /// second half is what keeps the phone's own additions from reading as the
  /// wrist's, and what keeps a slot the phone added and then removed from being
  /// appended back by a snapshot older than the removal.
  ///
  /// Each addition takes the next index after the phone's own last one, so the
  /// snapshot's positions are not the phone's: an added slot the wrist placed
  /// mid-ladder is still appended last, and every existing order stays where it
  /// is. Among themselves the additions keep the snapshot's order.
  List<SegmentEffort> _reconcile(
    String sessionId,
    Map<String, Object?> converged,
  ) {
    final target = _workoutState;
    if (target == null) return const [];

    final seen = _everSeen.putIfAbsent(sessionId, () => <String>{});
    final held = <String>{};
    var nextOrderIndex = 0;
    for (final segment in target.segments) {
      for (final effort in target.getEffortsForSegment(segment.id)) {
        held.add(effort.id);
        if (effort.orderIndex >= nextOrderIndex) {
          nextOrderIndex = effort.orderIndex + 1;
        }
      }
    }
    seen.addAll(held);

    final atMs = _clock().millisecondsSinceEpoch;
    final segmentId = WatchSessionImporter.segmentIdFor(sessionId);
    final additions = <SegmentEffort>[];
    final slots = _slots(converged);
    for (final slot in slots) {
      final slotId = slot['sessionExerciseId'];
      if (slotId is! String || slotId.isEmpty) continue;
      if (held.contains(slotId) || !seen.add(slotId)) continue;
      additions.add(
        _effort(
          slot,
          segmentId: segmentId,
          orderIndex: nextOrderIndex,
          atMs: atMs,
        ),
      );
      nextOrderIndex += 1;
    }

    return additions;
  }

  /// The non-empty slot ids of [converged].
  Set<String> _slotIds(Map<String, Object?> converged) {
    final ids = <String>{};
    for (final slot in _slots(converged)) {
      final slotId = slot['sessionExerciseId'];
      if (slotId is String && slotId.isNotEmpty) ids.add(slotId);
    }
    return ids;
  }

  /// The converged ladder's slots, in order. The reconciler copies each slot
  /// verbatim, so `sessionExerciseId` and `capabilities` arrive intact.
  List<Map<String, Object?>> _slots(Map<String, Object?> converged) => [
    for (final slot in converged['exercises'] as List? ?? const [])
      if (slot is Map) slot.cast<String, Object?>(),
  ];

  /// One slot's effort. Its id is the slot's (D-3); the slot is the only thing
  /// that knows which exercise and which kind it carries.
  SegmentEffort _effort(
    Map<String, Object?> slot, {
    required String segmentId,
    required int orderIndex,
    required int atMs,
  }) {
    final exerciseId = slot['exerciseId'];
    return SegmentEffort(
      id: slot['sessionExerciseId'] as String,
      segmentId: segmentId,
      orderIndex: orderIndex,
      topLevelOrderIndex: orderIndex,
      effortKind: _effortKind(slot),
      exerciseId: exerciseId is String ? exerciseId : null,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    );
  }

  /// The kind a slot's effort logs as (D-7).
  ///
  /// A slot declares one when the routine that produced it did; otherwise it is
  /// the first capability it carries that decides. That order is the wrist's
  /// (`watch_logging_state.dart`), repeated here rather than imported: this is
  /// the phone reading a wire slot, and that file is the wrist surface's own
  /// state. A snapshot carries no modality, so a slot nothing decides logs sets
  /// — the same default a hand-made free session gets.
  String _effortKind(Map<String, Object?> slot) {
    final declared = slot['effortKind'];
    if (declared is String && _declaredKinds.contains(declared)) {
      return declared;
    }

    final capabilities = <String>{
      for (final capability in slot['capabilities'] as List? ?? const [])
        if (capability is String) capability,
    };
    for (final capability in _kindPrecedence) {
      if (capabilities.contains(capability)) {
        return ModalityConfig.effortKindFromMetric(capability);
      }
    }
    return ModalityConfig.forModality(null)?.effortKind ?? BlockTypes.set;
  }
}
