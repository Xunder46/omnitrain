// Plan 210 — Recent PRs covers every lift with a logged set (one run).
//
// The record scan behind `recentPRs` now walks every exercise with a `set`
// effort in any completed session; the window and `kTopLiftCount` only decide
// which lifts get a trend entry in `topLifts`. Scenarios S-21101..S-21107.
//
// Plan: `docs/plans/2026-11-16-210-stats-recent-prs-every-lift-plan/2026-11-16-210-stats-recent-prs-every-lift-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ── Seed helpers (copied from test/stats_progress_test.dart, generalised
//    from MockWorkoutRepository to WorkoutRepository) ─────────────────────────

/// Local-midnight `[n]` days before today. Calendar arithmetic, not
/// `subtract(Duration(days: n))`: a Duration is an exact hour span, so under
/// a DST-observing timezone it can land on 23:00 of the previous day.
DateTime daysAgo(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - n);
}

/// Seed a completed session starting at [day] midnight.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  required DateTime day,
}) async {
  final startMs = day.millisecondsSinceEpoch;
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startMs,
      endedAtMs: startMs + 3600000,
      createdAtMs: startMs,
      updatedAtMs: startMs,
    ),
  );
}

/// Seed a set effort with one segment auto-created inside [sessionId].
/// [sets] is a list of (weight_kg, reps) pairs.
Future<String> _addSetEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required List<(double, int)> sets,
}) async {
  final segId = 'seg-$sessionId-$exerciseId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  final effId = 'eff-$sessionId-$exerciseId';
  await repo.createEffort(
    SegmentEffort(
      id: effId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'set',
      exerciseId: exerciseId,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  for (var i = 0; i < sets.length; i++) {
    final (weight, reps) = sets[i];
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effId-$i-weight',
        effortId: effId,
        metricId: MetricIds.weight,
        unitId: MetricIds.unitKg,
        valueReal: weight,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effId-$i-reps',
        effortId: effId,
        metricId: MetricIds.reps,
        unitId: MetricIds.unitReps,
        valueInt: reps,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
  }

  return effId;
}

/// Seed a `timed` effort carrying the same weight/reps rows a set effort
/// would, so the only thing keeping it out of the lift scan is its
/// `effortKind` (plan 210, S-21106).
Future<String> _addTimedEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required String exerciseId,
  required List<(double, int)> sets,
}) async {
  final segId = 'seg-$sessionId-$exerciseId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: 0,
      segmentType: 'main',
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  final effId = 'eff-$sessionId-$exerciseId';
  await repo.createEffort(
    SegmentEffort(
      id: effId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: 'timed',
      exerciseId: exerciseId,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  await repo.createTimedInstance(
    TimedInstance(
      id: 'ti-$effId',
      effortId: effId,
      entryIndex: 0,
      actualDurationSecs: 1800,
      state: TimedState.finished,
      createdAtMs: 1000,
      updatedAtMs: 1000,
    ),
  );

  for (var i = 0; i < sets.length; i++) {
    final (weight, reps) = sets[i];
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effId-$i-weight',
        effortId: effId,
        metricId: MetricIds.weight,
        unitId: MetricIds.unitKg,
        valueReal: weight,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
    await repo.createObservation(
      EffortObservation(
        id: 'obs-$effId-$i-reps',
        effortId: effId,
        metricId: MetricIds.reps,
        unitId: MetricIds.unitReps,
        valueInt: reps,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      ),
    );
  }

  return effId;
}

/// One lift, one session, one set: the exercise row, a completed session on
/// [day] days before today, and a single (weight, reps) set.
Future<void> _seedLift(
  WorkoutRepository repo, {
  required String exerciseId,
  required String name,
  required String sessionId,
  required int day,
  required double weight,
  required int reps,
}) async {
  await repo.createExercise(
    Exercise(id: exerciseId, name: name, createdAtMs: 1000, updatedAtMs: 1000),
  );
  await _seedSession(repo, id: sessionId, day: daysAgo(day));
  await _addSetEffort(
    repo,
    sessionId: sessionId,
    exerciseId: exerciseId,
    sets: [(weight, reps)],
  );
}

void main() {
  for (final harnessFactory in harnessFactories) {
    final harness = harnessFactory();

    group('${harness.name} — Recent PRs covers every lift (plan 210)', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(harness.close);

      test('S-21101 six one-set lifts yield the five newest records across '
          'all of them', () async {
        await _seedLift(
          repo,
          exerciseId: 'ex-l1',
          name: 'L1',
          sessionId: 's21101-l1',
          day: 6,
          weight: 60,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l2',
          name: 'L2',
          sessionId: 's21101-l2',
          day: 5,
          weight: 70,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l3',
          name: 'L3',
          sessionId: 's21101-l3',
          day: 4,
          weight: 80,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l4',
          name: 'L4',
          sessionId: 's21101-l4',
          day: 3,
          weight: 90,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l5',
          name: 'L5',
          sessionId: 's21101-l5',
          day: 2,
          weight: 100,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l6',
          name: 'L6',
          sessionId: 's21101-l6',
          day: 1,
          weight: 110,
          reps: 5,
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.recentPRs, hasLength(5));
        expect(data.recentPRs[0].exerciseName, 'L6');
        expect(data.recentPRs[1].exerciseName, 'L5');
        expect(data.recentPRs[2].exerciseName, 'L4');
        expect(data.recentPRs[3].exerciseName, 'L3');
        expect(data.recentPRs[4].exerciseName, 'L2');
        expect(data.recentPRs[0].e1Rm, closeTo(128.333, 0.01));
        expect(data.recentPRs[1].e1Rm, closeTo(116.667, 0.01));
        expect(data.recentPRs[2].e1Rm, closeTo(105.0, 0.01));
        expect(data.recentPRs[3].e1Rm, closeTo(93.333, 0.01));
        expect(data.recentPRs[4].e1Rm, closeTo(81.667, 0.01));
        expect(data.recentPRs[0].date, daysAgo(1));
        expect(data.recentPRs[1].date, daysAgo(2));
        expect(data.recentPRs[2].date, daysAgo(3));
        expect(data.recentPRs[3].date, daysAgo(4));
        expect(data.recentPRs[4].date, daysAgo(5));
        expect(data.recentPRs.where((pr) => pr.exerciseName == 'L1'), isEmpty);
      });

      test('S-21102 a record 45 days back is scanned over full history and '
          'listed', () async {
        await _seedLift(
          repo,
          exerciseId: 'ex-old',
          name: 'Old Lift',
          sessionId: 's21102-old',
          day: 45,
          weight: 100,
          reps: 3,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-row',
          name: 'Row',
          sessionId: 's21102-row',
          day: 0,
          weight: 50,
          reps: 5,
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.recentPRs, hasLength(2));
        expect(data.recentPRs[0].exerciseName, 'Row');
        expect(data.recentPRs[0].e1Rm, closeTo(58.333, 0.01));
        expect(data.recentPRs[0].date, daysAgo(0));
        expect(data.recentPRs[1].exerciseName, 'Old Lift');
        expect(data.recentPRs[1].e1Rm, closeTo(110.0, 0.01));
        expect(data.recentPRs[1].date, daysAgo(45));
      });

      test('S-21103 topLifts stays at the cap of three', () async {
        await _seedLift(
          repo,
          exerciseId: 'ex-l1',
          name: 'L1',
          sessionId: 's21103-l1',
          day: 6,
          weight: 60,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l2',
          name: 'L2',
          sessionId: 's21103-l2',
          day: 5,
          weight: 70,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l3',
          name: 'L3',
          sessionId: 's21103-l3',
          day: 4,
          weight: 80,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l4',
          name: 'L4',
          sessionId: 's21103-l4',
          day: 3,
          weight: 90,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l5',
          name: 'L5',
          sessionId: 's21103-l5',
          day: 2,
          weight: 100,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l6',
          name: 'L6',
          sessionId: 's21103-l6',
          day: 1,
          weight: 110,
          reps: 5,
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.topLifts, hasLength(3));
      });

      test('S-21104 a bodyweight lift outside the window carries its reps '
          'record', () async {
        await repo.createExercise(
          Exercise(
            id: 'ex-pushup',
            name: 'Push-up',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
        await _seedSession(repo, id: 's21104-pushup', day: daysAgo(50));
        await _addSetEffort(
          repo,
          sessionId: 's21104-pushup',
          exerciseId: 'ex-pushup',
          sets: [(0.0, 20), (0.0, 15), (0.0, 12)],
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-row',
          name: 'Row',
          sessionId: 's21104-row',
          day: 0,
          weight: 50,
          reps: 5,
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.recentPRs, hasLength(2));
        expect(data.recentPRs[0].exerciseName, 'Row');
        final pushup = data.recentPRs.firstWhere(
          (pr) => pr.exerciseName == 'Push-up',
        );
        expect(pushup.reps, 20);
        expect(pushup.e1Rm, isNull);
        expect(pushup.date, daysAgo(50));
      });

      test('S-21105 one lift over three improving days keeps exactly one '
          'record, its best', () async {
        await _seedLift(
          repo,
          exerciseId: 'ex-press',
          name: 'Press',
          sessionId: 's21105-d9',
          day: 9,
          weight: 60,
          reps: 5,
        );
        await _seedSession(repo, id: 's21105-d5', day: daysAgo(5));
        await _addSetEffort(
          repo,
          sessionId: 's21105-d5',
          exerciseId: 'ex-press',
          sets: [(70, 5)],
        );
        await _seedSession(repo, id: 's21105-d2', day: daysAgo(2));
        await _addSetEffort(
          repo,
          sessionId: 's21105-d2',
          exerciseId: 'ex-press',
          sets: [(80, 5)],
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.recentPRs, hasLength(1));
        expect(data.recentPRs.single.exerciseName, 'Press');
        expect(data.recentPRs.single.e1Rm, closeTo(93.333, 0.01));
        expect(data.recentPRs.single.date, daysAgo(2));
      });

      test(
        'S-21106 a timed-only history yields no records and no lifts',
        () async {
          await repo.createExercise(
            Exercise(
              id: 'ex-run',
              name: 'Run',
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          await _seedSession(repo, id: 's21106-run', day: daysAgo(0));
          await _addTimedEffort(
            repo,
            sessionId: 's21106-run',
            exerciseId: 'ex-run',
            sets: [(50, 5)],
          );

          final data = await StatsProgressService(repo).computeProgressData();

          expect(data.recentPRs, isEmpty);
          expect(data.topLifts, isEmpty);
        },
      );

      test('S-21107 a set effort naming an exercise id with no catalog row '
          'reads as the id', () async {
        await _seedLift(
          repo,
          exerciseId: 'ex-l1',
          name: 'L1',
          sessionId: 's21107-l1',
          day: 6,
          weight: 60,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l2',
          name: 'L2',
          sessionId: 's21107-l2',
          day: 5,
          weight: 70,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l3',
          name: 'L3',
          sessionId: 's21107-l3',
          day: 4,
          weight: 80,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l4',
          name: 'L4',
          sessionId: 's21107-l4',
          day: 3,
          weight: 90,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l5',
          name: 'L5',
          sessionId: 's21107-l5',
          day: 2,
          weight: 100,
          reps: 5,
        );
        await _seedLift(
          repo,
          exerciseId: 'ex-l6',
          name: 'L6',
          sessionId: 's21107-l6',
          day: 1,
          weight: 110,
          reps: 5,
        );
        await _seedSession(repo, id: 's21107-missing', day: daysAgo(0));
        await _addSetEffort(
          repo,
          sessionId: 's21107-missing',
          exerciseId: 'ex-missing',
          sets: [(40, 5)],
        );

        final data = await StatsProgressService(repo).computeProgressData();

        expect(data.recentPRs, hasLength(5));
        expect(data.recentPRs.first.exerciseName, 'ex-missing');
        expect(data.recentPRs.first.e1Rm, closeTo(46.667, 0.01));
      });

      test(
        'S-21108 a lift outside the window keeps its catalog name',
        () async {
          // Fourteen training days of Row fill the recent-days window, so the
          // 45-day-old lift is outside it and its name is not cached by the
          // window pass: the scan has to look it up.
          await repo.createExercise(
            Exercise(
              id: 'ex-row',
              name: 'Row',
              createdAtMs: 1000,
              updatedAtMs: 1000,
            ),
          );
          for (var day = 0; day < 14; day++) {
            await _seedSession(repo, id: 's21108-row-$day', day: daysAgo(day));
            await _addSetEffort(
              repo,
              sessionId: 's21108-row-$day',
              exerciseId: 'ex-row',
              sets: [(50, 5)],
            );
          }
          await _seedLift(
            repo,
            exerciseId: 'ex-old',
            name: 'Old Lift',
            sessionId: 's21108-old',
            day: 45,
            weight: 100,
            reps: 3,
          );

          final data = await StatsProgressService(repo).computeProgressData();

          expect(data.recentPRs, hasLength(2));
          expect(data.recentPRs[0].exerciseName, 'Row');
          expect(data.recentPRs[1].exerciseName, 'Old Lift');
          expect(data.recentPRs[1].e1Rm, closeTo(110.0, 0.01));
        },
      );
    });
  }
}
