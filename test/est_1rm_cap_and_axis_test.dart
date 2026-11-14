// Plan 157b P1 — Est. 1RM counts at most 12 reps; the axis is decided by
// majority (phone).
//
// Scenarios S-15801..S-15809 of
// `docs/plans/2026-11-13-157b-stats-1rm-cap-and-axis-plan/2026-11-13-157b-stats-1rm-cap-and-axis-plan.md`.
// Both stores must behave identically.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// One set effort of [exerciseId] with a single entry of [reps] reps at
/// [weightKg], on the segment `seedSession` created for [sessionId].
Future<void> seedOneSet(
  WorkoutRepository repo, {
  required String sessionId,
  required String effortId,
  required String exerciseId,
  required int reps,
  required double weightKg,
}) async {
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$sessionId',
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  await repo.createObservation(
    repsRow(effortId, 0, reps, atMs: fixtureRowAt(0)),
  );
  await repo.createObservation(
    weightRow(effortId, 0, weightKg, atMs: fixtureRowAt(0)),
  );
}

void main() {
  // S-15801 has no store behind it: the formula is a pure static.
  test('S-15801 epley1RM counts at most 12 reps of a set', () {
    expect(StatsProgressService.epley1RM(100, 1), closeTo(103.33333333333334, 1e-9));
    expect(StatsProgressService.epley1RM(100, 10), closeTo(133.33333333333331, 1e-9));
    expect(StatsProgressService.epley1RM(100, 12), closeTo(140.0, 1e-9));
    expect(StatsProgressService.epley1RM(100, 13), closeTo(140.0, 1e-9));
    expect(StatsProgressService.epley1RM(100, 30), closeTo(140.0, 1e-9));
    expect(StatsProgressService.epley1RM(0, 5), isNull);
    expect(StatsProgressService.epley1RM(100, 0), isNull);
    expect(
      StatsProgressService.epley1RM(100, 30),
      equals(StatsProgressService.epley1RM(100, 12)),
    );
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — Est. 1RM cap and axis majority (plan 157b)', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-15802 a 100 kg x 30 set reads 140.0 on both best reads', () async {
        await seedSession(repo, sessionId: 's-1', daysAgo: 1);
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Squat',
          capabilities: ['load'],
        );
        await seedOneSet(
          repo,
          sessionId: 's-1',
          effortId: 'e-s1',
          exerciseId: 'ex-squat',
          reps: 30,
          weightKg: 100.0,
        );
        final service = StatsProgressService(repo);
        expect(await service.getAllTimeBestE1RM('ex-squat'), closeTo(140.0, 1e-9));
        final bests = await service.getAllTimeBests();
        expect(bests['ex-squat']!.e1rm, closeTo(140.0, 1e-9));
      });

      test('S-15803 one stray zero-weight set leaves Squat on Est. 1RM', () async {
        for (final day in [5, 4, 3, 2]) {
          await seedSession(repo, sessionId: 's-$day', daysAgo: day);
          await seedOneSet(
            repo,
            sessionId: 's-$day',
            effortId: 'e-s$day',
            exerciseId: 'ex-squat',
            reps: 5,
            weightKg: 100.0,
          );
        }
        await seedSession(repo, sessionId: 's-1', daysAgo: 1);
        await seedOneSet(
          repo,
          sessionId: 's-1',
          effortId: 'e-s1',
          exerciseId: 'ex-squat',
          reps: 10,
          weightKg: 0.0,
        );
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Squat',
          capabilities: ['load'],
        );

        final data = await StatsProgressService(repo).computeProgressData();
        final squat = data.topLifts.firstWhere(
          (lift) => lift.exerciseName == 'Squat',
        );
        expect(squat.e1RmTrend, isNotEmpty);
        expect(squat.repsTrend, isEmpty);
        final pr = data.recentPRs.firstWhere(
          (record) => record.exerciseName == 'Squat',
        );
        expect(pr.e1Rm, isNotNull);
        expect(pr.reps, isNull);

        final summaries = await StatsProgressService(
          repo,
        ).computeExerciseMetrics();
        final squatMetrics = summaries.firstWhere(
          (summary) => summary.exerciseId == 'ex-squat',
        );
        expect(squatMetrics.best.metric, NativeMetric.estimatedOneRepMax);
        expect(squatMetrics.best.value, closeTo(116.6666667, 1e-6));
      });

      test('S-15804 a mostly bodyweight Push-up stays on the reps axis', () async {
        await seedExercise(repo, id: 'ex-pushup', name: 'Push-up');
        for (final day in [4, 3, 2]) {
          await seedSession(repo, sessionId: 's-$day', daysAgo: day);
          await seedOneSet(
            repo,
            sessionId: 's-$day',
            effortId: 'e-s$day',
            exerciseId: 'ex-pushup',
            reps: 12,
            weightKg: 0.0,
          );
        }
        await seedSession(repo, sessionId: 's-1', daysAgo: 1);
        await seedOneSet(
          repo,
          sessionId: 's-1',
          effortId: 'e-s1',
          exerciseId: 'ex-pushup',
          reps: 8,
          weightKg: 10.0,
        );

        final data = await StatsProgressService(repo).computeProgressData();
        final pushup = data.topLifts.firstWhere(
          (lift) => lift.exerciseName == 'Push-up',
        );
        expect(pushup.repsTrend, isNotEmpty);
        expect(pushup.e1RmTrend, isEmpty);
      });

      test('S-15805 a tie of zero-weight and loaded sets reads Est. 1RM', () async {
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Squat',
          capabilities: ['load'],
        );
        await seedSession(repo, sessionId: 's-1', daysAgo: 2);
        await seedOneSet(
          repo,
          sessionId: 's-1',
          effortId: 'e-s1',
          exerciseId: 'ex-squat',
          reps: 10,
          weightKg: 0.0,
        );
        await seedSession(repo, sessionId: 's-2', daysAgo: 1);
        await seedOneSet(
          repo,
          sessionId: 's-2',
          effortId: 'e-s2',
          exerciseId: 'ex-squat',
          reps: 8,
          weightKg: 60.0,
        );

        final data = await StatsProgressService(repo).computeProgressData();
        final squat = data.topLifts.firstWhere(
          (lift) => lift.exerciseName == 'Squat',
        );
        expect(squat.e1RmTrend, isNotEmpty);
        expect(squat.repsTrend, isEmpty);
      });

      test('S-15806 an all-zero-weight exercise stays on the reps axis', () async {
        await seedExercise(repo, id: 'ex-pushup', name: 'Push-up');
        for (final day in [3, 2, 1]) {
          await seedSession(repo, sessionId: 's-$day', daysAgo: day);
          await seedOneSet(
            repo,
            sessionId: 's-$day',
            effortId: 'e-s$day',
            exerciseId: 'ex-pushup',
            reps: 10,
            weightKg: 0.0,
          );
        }

        final data = await StatsProgressService(repo).computeProgressData();
        final pushup = data.topLifts.firstWhere(
          (lift) => lift.exerciseName == 'Push-up',
        );
        expect(pushup.repsTrend, isNotEmpty);
        expect(pushup.e1RmTrend, isEmpty);
      });

      test('S-15807 skipped sets tally nowhere: five loaded sets win the axis', () async {
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Squat',
          capabilities: ['load'],
        );
        for (final day in [10, 9, 8, 7, 6]) {
          await seedSession(repo, sessionId: 's-loaded-$day', daysAgo: day);
          await seedOneSet(
            repo,
            sessionId: 's-loaded-$day',
            effortId: 'e-loaded-$day',
            exerciseId: 'ex-squat',
            reps: 8,
            weightKg: 60.0,
          );
        }
        // Six skipped sets against five loaded ones: were they tallied as
        // zero-weight entries they would outnumber the loaded ones.
        for (final day in [11, 5, 4, 3, 2, 1]) {
          await seedSession(repo, sessionId: 's-skip-$day', daysAgo: day);
          await seedOneSet(
            repo,
            sessionId: 's-skip-$day',
            effortId: 'e-skip-$day',
            exerciseId: 'ex-squat',
            reps: 0,
            weightKg: 0.0,
          );
        }

        final data = await StatsProgressService(repo).computeProgressData();
        final squat = data.topLifts.firstWhere(
          (lift) => lift.exerciseName == 'Squat',
        );
        expect(squat.e1RmTrend, isNotEmpty);
        expect(squat.repsTrend, isEmpty);
      });

      test('S-15810b an unfinished session does not decide the axis', () async {
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Squat',
          capabilities: ['load'],
        );
        for (final day in [3, 2]) {
          await seedSession(repo, sessionId: 's-done-$day', daysAgo: day);
          await seedOneSet(
            repo,
            sessionId: 's-done-$day',
            effortId: 'e-done-$day',
            exerciseId: 'ex-squat',
            reps: 5,
            weightKg: 100.0,
          );
        }
        // A session still running (no end) holding three weightless sets.
        await seedSession(repo, sessionId: 's-live', daysAgo: 1, isRolling: true);
        for (final n in [1, 2, 3]) {
          await seedOneSet(
            repo,
            sessionId: 's-live',
            effortId: 'e-live-$n',
            exerciseId: 'ex-squat',
            reps: 10,
            weightKg: 0.0,
          );
        }

        final data = await StatsProgressService(repo).computeProgressData();
        final squat = data.topLifts.firstWhere(
          (lift) => lift.exerciseName == 'Squat',
        );
        expect(squat.e1RmTrend, isNotEmpty);
        expect(squat.repsTrend, isEmpty);
      });

      test('S-15808 progressionSamples read Squat in e1RM kilograms', () async {
        for (final day in [5, 4, 3, 2]) {
          await seedSession(repo, sessionId: 's-$day', daysAgo: day);
          await seedOneSet(
            repo,
            sessionId: 's-$day',
            effortId: 'e-s$day',
            exerciseId: 'ex-squat',
            reps: 5,
            weightKg: 100.0,
          );
        }
        await seedSession(repo, sessionId: 's-1', daysAgo: 1);
        await seedOneSet(
          repo,
          sessionId: 's-1',
          effortId: 'e-s1',
          exerciseId: 'ex-squat',
          reps: 10,
          weightKg: 0.0,
        );
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Squat',
          capabilities: ['load'],
        );

        final samples = (await StatsProgressService(
          repo,
        ).progressionSamples()).where((s) => s.exerciseId == 'ex-squat');
        final loaded = samples.where((s) => s.value > 0).toList();
        expect(loaded, hasLength(4));
        for (final sample in loaded) {
          expect(sample.value, closeTo(116.6666667, 1e-6));
        }
        expect(samples.any((s) => s.value == 10), isFalse);
      });

      test('S-15809 the toast comparison: 100 x 30 no longer beats 140.0', () async {
        await seedSession(repo, sessionId: 's-1', daysAgo: 1);
        await seedExercise(
          repo,
          id: 'ex-squat',
          name: 'Squat',
          capabilities: ['load'],
        );
        await seedOneSet(
          repo,
          sessionId: 's-1',
          effortId: 'e-s1',
          exerciseId: 'ex-squat',
          reps: 12,
          weightKg: 100.0,
        );
        final service = StatsProgressService(repo);
        final best = await service.getAllTimeBestE1RM('ex-squat');
        expect(best, closeTo(140.0, 1e-9));

        expect(StatsProgressService.epley1RM(100, 30)! > best, isFalse);
        expect(StatsProgressService.epley1RM(100, 12)! > best, isFalse);
        expect(StatsProgressService.epley1RM(101, 12)! > best, isTrue);
      });
    });
  }
}
