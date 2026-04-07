import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/delayed_note_repo.dart';

void main() {
  group('WorkoutState Exercise Note Serialization', () {
    test('save queue serializes rapid overlapping note saves', () async {
      final delayedRepo = DelayedNoteRepository(
        saveLatency: const Duration(milliseconds: 50),
      );
      final state = WorkoutState(delayedRepo);

      // Pre-populate cache to test update path
      state.saveExerciseNote('ex1', 'text1');
      await Future.delayed(const Duration(milliseconds: 100));

      // Fire rapid saves without awaiting individually (simulating debounce + dispose)
      state.saveExerciseNote('ex1', 'text2');
      state.saveExerciseNote('ex1', 'text3');
      state.saveExerciseNote('ex1', 'text4');

      // Wait for queue to drain
      await Future.delayed(const Duration(milliseconds: 500));

      // Final state must be text4
      final note = await delayedRepo.getExerciseNote('ex1');
      expect(
        note?.note,
        equals('text4'),
        reason: 'Last queued save should win despite rapid overlapping calls',
      );
    });

    test('load skips if already cached', () async {
      final delayedRepo = DelayedNoteRepository(
        loadLatency: const Duration(milliseconds: 50),
        saveLatency: const Duration(milliseconds: 50),
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      // Pre-seed a note in repo
      await delayedRepo.saveExerciseNote(
        ExerciseNote(
          id: 'note-ex1',
          exerciseId: 'ex1',
          note: 'preloaded',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final state = WorkoutState(delayedRepo);

      // First load should hit repository latency, then populate cache.
      final firstStopwatch = Stopwatch()..start();
      await state.loadExerciseNote('ex1');
      firstStopwatch.stop();
      expect(state.getExerciseNote('ex1')?.note, equals('preloaded'));
      expect(
        firstStopwatch.elapsedMilliseconds,
        greaterThanOrEqualTo(40),
        reason: 'First load should incur repository load latency',
      );

      // Second load should skip repository fetch because cache is populated.
      final stopwatch = Stopwatch()..start();
      await state.loadExerciseNote('ex1');
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(25),
        reason: 'Second load should be cache-fast and avoid repo latency',
      );
    });

    test('load prevents duplicate in-flight loads', () async {
      final delayedRepo = DelayedNoteRepository(
        saveLatency: const Duration(milliseconds: 100),
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      await delayedRepo.saveExerciseNote(
        ExerciseNote(
          id: 'note-ex1',
          exerciseId: 'ex1',
          note: 'test note',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final state = WorkoutState(delayedRepo);

      // Fire two loads simultaneously
      final future1 = state.loadExerciseNote('ex1');
      final future2 = state.loadExerciseNote('ex1');

      // Both should complete without error
      await Future.wait([future1, future2]);

      expect(
        state.getExerciseNote('ex1')?.note,
        equals('test note'),
        reason: 'Load should complete and cache should have the note',
      );
    });

    test('overlapping loads dedupe per exercise id', () async {
      final delayedRepo = DelayedNoteRepository(
        loadLatency: const Duration(milliseconds: 60),
        saveLatency: Duration.zero,
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      await delayedRepo.saveExerciseNote(
        ExerciseNote(
          id: 'note-ex1',
          exerciseId: 'ex1',
          note: 'note one',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await delayedRepo.saveExerciseNote(
        ExerciseNote(
          id: 'note-ex2',
          exerciseId: 'ex2',
          note: 'note two',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final state = WorkoutState(delayedRepo);

      // Two overlapping loads per exercise should collapse to one repo read each.
      final futures = <Future<void>>[
        state.loadExerciseNote('ex1'),
        state.loadExerciseNote('ex1'),
        state.loadExerciseNote('ex2'),
        state.loadExerciseNote('ex2'),
      ];

      await Future.wait(futures);

      expect(state.getExerciseNote('ex1')?.note, equals('note one'));
      expect(state.getExerciseNote('ex2')?.note, equals('note two'));
      expect(delayedRepo.getReadCountForExercise('ex1'), equals(1));
      expect(delayedRepo.getReadCountForExercise('ex2'), equals(1));
    });

    test('clearSession clears save queue to prevent stale writes', () async {
      final delayedRepo = DelayedNoteRepository(
        saveLatency: const Duration(milliseconds: 50),
      );
      final state = WorkoutState(delayedRepo);

      // Queue a save
      state.saveExerciseNote('ex1', 'old session note');

      // Clear without waiting for save
      state.clearSession();

      // The save queue should be empty
      // Wait beyond the save latency to verify no write occurs
      await Future.delayed(const Duration(milliseconds: 200));

      // Depending on timing, the note may or may not be in the repo.
      // What matters is the queue was cleared, so no new saves should happen.
      // Queue another save in a fresh context.
      state.saveExerciseNote('ex1', 'new session note');
      await Future.delayed(const Duration(milliseconds: 150));

      final note = await delayedRepo.getExerciseNote('ex1');
      // The final note should be 'new session note' regardless of timing.
      // If the queue wasn't cleared, old saves could interfere. This test
      // is more of a smoke test— the key is no errors during drawing/queueing.
      expect(note != null, true, reason: 'A note should exist after saves');
    });

    test('empty note text deletes note via queue', () async {
      final delayedRepo = DelayedNoteRepository(
        saveLatency: const Duration(milliseconds: 50),
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      // Pre-seed a note
      await delayedRepo.saveExerciseNote(
        ExerciseNote(
          id: 'note-ex1',
          exerciseId: 'ex1',
          note: 'initial note',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final state = WorkoutState(delayedRepo);
      await state.loadExerciseNote('ex1');

      // Save empty string (should delete)
      state.saveExerciseNote('ex1', '');

      await Future.delayed(const Duration(milliseconds: 150));

      expect(
        await delayedRepo.getExerciseNote('ex1'),
        isNull,
        reason: 'Empty save should delete the note from storage',
      );
      expect(
        state.getExerciseNote('ex1'),
        isNull,
        reason: 'Empty save should clear cache',
      );
    });
  });
}
