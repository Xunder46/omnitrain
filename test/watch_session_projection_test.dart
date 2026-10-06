// A phone session surfaces on the wrist at the next watch-initiated sync.
//
// Plan: `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/` (S-2, S-6, S-8,
// D-10, D-11) and `docs/plans/2026-10-05-15d-watch-session-sync-pr3-plan/` (the
// phone's own sets ride the answer: S-31, S-32, S-33, S-34, S-36, S-37, S-38,
// S-39, S-40, S-42).
// Scenario mapping:
//   S-2 a phone session surfaces at a watch-initiated sync → `S-2 ...`
//   S-8 phone edits reach the wrist at sync               → `S-8 ...`
//   S-6/D-10 a session this phone is not in stays untouched → `S-6 ...`
//   D-11 on-demand projection, never cached                → `D-11 ...`
//   S-31 the phone's own sets arrive as entries           → `S-31 ...`
//   S-32 the same answer twice doubles nothing            → `S-32 ...`
//   S-33/S-34 provenance: the wrist's own set is not sent back → `S-33 ...`
//   S-36 a ladder with nothing logged answers with no entries → `S-36 ...`
//   S-37 a phone entry counts like the wrist's own        → `S-37 ...`
//   S-38 the wrist adopts a session it does not hold      → `S-38 ...`
//   S-39 the projection is deterministic, and does not echo → `S-39 ...`
//   S-40 two sessions do not share entries                → `S-40 ...`
//   S-42 an entry the wire cannot carry is omitted        → `S-42 ...`
//
// The phone side is the graph `createWatchSync` builds, over a fake radio: the
// answer's shape, its revision, its entries and where it comes from are the
// shipping code's. The wrist side is the real engine over an in-memory store, so
// every answer is applied the way the watch app applies one — and the sets it
// holds are read back the way the wrist's logging surface reads them.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/platform/watch_transport.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';

import 'helpers/fake_preferences_service.dart';
// `seedExercise` comes from the capture harness: it writes capabilities through
// `setExerciseCapabilities`, which is the only way they reach a repository —
// `createExercise` ignores the inline list. The projection refuses a slot whose
// exercise carries none, so this is load-bearing.
import 'helpers/repository_harness.dart' hide seedExercise;
import 'helpers/sync_protocol_harness.dart';
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

/// The instant a fixture's rows are stamped with: [minute] past the phone's
/// own `_now` on the same day, so a stamp is readable in a debugger.
int _at(int minute) => DateTime.utc(
  2026,
  10,
  6,
  9,
  minute,
).millisecondsSinceEpoch;

/// The same instant, as the protocol writes one.
String _atIso(int minute) =>
    utcIso(DateTime.fromMillisecondsSinceEpoch(_at(minute), isUtc: true));

/// The entry id of the set the wrist logs in these fixtures. The wrist's own
/// id, which the phone imports and must never send back (D-34).
const String _wristEntryId = '9f2c1d2e-3b4a-4c5d-8e6f-7a8b9c0d1e2f';

/// The ids the answer's `entries` carry, in order.
List<String> _entryIds(Map<String, Object?> payload) => [
  for (final entry in _objects(payload['entries']))
    entry['entryId']! as String,
];

/// One set of a fixture slot: what its rows carry, and when they were written.
typedef _Set = ({int reps, double loadKg, bool skipped, int atMs});

