// Stats PR 2, Phase 2 — the phone's watch-capture storage (D-131, D-132).
//
// The phone stages everything it learns about a wrist session in the watch
// session inbox, and stores the heart-rate and step summaries the wrist
// measured. Both sit behind `WorkoutRepository`, so `HiveWorkoutRepository`
// and `MockWorkoutRepository` must agree value for value.
//
// Every test in `_parityTests` runs once per repository through a
// [_Harness]; no expected value depends on which repository runs it. The
// "Hive and Mock store the same rows" group runs one scripted sequence on
// both and compares what each stored, row by row, by `toMap`. The last group
// covers the model rules that hold before anything reaches a repository.
//
// Plan: docs/plans/2026-09-25-02-stats-pr2-watch-capture-plan.md

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

/// Stand-in for the path_provider platform channel, which has no
/// implementation under `flutter_test`. `HiveWorkoutRepository.initialize()`
/// calls `Hive.initFlutter()`, which asks it for the documents directory.
/// Same pattern as `test/food_library_persistence_test.dart`.
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

/// Opens one repository implementation, and reopens it over the same
/// storage as an app restart would.
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
    final dir = await Directory.systemTemp.createTemp('watch_capture_parity_');
    _dir = dir;
    _PathProviderChannel.install(dir);
    Hive.init(dir.path);
    final repo = HiveWorkoutRepository();
    await repo.initialize();
    return repo;
  }

  /// Closes every box, then opens a new repository over the same files.
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

// ─── Fixture ────────────────────────────────────────────────────────────────

/// 2026-09-25 [hour]:[minute]:[second] UTC, the day of the F-CAP contract.
int _at(int hour, int minute, [int second = 0]) =>
    DateTime.utc(2026, 9, 25, hour, minute, second).millisecondsSinceEpoch;

const _session = 's-cap-1';
const _otherSession = 's-other';

/// The wrist's timed event for the run, as F-CAP sends it.
Map<String, dynamic> _runEvent({num avgHeartRateBpm = 140}) => {
  'eventId': 'e-run',
  'entryId': 'e-run',
  'kind': 'timed',
  'sessionExerciseId': 'sx-run',
  'exerciseId': 'ex-run',
  'loggedAt': '2026-09-25T10:20:00.000Z',
  'startedAt': '2026-09-25T10:00:00.000Z',
  'endedAt': '2026-09-25T10:20:00.000Z',
  'avgHeartRateBpm': avgHeartRateBpm,
  'maxHeartRateBpm': 160,
  'steps': 3200,
};

WatchInboxEntry _wristRow(
  String entryId,
  String kind, {
  String session = _session,
  int receivedAtMs = 1000,
  Map<String, dynamic>? payload,
}) => WatchInboxEntry(
  entryId: entryId,
  watchSessionId: session,
  kind: kind,
  origin: WatchInboxEntry.originWatch,
  payload: payload ?? {'eventId': entryId, 'entryId': entryId, 'kind': kind},
  receivedAtMs: receivedAtMs,
);

SensorSummary _summary(
  String scope,
  String targetId, {
  String session = _session,
  required int fromMs,
  required int toMs,
  double? avg,
  double? max,
  int? steps,
}) => SensorSummary(
  sessionId: session,
  scope: scope,
  targetId: targetId,
  windowStartMs: fromMs,
  windowEndMs: toMs,
  avgHeartRateBpm: avg,
  maxHeartRateBpm: max,
  steps: steps,
  createdAtMs: _at(11, 0),
);

/// The summaries of [_session], in the order the repository must list them:
/// scope, then window start, then target id. Created shuffled by
/// [_seedHistory] so the order cannot come from insertion.
///
/// `eff-bench` and `eff-curl` are an interleaved superset, so their set-block
/// windows start together (D-123) and the tie falls to the target id.
/// `ti-run-b` precedes `ti-run-a` in time, so window order and id order
/// disagree.
final List<SensorSummary> _sessionSummaries = [
  _summary(
    SensorSummary.scopeSession,
    _session,
    fromMs: _at(10, 0),
    toMs: _at(10, 55),
    avg: 143,
    max: 180,
  ),
  _summary(
    SensorSummary.scopeEffort,
    'eff-bench',
    fromMs: _at(10, 42, 10),
    toMs: _at(10, 51),
    avg: 130,
    max: 150,
  ),
  _summary(
    SensorSummary.scopeEffort,
    'eff-curl',
    fromMs: _at(10, 42, 10),
    toMs: _at(10, 52),
    avg: 120,
    max: 125,
  ),
  _summary(
    SensorSummary.scopeTimedInstance,
    'ti-run-b',
    fromMs: _at(10, 0),
    toMs: _at(10, 20),
    avg: 140,
    max: 160,
    steps: 3200,
  ),
  // A measured zero is a value (D-125): steps only, no heart rate.
  _summary(
    SensorSummary.scopeTimedInstance,
    'ti-run-a',
    fromMs: _at(10, 20),
    toMs: _at(10, 22),
    steps: 0,
  ),
  _summary(
    SensorSummary.scopeRoundInstance,
    'ri-1',
    fromMs: _at(10, 25),
    toMs: _at(10, 30),
    avg: 160,
    max: 170,
  ),
  _summary(
    SensorSummary.scopeRoundInstance,
    'ri-2',
    fromMs: _at(10, 30),
    toMs: _at(10, 37),
    avg: 165,
    max: 180,
  ),
  _summary(
    SensorSummary.scopeRoundInstance,
    'ri-3',
    fromMs: _at(10, 37, 5),
    toMs: _at(10, 42, 5),
    avg: 155,
    max: 165,
  ),
];

