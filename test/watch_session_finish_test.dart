// Either side may end the session the wrist is running: the wrist's
// `session_lifecycle` ends the phone's copy of it, and a session the phone has
// already finished is never taken back into the live state.
//
// Plan: `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/2026-10-05-15a-watch-session-sync-pr1-plan.md`,
// Phase 4 — D-5, D-8, G1, G2, G3.
// Scenario mapping:
//   S-4 the wrist ends its own session        → `S-4 ...` (both arrival orders)
//   S-5 the phone's finish is pushed (D-81)   → `S-5 ...`
//   G1 never resurrect a finished session     → `G1 ...`, `G1 counter-case ...`
//   the wrist's sets merge into the session   → `a set logged on the watch ...`
//     the phone holds, once (PR 2a)
//
// Plan 19a Phase 5a — D-182, the phone's answer to a wrist announcement:
//   S-189 the wrist's own announcement is reset → `S-189 ...`
//   S-190 an ended session is not re-adopted     → `S-190 ...`
//   S-190b a fate outlives the mirror that wrote it → `S-190b ...`
//   S-191 a session the phone does not know is adopted → `S-191 ...`
//   S-192 agreeing and history are both answered → `S-192 ...` (two cases)
//   S-193 a dropped answer returns at the next announcement → `S-193 ...`
//
// Plan: `docs/plans/2026-10-08-18d-watch-rest-emit-and-docs-plan/2026-10-08-18d-watch-rest-emit-and-docs-plan.md`,
// Phase 1 — D-220, D-223. Scenarios: S-322, S-331 (the wrist's own finish is a
// rest's end too; the last group here is the wrist's engine, not the phone's).
//
// Every frame arrives through the real `LiveSessionMirrorState` behind the real
// `WatchIncomingRouter`, the inbox is wired the way `createWatchSync` wires it
// (including the adoption bridge's answer to "is this the phone's own
// session?"), and the phone's state is a real `WorkoutState`. Plain `test()`:
// no widget is involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_session_auto_push.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show
        CaptureTransport,
        observationsUp,
        importedEfforts,
        importedRows,
        seedExercise;

/// The phone's clock, pinned: every stamp the inbox writes is the same in both
/// arrival orders.
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
    required this.skipped,
  });

  final WatchIncomingRouter router;
  final LiveSessionMirrorState mirror;
  final WorkoutState state;
  final WatchSessionAdoptionBridge bridge;
  final CaptureTransport transport;

  /// What the graph reported as a failure: nothing, in these tests.
  final List<Object> failures;

  /// Every D-10 skip the bridge reported, in order, as the (held, offered)
  /// session ids it acted on.
  final List<({String held, String offered})> skipped;

  /// Every `session_lifecycle` this phone sent the wrist, in order.
  List<Map<String, Object?>> get lifecycles =>
      transport.ofType('session_lifecycle');
}

Future<_Phone> _phone(WorkoutRepository repository) async {
  final failures = <Object>[];
  final skipped = <({String held, String offered})>[];
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => _phoneNow,
    onFailure: (error, stack) => failures.add(error),
    onSkipped: (held, offered) => skipped.add((held: held, offered: offered)),
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
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_lifecycle',
  'origin': 'watch',
  'sentAt': '2026-10-05T10:30:00Z',
  'payload': {'state': state, 'at': '2026-10-05T10:30:00Z'},
};

/// The `state` of every `session_lifecycle` sent since index [from] — the
/// fates this phone has announced, in order.
List<String> _sentFates(_Phone phone, int from) => [
  for (final frame in phone.transport.sent.skip(from))
    if (frame['type'] == 'session_lifecycle')
      (frame['payload']! as Map)['state']! as String,
];

/// Starts the phone's own session `P` with one effort per id in
/// [exerciseIds], and answers with its id: the ladder a wrist announcement is
/// answered from (S-189).
Future<String> _startPhoneSession(
  _Phone phone,
  WorkoutRepository repository, {
  List<String> exerciseIds = const ['ex-bench', 'ex-squat'],
}) async {
  await phone.state.createNewSession(modality: null);
  for (final exerciseId in exerciseIds) {
    final exercise = (await repository.getExerciseById(exerciseId))!;
    await phone.state.addExerciseToSession(exercise);
  }
  return phone.state.currentSession!.id;
}

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

Map<String, Object?> _end(
  String sessionId, {
  double? avgHeartRateBpm,
  double? maxHeartRateBpm,
}) => {
  'entryId': 'end-$sessionId',
  'eventId': 'end-$sessionId',
  'kind': 'session_end',
  'loggedAt': '2026-10-05T10:30:00Z',
  'startedAt': '2026-10-05T10:00:00Z',
  'endedAt': '2026-10-05T10:30:00Z',
  'status': 'completed',
  'avgHeartRateBpm': ?avgHeartRateBpm,
  'maxHeartRateBpm': ?maxHeartRateBpm,
};

