// Plan 227 — a skipped set counts for nothing: a set marked skipped
// (`markSetSkipped`: reps 0, `valueBool` true, the planned weight left in
// place) stays stored but is read as nothing done — no Resistance minutes in
// the Training Mix and no completed set in the post-workout summary.
//
// Scenarios S-22701..S-22705.
//
// Plan: `docs/plans/2026-11-17-227-skipped-set-counts-for-nothing-plan/2026-11-17-227-skipped-set-counts-for-nothing-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/exercise_metric.dart';
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
  group('S-22701 Mix — a skipped-only lift gives its time to nothing (Mock)', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-22701 a finished round beside a lift whose only set was skipped '
        'reads Sports only', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'sports');
      final roundExercise = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('rounds'),
      );
      final roundEffortId = await state.addExerciseToSession(
        roundExercise,
        effortKindOverride: 'round',
      );

      // A finished round the session screen would have persisted: started
      // after the session, finished, holding its measured seconds. One
      // second, so the measured time stays inside the real ~1.1 s session
      // duration and the split scales Sports to the whole duration instead
      // of handing it to the dominant section (a 1:1 effort tie resolves to
      // Resistance in declaration order).
      final startedAtMs = state.currentSession!.startedAtMs + 100;
      await repo.createRoundInstance(
        RoundInstance(
          id: 'ri-$roundEffortId-0',
          effortId: roundEffortId,
          roundIndex: 0,
          plannedDurationSecs: 1,
          actualDurationSecs: 1,
          startedAtMs: startedAtMs,
          finishedAtMs: startedAtMs + 1000,
          completed: true,
          state: RoundState.finished,
          createdAtMs: startedAtMs,
          updatedAtMs: startedAtMs,
        ),
      );

      final lift = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      final liftEffortId = await state.addExerciseToSession(
        lift,
        effortKindOverride: 'set',
      );
      await state.markSetSkipped(liftEffortId, 0);

      final sessionId = state.currentSession!.id;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.endSession(writeToHealth: false);

      final timeBySection = await StatsProgressService(
        repo,
      ).sessionTimeBySectionFor(sessionId);

      expect(timeBySection.keys, {ExerciseSection.sports});
      expect(
        timeBySection[ExerciseSection.sports],
        closeTo(await _sessionDurationSecs(repo, sessionId), 0.5),
      );
    });
  });

  group('S-22702 Mix — a session whose only work was skipped (Mock)', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-22702 a lift whose only set was skipped gives no time', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');
      final lift = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      final effortId = await state.addExerciseToSession(lift);
      await state.markSetSkipped(effortId, 0);

      final sessionId = state.currentSession!.id;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.endSession(writeToHealth: false);

      expect(
        await StatsProgressService(repo).sessionTimeBySectionFor(sessionId),
        isEmpty,
      );
    });
  });

  group('S-22703 Mix — a logged set beside a skipped one (Mock)', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-22703 a lift with one logged set and one skipped set keeps '
        'Resistance', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');
      final lift = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      final effortId = await state.addExerciseToSession(lift);
      await state.updateEntryValue(effortId, 0, 'reps', 5);
      await state.updateEntryValue(effortId, 0, 'weight', 100.0);
      await state.recordRestStart(effortId, 1);
      await state.addEntry(effortId);
      await state.markSetSkipped(effortId, 1);

      final sessionId = state.currentSession!.id;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.endSession(writeToHealth: false);

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

  group('S-22704/S-22705 summary — a skipped set is not a set done (Mock)', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    test('S-22704 a logged set and a skipped set read one set done', () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');
      final lift = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      final effortId = await state.addExerciseToSession(lift);
      await state.updateEntryValue(effortId, 0, 'reps', 5);
      await state.updateEntryValue(effortId, 0, 'weight', 100.0);
      await state.recordRestStart(effortId, 1);
      await state.addEntry(effortId);
      await state.updateEntryValue(effortId, 1, 'weight', 120.0);
      await state.markSetSkipped(effortId, 1);

      final summary = state.computeSessionSummary();

      expect(summary.exercises.single.setsCompleted, 1);
      expect(summary.totalSets, 1);
    });

    test('S-22705 a skipped set\'s planned weight is never the best weight',
        () async {
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');
      final lift = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      final effortId = await state.addExerciseToSession(lift);
      await state.updateEntryValue(effortId, 0, 'reps', 5);
      await state.updateEntryValue(effortId, 0, 'weight', 100.0);
      await state.recordRestStart(effortId, 1);
      await state.addEntry(effortId);
      await state.updateEntryValue(effortId, 1, 'weight', 120.0);
      await state.markSetSkipped(effortId, 1);

      final summary = state.computeSessionSummary();

      expect(summary.exercises.single.bestWeight, 100.0);
      // Epley e1RM of 5 reps at 100 kg — the 120 kg skip never reaches it.
      expect(
        summary.exercises.single.bestE1RM,
        closeTo(100 * (1 + 5 / 30), 0.001),
      );
    });
  });
}
