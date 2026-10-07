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
import 'package:omnitrain/watch/session/watch_records.dart';

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
    // holds one (D-10), and is not an end either.
    await phone.router.receive(
      _snapshot(sessionId: 's-other', messageId: 'msg-other'),
    );
    expect(
      phone.lifecycles,
      isEmpty,
      reason: 'G1 an unadopted session is not a finished one',
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
}
