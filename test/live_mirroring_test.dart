// Live session mirroring — watch ↔ phone convergence over the sync protocol.
//
// Plan: `docs/plans/2026-07-13-09-c1-live-session-mirroring-plan.md`.
// Scenario mapping:
//   S-001 a set logged on the watch reaches the phone  → `S-001 ...`
//   S-002 a phone structure change reaches the watch   → `S-002 ...`
//   S-003 reconnect: no loss, no duplicates            → `S-003 ...`
//   S-004 removing the watch's current exercise        → `S-004 ...`
//   S-005 the timer's end moment is the same           → `S-005 ...`
//   S-006 joining a phone session from the watch       → `S-006 ...`
//   S-007 forced redelivery produces no duplicates     → `S-007 ...`
//   S-251 a snapshot of another session replaces it    → `S-251 ...`
//         (Stats PR 2, `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
//         D-130; S-252 is the S-008 group, which stays unchanged)
//
// Two implementations, one register. The phone's live mirror
// (`lib/state/watch/live_session_mirror_state.dart`) and the watch's engine
// (`lib/watch/session/watch_session_engine.dart`, the Wear OS half of the
// native watchOS engine) are both replayed through the same reconciliation
// fixtures, so "converges" is the fixture's verdict, not this file's opinion.
//
// The link between the two devices is an in-process transport pair: `send`
// carries an envelope to the peer, `requestSnapshot` asks for one, and a
// severed link buffers exactly as a radio would. Nothing here is a mock of the
// code under test — both devices run their real implementations.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_timer_math.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

import 'helpers/sync_protocol_harness.dart';

/// Every reconciliation fixture that replays from a snapshot.
List<Map<String, Object?>> _replayableFixtures() {
  final manifest = readProtocolJson('fixtures/manifest.json');
  return [
    for (final scenario in objectsOf(manifest['scenarios']))
      if (readProtocolJson('fixtures/${scenario['path']}')['snapshot'] != null)
        {
          'path': scenario['path'],
          'fixture': readProtocolJson('fixtures/${scenario['path']}'),
        },
  ];
}

Map<String, Object?> _slot(
  String slot, {
  String name = 'Barbell Bench Press',
}) => {
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'name': name,
  'capabilities': ['sets', 'reps', 'load'],
};

