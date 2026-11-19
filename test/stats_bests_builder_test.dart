// The standing bests the phone puts on the wire for the wrist (plan 87a,
// Phase 2): one pass over the history that equals the two per-exercise walks,
// and the `bests_down` frame built from it.
//
// Every number is re-derived here with `StatsProgressService.epley1RM`, never
// written as a decimal literal, so the fixture stays the plan's Fixture H and
// the arithmetic lives in one place.
//
// Scenarios: S-87a-1, S-87a-2, S-87a-3, S-87a-5, S-87a-9, S-87a-14 in
// `docs/plans/2026-10-26-87a-wrist-bests-contract-and-phone-sender-plan/`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/core/sync_protocol/wire_timestamps.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

import 'helpers/sync_protocol_harness.dart';

// ── Fixture H's exercises ────────────────────────────────────────────────
const String _bench = 'exercise-bench-press';
const String _squat = 'exercise-barbell-squat';
const String _pushUp = 'exercise-push-up';
const String _plank = 'exercise-plank-hold';

final DateTime _generatedAt = DateTime.utc(2026, 10, 26, 17);

// ── Helpers (mirrors `test/services_test.dart`) ──────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Creates a completed session with one set-based effort (reps × weight).
/// Returns the session. The repo is mutated in-place.
Future<TrainingSession> _seedCompletedSetSession(
  MockWorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  required int endedAtMs,
  required String exerciseId,
  required int reps,
  required double weight,
}) async {
  final session = TrainingSession(
    id: sessionId,
    ownerUserId: 'u-1',
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs,
    createdAtMs: startedAtMs,
    updatedAtMs: endedAtMs,
  );
  await repo.createSession(session);

  final segId = 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  final effortId = 'eff-$sessionId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );

  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-0-reps',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-0-weight',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: startedAtMs + 1,
      updatedAtMs: startedAtMs + 1,
    ),
  );

  return session;
}

/// Adds a further set effort to the single segment
/// [_seedCompletedSetSession] created for [session].
Future<void> _addSetTo(
  MockWorkoutRepository repo, {
  required TrainingSession session,
  required int orderIndex,
  required String exerciseId,
  required int reps,
  required double weight,
}) async {
  final effortId = 'eff-${session.id}-$orderIndex';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-${session.id}',
      orderIndex: orderIndex,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: session.startedAtMs,
      updatedAtMs: session.startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-reps',
      effortId: effortId,
      metricId: 'metric-reps',
      valueInt: reps,
      createdAtMs: session.startedAtMs,
      updatedAtMs: session.startedAtMs,
    ),
  );
  await repo.createObservation(
    EffortObservation(
      id: 'obs-$effortId-weight',
      effortId: effortId,
      metricId: 'metric-weight',
      valueReal: weight,
      createdAtMs: session.startedAtMs + 1,
      updatedAtMs: session.startedAtMs + 1,
    ),
  );
}

/// Adds a `hold` effort (a plank) to [session] carrying the fixture's
/// `0 reps, weight 0, 60 s hold`.
Future<void> _addHoldTo(
  MockWorkoutRepository repo, {
  required TrainingSession session,
  required int orderIndex,
  required String exerciseId,
  required int holdSeconds,
}) async {
  final effortId = 'eff-${session.id}-$orderIndex';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-${session.id}',
      orderIndex: orderIndex,
      effortKind: 'hold',
      exerciseId: exerciseId,
      createdAtMs: session.startedAtMs,
      updatedAtMs: session.startedAtMs,
    ),
  );
  for (final row in [
    ('metric-reps', 0, 0.0),
    ('metric-weight', 0, 0.0),
    ('metric-duration', holdSeconds, 0.0),
  ]) {
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effortId-${row.$1}',
        effortId: effortId,
        metricId: row.$1,
        valueInt: row.$2,
        valueReal: row.$3,
        createdAtMs: session.startedAtMs,
        updatedAtMs: session.startedAtMs,
      ),
    );
  }
}

