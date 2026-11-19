// Plan 249 P2 — the service/state tests for "last time" (S-24901..S-24907).
//
// The service answers from the four bulk reads only, so the fixtures seed
// sessions, segments, efforts and observation rows straight into the store,
// exactly the way the logger writes them (`obs-<effortId>-<n>-reps` /
// `obs-<effortId>-<n>-weight`). Plain `test()`: a Hive write never settles
// inside a `testWidgets`.
//
// Plan: `docs/plans/2026-11-19-249-last-time-line-plan/2026-11-19-249-last-time-line-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/last_performance_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture times ──────────────────────────────────────────────────────────

final _s1Start = DateTime(2026, 11, 10, 12).millisecondsSinceEpoch;
final _s1End = DateTime(2026, 11, 10, 13).millisecondsSinceEpoch;
final _s2Start = DateTime(2026, 11, 12, 12).millisecondsSinceEpoch;
final _s2End = DateTime(2026, 11, 12, 13).millisecondsSinceEpoch;
final _s3Start = DateTime(2026, 11, 13, 12).millisecondsSinceEpoch;

// ─── Seeding ────────────────────────────────────────────────────────────────

/// A session with one segment and one `set` effort for [exerciseId], holding
/// [sets] as reps/weight rows the way the logger numbers them (entry 0 first).
/// `endedAtMs` null leaves the session running (S-24901's s3). The effort id
/// `eff-<segmentId>-<exerciseId>` keeps a second block's effort apart (S-24905).
Future<void> seedBench(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  int? endedAtMs,
  required List<(int reps, double kg, {bool skipped})> sets,
  String exerciseId = 'ex-bench',
  String effortKind = 'set',
  int segmentOrder = 0,
  String? segmentId,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final segId = segmentId ?? 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: segmentOrder,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final effortId = 'eff-$segId-$exerciseId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: effortKind,
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  for (var n = 0; n < sets.length; n++) {
    final at = startedAtMs + 1000 + n;
    await repo.createObservation(
      repsRow(effortId, n, sets[n].$1, atMs: at, skipped: sets[n].skipped),
    );
    await repo.createObservation(
      weightRow(effortId, n, sets[n].$2, atMs: at + 1),
    );
  }
}