/// A schema-conformant `set` observation, the way the logging surfaces hand it
/// to the engine.
Map<String, Object?> _setEvent(
  TestClock clock, {
  required String entryId,
  String slot = 'sx-bench',
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': isoUtc(clock.now),
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'reps': 5,
  'loadKg': 80,
};

Map<String, Object?> _snapshotPayload({
  String sessionId = 's-live-1',
  String status = WatchSessionStatus.active,
  int revision = 0,
  int currentExerciseIndex = 0,
  List<Map<String, Object?>> exercises = const [],
  List<Map<String, Object?>> entries = const [],
  Map<String, Object?> timers = const {},
}) => {
  'sessionId': sessionId,
  'status': status,
  'revision': revision,
  'currentExerciseIndex': currentExerciseIndex,
  'exercises': exercises,
  'entries': entries,
  'timers': timers,
};

/// A `session_snapshot` envelope over [payload], as the other device would send
/// it.
Map<String, Object?> _snapshot({
  String sessionId = 's-live-1',
  String status = WatchSessionStatus.active,
  int revision = 0,
  int currentExerciseIndex = 0,
  List<Map<String, Object?>> exercises = const [],
  List<Map<String, Object?>> entries = const [],
  Map<String, Object?> timers = const {},
  String origin = 'watch',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-snapshot-$revision-$origin',
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': origin,
  'sentAt': '2026-07-13T06:30:00Z',
  'payload': _snapshotPayload(
    sessionId: sessionId,
    status: status,
    revision: revision,
    currentExerciseIndex: currentExerciseIndex,
    exercises: exercises,
    entries: entries,
    timers: timers,
  ),
};

/// Timers compare by instant, not by spelling: the engine writes timestamps in
/// the protocol's wire shape with milliseconds, a fixture may write the same
/// instant without them.
Map<String, Object?> _normalizedTimer(Map<String, Object?> timer) => {
  for (final entry in timer.entries)
    entry.key: switch (entry.key) {
      'startedAt' ||
      'pausedAt' ||
      'stoppedAt' => DateTime.parse(entry.value! as String),
      _ => entry.value,
    },
};

List<String> _slotIds(WatchSessionEngine engine) => [
  for (final slot in engine.session?.exercises ?? const [])
    slot['sessionExerciseId']! as String,
];

/// The slot order a converged `exercises` list carries — the phone's state, in
/// the same shape `_slotIds` reads from the watch's session.
List<String> _slotIdsIn(Object? exercises) => [
  for (final slot in objectsOf(exercises)) slot['sessionExerciseId']! as String,
];

/// One watch and one phone, joined by an in-process transport pair.
///
/// Severing the link models airplane mode: both devices keep working and the
/// transport buffers what it cannot carry, exactly as a store-and-forward radio
/// would.
class _Session {
  _Session({required Map<String, Object?> phoneState, TestClock? clock})
    : clock = clock ?? TestClock(DateTime.utc(2026, 7, 13, 6)) {
    final validator = loadProtocolValidator();
    final store = InMemoryWatchSessionStore();

    _watchTransport = _WatchTransport(this);
    _phoneTransport = _PhoneTransport(this);

    engine = WatchSessionEngine(
      store,
      onEmit: emitted.add,
      validator: validator,
      clock: this.clock.call,
      idFactory: () => 'rec-${++_ids}',
      sessionIdFactory: () => 's-live-1',
    );
    paths = WatchSessionStartPaths(
      engine: engine,
      store: store,
      validator: validator,
      clock: this.clock.call,
      idFactory: () => 'rec-${++_ids}',
    );
    orchestrator = WatchSyncOrchestrator(
      transport: _watchTransport,
      paths: paths,
      engine: engine,
    );
    phone = LiveSessionMirrorState(
      transport: _phoneTransport,
      snapshot: phoneState,
      validator: validator,
      clock: this.clock.call,
      idFactory: () => 'msg-${++_ids}',
    );
    phone.addListener(() => phoneNotifications++);
  }

  final TestClock clock;
  late final WatchSessionEngine engine;
  late final WatchSessionStartPaths paths;
  late final WatchSyncOrchestrator orchestrator;
  late final LiveSessionMirrorState phone;
  late final _WatchTransport _watchTransport;
  late final _PhoneTransport _phoneTransport;

  /// Everything the engine handed its sink.
  final List<Map<String, Object?>> emitted = [];

  /// Notifications the phone's live surface would re-render on.
  int phoneNotifications = 0;

  int _ids = 0;

  /// Whether the radio is up. A severed link buffers instead of delivering.
  bool linked = true;

  WatchSessionRecord get watchSession => engine.session!;

  List<String> get watchOrder => _slotIds(engine);

  /// Delivers everything the watch has emitted and not yet handed over.
  Future<void> deliverEmitted() async {
    final pending = [...emitted];
    emitted.clear();
    for (final envelope in pending) {
      await _watchTransport.send(envelope);
    }
  }

  /// The reconnect sequence: what the watch owes goes up, both sides exchange
  /// snapshots, and only then is the session converged.
  Future<void> reconnect() async {
    linked = true;
    await orchestrator.sync(reconnect: true);
    await phone.sync();
  }
}

/// The radio, watch half.
class _WatchTransport implements WatchSyncTransport {
  _WatchTransport(this.session);

  final _Session session;

  /// What the transport could not carry while the link was down.
  final List<Map<String, Object?>> buffered = [];

  /// Everything that went up, whether or not it was carried.
  final List<Map<String, Object?>> sent = [];

  /// How many times the watch asked the phone for its snapshot.
  int snapshotRequests = 0;

  @override
  bool isPhoneReachable = true;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {
    snapshotRequests++;
    if (session.linked) await session.phone.sendSnapshot();
  }

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    if (session.linked) {
      await session.phone.receive(envelope);
    } else {
      buffered.add(envelope);
    }
  }
}

/// The radio, phone half.
class _PhoneTransport implements WatchMirrorTransport {
  _PhoneTransport(this.session);

  final _Session session;

  /// Everything the phone sent down, whether or not it was carried.
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    if (session.linked) await session.orchestrator.receive(envelope);
  }

  @override
  Future<void> requestSnapshot() async {
    await session.orchestrator.answerSnapshotRequest();
  }
}

