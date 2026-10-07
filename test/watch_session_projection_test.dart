// A phone session surfaces on the wrist at the next watch-initiated sync.
//
// Plan: `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/` (S-2, S-6, S-8,
// D-10, D-11) and `docs/plans/2026-10-05-15d-watch-session-sync-pr3-plan/` (the
// phone's own sets ride the answer: S-31, S-32, S-33, S-34, S-35, S-36, S-37,
// S-38, S-39, S-40, S-41, S-43, D-35) and the negative-load plan
// (`docs/plans/2026-10-06-16-watch-negative-load-plan/`: S-59, S-60, D-58,
// D-60).
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
//   S-41 the wrist's own set survives an answer           → `S-41 ...`
//   S-43 the phone is unreachable at Sync                 → `S-43 ...`
//   S-35/D-35 an edit reaches the wrist, and a delete is announced as a
//        structure change, not carried by the answer  → `S-35 ...`
//        (D-110/D-114, plan 2026-10-06-17c-watch-auto-sync-pr3-plan: the
//        announcement itself is S-120..S-123 in watch_session_auto_push_test)
//   S-59 a snapshot carries the assist, and omits only the
//        row without reps                                 → `S-59 ...`
//   S-60 the floor is carried, one step below it is not   → `S-60 ...`
//   S-109 the phone catches up on resume, once             → `S-109 ...`
//         (this file: the graph's `sync()` sends the phone's OWN session or
//         nothing, then asks for the wrist's; the observer is in
//         watch_resume_sync_test.dart)
//
// S-42's "an entry the wire cannot carry is omitted" is now S-59/S-60: a
// band-assisted set is carried with its sign, and only a row with no reps or a
// load below the wire floor is omitted (D-58, D-60).
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
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
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

/// A second set the wrist logs in the same millisecond as [_wristEntryId]: two
/// rows, two groups of imported rows, one instant (F2).
const String _wristEntryId2 = '2b7e4f6a-1c8d-4e5f-9a0b-3c4d5e6f7a8b';

/// The ids the answer's `entries` carry, in order.
List<String> _entryIds(Map<String, Object?> payload) => [
  for (final entry in _objects(payload['entries']))
    entry['entryId']! as String,
];

/// The wrist's own snapshot of a session, with no entries of its own.
///
/// A wrist copy carrying the entries the phone pushed would claim the phone's
/// own groups as rows the wrist logged (D-112) and the projection would then
/// omit them; which is right for a wrist that really logged them, and wrong for
/// a fixture whose sets are the phone's. The ladder is kept, because holding it
/// is what makes the phone's mirror hold the session at all (D-114).
Map<String, Object?> _wristCopyWithoutEntries(Map<String, Object?> snapshot) => {
  ...snapshot,
  'payload': <String, Object?>{
    ..._payload(snapshot),
    'entries': const <Object?>[],
  },
};

