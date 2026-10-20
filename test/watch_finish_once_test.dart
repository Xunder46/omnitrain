// Finishing an interval on either device logs it once (plan 43c, D-1 and D-2).
//
// Plan: `docs/plans/2026-10-20-43c-finish-once-plan/2026-10-20-43c-finish-once-plan.md`,
// Phase P1.
// Scenario mapping:
//   S-6301 the entry fills the interval whose start is its own → `S-6301 ...`
//   S-6302 a paused interval is as good a target             → `S-6302 ...`
//   S-6302b a paused round is in progress                    → `S-6302b ...`
//   S-6303 the same for a hold (drill) and a round           → `S-6303a ...`,
//     `S-6303b ...`
//   S-6304 no start match: the in-progress one wins          → `S-6304 ...`
//   S-6305 two in progress, then neither matches             → `S-6305a ...`,
//     `S-6305b ...`
//   S-6306 the 1000 ms tolerance                             → `S-6306a ...`,
//     `S-6306b ...`
//   S-6307 nothing in progress: 43a's rule intact            → `S-6307a ...`,
//     `S-6307b ...`
//   S-6311 a duplicate is ignored, redelivery included       → `S-6311 ...`
//   S-6312 a duplicate hold and round                        → `S-6312a ...`,
//     `S-6312b ...`
//   S-6313 a start outside the tolerance is not a duplicate  → `S-6313 ...`
//   S-6314 the tolerance on the duplicate rule               → `S-6314a ...`,
//     `S-6314b ...`
//   S-6315 an entry's own half-written instance is not a duplicate of itself
//                                                            → `S-6315 ...`
//   S-6316 a rest following a duplicate lands on the phone's interval
//                                                            → `S-6316 ...`
//   S-6317 a half-written instance of the entry's own is finished, not
//     shadowed by a duplicate                              → `S-6317 ...`
// `test/watch_timed_fill_test.dart`'s S-5011 covers the other half of
// S-6315: an earlier pass's own place, readable, filled in place.
//
// Both groups run the same fixtures through the same phone: the merge must
// produce the same rows under `HiveWorkoutRepository` and
// `MockWorkoutRepository`. Plain `test()`: a Hive write inside a widget test's
// fake-async zone never drains.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/block_types.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/services/watch_session_importer.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/watch/live_session_mirror_state.dart';
import 'package:omnitrain/state/watch/watch_incoming_router.dart';
import 'package:omnitrain/state/watch/watch_nutrition_log_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_adoption_bridge.dart';
import 'package:omnitrain/state/watch/watch_session_inbox.dart';
import 'package:omnitrain/state/watch/watch_sync_wiring.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/watch/session/watch_records.dart';

import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart'
    show CaptureTransport, observationsUp, seedExercise, sortedObservations;

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The phone's clock when nothing in the scenario moves it.
final DateTime _phoneNow = DateTime.utc(2026, 10, 5, 11);

/// The session the phone holds and the slot its effort sits in (D-3: the
/// effort's id is its slot).
const String _sessionId = 's-w1';
const String _slot = 'sl-run';
const String _exerciseId = 'ex-run';
const String _wristEntryId = 'sx-run-1';

/// The wrist's window, `T1 < T3`, and a rest's, after it.
const String _t1 = '2026-10-05T10:10:00Z';
const String _t3 = '2026-10-05T10:30:00Z';
const String _t6 = '2026-10-05T10:31:00Z';

/// The stamp the phone's own intervals and their rows carry: the plan wrote
/// them before the session, so it is earlier than every wrist entry's.
const String _plannedAt = '2026-10-05T09:00:00Z';

/// A stamp that is neither the plan's nor the wrist entry's `loggedAt`: the
/// row that sits where an entry's own half-written instance was put, made by
/// something else.
const String _foreignAt = '2026-10-05T09:45:00Z';

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

/// The wrist entry's start, `S`.
int get _s => _msOf(_t1);

