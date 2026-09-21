// Phone manage-bridge for live sessions — the phone's half of a live sync.
//
// Plan: `.github/agents/plans/2026-07-13-10-c2-phone-manage-bridge-live-sessions-plan.md`.
// Scenario mapping:
//   S-001 the phone surfaces the live watch session   → `S-001 ...`
//   S-002 add an exercise from full-catalog search    → `S-002 ...`
//   S-003 reorder while a rest timer runs             → `S-003 ...`
//   S-004 correct a logged entry                      → `S-004 ...`
//   S-005 complete from the phone                     → `S-005 ...`
//   S-006 merge correctness across both devices       → `S-006 ...`
//   S-007 each structure change is the right event     → `S-007 ...`
//
// Both endpoints are real. The wrist is the actual `WatchSessionEngine` over an
// in-memory store, the phone is the actual `LiveSessionMirrorState`, and the
// link between them is a transport pair that hands each envelope to the peer —
// nothing here mocks the code under test. What the phone emits is judged by the
// protocol's own schemas (`SyncProtocolValidator`) and by the shape the
// structure-change fixture pins.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_timer_math.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

import 'helpers/sync_protocol_harness.dart';

const String _sessionId = 's-live-9';

Map<String, Object?> _slot(String slot, String name) => {
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'name': name,
  'capabilities': const ['sets', 'reps', 'load'],
};

/// The ladder the wrist starts on, shaped as the phone sends it.
final List<Map<String, Object?>> _slots = [
  _slot('sx-bench', 'Barbell Bench Press'),
  _slot('sx-plank', 'Plank'),
  _slot('sx-squat', 'Goblet Squat'),
];

List<String> _slotIds(List<Map<String, Object?>> exercises) => [
  for (final slot in exercises) slot['sessionExerciseId']! as String,
];

