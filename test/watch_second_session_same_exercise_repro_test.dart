// Two wrist workouts of one exercise keep their efforts apart (plan 81,
// S-15001).
//
// The defect this guards: a wrist-made session named its exercise slots
// `sx-<exerciseId>` — the same text in every session — and the phone's adoption
// used that slot id AS the effort row's id, so the second workout's effort row
// replaced the first one's and took its sets with it. The wrist now suffixes
// every slot id it mints with a per-session token (`sx-<exerciseId>~<token>`),
// so each session's effort row is its own.
//
// Both sessions here are the wrist's own work: a real `WatchSessionEngine` and
// `WatchSessionStartPaths` pick the exercise, log the sets and end the
// workout, and the phone receives exactly the envelopes the engine emitted —
// no hand-written frames.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/capability.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/sync_protocol/message_validator.dart';
import 'package:omnitrain/core/utils/logged_entry_rows.dart';
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
import 'package:omnitrain/watch/logging/watch_logging_state.dart';
import 'package:omnitrain/watch/logging/watch_metric_stepping.dart';
import 'package:omnitrain/watch/session/in_memory_watch_session_store.dart';
import 'package:omnitrain/watch/session/watch_session_engine.dart';
import 'package:omnitrain/watch/start/watch_session_start_paths.dart';

import 'helpers/repository_harness.dart' show PathProviderChannel, seedExercise;
import 'helpers/sync_protocol_harness.dart';
import 'helpers/watch_capture_import_harness.dart' show CaptureTransport;

/// The exercise both workouts pick, as the phone's catalog holds it.
const String _exerciseId = 'ex-bench';

/// The phone's clock; nothing in the scenario moves it.
final DateTime _phoneNow = DateTime.utc(2026, 10, 26, 12);

final SyncProtocolValidator _validator = loadProtocolValidator();

/// The protocol's own `routines_down` fixture, with the bench exercise named
/// `ex-bench` — the catalog the wrist holds and both workouts pick from.
Map<String, Object?> _catalog() {
  final envelope = readProtocolJson('fixtures/valid/routines_down.json');
  final payload = asObject(envelope['payload']!);
  for (final routine in objectsOf(payload['routines']!)) {
    for (final segment in objectsOf(routine['segments']!)) {
      for (final effort in objectsOf(segment['efforts']!)) {
        if (effort['exerciseId'] == 'ex-barbell-bench-press') {
          effort['exerciseId'] = _exerciseId;
        }
      }
    }
  }
  for (final exercise in objectsOf(payload['fallbackExercises']!)) {
    if (exercise['exerciseId'] == 'ex-barbell-bench-press') {
      exercise['exerciseId'] = _exerciseId;
    }
  }
  return envelope;
}

/// A wrist: one engine over its own storage, the start paths on top, and every
/// message either of them emits recorded in [emitted] — what the phone will
/// later be fed.
class _Wrist {
  _Wrist(this.engine, this.paths, this.clock, this.emitted);

  final WatchSessionEngine engine;
  final WatchSessionStartPaths paths;
  final TestClock clock;
  final List<Map<String, Object?>> emitted;

  /// The value screen for the effort the session is on. A fresh instance per
  /// access, like the real surface: hold one in a local to dial and log on it.
  WatchLoggingState get surface =>
      WatchLoggingState(engine: engine, clock: clock.call);
}

/// A launched wrist: restored, holding its own storage, with the catalog a
/// phone synced down already in it.
Future<_Wrist> _wrist({
  required List<Map<String, Object?>> emitted,
  required String Function() sessionIdFactory,
}) async {
  final clock = TestClock(DateTime.utc(2026, 10, 26, 12));
  final store = InMemoryWatchSessionStore();
  var ids = 0;
  final engine = WatchSessionEngine(
    store,
    onEmit: emitted.add,
    validator: _validator,
    clock: clock.call,
    idFactory: () => 'rec-${++ids}',
    sessionIdFactory: sessionIdFactory,
  );
  final paths = WatchSessionStartPaths(
    engine: engine,
    store: store,
    validator: _validator,
    clock: clock.call,
    idFactory: () => 'cat-${++ids}',
  );
  await engine.restore();
  await paths.restore();
  return _Wrist(engine, paths, clock, emitted);
}

/// One set, logged the way the logging surface logs: the crown dials reps and
/// load, the confirm writes it.
Future<void> _logSet(
  WatchLoggingState surface, {
  double repsDetents = 2,
  double loadDetents = 33,
}) async {
  surface.adjust(WatchMetricKey.reps, repsDetents);
  if (loadDetents > 0) surface.adjust(WatchMetricKey.weight, loadDetents);
  await surface.log();
}

void main() {
  group('Mock', () => _repro(open: _openMock, close: () async {}));
  group('Hive', () => _repro(open: _openHive, close: _closeHive));
}

Future<WorkoutRepository> _openMock() async {
  final repository = MockWorkoutRepository();
  await repository.initialize();
  await _seed(repository);
  return repository;
}

Directory? _hiveDir;

