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
//
// The phone side is the graph `createWatchSync` builds — the shipping wiring,
// including the push it returns — over a fake radio; the wrist side is the real
// engine over an in-memory store, so every pushed frame is applied the way the
// watch app applies one. The push is bound where a scenario starts from a
// settled fixture, so the fixture's own notifications are not part of the
// scenario, and every window is closed by `flush()` rather than by waiting.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
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

  /// True while the wrist is out of range: `send` reports and carries nothing.
  bool failing = false;

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
    if (failing) {
      onFailure(StateError('the wrist is out of range'));
      return;
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
}
