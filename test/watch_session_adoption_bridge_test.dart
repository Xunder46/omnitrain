// A session the wrist is running becomes the phone's own in-progress session.
//
// Plan: `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/2026-10-05-15a-watch-session-sync-pr1-plan.md`,
// Phase 2 — D-2, D-3, D-6, D-7, D-10.
// Scenario mapping:
//   S-1 a wrist-started free session becomes the phone's in-progress session
//       → `S-1 a wrist snapshot ...`, `S-1 Mock and Hive ...`, `S-1 a restart ...`,
//         `S-1 the adopted session survives checkForInProgressSession ...`
//   S-3 an empty wrist session does not surface as active → `S-3 ...`
//   S-6 the phone keeps the session it already has → `S-6 ...`, `S-6 counter-case ...`
//
// Plan: `docs/plans/2026-10-06-17b-watch-auto-sync-pr2-plan/2026-10-06-17b-watch-auto-sync-pr2-plan.md`,
// Phase 1 — D-92, D-93, D-94: a snapshot of the session the phone already holds
// is reconciled add-only. Scenario mapping:
//   S-102 a slot the wrist added to the held session → `S-102 ...`
//   S-104 a snapshot with no new slot changes nothing → `S-104 ...`
//   S-105 a phone-side rename is not undone → `S-105 ...`
//   S-106 the phone's own session is not taken away → `S-106 ...`
//   (S-103 and S-111 need the app's own screen and live in
//    `test/watch_session_adoption_build_notify_test.dart`.)
//
// Plan: `docs/plans/2026-10-06-17c-watch-auto-sync-pr3-plan/2026-10-06-17c-watch-auto-sync-pr3-plan.md`,
// review 1, F4 — D-112: the ids the push holds and the groups the projection
// claims are read in one pass over a slot's stamps.
//   F4 two rows of one slot sharing a stamp hold one id → `F4 ...`
//
// Plan: `docs/plans/2026-10-07-17d-watch-auto-sync-pr4-plan/2026-10-07-17d-watch-auto-sync-pr4-plan.md`,
// Phase 3 item 0 — D-133: a claimed record answers the row whose stamp claimed
// it, whatever position the record holds in its own list.
//   S-144 the ledger holds the row the claim names → `S-144 the ledger holds ...`
//
// Every snapshot arrives through the real `LiveSessionMirrorState` behind the
// real `WatchIncomingRouter`, so the bridge reads the reconciler's own converged
// output and the wiring is part of what these tests prove. Plain `test()`: no
// widget is involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
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
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/repository_harness.dart';
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, importedEfforts, importedRows, importedSegment;

/// The phone's clock, pinned: every row an adoption writes carries the same
/// stamps on both implementations, which is what makes the parity dump compare.
final DateTime _adoptedAt = DateTime.utc(2026, 10, 5, 12);

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
  // The harness writes an exercise's capabilities through its constructor, and
  // neither implementation keeps them there: both read them from a store of
  // their own (`_exerciseCapabilities` in the in-memory twin). Set them the way
  // the app does, or every slot this session projects is unrenderable and
  // `projectSession` has no ladder to speak from.
  for (final id in const ['ex-bench', 'ex-squat']) {
    await repository.setExerciseCapabilities(id, const [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.load,
    ]);
  }
  return repository;
}

/// A repository whose session writes fail: the adoption a wrist snapshot asks
/// for, with a disk that will not take the row. Everything else behaves as the
/// in-memory twin does.
class _UnwritableRepository extends MockWorkoutRepository {
  @override
  Future<String> createSession(TrainingSession session) async {
    throw StateError('the session row cannot be written');
  }
}

/// One phone, wired the way `createWatchSync` wires it: the watch session inbox,
/// the mirror behind the entry-staging transport, the router that drives them,
/// and the bridge bound to a real `WorkoutState`.
class _Phone {
  _Phone({
    required this.router,
    required this.mirror,
    required this.state,
    required this.bridge,
    required this.transport,
    required this.failures,
    required this.skipped,
  });

  final WatchIncomingRouter router;
  final LiveSessionMirrorState mirror;
  final WorkoutState state;
  final WatchSessionAdoptionBridge bridge;

  /// What the phone sent. The mirror's own answers live here too, which is what
  /// tells a frame this phase composes apart from one it does not.
  final CaptureTransport transport;

  /// What the bridge reported as a failure: nothing, in these tests.
  final List<Object> failures;

  /// Every D-10 skip the bridge reported, in order, as the (held, offered)
  /// session ids it acted on.
  final List<({String held, String offered})> skipped;
}

Future<_Phone> _phone(WorkoutRepository repository) async {
  final failures = <Object>[];
  final skipped = <({String held, String offered})>[];
  final transport = CaptureTransport();
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    clock: () => _adoptedAt,
    onFailure: (error, stack) => fail('the watch session inbox failed: $error'),
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: _validator,
  );
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => _adoptedAt,
    onFailure: (error, stack) => failures.add(error),
    onSkipped: (held, offered) => skipped.add((held: held, offered: offered)),
  );
  final state = WorkoutState(repository);
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
    skipped: skipped,
  );
}

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slot(
  String sessionExerciseId,
  String exerciseId, {
  List<String> capabilities = const [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.load,
  ],
  String? declaredKind,
}) => {
  'sessionExerciseId': sessionExerciseId,
  'exerciseId': exerciseId,
  'name': exerciseId,
  'capabilities': capabilities,
  'effortKind': ?declaredKind,
};