Future<WorkoutRepository> _openHive() async {
  final dir = await Directory.systemTemp.createTemp('watch_repro_');
  _hiveDir = dir;
  PathProviderChannel.install(dir);
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

Future<void> _seed(WorkoutRepository repository) async {
  await seedExercise(
    repository,
    id: _exerciseId,
    name: 'Barbell Bench Press',
    capabilities: [
      ExerciseCapability.sets,
      ExerciseCapability.reps,
      ExerciseCapability.load,
    ],
  );
  await repository.setExerciseCapabilities(_exerciseId, const [
    ExerciseCapability.sets,
    ExerciseCapability.reps,
    ExerciseCapability.load,
  ]);
}

void _repro({
  required Future<WorkoutRepository> Function() open,
  required Future<void> Function() close,
}) {
  late WorkoutRepository repository;

  setUp(() async => repository = await open());
  tearDown(close);

  test('S-15001 two wrist workouts of one exercise keep their efforts apart', () async {
    // The wrist: two sessions of the same exercise, the first ended, the
    // second left active.
    final emitted = <Map<String, Object?>>[];
    var started = 0;
    final wrist = await _wrist(
      emitted: emitted,
      sessionIdFactory: () => 's-w${++started}',
    );
    final synced = await wrist.paths.applyRoutinesDown(_catalog());
    expect(
      synced.applied,
      isTrue,
      reason: 'the wrist took the catalog that holds $_exerciseId',
    );
    final bench = wrist.paths.fallbackExercises.firstWhere(
      (exercise) => exercise.exerciseId == _exerciseId,
    );

    // Workout 1: pick the exercise, log two sets, end it.
    await wrist.paths.startFreeWorkout();
    await wrist.paths.addExerciseToSession(bench);
    final first = wrist.surface;
    await _logSet(first);
    await _logSet(first, repsDetents: 1, loadDetents: 0);
    await wrist.engine.finishSession();

    // Workout 2: the same exercise, one set, left active.
    wrist.clock.advance(const Duration(minutes: 30));
    await wrist.paths.startFreeWorkout();
    await wrist.paths.addExerciseToSession(bench);
    final second = wrist.surface;
    await _logSet(second);

    // The phone: the same harness the repro has always run, fed EVERY envelope
    // the engine emitted, in order — what the wrist really sends, no
    // hand-written frames.
    final transport = CaptureTransport();
    late final WatchSessionAdoptionBridge bridge;
    final inbox = WatchSessionInbox(
      phoneOwnsSession: (id) => bridge.holdsSession(id),
      repository: repository,
      transport: transport,
      clock: () => _phoneNow,
      onFailure: (error, stack) => fail('inbox failed: $error'),
    );
    final mirror = LiveSessionMirrorState(
      transport: WatchInboxStagingTransport(inner: transport, inbox: inbox),
      snapshot: watchSessionPlaceholder,
      validator: _validator,
    );
    bridge = WatchSessionAdoptionBridge(
      repository: repository,
      clock: () => _phoneNow,
      onFailure: (error, stack) => fail('bridge failed: $error'),
    );
    final state = WorkoutState(repository);
    bridge.bindWorkoutState(state);
    final router = WatchIncomingRouter(
      inbox: inbox,
      mirror: mirror,
      nutrition: WatchNutritionLogBridge(
        nutrition: NutritionState(repository),
        library: FoodLibraryState(repository),
        validator: _validator,
        transport: transport,
      ),
      adoption: bridge,
    );

    expect(emitted, isNotEmpty, reason: 'the wrist sent its two workouts');
    final refused = <String>[];
    var fed = 0;
    for (final envelope in emitted) {
      final receipt = await router.receive(envelope);
      fed++;
      if (receipt.inbox == WatchInboxOutcome.refused ||
          receipt.session == MirrorOutcome.refused) {
        refused.add('${envelope['type']} (${envelope['messageId']})');
      }
    }
    expect(
      fed,
      emitted.length,
      reason: 'every envelope the wrist emitted went to the phone router',
    );
    expect(refused, isEmpty, reason: 'the phone refused: ${refused.join(', ')}');

    // What the phone holds, read back from the repository.
    final w1Efforts = await repository.getSegmentEfforts('segment-s-w1');
    final w2Efforts = await repository.getSegmentEfforts('segment-s-w2');
    expect(
      w1Efforts,
      hasLength(1),
      reason: 'workout 1 keeps exactly its own effort after workout 2 began',
    );
    expect(
      w2Efforts,
      hasLength(1),
      reason: 'workout 2 has exactly its own effort',
    );
    final w1 = w1Efforts.single;
    final w2 = w2Efforts.single;
    expect(
      w1.id,
      isNot(w2.id),
      reason: 'two sessions must not share one effort row',
    );
    expect(
      w1.segmentId,
      'segment-s-w1',
      reason: "the original defect moved workout 1's effort into workout 2",
    );

    // Workout 1's effort holds its two sets (entry indices 0 and 1); workout
    // 2's holds only its one (index 0).
    Future<Set<String>> repsRowsOf(String effortId) async => {
      for (final row in await repository.getEffortObservations(effortId))
        if (row.metricId == MetricIds.reps) row.id,
    };
    expect(
      await repsRowsOf(w1.id),
      {
        LoggedEntryRows.observationId(w1.id, 0, 'reps'),
        LoggedEntryRows.observationId(w1.id, 1, 'reps'),
      },
      reason: 'workout 1 keeps both of its sets',
    );
    expect(
      await repsRowsOf(w2.id),
      {LoggedEntryRows.observationId(w2.id, 0, 'reps')},
      reason: 'workout 2 holds only the set it logged',
    );
  });
}