final List<SensorSummary> _otherSessionSummaries = [
  _summary(
    SensorSummary.scopeSession,
    _otherSession,
    session: _otherSession,
    fromMs: _at(8, 0),
    toMs: _at(8, 30),
    avg: 110,
    max: 120,
  ),
  _summary(
    SensorSummary.scopeTimedInstance,
    'ti-other',
    session: _otherSession,
    fromMs: _at(8, 0),
    toMs: _at(8, 20),
    avg: 100,
    max: 105,
    steps: 900,
  ),
];

/// Two imported sessions with every kind of summary target.
///
/// [_session]: block `blk-cap` holds `eff-run` (timed: `ti-run-b`,
/// `ti-run-a`), `eff-bjj` (round: `ri-1`–`ri-3`) and `eff-bench` (a set
/// block); `eff-curl` (a set block) stands outside the block.
/// [_otherSession]: `eff-other` (timed: `ti-other`). Each target carries a
/// summary.
Future<void> _seedHistory(WorkoutRepository repo) async {
  final created = _at(10, 0);
  for (final (id, start, end) in [
    (_session, _at(10, 0), _at(10, 55)),
    (_otherSession, _at(8, 0), _at(8, 30)),
  ]) {
    await repo.createSession(
      TrainingSession(
        id: id,
        ownerUserId: 'user-1',
        startedAtMs: start,
        endedAtMs: end,
        createdAtMs: start,
        updatedAtMs: end,
      ),
    );
    await repo.createSegment(
      SessionSegment(
        id: 'seg-$id',
        sessionId: id,
        orderIndex: 0,
        segmentType: 'main',
        createdAtMs: start,
        updatedAtMs: start,
      ),
    );
  }
  await repo.createSessionBlock(
    SessionBlock(
      id: 'blk-cap',
      sessionId: _session,
      name: 'Block',
      orderIndex: 0,
      createdAtMs: created,
      updatedAtMs: created,
    ),
  );
  for (final (id, kind, exerciseId, blockId, segmentId) in [
    ('eff-run', 'timed', 'ex-run', 'blk-cap', 'seg-$_session'),
    ('eff-bjj', 'round', 'ex-bjj', 'blk-cap', 'seg-$_session'),
    ('eff-bench', 'set', 'ex-bench', 'blk-cap', 'seg-$_session'),
    ('eff-curl', 'set', 'ex-curl', null, 'seg-$_session'),
    ('eff-other', 'timed', 'ex-run', null, 'seg-$_otherSession'),
  ]) {
    await repo.createEffort(
      SegmentEffort(
        id: id,
        segmentId: segmentId,
        orderIndex: 0,
        effortKind: kind,
        exerciseId: exerciseId,
        blockId: blockId,
        createdAtMs: created,
        updatedAtMs: created,
      ),
    );
  }
  for (final (id, effortId, index) in [
    ('ti-run-b', 'eff-run', 0),
    ('ti-run-a', 'eff-run', 1),
    ('ti-other', 'eff-other', 0),
  ]) {
    await repo.createTimedInstance(
      TimedInstance(
        id: id,
        effortId: effortId,
        entryIndex: index,
        createdAtMs: created,
        updatedAtMs: created,
      ),
    );
  }
  for (final (id, index) in [('ri-1', 0), ('ri-2', 1), ('ri-3', 2)]) {
    await repo.createRoundInstance(
      RoundInstance(
        id: id,
        effortId: 'eff-bjj',
        roundIndex: index,
        createdAtMs: created,
        updatedAtMs: created,
      ),
    );
  }
  final shuffled = [..._sessionSummaries.reversed, ..._otherSessionSummaries];
  for (final summary in shuffled) {
    expect(
      await repo.createSensorSummary(summary),
      isTrue,
      reason: 'D-131 fixture: ${summary.id} is new',
    );
  }
}