/// A phone with nobody on the other end: what the mirror sends is recorded and
/// nothing comes back, which is what a fixture replay needs.
class _RecordingTransport implements WatchMirrorTransport {
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);

  @override
  Future<void> requestSnapshot() async {}
}

void main() {
  group('S-001 a set logged on the watch reaches the phone', () {
    test('the entry is on the phone without the phone asking', () async {
      final session = _Session(
        phoneState: _snapshotPayload(
          exercises: [_slot('sx-bench'), _slot('sx-plank')],
        ),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench'), _slot('sx-plank')],
      );
      await session.deliverEmitted();

      await session.engine.appendObservation(
        _setEvent(session.clock, entryId: 'e-live-1'),
      );
      await session.deliverEmitted();

      final entries = objectsOf(session.phone.state['entries']);
      expect(entries, hasLength(1));
      expect(entries.single['entryId'], 'e-live-1');
      expect(entries.single['reps'], 5);
      expect(
        session.phoneNotifications,
        greaterThan(0),
        reason: 'the live view re-renders on the change, not on a poll',
      );
    });
  });

  group('S-002 a phone structure change reaches the watch', () {
    test('a reorder lands on the wrist and on the phone', () async {
      final session = _Session(
        phoneState: _snapshotPayload(
          exercises: [_slot('sx-bench'), _slot('sx-plank'), _slot('sx-squat')],
        ),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench'), _slot('sx-plank'), _slot('sx-squat')],
      );
      await session.deliverEmitted();

      await session.phone.applyStructureChange([
        {
          'kind': 'reorder_exercises',
          'order': ['sx-squat', 'sx-bench', 'sx-plank'],
        },
      ]);

      expect(session.watchOrder, ['sx-squat', 'sx-bench', 'sx-plank']);
      expect(_slotIdsIn(session.phone.state['exercises']), [
        'sx-squat',
        'sx-bench',
        'sx-plank',
      ]);
      expect(session.phone.state['revision'], 1);
    });
  });

  group('S-003 reconnect after offline logging', () {
    test('exactly the entries logged while apart arrive, once', () async {
      final session = _Session(
        phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench')],
      );
      await session.deliverEmitted();

      // Airplane mode: the phone is out of reach.
      session.linked = false;
      for (var index = 1; index <= 5; index++) {
        await session.engine.appendObservation(
          _setEvent(session.clock, entryId: 'e-offline-$index'),
        );
      }
      expect(session.phone.state['entries'], isEmpty);

      await session.reconnect();

      final entries = objectsOf(session.phone.state['entries']);
      expect(entries, hasLength(5));
      expect(entries.map((entry) => entry['entryId']), [
        'e-offline-1',
        'e-offline-2',
        'e-offline-3',
        'e-offline-4',
        'e-offline-5',
      ]);
      expect(
        session.engine.pendingObservations(),
        isEmpty,
        reason: "the phone's snapshot is the receipt for what it holds",
      );
    });

    test('a redelivered stream changes nothing', () async {
      final session = _Session(
        phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench')],
      );
      await session.deliverEmitted();
      await session.engine.appendObservation(
        _setEvent(session.clock, entryId: 'e-live-1'),
      );
      await session.deliverEmitted();

      final before = Map<String, Object?>.of(session.phone.state);

      // The transport retries everything it ever carried, twice over.
      for (final envelope in [
        ...session._watchTransport.sent,
        ...session._watchTransport.sent,
      ]) {
        await session.phone.receive(envelope);
      }

      expect(
        session.phone.state,
        equals(before),
        reason: 're-delivery is a no-op end to end',
      );
      expect(objectsOf(session.phone.state['entries']), hasLength(1));
    });
  });

  group('S-004 removing the watch\'s current exercise', () {
    test('the watch advances and nothing else moves', () async {
      final session = _Session(
        phoneState: _snapshotPayload(
          currentExerciseIndex: 1,
          exercises: [_slot('sx-bench'), _slot('sx-plank'), _slot('sx-squat')],
        ),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench'), _slot('sx-plank'), _slot('sx-squat')],
      );
      await session.engine.advanceExercise();
      await session.engine.appendObservation(
        _setEvent(session.clock, entryId: 'e-plank-1', slot: 'sx-plank'),
      );
      await session.engine.startTimer(
        WatchTimerKind.rest,
        plannedDurationMs: 90000,
      );
      final rest = session.engine.timerFor(WatchTimerKind.rest)!;
      await session.deliverEmitted();

      await session.phone.applyStructureChange([
        {'kind': 'remove_exercise', 'sessionExerciseId': 'sx-plank'},
      ]);

      expect(session.watchOrder, ['sx-bench', 'sx-squat']);
      expect(
        session.watchSession.currentExerciseIndex,
        1,
        reason: 'the position stays and now holds the exercise that followed',
      );
      expect(
        session.engine.entries.map((entry) => entry.entryId),
        contains('e-plank-1'),
        reason: 'entries logged against a removed slot stay logged',
      );
      final after = session.engine.timerFor(WatchTimerKind.rest)!;
      expect(after.recordId, rest.recordId);
      expect(after.state, WatchTimerState.running);
    });
  });

  group('S-005 the timer\'s end moment is the same on both devices', () {
    test(
      'a rest timer started on the wrist ends when the phone says it does',
      () async {
        final session = _Session(
          phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
        );
        await session.engine.createSession(
          modality: 'resistance_lifting',
          exercises: [_slot('sx-bench')],
        );
        await session.deliverEmitted();

        final timer = await session.engine.startTimer(
          WatchTimerKind.rest,
          plannedDurationMs: 90000,
        );
        await session.deliverEmitted();

        final onPhone = asObject(
          asObject(session.phone.state['timers'])['rest'],
        );
        expect(onPhone['kind'], 'rest');
        expect(
          onPhone.containsKey('remainingSeconds'),
          isFalse,
          reason: 'a countdown is never sent; the receiver derives it',
        );
        expect(
          completionInstant(timer),
          session.phone.timerEnd('rest'),
          reason: 'both sides derive the end from the same timestamps',
        );
        expect(
          session.phone.timerEnd('rest'),
          equals(session.clock.now.add(const Duration(seconds: 90))),
        );
      },
    );
  });

  group('S-006 joining an in-progress phone session from the watch', () {
    test('the watch comes back populated', () async {
      final session = _Session(
        phoneState: _snapshotPayload(
          currentExerciseIndex: 1,
          revision: 7,
          exercises: [_slot('sx-bench'), _slot('sx-plank')],
          entries: [
            {
              'entryId': 'e-phone-1',
              'eventId': 'e-phone-1',
              'kind': 'set',
              'loggedAt': '2026-07-13T06:10:00Z',
              'sessionExerciseId': 'sx-bench',
              'exerciseId': 'ex-sx-bench',
              'reps': 8,
              'loadKg': 60,
            },
            {
              'entryId': 'e-phone-2',
              'eventId': 'e-phone-2',
              'kind': 'hold',
              'loggedAt': '2026-07-13T06:20:00Z',
              'sessionExerciseId': 'sx-plank',
              'exerciseId': 'ex-sx-plank',
              'startedAt': '2026-07-13T06:19:00Z',
              'endedAt': '2026-07-13T06:20:00Z',
            },
          ],
          timers: {
            'rest': {
              'kind': 'rest',
              'state': 'running',
              'startedAt': '2026-07-13T06:25:00Z',
              'accumulatedPauseMs': 0,
              'plannedDurationMs': 90000,
            },
          },
        ),
      );
      // A watch with nothing on it: the session lives on the phone.
      await session.engine.restore();
      expect(session.engine.session, isNull);

      await session.orchestrator.sync(reconnect: true);

      expect(session._watchTransport.snapshotRequests, 1);
      final joined = session.watchSession;
      expect(joined.sessionId, 's-live-1');
      expect(joined.status, WatchSessionStatus.active);
      expect(joined.revision, 7);
      expect(joined.currentExerciseIndex, 1);
      expect(_slotIds(session.engine), ['sx-bench', 'sx-plank']);
      expect(
        session.engine.entries.map((entry) => entry.entryId),
        ['e-phone-1', 'e-phone-2'],
        reason: 'prior observations come with the session',
      );
      final rest = session.engine.timerFor(WatchTimerKind.rest)!;
      expect(rest.state, WatchTimerState.running);
      expect(completionInstant(rest), DateTime.utc(2026, 7, 13, 6, 26, 30));
    });
  });

  group('S-007 forced redelivery produces no duplicates', () {
    test('a duplicated snapshot leaves both devices where they were', () async {
      final session = _Session(
        phoneState: _snapshotPayload(
          exercises: [_slot('sx-bench')],
          entries: [
            {
              'entryId': 'e-1',
              'eventId': 'e-1',
              'kind': 'set',
              'loggedAt': '2026-07-13T06:05:00Z',
              'sessionExerciseId': 'sx-bench',
              'exerciseId': 'ex-sx-bench',
              'reps': 5,
              'loadKg': 80,
            },
          ],
        ),
      );
      await session.engine.restore();
      final snapshot = session.phone.snapshotEnvelope();

      await session.engine.applyMessage(snapshot);
      final afterFirst = Map<String, Object?>.of(session.phone.state);
      final watchEntries = [...session.engine.entries.map((e) => e.entryId)];
      await session.engine.applyMessage(snapshot);

      expect(session.phone.state, equals(afterFirst));
      expect(session.engine.entries.map((e) => e.entryId), watchEntries);
      expect(watchEntries, ['e-1']);
      expect(_slotIds(session.engine), ['sx-bench']);
    });
  });

  group(
    'S-008 a snapshot the phone disagrees with is answered with its own',
    () {
      test('the phone re-asserts its state and keeps it', () async {
        final session = _Session(
          phoneState: _snapshotPayload(
            revision: 5,
            exercises: [_slot('sx-bench'), _slot('sx-plank')],
          ),
        );
        final before = Map<String, Object?>.of(session.phone.state);
        final sentBefore = session._phoneTransport.sent.length;

        // A watch snapshot that reports a different shape.
        final outcome = await session.phone.receive(
          _snapshot(
            revision: 3,
            exercises: [_slot('sx-squat')],
            origin: 'watch',
          ),
        );

        expect(outcome, MirrorOutcome.applied);
        expect(
          session._phoneTransport.sent.length,
          sentBefore + 1,
          reason: 'structure is the phone\'s to own, so it answers',
        );
        final answer = asObject(session._phoneTransport.sent.last['payload']);
        expect(answer['revision'], 5);
        expect(answer['exercises'], before['exercises']);
      });

      test('an identical snapshot is left unanswered', () async {
        final session = _Session(
          phoneState: _snapshotPayload(
            revision: 5,
            exercises: [_slot('sx-bench')],
          ),
        );
        final sentBefore = session._phoneTransport.sent.length;

        // The phone's own state, arriving back from the watch.
        final outcome = await session.phone.receive(
          session.phone.snapshotEnvelope(),
        );

        expect(outcome, MirrorOutcome.applied);
        expect(
          session._phoneTransport.sent.length,
          sentBefore,
          reason: 'two agreeing devices must not answer each other for ever',
        );
      });
    },
  );

  group(
    'S-009 a sessionless watch answers a snapshot request with nothing',
    () {
      test('the watch sends no empty session when it has none', () async {
        final session = _Session(
          phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
        );
        await session.engine.restore();
        expect(session.engine.session, isNull);

        await session.orchestrator.answerSnapshotRequest();

        expect(
          session._watchTransport.sent,
          isEmpty,
          reason:
              'a watch with nothing logged has nothing authoritative to report',
        );
      });

      test('joining asks for a snapshot rather than offering one', () async {
        final session = _Session(
          phoneState: _snapshotPayload(
            revision: 4,
            exercises: [_slot('sx-bench'), _slot('sx-plank')],
          ),
        );
        await session.engine.restore();

        await session.orchestrator.sync(reconnect: true);

        expect(session._watchTransport.snapshotRequests, 1);
        expect(
          session._watchTransport.sent.where(
            (envelope) => envelope['type'] == 'session_snapshot',
          ),
          isEmpty,
        );
        expect(session.engine.session, isNotNull);
      });
    },
  );

  group('S-010 the phone drives the session it owns', () {
    test('a pushed exercise lands on the watch at the named index', () async {
      final session = _Session(
        phoneState: _snapshotPayload(
          exercises: [_slot('sx-bench'), _slot('sx-squat')],
        ),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench'), _slot('sx-squat')],
      );
      await session.deliverEmitted();

      final pushed = await session.phone.pushExercise(
        _slot('sx-pullup'),
        atIndex: 1,
      );

      expect(pushed['type'], 'exercise_push');
      expect(pushed['origin'], 'phone');
      expect(session.watchOrder, ['sx-bench', 'sx-pullup', 'sx-squat']);
      expect(
        _slotIdsIn(session.phone.state['exercises']),
        ['sx-bench', 'sx-pullup', 'sx-squat'],
        reason:
            'the phone applies what it originates, before telling the watch',
      );
    });

    test('completing from the phone closes the session on the watch', () async {
      final session = _Session(
        phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench')],
      );
      await session.deliverEmitted();

      final lifecycle = await session.phone.reportLifecycle(
        WatchLifecycleState.completed,
      );

      expect(lifecycle['type'], 'session_lifecycle');
      expect(session.watchSession.status, WatchSessionStatus.completed);
      expect(session.phone.state['status'], WatchSessionStatus.completed);
    });
  });

  group('a message the receiver cannot read', () {
    test('the phone refuses it and answers with its snapshot', () async {
      final session = _Session(
        phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
      );
      final before = Map<String, Object?>.of(session.phone.state);
      final v2 = readProtocolJson(
        'fixtures/reconciliation/version_mismatch.json',
      );
      final message = asObject(
        asObject((v2['cases']! as List).last)['message'],
      );

      final outcome = await session.phone.receive(message);

      expect(outcome, MirrorOutcome.refused);
      expect(session.phone.state, equals(before));
      final answer = session._phoneTransport.sent.last;
      expect(answer['type'], 'session_snapshot');
      expect(answer['protocolVersion'], SyncProtocolValidator.protocolVersion);
    });

    test(
      'a conformant message for another surface is ignored, not refused',
      () async {
        final session = _Session(
          phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
        );
        final before = Map<String, Object?>.of(session.phone.state);
        final sentBefore = session._phoneTransport.sent.length;
        final routines = readProtocolJson('fixtures/valid/routines_down.json');

        final outcome = await session.phone.receive(routines);

        expect(outcome, MirrorOutcome.ignored);
        expect(session.phone.state, equals(before));
        expect(
          session._phoneTransport.sent.length,
          sentBefore,
          reason: 'nothing to converge, so nothing is sent',
        );
      },
    );

    test('the watch refuses it and answers with its snapshot', () async {
      final session = _Session(
        phoneState: _snapshotPayload(exercises: [_slot('sx-bench')]),
      );
      await session.engine.createSession(
        modality: 'resistance_lifting',
        exercises: [_slot('sx-bench')],
      );
      await session.deliverEmitted();
      final v2 = readProtocolJson(
        'fixtures/reconciliation/version_mismatch.json',
      );
      final message = asObject(
        asObject((v2['cases']! as List).last)['message'],
      );

      await expectLater(
        session.orchestrator.receive(message),
        throwsA(isA<WatchEmissionRejected>()),
      );

      expect(session._watchTransport.sent.last['type'], 'session_snapshot');
      expect(_slotIds(session.engine), ['sx-bench']);
    });
  });

  // D-130. A second workout the wrist started is not a continuation of the one
  // the phone holds: the phone adopts it rather than re-asserting the old one
  // (which would yank the wrist back to it), and the record the phone closed for
  // the old one is not the new one's.
  group('S-251 a snapshot naming another session replaces the held one', () {
    test('S-251 the phone adopts it, answers nothing, and a later Finish '
        'closes the new session', () async {
      final clock = TestClock(DateTime.utc(2026, 9, 25, 9));
      var ids = 0;
      final transport = _RecordingTransport();
      final phone = LiveSessionMirrorState(
        transport: transport,
        snapshot: _snapshotPayload(
          sessionId: 's-prev',
          exercises: [_slot('sx-p')],
          entries: [
            _setEvent(
              TestClock(DateTime.utc(2026, 9, 25, 8, 30)),
              entryId: 'e-p1',
              slot: 'sx-p',
            ),
          ],
        ),
        validator: loadProtocolValidator(),
        clock: clock.call,
        idFactory: () => 'msg-${++ids}',
      );

      // The phone's own Finish closes s-prev and leaves its record.
      final previous = await phone.completeSession();
      expect(previous['sessionId'], 's-prev');
      expect(phone.status, WatchSessionStatus.completed);
      final sentBefore = transport.sent.length;

      final outcome = await phone.receive(
        _snapshot(
          sessionId: 's-next',
          exercises: [_slot('sx-b')],
          entries: [
            _setEvent(
              TestClock(DateTime.utc(2026, 9, 25, 9, 5)),
              entryId: 'e-b1',
              slot: 'sx-b',
            ),
          ],
          origin: 'watch',
        ),
      );

      expect(outcome, MirrorOutcome.applied);
      expect(phone.sessionId, 's-next', reason: 'S-251 the mirror is on s-next');
      expect(phone.status, WatchSessionStatus.active);
      expect(_slotIdsIn(phone.state['exercises']), ['sx-b']);
      expect(
        [for (final entry in phone.entries) entry['entryId']],
        ['e-b1'],
        reason: 'S-251 entries never merge across sessions',
      );
      expect(
        phone.completedRecord,
        isNull,
        reason: 'S-251 the record the phone closed belongs to s-prev',
      );
      expect(
        transport.sent.length,
        sentBefore,
        reason:
            'S-251 a snapshot of another session is adopted, never answered',
      );

      clock.advance(const Duration(minutes: 30));
      final next = await phone.completeSession();
      expect(
        next['sessionId'],
        's-next',
        reason: 'S-251 a later Finish closes the adopted session',
      );
      expect([
        for (final entry in objectsOf(next['entries'])) entry['entryId'],
      ], ['e-b1']);
      expect(transport.sent.last['type'], 'session_lifecycle');
      expect(transport.sent.last['sessionId'], 's-next');
    });
  });

  group('the reconciliation register drives both engines', () {
    for (final fixture in _replayableFixtures()) {
      final path = fixture['path']! as String;
      final replay = asObject(fixture['fixture']);

      test('phone: $path converges on its expected state', () async {
        final phone = LiveSessionMirrorState(
          transport: _RecordingTransport(),
          snapshot: asObject(asObject(replay['snapshot'])['payload']),
          validator: loadProtocolValidator(),
        );

        for (final message in objectsOf(replay['stream'])) {
          await phone.receive(message);
        }

        expect(phone.state, equals(asObject(replay['expected'])));
      });

      test('watch: $path converges on its expected state', () async {
        final clock = TestClock(DateTime.utc(2026, 7, 13, 6));
        var ids = 0;
        final engine = WatchSessionEngine(
          InMemoryWatchSessionStore(),
          validator: loadProtocolValidator(),
          clock: clock.call,
          idFactory: () => 'rec-${++ids}',
          sessionIdFactory: () => 's-replay',
        );
        await engine.restore();

        await engine.applyMessage(asObject(replay['snapshot']));
        for (final message in objectsOf(replay['stream'])) {
          if (message['type'] == 'observations_up') {
            for (final event in objectsOf(
              asObject(message['payload'])['events'],
            )) {
              await engine.appendObservation(event);
            }
          } else {
            await engine.applyMessage(message);
          }
        }

        final expected = asObject(replay['expected']);
        final session = engine.session!;
        expect(session.sessionId, expected['sessionId']);
        expect(session.status, expected['status']);
        expect(session.revision, expected['revision']);
        expect(session.currentExerciseIndex, expected['currentExerciseIndex']);
        expect(session.exercises, equals(expected['exercises']));
        expect([
          for (final entry in engine.entries) entry.payload,
        ], equals(expected['entries']));

        final expectedTimers = asObject(expected['timers']);
        for (final kind in WatchTimerKind.all) {
          final timer = engine.timerFor(kind);
          if (!expectedTimers.containsKey(kind)) {
            expect(
              timer == null || timer.state == WatchTimerState.stopped,
              isTrue,
              reason: '$kind must not be running when the fixture omits it',
            );
            continue;
          }
          expect(timer, isNotNull, reason: '$kind is expected to be running');
          expect(
            _normalizedTimer(timer!.toTimerJson()),
            equals(_normalizedTimer(asObject(expectedTimers[kind]))),
          );
        }
      });
    }
  });
}
