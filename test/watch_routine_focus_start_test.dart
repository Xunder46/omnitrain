// Wrist routine Focus → session modality, Dart half.
//
// Plan: `docs/plans/2026-11-05-125-wrist-routine-focus-modality-plan/`
// (2026-11-05-125b-watch-app-plan.md).
// Scenario mapping:
//   S-12561 the Focus table, one test per row   → `S-12561 ...`
//   S-12568 the phone snapshot leaves the Focus → `S-12568 ...`
//   S-12569 the relaunch keeps the Focus        → `S-12569 ...`
//   S-12570 adversarial focusModality parse     → `S-12570 ...`
//   S-12571 cardio-focus routine of squats      → `S-12571 ...`
//   S-12572 a focus-less routines_down          → `S-12572 ...`
//
// "Phone offline" is simulated as `test/watch_session_start_test.dart` does:
// every test that claims offline behaviour restores a fresh watch over the
// same store, with no transport in sight.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_display.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/sensors/watch_platform_workout.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/start/watch_routine_catalog.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

const String _protocolRoot = 'watch/sync_protocol';

/// Deterministic clock: nothing asserted here reads `DateTime.now()`.
class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

Map<String, Object?> _readJson(String relativePath) => _asObject(
  jsonDecode(
    File('${Directory.current.path}/$relativePath').readAsStringSync(),
  ),
);

/// The values the two watch clients must agree on.
Map<String, Object?> _contract() =>
    _readJson('watch/contract/watch_start_paths_contract.json');

/// The shared schemas, keyed the way `$ref` addresses them.
SyncProtocolValidator _validator() {
  final root = Directory('${Directory.current.path}/$_protocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  });
}

/// A transport that records what it was asked for and never invents a reply:
/// the reply arrives through `receive`, exactly as a real one would.
class _Transport implements WatchSyncTransport {
  @override
  bool isPhoneReachable = false;

  final List<DateTime?> requested = [];

  /// What the watch handed over: observations, timers, and snapshots.
  final List<Map<String, Object?>> sent = [];

  /// How many times the watch asked for a session snapshot.
  int snapshotRequests = 0;

  @override
  Future<void> requestRoutines({DateTime? since}) async {
    requested.add(since);
  }

  @override
  Future<void> requestSnapshot() async {
    snapshotRequests++;
  }

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);
}

/// A watch: one engine, its start paths, and the orchestrator that keeps them
/// fed. Rebuilt over the same store to simulate a relaunch.
class _Watch {
  _Watch._(this.engine, this.paths, this.orchestrator, this.clock);

  factory _Watch(_Harness harness) {
    final engine = harness.newEngine();
    final paths = harness.newPaths(engine);
    return _Watch._(
      engine,
      paths,
      WatchSyncOrchestrator(
        transport: harness.transport,
        paths: paths,
        engine: engine,
      ),
      harness.clock,
    );
  }

  final WatchSessionEngine engine;
  final WatchSessionStartPaths paths;
  final WatchSyncOrchestrator orchestrator;
  final _Clock clock;

  Future<void> restore() async {
    await engine.restore();
    await paths.restore();
  }
}

class _Harness {
  _Harness({WatchSessionStore? store, String Function()? sessionIdFactory})
    : clock = _Clock(DateTime.utc(2031, 3, 8, 9)),
      store = store ?? InMemoryWatchSessionStore(),
      _sessionIdFactory = sessionIdFactory;

  final _Clock clock;
  final WatchSessionStore store;
  final String Function()? _sessionIdFactory;

