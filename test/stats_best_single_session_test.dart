// Plan 211 — a Best is one session (service half).
//
// With `bestSingleSession: true`, `computeExerciseMetrics` re-reads an
// exercise whose all-history value is a running total — a cardio duration
// with no distance anywhere, or a round count — as its best one session,
// session by `session.id`, not a calendar day. The default call and the
// Instruments rows keep the totals.
//
// Scenarios S-21201, S-21202, S-21203, S-21204, S-21207, S-21208 and S-21209 of
// `docs/plans/2026-11-16-211-stats-best-is-one-session-plan/2026-11-16-211-stats-best-is-one-session-plan.md`.
// S-21205 and S-21206 (the screens) are the next run's.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

// ─── Fixture helpers ────────────────────────────────────────────────────────

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

/// The summary of [exerciseId], or a failure naming what was found instead.
ExerciseMetricSummary summaryOf(
  List<ExerciseMetricSummary> metrics,
  String exerciseId,
) {
  final matches = metrics.where((m) => m.exerciseId == exerciseId).toList();
  expect(matches, hasLength(1), reason: '$exerciseId must appear exactly once');
  return matches.single;
}

/// The section named [section], or a failure naming what was returned instead.
InstrumentSectionData sectionOf(
  List<InstrumentSectionData> sections,
  ExerciseSection section,
) {
  final matches = sections.where((s) => s.section == section).toList();
  expect(matches, hasLength(1), reason: '$section must appear exactly once');
  return matches.single;
}

/// The row of [exerciseId], or a failure naming what the section held instead.
InstrumentRow rowOf(InstrumentSectionData section, String exerciseId) {
  final matches = section.rows
      .where((r) => r.summary.exerciseId == exerciseId)
      .toList();
  expect(matches, hasLength(1), reason: '$exerciseId must appear exactly once');
  return matches.single;
}

/// Local midnight [daysAgo] days back — the day key a fixture places a session
/// on, and the bound a window is built from.
DateTime dayBack(int daysAgo) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - daysAgo);
}

