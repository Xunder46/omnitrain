// Watch session start paths — routines, free workouts, and pushes from the phone.
//
// Plan: `docs/plans/2026-07-13-08-b-watch-session-start-paths-plan.md`.
// Scenario mapping:
//   S-001 start from a routine, phone offline   → `S-001 ...`
//   S-002 free workout, phone offline           → `S-002 ...`
//   S-003 fallback list derivation              → `S-003 ...`
//   S-004 routine edit propagates               → `S-004 ...`
//   S-005 phone push adds an exercise           → `S-005 ...`
//   S-006 session-started lifecycle event       → `S-006 ...`
//   S-007 modality / effort-kind parity         → `S-007 ...`
//
// Two sources are read from the repository rather than restated here: the
// protocol schemas (so "conformant" is the schema's verdict, not this file's
// opinion) and `watch/contract/watch_start_paths_contract.json`, the values the
// native watchOS suite is held to as well. A rule that changes on one platform
// therefore fails the other's tests.
//
// "Phone offline" is simulated by never giving a watch anything but its own
// storage: every test that claims offline behaviour restores a fresh watch over
// the same store, with no transport in sight.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_config.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/start/watch_fallback_list.dart';
import 'package:omnitrain/watch/start/watch_routine_catalog.dart';
import 'package:omnitrain/watch/start/watch_start_screen.dart';
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

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

List<String> _strings(Object? value) =>
    (value! as List).cast<String>().toList(growable: false);

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

  /// The value screen the wrist would show for the exercise the session is on.
  WatchLoggingState get surface =>
      WatchLoggingState(engine: engine, clock: clock.call);
}

/// The effort kind the logging surface resolves for [capabilities], asked of a
/// watch of its own so a slot can be probed without moving the session under
/// test off the exercise the user is on.
Future<String> effortKindFor(
  List<String> capabilities,
  DateTime Function() clock,
) async {
  final engine = WatchSessionEngine(InMemoryWatchSessionStore(), clock: clock);
  await engine.createSession(
    modality: null,
    exercises: [
      {
        'sessionExerciseId': 'sx-probe',
        'exerciseId': 'ex-probe',
        'name': 'Probe',
        'capabilities': capabilities,
      },
    ],
  );
  return WatchLoggingState(engine: engine, clock: clock).effortKind;
}

class _Harness {
  _Harness({WatchSessionStore? store})
    : clock = _Clock(DateTime.utc(2026, 7, 13, 17)),
      store = store ?? InMemoryWatchSessionStore();

  final _Clock clock;
  final WatchSessionStore store;