/// Marks [session] as in progress by clearing its `endedAtMs`, the way
/// `test/services_test.dart` does.
Future<void> _reopen(MockWorkoutRepository repo, TrainingSession session) =>
    repo.updateSession(
      TrainingSession(
        id: session.id,
        ownerUserId: session.ownerUserId,
        startedAtMs: session.startedAtMs,
        createdAtMs: session.createdAtMs,
        updatedAtMs: session.startedAtMs,
      ),
    );

/// Fixture H: two completed sessions plus an in-progress one.
Future<MockWorkoutRepository> _fixtureH() async {
  final repo = await _freshRepo();

  final first = await _seedCompletedSetSession(
    repo,
    sessionId: 's-1',
    startedAtMs: 1000,
    endedAtMs: 2000,
    exerciseId: _bench,
    reps: 5,
    weight: 100.0,
  );
  await _addSetTo(
    repo,
    session: first,
    orderIndex: 1,
    exerciseId: _bench,
    reps: 3,
    weight: 100.0,
  );
  await _addSetTo(
    repo,
    session: first,
    orderIndex: 2,
    exerciseId: _squat,
    reps: 5,
    weight: 140.0,
  );
  await _addSetTo(
    repo,
    session: first,
    orderIndex: 3,
    exerciseId: _pushUp,
    reps: 12,
    weight: 0.0,
  );
  await _addHoldTo(
    repo,
    session: first,
    orderIndex: 4,
    exerciseId: _plank,
    holdSeconds: 60,
  );

  await _seedCompletedSetSession(
    repo,
    sessionId: 's-2',
    startedAtMs: 3000,
    endedAtMs: 4000,
    exerciseId: _bench,
    reps: 8,
    weight: 90.0,
  );

  final inProgress = await _seedCompletedSetSession(
    repo,
    sessionId: 's-3',
    startedAtMs: 5000,
    endedAtMs: 6000,
    exerciseId: _bench,
    reps: 5,
    weight: 120.0,
  );
  await _addSetTo(
    repo,
    session: inProgress,
    orderIndex: 1,
    exerciseId: _pushUp,
    reps: 20,
    weight: 0.0,
  );
  await _reopen(repo, inProgress);

  return repo;
}

Map<String, Object?> _payloadOf(Map<String, Object?> frame) =>
    (frame['payload']! as Map).cast<String, Object?>();

List<Map<String, Object?>> _bestsOf(Map<String, Object?> frame) => [
  for (final entry in _payloadOf(frame)['bests']! as List)
    (entry as Map).cast<String, Object?>(),
];

Map<String, Object?>? _entryOf(
  List<Map<String, Object?>> bests,
  String exerciseId,
) {
  for (final entry in bests) {
    if (entry['exerciseId'] == exerciseId) return entry;
  }
  return null;
}

/// The frame as the protocol receives it: through JSON, then through the real
/// schemas, so a builder that drifts from `bests_down.schema.json` fails here.
void _expectFrameAdmits(Map<String, Object?> frame, String reason) {
  final wire = (jsonDecode(jsonEncode(frame)) as Map).cast<String, Object?>();
  expect(loadProtocolValidator().validateEnvelope(wire), isEmpty, reason: reason);
}

