// Plan 217 P1 — the state counts the exercises the user did.
//
// `completedExerciseCount()` on the state: a `set` exercise counts when at
// least one of its sets is logged (a skip-marked set alone does not count);
// a `timed`, `drill` or `round` exercise counts when any of its instances has
// been started. The count is read while the session is open, never after
// `endSession`.
//
// Scenarios S-21701..S-21703 of
// `docs/plans/2026-11-16-217-finish-dialog-counts-what-you-did-plan/2026-11-16-217-finish-dialog-counts-what-you-did-plan.md`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — completedExerciseCount', () {
      late WorkoutRepository repo;
      late WorkoutState state;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      /// A live (open) session with [id]/'name' seeded, so the effort can be
      /// added the way a real workout starts. `seedSession` writes an ended
      /// session, which `endSession` refuses to touch.
      Future<void> openLiveSession() async {
        state = WorkoutState(repo);
        await state.createNewSession();
      }

      Future<String> seedAndAdd(
        String id,
        String name, {
        String? effortKindOverride,
      }) async {
        await seedExercise(
          repo,
          id: id,
          name: name,
          capabilities: ['load'],
        );
        final exercise = (await repo.getExercises()).firstWhere(
          (e) => e.id == id,
        );
        return state.addExerciseToSession(
          exercise,
          effortKindOverride: effortKindOverride,
        );
      }

      /// Fills the set at [i] with [reps] x [weight], the values the user
      /// typed into the logger.
      Future<void> fillSet(
        String effortId,
        int i, {
        required int reps,
        required double weight,
      }) async {
        await state.updateEntryValue(effortId, i, 'reps', reps);
        await state.updateEntryValue(effortId, i, 'weight', weight);
      }

      /// LOGS the set at [i] the way the screen does: a rest at position + 1.
      Future<void> logSet(String effortId, int i) =>
          state.recordRestStart(effortId, i + 1);

      test('S-21701 an exercise counts once a set is logged', () async {
        await openLiveSession();
        final xId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await state.addEntry(xId);
        await state.addEntry(xId);
        await fillSet(xId, 0, reps: 3, weight: 100.0);
        await logSet(xId, 0);
        final yId = await seedAndAdd('ex-row', 'Seated Row');
        await state.addEntry(yId);
        await state.addEntry(yId);

        expect(state.completedExerciseCount(), 1);

        await fillSet(yId, 1, reps: 8, weight: 40.0);
        await logSet(yId, 1);
        expect(state.completedExerciseCount(), 2);
      });

      test('S-21702 a skipped set does not make an exercise count', () async {
        await openLiveSession();
        final xId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(xId, 0, reps: 3, weight: 100.0);
        await logSet(xId, 0);
        final yId = await seedAndAdd('ex-row', 'Seated Row');
        await state.markSetSkipped(yId, 0);

        expect(state.completedExerciseCount(), 1);
      });

      test('S-21703 a started timed or round exercise counts, a never-started '
          'one does not', () async {
        await openLiveSession();
        final timedId = await seedAndAdd(
          'ex-run',
          'Easy Run',
          effortKindOverride: 'timed',
        );
        final roundId = await seedAndAdd(
          'ex-bag',
          'Heavy Bag',
          effortKindOverride: 'round',
        );

        expect(state.completedExerciseCount(), 0);

        await state.startTimedEntry(timedId, 0);
        expect(state.completedExerciseCount(), 1);

        await state.startRound(roundId, 0);
        expect(state.completedExerciseCount(), 2);
      });
    });
  }
}
