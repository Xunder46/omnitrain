// A wrist timed, hold or round entry FILLS the phone's first unfinished
// interval instead of appending a new one.
//
// Plan: `docs/plans/2026-10-19-43a-timed-fill-plan/2026-10-19-43a-timed-fill-plan.md`,
// Phase P1 — D-1 (the target interval), D-2 (how the fill writes, row pairing
// included) and D-3 (no rest is opened).
// Scenario mapping:
//   S-5001 a wrist timed entry fills the unfinished interval  → `S-5001 ...`
//   S-5002 the target may be running or paused                → `S-5002a ...`,
//     `S-5002b ...`
//   S-5003 every interval finished: the entry appends          → `S-5003 ...`
//   S-5004 two wrist entries: fill, then append                → `S-5004 ...`
//   S-5005 redelivery                                          → `S-5005 ...`
//   S-5006 a hold fills a drill effort's unfinished interval   → `S-5006 ...`
//   S-5007 a round fills the unfinished round                  → `S-5007 ...`
//   S-5007b the filled interval is the wrist's own             → `S-5007b ...`
//
// Both groups run the same fixtures through the same phone: the fill must
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
import 'package:omnitrain/core/sync_protocol/phone_entries.dart';
import 'package:omnitrain/core/utils/entry_rows.dart';
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
const String _wristEntryId2 = 'sx-run-2';

/// The wrist's first window, `T1 < T3`, and a second entry's, `T4 < T5`.
const String _t1 = '2026-10-05T10:10:00Z';
const String _t3 = '2026-10-05T10:30:00Z';
const String _t4 = '2026-10-05T10:40:00Z';
const String _t5 = '2026-10-05T10:50:00Z';

/// The stamp the phone's own intervals and their rows carry: the plan wrote
/// them before the session, so it is earlier than every wrist entry's.
const String _plannedAt = '2026-10-05T09:00:00Z';

int _msOf(String iso) => DateTime.parse(iso).toUtc().millisecondsSinceEpoch;

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

