// Plan 224 — a session with nothing done adds nothing to the Training Mix:
// a never-started round or run, or a lift emptied of its sets, contributes no
// time to the Mix, while everything with real work in it reads as before.
//
// Scenarios S-22401..S-22404.
//
// Plan: `docs/plans/2026-11-17-224-mix-ignores-a-session-with-nothing-done-plan/2026-11-17-224-mix-ignores-a-session-with-nothing-done-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
import 'package:omnitrain/core/models/training_load.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

/// The stored session's duration in seconds, the way the split computes it.
Future<double> _sessionDurationSecs(
  MockWorkoutRepository repo,
  String sessionId,
) async {
  final session = (await repo.getSession(sessionId))!;
  return ((session.endedAtMs! - session.startedAtMs) / 1000).round().toDouble();
}

void main() {
  group('S-22401 pure — an empty non-rolling session adds nothing', () {
    test('S-22401 no set, no measured time, 2400 s: the map is empty', () {
      expect(
        sessionTimeByModality(
          durationSecs: 2400,
          isRolling: false,
          measuredSecs: const {},
          dominantSection: ExerciseSection.sports,
          hasSets: false,
          hasEfforts: true,
        ),
        isEmpty,
      );
    });
  });

  group('S-22402 pure — the neighbouring rules stay', () {
    test('S-22402 a set effort with no measured time keeps the remainder', () {
      expect(
        sessionTimeByModality(
          durationSecs: 2400,
          isRolling: false,
          measuredSecs: const {},
          dominantSection: ExerciseSection.sports,
          hasSets: true,
        ),
        {ExerciseSection.resistance: 2400.0},
      );
    });

    test('S-22402 a session with no effort at all keeps the remainder '
        '(the old rule)', () {
      expect(
        sessionTimeByModality(
          durationSecs: 2400,
          isRolling: false,
          measuredSecs: const {},
          dominantSection: ExerciseSection.sports,
          hasSets: false,
          hasEfforts: false,
        ),
        {ExerciseSection.resistance: 2400.0},
      );
    });

    test('S-22402 a no-set session with measured time shares its whole '
        'duration (plan 179)', () {
      expect(
        sessionTimeByModality(
          durationSecs: 2400,
          isRolling: false,
          measuredSecs: const {ExerciseSection.cardio: 600.0},
          dominantSection: ExerciseSection.sports,
          hasSets: false,
        ),
        {ExerciseSection.cardio: 2400.0},
      );
    });

    test('S-22402 a rolling session with no measured time is unchanged', () {
      expect(
        sessionTimeByModality(
          durationSecs: 2400,
          isRolling: true,
          measuredSecs: const {},
          dominantSection: ExerciseSection.sports,
          hasSets: false,
        ),
        isEmpty,
      );
    });
  });

  group('S-22403 service — a never-started round adds nothing (Mock)', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-22403 a session whose only exercise is a never-started round '
        'gives no time', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'sports');
      final exercise = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('rounds'),
      );
      await state.addExerciseToSession(exercise, effortKindOverride: 'round');
      final sessionId = state.currentSession!.id;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.endSession();

      expect(
        await StatsProgressService(repo).sessionTimeBySectionFor(sessionId),
        isEmpty,
      );
    });

    test('S-22403 a session with a finished round gives Sports its whole '
        'duration', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'sports');
      final exercise = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('rounds'),
      );
      final effortId = await state.addExerciseToSession(
        exercise,
        effortKindOverride: 'round',
      );
      final sessionId = state.currentSession!.id;

      // A finished round the session screen would have persisted: started
      // after the session, finished, holding its measured seconds.
      final startedAtMs = state.currentSession!.startedAtMs + 100;
      await repo.createRoundInstance(
        RoundInstance(
          id: 'ri-$effortId-0',
          effortId: effortId,
          roundIndex: 0,
          plannedDurationSecs: 60,
          actualDurationSecs: 60,
          startedAtMs: startedAtMs,
          finishedAtMs: startedAtMs + 60000,
          completed: true,
          state: RoundState.finished,
          createdAtMs: startedAtMs,
          updatedAtMs: startedAtMs,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.endSession();

      expect(
        await StatsProgressService(repo).sessionTimeBySectionFor(sessionId),
        {ExerciseSection.sports: closeTo(await _sessionDurationSecs(repo, sessionId), 0.5)},
      );
    });
  });

  group('S-22404 service — a lift emptied of its sets adds nothing (Mock)', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-22404 a lift with nothing typed gives no time', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');
      final exercise = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      await state.addExerciseToSession(exercise);
      final sessionId = state.currentSession!.id;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.endSession(writeToHealth: false);

      expect(
        await StatsProgressService(repo).sessionTimeBySectionFor(sessionId),
        isEmpty,
      );
    });

    test('S-22404 a lift with one logged set gives Resistance only', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');
      final exercise = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      final effortId = await state.addExerciseToSession(exercise);
      final sessionId = state.currentSession!.id;
      await state.updateEntryValue(effortId, 0, 'reps', 3);
      await state.updateEntryValue(effortId, 0, 'weight', 100.0);
      await state.recordRestStart(effortId, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.endSession();

      final timeBySection = await StatsProgressService(
        repo,
      ).sessionTimeBySectionFor(sessionId);

      expect(timeBySection.keys, {ExerciseSection.resistance});
      expect(
        timeBySection[ExerciseSection.resistance],
        closeTo(await _sessionDurationSecs(repo, sessionId), 0.5),
      );
    });
  });
}