Future<List<String>> _summaryIds(
  WorkoutRepository repo,
  String sessionId,
) async => (await repo.getSensorSummariesForSession(
  sessionId,
)).map((s) => s.id).toList();

String _id(String scope, String targetId) =>
    SensorSummary.idFor(scope, targetId);

final List<String> _otherSessionIds = _otherSessionSummaries
    .map((s) => s.id)
    .toList();

// ─── Parity: one body per repository ────────────────────────────────────────

void _parityTests(_Harness Function() makeHarness) {
  late _Harness harness;
  late WorkoutRepository repo;

  setUp(() async {
    harness = makeHarness();
    repo = await harness.open();
  });

  tearDown(() async {
    await harness.close();
  });

  group('D-132 watch session inbox', () {
    test('D-132 stages put-if-absent: an altered redelivery is refused, and '
        'the staged row survives a restart unchanged', () async {
      final original = _wristRow(
        'e-run',
        WatchInboxEntry.kindTimed,
        receivedAtMs: 1000,
        payload: _runEvent(),
      );
      final altered = _wristRow(
        'e-run',
        WatchInboxEntry.kindTimed,
        receivedAtMs: 2000,
        payload: _runEvent(avgHeartRateBpm: 999),
      );

      expect(await repo.stageWatchInboxEntry(original), isTrue);
      expect(
        await repo.stageWatchInboxEntry(altered),
        isFalse,
        reason: 'D-132: a redelivered or altered copy is refused',
      );
      expect(
        (await repo.getWatchInboxEntry('e-run'))!.toMap(),
        original.toMap(),
        reason: 'D-132: the first copy is the record',
      );

      repo = await harness.restart();
      expect(
        (await repo.getWatchInboxEntry('e-run'))!.toMap(),
        original.toMap(),
        reason: 'D-132: staged durably',
      );
      expect(await repo.stageWatchInboxEntry(altered), isFalse);
      final staged = (await repo.getWatchInboxEntry('e-run'))!;
      expect(staged.payload['avgHeartRateBpm'], 140);
      expect(staged.appliedAtMs, isNull);
      expect(await repo.getWatchInboxEntry('e-never-staged'), isNull);
    });

    test('D-132 lists a session\'s rows by receivedAtMs, then entryId, and '
        'only that session\'s rows', () async {
      // Staged out of order; the ties at 100 and 200 fall to the entry id.
      for (final row in [
        _wristRow('e-set1', WatchInboxEntry.kindSet, receivedAtMs: 300),
        _wristRow(
          'rating-s-cap-1',
          WatchInboxEntry.kindEffortRating,
          receivedAtMs: 100,
        ),
        _wristRow('e-r2', WatchInboxEntry.kindRound, receivedAtMs: 200),
        _wristRow(
          'end-s-cap-1',
          WatchInboxEntry.kindSessionEnd,
          receivedAtMs: 100,
        ),
        _wristRow(
          'e-o1',
          WatchInboxEntry.kindSet,
          session: _otherSession,
          receivedAtMs: 50,
        ),
        _wristRow('e-r1', WatchInboxEntry.kindRound, receivedAtMs: 200),
      ]) {
        expect(await repo.stageWatchInboxEntry(row), isTrue);
      }

      expect(
        (await repo.getWatchInboxEntriesForSession(
          _session,
        )).map((e) => e.entryId).toList(),
        ['end-s-cap-1', 'rating-s-cap-1', 'e-r1', 'e-r2', 'e-set1'],
        reason: 'D-132: ordered by receivedAtMs, then entryId',
      );
      expect(
        (await repo.getWatchInboxEntriesForSession(
          _otherSession,
        )).map((e) => e.entryId).toList(),
        ['e-o1'],
      );
      expect(await repo.getWatchInboxEntriesForSession('s-none'), isEmpty);
    });

    test('D-132 marks rows applied in one batch; a row keeps its first stamp '
        'and unknown ids are skipped', () async {
      for (final id in ['e-a', 'e-b', 'e-c']) {
        await repo.stageWatchInboxEntry(_wristRow(id, WatchInboxEntry.kindSet));
      }

      await repo.markWatchInboxEntriesApplied([
        'e-a',
        'e-b',
        'e-unknown',
      ], 5000);
      await repo.markWatchInboxEntriesApplied(['e-a', 'e-c'], 6000);

      repo = await harness.restart();
      final applied = {
        for (final e in await repo.getWatchInboxEntriesForSession(_session))
          e.entryId: e.appliedAtMs,
      };
      expect(applied, {
        'e-a': 5000,
        'e-b': 5000,
        'e-c': 6000,
      }, reason: 'D-132: a tombstone keeps its first stamp');
      expect(
        await repo.getWatchInboxEntry('e-unknown'),
        isNull,
        reason: 'D-132: marking never creates a row',
      );
    });

    test('S-1412 D-132 unsets the applied stamp on the named rows only: an '
        'unapplied row and an unknown id are skipped, and nothing is created '
        'or deleted', () async {
      final appliedA = _wristRow(
        'e-a',
        WatchInboxEntry.kindSet,
        receivedAtMs: 100,
      );
      final appliedB = _wristRow(
        'e-b',
        WatchInboxEntry.kindSet,
        receivedAtMs: 200,
      );
      final unappliedC = _wristRow(
        'e-c',
        WatchInboxEntry.kindSet,
        receivedAtMs: 300,
      );
      for (final row in [
        appliedA,
        appliedB,
        unappliedC,
        _wristRow(
          'end-s-cap-1',
          WatchInboxEntry.kindSessionEnd,
          receivedAtMs: 400,
        ),
      ]) {
        expect(await repo.stageWatchInboxEntry(row), isTrue);
      }
      await repo.markWatchInboxEntriesApplied(['e-a', 'e-b'], 5000);

      final unappliedBefore = (await repo.getWatchInboxEntry('e-c'))!.toMap();
      final endsBefore = await repo.getWatchSessionIdsWithUnappliedEnd();

      await repo.clearWatchInboxApplied(['e-a', 'e-b', 'e-never-staged']);

      repo = await harness.restart();
      expect(
        (await repo.getWatchInboxEntry('e-a'))!.toMap(),
        {...appliedA.toMap(), 'applied_at_ms': null},
        reason: 'D-132: a named applied row is un-stamped, its payload intact',
      );
      expect(
        (await repo.getWatchInboxEntry('e-b'))!.appliedAtMs,
        isNull,
        reason: 'D-132: every named applied row is un-stamped',
      );
      expect(
        (await repo.getWatchInboxEntry('e-c'))!.toMap(),
        unappliedBefore,
        reason: 'D-132: an unapplied row is skipped, not rewritten',
      );
      expect(
        await repo.getWatchInboxEntry('e-never-staged'),
        isNull,
        reason: 'D-132: unsetting a stamp never creates a row',
      );
      expect(
        await repo.getWatchSessionIdsWithUnappliedEnd(),
        endsBefore,
        reason: 'D-132: the unapplied-end list is unchanged',
      );
      expect(
        (await repo.getWatchInboxEntriesForSession(_session)),
        hasLength(4),
        reason: 'D-132: no row is deleted',
      );
    });

    test('D-132 lists the sessions whose session_end is staged but not '
        'applied, oldest first, without repeats', () async {
      for (final row in [
        _wristRow(
          'end-s-b',
          WatchInboxEntry.kindSessionEnd,
          session: 's-b',
          receivedAtMs: 200,
        ),
        _wristRow(
          'end-s-a',
          WatchInboxEntry.kindSessionEnd,
          session: 's-a',
          receivedAtMs: 300,
        ),
        _wristRow(
          'rating-s-a',
          WatchInboxEntry.kindEffortRating,
          session: 's-a',
          receivedAtMs: 310,
        ),
        _wristRow(
          'end-s-f',
          WatchInboxEntry.kindSessionEnd,
          session: 's-f',
          receivedAtMs: 200,
        ),
        _wristRow(
          'end-s-c',
          WatchInboxEntry.kindSessionEnd,
          session: 's-c',
          receivedAtMs: 100,
        ),
        // A second session_end for s-c under another id: listed once.
        _wristRow(
          'end-s-c-again',
          WatchInboxEntry.kindSessionEnd,
          session: 's-c',
          receivedAtMs: 400,
        ),
        _wristRow(
          'e-d1',
          WatchInboxEntry.kindSet,
          session: 's-d',
          receivedAtMs: 50,
        ),
        _wristRow(
          'end-s-e',
          WatchInboxEntry.kindSessionEnd,
          session: 's-e',
          receivedAtMs: 150,
        ),
      ]) {
        await repo.stageWatchInboxEntry(row);
      }
      await repo.markWatchInboxEntriesApplied(['end-s-e'], 900);

      expect(
        await repo.getWatchSessionIdsWithUnappliedEnd(),
        ['s-c', 's-b', 's-f', 's-a'],
        reason:
            'D-132: import resumes for every staged, unapplied session_end; '
            'no end (s-d) or an applied end (s-e) is not listed',
      );

      await repo.markWatchInboxEntriesApplied(['end-s-b'], 901);
      expect(await repo.getWatchSessionIdsWithUnappliedEnd(), [
        's-c',
        's-f',
        's-a',
      ]);
    });
  });

  group('D-131 sensor summaries', () {
    test('D-131 stores put-if-absent by scope and target: a second copy '
        'never replaces the first', () async {
      final first = _summary(
        SensorSummary.scopeTimedInstance,
        'ti-run-b',
        fromMs: _at(10, 0),
        toMs: _at(10, 20),
        avg: 140,
        max: 160,
        steps: 3200,
      );
      final second = _summary(
        SensorSummary.scopeTimedInstance,
        'ti-run-b',
        fromMs: _at(10, 1),
        toMs: _at(10, 19),
        avg: 999,
        max: 999,
        steps: 1,
      );

      expect(await repo.createSensorSummary(first), isTrue);
      expect(
        await repo.createSensorSummary(second),
        isFalse,
        reason: 'D-131: one row per (scope, target), never rewritten',
      );

      repo = await harness.restart();
      final stored = await repo.getSensorSummariesForSession(_session);
      expect(
        stored.map((s) => s.toMap()).toList(),
        [first.toMap()],
        reason: 'D-131: the first copy stays',
      );
    });

    test('D-131 lists a session\'s summaries by scope, then window start, '
        'then target, and only that session\'s', () async {
      await _seedHistory(repo);

      expect(
        (await repo.getSensorSummariesForSession(
          _session,
        )).map((s) => s.toMap()).toList(),
        _sessionSummaries.map((s) => s.toMap()).toList(),
        reason: 'D-131: scope order, then windowStartMs, then targetId',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
      expect(await repo.getSensorSummariesForSession('s-none'), isEmpty);
    });

    test('D-131 refuses a zero heart rate, an average above the maximum, '
        'steps outside a timed entry and an empty summary, and stores '
        'nothing', () async {
      Future<void> refuses(SensorSummary Function() build, String rule) async {
        expect(build, throwsArgumentError, reason: 'D-131 refuses $rule');
      }

      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
          avg: 0,
          max: 0,
        ),
        'a zero heart rate',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
          avg: 171,
          max: 170,
        ),
        'an average above the maximum',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
          avg: 160,
          max: 170,
          steps: 40,
        ),
        'steps on a round',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
        ),
        'an empty summary',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
          avg: 160,
        ),
        'an average without a maximum',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeTimedInstance,
          'ti-run-b',
          fromMs: _at(10, 0),
          toMs: _at(10, 20),
          steps: -1,
        ),
        'negative steps',
      );
      await refuses(
        () => _summary(
          'set_block',
          'eff-bench',
          fromMs: _at(10, 42),
          toMs: _at(10, 51),
          avg: 130,
          max: 150,
        ),
        'an unknown scope',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeSession,
          _otherSession,
          fromMs: _at(10, 0),
          toMs: _at(10, 55),
          avg: 143,
          max: 180,
        ),
        'a session summary that targets another session',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 30),
          toMs: _at(10, 25),
          avg: 160,
          max: 170,
        ),
        'a window that ends before it starts',
      );
      await refuses(
        () => SensorSummary(
          sessionId: _session,
          scope: SensorSummary.scopeRoundInstance,
          targetId: 'ri-1',
          windowStartMs: _at(10, 25),
          windowEndMs: _at(10, 30),
          avgHeartRateBpm: 160,
          maxHeartRateBpm: 170,
          source: 'phone',
          createdAtMs: _at(11, 0),
        ),
        'a source other than the watch',
      );

      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
          avg: double.nan,
          max: double.nan,
        ),
        'a heart rate that is not a number',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          'ri-1',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
          avg: 160,
          max: double.infinity,
        ),
        'an infinite heart rate',
      );
      await refuses(
        () => _summary(
          SensorSummary.scopeRoundInstance,
          '',
          fromMs: _at(10, 25),
          toMs: _at(10, 30),
          avg: 160,
          max: 170,
        ),
        'a summary with no target',
      );

      expect(
        await repo.getSensorSummariesForSession(_session),
        isEmpty,
        reason: 'D-131: nothing refused reaches storage',
      );
    });
  });

  group('D-131 summaries go with their targets; D-132 the inbox stays', () {
    test('D-131 deleteSession removes every summary of the session and no '
        'other', () async {
      await _seedHistory(repo);

      await repo.deleteSession(_session);

      expect(
        await repo.getSensorSummariesForSession(_session),
        isEmpty,
        reason: 'D-131: no summary outlives its session',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
    });

    test('D-131 deleteEffort removes the effort\'s summary and its '
        'instances\' summaries', () async {
      await _seedHistory(repo);

      await repo.deleteEffort('eff-bench');
      await repo.deleteEffort('eff-bjj');

      expect(
        await _summaryIds(repo, _session),
        [
          _id(SensorSummary.scopeSession, _session),
          _id(SensorSummary.scopeEffort, 'eff-curl'),
          _id(SensorSummary.scopeTimedInstance, 'ti-run-b'),
          _id(SensorSummary.scopeTimedInstance, 'ti-run-a'),
        ],
        reason: 'D-131: a summary is deleted together with its target',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
    });

    test('D-131 deleteTimedInstance removes that instance\'s summary '
        'only', () async {
      await _seedHistory(repo);

      await repo.deleteTimedInstance('ti-run-b');

      expect(
        await _summaryIds(repo, _session),
        [
          _id(SensorSummary.scopeSession, _session),
          _id(SensorSummary.scopeEffort, 'eff-bench'),
          _id(SensorSummary.scopeEffort, 'eff-curl'),
          _id(SensorSummary.scopeTimedInstance, 'ti-run-a'),
          _id(SensorSummary.scopeRoundInstance, 'ri-1'),
          _id(SensorSummary.scopeRoundInstance, 'ri-2'),
          _id(SensorSummary.scopeRoundInstance, 'ri-3'),
        ],
        reason: 'D-131: a summary is deleted together with its target',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
    });

    test('D-131 deleteTimedInstancesForEffort removes the summaries of that '
        'effort\'s timed instances', () async {
      await _seedHistory(repo);

      await repo.deleteTimedInstancesForEffort('eff-run');

      expect(
        await _summaryIds(repo, _session),
        [
          _id(SensorSummary.scopeSession, _session),
          _id(SensorSummary.scopeEffort, 'eff-bench'),
          _id(SensorSummary.scopeEffort, 'eff-curl'),
          _id(SensorSummary.scopeRoundInstance, 'ri-1'),
          _id(SensorSummary.scopeRoundInstance, 'ri-2'),
          _id(SensorSummary.scopeRoundInstance, 'ri-3'),
        ],
        reason: 'D-131: a summary is deleted together with its target',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
    });

    test('D-131 deleteRoundInstance removes that round\'s summary '
        'only', () async {
      await _seedHistory(repo);

      await repo.deleteRoundInstance('ri-2');

      expect(
        await _summaryIds(repo, _session),
        [
          _id(SensorSummary.scopeSession, _session),
          _id(SensorSummary.scopeEffort, 'eff-bench'),
          _id(SensorSummary.scopeEffort, 'eff-curl'),
          _id(SensorSummary.scopeTimedInstance, 'ti-run-b'),
          _id(SensorSummary.scopeTimedInstance, 'ti-run-a'),
          _id(SensorSummary.scopeRoundInstance, 'ri-1'),
          _id(SensorSummary.scopeRoundInstance, 'ri-3'),
        ],
        reason: 'D-131: a summary is deleted together with its target',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
    });

    test('D-131 deleteRoundInstancesForEffort removes the summaries of that '
        'effort\'s rounds', () async {
      await _seedHistory(repo);

      await repo.deleteRoundInstancesForEffort('eff-bjj');

      expect(
        await _summaryIds(repo, _session),
        [
          _id(SensorSummary.scopeSession, _session),
          _id(SensorSummary.scopeEffort, 'eff-bench'),
          _id(SensorSummary.scopeEffort, 'eff-curl'),
          _id(SensorSummary.scopeTimedInstance, 'ti-run-b'),
          _id(SensorSummary.scopeTimedInstance, 'ti-run-a'),
        ],
        reason: 'D-131: a summary is deleted together with its target',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
    });

    test('D-131 deleteSessionBlock removes the summaries of the block\'s '
        'efforts and their instances', () async {
      await _seedHistory(repo);

      await repo.deleteSessionBlock('blk-cap');

      expect(
        await _summaryIds(repo, _session),
        [
          _id(SensorSummary.scopeSession, _session),
          _id(SensorSummary.scopeEffort, 'eff-curl'),
        ],
        reason: 'D-131: a summary is deleted together with its target',
      );
      expect(await _summaryIds(repo, _otherSession), _otherSessionIds);
    });

    test('D-132 the inbox survives deleteSession: its rows, applied or not, '
        'stay as tombstones', () async {
      await _seedHistory(repo);
      for (final row in [
        _wristRow('e-run', WatchInboxEntry.kindTimed, payload: _runEvent()),
        _wristRow('end-s-cap-1', WatchInboxEntry.kindSessionEnd),
        WatchInboxEntry(
          entryId: WatchInboxEntry.phoneRatingId(_session),
          watchSessionId: _session,
          kind: WatchInboxEntry.kindPhoneRating,
          origin: WatchInboxEntry.originPhone,
          payload: {'rating': 2},
          receivedAtMs: 1100,
        ),
      ]) {
        await repo.stageWatchInboxEntry(row);
      }
      await repo.markWatchInboxEntriesApplied(['e-run', 'end-s-cap-1'], 5000);
      final before = [
        for (final e in await repo.getWatchInboxEntriesForSession(_session))
          e.toMap(),
      ];

      await repo.deleteSession(_session);

      expect(
        [
          for (final e in await repo.getWatchInboxEntriesForSession(_session))
            e.toMap(),
        ],
        before,
        reason: 'D-132: no history delete cascades into the inbox',
      );
      expect(before, hasLength(3));
      expect(await repo.getSensorSummariesForSession(_session), isEmpty);
    });
  });
}

// ─── Cross-repository comparison ────────────────────────────────────────────

/// One scripted sequence over every new repository path.
Future<void> _script(WorkoutRepository repo) async {
  await _seedHistory(repo);
  await repo.stageWatchInboxEntry(
    _wristRow('e-run', WatchInboxEntry.kindTimed, payload: _runEvent()),
  );
  await repo.stageWatchInboxEntry(
    _wristRow(
      'e-run',
      WatchInboxEntry.kindTimed,
      receivedAtMs: 1500,
      payload: _runEvent(avgHeartRateBpm: 999),
    ),
  );
  await repo.stageWatchInboxEntry(
    _wristRow('end-s-cap-1', WatchInboxEntry.kindSessionEnd, receivedAtMs: 900),
  );
  await repo.stageWatchInboxEntry(
    WatchInboxEntry(
      entryId: WatchInboxEntry.phoneChangeId('chg-7', 0),
      watchSessionId: _session,
      kind: WatchInboxEntry.kindPhoneCorrection,
      origin: WatchInboxEntry.originPhone,
      payload: {
        'kind': 'correct_entry',
        'entryId': 'e-set2',
        'correction': {'reps': 6},
      },
      receivedAtMs: 950,
    ),
  );
  await repo.stageWatchInboxEntry(
    _wristRow(
      'end-s-other',
      WatchInboxEntry.kindSessionEnd,
      session: _otherSession,
      receivedAtMs: 800,
    ),
  );
  await repo.markWatchInboxEntriesApplied(['end-s-cap-1', 'e-run'], 5000);
  await repo.markWatchInboxEntriesApplied(['e-run'], 6000);
  await repo.clearWatchInboxApplied(['e-run']);
  await repo.createSensorSummary(
    _summary(
      SensorSummary.scopeRoundInstance,
      'ri-1',
      fromMs: _at(10, 26),
      toMs: _at(10, 29),
      avg: 1,
      max: 1,
    ),
  );
  await repo.deleteTimedInstance('ti-run-a');
  await repo.deleteRoundInstancesForEffort('eff-bjj');
}

/// Everything the new paths hold, as `toMap` rows.
Future<Map<String, Object?>> _dump(WorkoutRepository repo) async => {
  for (final session in [_session, _otherSession]) ...{
    'inbox $session': [
      for (final e in await repo.getWatchInboxEntriesForSession(session))
        e.toMap(),
    ],
    'summaries $session': [
      for (final s in await repo.getSensorSummariesForSession(session))
        s.toMap(),
    ],
  },
  'unapplied ends': await repo.getWatchSessionIdsWithUnappliedEnd(),
};

void main() {
  group('Mock', () => _parityTests(_MockHarness.new));
  group('Hive', () => _parityTests(_HiveHarness.new));

  group('Hive and Mock store the same rows', () {
    test('D-131/D-132 one scripted sequence leaves identical inbox rows and '
        'summaries on Hive and Mock, by toMap', () async {
      final mockHarness = _MockHarness();
      final hiveHarness = _HiveHarness();
      try {
        final mock = await mockHarness.open();
        final hive = await hiveHarness.open();
        await _script(mock);
        await _script(hive);

        final mockRows = await _dump(mock);
        final hiveRows = await _dump(await hiveHarness.restart());
        expect(
          hiveRows,
          mockRows,
          reason: 'Hive ↔ Mock parity: the same rows, value for value',
        );
        expect(
          mockRows['summaries $_session'],
          hasLength(4),
          reason: 'the script leaves the session, both set blocks and ti-run-b',
        );
        expect(mockRows['unapplied ends'], [_otherSession]);
        final inboxRows = (mockRows['inbox $_session']! as List)
            .cast<Map<String, Object?>>();
        expect(
          inboxRows.firstWhere(
            (r) => r['entry_id'] == 'e-run',
          )['applied_at_ms'],
          isNull,
          reason: 'the script unsets one applied stamp and both stores agree',
        );
      } finally {
        await mockHarness.close();
        await hiveHarness.close();
      }
    });
  });

  group('D-131/D-132 model rules', () {
    test('D-131 a summary\'s id is derived from its scope and target, and '
        'fromMap refuses a stored id that is not', () {
      final summary = _sessionSummaries[3];
      expect(
        summary.id,
        'sensor-timed_instance-ti-run-b',
        reason: 'D-131: the id derives from scope and target',
      );
      expect(
        SensorSummary.fromMap(summary.toMap()).toMap(),
        summary.toMap(),
        reason: 'D-131: toMap/fromMap round trip',
      );
      expect(
        () => SensorSummary.fromMap({...summary.toMap(), 'id': 'other'}),
        throwsArgumentError,
        reason: 'D-131: a stored id that is not derived is refused',
      );
    });

    test('D-132 WatchInboxEntry refuses a kind outside its origin\'s '
        'vocabulary and phone ids that are not the deterministic ones', () {
      WatchInboxEntry build({
        String entryId = 'e-1',
        String kind = WatchInboxEntry.kindSet,
        String origin = WatchInboxEntry.originWatch,
      }) => WatchInboxEntry(
        entryId: entryId,
        watchSessionId: _session,
        kind: kind,
        origin: origin,
        payload: const {},
        receivedAtMs: 1,
      );

      for (final kind in WatchInboxEntry.watchKinds) {
        expect(build(kind: kind).kind, kind);
      }
      expect(
        () => build(entryId: ''),
        throwsArgumentError,
        reason: 'D-132: a staged row names its entry',
      );
      expect(
        () => build(origin: 'wear'),
        throwsArgumentError,
        reason: 'D-132: origin is watch or phone',
      );
      expect(
        () => build(kind: 'nutrition_log'),
        throwsArgumentError,
        reason: 'D-132: quick-logs stay with the nutrition bridge',
      );
      expect(
        () => build(kind: WatchInboxEntry.kindSet, origin: 'phone'),
        throwsArgumentError,
        reason: 'D-132: the phone never stages a wrist event as its own',
      );
      expect(
        () => build(
          entryId: WatchInboxEntry.phoneRatingId(_session),
          kind: WatchInboxEntry.kindPhoneRating,
        ),
        throwsArgumentError,
        reason: 'D-132: a phone annotation has origin phone',
      );
      expect(
        () => build(
          entryId: 'phone-rating-s-other',
          kind: WatchInboxEntry.kindPhoneRating,
          origin: WatchInboxEntry.originPhone,
        ),
        throwsArgumentError,
        reason: 'D-132: one phone rating per session, under its fixed id',
      );
      expect(
        () => build(
          entryId: 'e-set2',
          kind: WatchInboxEntry.kindPhoneCorrection,
          origin: WatchInboxEntry.originPhone,
        ),
        throwsArgumentError,
        reason: 'D-132: a phone change is keyed by its changeId and index',
      );
      expect(
        build(
          entryId: WatchInboxEntry.phoneChangeId('chg-7', 1),
          kind: WatchInboxEntry.kindPhoneDeletion,
          origin: WatchInboxEntry.originPhone,
        ).entryId,
        'phone-change-chg-7-1',
      );
      expect(
        build(
          entryId: WatchInboxEntry.phoneRatingId(_session),
          kind: WatchInboxEntry.kindPhoneRating,
          origin: WatchInboxEntry.originPhone,
        ).entryId,
        'phone-rating-s-cap-1',
      );
    });

    test('D-132 a staged payload is JSON, and the map a caller reads is a '
        'copy', () {
      final entry = _wristRow(
        'e-run',
        WatchInboxEntry.kindTimed,
        payload: _runEvent(),
      );

      entry.payload['avgHeartRateBpm'] = 999;
      expect(
        entry.payload,
        _runEvent(),
        reason: 'D-132: the map a caller reads is a copy',
      );
      expect(
        WatchInboxEntry.fromMap(entry.toMap()).toMap(),
        entry.toMap(),
        reason: 'D-132: toMap/fromMap round trip',
      );
      expect(
        () => _wristRow(
          'e-bad',
          WatchInboxEntry.kindSet,
          payload: {'at': DateTime.utc(2026)},
        ),
        throwsArgumentError,
        reason: 'D-132: a payload that is not JSON is refused',
      );
      expect(
        () => WatchInboxEntry.fromMap({
          ...entry.toMap(),
          'payload_json': '[1, 2]',
        }),
        throwsArgumentError,
        reason: 'D-132: a stored payload is a JSON object',
      );
      expect(
        () => WatchInboxEntry.fromMap({
          ...entry.toMap(),
          'payload_json': '{not json',
        }),
        throwsArgumentError,
        reason: 'D-132: a stored payload that is not JSON is refused',
      );
    });
  });
}