/// A window covering the last [days] calendar days, ending with today.
StatsWindow windowOfDays(int days) => StatsWindow(
  fromMs: dayBack(days - 1),
  toMs: DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23,
    59,
    59,
    999,
  ),
  label: 'Last $days days',
  isPeriodScoped: false,
  recentDays: days,
);

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Best single session (${harness.name})', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'S-21201 a no-distance cardio Best is its longest session',
        () async {
          await seedExercise(repo, id: 'ex-ell', name: 'Elliptical');
          await seedSession(
            repo,
            sessionId: 's-ell-a',
            modality: 'cardio_endurance',
            daysAgo: 3,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-ell-a',
            effortId: 'eff-ell-a',
            exerciseId: 'ex-ell',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-ell-a',
            entryIndex: 0,
            durationSecs: 1200,
          );
          await seedSession(
            repo,
            sessionId: 's-ell-b',
            modality: 'cardio_endurance',
            daysAgo: 2,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-ell-b',
            effortId: 'eff-ell-b',
            exerciseId: 'ex-ell',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-ell-b',
            entryIndex: 0,
            durationSecs: 2100,
          );
          await seedSession(
            repo,
            sessionId: 's-ell-c',
            modality: 'cardio_endurance',
            daysAgo: 1,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-ell-c',
            effortId: 'eff-ell-c',
            exerciseId: 'ex-ell',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-ell-c',
            entryIndex: 0,
            durationSecs: 1500,
          );

          final metrics = await StatsProgressService(
            repo,
          ).computeExerciseMetrics(bestSingleSession: true);

          final ell = summaryOf(metrics, 'ex-ell');
          expect(ell.best.metric, NativeMetric.duration);
          expect(ell.best.value, 2100);
        },
      );

      test(
        'S-21202 a rounds Best is the session with the most rounds',
        () async {
          await seedExercise(repo, id: 'ex-bjj', name: 'BJJ');
          await seedSession(
            repo,
            sessionId: 's-bjj-a',
            modality: 'sports',
            daysAgo: 3,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-a',
            effortId: 'eff-bjj-a',
            exerciseId: 'ex-bjj',
            rounds: [
              roundInstance(
                'eff-bjj-a',
                0,
                durationSecs: 180,
                startedAtMs: fixtureStart,
              ),
              roundInstance(
                'eff-bjj-a',
                1,
                durationSecs: 180,
                startedAtMs: fixtureStart + 1000,
              ),
              roundInstance(
                'eff-bjj-a',
                2,
                durationSecs: 180,
                startedAtMs: fixtureStart + 2000,
              ),
            ],
          );
          await seedSession(
            repo,
            sessionId: 's-bjj-b',
            modality: 'sports',
            daysAgo: 2,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-b',
            effortId: 'eff-bjj-b',
            exerciseId: 'ex-bjj',
            rounds: [
              for (var i = 0; i < 5; i++)
                roundInstance(
                  'eff-bjj-b',
                  i,
                  durationSecs: 120,
                  startedAtMs: fixtureStart + i * 1000,
                ),
            ],
          );
          await seedSession(
            repo,
            sessionId: 's-bjj-c',
            modality: 'sports',
            daysAgo: 1,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-c',
            effortId: 'eff-bjj-c',
            exerciseId: 'ex-bjj',
            rounds: [
              roundInstance(
                'eff-bjj-c',
                0,
                durationSecs: 90,
                startedAtMs: fixtureStart,
              ),
              roundInstance(
                'eff-bjj-c',
                1,
                durationSecs: 90,
                startedAtMs: fixtureStart + 1000,
              ),
            ],
          );

          final metrics = await StatsProgressService(
            repo,
          ).computeExerciseMetrics(bestSingleSession: true);

          final bjj = summaryOf(metrics, 'ex-bjj');
          expect(bjj.best.metric, NativeMetric.rounds);
          expect(bjj.best.value, 5);
          expect(bjj.best.secondaryMetric, NativeMetric.roundMinutes);
          // The winning session's own round minutes (5 × 120 s), not the total.
          expect(bjj.best.secondaryValue, closeTo(10, 0.01));
        },
      );

      test('S-21203 a distance cardio keeps its pace, flag or not', () async {
        await seedExercise(repo, id: 'ex-run', name: 'Run');
        await seedSession(
          repo,
          sessionId: 's-run-a',
          modality: 'cardio_endurance',
          daysAgo: 2,
        );
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-run-a',
          effortId: 'eff-run-a',
          exerciseId: 'ex-run',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-run-a',
          entryIndex: 0,
          durationSecs: 1500,
          metres: 5000,
        );
        await seedSession(
          repo,
          sessionId: 's-run-b',
          modality: 'cardio_endurance',
          daysAgo: 1,
        );
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-run-b',
          effortId: 'eff-run-b',
          exerciseId: 'ex-run',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-run-b',
          entryIndex: 0,
          durationSecs: 3600,
        );
        // A second run with a distance, slower (360 s/km): a re-read that took
        // the largest figure per session would pick this one over 300.
        await seedSession(
          repo,
          sessionId: 's-run-c',
          modality: 'cardio_endurance',
          daysAgo: 3,
        );
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-run-c',
          effortId: 'eff-run-c',
          exerciseId: 'ex-run',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-run-c',
          entryIndex: 0,
          durationSecs: 1800,
          metres: 5000,
        );

        final service = StatsProgressService(repo);
        final flagged = await service.computeExerciseMetrics(
          bestSingleSession: true,
        );
        final plain = await service.computeExerciseMetrics();

        final run = summaryOf(flagged, 'ex-run');
        expect(run.best.metric, NativeMetric.pace);
        expect(run.best.value, closeTo(300, 0.01));
        // The all-history read is a pace, not a running total, so the flag
        // returns it as it was.
        expect(summaryOf(plain, 'ex-run').best.value, run.best.value);
      });

      test(
        'S-21204 the default call and the Instruments rows keep totals',
        () async {
          await seedExercise(repo, id: 'ex-ell', name: 'Elliptical');
          await seedSession(
            repo,
            sessionId: 's-ell-a',
            modality: 'cardio_endurance',
            daysAgo: 3,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-ell-a',
            effortId: 'eff-ell-a',
            exerciseId: 'ex-ell',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-ell-a',
            entryIndex: 0,
            durationSecs: 1200,
          );
          await seedSession(
            repo,
            sessionId: 's-ell-b',
            modality: 'cardio_endurance',
            daysAgo: 2,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-ell-b',
            effortId: 'eff-ell-b',
            exerciseId: 'ex-ell',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-ell-b',
            entryIndex: 0,
            durationSecs: 2100,
          );
          await seedSession(
            repo,
            sessionId: 's-ell-c',
            modality: 'cardio_endurance',
            daysAgo: 1,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-ell-c',
            effortId: 'eff-ell-c',
            exerciseId: 'ex-ell',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-ell-c',
            entryIndex: 0,
            durationSecs: 1500,
          );

          await seedExercise(repo, id: 'ex-bjj', name: 'BJJ');
          await seedSession(
            repo,
            sessionId: 's-bjj-a',
            modality: 'sports',
            daysAgo: 3,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-a',
            effortId: 'eff-bjj-a',
            exerciseId: 'ex-bjj',
            rounds: [
              roundInstance(
                'eff-bjj-a',
                0,
                durationSecs: 180,
                startedAtMs: fixtureStart,
              ),
              roundInstance(
                'eff-bjj-a',
                1,
                durationSecs: 180,
                startedAtMs: fixtureStart + 1000,
              ),
              roundInstance(
                'eff-bjj-a',
                2,
                durationSecs: 180,
                startedAtMs: fixtureStart + 2000,
              ),
            ],
          );
          await seedSession(
            repo,
            sessionId: 's-bjj-b',
            modality: 'sports',
            daysAgo: 2,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-b',
            effortId: 'eff-bjj-b',
            exerciseId: 'ex-bjj',
            rounds: [
              for (var i = 0; i < 5; i++)
                roundInstance(
                  'eff-bjj-b',
                  i,
                  durationSecs: 120,
                  startedAtMs: fixtureStart + i * 1000,
                ),
            ],
          );
          await seedSession(
            repo,
            sessionId: 's-bjj-c',
            modality: 'sports',
            daysAgo: 1,
          );
          await seedRoundEffort(
            repo,
            segmentId: 'seg-s-bjj-c',
            effortId: 'eff-bjj-c',
            exerciseId: 'ex-bjj',
            rounds: [
              roundInstance(
                'eff-bjj-c',
                0,
                durationSecs: 90,
                startedAtMs: fixtureStart,
              ),
              roundInstance(
                'eff-bjj-c',
                1,
                durationSecs: 90,
                startedAtMs: fixtureStart + 1000,
              ),
            ],
          );

          final service = StatsProgressService(repo);
          final plain = await service.computeExerciseMetrics();

          final ell = summaryOf(plain, 'ex-ell');
          expect(ell.best.metric, NativeMetric.duration);
          expect(ell.best.value, 4800);

          final bjj = summaryOf(plain, 'ex-bjj');
          expect(bjj.best.metric, NativeMetric.rounds);
          expect(bjj.best.value, 10);
          expect(bjj.best.secondaryValue, closeTo(22, 0.01));

          final sections = await service.computeInstrumentSections(
            window: windowOfDays(10),
          );
          final ellRow = rowOf(
            sectionOf(sections, ExerciseSection.cardio),
            'ex-ell',
          );
          expect(ellRow.summary.best.value, 4800);
          final bjjRow = rowOf(
            sectionOf(sections, ExerciseSection.sports),
            'ex-bjj',
          );
          expect(bjjRow.summary.best.value, 10);
        },
      );

      test(
        'S-21207 two sessions on one day are not summed into the Best',
        () async {
          await seedExercise(repo, id: 'ex-bike', name: 'Bike');
          await seedSession(
            repo,
            sessionId: 's-bike-a',
            modality: 'cardio_endurance',
            daysAgo: 1,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-bike-a',
            effortId: 'eff-bike-a',
            exerciseId: 'ex-bike',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-bike-a',
            entryIndex: 0,
            durationSecs: 1200,
          );
          await seedSession(
            repo,
            sessionId: 's-bike-b',
            modality: 'cardio_endurance',
            daysAgo: 1,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-bike-b',
            effortId: 'eff-bike-b',
            exerciseId: 'ex-bike',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-bike-b',
            entryIndex: 0,
            durationSecs: 1200,
          );
          await seedSession(
            repo,
            sessionId: 's-bike-c',
            modality: 'cardio_endurance',
            daysAgo: 3,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-bike-c',
            effortId: 'eff-bike-c',
            exerciseId: 'ex-bike',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-bike-c',
            entryIndex: 0,
            durationSecs: 1500,
          );

          final metrics = await StatsProgressService(
            repo,
          ).computeExerciseMetrics(bestSingleSession: true);

          final bike = summaryOf(metrics, 'ex-bike');
          // The larger single session, not the 2400 s day total.
          expect(bike.best.value, 1500);

          // The chart's day total and the Best differ: two days, and the
          // two-session day reads its own 2400 s.
          expect(bike.points, hasLength(2));
          expect(bike.points.last.value.value, 2400);
        },
      );

      test(
        'S-21208 an unfinished entry alone reads the zero fallback',
        () async {
          await seedExercise(repo, id: 'ex-walk', name: 'Walk');
          await seedSession(
            repo,
            sessionId: 's-walk-a',
            modality: 'cardio_endurance',
            daysAgo: 1,
          );
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-walk-a',
            effortId: 'eff-walk-a',
            exerciseId: 'ex-walk',
          );
          await repo.createTimedInstance(
            timedInstance(
              'eff-walk-a',
              0,
              durationSecs: 600,
              entryIndex: 0,
              state: TimedState.active,
            ),
          );

          final metrics = await StatsProgressService(
            repo,
          ).computeExerciseMetrics(bestSingleSession: true);

          final walk = summaryOf(metrics, 'ex-walk');
          expect(walk.best.metric, NativeMetric.duration);
          expect(walk.best.value, 0);
          expect(walk.exerciseId, 'ex-walk');
        },
      );

      test(
        'S-21209 a tie between two sessions keeps the earlier one',
        () async {
          await seedExercise(repo, id: 'ex-tie', name: 'Sparring');
          for (final (suffix, daysAgo, roundSecs) in [
            ('a', 2, 100),
            ('b', 1, 300),
          ]) {
            await seedSession(
              repo,
              sessionId: 's-tie-$suffix',
              modality: 'sports',
              daysAgo: daysAgo,
            );
            await seedRoundEffort(
              repo,
              segmentId: 'seg-s-tie-$suffix',
              effortId: 'eff-tie-$suffix',
              exerciseId: 'ex-tie',
              rounds: [
                for (var i = 0; i < 2; i++)
                  roundInstance(
                    'eff-tie-$suffix',
                    i,
                    durationSecs: roundSecs,
                    startedAtMs: fixtureStart + i * 1000,
                  ),
              ],
            );
          }

          final metrics = await StatsProgressService(
            repo,
          ).computeExerciseMetrics(bestSingleSession: true);

          final tie = summaryOf(metrics, 'ex-tie');
          expect(tie.best.value, 2);
          // Two rounds of 100 s (the earlier session), not two of 300 s.
          expect(tie.best.secondaryValue, closeTo(200 / 60, 0.01));
        },
      );
    });
  }
}
