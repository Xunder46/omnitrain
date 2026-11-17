// Plan 220 P1 — Finish with nothing logged discards the workout (state side).
//
// `finishWouldSaveNothing()` on the state: true when the session is live, no
// exercise counts ([completedExerciseCount] is 0), the wrist does not run it
// and no wrist row is staged for it; false once anything is logged or started,
// and always false for a workout the watch took part in.
//
// Scenario S-22001 of
// `docs/plans/2026-11-17-220-finish-with-nothing-logged-discards-plan/2026-11-17-220-finish-with-nothing-logged-discards-plan.md`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — finishWouldSaveNothing', () {
      late WorkoutRepository repo;
      late WorkoutState state;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      /// A live (open) session with [id]/'name' seeded, so the effort can be
      /// added the way a real workout starts. `seedSession` writes an ended
      /// session, which `endSession` refuses to touch.
      Future<void> openLiveSession({bool Function(String)? wristRuns}) async {
        state = WorkoutState(repo, wristRunsSession: wristRuns);
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

      test('S-22001 a typed-but-unlogged set alone is nothing done', () async {
        await openLiveSession();
        final xId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(xId, 0, reps: 3, weight: 100.0);

        expect(await state.finishWouldSaveNothing(), isTrue);

        await logSet(xId, 0);
        expect(await state.finishWouldSaveNothing(), isFalse);
      });

      test('S-22001 a started timed exercise is something done', () async {
        await openLiveSession();
        final timedId = await seedAndAdd(
          'ex-run',
          'Easy Run',
          effortKindOverride: 'timed',
        );

        expect(await state.finishWouldSaveNothing(), isTrue);

        await state.startTimedEntry(timedId, 0);
        expect(await state.finishWouldSaveNothing(), isFalse);
      });

      test('S-22001 a session the wrist runs is never nothing done', () async {
        await openLiveSession(wristRuns: (_) => true);
        final xId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(xId, 0, reps: 3, weight: 100.0);

        expect(await state.finishWouldSaveNothing(), isFalse);
      });

      test('S-22001 a staged wrist row is never nothing done', () async {
        await openLiveSession();
        final xId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
        await fillSet(xId, 0, reps: 3, weight: 100.0);
        await repo.stageWatchInboxEntry(
          WatchInboxEntry(
            entryId: 'e-late',
            watchSessionId: state.currentSession!.id,
            kind: WatchInboxEntry.kindSet,
            origin: WatchInboxEntry.originWatch,
            payload: {
              'eventId': 'e-late',
              'entryId': 'e-late',
              'kind': 'set',
              'reps': 5,
              'loadKg': 60,
            },
            receivedAtMs: fixtureStart,
          ),
        );

        expect(await state.finishWouldSaveNothing(), isFalse);
      });
    });
  }
}
