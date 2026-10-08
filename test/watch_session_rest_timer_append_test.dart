// A running rest timer survives the append a wrist snapshot asks for.
//
// Plan: `docs/plans/2026-10-06-17b-watch-auto-sync-pr2-plan/2026-10-06-17b-watch-auto-sync-pr2-plan.md`,
// Phase 1 — D-94. Scenario: S-110.
//
// Plain `test()`: a rest is a wall-clock record, so its timing is derived from
// the row at whatever `nowMs` the caller passes — no widget, no real clock, and
// no threshold to race. The snapshot arrives through the real mirror and router,
// the way every other adoption test delivers one.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, seedExercise;

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

    final transport = CaptureTransport();
    final inbox = WatchSessionInbox(
      repository: repository,
      transport: transport,
      clock: () => _at,
      onFailure: (error, stack) => fail('the session inbox failed: $error'),
    );
    final mirror = LiveSessionMirrorState(
      transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
      snapshot: watchSessionPlaceholder,
      validator: _validator,
    );
    final bridge = WatchSessionAdoptionBridge(
      repository: repository,
      clock: () => _at,
      onFailure: (error, stack) => fail('the bridge failed: $error'),
    );
    final state = WorkoutState(repository);
    bridge.bindWorkoutState(state);
    final router = WatchIncomingRouter(
      inbox: inbox,
      mirror: mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: NutritionState(repository),
        library: FoodLibraryState(repository),
        validator: _validator,
        transport: transport,
      ),
      adoption: bridge,
    );

    // The phone holds the wrist's session with `[A, B]` in it.
    await router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 3,
        currentExerciseIndex: 1,
        exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
        messageId: 'msg-s110-1',
      ),
    );
    final segmentId = state.segments.single.id;
    expect(
      [for (final effort in state.getEffortsForSegment(segmentId)) effort.id],
      ['sl-1', 'sl-2'],
    );

    // A rest is running on A: the open wall-clock record that logging a set
    // leaves behind (`restEndMs` null), which is what the session screen's rest
    // tile and the global timer read their elapsed count from. Rest is a
    // count-up with no length (D-160). It is started through
    // the live state, so it is in the timer manager and in the repository both.
    await state.recordRestStart('sl-1', 1);
    final restBefore = state.getEntryRests('sl-1').single;
    expect(restBefore.restEndMs, isNull, reason: 'the rest is running');
    expect(state.hasRestRecord('sl-1', 1), isTrue);

    // Elapsed time is derived from the record and the moment it is asked about,
    // so the same `now` can be asked again after the append.
    final nowMs = restBefore.restStartMs + 45000;
    expect(
      restBefore.elapsedSeconds(nowMs),
      45,
      reason: 'it counts from its own start',
    );
    final indexBefore = mirror.state['currentExerciseIndex'];

    var notifications = 0;
    state.addListener(() => notifications += 1);

    // The wrist adds C and sends the ladder it holds.
    await router.receive(
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
      [for (final effort in state.getEffortsForSegment(segmentId)) effort.id],
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

    final restAfter = state.getEntryRests('sl-1').single;
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
    expect(state.hasRestRecord('sl-1', 1), isTrue);
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
      mirror.state['currentExerciseIndex'],
      indexBefore,
      reason: 'the position the wrist reports is not moved',
    );
  });
}
