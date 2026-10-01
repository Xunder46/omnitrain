// Entry identity (Stats PR 3a2) — the repository harness and the shared
// fixtures every scenario of the plan runs on.
//
// The scenarios marked "Reopened" need the same storage read back by a fresh
// repository, and the ones marked "Mock and Hive" must end identical on both,
// so both live here rather than in each test file.
//
// Plan: `docs/plans/2026-09-27-03a2-stats-pr3a2-entry-identity-plan.md`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test`.
class PathProviderChannel {
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

/// Opens one repository implementation, and reopens it over the same storage as
/// an app restart would.
abstract class RepositoryHarness {
  String get name;
  Future<WorkoutRepository> open();

  /// A repository over the same storage, as after an app restart.
  Future<WorkoutRepository> restart();
  Future<void> close();
}

class MockRepositoryHarness implements RepositoryHarness {
  MockWorkoutRepository? _repo;

  @override
  String get name => 'Mock';

  @override
  Future<WorkoutRepository> open() async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    return _repo = repo;
  }

  /// In-memory storage has no restart: the same store comes back.
  @override
  Future<WorkoutRepository> restart() async => _repo!;

  @override
  Future<void> close() async {}
}

class HiveRepositoryHarness implements RepositoryHarness {
  Directory? _dir;

  @override
  String get name => 'Hive';

  @override
  Future<WorkoutRepository> open() async {
    final dir = await Directory.systemTemp.createTemp('entry_identity_');
    _dir = dir;
    PathProviderChannel.install(dir);
    Hive.init(dir.path);
    final repo = HiveWorkoutRepository();
    await repo.initialize();
    return repo;
  }

  @override
  Future<WorkoutRepository> restart() async {
    await Hive.close();
    final repo = HiveWorkoutRepository();
    await repo.initialize();
    return repo;
  }

  @override
  Future<void> close() async {
    await Hive.deleteFromDisk();
    final dir = _dir;
    if (dir != null && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

/// One factory per implementation, so a group can name the store under test.
List<RepositoryHarness Function()> get harnessFactories =>
    <RepositoryHarness Function()>[
      MockRepositoryHarness.new,
      HiveRepositoryHarness.new,
    ];

// ─── Shared times ───────────────────────────────────────────────────────────

/// A completed session's start, a day back, so Stats sees it as history.
int get fixtureStart => DateTime.now().millisecondsSinceEpoch - 86400000;

/// The row timestamp of fixture entry n: later for higher n, so that a rule
/// reading `createdAtMs` as a tiebreak sees the order the rows were written in.
int fixtureRowAt(int n) => fixtureStart + 1000 + n;

// ─── Sessions, exercises and efforts ────────────────────────────────────────

/// A session holding one segment, for a fixture to hang its efforts on.
Future<void> seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  String? modality,
  bool isRolling = false,
  int daysAgo = 1,
}) async {
  final start = fixtureStart - (daysAgo - 1) * 86400000;
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: start,
      endedAtMs: isRolling ? null : start + 3600000,
      modality: modality,
      isRolling: isRolling,
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: start,
      updatedAtMs: start,
    ),
  );
}

Future<void> seedExercise(
  WorkoutRepository repo, {
  required String id,
  required String name,
  List<String> capabilities = const [],
}) async {
  final at = fixtureStart;
  await repo.createExercise(
    Exercise(
      id: id,
      name: name,
      capabilities: capabilities,
      createdAtMs: at,
      updatedAtMs: at,
    ),
  );
}

/// FX-12SETS: twelve weighted sets on a barbell movement, reps n+1 and weight
/// 10(n+1) kg, written in order.
Future<void> seedWeightedSets(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  String exerciseId = 'ex-row',
}) async {
  await seedExercise(repo, id: exerciseId, name: 'Row', capabilities: ['load']);
  await seedSetEffort(
    repo,
    segmentId: segmentId,
    effortId: effortId,
    exerciseId: exerciseId,
    entryCount: 12,
    hasExtraWeight: false,
  );
}

/// FX-12PULL: twelve bodyweight sets, reps n+1 and extra weight n kg — the
/// fixture whose rows the id pattern could not read, so every bodyweight effort
/// fell back to the store's own order (G3).
Future<void> seedBodyweightSets(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  String exerciseId = 'ex-pull',
}) async {
  await seedExercise(repo, id: exerciseId, name: 'Pull-up');
  await seedSetEffort(
    repo,
    segmentId: segmentId,
    effortId: effortId,
    exerciseId: exerciseId,
    entryCount: 12,
    hasExtraWeight: true,
    weightFactor: 0.0,
  );
}

/// FX-12TIMED: twelve finished instances of 60 s, distances (n+1)×100 m and
/// extra weights n kg.
Future<void> seedTimedEntries(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  int entryCount = 12,
  String exerciseId = 'ex-run',
  String exerciseName = 'Easy Run',
  int secondsPerEntry = 60,
  double metresBase = 100.0,
}) async {
  await seedExercise(repo, id: exerciseId, name: exerciseName);
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );

  for (var n = 0; n < entryCount; n++) {
    await repo.createTimedInstance(
      timedInstance(effortId, n, durationSecs: secondsPerEntry, entryIndex: n),
    );
    await repo.createObservation(
      distanceRow(effortId, n, (n + 1) * metresBase, atMs: fixtureRowAt(n)),
    );
    await repo.createObservation(
      extraWeightRow(effortId, n, n.toDouble(), atMs: fixtureRowAt(n)),
    );
  }
}