/// One `session_snapshot` from the wrist.
Map<String, Object?> _snapshot({
  required String sessionId,
  required int revision,
  List<Map<String, Object?>> exercises = const [],
  String status = WatchSessionStatus.active,
  int currentExerciseIndex = 0,
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
    'exercises': [...exercises],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// S-1's wrist session: `s-w1`, on the second of two set slots, nothing logged.
Map<String, Object?> _s1Envelope() => _snapshot(
  sessionId: 's-w1',
  revision: 3,
  currentExerciseIndex: 1,
  exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
  messageId: 'msg-s1',
);

/// The rows a phone session the user is already running has: its own id family,
/// one segment, one effort per exercise — and, for an active one, a logged entry.
Future<void> _seedPhoneSession(
  WorkoutRepository repository, {
  required String sessionId,
  List<(String effortId, String exerciseId)> efforts = const [],
  List<String> kinds = const [],
  String? loggedEffortId,
}) async {
  const at = 1780000000000;
  await repository.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: LoggedEntryRows.ownerUserId,
      startedAtMs: at,
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
  final segmentId = 'segment-$sessionId';
  await repository.createSegment(
    LoggedEntryRows.defaultSegment(
      id: segmentId,
      sessionId: sessionId,
      atMs: at,
    ),
  );
  for (final (index, effort) in efforts.indexed) {
    await repository.createEffort(
      SegmentEffort(
        id: effort.$1,
        segmentId: segmentId,
        orderIndex: index,
        topLevelOrderIndex: index,
        effortKind: kinds.isEmpty ? BlockTypes.set : kinds[index],
        exerciseId: effort.$2,
        createdAtMs: at,
        updatedAtMs: at,
      ),
    );
  }
  if (loggedEffortId != null) {
    await repository.createObservation(repsRow(loggedEffortId, 0, 5, atMs: at));
  }
}

/// Counts the notifications [state] fires from now on.
///
/// A reader over a counter, so a test can hold one and read it before and after
/// a delivery — which is what makes D-94's "exactly one" and D-92's "nothing
/// changed, nothing notified" observable.
int Function() _notifications(WorkoutState state) {
  var count = 0;
  state.addListener(() => count += 1);
  return () => count;
}

/// The ladder one `session_snapshot` the phone sent carries, by slot id.
List<Object?> _sentLadder(Map<String, Object?> envelope) => [
  for (final slot in (envelope['payload'] as Map)['exercises'] as List)
    (slot as Map)['sessionExerciseId'],
];

void main() {
  test('S-1 a wrist snapshot becomes the phone\'s in-progress session', () async {
    final repository = await _repository();
    final phone = await _phone(repository);

    final receipt = await phone.router.receive(_s1Envelope());

    // The mirror is still the reconciler: the bridge projects its verdict, it
    // does not replace it.
    expect(receipt.session, MirrorOutcome.applied);
    expect([for (final slot in phone.mirror.exercises) slot['exerciseId']], [
      'ex-bench',
      'ex-squat',
    ]);

    final session = await repository.getSession('s-w1');
    expect(session, isNotNull, reason: 'S-1 the wrist session is a real row');
    expect(session!.ownerUserId, LoggedEntryRows.ownerUserId);
    expect(
      session.modality,
      isNull,
      reason: 'D-7 a wrist free session is Free Training',
    );
    expect(session.endedAtMs, isNull, reason: 'D-2 an in-progress session');
    expect(session.isRolling, isFalse);

    final segment = await importedSegment(repository, 's-w1');
    final efforts = await importedEfforts(repository, 's-w1');
    expect(
      [for (final effort in efforts) effort.id],
      ['sl-1', 'sl-2'],
      reason: 'D-3 each effort row id IS its slot id, in ladder order',
    );
    expect(
      [for (final effort in efforts) effort.exerciseId],
      ['ex-bench', 'ex-squat'],
    );
    expect(
      [for (final effort in efforts) effort.effortKind],
      [BlockTypes.set, BlockTypes.set],
    );
    expect([for (final effort in efforts) effort.orderIndex], [0, 1]);
    expect(
      [for (final effort in efforts) effort.segmentId],
      [segment.id, segment.id],
      reason: 'S-1 one default segment holds the whole ladder',
    );

    // What the phone renders: the home's Free Training tile is active, and the
    // regular session screen opens on this ladder.
    expect(phone.state.currentSession?.id, 's-w1');
    expect(phone.state.hasActiveSession, isTrue, reason: 'D-6, AC2');
    expect(phone.state.segments, hasLength(1));
    expect(
      [
        for (final effort in phone.state.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['sl-1', 'sl-2'],
    );
    expect(phone.failures, isEmpty);
  });

  test('S-1 Mock and Hive adopt the same rows', () async {
    final dumps = <String, Map<String, Object?>>{};

    for (final factory in harnessFactories) {
      final harness = factory();
      final repository = await harness.open();
      try {
        final phone = await _phone(repository);
        await phone.router.receive(_s1Envelope());

        dumps[harness.name] = await importedRows(repository, 's-w1');
        expect(
          phone.state.hasActiveSession,
          isTrue,
          reason: '${harness.name}: the adopted ladder is live state',
        );
      } finally {
        await harness.close();
      }
    }

    expect(dumps['Hive'], dumps['Mock']);
  });

  test('S-1 a restart resolves the same session and slot ids', () async {
    for (final factory in harnessFactories) {
      final harness = factory();
      final repository = await harness.open();
      try {
        await (await _phone(repository)).router.receive(_s1Envelope());

        final state = WorkoutState(await harness.restart());
        await state.loadHistoricalSession('s-w1');

        expect(state.currentSession?.id, 's-w1', reason: '${harness.name}: D-3');
        expect(
          state.hasActiveSession,
          isTrue,
          reason:
              '${harness.name}: it is still the phone\'s in-progress session',
        );
        expect(
          [
            for (final effort
                in state.getEffortsForSegment(state.segments.single.id))
              effort.id,
          ],
          ['sl-1', 'sl-2'],
          reason: '${harness.name}: the slot ids survive the restart unchanged',
        );
      } finally {
        await harness.close();
      }
    }
  });

  test('S-3 an empty wrist session is adopted but reads "not yet active"',
      () async {
    final repository = await _repository();
    final phone = await _phone(repository);

    await phone.router.receive(
      _snapshot(sessionId: 's-w0', revision: 1, messageId: 'msg-s3'),
    );

    expect((await repository.getSession('s-w0'))?.endedAtMs, isNull);
    final segments = await repository.getSessionSegments('s-w0');
    expect(segments, hasLength(1));
    expect(await repository.getSegmentEfforts(segments.single.id), isEmpty);

    expect(phone.state.currentSession?.id, 's-w0');
    expect(
      phone.state.hasActiveSession,
      isFalse,
      reason:
          'D-6, AC5: zero efforts reads exactly like a just-created phone '
          'session, so nothing offers it as active and nothing navigates',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6 the phone keeps the session it is already running', () async {
    final repository = await _repository();
    await _seedPhoneSession(
      repository,
      sessionId: 'session-phone-1',
      efforts: const [
        ('effort-a', 'ex-bench'),
        ('effort-b', 'ex-squat'),
      ],
      loggedEffortId: 'effort-a',
    );
    final phone = await _phone(repository);
    await phone.state.loadHistoricalSession('session-phone-1');
    expect(phone.state.hasActiveSession, isTrue);

    final rows = await importedRows(repository, 'session-phone-1');
    final sessions = (await repository.getAllSessions()).length;

    final receipt = await phone.router.receive(
      _snapshot(
        sessionId: 's-w2',
        revision: 1,
        exercises: [_slot('sl-1', 'ex-deadlift')],
        messageId: 'msg-s6',
      ),
    );

    expect(
      receipt.session,
      MirrorOutcome.applied,
      reason: 'D-10 sits above the reconciler: the mirror still switches',
    );
    expect(
      phone.mirror.state['sessionId'],
      's-w2',
      reason: 'the protocol projection follows the wrist',
    );

    expect(
      await repository.getSession('s-w2'),
      isNull,
      reason: 'D-10 the wrist session is not adopted',
    );
    expect(phone.state.currentSession?.id, 'session-phone-1');
    expect(phone.state.hasActiveSession, isTrue);
    expect(
      (await repository.getAllSessions()).length,
      sessions,
      reason: 'S-6 no history row is created',
    );
    expect(
      await importedRows(repository, 'session-phone-1'),
      rows,
      reason: 'S-6 the phone\'s rows, entries and segment are untouched',
    );

    expect(
      phone.skipped,
      [(held: 'session-phone-1', offered: 's-w2')],
      reason: 'D-10 the skipped adoption is reported, not dropped',
    );
    expect(
      phone.failures,
      isEmpty,
      reason:
          'D-10 refusing is the rule working: the skip is not a failure and '
          'carries no stack',
    );

    // The wrist re-sends the snapshot it holds, because it has not converged
    // yet. The same decision again is not a second skip to report.
    expect(
      await phone.bridge.consider(phone.mirror.state),
      WatchSessionAdoption.refusedConflict,
      reason: 'the same pair is refused again',
    );
    expect(
      phone.skipped,
      hasLength(1),
      reason: 'D-10 the skip is reported once per (held, offered) pair',
    );
  });

  test('S-6 counter-case an empty phone session does not block adoption',
      () async {
    final repository = await _repository();
    await _seedPhoneSession(repository, sessionId: 'session-phone-empty');
    final phone = await _phone(repository);
    await phone.state.loadHistoricalSession('session-phone-empty');
    expect(phone.state.hasActiveSession, isFalse);

    await phone.router.receive(
      _snapshot(
        sessionId: 's-w2',
        revision: 1,
        exercises: [_slot('sl-1', 'ex-deadlift')],
        messageId: 'msg-s6-counter',
      ),
    );

    expect(
      await repository.getSession('s-w2'),
      isNotNull,
      reason: 'D-10: an empty session is nothing to protect',
    );
    expect(phone.state.currentSession?.id, 's-w2');
    expect(phone.state.hasActiveSession, isTrue);
    expect(
      [
        for (final effort in await importedEfforts(repository, 's-w2'))
          effort.exerciseId,
      ],
      ['ex-deadlift'],
    );
    expect(phone.failures, isEmpty);
  });

  test('a second snapshot of the session the phone holds does not rewrite it',
      () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_s1Envelope());
    final rows = await importedRows(repository, 's-w1');

    // The same ladder again: nothing to adopt, and nothing written.
    final again = await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 4,
        currentExerciseIndex: 1,
        exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
        messageId: 'msg-again',
      ),
    );
    expect(again.session, MirrorOutcome.applied);
    expect(await importedRows(repository, 's-w1'), rows);
    expect(
      await phone.bridge.consider(phone.mirror.state),
      WatchSessionAdoption.alreadyHeld,
      reason: 'D-2: the phone holds this session, so there is nothing to adopt',
    );

    // A ladder the wrist rewrote. The row it replaced the ladder with carries a
    // slot the phone has never seen; the phone appends that one and keeps its
    // own two where they are (D-92/D-93). The mirror applies the frame and
    // re-asserts the phone's own, which is its rule and unchanged by this phase.
    final rewritten = await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 9,
        exercises: [_slot('sl-9', 'ex-deadlift')],
        messageId: 'msg-rewritten',
      ),
    );
    expect(rewritten.session, MirrorOutcome.applied);
    expect(
      [for (final effort in await importedEfforts(repository, 's-w1')) effort.id],
      ['sl-1', 'sl-2', 'sl-9'],
      reason: 'D-92 the ladder grows by the unknown slot, add-only',
    );
    expect(
      [
        for (final effort in await importedEfforts(repository, 's-w1'))
          effort.orderIndex,
      ],
      [0, 1, 2],
      reason:
          'the phone\'s own slots keep their places and the new one is last: '
          'nothing is reordered',
    );
    expect(
      (await repository.getSession('s-w1'))!.endedAtMs,
      isNull,
      reason: 'the session is still running after the append',
    );
    expect(phone.state.currentSession?.id, 's-w1');
    expect(phone.failures, isEmpty);
  });

  test('S-102 a slot the wrist added to the held session is appended', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_s1Envelope());

    final segment = await importedSegment(repository, 's-w1');
    final before = phone.state.currentSession!;
    final indexBefore = phone.mirror.state['currentExerciseIndex'];
    final notifications = _notifications(phone.state);

    final receipt = await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 4,
        currentExerciseIndex: 1,
        exercises: [
          _slot('sl-1', 'ex-bench'),
          _slot('sl-2', 'ex-squat'),
          _slot('sl-3', 'ex-deadlift'),
        ],
        messageId: 'msg-s102',
      ),
    );

    expect(receipt.session, MirrorOutcome.applied);
    expect(
      [
        for (final effort in phone.state.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['sl-1', 'sl-2', 'sl-3'],
      reason: 'D-92 the phone\'s ladder grows by the slot the wrist added',
    );
    final efforts = await importedEfforts(repository, 's-w1');
    expect(
      [for (final effort in efforts) effort.id],
      ['sl-1', 'sl-2', 'sl-3'],
      reason: 'D-3 the appended slot is a real row, under its own slot id',
    );
    expect(
      [for (final effort in efforts) effort.orderIndex],
      [0, 1, 2],
      reason: 'appended last, after the two the phone already held',
    );
    expect(
      efforts.last.segmentId,
      segment.id,
      reason: 'the appended effort joins the session\'s existing segment',
    );
    expect(
      efforts.last.exerciseId,
      'ex-deadlift',
      reason: 'the slot\'s own exercise is what the row carries',
    );

    final after = phone.state.currentSession!;
    expect(
      after.updatedAtMs,
      before.updatedAtMs,
      reason:
          'D-92 the session row is not rewritten: its stamps, its start and its '
          'status are the phone\'s',
    );
    expect(after.startedAtMs, before.startedAtMs);
    expect(after.endedAtMs, isNull, reason: 'the session is still running');
    expect(
      phone.mirror.state['currentExerciseIndex'],
      indexBefore,
      reason: 'the position the wrist reports is not moved',
    );
    expect(
      notifications(),
      1,
      reason:
          'D-94 one notify for the one change, not the three a session reload '
          'fires',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-104 a snapshot with no new slot changes nothing', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_s1Envelope());
    final rows = await importedRows(repository, 's-w1');
    final notifications = _notifications(phone.state);
    final snapshotsBefore = phone.transport.ofType('session_snapshot').length;

    // The same ladder with a moved revision: a change of the phone's own,
    // echoed back to it.
    final receipt = await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 7,
        currentExerciseIndex: 1,
        exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
        messageId: 'msg-s104',
      ),
    );

    expect(receipt.session, MirrorOutcome.applied);
    expect(
      await importedRows(repository, 's-w1'),
      rows,
      reason: 'nothing is added, removed or reordered: no row is written',
    );
    expect(
      [for (final effort in await importedEfforts(repository, 's-w1')) effort.id],
      ['sl-1', 'sl-2'],
    );
    expect(
      notifications(),
      0,
      reason: 'the reconcile is a no-op, so nothing notifies',
    );
    for (final envelope
        in phone.transport.ofType('session_snapshot').skip(snapshotsBefore)) {
      expect(
        _sentLadder(envelope),
        ['sl-1', 'sl-2'],
        reason:
            'no frame composed by the reconcile is sent: what the phone answers '
            'with is the ladder it already held',
      );
    }
    expect(phone.failures, isEmpty);
  });

  test('S-105 a phone-side rename is not undone by a wrist snapshot', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_s1Envelope());

    // The user renames B on the phone. The wrist's ladder still carries the
    // name B had when the session was adopted: a snapshot's slot name is a copy
    // of an exercise row, and the phone owns that row.
    final renamed = (await repository.getExerciseById('ex-squat'))!;
    await repository.updateExercise(
      Exercise(
        id: renamed.id,
        name: 'Back Squat (my bar)',
        createdAtMs: renamed.createdAtMs,
        updatedAtMs: 1788000009999,
      ),
    );
    await phone.state.loadHistoricalSession('s-w1');
    expect(
      phone.state.getExercise('ex-squat')?.name,
      'Back Squat (my bar)',
      reason: 'the phone holds the user\'s name',
    );
    final rows = await importedRows(repository, 's-w1');
    final notifications = _notifications(phone.state);

    await phone.router.receive(
      _snapshot(
        sessionId: 's-w1',
        revision: 5,
        currentExerciseIndex: 1,
        exercises: [_slot('sl-1', 'ex-bench'), _slot('sl-2', 'ex-squat')],
        messageId: 'msg-s105',
      ),
    );

    expect(
      [for (final effort in await importedEfforts(repository, 's-w1')) effort.id],
      ['sl-1', 'sl-2'],
      reason:
          'the slot is known by its sessionExerciseId, so the wrist\'s stale '
          'name is not a second B',
    );
    expect(
      await importedRows(repository, 's-w1'),
      rows,
      reason: 'nothing is written for a ladder the phone has taken',
    );
    final ladder = (await phone.bridge.projectSession(null))!['exercises']! as List;
    expect(
      [for (final slot in ladder) (slot as Map)['name']],
      ['Barbell Bench Press', 'Back Squat (my bar)'],
      reason:
          'the ladder the phone would send names B the way the user renames it, '
          'not the way the wrist\'s stale copy does',
    );
    expect(
      [for (final slot in ladder) (slot as Map)['sessionExerciseId']],
      ['sl-1', 'sl-2'],
      reason: 'and the order is unchanged',
    );
    expect(notifications(), 0, reason: 'nothing changed, so nothing notifies');
    expect(phone.failures, isEmpty);
  });

  test('S-106 the phone\'s own session is not taken away', () async {
    final repository = await _repository();
    await _seedPhoneSession(
      repository,
      sessionId: 'session-phone-1',
      efforts: const [('effort-a', 'ex-bench'), ('effort-b', 'ex-squat')],
      loggedEffortId: 'effort-a',
    );
    final phone = await _phone(repository);
    await phone.state.loadHistoricalSession('session-phone-1');
    final segment = phone.state.segments.single;
    final rows = await importedRows(repository, 'session-phone-1');
    final indexBefore =
        (await phone.bridge.projectSession(null))!['currentExerciseIndex'];
    final notifications = _notifications(phone.state);

    // A different session, with an active status: the wrist started its own.
    final receipt = await phone.router.receive(
      _snapshot(
        sessionId: 's-w2',
        revision: 1,
        exercises: [_slot('sl-9', 'ex-deadlift')],
        messageId: 'msg-s106',
      ),
    );

    expect(receipt.session, MirrorOutcome.applied);
    expect(
      await phone.bridge.consider(phone.mirror.state),
      WatchSessionAdoption.refusedConflict,
      reason: '17a D-10: a session the phone is not in is refused whole',
    );
    expect(
      phone.state.currentSession?.id,
      'session-phone-1',
      reason: 'the phone still holds the session it is running',
    );
    expect(
      [
        for (final effort in phone.state.getEffortsForSegment(segment.id))
          effort.id,
      ],
      ['effort-a', 'effort-b'],
      reason: 'D-92 nothing of the wrist\'s ladder is appended to the phone\'s',
    );
    expect(
      (await phone.bridge.projectSession(null))!['currentExerciseIndex'],
      indexBefore,
      reason: 'and its position is untouched',
    );
    expect(
      await importedRows(repository, 'session-phone-1'),
      rows,
      reason: 'no row of the phone\'s session was written',
    );
    expect(
      await repository.getSession('s-w2'),
      isNull,
      reason: 'the wrist\'s session is not adopted either',
    );
    expect(
      await importedEfforts(repository, 's-w2'),
      isEmpty,
      reason: 'and none of its slots are',
    );
    expect(
      phone.transport.ofType('session_snapshot').map(_sentLadder),
      isEmpty,
      reason:
          'the phone has no ladder for another session to answer with: the '
          'mirror switches without an answer frame',
    );
    expect(notifications(), 0, reason: 'nothing of the phone\'s own was touched');
    expect(
      phone.skipped,
      [(held: 'session-phone-1', offered: 's-w2')],
      reason: 'the skip is reported once, for the pair it acted on',
    );
    expect(phone.failures, isEmpty);
  });

  test('a slot resolves its effort kind from its declaration, then its '
      'capabilities', () async {
    final repository = await _repository();
    final phone = await _phone(repository);

    await phone.router.receive(
      _snapshot(
        sessionId: 's-kind',
        revision: 1,
        exercises: [
          // Declared by the routine that produced the slot: wins over `time`.
          _slot(
            'sl-declared',
            'ex-row',
            capabilities: [ExerciseCapability.time],
            declaredKind: BlockTypes.round,
          ),
          // Nothing declared: `hold` decides, in the order the wrist resolves
          // it by, even though the slot carries `time` as well.
          _slot('sl-hold', 'ex-plank', capabilities: [
            ExerciseCapability.hold,
            ExerciseCapability.time,
          ]),
          // Nothing that decides: the free-session default.
          _slot('sl-bilateral', 'ex-lunge', capabilities: [
            ExerciseCapability.bilateral,
          ]),
        ],
        messageId: 'msg-kind',
      ),
    );

    expect(
      [for (final effort in await importedEfforts(repository, 's-kind')) effort.effortKind],
      [BlockTypes.round, BlockTypes.drill, BlockTypes.set],
    );
  });

  test('a snapshot the wrist has closed is not adopted', () async {
    final repository = await _repository();
    final phone = await _phone(repository);

    await phone.router.receive(
      _snapshot(
        sessionId: 's-w3',
        revision: 1,
        status: WatchSessionStatus.completed,
        exercises: [_slot('sl-1', 'ex-bench')],
        messageId: 'msg-closed',
      ),
    );

    expect(
      await repository.getSession('s-w3'),
      isNull,
      reason: 'D-2 adopts the session the wrist is running, not one it ended',
    );
    expect(phone.state.currentSession, isNull);
    expect(phone.state.hasActiveSession, isFalse);
  });

  test('an unbound bridge writes nothing', () async {
    final repository = await _repository();
    final failures = <Object>[];
    final bridge = WatchSessionAdoptionBridge(
      repository: repository,
      clock: () => _adoptedAt,
      onFailure: (error, stack) => failures.add(error),
    );

    final outcome = await bridge.consider({
      'sessionId': 's-w9',
      'status': WatchSessionStatus.active,
      'revision': 1,
      'currentExerciseIndex': 0,
      'exercises': [_slot('sl-1', 'ex-bench')],
      'entries': <Object?>[],
      'timers': <String, Object?>{},
    });

    expect(outcome, WatchSessionAdoption.unbound);
    expect(await repository.getSession('s-w9'), isNull);
    expect(failures, isEmpty);
  });

  // The one failure the bridge can have that is not the rule working: the
  // adoption itself. D-10 is a skip and reports through `onSkipped`; a row that
  // cannot be written is a failure, and it goes to the graph's hook and still
  // reaches whoever asked for the adoption.
  test('an adoption that cannot be written is reported as a failure', () async {
    final repository = _UnwritableRepository();
    await repository.initialize();
    final failures = <Object>[];
    final bridge = WatchSessionAdoptionBridge(
      repository: repository,
      clock: () => _adoptedAt,
      onFailure: (error, stack) => failures.add(error),
    );
    bridge.bindWorkoutState(WorkoutState(repository));

    await expectLater(
      bridge.consider({
        'sessionId': 's-w9',
        'status': WatchSessionStatus.active,
        'revision': 1,
        'currentExerciseIndex': 0,
        'exercises': [_slot('sl-1', 'ex-bench')],
        'entries': <Object?>[],
        'timers': <String, Object?>{},
      }),
      throwsA(isA<StateError>()),
    );

    expect(failures, hasLength(1));
    expect(await repository.getSession('s-w9'), isNull);
  });

  // The guard the restart path rests on. `checkForInProgressSession` keeps
  // `sessions.first` and deletes the rest, and both repositories sort
  // in-progress rows by `startedAtMs` descending — so an adopted session is
  // only safe if it is the newer row. A same-millisecond tie is accepted: the
  // adapter builds the adopted row from the wrist's own clock while a phone row
  // is stamped by the phone's, and the two are never equal in practice.
  test(
    'S-1 the adopted session survives checkForInProgressSession beside an '
    'empty phone row',
    () async {
      final repository = await _repository();
      await _seedPhoneSession(repository, sessionId: 'session-phone-empty');
      final phone = await _phone(repository);
      await phone.router.receive(_s1Envelope());

      // A restart: a fresh state over the same rows.
      final restarted = WorkoutState(repository);
      final survivor = await restarted.checkForInProgressSession();
      expect(
        survivor?.id,
        's-w1',
        reason: 'the adopted row is the newer in-progress row',
      );
      await restarted.loadHistoricalSession(survivor!.id);

      expect(restarted.currentSession?.id, 's-w1');
      expect(restarted.hasActiveSession, isTrue);
      expect(
        [
          for (final effort
              in restarted.getEffortsForSegment(restarted.segments.single.id))
            effort.id,
        ],
        ['sl-1', 'sl-2'],
        reason: 'D-3 the slot ids survive the restart unchanged',
      );
      expect(
        await repository.getSession('session-phone-empty'),
        isNull,
        reason: 'the older empty row is swept, not the wrist\'s session',
      );
    },
  );

  // F4: one row, one claim. The ids the push's ledger holds and the groups the
  // projection leaves out are two readings of one rule, so a slot whose wrist
  // rows outnumber its groups by a shared stamp must hold as many ids as the
  // projection pairs with groups — never one id per row.
  test(
    'F4 two wrist rows of one slot that share a stamp hold one id — the row the '
    'projection pairs with the slot\'s one group',
    () async {
      const at = 1780000000000;
      const slot = 'sl-1';
      final repository = await _repository();
      await repository.createSession(
        TrainingSession(
          id: 's-1',
          ownerUserId: LoggedEntryRows.ownerUserId,
          startedAtMs: at,
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.createSegment(
        LoggedEntryRows.defaultSegment(
          id: 'segment-s-1',
          sessionId: 's-1',
          atMs: at,
        ),
      );
      await repository.createEffort(
        SegmentEffort(
          id: slot,
          segmentId: 'segment-s-1',
          orderIndex: 0,
          topLevelOrderIndex: 0,
          effortKind: BlockTypes.set,
          exerciseId: 'ex-bench',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      // The slot's one group: the phone's own set, written in the millisecond
      // both of the wrist's rows carry (D-34).
      await repository.createObservation(repsRow(slot, 0, 5, atMs: at));

      final loggedAt = DateTime.fromMillisecondsSinceEpoch(
        at,
        isUtc: true,
      ).toIso8601String();
      final rows = const ['entry-sl-1-0', 'entry-sl-1-1'];
      for (final entryId in rows) {
        await repository.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: entryId,
            watchSessionId: 's-1',
            kind: WatchInboxEntry.kindSet,
            origin: WatchInboxEntry.originWatch,
            payload: <String, dynamic>{
              'entryId': entryId,
              'eventId': entryId,
              'kind': 'set',
              'loggedAt': loggedAt,
              'sessionExerciseId': slot,
              'exerciseId': 'ex-bench',
              'reps': 5,
              'loadKg': 55.0,
            },
            receivedAtMs: at,
          ),
        );
        await repository.markWatchInboxEntriesApplied([entryId], at);
      }

      final phone = await _phone(repository);
      await phone.state.loadHistoricalSession('s-1');

      final projected = (await phone.bridge.projectSession(null))!;
      expect(
        [
          for (final entry in projected['entries']! as List)
            (entry as Map)['entryId'],
        ],
        isEmpty,
        reason:
            'the fixture: both rows carry the stamp of the slot\'s one group, '
            'and the row that claims it is the wrist\'s, so the projection '
            'pairs that group with a row and leaves none of its own to send '
            '(D-34)',
      );

      expect(
        await phone.bridge.heldWristEntryIds('s-1'),
        {'entry-sl-1-0'},
        reason:
            'F4 the ledger names the one row the claim rule pairs with the '
            'slot\'s one group: asking stamp by stamp instead names both rows, '
            'and the push then reads the second row as a set the phone still '
            'holds and never announces its deletion (D-112, S-122)',
      );
    },
  );

  // 17d Phase 3 item 0: `resolveRecordClaims` answers *record* positions, and
  // the ledger holds one value per wrist row — so a claim must be read back
  // through the row's own index. A phone-logged record can stand before the
  // record the importer wrote for a wrist row: reading the record position as a
  // row index then names the wrong row, or none at all when the wrist holds
  // fewer rows than the phone holds records, and the push never announces the
  // deletion that row needs (S-144).
  test(
    'S-144 the ledger holds the row whose stamp claimed a record, not the '
    'record\'s position in the phone\'s list',
    () async {
      const at = 1780000000000;
      const wristStamp = at + 60000;
      final repository = await _repository();
      await repository.createSession(
        TrainingSession(
          id: 's-1',
          ownerUserId: LoggedEntryRows.ownerUserId,
          startedAtMs: at,
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );
      await repository.createSegment(
        LoggedEntryRows.defaultSegment(
          id: 'segment-s-1',
          sessionId: 's-1',
          atMs: at,
        ),
      );
      Future<void> slot(String id, String kind) => repository.createEffort(
        SegmentEffort(
          id: id,
          segmentId: 'segment-s-1',
          orderIndex: 0,
          topLevelOrderIndex: 0,
          effortKind: kind,
          exerciseId: 'ex-bench',
          createdAtMs: at,
          updatedAtMs: at,
        ),
      );

      // A timed slot: the phone's own record (index 0) stands before the one
      // the wrist's row imported (index 1).
      await slot('sl-timed', BlockTypes.timed);
      await repository.createTimedInstance(
        timedInstance('sl-timed', 0, entryIndex: 0, durationSecs: 60)
            .copyWith(createdAtMs: at),
      );
      await repository.createTimedInstance(
        timedInstance(
          'sl-timed',
          1,
          entryIndex: 1,
          durationSecs: 30,
          startedAtMs: wristStamp,
          finishedAtMs: wristStamp + 30000,
        ).copyWith(createdAtMs: wristStamp),
      );

      // A rounds slot with the same shape.
      await slot('sl-round', BlockTypes.round);
      await repository.createRoundInstance(
        roundInstance('sl-round', 0).copyWith(createdAtMs: at),
      );
      await repository.createRoundInstance(
        roundInstance(
          'sl-round',
          1,
          startedAtMs: wristStamp,
        ).copyWith(createdAtMs: wristStamp),
      );

      // The counter-case: the wrist's record (index 0) stands before the
      // phone's own (index 1).
      await slot('sl-counter', BlockTypes.timed);
      await repository.createTimedInstance(
        timedInstance(
          'sl-counter',
          0,
          entryIndex: 0,
          durationSecs: 60,
          startedAtMs: wristStamp,
          finishedAtMs: wristStamp + 60000,
        ).copyWith(createdAtMs: wristStamp),
      );
      await repository.createTimedInstance(
        timedInstance('sl-counter', 1, entryIndex: 1, durationSecs: 30)
            .copyWith(createdAtMs: at),
      );

      final loggedAt = DateTime.fromMillisecondsSinceEpoch(
        wristStamp,
        isUtc: true,
      ).toIso8601String();
      for (final row in const [
        (
          entryId: 'row-timed',
          slot: 'sl-timed',
          kind: WatchInboxEntry.kindTimed,
        ),
        (
          entryId: 'row-round',
          slot: 'sl-round',
          kind: WatchInboxEntry.kindRound,
        ),
        (
          entryId: 'row-counter',
          slot: 'sl-counter',
          kind: WatchInboxEntry.kindTimed,
        ),
      ]) {
        await repository.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: row.entryId,
            watchSessionId: 's-1',
            kind: row.kind,
            origin: WatchInboxEntry.originWatch,
            payload: <String, dynamic>{
              'entryId': row.entryId,
              'eventId': row.entryId,
              'kind': row.kind,
              'loggedAt': loggedAt,
              'sessionExerciseId': row.slot,
              'exerciseId': 'ex-bench',
            },
            receivedAtMs: at,
          ),
        );
        await repository.markWatchInboxEntriesApplied([row.entryId], at);
      }

      final phone = await _phone(repository);

      expect(
        await phone.bridge.heldWristEntryIds('s-1'),
        {'row-timed', 'row-round', 'row-counter'},
        reason:
            'S-144 the ledger holds each row whose stamp still claims a record '
            'of its kind: the claim\'s record positions must be read back '
            'through the rows, or the timed slot reads the second record\'s '
            'position as a second row (RangeError) and no deletion of the '
            'three is ever announced',
      );
    },
  );

  // Plan 2026-10-09-21b, Phase 2 (D-1409, D-1410, D-1411). The length a wrist
  // counts a period down from is the number the phone's own round control would
  // count from, and a length-only edit is a changed ladder.
  group('S-1405 the phone sends the number', () {
    /// One slot of a projection, by its id, so a scenario reads a field without
    /// pinning the frame's shape.
    Map<String, Object?> slotOf(Map<String, Object?> projection, String id) =>
        (projection['exercises']! as List)
            .cast<Map<String, Object?>>()
            .firstWhere((slot) => slot['sessionExerciseId'] == id);

    /// The harness catalog plus a round exercise whose period length the phone
    /// knows: Soccer, a 40-minute half. Squat keeps its capabilities but gains
    /// none of the number, which is the exercise-with-no-length case.
    Future<WorkoutRepository> roundRepository() async {
      final repository = await _repository();
      await repository.createExercise(
        Exercise(
          id: 'ex-soccer',
          name: 'Soccer',
          defaultRoundDurationSecs: 2400,
          createdAtMs: _adoptedAt.millisecondsSinceEpoch,
          updatedAtMs: _adoptedAt.millisecondsSinceEpoch,
        ),
      );
      await repository.setExerciseCapabilities('ex-soccer', const [
        ExerciseCapability.time,
        ExerciseCapability.rounds,
      ]);
      await repository.setExerciseCapabilities('ex-squat', const [
        ExerciseCapability.time,
        ExerciseCapability.rounds,
      ]);
      return repository;
    }

    test('S-1405 a round effort carries the exercise default, or its own round',
        () async {
      final repository = await roundRepository();
      await _seedPhoneSession(
        repository,
        sessionId: 'session-round',
        efforts: const [('sx-soccer', 'ex-soccer')],
        kinds: const [BlockTypes.round],
      );
      final phone = await _phone(repository);
      await phone.state.loadHistoricalSession('session-round');

      expect(
        slotOf(
          (await phone.bridge.projectSession(null))!,
          'sx-soccer',
        )['roundDurationSecs'],
        2400,
        reason:
            'S-1405 an effort holding no round yet carries the exercise\'s own '
            'period length, the number the phone would start the first round '
            'from',
      );

      // The user re-times the slot's round: the effort's own number wins over
      // the exercise default.
      await phone.state.addRound('sx-soccer', plannedDurationSecs: 180);
      await phone.state.updateRoundPlannedDuration('sx-soccer', 0, 900);
      expect(
        slotOf(
          (await phone.bridge.projectSession(null))!,
          'sx-soccer',
        )['roundDurationSecs'],
        900,
        reason:
            'S-1405 the effort\'s own round is what the phone counts the next '
            'one from (D-1409)',
      );
    });

    test('S-1405 a timed effort and an exercise with no length send no field',
        () async {
      final repository = await roundRepository();
      await _seedPhoneSession(
        repository,
        sessionId: 'session-mixed',
        efforts: const [
          ('sx-round', 'ex-soccer'),
          ('sx-timed', 'ex-soccer'),
          ('sx-no-length', 'ex-squat'),
          ('sx-set', 'ex-squat'),
        ],
        kinds: const [
          BlockTypes.round,
          BlockTypes.timed,
          BlockTypes.round,
          BlockTypes.set,
        ],
      );
      final phone = await _phone(repository);
      await phone.state.loadHistoricalSession('session-mixed');
      final projection = (await phone.bridge.projectSession(null))!;

      expect(
        slotOf(projection, 'sx-round')['roundDurationSecs'],
        2400,
        reason:
            'the frame carries the field at all, so each absence below is that '
            'slot\'s and not the frame\'s',
      );
      expect(
        slotOf(projection, 'sx-timed').containsKey('roundDurationSecs'),
        isFalse,
        reason:
            'S-1405 a timed effort is not a period: the number is omitted '
            'whatever the exercise knows',
      );
      expect(
        slotOf(projection, 'sx-no-length').containsKey('roundDurationSecs'),
        isFalse,
        reason:
            'S-1405 a round effort on an exercise with no default and no round '
            'has no number to send',
      );
      expect(
        slotOf(projection, 'sx-no-length')['capabilities'],
        isNotEmpty,
        reason: 'the fixture: that slot rides the ladder, so the absence is the '
            'field\'s and not the slot\'s',
      );
      expect(
        slotOf(projection, 'sx-set').containsKey('roundDurationSecs'),
        isFalse,
        reason: 'S-1405 a set effort never carries a period length',
      );
    });

    test('S-1408 a non-round kind never gets the field', () async {
      final repository = await roundRepository();
      await _seedPhoneSession(
        repository,
        sessionId: 'session-amrap',
        efforts: const [
          ('sx-amrap', 'ex-soccer'),
          ('sx-round', 'ex-soccer'),
        ],
        kinds: const [BlockTypes.amrap, BlockTypes.round],
      );
      final phone = await _phone(repository);
      await phone.state.loadHistoricalSession('session-amrap');

      // An AMRAP holds a round record of 900 s, and a receiver still resolves
      // `round` from its capabilities — but the phone's own round control does
      // not count an AMRAP down, so no number travels (D-1409). The round
      // effort beside it, re-timed to the same 900 s, does travel.
      await phone.state.addRound('sx-amrap', plannedDurationSecs: 900);
      await phone.state.addRound('sx-round', plannedDurationSecs: 900);
      final projection = (await phone.bridge.projectSession(null))!;

      expect(
        slotOf(projection, 'sx-round')['roundDurationSecs'],
        900,
        reason: 'the round effort\'s own 900 s is exactly what must travel',
      );
      expect(
        slotOf(projection, 'sx-amrap').containsKey('roundDurationSecs'),
        isFalse,
        reason:
            'S-1408 the kind that decides is the phone\'s own effort kind, and '
            'an AMRAP is not a round',
      );
    });

    test('S-1409 a length-only change moves the revision', () async {
      final repository = await roundRepository();
      await _seedPhoneSession(
        repository,
        sessionId: 'session-retime',
        efforts: const [('sx-soccer', 'ex-soccer')],
        kinds: const [BlockTypes.round],
      );
      final phone = await _phone(repository);
      await phone.state.loadHistoricalSession('session-retime');
      await phone.state.addRound('sx-soccer', plannedDurationSecs: 180);

      final first = (await phone.bridge.projectSession(null))!;
      expect(slotOf(first, 'sx-soccer')['roundDurationSecs'], 180);

      await phone.state.updateRoundPlannedDuration('sx-soccer', 0, 600);

      final second = (await phone.bridge.projectSession(null))!;
      expect(slotOf(second, 'sx-soccer')['roundDurationSecs'], 600);
      expect(
        second['revision'],
        (first['revision']! as int) + 1,
        reason:
            'D-1410 the wrist renders the length, so a length-only edit is a '
            'changed ladder and must state a newer revision',
      );

      final third = (await phone.bridge.projectSession(null))!;
      expect(
        third['revision'],
        second['revision'],
        reason:
            'D-1410 a ladder that has not changed keeps the revision already '
            'stated',
      );
    });

    test('S-1411 the same number twice is the same bytes', () async {
      final repository = await roundRepository();
      await _seedPhoneSession(
        repository,
        sessionId: 'session-twice',
        efforts: const [('sx-soccer', 'ex-soccer')],
        kinds: const [BlockTypes.round],
      );
      final phone = await _phone(repository);
      await phone.state.loadHistoricalSession('session-twice');

      final first = (await phone.bridge.projectSession(null))!;
      final second = (await phone.bridge.projectSession(null))!;

      expect(
        slotOf(second, 'sx-soccer'),
        slotOf(first, 'sx-soccer'),
        reason:
            'S-1411 nothing changed between the two projections, so the slot is '
            'the same map, field for field',
      );
      expect(slotOf(second, 'sx-soccer')['roundDurationSecs'], 2400);
      expect(
        second['revision'],
        first['revision'],
        reason: 'S-1411 and the revision does not move for an unchanged ladder',
      );
    });
  });
}
