// Plan 232 P1 — saving an edited workout never turns unstarted rounds into
// done ones.
//
// Edit Session's Save runs `normalizeRoundsToFinished()`, which used to finish
// EVERY round that was not finished at its planned duration, so saving an edit
// of a note invented rounds and minutes that were never done. After plan 232
// only rounds that were really started (running or paused) are finished; a
// round that was never started stays never started.
//
// Scenarios S-23201..S-23204 of
// `docs/plans/2026-11-17-232-edit-save-keeps-unstarted-rounds-plan/2026-11-17-232-edit-save-keeps-unstarted-rounds-plan.md`.
// Both stores must end identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/repository_harness.dart';

void main() {
  const sessionId = 'sess-232';
  const effortId = 'eff-232';

  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — save keeps unstarted rounds (plan 232)', () {
      late WorkoutRepository repo;
      late WorkoutState state;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      /// A finished session holding one round exercise of [rounds]: the shape
      /// Edit Session opens (S-22403's finished-round fixture, stored).
      Future<WorkoutState> seedSessionWithRounds(
        List<RoundInstance> rounds,
      ) async {
        await seedSession(repo, sessionId: sessionId);
        await seedExercise(repo, id: 'ex-232', name: 'BJJ');
        await seedRoundEffort(
          repo,
          segmentId: 'seg-$sessionId',
          effortId: effortId,
          exerciseId: 'ex-232',
          rounds: rounds,
        );
        return loadState(repo, sessionId);
      }

      /// One round finished at 60 s, two planned rounds nobody started.
      List<RoundInstance> threeRounds() => [
        roundInstance(effortId, 0, durationSecs: 60),
        roundInstance(
          effortId,
          1,
          durationSecs: 180,
          state: RoundState.notStarted,
          completed: false,
          startedAtMs: 0,
        ),
        roundInstance(
          effortId,
          2,
          durationSecs: 180,
          state: RoundState.notStarted,
          completed: false,
          startedAtMs: 0,
        ),
      ];

      test('S-23201 saving an edit leaves the never-started rounds alone',
          () async {
        state = await seedSessionWithRounds(threeRounds());

        await state.normalizeRoundsToFinished();
        expect(state.error, isNull, reason: 'the edit is saved');

        final rounds = state.getRoundsForEffort(effortId);
        expect(rounds[0].state, RoundState.finished);
        expect(rounds[0].actualDurationSecs, 60);
        expect(rounds[1].state, RoundState.notStarted);
        expect(rounds[2].state, RoundState.notStarted);
      });

      test('S-23202 a running and a paused round are still finished at their '
          'planned length', () async {
        state = await seedSessionWithRounds([
          roundInstance(effortId, 0, durationSecs: 60),
          roundInstance(
            effortId,
            1,
            durationSecs: 180,
            state: RoundState.active,
            completed: false,
          ),
          // A paused round holds the instant it froze at.
          roundInstance(
            effortId,
            2,
            durationSecs: 180,
            state: RoundState.paused,
            completed: false,
          ).copyWith(pausedAtMs: fixtureStart + 150000),
        ]);

        await state.normalizeRoundsToFinished();
        expect(state.error, isNull, reason: 'the edit is saved');

        final rounds = state.getRoundsForEffort(effortId);
        expect(rounds[1].state, RoundState.finished);
        expect(rounds[1].actualDurationSecs, 180);
        expect(rounds[2].state, RoundState.finished);
        expect(rounds[2].actualDurationSecs, 180);
      });

      test('S-23203 the summary does not grow over the unstarted rounds',
          () async {
        state = await seedSessionWithRounds(threeRounds());

        final before = state.computeSessionSummary();
        expect(before.totalRounds, 1, reason: 'only the round really done');
        expect(before.totalRoundDurationMs, 60000);

        await state.normalizeRoundsToFinished();

        final after = state.computeSessionSummary();
        expect(after.totalRounds, before.totalRounds);
        expect(after.totalRoundDurationMs, before.totalRoundDurationMs);
      });

      test('S-23204 after the save a fresh state over the same store still '
          'reads the unstarted rounds', () async {
        state = await seedSessionWithRounds(threeRounds());

        await state.normalizeRoundsToFinished();
        final fresh = await loadState(await harness.restart(), sessionId);
        final rounds = fresh.getRoundsForEffort(effortId);
        expect(rounds[0].state, RoundState.finished);
        expect(rounds[1].state, RoundState.notStarted);
        expect(rounds[2].state, RoundState.notStarted);
      });
    });
  }
}
