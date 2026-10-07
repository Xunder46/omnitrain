// The phone pushes its own session to the wrist, without a Sync (auto-sync PR
// 1b, Phase 3A).
//
// Plan: `docs/plans/2026-10-06-17a-watch-auto-sync-pr1-plan/` (D-75…D-84).
// Scenario mapping:
//   S-70 a change on the phone reaches the wrist       → `S-70 ...`
//   S-71 a push carries the converged place            → `S-71 ...`
//   S-72 the phone's finish is announced               → `S-72 ...`
//   S-73 the phone's discard abandons the wrist's copy → `S-73 ...`
//   S-74 a notification that changes nothing pushes nothing → `S-74 ...`
//   S-75 a burst inside one window is one push         → `S-75 ...`
//   S-80 an applied frame is not pushed back           → `S-80 ...`
//   S-81 a re-delivered frame changes nothing          → `S-81 ...`
//   S-83 a push the radio cannot carry is dropped      → `S-83 ...`
//   S-84 browsing another session pushes nothing       → `S-84 ...`
//   S-85 every session in one run is announced once    → `S-85 ...`
//   S-86 the phone never abandons a session it never held → `S-86 ...`
//   S-87 a wrist frame inside the window loses no finish → `S-87 ...`
//   S-88 browsing away does not lose a later finish   → `S-88 ...`
//   S-112 a hung send cannot wedge the push           → `S-112 ...`
//   S-113 a debounce-path failure is reported         → `S-113 ...`
//   S-120 a set deleted on the phone disappears on the wrist
//                                                     → `S-120 ...`
//   S-121 several deletions, and a deletion that never was → `S-121 ...`
//   S-122 an entry the wrist logged, imported and deleted → `S-122 ...`
//   S-123 the first pass announces nothing (negative guard) → `S-123 ...`
//   S-126 another session's deletion changes nothing   → `S-126 ...`
//   D-114 leaving a session and coming back re-seeds its ledger → `D-114 ...`
//   F4 a flush never leaks and never announces twice   → `F4 ...`
//   F2 a set the phone re-used and dropped again is announced again
//                                                     → `F2 ...`
//   F3 a deletion frame names the session it is about  → `F3 ...`
//   F7 a deletion whose send failed is owed, then sent → `F7 ...`
//   G2 an Error from the session read is not swallowed  → `G2 ...`
//
// The delete half is 17c Phase 1 (D-110…D-114, S-120…S-126); S-124, S-125 and
// S-126's dedupe half are the engine's and live in `watch_session_engine_test.dart`.
//
// The phone side is the graph `createWatchSync` builds — the shipping wiring,
// including the push it returns — over a fake radio; the wrist side is the real
// engine over an in-memory store, so every pushed frame is applied the way the
// watch app applies one. The push is bound where a scenario starts from a
// settled fixture, so the fixture's own notifications are not part of the
// scenario, and every window is closed by `flush()` rather than by waiting.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/phone_envelope.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_session_auto_push.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_records.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
// `seedExercise` comes from the capture harness: it writes capabilities through
// `setExerciseCapabilities`, which is the only way they reach a repository —
// `createExercise` ignores the inline list. The projection refuses a slot whose
// exercise carries none, so this is load-bearing.
import 'helpers/watch_capture_import_harness.dart' show seedExercise;

final DateTime _now = DateTime.utc(2026, 10, 6, 9);

Map<String, Object?> _asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

List<Map<String, Object?>> _objects(Object? value) =>
    (value! as List).map(_asObject).toList(growable: false);

Map<String, Object?> _payload(Map<String, Object?> envelope) =>
    _asObject(envelope['payload']);

List<String> _slotIds(Map<String, Object?> payload) => [
  for (final slot in _objects(payload['exercises']))
    slot['sessionExerciseId']! as String,
];

List<String> _entryIds(Map<String, Object?> payload) => [
  for (final entry in _objects(payload['entries']))
    entry['entryId']! as String,
];

List<String> _sorted(Iterable<String> ids) => [...ids]..sort();

/// One ladder slot as the protocol spells it — what a wrist writes when it
/// starts a session on its own.
Map<String, Object?> _slot(
  String id,
  String exerciseId,
  String name,
  List<String> capabilities,
) => <String, Object?>{
  'sessionExerciseId': id,
  'exerciseId': exerciseId,
  'name': name,
  'effortKind': 'set',
  'capabilities': capabilities,
};

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// Polls [ready] to a bounded deadline — never unbounded — so a push that never
/// settles fails the test rather than hanging it.
Future<void> _until(bool Function() ready, {required String reason}) async {
  for (var attempt = 0; attempt < 500; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail(reason);
}

/// The instant a fixture's rows are stamped with: [minute] past the phone's own
/// `_now` on the same day.
int _at(int minute) =>
    DateTime.utc(2026, 10, 6, 9, minute).millisecondsSinceEpoch;

/// The same instant, as the protocol writes one.
String _atIso(int minute) =>
    utcIso(DateTime.fromMillisecondsSinceEpoch(_at(minute), isUtc: true));

/// The first set the wrist logs in these fixtures: its own id, which the phone
/// imports and must never send back (D-34).
const String _wristEntryId = '9f2c1d2e-3b4a-4c5d-8e6f-7a8b9c0d1e2f';

/// A second set the wrist logs.
const String _wristEntryId2 = '2b7e4f6a-1c8d-4e5f-9a0b-3c4d5e6f7a8b';

/// The slot id the phone's own sets land on, and the id the wrist's ladder
/// carries it under (D-3: an adopted effort's row id IS its slot id).
const String _firstSlot = 'sx-1';

/// The second slot, which the phone never logs in.
const String _secondSlot = 'sx-2';

/// A catalog the phone can open a session from.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-squat',
    name: 'Squat',
    capabilities: ['sets', 'reps', 'load'],
  );
  await seedExercise(
    repository,
    id: 'ex-bench',
    name: 'Bench Press',
    capabilities: ['sets', 'reps', 'load'],
  );
  await seedExercise(
    repository,
    id: 'ex-deadlift',
    name: 'Deadlift',
    capabilities: ['sets', 'reps', 'load'],
  );
  await seedExercise(
    repository,
    id: 'ex-row',
    name: 'Barbell Row',
    capabilities: ['sets', 'reps', 'load'],
  );
}

/// The phone's radio: records what the phone sent, hands the phone one frame
/// from the wrist the way the platform channel does, and reports what it cannot
/// carry the way the platform channel does — never by throwing (D-83).
class _PhoneRadio implements WatchTransport {
  _PhoneRadio(this.onFailure);

  final void Function(Object error) onFailure;

  final List<Map<String, Object?>> sent = [];

  /// Every frame handed to `send`, including the ones it then failed: what a
  /// pass tried to announce is not visible in [sent] alone (F7).
  final List<Map<String, Object?>> attempted = [];

  /// True while the wrist is out of range: `send` reports and carries nothing.
  bool failing = false;

  /// True while the next `send` is not to complete at all — a radio that has
  /// gone silent (S-112's seam). One frame, then the flag clears itself.
  bool hangNext = false;

  /// True while `send` throws instead of reporting — a platform channel that
  /// fails the future rather than the callback (S-113's seam).
  bool throwing = false;

  WatchInboundHandler? _handler;

  @override
  bool get isPhoneReachable => true;

  @override
  void onIncoming(WatchInboundHandler handler) => _handler = handler;

  @override
  Future<void> refreshReachability() async {}

  @override
  Future<void> requestRoutines({DateTime? since}) async =>
      send(WatchTransportRequest.routinesFrame(since: since));

  @override
  Future<void> requestSnapshot() async =>
      send(WatchTransportRequest.snapshotFrame());

  @override
  Future<void> send(Map<String, Object?> envelope) async {
    attempted.add(envelope);
    if (failing) {
      onFailure(StateError('the wrist is out of range'));
      return;
    }
    if (throwing) throw Exception('the radio refused the frame');
    if (hangNext) {
      hangNext = false;
      return Completer<void>().future;
    }
    sent.add(envelope);
  }

  /// One frame from the wrist, the way the radio delivers one.
  Future<void> fromWrist(Map<String, Object?> frame) async {
    final handler = _handler;
    if (handler == null) {
      throw StateError('the phone graph never bound its inbound handler');
    }
    await handler(frame);
  }

  /// Everything the phone sent of one type, in order.
  List<Map<String, Object?>> ofType(String type) => [
    for (final envelope in sent)
      if (envelope['type'] == type) envelope,
  ];
}

