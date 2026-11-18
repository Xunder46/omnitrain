// Plan 229 P1 — Opening a past session never loses the running workout
// (state side).
//
// `viewHistoricalSession` remembers a running workout's id while a finished
// session takes the shared session slot, and `resumeSuspendedLiveSession`
// puts it back when the view closes. Scenarios S-22901..S-22905 and S-22908 of
// `docs/plans/2026-11-17-229-past-session-keeps-the-running-workout-plan/`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — past session keeps the running workout', () {
      late WorkoutRepository repo;
      late WorkoutState state;

      setUp(() async {
        repo = await harness.open();
        state = WorkoutState(repo);
      });
      tearDown(() async => await harness.close());

      /// A finished session holding one logged set, seeded through its own
      /// state over the same repo the way a past workout was stored. Returns
      /// its id. The short delay keeps two seeded ids apart: the id is the
      /// create time in milliseconds.
      Future<String> seedFinishedSession(String id) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await seedExercise(
          repo,
          id: 'ex-$id',
          name: 'Squat $id',
          capabilities: ['load'],
        );
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == 'ex-$id',
        );
        final builder = WorkoutState(repo);
        await builder.createNewSession();
        final sessionId = builder.currentSession!.id;
        final effortId = await builder.addExerciseToSession(exercise);
        await builder.updateEntryValue(effortId, 0, 'reps', 5);
        await builder.updateEntryValue(effortId, 0, 'weight', 80.0);
        await builder.recordRestStart(effortId, 1);
        await builder.endSession(writeToHealth: false);
        return sessionId;
      }

      /// Starts a running workout on [state]: two sets, the first logged
      /// (3 x 100) with its rest at entry 1, left open as the helper leaves
      /// it. Returns the session and effort ids.
      Future<({String sessionId, String effortId})>
      startRunningWorkout() async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await seedExercise(
          repo,
          id: 'ex-running',
          name: 'Barbell Back Squat',
          capabilities: ['load'],
        );
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == 'ex-running',
        );
        await state.createNewSession();
        final sessionId = state.currentSession!.id;
        final effortId = await state.addExerciseToSession(exercise);
        await state.addEntry(effortId);
        await state.updateEntryValue(effortId, 0, 'reps', 3);
        await state.updateEntryValue(effortId, 0, 'weight', 100.0);
        await state.recordRestStart(effortId, 1);
        return (sessionId: sessionId, effortId: effortId);
      }

      test(
        'S-22901 viewing a past session then resuming puts the running workout back',
        () async {
          final pastId = await seedFinishedSession('past');
          final run = await startRunningWorkout();
          final restBefore = state.getEntryRests(run.effortId).single;

          await state.viewHistoricalSession(pastId);
          expect(state.currentSession!.id, pastId);
          expect(state.currentSession!.endedAtMs, isNotNull);
          expect(state.hasActiveSession, isFalse);

          await state.resumeSuspendedLiveSession();
          expect(state.currentSession!.id, run.sessionId);
          expect(state.currentSession!.endedAtMs, isNull);
          expect(state.hasActiveSession, isTrue);
          final exercises = state.getExercisesWithEntries();
          expect(exercises.single['entries'], hasLength(2));
          final rest = state.getEntryRests(run.effortId).single;
          expect(rest.entryIndex, restBefore.entryIndex);
          expect(rest.restEndMs, isNull);
        },
      );

      test(
        'S-22902 no running workout: the resume leaves the past session loaded',
        () async {
          final pastId = await seedFinishedSession('past');
          final otherId = await seedFinishedSession('other');

          // No running workout: the current session is the finished `other`.
          await state.loadHistoricalSession(otherId);

          await state.viewHistoricalSession(pastId);
          expect(state.currentSession!.id, pastId);

          await state.resumeSuspendedLiveSession();
          expect(state.currentSession!.id, pastId);
        },
      );

      test(
        'S-22903 a resume never reloads a workout the store has ended',
        () async {
          final pastId = await seedFinishedSession('past');
          final run = await startRunningWorkout();

          await state.viewHistoricalSession(pastId);

          // The wrist ends R meanwhile. The simplest way that works on both
          // stores: a third state loads R the way the app does and ends it.
          final ender = WorkoutState(repo);
          await ender.loadHistoricalSession(run.sessionId);
          await ender.endSession(writeToHealth: false);

          await state.resumeSuspendedLiveSession();
          expect(state.currentSession!.id, pastId);
          expect(state.hasActiveSession, isFalse);
        },
      );

      test(
        'S-22904 viewing a second past session keeps the running workout remembered',
        () async {
          final aId = await seedFinishedSession('a');
          final bId = await seedFinishedSession('b');
          final run = await startRunningWorkout();

          await state.viewHistoricalSession(aId);
          await state.viewHistoricalSession(bId);
          expect(state.currentSession!.id, bId);

          await state.resumeSuspendedLiveSession();
          expect(state.currentSession!.id, run.sessionId);
          expect(state.hasActiveSession, isTrue);
        },
      );

      test('S-22908 a resume that already happened is spent: a second one '
          'reloads nothing', () async {
        final aId = await seedFinishedSession('a');
        final run = await startRunningWorkout();

        await state.viewHistoricalSession(aId);
        await state.resumeSuspendedLiveSession();
        expect(state.currentSession!.id, run.sessionId);

        // The user opens the past session by a path that does not remember
        // anything (a plain load), then a stray second resume arrives.
        await state.loadHistoricalSession(aId);
        await state.resumeSuspendedLiveSession();
        expect(state.currentSession!.id, aId);
      });

      test(
        'S-22905 a resume never replaces another open session that became current',
        () async {
          final pastId = await seedFinishedSession('past');
          final run = await startRunningWorkout();

          await state.viewHistoricalSession(pastId);

          // The adoption path: another open session C becomes current. The
          // short delay keeps C's create-time id apart from R's.
          await Future<void>.delayed(const Duration(milliseconds: 2));
          await state.createNewSession();
          final adoptedId = state.currentSession!.id;
          expect(adoptedId, isNot(run.sessionId));

          await state.resumeSuspendedLiveSession();
          expect(state.currentSession!.id, adoptedId);
          expect(state.currentSession!.endedAtMs, isNull);
        },
      );
    });
  }
}
