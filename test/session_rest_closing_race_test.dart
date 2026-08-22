// Test scenarios S-1 and S-2: Rest timer closing immediately when timed effort starts
//
// S-1: Log Set → Start Timed → Log Timed (No Overlap)
//   Verifies that hasRestRecord and getRestElapsedSeconds reflect the closed state
//   immediately after startTimedEntry, before the async repository persist completes.
//
// S-2: High-Latency Rest Close (Async Persist Lag)
//   Simulates 500ms async delay in repository.updateEntryRest() to verify the
//   in-memory cache is closed synchronously even while the persist is still in-flight.

import 'dart:async';

import 'package:test/test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/delayed_rest_mock_repository.dart';

// ── Shared test setup ───────────────────────────────────────────────────────

Future<WorkoutState> _setupWorkoutState(MockWorkoutRepository repo) async {
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession(modality: 'cardio_endurance');
  return workoutState;
}

Future<String> _addTimedEffort(
  WorkoutState workoutState,
  MockWorkoutRepository repo,
) async {
  final exercises = await repo.getExercises();
  final timedExercise =
      exercises.firstWhere((e) => e.capabilities.contains('time'));
  final effortId = await workoutState.addExerciseToSession(
    timedExercise,
    chosenMetric: 'duration',
  );
  await workoutState.addEntry(effortId);
  return effortId;
}

void main() {
  group('Session Rest Closing Race', () {
    // ── S-1: Log Set → Start Timed → Log Timed (No Overlap) ────────────────

    test(
      'S-1: rest is closed in-memory immediately when timed timer starts',
      () async {
        final repo = MockWorkoutRepository();
        final workoutState = await _setupWorkoutState(repo);
        final effortId = await _addTimedEffort(workoutState, repo);

        // Step 1: Log a set (via updateEntryValue)
        await workoutState.updateEntryValue(effortId, 0, 'duration', 30);

        // Step 2: Verify rest starts (would be auto-called after logging in real UI)
        await workoutState.recordRestStart(effortId, 1);

        // Step 3: Verify rest is open and counting
        expect(workoutState.hasRestRecord(effortId, 1), isTrue);
        // Add a delay to ensure enough time has passed since rest start
        // (elapsedSeconds needs at least 1 second to show > 0)
        await Future.delayed(const Duration(milliseconds: 1100));
        expect(workoutState.getRestElapsedSeconds(effortId, 1), greaterThan(0));

        // Step 4: Start timed entry for entryIndex 1
        await workoutState.startTimedEntry(effortId, 1);

        // Step 5: Verify rest is closed IMMEDIATELY in memory
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isFalse,
          reason: 'rest should be closed in-memory immediately after '
              'startTimedEntry, not wait for async persist',
        );
        expect(
          workoutState.getRestElapsedSeconds(effortId, 1),
          equals(0),
          reason:
              'closed rest should return 0 elapsed seconds immediately',
        );

        // Step 6: Log the timed entry
        await workoutState.finishTimedEntry(effortId, 1);

        // Step 7: Start a new rest for entryIndex 2
        await workoutState.recordRestStart(effortId, 2);

        // Verify the new rest is open
        expect(workoutState.hasRestRecord(effortId, 2), isTrue);
        // Verify old rest is closed
        expect(workoutState.hasRestRecord(effortId, 1), isFalse);
      },
    );

    // ── S-2: High-Latency Rest Close (Async Persist Lag) ────────────────────

    test(
      'S-2: rest is closed in-memory while repository persist is still in-flight',
      () async {
        // Gate only updateEntryRest, not createEntryRest, so recordRestStart can
        // complete normally but closeAllOpenRests updateEntryRest will be held.
        final repo = DelayedRestMockRepository(gateUpdateEntryRest: true);
        final workoutState = await _setupWorkoutState(repo);
        final effortId = await _addTimedEffort(workoutState, repo);

        // Step 1: Log a set
        await workoutState.updateEntryValue(effortId, 0, 'duration', 30);

        // Step 2: Start rest for entryIndex 1 (will complete normally, no gate)
        await workoutState.recordRestStart(effortId, 1);

        // Verify rest is open
        expect(workoutState.hasRestRecord(effortId, 1), isTrue);
        // Add a delay to ensure enough time has passed since rest start
        // (elapsedSeconds needs at least 1 second to show > 0)
        await Future.delayed(const Duration(milliseconds: 1100));
        final restElapsedBefore =
            workoutState.getRestElapsedSeconds(effortId, 1);
        expect(restElapsedBefore, greaterThan(0));

        // Step 3: Start timed timer for entryIndex 1
        // This fires closeAllOpenRests() asynchronously, which will hold on
        // updateEntryRest due to the gate, but the in-memory close happens BEFORE
        // the gate blocks.
        unawaited(workoutState.startTimedEntry(effortId, 1));

        // Give the async part a chance to reach the gate on updateEntryRest
        await Future.delayed(const Duration(milliseconds: 50));

        // Step 4: The in-memory cache should be closed even though persist
        // is held up by the gate
        expect(
          repo.hasPendingUpdateOperations,
          isTrue,
          reason: 'repository updateEntryRest should be held in-flight',
        );
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isFalse,
          reason: 'rest should be closed in-memory IMMEDIATELY, even while '
              'repository persist is in-flight',
        );
        expect(
          workoutState.getRestElapsedSeconds(effortId, 1),
          equals(0),
          reason: 'closed rest should return 0 elapsed seconds immediately, '
              'even while persist is in-flight',
        );

        // Step 5: Allow the async persist to complete
        repo.completePendingUpdateEntryRest();
        await Future.delayed(const Duration(milliseconds: 50));

        // Verify state is consistent after persist completes
        expect(
          workoutState.hasRestRecord(effortId, 1),
          isFalse,
          reason:
              'rest should still be closed after repository persist completes',
        );
        expect(
          workoutState.getRestElapsedSeconds(effortId, 1),
          equals(0),
        );

        // Step 6: Start new rest for entryIndex 2
        await workoutState.recordRestStart(effortId, 2);
        expect(workoutState.hasRestRecord(effortId, 2), isTrue);
        expect(workoutState.hasRestRecord(effortId, 1), isFalse);
      },
    );
  });
}