void main() {
  group('StatsProgressService.getAllTimeBests', () {
    test(
      'S-87a-1 fixture H: completed sets only, both axes, in-progress excluded',
      () async {
        final repo = await _fixtureH();
        final bests = await StatsProgressService(repo).getAllTimeBests();

        expect(bests.keys, unorderedEquals([_bench, _squat, _pushUp]));

        final bench = bests[_bench]!;
        expect(
          bench.e1rm,
          StatsProgressService.epley1RM(100.0, 5),
          reason: 'S-87a-1 the best bench e1RM is the 100 × 5 set',
        );
        expect(
          bench.e1rm,
          isNot(StatsProgressService.epley1RM(90.0, 8)),
          reason: 'S-87a-1 the 90 × 8 set is not the best',
        );
        expect(
          bench.reps,
          0,
          reason: 'S-87a-1 a weighted exercise has no bodyweight rep best',
        );

        final squat = bests[_squat]!;
        expect(squat.e1rm, StatsProgressService.epley1RM(140.0, 5));
        expect(squat.reps, 0);

        final pushUp = bests[_pushUp]!;
        expect(
          pushUp.reps,
          12,
          reason: 'S-87a-1 the in-progress 20 reps are not history',
        );
        expect(pushUp.e1rm, 0.0);

        expect(
          bests.containsKey(_plank),
          isFalse,
          reason: 'S-87a-1 a hold effort is not a set',
        );
      },
    );

    test('S-87a-2 an exercise trained on both axes carries both bests', () async {
      final repo = await _freshRepo();
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-weighted',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: _bench,
        reps: 5,
        weight: 100.0,
      );
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-bodyweight',
        startedAtMs: 3000,
        endedAtMs: 4000,
        exerciseId: _bench,
        reps: 15,
        weight: 0.0,
      );

      final best = (await StatsProgressService(repo).getAllTimeBests())[_bench]!;
      expect(best.e1rm, StatsProgressService.epley1RM(100.0, 5));
      expect(best.reps, 15);
    });

    test('S-87a-3 no completed sessions yields no bests', () async {
      final repo = await _freshRepo();
      expect(await StatsProgressService(repo).getAllTimeBests(), isEmpty);
    });

    test('S-87a-14 an in-progress session contributes nothing', () async {
      final repo = await _freshRepo();
      final session = await _seedCompletedSetSession(
        repo,
        sessionId: 's-open',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: _bench,
        reps: 5,
        weight: 100.0,
      );
      await _reopen(repo, session);

      expect(await StatsProgressService(repo).getAllTimeBests(), isEmpty);
    });

    test(
      'S-87a-5 parity: every exercise equals getAllTimeBestE1RM and '
      'getAllTimeBestReps',
      () async {
        final repo = await _fixtureH();
        final service = StatsProgressService(repo);
        final bulk = await service.getAllTimeBests();

        final ids = <String>{
          _bench,
          _squat,
          _pushUp,
          _plank,
          for (final exercise in await repo.getExercises()) exercise.id,
        };
        expect(ids.length, greaterThan(3), reason: 'S-87a-5 seed data is walked');

        for (final id in ids) {
          expect(
            bulk[id]?.e1rm ?? 0.0,
            await service.getAllTimeBestE1RM(id),
            reason: 'S-87a-5 e1RM axis agrees for $id',
          );
          expect(
            bulk[id]?.reps ?? 0,
            await service.getAllTimeBestReps(id),
            reason: 'S-87a-5 reps axis agrees for $id',
          );
        }
      },
    );

    test('S-87a-9 more than 300 trained exercises all reach the bulk map', () async {
      final repo = await _freshRepo();
      final session = await _seedCompletedSetSession(
        repo,
        sessionId: 's-cap',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: 'ex-000',
        reps: 5,
        weight: 60.0,
      );
      for (var index = 1; index <= 300; index++) {
        await _addSetTo(
          repo,
          session: session,
          orderIndex: index,
          exerciseId: 'ex-${index.toString().padLeft(3, '0')}',
          reps: 5,
          weight: 60.0,
        );
      }

      expect(await StatsProgressService(repo).getAllTimeBests(), hasLength(301));
    });
  });

  group('WatchReferenceSync.buildBestsDown', () {
    test('S-87a-1 the frame carries fixture H, ordered by exerciseId', () async {
      final repo = await _fixtureH();
      final bests = await StatsProgressService(repo).getAllTimeBests();
      final frame = WatchReferenceSync.buildBestsDown(
        bests: bests,
        generatedAt: _generatedAt,
      );

      expect(frame['type'], 'bests_down');
      expect(frame['origin'], 'phone');
      expect(
        frame['messageId'],
        'msg-bests-${_generatedAt.toUtc().millisecondsSinceEpoch}',
      );
      expect(_payloadOf(frame)['generatedAt'], utcIso(_generatedAt));

      final entries = _bestsOf(frame);
      expect(
        [for (final entry in entries) entry['exerciseId']],
        [_squat, _bench, _pushUp],
        reason: 'S-87a-1/D-12 ascending exerciseId, the hold absent',
      );

      final bench = _entryOf(entries, _bench)!;
      expect(bench['e1rmKg'], isA<double>());
      expect(
        bench['e1rmKg'],
        StatsProgressService.epley1RM(100.0, 5),
        reason: 'S-87a-1/D-10 the unrounded estimate',
      );
      expect(bench.containsKey('repsBest'), isFalse);

      final squat = _entryOf(entries, _squat)!;
      expect(squat['e1rmKg'], StatsProgressService.epley1RM(140.0, 5));

      final pushUp = _entryOf(entries, _pushUp)!;
      expect(pushUp['repsBest'], 12);
      expect(pushUp.containsKey('e1rmKg'), isFalse);

      expect(_entryOf(entries, _plank), isNull);
      _expectFrameAdmits(frame, 'S-87a-1 the built frame is schema-valid');
    });

    test('S-87a-2 the frame carries both axes for one exercise', () async {
      final repo = await _freshRepo();
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-weighted',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: _bench,
        reps: 5,
        weight: 100.0,
      );
      await _seedCompletedSetSession(
        repo,
        sessionId: 's-bodyweight',
        startedAtMs: 3000,
        endedAtMs: 4000,
        exerciseId: _bench,
        reps: 15,
        weight: 0.0,
      );

      final frame = WatchReferenceSync.buildBestsDown(
        bests: await StatsProgressService(repo).getAllTimeBests(),
        generatedAt: _generatedAt,
      );
      final entry = _bestsOf(frame).single;
      expect(entry['e1rmKg'], StatsProgressService.epley1RM(100.0, 5));
      expect(entry['repsBest'], 15);
      _expectFrameAdmits(frame, 'S-87a-2 both axes are one valid entry');
    });

    test('S-87a-3 an empty history is an empty bests array', () async {
      final repo = await _freshRepo();
      final frame = WatchReferenceSync.buildBestsDown(
        bests: await StatsProgressService(repo).getAllTimeBests(),
        generatedAt: _generatedAt,
      );

      expect(_bestsOf(frame), isEmpty);
      _expectFrameAdmits(frame, 'S-87a-3 an empty frame is a frame');
    });

    test('S-87a-14 in-progress only builds an empty bests array', () async {
      final repo = await _freshRepo();
      final session = await _seedCompletedSetSession(
        repo,
        sessionId: 's-open',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: _bench,
        reps: 5,
        weight: 100.0,
      );
      await _reopen(repo, session);

      final frame = WatchReferenceSync.buildBestsDown(
        bests: await StatsProgressService(repo).getAllTimeBests(),
        generatedAt: _generatedAt,
      );
      expect(_bestsOf(frame), isEmpty);
      _expectFrameAdmits(frame, 'S-87a-14 no history is an empty frame');
    });

    test('S-87a-9 the frame stops at 300, ex-000 through ex-299', () async {
      final repo = await _freshRepo();
      final session = await _seedCompletedSetSession(
        repo,
        sessionId: 's-cap',
        startedAtMs: 1000,
        endedAtMs: 2000,
        exerciseId: 'ex-000',
        reps: 5,
        weight: 60.0,
      );
      for (var index = 1; index <= 300; index++) {
        await _addSetTo(
          repo,
          session: session,
          orderIndex: index,
          exerciseId: 'ex-${index.toString().padLeft(3, '0')}',
          reps: 5,
          weight: 60.0,
        );
      }

      final frame = WatchReferenceSync.buildBestsDown(
        bests: await StatsProgressService(repo).getAllTimeBests(),
        generatedAt: _generatedAt,
      );
      final entries = _bestsOf(frame);
      expect(entries, hasLength(300));
      expect(entries.first['exerciseId'], 'ex-000');
      expect(entries.last['exerciseId'], 'ex-299');
      expect(_entryOf(entries, 'ex-300'), isNull);
      expect(
        [for (final entry in entries) entry['exerciseId']],
        [for (var index = 0; index < 300; index++) 'ex-${index.toString().padLeft(3, '0')}'],
      );
      expect(
        entries.first['e1rmKg'],
        StatsProgressService.epley1RM(60.0, 5),
      );
      _expectFrameAdmits(frame, 'S-87a-9 a 300-entry frame is schema-valid');
    });
  });
}
