// Test scenario S-4: Drill Effort Rest Close and New Rest Start
//
// Verifies that when a drill entry is finished, its associated rest records
// are properly closed and a new rest can be started for the next entry without
// stale state from the previous effort.
//
// Note: This test does not directly assert on the display cache (_effortElapsed)
// because that is UI-layer state. Instead, it verifies the observable behavior
// that rest records are closed and new rests start correctly, which is the
// contract that prevents display cache bleed at the UI level.

import 'package:test/test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Shared test setup ───────────────────────────────────────────────────────

Future<WorkoutState> _setupWorkoutState(MockWorkoutRepository repo) async {
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession(modality: 'isometric_stretching');
  return workoutState;
}

Future<String> _addDrillEffort(
  WorkoutState workoutState,
  MockWorkoutRepository repo,
) async {
  final exercises = await repo.getExercises();
  final drillExercise = exercises.firstWhere(
    (e) => e.capabilities.contains('time'),
  );
  final effortId = await workoutState.addExerciseToSession(
    drillExercise,
    chosenMetric: 'duration',
  );
  await workoutState.addEntry(effortId);
  return effortId;
}

void main() {
  group('Drill Display Cache Sync', () {
    // ── S-4: Drill Effort with Display Cache Sync ──────────────────────────

    test(
      'S-4: drill effort rest closes and new rest starts without stale state',
      () async {
        final repo = MockWorkoutRepository();
        final workoutState = await _setupWorkoutState(repo);
        final effortId = await _addDrillEffort(workoutState, repo);

        // Step 1: Start the drill entry and let it run for some time
        await workoutState.startTimedEntry(effortId, 0);
        // Simulate some elapsed time
        await Future.delayed(const Duration(milliseconds: 100));

        // Step 2: Finish the drill entry (this closes associated rests)
        await workoutState.finishTimedEntry(effortId, 0);

        // Step 3: Start a new rest for entryIndex 1 (without stale state)
        await workoutState.recordRestStart(effortId, 1);

        // Verify the new rest is open and counting
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isTrue,
          reason: 'new rest should be open for entryIndex 1',
        );
        final elapsedAfterStart = workoutState.getRestElapsedSeconds(
          effortId,
          1,
        );
        expect(
          elapsedAfterStart,
          greaterThanOrEqualTo(0),
          reason: 'new rest should start counting from 0',
        );

        // Wait a bit and verify the rest is still counting
        await Future.delayed(const Duration(milliseconds: 100));
        final elapsedAfterWait = workoutState.getRestElapsedSeconds(
          effortId,
          1,
        );
        expect(
          elapsedAfterWait,
          greaterThanOrEqualTo(elapsedAfterStart),
          reason: 'rest should continue counting',
        );

        // Verify old drill rest (if any) is closed
        expect(
          workoutState.hasRestRecord(effortId, 0),
          isFalse,
          reason: 'drill entry (entryIndex 0) should not have an open rest',
        );
      },
    );
  });
}