/// A clock a scenario can hold still.
class _Clock {
  DateTime now = _phoneNow;
}

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test` (`HiveWorkoutRepository.initialize()`
/// calls `Hive.initFlutter()`). Same pattern as
/// `test/watch_session_merge_test.dart`.
class _PathProviderChannel {
  static const MethodChannel _channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  static late Directory _root;

  static void install(Directory root) {
    _root = root;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
      case 'getTemporaryDirectory':
        return _root.path;
      default:
        return null;
    }
  }
}

/// One phone, wired the way `createWatchSync` wires it: the adoption bridge
/// first, the inbox that asks it whether a session is the phone's own, the
/// mirror behind the entry-staging transport, and the router that drives them.
class _Phone {
  _Phone({
    required this.repository,
    required this.transport,
    required this.router,
    required this.state,
    required this.bridge,
    required this.failures,
  });

  final WorkoutRepository repository;
  final CaptureTransport transport;
  final WatchIncomingRouter router;
  final WorkoutState state;
  final WatchSessionAdoptionBridge bridge;

  /// What the graph reported as a failure: nothing, in these scenarios.
  final List<Object> failures;
}

Future<_Phone> _phone(WorkoutRepository repository) async {
  final failures = <Object>[];
  final clock = _Clock();
  final transport = CaptureTransport();
  final bridge = WatchSessionAdoptionBridge(
    repository: repository,
    clock: () => clock.now,
    onFailure: (error, stack) => failures.add(error),
  );
  final inbox = WatchSessionInbox(
    repository: repository,
    transport: transport,
    validator: _validator,
    clock: () => clock.now,
    onHistoryChanged: () async {},
    onFailure: (error, stack) => fail('the watch session inbox failed: $error'),
    phoneOwnsSession: bridge.holdsSession,
    onSessionRowsChanged: bridge.refreshHeldEfforts,
  );
  final mirror = LiveSessionMirrorState(
    transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
    snapshot: watchSessionPlaceholder,
    validator: _validator,
    projection: bridge.projectSession,
  );
  final state = WorkoutState(repository);
  bridge.bindWorkoutState(state);

  return _Phone(
    repository: repository,
    transport: transport,
    router: WatchIncomingRouter(
      inbox: inbox,
      mirror: mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: NutritionState(repository),
        library: FoodLibraryState(repository),
        validator: _validator,
        transport: transport,
      ),
      adoption: bridge,
    ),
    state: state,
    bridge: bridge,
    failures: failures,
  );
}

// ─── Fixture T ──────────────────────────────────────────────────────────────

/// One ladder slot as the wrist sends it.
Map<String, Object?> _slotOf(String capabilitiesName) => {
  'sessionExerciseId': _slot,
  'exerciseId': _exerciseId,
  'name': 'Trail Run',
  'capabilities': switch (capabilitiesName) {
    'hold' => [ExerciseCapability.hold, ExerciseCapability.time],
    'round' => [ExerciseCapability.time, ExerciseCapability.rounds],
    _ => [ExerciseCapability.time, ExerciseCapability.distance],
  },
};

/// One `session_snapshot` from the wrist, adopting `s-w1` onto the phone with
/// a single slot whose kind the capabilities decide.
Map<String, Object?> _snapshot({
  String messageId = 'msg-snapshot',
  String capabilitiesName = 'timed',
}) => {
  'protocolVersion': SyncProtocolValidator.protocolVersion,
  'messageId': messageId,
  'sessionId': _sessionId,
  'type': 'session_snapshot',
  'origin': 'watch',
  'sentAt': '2026-10-05T10:00:00Z',
  'payload': {
    'sessionId': _sessionId,
    'revision': 3,
    'status': WatchSessionStatus.active,
    'currentExerciseIndex': 0,
    'exercises': [_slotOf(capabilitiesName)],
    'entries': <Object?>[],
    'timers': <String, Object?>{},
  },
};

/// A timed entry the wrist logged, 20 minutes and 2 500 m in the fixture.
Map<String, Object?> _timed(
  String entryId, {
  String startedAt = _t1,
  String endedAt = _t3,
  double? distanceMeters = 2500,
  String? distanceSource = 'gps',
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'timed',
  'loggedAt': endedAt,
  'sessionExerciseId': _slot,
  'exerciseId': _exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'distanceMeters': ?distanceMeters,
  if (distanceMeters != null && distanceSource != null)
    'distanceSource': distanceSource,
};

/// A hold entry the wrist logged, with the load it was held with.
Map<String, Object?> _hold(
  String entryId, {
  required double extraLoadKg,
  String startedAt = _t1,
  String endedAt = _t3,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'hold',
  'loggedAt': endedAt,
  'sessionExerciseId': _slot,
  'exerciseId': _exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'extraLoadKg': extraLoadKg,
};

/// A round entry the wrist logged.
Map<String, Object?> _round(
  String entryId, {
  required int roundNumber,
  String startedAt = _t1,
  String endedAt = _t3,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'round',
  'loggedAt': endedAt,
  'sessionExerciseId': _slot,
  'exerciseId': _exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'roundNumber': roundNumber,
};

/// A rest the wrist logged after [afterEntryId] (18b D-166).
Map<String, Object?> _rest(
  String entryId, {
  required String afterEntryId,
  String startedAt = _t3,
  String endedAt = _t6,
}) => {
  'entryId': entryId,
  'eventId': entryId,
  'kind': 'rest',
  'loggedAt': endedAt,
  'sessionExerciseId': _slot,
  'exerciseId': _exerciseId,
  'startedAt': startedAt,
  'endedAt': endedAt,
  'afterEntryId': afterEntryId,
};

/// One phone interval as a scenario writes it: where its clock started (0 when
/// it never did) and what state it holds.
typedef _TimedSpec = ({int startMs, TimedState state});
typedef _RoundSpec = ({int startMs, RoundState state});

/// The phone's timed intervals, written straight into the repository, with one
/// distance and one extra-weight row each — the rows the fill pairs with.
Future<void> _timedIntervals(
  WorkoutRepository repository,
  List<_TimedSpec> specs,
) async {
  final atMs = _msOf(_plannedAt);
  for (var index = 0; index < specs.length; index++) {
    final spec = specs[index];
    final finished = spec.state == TimedState.finished;
    await repository.createTimedInstance(
      TimedInstance(
        id: 'phone-ti-$index',
        effortId: _slot,
        entryIndex: index,
        actualDurationSecs: finished ? 120 : 0,
        startedAtMs: spec.startMs,
        finishedAtMs: finished ? spec.startMs + 120000 : null,
        state: spec.state,
        pausedAtMs: spec.state == TimedState.paused
            ? spec.startMs + 60000
            : null,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );
    for (final row in LoggedEntryRows.timedObservations(
      effortId: _slot,
      entryIndex: index,
      distanceMeters: 0.0,
      atMs: atMs,
    )) {
      await repository.createObservation(row);
    }
  }
}

/// The phone's drill intervals, with the phone's own 5 kg of added load on each
/// row (`test/watch_timed_fill_test.dart`'s S-5006 fixture).
Future<void> _holdIntervals(
  WorkoutRepository repository,
  List<_TimedSpec> specs,
) async {
  final atMs = _msOf(_plannedAt);
  for (var index = 0; index < specs.length; index++) {
    final spec = specs[index];
    final finished = spec.state == TimedState.finished;
    await repository.createTimedInstance(
      TimedInstance(
        id: 'phone-ti-$index',
        effortId: _slot,
        entryIndex: index,
        actualDurationSecs: finished ? 120 : 0,
        startedAtMs: spec.startMs,
        finishedAtMs: finished ? spec.startMs + 120000 : null,
        state: spec.state,
        pausedAtMs: spec.state == TimedState.paused
            ? spec.startMs + 60000
            : null,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );
    for (final row in LoggedEntryRows.drillObservations(
      effortId: _slot,
      entryIndex: index,
      extraWeightKg: 5.0,
      atMs: atMs,
    )) {
      await repository.createObservation(row);
    }
  }
}

/// The phone's rounds. A round effort has no observation rows.
Future<void> _roundIntervals(
  WorkoutRepository repository,
  List<_RoundSpec> specs,
) async {
  final atMs = _msOf(_plannedAt);
  for (var index = 0; index < specs.length; index++) {
    final spec = specs[index];
    final finished = spec.state == RoundState.finished;
    await repository.createRoundInstance(
      RoundInstance(
        id: 'phone-ri-$index',
        effortId: _slot,
        roundIndex: index,
        plannedDurationSecs: 180,
        actualDurationSecs: finished ? 180 : 0,
        startedAtMs: spec.startMs,
        finishedAtMs: finished ? spec.startMs + 180000 : null,
        completed: finished,
        state: spec.state,
        pausedAtMs: spec.state == RoundState.paused
            ? spec.startMs + 60000
            : null,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );
  }
}

/// Fixture for S-6315 and S-6317: the phone's interval 0 finished before the
/// wrist's start, and the entry's own instance sits at position 1 — written by
/// an earlier pass that never wrote its rows — next to a foreign row stamped
/// when the entry was not, so that position cannot be read as the entry's own
/// (the duplicate rule is what the pass reaches).
///
/// [ownState] and [ownStartMs] shape the half-written instance: S-6315's is
/// finished and starts with the entry, S-6317's was never started.
/// [phoneStartMs] is when the phone's interval 0 began.
Future<void> _ownInstanceHalfWritten(
  WorkoutRepository repository, {
  TimedState ownState = TimedState.finished,
  int? ownStartMs,
  int? phoneStartMs,
}) async {
  final ownFinished = ownState == TimedState.finished;
  await _timedIntervals(repository, [
    (
      startMs: phoneStartMs ?? _s - 60 * 60 * 1000,
      state: TimedState.finished,
    ),
  ]);
  final loggedAt = _msOf(_t3);
  await repository.createTimedInstance(
    TimedInstance(
      id: WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      effortId: _slot,
      entryIndex: 1,
      actualDurationSecs: ownFinished ? 1200 : 0,
      startedAtMs: ownStartMs ?? (ownFinished ? _s : 0),
      finishedAtMs: ownFinished ? loggedAt : null,
      state: ownState,
      createdAtMs: loggedAt,
      updatedAtMs: loggedAt,
    ),
  );
  for (final row in LoggedEntryRows.timedObservations(
    effortId: _slot,
    entryIndex: 1,
    distanceMeters: 400.0,
    atMs: _msOf(_foreignAt),
  )) {
    await repository.createObservation(row);
  }
}

// ─── Reading what happened ──────────────────────────────────────────────────

Future<List<SegmentEffort>> _efforts(WorkoutRepository repository) async {
  final segments = await repository.getSessionSegments(_sessionId);
  return repository.getSegmentEfforts(segments.single.id);
}

Future<List<TimedInstance>> _timedInstances(WorkoutRepository repository) =>
    repository.getTimedInstances(_slot);

Future<List<RoundInstance>> _roundInstances(WorkoutRepository repository) =>
    repository.getRoundInstances(_slot);

Future<List<EffortObservation>> _sortedRows(WorkoutRepository repository) =>
    sortedObservations(repository, _slot);

Future<int> _rowCount(WorkoutRepository repository) async =>
    (await _sortedRows(repository)).length;

// ─── The scenarios ──────────────────────────────────────────────────────────

void main() {
  group('Mock', () => _finishOnceTests(open: _openMock, close: () async {}));
  group('Hive', () => _finishOnceTests(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('watch_finish_once_');
  _hiveDir = dir;
  _PathProviderChannel.install(dir);
  Hive.init(dir.path);
  final repository = HiveWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Future<void> _closeHive() async {
  await Hive.deleteFromDisk();
  final dir = _hiveDir;
  if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  _hiveDir = null;
}

/// The fixture's catalog: the run, hold and round exercise, with the
/// capabilities that decide its effort kind.
Future<void> _seed(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: _exerciseId,
    name: 'Trail Run',
    capabilities: [
      ExerciseCapability.time,
      ExerciseCapability.distance,
      ExerciseCapability.hold,
      ExerciseCapability.rounds,
    ],
  );
}

void _finishOnceTests({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test('S-6301 the entry fills the interval whose start is its own', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: 0, state: TimedState.notStarted),
      (startMs: _s, state: TimedState.active),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6301 the entry fills the running interval, it adds no third',
    );
    expect(
      instances[0].id,
      'phone-ti-0',
      reason: 'S-6301 the untouched interval keeps its id',
    );
    expect(
      instances[0].state,
      TimedState.notStarted,
      reason: 'S-6301 and is still not started',
    );
    expect(
      instances[0].startedAtMs,
      0,
      reason: 'S-6301 with the start it never had',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6301 the interval that started with the entry holds it',
    );
    expect(
      instances[1].entryIndex,
      1,
      reason: 'S-6301 at the position it held',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-6301 and it is finished',
    );
    expect(
      instances[1].startedAtMs,
      _s,
      reason: 'S-6301 carrying the shared start',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6302 a paused interval is as good a target', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: 0, state: TimedState.notStarted),
      (startMs: _s, state: TimedState.paused),
    ]);
    expect(
      (await _timedInstances(repository))[1].pausedAtMs,
      isNotNull,
      reason: 'S-6302 the fixture\'s second interval is paused',
    );

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6302 the paused interval is filled, it adds no third',
    );
    expect(
      instances[0].state,
      TimedState.notStarted,
      reason: 'S-6302 the first interval is untouched',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6302 the paused interval holds the wrist\'s record',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-6302 the wrist logged it, so it is finished',
    );
    expect(instances[1].startedAtMs, _s, reason: 'S-6302 at the shared start');
    expect(phone.failures, isEmpty);
  });

  test('S-6302b a paused round is in progress', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(capabilitiesName: 'round'));
    await _roundIntervals(repository, [
      (startMs: 0, state: RoundState.notStarted),
      (startMs: _s, state: RoundState.paused),
    ]);
    expect(
      (await _roundInstances(repository))[1].pausedAtMs,
      isNotNull,
      reason: 'S-6302b the fixture\'s second round is paused',
    );

    await phone.router.receive(
      observationsUp(_sessionId, [
        _round(_wristEntryId, roundNumber: 2),
      ], messageId: 'msg-round-1'),
    );

    final rounds = await _roundInstances(repository);
    expect(
      rounds,
      hasLength(2),
      reason: 'S-6302b the paused round is filled, it adds no third',
    );
    expect(
      rounds[0].id,
      'phone-ri-0',
      reason: 'S-6302b the first round is untouched',
    );
    expect(
      rounds[0].state,
      RoundState.notStarted,
      reason: 'S-6302b and is still not started',
    );
    expect(
      rounds[1].id,
      WatchSessionImporter.roundInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6302b the paused round holds the wrist\'s record',
    );
    expect(
      rounds[1].state,
      RoundState.finished,
      reason: 'S-6302b the wrist logged it, so it is finished',
    );
    expect(rounds[1].startedAtMs, _s, reason: 'S-6302b at the shared start');
    expect(phone.failures, isEmpty);
  });

  test('S-6303a a hold fills the drill interval with its start', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(capabilitiesName: 'hold'));
    expect(
      (await _efforts(repository)).single.effortKind,
      BlockTypes.drill,
      reason: 'S-6303a the slot is a drill effort on the phone',
    );
    await _holdIntervals(repository, [
      (startMs: 0, state: TimedState.notStarted),
      (startMs: _s, state: TimedState.active),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _hold(_wristEntryId, extraLoadKg: 10),
      ], messageId: 'msg-hold-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6303a the hold fills the running interval',
    );
    expect(
      instances[0].id,
      'phone-ti-0',
      reason: 'S-6303a the untouched interval keeps its id',
    );
    expect(
      instances[0].state,
      TimedState.notStarted,
      reason: 'S-6303a and is still not started',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6303a the interval that started with the entry holds it',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-6303a and it is finished',
    );
    expect(instances[1].startedAtMs, _s, reason: 'S-6303a at the shared start');

    final weights = [
      for (final row in await _sortedRows(repository))
        if (row.metricId == MetricIds.extraWeight) row,
    ];
    expect(
      weights,
      hasLength(2),
      reason: 'S-6303a one extra-weight row per interval',
    );
    expect(
      weights[0].valueReal,
      5.0,
      reason: 'S-6303a interval 0\'s row is the phone\'s own',
    );
    expect(
      weights[1].valueReal,
      10.0,
      reason: 'S-6303a the filled interval holds the wrist\'s load',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6303b a round fills the round with its start', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(capabilitiesName: 'round'));
    expect(
      (await _efforts(repository)).single.effortKind,
      BlockTypes.round,
      reason: 'S-6303b the slot is a round effort on the phone',
    );
    await _roundIntervals(repository, [
      (startMs: 0, state: RoundState.notStarted),
      (startMs: _s, state: RoundState.active),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _round(_wristEntryId, roundNumber: 2),
      ], messageId: 'msg-round-1'),
    );

    final rounds = await _roundInstances(repository);
    expect(
      rounds,
      hasLength(2),
      reason: 'S-6303b the round fills the running one',
    );
    expect(
      rounds[0].id,
      'phone-ri-0',
      reason: 'S-6303b the untouched round keeps its id',
    );
    expect(
      rounds[0].state,
      RoundState.notStarted,
      reason: 'S-6303b and is still not started',
    );
    expect(
      rounds[1].id,
      WatchSessionImporter.roundInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6303b the round that started with the entry holds it',
    );
    expect(
      rounds[1].state,
      RoundState.finished,
      reason: 'S-6303b and the wrist\'s window says it is finished',
    );
    expect(rounds[1].startedAtMs, _s, reason: 'S-6303b at the shared start');
    expect(
      await _sortedRows(repository),
      isEmpty,
      reason: 'S-6303b a round creates no observation rows',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6304 without a start match the in-progress one wins', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: 0, state: TimedState.notStarted),
      (startMs: _s - 10 * 60 * 1000, state: TimedState.active),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6304 the in-progress interval is filled, no third appears',
    );
    expect(
      instances[0].state,
      TimedState.notStarted,
      reason: 'S-6304 the first interval is untouched',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6304 the running interval holds the wrist\'s record',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-6304 and it is finished',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-6305a of two in-progress intervals the shared start is filled',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _timedIntervals(repository, [
        (startMs: 0, state: TimedState.notStarted),
        (startMs: _s - 20 * 60 * 1000, state: TimedState.active),
        (startMs: _s, state: TimedState.paused),
      ]);

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-finish-1'),
      );

      final instances = await _timedInstances(repository);
      expect(
        instances,
        hasLength(3),
        reason: 'S-6305a the entry fills one interval and adds none',
      );
      expect(
        instances[1].id,
        'phone-ti-1',
        reason: 'S-6305a the earlier interval keeps its id',
      );
      expect(
        instances[1].state,
        TimedState.active,
        reason: 'S-6305a and stays active',
      );
      expect(
        instances[2].id,
        WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
        reason: 'S-6305a the interval that started with the entry holds it',
      );
      expect(
        instances[2].state,
        TimedState.finished,
        reason: 'S-6305a and is finished',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-6305b matching neither start, the first in-progress wins', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: 0, state: TimedState.notStarted),
      (startMs: _s - 20 * 60 * 1000, state: TimedState.active),
      (startMs: _s, state: TimedState.paused),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(
          _wristEntryId,
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            _s + 5 * 60 * 1000,
            isUtc: true,
          ).toIso8601String(),
        ),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(3),
      reason: 'S-6305b the entry fills one interval and adds none',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6305b the first in-progress interval is filled',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-6305b and it is finished',
    );
    expect(
      instances[2].id,
      'phone-ti-2',
      reason: 'S-6305b the paused interval keeps its id',
    );
    expect(
      instances[2].state,
      TimedState.paused,
      reason: 'S-6305b and stays paused',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6306a a start 400 ms from the phone\'s is the same start', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: _s - 5000, state: TimedState.active),
      (startMs: _s, state: TimedState.paused),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(
          _wristEntryId,
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            _s + 400,
            isUtc: true,
          ).toIso8601String(),
        ),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6306a the entry fills an interval and adds none',
    );
    expect(
      instances[0].id,
      'phone-ti-0',
      reason: 'S-6306a the other in-progress interval keeps its id',
    );
    expect(
      instances[0].state,
      TimedState.active,
      reason: 'S-6306a and stays active',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6306a within the tolerance the second interval is the match',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-6306a and it is finished',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6306b a start 5 s from the phone\'s is not the same start', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: _s - 5000, state: TimedState.active),
      (startMs: _s, state: TimedState.paused),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(
          _wristEntryId,
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            _s + 5000,
            isUtc: true,
          ).toIso8601String(),
        ),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6306b the entry fills an interval and adds none',
    );
    expect(
      instances[0].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason:
          'S-6306b no start matches, so the first in-progress one is filled',
    );
    expect(
      instances[0].state,
      TimedState.finished,
      reason: 'S-6306b and it is finished',
    );
    expect(
      instances[1].id,
      'phone-ti-1',
      reason: 'S-6306b the other interval keeps its id',
    );
    expect(
      instances[1].state,
      TimedState.paused,
      reason: 'S-6306b and stays paused',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-6307a nothing in progress: the first not-finished is filled',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _timedIntervals(repository, [
        (startMs: 0, state: TimedState.notStarted),
        (startMs: 0, state: TimedState.notStarted),
      ]);

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-finish-1'),
      );

      final instances = await _timedInstances(repository);
      expect(
        instances,
        hasLength(2),
        reason:
            'S-6307a 43a\'s rule stands: the first unlogged interval is filled',
      );
      expect(
        instances[0].id,
        WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
        reason: 'S-6307a interval 0 holds the wrist\'s record',
      );
      expect(
        instances[0].state,
        TimedState.finished,
        reason: 'S-6307a and it is finished',
      );
      expect(
        instances[1].id,
        'phone-ti-1',
        reason: 'S-6307a the second interval is untouched',
      );
      expect(
        instances[1].state,
        TimedState.notStarted,
        reason: 'S-6307a and still not started',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-6307b every interval finished: the entry appends', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: _s - 10 * 60 * 1000, state: TimedState.finished),
      (startMs: _s - 5 * 60 * 1000, state: TimedState.finished),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(3),
      reason: 'S-6307b with nothing unfinished the entry appends',
    );
    expect(
      [for (final instance in instances) instance.entryIndex],
      [0, 1, 2],
      reason: 'S-6307b after the last interval',
    );
    expect(
      instances[2].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6307b the appended interval is the wrist\'s own record',
    );
    expect(
      instances[0].id,
      'phone-ti-0',
      reason: 'S-6307b and no phone interval is removed',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-6311 a second report of an interval the phone logged is ignored',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _timedIntervals(repository, [
        (startMs: _s, state: TimedState.finished),
        (startMs: 0, state: TimedState.notStarted),
      ]);
      final before = [
        for (final instance in await _timedInstances(repository))
          instance.toMap(),
      ];
      final rowsBefore = await _rowCount(repository);
      expect(
        (await _timedInstances(repository))[0].actualDurationSecs,
        120,
        reason: 'S-6311 the fixture\'s interval 0 was logged by the phone',
      );

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-finish-1'),
      );

      expect(
        [
          for (final instance in await _timedInstances(repository))
            instance.toMap(),
        ],
        before,
        reason: 'S-6311 the phone keeps the entry it already has',
      );
      expect(
        await _timedInstances(repository),
        hasLength(2),
        reason: 'S-6311 the duplicate adds no interval',
      );
      expect(
        await _rowCount(repository),
        rowsBefore,
        reason: 'S-6311 and writes no observation row',
      );
      expect(phone.failures, isEmpty);

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-finish-1-again'),
      );

      expect(
        [
          for (final instance in await _timedInstances(repository))
            instance.toMap(),
        ],
        before,
        reason: 'S-6311 a redelivery of the same message is the same',
      );
      expect(
        await _rowCount(repository),
        rowsBefore,
        reason: 'S-6311 and rewrites no row',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-6312a a second report of a hold is ignored', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(capabilitiesName: 'hold'));
    await _holdIntervals(repository, [
      (startMs: _s, state: TimedState.finished),
      (startMs: 0, state: TimedState.notStarted),
    ]);
    final before = [
      for (final instance in await _timedInstances(repository))
        instance.toMap(),
    ];
    final rowsBefore = await _rowCount(repository);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _hold(_wristEntryId, extraLoadKg: 10),
      ], messageId: 'msg-hold-1'),
    );

    expect(
      [
        for (final instance in await _timedInstances(repository))
          instance.toMap(),
      ],
      before,
      reason: 'S-6312a the phone keeps the hold it already has',
    );
    expect(
      await _rowCount(repository),
      rowsBefore,
      reason: 'S-6312a and writes no extra-weight row',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6312b a second report of a round is ignored', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(capabilitiesName: 'round'));
    await _roundIntervals(repository, [
      (startMs: _s, state: RoundState.finished),
      (startMs: 0, state: RoundState.notStarted),
    ]);
    final before = [
      for (final round in await _roundInstances(repository)) round.toMap(),
    ];

    await phone.router.receive(
      observationsUp(_sessionId, [
        _round(_wristEntryId, roundNumber: 2),
      ], messageId: 'msg-round-1'),
    );

    expect(
      [for (final round in await _roundInstances(repository)) round.toMap()],
      before,
      reason: 'S-6312b the phone keeps the round it already has',
    );
    expect(
      await _roundInstances(repository),
      hasLength(2),
      reason: 'S-6312b the duplicate adds no round',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-6313 a start outside the tolerance is not a duplicate', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: _s - 30 * 1000, state: TimedState.finished),
      (startMs: 0, state: TimedState.notStarted),
    ]);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6313 the entry fills the not-finished interval',
    );
    expect(
      instances[0].id,
      'phone-ti-0',
      reason: 'S-6313 the phone\'s finished interval is untouched',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6313 interval 1 holds the wrist\'s record',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-6313 and it is finished',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-6314a a phone start 400 ms away makes the entry a duplicate',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _timedIntervals(repository, [
        (startMs: _s + 400, state: TimedState.finished),
        (startMs: 0, state: TimedState.notStarted),
      ]);
      final before = [
        for (final instance in await _timedInstances(repository))
          instance.toMap(),
      ];

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-finish-1'),
      );

      expect(
        [
          for (final instance in await _timedInstances(repository))
            instance.toMap(),
        ],
        before,
        reason: 'S-6314a inside the tolerance the entry is a duplicate',
      );
      expect(
        await _timedInstances(repository),
        hasLength(2),
        reason: 'S-6314a so the count stays 2',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test('S-6314b a phone start 5 s away is no duplicate', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _timedIntervals(repository, [
      (startMs: _s + 5000, state: TimedState.finished),
      (startMs: 0, state: TimedState.notStarted),
    ]);
    final before = [
      for (final instance in await _timedInstances(repository))
        instance.toMap(),
    ];

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-finish-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-6314b the entry fills the not-finished interval',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-6314b outside the tolerance interval 1 holds the record',
    );
    expect(
      instances[0].toMap(),
      before[0],
      reason: 'S-6314b the phone\'s finished interval is untouched',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-6315 an entry\'s own half-written instance is not a duplicate of itself',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _ownInstanceHalfWritten(repository);
      final foreignRows = [
        for (final row in await _sortedRows(repository))
          if (row.createdAtMs == _msOf(_foreignAt)) row,
      ];
      expect(
        foreignRows,
        hasLength(2),
        reason:
            'S-6315 the fixture puts a foreign row at the instance\'s '
            'position, so that position is not readable as the entry\'s own',
      );

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-finish-1'),
      );

      final rows = await _sortedRows(repository);
      final stamped = [
        for (final row in rows)
          if (row.metricId == MetricIds.distance &&
              row.createdAtMs == _msOf(_t3))
            row,
      ];
      expect(
        stamped,
        hasLength(1),
        reason: 'S-6315 the entry is written, not dropped as its own duplicate',
      );
      expect(
        stamped.single.valueReal,
        2500.0,
        reason: 'S-6315 carrying the wrist\'s distance',
      );
      expect(
        stamped.single.id,
        LoggedEntryRows.observationId(_slot, 2, 'distance'),
        reason: 'S-6315 after the position the half-written instance holds',
      );
      expect(
        [
          for (final row in rows)
            if (row.createdAtMs == _msOf(_foreignAt)) row.toMap(),
        ],
        [for (final row in foreignRows) row.toMap()],
        reason: 'S-6315 the foreign row keeps its own record untouched',
      );
      expect(
        await _timedInstances(repository),
        hasLength(2),
        reason: 'S-6315 the entry adds no interval',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test(
    'S-6316 a rest after a duplicate lands on the phone\'s interval',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _timedIntervals(repository, [
        (startMs: _s, state: TimedState.finished),
        (startMs: 0, state: TimedState.notStarted),
      ]);

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
          _rest('sx-rest-1', afterEntryId: _wristEntryId),
        ], messageId: 'msg-finish-1'),
      );

      final rests = await repository.getEntryRests(_slot);
      expect(rests, hasLength(1), reason: 'S-6316 exactly one rest is written');
      expect(
        rests.single.entryIndex,
        1,
        reason: 'S-6316 it follows the phone\'s finished interval 0',
      );
      expect(
        rests.single.restStartMs,
        _msOf(_t3),
        reason: 'S-6316 with the wrist\'s start',
      );
      expect(rests.single.restEndMs, _msOf(_t6), reason: 'S-6316 to its end');
      expect(
        await _timedInstances(repository),
        hasLength(2),
        reason: 'S-6316 and the duplicate still adds no interval',
      );
      expect(phone.failures, isEmpty);
    },
  );

  test(
    'S-6317 a half-written instance of the entry\'s own is finished, not '
    'shadowed by a duplicate',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _ownInstanceHalfWritten(
        repository,
        ownState: TimedState.notStarted,
        ownStartMs: 0,
        phoneStartMs: _s,
      );
      final ownId = WatchSessionImporter.timedInstanceIdFor(
        _sessionId,
        _wristEntryId,
      );
      final phoneBefore = [
        for (final instance in await _timedInstances(repository))
          if (instance.id == 'phone-ti-0') instance.toMap(),
      ];

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-finish-1'),
      );

      final instances = await _timedInstances(repository);
      expect(
        instances,
        hasLength(2),
        reason: 'S-6317 the entry repairs its own instance, it adds no third',
      );
      final own = instances.singleWhere((instance) => instance.id == ownId);
      expect(
        own.state,
        TimedState.finished,
        reason: 'S-6317 the instance the entry began is finished, not dropped',
      );
      expect(
        own.startedAtMs,
        _s,
        reason: 'S-6317 and it starts with the entry',
      );
      expect(
        [
          for (final instance in instances)
            if (instance.id == 'phone-ti-0') instance.toMap(),
        ],
        phoneBefore,
        reason: 'S-6317 the phone\'s finished interval is untouched',
      );
      expect(phone.failures, isEmpty);
    },
  );
}
