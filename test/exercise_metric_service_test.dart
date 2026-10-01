// Stats PR 4a, Phase 2 — the per-exercise native value.
//
// `computeExerciseMetrics` turns one exercise's whole history into the single
// number its section is read by, plus one point per training day, the day it
// was last trained and the number of sessions it appeared in. The axis rule for
// Resistance, the pace rule for Cardio, the longest-hold rule for Isometric and
// the round rule for Sports are the same rules the older per-day passes and
// `SessionSummaryBuilder` already own, so the surfaces cannot disagree.
//
// Scenarios S-904 … S-911 of
// `docs/plans/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.md`.
// S-910's screen half (Records & Trends' empty state) belongs to Phase 3.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/session_summary_builder.dart';
import 'package:omnitrain/state/workout/timer_manager.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture helpers ────────────────────────────────────────────────────────

/// A `set` effort on [segmentId], with no rows yet.
Future<void> addSetEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
  int orderIndex = 0,
}) => repo.createEffort(
  SegmentEffort(
    id: effortId,
    segmentId: segmentId,
    orderIndex: orderIndex,
    effortKind: 'set',
    exerciseId: exerciseId,
    createdAtMs: fixtureStart,
    updatedAtMs: fixtureStart,
  ),
);

/// One set entry: [reps] at [weightKg], with an added-weight row when
/// [addedWeightKg] is given.
Future<void> seedSetEntry(
  WorkoutRepository repo, {
  required String effortId,
  required int number,
  required int reps,
  required double weightKg,
  double? addedWeightKg,
}) async {
  await repo.createObservation(
    repsRow(effortId, number, reps, atMs: fixtureRowAt(number)),
  );
  await repo.createObservation(
    weightRow(effortId, number, weightKg, atMs: fixtureRowAt(number)),
  );
  if (addedWeightKg != null) {
    await repo.createObservation(
      extraWeightRow(
        effortId,
        number,
        addedWeightKg,
        atMs: fixtureRowAt(number),
      ),
    );
  }
}

/// A `timed` effort on [segmentId], with no entries yet.
Future<void> addTimedEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
  int orderIndex = 0,
}) => repo.createEffort(
  SegmentEffort(
    id: effortId,
    segmentId: segmentId,
    orderIndex: orderIndex,
    effortKind: 'timed',
    exerciseId: exerciseId,
    createdAtMs: fixtureStart,
    updatedAtMs: fixtureStart,
  ),
);

/// One finished timed entry of [effortId]: [durationSecs] long, with a distance
/// row of [metres] when it is given.
Future<void> seedTimedEntry(
  WorkoutRepository repo, {
  required String effortId,
  required int entryIndex,
  required int durationSecs,
  double? metres,
  String? source,
}) async {
  await repo.createTimedInstance(
    timedInstance(
      effortId,
      entryIndex,
      durationSecs: durationSecs,
      entryIndex: entryIndex,
    ),
  );
  if (metres != null) {
    await repo.createObservation(
      distanceRow(
        effortId,
        entryIndex,
        metres,
        atMs: fixtureRowAt(entryIndex),
        source: source,
      ),
    );
  }
}

/// A `drill` effort on [segmentId]: one finished hold per entry, with the added
/// weight each entry's row carries.
Future<void> seedHolds(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
  required List<int> holdSecs,
  required List<double> addedWeightKg,
}) async {
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segmentId,
      orderIndex: 0,
      effortKind: 'drill',
      exerciseId: exerciseId,
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
  for (var i = 0; i < holdSecs.length; i++) {
    await repo.createTimedInstance(
      timedInstance(effortId, i, durationSecs: holdSecs[i], entryIndex: i),
    );
    await repo.createObservation(
      extraWeightRow(effortId, i, addedWeightKg[i], atMs: fixtureRowAt(i)),
    );
  }
}

/// The summary of [exerciseId], or a failure naming what was found instead.
ExerciseMetricSummary summaryOf(
  List<ExerciseMetricSummary> metrics,
  String exerciseId,
) {
  final matches = metrics.where((m) => m.exerciseId == exerciseId).toList();
  expect(matches, hasLength(1), reason: '$exerciseId must appear exactly once');
  return matches.single;
}

