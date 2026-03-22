import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/home/home_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

void main() {
  group('Data tracking fixes', () {
    test('maintenance hint persists across HomeState init cycles', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final firstState = HomeState(repository);
      await firstState.init();
      expect(firstState.shouldShowMaintenanceHint, isTrue);

      await firstState.markMaintenanceHintSeen();
      expect(firstState.shouldShowMaintenanceHint, isFalse);

      final secondState = HomeState(repository);
      await secondState.init();
      expect(secondState.shouldShowMaintenanceHint, isFalse);
    });

    test('skip marker persists and rehydrates on reload', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final state = WorkoutState(repository);
      await state.createNewSession();

      final exercise = (await repository.getExercises()).first;
      await state.addExerciseToSession(exercise, chosenMetric: 'reps');

      final effortId = state.getExercisesWithEntries().first['id'] as String;
      await state.markSetSkipped(effortId, 0);

      final inMemoryEntry =
          (state.getExercisesWithEntries().first['entries'] as List).first
              as Map<String, dynamic>;
      expect(inMemoryEntry['skipped'], isTrue);
      expect(inMemoryEntry['reps'], 0);

      final reloaded = WorkoutState(repository);
      await reloaded.loadHistoricalSession(state.currentSession!.id);

      final reloadedEntry =
          (reloaded.getExercisesWithEntries().first['entries'] as List).first
              as Map<String, dynamic>;
      expect(reloadedEntry['skipped'], isTrue);
      expect(reloadedEntry['reps'], 0);
    });

    test('skip marker clears when reps are later logged', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final state = WorkoutState(repository);
      await state.createNewSession();

      final exercise = (await repository.getExercises()).first;
      await state.addExerciseToSession(exercise, chosenMetric: 'reps');

      final effortId = state.getExercisesWithEntries().first['id'] as String;
      await state.markSetSkipped(effortId, 0);

      await state.updateEntryValue(effortId, 0, 'reps', 8);

      final entry =
          (state.getExercisesWithEntries().first['entries'] as List).first
              as Map<String, dynamic>;
      expect(entry['reps'], 8);
      expect(entry['skipped'], isFalse);

      final observations = await repository.getEffortObservations(effortId);
      final repsObs = observations.firstWhere((o) => o.metricId == 'metric-reps');
      expect(repsObs.valueInt, 8);
      expect(repsObs.valueBool, isFalse);
    });

    test('session RPE persists and rehydrates', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final state = WorkoutState(repository);
      await state.createNewSession();
      final sessionId = state.currentSession!.id;

      await state.updateSessionRpe(sessionId, 7.0);

      final persisted = await repository.getSession(sessionId);
      expect(persisted?.perceivedSessionRpe, 7.0);

      final reloaded = WorkoutState(repository);
      await reloaded.loadHistoricalSession(sessionId);
      expect(reloaded.currentSession?.perceivedSessionRpe, 7.0);
    });
  });
}
