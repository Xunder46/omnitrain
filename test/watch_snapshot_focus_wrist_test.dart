// The Dart wrist reads the snapshot's modality on the FIRST hearing of a
// session only — the Dart half of plan 125d's watch scenarios.
//
// Plan: `docs/plans/2026-11-05-125-wrist-routine-focus-modality-plan/
// 2026-11-05-125d-snapshot-focus-plan.md`, Phase P2.
// Scenario mapping (Dart halves; (b) of S-12597 and the coordinator half of
// S-12593 are Swift-only — there is no coordinator in Dart):
//   S-12592  the five Focus keys stamp themselves on the snapshot that creates
//            the row; every other value and the absent key stamp nothing
//                                                        → `S-12592 ...`
//   S-12593  the stamped key resolves to the Focus table's Health type and
//            GPS flag                                    → `S-12593 ...`
//   S-12594b a snapshot naming another session is refused whole while a Free
//            workout with an exercise is held (D-78)     → `S-12594b ...`
//   S-12595  first hearing only: never override, never null → `S-12595a..e ...`
//   S-12596  the Focus survives a relaunch and a later keyless snapshot
//                                                        → `S-12596 ...`
//   S-12597  an old phone's keyless fixture behaves as before; a validating
//            receiver refuses a malformed key whole      → `S-12597a ...`,
//                                                        `S-12597c ...`
//
// Two engines, exactly as the repo ships them: the harness engine carries the
// protocol validator (the `_Harness` shape of
// `test/watch_session_start_test.dart`), while the shipped watch builds none
// (`ContentView.swift`) — so the malformed-value arms run on a validator-less
// engine, and a validating receiver's refusal is its own test (S-12597c).
// Plain `test()`: no testWidgets, no Hive, no real clock — the snapshots carry
// their own stamps and the engine clock sits before all of them.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/sensors/watch_platform_workout.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

import 'helpers/sync_protocol_harness.dart'
    show TestClock, isoUtc, loadProtocolValidator, readProtocolJson;

/// The Focus table: the five keys the phone can send, each with the Health
/// type and GPS flag the wrist resolves it to — the same values the Swift twin
/// reads out of `WatchActivityTypes.byModality` and `WatchGpsPolicy`
/// (`watch/contract/`, 125b's table).
const Map<String, ({String healthType, bool gps})> _focusTable = {
  'isometric_stretching': (healthType: 'flexibility', gps: false),
  'resistance_lifting': (healthType: 'traditionalStrengthTraining', gps: false),
  'cardio_endurance': (healthType: 'running', gps: true),
  'sports': (healthType: 'other', gps: true),
  'conditioning_mixed': (healthType: 'crossTraining', gps: false),
};

/// The keys `byModality` still names that the phone's own catalog no longer
/// offers: a filter that dropped them would break a replayed old session.
const List<String> _legacyKeys = [
  'strength_resistance',
  'skill_technique',
  'mobility_flexibility',
  'recovery_rehab',
  'competition_match',
];

/// The snapshot stamps, minutes apart, all after the engine clock's 17:00 —
/// the stale-snapshot guard compares instants, so a later snapshot must carry
/// a later stamp.
final DateTime _t0 = DateTime.utc(2026, 7, 13, 17, 5);
final DateTime _t1 = DateTime.utc(2026, 7, 13, 17, 10);

const String _phoneSessionId = 's-phone-125d';
const String _slotId = 'sx-focus-125d';

/// Sentinel: build the payload WITHOUT the `modality` key at all, the way an
/// old phone's converged-state frame arrives.
const Object _absent = Object();

Map<String, Object?> _slot() => {
  'sessionExerciseId': _slotId,
  'exerciseId': 'ex-focus-125d',
  'name': 'Focus Bench 125d',
  'capabilities': ['reps', 'sets', 'load'],
};

Map<String, Object?> _snapshot(
  String messageId, {
  required int revision,
  required DateTime sentAt,
  Object? modality = _absent,
  String sessionId = _phoneSessionId,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'phone',
  'sentAt': isoUtc(sentAt),
  'payload': <String, Object?>{
    'sessionId': sessionId,
    'revision': revision,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [_slot()],
    'entries': const <Object?>[],
    'timers': const <String, Object?>{},
    if (!identical(modality, _absent)) 'modality': modality,
  },
};

class _Transport implements WatchSyncTransport {
  @override
  bool isPhoneReachable = false;

  /// What the watch handed over; a refused snapshot is answered with silence
  /// when the wrist holds nothing.
  final List<Map<String, Object?>> sent = [];

  @override
  Future<void> requestRoutines({DateTime? since}) async {}

  @override
  Future<void> requestSnapshot() async {}

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);
}

