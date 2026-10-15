// A running rest timer survives the append a wrist snapshot asks for, a rest
// the wrist logged lands beside the phone's own running rest, and the wrist's
// own stop appends the rest row and reports it.
//
// Plan: `docs/plans/2026-10-06-17b-watch-auto-sync-pr2-plan/2026-10-06-17b-watch-auto-sync-pr2-plan.md`,
// Phase 1 — D-94. Scenario: S-110.
// Plan: `docs/plans/2026-10-08-18c-watch-rest-to-phone-plan/2026-10-08-18c-watch-rest-to-phone-plan.md`,
// Phase 2 — D-210. Scenario: S-320.
// Plan: `docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md`,
// Phase 1 — D-219. Scenario: S-320.
//
// Plain `test()`: a rest is a wall-clock record, so its timing is derived from
// the row at whatever `nowMs` the caller passes — no widget, no real clock, and
// no threshold to race. The snapshot arrives through the real mirror and router,
// the way every other adoption test delivers one.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, observationsUp, seedExercise;

final DateTime _at = DateTime.utc(2026, 10, 6, 12);

final SyncProtocolValidator _validator = loadProtocolValidator();

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(String sessionExerciseId, String exerciseId) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': const ['sets', 'reps', 'load'],
};

/// One `session_snapshot` from the wrist.
Map<String, Object?> _snapshot({
  required String sessionId,
  required int revision,
  required List<Map<String, Object?>> exercises,
  required String messageId,
  int currentExerciseIndex = 0,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-06T12:00:00Z',
  'payload': {
    'sessionId': sessionId,
    'revision': revision,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': currentExerciseIndex,
    'exercises': [...exercises],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// The set the wrist logged, and the rest that followed it.
const String _setAt = '2026-10-06T11:55:00Z';
const String _restStart = '2026-10-06T11:56:00Z';
const String _restEnd = '2026-10-06T11:57:10Z';
const String _endAt = '2026-10-06T12:00:00Z';

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

/// Deterministic clock: the wrist reads time only through its injected clock,
/// so a rest's window is asserted against instants, not counters.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

/// The `rest` events the wrist emitted, in the order they travelled.
List<Map<String, Object?>> _restEvents(List<Map<String, Object?>> frames) {
  final events = <Map<String, Object?>>[];
  for (final frame in frames) {
    if (frame['type'] != 'observations_up') continue;
    for (final event in (frame['payload']! as Map)['events']! as List) {
      final carried = Map<String, Object?>.from(event as Map);
      if (carried['kind'] == WatchObservationKind.rest) events.add(carried);
    }
  }
  return events;
}

/// One set the wrist logged.
Map<String, Object?> _set(String entryId) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': _setAt,
  'sessionExerciseId': 'sl-1',
  'exerciseId': 'ex-bench',
  'reps': 8,
  'loadKg': 40,
};

/// One rest the wrist observed, naming the entry it followed (18b D-166).
Map<String, Object?> _rest(String entryId, {String afterEntryId = 'sx-1'}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'rest',
  'loggedAt': _restEnd,
  'sessionExerciseId': 'sl-1',
  'exerciseId': 'ex-bench',
  'startedAt': _restStart,
  'endedAt': _restEnd,
  'afterEntryId': afterEntryId,
};

/// The wrist's own end for `s-w1`.
Map<String, Object?> _end() => {
  'entryId': 'end-s-w1',
  'eventId': 'end-s-w1',
  'kind': 'session_end',
  'loggedAt': _endAt,
  'startedAt': '2026-10-06T11:40:00Z',
  'endedAt': _endAt,
  'status': 'completed',
  'avgHeartRateBpm': 140,
  'maxHeartRateBpm': 165,
};

/// The phone's graph, Mock-only: the inbox, the mirror behind the router, the
/// adoption bridge and the live state it binds.
Future<
  ({
    WatchIncomingRouter router,
    LiveSessionMirrorState mirror,
    WorkoutState state,
  })
>
_phone(WorkoutRepository repository) async {
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => _at,
    onFailure: (error, stack) => fail('the bridge failed: $error'),
  );
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    clock: () => _at,
    onFailure: (error, stack) => fail('the session inbox failed: $error'),
    phoneOwnsSession: bridge.holdsSession,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: _validator,
  );
  final state = WorkoutState(repository);
  bridge.bindWorkoutState(state);
  return (
    router: WatchIncomingRouter(
      inbox: inbox,
      mirror: mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: NutritionState(repository),
        library: FoodLibraryState(repository),
        validator: _validator,
        transport: transport,
      ),
      adoption: bridge,
    ),
    mirror: mirror,
    state: state,
  );
}

