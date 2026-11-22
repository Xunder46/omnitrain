// WatchEffortRatingState — the End that owes the rating, the question, and the
// one answer it records (plan 284, D-28405..D-28407).
//
// Scenario mapping:
//   S-28409 the copy constants hold to the contract file → `S-28409 ...`
//   S-28410 End with the setting asking stores one owed prompt → `S-28410 ...`
//   S-28411 the owed rule ignores none of its four conditions → `S-28411a..d ...`
//   S-28412 the phone's deletions are seen before End → `S-28412 ...`
//   S-28413 End without an active session writes nothing → `S-28413 ...`
//   S-28414 the owed note survives a relaunch → `S-28414 ...`
//   S-28415 two owed sessions, newest asked first → `S-28415 ...`
//   S-28416 the pick rules → `S-28416 ...`
//   S-28417 Confirm needs a pick and records once → `S-28417 ...`
//   S-28418 Skip records nothing; a later answer still closes → `S-28418 ...`
//
// Plain `test()` throughout: this is the state layer, no widgets. The Mock
// store carries every scenario; S-28414 repeats its relaunch over Hive the way
// 283a's S-28307 does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/watch/logging/watch_effort_rating_state.dart';
import 'package:omnitrain/watch/session/hive_watch_session_store.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/session/watch_session_store.dart';
import 'package:omnitrain/watch/start/watch_phone_preferences.dart';

const String _protocolRoot = 'watch/sync_protocol';
const String _t1 = '2026-09-25T09:00:00Z';

class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) {
    now = now.add(duration);
  }
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

Map<String, Object?> _setEvent(_Clock clock, {required String entryId}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'set',
  'loggedAt': utcIso(clock.now),
  'sessionExerciseId': 'sx-bench',
  'exerciseId': 'ex-sx-bench',
  'reps': 5,
  'loadKg': 80,
};

/// A `rest` observation in the shape the engine's own rest ending builds —
/// appended directly, so the session holds a rest and no effort entry.
Map<String, Object?> _restEvent(_Clock clock, {required String entryId}) {
  final startedAt = clock.now;
  clock.advance(const Duration(seconds: 30));
  return {
    'entryId': entryId,
    'eventId': entryId,
    'kind': WatchObservationKind.rest,
    'loggedAt': utcIso(clock.now),
    'sessionExerciseId': 'sx-bench',
    'exerciseId': 'ex-sx-bench',
    'startedAt': utcIso(startedAt),
    'endedAt': utcIso(clock.now),
    'afterEntryId': 'entry-1',
  };
}

/// One `structure_change` from the phone, over the wrist's own session.
Map<String, Object?> _structureChange(
  String sessionId, {
  required String changeId,
  required List<Map<String, Object?>> changes,
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': 'msg-$changeId',
  'sessionId': sessionId,
  'type': 'structure_change',
  'origin': 'phone',
  'sentAt': '2026-07-13T06:30:00Z',
  'payload': <String, Object?>{'changeId': changeId, 'changes': changes},
};

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

/// A `preferences_down` envelope in the shape the valid fixtures carry, with
/// the effort-rating prompt setting the caller chooses.
Map<String, Object?> _envelope({
  String messageId = 'msg-prefs',
  Object? generatedAt,
  Object? effortRatingPrompt,
  Object? restPingSeconds,
}) => {
  'protocolVersion': 1,
  'messageId': messageId,
  'type': 'preferences_down',
  'origin': 'phone',
  'sentAt': '2026-09-25T09:00:00Z',
  'payload': {
    'generatedAt': ?generatedAt,
    'effortRatingPrompt': ?effortRatingPrompt,
    'restPingSeconds': ?restPingSeconds,
  },
};

class _Harness {
  _Harness({WatchSessionStore? store})
    : clock = _Clock(DateTime.utc(2026, 7, 13, 6)),
      store = store ?? InMemoryWatchSessionStore();

  final _Clock clock;
  final WatchSessionStore store;
  final List<Map<String, Object?>> emitted = [];
  int _ids = 0;
  int _sessions = 0;

  /// A fresh engine over the same storage — a relaunch, not a hand-over.
  WatchSessionEngine newEngine() => WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: _validator(),
    clock: clock.call,
    idFactory: () => 'rec-${++_ids}',
    sessionIdFactory: () => 's-watch-${++_sessions}',
  );

  /// An engine that has already restored, i.e. one that is running.
  Future<WatchSessionEngine> runningEngine({WatchSessionEngine? engine}) async {
    final live = engine ?? newEngine();
    await live.restore();
    return live;
  }
}

