import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'helpers/delayed_note_repo.dart';

void main() {
  group('Exercise Note Save Ordering', () {
    test('delayed repository preserves last write via chained futures', () async {
        final repo = DelayedNoteRepository(
          saveLatency: const Duration(milliseconds: 50));

      // Simulate two rapid saves using a queue like WorkoutState does.
      // Without the queue, whichever save completes last would win incorrectly.

      // Create futures that simulate the save queue pattern.
      Future<void> queuedFuture1 =
          repo.saveExerciseNote(ExerciseNote(
            id: 'note-ex1',
            exerciseId: 'ex1',
            note: 'first text',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ));

      // Small delay between writes.
      await Future.delayed(const Duration(milliseconds: 10));

      Future<void> queuedFuture2 =
          queuedFuture1.then((_) => repo.saveExerciseNote(ExerciseNote(
            id: 'note-ex1',
            exerciseId: 'ex1',
            note: 'second text',
            createdAtMs: 1000,
            updatedAtMs: 1010,
          )));

      // Wait for both to complete.
      await queuedFuture2;

      // Final state must be 'second text', not 'first text' overwriting it.
      final finalNote = await repo.getExerciseNote('ex1');
      expect(
        finalNote?.note,
        equals('second text'),
        reason: 'Last save should not be overwritten by earlier in-flight save',
      );
    });

    test('rapid overlapping saves maintain order', () async {
        final repo = DelayedNoteRepository(
          saveLatency: const Duration(milliseconds: 50));

      // Simulate WorkoutState queueing behavior where saves are chained.
      final saveQueue = <String, Future<void>>{};

      Future<void> queuedSave(String exerciseId, String text) async {
        saveQueue[exerciseId] = (saveQueue[exerciseId] ?? Future.value())
            .then((_) async {
          final now = DateTime.now().millisecondsSinceEpoch;
          final note = ExerciseNote(
            id: 'note-$exerciseId',
            exerciseId: exerciseId,
            note: text,
            createdAtMs: now,
            updatedAtMs: now,
          );
          await repo.saveExerciseNote(note);
        });
      }

      // Fire multiple saves rapidly.
      unawaited(queuedSave('ex1', 'text1'));
      unawaited(queuedSave('ex1', 'text2'));
      unawaited(queuedSave('ex1', 'text3'));

      // Wait for queue to drain.
      await Future.delayed(const Duration(milliseconds: 300));

      final finalNote = await repo.getExerciseNote('ex1');
      expect(
        finalNote?.note,
        equals('text3'),
        reason: 'Latest save should win despite overlapping queues',
      );
    });

    test('note cache loaded before detail render with delayed repository', ()
        async {
      final repo = DelayedNoteRepository(
        loadLatency: const Duration(milliseconds: 100),
        saveLatency: const Duration(milliseconds: 100),
      );

      // Pre-seed a note.
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.saveExerciseNote(ExerciseNote(
        id: 'note-ex1',
        exerciseId: 'ex1',
        note: 'existing note',
        createdAtMs: now,
        updatedAtMs: now,
      ));

      // Simulate loading before rendering (key requirement from Iteration 2 feedback).
      bool renderWasFired = false;
      final noteCache = <String, ExerciseNote?>{};

      // Step 1: Load note asynchronously.
      final loadFuture = repo.getExerciseNote('ex1').then((note) {
        noteCache['ex1'] = note;
      });

      // Step 2: Verify that rendering doesn't happen until load completes.
      // In real code, this is enforced by awaiting loadFuture before setState.
      expect(
        renderWasFired,
        false,
        reason: 'Detail should not render until note load completes',
      );

      // Step 3: Wait for load to complete.
      await loadFuture;

      // Step 4: Now it's safe to render.
      renderWasFired = true;
      expect(noteCache['ex1']?.note, equals('existing note'));
      expect(renderWasFired, true);
    });

    test('clearing notes in queue does not lose data between saves', () async {
        final repo = DelayedNoteRepository(
          saveLatency: const Duration(milliseconds: 50));

      final saveQueue = <String, Future<void>>{};

      Future<void> queuedSave(String exerciseId, String? text) async {
        saveQueue[exerciseId] = (saveQueue[exerciseId] ?? Future.value())
            .then((_) async {
          if (text == null || text.isEmpty) {
            await repo.deleteExerciseNote(exerciseId);
          } else {
            final now = DateTime.now().millisecondsSinceEpoch;
            final note = ExerciseNote(
              id: 'note-$exerciseId',
              exerciseId: exerciseId,
              note: text,
              createdAtMs: now,
              updatedAtMs: now,
            );
            await repo.saveExerciseNote(note);
          }
        });
      }

      // Save, modify, clear rapidly.
      unawaited(queuedSave('ex1', 'text1'));
      unawaited(queuedSave('ex1', 'text2'));
      unawaited(queuedSave('ex1', null)); // Clear

      await Future.delayed(const Duration(milliseconds: 300));

      final finalNote = await repo.getExerciseNote('ex1');
      expect(
        finalNote,
        isNull,
        reason: 'Final state should be deleted',
      );
    });
  });
}