  final String sessionId = 's-foc-31';
  final List<Map<String, Object?>> emitted = [];
  final _Transport transport = _Transport();
  int _ids = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over.
  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: _validator(),
    clock: clock.call,
    idFactory: () => 'foc-${++_ids}',
    sessionIdFactory: _sessionIdFactory ?? () => sessionId,
  );

  WatchSessionStartPaths newPaths(WatchSessionEngine engine) =>
      WatchSessionStartPaths(
        engine: engine,
        store: store,
        validator: _validator(),
        clock: clock.call,
        idFactory: () => 'frt-${++_ids}',
      );

  /// A launched watch: restored, and holding its own storage.
  Future<_Watch> launch() async {
    final watch = _Watch(this);
    await watch.restore();
    return watch;
  }

  /// What the phone sent, synced and applied the way a launch would: through
  /// the orchestrator, so routing is exercised rather than bypassed.
  Future<void> syncRoutinesDown(
    _Watch watch,
    Map<String, Object?> envelope,
  ) async {
    expect(await watch.orchestrator.receive(envelope), isTrue);
  }

  /// Every message the watch owes the phone, validated against the schemas.
  List<Map<String, Object?>> emittedOf(String type) => [
    for (final envelope in emitted)
      if (envelope['type'] == type) envelope,
  ];
}

final List<Map<String, Object?>> _benchAndPlankEfforts = [
  {
    'effortId': 'eff-bench-foc',
    'exerciseId': 'ex-barbell-bench-press',
    'exerciseName': 'Barbell Bench Press',
    'effortKind': 'set',
    'capabilities': ['sets', 'reps', 'load'],
    'targets': {'sets': 3, 'reps': 5, 'loadKg': 60},
  },
  {
    'effortId': 'eff-plank-foc',
    'exerciseId': 'ex-plank',
    'exerciseName': 'Plank',
    'effortKind': 'timed',
    'capabilities': ['time', 'hold'],
    'targets': {'holdMs': 45000},
  },
];

Map<String, Object?> _effort(
  String id,
  List<String> capabilities,
) => {
  'effortId': id,
  'exerciseId': 'ex-front-squat',
  'exerciseName': 'Front Squat',
  'effortKind': 'set',
  'capabilities': capabilities,
  'targets': {'sets': 3, 'reps': 8},
};

/// One routine, in the shape a `routines_down` carries. [focus] is the
/// `focusModality` value in whatever (malformed) shape the case asks for — it
/// lands in the map raw, which is exactly what makes the parse adversarial;
/// [withFocusKey] names a `routines_down` that never carried the field.
Map<String, Object?> _routine(
  String id,
  String name,
  List<Map<String, Object?>> efforts, {
  Object? focus,
  bool withFocusKey = true,
}) => {
  'routineId': id,
  'name': name,
  'updatedAt': '2031-03-07T20:00:00Z',
  if (withFocusKey) 'focusModality': focus,
  'segments': [
    {'segmentId': 'seg-$id', 'name': 'Main', 'efforts': efforts},
  ],
};

/// The contract's message with the caller's routines, so the frame is the one
/// the validator already accepts apart from the `focusModality` under test. The
/// contract's own fallback list covers every exercise the routines name unless
/// a case brings its own extra fallback row ([fallbackExercises]).
Map<String, Object?> _routinesDown(
  String messageId,
  List<Map<String, Object?>> routines, {
  List<Map<String, Object?>>? fallbackExercises,
}) {
  final sent = _asObject(
    _asObject(_contract()['fallback'])['routinesDown'],
  );
  final payload = _asObject(sent['payload']);

  return {
    ...sent,
    'messageId': messageId,
    'sentAt': '2031-03-08T09:00:00Z',
    'payload': {
      ...payload,
      'generatedAt': '2031-03-08T09:00:00Z',
      'routines': routines,
      'fallbackExercises': ?fallbackExercises,
    },
  };
}

/// A `session_snapshot` from the phone over [sessionId], with no modality key
/// anywhere — the phone's echo of a start it did not dictate (F-5).
Map<String, Object?> _phoneSnapshot(
  String sessionId,
  String messageId,
  List<Map<String, Object?>> exercises,
) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'phone',
  'sentAt': '2031-03-08T09:20:00Z',
  'payload': {
    'sessionId': sessionId,
    'revision': 1,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': exercises,
    'entries': <Map<String, Object?>>[],
    'timers': <String, Object?>{},
  },
};

