// Plan 230 P1 — a confirmed "Start New Session?" really discards the running
// workout (state side).
//
// `discardUnfinishedSession` really deletes a workout that is still open (the
// store row goes, like the Discard button); a finished session shown in the
// slot is only released, never deleted. Scenarios S-23001..S-23003 of
// `docs/plans/2026-11-17-230-start-new-really-discards-plan/`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — start new really discards', () {
      late WorkoutRepository repo;
      late WorkoutState state;

      setUp(() async {
        repo = await harness.open();
        state = WorkoutState(repo);
      });
      tearDown(() async => await harness.close());

      /// Seeds a finished session A through a second state over the same
      /// repo, the way a past workout was stored. Returns its id.
      Future<String> seedFinishedSession(String name) async {
        // The short delay keeps the two ms-based ids apart.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final builder = WorkoutState(repo);
        await builder.createNewSession(title: name);
        await builder.endSession(writeToHealth: false);
        return builder.currentSession!.id;
      }

      /// Starts a running workout R on [state] with one logged set, left open.
      Future<String> startRunningWorkout() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await seedExercise(
          repo,
          id: 'ex-running',
          name: 'Barbell Back Squat',
          capabilities: ['load'],
        );
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == 'ex-running',
        );
        await state.createNewSession(title: 'R');
        final sessionId = state.currentSession!.id;
        final effortId = await state.addExerciseToSession(exercise);
        await state.addEntry(effortId);
        await state.updateEntryValue(effortId, 0, 'reps', 3);
        await state.updateEntryValue(effortId, 0, 'weight', 100.0);
        return sessionId;
      }

      test(
        'S-23001 a confirmed Start New over a running workout deletes the row: '
        'relaunch finds nothing',
        () async {
          final runningId = await startRunningWorkout();
          expect((await repo.getSession(runningId))!.endedAtMs, isNull);

          await state.discardUnfinishedSession();
          expect(state.currentSession, isNull);
          expect(await repo.getSession(runningId), isNull);

          // The new workout N is created with a logged set and finished.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await seedExercise(
            repo,
            id: 'ex-n',
            name: 'Row',
            capabilities: ['load'],
          );
          final row = (await repo.getExercises()).firstWhere(
            (e) => e.id == 'ex-n',
          );
          await state.createNewSession(title: 'N');
          final effortId = await state.addExerciseToSession(row);
          await state.addEntry(effortId);
          await state.updateEntryValue(effortId, 0, 'reps', 5);
          await state.endSession(writeToHealth: false);

          // Relaunch: a fresh state over the same store.
          final freshRepo = await harness.restart();
          final fresh = WorkoutState(freshRepo);
          expect(await freshRepo.getSession(runningId), isNull);
          expect(await fresh.checkForInProgressSession(), isNull);
        },
      );

      test(
        'S-23002 a finished session in the slot is only released, never deleted',
        () async {
          final finishedId = await seedFinishedSession('A');
          await state.loadHistoricalSession(finishedId);
          expect(state.currentSession!.id, finishedId);
          expect(state.currentSession!.endedAtMs, isNotNull);

          await state.discardUnfinishedSession();
          expect(state.currentSession, isNull);

          final stored = await repo.getSession(finishedId);
          expect(stored, isNotNull);
          expect(stored!.endedAtMs, isNotNull);
        },
      );

      test(
        'S-23003 no current session: the call is a harmless no-op',
        () async {
          expect(state.currentSession, isNull);
          await state.discardUnfinishedSession();
          expect(state.currentSession, isNull);
        },
      );
    });
  }
}
