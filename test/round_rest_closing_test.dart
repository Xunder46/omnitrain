// Test scenario S-3: Round Effort with Rest Closing Race
//
// Verifies that when a round timer starts, open rest records are closed
// in-memory immediately, and the repository persist happens asynchronously.

import 'package:test/test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Shared test setup ───────────────────────────────────────────────────────

Future<WorkoutState> _setupWorkoutState(MockWorkoutRepository repo) async {
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession(modality: 'sports');
  return workoutState;
}

Future<String> _addRoundEffort(
  WorkoutState workoutState,
  MockWorkoutRepository repo,
) async {
  final exercises = await repo.getExercises();
  final roundExercise =
      exercises.firstWhere((e) => e.capabilities.contains('rounds'));
  final effortId = await workoutState.addExerciseToSession(
    roundExercise,
    chosenMetric: 'rounds',
  );
  await workoutState.addEntry(effortId);
  return effortId;
}

void main() {
  group('Round Rest Closing', () {
    // ── S-3: Round Effort with Rest Closing Race ───────────────────────────

    test(
      'S-3: open rest is closed when round timer starts',
      () async {
        final repo = MockWorkoutRepository();
        final workoutState = await _setupWorkoutState(repo);
        final effortId = await _addRoundEffort(workoutState, repo);

        // Step 1: Start a rest for entryIndex 1
        await workoutState.recordRestStart(effortId, 1);
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isTrue,
          reason: 'rest should be open after recordRestStart',
        );

        // Step 2: Start a round timer for entryIndex 1
        await workoutState.startRound(effortId, 1);

        // Step 3: Immediately check rest state (synchronous close should be done)
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isFalse,
          reason: 'rest should be closed in-memory immediately when round starts',
        );

        // Step 4: Let one tick fire and check again
        await Future.delayed(const Duration(milliseconds: 100));
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isFalse,
          reason: 'rest should remain closed after round tick',
        );

        // Step 5: Complete the round
        await workoutState.endRoundEarly(effortId, 1);

        // Step 6: Start a new rest for entryIndex 2
        await workoutState.recordRestStart(effortId, 2);

        // Verify new rest is open and old rest is closed
        expect(
          workoutState.hasRestRecord(effortId, 2),
          isTrue,
          reason: 'new rest should be open for entryIndex 2',
        );
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isFalse,
          reason: 'old rest for entryIndex 1 should remain closed',
        );
      },
    );
  });
}
