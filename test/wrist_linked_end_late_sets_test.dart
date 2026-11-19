// Plan 218 P2 — a wrist-linked workout's end drops its planned sets, and
// nothing that arrives afterwards is lost.
//
// Plan: `docs/plans/2026-11-16-218-wrist-linked-workouts-drop-planned-sets-plan/2026-11-16-218-wrist-linked-workouts-drop-planned-sets-plan.md`,
// Scout findings 2, 4, 5, D-1..D-3. Scenario mapping:
//   S-21804 the end before the sets drops the planned set, keeps the
//           exercise, and a late wrist set still lands
//   S-21805 a wrist set half written when the end arrives is not dropped
//   S-21806 a set typed into the finished workout is not touched by a later
//           wrist pass
//
// The harness is the one `test/watch_session_finish_test.dart` builds, with
// one change: the phone's state gets the inbox's import chain
// (`afterPendingWristImports`), the way `createWatchSync` wires it. Plain
// `test()`: no widget is involved, no Hive — these tests await real futures.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart'
    show watchSessionPlaceholder;
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, observationsUp, seedExercise;

/// The phone's clock, pinned: every stamp the inbox writes is the same in
/// both arrival orders.
final DateTime _phoneNow = DateTime.utc(2026, 10, 5, 12);

final SyncProtocolValidator _validator = loadProtocolValidator();

Future<WorkoutRepository> _repository() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await seedExercise(
    repository,
    id: 'ex-bench',
    name: 'Barbell Bench Press',
    capabilities: [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.load,
    ],
  );
  await seedExercise(
    repository,
    id: 'ex-squat',
    name: 'Barbell Back Squat',
    capabilities: [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.load,
    ],
  );
  return repository;
}

/// One phone, wired the way `createWatchSync` wires it: the adoption bridge
/// first, the inbox that asks it whether a session is the phone's own, the
/// mirror behind the entry-staging transport, and the router that drives them.
class _Phone {
  _Phone({
    required this.router,
    required this.mirror,
    required this.state,
    required this.bridge,
    required this.transport,
    required this.failures,
  });

  final WatchIncomingRouter router;
  final LiveSessionMirrorState mirror;
  final WorkoutState state;
  final WatchSessionAdoptionBridge bridge;
  final CaptureTransport transport;

  /// What the graph reported as a failure: nothing, in these tests.
  final List<Object> failures;
}

Future<_Phone> _phone(
  WorkoutRepository repository, {
  DateTime Function()? bridgeClock,
}) async {
  final failures = <Object>[];
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: bridgeClock ?? () => _phoneNow,
    onFailure: (error, stack) => failures.add(error),
  );
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: _validator,
    clock: () => _phoneNow,
    onFailure: (error, stack) => fail('the watch session inbox failed: $error'),
    phoneOwnsSession: bridge.holdsSession,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: _validator,
    projection: bridge.projectSession,
  );
  // Plan 218: the state's finish drop runs behind the inbox's queued import
  // passes, the way `createWatchSync` wires it.
  final state = WorkoutState(
    repository,
    afterPendingWristImports: inbox.afterPendingImports,
  );
  bridge.bindWorkoutState(state);

  return _Phone(
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
    bridge: bridge,
    transport: transport,
    failures: failures,
  );
}

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(String sessionExerciseId, String exerciseId) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.load,
  ],
};

