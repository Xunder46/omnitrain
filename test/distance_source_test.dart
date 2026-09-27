// Stats PR 3a, Phase 1 — the stored distance source and the pairing contract.
//
// Every distance records where it came from, and a distance row is tied to the
// entry it belongs to by relative order rather than by the order a store
// happens to return rows in. Both rules sit behind `WorkoutRepository`, so
// `HiveWorkoutRepository` and `MockWorkoutRepository` must agree value for
// value, and a Hive restart must not change what a source or a pairing reads.
//
// Scenarios: S-801, S-802, S-803 (the model half), S-804–S-808 of
// `.github/agents/plans/2026-09-26-03a-stats-pr3a-phone-distance-plan.md`.
// The SQL half of S-803 lives in `db_seed_test.dart`.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/utils/distance_source.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ─── Harness (the pattern of `watch_capture_repository_parity_test.dart`) ─────

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test`.
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

/// Opens one repository implementation, and reopens it over the same storage
/// as an app restart would.
abstract class _Harness {
  String get name;
  Future<WorkoutRepository> open();

  /// A repository over the same storage, as after an app restart.
  Future<WorkoutRepository> restart();
  Future<void> close();
}

class _MockHarness implements _Harness {
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

class _HiveHarness implements _Harness {
  Directory? _dir;

  @override
  String get name => 'Hive';

  @override
  Future<WorkoutRepository> open() async {
    final dir = await Directory.systemTemp.createTemp('distance_source_');
    _dir = dir;
    _PathProviderChannel.install(dir);
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

// ─── Fixtures ───────────────────────────────────────────────────────────────

int get _start => DateTime.now().millisecondsSinceEpoch - 86400000;
int get _rowAt => _start + 60000;

/// A distance row as the phone and the watch import write one.
EffortObservation _distanceRow(
  String effortId,
  int entryIndex,
  double metres, {
  String? source,
  String? id,
}) => EffortObservation(
  id: id ?? 'obs-$effortId-$entryIndex-distance',
  effortId: effortId,
  metricId: MetricIds.distance,
  unitId: MetricIds.unitMeters,
  valueReal: metres,
  valueSource: source,
  createdAtMs: _rowAt,
  updatedAtMs: _rowAt,
);

/// A distance row as this app stored one before the source existed: a raw map
/// with no `value_source` key at all (S-801).
EffortObservation _legacyDistanceRow(
  String effortId,
  int entryIndex,
  double metres,
) => EffortObservation.fromMap({
  'id': 'obs-$effortId-$entryIndex-distance',
  'effort_id': effortId,
  'metric_id': MetricIds.distance,
  'unit_id': MetricIds.unitMeters,
  'value_real': metres,
  'created_at_ms': _rowAt,
  'updated_at_ms': _rowAt,
});

TimedInstance _timedInstance(
  String effortId,
  int entryIndex, {
  int actualDurationSecs = 600,
}) => TimedInstance(
  id: 'ti-$effortId-$entryIndex',
  effortId: effortId,
  entryIndex: entryIndex,
  targetDurationSecs: actualDurationSecs,
  actualDurationSecs: actualDurationSecs,
  startedAtMs: _start,
  finishedAtMs: _start + actualDurationSecs * 1000,
  state: TimedState.finished,
  createdAtMs: _start,
  updatedAtMs: _start,
);

/// A completed, ended session holding one segment, for a fixture to add its
/// efforts and rows to.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String sessionId,
  String? modality,
  bool isRolling = false,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: _start,
      endedAtMs: isRolling ? null : _start + 3600000,
      modality: modality,
      isRolling: isRolling,
      createdAtMs: _start,
      updatedAtMs: _start,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$sessionId',
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'workout',
      createdAtMs: _start,
      updatedAtMs: _start,
    ),
  );
}

/// One timed effort on [segmentId], its instances, and its stored rows.
Future<void> _seedTimedEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  int orderIndex = 0,
  int entryCount = 1,
  int entryDurationSecs = 600,
  List<EffortObservation> rows = const [],
  String? blockId,
  String? exerciseId,
}) async {
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: orderIndex,
      effortKind: 'timed',
      exerciseId: exerciseId,
      blockId: blockId,
      createdAtMs: _start,
      updatedAtMs: _start,
    ),
  );
  for (var i = 0; i < entryCount; i++) {
    await repo.createTimedInstance(
      _timedInstance(effortId, i, actualDurationSecs: entryDurationSecs),
    );
  }
  for (final row in rows) {
    await repo.createObservation(row);
  }
}

/// FX-CARDIO, the plan's shared fixture: two timed efforts, one estimate, one
/// row with no source, one empty entry.
Future<void> _seedCardioSession(WorkoutRepository repo) async {
  await _seedSession(repo, sessionId: 's-cardio', modality: 'cardio_endurance');
  await _seedTimedEffort(
    repo,
    segmentId: 'seg-s-cardio',
    effortId: 'e-tread',
    entryCount: 2,
    exerciseId: 'ex-treadmill',
    rows: [
      _distanceRow(
        'e-tread',
        0,
        4873.6,
        source: EffortObservation.sourceEstimated,
      ),
      _legacyDistanceRow('e-tread', 1, 0.0),
    ],
  );
  await _seedTimedEffort(
    repo,
    segmentId: 'seg-s-cardio',
    effortId: 'e-easy',
    orderIndex: 1,
    entryDurationSecs: 1800,
    exerciseId: 'ex-easy-run',
    rows: [_legacyDistanceRow('e-easy', 0, 5000.0)],
  );
}

Future<WorkoutState> _loadState(
  WorkoutRepository repo,
  String sessionId,
) async {
  final state = WorkoutState(repo);
  await state.loadHistoricalSession(sessionId);
  return state;
}

List<EffortObservation> _distanceRows(WorkoutState state, String effortId) =>
    state
        .getObservationsForEffort(effortId)
        .where((row) => row.metricId == MetricIds.distance)
        .toList();

EffortObservation _rowWithId(List<EffortObservation> rows, String id) =>
    rows.firstWhere((row) => row.id == id);

// ─── The guard's scanner (S-804 (c)) ────────────────────────────────────────

/// The text of every `marker` call's argument list in [source].
Iterable<String> _argumentLists(String source, String marker) sync* {
  var index = source.indexOf(marker);
  while (index >= 0) {
    final open = index + marker.length - 1;
    var depth = 0;
    var quote = '';
    for (var i = open; i < source.length; i++) {
      final char = source[i];
      if (quote.isNotEmpty) {
        if (char == quote) quote = '';
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
        continue;
      }
      if (char == '(') depth++;
      if (char != ')') continue;
      depth--;
      if (depth == 0) {
        yield source.substring(open, i + 1);
        break;
      }
    }
    index = source.indexOf(marker, index + marker.length);
  }
}

int _lineOf(String source, int index) =>
    '\n'.allMatches(source.substring(0, index)).length + 1;

// ─── The bodies, run once per repository ────────────────────────────────────

void _phaseOneTests(String name, _Harness Function() makeHarness) {
  late _Harness harness;
  late WorkoutRepository repo;

  setUp(() async {
    harness = makeHarness();
    repo = await harness.open();
  });

  tearDown(() async {
    await harness.close();
  });

  /// The repository name, in every test's title.
  String titled(String base) => '$base ($name)';

  test(titled('S-801 a legacy distance reads as entered'), () async {
    await _seedSession(repo, sessionId: 's-legacy');
    await _seedTimedEffort(
      repo,
      segmentId: 'seg-s-legacy',
      effortId: 'e-legacy',
      rows: [_legacyDistanceRow('e-legacy', 0, 5000.0)],
    );

    final rows = await repo.getEffortObservations('e-legacy');
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.valueSource, isNull);
    expect(
      DistanceSource.resolve(row.valueSource),
      EffortObservation.sourceEntered,
    );
    expect(DistanceSource.isEstimated(row.valueSource), isFalse);
    expect(row.toMap()['value_source'], isNull);
  });

  test(titled('S-802 each source round-trips a restart'), () async {
    await _seedSession(repo, sessionId: 's-sources');
    await _seedTimedEffort(
      repo,
      segmentId: 'seg-s-sources',
      effortId: 'e-1',
      entryCount: 3,
      rows: [
        _distanceRow('e-1', 0, 1000.0, source: EffortObservation.sourceGps),
        _distanceRow('e-1', 1, 2000.0, source: EffortObservation.sourceEntered),
        _distanceRow(
          'e-1',
          2,
          3000.0,
          source: EffortObservation.sourceEstimated,
        ),
        EffortObservation(
          id: 'obs-e-1-0-reps',
          effortId: 'e-1',
          metricId: MetricIds.reps,
          valueInt: 8,
          createdAtMs: _rowAt,
          updatedAtMs: _rowAt,
        ),
      ],
    );

    repo = await harness.restart();

    final rows = await repo.getEffortObservations('e-1');
    final sources = {for (final row in rows) row.id: row.valueSource};
    expect(sources['obs-e-1-0-distance'], EffortObservation.sourceGps);
    expect(sources['obs-e-1-1-distance'], EffortObservation.sourceEntered);
    expect(sources['obs-e-1-2-distance'], EffortObservation.sourceEstimated);
    expect(sources['obs-e-1-0-reps'], isNull);
  });

  test(titled('S-804 copies keep the source'), () async {
    await _seedSession(repo, sessionId: 's-rolling', isRolling: true);
    await repo.createSessionBlock(
      SessionBlock(
        id: 'blk-1',
        sessionId: 's-rolling',
        name: 'Block',
        orderIndex: 0,
        createdAtMs: _start,
        updatedAtMs: _start,
      ),
    );
    await _seedTimedEffort(
      repo,
      segmentId: 'seg-s-rolling',
      effortId: 'e-blk',
      blockId: 'blk-1',
      rows: [
        _distanceRow(
          'e-blk',
          0,
          4873.6,
          source: EffortObservation.sourceEstimated,
        ),
      ],
    );

    // (a) updateEntryValue keeps the source of the row it replaces.
    final state = await _loadState(repo, 's-rolling');
    final before = _distanceRows(state, 'e-blk').single;
    await state.updateEntryValue('e-blk', 0, 'distance', 4873.6);
    final after = _distanceRows(state, 'e-blk').single;
    expect(after.valueReal, 4873.6);
    expect(after.valueSource, EffortObservation.sourceEstimated);
    expect(after.id, before.id);

    // (b) a block clone carries the source to the new row.
    final cloneBlockId = await repo.cloneSessionBlock('blk-1');
    expect(cloneBlockId, isNotEmpty);
    final cloneEfforts = (await repo.getSegmentEfforts(
      'seg-s-rolling',
    )).where((effort) => effort.blockId == cloneBlockId).toList();
    expect(cloneEfforts, hasLength(1));
    final cloned = await repo.getEffortObservations(cloneEfforts.single.id);
    expect(cloned, hasLength(1));
    expect(cloned.single.valueReal, 4873.6);
    expect(cloned.single.valueSource, EffortObservation.sourceEstimated);
  });

  test(titled('S-805 setting a distance'), () async {
    await _seedCardioSession(repo);
    final state = await _loadState(repo, 's-cardio');

    var notifications = 0;
    state.addListener(() => notifications++);

    final rowsBefore = _distanceRows(state, 'e-tread');
    final emptyRow = _rowWithId(rowsBefore, 'obs-e-tread-1-distance');
    final filledRow = _rowWithId(
      _distanceRows(state, 'e-easy'),
      'obs-e-easy-0-distance',
    );

    await state.setEntryDistance('e-tread', 1, 1500.0);
    await state.setEntryDistance('e-easy', 0, 0.0);

    final treadRow = _rowWithId(_distanceRows(state, 'e-tread'), emptyRow.id);
    expect(treadRow.valueReal, 1500.0);
    expect(treadRow.valueSource, EffortObservation.sourceEntered);
    expect(treadRow.createdAtMs, emptyRow.createdAtMs);
    expect(treadRow.updatedAtMs, greaterThan(emptyRow.updatedAtMs));

    final easyRow = _rowWithId(_distanceRows(state, 'e-easy'), filledRow.id);
    expect(easyRow.valueReal, 0.0);
    expect(easyRow.valueSource, isNull);
    expect(easyRow.createdAtMs, filledRow.createdAtMs);
    expect(easyRow.updatedAtMs, greaterThan(filledRow.updatedAtMs));

    expect(notifications, greaterThanOrEqualTo(2));

    // The same values come back from storage, restart or not.
    repo = await harness.restart();
    final reloaded = await _loadState(repo, 's-cardio');
    final reloadedTread = _rowWithId(
      _distanceRows(reloaded, 'e-tread'),
      emptyRow.id,
    );
    expect(reloadedTread.valueReal, 1500.0);
    expect(reloadedTread.valueSource, EffortObservation.sourceEntered);
    final reloadedEasy = _rowWithId(
      _distanceRows(reloaded, 'e-easy'),
      filledRow.id,
    );
    expect(reloadedEasy.valueReal, 0.0);
    expect(reloadedEasy.valueSource, isNull);
  });

  test(titled('S-806 confirming keeps the number'), () async {
    await _seedCardioSession(repo);
    final state = await _loadState(repo, 's-cardio');

    await state.confirmEntryDistance('e-tread', 0);
    await state.confirmEntryDistance('e-tread', 1);

    final rows = _distanceRows(state, 'e-tread');
    final first = _rowWithId(rows, 'obs-e-tread-0-distance');
    expect(first.valueReal, 4873.6);
    expect(first.valueSource, EffortObservation.sourceEntered);

    final second = _rowWithId(rows, 'obs-e-tread-1-distance');
    expect(second.valueReal, 0.0);
    expect(second.valueSource, isNull);
  });

  test(titled('S-807 missing rows are filled in position'), () async {
    await _seedSession(repo, sessionId: 's-gap');
    await _seedTimedEffort(
      repo,
      segmentId: 'seg-s-gap',
      effortId: 'e-gap',
      entryCount: 3,
      rows: [_distanceRow('e-gap', 0, 0.0)],
    );
    final state = await _loadState(repo, 's-gap');

    await state.setEntryDistance('e-gap', 2, 1500.0);

    final paired = DistancePairing.forEntries(
      distanceRows: _distanceRows(state, 'e-gap'),
      entryCount: 3,
    );
    expect(paired.map((row) => row?.valueReal).toList(), [0.0, 0.0, 1500.0]);
    expect(paired[1]!.valueSource, isNull);
    expect(paired[2]!.valueSource, EffortObservation.sourceEntered);
    expect(paired[1]!.id, 'obs-e-gap-1-distance');
    expect(paired[2]!.id, 'obs-e-gap-2-distance');
  });

  test(titled('S-808 pairing survives store order'), () async {
    await _seedSession(repo, sessionId: 's-12');
    await _seedTimedEffort(
      repo,
      segmentId: 'seg-s-12',
      effortId: 'e-12',
      entryCount: 12,
      rows: [
        for (var i = 0; i < 12; i++) _distanceRow('e-12', i, (i + 1) * 100.0),
      ],
    );

    repo = await harness.restart();

    final rows = await repo.getEffortObservations('e-12');
    final paired = DistancePairing.forEntries(
      distanceRows: rows,
      entryCount: 12,
    );
    for (var k = 0; k < 12; k++) {
      expect(
        paired[k]?.valueReal,
        (k + 1) * 100.0,
        reason: 'entry $k pairs with its own row',
      );
    }

    // The pairing is order-independent: the same rows in reverse still pair
    // the same way.
    final shuffled = DistancePairing.forEntries(
      distanceRows: rows.reversed.toList(),
      entryCount: 12,
    );
    expect(
      shuffled.map((row) => row?.valueReal).toList(),
      paired.map((row) => row?.valueReal).toList(),
    );
  });
}

void main() {
  group('Mock', () => _phaseOneTests('Mock', _MockHarness.new));
  group('Hive', () => _phaseOneTests('Hive', _HiveHarness.new));

  group('S-803 writer defects are refused', () {
    test('a source on a metric that cannot carry one throws', () {
      expect(
        () => EffortObservation(
          id: 'obs-e-1-0-reps',
          effortId: 'e-1',
          metricId: MetricIds.reps,
          valueInt: 8,
          valueSource: EffortObservation.sourceEntered,
          createdAtMs: _rowAt,
          updatedAtMs: _rowAt,
        ),
        throwsArgumentError,
      );
    });

    test('a source outside the vocabulary throws', () {
      expect(
        () => EffortObservation(
          id: 'obs-e-1-0-distance',
          effortId: 'e-1',
          metricId: MetricIds.distance,
          valueReal: 1000.0,
          valueSource: 'manual',
          createdAtMs: _rowAt,
          updatedAtMs: _rowAt,
        ),
        throwsArgumentError,
      );
    });

    test('an estimated distance constructs', () {
      final row = _distanceRow(
        'e-1',
        0,
        3000.0,
        source: EffortObservation.sourceEstimated,
      );
      expect(row.valueSource, EffortObservation.sourceEstimated);
      expect(DistanceSource.isEstimated(row.valueSource), isTrue);
    });
  });

  group('S-804 (c) source guard', () {
    test('every observation copy forwards valueSource', () {
      final offenders = <String>[];
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        for (final arguments in _argumentLists(source, 'EffortObservation(')) {
          if (!arguments.contains('rpeRating:')) continue;
          if (arguments.contains('valueSource:')) continue;
          final line = _lineOf(source, source.indexOf(arguments));
          offenders.add('${file.path}:$line');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'D-311: these EffortObservation copies drop valueSource, so a '
            'distance loses its source whenever the row is copied:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
