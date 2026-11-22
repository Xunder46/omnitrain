// Watch engine — the effort rating, its one-row rule and its survival of a
// prune (plan 284, D-28401..D-28404).
//
// Scenario mapping:
//   S-28401 record -> row fields, one frame          → `S-28401 ...`
//   S-28402 second call returns null, nothing new    → `S-28402 ...`
//   S-28403 hasEffortRating false/true/false         → `S-28403 ...`
//   S-28404 ratings 0 and 6 refused, nothing stored  → `S-28404 ...`
//   S-28405 confirmed+pruned rating stays known      → `S-28405 ...`
//   S-28406 the phone's snapshot closes the question → `S-28406 ...`
//   S-28407 WatchRatingPromptRecord through stores   → `S-28407 ...`
//   S-28408 the kind constants                       → `S-28408 ...`

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';

const String _protocolRoot = 'watch/sync_protocol';

class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;
}

Map<String, Object?> _slot(String slot) => {
  'sessionExerciseId': slot,
  'exerciseId': 'ex-$slot',
  'name': slot,
  'capabilities': ['reps', 'sets', 'load'],
};

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

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

/// One `session_snapshot` from the phone, over the wrist's own session.
Map<String, Object?> _snapshotOf(
  String sessionId, {
  required String messageId,
  String sentAt = '2026-07-13T06:30:00Z',
  List<Map<String, Object?>> entries = const <Map<String, Object?>>[],
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': sessionId,
  'type': 'session_snapshot',
  'origin': 'phone',
  'sentAt': sentAt,
  'payload': <String, Object?>{
    'sessionId': sessionId,
    'revision': 0,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [_slot('sx-bench')],
    'entries': entries,
    'timers': <String, Object?>{},
  },
};

class _Harness {
  _Harness({WatchSessionStore? store})
    : clock = _Clock(DateTime.utc(2026, 7, 13, 6)),
      store = store ?? InMemoryWatchSessionStore();

  final _Clock clock;
  final WatchSessionStore store;
  final String sessionId = 's-watch-1';
  final List<Map<String, Object?>> emitted = [];
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

  /// An engine that has already restored, i.e. one that is running.
  Future<WatchSessionEngine> runningEngine({WatchSessionEngine? engine}) async {
    final live = engine ?? newEngine();
    await live.restore();
    return live;
  }
}

/// The `observations_up` frames the harness has emitted so far.
List<Map<String, Object?>> _emittedRatingFrames(_Harness harness) => [
  for (final frame in harness.emitted)
    if (frame['type'] == 'observations_up') _asObject(frame),
];

/// The events one `observations_up` envelope carries.
List<Map<String, Object?>> _eventsOf(Map<String, Object?> frame) => [
  for (final event in _asObject(frame['payload'])['events']! as List)
    _asObject(event),
];

/// The effort-rating rows the engine currently holds.
List<WatchObservationRecord> _heldRatings(WatchSessionEngine engine) => [
  for (final row in engine.observations)
    if (row.kind == WatchObservationKind.effortRating) row,
];

/// S-28405's body, run unchanged over the Mock store and over Hive.
Future<void> _ratingSurvivesPrune(WatchSessionStore store) async {
  final harness = _Harness(store: store);
  final engine = await harness.runningEngine();
  final id = WatchSessionCapture.effortRatingId(harness.sessionId);

  await engine.recordEffortRating(4, sessionId: harness.sessionId);
  await engine.confirmObservations([id]);
  await engine.pruneConfirmed();

  expect(engine.hasEffortRating(harness.sessionId), isTrue);
  expect(_heldRatings(engine), isEmpty);

  final relaunched = await harness.runningEngine();
  expect(relaunched.hasEffortRating(harness.sessionId), isTrue);
}

/// S-28407's body, run unchanged over the Mock store and over Hive.
Future<void> _promptRecordRoundTrip(WatchSessionStore store) async {
  final recordedAt = DateTime.utc(2026, 7, 13, 6);
  final record = WatchRatingPromptRecord(
    recordId: WatchRatingPromptRecord.recordIdFor('s-1'),
    sessionId: 's-1',
    recordedAt: recordedAt,
  );

  final stored = await store.append(record);
  expect(stored.recordId, 'prompt-s-1');

  final contents = await store.readAll();
  expect(contents.ratingPrompts, hasLength(1));
  expect(contents.ratingPrompts.single.recordId, 'prompt-s-1');
  expect(contents.ratingPrompts.single.sessionId, 's-1');
  expect(contents.ratingPrompts.single.recordedAt, recordedAt);

  await store.append(record);
  expect((await store.readAll()).ratingPrompts, hasLength(1));
}

void main() {
  group('S-28401 recordEffortRating', () {
    test(
      'S-28401 record -> row fields and exactly ONE observations_up frame',
      () async {
        final harness = _Harness();
        final engine = await harness.runningEngine();
        await engine.createSession(
          modality: null,
          exercises: [_slot('sx-bench')],
        );

        final row = await engine.recordEffortRating(
          4,
          sessionId: harness.sessionId,
        );

        final id = WatchSessionCapture.effortRatingId(harness.sessionId);
        expect(row, isNotNull);
        expect(row!.recordId, id);
        expect(row.kind, WatchObservationKind.effortRating);
        expect(row.payload['entryId'], id);
        expect(row.payload['eventId'], id);
        expect(row.payload['rating'], 4);
        expect(row.payload['loggedAt'], utcIso(harness.clock.now));

        final frames = _emittedRatingFrames(harness);
        expect(frames, hasLength(1));
        final events = _eventsOf(frames.single);
        expect(events, hasLength(1));
        expect(events[0]['kind'], 'effort_rating');
        expect(events[0]['rating'], 4);
        expect(events[0]['entryId'], id);
        expect(events[0]['eventId'], id);
        expect(events[0]['loggedAt'], utcIso(harness.clock.now));
      },
    );
  });

  test('S-28402 a second recordEffortRating returns null and changes nothing',
      () async {
    final harness = _Harness();
    final engine = await harness.runningEngine();
    await engine.createSession(
      modality: null,
      exercises: [_slot('sx-bench')],
    );
    await engine.recordEffortRating(4, sessionId: harness.sessionId);

    final second = await engine.recordEffortRating(2, sessionId: 's-watch-1');

    expect(second, isNull);
    expect(_emittedRatingFrames(harness), hasLength(1));
    expect(_heldRatings(engine), hasLength(1));
    expect(_heldRatings(engine).single.payload['rating'], 4);
  });

  test(
    'S-28403 hasEffortRating is false before, true after, false for another session',
    () async {
      final harness = _Harness();
      final engine = await harness.runningEngine();
      expect(engine.hasEffortRating(harness.sessionId), isFalse);

      await engine.recordEffortRating(4, sessionId: harness.sessionId);

      expect(engine.hasEffortRating(harness.sessionId), isTrue);
      expect(engine.hasEffortRating('s-other'), isFalse);
    },
  );

  test('S-28404 a rating of 0 and of 6 is refused and stores nothing', () async {
    final harness = _Harness();
    final engine = await harness.runningEngine();

    await expectLater(
      engine.recordEffortRating(0, sessionId: harness.sessionId),
      throwsA(isA<WatchEmissionRejected>()),
    );
    await expectLater(
      engine.recordEffortRating(6, sessionId: harness.sessionId),
      throwsA(isA<WatchEmissionRejected>()),
    );

    expect(_heldRatings(engine), isEmpty);
    expect(_emittedRatingFrames(harness), isEmpty);
  });

  group('S-28405 a confirmed and pruned rating is still known after relaunch', () {
    test('S-28405 Mock: pruneConfirmed forgets the row, not the answer', () async {
      await _ratingSurvivesPrune(InMemoryWatchSessionStore());
    });

    test('S-28405 Hive: pruneConfirmed forgets the row, not the answer',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'watch_effort_rating_',
      );
      addTearDown(() async {
        await Hive.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      Hive.init(tempDir.path);

      await _ratingSurvivesPrune(HiveWatchSessionStore());
    });
  });

  test("S-28406 the phone's session_snapshot closes the question", () async {
    final harness = _Harness();
    final engine = await harness.runningEngine();
    await engine.createSession(
      modality: null,
      exercises: [_slot('sx-bench')],
    );
    final id = WatchSessionCapture.effortRatingId(harness.sessionId);
    expect(
      await engine.applyMessage(
        _snapshotOf(
          harness.sessionId,
          messageId: 'msg-phone-rating',
          entries: [
            {
              'entryId': id,
              'eventId': id,
              'kind': WatchObservationKind.effortRating,
              'loggedAt': '2026-07-13T06:10:00Z',
              'rating': 5,
            },
          ],
        ),
      ),
      isTrue,
    );
    final framesBefore = _emittedRatingFrames(harness).length;

    expect(engine.hasEffortRating(harness.sessionId), isTrue);
    expect(
      await engine.recordEffortRating(2, sessionId: harness.sessionId),
      isNull,
    );
    expect(_emittedRatingFrames(harness), hasLength(framesBefore));
  });

  group('S-28407 a WatchRatingPromptRecord round-trips through each store', () {
    test('S-28407 Mock: one row per session, appended twice stays one', () async {
      await _promptRecordRoundTrip(InMemoryWatchSessionStore());
    });

    test('S-28407 Hive: one row per session, appended twice stays one',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'watch_effort_rating_',
      );
      addTearDown(() async {
        await Hive.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      Hive.init(tempDir.path);

      await _promptRecordRoundTrip(HiveWatchSessionStore());
    });
  });

  test('S-28408 the constants', () {
    expect(WatchObservationKind.effortRating, 'effort_rating');
    expect(WatchObservationKind.all, contains(WatchObservationKind.effortRating));
    expect(
      WatchObservationKind.efforts,
      isNot(contains(WatchObservationKind.effortRating)),
    );
  });
}