void main() {
  test('S-110 a running rest survives the append', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    for (final exercise in const [
      ('ex-bench', 'Bench Press'),
      ('ex-squat', 'Back Squat'),
      ('ex-deadlift', 'Deadlift'),
    ]) {
      await seedExercise(
        repository,
        id: exercise.$1,
        name: exercise.$2,
        capabilities: const ['sets', 'reps', 'load'],
      );
    }

    final phone = await _phone(repository);

    // The phone holds the wrist's session with `[A, B]` in it.
    await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 3,
        currentExerciseIndex: 1,
        exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
        messageId: 'msg-s110-1',
      ),
    );
    final segmentId = phone.state.segments.single.id;
    expect(
      [
        for (final effort in phone.state.getEffortsForSegment(segmentId))
          effort.id,
      ],
      ['sl-1', 'sl-2'],
    );

    // A rest is running on A: the open wall-clock record that logging a set
    // leaves behind (`restEndMs` null), which is what the session screen's rest
    // tile and the global timer read their elapsed count from. Rest is a
    // count-up with no length (D-160). It is started through
    // the live state, so it is in the timer manager and in the repository both.
    await phone.state.recordRestStart('sl-1', 1);
    final restBefore = phone.state.getEntryRests('sl-1').single;
    expect(restBefore.restEndMs, isNull, reason: 'the rest is running');
    expect(phone.state.hasRestRecord('sl-1', 1), isTrue);

    // Elapsed time is derived from the record and the moment it is asked about,
    // so the same `now` can be asked again after the append.
    final nowMs = restBefore.restStartMs + 45000;
    expect(
      restBefore.elapsedSeconds(nowMs),
      45,
      reason: 'it counts from its own start',
    );
    final indexBefore = phone.mirror.state['currentExerciseIndex'];

    var notifications = 0;
    phone.state.addListener(() => notifications += 1);

    // The wrist adds C and sends the ladder it holds.
    await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 4,
        currentExerciseIndex: 1,
        exercises: [
          _slot('sl-1', 'ex-bench'),
          _slot('sl-2', 'ex-squat'),
          _slot('sl-3', 'ex-deadlift'),
        ],
        messageId: 'msg-s110-2',
      ),
    );

    expect(
      [
        for (final effort in phone.state.getEffortsForSegment(segmentId))
          effort.id,
      ],
      ['sl-1', 'sl-2', 'sl-3'],
      reason: 'D-92 C exists: the append landed',
    );
    expect(
      notifications,
      1,
      reason:
          'D-94 one notify for the append — not the reload a session load does, '
          'which notifies three times and clears every timer',
    );

    final restAfter = phone.state.getEntryRests('sl-1').single;
    expect(restAfter.id, restBefore.id);
    expect(
      restAfter.restStartMs,
      restBefore.restStartMs,
      reason: 'the same record is still open, un-restarted',
    );
    expect(
      restAfter.restEndMs,
      isNull,
      reason: 'the rest is still running: the append closed nothing',
    );
    expect(phone.state.hasRestRecord('sl-1', 1), isTrue);
    expect(
      restAfter.elapsedSeconds(nowMs),
      restBefore.elapsedSeconds(nowMs),
      reason: 'and it is still counting to the same end',
    );
    expect(
      (await repository.getEntryRests('sl-1')).map((rest) => rest.toMap()),
      [restBefore.toMap()],
      reason: 'no rest row was deleted or rewritten',
    );
    expect(
      phone.mirror.state['currentExerciseIndex'],
      indexBefore,
      reason: 'the position the wrist reports is not moved',
    );
  });

  test('S-320 a wrist rest lands beside the phone\'s running rest', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    for (final exercise in const [
      ('ex-bench', 'Bench Press'),
      ('ex-squat', 'Back Squat'),
    ]) {
      await seedExercise(
        repository,
        id: exercise.$1,
        name: exercise.$2,
        capabilities: const ['sets', 'reps', 'load'],
      );
    }

    final phone = await _phone(repository);
    await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 3,
        exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
        messageId: 'msg-s320-1',
      ),
    );

    // A rest is running on A, counted from the phone's own entry at index 0:
    // open, with no end (D-160). It is the record the rest tile and the global
    // timer read their elapsed count from.
    await phone.state.recordRestStart('sl-1', 0);
    final running = phone.state.getEntryRests('sl-1').single;
    expect(running.restEndMs, isNull, reason: 'the phone\'s rest is running');
    final nowMs = running.restStartMs + 45000;

    // The wrist sends the set it logged, the rest that followed it, and its end.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-1'),
        _rest('rest-a1'),
        _end(),
      ], messageId: 'msg-s320-2'),
    );

    final rows = await repository.getEntryRests('sl-1');
    expect(
      [for (final row in rows) row.entryIndex],
      [0, 1],
      reason:
          'S-320 the running rest keeps its spot, and the wrist\'s rest lands '
          'after the set the wrist logged',
    );
    final wristRest = rows.singleWhere((row) => row.entryIndex == 1);
    expect(wristRest.id, 'rest-sl-1-1', reason: 'S-320 D-167\'s id');
    expect(
      wristRest.restStartMs,
      _msOf(_restStart),
      reason: 'S-320 the window the wrist observed',
    );
    expect(
      wristRest.restEndMs,
      _msOf(_restEnd),
      reason: 'S-320 and the end it observed',
    );

    final stillRunning = phone.state
        .getEntryRests('sl-1')
        .firstWhere((rest) => rest.entryIndex == 0);
    expect(
      stillRunning.id,
      running.id,
      reason: 'S-320 the phone\'s own rest is the same record',
    );
    expect(
      stillRunning.restEndMs,
      isNull,
      reason: 'S-320 the import closed no rest of the phone\'s',
    );
    expect(
      stillRunning.elapsedSeconds(nowMs),
      running.elapsedSeconds(nowMs),
      reason: 'S-320 the running timer still counts to the same end',
    );
    expect(
      phone.state.hasRestRecord('sl-1', 0),
      isTrue,
      reason: 'S-320 the timer the phone started is still running',
    );
  });

  test('S-320 the wrist\'s stop appends the rest row and emits it', () async {
    final clock = _Clock(_at);
    final store = InMemoryWatchSessionStore();
    final emitted = <Map<String, Object?>>[];
    final engine = WatchSessionEngine(
      store,
      clock: clock.call,
      onEmit: emitted.add,
      sessionIdFactory: () => 's-w1',
    );
    await engine.createSession(
      modality: 'resistance_lifting',
      exercises: [_slot('sl-1', 'ex-bench')],
    );
    final surface = WatchLoggingState(engine: engine, clock: clock.call);

    // The set the wrist logs leaves a rest running behind it. A rest is a
    // count-up with no length (D-160), so only its start is known until the
    // wrist stops it.
    await surface.log();
    final setEntryId = engine.observations.single.entryId;
    clock.advance(const Duration(seconds: 45));
    await surface.endRest();

    final restRows = [
      for (final row in (await store.readAll()).timers)
        if (row.kind == WatchTimerKind.rest) row,
    ];
    expect(
      restRows,
      hasLength(2),
      reason: 'the row that ran, and the row the stop appended',
    );
    final stopped = restRows.last;
    expect(stopped.startedAt, _at, reason: 'it started where the set was logged');
    expect(stopped.stoppedAt, clock.now, reason: 'it stopped at the tap instant');
    expect(stopped.state, WatchTimerState.stopped);

    final rests = _restEvents(emitted);
    expect(rests, hasLength(1), reason: 'S-320 one rest ended, one event');
    expect(rests.single['startedAt'], utcIso(_at));
    expect(rests.single['endedAt'], utcIso(clock.now));
    expect(
      rests.single['afterEntryId'],
      setEntryId,
      reason: 'S-320 the rest names the set it followed',
    );
    expect(
      rests.single['eventId'],
      '${stopped.recordId}-rest',
      reason: 'the event is derived from the row, so a re-send is the same one',
    );
  });
}