/// The message types a focus-less start of the same routine shape emits: what
/// S-12561's rows must hold still for a focused start.
Future<List<String>> _focuslessStartFrameTypes() async {
  final harness = _Harness();
  final watch = await harness.launch();
  await harness.syncRoutinesDown(
    watch,
    _routinesDown('msg-foc-baseline', [
      _routine(
        'routine-foc-baseline',
        'Baseline',
        _benchAndPlankEfforts,
        withFocusKey: false,
      ),
    ]),
  );
  await watch.paths.startFromRoutine('routine-foc-baseline');
  return [
    for (final envelope in harness.emitted) envelope['type']! as String,
  ];
}

/// The S-12561 rows: the Focus key and the Health kind, GPS and round word it
/// must read back through.
const List<({String focus, String health, bool gps, String rounds})>
_focusRows = [
  (
    focus: 'isometric_stretching',
    health: 'flexibility',
    gps: false,
    rounds: 'Rounds',
  ),
  (
    focus: 'resistance_lifting',
    health: 'traditionalStrengthTraining',
    gps: false,
    rounds: 'Rounds',
  ),
  (
    focus: 'cardio_endurance',
    health: 'running',
    gps: true,
    rounds: 'Intervals',
  ),
  (focus: 'sports', health: 'other', gps: true, rounds: 'Periods'),
  (
    focus: 'conditioning_mixed',
    health: 'crossTraining',
    gps: false,
    rounds: 'Rounds',
  ),
];