  /// The session every engine in this harness starts, so a relaunch continues
  /// the same workout rather than inventing a new one.
  final String sessionId = 's-watch-1';
  final List<Map<String, Object?>> emitted = [];
  final _Transport transport = _Transport();
  int _ids = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over.
  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: _validator(),
    clock: clock.call,
    idFactory: () => 'rec-${++_ids}',
    sessionIdFactory: () => sessionId,
  );

  WatchSessionStartPaths newPaths(WatchSessionEngine engine) =>
      WatchSessionStartPaths(
        engine: engine,
        store: store,
        validator: _validator(),
        clock: clock.call,
        idFactory: () => 'cat-${++_ids}',
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

/// The effort kind the phone's own rule gives for [capabilities]: the
/// precedence pinned in `watch/contract/watch_logging_contract.json`, resolved
/// through the phone's canonical `ModalityConfig` — the same owner the watch's
/// logging surface reads.
String _phoneEffortKind(List<String> capabilities) {
  const precedence = [
    'hold',
    'rounds',
    'reps',
    'sets',
    'load',
    'time',
    'distance',
  ];
  return ModalityConfig.effortKindFromMetric(
    precedence.firstWhere(capabilities.contains, orElse: () => 'reps'),
  );
}

/// The contract's message plus a second routine, so the routine list is
/// exercised with more than one entry. The added routine reuses an exercise the
/// contract's fallback list already covers, which is what keeps the message
/// conformant — the protocol rejects a `routines_down` that names an exercise
/// the watch could not log with the phone off.
Map<String, Object?> _twoRoutineMessage(WatchRoutineEffort effort) {
  final sent = _asObject(_asObject(_contract()['fallback'])['routinesDown']);
  final payload = _asObject(sent['payload']);

  return {
    ...sent,
    'messageId': 'msg-routines-second',
    'sentAt': '2026-07-13T18:30:00Z',
    'payload': {
      ...payload,
      'generatedAt': '2026-07-13T18:30:00Z',
      'routines': [
        ..._objects(payload['routines']),
        {
          'routineId': 'routine-pull-day',
          'name': 'Pull Day',
          'updatedAt': '2026-07-13T18:30:00Z',
          'segments': [
            {
              'segmentId': 'seg-pull',
              'name': 'Pull',
              'efforts': [effort.toJson()],
            },
          ],
        },
      ],
    },
  };
}

/// A push at [index], carrying the contract's own slot so the only thing that
/// varies between cases is the position.
Map<String, Object?> _pushAt(int index) {
  final envelope = _asObject(
    _asObject(_contract()['exercisePush'])['envelope'],
  );
  return {
    ...envelope,
    'messageId': 'msg-push-at-$index',
    'payload': {..._asObject(envelope['payload']), 'insertAtIndex': index},
  };
}

void main() {
  late _Harness harness;
  late _Watch watch;

  setUp(() {
    harness = _Harness();
  });

  /// The phone's first message, applied and cached.
  Future<void> syncFirstMessage() async {
    final fallback = _asObject(_contract()['fallback']);
    await harness.syncRoutinesDown(watch, _asObject(fallback['routinesDown']));
  }

  group('S-003 fallback list derivation', () {
    test(
      'unions recents and routine exercises, deduplicated, in the contract order',
      () {
        final fallback = _asObject(_contract()['fallback']);
        final sent = WatchRoutinesDown.fromEnvelope(
          _asObject(fallback['routinesDown']),
        );

        final derived = deriveFallbackExercises(
          recents: _objects(
            fallback['recents'],
          ).map((json) => WatchCatalogExercise.fromJson(json)).toList(),
          syncedFallback: sent.fallbackExercises,
          routines: sent.routines,
        );

        expect(
          derived.map((exercise) => exercise.exerciseId),
          _strings(fallback['expected']),
          reason: 'recents first, then the synced list, then routine order',
        );
        expect(
          derived.map((exercise) => exercise.exerciseId).toSet(),
          hasLength(derived.length),
          reason: 'an exercise appears once, however many sources name it',
        );
      },
    );

    test('routine-referenced exercises keep routine order', () {
      final fallback = _asObject(_contract()['fallback']);
      final sent = WatchRoutinesDown.fromEnvelope(
        _asObject(fallback['routinesDown']),
      );

      expect(
        sent.routines
            .expand((routine) => routine.referencedExercises)
            .map((exercise) => exercise.exerciseId),
        _strings(fallback['routineOrder']),
        reason: 'segments in order, efforts in order, duplicates dropped',
      );
    });

    test(
      'the stored list covers every exercise a synced routine names',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();

        final referenced = watch.paths.routines
            .expand((routine) => routine.referencedExercises)
            .map((exercise) => exercise.exerciseId);

        final offered = watch.paths.fallbackExercises
            .map((exercise) => exercise.exerciseId)
            .toSet();
        expect(offered, containsAll(referenced));
      },
    );
  });

  group('S-001 start from a routine, phone offline', () {
    test(
      'creates the routine\'s structure and loads the first exercise',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        final expected = _objects(
          _asObject(_contract()['routineSession'])['expectedSlots'],
        );

        final session = await watch.paths.startFromRoutine('routine-push-a');

        expect(session.status, WatchSessionStatus.active);
        expect(session.currentExerciseIndex, 0);
        expect(session.exercises, expected);
        expect(watch.engine.currentExercise, expected.first);

        // The first exercise reaches the logging surface as its own effort kind,
        // off the capabilities the routine carried — not a guess from the name.
        expect(watch.surface.effortKind, WatchEffortKind.set);
        expect(watch.surface.exerciseName, 'Barbell Bench Press');
        expect(watch.surface.fields, isNotEmpty);
      },
    );

    test(
      'a relaunch with no phone still lists the routines and starts one',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();

        // Gone: engine, start paths, in-memory state. Left: the store.
        final relaunched = await harness.launch();

        expect(relaunched.paths.routines.map((routine) => routine.name), [
          'Push A',
        ]);
        final session = await relaunched.paths.startFromRoutine(
          'routine-push-a',
        );
        expect(session.exercises, hasLength(3));
        expect(relaunched.paths.phoneReachable, isFalse);
      },
    );

    test('lists every synced routine, and starts any one of them', () async {
      watch = await harness.launch();
      await syncFirstMessage();

      // A second routine, composed from what the contract already pins so the
      // message stays conformant: its exercise is in the fallback list.
      final sent = WatchRoutinesDown.fromEnvelope(
        _asObject(_asObject(_contract()['fallback'])['routinesDown']),
      );
      final pullUp = sent.routines.single.efforts.lastWhere(
        (effort) => effort.exerciseId == 'ex-pull-up',
      );
      final twoRoutines = _twoRoutineMessage(pullUp);

      await harness.syncRoutinesDown(watch, twoRoutines);

      expect(watch.paths.routines.map((routine) => routine.name), [
        'Push A',
        'Pull Day',
      ]);

      final session = await watch.paths.startFromRoutine('routine-pull-day');
      expect(session.exercises, hasLength(1));
      expect(session.exercises.single['exerciseId'], 'ex-pull-up');
      expect(watch.surface.exerciseName, 'Pull-Up');
    });

    test(
      'the started session survives a kill, with its structure and start instant',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        final started = await watch.paths.startFromRoutine('routine-push-a');

        harness.clock.advance(const Duration(minutes: 12));
        final relaunched = await harness.launch();

        expect(relaunched.engine.session, isNotNull);
        expect(relaunched.engine.session!.sessionId, started.sessionId);
        expect(relaunched.engine.session!.startedAt, started.startedAt);
        expect(relaunched.engine.session!.exercises, started.exercises);
      },
    );
  });

  group('S-002 free workout, phone offline', () {
    test(
      'starts empty and adds a fallback-list exercise with its own surface',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        final fallback = _asObject(_contract()['fallback']);
        final bench = watch.paths.fallbackExercises.firstWhere(
          (exercise) => exercise.exerciseId == 'ex-barbell-bench-press',
        );

        final started = await watch.paths.startFreeWorkout();
        expect(started.exercises, isEmpty);
        expect(started.modality, isNull);

        final session = await watch.paths.addExerciseToSession(bench);

        expect(session.exercises, hasLength(1));
        expect(
          session.exercises.first['sessionExerciseId'],
          fallback['expectedPickerSlotId'],
        );
        expect(session.exercises.first['exerciseId'], bench.exerciseId);
        expect(watch.surface.effortKind, WatchEffortKind.set);
        expect(watch.surface.exerciseName, 'Barbell Bench Press');

        await watch.surface.log();

        final events = harness
            .emittedOf('observations_up')
            .expand(
              (envelope) => _objects(_asObject(envelope['payload'])['events']),
            );
        expect(events, hasLength(1));
        expect(events.first['exerciseId'], 'ex-barbell-bench-press');
        expect(
          _validator().validateEnvelope(
            harness.emittedOf('observations_up').single,
          ),
          isEmpty,
        );

        // Persisted, not just emitted: the register's outcome is that the entry
        // survives whatever happens to the app next.
        expect(
          (await harness.store.readAll()).observations.map(
            (observation) => observation.entryId,
          ),
          [events.first['entryId']],
        );
      },
    );

    test(
      'the exercise added mid-session becomes the one being logged',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        final plank = watch.paths.fallbackExercises.firstWhere(
          (exercise) => exercise.exerciseId == 'ex-plank',
        );

        await watch.paths.startFreeWorkout();
        final session = await watch.paths.addExerciseToSession(plank);

        expect(session.currentExerciseIndex, 0);
        expect(watch.surface.exerciseName, 'Plank');
        expect(watch.surface.effortKind, WatchEffortKind.drill);
      },
    );

    test(
      'a free workout started offline is still there after a relaunch',
      () async {
        watch = await harness.launch();
        final started = await watch.paths.startFreeWorkout();

        final relaunched = await harness.launch();

        expect(relaunched.engine.session!.sessionId, started.sessionId);
        expect(relaunched.engine.session!.exercises, isEmpty);
      },
    );
  });

  group('S-006 session-started lifecycle event', () {
    test(
      'starting from a routine emits one conformant session-started event',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        final expected = _asObject(_contract()['sessionStarted']);

        final session = await watch.paths.startFromRoutine('routine-push-a');

        final lifecycle = harness.emittedOf('session_lifecycle');
        expect(lifecycle, hasLength(1));
        final envelope = lifecycle.single;
        expect(_validator().validateEnvelope(envelope), isEmpty);
        expect(envelope['origin'], expected['origin']);
        expect(envelope['sessionId'], session.sessionId);
        expect(_asObject(envelope['payload']), {
          'state': expected['state'],
          'at': utcIso(session.startedAt),
        });

        // The protocol's own fixture, not just the schemas: the family's shape and
        // the origin the register names are the fixture's, so a change to either
        // side shows up here.
        final fixture = _readJson(
          '$_protocolRoot/fixtures/valid/session_lifecycle.json',
        );
        expect(envelope['type'], fixture['type']);
        expect(envelope['origin'], fixture['origin']);
        expect(
          _asObject(fixture['payload'])['state'],
          isNot(expected['state']),
          reason: 'the fixture is the advanced shape; started carries no index',
        );
      },
    );

    test(
      'a free workout emits the same event, and a relaunch does not re-emit it',
      () async {
        watch = await harness.launch();

        await watch.paths.startFreeWorkout();
        await harness.launch();

        final lifecycle = harness.emittedOf('session_lifecycle');
        expect(lifecycle, hasLength(1), reason: 'one per session start');
        expect(_asObject(lifecycle.single['payload'])['state'], 'started');
      },
    );

    test(
      'advancing and finishing report themselves, and nothing else',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        await watch.paths.startFromRoutine('routine-push-a');

        await watch.engine.advanceExercise();
        await watch.engine.finishSession();

        final payloads = harness
            .emittedOf('session_lifecycle')
            .map((envelope) => _asObject(envelope['payload']))
            .toList();
        expect(payloads.map((payload) => payload['state']), [
          'started',
          'exercise_advanced',
          'completed',
        ]);
        expect(payloads[1]['exerciseIndex'], 1);
        expect(payloads[2].containsKey('exerciseIndex'), isFalse);
        expect(
          harness
              .emittedOf('session_lifecycle')
              .expand(_validator().validateEnvelope),
          isEmpty,
        );

        // The advanced event is the one the protocol's fixture pins, field for
        // field — including the index, which no other state may carry.
        final fixture = _readJson(
          '$_protocolRoot/fixtures/valid/session_lifecycle.json',
        );
        expect(
          payloads[1].keys.toSet(),
          _asObject(fixture['payload']).keys.toSet(),
        );
        expect(_asObject(fixture['payload'])['state'], payloads[1]['state']);
      },
    );
  });

  group('S-005 phone push adds an exercise to the live session', () {
    test(
      'inserts at the chosen position and stays on the same exercise',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        await watch.paths.startFromRoutine('routine-push-a');
        final push = _asObject(_contract()['exercisePush']);

        for (var i = 0; i < (push['startIndex']! as int); i++) {
          await watch.engine.advanceExercise();
        }
        final before = watch.engine.currentExercise!['sessionExerciseId'];

        expect(
          await watch.orchestrator.receive(_asObject(push['envelope'])),
          isTrue,
        );

        final expected = _asObject(_contract()['routineSession']);
        expect(
          watch.engine.session!.exercises.map(
            (slot) => slot['sessionExerciseId'],
          ),
          _strings(push['expectedSlotIds']),
        );
        expect(
          watch.engine.currentExercise!['sessionExerciseId'],
          push['expectedCurrentSlotId'],
          reason: 'the push is not a request to move the user elsewhere',
        );
        expect(
          watch.engine.currentExercise!['sessionExerciseId'],
          before,
          reason: 'the position follows the exercise, not the index',
        );
        expect(expected['routineId'], 'routine-push-a');
      },
    );

    test('the pushed exercise logs with its own effort kind', () async {
      watch = await harness.launch();
      await syncFirstMessage();
      await watch.paths.startFromRoutine('routine-push-a');
      final push = _asObject(_contract()['exercisePush']);

      await watch.orchestrator.receive(_asObject(push['envelope']));

      // The push lands behind the exercise the user was on, so advancing twice
      // is how a wrist reaches it — and then it has to log as a set.
      final pushedIndex = watch.engine.session!.exercises.indexWhere(
        (slot) => slot['sessionExerciseId'] == push['pushedSlotId'],
      );
      while (watch.engine.session!.currentExerciseIndex < pushedIndex) {
        await watch.engine.advanceExercise();
      }

      expect(
        watch.engine.currentExercise!['sessionExerciseId'],
        push['pushedSlotId'],
      );
      expect(watch.surface.effortKind, WatchEffortKind.set);

      await watch.surface.log();
      final events = _objects(
        _asObject(
          harness.emittedOf('observations_up').last['payload'],
        )['events'],
      );
      expect(events, hasLength(1));
      expect(events.first['sessionExerciseId'], push['pushedSlotId']);
      expect(events.first['exerciseId'], 'ex-front-squat');
    });

    test(
      'a push before the current exercise leaves the user where they were',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        await watch.paths.startFromRoutine('routine-push-a');

        await watch.engine.advanceExercise();
        await watch.engine.advanceExercise();
        expect(
          watch.engine.currentExercise!['sessionExerciseId'],
          'sx-eff-pullup',
        );
        expect(watch.engine.session!.currentExerciseIndex, 2);

        await watch.orchestrator.receive(_pushAt(0));

        expect(
          watch.engine.session!.exercises.map(
            (slot) => slot['sessionExerciseId'],
          ),
          [
            'sx-push-front-squat',
            'sx-eff-bench',
            'sx-eff-plank',
            'sx-eff-pullup',
          ],
        );
        expect(
          watch.engine.currentExercise!['sessionExerciseId'],
          'sx-eff-pullup',
          reason: 'inserting earlier in the ladder must not move the user',
        );
        expect(
          watch.engine.session!.currentExerciseIndex,
          3,
          reason: 'the position follows the exercise, so it shifts with it',
        );
      },
    );

    test('a re-delivered push changes nothing', () async {
      watch = await harness.launch();
      await syncFirstMessage();
      await watch.paths.startFromRoutine('routine-push-a');
      final push = _asObject(_contract()['exercisePush']);

      await watch.orchestrator.receive(_asObject(push['envelope']));
      final after = watch.engine.session!;
      await watch.orchestrator.receive(_asObject(push['envelope']));

      expect(watch.engine.session!.exercises, after.exercises);
      expect(
        watch.engine.session!.currentExerciseIndex,
        after.currentExerciseIndex,
      );
    });

    test('a non-conformant push changes nothing', () async {
      watch = await harness.launch();
      await syncFirstMessage();
      await watch.paths.startFromRoutine('routine-push-a');
      final before = watch.engine.session!;
      final invalid = _readJson(
        '$_protocolRoot/fixtures/invalid/exercise_push_unknown_origin.json',
      );

      await expectLater(
        watch.orchestrator.receive(invalid),
        throwsA(isA<WatchEmissionRejected>()),
      );

      expect(watch.engine.session!.exercises, before.exercises);
      expect(
        watch.engine.session!.currentExerciseIndex,
        before.currentExerciseIndex,
      );
    });
  });

  group('S-004 routine edit propagates', () {
    test(
      'a newer message replaces the cached routine with no user action',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        final edit = _asObject(_contract()['routineEdit']);

        await harness.syncRoutinesDown(watch, _asObject(edit['routinesDown']));

        expect(watch.paths.routines, hasLength(1));
        expect(watch.paths.routines.single.name, edit['expectedRoutineName']);
        expect(
          watch.paths.routines.single.slots.map(
            (slot) => slot['sessionExerciseId'],
          ),
          _strings(edit['expectedSlotIds']),
        );
        expect(
          watch.paths.syncedAt,
          DateTime.parse(
            _asObject(
                  _asObject(edit['routinesDown'])['payload'],
                )['generatedAt']!
                as String,
          ).toUtc(),
        );
      },
    );

    test('an older message does not roll the cache back', () async {
      watch = await harness.launch();
      final fallback = _asObject(_contract()['fallback']);
      final edit = _asObject(_contract()['routineEdit']);
      await harness.syncRoutinesDown(watch, _asObject(edit['routinesDown']));

      final stale = await watch.paths.applyRoutinesDown(
        _asObject(fallback['routinesDown']),
      );

      expect(stale.applied, isFalse);
      expect(
        stale.decision.accepted,
        isTrue,
        reason: 'understood and dropped, not rejected: nothing was malformed',
      );
      expect(watch.paths.routines.single.name, 'Push A (deload)');
    });

    test(
      'a message whose fallback list misses a routine exercise is rejected',
      () async {
        watch = await harness.launch();
        final invalid = _readJson(
          '$_protocolRoot/fixtures/invalid/routines_down_unlisted_fallback_exercise.json',
        );

        final result = await watch.paths.applyRoutinesDown(invalid);

        expect(result.applied, isFalse);
        expect(result.decision.rejections, isNotEmpty);
        expect(watch.paths.routines, isEmpty);
      },
    );

    test(
      'syncing appends a row: nothing already stored is rewritten',
      () async {
        watch = await harness.launch();
        final fallback = _asObject(_contract()['fallback']);
        final edit = _asObject(_contract()['routineEdit']);

        await harness.syncRoutinesDown(
          watch,
          _asObject(fallback['routinesDown']),
        );
        await harness.syncRoutinesDown(watch, _asObject(edit['routinesDown']));
        final contents = await harness.store.readAll();

        expect(contents.routineCatalogs, hasLength(2));
        expect(
          contents.routineCatalogs.map(
            (catalog) => _asObject(catalog.routines.single)['name'],
          ),
          ['Push A', 'Push A (deload)'],
          reason: 'the log keeps both versions; the newest one wins',
        );
      },
    );
  });

  group('S-007 modality / effort-kind parity with the phone', () {
    test('every capability set resolves the way the phone resolves it', () {
      final cases = _objects(_contract()['effortKindParity']);

      for (final example in cases) {
        final capabilities = _strings(example['capabilities']);
        expect(
          _phoneEffortKind(capabilities),
          example['effortKind'],
          reason: 'the contract and the phone disagree for $capabilities',
        );
      }
    });

    test(
      'a routine-named effort renders the kind the routine declared',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        final sent = WatchRoutinesDown.fromEnvelope(
          _asObject(_asObject(_contract()['fallback'])['routinesDown']),
        );
        final session = await watch.paths.startFromRoutine('routine-push-a');

        // Walk the session the way the user would, asking the real surface what
        // each exercise is.
        final rendered = <String, String>{};
        while (true) {
          final slot = watch.engine.currentExercise!;
          rendered[slot['exerciseId']! as String] = watch.surface.effortKind;
          if (session.exercises.length - 1 <=
              watch.engine.session!.currentExerciseIndex) {
            break;
          }
          await watch.engine.advanceExercise();
        }

        for (final effort in sent.routines.expand(
          (routine) => routine.efforts,
        )) {
          expect(
            rendered[effort.exerciseId],
            effort.effortKind,
            reason:
                '${effort.exerciseName} renders as the routine declares it',
          );
        }

        // The divergence this closes (D-6): `Plank` carries `time` and `hold`,
        // which the capability rule reads as a drill, while the routine the
        // user built declares it `timed`. The routine wins — the wrist renders
        // the surface the phone's own routine sets up, not one inferred from a
        // capability list. Resolving plan 08's open item 2.
        expect(rendered['ex-plank'], 'timed');
        final plank = sent.routines
            .expand((routine) => routine.efforts)
            .firstWhere((effort) => effort.exerciseName == 'Plank');
        expect(
          _phoneEffortKind(plank.capabilities),
          isNot('timed'),
          reason: 'the capability rule alone would have rendered a hold',
        );
      },
    );

    test(
      'a pushed exercise and a routine exercise with the same capabilities agree',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();
        await watch.paths.startFromRoutine('routine-push-a');
        final push = _asObject(_contract()['exercisePush']);
        await watch.orchestrator.receive(_asObject(push['envelope']));

        final pushed = watch.engine.session!.exercises.firstWhere(
          (slot) => slot['sessionExerciseId'] == push['pushedSlotId'],
        );
        final routineSlot = watch.engine.session!.exercises.first;
        expect(pushed['capabilities'], routineSlot['capabilities']);
        expect(
          await effortKindFor(
            _strings(pushed['capabilities']),
            harness.clock.call,
          ),
          watch.surface.effortKind,
          reason:
              'same capabilities, same surface, wherever the exercise came from',
        );
      },
    );
  });

  group('proactive sync', () {
    test(
      'connect pulls everything; reconnect asks only for what changed',
      () async {
        watch = await harness.launch();
        final fallback = _asObject(_contract()['fallback']);

        await watch.orchestrator.sync();
        expect(harness.transport.requested, [null]);

        await harness.syncRoutinesDown(
          watch,
          _asObject(fallback['routinesDown']),
        );
        harness.transport.isPhoneReachable = true;
        await watch.orchestrator.sync(reconnect: true);

        expect(
          harness.transport.requested,
          [null, watch.paths.syncedAt],
          reason: 'the second request carries the catalog it already has',
        );
        expect(watch.paths.phoneReachable, isTrue);
      },
    );

    test(
      'an unreachable phone never blocks the routines the watch already has',
      () async {
        watch = await harness.launch();
        await syncFirstMessage();

        harness.transport.isPhoneReachable = false;
        await watch.orchestrator.sync();

        expect(watch.paths.phoneReachable, isFalse);
        expect(watch.paths.routines, hasLength(1));
        expect(watch.paths.fallbackExercises, isNotEmpty);
      },
    );
  });

  group('start surfaces', () {
    testWidgets('the screen says there is no automatic sync', (tester) async {
      watch = await harness.launch();
      final surface = _asObject(_contract()['startSurface']);

      await tester.pumpWidget(
        MaterialApp(home: WatchStartScreen(paths: watch.paths)),
      );

      // Said whether or not anything has synced: it is the whole reason the
      // routine list looks the way it does, and the only thing telling the user
      // that asking is what changes it (D-7, S-010). The sentence comes from the
      // shared contract, so the watchOS client says the same thing.
      expect(
        WatchStartScreen.noAutoSyncLabel,
        surface['noAutoSyncLabel'],
      );
      expect(find.text(WatchStartScreen.noAutoSyncLabel), findsOneWidget);
    });

    testWidgets('the sync action is offered only when the app can ask', (
      tester,
    ) async {
      watch = await harness.launch();
      final surface = _asObject(_contract()['startSurface']);
      var requested = 0;

      expect(WatchStartScreen.syncLabel, surface['syncLabel']);

      await tester.pumpWidget(
        MaterialApp(
          home: WatchStartScreen(
            paths: watch.paths,
            onRequestSync: () => requested++,
          ),
        ),
      );
      await tester.tap(find.text(WatchStartScreen.syncLabel));
      expect(requested, 1);

      // No transport, no button: the widget does not own the radio, and a
      // button that cannot do anything is worse than none.
      await tester.pumpWidget(
        MaterialApp(home: WatchStartScreen(paths: watch.paths)),
      );
      expect(find.text(WatchStartScreen.syncLabel), findsNothing);
      expect(find.text(WatchStartScreen.noAutoSyncLabel), findsOneWidget);
    });

    testWidgets('the start screen lists synced routines and starts one', (
      tester,
    ) async {
      watch = await harness.launch();
      await syncFirstMessage();
      WatchSessionRecord? started;

      await tester.pumpWidget(
        MaterialApp(
          home: WatchStartScreen(
            paths: watch.paths,
            onSessionStarted: (session) => started = session,
          ),
        ),
      );

      expect(find.text('Push A'), findsOneWidget);
      await tester.tap(find.text('Push A'));
      await tester.pumpAndSettle();

      expect(started, isNotNull);
      expect(started!.exercises, hasLength(3));
    });

    testWidgets(
      'free workout opens the picker, which offers exactly the fallback list',
      (tester) async {
        watch = await harness.launch();
        await syncFirstMessage();
        WatchSessionRecord? started;

        await tester.pumpWidget(
          MaterialApp(
            home: WatchStartScreen(
              paths: watch.paths,
              onSessionStarted: (session) => started = session,
            ),
          ),
        );

        await tester.tap(find.text('Free workout'));
        await tester.pumpAndSettle();

        expect(
          started,
          isNull,
          reason: 'an empty session with nothing to log is not ready yet',
        );
        for (final exercise in watch.paths.fallbackExercises) {
          expect(
            find.text(exercise.name),
            findsOneWidget,
            reason: '${exercise.name} is in the fallback list',
          );
        }
        expect(
          find.text('Barbell Row'),
          findsNothing,
          reason: 'exercises the phone never synced are not offered',
        );

        await tester.tap(find.text('Plank'));
        await tester.pumpAndSettle();

        expect(started, isNotNull);
        expect(started!.exercises, hasLength(1));
        expect(started!.exercises.first['exerciseId'], 'ex-plank');
        expect(
          find.text('Free workout'),
          findsOneWidget,
          reason: 'the list dismisses itself: a pick is the whole request',
        );
      },
    );

    testWidgets('an empty fallback list says so instead of showing nothing', (
      tester,
    ) async {
      watch = await harness.launch();

      await tester.pumpWidget(
        MaterialApp(home: WatchStartScreen(paths: watch.paths)),
      );

      expect(find.textContaining('phone'), findsWidgets);
    });

    testWidgets('the search-on-phone affordance appears only while reachable', (
      tester,
    ) async {
      watch = await harness.launch();
      await syncFirstMessage();
      await watch.paths.startFreeWorkout();

      await tester.pumpWidget(
        MaterialApp(home: WatchStartScreen(paths: watch.paths)),
      );
      expect(find.text('Search on phone'), findsNothing);

      harness.transport.isPhoneReachable = true;
      await watch.orchestrator.sync(reconnect: true);
      await tester.pumpWidget(
        MaterialApp(home: WatchStartScreen(paths: watch.paths)),
      );

      expect(find.text('Search on phone'), findsOneWidget);
    });
  });
}