/// Fixture T (D-1): the phone holds two intervals of [_slot], the first
/// finished and the second [secondState] — unlogged, which is what the wrist's
/// entry is about to fill. [finishBoth] makes every interval finished, so the
/// next entry has nothing to fill (S-5003).
Future<void> _phoneIntervals(
  WorkoutRepository repository, {
  TimedState secondState = TimedState.notStarted,
  bool finishBoth = false,
}) async {
  await _clearSeededIntervals(repository);
  final atMs = _msOf(_plannedAt);
  for (var index = 0; index < 2; index++) {
    final finished = finishBoth || index == 0;
    final state = finished ? TimedState.finished : secondState;
    await repository.createTimedInstance(
      TimedInstance(
        id: 'phone-ti-$index',
        effortId: _slot,
        entryIndex: index,
        actualDurationSecs: finished ? 120 : 0,
        startedAtMs: state == TimedState.notStarted ? 0 : atMs,
        finishedAtMs: finished ? atMs + 120000 : null,
        state: state,
        pausedAtMs: state == TimedState.paused ? atMs + 60000 : null,
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

/// Fixture for S-5010: the phone planned three intervals and deleted the
/// middle one, so its two remaining instances sit at `entryIndex` 0 and 1 while
/// their rows carry the numbers 0 and 2 — the hole a middle delete leaves.
Future<void> _phoneIntervalsHoled(WorkoutRepository repository) async {
  await _clearSeededIntervals(repository);
  final atMs = _msOf(_plannedAt);
  for (final (position, number) in [(0, 0), (1, 2)]) {
    final finished = position == 0;
    await repository.createTimedInstance(
      TimedInstance(
        id: 'phone-ti-$number',
        effortId: _slot,
        entryIndex: position,
        actualDurationSecs: finished ? 120 : 0,
        startedAtMs: finished ? atMs : 0,
        finishedAtMs: finished ? atMs + 120000 : null,
        state: finished ? TimedState.finished : TimedState.notStarted,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );
    for (final row in LoggedEntryRows.timedObservations(
      effortId: _slot,
      entryIndex: number,
      distanceMeters: 0.0,
      atMs: atMs,
    )) {
      await repository.createObservation(row);
    }
  }
}

/// Fixture for S-5011: phone interval 0 finished; the wrist's own interval 1
/// from an earlier pass, written without its rows; phone interval 2 unlogged
/// with its rows numbered 2.
Future<void> _halfWrittenWristPass(WorkoutRepository repository) async {
  await _clearSeededIntervals(repository);
  final atMs = _msOf(_plannedAt);
  await repository.createTimedInstance(
    TimedInstance(
      id: 'phone-ti-0',
      effortId: _slot,
      entryIndex: 0,
      actualDurationSecs: 120,
      startedAtMs: atMs,
      finishedAtMs: atMs + 120000,
      state: TimedState.finished,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  );
  for (final row in LoggedEntryRows.timedObservations(
    effortId: _slot,
    entryIndex: 0,
    distanceMeters: 0.0,
    atMs: atMs,
  )) {
    await repository.createObservation(row);
  }
  await repository.createTimedInstance(
    TimedInstance(
      id: WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      effortId: _slot,
      entryIndex: 1,
      actualDurationSecs: 1200,
      startedAtMs: _msOf(_t1),
      finishedAtMs: _msOf(_t3),
      state: TimedState.finished,
      createdAtMs: _msOf(_t3),
      updatedAtMs: _msOf(_t3),
    ),
  );
  await repository.createTimedInstance(
    TimedInstance(
      id: 'phone-ti-2',
      effortId: _slot,
      entryIndex: 2,
      actualDurationSecs: 0,
      startedAtMs: 0,
      state: TimedState.notStarted,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  );
  for (final row in LoggedEntryRows.timedObservations(
    effortId: _slot,
    entryIndex: 2,
    distanceMeters: 0.0,
    atMs: atMs,
  )) {
    await repository.createObservation(row);
  }
}

/// Fixture for S-5006: two drill intervals, the second unlogged, with the
/// phone's own 5 kg added load on each row.
Future<void> _phoneHolds(WorkoutRepository repository) async {
  await _clearSeededIntervals(repository);
  final atMs = _msOf(_plannedAt);
  for (var index = 0; index < 2; index++) {
    final finished = index == 0;
    await repository.createTimedInstance(
      TimedInstance(
        id: 'phone-ti-$index',
        effortId: _slot,
        entryIndex: index,
        actualDurationSecs: finished ? 120 : 0,
        startedAtMs: finished ? atMs : 0,
        finishedAtMs: finished ? atMs + 120000 : null,
        state: finished ? TimedState.finished : TimedState.notStarted,
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

/// Fixture for S-5007: two rounds, the second unlogged. A round effort has no
/// observation rows.
Future<void> _phoneRounds(WorkoutRepository repository) async {
  await _clearSeededIntervals(repository);
  final atMs = _msOf(_plannedAt);
  for (var index = 0; index < 2; index++) {
    final finished = index == 0;
    await repository.createRoundInstance(
      RoundInstance(
        id: 'phone-ri-$index',
        effortId: _slot,
        roundIndex: index,
        plannedDurationSecs: 180,
        actualDurationSecs: finished ? 180 : 0,
        startedAtMs: finished ? atMs : 0,
        finishedAtMs: finished ? atMs + 180000 : null,
        completed: finished,
        state: finished ? RoundState.finished : RoundState.notStarted,
        createdAtMs: atMs,
        updatedAtMs: atMs,
      ),
    );
  }
}

// ─── Reading what happened ──────────────────────────────────────────────────

/// The interval an adopted slot starts with: the fixtures below write the
/// phone's own intervals, so the adoption's first one goes first.
Future<void> _clearSeededIntervals(WorkoutRepository repository) async {
  for (final effort in await _efforts(repository)) {
    if (effort.effortKind == 'set') continue;
    for (final t in await repository.getTimedInstances(effort.id)) {
      await repository.deleteTimedInstance(t.id);
    }
    for (final r in await repository.getRoundInstances(effort.id)) {
      await repository.deleteRoundInstance(r.id);
    }
    for (final o in await repository.getEffortObservations(effort.id)) {
      await repository.deleteObservation(o.id);
    }
  }
}

Future<List<SegmentEffort>> _efforts(WorkoutRepository repository) async {
  final segments = await repository.getSessionSegments(_sessionId);
  return repository.getSegmentEfforts(segments.single.id);
}

/// One effort's timed instances, in the order their store returns them —
/// `entryIndex`, as the projection and the row pairing read them.
Future<List<TimedInstance>> _timedInstances(WorkoutRepository repository) =>
    repository.getTimedInstances(_slot);

Future<List<RoundInstance>> _roundInstances(WorkoutRepository repository) =>
    repository.getRoundInstances(_slot);

/// One effort's rows carrying [metricId], in id order.
Future<List<EffortObservation>> _rows(
  WorkoutRepository repository,
  String metricId,
) async => [
  for (final row in await sortedObservations(repository, _slot))
    if (row.metricId == metricId) row,
];

// ─── The scenarios ──────────────────────────────────────────────────────────

void main() {
  group('Mock', () => _fillTests(open: _openMock, close: () async {}));
  group('Hive', () => _fillTests(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('watch_timed_fill_');
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

/// The fixture's catalog: the run, the hold and the round exercise, each with
/// the capabilities that decide its effort kind.
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

void _fillTests({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test('S-5001 a wrist timed entry fills the unfinished interval', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    expect(
      phone.state.currentSession?.id,
      _sessionId,
      reason: 'S-5001 the phone holds the session the wrist is running',
    );
    expect(
      (await _efforts(repository)).single.effortKind,
      BlockTypes.timed,
      reason: 'S-5001 the slot is a timed effort on the phone',
    );
    await _phoneIntervals(repository);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-timed-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-5001 the wrist\'s entry fills interval 1 — it adds no third',
    );
    expect(
      instances[0].id,
      'phone-ti-0',
      reason: 'S-5001 the finished interval is untouched',
    );
    expect(
      instances[0].state,
      TimedState.finished,
      reason: 'S-5001 and still finished',
    );
    expect(
      instances[0].createdAtMs,
      _msOf(_plannedAt),
      reason: 'S-5001 with the plan\'s own stamp',
    );
    final filled = instances[1];
    expect(
      filled.id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-5001 the interval now holds the wrist\'s record',
    );
    expect(
      filled.entryIndex,
      1,
      reason: 'S-5001 at the position the unlogged interval held',
    );
    expect(
      filled.state,
      TimedState.finished,
      reason: 'S-5001 the wrist logged it, so it is finished',
    );
    expect(
      filled.startedAtMs,
      _msOf(_t1),
      reason: 'S-5001 carrying the wrist\'s window',
    );
    expect(filled.finishedAtMs, _msOf(_t3), reason: 'S-5001 to its end');
    expect(
      filled.createdAtMs,
      _msOf(_t3),
      reason:
          'S-5001 stamped with the wrist\'s loggedAt, so the projection sends '
          'it to nobody (D-2)',
    );

    final distances = await _rows(repository, MetricIds.distance);
    expect(
      distances,
      hasLength(2),
      reason: 'S-5001 the effort still holds two distance rows',
    );
    expect(
      distances[0].id,
      LoggedEntryRows.observationId(_slot, 0, 'distance'),
      reason: 'S-5001 interval 0\'s row is the phone\'s own',
    );
    expect(distances[0].valueReal, 0.0, reason: 'S-5001 and untouched');
    expect(
      distances[0].createdAtMs,
      _msOf(_plannedAt),
      reason: 'S-5001 with the plan\'s stamp',
    );
    expect(
      distances[1].id,
      LoggedEntryRows.observationId(_slot, 1, 'distance'),
      reason: 'S-5001 the filled interval\'s row keeps its number (D-2)',
    );
    expect(
      distances[1].valueReal,
      2500.0,
      reason: 'S-5001 and holds the wrist\'s distance',
    );
    expect(
      distances[1].valueSource,
      EffortObservation.sourceGps,
      reason: 'S-5001 with the source the wrist sent',
    );
    expect(
      distances[1].createdAtMs,
      _msOf(_t3),
      reason: 'S-5001 carrying the wrist\'s stamp',
    );
    expect(
      await repository.getEntryRests(_slot),
      isEmpty,
      reason: 'S-5001 D-3 no rest is opened for a timed fill',
    );
    expect(phone.failures, isEmpty);
  });

  for (final (label, state) in [
    ('S-5002a a running interval is filled', TimedState.active),
    ('S-5002b a paused interval is filled', TimedState.paused),
  ]) {
    test(label, () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _phoneIntervals(repository, secondState: state);
      expect(
        (await _timedInstances(repository)).last.state,
        state,
        reason: '$label the fixture\'s second interval is unfinished',
      );

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-timed-1'),
      );

      final instances = await _timedInstances(repository);
      expect(
        instances,
        hasLength(2),
        reason: '$label the unfinished interval is filled, not left running',
      );
      expect(
        instances[1].id,
        WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
        reason: '$label interval 1 holds the wrist\'s record',
      );
      expect(
        instances[1].state,
        TimedState.finished,
        reason: '$label and the wrist\'s window says it is finished',
      );
      expect(
        await _rows(repository, MetricIds.distance),
        hasLength(2),
        reason: '$label no third distance row appears',
      );
      expect(phone.failures, isEmpty);
    });
  }

  test('S-5003 every interval finished: the entry appends', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _phoneIntervals(repository, finishBoth: true);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-timed-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(3),
      reason: 'S-5003 with nothing unlogged the wrist\'s entry appends',
    );
    expect(
      [for (final instance in instances) instance.entryIndex],
      [0, 1, 2],
      reason: 'S-5003 after the last interval',
    );
    expect(
      instances[2].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-5003 the appended interval is the wrist\'s own record',
    );
    expect(
      instances[0].id,
      'phone-ti-0',
      reason: 'S-5003 and no phone row is removed',
    );
    expect(
      await _rows(repository, MetricIds.distance),
      hasLength(3),
      reason: 'S-5003 the appended interval brings its own distance row',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-5004 two wrist entries: fill, then append', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _phoneIntervals(repository);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
        _timed(
          _wristEntryId2,
          startedAt: _t4,
          endedAt: _t5,
          distanceMeters: 1000,
        ),
      ], messageId: 'msg-timed-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(3),
      reason: 'S-5004 the first entry fills, the second appends',
    );
    expect(
      [for (final instance in instances) instance.entryIndex],
      [0, 1, 2],
      reason: 'S-5004 in order, with no hole',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-5004 the first entry took the unlogged interval',
    );
    expect(
      instances[2].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId2),
      reason: 'S-5004 the second had nothing left to fill',
    );
    expect(
      [
        for (final row in await _rows(repository, MetricIds.distance))
          row.valueReal,
      ],
      [0.0, 2500.0, 1000.0],
      reason: 'S-5004 the rows stay paired with their intervals',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-5005 a redelivery writes nothing', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _phoneIntervals(repository);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-timed-1'),
    );
    final afterFirst = [
      for (final instance in await _timedInstances(repository))
        instance.toMap(),
    ];
    final rowsAfterFirst = [
      for (final row in await sortedObservations(repository, _slot))
        row.toMap(),
    ];

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-timed-1-again'),
    );

    expect(
      [
        for (final instance in await _timedInstances(repository))
          instance.toMap(),
      ],
      afterFirst,
      reason: 'S-5005 the redelivery re-fills and appends nothing',
    );
    expect(
      [
        for (final row in await sortedObservations(repository, _slot))
          row.toMap(),
      ],
      rowsAfterFirst,
      reason: 'S-5005 and rewrites no row',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-5006 a hold fills a drill effort\'s unfinished interval', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(capabilitiesName: 'hold'));
    expect(
      (await _efforts(repository)).single.effortKind,
      BlockTypes.drill,
      reason: 'S-5006 the slot is a drill effort on the phone',
    );
    await _phoneHolds(repository);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _hold(_wristEntryId, extraLoadKg: 10),
      ], messageId: 'msg-hold-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-5006 the wrist\'s hold fills interval 1',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-5006 the interval now holds the wrist\'s record',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-5006 and it is finished',
    );
    expect(
      instances[1].startedAtMs,
      _msOf(_t1),
      reason: 'S-5006 carrying the wrist\'s window',
    );
    final weights = await _rows(repository, MetricIds.extraWeight);
    expect(
      weights,
      hasLength(2),
      reason: 'S-5006 one extra-weight row per interval',
    );
    expect(
      weights[0].valueReal,
      5.0,
      reason: 'S-5006 interval 0\'s row is the phone\'s own',
    );
    expect(
      weights[0].id,
      LoggedEntryRows.observationId(_slot, 0, 'extra-weight'),
      reason: 'S-5006 and keeps its number',
    );
    expect(
      weights[1].id,
      LoggedEntryRows.observationId(_slot, 1, 'extra-weight'),
      reason: 'S-5006 the filled interval\'s row keeps its number (D-2)',
    );
    expect(
      weights[1].valueReal,
      10.0,
      reason: 'S-5006 and holds the load the wrist held',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-5007 a round fills the unfinished round', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot(capabilitiesName: 'round'));
    expect(
      (await _efforts(repository)).single.effortKind,
      BlockTypes.round,
      reason: 'S-5007 the slot is a round effort on the phone',
    );
    await _phoneRounds(repository);

    await phone.router.receive(
      observationsUp(_sessionId, [
        _round(_wristEntryId, roundNumber: 2),
      ], messageId: 'msg-round-1'),
    );

    final rounds = await _roundInstances(repository);
    expect(
      rounds,
      hasLength(2),
      reason: 'S-5007 the wrist\'s round fills round 1',
    );
    expect(
      [for (final round in rounds) round.roundIndex],
      [0, 1],
      reason: 'S-5007 with the positions unchanged',
    );
    expect(
      rounds[1].id,
      WatchSessionImporter.roundInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-5007 round 1 now holds the wrist\'s record',
    );
    expect(
      rounds[1].state,
      RoundState.finished,
      reason: 'S-5007 and the wrist\'s window says it is finished',
    );
    expect(
      rounds[1].completed,
      isTrue,
      reason: 'S-5007 completed, as an imported round is',
    );
    expect(
      rounds[1].startedAtMs,
      _msOf(_t1),
      reason: 'S-5007 carrying the wrist\'s window',
    );
    expect(rounds[1].finishedAtMs, _msOf(_t3), reason: 'S-5007 to its end');
    expect(
      await sortedObservations(repository, _slot),
      isEmpty,
      reason: 'S-5007 a round creates no observation rows',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-5007b the filled interval is the wrist\'s own', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _phoneIntervals(repository);
    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-timed-1'),
    );

    final projected = PhoneEntries.projectTimed(
      sessionExerciseId: _slot,
      exerciseId: _exerciseId,
      instances: await _timedInstances(repository),
      rows: await repository.getEffortObservations(_slot),
      wristLoggedAtMs: [_msOf(_t3)],
    );

    expect(
      projected,
      hasLength(1),
      reason:
          'S-5007b the filled interval is claimed by the wrist\'s own stamp; '
          'only the phone\'s interval is sent back',
    );
    expect(
      projected.single['entryId'],
      'entry-$_slot-0',
      reason: 'S-5007b the phone\'s interval 0 is the one projected',
    );
    expect(phone.failures, isEmpty);
  });

  test('S-5010 a hole in the row numbers: the fill keeps the pairing', () async {
    final phone = await _phone(repository);
    await phone.router.receive(_snapshot());
    await _phoneIntervalsHoled(repository);
    expect(
      [
        for (final instance in await _timedInstances(repository))
          instance.entryIndex,
      ],
      [0, 1],
      reason: 'S-5010 the fixture\'s two instances sit at positions 0 and 1',
    );
    expect(
      [
        for (final row in await _rows(repository, MetricIds.distance))
          EntryRows.numberInId(row.id),
      ],
      [0, 2],
      reason: 'S-5010 while their rows carry the numbers 0 and 2',
    );

    await phone.router.receive(
      observationsUp(_sessionId, [
        _timed(_wristEntryId),
      ], messageId: 'msg-timed-1'),
    );

    final instances = await _timedInstances(repository);
    expect(
      instances,
      hasLength(2),
      reason: 'S-5010 the fill takes the unlogged interval, it adds no third',
    );
    expect(
      [for (final instance in instances) instance.entryIndex],
      [0, 1],
      reason: 'S-5010 the positions are the intervals\', not the row numbers',
    );
    expect(
      instances[1].id,
      WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
      reason: 'S-5010 interval 1 holds the wrist\'s record',
    );
    expect(
      instances[1].state,
      TimedState.finished,
      reason: 'S-5010 the wrist logged it, so it is finished',
    );

    final distances = await _rows(repository, MetricIds.distance);
    expect(
      distances,
      hasLength(2),
      reason: 'S-5010 exactly two distance rows remain',
    );
    expect(
      [for (final row in distances) EntryRows.numberInId(row.id)],
      [0, 2],
      reason:
          'S-5010 the filled row keeps the doomed row\'s number (D-2), '
          'not the interval\'s position',
    );
    expect(
      [for (final row in distances) row.id],
      [
        LoggedEntryRows.observationId(_slot, 0, 'distance'),
        LoggedEntryRows.observationId(_slot, 2, 'distance'),
      ],
      reason: 'S-5010 the rows are numbered 0 and 2, never 1',
    );
    expect(
      [for (final row in distances) row.valueReal],
      [0.0, 2500.0],
      reason:
          'S-5010 interval 0\'s value is untouched, the filled one carries '
          'the wrist\'s distance',
    );

    final weights = await _rows(repository, MetricIds.extraWeight);
    expect(
      weights,
      hasLength(2),
      reason: 'S-5010 exactly two extra-weight rows remain',
    );
    expect(
      [for (final row in weights) EntryRows.numberInId(row.id)],
      [0, 2],
      reason: 'S-5010 the extra-weight row follows the same numbers',
    );
    expect(
      [for (final row in weights) row.id],
      [
        LoggedEntryRows.observationId(_slot, 0, 'extra-weight'),
        LoggedEntryRows.observationId(_slot, 2, 'extra-weight'),
      ],
      reason: 'S-5010 both metrics stay paired with their intervals',
    );
    expect(
      await repository.getEntryRests(_slot),
      isEmpty,
      reason: 'S-5010 D-3 no rest is opened for a timed fill',
    );
    expect(phone.failures, isEmpty);
  });

  test(
    'S-5011 a half-written earlier pass is finished in place, never another '
    'interval',
    () async {
      final phone = await _phone(repository);
      await phone.router.receive(_snapshot());
      await _halfWrittenWristPass(repository);
      expect(
        await _timedInstances(repository),
        hasLength(3),
        reason: 'S-5011 the fixture holds three intervals',
      );

      await phone.router.receive(
        observationsUp(_sessionId, [
          _timed(_wristEntryId),
        ], messageId: 'msg-timed-2'),
      );

      final instances = await _timedInstances(repository);
      expect(
        instances,
        hasLength(3),
        reason:
            'S-5011 the earlier pass\'s interval is finished in place — no '
            'phone interval is consumed',
      );
      expect(
        [for (final instance in instances) instance.entryIndex],
        [0, 1, 2],
        reason: 'S-5011 at the positions they held',
      );
      expect(
        instances[1].id,
        WatchSessionImporter.timedInstanceIdFor(_sessionId, _wristEntryId),
        reason: 'S-5011 interval 1 is the wrist\'s own from the earlier pass',
      );
      expect(
        instances[1].state,
        TimedState.finished,
        reason: 'S-5011 and it stays finished',
      );
      expect(
        instances[2].id,
        'phone-ti-2',
        reason: 'S-5011 the phone\'s later interval is untouched',
      );
      expect(
        instances[2].state,
        TimedState.notStarted,
        reason: 'S-5011 and still unlogged',
      );

      final distances = await _rows(repository, MetricIds.distance);
      expect(
        [for (final row in distances) EntryRows.numberInId(row.id)],
        [0, 1, 2],
        reason:
            'S-5011 the wrist\'s own place takes its rows; the phone\'s '
            'number 2 stays',
      );
      expect(
        distances[1].valueReal,
        2500.0,
        reason: 'S-5011 the earlier pass\'s missing rows are written now',
      );
      expect(
        distances[2].valueReal,
        0.0,
        reason: 'S-5011 and the phone\'s later interval keeps its own row',
      );
      expect(phone.failures, isEmpty);
    },
  );
}
