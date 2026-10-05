// A phone session surfaces on the wrist at the next watch-initiated sync.
//
// Plan: `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/`.
// Scenario mapping:
//   S-2 a phone session surfaces at a watch-initiated sync → `S-2 ...`
//   S-8 phone edits reach the wrist at sync               → `S-8 ...`
//   S-6/D-10 a session this phone is not in stays untouched → `S-6 ...`
//   D-11 on-demand projection, never cached                → `D-11 ...`
//
// The phone side is the graph `createWatchSync` builds, over a fake radio: the
// answer's shape, its revision and where it comes from are the shipping code's.
// The wrist side is the real engine over an in-memory store, so every answer is
// applied the way the watch app applies one.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
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

/// One ladder slot as the protocol spells it — what a wrist writes when it
/// starts a session on its own (S-1's fixture, S-8's hand-over).
Map<String, Object?> _slot(
  String id,
  String exerciseId,
  String name,
  List<String> capabilities, {
  String? effortKind,
}) => <String, Object?>{
  'sessionExerciseId': id,
  'exerciseId': exerciseId,
  'name': name,
  'effortKind': ?effortKind,
  'capabilities': capabilities,
};

/// Lets the radio's dispatch settle before the next frame is handed over.
Future<void> _settle() => pumpEventQueue();

/// A catalog the phone can open a session from. `ex-nothing` is a custom
/// exercise from before capabilities were recorded.
Future<void> _seedCatalog(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: 'ex-bench',
    name: 'Bench Press',
    capabilities: ['sets', 'reps', 'load'],
  );
  await seedExercise(
    repository,
    id: 'ex-squat',
    name: 'Squat',
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
    id: 'ex-plank',
    name: 'Plank',
    capabilities: ['time', 'hold'],
  );
  await seedExercise(
    repository,
    id: 'ex-nothing',
    name: 'Mystery',
    capabilities: [],
  );
}

/// The phone's radio: records what the phone sent, and hands the phone one
/// frame from the wrist the way the platform channel does.
class _PhoneRadio implements WatchTransport {
  final List<Map<String, Object?>> sent = [];

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
  Future<void> send(Map<String, Object?> envelope) async => sent.add(envelope);

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

  /// The one frame of [type] the phone sent.
  Map<String, Object?> lastOfType(String type) => ofType(type).last;
}