Map<String, Object?> _rating(String sessionId, int rating) => {
  'entryId': 'rating-$sessionId',
  'eventId': 'rating-$sessionId',
  'kind': 'effort_rating',
  'loggedAt': '2026-10-05T10:30:30Z',
  'rating': rating,
};

/// The one fact the wrist alone knows about a session the phone owns — the
/// rating — read off the session the phone holds.
Future<int?> _heldRating(_Phone phone) async =>
    (await phone.state.repository.getSession('s-w1'))?.sessionFeeling;

/// The staged rows of `s-w1` by entry id, so a test can say what stayed put.
Future<Map<String, WatchInboxEntry>> _staged(
  WorkoutRepository repository,
) async {
  return {
    for (final row in await repository.getWatchInboxEntriesForSession('s-w1'))
      row.entryId: row,
  };
}

/// The staged row ids, sorted: the order rows are listed in is the
/// implementation's, and what a test has to say about them is which ones there
/// are.
List<String> _stagedIds(Map<String, WatchInboxEntry> staged) =>
    staged.keys.toList()..sort();

/// [importedRows] without the staged rows: what the phone wrote, which is what
/// a test asserting "nothing was written" compares.
Map<String, Object?> _written(Map<String, Object?> rows) =>
    Map<String, Object?>.of(rows)..remove('inbox');

/// What both arrival orders must end with: one session, ended, rated 4, and no
/// second copy of the ladder the phone already had.
Future<void> _expectOneEndedSession(
  _Phone phone,
  WorkoutRepository repository,
) async {
  final session = phone.state.currentSession;
  expect(session?.id, 's-w1', reason: 'S-4 the phone holds the wrist session');
  expect(
    session?.endedAtMs,
    isNotNull,
    reason: 'S-4, D-5 the wrist\'s own end closes the phone\'s session',
  );
  expect(phone.state.hasActiveSession, isFalse, reason: 'S-4 it is over');

  final sessions = await repository.getAllSessions();
  expect(
    [for (final row in sessions) row.id],
    ['s-w1'],
    reason: 'S-4 one session, not a second copy of the wrist\'s',
  );
  expect(
    await _heldRating(phone),
    4,
    reason: 'D-8 the wrist\'s rating is the session\'s one rating',
  );
  expect(
    [for (final effort in await importedEfforts(repository, 's-w1')) effort.id],
    ['sl-1', 'sl-2'],
    reason:
        'the wrist\'s set rows do not become a second effort per slot — the '
        'phone\'s rows already are those slots (D-3)',
  );
  expect(
    [for (final row in await repository.getEffortObservations('sl-1')) row.id],
    ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
    reason:
        'D-14 the wrist\'s set for sl-1 is a row of the effort the phone '
        'already has, not a copy of it',
  );
  expect(
    [for (final row in await repository.getEffortObservations('sl-2')) row.id],
    ['obs-sl-2-0-reps', 'obs-sl-2-0-weight'],
    reason: 'D-14 and the same for the second slot',
  );
  expect(phone.failures, isEmpty);
}