void main() {
  late MockWorkoutRepository repository;
  late WorkoutState phoneState;
  late SettingsState phoneSettings;
  late _PhoneRadio radio;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late InMemoryWatchSessionStore wristStore;
  late List<Map<String, Object?>> wristFrames;
  late List<Object> failures;

  /// One catalog exercise added to the phone's running session through the
  /// regular session path. Answers the effort id it was given, which is also
  /// the slot id the wrist sees (D-3).
  Future<String> add(String exerciseId) async {
    final exercise = (await repository.getExerciseById(exerciseId))!;
    return phoneState.addExerciseToSession(exercise);
  }

  /// How many sets the phone's own session holds on [effortId]. A set is two
  /// rows — reps and weight — so the reps rows are what count entries.
  Future<int> phoneEntries(String effortId) async => [
    for (final row in await repository.getEffortObservations(effortId))
      if (row.metricId == MetricIds.reps) row,
  ].length;

  /// The phone's ladder as slot ids, in order.
  List<String> phoneSlots() => [
    for (final segment in phoneState.segments)
      for (final effort in phoneState.getEffortsForSegment(segment.id))
        effort.id,
  ];

  /// The wrist's ladder as slot ids, in order.
  List<String> wristSlots() => [
    for (final slot in engine.session!.exercises)
      slot['sessionExerciseId']! as String,
  ];

  /// The ids of the entries the wrist's store holds.
  List<String> wristEntryIds() => [
    for (final row in engine.entries) row.recordId,
  ];

  /// Every row the wrist's store holds, as `type:id` — the identity a
  /// re-delivered frame must leave alone (S-81).
  Future<List<String>> wristRows() async {
    final contents = await wristStore.readAll();
    return <String>[
      for (final row in contents.sessions) 'session:${row.recordId}',
      for (final row in contents.observations) 'observation:${row.recordId}',
      for (final row in contents.timers) 'timer:${row.recordId}',
      for (final row in contents.sensorSamples) 'sample:${row.recordId}',
    ]..sort();
  }

  /// The phone graph a fresh app start builds, over [radio]. The app binds its
  /// own `WorkoutState` to the adoption and to the push in `lib/main.dart`; a
  /// scenario binds the push itself, once its fixture has settled.
  Future<WatchSyncGraph> startGraph() async {
    final created = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: phoneSettings,
      transport: radio,
      clock: () => _now,
      onFailure: (error, stack) => failures.add(error),
    ))!;
    created.adoption.bindWorkoutState(phoneState);
    return created;
  }

  /// The wrist starts `s-1` with two slots and logs one set on the first, and
  /// the phone adopts it: the fixture every scenario here starts from.
  ///
  /// The snapshot goes over first, because an observation for a session the
  /// phone does not own is staged as history rather than merged into the live
  /// one — the adoption is what makes `s-1` the phone's own session.
  Future<void> wristStartsSession() async {
    await engine.createSession(
      modality: null,
      exercises: [
        _slot(_firstSlot, 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
        _slot(_secondSlot, 'ex-bench', 'Bench Press', ['sets', 'reps', 'load']),
      ],
    );
    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    await engine.appendObservation(<String, Object?>{
      'entryId': _wristEntryId,
      'eventId': _wristEntryId,
      'kind': 'set',
      'loggedAt': _atIso(1),
      'sessionExerciseId': _firstSlot,
      'exerciseId': 'ex-squat',
      'reps': 8,
      'loadKg': 60.0,
    });
    await radio.fromWrist(wristFrames.last);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      's-1',
      reason: 'the fixture: the phone\'s own session is the wrist\'s',
    );
    expect(phoneSlots(), [_firstSlot, _secondSlot]);
    expect(
      await phoneEntries(_firstSlot),
      1,
      reason: 'the fixture: the wrist\'s set merged into the phone\'s session',
    );
  }

  /// The phone logs one of its own sets and pushes it: S-70's whole flow, which
  /// the later scenarios continue from. Answers the frame the phone sent.
  Future<Map<String, Object?>> pushPhoneSet() async {
    await phoneState.addEntry(
      _firstSlot,
      previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
    );
    await graph.autoPush.flush();
    final pushes = radio.ofType('session_snapshot');
    expect(pushes, hasLength(1), reason: 'S-70 one change, one frame');
    return pushes.single;
  }

  /// The phone logs one more of its own sets, pushes it and the wrist applies
  /// the frame — the state S-120's fixture needs, where the wrist holds a set
  /// the phone is about to drop. Answers the id the phone minted for it.
  Future<String> logSetHeldByBoth() async {
    final snapshots = radio.ofType('session_snapshot');
    final before = [
      if (snapshots.isNotEmpty) ..._entryIds(_payload(snapshots.last)),
    ];
    await phoneState.addEntry(
      _firstSlot,
      previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
    );
    await graph.autoPush.flush();
    final push = radio.ofType('session_snapshot').last;
    final added = _entryIds(_payload(push)).firstWhere(
      (entryId) => !before.contains(entryId),
      orElse: () => fail('the fixture: the phone logged no new set'),
    );
    await engine.applyMessage(push);
    return added;
  }

  setUp(() async {
    failures = [];
    repository = MockWorkoutRepository();
    await repository.initialize();
    await _seedCatalog(repository);

    phoneState = WorkoutState(repository);
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();

    radio = _PhoneRadio(failures.add);
    graph = await startGraph();

    wristFrames = [];
    wristStore = InMemoryWatchSessionStore();
    engine = WatchSessionEngine(
      wristStore,
      clock: () => _now,
      sessionIdFactory: () => 's-1',
      onEmit: wristFrames.add,
    );
  });

  group('S-70 a change on the phone reaches the wrist without a sync', () {
    test(
      'S-70 the phone\'s own set is pushed as one snapshot, and the wrist\'s '
      'own set is not sent back',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);

        final push = await pushPhoneSet();

        expect(push['origin'], 'phone');
        expect(push['sessionId'], 's-1');
        final payload = _payload(push);
        expect(push['type'], 'session_snapshot');
        expect(
          _slotIds(payload),
          [_firstSlot, _secondSlot],
          reason: 'S-70 the push carries the ladder the phone holds',
        );
        expect(
          _entryIds(payload),
          ['entry-$_firstSlot-1'],
          reason:
              'S-70 the phone\'s own set rides the push, and the wrist\'s own '
              'set does not come back to it under a phone id (D-34). The '
              'wrist\'s set is the first group of the slot, so the phone\'s is '
              'the second: the session path numbers a new set above every '
              'number the effort holds (D-325)',
        );
        expect(
          _objects(payload['entries']).single['reps'],
          8,
          reason:
              'S-70 the phone\'s set rides the push with the values it was '
              'logged with (the fixture\'s 62.5 kg × 8), so the wrist holds the '
              'same set the phone does',
        );
        expect(_objects(payload['entries']).single['loadKg'], 62.5);
        expect(payload['timers'], isEmpty);
        expect(payload['currentExerciseIndex'], 0);

        await engine.applyMessage(push);
        expect(wristSlots(), [_firstSlot, _secondSlot]);
        expect(
          wristEntryIds(),
          containsAll(<String>[_wristEntryId, 'entry-$_firstSlot-1']),
          reason:
              'S-70 the wrist applies the push: the phone\'s set lands beside '
              'the set the wrist logged itself',
        );
        final own = engine.entries.firstWhere(
          (row) => row.recordId == _wristEntryId,
        );
        expect(own.payload['reps'], 8);
        expect(own.payload['loadKg'], 60.0);
        expect(
          engine.session!.currentExerciseIndex,
          0,
          reason: 'S-70 the push does not move the wrist off its exercise',
        );
        expect(failures, isEmpty);

        await phoneState.refreshEfforts([_firstSlot]);
        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot'),
          hasLength(1),
          reason:
              'S-70 a notification that changes nothing the wrist can see '
              'pushes nothing (D-76)',
        );
      },
    );
  });

  group('S-71 a push carries the converged place', () {
    test('S-71 the push reports the wrist\'s position, not slot 0', () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      // The wrist moves to its second slot and re-asserts its own snapshot at
      // the next sync; the phone converges on it.
      await engine.startTimer('rest', plannedDurationMs: 90000);
      final restTimer = engine.timerFor('rest')!;
      await engine.advanceExercise();
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        graph.mirror.currentExerciseIndex,
        1,
        reason: 'the fixture: the phone converged on the wrist\'s position',
      );
      expect(
        engine.session!.currentExercise!['sessionExerciseId'],
        _secondSlot,
      );

      // The mirror's own re-assertion is not this scenario's frame: the push is
      // what the phone sends about its own session.
      radio.sent.clear();

      final third = await add('ex-deadlift');
      await graph.autoPush.flush();

      final push = radio.ofType('session_snapshot');
      expect(push, hasLength(1), reason: 'S-71 one change, one frame');
      final payload = _payload(push.single);
      expect(
        payload['currentExerciseIndex'],
        1,
        reason:
            'S-71 the push carries the place the two devices converged on, not '
            'slot 0 and not the phone\'s own place (D-77)',
      );
      expect(_slotIds(payload), [_firstSlot, _secondSlot, third]);
      expect(
        payload['timers'],
        isEmpty,
        reason:
            'S-71 the phone asserts no timers of its own, so the wrist\'s own '
            'countdown is the one that stands (D-80)',
      );

      await engine.applyMessage(push.single);
      expect(wristSlots(), [_firstSlot, _secondSlot, third]);
      expect(
        engine.session!.currentExerciseIndex,
        1,
        reason: 'S-71 the push leaves the wrist on the exercise it is on',
      );
      final after = engine.timerFor('rest')!;
      expect(after.recordId, restTimer.recordId);
      expect(
        after.stoppedAt,
        isNull,
        reason:
            'S-71 the wrist\'s rest countdown is still running after the push',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-72 the phone\'s finish is announced', () {
    test('S-72 finishing on the phone ends the wrist\'s copy, once', () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      final snapshotsBefore = radio.ofType('session_snapshot').length;
      await phoneState.endSession();
      await graph.autoPush.flush();

      final ends = radio.ofType('session_lifecycle');
      expect(ends, hasLength(1), reason: 'S-72 the end is announced');
      expect(ends.single['sessionId'], 's-1');
      expect(_payload(ends.single)['state'], WatchLifecycleState.completed);
      expect(
        radio.ofType('session_snapshot'),
        hasLength(snapshotsBefore),
        reason:
            'S-72 an ended session has nothing of the phone\'s own to assert',
      );
      expect(
        graph.mirror.status,
        WatchSessionStatus.completed,
        reason: 'S-72 the mirror holds the session as closed',
      );

      await phoneState.loadSessionData();
      await graph.autoPush.flush();
      expect(
        radio.ofType('session_lifecycle'),
        hasLength(1),
        reason: 'S-72 the end is announced once, however often the state notifies',
      );

      await engine.applyMessage(ends.single);
      expect(engine.session!.status, WatchSessionStatus.completed);
      expect(
        wristEntryIds(),
        contains(_wristEntryId),
        reason: 'S-72 the wrist\'s own set survives the phone\'s finish',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-73 the phone\'s discard abandons the wrist\'s copy', () {
    test('S-73 discarding on the phone abandons the wrist\'s copy, once',
        () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      final snapshotsBefore = radio.ofType('session_snapshot').length;
      await phoneState.discardCurrentSession();
      await graph.autoPush.flush();

      final ends = radio.ofType('session_lifecycle');
      expect(ends, hasLength(1));
      expect(ends.single['sessionId'], 's-1');
      expect(
        _payload(ends.single)['state'],
        WatchLifecycleState.abandoned,
        reason:
            'S-73 a session the phone no longer holds at all is abandoned, not '
            'completed (D-81)',
      );
      expect(
        radio.ofType('session_snapshot'),
        hasLength(snapshotsBefore),
        reason:
            'S-73 a session the phone no longer holds has nothing to assert '
            'either, so the announcement is the whole of it',
      );

      await phoneState.loadSessionData();
      await graph.autoPush.flush();
      expect(
        radio.ofType('session_lifecycle'),
        hasLength(1),
        reason: 'S-73 the abandonment is announced once',
      );

      await engine.applyMessage(ends.single);
      expect(engine.session!.status, WatchSessionStatus.abandoned);
      expect(
        wristEntryIds(),
        contains(_wristEntryId),
        reason: 'S-73 the wrist\'s own set stays logged (D-81)',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-74 a notification that changes nothing pushes nothing', () {
    test('S-74 five notifications without a change push nothing', () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      await phoneState.refreshEfforts([_firstSlot]);
      await phoneState.refreshEfforts([_firstSlot]);
      await phoneState.loadSessionData();
      await phoneState.updateSessionNote('felt strong');
      await phoneState.refreshEfforts([_firstSlot]);
      await graph.autoPush.flush();

      expect(
        radio.ofType('session_snapshot'),
        hasLength(1),
        reason:
            'S-74 the payload is compared by its encoding, so a reload, a note '
            'and a refresh that leave the session the same send nothing (D-76)',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-75 a burst of changes inside one window is one push', () {
    test('S-75 three changes inside the window are one frame', () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      final deadlift = await add('ex-deadlift');
      final row = await add('ex-row');
      await phoneState.addEntry(_firstSlot);

      expect(
        radio.ofType('session_snapshot'),
        hasLength(1),
        reason:
            'S-75 the trailing window is still open, so a burst is not three '
            'frames (D-76)',
      );

      await graph.autoPush.flush();
      final pushes = radio.ofType('session_snapshot');
      expect(pushes, hasLength(2), reason: 'S-75 the window closes into one');
      final payload = _payload(pushes.last);
      expect(_slotIds(payload), [_firstSlot, _secondSlot, deadlift, row]);
      expect(
        _sorted(_entryIds(payload)),
        _sorted([
          'entry-$_firstSlot-1',
          'entry-$_firstSlot-2',
          'entry-$deadlift-0',
          'entry-$row-0',
        ]),
        reason:
            'S-75 the one frame carries everything the burst changed: the '
            'phone\'s sets, and the set the session path logs for each exercise '
            'it added',
      );
      expect(failures, isEmpty);
    });

    test('S-75 the trailing window closes by itself', () async {
      await wristStartsSession();

      // A push of its own, over the same mirror and repository the graph wired,
      // with a window short enough to wait for — the only scenario here that
      // lets the timer fire instead of closing the window by hand.
      final push = WatchSessionAutoPush(
        mirror: graph.mirror,
        getSession: repository.getSession,
        debounce: const Duration(milliseconds: 5),
      )..bindWorkoutState(phoneState);
      addTearDown(push.dispose);

      await phoneState.addEntry(_firstSlot);

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (radio.ofType('session_snapshot').isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      final pushes = radio.ofType('session_snapshot');
      expect(
        pushes,
        hasLength(1),
        reason:
            'S-75 the window closes on its own and pushes what changed, with '
            'nobody asking (D-76)',
      );
      expect(
        _entryIds(_payload(pushes.single)),
        ['entry-$_firstSlot-1'],
      );
    });
  });

  group('S-80 a frame the phone applied from the wrist is not pushed back', () {
    test(
      'S-80 the wrist\'s own set and its snapshot are not answered with a push',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();
        final pushesBefore = radio.ofType('session_snapshot').length;

        // The wrist logs its own second set and reports it.
        await engine.appendObservation(<String, Object?>{
          'entryId': _wristEntryId2,
          'eventId': _wristEntryId2,
          'kind': 'set',
          'loggedAt': _atIso(2),
          'sessionExerciseId': _firstSlot,
          'exerciseId': 'ex-squat',
          'reps': 6,
          'loadKg': 65.0,
        });
        await radio.fromWrist(wristFrames.last);
        await _settle();

        expect(
          [for (final entry in graph.mirror.entries) entry['entryId']],
          contains(_wristEntryId2),
          reason: 'the fixture: the phone\'s mirror holds the wrist\'s set',
        );
        expect(
          await phoneEntries(_firstSlot),
          3,
          reason:
              'the fixture: the wrist\'s set merged into the phone\'s own '
              'session, beside the wrist\'s first set and the phone\'s own',
        );

        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot'),
          hasLength(pushesBefore),
          reason:
              'S-80 a frame the phone applied from the wrist is not pushed '
              'back: the rows it brought in are not news (D-82)',
        );

        // The wrist moves on and re-asserts its snapshot at the next sync. The
        // phone converges on it, and whatever the frame itself settles (a
        // re-assertion of its own shape included) is where the count stands.
        await engine.advanceExercise();
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();
        expect(graph.mirror.currentExerciseIndex, 1);
        final afterFrame = radio.ofType('session_snapshot').length;

        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot'),
          hasLength(afterFrame),
          reason:
              'S-80 the applied frame became the baseline, so the place it '
              'reports is not pushed back either (D-82)',
        );

        // The phone's own next change is pushed, carrying the converged place.
        await phoneState.addEntry(_firstSlot);
        await graph.autoPush.flush();
        final pushes = radio.ofType('session_snapshot');
        expect(pushes, hasLength(afterFrame + 1));
        expect(_payload(pushes.last)['currentExerciseIndex'], 1);
        expect(
          _entryIds(_payload(pushes.last)),
          ['entry-$_firstSlot-1', 'entry-$_firstSlot-3'],
          reason:
              'S-80 the push carries the phone\'s own sets, never the wrist\'s '
              'own back to it (D-34). The wrist\'s two sets took groups 0 and '
              '2 as they merged in, so the phone\'s second set is numbered 3 '
              '(D-325)',
        );

        await engine.applyMessage(pushes.last);
        expect(
          wristEntryIds(),
          containsAll(<String>[
            _wristEntryId,
            _wristEntryId2,
            'entry-$_firstSlot-1',
            'entry-$_firstSlot-3',
          ]),
          reason: 'S-80 the wrist keeps its own sets and gains the phone\'s',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-81 a re-delivered frame changes nothing', () {
    test('S-81 the same snapshot twice writes nothing new on the wrist',
        () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      final push = await pushPhoneSet();

      expect(await engine.applyMessage(push), isTrue);
      final applied = await wristRows();
      expect(
        wristEntryIds(),
        contains('entry-$_firstSlot-1'),
        reason: 'the fixture: the phone\'s set is on the wrist',
      );

      expect(
        await engine.applyMessage(push),
        isTrue,
        reason:
            'S-81 a re-delivered snapshot is applied, not refused: the wrist '
            'is in the session it names',
      );
      expect(
        await wristRows(),
        applied,
        reason:
            'S-81 the same message id leaves the wrist\'s rows exactly as they '
            'were — no second entry, no second session row, no second timer '
            '(the push\'s fire-and-forget transport relies on this)',
      );
      expect(failures, isEmpty);
    });

    test('S-81 the same lifecycle twice ends the wrist\'s copy once', () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      await phoneState.endSession();
      await graph.autoPush.flush();
      final end = radio.ofType('session_lifecycle').single;

      expect(await engine.applyMessage(end), isTrue);
      final ended = await wristRows();
      expect(engine.session!.status, WatchSessionStatus.completed);

      expect(await engine.applyMessage(end), isTrue);
      expect(
        await wristRows(),
        ended,
        reason: 'S-81 the same end re-delivered writes no second end row',
      );
      expect(engine.session!.status, WatchSessionStatus.completed);
      expect(failures, isEmpty);
    });

    test(
      'S-81 the same observation twice leaves the phone unchanged and pushes '
      'nothing',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();
        final pushesBefore = radio.ofType('session_snapshot').length;

        final replayed = wristFrames.last;
        final rowsBefore =
            (await repository.getEffortObservations(_firstSlot)).length;
        await radio.fromWrist(replayed);
        await _settle();
        await radio.fromWrist(replayed);
        await _settle();

        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot'),
          hasLength(pushesBefore),
          reason:
              'S-81 a wrist frame re-delivered with the same message id changes '
              'nothing and pushes nothing (D-76, D-82)',
        );
        expect(
          (await repository.getEffortObservations(_firstSlot)).length,
          rowsBefore,
          reason: 'S-81 the phone\'s own rows are unchanged by the replay',
        );
        expect(
          radio.ofType('receipt'),
          isNotEmpty,
          reason:
              'S-81 the phone still acknowledges the re-delivered entry — the '
              'wrist never got its receipt (D-132)',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-83 a push the radio cannot carry is dropped', () {
    test(
      'S-83 a failed send is reported once, changes nothing, and is not retried',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);

        radio.failing = true;
        await phoneState.addEntry(_firstSlot);
        await graph.autoPush.flush();

        expect(
          failures,
          hasLength(1),
          reason:
              'S-83 the radio reports what it cannot carry, once (D-83)',
        );
        expect(
          radio.ofType('session_snapshot'),
          isEmpty,
          reason: 'S-83 nothing left the phone',
        );
        expect(
          await phoneEntries(_firstSlot),
          2,
          reason:
              'S-83 the phone\'s own state is undisturbed: the push writes '
              'nothing and queues nothing',
        );

        await graph.autoPush.flush();
        expect(
          failures,
          hasLength(1),
          reason:
              'S-83 the payload that failed is baselined all the same, so the '
              'same state is not attempted twice: catching up is PR 2\'s job',
        );

        await phoneState.addEntry(_firstSlot);
        radio.failing = false;
        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot'),
          hasLength(1),
          reason: 'S-83 the next change the phone has is pushed again',
        );
        expect(failures, hasLength(1));
      },
    );
  });

  group('S-84 browsing another session pushes nothing', () {
    test('S-84 opening a past session pushes nothing for the live one',
        () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();
      final pushesBefore = radio.ofType('session_snapshot').length;

      // A finished session in the phone's history, with a ladder of its own.
      final start = _at(0);
      await repository.createSession(
        TrainingSession(
          id: 'h-1',
          ownerUserId: LoggedEntryRows.ownerUserId,
          startedAtMs: start,
          endedAtMs: start + 60000,
          createdAtMs: start,
          updatedAtMs: start + 60000,
        ),
      );
      await repository.createSegment(
        LoggedEntryRows.defaultSegment(
          id: 'segment-h-1',
          sessionId: 'h-1',
          atMs: start,
        ),
      );
      await repository.createEffort(
        SegmentEffort(
          id: 'h-slot',
          segmentId: 'segment-h-1',
          orderIndex: 0,
          effortKind: 'set',
          exerciseId: 'ex-bench',
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      for (final row in LoggedEntryRows.setObservations(
        effortId: 'h-slot',
        entryIndex: 0,
        reps: 5,
        weightKg: 50,
        exerciseHasLoad: true,
        atMs: start,
      )) {
        await repository.createObservation(row);
      }

      // The user opens it. The mirror still holds the wrist's session as live,
      // and that session's own row has no end.
      await phoneState.loadHistoricalSession('h-1');
      await graph.autoPush.flush();

      expect(
        radio.ofType('session_snapshot'),
        hasLength(pushesBefore),
        reason:
            'S-84 a finished session the user is reading is not a session to '
            'push, and the live one has not changed',
      );
      expect(
        radio.ofType('session_lifecycle'),
        isEmpty,
        reason:
            'S-84 browsing history must not end the session the wrist is still '
            'in: the rule reads that session\'s own row, never the phone\'s '
            'current-session pointer (D-81)',
      );

      // Opening the live session again is still nothing: the payload is the one
      // the phone last sent for it.
      await phoneState.loadHistoricalSession('s-1');
      await graph.autoPush.flush();
      expect(
        radio.ofType('session_snapshot'),
        hasLength(pushesBefore),
        reason:
            'S-84 re-reading the live session sends nothing: the payload equals '
            'the one already on the wrist (D-76)',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-85 every session in one app run is announced for itself', () {
    test(
      'S-85 two finishes and a discard are announced once each, under each '
      'session\'s own id',
      () async {
        // Session 1: adopted off the wrist, logged into and finished on the
        // phone. The mirror holds this one.
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();
        await phoneState.endSession();
        await graph.autoPush.flush();

        // Session 2: the phone's own, started after the first finished. The
        // mirror still holds session 1.
        await phoneState.createNewSession();
        final second = await add('ex-bench');
        final secondId = phoneState.currentSession!.id;
        await phoneState.addEntry(
          second,
          previousValues: <String, dynamic>{'reps': 5, 'weight': 40},
        );
        await graph.autoPush.flush();
        expect(
          [
            for (final frame in radio.ofType('session_snapshot'))
              frame['sessionId'],
          ],
          contains(secondId),
          reason: 'the fixture: session 2 is the phone\'s own and is pushed',
        );

        await phoneState.endSession();
        await graph.autoPush.flush();

        // Session 3: started, pushed, then discarded without ever ending.
        // The phone names a session `session-<millisecondsSinceEpoch>`
        // (`lib/state/workout/session_core_io.dart`), so two sessions started
        // inside one millisecond collide on their id — and this fixture would
        // then hold two sessions under one id, a state the rule under test
        // ("under each session's own id") cannot satisfy. Start the third once
        // the id clock has moved past the second.
        while ('session-${DateTime.now().millisecondsSinceEpoch}' == secondId) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await phoneState.createNewSession();
        final third = await add('ex-deadlift');
        final thirdId = phoneState.currentSession!.id;
        await phoneState.addEntry(third);
        await graph.autoPush.flush();
        await phoneState.discardCurrentSession();
        await graph.autoPush.flush();

        final announced = <String, List<String>>{};
        for (final frame in radio.ofType('session_lifecycle')) {
          (announced[frame['sessionId']! as String] ??= []).add(
            _payload(frame)['state']! as String,
          );
        }
        expect(
          announced,
          <String, List<String>>{
            's-1': [WatchLifecycleState.completed],
            secondId: [WatchLifecycleState.completed],
            thirdId: [WatchLifecycleState.abandoned],
          },
          reason:
              'S-85 the rule reads the phone\'s own session, so a second '
              'session in the same app run is announced like the first, under '
              'its own id, and each one exactly once (D-81)',
        );
        expect(failures, isEmpty);
      },
    );

    test('S-85 the end the wrist itself caused is not announced back at it',
        () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      // The wrist ends its own session, and says so. The phone's copy ends with
      // it, through the router, so both devices hold the fact already.
      await engine.finishSession();
      final lifecycle = wristFrames.last;
      expect(
        lifecycle['type'],
        'session_lifecycle',
        reason: 'the fixture: the wrist announces its own end',
      );
      await radio.fromWrist(lifecycle);
      await _settle();
      expect(graph.mirror.status, WatchSessionStatus.completed);
      expect(
        phoneState.currentSession?.endedAtMs,
        isNotNull,
        reason: 'the fixture: the wrist is the authority on its own session',
      );
      radio.sent.clear();

      await graph.autoPush.flush();
      await phoneState.loadSessionData();
      await graph.autoPush.flush();

      expect(
        radio.ofType('session_lifecycle'),
        isEmpty,
        reason:
            'S-85 the phone announces ends it caused, not ends it was told '
            'about: the wrist already holds this one, so there is nothing left '
            'to say (D-81)',
      );
      expect(failures, isEmpty);
    });
  });

  group('S-86 a session the phone never held is not abandoned', () {
    test(
      'S-86 the phone\'s own push does not end the wrist\'s live session',
      () async {
        // The phone starts a session of its own and puts a ladder in it.
        await phoneState.createNewSession();
        final own = await add('ex-squat');
        final ownSessionId = phoneState.currentSession!.id;

        // The wrist is running a session of its own — X — which the phone has
        // no row for and refuses to adopt (D-10).
        await engine.createSession(
          modality: null,
          exercises: [
            _slot(_firstSlot, 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
          ],
        );
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();
        expect(
          graph.mirror.sessionId,
          's-1',
          reason: 'the fixture: the mirror took the wrist\'s own session',
        );
        expect(
          await repository.getSession('s-1'),
          isNull,
          reason:
              'the fixture: the phone never held X, so there is no row for it '
              '(D-10 refused the adoption)',
        );
        expect(phoneState.currentSession?.id, ownSessionId);

        graph.autoPush.bindWorkoutState(phoneState);
        await phoneState.addEntry(
          own,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        await graph.autoPush.flush();

        expect(
          radio.ofType('session_lifecycle'),
          isEmpty,
          reason:
              'S-86 a missing row means "discarded" only for a session the '
              'phone itself held and pushed: announcing `abandoned` for the '
              'wrist\'s session would end the workout running on the wrist',
        );
        final pushes = radio.ofType('session_snapshot');
        expect(
          pushes,
          hasLength(1),
          reason: 'S-86 the phone\'s own session is the only frame it sends',
        );
        expect(pushes.single['sessionId'], ownSessionId);
        expect(_slotIds(_payload(pushes.single)), [own]);
        expect(
          engine.session!.status,
          WatchSessionStatus.active,
          reason: 'S-86 nothing the phone sent named the wrist\'s session',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-87 a finish survives a wrist frame inside its window', () {
    test(
      'S-87 a frame the wrist sends inside the window does not lose the '
      'finish it landed in',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();

        // The phone finishes its session and starts another: two notifications
        // inside one debounce window, so no flush has run yet and the finish is
        // still pending when the frame below lands.
        await phoneState.endSession();
        await phoneState.createNewSession();
        final secondId = phoneState.currentSession!.id;

        // The phone is already logging in the new session: a session with no
        // rows of its own is one the projection cannot speak for, so a frame
        // that re-baselines onto it would compose nothing and never reach the
        // pending finish. (The discard variant carries the same effort.)
        await add('ex-squat');

        // A frame from the wrist lands in that window. The shipping wiring
        // re-baselines the push after every applied frame (D-82), so the push
        // composes the phone's new session while the finish is still pending.
        await engine.appendObservation(<String, Object?>{
          'entryId': _wristEntryId2,
          'eventId': _wristEntryId2,
          'kind': 'set',
          'loggedAt': _atIso(2),
          'sessionExerciseId': _secondSlot,
          'exerciseId': 'ex-bench',
          'reps': 6,
          'loadKg': 45.0,
        });
        await radio.fromWrist(wristFrames.last);
        await _settle();

        // News of the phone's own session, so that the push that follows the
        // finish is a real change and not a no-op.
        await add('ex-row');
        await graph.autoPush.flush();

        final announced = radio.ofType('session_lifecycle');
        expect(
          [for (final frame in announced) frame['sessionId']],
          ['s-1'],
          reason:
              'S-87 the finish the frame landed in is announced, under the '
              'session that finished: re-baselining the push onto the session '
              'the phone moved to must not erase a finish not yet said (D-81)',
        );
        expect(
          _payload(announced.single)['state'],
          WatchLifecycleState.completed,
        );
        expect(
          radio.ofType('session_snapshot').last['sessionId'],
          secondId,
          reason: 'S-87 the session the phone moved to is still pushed',
        );
        expect(failures, isEmpty);
      },
    );

    test(
      'S-87 a frame the wrist sends inside the window does not lose the '
      'discard it landed in',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();

        // The phone discards its session and starts another: two notifications
        // inside one debounce window, so the discard is still pending when the
        // frame below lands.
        await phoneState.discardCurrentSession();
        await phoneState.createNewSession();
        final secondId = phoneState.currentSession!.id;

        // The phone is already logging in the new session: a session with no
        // rows of its own is one the projection cannot speak for, and a frame
        // that re-baselines onto it would compose nothing at all.
        await add('ex-squat');

        await engine.appendObservation(<String, Object?>{
          'entryId': _wristEntryId2,
          'eventId': _wristEntryId2,
          'kind': 'set',
          'loggedAt': _atIso(2),
          'sessionExerciseId': _secondSlot,
          'exerciseId': 'ex-bench',
          'reps': 6,
          'loadKg': 45.0,
        });
        await radio.fromWrist(wristFrames.last);
        await _settle();

        // News of the phone's own session, so that the push that follows the
        // discard is a real change and not a no-op.
        await add('ex-row');
        await graph.autoPush.flush();

        final announced = radio.ofType('session_lifecycle');
        expect(
          [for (final frame in announced) frame['sessionId']],
          ['s-1'],
          reason:
              'S-87 a session the phone discarded inside the window is '
              'abandoned once, not lost to the frame that landed in it',
        );
        expect(
          _payload(announced.single)['state'],
          WatchLifecycleState.abandoned,
        );
        expect(
          radio.ofType('session_snapshot').last['sessionId'],
          secondId,
          reason: 'S-87 the session the phone moved to is still pushed',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('S-88 browsing away does not lose a later finish', () {
    test(
      'S-88 browsing a past session and then finishing the live one inside '
      'one window still announces the finish',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();
        final pushesBefore = radio.ofType('session_snapshot').length;

        // A finished session in the phone's history, which the user opens.
        final start = _at(0);
        await repository.createSession(
          TrainingSession(
            id: 'h-1',
            ownerUserId: LoggedEntryRows.ownerUserId,
            startedAtMs: start,
            endedAtMs: start + 60000,
            createdAtMs: start,
            updatedAtMs: start + 60000,
          ),
        );

        // The browse: the phone composes nothing of its own, and the live
        // session's own row is still unended, so nothing is announced — the
        // S-84 shape, which stays silent.
        await phoneState.loadHistoricalSession('h-1');
        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot'),
          hasLength(pushesBefore),
          reason: 'S-88 browsing history sends nothing (S-84)',
        );
        expect(
          radio.ofType('session_lifecycle'),
          isEmpty,
          reason:
              'S-88 a past session the user reads is not an end: the live '
              'session\'s own row is still unended (D-81)',
        );

        // Back to the live session, and finished with no flush in between: the
        // end is decided while the phone composes nothing of its own.
        await phoneState.loadHistoricalSession('s-1');
        await phoneState.endSession();
        await graph.autoPush.flush();

        final ends = radio.ofType('session_lifecycle');
        expect(
          [for (final frame in ends) frame['sessionId']],
          ['s-1'],
          reason:
              'S-88 a running session the phone merely stopped composing while '
              'the user browsed keeps its pending end: finishing it afterwards '
              'is announced once, not lost to the browse (D-81)',
        );
        expect(_payload(ends.single)['state'], WatchLifecycleState.completed);
        expect(failures, isEmpty);
      },
    );
  });

  group('F4 a flush that cannot finish does not disturb the phone', () {
    test(
      'F4 a throwing getSession leaks no async error and the next flush '
      'announces the end',
      () async {
        await wristStartsSession();

        var readable = true;
        final push = WatchSessionAutoPush(
          mirror: graph.mirror,
          getSession: (sessionId) async {
            // A repository read that fails is an `Exception`: an `Error` here
            // would be a programming fault, which the push leaves to surface
            // (G2 — see `G2 an Error from the session read is not swallowed`).
            if (!readable) throw Exception('the repository cannot be read');
            return repository.getSession(sessionId);
          },
        )..bindWorkoutState(phoneState);
        addTearDown(push.dispose);

        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        await push.flush();
        expect(radio.ofType('session_snapshot'), hasLength(1));

        // The session ends while its row cannot be read: the flush must not
        // throw and must not lose the end.
        readable = false;
        await phoneState.endSession();
        await push.flush();
        expect(
          radio.ofType('session_lifecycle'),
          isEmpty,
          reason:
              'F4 a read the phone cannot make sends nothing — and the phone '
              'is undisturbed: the flush returns rather than throwing',
        );

        readable = true;
        await push.flush();
        final ends = radio.ofType('session_lifecycle');
        expect(
          ends,
          hasLength(1),
          reason: 'F4 the next notification still announces the end',
        );
        expect(ends.single['sessionId'], 's-1');
        expect(_payload(ends.single)['state'], WatchLifecycleState.completed);
        expect(failures, isEmpty);
      },
    );

    test('F4 two overlapping flushes announce the end once', () async {
      await wristStartsSession();
      graph.autoPush.bindWorkoutState(phoneState);
      await pushPhoneSet();

      await phoneState.endSession();
      final first = graph.autoPush.flush();
      final second = graph.autoPush.flush();
      await Future.wait(<Future<void>>[first, second]);

      final ends = radio.ofType('session_lifecycle');
      expect(
        ends,
        hasLength(1),
        reason:
            'F4 two flushes that overlap are one drain, so the session is '
            'announced once (D-81)',
      );
      expect(ends.single['sessionId'], 's-1');
      expect(_payload(ends.single)['state'], WatchLifecycleState.completed);
      expect(failures, isEmpty);
    });

    test('G2 an Error from the session read is not swallowed', () async {
      await wristStartsSession();

      final push = WatchSessionAutoPush(
        mirror: graph.mirror,
        getSession: (sessionId) async =>
            throw StateError('the session read is broken'),
      )..bindWorkoutState(phoneState);
      addTearDown(push.dispose);

      await phoneState.addEntry(
        _firstSlot,
        previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
      );

      await expectLater(push.flush(), throwsStateError);
      expect(
        radio.ofType('session_snapshot'),
        isEmpty,
        reason: 'G2 the pass stopped at the fault: nothing was sent for it',
      );
      push.dispose();
    });
  });

  group('S-112 a hung send cannot wedge the push', () {
    test(
      'S-112 a send that never completes is abandoned and reported, and the '
      'change made while it hung still leaves the phone',
      () async {
        await wristStartsSession();

        final reported = <Object>[];
        final push = WatchSessionAutoPush(
          mirror: graph.mirror,
          getSession: repository.getSession,
          // A real, small bound: the pass is abandoned this long after the
          // radio goes silent, well inside the poll deadline below.
          sendTimeout: const Duration(milliseconds: 200),
          onFailure: (error, stack) => reported.add(error),
        )..bindWorkoutState(phoneState);
        addTearDown(push.dispose);

        radio.hangNext = true;
        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        final hung = push.flush();
        await _until(
          () => !radio.hangNext,
          reason: 'S-112 the fixture: the first send was reached and is hung',
        );

        // A second change while that send is still hung: its flush joins the
        // running drain and asks for one more pass, which is the branch a
        // wedged drain used to swallow for the rest of the app run.
        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 65.0},
        );
        final joined = push.flush();
        await _until(
          () => reported.isNotEmpty,
          reason:
              'S-112 the pass that never finishes is abandoned at sendTimeout '
              'and reported, instead of holding the drain open for ever',
        );
        await hung;
        await joined;

        expect(
          reported,
          hasLength(1),
          reason: 'S-112 exactly one failure is reported for the hung pass',
        );
        expect(
          reported.single,
          isA<TimeoutException>(),
          reason: 'S-112 a pass that outran its bound is reported as a timeout',
        );

        final pushes = radio.ofType('session_snapshot');
        expect(
          pushes,
          hasLength(1),
          reason:
              'S-112 the second change left the phone and nothing was queued '
              'or retried for the hung one: the payload that failed is not '
              'attempted twice (D-83: its baseline was already stored)',
        );
        expect(
          [
            for (final entry in _objects(_payload(pushes.single)['entries']))
              entry['loadKg'],
          ],
          contains(65.0),
          reason:
              'S-112 the frame carries the second change — the newest state, '
              'not a replay of the hung one',
        );
      },
    );
  });

  group('S-113 a failure on the push path is reported', () {
    test(
      'S-113 a throwing send is reported once, and the next change still '
      'pushes',
      () async {
        await wristStartsSession();

        final reported = <Object>[];
        final push = WatchSessionAutoPush(
          mirror: graph.mirror,
          getSession: repository.getSession,
          onFailure: (error, stack) => reported.add(error),
        )..bindWorkoutState(phoneState);
        addTearDown(push.dispose);

        radio.throwing = true;
        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        await push.flush();

        expect(
          reported,
          hasLength(1),
          reason:
              'S-113 an Exception the send threw is reported through the hook '
              'rather than swallowed (D-98)',
        );
        expect(reported.single, isA<Exception>());
        expect(radio.ofType('session_snapshot'), isEmpty);

        radio.throwing = false;
        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 65.0},
        );
        await push.flush();

        final pushes = radio.ofType('session_snapshot');
        expect(
          pushes,
          hasLength(1),
          reason:
              'S-113 the push still works on the next change: the send that '
              'threw left nothing queued and nothing wedged (D-83)',
        );
        expect(
          [
            for (final entry in _objects(_payload(pushes.single)['entries']))
              entry['loadKg'],
          ],
          contains(65.0),
          reason: 'S-113 the frame that follows carries the newest state',
        );
        expect(reported, hasLength(1));
      },
    );

    test(
      'S-113 an Error from the debounce timer path is reported, not unhandled, '
      'and a direct flush still throws it',
      () async {
        await wristStartsSession();

        final reported = <Object>[];
        final push = WatchSessionAutoPush(
          mirror: graph.mirror,
          // An `Error` is a programming fault: `_pushOnce` does not catch it, so
          // it escapes `flush()` (G2).
          getSession: (sessionId) async =>
              throw StateError('the session read is broken'),
          debounce: const Duration(milliseconds: 5),
          onFailure: (error, stack) => reported.add(error),
        )..bindWorkoutState(phoneState);
        addTearDown(push.dispose);

        final unhandled = <Object>[];
        final body = runZonedGuarded(() async {
          await phoneState.addEntry(
            _firstSlot,
            previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
          );
          // Either the pass reports it (D-99) or it escapes as an unhandled
          // async error: waiting for either is what keeps a regression from
          // hanging this test instead of failing it.
          await _until(
            () => reported.isNotEmpty || unhandled.isNotEmpty,
            reason:
                'S-113 an Error escaping the debounce timer\'s flush is '
                'either reported through the hook (D-99) or unhandled — it '
                'never simply disappears',
          );

          // The direct caller is still told: the timer path swallows nothing
          // that a non-timer caller would have seen (G2).
          await expectLater(push.flush(), throwsStateError);
        }, (error, stack) => unhandled.add(error));
        await body;

        expect(
          reported,
          hasLength(1),
          reason:
              'S-113 the timer path reports what escapes a pass through the '
              'hook instead of raising an unhandled async error (D-99)',
        );
        expect(reported.single, isA<StateError>());
        expect(
          unhandled,
          isEmpty,
          reason:
              'S-113 the timer path raises no unhandled async error: it is '
              'recorded through the hook instead (D-99)',
        );
      },
    );
  });

  group('S-120 a set deleted on the phone disappears on the wrist', () {
    test(
      'S-120 the push names the set the phone dropped, in a frame the wrist '
      'applies, before the snapshot that no longer carries it',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);

        final first = await pushPhoneSet();
        await engine.applyMessage(first);
        final doomed = await logSetHeldByBoth();
        expect(
          wristEntryIds(),
          containsAll(<String>[_wristEntryId, 'entry-$_firstSlot-1', doomed]),
          reason: 'the fixture: the wrist holds both of the phone\'s sets',
        );

        await phoneState.deleteEntry(_firstSlot, 2);
        await graph.autoPush.flush();

        final deletions = radio.ofType('structure_change');
        expect(
          deletions,
          hasLength(1),
          reason:
              'S-120 one frame per set that vanished, and none for the sets '
              'that did not',
        );
        final deletion = deletions.single;
        final snapshot = radio.ofType('session_snapshot').last;
        expect(
          radio.sent.indexOf(deletion),
          lessThan(radio.sent.indexOf(snapshot)),
          reason:
              'D-111 the deletion goes out before the snapshot of the same '
              'pass, so a set the phone re-created under a reused id ends up '
              'visible rather than deleted',
        );
        expect(
          deletion['sessionId'],
          's-1',
          reason:
              'D-114 the frame names the session both devices hold: the wrist '
              'refuses a frame naming any other',
        );
        expect(
          _payload(deletion)['changeId'],
          startsWith('del-$doomed-'),
          reason:
              'D-116 (F2) the id names the entry *and* the delete event, so a '
              're-delivery of this frame is a no-op on the wrist while the '
              'second deletion of a number the phone re-used is not',
        );
        expect(
          _payload(deletion)['changes'],
          [
            {'kind': 'delete_entry', 'entryId': doomed},
          ],
          reason: 'S-120 the frame names the set the phone dropped (D-110)',
        );
        expect(
          _entryIds(_payload(snapshot)),
          ['entry-$_firstSlot-1'],
          reason:
              'S-120 the snapshot that follows carries the survivors only — '
              'and never the set the wrist logged itself (D-34)',
        );

        await engine.applyMessage(deletion);
        expect(
          _sorted(wristEntryIds()),
          _sorted(<String>[_wristEntryId, 'entry-$_firstSlot-1']),
          reason:
              'S-120 the wrist hides the set the frame named, so a set the '
              'phone dropped leaves the ladder it was logged against',
        );
        expect(
          [
            for (final row in engine.observations) row.payload['entryId'],
          ],
          contains(doomed),
          reason:
              'I-3 the wrist\'s log is append-only: the row the entry was '
              'projected from is still stored, only hidden',
        );
      },
    );
  });

  group('S-121 several deletions, and a deletion that never was', () {
    test(
      'S-121 two sets dropped in one pass are two frames in ascending id '
      'order, and the snapshot carries the survivors',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);

        await pushPhoneSet();
        final second = await logSetHeldByBoth();
        final third = await logSetHeldByBoth();
        final fourth = await logSetHeldByBoth();
        expect(
          _sorted(<String>[second, third, fourth]),
          _sorted(<String>[
            'entry-$_firstSlot-2',
            'entry-$_firstSlot-3',
            'entry-$_firstSlot-4',
          ]),
          reason:
              'the fixture: the phone numbers its own sets above every row the '
              'effort holds (D-325)',
        );

        // The later entry goes first: the phone's own set 4 is addressed by
        // number, so dropping it does not renumber the survivors.
        await phoneState.deleteEntry(_firstSlot, 4);
        await phoneState.deleteEntry(_firstSlot, 2);
        await graph.autoPush.flush();

        final deletions = radio.ofType('structure_change');
        expect(
          deletions,
          hasLength(2),
          reason: 'S-121 one frame per set that vanished',
        );
        expect(
          [
            for (final frame in deletions) _payload(frame)['changeId'],
          ],
          [startsWith('del-$second-'), startsWith('del-$fourth-')],
          reason:
              'S-121 the frames go out in ascending id order, so the same two '
              'deletions look the same however the store listed the rows',
        );
        expect(
          [
            for (final frame in deletions) _payload(frame)['changes'],
          ],
          [
            [
              {'kind': 'delete_entry', 'entryId': second},
            ],
            [
              {'kind': 'delete_entry', 'entryId': fourth},
            ],
          ],
          reason: 'S-121 each frame names exactly the set it is about',
        );
        expect(
          _sorted(
            _entryIds(_payload(radio.ofType('session_snapshot').last)),
          ),
          _sorted(<String>['entry-$_firstSlot-1', third]),
          reason: 'S-121 the snapshot of that pass carries the two survivors',
        );
      },
    );

    test(
      'S-121 a set logged and dropped inside one window is announced to nobody',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();

        // Both changes land inside one debounce window: the set the user
        // dropped never left the phone, so the wrist was never told to hold it.
        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        await phoneState.deleteEntry(_firstSlot, 3);
        await graph.autoPush.flush();

        expect(
          radio.ofType('structure_change'),
          isEmpty,
          reason:
              'S-121 an id the phone never announced cannot vanish: the '
              'ledger is what the wrist was told, not what the phone holds '
              '(D-111)',
        );
        expect(
          _sorted(
            _entryIds(_payload(radio.ofType('session_snapshot').last)),
          ),
          _sorted(<String>['entry-$_firstSlot-1', 'entry-$_firstSlot-2']),
          reason: 'S-121 the snapshot carries the sets the phone kept',
        );
      },
    );
  });

  group('S-122 a set the wrist logged, imported and deleted on the phone', () {
    test(
      'S-122 the frame names the wrist\'s own entry id, so the entry the wrist '
      'logged leaves it too',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await engine.applyMessage(await pushPhoneSet());
        expect(
          wristEntryIds(),
          containsAll(<String>[_wristEntryId, 'entry-$_firstSlot-1']),
          reason:
              'the fixture: the wrist holds the set it logged and the set the '
              'phone logged',
        );

        // The slot's first group is the row the phone imported from the wrist
        // (D-34), so entry 0 is the set the user sees as the wrist's.
        await phoneState.deleteEntry(_firstSlot, 0);
        await graph.autoPush.flush();

        final deletion = radio.ofType('structure_change').single;
        expect(
          _payload(deletion)['changes'],
          [
            {'kind': 'delete_entry', 'entryId': _wristEntryId},
          ],
          reason:
              'S-122 the frame names the wrist\'s own row id — the id the '
              'phone\'s inbox row carries — and not a phone-minted one (D-112)',
        );
        expect(
          _payload(deletion)['changeId'],
          startsWith('del-$_wristEntryId-'),
          reason: 'D-116 the id names the entry the deletion is about',
        );
        expect(
          await phoneEntries(_firstSlot),
          1,
          reason:
              'S-122 the phone\'s group stays deleted: only the phone\'s own '
              'set is left on the slot',
        );

        await engine.applyMessage(deletion);
        expect(
          wristEntryIds(),
          isNot(contains(_wristEntryId)),
          reason:
              'S-122 the wrist hides the set it logged itself when the phone '
              'deleted it (TRAP 1)',
        );
        expect(wristEntryIds(), contains('entry-$_firstSlot-1'));
        expect(
          [
            for (final row in engine.observations) row.payload['entryId'],
          ],
          contains(_wristEntryId),
          reason:
              'I-3 the wrist\'s own row is hidden, never deleted from the '
              'append-only log',
        );
      },
    );
  });

  group('S-123 the first pass announces nothing', () {
    test(
      'S-123 a push that binds to a session the wrist already holds seeds its '
      'ledger and announces no deletion',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();
        final second = await logSetHeldByBoth();
        final third = await logSetHeldByBoth();
        expect(
          wristEntryIds(),
          containsAll(<String>[_wristEntryId, 'entry-$_firstSlot-1', second, third]),
          reason:
              'the fixture: the wrist has held all three sets since before the '
              'push below existed, the way it has after a re-launch',
        );

        final rebound = WatchSessionAutoPush(
          mirror: graph.mirror,
          getSession: repository.getSession,
        )..bindWorkoutState(phoneState);
        addTearDown(rebound.dispose);

        await rebound.flush();

        expect(
          radio.ofType('structure_change'),
          isEmpty,
          reason:
              'S-123 the first pass of a session seeds the ledger from what '
              'the phone holds: announcing the difference against an empty '
              'set would order the wrist to delete everything it holds',
        );
        expect(
          _sorted(
            _entryIds(_payload(radio.ofType('session_snapshot').last)),
          ),
          _sorted(<String>['entry-$_firstSlot-1', second, third]),
          reason:
              'S-123 the first pass is otherwise the snapshot the push always '
              'sent (D-76)',
        );
      },
    );
  });

  group('S-126 another session\'s deletion changes nothing', () {
    test(
      'S-126 a delete frame naming a session the wrist is not running is '
      'refused whole, twice',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await engine.applyMessage(await pushPhoneSet());
        expect(
          wristEntryIds(),
          containsAll(<String>[_wristEntryId, 'entry-$_firstSlot-1']),
          reason: 'the fixture: the wrist holds two sets of its session',
        );

        // What a phone whose mirror holds another session sends: the same
        // envelope builder the mirror uses, naming the session it holds.
        final foreign = phoneEnvelope(
          type: 'structure_change',
          messageId: 'msg-other-session',
          sentAt: _now,
          sessionId: 'sess-b',
          payload: {
            'changeId': 'chg-other-session',
            'changes': [
              {'kind': 'delete_entry', 'entryId': 'entry-$_firstSlot-1'},
            ],
          },
        );
        final before = await wristRows();

        expect(
          await engine.applyMessage(foreign),
          isFalse,
          reason:
              'S-126 the wrist\'s session guard refuses a frame naming another '
              'session (D-79)',
        );
        expect(
          await engine.applyMessage(foreign),
          isFalse,
          reason: 'S-126 the same refusal again, with nothing applied either time',
        );
        expect(
          _sorted(wristEntryIds()),
          _sorted(<String>[_wristEntryId, 'entry-$_firstSlot-1']),
          reason: 'S-126 a foreign session\'s deletion leaves the ladder alone',
        );
        expect(
          await wristRows(),
          before,
          reason:
              'S-126 no row is appended for a foreign session, so the store '
              'does not accumulate copies of a change it refuses',
        );
      },
    );
  });

  group('D-114 leaving a session and coming back re-seeds the ledger', () {
    test(
      'D-114 the session the phone comes back to seeds its ledger again, so '
      'the set it lost in between is not announced by the return pass',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await engine.applyMessage(await pushPhoneSet());
        final doomed = await logSetHeldByBoth();
        await graph.autoPush.flush();
        expect(
          wristEntryIds(),
          containsAll(<String>[_wristEntryId, 'entry-$_firstSlot-1', doomed]),
          reason:
              'the fixture: the wrist holds the set it logged and the phone\'s '
              'two, which is what the push\'s ledger records for `s-1`',
        );

        // The user drops the phone's second set and starts a session of their
        // own, both inside one window and both started in this turn, so no pass
        // composes `s-1` between the two: the set is gone from `s-1` before any
        // pass of `s-1` sees it go (D-114, D-111's 250 ms window).
        final dropping = phoneState.deleteEntry(_firstSlot, 2);
        final switching = phoneState.createNewSession();
        await dropping;
        await switching;
        final other = await add('ex-bench');
        await phoneState.addEntry(other);
        await graph.autoPush.flush();

        expect(
          radio.ofType('session_snapshot').last['sessionId'],
          isNot('s-1'),
          reason:
              'the fixture: the window the switch closed composed the phone\'s '
              'new session',
        );
        expect(
          radio.ofType('structure_change'),
          isEmpty,
          reason:
              'the fixture: nobody announced the dropped set, because no pass '
              'of `s-1` ran between the deletion and the switch',
        );

        // Back to the session the wrist is running, which no longer holds one
        // of the phone's sets.
        await phoneState.loadHistoricalSession('s-1');
        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot').last['sessionId'],
          's-1',
          reason: 'the fixture: the pass after the browse composed `s-1` again',
        );

        expect(
          radio.ofType('structure_change'),
          isEmpty,
          reason:
              'D-114 the ledger is dropped on every pass but the composed '
              'session\'s, so a phone that leaves `s-1` and comes back seeds '
              'again from what it holds now instead of comparing `s-1` against '
              'the ids it announced before the switch: the first pass of the '
              'returned session announces nothing, and in particular no '
              'deletion for the set that stopped being held in between',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('F2 a deletion is announced per delete event, not per entry', () {
    test(
      'F2 a number the phone re-used and dropped again is announced again, '
      'under a change id the wrist has not applied',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await pushPhoneSet();
        await logSetHeldByBoth();
        final doomed = await logSetHeldByBoth();
        expect(
          doomed,
          'entry-$_firstSlot-3',
          reason: 'the fixture: the phone numbered its third set 3 (D-325)',
        );

        // The user drops that set: the frame goes out and the wrist hides it.
        await phoneState.deleteEntry(_firstSlot, 3);
        await graph.autoPush.flush();
        final first = radio.ofType('structure_change').single;
        await engine.applyMessage(first);
        expect(
          wristEntryIds(),
          isNot(contains(doomed)),
          reason: 'the fixture: the wrist hid the set the phone dropped',
        );

        // The phone logs another set, which its mint numbers 3 again, and the
        // wrist applies the snapshot carrying it: the id the lens hides is
        // stated again with a later stamp, which is the wrist's own rule for a
        // re-created row (D-113.3).
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await phoneState.addEntry(
          _firstSlot,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        await graph.autoPush.flush();
        await engine.applyMessage(radio.ofType('session_snapshot').last);
        expect(
          wristEntryIds(),
          contains(doomed),
          reason:
              'the fixture: the row the phone re-created under number 3 is '
              'visible on the wrist again',
        );

        // Dropping it is a second deletion *event*, of a number the phone has
        // already announced once (F2).
        await phoneState.deleteEntry(_firstSlot, 3);
        await graph.autoPush.flush();
        final second = radio.ofType('structure_change').last;
        expect(
          _payload(second)['changeId'],
          isNot(_payload(first)['changeId']),
          reason:
              'F2 two deletion events are two change ids: the wrist drops a '
              'change id it has already applied, durably, so an id derived '
              'from the entry alone would have it swallow the second deletion '
              'of a number the phone re-used',
        );
        expect(
          _payload(second)['changeId'],
          startsWith('del-$doomed-'),
          reason: 'F2 the id still names the entry the event is about',
        );

        await engine.applyMessage(second);
        expect(
          wristEntryIds(),
          isNot(contains(doomed)),
          reason:
              'F2 the wrist hides the set the second event names: the frame is '
              'not deduped against the one it already applied',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('F3 a deletion frame names the session it is about', () {
    test(
      'F3 a deletion of the phone\'s own session neither names nor moves the '
      'wrist\'s session, which the phone never held',
      () async {
        // The phone starts a session of its own — Y — which is what the push
        // composes.
        await phoneState.createNewSession();
        final own = await add('ex-squat');
        final ownSessionId = phoneState.currentSession!.id;

        // The wrist is running a session of its own — X — which the phone has
        // no row for: the mirror takes it (S-86) and refuses to adopt it
        // (D-10).
        await engine.createSession(
          modality: null,
          exercises: [
            _slot(_firstSlot, 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
          ],
        );
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();
        expect(
          graph.mirror.sessionId,
          's-1',
          reason: 'the fixture: the mirror took the wrist\'s own session',
        );

        graph.autoPush.bindWorkoutState(phoneState);
        await phoneState.addEntry(
          own,
          previousValues: <String, dynamic>{'reps': 8, 'weight': 62.5},
        );
        await graph.autoPush.flush();
        expect(
          radio.ofType('session_snapshot').last['sessionId'],
          ownSessionId,
          reason: 'the fixture: the push composes the phone\'s own session',
        );
        expect(
          graph.mirror.sessionId,
          's-1',
          reason:
              'the fixture: the mirror still holds the wrist\'s session, and '
              'the phone\'s is the one the payload names',
        );
        final before = graph.mirror.state;
        final beforeIds = _entryIds(
          _payload(radio.ofType('session_snapshot').last),
        );
        expect(
          beforeIds,
          hasLength(2),
          reason: 'the fixture: the phone\'s own session holds its two sets',
        );

        await phoneState.deleteEntry(own, 0);
        await graph.autoPush.flush();

        // The set the phone dropped, read off the pass that followed it: the
        // deletion and the snapshot of the same pass go out together (D-111).
        final afterIds = _entryIds(
          _payload(radio.ofType('session_snapshot').last),
        );
        final dropped = beforeIds.firstWhere(
          (entryId) => !afterIds.contains(entryId),
          orElse: () => fail('the fixture: the phone dropped no set'),
        );

        final deletion = radio.ofType('structure_change').single;
        expect(
          deletion['sessionId'],
          ownSessionId,
          reason:
              'F3 the frame names the session the deletion is about — the one '
              'the pass composed — and not the session the mirror happens to '
              'hold: the wrist refuses a frame naming any other session, so '
              'this deletion would be invisible to the user',
        );
        expect(
          _payload(deletion)['changes'],
          [
            {'kind': 'delete_entry', 'entryId': dropped},
          ],
          reason: 'F3 the frame still names the set the phone dropped',
        );
        expect(
          graph.mirror.state,
          before,
          reason:
              'F3 a deletion of the phone\'s session never moves the mirror\'s '
              'state for the wrist\'s: applying it locally would hide an entry '
              'of a session the frame does not name',
        );
        expect(failures, isEmpty);
      },
    );
  });

  group('F7 a deletion whose send failed is owed, not lost', () {
    test(
      'F7 the next pass announces the deletion the failed one could not, under '
      'the change id it was minted with',
      () async {
        await wristStartsSession();
        graph.autoPush.bindWorkoutState(phoneState);
        await engine.applyMessage(await pushPhoneSet());
        final doomed = await logSetHeldByBoth();

        // The frame the deletion owes never leaves the phone: the transport
        // fails the future rather than reporting it (S-113's seam).
        radio.throwing = true;
        await phoneState.deleteEntry(_firstSlot, 2);
        await graph.autoPush.flush();
        expect(
          failures,
          hasLength(1),
          reason: 'F7 the failed pass is reported, once (D-98)',
        );
        expect(
          radio.ofType('structure_change'),
          isEmpty,
          reason: 'F7 the transport carried no deletion frame',
        );
        final attempted = [
          for (final frame in radio.attempted)
            if (frame['type'] == 'structure_change') frame,
        ];
        expect(
          attempted,
          hasLength(1),
          reason: 'F7 the pass did try to announce the deletion it owed',
        );

        // The radio comes back. The deletion is still owed, and it is the same
        // change: a new id would be a second change for the one deletion.
        radio.throwing = false;
        await graph.autoPush.flush();
        final retried = radio.ofType('structure_change');
        expect(
          retried,
          hasLength(1),
          reason:
              'F7 a deletion stays owed until its frame has gone: the ledger of '
              'what the wrist was told is never updated by a send that failed',
        );
        expect(
          _payload(retried.single)['changeId'],
          _payload(attempted.single)['changeId'],
          reason: 'F7 the owed event keeps the change id it was minted with',
        );
        expect(failures, hasLength(1), reason: 'the retry did not fail');

        await engine.applyMessage(retried.single);
        expect(
          wristEntryIds(),
          isNot(contains(doomed)),
          reason: 'F7 the retried frame hides the set the phone dropped',
        );

        // It has gone: no later pass announces it again.
        await graph.autoPush.flush();
        expect(
          radio.ofType('structure_change'),
          hasLength(1),
          reason: 'F7 an announced deletion is not announced again',
        );
        expect(failures, hasLength(1));
      },
    );
  });
}