/// One `session_snapshot` from the wrist.
Map<String, Object?> _snapshot({
  String sessionId = 's-w1',
  int revision = 3,
  String status = WatchSessionStatus.active,
  int currentExerciseIndex = 1,
  String messageId = 'msg-snapshot',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-05T10:00:00Z',
  'payload': {
    'sessionId': sessionId,
    'revision': revision,
    'status': status,
    'currentExerciseIndex': currentExerciseIndex,
    'exercises': [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// One `session_lifecycle` from the wrist, as the shipping watch emits it.
Map<String, Object?> _lifecycle(
  String sessionId, {
  String state = WatchLifecycleState.completed,
  String messageId = 'msg-wrist-lifecycle',
  String at = '2026-10-05T10:30:00Z',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'watch',
  'sentAt': at,
  'payload': {'state': state, 'at': at},
};

/// A set the wrist logged, naming the slot it belongs to.
Map<String, Object?> _set(String entryId, {required String slot}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': '2026-10-05T10:10:00Z',
  'sessionExerciseId': slot,
  'exerciseId': slot == 'sl-1' ? 'ex-bench' : 'ex-squat',
  'reps': 5,
  'loadKg': 80,
};

/// The ids of the efforts the phone holds for the adopted session.
Future<List<String>> _effortIds(WorkoutRepository repository) async {
  final segments = await repository.getSessionSegments('s-w1');
  return [
    for (final segment in segments)
      ...await repository.getSegmentEfforts(segment.id),
  ].map((effort) => effort.id).toList();
}

/// An effort's set entries as the store holds them.
Future<List<Map<String, dynamic>>> _sets(
  WorkoutRepository repository,
  String effortId,
) async => [
  for (final group in EntryRows.setGroups(
    await repository.getEffortObservations(effortId),
  ))
    group.entry,
];

/// The indexes of [effortId]'s rests in the store.
Future<List<int>> _restIndexes(
  WorkoutRepository repository,
  String effortId,
) async => [
  for (final rest in await repository.getEntryRests(effortId)) rest.entryIndex,
];

/// A repository that holds the merge pass's first `createEntryRest` — the
/// instant a wrist set's row is written and its rest is not yet — until the
/// test releases it, so the wrist's end can arrive in that gap (S-21805).
class _GatedRestRepository extends MockWorkoutRepository {
  /// Completed when the first rest write is reached.
  final Completer<void> reached = Completer<void>();

  /// Completed by the test to let the rest write through.
  final Completer<void> gate = Completer<void>();

  bool _heldFirst = false;

  @override
  Future<String> createEntryRest(EntryRest rest) async {
    if (!_heldFirst) {
      _heldFirst = true;
      reached.complete();
      await gate.future;
    }
    return super.createEntryRest(rest);
  }
}

void main() {
  test('S-21804 the end before the sets drops the planned set, keeps the '
      'exercise, and a late wrist set still lands', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    expect(
      await _effortIds(repository),
      ['sl-1', 'sl-2'],
      reason: 'the phone holds an effort per slot the wrist announced',
    );

    // The wrist ends its session with nothing logged yet.
    await phone.router.receive(_lifecycle('s-w1'));

    expect(
      (await repository.getSession('s-w1'))!.endedAtMs,
      isNotNull,
      reason: 'the wrist\'s end closes the phone\'s copy of the session',
    );
    expect(
      await _sets(repository, 'sl-1'),
      isEmpty,
      reason: 'plan 218: the planned set nobody logged goes',
    );
    expect(await _sets(repository, 'sl-2'), isEmpty);
    expect(
      await _effortIds(repository),
      ['sl-1', 'sl-2'],
      reason:
          'plan 218: the exercises stay for the late wrist sets a removed '
          'exercise would lose',
    );

    // A late wrist set arrives for the bench.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-1', slot: 'sl-1'),
      ], messageId: 'msg-set-1'),
    );

    final bench = await _sets(repository, 'sl-1');
    expect(bench, hasLength(1), reason: 'the late set is stored, nothing lost');
    expect(bench.single['reps'], 5);
    expect(bench.single['weight'], 80);
    expect(
      await _restIndexes(repository, 'sl-1'),
      [1],
      reason: 'the late set is logged: a rest sits at its position + 1',
    );
    expect(
      await _sets(repository, 'sl-2'),
      isEmpty,
      reason: 'the squat still holds no set',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-21805 a wrist set half written when the end arrives is not dropped',
      () async {
    final repository = _GatedRestRepository();
    await repository.initialize();
    await seedExercise(
      repository,
      id: 'ex-bench',
      name: 'Barbell Bench Press',
      capabilities: [
        ExerciseCapability.sets,
        ExerciseCapability.reps,
        ExerciseCapability.load,
      ],
    );
    await seedExercise(
      repository,
      id: 'ex-squat',
      name: 'Barbell Back Squat',
      capabilities: [
        ExerciseCapability.sets,
        ExerciseCapability.reps,
        ExerciseCapability.load,
      ],
    );
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // The merge pass for the wrist set starts and pauses between the set's
    // row write and its rest write.
    final pass = phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-1', slot: 'sl-1'),
      ], messageId: 'msg-set-1'),
    );
    await repository.reached.future;

    // The wrist's end arrives while the pass is still holding the store.
    final end = phone.router.receive(_lifecycle('s-w1'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      (await repository.getSession('s-w1'))!.endedAtMs,
      isNull,
      reason: 'the end waits behind the pass that is writing the set (D-3)',
    );

    repository.gate.complete();
    await Future.wait([pass, end]);

    expect(
      (await repository.getSession('s-w1'))!.endedAtMs,
      isNotNull,
      reason: 'the end lands once the pass has settled',
    );
    final bench = await _sets(repository, 'sl-1');
    expect(
      bench,
      hasLength(1),
      reason:
          'nothing was lost: the prune ran after the pass and the set it read '
          'was already logged',
    );
    expect(bench.single['reps'], 5);
    expect(bench.single['weight'], 80);
    expect(
      await _restIndexes(repository, 'sl-1'),
      [1],
      reason: 'the set kept its rest: the row and the rest were never split',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-21806 a set typed into the finished workout is not touched by a '
      'later wrist pass', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await phone.router.receive(_lifecycle('s-w1'));
    expect(
      (await repository.getSession('s-w1'))!.endedAtMs,
      isNotNull,
      reason: 'the fixture: the workout is finished',
    );

    // The user opens the finished, held workout and types a set with no rest,
    // the way `test/finish_drops_unlogged_sets_test.dart` S-15705 does.
    // The guard: the drop runs once, at the end, and a later pass must neither
    // run it again (it would delete this rest-less typed set) nor let the late
    // wrist set FILL it (`_plannedSetToFill` reads a rest-less row as planned;
    // an ended workout has no planned sets, so the importer appends there,
    // `fillPlannedSets: existing.endedAtMs == null`).
    await phone.state.addEntry('sl-1');
    await phone.state.updateEntryValue('sl-1', 0, 'reps', 8);
    await phone.state.updateEntryValue('sl-1', 0, 'weight', 40.0);

    // A late wrist set arrives for the same effort and its pass settles.
    await phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-1', slot: 'sl-1'),
      ], messageId: 'msg-set-1'),
    );

    final bench = await _sets(repository, 'sl-1');
    expect(
      bench,
      hasLength(2),
      reason:
          'the prune ran once at the end, never on the later pass: the typed '
          'set and the wrist set both stay',
    );
    expect(bench[0]['reps'], 8, reason: 'the set the user typed stays');
    expect(bench[0]['weight'], 40.0);
    expect(bench[1]['reps'], 5, reason: 'the wrist set is stored too');
    expect(bench[1]['weight'], 80);
    expect(phone.failures, isEmpty);
  });
}
