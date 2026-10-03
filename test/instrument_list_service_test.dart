// Stats PR 4b, Phase 2 — the Instruments computation.
//
// `computeInstrumentSections` turns the window's per-exercise native values
// into the ordered sections and rows the Instruments list renders: which
// sections appear and in what order (D-504), which rows sit in each and in
// what order (D-505, D-506), what each row's change indicator compares against
// (D-508, D-509), and the cadence and heart-rate figures a row carries
// (D-511, D-512).
//
// Scenarios S-1005 … S-1010, S-1013 and S-1018 of
// `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/2026-10-01-04b-stats-pr4b-instruments-data-plan.md`.
// S-1007's formatting half is asserted through 4a's own formatter, so the row
// and the Exercise Progress screen cannot read one number two ways.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/instrument_list.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/stats/widgets/native_value_format.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

// ─── Fixture helpers ────────────────────────────────────────────────────────

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

/// A `set` effort on [segmentId] with no rows yet.
Future<void> addSetEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
}) => repo.createEffort(
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

/// One set entry: [reps] at [weightKg].
Future<void> seedSetEntry(
  WorkoutRepository repo, {
  required String effortId,
  required int number,
  required int reps,
  required double weightKg,
}) async {
  await repo.createObservation(
    repsRow(effortId, number, reps, atMs: fixtureRowAt(number)),
  );
  await repo.createObservation(
    weightRow(effortId, number, weightKg, atMs: fixtureRowAt(number)),
  );
}

/// A `timed` effort on [segmentId] with no entries yet.
Future<void> addTimedEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
}) => repo.createEffort(
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

/// A `drill` effort on [segmentId] with no entries yet.
Future<void> addDrillEffort(
  WorkoutRepository repo, {
  required String segmentId,
  required String effortId,
  required String exerciseId,
}) => repo.createEffort(
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

/// One finished timed entry of [effortId], [durationSecs] long, with a distance
/// row of [metres] when it is given.
Future<void> seedTimedEntry(
  WorkoutRepository repo, {
  required String effortId,
  required int entryIndex,
  required int durationSecs,
  double? metres,
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
      distanceRow(effortId, entryIndex, metres, atMs: fixtureRowAt(entryIndex)),
    );
  }
}

/// A `timed_instance` sensor summary on [sessionId] for the instance
/// `ti-<effortId>-<entryIndex>`.
Future<void> seedInstanceSummary(
  WorkoutRepository repo, {
  required String sessionId,
  required String effortId,
  required int entryIndex,
  double? avgHeartRateBpm,
  int? steps,
}) => seedSensorSummary(
  repo,
  sensorSummary(
    sessionId: sessionId,
    scope: SensorSummary.scopeTimedInstance,
    targetId: 'ti-$effortId-$entryIndex',
    windowStartMs: fixtureStart,
    windowEndMs: fixtureStart + 1000,
    avgHeartRateBpm: avgHeartRateBpm,
    steps: steps,
  ),
);

/// A `round_instance` sensor summary on [sessionId] for the round
/// `ri-<effortId>-<roundIndex>`.
Future<void> seedRoundSummary(
  WorkoutRepository repo, {
  required String sessionId,
  required String effortId,
  required int roundIndex,
  required double avgHeartRateBpm,
}) => seedSensorSummary(
  repo,
  sensorSummary(
    sessionId: sessionId,
    scope: SensorSummary.scopeRoundInstance,
    targetId: 'ri-$effortId-$roundIndex',
    windowStartMs: fixtureStart,
    windowEndMs: fixtureStart + 1000,
    avgHeartRateBpm: avgHeartRateBpm,
  ),
);

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the Instruments computation', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'S-1005 sections are ordered by training days in the window',
        () async {
          await seedExercise(repo, id: 'ex-run', name: 'Easy Run');
          await seedExercise(repo, id: 'ex-squat', name: 'Back Squat');

          // Cardio on three distinct days.
          for (final daysAgo in [1, 2, 3]) {
            final sessionId = 's-1005-run-$daysAgo';
            await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
            await addTimedEffort(
              repo,
              segmentId: 'seg-$sessionId',
              effortId: 'eff-1005-run-$daysAgo',
              exerciseId: 'ex-run',
            );
            await seedTimedEntry(
              repo,
              effortId: 'eff-1005-run-$daysAgo',
              entryIndex: 0,
              durationSecs: 600,
            );
          }

          // Resistance on one day.
          await seedSession(repo, sessionId: 's-1005-squat', daysAgo: 2);
          await addSetEffort(
            repo,
            segmentId: 'seg-s-1005-squat',
            effortId: 'eff-1005-squat',
            exerciseId: 'ex-squat',
          );
          await seedSetEntry(
            repo,
            effortId: 'eff-1005-squat',
            number: 0,
            reps: 5,
            weightKg: 100,
          );

          final service = StatsProgressService(repo);
          final sections = await service.computeInstrumentSections(
            window: windowOfDays(14),
          );

          expect(
            [for (final section in sections) section.section],
            [ExerciseSection.cardio, ExerciseSection.resistance],
            reason: 'cardio leads on 3 training days despite declaration order',
          );
          expect(
            sectionOf(sections, ExerciseSection.cardio).trainingDayCount,
            3,
          );
          expect(
            sectionOf(sections, ExerciseSection.resistance).trainingDayCount,
            1,
          );

          // (b) the resistance session moved outside the window.
          final moved = StatsProgressService(repo);
          final narrow = await moved.computeInstrumentSections(
            window: windowOfDays(2),
          );
          expect(
            [for (final section in narrow) section.section],
            [ExerciseSection.cardio],
            reason: 'a section with no work in the window does not appear',
          );
        },
      );

      test('S-1006 the section comes from the effort kind, not the '
          'session modality', () async {
        await seedExercise(repo, id: 'ex-squat', name: 'Back Squat');
        await seedExercise(repo, id: 'ex-warmup', name: 'Treadmill Warm-up');
        await seedExercise(repo, id: 'ex-plank-timed', name: 'Plank');
        await seedExercise(repo, id: 'ex-plank-hold', name: 'Plank');
        await seedExercise(repo, id: 'ex-bjj', name: 'BJJ Rounds');

        // (a) a Free Training session holding a set effort.
        await seedSession(
          repo,
          sessionId: 's-1006a',
          modality: null,
          daysAgo: 1,
        );
        await addSetEffort(
          repo,
          segmentId: 'seg-s-1006a',
          effortId: 'eff-1006a',
          exerciseId: 'ex-squat',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-1006a',
          number: 0,
          reps: 5,
          weightKg: 100,
        );

        // (b) a resistance session holding a timed effort.
        await seedSession(
          repo,
          sessionId: 's-1006b',
          modality: 'resistance_lifting',
          daysAgo: 2,
        );
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-1006b',
          effortId: 'eff-1006b',
          exerciseId: 'ex-warmup',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1006b',
          entryIndex: 0,
          durationSecs: 300,
        );

        // (c) a timed effort on an exercise named 'Plank'.
        await seedSession(repo, sessionId: 's-1006c', daysAgo: 3);
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-1006c',
          effortId: 'eff-1006c',
          exerciseId: 'ex-plank-timed',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1006c',
          entryIndex: 0,
          durationSecs: 120,
        );

        // (d) a drill effort on a second exercise also named 'Plank'.
        await seedSession(repo, sessionId: 's-1006d', daysAgo: 4);
        await addDrillEffort(
          repo,
          segmentId: 'seg-s-1006d',
          effortId: 'eff-1006d',
          exerciseId: 'ex-plank-hold',
        );
        await repo.createTimedInstance(
          timedInstance('eff-1006d', 0, durationSecs: 90, entryIndex: 0),
        );

        // (e) a round effort inside a sports session.
        await seedSession(
          repo,
          sessionId: 's-1006e',
          modality: 'sports',
          daysAgo: 5,
        );
        await seedRoundEffort(
          repo,
          segmentId: 'seg-s-1006e',
          effortId: 'eff-1006e',
          exerciseId: 'ex-bjj',
          rounds: [roundInstance('eff-1006e', 0, durationSecs: 180)],
        );

        final sections = await StatsProgressService(
          repo,
        ).computeInstrumentSections(window: windowOfDays(14));

        expect(
          sectionOf(
            sections,
            ExerciseSection.resistance,
          ).rows.single.summary.exerciseId,
          'ex-squat',
          reason: 'a set effort in a Free Training session is Resistance',
        );
        expect(
          sectionOf(
            sections,
            ExerciseSection.cardio,
          ).rows.map((r) => r.summary.exerciseId),
          containsAll(<String>['ex-warmup', 'ex-plank-timed']),
          reason: 'a timed effort is Cardio whatever the session modality',
        );
        expect(
          sectionOf(
            sections,
            ExerciseSection.isometric,
          ).rows.single.summary.exerciseId,
          'ex-plank-hold',
        );
        expect(
          sectionOf(
            sections,
            ExerciseSection.sports,
          ).rows.single.summary.exerciseId,
          'ex-bjj',
        );

        // The two 'Plank' exercises sit in two sections, each with its own
        // value: the same display name is not the same exercise.
        final timedPlank = rowOf(
          sectionOf(sections, ExerciseSection.cardio),
          'ex-plank-timed',
        );
        final holdPlank = rowOf(
          sectionOf(sections, ExerciseSection.isometric),
          'ex-plank-hold',
        );
        expect(timedPlank.summary.name, 'Plank');
        expect(holdPlank.summary.name, 'Plank');
        expect(timedPlank.summary.best.metric, NativeMetric.duration);
        expect(holdPlank.summary.best.metric, NativeMetric.hold);
      });

      test('S-1007 the native value per row is 4a\'s, formatted by 4a\'s '
          'formatter', () async {
        final settings = SettingsState(repo, fakePreferencesService());

        await seedExercise(repo, id: 'ex-row', name: 'Barbell Row');
        await seedExercise(repo, id: 'ex-pull', name: 'Pull-up');
        await seedExercise(repo, id: 'ex-run', name: 'Easy Run');
        await seedExercise(repo, id: 'ex-walk', name: 'Walk');
        await seedExercise(repo, id: 'ex-hold', name: 'Dead Hang');
        await seedExercise(repo, id: 'ex-timed-hold', name: 'Wall Sit');
        await seedExercise(repo, id: 'ex-bjj', name: 'BJJ Rounds');

        await seedSession(repo, sessionId: 's-1007a', daysAgo: 1);
        await addSetEffort(
          repo,
          segmentId: 'seg-s-1007a',
          effortId: 'eff-1007a',
          exerciseId: 'ex-row',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-1007a',
          number: 0,
          reps: 5,
          weightKg: 100,
        );

        await seedSession(repo, sessionId: 's-1007b', daysAgo: 2);
        await addSetEffort(
          repo,
          segmentId: 'seg-s-1007b',
          effortId: 'eff-1007b',
          exerciseId: 'ex-pull',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-1007b',
          number: 0,
          reps: 8,
          weightKg: 0,
        );
        await repo.createObservation(
          extraWeightRow('eff-1007b', 0, 5, atMs: fixtureRowAt(0)),
        );

        await seedSession(repo, sessionId: 's-1007c', daysAgo: 3);
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-1007c',
          effortId: 'eff-1007c',
          exerciseId: 'ex-run',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1007c',
          entryIndex: 0,
          durationSecs: 600,
          metres: 2000,
        );

        await seedSession(repo, sessionId: 's-1007d', daysAgo: 4);
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-1007d',
          effortId: 'eff-1007d',
          exerciseId: 'ex-walk',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1007d',
          entryIndex: 0,
          durationSecs: 900,
        );

        await seedSession(repo, sessionId: 's-1007e', daysAgo: 5);
        await addDrillEffort(
          repo,
          segmentId: 'seg-s-1007e',
          effortId: 'eff-1007e',
          exerciseId: 'ex-hold',
        );
        await repo.createTimedInstance(
          timedInstance('eff-1007e', 0, durationSecs: 60, entryIndex: 0),
        );
        await repo.createTimedInstance(
          timedInstance('eff-1007e', 1, durationSecs: 45, entryIndex: 1),
        );

        await seedSession(repo, sessionId: 's-1007f', daysAgo: 6);
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-1007f',
          effortId: 'eff-1007f',
          exerciseId: 'ex-timed-hold',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1007f',
          entryIndex: 0,
          durationSecs: 120,
        );

        await seedSession(repo, sessionId: 's-1007g', daysAgo: 7);
        await seedRoundEffort(
          repo,
          segmentId: 'seg-s-1007g',
          effortId: 'eff-1007g',
          exerciseId: 'ex-bjj',
          rounds: [
            roundInstance('eff-1007g', 0, durationSecs: 180),
            roundInstance('eff-1007g', 1, durationSecs: 120),
          ],
        );

        final window = windowOfDays(14);
        final service = StatsProgressService(repo);
        final sections = await service.computeInstrumentSections(
          window: window,
        );
        final metrics = await service.computeExerciseMetrics(
          fromMs: window.fromMs.millisecondsSinceEpoch,
          toMs: window.toMs.millisecondsSinceEpoch,
        );

        final rows = [for (final section in sections) ...section.rows];
        expect(rows, hasLength(7));

        for (final row in rows) {
          final expected = metrics
              .where((m) => m.exerciseId == row.summary.exerciseId)
              .single;
          expect(
            row.summary.best.metric,
            expected.best.metric,
            reason: '${row.summary.exerciseId} reads 4a\'s metric',
          );
          expect(
            row.summary.best.value,
            expected.best.value,
            reason: '${row.summary.exerciseId} reads 4a\'s value',
          );
          expect(
            formatNativeValue(row.summary.best, settings),
            formatNativeValue(expected.best, settings),
          );
        }

        final pull = rowOf(
          sectionOf(sections, ExerciseSection.resistance),
          'ex-pull',
        );
        expect(
          formatNativeValue(pull.summary.best, settings),
          '8 reps (+5 kg)',
        );

        final hold = rowOf(
          sectionOf(sections, ExerciseSection.isometric),
          'ex-hold',
        );
        expect(formatNativeValue(hold.summary.best, settings), '1:00');
        expect(
          formatNativeSecondary(hold.summary.best, settings),
          '1:45',
          reason: 'the hold\'s total time is the secondary figure',
        );
        expect(
          nativeSecondaryLabel(hold.summary.best.secondaryMetric),
          'Total hold',
        );

        final bjj = rowOf(
          sectionOf(sections, ExerciseSection.sports),
          'ex-bjj',
        );
        expect(formatNativeValue(bjj.summary.best, settings), '2 rounds');
        expect(formatNativeSecondary(bjj.summary.best, settings), '5 min');
        expect(
          nativeSecondaryLabel(bjj.summary.best.secondaryMetric),
          'Total time',
        );
      });

      test('S-1008 cadence and average heart rate', () async {
        await seedExercise(repo, id: 'ex-run', name: 'Easy Run');
        await seedExercise(repo, id: 'ex-walk', name: 'Walk');
        await seedExercise(repo, id: 'ex-bjj', name: 'BJJ Rounds');
        await seedExercise(repo, id: 'ex-hold', name: 'Dead Hang');
        await seedExercise(repo, id: 'ex-squat', name: 'Back Squat');

        // (a) two finished timed instances, 300 s and 600 s, with steps and HR.
        await seedSession(repo, sessionId: 's-1008a', daysAgo: 1);
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-1008a',
          effortId: 'eff-1008a',
          exerciseId: 'ex-run',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1008a',
          entryIndex: 0,
          durationSecs: 300,
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1008a',
          entryIndex: 1,
          durationSecs: 600,
        );
        await seedInstanceSummary(
          repo,
          sessionId: 's-1008a',
          effortId: 'eff-1008a',
          entryIndex: 0,
          avgHeartRateBpm: 140,
          steps: 600,
        );
        await seedInstanceSummary(
          repo,
          sessionId: 's-1008a',
          effortId: 'eff-1008a',
          entryIndex: 1,
          avgHeartRateBpm: 150,
          steps: 1200,
        );

        // (b) the same shape with no summaries at all.
        await seedSession(repo, sessionId: 's-1008b', daysAgo: 2);
        await addTimedEffort(
          repo,
          segmentId: 'seg-s-1008b',
          effortId: 'eff-1008b',
          exerciseId: 'ex-walk',
        );
        await seedTimedEntry(
          repo,
          effortId: 'eff-1008b',
          entryIndex: 0,
          durationSecs: 300,
        );

        // (c) a sports exercise with two round summaries.
        await seedSession(repo, sessionId: 's-1008c', daysAgo: 3);
        await seedRoundEffort(
          repo,
          segmentId: 'seg-s-1008c',
          effortId: 'eff-1008c',
          exerciseId: 'ex-bjj',
          rounds: [
            roundInstance('eff-1008c', 0, durationSecs: 180),
            roundInstance('eff-1008c', 1, durationSecs: 180),
          ],
        );
        await seedRoundSummary(
          repo,
          sessionId: 's-1008c',
          effortId: 'eff-1008c',
          roundIndex: 0,
          avgHeartRateBpm: 146,
        );
        await seedRoundSummary(
          repo,
          sessionId: 's-1008c',
          effortId: 'eff-1008c',
          roundIndex: 1,
          avgHeartRateBpm: 150,
        );

        // (d) an isometric and a resistance exercise, summaries present.
        await seedSession(repo, sessionId: 's-1008d', daysAgo: 4);
        await addDrillEffort(
          repo,
          segmentId: 'seg-s-1008d',
          effortId: 'eff-1008d',
          exerciseId: 'ex-hold',
        );
        await repo.createTimedInstance(
          timedInstance('eff-1008d', 0, durationSecs: 60, entryIndex: 0),
        );
        await seedInstanceSummary(
          repo,
          sessionId: 's-1008d',
          effortId: 'eff-1008d',
          entryIndex: 0,
          avgHeartRateBpm: 120,
          steps: 30,
        );

        await seedSession(repo, sessionId: 's-1008e', daysAgo: 5);
        await addSetEffort(
          repo,
          segmentId: 'seg-s-1008e',
          effortId: 'eff-1008e',
          exerciseId: 'ex-squat',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-1008e',
          number: 0,
          reps: 5,
          weightKg: 100,
        );
        await seedSensorSummary(
          repo,
          sensorSummary(
            sessionId: 's-1008e',
            scope: SensorSummary.scopeEffort,
            targetId: 'eff-1008e',
            windowStartMs: fixtureStart,
            windowEndMs: fixtureStart + 1000,
            avgHeartRateBpm: 130,
          ),
        );

        final sections = await StatsProgressService(
          repo,
        ).computeInstrumentSections(window: windowOfDays(14));

        final run = rowOf(
          sectionOf(sections, ExerciseSection.cardio),
          'ex-run',
        );
        expect(run.cadenceStepsPerMin, 120);
        expect(run.averageHeartRateBpm, 145);

        final walk = rowOf(
          sectionOf(sections, ExerciseSection.cardio),
          'ex-walk',
        );
        expect(walk.cadenceStepsPerMin, isNull);
        expect(walk.averageHeartRateBpm, isNull);

        final bjj = rowOf(
          sectionOf(sections, ExerciseSection.sports),
          'ex-bjj',
        );
        expect(bjj.averageHeartRateBpm, 148);
        expect(bjj.cadenceStepsPerMin, isNull);

        final hold = rowOf(
          sectionOf(sections, ExerciseSection.isometric),
          'ex-hold',
        );
        expect(hold.averageHeartRateBpm, isNull);
        expect(hold.cadenceStepsPerMin, isNull);

        final squat = rowOf(
          sectionOf(sections, ExerciseSection.resistance),
          'ex-squat',
        );
        expect(squat.averageHeartRateBpm, isNull);
        expect(squat.cadenceStepsPerMin, isNull);
      });

      test(
        'S-1009 the change indicator, and when it must not appear',
        () async {
          await seedExercise(repo, id: 'ex-a', name: 'A Press');
          await seedExercise(repo, id: 'ex-b', name: 'B Press');
          await seedExercise(repo, id: 'ex-c', name: 'C Press');
          await seedExercise(repo, id: 'ex-d', name: 'D Press');
          await seedExercise(repo, id: 'ex-e', name: 'E Press');
          await seedExercise(repo, id: 'ex-f', name: 'F Press');

          // A helper: one set effort of [exerciseId] on the day [daysAgo] back.
          Future<void> setOn(
            String exerciseId,
            int daysAgo,
            double weightKg,
          ) async {
            final sessionId = 's-1009-$exerciseId-$daysAgo';
            await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
            await addSetEffort(
              repo,
              segmentId: 'seg-$sessionId',
              effortId: 'eff-$sessionId',
              exerciseId: exerciseId,
            );
            await seedSetEntry(
              repo,
              effortId: 'eff-$sessionId',
              number: 0,
              reps: 5,
              weightKg: weightKg,
            );
          }

          // (a) higher in the window, (b) lower, (c) window only,
          // (e) identical, (f) previous range only.
          await setOn('ex-a', 1, 120);
          await setOn('ex-a', 8, 100);
          await setOn('ex-b', 2, 80);
          await setOn('ex-b', 9, 100);
          await setOn('ex-c', 3, 100);
          await setOn('ex-e', 4, 100);
          await setOn('ex-e', 10, 100);
          await setOn('ex-f', 11, 100);

          // (d) a drill in the window, a timed effort in the previous range.
          await seedSession(repo, sessionId: 's-1009-d-now', daysAgo: 5);
          await addDrillEffort(
            repo,
            segmentId: 'seg-s-1009-d-now',
            effortId: 'eff-1009-d-now',
            exerciseId: 'ex-d',
          );
          await repo.createTimedInstance(
            timedInstance('eff-1009-d-now', 0, durationSecs: 60, entryIndex: 0),
          );
          await seedSession(repo, sessionId: 's-1009-d-prev', daysAgo: 12);
          await addTimedEffort(
            repo,
            segmentId: 'seg-s-1009-d-prev',
            effortId: 'eff-1009-d-prev',
            exerciseId: 'ex-d',
          );
          await seedTimedEntry(
            repo,
            effortId: 'eff-1009-d-prev',
            entryIndex: 0,
            durationSecs: 300,
          );

          final sections = await StatsProgressService(
            repo,
          ).computeInstrumentSections(window: windowOfDays(7));
          final resistance = sectionOf(sections, ExerciseSection.resistance);

          final a = rowOf(resistance, 'ex-a');
          expect(a.previousValue, isNotNull);
          expect(a.summary.best.value - a.previousValue!.value, greaterThan(0));

          final b = rowOf(resistance, 'ex-b');
          expect(b.previousValue, isNotNull);
          expect(b.summary.best.value - b.previousValue!.value, lessThan(0));

          expect(rowOf(resistance, 'ex-c').previousValue, isNull);
          expect(rowOf(resistance, 'ex-e').previousValue, isNotNull);
          expect(
            rowOf(resistance, 'ex-e').summary.best.value -
                rowOf(resistance, 'ex-e').previousValue!.value,
            0,
          );
          expect(
            resistance.rows.map((r) => r.summary.exerciseId),
            isNot(contains('ex-f')),
            reason:
                'an exercise trained only in the previous range is not a row',
          );

          final d = rowOf(
            sectionOf(sections, ExerciseSection.isometric),
            'ex-d',
          );
          expect(d.summary.best.metric, NativeMetric.hold);
          expect(
            d.previousValue,
            isNull,
            reason: 'a metric mismatch is not comparable',
          );
        },
      );

      test('S-1009 the previous range is calendar arithmetic', () {
        final window = StatsWindow(
          fromMs: DateTime(2026, 3, 8),
          toMs: DateTime(2026, 3, 14, 23, 59, 59, 999),
          label: 'Last 7 days',
          isPeriodScoped: false,
          recentDays: 7,
        );

        final previous = StatsProgressService.previousRangeFor(window);

        expect(previous.toMs, window.fromMs.millisecondsSinceEpoch - 1);
        expect(previous.fromMs, DateTime(2026, 3, 1).millisecondsSinceEpoch);
      });

      test(
        'S-1010 row ordering, duplicate names and a zero-valued row',
        () async {
          await seedExercise(repo, id: 'ex-3', name: 'Bench Press');
          await seedExercise(repo, id: 'ex-dup-a', name: 'Custom Press');
          await seedExercise(repo, id: 'ex-dup-b', name: 'Custom Press');
          await seedExercise(repo, id: 'ex-2', name: 'Squat');
          await seedExercise(repo, id: 'ex-1', name: 'Row');
          await seedExercise(repo, id: 'ex-0', name: 'Empty Set');

          Future<void> setOn(String exerciseId, int daysAgo) async {
            final sessionId = 's-1010-$exerciseId-$daysAgo';
            await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
            await addSetEffort(
              repo,
              segmentId: 'seg-$sessionId',
              effortId: 'eff-$sessionId',
              exerciseId: exerciseId,
            );
            await seedSetEntry(
              repo,
              effortId: 'eff-$sessionId',
              number: 0,
              reps: 5,
              weightKg: 100,
            );
          }

          for (final daysAgo in [1, 2, 3]) {
            await setOn('ex-3', daysAgo);
          }
          for (final daysAgo in [1, 2]) {
            await setOn('ex-dup-a', daysAgo);
            await setOn('ex-dup-b', daysAgo);
            await setOn('ex-2', daysAgo);
          }
          await setOn('ex-1', 1);

          // ex-0: a set effort with no observation rows at all.
          await seedSession(repo, sessionId: 's-1010-ex-0', daysAgo: 1);
          await addSetEffort(
            repo,
            segmentId: 'seg-s-1010-ex-0',
            effortId: 'eff-1010-ex-0',
            exerciseId: 'ex-0',
          );

          final sections = await StatsProgressService(
            repo,
          ).computeInstrumentSections(window: windowOfDays(14));
          final resistance = sectionOf(sections, ExerciseSection.resistance);

          expect(
            [for (final row in resistance.rows) row.summary.exerciseId],
            ['ex-3', 'ex-dup-a', 'ex-dup-b', 'ex-2', 'ex-1', 'ex-0'],
          );

          final zero = rowOf(resistance, 'ex-0');
          expect(zero.summary.best.value, 0);
          expect(
            zero.summary.points,
            isEmpty,
            reason: 'a row with no readable value has no sparkline',
          );
        },
      );

      test('S-1013 a lifter-only user', () async {
        await seedExercise(repo, id: 'ex-squat', name: 'Back Squat');
        await seedExercise(repo, id: 'ex-row', name: 'Barbell Row');

        for (final daysAgo in [1, 2]) {
          final sessionId = 's-1013-$daysAgo';
          await seedSession(repo, sessionId: sessionId, daysAgo: daysAgo);
          await addSetEffort(
            repo,
            segmentId: 'seg-$sessionId',
            effortId: 'eff-1013-squat-$daysAgo',
            exerciseId: 'ex-squat',
          );
          await seedSetEntry(
            repo,
            effortId: 'eff-1013-squat-$daysAgo',
            number: 0,
            reps: 5,
            weightKg: 100,
          );
          await addSetEffort(
            repo,
            segmentId: 'seg-$sessionId',
            effortId: 'eff-1013-row-$daysAgo',
            exerciseId: 'ex-row',
          );
          await seedSetEntry(
            repo,
            effortId: 'eff-1013-row-$daysAgo',
            number: 0,
            reps: 8,
            weightKg: 60,
          );
        }

        final sections = await StatsProgressService(
          repo,
        ).computeInstrumentSections(window: windowOfDays(14));

        expect(sections, hasLength(1));
        expect(sections.single.section, ExerciseSection.resistance);
        // Both exercises are trained on the same two days, so D-506's tie falls
        // to the name: 'Back Squat' sorts before 'Barbell Row'.
        expect(
          sections.single.rows.map((r) => r.summary.exerciseId),
          ['ex-squat', 'ex-row'],
          reason: 'equal point counts, so the name decides: Back Squat first',
        );
      });

      test('S-1018 an exercise with a single session', () async {
        await seedExercise(repo, id: 'ex-squat', name: 'Back Squat');
        await seedSession(repo, sessionId: 's-1018', daysAgo: 1);
        await addSetEffort(
          repo,
          segmentId: 'seg-s-1018',
          effortId: 'eff-1018',
          exerciseId: 'ex-squat',
        );
        await seedSetEntry(
          repo,
          effortId: 'eff-1018',
          number: 0,
          reps: 5,
          weightKg: 100,
        );

        final sections = await StatsProgressService(
          repo,
        ).computeInstrumentSections(window: windowOfDays(14));

        final row = sectionOf(sections, ExerciseSection.resistance).rows.single;
        expect(row.summary.exerciseId, 'ex-squat');
        expect(row.summary.points, hasLength(1));
        expect(row.summary.best.value, greaterThan(0));
        expect(row.previousValue, isNull);
        expect(row.summary.sessionCount, 1);
      });
    });
  }
}