/// One rig: the engine, the phone's settings and the state, over one store.
class _Rig {
  _Rig(this.harness, this.engine, this.preferences, this.state);

  final _Harness harness;
  final WatchSessionEngine engine;
  final WatchPhonePreferences preferences;
  final WatchEffortRatingState state;
}

/// Builds a rig over [store]. [asks] applies a `preferences_down` carrying the
/// `effortRatingPrompt` value; null means the wrist never heard from the phone.
Future<_Rig> _rig(WatchSessionStore store, {bool? asks = true}) async {
  final harness = _Harness(store: store);
  final engine = await harness.runningEngine();
  final preferences = WatchPhonePreferences(
    store: store,
    clock: harness.clock.call,
  );
  if (asks != null) {
    expect(
      await preferences.applyPreferencesDown(
        _envelope(
          messageId: 'msg-prefs',
          generatedAt: _t1,
          effortRatingPrompt: asks,
          restPingSeconds: 90,
        ),
      ),
      isTrue,
      reason: 'the preferences copy applies',
    );
  }
  final state = WatchEffortRatingState(
    engine: engine,
    store: store,
    preferences: preferences,
    clock: harness.clock.call,
  );
  await state.restore();
  return _Rig(harness, engine, preferences, state);
}

/// A Hive store the test owns the directory of.
Future<WatchSessionStore> _hiveStore() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'watch_effort_rating_state_',
  );
  addTearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
  Hive.init(tempDir.path);
  return HiveWatchSessionStore();
}

/// Creates the session and logs one set into it; returns the session id.
Future<String> _sessionWithOneSet(_Rig rig, {String entryId = 'entry-1'}) async {
  await rig.engine.createSession(modality: null, exercises: [_slot('sx-bench')]);
  await rig.engine.appendObservation(_setEvent(rig.harness.clock, entryId: entryId));
  return rig.engine.session!.sessionId;
}

/// The `effort_rating` events that have travelled, in the order they were
/// emitted.
List<Map<String, Object?>> _emittedRatingEvents(_Harness harness) => [
  for (final frame in harness.emitted)
    if (frame['type'] == 'observations_up')
      for (final event in _asObject(frame['payload'])['events']! as List)
        if (_asObject(event)['kind'] == WatchObservationKind.effortRating)
          _asObject(event),
];

/// The effort-rating rows the engine currently holds.
List<WatchObservationRecord> _heldRatings(WatchSessionEngine engine) => [
  for (final row in engine.observations)
    if (row.kind == WatchObservationKind.effortRating) row,
];

/// The shared body of S-28411's four guards: End runs, the session ends, and
/// nothing is owed and nothing stored.
Future<void> _expectEndedWithoutPrompt(
  _Rig rig,
  WatchSessionRecord? ended,
) async {
  expect(ended, isNotNull);
  expect(ended!.status, WatchSessionStatus.completed);
  expect(rig.state.isPromptOwed, isFalse);
  expect((await rig.harness.store.readAll()).ratingPrompts, isEmpty);
}

/// S-28414's body, run unchanged over the Mock store and over Hive.
Future<void> _owedSurvivesRelaunch(WatchSessionStore store) async {
  final rig = await _rig(store);
  final id = await _sessionWithOneSet(rig);
  await rig.state.end();
  expect(rig.state.isPromptOwed, isTrue);
  expect(rig.state.promptSessionId, id);

  final fresh = WatchEffortRatingState(
    engine: rig.engine,
    store: store,
    preferences: rig.preferences,
    clock: rig.harness.clock.call,
  );
  await fresh.restore();
  expect(fresh.isPromptOwed, isTrue);
  expect(fresh.promptSessionId, id);
}