/// A watch: one engine and the orchestrator that keeps it fed. Rebuilt over
/// the same store to simulate a relaunch, the way
/// `test/watch_session_start_test.dart`'s harness does.
class _Watch {
  _Watch._(this.engine, this.paths, this.orchestrator);

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
    );
  }

  final WatchSessionEngine engine;
  final WatchSessionStartPaths paths;
  final WatchSyncOrchestrator orchestrator;

  Future<void> restore() async {
    await engine.restore();
    await paths.restore();
  }
}

class _Harness {
  _Harness()
    : clock = TestClock(DateTime.utc(2026, 7, 13, 17)),
      store = InMemoryWatchSessionStore();

  final TestClock clock;
  final InMemoryWatchSessionStore store;
  final String sessionId = 's-watch-1';
  final List<Map<String, Object?>> emitted = [];
  final _Transport transport = _Transport();
  int _ids = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over. It
  /// carries the protocol validator, the way the packaged watch app does.
  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: loadProtocolValidator(),
    clock: clock.call,
    idFactory: () => 'rec-${++_ids}',
    sessionIdFactory: () => sessionId,
  );

  /// The shipped watch's engine: no validator. A malformed `modality` value
  /// reaches the snapshot row unfiltered, which is what the malformed arms of
  /// S-12592 and S-12595d need in order to be seen stamping nothing.
  WatchSessionEngine newPlainEngine() => WatchSessionEngine(
    store,
    clock: clock.call,
    idFactory: () => 'rec-${++_ids}',
    sessionIdFactory: () => sessionId,
  );

  WatchSessionStartPaths newPaths(WatchSessionEngine engine) =>
      WatchSessionStartPaths(
        engine: engine,
        store: store,
        validator: loadProtocolValidator(),
        clock: clock.call,
        idFactory: () => 'cat-${++_ids}',
      );

  /// A launched watch: restored, and holding its own storage.
  Future<_Watch> launch() async {
    final watch = _Watch(this);
    await watch.restore();
    return watch;
  }
}

/// Applies [snapshot] to a fresh wrist of the given kind — through the
/// orchestrator on a validating engine, straight onto the engine when it is
/// validator-less — and answers the modality the wrist holds afterwards.
/// The snapshot must apply (`true`) and nothing may throw.
Future<String?> _stampedModality(
  Map<String, Object?> snapshot, {
  required bool validated,
}) async {
  final harness = _Harness();
  if (validated) {
    final watch = await harness.launch();
    expect(await watch.orchestrator.receive(snapshot), isTrue);
    return watch.engine.session?.modality;
  }
  final engine = harness.newPlainEngine();
  await engine.restore();
  expect(await engine.applyMessage(snapshot), isTrue);
  return engine.session?.modality;
}