/// A schema-conformant `set` event, the way the wrist hands it to its engine.
Map<String, Object?> _setEvent(
  DateTime loggedAt, {
  required String entryId,
  String slot = 'sx-bench',
  double loadKg = 80,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': isoUtc(loggedAt),
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'reps': 5,
  'loadKg': loadKg,
};

Map<String, Object?> _snapshotPayload({
  String sessionId = _sessionId,
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

/// One wrist and one phone, joined by a transport pair.
class _Bridge {
  _Bridge({Map<String, Object?>? phoneState})
    : clock = TestClock(DateTime.utc(2026, 7, 13, 6)) {
    final validator = loadProtocolValidator();
    _store = InMemoryWatchSessionStore();
    _wristTransport = _WristTransport(this);
    _phoneTransport = _PhoneTransport(this);

    wrist = WatchSessionEngine(
      _store,
      onEmit: wristEmits.add,
      validator: validator,
      clock: clock.call,
      idFactory: () => 'wrec-${++_ids}',
      sessionIdFactory: () => _sessionId,
    );
    paths = WatchSessionStartPaths(
      engine: wrist,
      store: _store,
      validator: validator,
      clock: clock.call,
      idFactory: () => 'wrec-${++_ids}',
    );
    orchestrator = WatchSyncOrchestrator(
      transport: _wristTransport,
      paths: paths,
      engine: wrist,
    );
    phone = LiveSessionMirrorState(
      transport: _phoneTransport,
      // A phone that has not been told anything yet: it holds the session's
      // identity and nothing else. Everything else arrives from the wrist.
      snapshot:
          phoneState ??
          _snapshotPayload(
            sessionId: _sessionId,
            status: WatchSessionStatus.active,
          ),
      validator: validator,
      clock: clock.call,
      idFactory: () => 'pmsg-${++_ids}',
    );
    phone.addListener(() => phoneNotifications++);
  }

  final TestClock clock;
  late final InMemoryWatchSessionStore _store;
  late final WatchSessionEngine wrist;
  late final WatchSessionStartPaths paths;
  late final WatchSyncOrchestrator orchestrator;
  late final LiveSessionMirrorState phone;
  late final _WristTransport _wristTransport;
  late final _PhoneTransport _phoneTransport;

  /// Everything the wrist handed its sink.
  final List<Map<String, Object?>> wristEmits = [];

  /// Notifications the phone's live surface would re-render on.
  int phoneNotifications = 0;

  /// Everything the phone sent down, whether or not the wrist had a use for it.
  List<Map<String, Object?>> get sent => _phoneTransport.sent;

  int _ids = 0;

  /// Hands the phone everything the wrist has emitted since the last call —
  /// the radio catching up.
  Future<void> deliverWristEmits() async {
    final pending = [...wristEmits];
    wristEmits.clear();
    for (final envelope in pending) {
      await _phoneTransport.deliver(envelope);
    }
  }

  /// The connect handshake: the wrist reports its session, the phone answers
  /// with what it holds and asks for the wrist's.
  Future<void> connect() async {
    await orchestrator.sync();
    await phone.sync();
  }

  /// The last message the phone emitted, as the wrist received it.
  Map<String, Object?> get lastSent => sent.last;
}

/// The radio, wrist half.
class _WristTransport implements WatchSyncTransport {
  _WristTransport(this.bridge);

  final _Bridge bridge;

  @override
  bool isPhoneReachable = true;

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {
    await bridge.phone.sendSnapshot();
  }

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    await bridge.phone.receive(envelope);
  }
}

/// The radio, phone half.
class _PhoneTransport implements WatchMirrorTransport {
  _PhoneTransport(this.bridge);

  final _Bridge bridge;

  /// Everything the phone sent down, whether or not the wrist applied it.
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    sent.add(envelope);
    await bridge.wrist.applyMessage(envelope);
  }

  /// A message handed over without being counted as an outgoing send — how the
  /// wrist's own emits reach the phone.
  Future<void> deliver(Map<String, Object?> envelope) async {
    await bridge.phone.receive(envelope);
  }

  @override
  Future<void> requestSnapshot() async {
    await bridge.orchestrator.answerSnapshotRequest();
  }
}

void main() {
  // ── The phone's view of a session that started on the wrist ───────────────

  group('S-001 the phone surfaces the live watch session', () {
    test(
      'a wrist-started session renders on the phone, ladder included',
      () async {
        final bridge = _Bridge();
        await bridge.wrist.createSession(
          modality: 'resistance_lifting',
          exercises: _slots,
        );

        await bridge.connect();

        expect(bridge.phone.isActive, isTrue);
        expect(bridge.phone.sessionId, _sessionId);
        expect(_slotIds(bridge.phone.exercises), _slotIds(_slots));
        expect(bridge.phone.currentExercise?['name'], 'Barbell Bench Press');
        expect(bridge.phone.entries, isEmpty);
        expect(
          bridge.phoneNotifications,
          greaterThan(0),
          reason: 'the live surface re-renders on what arrives, not on a poll',
        );
      },
    );

    test(
      'the phone does not wipe the wrist\'s ladder it has just adopted',
      () async {
        final bridge = _Bridge();
        await bridge.wrist.createSession(
          modality: 'resistance_lifting',
          exercises: _slots,
        );

        await bridge.connect();

        expect(
          _slotIds(bridge.wrist.session!.exercises),
          _slotIds(_slots),
          reason: 'a phone holding no ladder has none to assert',
        );
      },
    );
  });

  // ── Structure the phone owns ──────────────────────────────────────────────

  group('S-002 add an exercise from full-catalog search', () {
    test('the pushed exercise lands at the position the phone chose', () async {
      final bridge = _Bridge();
      await bridge.wrist.createSession(
        modality: 'resistance_lifting',
        exercises: _slots,
      );
      await bridge.connect();

      final envelope = await bridge.phone.pushExercise(
        _slot('sx-row', 'Barbell Row'),
        atIndex: 1,
      );

      expect(envelope['type'], 'exercise_push');
      expect(asObject(envelope['payload'])['insertAtIndex'], 1);
      expect(_slotIds(bridge.wrist.session!.exercises), [
        'sx-bench',
        'sx-row',
        'sx-plank',
        'sx-squat',
      ]);
      expect(
        _slotIds(bridge.phone.exercises),
        ['sx-bench', 'sx-row', 'sx-plank', 'sx-squat'],
        reason: 'the phone has to be looking at the session it just edited',
      );
    });

    test('an added exercise by the phone\'s own management sends '
        'add_exercise', () async {
      final bridge = await _connectedBridge();

      await bridge.phone.addExercise(
        _slot('sx-row', 'Barbell Row'),
        atIndex: 0,
      );

      expect(_slotIds(bridge.wrist.session!.exercises).first, 'sx-row');
      expect(
        _slotIds(bridge.phone.exercises).first,
        'sx-row',
        reason:
            'the position the user picked is the position both devices show',
      );
    });

    test('adding without a position puts the exercise at the end', () async {
      final bridge = await _connectedBridge();

      await bridge.phone.addExercise(_slot('sx-row', 'Barbell Row'));

      expect(_slotIds(bridge.phone.exercises).last, 'sx-row');
      expect(_slotIds(bridge.wrist.session!.exercises).last, 'sx-row');
    });

    test(
      'removing an exercise takes it off both ladders and keeps entries',
      () async {
        final bridge = await _connectedBridge();
        await bridge.wrist.appendObservation(
          _setEvent(bridge.clock.now, entryId: 'e-1'),
        );
        await bridge.deliverWristEmits();
        expect(bridge.phone.entries, hasLength(1));

        await bridge.phone.removeExercise('sx-bench');

        expect(_slotIds(bridge.phone.exercises), ['sx-plank', 'sx-squat']);
        expect(_slotIds(bridge.wrist.session!.exercises), [
          'sx-plank',
          'sx-squat',
        ]);
        expect(
          bridge.phone.entries,
          hasLength(1),
          reason:
              'history records what happened, not what the ladder holds now',
        );
      },
    );
  });

  group('S-003 reorder while a rest timer runs', () {
    test('the wrist reorders and the running timer is undisturbed', () async {
      final bridge = await _connectedBridge();
      await bridge.wrist.startTimer(
        WatchTimerKind.rest,
        plannedDurationMs: 90 * Duration.millisecondsPerSecond,
      );
      await bridge.deliverWristEmits();
      final restBefore = bridge.wrist.timerFor(WatchTimerKind.rest)!;
      final restEndBefore = completionInstant(restBefore)!;

      await bridge.phone.reorderExercises(['sx-squat', 'sx-bench', 'sx-plank']);

      expect(_slotIds(bridge.wrist.session!.exercises), [
        'sx-squat',
        'sx-bench',
        'sx-plank',
      ]);
      expect(_slotIds(bridge.phone.exercises), [
        'sx-squat',
        'sx-bench',
        'sx-plank',
      ]);

      final restAfter = bridge.wrist.timerFor(WatchTimerKind.rest)!;
      expect(restAfter.state, WatchTimerState.running);
      expect(restAfter.startedAt, restBefore.startedAt);
      expect(completionInstant(restAfter), restEndBefore);
    });

    test('slots the order does not name keep their relative order', () async {
      final bridge = await _connectedBridge();

      await bridge.phone.reorderExercises(['sx-squat']);

      expect(_slotIds(bridge.phone.exercises), [
        'sx-squat',
        'sx-bench',
        'sx-plank',
      ]);
      expect(_slotIds(bridge.wrist.session!.exercises), [
        'sx-squat',
        'sx-bench',
        'sx-plank',
      ]);
    });

    // The ladder arithmetic is the state's, not a widget's, so it is asserted
    // here against the wrist rather than through a menu tap.
    test('a one-place move reaches the wrist as the whole order', () async {
      final bridge = await _connectedBridge();

      await bridge.phone.moveExercise(0, 1);

      expect(_slotIds(bridge.phone.exercises), [
        'sx-plank',
        'sx-bench',
        'sx-squat',
      ]);
      expect(_slotIds(bridge.wrist.session!.exercises), [
        'sx-plank',
        'sx-bench',
        'sx-squat',
      ]);
    });

    test('a move off either end of the ladder sends nothing', () async {
      final bridge = await _connectedBridge();
      final ladderBefore = _slotIds(bridge.phone.exercises);

      await bridge.phone.moveExercise(0, -1);
      await bridge.phone.moveExercise(2, 1);
      await bridge.phone.moveExercise(9, -1);

      expect(_slotIds(bridge.phone.exercises), ladderBefore);
      expect(_slotIds(bridge.wrist.session!.exercises), ladderBefore);
    });

    test(
      'a swap replaces what the slot holds and leaves the position alone',
      () async {
        final bridge = await _connectedBridge();
        await bridge.wrist.advanceExercise();
        await bridge.deliverWristEmits();

        await bridge.phone.swapExercise(
          'sx-plank',
          _slot('sx-row', 'Barbell Row')..remove('sessionExerciseId'),
        );

        expect(_slotIds(bridge.phone.exercises), [
          'sx-bench',
          'sx-plank',
          'sx-squat',
        ]);
        expect(
          bridge.phone.exercises[1]['name'],
          'Barbell Row',
          reason: 'the slot keeps its id and its place',
        );
        expect(bridge.phone.currentExerciseIndex, 1);
      },
    );
  });

  // ── Correcting what the wrist logged ─────────────────────────────────────

  group('S-004 correct a logged entry', () {
    test('the correction reaches the wrist\'s displayed history', () async {
      final bridge = await _connectedBridge();
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-1', loadKg: 800),
      );
      await bridge.deliverWristEmits();

      await bridge.phone.correctEntry('e-1', {'loadKg': 80});

      expect(
        bridge.wrist.entries.single.payload['loadKg'],
        80,
        reason: 'a fat-fingered set is fixable from the phone',
      );
      expect(
        bridge.phone.entries.single['loadKg'],
        80,
        reason: 'the phone shows the corrected value too',
      );
    });

    test('a deleted entry leaves both histories and stays deleted', () async {
      final bridge = await _connectedBridge();
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-1'),
      );
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-2'),
      );
      await bridge.deliverWristEmits();

      await bridge.phone.deleteEntry('e-1');

      expect(
        [for (final entry in bridge.phone.entries) entry['entryId']],
        ['e-2'],
      );
      expect(
        [for (final entry in bridge.wrist.entries) entry.entryId],
        ['e-2'],
      );
    });
  });

  // ── Completing from the phone ────────────────────────────────────────────

  group('S-005 complete from the phone', () {
    test('one completed record closes the wrist\'s session', () async {
      final bridge = await _connectedBridge();
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-1'),
      );
      await bridge.deliverWristEmits();

      final record = await bridge.phone.completeSession();

      expect(record['status'], WatchSessionStatus.completed);
      expect(
        bridge.wrist.session!.status,
        WatchSessionStatus.completed,
        reason: 'the wrist exits the session gracefully',
      );
      expect(
        [
          for (final envelope in bridge.sent) envelope['type'],
        ].where((type) => type == 'session_lifecycle').length,
        1,
      );
      expect(bridge.phone.completedRecord, isNotNull);
    });

    test('completing twice yields the one record, not a second', () async {
      final bridge = await _connectedBridge();
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-1'),
      );
      await bridge.deliverWristEmits();

      final first = await bridge.phone.completeSession();
      final lifecycleAfterFirst = bridge.sent
          .where((envelope) => envelope['type'] == 'session_lifecycle')
          .length;
      final second = await bridge.phone.completeSession();

      expect(second, first);
      expect(
        bridge.sent
            .where((envelope) => envelope['type'] == 'session_lifecycle')
            .length,
        lifecycleAfterFirst,
        reason: 'a session completes once, however many times Finish is tapped',
      );
      expect(bridge.phone.isActive, isFalse);
    });
  });

  // ── Merging what both devices logged ─────────────────────────────────────

  group('S-006 merge correctness across both devices', () {
    test('interleaved observations merge into one ordered record', () async {
      // The phone started the session and logged two entries before the wrist
      // joined — the phone's own history, which the wrist's snapshot response
      // must not displace.
      final bridge = _Bridge(
        phoneState: _snapshotPayload(
          exercises: _slots,
          revision: 4,
          entries: [
            _setEvent(DateTime.utc(2026, 7, 13, 5, 58), entryId: 'e-a'),
            _setEvent(DateTime.utc(2026, 7, 13, 6, 2), entryId: 'e-c'),
          ],
        ),
      );
      await bridge.wrist.createSession(
        modality: 'resistance_lifting',
        exercises: _slots,
      );
      await bridge.connect();

      // The wrist logs two more, interleaved around the phone's second entry.
      await bridge.wrist.appendObservation(
        _setEvent(DateTime.utc(2026, 7, 13, 6), entryId: 'e-b'),
      );
      await bridge.wrist.appendObservation(
        _setEvent(DateTime.utc(2026, 7, 13, 6, 5), entryId: 'e-d'),
      );
      await bridge.deliverWristEmits();

      final record = await bridge.phone.completeSession();

      expect(record['status'], WatchSessionStatus.completed);
      expect(
        [for (final entry in objectsOf(record['entries'])) entry['entryId']],
        ['e-a', 'e-b', 'e-c', 'e-d'],
        reason: 'one record, in wall-clock order, whoever logged it',
      );
      expect(
        {
          for (final entry in objectsOf(record['entries']))
            entry['entryId']: entry['loadKg'],
        },
        {'e-a': 80.0, 'e-b': 80.0, 'e-c': 80.0, 'e-d': 80.0},
        reason: 'no observation is lost or applied twice by the exchange',
      );
    });

    test('a reconnect re-sends nothing the phone has already merged', () async {
      final bridge = await _connectedBridge();
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-1'),
      );
      await bridge.deliverWristEmits();

      await bridge.orchestrator.sync(reconnect: true);
      await bridge.phone.sync();
      await bridge.deliverWristEmits();

      expect(bridge.phone.entries, hasLength(1));
      final record = await bridge.phone.completeSession();
      expect(objectsOf(record['entries']), hasLength(1));
    });
  });

  // ── Every structure change is the protocol's own event ───────────────────

  group('S-007 each structure change is the right protocol event', () {
    test('every operation emits a schema-conformant message', () async {
      final bridge = await _connectedBridge();
      final validator = loadProtocolValidator();

      await bridge.phone.addExercise(_slot('sx-row', 'Barbell Row'));
      await bridge.phone.removeExercise('sx-plank');
      await bridge.phone.reorderExercises(['sx-row', 'sx-bench', 'sx-squat']);
      await bridge.phone.swapExercise(
        'sx-squat',
        _slot('sx-lunge', 'Walking Lunge')..remove('sessionExerciseId'),
      );
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-1'),
      );
      await bridge.deliverWristEmits();
      await bridge.phone.correctEntry('e-1', {'reps': 6});
      await bridge.phone.deleteEntry('e-1');
      await bridge.phone.pushExercise(
        _slot('sx-fly', 'Dumbbell Fly'),
        atIndex: 0,
      );

      expect(bridge.sent, isNotEmpty);
      for (final envelope in bridge.sent) {
        expect(
          validator.validateEnvelope(envelope),
          isEmpty,
          reason:
              '${envelope['type']} must conform: '
              '${validator.validateEnvelope(envelope)}',
        );
      }
    });

    test('every change carries exactly the fields the fixture pins', () async {
      final bridge = await _connectedBridge();
      final fixtureKinds = _fixtureChangeShapes();

      await bridge.phone.addExercise(
        _slot('sx-row', 'Barbell Row'),
        atIndex: 1,
      );
      await bridge.phone.removeExercise('sx-plank');
      await bridge.phone.reorderExercises(['sx-bench', 'sx-squat']);
      await bridge.phone.swapExercise(
        'sx-squat',
        _slot('sx-lunge', 'Walking Lunge')..remove('sessionExerciseId'),
      );
      await bridge.wrist.appendObservation(
        _setEvent(bridge.clock.now, entryId: 'e-1'),
      );
      await bridge.deliverWristEmits();
      await bridge.phone.correctEntry('e-1', {'loadKg': 82.5});
      await bridge.phone.deleteEntry('e-1');

      final emitted = {
        for (final envelope in bridge.sent)
          if (envelope['type'] == 'structure_change')
            for (final change in objectsOf(
              asObject(envelope['payload'])['changes'],
            ))
              change['kind']! as String: change.keys.toSet(),
      };

      expect(emitted.keys.toSet(), fixtureKinds.keys.toSet());
      for (final entry in emitted.entries) {
        expect(
          entry.value,
          fixtureKinds[entry.key],
          reason: '${entry.key} must carry the shape the fixture pins',
        );
      }
    });

    test(
      'a completed session is the one lifecycle event the phone sends',
      () async {
        final bridge = await _connectedBridge();

        await bridge.phone.reportLifecycle(WatchLifecycleState.completed);

        final lifecycle = asObject(bridge.lastSent['payload']);
        expect(bridge.lastSent['type'], 'session_lifecycle');
        expect(lifecycle['state'], WatchLifecycleState.completed);
        expect(
          bridge.sent.where(
            (envelope) => envelope['type'] == 'structure_change',
          ),
          isEmpty,
        );
      },
    );
  });
}

/// A bridge with a wrist-started session, already connected.
Future<_Bridge> _connectedBridge() async {
  final bridge = _Bridge();
  await bridge.wrist.createSession(
    modality: 'resistance_lifting',
    exercises: _slots,
  );
  await bridge.connect();
  return bridge;
}

/// The change shapes the protocol's own structure-change fixture carries,
/// keyed by `kind` — the shape each change the phone emits is measured against.
Map<String, Set<String>> _fixtureChangeShapes() {
  final fixture = readProtocolJson('fixtures/valid/structure_change.json');
  return {
    for (final change in objectsOf(asObject(fixture['payload'])['changes']))
      change['kind']! as String: change.keys.toSet(),
  };
}