/// The repository fixtures this file's scenarios start from.
///
/// Both write straight to the repository rather than through the session screen:
/// the regular session path logs a default set with a real clock when an
/// exercise is added, and a scenario that pins an exact ladder, stamp or
/// provenance needs rows of its own.
abstract final class _SessionFixture {
  /// Seeds a running phone session holding one `set` slot, with exactly the row
  /// groups [sets] names and nothing else. Answers the slot's id.
  static Future<String> seedSets(
    WorkoutRepository repository,
    WorkoutState state,
    String sessionId,
    String slotId,
    String exerciseId,
    List<_Set> sets,
  ) async {
    final start = _at(0);
    await repository.createSession(
      TrainingSession(
        id: sessionId,
        ownerUserId: LoggedEntryRows.ownerUserId,
        startedAtMs: start,
        // Running: the answer is the session the phone is in, and a session
        // with an end is history (G1).
        endedAtMs: null,
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
    await repository.createSegment(
      LoggedEntryRows.defaultSegment(
        id: 'segment-$sessionId',
        sessionId: sessionId,
        atMs: start,
      ),
    );
    await repository.createEffort(
      SegmentEffort(
        id: slotId,
        segmentId: 'segment-$sessionId',
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: exerciseId,
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
    for (var number = 0; number < sets.length; number++) {
      final set = sets[number];
      if (set.skipped) {
        // A skipped set: the reps row says so, the way the session screen
        // writes one.
        await repository.createObservation(
          EffortObservation(
            id: LoggedEntryRows.observationId(slotId, number, 'reps'),
            effortId: slotId,
            metricId: MetricIds.reps,
            unitId: MetricIds.unitReps,
            valueInt: 0,
            valueBool: true,
            createdAtMs: set.atMs,
            updatedAtMs: set.atMs,
          ),
        );
        continue;
      }
      for (final row in LoggedEntryRows.setObservations(
        effortId: slotId,
        entryIndex: number,
        reps: set.reps,
        weightKg: set.loadKg,
        exerciseHasLoad: true,
        atMs: set.atMs,
      )) {
        await repository.createObservation(row);
      }
    }
    await state.loadHistoricalSession(sessionId);
    return slotId;
  }

  /// Stages the watch-inbox row of a set the wrist logged in [slotId] and marks
  /// it applied — a live row, which is what the provenance claim (D-34) reads.
  ///
  /// The row's `loggedAt` is the identity the importer stamps on every row it
  /// writes for that entry, so a fixture passes the stamp its imported rows
  /// carry.
  static Future<void> stageImportedSet(
    WorkoutRepository repository,
    String sessionId,
    String slotId, {
    required String entryId,
    required int loggedAtMs,
  }) async {
    await repository.stageWatchInboxEntry(
      WatchInboxEntry(
        entryId: entryId,
        watchSessionId: sessionId,
        kind: WatchInboxEntry.kindSet,
        origin: WatchInboxEntry.originWatch,
        payload: <String, dynamic>{
          'entryId': entryId,
          'eventId': entryId,
          'kind': 'set',
          'loggedAt': utcIso(
            DateTime.fromMillisecondsSinceEpoch(loggedAtMs, isUtc: true),
          ),
          'sessionExerciseId': slotId,
          'exerciseId': 'ex-bench',
          'reps': 5,
          'loadKg': 55.0,
        },
        receivedAtMs: loggedAtMs,
      ),
    );
    await repository.markWatchInboxEntriesApplied([entryId], loggedAtMs);
  }
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

  /// A running phone session holding one `set` slot with exactly [sets] logged
  /// in it, loaded as the session the phone is in.
  Future<String> seed(
    String sessionId,
    List<_Set> sets, {
    String slotId = 'slot-bench',
    String exerciseId = 'ex-bench',
  }) => _SessionFixture.seedSets(
    repository,
    phoneState,
    sessionId,
    slotId,
    exerciseId,
    sets,
  );

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
        expect(
          _entryIds(payload),
          ['entry-$bench-0'],
          reason:
              'S-31 the phone answers with the sets it logged itself. The '
              'session path logs one set when an exercise is added, and only '
              'the `set` slot carries one: a `timed` or unnamed kind has no '
              'wire entry yet (D-39)',
        );
        expect(_objects(payload['entries']).single['reps'], 10);
        expect(_objects(payload['entries']).single['loadKg'], 0.0);
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

  group('S-31…S-42 the sets the phone logged ride the answer', () {
    /// A phone session of one `set` slot with three groups: the phone's own at
    /// the first and third instants, and — when [wristAlsoLogged] — a second
    /// group carrying the rows the importer wrote for a set the wrist logged,
    /// whose live inbox row is staged at that same instant (D-34's identity).
    Future<String> phoneSets({
      required int secondAtMs,
      required int thirdAtMs,
      bool wristAlsoLogged = false,
    }) async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 5, loadKg: 55.0, skipped: false, atMs: secondAtMs),
        (reps: 10, loadKg: 70.0, skipped: false, atMs: thirdAtMs),
      ]);
      if (wristAlsoLogged) {
        await _SessionFixture.stageImportedSet(
          repository,
          'sess-1',
          'slot-bench',
          entryId: _wristEntryId,
          loggedAtMs: secondAtMs,
        );
      }
      return 'sess-1';
    }

    /// The set the wrist logged itself, as the wrist logs one: the same entry
    /// id and the same instant the phone imported.
    Future<void> wristLogsItsOwnSet() => engine.appendObservation(
      <String, Object?>{
        'entryId': _wristEntryId,
        'eventId': _wristEntryId,
        'kind': 'set',
        'loggedAt': _atIso(2),
        'sessionExerciseId': 'slot-bench',
        'exerciseId': 'ex-bench',
        'reps': 5,
        'loadKg': 55.0,
      },
    );

    test('S-31 the phone\'s own sets arrive as entries', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
      ]);
      expect(
        engine.observations,
        isEmpty,
        reason: 'the fixture: the wrist has logged nothing of its own',
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();

      final answer = radio.lastOfType('session_snapshot');
      final payload = _payload(answer);
      expect(payload['sessionId'], 'sess-1');
      expect(_slotIds(payload), ['slot-bench']);
      expect(
        _entryIds(payload),
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason:
            'S-31 both sets this phone logged ride the answer, named by the '
            'slot they are in and their place in the ladder (D-33), so the '
            'wrist can hold them like its own',
      );
      final entries = _objects(payload['entries']);
      expect([for (final entry in entries) entry['kind']], ['set', 'set']);
      expect([for (final entry in entries) entry['reps']], [8, 8]);
      expect([for (final entry in entries) entry['loadKg']], [60.0, 62.5]);
      expect(
        [for (final entry in entries) entry['sessionExerciseId']],
        ['slot-bench', 'slot-bench'],
      );
      expect(
        [for (final entry in entries) entry['exerciseId']],
        ['ex-bench', 'ex-bench'],
      );
      expect(
        [for (final entry in entries) entry['loggedAt']],
        [_atIso(1), _atIso(2)],
        reason:
            'D-36 the instant the set was logged, as the protocol writes one',
      );
      expect(
        [for (final entry in entries) entry['eventId']],
        _entryIds(payload),
        reason: 'D-33 the phone is the writer, so the entry is its own event',
      );
      expect(
        payload['timers'],
        isEmpty,
        reason: 'D-42 the phone carries no timer state down',
      );

      expect(await engine.applyMessage(answer), isTrue);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason: 'S-31 the wrist holds both, in the order the protocol reads them',
      );
      expect(engine.entries.first.payload['reps'], 8);
      expect(engine.entries.last.payload['loadKg'], 62.5);
      expect(
        [for (final entry in engine.entries) entry.confirmedAt],
        everyElement(isNotNull),
        reason: 'the phone stated them, so they are receipted, not owed',
      );
      expect(engine.pendingObservations(), isEmpty);
      expect(reportedFailure, isNull);
    });

    test('S-32 the same answer twice doubles nothing', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
      ]);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');

      expect(await engine.applyMessage(answer), isTrue);
      expect(
        await engine.applyMessage(answer),
        isTrue,
        reason: 'the very same frame, message id and all, is not an error',
      );
      expect(
        await engine.applyMessage({...answer, 'messageId': 'msg-redelivered'}),
        isTrue,
        reason: 'nor is the same answer under a fresh message id',
      );

      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason:
            'S-32 the same entry, however often it arrives, is the row the '
            'wrist already wrote: the id is the phone\'s (D-33) and the wrist '
            'keys on it',
      );
      expect(engine.observations, hasLength(2));
      expect(
        engine.pendingObservations(),
        isEmpty,
        reason: 'S-32 a re-delivered snapshot is never echoed back',
      );
    });

    test('S-33 the wrist\'s own set is not sent back to it', () async {
      await phoneSets(secondAtMs: _at(2), thirdAtMs: _at(3), wristAlsoLogged: true);
      expect(
        phoneState.getObservationsForEffort('slot-bench'),
        hasLength(6),
        reason: 'the fixture: three sets of rows, one of them the wrist\'s',
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();

      final answer = radio.lastOfType('session_snapshot');
      final payload = _payload(answer);
      expect(
        _entryIds(payload),
        ['entry-slot-bench-0', 'entry-slot-bench-2'],
        reason:
            'S-33 the middle set is the wrist\'s own, so the answer carries the '
            'phone\'s two and never the wrist\'s: naming it back under a phone '
            'id would double it (D-34)',
      );
      expect(
        jsonEncode(payload),
        isNot(contains(_wristEntryId)),
        reason: 'S-33 the wrist\'s entry is not sent back under any name',
      );
      expect(
        [for (final entry in _objects(payload['entries'])) entry['reps']],
        [8, 10],
      );

      expect(await engine.applyMessage(answer), isTrue);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-2'],
        reason: 'the wrist holds the two it was sent, and nothing else',
      );
    });

    test('S-34 one live row claims one ladder group', () async {
      await phoneSets(
        secondAtMs: _at(2),
        thirdAtMs: _at(2),
        wristAlsoLogged: true,
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      expect(
        _entryIds(_payload(answer)),
        ['entry-slot-bench-0', 'entry-slot-bench-2'],
        reason:
            'S-34 the wrist\'s row claims the first group stamped like it, and '
            'the later group — a set of the phone\'s own, logged in the same '
            'millisecond — is still sent: one row claims one group',
      );

      // The device that logged it logs it: the wrist holds its own row and the
      // two the phone sent, each exactly once.
      expect(await engine.applyMessage(answer), isTrue);
      await wristLogsItsOwnSet();

      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', _wristEntryId, 'entry-slot-bench-2'],
        reason:
            'S-34 three sets, each represented once: the wrist\'s own and the '
            'two the phone logged, in the order they were logged',
      );
    });

    test('S-36 a ladder with nothing logged answers with no entries', () async {
      await seed('sess-1', const []);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();

      final payload = _payload(radio.lastOfType('session_snapshot'));
      expect(_slotIds(payload), ['slot-bench']);
      expect(
        _objects(payload['entries']),
        isEmpty,
        reason:
            'S-36 a session with nothing logged answers with an empty list, '
            'not an absent one: the field is part of the state',
      );
      expect(_entryIds(payload), isEmpty);
      expect(reportedFailure, isNull);
    });

    test('S-37 a phone entry counts like the wrist\'s own', () async {
      await phoneSets(secondAtMs: _at(2), thirdAtMs: _at(3), wristAlsoLogged: true);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        await engine.applyMessage(radio.lastOfType('session_snapshot')),
        isTrue,
      );
      expect(wristSlots(), ['slot-bench']);

      await wristLogsItsOwnSet();

      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', _wristEntryId, 'entry-slot-bench-2'],
        reason:
            'S-37 the list the logging screen reads holds three sets: two the '
            'phone logged and one the wrist did',
      );
      expect(engine.entries.first.payload['reps'], 8);
      expect(
        engine.entries.last.payload['reps'],
        10,
        reason:
            'S-37 the newest set is the phone\'s, logged after the wrist\'s '
            'own: a phone entry is ordered by when it was logged, not by when '
            'it arrived',
      );
      expect(
        engine.entries.last.payload.keys.toSet(),
        engine.entries[1].payload.keys.toSet(),
        reason:
            'D-33 a phone entry carries the fields the wrist\'s own carries, '
            'so nothing downstream can tell them apart',
      );
    });

    test('S-38 the wrist adopts a session it does not hold', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
      ]);
      expect(engine.session, isNull, reason: 'the wrist holds nothing yet');

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        await engine.applyMessage(radio.lastOfType('session_snapshot')),
        isTrue,
      );

      expect(engine.session!.sessionId, 'sess-1');
      expect(wristSlots(), ['slot-bench']);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason: 'S-38 the session arrives with the sets the phone logged in it',
      );
      expect(
        [for (final entry in engine.observations) entry.confirmedAt],
        everyElement(isNotNull),
        reason:
            'S-38 the wrist logged nothing of its own, so every row it now '
            'holds is one the phone stated',
      );
      expect(engine.pendingObservations(), isEmpty);
    });

    test('S-39 the projection is deterministic, and an echo is not sent', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
      ]);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final first = _payload(radio.lastOfType('session_snapshot'));
      expect(await engine.applyMessage(radio.lastOfType('session_snapshot')), isTrue);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final second = _payload(radio.lastOfType('session_snapshot'));
      expect(
        jsonEncode(second['entries']),
        jsonEncode(first['entries']),
        reason:
            'S-39 byte-identical: the ids come from the ladder and the instants '
            'from the rows, never from a clock or a counter',
      );
      expect(second['revision'], first['revision']);

      radio.sent.clear();
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        radio.ofType('session_snapshot'),
        isEmpty,
        reason:
            'S-39 the wrist states the shape it was sent, so the phone has '
            'nothing to correct and does not re-assert',
      );
      expect(reportedFailure, isNull);
    });

    test('S-40 two sessions do not share entries', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
      ]);
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        await engine.applyMessage(radio.lastOfType('session_snapshot')),
        isTrue,
      );
      expect(engine.session!.sessionId, 'sess-1');

      await seed('sess-2', [
        (reps: 6, loadKg: 40.0, skipped: false, atMs: _at(4)),
      ], slotId: 'slot-other');

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      final payload = _payload(answer);
      expect(payload['sessionId'], 'sess-2');
      expect(_slotIds(payload), ['slot-other']);
      expect(_entryIds(payload), ['entry-slot-other-0']);

      expect(await engine.applyMessage(answer), isTrue);
      expect(engine.session!.sessionId, 'sess-2');
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-other-0'],
        reason:
            'S-40 the entries belong to the session they were logged in: '
            'sess-1\'s rows are not carried into sess-2',
      );
      expect(
        [for (final entry in engine.entries) entry.sessionId],
        ['sess-2'],
      );
    });

    test('S-42 a set the wire cannot carry is omitted', () async {
      await seed('sess-1', [
        (reps: 0, loadKg: 0.0, skipped: true, atMs: _at(1)),
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(2)),
      ]);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      final payload = _payload(answer);
      expect(
        _entryIds(payload),
        ['entry-slot-bench-1'],
        reason:
            'S-42 a skipped set has no wire shape — the schema has no field to '
            'say so and `reps` has a minimum of 1 — so it is left out, never '
            'placeheld (D-40)',
      );
      final sent = _objects(payload['entries']).single;
      expect(sent['reps'], 8);
      expect(sent['loadKg'], 60.0);

      expect(
        loadProtocolValidator().validateEnvelope(answer),
        isEmpty,
        reason:
            'S-42 a `reps: 0` entry would be a rejection, and a rejected entry '
            'costs the whole snapshot: omitting it is what keeps the answer '
            'conformant',
      );

      expect(await engine.applyMessage(answer), isTrue);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-1'],
        reason: 'the wrist holds the set that could be carried, and no other',
      );
    });
  });

  // The same answer on both stores: the projection is a read, so what it reads
  // must not depend on which store holds the rows.
  final parity = <String, String>{};
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — S-31 the answer is the same on both stores', () {
      late WorkoutRepository store;

      setUp(() async => store = await harness.open());
      tearDown(() async => await harness.close());

      test('S-31 both stores project the same entries', () async {
        await seedExercise(
          store,
          id: 'ex-bench',
          name: 'Bench Press',
          capabilities: ['sets', 'reps', 'load'],
        );
        final state = WorkoutState(store);
        await _SessionFixture.seedSets(store, state, 'sess-1', 'slot-bench', 'ex-bench', [
          (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
          (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
        ]);
        await _SessionFixture.stageImportedSet(
          store,
          'sess-1',
          'slot-bench',
          entryId: _wristEntryId,
          loggedAtMs: _at(3),
        );

        final bridge = WatchSessionAdoptionBridge(repository: store);
        bridge.bindWorkoutState(state);
        final payload = await bridge.projectSession(null);

        expect(payload, isNotNull);
        expect(_slotIds(payload!), ['slot-bench']);
        expect(
          _entryIds(payload),
          ['entry-slot-bench-0', 'entry-slot-bench-1'],
          reason: 'both sets are the phone\'s: the wrist\'s row is stamped later',
        );
        expect(
          [for (final entry in _objects(payload['entries'])) entry['loadKg']],
          [60.0, 62.5],
        );
        expect(payload['timers'], isEmpty);
        parity[harness.name] = jsonEncode(payload);
      });
    });
  }

  test('S-31 Mock and Hive answer byte for byte the same', () {
    expect(parity['Mock'], isNotNull, reason: 'the Mock group ran');
    expect(parity['Hive'], isNotNull, reason: 'the Hive group ran');
    expect(
      parity['Hive'],
      parity['Mock'],
      reason:
          'the projection reads the rows through the repository interface, so '
          'the store underneath must not show through (G1)',
    );
  });
}