void main() {
  group('S-12592 the first hearing stamps only a key the wrist knows', () {
    _focusTable.forEach((key, _) {
      test(
        'S-12592 $key stamps itself on the snapshot that creates the row',
        () async {
          expect(
            await _stampedModality(
              _snapshot('m-92a', revision: 7, sentAt: _t0, modality: key),
              validated: true,
            ),
            key,
            reason: 'the validating engine stamps the key it holds',
          );
          expect(
            await _stampedModality(
              _snapshot('m-92b', revision: 7, sentAt: _t0, modality: key),
              validated: false,
            ),
            key,
            reason: 'the validator-less engine stamps the same key',
          );
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });

    test(
      'S-12592 a well-typed key the wrist does not know stamps nothing',
      () async {
        const unknowns = [
          'Stretching',
          'ISOMETRIC_STRETCHING',
          ' cardio_endurance',
          'no_such_modality',
        ];
        for (final (i, value) in unknowns.indexed) {
          expect(
            await _stampedModality(
              _snapshot('m-92u$i', revision: 7, sentAt: _t0, modality: value),
              validated: true,
            ),
            isNull,
            reason: '"$value" is not a key of byModality (validating engine)',
          );
          expect(
            await _stampedModality(
              _snapshot('m-92v$i', revision: 7, sentAt: _t0, modality: value),
              validated: false,
            ),
            isNull,
            reason:
                '"$value" is not a key of byModality (validator-less engine)',
          );
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('S-12592 a malformed value is refused by the schema, so it is read '
        'only by a validator-less engine — and stamps nothing', () async {
      const malformed = <Object?>[
        '',
        12,
        null,
        ['sports'],
        <String, Object?>{},
      ];
      for (final (i, value) in malformed.indexed) {
        expect(
          await _stampedModality(
            _snapshot('m-92m$i', revision: 7, sentAt: _t0, modality: value),
            validated: false,
          ),
          isNull,
          reason: '`$value` stamps nothing',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
      'S-12592 a snapshot without the key stamps nothing',
      () async {
        expect(
          await _stampedModality(
            _snapshot('m-92k1', revision: 7, sentAt: _t0),
            validated: true,
          ),
          isNull,
        );
        expect(
          await _stampedModality(
            _snapshot('m-92k2', revision: 7, sentAt: _t0),
            validated: false,
          ),
          isNull,
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });

  group('S-12592 WatchActivityTypes.knownModality, the filter itself', () {
    test('S-12592 a key of byModality comes back as itself', () {
      final keys = [..._focusTable.keys, ..._legacyKeys];
      expect(
        [for (final key in keys) WatchActivityTypes.knownModality(key)],
        keys,
        reason: 'the good keys and the legacy keys are all known',
      );
    });

    test('S-12592 everything else is null, never a throw', () {
      const bad = <Object?>[
        '',
        'Stretching',
        'ISOMETRIC_STRETCHING',
        ' cardio_endurance',
        'no_such_modality',
        7,
        null,
        ['sports'],
        <String, Object?>{},
      ];
      expect(
        [for (final value in bad) WatchActivityTypes.knownModality(value)],
        [for (final _ in bad) null],
      );
    });
  });

  group('S-12593 the stamped Focus resolves to the table', () {
    _focusTable.forEach((key, focus) {
      test(
        'S-12593 $key reads as ${focus.healthType} with GPS ${focus.gps}',
        () async {
          final harness = _Harness();
          final watch = await harness.launch();
          expect(
            await watch.orchestrator.receive(
              _snapshot('m-93', revision: 7, sentAt: _t0, modality: key),
            ),
            isTrue,
          );
          final modality = watch.engine.session!.modality;
          expect(modality, key, reason: 'S-12592 stamped it');
          expect(
            WatchActivityTypes.forModality(modality).watchOs,
            focus.healthType,
            reason: 'the Health type the wrist would open the workout as',
          );
          expect(
            WatchGpsPolicy.isRequired(modality),
            focus.gps,
            reason: 'the GPS flag the wrist would decide location by',
          );
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });
  });

  group('S-12594b a held Free workout with an exercise is never replaced', () {
    test('S-12594b a snapshot naming another session is refused whole, its '
        'Focus with it', () async {
      final harness = _Harness();
      final watch = await harness.launch();
      await watch.engine.createSession(
        modality: null,
        exercises: [
          {
            'sessionExerciseId': 'sx-free-125d',
            'exerciseId': 'ex-free-125d',
            'name': 'Free Bench 125d',
            'capabilities': ['reps', 'sets', 'load'],
          },
        ],
      );
      final held = watch.engine.session!;

      final applied = await watch.orchestrator.receive(
        _snapshot(
          'm-94b',
          revision: 7,
          sentAt: _t0,
          modality: 'isometric_stretching',
        ),
      );

      expect(
        applied,
        isFalse,
        reason: 'D-78: the held workout is not replaced',
      );
      expect(watch.engine.session, same(held));
      expect(
        watch.engine.session!.modality,
        isNull,
        reason:
            'the held session keeps its own (null) modality; the '
            'snapshot\'s Focus must not land on it',
      );
      expect(watch.engine.session!.exercises, held.exercises);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('S-12595 first hearing only: never override, never null', () {
    test(
      'S-12595a a held modality survives a snapshot with a different key',
      () async {
        final harness = _Harness();
        final watch = await harness.launch();
        expect(
          await watch.orchestrator.receive(
            _snapshot('m-95a1', revision: 7, sentAt: _t0, modality: 'sports'),
          ),
          isTrue,
        );
        expect(watch.engine.session!.modality, 'sports');

        expect(
          await watch.orchestrator.receive(
            _snapshot(
              'm-95a2',
              revision: 8,
              sentAt: _t1,
              modality: 'isometric_stretching',
            ),
          ),
          isTrue,
        );
        expect(
          watch.engine.session!.modality,
          'sports',
          reason:
              'the first hearing already passed; the later key never '
              'overrides it',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'S-12595b a held nil survives a snapshot that carries a key',
      () async {
        final harness = _Harness();
        final watch = await harness.launch();
        expect(
          await watch.orchestrator.receive(
            _snapshot('m-95b1', revision: 7, sentAt: _t0),
          ),
          isTrue,
        );
        expect(watch.engine.session!.modality, isNull);

        expect(
          await watch.orchestrator.receive(
            _snapshot('m-95b2', revision: 8, sentAt: _t1, modality: 'sports'),
          ),
          isTrue,
        );
        expect(
          watch.engine.session!.modality,
          isNull,
          reason:
              'a held nil stays nil: no mid-workout location prompt or word '
              'flip',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'S-12595c a held modality survives a snapshot that carries no key',
      () async {
        final harness = _Harness();
        final watch = await harness.launch();
        expect(
          await watch.orchestrator.receive(
            _snapshot('m-95c1', revision: 7, sentAt: _t0, modality: 'sports'),
          ),
          isTrue,
        );

        expect(
          await watch.orchestrator.receive(
            _snapshot('m-95c2', revision: 8, sentAt: _t1),
          ),
          isTrue,
          reason: 'a converged-state frame from an older phone still applies',
        );
        expect(
          watch.engine.session!.modality,
          'sports',
          reason: 'the keyless frame must not null the held modality',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('S-12595d a held modality survives malformed values (validator-less '
        'engine)', () async {
      final harness = _Harness();
      final engine = harness.newPlainEngine();
      await engine.restore();
      expect(
        await engine.applyMessage(
          _snapshot('m-95d1', revision: 7, sentAt: _t0, modality: 'sports'),
        ),
        isTrue,
      );
      expect(engine.session!.modality, 'sports');

      const malformed = <Object?>[null, '', 7];
      for (final (i, value) in malformed.indexed) {
        expect(
          await engine.applyMessage(
            _snapshot(
              'm-95d${i + 2}',
              revision: 8 + i,
              sentAt: _t1.add(Duration(minutes: i)),
              modality: value,
            ),
          ),
          isTrue,
        );
        expect(
          engine.session!.modality,
          'sports',
          reason: '`$value` never nulls or overrides the held modality',
        );
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('S-12595e a newer key after first hearing does not stamp a held nil '
        '(the documented limit of first-hearing-only)', () async {
      final harness = _Harness();
      final watch = await harness.launch();
      expect(
        await watch.orchestrator.receive(
          _snapshot('m-95e1', revision: 7, sentAt: _t0),
        ),
        isTrue,
        reason: 'the keyless snapshot creates the row with a nil modality',
      );

      expect(
        await watch.orchestrator.receive(
          _snapshot('m-95e2', revision: 8, sentAt: _t1, modality: 'sports'),
        ),
        isTrue,
      );
      expect(
        watch.engine.session!.modality,
        isNull,
        reason:
            'first hearing already passed: a NEWER snapshot with a key '
            'does not stamp a held nil (D-12591, accepted limit)',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('S-12596 the Focus survives a relaunch', () {
    test('S-12596 a restored row keeps its Focus through a later keyless '
        'snapshot', () async {
      final harness = _Harness();
      var watch = await harness.launch();
      expect(
        await watch.orchestrator.receive(
          _snapshot('m-96a', revision: 7, sentAt: _t0, modality: 'sports'),
        ),
        isTrue,
      );
      expect(watch.engine.session!.modality, 'sports');

      watch = await harness.launch();
      expect(
        watch.engine.session!.modality,
        'sports',
        reason: 'restore() reads the Focus back from storage',
      );

      expect(
        await watch.orchestrator.receive(
          _snapshot('m-96b', revision: 8, sentAt: _t1),
        ),
        isTrue,
      );
      expect(
        watch.engine.session!.modality,
        'sports',
        reason:
            'the keyless snapshot that follows the relaunch does not null '
            'it',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('S-12597 old phone and validating receiver', () {
    test(
      'S-12597a the shipped keyless fixture behaves exactly as before',
      () async {
        final harness = _Harness();
        final watch = await harness.launch();
        final fixture = readProtocolJson(
          'fixtures/valid/session_snapshot.json',
        );

        expect(await watch.orchestrator.receive(fixture), isTrue);
        expect(watch.engine.session!.sessionId, 's-2026-07-13-1');
        expect(
          watch.engine.session!.modality,
          isNull,
          reason:
              'an old phone sends no key: the wrist stamps nothing, Health '
              'comes from the exercises, as before 125d',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'S-12597c a validating receiver refuses a malformed key whole',
      () async {
        final harness = _Harness();
        final watch = await harness.launch();

        await expectLater(
          watch.orchestrator.receive(
            _snapshot('m-97c', revision: 7, sentAt: _t0, modality: 7),
          ),
          throwsA(
            isA<WatchEmissionRejected>()
                .having(
                  (error) => error.decision.rejectionCodes,
                  'rejectionCodes',
                  contains('invalid_type'),
                )
                .having(
                  (error) => [
                    for (final rejection in error.decision.rejections)
                      rejection.path,
                  ],
                  'paths',
                  contains(r'$.payload.modality'),
                ),
          ),
        );

        expect(
          watch.engine.session,
          isNull,
          reason: 'the snapshot was refused whole: nothing was written',
        );
        expect(
          harness.transport.sent,
          isEmpty,
          reason: 'a sessionless wrist answers a refusal with silence',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