void main() {
  group('S-28409 the copy holds to the contract file', () {
    test('S-28409 title, scale and labels match the contract', () async {
      final contract = jsonDecode(
        File(
          '${Directory.current.path}/watch/contract/watch_effort_rating_contract.json',
        ).readAsStringSync(),
      ) as Map<String, Object?>;
      final scaleBounds = _asObject(contract['scale']);
      final labels = _asObject(contract['labels']);

      expect(WatchEffortRatingCopy.title, contract['title']);
      expect(WatchEffortRatingCopy.lowest, scaleBounds['min']);
      expect(WatchEffortRatingCopy.highest, scaleBounds['max']);
      expect(WatchEffortRatingCopy.lowestLabel, labels['1']);
      expect(WatchEffortRatingCopy.highestLabel, labels['5']);
      expect(
        WatchEffortRatingCopy.promptBeforeFirstSync,
        contract['promptBeforeFirstSync'],
      );

      final rig = await _rig(InMemoryWatchSessionStore(), asks: null);
      expect(rig.state.scale, [1, 2, 3, 4, 5]);
      expect(rig.state.title, contract['title']);
      expect(rig.state.lowestLabel, labels['1']);
      expect(rig.state.highestLabel, labels['5']);
    });
  });

  test('S-28410 End with the setting asking stores one owed prompt', () async {
    final rig = await _rig(InMemoryWatchSessionStore());
    final id = await _sessionWithOneSet(rig);

    final ended = await rig.state.end();

    expect(ended, isNotNull);
    expect(ended!.status, WatchSessionStatus.completed);
    expect(rig.state.isPromptOwed, isTrue);
    expect(rig.state.promptSessionId, id);
    final contents = await rig.harness.store.readAll();
    expect(contents.ratingPrompts, hasLength(1));
    expect(contents.ratingPrompts.single.recordId, 'prompt-$id');
    expect(contents.ratingPrompts.single.sessionId, id);
  });

  group('S-28411 nothing is owed when one of the four conditions fails', () {
    test('S-28411a the setting is off', () async {
      final rig = await _rig(InMemoryWatchSessionStore(), asks: false);
      await _sessionWithOneSet(rig);

      await _expectEndedWithoutPrompt(rig, await rig.state.end());
    });

    test('S-28411b only a rest, no effort entry', () async {
      final rig = await _rig(InMemoryWatchSessionStore());
      await rig.engine.createSession(
        modality: null,
        exercises: [_slot('sx-bench')],
      );
      await rig.engine.appendObservation(
        _restEvent(rig.harness.clock, entryId: 'rest-1'),
      );

      await _expectEndedWithoutPrompt(rig, await rig.state.end());
    });

    test('S-28411c the session already holds a rating', () async {
      final rig = await _rig(InMemoryWatchSessionStore());
      final id = await _sessionWithOneSet(rig);
      await rig.engine.recordEffortRating(4, sessionId: id);

      await _expectEndedWithoutPrompt(rig, await rig.state.end());
    });

    test("S-28411d the wrist never heard from the phone", () async {
      final rig = await _rig(InMemoryWatchSessionStore(), asks: null);
      await _sessionWithOneSet(rig);

      await _expectEndedWithoutPrompt(rig, await rig.state.end());
    });
  });

  test("S-28412 the phone's deletions are seen before End", () async {
    final rig = await _rig(InMemoryWatchSessionStore());
    final id = await _sessionWithOneSet(rig, entryId: 'e-1');

    expect(
      await rig.engine.applyMessage(
        _structureChange(
          id,
          changeId: 'chg-delete-1',
          changes: [
            {'kind': 'delete_entry', 'entryId': 'e-1'},
          ],
        ),
      ),
      isTrue,
    );
    expect(rig.engine.entries, isEmpty);

    await _expectEndedWithoutPrompt(rig, await rig.state.end());
  });

  group('S-28413 End without an active session', () {
    test('S-28413 no session: null, nothing stored', () async {
      final rig = await _rig(InMemoryWatchSessionStore());

      expect(await rig.state.end(), isNull);
      expect((await rig.harness.store.readAll()).ratingPrompts, isEmpty);
    });

    test('S-28413 an already-completed session: null, nothing stored', () async {
      final rig = await _rig(InMemoryWatchSessionStore());
      await _sessionWithOneSet(rig);
      await rig.engine.finishSession();

      expect(await rig.state.end(), isNull);
      expect((await rig.harness.store.readAll()).ratingPrompts, isEmpty);
    });
  });

  group('S-28414 the owed note survives a relaunch', () {
    test('S-28414 Mock: a fresh state over the same store still owes', () async {
      await _owedSurvivesRelaunch(InMemoryWatchSessionStore());
    });

    test('S-28414 Hive: a fresh state over the same store still owes', () async {
      await _owedSurvivesRelaunch(await _hiveStore());
    });
  });

  test('S-28415 two owed sessions: the newest asked first, the answer clears it',
      () async {
    final rig = await _rig(InMemoryWatchSessionStore());
    final a = await _sessionWithOneSet(rig, entryId: 'entry-1');
    await rig.state.end();
    final b = await _sessionWithOneSet(rig, entryId: 'entry-2');
    await rig.state.end();

    expect(rig.state.owedSessionIds, [b, a]);

    rig.state.select(4);
    final recorded = await rig.state.confirm();
    expect(recorded, isNotNull);
    expect(recorded!.recordId, 'rating-$b');
    expect(rig.state.promptSessionId, a);
  });

  group('S-28416 the pick rules', () {
    test('S-28416 step(1) from nothing picks the lowest', () async {
      final rig = await _rig(InMemoryWatchSessionStore(), asks: null);
      rig.state.step(1);
      expect(rig.state.selected, 1);
    });

    test('S-28416 step(3) from nothing picks 3', () async {
      final rig = await _rig(InMemoryWatchSessionStore(), asks: null);
      rig.state.step(3);
      expect(rig.state.selected, 3);
    });

    test('S-28416 step(-1) from nothing picks nothing', () async {
      final rig = await _rig(InMemoryWatchSessionStore(), asks: null);
      rig.state.step(-1);
      expect(rig.state.selected, isNull);
    });

    test('S-28416 select(4) then step(5) stops at the top', () async {
      final rig = await _rig(InMemoryWatchSessionStore(), asks: null);
      rig.state.select(4);
      rig.state.step(5);
      expect(rig.state.selected, 5);
    });

    test('S-28416 select(4) then step(-10) stops at the bottom', () async {
      final rig = await _rig(InMemoryWatchSessionStore(), asks: null);
      rig.state.select(4);
      rig.state.step(-10);
      expect(rig.state.selected, 1);
    });

    test('S-28416 select(0) and select(6) change nothing', () async {
      final fromNothing = await _rig(InMemoryWatchSessionStore(), asks: null);
      fromNothing.state.select(0);
      expect(fromNothing.state.selected, isNull);
      fromNothing.state.select(6);
      expect(fromNothing.state.selected, isNull);

      final fromTwo = await _rig(InMemoryWatchSessionStore(), asks: null);
      fromTwo.state.select(2);
      fromTwo.state.select(0);
      expect(fromTwo.state.selected, 2);
      fromTwo.state.select(6);
      expect(fromTwo.state.selected, 2);
    });
  });

  test('S-28417 Confirm needs a pick, records once, and clears the question',
      () async {
    final rig = await _rig(InMemoryWatchSessionStore());
    final id = await _sessionWithOneSet(rig);
    await rig.state.end();

    expect(rig.state.canConfirm, isFalse);
    expect(await rig.state.confirm(), isNull);
    expect(rig.engine.hasEffortRating(id), isFalse);
    expect(_emittedRatingEvents(rig.harness), isEmpty);

    rig.state.select(3);
    expect(rig.state.canConfirm, isTrue);

    rig.state.select(2);
    final recorded = await rig.state.confirm();
    expect(recorded, isNotNull);
    expect(recorded!.recordId, 'rating-$id');
    expect(recorded.payload['rating'], 2);
    expect(rig.state.selected, isNull);
    expect(rig.state.isPromptOwed, isFalse);
    expect(rig.engine.hasEffortRating(id), isTrue);
    expect(_emittedRatingEvents(rig.harness), hasLength(1));
  });

  test('S-28418 Skip records nothing; a later answer still closes the question',
      () async {
    final rig = await _rig(InMemoryWatchSessionStore());
    final id = await _sessionWithOneSet(rig);
    await rig.state.end();

    rig.state.select(2);
    rig.state.skipPrompt();
    expect(rig.state.isPromptOwed, isFalse);
    expect(rig.state.selected, isNull);
    expect(_heldRatings(rig.engine), isEmpty);
    final contents = await rig.harness.store.readAll();
    expect(contents.ratingPrompts, hasLength(1));
    expect(contents.ratingPrompts.single.recordId, 'prompt-$id');

    final fresh = WatchEffortRatingState(
      engine: rig.engine,
      store: rig.harness.store,
      preferences: rig.preferences,
      clock: rig.harness.clock.call,
    );
    await fresh.restore();
    expect(fresh.isPromptOwed, isTrue);

    final ratingId = WatchSessionCapture.effortRatingId(id);
    expect(
      await rig.engine.applyMessage(
        _snapshotOf(
          id,
          messageId: 'msg-phone-rating',
          entries: [
            {
              'entryId': ratingId,
              'eventId': ratingId,
              'kind': WatchObservationKind.effortRating,
              'loggedAt': '2026-07-13T06:10:00Z',
              'rating': 5,
            },
          ],
        ),
      ),
      isTrue,
    );
    expect(fresh.isPromptOwed, isFalse);
  });
}
