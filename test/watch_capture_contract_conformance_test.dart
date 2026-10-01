// Watch capture — the protocol additions and the shared capture contract.
//
// Plan: `docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md`,
// Phase 1 (protocol and shared contracts).
// Scenario mapping:
//   S-204 preferences_down conforms, and the Dart wrist ignores it → `S-204 ...`
//   S-207 the capture contract conforms                             → `S-207 ...`
//
// S-201 – S-203 and S-205 are fixtures, not tests: the manifest-walking suites
// run them without edits (`test/sync_protocol_fixtures_test.dart`,
// `test/live_mirroring_test.dart`,
// `test/watch_reconciliation_cross_stack_test.dart`,
// `test/watch_session_engine_test.dart`, and the watchOS
// `SyncProtocolFixturesTests` and `WatchLiveMirroringTests`). S-206 is the
// sensor-kind equality `test/watch_sensor_recording_test.dart` already pins.
//
// `watch/contract/watch_capture_contract.json` (F-CAP) is shared with the
// watchOS suite, so "conformant" is the schema's verdict on both stacks rather
// than this file's opinion. The wrist's arithmetic is not recomputed here: the
// Swift replay owns that. What this file owns is that every event the contract
// promises is one the protocol accepts, and that the contract's halves — the
// wrist's events and the phone's import — describe the same session.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';
import 'package:omnitrain/watch/start/watch_sync_orchestrator.dart';

import 'helpers/sync_protocol_harness.dart';

Map<String, Object?> _captureContract() => asObject(
  jsonDecode(
    File(
      '${Directory.current.path}/watch/contract/watch_capture_contract.json',
    ).readAsStringSync(),
  ),
);

/// [event] the way the wrist sends it: one event per `observations_up`.
Map<String, Object?> _asWristSendsIt(
  String sessionId,
  Map<String, Object?> event,
) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-${event['entryId']}',
  'sessionId': sessionId,
  'type': 'observations_up',
  'origin': 'watch',
  'sentAt': event['loggedAt'],
  'payload': {
    'events': [event],
  },
};

const List<String> _summaryFields = [
  'avgHeartRateBpm',
  'maxHeartRateBpm',
  'steps',
  'setBlockHeartRates',
];

Map<String, Object?> _heartRatePair(Map<String, Object?> record) => {
  if (record.containsKey('avgHeartRateBpm'))
    'avgHeartRateBpm': record['avgHeartRateBpm'],
  if (record.containsKey('maxHeartRateBpm'))
    'maxHeartRateBpm': record['maxHeartRateBpm'],
};

/// The summary rows the wrist's events carry, in the import's vocabulary: a
/// session end's pair and set blocks, a timed or hold entry's pair and steps
/// (both become a timed instance on the phone), and a round's pair.
List<Map<String, Object?>> _summariesCarriedBy(
  String sessionId,
  List<Map<String, Object?>> events,
) {
  final rows = <Map<String, Object?>>[];
  for (final event in events) {
    final pair = _heartRatePair(event);
    switch (event['kind']) {
      case 'session_end':
        if (pair.isNotEmpty) {
          rows.add({
            'scope': 'session',
            'target': {'sessionId': sessionId},
            ...pair,
          });
        }
        for (final block in objectsOf(event['setBlockHeartRates'] ?? [])) {
          rows.add({
            'scope': 'effort',
            'target': {
              'effortKind': 'set',
              'sessionExerciseId': block['sessionExerciseId'],
              'exerciseId': block['exerciseId'],
            },
            ..._heartRatePair(block),
          });
        }
      case 'timed' || 'hold':
        final measured = {
          ...pair,
          if (event.containsKey('steps')) 'steps': event['steps'],
        };
        if (measured.isNotEmpty) {
          rows.add({
            'scope': 'timed_instance',
            'target': {'entryId': event['entryId']},
            ...measured,
          });
        }
      case 'round':
        if (pair.isNotEmpty) {
          rows.add({
            'scope': 'round_instance',
            'target': {'entryId': event['entryId']},
            ...pair,
          });
        }
    }
  }
  return rows;
}

Map<String, Object?> _storeContents(WatchStoreContents contents) => {
  'sessions': [for (final row in contents.sessions) row.toJson()],
  'observations': [for (final row in contents.observations) row.toJson()],
  'timers': [for (final row in contents.timers) row.toJson()],
  'sensorSamples': [for (final row in contents.sensorSamples) row.toJson()],
  'confirmations': [for (final row in contents.confirmations) row.toJson()],
  'routineCatalogs': [for (final row in contents.routineCatalogs) row.toJson()],
  'foodCatalogs': [for (final row in contents.foodCatalogs) row.toJson()],
};

/// A link to the phone that records what the wrist asked of it.
class _Transport implements WatchSyncTransport {
  @override
  bool isPhoneReachable = true;

  final List<Map<String, Object?>> sent = [];
  int routineRequests = 0;
  int snapshotRequests = 0;

  @override
  Future<void> requestRoutines({DateTime? since}) async => routineRequests++;

  @override
  Future<void> requestSnapshot() async => snapshotRequests++;

  @override
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);
}

