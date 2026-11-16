// The Dart twin names its session's modality in its own `session_snapshot`
// when the row holds one, and sends none for a Free session — the twin half
// of plan 204 (the Swift wrist gets the same change beside this one).
//
// Plan: `docs/plans/2026-11-15-204-wrist-names-its-modality-plan/
// 2026-11-15-204-wrist-names-its-modality-plan.md`, Phase P2.
// Scenario mapping (all through the twin,
// `lib/watch/session/watch_session_engine.dart`'s `sessionSnapshot()`):
//   S-20405  a session with a modality names it in its snapshot → `S-20405 a
//            session with a modality ...`
//   S-20405  a Free session names none                          → `S-20405 a
//            free session ...`
//   S-20405  every other key is what it was and the envelope conforms
//                                                        → `S-20405 every ...`
//   S-20405  a restart keeps the modality (the twin's restore, as the engine
//            tests show it)                              → `S-20405 a restart ...`
//
// The engine over the in-memory store and `createSession`'s signature are the
// shapes of `test/watch_session_engine_test.dart` and
// `test/watch_snapshot_focus_wrist_test.dart`. Plain `test()`: no
// testWidgets, no Hive, no real clock — the engine reads time only through
// its injected clock.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/sync_protocol_harness.dart' show TestClock, loadProtocolValidator;

const String _modality = 'isometric_stretching';

/// The seven keys the payload carried before plan 204.
const Set<String> _existingKeys = {
  'sessionId',
  'revision',
  'status',
  'currentExerciseIndex',
  'exercises',
  'entries',
  'timers',
};

Map<String, Object?> _slot() => {
  'sessionExerciseId': 'sx-modality-204',
  'exerciseId': 'ex-modality-204',
  'name': 'Modality Bench 204',
  'capabilities': ['reps', 'sets', 'load'],
};

class _Harness {
  _Harness() : clock = TestClock(DateTime.utc(2026, 7, 13, 17));

  final TestClock clock;
  final InMemoryWatchSessionStore store = InMemoryWatchSessionStore();
  final List<Map<String, Object?>> emitted = [];
  int _ids = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over.
  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: loadProtocolValidator(),
    clock: clock.call,
    idFactory: () => 'rec-${++_ids}',
    sessionIdFactory: () => 's-watch-204',
  );

  /// An engine that has already restored, i.e. one that is running.
  Future<WatchSessionEngine> runningEngine() async {
    final engine = newEngine();
    await engine.restore();
    return engine;
  }
}

Future<WatchSessionEngine> _engineWithModality(
  _Harness harness, {
  required String? modality,
}) async {
  final engine = await harness.runningEngine();
  await engine.createSession(modality: modality, exercises: [_slot()]);
  return engine;
}

void main() {
  group('S-20405 the twin names its session\'s modality in its snapshot', () {
    test('S-20405 a session with a modality names it in its snapshot', () async {
      final engine = await _engineWithModality(
        _Harness(),
        modality: _modality,
      );

      final payload = engine.sessionSnapshot()!['payload']! as Map<String, Object?>;
      expect(
        payload['modality'],
        _modality,
        reason: 'the row holds a non-empty modality, so the payload names it',
      );
    });

    test('S-20405 a free session names none', () async {
      final engine = await _engineWithModality(_Harness(), modality: null);

      final payload =
          engine.sessionSnapshot()!['payload']! as Map<String, Object?>;
      expect(
        payload.containsKey('modality'),
        isFalse,
        reason: 'a Free session holds no modality, so no key travels at all',
      );
    });

    test('S-20405 every other key is what it was and the envelope conforms', () async {
      final validator = loadProtocolValidator();

      // The modality case: the seven existing keys plus `modality`, and the
      // envelope the project's own validator accepts.
      final engine = await _engineWithModality(
        _Harness(),
        modality: _modality,
      );
      final envelope = engine.sessionSnapshot()!;
      expect(
        (envelope['payload']! as Map<String, Object?>).keys.toSet(),
        _existingKeys.union({'modality'}),
        reason: 'modality is the only key the payload gained',
      );
      expect(
        validator.validateEnvelope(envelope),
        isEmpty,
        reason: 'the schema already declares the key, so the envelope conforms',
      );

      // The free case: the same set without `modality`, and it conforms too.
      final freeEngine = await _engineWithModality(_Harness(), modality: null);
      final freeEnvelope = freeEngine.sessionSnapshot()!;
      expect(
        (freeEnvelope['payload']! as Map<String, Object?>).keys.toSet(),
        _existingKeys,
        reason: 'a keyless Free snapshot is the payload it always was',
      );
      expect(validator.validateEnvelope(freeEnvelope), isEmpty);
    });

    test('S-20405 a restart keeps the modality', () async {
      final harness = _Harness();
      await _engineWithModality(harness, modality: _modality);

      final relaunched = await harness.runningEngine();
      final relaunchedPayload =
          relaunched.sessionSnapshot()!['payload']! as Map<String, Object?>;
      expect(
        relaunchedPayload['modality'],
        _modality,
        reason: 'a relaunch rebuilds the row from storage with its modality',
      );
    });
  });
}