/// The answer's entries as `entryId → loadKg`, decoded — never matched as a
/// substring, so `-200` and `-200.1` cannot be confused (S-60). An entry with no
/// `loadKg` reads null: the wire keeps "no load" and "load 0" indistinguishable
/// (D-60).
Map<String, double?> _loadsById(Map<String, Object?> payload) => {
  for (final entry in _objects(payload['entries']))
    entry['entryId']! as String: entry['loadKg'] as double?,
};

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

  /// Stages the watch-inbox row of a set the wrist logged in [slotId] and — when
  /// [applied] — marks it applied: a live row, which is what the provenance
  /// claim (D-34) reads.
  ///
  /// A fixture passes `applied: false` for the half-applied state the importer
  /// can leave behind, where an entry's rows are already written but the row
  /// they came from is still staged (F3).
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
    bool applied = true,
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
    if (applied) {
      await repository.markWatchInboxEntriesApplied([entryId], loggedAtMs);
    }
  }

  /// Seeds a running phone session holding one effort per entry of [slots] —
  /// [effortKind] is the kind the phone stores — and runs each slot's `write` to
  /// fill its records and rows, so a scenario names exactly the instances it
  /// needs and nothing else. Answers the last slot's id.
  static Future<String> seedEfforts(
    WorkoutRepository repository,
    WorkoutState state,
    String sessionId,
    List<
      ({
        String slotId,
        String exerciseId,
        String effortKind,
        Future<void> Function() write,
      })
    >
    slots,
  ) async {
    final start = _at(0);
    await repository.createSession(
      TrainingSession(
        id: sessionId,
        ownerUserId: LoggedEntryRows.ownerUserId,
        startedAtMs: start,
        endedAtMs: null,
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
    final segmentId = 'segment-$sessionId';
    await repository.createSegment(
      LoggedEntryRows.defaultSegment(
        id: segmentId,
        sessionId: sessionId,
        atMs: start,
      ),
    );
    for (final (index, slot) in slots.indexed) {
      await repository.createEffort(
        SegmentEffort(
          id: slot.slotId,
          segmentId: segmentId,
          orderIndex: index,
          effortKind: slot.effortKind,
          exerciseId: slot.exerciseId,
          createdAtMs: start,
          updatedAtMs: start,
        ),
      );
      await slot.write();
    }
    await state.loadHistoricalSession(sessionId);
    return slots.last.slotId;
  }

  /// Stages the watch-inbox row of a non-set entry the wrist logged: [kind] is
  /// the wire kind, and the row carries the fields every entry has plus
  /// [payload]'s.
  ///
  /// The row's `loggedAt` is what the importer stamps on the record it writes
  /// for the entry (`createdAtMs`), so a fixture passes the stamp its imported
  /// record carries (D-133).
  static Future<void> stageImportedEntry(
    WorkoutRepository repository,
    String sessionId, {
    required String entryId,
    required String kind,
    required String slotId,
    required String exerciseId,
    required int loggedAtMs,
    Map<String, Object?> payload = const {},
  }) async {
    await repository.stageWatchInboxEntry(
      WatchInboxEntry(
        entryId: entryId,
        watchSessionId: sessionId,
        kind: kind,
        origin: WatchInboxEntry.originWatch,
        payload: <String, dynamic>{
          'entryId': entryId,
          'eventId': entryId,
          'kind': kind,
          'loggedAt': utcIso(
            DateTime.fromMillisecondsSinceEpoch(loggedAtMs, isUtc: true),
          ),
          'sessionExerciseId': slotId,
          'exerciseId': exerciseId,
          ...payload,
        },
        receivedAtMs: loggedAtMs,
      ),
    );
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
          ['entry-$bench-0', 'entry-$squat-0'],
          reason:
              'S-31 the phone answers with the entries it logged itself: the '
              'session path logs one group when an exercise is added. The '
              '`amrap` slot resolves to `set` by capability, so its group rides '
              '(D-130); the `timed` slot has no window yet, so its entry is '
              'omitted (D-132)',
        );
        expect(_objects(payload['entries']).first['reps'], 10);
        expect(
          _objects(payload['entries']).first.containsKey('loadKg'),
          isFalse,
          reason:
              'D-60 a zero weight still sends no `loadKg`: the wire keeps "no '
              'load" and "load 0" indistinguishable',
        );
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

  group('S-76 a manual Sync answers with the wrist\'s own place', () {
    test('S-76 the answer carries the position the wrist is on', () async {
      await engine.createSession(
        modality: null,
        exercises: [
          _slot('sl-1', 'ex-bench', 'Bench Press', ['sets', 'reps', 'load']),
          _slot('sl-2', 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
          _slot('sl-3', 'ex-deadlift', 'Deadlift', ['sets', 'reps', 'load']),
        ],
      );
      final wristSessionId = engine.session!.sessionId;

      // The phone adopts the wrist's session (S-1), so both ladders are the
      // same three slots and the phone's own place is still its first slot.
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(phoneSlots(), ['sl-1', 'sl-2', 'sl-3']);
      expect(phoneState.currentSession?.id, wristSessionId);

      // The wrist works through its ladder and tells the phone where it got to.
      await engine.advanceExercise();
      await engine.advanceExercise();
      expect(engine.session!.currentExerciseIndex, 2);
      radio.sent.clear();
      await radio.fromWrist(engine.sessionSnapshot()!);
      await _settle();
      expect(
        graph.mirror.currentExerciseIndex,
        2,
        reason: 'the fixture: the phone converged on the wrist\'s position',
      );

      // The wrist taps Sync.
      radio.sent.clear();
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();

      final answer = radio.lastOfType('session_snapshot');
      final payload = _payload(answer);
      expect(payload['sessionId'], wristSessionId);
      expect(_slotIds(payload), ['sl-1', 'sl-2', 'sl-3']);
      expect(
        payload['currentExerciseIndex'],
        2,
        reason:
            'S-76 the answer carries the place the wrist reported, so a manual '
            'Sync does not yank it back to its first exercise (D-77). Without '
            'the fix it carries 0, the phone\'s own place',
      );
      expect(
        engine.session!.currentExerciseIndex,
        2,
        reason: 'S-76 the wrist is still where it was',
      );
      expect(
        engine.session!.currentExercise!['sessionExerciseId'],
        'sl-3',
        reason: 'S-76 and on the exercise it was on',
      );
      expect(
        phoneState.currentSession?.id,
        wristSessionId,
        reason: 'S-76 the answer is composed from the phone\'s own session',
      );
      expect(reportedFailure, isNull);
    });
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

  group('S-31…S-43 the sets the phone logged ride the answer', () {
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

    test('S-35 a re-statement is append-only and doubles nothing', () async {
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
      expect(
        [for (final entry in engine.entries) entry.payload['loadKg']],
        [60.0, 62.5],
        reason: 'the fixture: the wrist holds the phone\'s first set at 60 kg',
      );

      // The phone corrects its first set: 60.0 kg -> 65.0 kg, same row group.
      final weightId = LoggedEntryRows.observationId('slot-bench', 0, 'weight');
      final storedWeight = (await repository.getEffortObservations(
        'slot-bench',
      )).firstWhere((row) => row.id == weightId);
      await repository.updateObservation(
        EffortObservation(
          id: storedWeight.id,
          effortId: storedWeight.effortId,
          metricId: storedWeight.metricId,
          unitId: storedWeight.unitId,
          valueReal: 65.0,
          createdAtMs: storedWeight.createdAtMs,
          updatedAtMs: _at(3),
        ),
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final edited = radio.lastOfType('session_snapshot');
      expect(await engine.applyMessage(edited), isTrue);
      expect(
        await engine.applyMessage(edited),
        isTrue,
        reason:
            'S-35 the very same re-statement a second time is not an error, and '
            'the wrist keys it on the `entryId` the phone wrote (D-33)',
      );

      expect(
        [for (final entry in engine.entries) entry.payload['loadKg']],
        [65.0, 62.5],
        reason:
            'S-35 the wrist holds the id, so the snapshot re-states it and the '
            'projection shows the corrected weight (D-35)',
      );
      expect(
        engine.observations,
        hasLength(2),
        reason:
            'S-35 a re-statement folds into the projection over the row the '
            'wrist already wrote: nothing is appended, so a re-delivered edit '
            'cannot double the set',
      );
      expect(
        [
          for (final row in engine.observations)
            if (row.entryId == 'entry-slot-bench-0') row.payload['loadKg'],
        ],
        [60.0],
        reason: 'S-35 the stored row is never rewritten (append-only)',
      );
      expect(
        [for (final row in engine.observations) row.confirmedAt],
        everyElement(isNotNull),
        reason: 'S-35 a re-stated id is still a receipt for the row it names',
      );
      expect(engine.pendingObservations(), isEmpty);
      expect(reportedFailure, isNull);
    });

    test('S-35 a re-statement of a deleted id stays deleted', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
      ]);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      await engine.applyMessage(radio.lastOfType('session_snapshot'));
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
      );

      // The phone drops the second set: a structure change naming an entry that
      // is not an edit to it.
      expect(
        await engine.applyMessage(<String, Object?>{
          'protocolVersion': SyncProtocolValidator.protocolVersion,
          'messageId': 'msg-change-1',
          'sessionId': 'sess-1',
          'type': 'structure_change',
          'origin': 'phone',
          'sentAt': _atIso(3),
          'payload': <String, Object?>{
            'changeId': 'chg-1',
            'changes': [
              <String, Object?>{
                'kind': 'delete_entry',
                'entryId': 'entry-slot-bench-1',
              },
            ],
          },
        }),
        isTrue,
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0'],
        reason: 'the delete drops the id from the projection',
      );

      // An answer that still names the deleted id: the wrist holds the row, so
      // the snapshot re-states it — and a re-statement of a deleted id stays
      // deleted, because the projection drops deleted ids before it reads the
      // corrections.
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        _entryIds(_payload(radio.lastOfType('session_snapshot'))),
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason: 'the fixture: the phone still holds the set the wrist dropped',
      );
      expect(
        await engine.applyMessage(radio.lastOfType('session_snapshot')),
        isTrue,
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0'],
        reason:
            'S-35 a re-statement does not resurrect a deletion: the phone owns '
            'the delete, and the id stays dropped',
      );
      expect(
        [for (final entry in engine.observations) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason: 'the row is not un-stored either; only the projection hides it',
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

    test('S-41 the wrist\'s own set survives an answer with no phone entries',
        () async {
      // The phone holds `sess-1`, and the only rows in it are the ones the
      // importer wrote for a set the wrist logged: a live inbox row claims
      // them, so they are the wrist's (D-34) and the phone has no entry of its
      // own to send.
      await seed('sess-1', [
        (reps: 5, loadKg: 55.0, skipped: false, atMs: _at(2)),
      ]);
      await _SessionFixture.stageImportedSet(
        repository,
        'sess-1',
        'slot-bench',
        entryId: _wristEntryId,
        loggedAtMs: _at(2),
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        _payload(radio.lastOfType('session_snapshot'))['entries'],
        isEmpty,
        reason:
            'S-41 the fixture: everything the phone holds came from the wrist, '
            'so the answer carries no entry',
      );
      expect(
        await engine.applyMessage(radio.lastOfType('session_snapshot')),
        isTrue,
      );

      // The wrist logs that set itself, as it did before the sync.
      await wristLogsItsOwnSet();
      radio.sent.clear();

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      expect(
        _payload(answer)['entries'],
        isEmpty,
        reason:
            'S-41 the phone\'s only set is the wrist\'s own, and it is never '
            'echoed back to its author (D-34)',
      );

      expect(await engine.applyMessage(answer), isTrue);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        [_wristEntryId],
        reason:
            'S-41 the wrist\'s row survives a merge of nothing: no answer takes '
            'away what the wrist wrote itself',
      );
      expect(
        engine.observations,
        hasLength(1),
        reason: 'S-41 and it is still one row, not two',
      );
      expect(
        engine.pendingObservations(),
        hasLength(1),
        reason:
            'S-41 an answer naming no entry confirms none, so the snapshot is '
            'not the receipt for a row the wrist logged',
      );

      // What does receipt it: the phone's `receipt`, the path that already
      // acknowledges observations the phone has recorded.
      expect(
        await engine.applyMessage(
          WatchNutritionLogBridge.receiptFor(
            entryIds: const [_wristEntryId],
            sentAt: DateTime.fromMillisecondsSinceEpoch(_at(3), isUtc: true),
            messageId: 'msg-receipt-1',
          ),
        ),
        isTrue,
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        [_wristEntryId],
        reason: 'S-41 the receipt changes what the wrist owes, not what it holds',
      );
      expect(
        engine.entries.single.confirmedAt,
        isNotNull,
        reason: 'S-41 the receipt path confirms the wrist\'s own row',
      );
      expect(engine.pendingObservations(), isEmpty);
      expect(reportedFailure, isNull);
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

      // The user finishes sess-1 before the phone's next workout arrives: a wrist
      // mid-session refuses a snapshot naming another session (D-78, S-77), and
      // what this scenario is about is the switch that is still allowed.
      await engine.finishSession();

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

    test('S-59 a snapshot carries the assist, and omits only the row without '
        'reps', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: -20.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(2)),
        (reps: 0, loadKg: 0.0, skipped: true, atMs: _at(3)),
      ]);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      final payload = _payload(answer);

      expect(
        _loadsById(payload),
        {'entry-slot-bench-0': -20.0, 'entry-slot-bench-1': 60.0},
        reason:
            'S-59 a band-assisted set travels with its sign and its value, '
            'verbatim: not rounded, not re-signed, not converted. The skipped '
            'row has no wire shape — the schema has no field to say so and '
            '`reps` has a minimum of 1 — so it is left out, never placeheld '
            '(D-60)',
      );
      expect(
        loadProtocolValidator().validateEnvelope(answer),
        isEmpty,
        reason:
            'S-59 a `reps: 0` entry would be a rejection, and a rejected entry '
            'costs the whole snapshot: omitting it is what keeps the answer '
            'conformant, and the assist is conformant as it stands',
      );

      expect(await engine.applyMessage(answer), isTrue);
      expect(
        [
          for (final entry in engine.entries)
            (entry.entryId, entry.payload['loadKg']),
        ],
        [
          ('entry-slot-bench-0', -20.0),
          ('entry-slot-bench-1', 60.0),
        ],
        reason:
            'S-59 the wrist holds the assist at −20 kg, and nothing becomes 0 '
            'or +20 on the way',
      );
    });

    test('S-60 the floor is carried, one step below it is not', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: -200.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: -200.1, skipped: false, atMs: _at(2)),
        (reps: 8, loadKg: -240.0, skipped: false, atMs: _at(3)),
        (reps: 1, loadKg: 0.0, skipped: false, atMs: _at(4)),
      ]);

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      final payload = _payload(answer);

      expect(
        _entryIds(payload),
        ['entry-slot-bench-0', 'entry-slot-bench-3'],
        reason:
            'S-60 −200 kg is the last value the wire carries; −200.1 and −240 '
            'are below the floor and are omitted rather than clamped into range '
            '(D-58, D-60)',
      );
      expect(
        _loadsById(payload),
        {'entry-slot-bench-0': -200.0, 'entry-slot-bench-3': null},
        reason:
            'S-60 the floor itself is carried exactly, and the zero-weight row '
            'is carried with no `loadKg` key at all (D-60)',
      );
      expect(
        _objects(payload['entries']).last.containsKey('loadKg'),
        isFalse,
        reason:
            'S-60 the wire never claims "load 0": a zero weight sends no key',
      );
      expect(
        loadProtocolValidator().validateEnvelope(answer),
        isEmpty,
        reason: 'S-60 a below-floor entry would be a rejection (S-65)',
      );

      expect(await engine.applyMessage(answer), isTrue);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-3'],
        reason: 'S-60 the wrist holds the floor and the unloaded set, no other',
      );
    });

    test('S-34 a staged row claims its group before it is marked applied',
        () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 5, loadKg: 55.0, skipped: false, atMs: _at(2)),
      ]);
      // The half-applied state an interrupted import leaves: the entry's rows
      // are written (the group stamped `_at(2)`), and the inbox row they came
      // from is still staged — the importer marks it applied only once every
      // row has landed.
      await _SessionFixture.stageImportedSet(
        repository,
        'sess-1',
        'slot-bench',
        entryId: _wristEntryId,
        loggedAtMs: _at(2),
        applied: false,
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      expect(
        _entryIds(_payload(answer)),
        ['entry-slot-bench-0'],
        reason:
            'S-34 F3 the staged row still claims the group its rows were '
            'written for, so the wrist\'s own set is not sent back to it under '
            'a phone id — reading only applied rows would double it, and staged '
            'rows are never deleted, so the duplicate would never go away',
      );
    });

    test('S-34 a second watch row at one stamp claims the second group',
        () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 5, loadKg: 55.0, skipped: false, atMs: _at(2)),
        (reps: 6, loadKg: 50.0, skipped: false, atMs: _at(2)),
        (reps: 10, loadKg: 70.0, skipped: false, atMs: _at(2)),
      ]);
      // Two sets the wrist logged in the same millisecond: two live inbox rows
      // and two groups of imported rows at one stamp.
      for (final entryId in [_wristEntryId, _wristEntryId2]) {
        await _SessionFixture.stageImportedSet(
          repository,
          'sess-1',
          'slot-bench',
          entryId: entryId,
          loggedAtMs: _at(2),
        );
      }

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final answer = radio.lastOfType('session_snapshot');
      expect(
        _entryIds(_payload(answer)),
        ['entry-slot-bench-0', 'entry-slot-bench-3'],
        reason:
            'S-34 F2 the claim is one group per row: the first row takes the '
            'first group stamped like it (number 1) and the second row the next '
            'one (number 2), so the group left over — number 3, a set the phone '
            'logged in the same millisecond — is still sent. The ladder the '
            'wrist ends up with is neither doubled nor short',
      );
      expect(loadProtocolValidator().validateEnvelope(answer), isEmpty);

      expect(await engine.applyMessage(answer), isTrue);
      for (final entryId in [_wristEntryId, _wristEntryId2]) {
        await engine.appendObservation(<String, Object?>{
          'entryId': entryId,
          'eventId': entryId,
          'kind': 'set',
          'loggedAt': _atIso(2),
          'sessionExerciseId': 'slot-bench',
          'exerciseId': 'ex-bench',
          'reps': 5,
          'loadKg': 55.0,
        });
      }

      final held = [for (final entry in engine.entries) entry.entryId];
      expect(held.toSet(), {
        'entry-slot-bench-0',
        'entry-slot-bench-3',
        _wristEntryId,
        _wristEntryId2,
      });
      expect(
        held,
        hasLength(4),
        reason: 'S-34 F2 four sets, and not one of them twice',
      );
    });

    test('S-31 two phone sets at one instant answer in `entryId` order',
        () async {
      await seed('sess-1', const []);
      // Two sets logged in the same millisecond whose entry numbers sort the
      // other way round byte-wise ("…-10" is below "…-9"), so the order the
      // answer carries them in can only come from the tie-break.
      for (final number in [9, 10]) {
        for (final row in LoggedEntryRows.setObservations(
          effortId: 'slot-bench',
          entryIndex: number,
          reps: 8,
          weightKg: 60.0,
          exerciseHasLoad: true,
          atMs: _at(2),
        )) {
          await repository.createObservation(row);
        }
      }

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        _entryIds(_payload(radio.lastOfType('session_snapshot'))),
        ['entry-slot-bench-10', 'entry-slot-bench-9'],
        reason:
            'S-31 F5 the protocol orders by `loggedAt`, then by `entryId` — the '
            'wrist\'s own order (AC-6) — so two sets logged in one millisecond '
            'do not depend on the order the store handed their rows back',
      );
    });

    test('S-35 an edit reaches the wrist and a delete is announced', () async {
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
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
      );

      // An edit: the phone's first set is corrected from 60.0 to 65.0.
      final weightId = LoggedEntryRows.observationId('slot-bench', 0, 'weight');
      final storedWeight = (await repository.getEffortObservations(
        'slot-bench',
      )).firstWhere((row) => row.id == weightId);
      await repository.updateObservation(
        EffortObservation(
          id: storedWeight.id,
          effortId: storedWeight.effortId,
          metricId: storedWeight.metricId,
          unitId: storedWeight.unitId,
          valueReal: 65.0,
          createdAtMs: storedWeight.createdAtMs,
          updatedAtMs: _at(3),
        ),
      );

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final edited = radio.lastOfType('session_snapshot');
      expect(
        [
          for (final entry in _objects(_payload(edited)['entries']))
            entry['loadKg'],
        ],
        [65.0, 62.5],
        reason:
            'S-35 the edit rides the phone\'s state: the projection names both '
            'sets, the edited one with the corrected weight — it omits nothing '
            'it should carry (D-35)',
      );
      expect(
        await engine.applyMessage(edited),
        isTrue,
      );
      expect(
        [
          for (final entry in engine.entries) entry.payload['loadKg'],
        ],
        [65.0, 62.5],
        reason:
            'S-35 the wrist holds the id already, so the snapshot re-states it: '
            'the projection shows the phone\'s current value (D-35)',
      );
      expect(
        [
          for (final entry in engine.observations) entry.payload['loadKg'],
        ],
        [60.0, 62.5],
        reason:
            'S-35 the store stays append-only: the row the wrist wrote when the '
            'entry first arrived is never rewritten, and a re-stated id appends '
            'nothing, so the set is never doubled',
      );

      // A delete: the phone drops the set it logged second. An answer cannot
      // carry an absence, so the delete is announced as a structure change on
      // the push's next pass (D-110) — and the frame names the session only
      // because the phone's mirror holds it, which here means the wrist's copy
      // has been handed back, the way it is after a hand-over.
      graph.autoPush.bindWorkoutState(phoneState);
      await graph.autoPush.flush();
      expect(
        radio.ofType('structure_change'),
        isEmpty,
        reason:
            'S-123 the first pass of a session seeds the announced ledger: '
            'nothing has vanished yet, so nothing is announced',
      );

      for (final metricKey in ['reps', 'weight']) {
        await repository.deleteObservation(
          LoggedEntryRows.observationId('slot-bench', 1, metricKey),
        );
      }

      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      final deleted = radio.lastOfType('session_snapshot');
      expect(
        _entryIds(_payload(deleted)),
        ['entry-slot-bench-0'],
        reason:
            'D-38 a delete is not carried: the projection carries nothing for a '
            'group the phone no longer holds',
      );
      expect(await engine.applyMessage(deleted), isTrue);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason:
            'D-38 the answer alone takes nothing away — which is the gap the '
            'announcement below fills (D-110)',
      );

      await radio.fromWrist(_wristCopyWithoutEntries(engine.sessionSnapshot()!));
      await _settle();

      final phoneProjection = await graph.adoption.projectSession(
        const <String, Object?>{},
      );
      expect(
        _entryIds(phoneProjection!),
        ['entry-slot-bench-0'],
        reason:
            'D-112 a wrist copy with no entries of its own claims no group, so '
            'the phone still projects its own surviving set',
      );

      await graph.autoPush.flush();
      final deletion = radio.ofType('structure_change').single;
      expect(
        deletion['sessionId'],
        'sess-1',
        reason:
            'D-114 the frame names the session both devices hold — the wrist '
            'would refuse one it is not running',
      );
      expect(
        _payload(deletion)['changeId'],
        startsWith('del-entry-slot-bench-1-'),
        reason:
            'D-110 the id names the entry the deletion is about and is minted '
            'per delete event, so a resend of the same event is a no-op (D-113) '
            'while a second deletion of a re-used number is a new change',
      );
      expect(
        _payload(deletion)['changes'],
        [
          {'kind': 'delete_entry', 'entryId': 'entry-slot-bench-1'},
        ],
        reason:
            'S-35 the phone now names the set it dropped, in a frame the wrist '
            'applies (D-110)',
      );

      await engine.applyMessage(deletion);
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0'],
        reason:
            'S-35 the wrist hides the entry the frame named, so a set the phone '
            'dropped leaves the ladder it was logged against',
      );
      expect(
        [for (final entry in engine.observations) entry.payload['entryId']],
        ['entry-slot-bench-0', 'entry-slot-bench-1'],
        reason:
            'S-35/D-115 the wrist hides an entry without rewriting the rows it '
            'already wrote: the store stays append-only (I-3)',
      );
    });

    test('S-35 a second edit wins over the first', () async {
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

      final weightId = LoggedEntryRows.observationId('slot-bench', 0, 'weight');

      // One edit: the phone rewrites its first set's weight, syncs, and the
      // answer is applied to the wrist — the way the shipping app does it.
      Future<void> editAndSync(double loadKg, int atMs) async {
        final stored = (await repository.getEffortObservations('slot-bench'))
            .firstWhere((row) => row.id == weightId);
        await repository.updateObservation(
          EffortObservation(
            id: stored.id,
            effortId: stored.effortId,
            metricId: stored.metricId,
            unitId: stored.unitId,
            valueReal: loadKg,
            createdAtMs: stored.createdAtMs,
            updatedAtMs: atMs,
          ),
        );
        await radio.fromWrist(WatchTransportRequest.snapshotFrame());
        await _settle();
        expect(
          await engine.applyMessage(radio.lastOfType('session_snapshot')),
          isTrue,
        );
      }

      await editAndSync(65.0, _at(3));
      expect(
        [for (final entry in engine.entries) entry.payload['loadKg']],
        [65.0, 62.5],
        reason: 'S-35 the first edit reaches the wrist (60 -> 65)',
      );

      // The second edit is the one that matters: the wrist already holds 65,
      // so a fold order that let the earlier correction win would keep
      // showing it instead of the phone's newest value.
      await editAndSync(70.0, _at(4));
      expect(
        [for (final entry in engine.entries) entry.payload['loadKg']],
        [70.0, 62.5],
        reason:
            'S-35/D-35 the newest snapshot is authoritative: a set edited '
            'twice (60 -> 65 -> 70) shows 70 on the wrist, not the first '
            'correction',
      );
      expect(
        engine.observations
            .where((row) => row.recordId == 'entry-slot-bench-0')
            .length,
        1,
        reason: 'S-35 one row per id however many times the phone re-states it',
      );
      expect(
        [for (final entry in engine.observations) entry.payload['loadKg']],
        [60.0, 62.5],
        reason:
            'S-35 the store stays append-only: the second edit rewrites no '
            'stored row and doubles no set',
      );
    });

    test('S-43 the phone is unreachable at Sync', () async {
      await seed('sess-1', [
        (reps: 8, loadKg: 60.0, skipped: false, atMs: _at(1)),
        (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(2)),
      ]);

      // The wrist is running sess-1 with the phone's sets and has logged one of
      // its own, which it still owes the phone.
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      await engine.applyMessage(radio.lastOfType('session_snapshot'));
      await wristLogsItsOwnSet();
      final held = [for (final entry in engine.entries) entry.entryId];
      final owed = engine.pendingObservations().length;
      expect(held, ['entry-slot-bench-0', _wristEntryId, 'entry-slot-bench-1']);
      expect(owed, 1);

      // The Sync runs and the phone does not answer: the radio carries the
      // request in, the answer is composed per request — and never delivered.
      radio.sent.clear();
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        radio.ofType('session_snapshot'),
        hasLength(1),
        reason: 'S-43 the phone composed exactly one answer to the request',
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        held,
        reason:
            'S-43 nothing reached the wrist, so nothing changed on it: it keeps '
            'its own row and the two the phone sent, each once',
      );
      expect(
        engine.pendingObservations().length,
        owed,
        reason: 'S-43 the wrist still owes the phone its own set',
      );

      // The same Sync, answered: the phone's sets arrive — and neither side
      // doubled or lost anything.
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      expect(
        await engine.applyMessage(radio.lastOfType('session_snapshot')),
        isTrue,
      );
      expect(
        [for (final entry in engine.entries) entry.entryId],
        ['entry-slot-bench-0', _wristEntryId, 'entry-slot-bench-1'],
        reason:
            'S-43 a later answered Sync converges exactly: the two sets the '
            'phone logged and the one the wrist logged, each once — an '
            'unreachable Sync queues nothing, so nothing is lost or doubled',
      );
      expect(reportedFailure, isNull);
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

  group('S-140…S-143 the phone projects the kinds it used to drop', () {
    /// The answer's entries by their own id, so a scenario reads one entry's
    /// fields without pinning the frame's order.
    Map<String, Map<String, Object?>> byId(Map<String, Object?> payload) => {
      for (final entry in _objects(payload['entries']))
        entry['entryId']! as String: entry,
    };

    /// The answer to one `snapshot` request, from the phone's own projection of
    /// the session it holds.
    Future<Map<String, Object?>> answer() async {
      await radio.fromWrist(WatchTransportRequest.snapshotFrame());
      await _settle();
      return radio.lastOfType('session_snapshot');
    }

    /// The round exercise these fixtures log: the catalog's own, so the slot
    /// carries a capability list and rides the answer at all.
    Future<void> seedRoundsExercise() => seedExercise(
      repository,
      id: 'ex-burpee',
      name: 'Burpees',
      capabilities: ['rounds', 'time'],
    );

    test('S-140 a phone timed entry reaches the wrist', () async {
      await _SessionFixture.seedEfforts(repository, phoneState, 'sess-t', [
        (
          slotId: 'slot-plank',
          exerciseId: 'ex-plank',
          effortKind: 'timed',
          write: () async {
            await repository.createTimedInstance(
              timedInstance(
                'slot-plank',
                0,
                durationSecs: 60,
                entryIndex: 1,
                startedAtMs: _at(1),
                finishedAtMs: _at(2),
              ),
            );
            await repository.createObservation(
              distanceRow('slot-plank', 1, 0, atMs: _at(2)),
            );
          },
        ),
      ]);

      final snapshot = await answer();
      final payload = _payload(snapshot);
      expect(_slotIds(payload), ['slot-plank']);
      expect(
        _entryIds(payload),
        ['entry-slot-plank-1'],
        reason:
            'D-131 the phone\'s timed record rides the answer, named by its '
            'slot and the record\'s own index',
      );
      final entry = _objects(payload['entries']).single;
      expect(entry['kind'], 'timed');
      expect(entry['sessionExerciseId'], 'slot-plank');
      expect(entry['exerciseId'], 'ex-plank');
      expect(entry['loggedAt'], _atIso(2));
      expect(entry['startedAt'], _atIso(1));
      expect(entry['endedAt'], _atIso(2));
      expect(
        entry.containsKey('distanceMeters'),
        isFalse,
        reason: 'D-132 a distance of 0 is omitted, never sent as 0',
      );
      expect(
        loadProtocolValidator().validateEnvelope(snapshot),
        isEmpty,
        reason: 'one entry the wire cannot carry rejects the whole snapshot',
      );

      expect(await engine.applyMessage(snapshot), isTrue);
      expect(
        [for (final record in engine.entries) record.entryId],
        ['entry-slot-plank-1'],
        reason: 'S-140 the wrist holds the entry the phone sent it',
      );
    });

    test('S-141 a round and a hold carry their own fields', () async {
      await seedRoundsExercise();
      await _SessionFixture.seedEfforts(repository, phoneState, 'sess-k', [
        (
          slotId: 'slot-burpee',
          exerciseId: 'ex-burpee',
          effortKind: 'round',
          write: () async {
            await repository.createRoundInstance(
              roundInstance(
                'slot-burpee',
                0,
              ).copyWith(totalPausedDurationMs: 5000),
            );
            await repository.createRoundInstance(
              roundInstance('slot-burpee', 1),
            );
          },
        ),
        (
          slotId: 'slot-hold',
          exerciseId: 'ex-plank',
          effortKind: 'drill',
          write: () async {
            await repository.createTimedInstance(
              timedInstance('slot-hold', 0, durationSecs: 30, entryIndex: 0),
            );
            await repository.createObservation(
              extraWeightRow('slot-hold', 0, 12, atMs: fixtureRowAt(0)),
            );
          },
        ),
      ]);

      final snapshot = await answer();
      final entries = byId(_payload(snapshot));
      expect(entries.keys.toSet(), {
        'entry-slot-burpee-0',
        'entry-slot-burpee-1',
        'entry-slot-hold-0',
      });
      expect(entries['entry-slot-burpee-0']!['kind'], 'round');
      expect(
        entries['entry-slot-burpee-0']!['roundNumber'],
        1,
        reason: 'D-130 a round index is 0-based on the phone, 1-based on the wire',
      );
      expect(
        entries['entry-slot-burpee-0']!['pausedMs'],
        5000,
        reason: 'D-130 a round carries the time it spent paused',
      );
      expect(entries['entry-slot-burpee-1']!['roundNumber'], 2);
      expect(
        entries['entry-slot-burpee-1']!.containsKey('pausedMs'),
        isFalse,
        reason: 'D-132 a round that was never paused sends no pause',
      );
      expect(
        entries['entry-slot-hold-0']!['kind'],
        'hold',
        reason:
            'D-130 a drill effort is a hold on the wire, the kind the wrist\'s '
            'own logger spells',
      );
      expect(
        entries['entry-slot-hold-0']!['extraLoadKg'],
        12.0,
        reason: 'D-130 a hold carries the weight it was held with',
      );
      expect(
        [
          entries['entry-slot-hold-0']!['startedAt'],
          entries['entry-slot-hold-0']!['endedAt'],
        ],
        [isA<String>(), isA<String>()],
        reason: 'D-130 a hold carries the window it was held over',
      );
      expect(loadProtocolValidator().validateEnvelope(snapshot), isEmpty);
    });

    test('S-142 a wrist-logged entry of any kind is not doubled', () async {
      await seedRoundsExercise();
      await _SessionFixture.seedEfforts(repository, phoneState, 'sess-c', [
        (
          slotId: 'slot-plank',
          exerciseId: 'ex-plank',
          effortKind: 'timed',
          write: () async {
            // The record the importer wrote for the wrist's own timed entry:
            // the importer stamps it with the row's `loggedAt` (fact (a)), so
            // the row's stamp still claims it.
            await repository.createTimedInstance(
              timedInstance(
                'slot-plank',
                0,
                durationSecs: 60,
                entryIndex: 0,
                startedAtMs: _at(1),
                finishedAtMs: _at(2),
              ).copyWith(createdAtMs: _at(2)),
            );
            await _SessionFixture.stageImportedEntry(
              repository,
              'sess-c',
              entryId: _wristEntryId,
              kind: WatchInboxEntry.kindTimed,
              slotId: 'slot-plank',
              exerciseId: 'ex-plank',
              loggedAtMs: _at(2),
            );
            await repository.createTimedInstance(
              timedInstance(
                'slot-plank',
                1,
                durationSecs: 30,
                entryIndex: 1,
                startedAtMs: _at(3),
                finishedAtMs: _at(4),
              ),
            );
          },
        ),
        (
          slotId: 'slot-burpee',
          exerciseId: 'ex-burpee',
          effortKind: 'round',
          write: () async {
            await repository.createRoundInstance(
              roundInstance(
                'slot-burpee',
                0,
                startedAtMs: _at(1),
                durationSecs: 60,
              ).copyWith(createdAtMs: _at(2)),
            );
            await _SessionFixture.stageImportedEntry(
              repository,
              'sess-c',
              entryId: _wristEntryId2,
              kind: WatchInboxEntry.kindRound,
              slotId: 'slot-burpee',
              exerciseId: 'ex-burpee',
              loggedAtMs: _at(2),
            );
            await repository.createRoundInstance(
              roundInstance(
                'slot-burpee',
                1,
                startedAtMs: _at(4),
                durationSecs: 60,
              ),
            );
          },
        ),
      ]);

      final snapshot = await answer();
      final entries = byId(_payload(snapshot));
      expect(
        _entryIds(_payload(snapshot)),
        ['entry-slot-plank-1', 'entry-slot-burpee-1'],
        reason:
            'D-133 one wrist entry produces at most one phone entry: neither '
            'wrist row rides back, and no claimed record rides twice',
      );
      expect(
        entries.keys.toSet(),
        {'entry-slot-plank-1', 'entry-slot-burpee-1'},
        reason:
            'D-133 the wrist\'s own timed and round entries claim their phone '
            'records, so neither rides back under a phone-minted id',
      );
      expect(
        {for (final entry in entries.values) entry['kind']},
        {'timed', 'round'},
      );
      expect(loadProtocolValidator().validateEnvelope(snapshot), isEmpty);
    });

    test(
      'D-133 a timed row never claims a round record written at the same '
      'millisecond',
      () async {
        await seedRoundsExercise();
        await _SessionFixture.seedEfforts(repository, phoneState, 'sess-k', [
          (
            slotId: 'slot-burpee',
            exerciseId: 'ex-burpee',
            effortKind: 'round',
            write: () async {
              // The wrist's own timed entry, imported at this millisecond, and
              // the record the importer wrote for it.
              await repository.createTimedInstance(
                timedInstance(
                  'slot-burpee',
                  0,
                  durationSecs: 60,
                  entryIndex: 0,
                  startedAtMs: _at(1),
                  finishedAtMs: _at(2),
                ).copyWith(createdAtMs: _at(2)),
              );
              await _SessionFixture.stageImportedEntry(
                repository,
                'sess-k',
                entryId: _wristEntryId,
                kind: WatchInboxEntry.kindTimed,
                slotId: 'slot-burpee',
                exerciseId: 'ex-burpee',
                loggedAtMs: _at(2),
              );
              // The phone's own round, written in that same millisecond: the
              // timed row is not its owner.
              await repository.createRoundInstance(
                roundInstance(
                  'slot-burpee',
                  0,
                  startedAtMs: _at(2),
                  durationSecs: 60,
                ).copyWith(createdAtMs: _at(2)),
              );
            },
          ),
        ]);

        final snapshot = await answer();
        final entries = byId(_payload(snapshot));
        expect(
          entries.keys.toSet(),
          {'entry-slot-burpee-0'},
          reason:
              'D-133 a row claims the records of its own kind alone: the round '
              'written in the same millisecond still rides the answer',
        );
        expect(entries['entry-slot-burpee-0']!['kind'], 'round');
        expect(
          loadProtocolValidator().validateEnvelope(snapshot),
          isEmpty,
          reason: 'the answer carrying both records is still a frame the wire accepts',
        );
        expect(
          await graph.adoption.heldWristEntryIds('sess-k'),
          contains(_wristEntryId),
          reason:
              'D-133 the timed row is held all the same: the timed record at '
              'that millisecond is the one that claims it',
        );
      },
    );

    test(
      'D-132 a hold held with nothing added is projected without the field',
      () async {
        await _SessionFixture.seedEfforts(repository, phoneState, 'sess-z', [
          (
            slotId: 'slot-hold',
            exerciseId: 'ex-plank',
            effortKind: 'drill',
            write: () async {
              await repository.createTimedInstance(
                timedInstance('slot-hold', 0, durationSecs: 30, entryIndex: 0),
              );
              // The writer's own shape for a hold with nothing added: the row
              // is written, carrying 0.
              await repository.createObservation(
                extraWeightRow('slot-hold', 0, 0, atMs: fixtureRowAt(0)),
              );
            },
          ),
        ]);

        final snapshot = await answer();
        final entry = byId(_payload(snapshot))['entry-slot-hold-0']!;
        expect(entry['kind'], 'hold');
        expect(
          entry.containsKey('extraLoadKg'),
          isFalse,
          reason: 'D-132 an added weight of exactly 0 is omitted, never sent',
        );
        expect(
          loadProtocolValidator().validateEnvelope(snapshot),
          isEmpty,
          reason: 'the hold as the wrist is sent it is a frame the wire accepts',
        );
      },
    );

    test('S-143 an unrepresentable instance is omitted, not faked', () async {
      await _SessionFixture.seedEfforts(repository, phoneState, 'sess-o', [
        (
          slotId: 'slot-plank',
          exerciseId: 'ex-plank',
          effortKind: 'timed',
          write: () async {
            await repository.createTimedInstance(
              timedInstance(
                'slot-plank',
                0,
                durationSecs: 0,
                entryIndex: 0,
                startedAtMs: 0,
                finishedAtMs: null,
                state: TimedState.notStarted,
              ),
            );
            await repository.createTimedInstance(
              timedInstance(
                'slot-plank',
                1,
                durationSecs: 0,
                entryIndex: 1,
                startedAtMs: _at(1),
                finishedAtMs: _at(1),
              ),
            );
            await repository.createTimedInstance(
              timedInstance(
                'slot-plank',
                2,
                durationSecs: 60,
                entryIndex: 2,
                startedAtMs: _at(1),
                finishedAtMs: _at(2),
              ),
            );
            // The writer's own shape: every entry index carries a distance row
            // and an added-load row, 0 where nothing was recorded
            // (`LoggedEntryRows.timedObservations`).
            for (var i = 0; i < 3; i++) {
              await repository.createObservation(
                distanceRow(
                  'slot-plank',
                  i,
                  i == 2 ? 250 : 0,
                  atMs: _at(2),
                  source: i == 2 ? EffortObservation.sourceEntered : null,
                ),
              );
              await repository.createObservation(
                extraWeightRow('slot-plank', i, 0, atMs: _at(2)),
              );
            }
          },
        ),
      ]);

      final snapshot = await answer();
      final payload = _payload(snapshot);
      expect(
        _entryIds(payload),
        ['entry-slot-plank-2'],
        reason:
            'D-132 an instance that never started and a window of no length are '
            'omitted, never placeheld',
      );
      final entry = _objects(payload['entries']).single;
      expect(entry['startedAt'], isNot(entry['endedAt']));
      expect(
        entry['distanceMeters'],
        250.0,
        reason: 'D-132 a distance above 0 rides the timed entry',
      );
      expect(entry['distanceSource'], EffortObservation.sourceEntered);
      expect(loadProtocolValidator().validateEnvelope(snapshot), isEmpty);
    });
  });

  group('S-109 the phone catches up on resume, once', () {
    test(
      'S-109 case A one resume is one catch-up: the phone\'s OWN session and '
      'then the request for the wrist\'s, once per resume',
      () async {
        await seed('sess-1', [
          (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(1)),
        ]);
        final ladderBefore = phoneSlots();
        final before = radio.sent.length;

        await graph.sync();

        final frames = radio.sent.sublist(before);
        expect(
          frames,
          hasLength(2),
          reason:
              'S-109 one resume is one catch-up: exactly one frame out and one '
              'frame asking, not a stream of them',
        );
        expect(
          frames.first['type'],
          'session_snapshot',
          reason:
              'S-109 the phone asserts its own session first — the half of the '
              'catch-up the wrist cannot learn any other way',
        );
        expect(frames.first['origin'], 'phone');
        expect(
          _payload(frames.first)['sessionId'],
          'sess-1',
          reason:
              'S-109 case A the frame is the phone\'s own session, composed '
              'from the projection (D-11) — not the mirror\'s converged copy, '
              'which here is still the placeholder this phone never asserted',
        );
        expect(
          _slotIds(_payload(frames.first)),
          ladderBefore,
          reason:
              'S-109 case A the ladder in the frame is the one the phone holds '
              'now, not a copy the mirror reconciled earlier',
        );
        expect(
          WatchTransportRequest.nameOf(frames.last),
          WatchTransportRequest.snapshot,
          reason:
              'S-109 and then asks the wrist for its own copy, which is how a '
              'session the wrist started while the phone was away arrives',
        );
        expect(
          phoneSlots(),
          ladderBefore,
          reason:
              'S-109 the trigger asks and stops there: the session the phone '
              'holds is untouched (no timer cleared, no navigation)',
        );

        final secondBefore = radio.sent.length;
        await graph.sync();
        expect(
          radio.sent.sublist(secondBefore),
          hasLength(2),
          reason: 'S-109 a second resume catches up again — one per resume',
        );
      },
    );

    test(
      'S-109 case B a phone holding no session sends no snapshot at all',
      () async {
        expect(
          phoneState.currentSession,
          isNull,
          reason: 'the fixture: nothing is running on the phone',
        );

        await graph.sync();

        expect(
          radio.ofType('session_snapshot'),
          isEmpty,
          reason:
              'S-109 case B the phone has no session of its own to assert: the '
              'mirror\'s converged copy is the placeholder, and a placeholder '
              'is not a session (D-11)',
        );
        expect(
          [
            for (final frame in radio.sent)
              if (frame['payload'] is Map)
                (frame['payload']! as Map)['sessionId'],
          ],
          isNot(contains('s-phone-unjoined')),
          reason:
              'S-109 case B nothing named the placeholder leaves this phone — a '
              'wrist holding nothing must not store a junk abandoned session',
        );
        expect(
          radio.sent,
          hasLength(1),
          reason:
              'S-109 case B the request is the whole catch-up when the phone '
              'has nothing to assert',
        );
        expect(
          WatchTransportRequest.nameOf(radio.sent.single),
          WatchTransportRequest.snapshot,
          reason:
              'S-109 case B and it is the request: asking the wrist for its '
              'copy is how a session started on the wrist arrives',
        );
        expect(reportedFailure, isNull);
      },
    );

    test(
      'S-109 case C the phone asserts its own session, never the wrist\'s copy',
      () async {
        await seed('sess-1', [
          (reps: 8, loadKg: 62.5, skipped: false, atMs: _at(1)),
        ]);
        final held = phoneState.currentSession!.id;

        // The wrist starts its own session and sends it; the phone refuses to
        // adopt it because it is already working through its own (D-10).
        await engine.createSession(
          modality: null,
          exercises: [
            _slot('wl-1', 'ex-squat', 'Squat', ['sets', 'reps', 'load']),
          ],
        );
        final wristSessionId = engine.session!.sessionId;
        await radio.fromWrist(engine.sessionSnapshot()!);
        await _settle();

        expect(
          skipped,
          [(held: held, offered: wristSessionId)],
          reason: 'the fixture: the phone refused the wrist\'s session',
        );
        expect(
          _slotIds(graph.mirror.state),
          ['wl-1'],
          reason:
              'the fixture: the mirror converged on the wrist\'s copy while the '
              'phone kept its own (S-6, D-10)',
        );

        radio.sent.clear();
        await graph.sync();

        final snapshot = radio.lastOfType('session_snapshot');
        expect(
          _payload(snapshot)['sessionId'],
          held,
          reason:
              'S-109 case C a resume asserts the session the phone is working '
              'through — composed from its own state (D-11)',
        );
        expect(
          _payload(snapshot)['sessionId'],
          isNot(wristSessionId),
          reason:
              'S-109 case C never the wrist\'s copy the mirror converged on: a '
              'resume must not hand the wrist back its own stale session',
        );
        expect(
          _slotIds(_payload(snapshot)),
          ['slot-bench'],
          reason:
              'S-109 case C and the ladder in it is the phone\'s own, not the '
              'converged copy\'s',
        );
        expect(reportedFailure, isNull);
      },
    );
  });
}