/// Deterministic clock for the wrist's engine: a rest's window is asserted
/// against instants, never against a real clock.
class _WristClock {
  _WristClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

/// The one ladder slot the wrist's own session holds.
Map<String, Object?> _wristSlot() => {
  'sessionExerciseId': 'sl-1',
  'exerciseId': 'ex-bench',
  'name': 'ex-bench',
  'capabilities': ['reps', 'sets', 'load'],
};

/// The set the wrist logs, as the logging surface hands it to the engine.
Map<String, Object?> _wristSet(DateTime at) => {
  'entryId': 'entry-1',
  'eventId': 'entry-1',
  'kind': 'set',
  'loggedAt': utcIso(at),
  'sessionExerciseId': 'sl-1',
  'exerciseId': 'ex-bench',
  'reps': 8,
  'loadKg': 40,
};

void main() {
  test('S-4 the wrist ends its session, roster of logged sets first', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    expect(phone.state.hasActiveSession, isTrue);

    // The wrist logs two sets while it runs…
    await phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-1', slot: 'sl-1'),
      ], messageId: 'msg-set-1'),
    );
    await phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-2', slot: 'sl-2'),
      ], messageId: 'msg-set-2'),
    );
    // …then ends with its rating, and says so.
    await phone.router.receive(
      observationsUp('s-w1', [
        _rating('s-w1', 4),
        _end('s-w1'),
      ], messageId: 'msg-end'),
    );
    await phone.router.receive(_lifecycle('s-w1'));

    await _expectOneEndedSession(phone, repository);

    final staged = await _staged(repository);
    for (final entryId in ['sx-1', 'sx-2']) {
      expect(
        staged[entryId]?.appliedAtMs,
        isNotNull,
        reason:
            'D-18 $entryId merged into the session the phone holds, so the '
            'wrist is told it may forget it',
      );
      expect(
        phone.transport.receiptedEntryIds,
        contains(entryId),
        reason: 'D-18 the receipt names every row the merge looked at',
      );
    }
    expect(
      phone.transport.receiptedEntryIds,
      containsAll(['end-s-w1', 'rating-s-w1']),
      reason: 'the two rows the phone did apply are acknowledged',
    );
  });

  test('S-4 the wrist ends its session, end before the logged sets', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // The end reaches the phone before the sets behind it do.
    await phone.router.receive(_lifecycle('s-w1'));
    await phone.router.receive(
      observationsUp('s-w1', [
        _rating('s-w1', 4),
        _end('s-w1'),
      ], messageId: 'msg-end'),
    );
    await phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-1', slot: 'sl-1'),
      ], messageId: 'msg-set-1'),
    );
    await phone.router.receive(
      observationsUp('s-w1', [
        _set('sx-2', slot: 'sl-2'),
      ], messageId: 'msg-set-2'),
    );

    await _expectOneEndedSession(phone, repository);

    final staged = await _staged(repository);
    expect(_stagedIds(staged), [
      'end-s-w1',
      'rating-s-w1',
      'sx-1',
      'sx-2',
    ], reason: 'the sets are still held, not dropped');
    expect(
      staged['sx-2']?.appliedAtMs,
      isNotNull,
      reason:
          'an entry that arrived after the end merges like any other — a merge '
          'does not wait for an end (D-13)',
    );
  });

  test('S-5 the phone\'s own finish is reported, and the wrist is answered '
      'at its next sync', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    final push = WatchSessionAutoPush(
      mirror: phone.mirror,
      getSession: repository.getSession,
    )..bindWorkoutState(phone.state);
    addTearDown(push.dispose);

    await phone.router.receive(_snapshot());
    expect(phone.state.hasActiveSession, isTrue);
    // The graph's post-frame step (D-82), which this harness drives by hand:
    // the frame the phone just applied becomes the push's baseline, so the
    // session it names is the phone's own from here on.
    await push.rebaseline();

    // The owner ends the session on the phone, through the ordinary finish.
    await phone.state.endSession();
    expect(phone.state.currentSession?.endedAtMs, isNotNull);

    // The window closes: the phone reports its own finish (D-81).
    await push.flush();

    final reported = phone.lifecycles;
    expect(
      [for (final envelope in reported) envelope['sessionId']],
      ['s-w1'],
      reason: 'S-5 the push names the session the mirror holds',
    );
    expect(
      [(reported.single['payload']! as Map)['state']],
      [WatchLifecycleState.completed],
      reason: 'S-5 the phone\'s finish ends the wrist\'s copy',
    );
    expect(
      phone.mirror.status,
      WatchSessionStatus.completed,
      reason: 'S-5 the mirror converges with the lifecycle it sent',
    );

    // The wrist, still running its copy, syncs again.
    final receipt = await phone.router.receive(
      _snapshot(revision: 3, messageId: 'msg-next-sync'),
    );
    expect(receipt.session, MirrorOutcome.applied);

    final answered = phone.lifecycles;
    expect(
      [for (final envelope in answered) envelope['sessionId']],
      ['s-w1', 's-w1'],
      reason:
          'G1/S-5 the wrist\'s next sync is answered with the end as well, on '
          'top of the one the push already sent',
    );
    expect(
      [(answered.last['payload']! as Map)['state']],
      [WatchLifecycleState.completed],
      reason: 'S-5 the wrist\'s copy is ended for it',
    );
    expect(
      [
        for (final envelope in phone.transport.ofType('session_snapshot'))
          (envelope['payload']! as Map)['status'],
      ],
      [WatchSessionStatus.completed],
      reason:
          'S-5 the phone asserts no ladder of its own for a session it has '
          'finished: the one snapshot is the mirror\'s own copy, re-asserted '
          'because the wrist still reports it as active',
    );

    expect(
      await repository.getAllSessions(),
      hasLength(1),
      reason: 'S-5 one history entry, still the one the phone finished',
    );
    expect(
      phone.state.currentSession?.id,
      's-w1',
      reason: 'S-5 the wrist\'s snapshot does not load a fresh copy',
    );
    expect(phone.failures, isEmpty);
  });

  test('G1 a finished session is not adopted back after a restart', () async {
    final repository = await _repository();
    final first = await _phone(repository);
    await first.router.receive(_snapshot());
    await first.router.receive(_lifecycle('s-w1'));
    expect(first.state.currentSession?.endedAtMs, isNotNull);

    final endedSession = await importedRows(repository, 's-w1');
    final sessionCount = (await repository.getAllSessions()).length;

    // The phone restarts: a fresh graph over the same storage, holding nothing.
    final second = await _phone(repository);
    expect(second.state.currentSession, isNull);

    // The wrist is still looking at the session the phone has finished, and
    // syncs it.
    final receipt = await second.router.receive(
      _snapshot(messageId: 'msg-after-restart'),
    );
    expect(receipt.session, MirrorOutcome.applied);
    expect(
      await second.bridge.consider({
        'sessionId': 's-w1',
        'status': WatchSessionStatus.active,
      }),
      WatchSessionAdoption.alreadyEnded,
      reason: 'G1 the row is history, so there is nothing to adopt',
    );

    expect(
      second.state.currentSession,
      isNull,
      reason: 'G1 nothing is loaded back into the phone\'s live state',
    );
    expect(
      _written(await importedRows(repository, 's-w1')),
      _written(endedSession),
      reason: 'G1 nothing is written, and the finish stands',
    );
    expect(
      (await repository.getAllSessions()).length,
      sessionCount,
      reason: 'G1 no session is added',
    );

    final answered = second.lifecycles;
    expect(answered, hasLength(1), reason: 'G1 the wrist is told, once');
    expect(answered.single['sessionId'], 's-w1');
    expect(
      (answered.single['payload']! as Map)['state'],
      WatchLifecycleState.completed,
    );
    expect(
      second.mirror.state['status'],
      WatchSessionStatus.completed,
      reason: 'G1 the answer is the phone\'s own end, applied here first',
    );
  });

  test('G1 counter-case a running session is not answered with an end', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    // The wrist syncs the same session again: the phone is running it, so there
    // is no end to answer with.
    await phone.router.receive(_snapshot(revision: 3, messageId: 'msg-again'));
    expect(
      phone.lifecycles,
      isEmpty,
      reason: 'G1 only a session whose row has ended is answered with an end',
    );
    expect(
      phone.state.currentSession?.id,
      's-w1',
      reason: 'the phone keeps the session it holds (D-10)',
    );
    expect(phone.state.currentSession?.endedAtMs, isNull);

    // A snapshot of a session this phone is not in is not adoptable while it
    // holds one (D-10). D-182's second row answers it: the announced session is
    // ended under its own name, and the phone's held session follows — the end
    // never names the session the phone is running.
    final sentBefore = phone.transport.sent.length;
    await phone.router.receive(
      _snapshot(sessionId: 's-other', messageId: 'msg-other'),
    );
    final answer = phone.transport.sent.sublist(sentBefore);
    final ends = [
      for (final frame in answer)
        if (frame['type'] == 'session_lifecycle') frame,
    ];
    expect(
      [for (final frame in ends) frame['sessionId']],
      ['s-other'],
      reason: 'D-182 the end names the announced session, never s-w1',
    );
    expect(
      [for (final frame in ends) (frame['payload']! as Map)['state']],
      [WatchLifecycleState.abandoned],
      reason: 'G1/D-182 the wrist\'s own session is the one that ends',
    );
    expect(
      [
        for (final frame in answer)
          if (frame['type'] == 'session_snapshot') frame['sessionId'],
      ],
      everyElement(phone.state.currentSession!.id),
      reason: 'D-182 the rest of the answer is the phone\'s own session',
    );
    expect(
      phone.state.currentSession?.id,
      's-w1',
      reason: 'G1/D-10 the phone keeps the session it holds',
    );
    expect(
      phone.skipped,
      [(held: 's-w1', offered: 's-other')],
      reason: 'D-10 the crossed session is the one skip in this test',
    );
    expect(
      phone.failures,
      isEmpty,
      reason: 'D-10 a skip is not a failure and carries no stack',
    );
  });

  test(
    'a set logged on the watch lands in the session the phone holds',
    () async {
      final repository = await _repository();
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());

      final sets = observationsUp('s-w1', [
        _set('sx-1', slot: 'sl-1'),
      ], messageId: 'msg-set');

      // A session the phone is running: its efforts are the phone's, so the
      // wrist's set becomes a row of one of them (D-14).
      await phone.router.receive(sets);
      expect(
        [
          for (final row in await repository.getEffortObservations('sl-1'))
            row.id,
        ],
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'D-14 the wrist\'s set is a row of the effort the phone has',
      );
      expect(
        (await _staged(repository))['sx-1']?.appliedAtMs,
        isNotNull,
        reason: 'D-18 the phone used it, so the wrist may forget it',
      );
      expect(
        phone.transport.receiptedEntryIds,
        contains('sx-1'),
        reason: 'D-18 the receipt names what the merge applied',
      );

      // The wrist redelivers it, as an unacknowledged entry must be.
      await phone.router.receive(
        observationsUp('s-w1', [
          _set('sx-1', slot: 'sl-1'),
        ], messageId: 'msg-set-again'),
      );
      expect(
        _stagedIds(await _staged(repository)),
        ['sx-1'],
        reason: 'a redelivery is the same row, not a second one',
      );
      expect(
        [
          for (final row in await repository.getEffortObservations('sl-1'))
            row.id,
        ],
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'D-15 a redelivery writes no second entry',
      );

      // The end and the rating arrive: those it applies too.
      await phone.router.receive(
        observationsUp('s-w1', [
          _rating('s-w1', 4),
          _end('s-w1', avgHeartRateBpm: 140, maxHeartRateBpm: 165),
        ], messageId: 'msg-end'),
      );
      await phone.router.receive(_lifecycle('s-w1'));

      final staged = await _staged(repository);
      expect(
        _stagedIds(staged),
        ['end-s-w1', 'rating-s-w1', 'sx-1'],
        reason: 'every row of the session is held, and applied',
      );
      expect(staged['sx-1']?.appliedAtMs, isNotNull);
      expect(staged['end-s-w1']?.appliedAtMs, isNotNull);
      expect(await _heldRating(phone), 4);
      expect(
        [
          for (final effort in await importedEfforts(repository, 's-w1'))
            effort.id,
        ],
        ['sl-1', 'sl-2'],
        reason: 'D-14 the merge creates no effort',
      );
      expect(
        [
          for (final row in await repository.getEffortObservations('sl-1'))
            row.id,
        ],
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'the end and the rating add no entry',
      );

      final summaries = await repository.getSensorSummariesForSession('s-w1');
      expect(
        summaries.map((summary) => summary.id),
        ['sensor-session-s-w1'],
        reason: 'S-15 the held session\'s end attaches one session summary',
      );
      expect(summaries.single.avgHeartRateBpm, 140);
      expect(summaries.single.maxHeartRateBpm, 165);

      // Everything has been acknowledged, so a redelivery changes nothing.
      await phone.router.receive(
        observationsUp('s-w1', [
          _rating('s-w1', 4),
          _end('s-w1', avgHeartRateBpm: 140, maxHeartRateBpm: 165),
        ], messageId: 'msg-end-again'),
      );
      expect(_stagedIds(await _staged(repository)), _stagedIds(staged));
      expect(await _heldRating(phone), 4);
      expect(
        await repository.getSensorSummariesForSession('s-w1'),
        hasLength(1),
        reason: 'a redelivered end attaches no second summary',
      );
      expect(
        phone.state.currentSession?.endedAtMs,
        isNotNull,
        reason: 'the session stays ended',
      );
      expect(
        [
          for (final row in await repository.getEffortObservations('sl-1'))
            row.id,
        ],
        ['obs-sl-1-0-reps', 'obs-sl-1-0-weight'],
        reason: 'D-15 a redelivery writes no second entry',
      );
    },
  );

  test('a lifecycle naming another session changes nothing', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());

    await phone.router.receive(_lifecycle('s-other', messageId: 'msg-other'));

    expect(phone.state.currentSession?.id, 's-w1');
    expect(
      phone.state.currentSession?.endedAtMs,
      isNull,
      reason: 'a session the wrist never ran is not the one its end names',
    );
    expect(phone.mirror.state['sessionId'], 's-w1');
    expect(
      phone.mirror.state['status'],
      WatchSessionStatus.active,
      reason: 'the mirror folds only the session it holds',
    );
    expect(phone.lifecycles, isEmpty);
  });

  test('a wrist abandoned lifecycle discards the phone\'s copy', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    expect(phone.state.hasActiveSession, isTrue);

    await phone.router.receive(
      _lifecycle(
        's-w1',
        state: WatchLifecycleState.abandoned,
        messageId: 'msg-abandoned',
      ),
    );

    expect(
      phone.state.currentSession,
      isNull,
      reason: 'D-5 an abandoned wrist session is discarded, not kept',
    );
    expect(
      await repository.getSession('s-w1'),
      isNull,
      reason: 'the discard deletes the row the adoption created',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-189 the wrist\'s own announcement is answered with the reset', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    final p1 = await _startPhoneSession(phone, repository);
    final sentBefore = phone.transport.sent.length;

    await phone.router.receive(_snapshot(sessionId: 'w1'));

    final answer = phone.transport.sent.sublist(sentBefore);
    expect(
      [for (final frame in answer) frame['type']],
      ['session_lifecycle', 'session_snapshot'],
      reason: 'D-182 the reset is the end first, then the phone\'s session',
    );
    expect(answer.first['sessionId'], 'w1');
    expect(
      (answer.first['payload']! as Map)['state'],
      WatchLifecycleState.abandoned,
      reason: 'the wrist\'s session is not the one this phone is running',
    );
    expect(answer.last['sessionId'], p1, reason: 'P, not W, is sent');
    final projected = answer.last['payload']! as Map;
    final ownLadder = [
      for (final effort in phone.state.getEffortsForSegment(
        phone.state.segments.first.id,
      ))
        effort.id,
    ];
    expect(ownLadder, hasLength(2));
    expect(
      [
        for (final slot in (projected['exercises']! as List).cast<Map>())
          slot['sessionExerciseId'],
      ],
      ownLadder,
      reason: 'the answer carries the phone\'s own ladder, not the wrist\'s',
    );
    expect(
      projected['currentExerciseIndex'],
      0,
      reason: 'D-182 the answer is composed before W\'s index is applied here',
    );
    expect(
      phone.skipped,
      [(held: p1, offered: 'w1')],
      reason: 'D-10 the conflict is reported, once',
    );
    expect(
      phone.state.currentSession?.id,
      p1,
      reason: 'the phone keeps the session it holds (D-10)',
    );
    expect(
      phone.mirror.state['sessionId'],
      'w1',
      reason: 'D-176 the mirror is still on the wrist\'s session',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-190 a wrist session the phone has ended is not adopted back', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    final p1 = await _startPhoneSession(phone, repository);
    // W announces a session this phone is not in: D-182's second row ends it
    // under its own name. The phone then lets its own session go, so from here
    // on only its memory of that end can answer W.
    await phone.router.receive(_snapshot(sessionId: 'w1'));
    expect(phone.skipped, [(held: p1, offered: 'w1')]);
    await phone.state.discardCurrentSession();
    expect(phone.state.currentSession, isNull);
    expect(
      await phone.mirror.projectedSession(),
      isNull,
      reason: 'the phone has nothing to offer, so the fate is the whole answer',
    );

    final first = phone.transport.sent.length;
    await phone.router.receive(
      _snapshot(sessionId: 'w1', messageId: 'msg-again-1'),
    );
    expect(
      _sentFates(phone, first),
      [WatchLifecycleState.abandoned],
      reason: 'D-182 row three: the announced fate is the whole answer',
    );
    expect(
      phone.state.currentSession,
      isNull,
      reason: 'the phone does not adopt the session it has just ended',
    );

    // The memory survives the announcement that consumed it: the same frame
    // again is answered the same way, not adopted.
    final second = phone.transport.sent.length;
    await phone.router.receive(
      _snapshot(sessionId: 'w1', messageId: 'msg-again-2'),
    );
    expect(_sentFates(phone, second), [WatchLifecycleState.abandoned]);
    expect(phone.state.currentSession, isNull);

    // And it tracks the fate the phone announced, not that it announced one.
    await phone.mirror.reportLifecycleFor('w1', WatchLifecycleState.completed);
    final third = phone.transport.sent.length;
    await phone.router.receive(
      _snapshot(sessionId: 'w1', messageId: 'msg-again-3'),
    );
    expect(_sentFates(phone, third), [WatchLifecycleState.completed]);
    expect(phone.state.currentSession, isNull);
    expect(
      await phone.mirror.projectedSession(),
      isNull,
      reason: 'the announcements never loaded the ended session back',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-190b a fate outlives the mirror that wrote it', () async {
    final repository = await _repository();
    final phone = await _phone(repository);

    // The phone adopts the wrist's session W and ends it by name, so the end
    // is the phone's own announcement and the mirror still holds W when it
    // records how W ended.
    await phone.router.receive(
      _snapshot(sessionId: 'w1', messageId: 'msg-w1-first'),
    );
    expect(phone.state.currentSession?.id, 'w1');
    await phone.mirror.reportLifecycleFor('w1', WatchLifecycleState.completed);
    expect(
      phone.mirror.status,
      WatchSessionStatus.completed,
      reason: 'the fixture: the mirror holds w1, so the end applies here too',
    );

    // The mirror then moves on — off W entirely — and the phone holds nothing:
    // from here on nothing but the memory can say how W ended.
    await phone.state.discardCurrentSession();
    expect(
      await repository.getSession('w1'),
      isNull,
      reason:
          'S-190b the ended session leaves no row: the memory, not history, '
          'is what this phone has to answer W with',
    );
    await phone.router.receive(
      _snapshot(sessionId: 'x1', messageId: 'msg-x1-next'),
    );
    await phone.state.discardCurrentSession();
    expect(phone.state.currentSession, isNull);
    expect(phone.mirror.state['sessionId'], 'x1');

    final sentBefore = phone.transport.sent.length;
    await phone.router.receive(
      _snapshot(sessionId: 'w1', messageId: 'msg-w1-again'),
    );

    expect(
      [
        for (final frame in phone.transport.sent.skip(sentBefore))
          '${frame['type']}:${frame['sessionId']}',
      ],
      ['session_lifecycle:w1'],
      reason:
          'S-190b the remembered fate is the whole answer: one frame, naming '
          'the wrist\'s own session, and no state to send',
    );
    expect(
      _sentFates(phone, sentBefore),
      [WatchLifecycleState.completed],
      reason:
          'S-190b how this phone ended W is remembered past the mirror that '
          'wrote it — the row is gone, so without the memory W would be '
          'adopted back and left `active`',
    );
    expect(
      phone.state.currentSession,
      isNull,
      reason: 'D-182 row three: the session the phone ended is not adopted back',
    );
    expect(phone.skipped, isEmpty);
    expect(phone.failures, isEmpty);
  });

  test('S-191 a wrist session the phone does not know is adopted', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    final sentBefore = phone.transport.sent.length;

    final receipt = await phone.router.receive(_snapshot(sessionId: 'w2'));

    expect(receipt.session, MirrorOutcome.applied);
    expect(
      phone.transport.sent.length,
      sentBefore,
      reason: 'the phone ADOPTS a wrist session when it has none (owner rule)',
    );
    expect(phone.lifecycles, isEmpty, reason: 'nothing is ended');
    expect(phone.skipped, isEmpty, reason: 'D-10 there is no conflict to report');
    expect(
      await phone.bridge.consider({
        'sessionId': 'w2',
        'status': WatchSessionStatus.active,
      }),
      WatchSessionAdoption.alreadyHeld,
      reason: 'S-191 the verdict was `adopted`: W is the phone\'s own now',
    );
    expect(phone.state.currentSession?.id, 'w2');
    expect(
      [
        for (final effort in phone.state.getEffortsForSegment(
          phone.state.segments.first.id,
        ))
          effort.id,
      ],
      ['sl-1', 'sl-2'],
      reason: 'D-2 the wrist\'s ladder is loaded as the phone\'s own',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-192 a wrist snapshot the phone already holds is answered with '
      'nothing', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(sessionId: 'w1'));
    // What a converged pair looks like on the wire: the wrist echoes the state
    // the phone last sent it.
    final echo = phone.mirror.snapshotEnvelope(
      state: (await phone.mirror.projectedSession())!,
      messageId: 'msg-converged',
    );
    final sentBefore = phone.transport.sent.length;

    final receipt = await phone.router.receive(echo);

    expect(receipt.session, MirrorOutcome.applied);
    expect(
      phone.transport.sent.length,
      sentBefore,
      reason: 'D-182 row one: a pair that agrees is answered with nothing',
    );
    expect(
      phone.lifecycles,
      isEmpty,
      reason: 'no end is announced for a session the phone is in',
    );
    expect(phone.state.currentSession?.id, 'w1');
    expect(phone.skipped, isEmpty);
    expect(phone.failures, isEmpty);
  });

  test('S-192 a wrist snapshot of a phone row that is history is answered '
      'with its end', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(sessionId: 'w1'));
    // The phone finishes the session and has announced no fate for it: the row
    // is history, and this phone does not remember why.
    await phone.state.endSession();
    final sentBefore = phone.transport.sent.length;

    await phone.router.receive(
      _snapshot(sessionId: 'w1', messageId: 'msg-after-own-end'),
    );

    expect(
      _sentFates(phone, sentBefore),
      [WatchLifecycleState.completed],
      reason: 'G1/D-182 row four: history is answered with the phone\'s end',
    );
    expect(
      phone.state.currentSession?.endedAtMs,
      isNotNull,
      reason: 'G1 nothing is loaded back into the phone\'s live state',
    );
    expect(
      phone.mirror.state['status'],
      WatchSessionStatus.completed,
      reason: 'the answer is the phone\'s own end, applied here first',
    );
    expect(phone.skipped, isEmpty);
    expect(phone.failures, isEmpty);
  });

  test('S-193 an answer the transport dropped returns at the wrist\'s next '
      'announcement', () async {
    final repository = await _repository();
    final phone = await _phone(repository);
    final p1 = await _startPhoneSession(phone, repository);
    var failing = true;
    phone.transport.onSend = (envelope) async {
      if (failing && envelope['type'] == 'session_lifecycle') {
        failing = false;
        throw StateError('the phone\'s radio is down');
      }
    };

    await expectLater(
      phone.router.receive(_snapshot(sessionId: 'w1')),
      throwsA(isA<StateError>()),
    );
    expect(
      phone.transport.sent,
      isEmpty,
      reason: 'D-183 a failed answer is not queued and not retried in place',
    );

    final sentBefore = phone.transport.sent.length;
    await phone.router.receive(
      _snapshot(sessionId: 'w1', messageId: 'msg-next-activation'),
    );

    expect(
      _sentFates(phone, sentBefore),
      [WatchLifecycleState.abandoned],
      reason: 'D-183 the next announcement earns the full answer',
    );
    final delta = phone.transport.sent.sublist(sentBefore);
    expect(
      [
        for (final frame in delta)
          if (frame['type'] == 'session_lifecycle') frame['sessionId'],
      ],
      ['w1'],
      reason: 'the end names the announced session, never the phone\'s own',
    );
    final snapshots = [
      for (final frame in delta)
        if (frame['type'] == 'session_snapshot') frame,
    ];
    expect(snapshots, isNotEmpty, reason: 'the answer ends W, then sends P');
    expect(
      snapshots.last['sessionId'],
      p1,
      reason: 'D-182 the answer closes with P, the phone\'s own session',
    );
    expect(
      phone.skipped,
      [(held: p1, offered: 'w1')],
      reason: 'D-10 the conflict is reported once, across the retry',
    );
    expect(phone.state.currentSession?.id, p1);
    expect(phone.mirror.state['sessionId'], 'w1');
    expect(phone.failures, isEmpty);
  });

  // The wrist's own End is a rest's ending too (D-220, D-223): the rest left
  // running is stopped at the instant the terminal row records, and reported,
  // so the phone's total has both of its ends. The real engine over a real
  // store — no phone graph is involved here.
  group('S-322 / S-331 a rest cannot outlive the workout', () {
    late _WristClock clock;
    late InMemoryWatchSessionStore store;
    late WatchSessionEngine engine;
    late String setEntryId;

    setUp(() async {
      clock = _WristClock(DateTime.utc(2026, 10, 8, 12));
      store = InMemoryWatchSessionStore();
      engine = WatchSessionEngine(
        store,
        clock: clock.call,
        sessionIdFactory: () => 's-w1',
      );
      await engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_wristSlot()],
      );
      await engine.appendObservation(_wristSet(clock.now));
      setEntryId = engine.observations.single.entryId;
      await engine.startTimer(WatchTimerKind.rest);
    });

    test('S-322 End stops the rest, reports it, and the end comes last', () async {
      final restStartedAt = clock.now;
      clock.advance(const Duration(seconds: 30));
      await engine.finishSession();

      final rest = engine.observations.singleWhere(
        (row) => row.kind == WatchObservationKind.rest,
      );
      expect(rest.payload['afterEntryId'], setEntryId);
      expect(rest.payload['sessionExerciseId'], 'sl-1');
      expect(rest.payload['startedAt'], utcIso(restStartedAt));
      expect(
        rest.payload['endedAt'],
        utcIso(clock.now),
        reason: 'S-322 the rest ends where the workout did',
      );
      expect(
        engine.observations.map((row) => row.kind),
        ['set', 'rest'],
        reason: 'S-322 the rest is written before the terminal row is built',
      );

      final stopped = engine.timerFor(WatchTimerKind.rest)!;
      expect(stopped.state, WatchTimerState.stopped);
      expect(stopped.stoppedAt, clock.now);
      expect(engine.session!.status, WatchSessionStatus.completed);
      expect(
        engine.session!.exercises.map((slot) => slot['sessionExerciseId']),
        ['sl-1'],
        reason: 'the terminal row was built after the stop, so it kept the slot',
      );

      final written = engine.observations.length;
      engine.replaySessionEnd();
      expect(
        engine.observations.length,
        written,
        reason: 'S-322 a replayed end adds nothing: the rest is already over',
      );
    });

    test('S-331 the rebuilt engine holds no running rest', () async {
      clock.advance(const Duration(seconds: 30));
      await engine.finishSession();

      final relaunched = WatchSessionEngine(
        store,
        clock: clock.call,
        sessionIdFactory: () => 's-w1',
      );
      await relaunched.restore();

      expect(relaunched.session!.status, WatchSessionStatus.completed);
      expect(
        relaunched.timerFor(WatchTimerKind.rest)!.state,
        WatchTimerState.stopped,
        reason: 'S-331 no rest survives the workout it was running in',
      );
      expect(
        relaunched.observations.map((row) => row.kind),
        ['set', 'rest'],
        reason:
            'S-331 the rest the end reported is stored, so the phone still '
            'owes it a receipt',
      );
      expect(
        relaunched.observations
            .singleWhere((row) => row.kind == WatchObservationKind.rest)
            .payload['afterEntryId'],
        setEntryId,
        reason: 'S-331 and it still names the set it followed',
      );
    });
  });
}