void main() {
  late _Harness harness;
  late _Watch watch;

  setUp(() {
    harness = _Harness();
  });

  group('S-12561 the focus stamps the started session', () {
    for (final (:focus, :health, :gps, :rounds) in _focusRows) {
      final String rowLabel = 'row $focus';
      test('S-12561 $rowLabel starts with the focus and the table holds',
          () async {
      watch = await harness.launch();

      // A focus-less start of the same routine, read before the focused one
      // runs: one watch of its own, asserted below against what the focused
      // start emits.
      final baseline = await _focuslessStartFrameTypes();

      await harness.syncRoutinesDown(
        watch,
        _routinesDown('msg-foc-$focus', [
          _routine(
            'routine-foc-$focus',
            'Focus $focus',
            _benchAndPlankEfforts,
            focus: focus,
          ),
        ]),
      );

      final session = await watch.paths.startFromRoutine(
        'routine-foc-$focus',
      );

      expect(
        harness.emitted.map((envelope) => envelope['type']),
        baseline,
        reason: 'S-12561 $rowLabel: the frames a focus-less start emits',
      );
      expect(session.modality, focus, reason: 'S-12561 $rowLabel');
      expect(
        WatchActivityTypes.forModality(session.modality).watchOs,
        health,
        reason: 'S-12561 $rowLabel: Health kind',
      );
      expect(
        WatchGpsPolicy.isRequired(session.modality),
        gps,
        reason: 'S-12561 $rowLabel: GPS',
      );
      expect(
        ModalityDisplay.getRoundsLabel(session.modality),
        rounds,
        reason: 'S-12561 $rowLabel: round word',
      );
    });
    }
  });

  group('S-12568 the phone snapshot does not undo the focus', () {
    test('S-12568 a phone session_snapshot leaves the focus untouched', () async {
      watch = await harness.launch();
      await harness.syncRoutinesDown(
        watch,
        _routinesDown('msg-foc-snapshot', [
          _routine(
            'routine-foc-snapshot',
            'Focus snapshot',
            _benchAndPlankEfforts,
            focus: 'cardio_endurance',
          ),
        ]),
      );
      final started = await watch.paths.startFromRoutine(
        'routine-foc-snapshot',
      );
      final focused = started.modality;
      expect(focused, 'cardio_endurance');

      final applied = await watch.engine.applyMessage(
        _phoneSnapshot(started.sessionId, 'msg-snap-foc', started.exercises),
      );

      expect(applied, isTrue);
      expect(watch.engine.session!.modality, focused);
    });
  });

  group('S-12569 the relaunch keeps the focus', () {
    test('S-12569 the routine and the start survive a relaunch with the focus',
        () async {
      watch = await harness.launch();
      await harness.syncRoutinesDown(
        watch,
        _routinesDown('msg-foc-relaunch', [
          _routine(
            'routine-foc-relaunch',
            'Focus relaunch',
            _benchAndPlankEfforts,
            focus: 'sports',
          ),
        ]),
      );

      final started = await watch.paths.startFromRoutine(
        'routine-foc-relaunch',
      );
      expect(started.modality, 'sports');

      final relaunched = await harness.launch();
      final routine = relaunched.paths.routines.single;
      expect(routine.focusModality, 'sports');
      expect(_asObject(routine.toJson())['focusModality'], 'sports');
      expect(relaunched.engine.session!.modality, 'sports');
    });
  });

  group('S-12570 an adversarial focus drops no routine, stamps no session', () {
    test('S-12570 malformed focus values parse tolerantly, all across the list',
        () async {
      watch = await harness.launch();
      const adversarial = <Object?>[
        '',
        'Stretching',
        'ISOMETRIC_STRETCHING',
        ' cardio_endurance',
        12,
        null,
        ['sports'],
        <String, Object?>{},
      ];
      final routines = [
        for (var i = 0; i < adversarial.length; i++)
          _routine(
            'routine-adv-$i',
            'Adversarial $i',
            [
              _effort('eff-adv-$i', ['reps', 'sets', 'load']),
            ],
            focus: adversarial[i],
          ),
      ];
      const squatRow = {
        'exerciseId': 'ex-front-squat',
        'name': 'Front Squat',
        'capabilities': ['sets', 'reps', 'load'],
      };

      // The frame is applied the way the wrist would hold its newest catalog:
      // parsed, stored, and read back by a relaunch over the same store.
      await harness.store.append(
        WatchRoutinesDown.fromEnvelope(
          _routinesDown('msg-foc-adv', routines, fallbackExercises: [squatRow]),
        ).toRecord(recordId: 'foc-adv-catalog', recordedAt: harness.clock.now),
      );

      final applied = await harness.launch();

      expect(applied.paths.routines, hasLength(routines.length));
      for (var i = 0; i < adversarial.length; i++) {
        expect(
          applied.paths.routines[i].startModality,
          isNull,
          reason: 'S-12570 case $i (${adversarial[i]})',
        );
        expect(
          applied.paths.routines[i].focusModality,
          adversarial[i] is String && (adversarial[i] as String).isNotEmpty
              ? adversarial[i]
              : isNull,
          reason: 'S-12570 case $i focusModality (${adversarial[i]})',
        );
        final session = await applied.paths.startFromRoutine('routine-adv-$i');
        expect(
          session.modality,
          isNull,
          reason: 'S-12570 case $i session (${adversarial[i]})',
        );
        await applied.engine.abandonSession();
      }
    });
  });

  group('S-12571 a cardio-focus routine of a strength exercise', () {
    test('S-12571 the focus, not the exercises, types the session', () async {
      watch = await harness.launch();
      await harness.syncRoutinesDown(
        watch,
        _routinesDown('msg-foc-squat', [
          _routine(
            'routine-foc-squat',
            'Cardio Squats',
            [_effort('eff-squat-foc', ['reps', 'sets', 'load'])],
            focus: 'cardio_endurance',
          ),
        ], fallbackExercises: const [
          {
            'exerciseId': 'ex-front-squat',
            'name': 'Front Squat',
            'capabilities': ['sets', 'reps', 'load'],
          },
        ]),
      );

      final session = await watch.paths.startFromRoutine('routine-foc-squat');

      expect(session.modality, 'cardio_endurance');
      expect(
        WatchActivityTypes.forModality(session.modality).watchOs,
        'running',
      );
      expect(WatchGpsPolicy.isRequired(session.modality), isTrue);
      expect(ModalityDisplay.getRoundsLabel(session.modality), 'Intervals');
    });
  });

  group('S-12572 a routines_down with no focus anywhere', () {
    test('S-12572 the default path is untouched', () async {
      watch = await harness.launch();
      await harness.syncRoutinesDown(
        watch,
        _routinesDown('msg-foc-none', [
          _routine('routine-foc-none', 'No Focus', _benchAndPlankEfforts,
              withFocusKey: false),
        ]),
      );

      expect(watch.paths.routines.single.focusModality, isNull);

      final session = await watch.paths.startFromRoutine('routine-foc-none');
      expect(session.modality, isNull);
    });
  });
}
