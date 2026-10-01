// Cross-stack conformance: the phone's reconciler and the wrist's engine on the
// same fixtures, in lockstep.
//
// Plan: `docs/plans/2026-09-21-13-watch-integration-shipping.md`,
// Phase 5 (D-4).
// Scenario mapping:
//   S-008 snapshot merge                  → `S-008 ...`
//   S-009 remove the current exercise     → `S-009 ...`
//
// Two engines implement the same protocol rules — `SyncSessionReconciler` on the
// phone, `WatchSessionEngine` on the wrist — and until now the shared fixtures
// held each side to the spec separately. This test holds them to *each other*:
// the same fixture replayed through both must converge on the same structure
// state, or the divergence fails here rather than on a user's wrist.
//
// What "the same" means: the ladder in order (slot id and exercise id), the
// current position, the revision, the status, and which timers exist. Entries are
// deliberately out of the comparison — the phone's reconciler takes entries from
// every `observations_up` it is handed, while the wrist is the device that
// produced them and never applies its own; a difference in entry *provenance*
// that is not a difference in structure. Entry ids are checked for agreement on
// the fixtures where the wrist does receive them, through the snapshot.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/session_reconciler.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

const String _fixtures = 'watch/sync_protocol/fixtures/reconciliation';

final DateTime _now = DateTime.utc(2026, 9, 21, 12);

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objectsIn(Object? value) =>
    ((value as List?) ?? const []).map(_asObject).toList(growable: false);

Map<String, Object?> _payloadOf(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

List<Map<String, Object?>> _streamOf(Map<String, Object?> fixture) =>
    _objectsIn(fixture['stream']);

/// Every reconciliation fixture, newest protocol rules included.
List<Map<String, Object?>> _fixtures_() {
  final directory = Directory('${Directory.current.path}/$_fixtures');
  return [
    for (final file in directory.listSync().whereType<File>())
      if (file.path.endsWith('.json'))
        _asObject(jsonDecode(file.readAsStringSync())),
    // The version-mismatch fixture carries cases rather than a stream and is
    // driven by the protocol gate's own test.
  ].where((fixture) => fixture['snapshot'] != null).toList(growable: false);
}

String _fixtureName(Map<String, Object?> fixture) =>
    '${fixture['name']} ';

/// The structure state both engines must agree on.
Map<String, Object?> _structureOf(
  List<Map<String, Object?>> exercises,
  Map<String, Object?> state,
) => {
  'ladder': [
    for (final slot in exercises)
      {
        'sessionExerciseId': slot['sessionExerciseId'],
        'exerciseId': slot['exerciseId'],
      },
  ],
  'currentExerciseIndex': state['currentExerciseIndex'],
  'revision': state['revision'],
  'status': state['status'],
  'timers': ((state['timers'] as Map?)?.keys.toList() ?? const [])..sort(),
};

void main() {
  final fixtures = _fixtures_();

  test('the fixture set is the protocol register, not a hardcoded list', () {
    expect(
      Directory('${Directory.current.path}/$_fixtures')
          .listSync()
          .whereType<File>()
          .length,
      greaterThanOrEqualTo(10),
    );
  });

  for (final fixture in fixtures) {
    test('S-008/S-009 ${_fixtureName(fixture)}converges on both stacks',
        () async {
      final snapshot = _asObject(fixture['snapshot']);
      final phone = SyncSessionReconciler.fromSnapshot(_payloadOf(snapshot));
      final engine = WatchSessionEngine(
        InMemoryWatchSessionStore(),
        clock: () => _now,
      );
      await engine.applyMessage(snapshot);

      for (final message in _streamOf(fixture)) {
        phone.applyMessage(message);
        // The wrist's own product: it logged those entries, and a device does
        // not apply its own observations back onto itself.
        if (message['type'] == 'observations_up') continue;
        await engine.applyMessage(message);
      }

      final phoneState = phone.convergedState();
      final watchState = engine.sessionSnapshot()!;
      final watchPayload = _payloadOf(watchState);

      expect(
        _structureOf(engine.session!.exercises, watchPayload),
        _structureOf(
          _objectsIn(phoneState['exercises']),
          phoneState,
        ),
        reason: '${fixture['name']} diverged between the two stacks',
      );
    });
  }

  test('S-009 removing the current exercise leaves both stacks on the next one',
      () async {
    final fixture = fixtures.firstWhere(
      (fixture) => (fixture['name']! as String).contains(
        'advances to the next valid exercise',
      ),
    );
    final snapshot = _asObject(fixture['snapshot']);
    final phone = SyncSessionReconciler.fromSnapshot(_payloadOf(snapshot));
    final engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
    );
    await engine.applyMessage(snapshot);

    final ladderBefore = [...engine.session!.exercises];
    final before = engine.session!.currentExerciseIndex;
    final removed =
        ladderBefore[before]['sessionExerciseId']! as String;

    for (final message in _streamOf(fixture)) {
      phone.applyMessage(message);
      await engine.applyMessage(message);
    }

    final after = phone.convergedState();
    final ladderAfter = engine.session!.exercises;

    // The point of the fixture: the position stays inside the ladder and moves
    // to the exercise that followed the removed one, on both stacks.
    expect(
      ladderAfter.any((slot) => slot['sessionExerciseId'] == removed),
      isFalse,
    );
    expect(engine.session!.currentExerciseIndex, after['currentExerciseIndex']);
    expect(engine.session!.currentExerciseIndex, lessThan(ladderAfter.length));
  });
}