void main() {
  final validator = loadProtocolValidator();
  final contract = _captureContract();
  final cases = objectsOf(contract['cases']);

  group('S-207 the capture contract conforms', () {
    test('holds the three F-CAP cases', () {
      expect(cases.map((captureCase) => captureCase['name']), [
        'full',
        'no-sensors',
        'prompt-off',
      ]);
    });

    for (final captureCase in cases) {
      final name = captureCase['name']! as String;
      final sessionId = captureCase['sessionId']! as String;
      final events = objectsOf(captureCase['expectedEvents']);
      final expectedImport = asObject(captureCase['expectedImport']);

      test('$name: every expected event, sent as the wrist sends it, is one '
          'the protocol accepts', () {
        expect(events, isNotEmpty);
        for (final event in events) {
          expect(
            validator
                .validateEnvelope(_asWristSendsIt(sessionId, event))
                .map((rejection) => rejection.toString())
                .toList(),
            isEmpty,
            reason: 'S-207 $name: ${event['entryId']} must conform',
          );
        }
      });

      test('$name: the phone receipts exactly the entries the wrist sent', () {
        final sentIds = [for (final event in events) event['entryId']];

        expect(sentIds.toSet(), hasLength(sentIds.length));
        expect(expectedImport['receiptedEntryIds'], equals(sentIds));
      });

      test('$name: the imported summaries are the ones the events carry', () {
        expect(
          objectsOf(expectedImport['sensorSummaries']),
          unorderedEquals(_summariesCarriedBy(sessionId, events)),
        );
      });

      test('$name: the imported rating is the one the wrist recorded', () {
        final ratings = [
          for (final event in events)
            if (event['kind'] == 'effort_rating') event['rating'],
        ];

        expect(ratings.length, lessThanOrEqualTo(1));
        expect(
          asObject(expectedImport['session'])['sessionFeeling'],
          ratings.isEmpty ? isNull : ratings.single,
        );
      });
    }

    test('no-sensors: no event carries a summary, and nothing is '
        'summarised', () {
      final noSensors = cases.singleWhere(
        (captureCase) => captureCase['name'] == 'no-sensors',
      );

      for (final event in objectsOf(noSensors['expectedEvents'])) {
        for (final field in _summaryFields) {
          expect(
            event.containsKey(field),
            isFalse,
            reason: '${event['entryId']} must not carry $field',
          );
        }
      }
      expect(
        asObject(noSensors['expectedImport'])['sensorSummaries'],
        isEmpty,
      );
    });

    test('prompt-off: the wrist is told not to ask, so there is no '
        'rating', () {
      final promptOff = cases.singleWhere(
        (captureCase) => captureCase['name'] == 'prompt-off',
      );
      final timeline = objectsOf(promptOff['timeline']);

      expect(
        timeline.singleWhere(
          (op) => op['op'] == 'preferences',
        )['effortRatingPrompt'],
        isFalse,
      );
      expect(timeline.where((op) => op['op'] == 'answer'), isEmpty);
      expect(
        objectsOf(
          promptOff['expectedEvents'],
        ).where((event) => event['kind'] == 'effort_rating'),
        isEmpty,
      );
    });
  });

  group('S-204 preferences_down', () {
    final fixture = readProtocolJson('fixtures/valid/preferences_down.json');

    test('conforms to the protocol', () {
      expect(
        validator
            .validateEnvelope(fixture)
            .map((rejection) => rejection.toString())
            .toList(),
        isEmpty,
        reason: 'S-204 preferences_down must conform',
      );
    });

    test('the Dart wrist ignores it and stores nothing', () async {
      final store = InMemoryWatchSessionStore();
      final clock = TestClock(DateTime.utc(2026, 9, 25, 9));
      final emitted = <Map<String, Object?>>[];
      var ids = 0;
      final engine = WatchSessionEngine(
        store,
        onEmit: emitted.add,
        validator: validator,
        clock: clock.call,
        idFactory: () => 'rec-${++ids}',
        sessionIdFactory: () => 's-prefs',
      );
      final paths = WatchSessionStartPaths(
        engine: engine,
        store: store,
        validator: validator,
        clock: clock.call,
        idFactory: () => 'cat-${++ids}',
      );
      await engine.restore();
      await paths.restore();
      final transport = _Transport();
      final orchestrator = WatchSyncOrchestrator(
        transport: transport,
        paths: paths,
        engine: engine,
      );
      // A wrist with a session running: the message must leave it untouched.
      await engine.createSession(
        modality: null,
        exercises: [
          {
            'sessionExerciseId': 'sx-bench',
            'exerciseId': 'ex-bench',
            'name': 'Barbell Bench Press',
            'capabilities': ['sets', 'reps', 'load'],
          },
        ],
      );
      final storedBefore = _storeContents(await store.readAll());
      final emittedBefore = emitted.length;

      final applied = await orchestrator.receive(fixture);

      expect(
        applied,
        isFalse,
        reason: 'S-204 the Dart wrist has no use for preferences_down',
      );
      expect(
        _storeContents(await store.readAll()),
        equals(storedBefore),
        reason: 'S-204 the Dart wrist stores nothing from preferences_down',
      );
      expect(emitted, hasLength(emittedBefore));
      expect(transport.sent, isEmpty);
      expect(transport.snapshotRequests, 0);
      expect(transport.routineRequests, 0);
    });
  });
}
