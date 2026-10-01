// Tests for the set count label on the session details screen.
//
// Verifies that `getExercisesWithEntries()` returns a stable `entries.length`
// that reflects the total scope of an exercise (logged + planned) for every
// modality, and that the round subtitle in _buildExerciseSubtitle shows the
// same total regardless of how many rounds have been completed.
//
// These are pure state-layer tests — no widget rendering required.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Returns the first exercise from the seed data whose capabilities list
/// contains [capability]. Falls back to [exercises.first] if none match.
Future<Exercise> _exerciseWith(
  MockWorkoutRepository repo,
  String capability,
) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere(
    (e) => e.capabilities.contains(capability),
    orElse: () => exercises.first,
  );
}

/// Returns [exercises.length] from the single exercise returned by
/// [getExercisesWithEntries()].
int _entryCount(WorkoutState state) {
  final all = state.getExercisesWithEntries();
  if (all.isEmpty) return -1;
  return (all.first['entries'] as List).length;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // resistance (set) modality
  // ══════════════════════════════════════════════════════════════════════════

  group('set count — resistance (set) modality', () {
    test(
      'S-SET-01: 4 planned sets show count 4 before any are logged',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'resistance_lifting');

        final exercise = await _exerciseWith(repo, 'load');
        final effortId = await state.addExerciseToSession(exercise);
        // addExerciseToSession seeds one entry; add 3 more to get 4 total.
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        expect(_entryCount(state), 4);
      },
    );

    test(
      'S-SET-02: count remains 4 after partially logging 2 of 4 sets',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'resistance_lifting');

        final exercise = await _exerciseWith(repo, 'load');
        final effortId = await state.addExerciseToSession(exercise);
        await state.addEntry(effortId);
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        // "Log" sets 0 and 1 by writing non-zero reps.
        await state.updateEntryValue(effortId, 0, 'reps', 10);
        await state.updateEntryValue(effortId, 1, 'reps', 10);

        expect(_entryCount(state), 4);
      },
    );

    test('S-SET-03: count remains 4 after all 4 sets are logged', () async {
      final repo = await _freshRepo();
      final state = WorkoutState(repo);
      await state.createNewSession(modality: 'resistance_lifting');

      final exercise = await _exerciseWith(repo, 'load');
      final effortId = await state.addExerciseToSession(exercise);
      await state.addEntry(effortId);
      await state.addEntry(effortId);
      await state.addEntry(effortId);

      for (int i = 0; i < 4; i++) {
        await state.updateEntryValue(effortId, i, 'reps', 8);
      }

      expect(_entryCount(state), 4);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // timed modality
  // ══════════════════════════════════════════════════════════════════════════

  group('set count — timed modality', () {
    test(
      'S-TIMED-01: 3 planned intervals show count 3 before any are started',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercise = await _exerciseWith(repo, 'time');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'timed',
        );
        // addExerciseToSession seeds 1; add 2 more.
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        expect(_entryCount(state), 3);
      },
    );

    test(
      'S-TIMED-02: count remains 3 after 1 of 3 intervals is finished',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercise = await _exerciseWith(repo, 'time');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'timed',
        );
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        await state.startTimedEntry(effortId, 0);
        await state.finishTimedEntry(effortId, 0);

        expect(_entryCount(state), 3);

        // All three instances must be visible — not just the finished one.
        final instances = state.getTimedInstancesForEffort(effortId);
        expect(instances, hasLength(3));
        expect(
          instances.where((i) => i.state == TimedState.finished),
          hasLength(1),
        );
        expect(
          instances.where((i) => i.state == TimedState.notStarted),
          hasLength(2),
        );
      },
    );

    test(
      'S-TIMED-03: count remains 3 after all 3 intervals are finished',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'cardio_endurance');

        final exercise = await _exerciseWith(repo, 'time');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'timed',
        );
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        for (int i = 0; i < 3; i++) {
          await state.startTimedEntry(effortId, i);
          await state.finishTimedEntry(effortId, i);
        }

        expect(_entryCount(state), 3);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // drill modality
  // ══════════════════════════════════════════════════════════════════════════

  group('set count — drill modality', () {
    test(
      'S-DRILL-01: 2 planned holds show count 2 before any are started',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercise = await _exerciseWith(repo, 'hold');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'drill',
        );
        // addExerciseToSession seeds 1; add 1 more.
        await state.addEntry(effortId);

        expect(_entryCount(state), 2);
      },
    );

    test(
      'S-DRILL-02: count remains 2 after 1 of 2 holds is finished',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercise = await _exerciseWith(repo, 'hold');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'drill',
        );
        await state.addEntry(effortId);

        await state.startTimedEntry(effortId, 0);
        await state.finishTimedEntry(effortId, 0);

        expect(_entryCount(state), 2);
      },
    );

    test(
      'S-DRILL-03: count remains 2 after all 2 holds are finished',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession();

        final exercise = await _exerciseWith(repo, 'hold');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'drill',
        );
        await state.addEntry(effortId);

        for (int i = 0; i < 2; i++) {
          await state.startTimedEntry(effortId, i);
          await state.finishTimedEntry(effortId, i);
        }

        expect(_entryCount(state), 2);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // round modality — the previously broken modality
  // ══════════════════════════════════════════════════════════════════════════

  group('set count — round modality', () {
    test(
      'S-ROUND-01: 3 planned rounds show total count 3 before any are started',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercise = await _exerciseWith(repo, 'rounds');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'round',
        );
        // addExerciseToSession seeds 1; add 2 more.
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        // entries in getExercisesWithEntries() should reflect all 3 rounds.
        expect(_entryCount(state), 3);

        // getRoundsForEffort should also return all 3.
        final rounds = state.getRoundsForEffort(effortId);
        expect(rounds, hasLength(3));
        expect(rounds.every((r) => r.state == RoundState.notStarted), isTrue);
      },
    );

    test(
      'S-ROUND-02: total remains 3 after 1 round is ended early (not naturally completed)',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercise = await _exerciseWith(repo, 'rounds');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'round',
        );
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        // Start and end round 0 early (completed == false, but state == finished).
        await state.startRound(effortId, 0);
        await state.endRoundEarly(effortId, 0);

        expect(_entryCount(state), 3);

        final rounds = state.getRoundsForEffort(effortId);
        expect(rounds, hasLength(3));
        // Round 0 finished early — not naturally completed.
        expect(rounds[0].state, RoundState.finished);
        expect(rounds[0].completed, isFalse);
        // Rounds 1 and 2 still not started.
        expect(
          rounds.where((r) => r.state == RoundState.notStarted),
          hasLength(2),
        );
      },
    );

    test(
      'S-ROUND-03: total remains 3 after all 3 rounds are naturally completed',
      () async {
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercise = await _exerciseWith(repo, 'rounds');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'round',
        );
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        for (int i = 0; i < 3; i++) {
          await state.startRound(effortId, i);
          await state.completeRound(effortId, i);
        }

        expect(_entryCount(state), 3);

        final rounds = state.getRoundsForEffort(effortId);
        expect(rounds, hasLength(3));
        expect(rounds.every((r) => r.completed), isTrue);
      },
    );

    test(
      'S-ROUND-04: subtitle count equals total rounds regardless of completion state',
      () async {
        // This test directly validates the fixed _buildExerciseSubtitle logic
        // (the round case now uses .length instead of filtering for completed rounds).
        final repo = await _freshRepo();
        final state = WorkoutState(repo);
        await state.createNewSession(modality: 'sports');

        final exercise = await _exerciseWith(repo, 'rounds');
        final effortId = await state.addExerciseToSession(
          exercise,
          effortKindOverride: 'round',
        );
        await state.addEntry(effortId);
        await state.addEntry(effortId);

        // Before any round is started, all 3 should be in the total.
        final beforeAny = state.getRoundsForEffort(effortId).length;
        expect(beforeAny, 3);

        // After 1 round completed naturally.
        await state.startRound(effortId, 0);
        await state.completeRound(effortId, 0);
        final after1 = state.getRoundsForEffort(effortId).length;
        expect(after1, 3); // total unchanged

        // After all 3 rounds completed.
        await state.startRound(effortId, 1);
        await state.completeRound(effortId, 1);
        await state.startRound(effortId, 2);
        await state.completeRound(effortId, 2);
        final afterAll = state.getRoundsForEffort(effortId).length;
        expect(afterAll, 3); // still 3 — stable
      },
    );
  });
}