void main() {
  late MockWorkoutRepository repository;
  late WorkoutState phoneState;
  late SettingsState phoneSettings;
  late _PhoneRadio radio;
  late WatchSyncGraph graph;
  late WatchSessionEngine engine;
  late Object? reportedFailure;
  late List<({String held, String offered})> skipped;

  /// Adds one catalog exercise to the phone's running session through the
  /// regular session path, and answers the effort id it was given — which is
  /// also the slot id the wrist sees (D-3).
  Future<String> add(String exerciseId, {String? effortKindOverride}) async {
    final exercise = (await repository.getExerciseById(exerciseId))!;
    return phoneState.addExerciseToSession(
      exercise,
      effortKindOverride: effortKindOverride,
    );
  }

  /// The phone graph a fresh app start builds, over [radio], with [bind] as the
  /// session state it projects from — the app binds its own in `lib/main.dart`,
  /// which is how a graph with no state (the transport tests) answers from the
  /// mirror's copy instead.
  Future<WatchSyncGraph> startGraph(
    _PhoneRadio radio, {
    WorkoutState? bind,
  }) async {
    final created = (await createWatchSync(
      repository: repository,
      nutritionState: NutritionState(repository),
      foodLibraryState: FoodLibraryState(repository),
      settingsState: phoneSettings,
      transport: radio,
      clock: () => _now,
      onFailure: (error, stack) => reportedFailure = error,
      onSkipped: (held, offered) => skipped.add((held: held, offered: offered)),
    ))!;
    created.adoption.bindWorkoutState(bind ?? phoneState);
    return created;
  }

  /// What the wrist holds as its ladder, in order.
  List<String> wristSlots() => [
    for (final slot in engine.session!.exercises)
      slot['sessionExerciseId']! as String,
  ];

  /// The phone's ladder as slot ids, in order. A slot the projection would drop
  /// — an effort whose exercise is unknown or carries no capability — shows up
  /// here, so callers compare it against a ladder that has none of those.
  List<String> phoneSlots() => [
    for (final segment in phoneState.segments)
      for (final effort in phoneState.getEffortsForSegment(segment.id))
        effort.id,
  ];

  /// S-8's fixture at the point both cases start from: the wrist starts `s-w1`
  /// with two slots, the phone adopts that session at the hand-over (S-1), the
  /// wrist moves to its second slot, and the phone adds a third exercise through
  /// the regular session path. Answers the added slot's id.
  Future<String> s8Setup() async {
    await engine.createSession(
      modality: null,
      exercises: [
        _slot('sl-1', 'ex-bench', 'Bench Press', ['sets', 'reps', 'load']),
        _slot('sl-2', 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
      ],
    );
    final wristSessionId = engine.session!.sessionId;

    await radio.fromWrist(engine.sessionSnapshot()!);
    await _settle();

    expect(
      phoneState.currentSession?.id,
      wristSessionId,
      reason: 'S-1 the phone\'s own session is the one the wrist is running',
    );
    expect(
      phoneSlots(),
      ['sl-1', 'sl-2'],
      reason: 'D-3 an adopted effort\'s row id IS its slot id',
    );

    await engine.advanceExercise();
    expect(
      engine.session!.currentExercise!['sessionExerciseId'],
      'sl-2',
      reason: 'the wrist is on the slot the phone is about to edit',
    );

    return add('ex-deadlift');
  }

  setUp(() async {
    reportedFailure = null;
    skipped = [];
    repository = MockWorkoutRepository();
    await repository.initialize();
    await _seedCatalog(repository);

    phoneState = WorkoutState(repository);
    phoneSettings = SettingsState(repository, fakePreferencesService());
    await phoneSettings.initialize();

    radio = _PhoneRadio();
    graph = await startGraph(radio);

    engine = WatchSessionEngine(
      InMemoryWatchSessionStore(),
      clock: () => _now,
    );
  });

  group('S-2 the phone answers a sync with the session it holds', () {
    test(
      'S-2 a running phone session is answered with its own ladder',
      () async {
        await phoneState.createNewSession(modality: null);
        final bench = await add('ex-bench');
        await add('ex-nothing');
        final plank = await add('ex-plank', effortKindOverride: 'timed');
        final squat = await add('ex-squat', effortKindOverride: 'amrap');

        await radio.fromWrist(WatchTransportRequest.snapshotFrame());
        await _settle();

        final answer = radio.lastOfType('session_snapshot');
        expect(answer['origin'], 'phone');
        final payload = _payload(answer);
        expect(payload['sessionId'], phoneState.currentSession!.id);
        expect(payload['status'], 'active');
        expect(payload['revision'], greaterThan(0));
        expect(
          _slotIds(payload),
          [bench, plank, squat],
          reason:
              'S-2 the ladder is the phone\'s own, in its own order, and an '
              'exercise carrying no capability is not a slot the wrist can hold',
        );
        expect(
          [
            for (final slot in _objects(payload['exercises'])) slot['exerciseId'],
          ],
          ['ex-bench', 'ex-plank', 'ex-squat'],
        );
        expect(
          [for (final slot in _objects(payload['exercises'])) slot['name']],
          ['Bench Press', 'Plank', 'Squat'],
        );
        expect(
          _objects(payload['exercises']).first['capabilities'],
          ['sets', 'reps', 'load'],
        );
        expect(_objects(payload['exercises']).first['effortKind'], 'set');
        expect(_objects(payload['exercises'])[1]['effortKind'], 'timed');
        expect(
          _objects(payload['exercises'])[2].containsKey('effortKind'),
          isFalse,
          reason:
              'an effort kind outside the wire vocabulary is left for the '
              'wrist to derive from the capabilities',
        );
        expect(
          payload['currentExerciseIndex'],
          0,
          reason:
              'a sessionless wrist asks with no position of its own, and a '
              'phone session opens on its first slot',
        );
        expect(payload['entries'], isEmpty);
        expect(payload['timers'], isEmpty);
        expect(reportedFailure, isNull);
      },
    );

    test('S-2 an idle phone still answers with silence', () async {
      await phoneState.createNewSession(modality: null);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();

      expect(
        radio.sent,
        isEmpty,
        reason:
            'a session with no exercise is not yet active (D-6), and an '
            'empty ladder is not a state to send',
      );
      expect(reportedFailure, isNull);
    });
  });

  group('S-8 phone edits reach the wrist at the next sync', () {
    test(
      'S-8 case A an added exercise is answered with the extended ladder',
      () async {
        final deadlift = await s8Setup();
        final held = _payload(engine.sessionSnapshot()!)['revision']! as int;

        // The wrist taps Sync and hands over the ladder it holds.
        radio.sent.clear();
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();

        final answer = radio.lastOfType('session_snapshot');
        final payload = _payload(answer);
        expect(
          _slotIds(payload),
          ['sl-1', 'sl-2', deadlift],
          reason:
              'S-8 case A the whole ladder is composed from the phone\'s own '
              'session at the moment of the sync',
        );
        expect(
          payload['revision'],
          greaterThan(held),
          reason:
              'S-8 case A the revision rises with the ladder, so the wrist\'s '
              'replace-structure rule accepts the answer',
        );
        expect(
          payload['currentExerciseIndex'],
          1,
          reason: 'the wrist keeps the place it reports it is on',
        );

        expect(await engine.applyMessage(answer), isTrue);
        expect(wristSlots(), ['sl-1', 'sl-2', deadlift]);
        expect(engine.session!.currentExercise!['sessionExerciseId'], 'sl-2');

        // Agreeing peers stay silent: the wrist now holds what the phone holds,
        // so handing its snapshot over again is answered with nothing.
        radio.sent.clear();
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();
        expect(
          radio.ofType('session_snapshot'),
          isEmpty,
          reason:
              'S-8 case A replaying the wrist\'s snapshot produces no second '
              'answer',
        );
        expect(reportedFailure, isNull);
      },
    );

    test(
      'S-8 case B removing the exercise the wrist is on moves its position',
      () async {
        final deadlift = await s8Setup();

        // Case A's answer, applied, so the wrist holds the three-slot ladder
        // case B's fixture names.
        radio.sent.clear();
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();
        expect(
          await engine.applyMessage(radio.lastOfType('session_snapshot')),
          isTrue,
        );
        expect(wristSlots(), ['sl-1', 'sl-2', deadlift]);

        // One set logged on the slot the phone is about to remove.
        await engine.appendObservation({
          'entryId': 'entry-on-squat',
          'eventId': 'entry-on-squat',
          'kind': 'set',
          'loggedAt': '2026-10-06T09:05:00.000Z',
          'sessionExerciseId': 'sl-2',
          'exerciseId': 'ex-squat',
          'reps': 5,
          'loadKg': 80,
        });
        final held = _payload(engine.sessionSnapshot()!)['revision']! as int;

        // The phone removes the exercise the wrist is on.
        await phoneState.removeExerciseFromSession('sl-2');
        expect(
          phoneState.getEffortsForSegment(phoneState.segments.single.id),
          hasLength(2),
          reason: 'the regular session path removed the effort',
        );

        // The wrist taps Sync and hands over the ladder it held.
        radio.sent.clear();
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();

        final answer = radio.lastOfType('session_snapshot');
        final payload = _payload(answer);
        expect(_slotIds(payload), ['sl-1', deadlift]);
        expect(
          payload['revision'],
          greaterThan(held),
          reason: 'the removed slot is a ladder change like any other',
        );
        expect(
          payload['currentExerciseIndex'],
          1,
          reason: 'the position the wrist reported is inside the shorter ladder',
        );

        expect(await engine.applyMessage(answer), isTrue);
        expect(wristSlots(), ['sl-1', deadlift]);
        expect(
          engine.session!.currentExerciseIndex,
          1,
          reason:
              'S-8 case B the position moves the way '
              '`fixtures/reconciliation/remove_current_exercise.json` pins it',
        );
        expect(
          engine.session!.currentExercise!['sessionExerciseId'],
          deadlift,
          reason: 'index 1 now holds the exercise that followed the removed slot',
        );
        expect(
          [for (final entry in engine.entries) entry.entryId],
          contains('entry-on-squat'),
          reason: 'S-8 case B the removed slot\'s logged entries are not lost',
        );
        expect(reportedFailure, isNull);
      },
    );
  });

  group('D-10 the phone never asserts a session it is not in', () {
    test('S-6 a wrist session this phone is not in is left alone', () async {
      await phoneState.createNewSession(modality: null);
      final bench = await add('ex-bench');
      final phoneSessionId = phoneState.currentSession!.id;

      await engine.createSession(
        modality: null,
        exercises: [
          _slot('wl-1', 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
          _slot('wl-2', 'ex-plank', 'Plank', ['time', 'hold']),
        ],
      );
      final wristSessionId = engine.session!.sessionId;

      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();

      expect(
        skipped,
        [(held: phoneSessionId, offered: wristSessionId)],
        reason: 'S-6 the skipped adoption is reported with both session ids',
      );
      expect(
        reportedFailure,
        isNull,
        reason:
            'S-6 refusing is the rule working: the skip is not a failure and '
            'carries no stack',
      );
      expect(
        phoneState.currentSession!.id,
        phoneSessionId,
        reason: 'S-6 the phone keeps the session it is working through',
      );
      expect(phoneSlots(), [bench]);
      expect(
        await repository.getSession(wristSessionId),
        isNull,
        reason: 'S-6 nothing is created for a session the phone did not adopt',
      );
      expect(
        _slotIds(graph.mirror.state),
        ['wl-1', 'wl-2'],
        reason: 'the switch is the mirror\'s business (protocol MUST rule)',
      );

      // The wrist taps Sync again. The phone holds no ladder for the session
      // the wrist is running, so it has none of its own to assert: the wrist's
      // own ladder comes back, and agreeing peers stay silent.
      radio.sent.clear();
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();

      expect(
        radio.ofType('session_snapshot'),
        isEmpty,
        reason: 'S-6 the wrist snapshot is not answered with another session',
      );
      expect(engine.session!.sessionId, wristSessionId);
      expect(wristSlots(), ['wl-1', 'wl-2']);
      expect(phoneState.currentSession!.id, phoneSessionId);
      expect(phoneSlots(), [bench]);
      expect(
        skipped,
        hasLength(1),
        reason: 'S-6 the same pair, sent twice, is reported once',
      );
    });
  });

  group('D-11 the projection is composed on demand', () {
    test('D-11 the revision rises with the ladder, and only with it', () async {
      await phoneState.createNewSession(modality: null);
      final bench = await add('ex-bench');

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final first = _payload(radio.lastOfType('session_snapshot'));
      expect(_slotIds(first), [bench]);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final repeat = _payload(radio.lastOfType('session_snapshot'));
      expect(
        repeat['revision'],
        first['revision'],
        reason:
            'an unchanged ladder states the revision it already stated, so a '
            'wrist that converged is not told the shape moved',
      );

      final squat = await add('ex-squat');
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();

      final extended = _payload(radio.lastOfType('session_snapshot'));
      expect(
        _slotIds(extended),
        [bench, squat],
        reason:
            'D-11 never a cached copy: the answer is the ladder the phone holds '
            'when it is asked',
      );
      expect(
        extended['revision'],
        greaterThan(first['revision']! as int),
        reason: 'D-11 a changed ladder is newer than anything the wrist holds',
      );
      expect(extended['currentExerciseIndex'], 0);
    });
  });
}