/// A repeated effort on [segmentId]: one finished instance per entry, plus
/// whatever [rows] the fixture stores. [effortKind] is `drill` (a hold) unless
/// the fixture needs a plain timed effort.
Future<void> seedHoldEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
  required int entryCount,
  List<EffortObservation> rows = const [],
  int secondsPerEntry = 60,
  String effortKind = 'drill',
}) async {
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      effortKind: effortKind,
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  for (var n = 0; n < entryCount; n++) {
    await repo.createTimedInstance(
      timedInstance(effortId, n, durationSecs: secondsPerEntry, entryIndex: n),
    );
  }
  for (final row in rows) {
    await repo.createObservation(row);
  }
}

/// A set effort and its rows: entry n reads reps n+1, weight 10(n+1) kg, and —
/// when [hasExtraWeight] — extra weight n kg.
Future<void> seedSetEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
  required int entryCount,
  required bool hasExtraWeight,
  double weightFactor = 10.0,
  int repsBase = 1,
  List<int>? numbers,
  List<int>? extraWeightNumbers,
}) async {
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );

  final entryNumbers = numbers ?? [for (var n = 0; n < entryCount; n++) n];
  for (final n in entryNumbers) {
    await repo.createObservation(
      repsRow(effortId, n, repsBase + n, atMs: fixtureRowAt(n)),
    );
    await repo.createObservation(
      weightRow(effortId, n, weightFactor * (n + 1), atMs: fixtureRowAt(n)),
    );
    if (hasExtraWeight &&
        (extraWeightNumbers == null || extraWeightNumbers.contains(n))) {
      await repo.createObservation(
        extraWeightRow(effortId, n, n.toDouble(), atMs: fixtureRowAt(n)),
      );
    }
  }
}

// ─── Rows and instances ─────────────────────────────────────────────────────

EffortObservation distanceRow(
  String effortId,
  int entryNumber,
  double metres, {
  required int atMs,
  String? source,
  String? id,
}) => EffortObservation(
  id: id ?? 'obs-$effortId-$entryNumber-distance',
  effortId: effortId,
  metricId: MetricIds.distance,
  unitId: MetricIds.unitMeters,
  valueReal: metres,
  valueSource: source,
  createdAtMs: atMs,
  updatedAtMs: atMs,
);

EffortObservation repsRow(
  String effortId,
  int entryNumber,
  int reps, {
  required int atMs,
  bool skipped = false,
  String? id,
}) => EffortObservation(
  id: id ?? 'obs-$effortId-$entryNumber-reps',
  effortId: effortId,
  metricId: MetricIds.reps,
  unitId: MetricIds.unitReps,
  valueInt: reps,
  valueBool: skipped ? true : null,
  createdAtMs: atMs,
  updatedAtMs: atMs,
);

EffortObservation weightRow(
  String effortId,
  int entryNumber,
  double kg, {
  required int atMs,
  String? id,
}) => EffortObservation(
  id: id ?? 'obs-$effortId-$entryNumber-weight',
  effortId: effortId,
  metricId: MetricIds.weight,
  unitId: MetricIds.unitKg,
  valueReal: kg,
  createdAtMs: atMs,
  updatedAtMs: atMs,
);

EffortObservation extraWeightRow(
  String effortId,
  int entryNumber,
  double kg, {
  required int atMs,
  String? id,
}) => EffortObservation(
  id: id ?? 'obs-$effortId-$entryNumber-extra-weight',
  effortId: effortId,
  metricId: MetricIds.extraWeight,
  unitId: MetricIds.unitKg,
  valueReal: kg,
  createdAtMs: atMs,
  updatedAtMs: atMs,
);

TimedInstance timedInstance(
  String effortId,
  int entryNumber, {
  required int durationSecs,
  required int entryIndex,
  TimedState state = TimedState.finished,
  int? startedAtMs,
  int? finishedAtMs,
}) {
  final start = startedAtMs ?? fixtureStart + entryIndex * 60000;
  return TimedInstance(
    id: 'ti-$effortId-$entryIndex',
    effortId: effortId,
    entryIndex: entryIndex,
    targetDurationSecs: durationSecs,
    actualDurationSecs: state == TimedState.finished ? durationSecs : 0,
    startedAtMs: start,
    finishedAtMs:
        finishedAtMs ??
        (state == TimedState.finished ? start + durationSecs * 1000 : null),
    state: state,
    createdAtMs: fixtureStart,
    updatedAtMs: fixtureStart,
  );
}

// ─── State and reads ────────────────────────────────────────────────────────

Future<WorkoutState> loadState(WorkoutRepository repo, String sessionId) async {
  final state = WorkoutState(repo);
  await state.loadHistoricalSession(sessionId);
  return state;
}

/// The rows [effortId] holds of [metricId], read back from the store.
Future<List<EffortObservation>> storedRows(
  WorkoutRepository repo,
  String effortId,
  String metricId,
) async => (await repo.getEffortObservations(
  effortId,
)).where((row) => row.metricId == metricId).toList();

/// Every id the store holds for [effortId].
Future<Set<String>> storedRowIds(
  WorkoutRepository repo,
  String effortId,
) async => {
  for (final row in await repo.getEffortObservations(effortId)) row.id,
};