/// A `SessionSummaryBuilder` over [sessionId]'s stored efforts, so the Sports
/// round count can be compared against the rule the Summary screen owns.
Future<SessionSummaryBuilder> builderFor(
  WorkoutRepository repo,
  String sessionId,
) async {
  final timerManager = TimerManager(
    repo,
    notify: () {},
    setError: (_) {},
    clearError: () {},
  );
  final segments = await repo.getSessionSegments(sessionId);
  final efforts = <String, List<SegmentEffort>>{};
  final observations = <String, List<EffortObservation>>{};
  for (final segment in segments) {
    final segmentEfforts = await repo.getSegmentEfforts(segment.id);
    efforts[segment.id] = segmentEfforts;
    for (final effort in segmentEfforts) {
      observations[effort.id] = await repo.getEffortObservations(effort.id);
      if (effort.effortKind == 'round') {
        timerManager.setRoundInstances(
          effort.id,
          await repo.getRoundInstances(effort.id),
        );
      }
    }
  }
  return SessionSummaryBuilder(
    timerManager: timerManager,
    observations: observations,
    efforts: efforts,
    segments: segments,
    exerciseCache: const {},
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the per-exercise native value', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-904 the Resistance value, and the axis that decides it', () async {
        // ex-row, weight-axis: two completed sessions.
        await seedExercise(repo, id: 'ex-row', name: 'Barbell Row');
        await seedSession(repo, sessionId: 's-904a', modality: 'resistance');
        await addSetEffort(
          repo,
          segmentId: 'seg-s-904a',
          effortId: 'eff-904-row-a',
          exerciseId: 'ex-row',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-904-row-a',
          number: 0,
          reps: 5,
          weightKg: 100,
        );
        await seedSession(repo, sessionId: 's-904b', modality: 'resistance');
        await addSetEffort(
          repo,
          segmentId: 'seg-s-904b',
          effortId: 'eff-904-row-b',
          exerciseId: 'ex-row',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-904-row-b',
          number: 0,
          reps: 3,
          weightKg: 120,
        );

        // ex-pull, reps-axis: an old weightless set decides the axis for the
        // whole exercise, then a recent weighted set with an added-weight row.
        await seedExercise(repo, id: 'ex-pull', name: 'Pull-up');
        await seedSession(repo, sessionId: 's-904c', daysAgo: 40);
        await addSetEffort(
          repo,
          segmentId: 'seg-s-904c',
          effortId: 'eff-904-pull-old',
          exerciseId: 'ex-pull',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-904-pull-old',
          number: 0,
          reps: 4,
          weightKg: 0,
        );
        await seedSession(repo, sessionId: 's-904d', daysAgo: 2);
        await addSetEffort(
          repo,
          segmentId: 'seg-s-904d',
          effortId: 'eff-904-pull-new',
          exerciseId: 'ex-pull',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-904-pull-new',
          number: 0,
          reps: 8,
          weightKg: 20,
          addedWeightKg: 5,
        );

        // ex-carry, bodyweight: two sets, the heavier-rep one wins.
        await seedExercise(repo, id: 'ex-carry', name: 'Farmer Carry');
        await seedSession(repo, sessionId: 's-904e', daysAgo: 3);
        await addSetEffort(
          repo,
          segmentId: 'seg-s-904e',
          effortId: 'eff-904-carry',
          exerciseId: 'ex-carry',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-904-carry',
          number: 0,
          reps: 30,
          weightKg: 0,
          addedWeightKg: 10,
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-904-carry',
          number: 1,
          reps: 12,
          weightKg: 0,
          addedWeightKg: 10,
        );

        final metrics = await StatsProgressService(
          repo,
        ).computeExerciseMetrics();

        final row = summaryOf(metrics, 'ex-row');
        expect(row.section, ExerciseSection.resistance);
        expect(row.best.metric, NativeMetric.estimatedOneRepMax);
        expect(row.best.value, closeTo(132.0, 0.001));

        final pull = summaryOf(metrics, 'ex-pull');
        expect(pull.section, ExerciseSection.resistance);
        expect(pull.best.metric, NativeMetric.reps);
        expect(pull.best.value, 8);
        expect(pull.best.addedWeightKg, 5);
        // One series, one metric: the axis is a property of the exercise, not
        // of the day the point came from.
        expect(
          [for (final point in pull.points) point.value.metric],
          [NativeMetric.reps, NativeMetric.reps],
        );
        expect([for (final point in pull.points) point.value.value], [4, 8]);

        final carry = summaryOf(metrics, 'ex-carry');
        expect(carry.best.metric, NativeMetric.reps);
        expect(carry.best.value, 30);
        expect(carry.best.addedWeightKg, 10);
      });

      test(
        'S-905 an exercise logged under two kinds sits in one section',
        () async {
          await seedExercise(repo, id: 'ex-mixed', name: 'Mixed');
          await seedSession(repo, sessionId: 's-905a', modality: 'resistance');
          await addSetEffort(
            repo,
            segmentId: 'seg-s-905a',
            effortId: 'eff-905-mixed-set',
            exerciseId: 'ex-mixed',
          );
          await seedSetEntry(
            repo,
            effortId: 'eff-905-mixed-set',
            number: 0,
            reps: 5,
            weightKg: 40,
          );
          await seedSession(repo, sessionId: 's-905b', daysAgo: 2);
          await seedHoldEffort(
            repo,
            segmentId: 'seg-s-905b',
            effortId: 'eff-905-mixed-timed-1',
            exerciseId: 'ex-mixed',
            entryCount: 1,
            effortKind: 'timed',
          );
          await seedSession(repo, sessionId: 's-905c', daysAgo: 3);
          await seedHoldEffort(
            repo,
            segmentId: 'seg-s-905c',
            effortId: 'eff-905-mixed-timed-2',
            exerciseId: 'ex-mixed',
            entryCount: 1,
            effortKind: 'timed',
          );

          await seedExercise(repo, id: 'ex-tied', name: 'Tied');
          await seedSession(repo, sessionId: 's-905d', daysAgo: 2);
          await seedHoldEffort(
            repo,
            segmentId: 'seg-s-905d',
            effortId: 'eff-905-tied-timed',
            exerciseId: 'ex-tied',
            entryCount: 1,
            effortKind: 'timed',
          );
          await seedSession(repo, sessionId: 's-905e', daysAgo: 3);
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-905e',
            effortId: 'eff-905-tied-round',
            exerciseId: 'ex-tied',
            rounds: [roundInstance('eff-905-tied-round', 0)],
          );

          await seedExercise(repo, id: 'ex-sets', name: 'Sets Only');
          await seedSession(repo, sessionId: 's-905f', daysAgo: 2);
          await addSetEffort(
            repo,
            segmentId: 'seg-s-905f',
            effortId: 'eff-905-sets',
            exerciseId: 'ex-sets',
          );
          await seedSetEntry(
            repo,
            effortId: 'eff-905-sets',
            number: 0,
            reps: 5,
            weightKg: 60,
          );

          final metrics = await StatsProgressService(
            repo,
          ).computeExerciseMetrics();

          expect(
            summaryOf(metrics, 'ex-mixed').section,
            ExerciseSection.cardio,
          );
          expect(summaryOf(metrics, 'ex-tied').section, ExerciseSection.cardio);
          expect(
            summaryOf(metrics, 'ex-sets').section,
            ExerciseSection.resistance,
          );
        },
      );

      test('S-906 the Cardio value, and the est. marker', () async {
        // ex-run: two finished entries, the faster pace wins.
        await seedExercise(repo, id: 'ex-run', name: 'Run');
        await seedSession(
          repo,
          sessionId: 's-906a',
          modality: 'cardio_endurance',
        );
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-906a',
          effortId: 'eff-906-run',
          exerciseId: 'ex-run',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-906-run',
          entryIndex: 0,
          durationSecs: 600,
          metres: 2000,
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-906-run',
          entryIndex: 1,
          durationSecs: 300,
          metres: 1500,
        );

        // ex-ride: durations, no distance row at all.
        await seedExercise(repo, id: 'ex-ride', name: 'Ride');
        await seedSession(
          repo,
          sessionId: 's-906b',
          modality: 'cardio_endurance',
        );
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-906b',
          effortId: 'eff-906-ride',
          exerciseId: 'ex-ride',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-906-ride',
          entryIndex: 0,
          durationSecs: 600,
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-906-ride',
          entryIndex: 1,
          durationSecs: 300,
        );

        // ex-hike: one entry, an estimated distance behind the pace.
        await seedExercise(repo, id: 'ex-hike', name: 'Hike');
        await seedSession(
          repo,
          sessionId: 's-906c',
          modality: 'cardio_endurance',
        );
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-906c',
          effortId: 'eff-906-hike',
          exerciseId: 'ex-hike',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-906-hike',
          entryIndex: 0,
          durationSecs: 1800,
          metres: 3000,
          source: EffortObservation.sourceEstimated,
        );

        final metrics = await StatsProgressService(
          repo,
        ).computeExerciseMetrics();

        final run = summaryOf(metrics, 'ex-run');
        expect(run.section, ExerciseSection.cardio);
        expect(run.best.metric, NativeMetric.pace);
        expect(run.best.value, closeTo(200, 0.001));
        expect(run.best.estimated, isFalse);

        final ride = summaryOf(metrics, 'ex-ride');
        expect(ride.best.metric, NativeMetric.duration);
        expect(ride.best.value, 900);

        final hike = summaryOf(metrics, 'ex-hike');
        expect(hike.best.metric, NativeMetric.pace);
        expect(hike.best.value, closeTo(600, 0.001));
        expect(hike.best.estimated, isTrue);
      });

      test('S-907 the Isometric value, and a Plank logged two ways', () async {
        await seedExercise(repo, id: 'ex-plank-hold', name: 'Plank');
        await seedSession(
          repo,
          sessionId: 's-907a',
          modality: 'isometric_stretching',
        );
        await seedHolds(
          repo,
          segmentId: 'seg-s-907a',
          effortId: 'eff-907-hold',
          exerciseId: 'ex-plank-hold',
          holdSecs: [30, 90, 45],
          addedWeightKg: [0, 10, 0],
        );

        await seedExercise(repo, id: 'ex-plank-timed', name: 'Plank Timed');
        await seedSession(
          repo,
          sessionId: 's-907b',
          modality: 'cardio_endurance',
        );
        await seedHoldEffort(
          repo,
          segmentId: 'seg-s-907b',
          effortId: 'eff-907-timed',
          exerciseId: 'ex-plank-timed',
          entryCount: 2,
          effortKind: 'timed',
        );

        final metrics = await StatsProgressService(
          repo,
        ).computeExerciseMetrics();

        final hold = summaryOf(metrics, 'ex-plank-hold');
        expect(hold.section, ExerciseSection.isometric);
        expect(hold.best.metric, NativeMetric.hold);
        expect(hold.best.value, 90);
        expect(hold.best.addedWeightKg, 10);
        expect(hold.best.secondaryMetric, NativeMetric.duration);
        expect(hold.best.secondaryValue, 165);

        final timed = summaryOf(metrics, 'ex-plank-timed');
        expect(timed.section, ExerciseSection.cardio);
        expect(timed.best.metric, NativeMetric.duration);
        expect(timed.best.value, 120);
      });

      test('S-908 rounds completed, and the rule that decides it', () async {
        await seedExercise(repo, id: 'ex-bjj', name: 'BJJ');
        await seedSession(repo, sessionId: 's-908', modality: 'sports');
        await seedRoundEffort(
          repo,
          segmentId: 'seg-s-908',
          effortId: 'eff-908',
          exerciseId: 'ex-bjj',
          rounds: [
            roundInstance(
              'eff-908',
              0,
              durationSecs: 180,
              startedAtMs: fixtureStart,
            ),
            roundInstance(
              'eff-908',
              1,
              durationSecs: 120,
              completed: false,
              startedAtMs: fixtureStart + 60000,
            ),
            // A paused-then-abandoned round: an end stamp, but not finished.
            roundInstance(
              'eff-908',
              2,
              durationSecs: 90,
              state: RoundState.active,
              startedAtMs: fixtureStart + 120000,
              finishedAtMs: fixtureStart + 210000,
            ),
            roundInstance(
              'eff-908',
              3,
              durationSecs: 90,
              state: RoundState.notStarted,
              startedAtMs: 0,
            ),
            // Finished, but with no end stamp.
            roundInstance(
              'eff-908',
              4,
              durationSecs: 60,
              startedAtMs: fixtureStart + 240000,
              finishedAtMs: null,
            ),
          ],
        );

        final metrics = await StatsProgressService(
          repo,
        ).computeExerciseMetrics();

        final bjj = summaryOf(metrics, 'ex-bjj');
        expect(bjj.section, ExerciseSection.sports);
        expect(bjj.best.metric, NativeMetric.rounds);
        expect(bjj.best.value, 2);
        expect(bjj.best.secondaryMetric, NativeMetric.roundMinutes);
        expect(bjj.best.secondaryValue, 5);

        final session = await repo.getSession('s-908');
        final summary = (await builderFor(
          repo,
          's-908',
        )).buildSessionSummary(session!);
        expect(summary.totalRounds, bjj.best.value);
      });

      test('S-909 an exercise with exactly one session', () async {
        await seedExercise(repo, id: 'ex-squat', name: 'Back Squat');
        await seedSession(repo, sessionId: 's-909', modality: 'resistance');
        await addSetEffort(
          repo,
          segmentId: 'seg-s-909',
          effortId: 'eff-909',
          exerciseId: 'ex-squat',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-909',
          number: 0,
          reps: 5,
          weightKg: 100,
        );

        final metrics = await StatsProgressService(
          repo,
        ).computeExerciseMetrics();

        final squat = summaryOf(metrics, 'ex-squat');
        expect(squat.best.metric, NativeMetric.estimatedOneRepMax);
        expect(squat.best.value, closeTo(100 * (1 + 5 / 30.0), 0.001));
        expect(squat.points, hasLength(1));
        expect(squat.sessionCount, 1);

        final session = await repo.getSession('s-909');
        expect(squat.lastTrainedMs, session!.startedAtMs);
      });

      test('S-910 an empty history', () async {
        final metrics = await StatsProgressService(
          repo,
        ).computeExerciseMetrics();

        expect(metrics, isEmpty);
      });

      test(
        'S-911 an exercise last trained a year ago is still listed',
        () async {
          await seedExercise(repo, id: 'ex-deadlift', name: 'Deadlift');
          await seedSession(repo, sessionId: 's-911a', daysAgo: 370);
          await addSetEffort(
            repo,
            segmentId: 'seg-s-911a',
            effortId: 'eff-911-deadlift',
            exerciseId: 'ex-deadlift',
          );
          await seedSetEntry(
            repo,
            effortId: 'eff-911-deadlift',
            number: 0,
            reps: 5,
            weightKg: 140,
          );

          await seedExercise(repo, id: 'ex-bench', name: 'Bench Press');
          await seedSession(repo, sessionId: 's-911b', daysAgo: 1);
          await addSetEffort(
            repo,
            segmentId: 'seg-s-911b',
            effortId: 'eff-911-bench',
            exerciseId: 'ex-bench',
          );
          await seedSetEntry(
            repo,
            effortId: 'eff-911-bench',
            number: 0,
            reps: 5,
            weightKg: 80,
          );

          final metrics = await StatsProgressService(
            repo,
          ).computeExerciseMetrics();

          final old = await repo.getSession('s-911a');
          final deadlift = summaryOf(metrics, 'ex-deadlift');
          expect(deadlift.lastTrainedMs, old!.startedAtMs);
          expect(deadlift.sessionCount, 1);

          final bench = summaryOf(metrics, 'ex-bench');
          final recent = await repo.getSession('s-911b');
          expect(bench.lastTrainedMs, recent!.startedAtMs);
          expect(metrics, hasLength(2));
        },
      );
    });
  }
}