/// The standard S-24901 fixture: s1 (Nov 10, ended, three sets), s2 (Nov 12,
/// ended, one set), s3 (Nov 13, running, one set).
Future<void> seedStandardFixture(WorkoutRepository repo) async {
  await seedBench(
    repo,
    sessionId: 's1',
    startedAtMs: _s1Start,
    endedAtMs: _s1End,
    sets: [
      (8, 80.0, skipped: false),
      (8, 80.0, skipped: false),
      (6, 82.5, skipped: false),
    ],
  );
  await seedBench(
    repo,
    sessionId: 's2',
    startedAtMs: _s2Start,
    endedAtMs: _s2End,
    sets: [(5, 90.0, skipped: false)],
  );
  await seedBench(
    repo,
    sessionId: 's3',
    startedAtMs: _s3Start,
    sets: [(1, 100.0, skipped: false)],
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  for (final make in harnessFactories) {
    final name = make().name;
    group('$name: last time service', () {
      late RepositoryHarness harness;
      setUp(() => harness = make());
      tearDown(() => harness.close());

      test('S-24901 the newest finished workout answers, the running one '
          'does not', () async {
        final repo = await harness.open();
        await seedStandardFixture(repo);

        final answer = await LastPerformanceService(
          repo,
        ).lastSetsFor('ex-bench');

        expect(answer!.startedAtMs, _s2Start);
        expect(answer.sets, hasLength(1));
        expect(answer.sets.single.reps, 5);
        expect(answer.sets.single.weightKg, 90.0);
      });

      test(
        'S-24902 excludeSessionId falls through to the older workout',
        () async {
          final repo = await harness.open();
          await seedStandardFixture(repo);

          final answer = await LastPerformanceService(
            repo,
          ).lastSetsFor('ex-bench', excludeSessionId: 's2');

          expect(answer!.startedAtMs, _s1Start);
          expect(answer.sets, hasLength(3));
          expect(answer.sets[0].reps, 8);
          expect(answer.sets[0].weightKg, 80.0);
          expect(answer.sets[1].reps, 8);
          expect(answer.sets[2].reps, 6);
          expect(answer.sets[2].weightKg, 82.5);
        },
      );

      test('S-24903a skipped and empty sets are not kept', () async {
        final repo = await harness.open();
        await seedStandardFixture(repo);
        // s2 re-seeded: a skipped set and a reps-0 set before the kept one.
        // createSession is a put by id, so the session rows are unchanged.
        await seedBench(
          repo,
          sessionId: 's2',
          startedAtMs: _s2Start,
          endedAtMs: _s2End,
          sets: [
            (5, 90.0, skipped: true),
            (0, 0.0, skipped: false),
            (5, 90.0, skipped: false),
          ],
        );

        final answer = await LastPerformanceService(
          repo,
        ).lastSetsFor('ex-bench');

        expect(answer!.startedAtMs, _s2Start);
        expect(answer.sets, hasLength(1));
        expect(answer.sets.single.reps, 5);
        expect(answer.sets.single.weightKg, 90.0);
      });

      test(
        'S-24903b an all-skipped workout falls through to the older one',
        () async {
          final repo = await harness.open();
          await seedStandardFixture(repo);
          await seedBench(
            repo,
            sessionId: 's2',
            startedAtMs: _s2Start,
            endedAtMs: _s2End,
            sets: [(5, 90.0, skipped: true)],
          );

          final answer = await LastPerformanceService(
            repo,
          ).lastSetsFor('ex-bench');

          expect(answer!.startedAtMs, _s1Start);
          expect(answer.sets, hasLength(3));
          expect(answer.sets[2].reps, 6);
          expect(answer.sets[2].weightKg, 82.5);
        },
      );

      test('S-24904a an exercise with no history answers null', () async {
        final repo = await harness.open();
        await seedStandardFixture(repo);

        final answer = await LastPerformanceService(
          repo,
        ).lastSetsFor('ex-squat');

        expect(answer, isNull);
      });

      test(
        'S-24904b a timed effort is not a set effort, even with set rows',
        () async {
          final repo = await harness.open();
          // The timed effort holds real reps/weight rows, as if a timed exercise
          // had been logged through the set logger: without the kind check the
          // service would answer [(5, 90.0)]. No other session holds the
          // exercise, so a correct kind check answers null.
          await seedBench(
            repo,
            sessionId: 's1',
            startedAtMs: _s1Start,
            endedAtMs: _s1End,
            sets: [(5, 90.0, skipped: false)],
            effortKind: 'timed',
          );

          final answer = await LastPerformanceService(
            repo,
          ).lastSetsFor('ex-bench');

          expect(answer, isNull);
        },
      );

      test('S-24905 two blocks list both, in block order', () async {
        final repo = await harness.open();
        // Block order 1 seeded first, so the store order cannot give the
        // answer by accident.
        await seedBench(
          repo,
          sessionId: 's2',
          startedAtMs: _s2Start,
          endedAtMs: _s2End,
          sets: [(4, 92.5, skipped: false)],
          segmentId: 'seg-s2-b',
          segmentOrder: 1,
        );
        await seedBench(
          repo,
          sessionId: 's2',
          startedAtMs: _s2Start,
          endedAtMs: _s2End,
          sets: [(5, 90.0, skipped: false)],
        );

        final answer = await LastPerformanceService(
          repo,
        ).lastSetsFor('ex-bench');

        expect(answer!.startedAtMs, _s2Start);
        expect(answer.sets, hasLength(2));
        expect(answer.sets[0].reps, 5);
        expect(answer.sets[0].weightKg, 90.0);
        expect(answer.sets[1].reps, 4);
        expect(answer.sets[1].weightKg, 92.5);
      });

      test('S-24906 store order does not decide', () async {
        final repo = await harness.open();
        // s2 stored before s1.
        await seedBench(
          repo,
          sessionId: 's2',
          startedAtMs: _s2Start,
          endedAtMs: _s2End,
          sets: [(5, 90.0, skipped: false)],
        );
        await seedBench(
          repo,
          sessionId: 's1',
          startedAtMs: _s1Start,
          endedAtMs: _s1End,
          sets: [
            (8, 80.0, skipped: false),
            (8, 80.0, skipped: false),
            (6, 82.5, skipped: false),
          ],
        );

        final answer = await LastPerformanceService(
          repo,
        ).lastSetsFor('ex-bench');

        expect(answer!.startedAtMs, _s2Start);
        expect(answer.sets.single.reps, 5);
        expect(answer.sets.single.weightKg, 90.0);
      });
    });
  }

  // S-24907 is state-level and Mock only: the running workout is never its
  // own "last time", because WorkoutState passes its id as excludeSessionId.
  test('S-24907 the running workout is not its own last time', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    await seedBench(
      repo,
      sessionId: 's1',
      startedAtMs: _s1Start,
      endedAtMs: _s1End,
      sets: [
        (8, 80.0, skipped: false),
        (8, 80.0, skipped: false),
        (6, 82.5, skipped: false),
      ],
    );
    await seedBench(
      repo,
      sessionId: 's2',
      startedAtMs: _s2Start,
      endedAtMs: _s2End,
      sets: [(5, 90.0, skipped: false)],
    );

    final state = WorkoutState(repo);
    await state.createNewSession(modality: Modality.resistanceLifting);

    // The live session holds the exercise with a logged set, the way s3
    // does in S-24901.
    final live = state.currentSession!;
    final segment = (await repo.getSessionSegments(live.id)).first;
    final effortId = 'eff-${segment.id}-ex-bench';
    await repo.createEffort(
      SegmentEffort(
        id: effortId,
        segmentId: segment.id,
        orderIndex: 0,
        effortKind: 'set',
        exerciseId: 'ex-bench',
        createdAtMs: live.startedAtMs,
        updatedAtMs: live.startedAtMs,
      ),
    );
    await repo.createObservation(
      repsRow(effortId, 0, 1, atMs: live.startedAtMs + 1000),
    );
    await repo.createObservation(
      weightRow(effortId, 0, 100.0, atMs: live.startedAtMs + 1001),
    );

    final answer = await state.lastSetsFor('ex-bench');

    expect(answer!.startedAtMs, _s2Start);
    expect(answer.sets.single.reps, 5);
    expect(answer.sets.single.weightKg, 90.0);
  });

  // S-24907b is Mock only: the exclusion also covers a FINISHED session
  // loaded as the current one (a workout opened for editing) — without the
  // excludeSessionId pass-through the answer would be s2's own set.
  test('S-24907b the loaded workout is not its own last time', () async {
    final repo = MockWorkoutRepository();
    await repo.initialize();
    await seedBench(
      repo,
      sessionId: 's1',
      startedAtMs: _s1Start,
      endedAtMs: _s1End,
      sets: [
        (8, 80.0, skipped: false),
        (8, 80.0, skipped: false),
        (6, 82.5, skipped: false),
      ],
    );
    await seedBench(
      repo,
      sessionId: 's2',
      startedAtMs: _s2Start,
      endedAtMs: _s2End,
      sets: [(5, 90.0, skipped: false)],
    );

    final state = WorkoutState(repo);
    await state.loadHistoricalSession('s2');

    final answer = await state.lastSetsFor('ex-bench');

    expect(answer!.startedAtMs, _s1Start);
    expect(answer.sets, hasLength(3));
    expect(answer.sets.first.reps, 8);
  });

  // Plan 250 (review finding 2): the cached history is single-flight. Two
  // callers that arrive before the first read finishes share it.
  test(
    'S-25013 a cached service reads the history once for two callers',
    () async {
      final repo = _CountingRepo();
      await repo.initialize();
      await seedBench(
        repo,
        sessionId: 's2',
        startedAtMs: _s2Start,
        endedAtMs: _s2End,
        sets: [(5, 90.0, skipped: false)],
      );
      repo.sessionReads = 0;

      final cached = LastPerformanceService(repo, cacheHistory: true);
      final answers = await Future.wait([
        cached.lastSetsFor('ex-bench'),
        cached.lastSetsFor('ex-bench'),
      ]);
      await cached.lastSetsFor('ex-bench');

      expect(answers.every((a) => a?.sets.single.reps == 5), isTrue);
      expect(repo.sessionReads, 1);

      // Control: the default service asks fresh every time.
      repo.sessionReads = 0;
      final fresh = LastPerformanceService(repo);
      await fresh.lastSetsFor('ex-bench');
      await fresh.lastSetsFor('ex-bench');
      expect(repo.sessionReads, 2);
    },
  );

  // A failed read is not kept: the next call reads again.
  test('S-25014 a failed history read is retried by the next call', () async {
    final repo = _CountingRepo();
    await repo.initialize();
    await seedBench(
      repo,
      sessionId: 's2',
      startedAtMs: _s2Start,
      endedAtMs: _s2End,
      sets: [(5, 90.0, skipped: false)],
    );
    repo.sessionReads = 0;
    repo.failNextRead = true;

    final cached = LastPerformanceService(repo, cacheHistory: true);
    await expectLater(cached.lastSetsFor('ex-bench'), throwsStateError);
    final answer = await cached.lastSetsFor('ex-bench');

    expect(answer!.sets.single.reps, 5);
    expect(repo.sessionReads, 2);
  });
}

/// Counts how often the sessions are read and can fail the next read
/// (plan 250 S-25013, S-25014).
class _CountingRepo extends MockWorkoutRepository {
  int sessionReads = 0;
  bool failNextRead = false;

  @override
  Future<List<TrainingSession>> getAllSessions() {
    sessionReads++;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('boom');
    }
    return super.getAllSessions();
  }
}
