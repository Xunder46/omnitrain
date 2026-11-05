// Plan 38d (P1) — a changed round length applies to the later unstarted rounds.
//
// The rule lives behind `WorkoutRepository`, so `MockWorkoutRepository` and
// `HiveWorkoutRepository` must persist the same `plannedDurationSecs` values:
// the round at `fromIndex` is written unless it is finished, every later round
// only while it has not started, and a running round keeps the length it
// started with. The values are read back from the store, not from the cache.
//
// S-4412 of
// `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// The planned lengths the store holds for [effortId], in round order.
Future<List<int>> _storedPlannedSecs(
  WorkoutRepository repo,
  String effortId,
) async {
  final rounds = [...await repo.getRoundInstances(effortId)]
    ..sort((a, b) => a.roundIndex.compareTo(b.roundIndex));
  return rounds.map((round) => round.plannedDurationSecs).toList();
}

/// A `sports` session holding one three-round effort on `e-bag`.
Future<void> _seedThreeRounds(
  WorkoutRepository repo, {
  required RoundState firstRoundState,
  int firstRoundSecs = 180,
}) async {
  await seedSession(repo, sessionId: 's-4412', modality: 'sports');
  await seedExercise(
    repo,
    id: 'ex-bag',
    name: 'Heavy Bag',
    capabilities: ['rounds'],
  );
  await seedRoundEffort(
    repo,
    segmentId: 'seg-s-4412',
    effortId: 'e-bag',
    exerciseId: 'ex-bag',
    rounds: [
      roundInstance(
        'e-bag',
        0,
        durationSecs: firstRoundSecs,
        state: firstRoundState,
      ),
      roundInstance('e-bag', 1, state: RoundState.notStarted),
      roundInstance('e-bag', 2, state: RoundState.notStarted),
    ],
  );
}

void _parityBodies(String name, RepositoryHarness Function() makeHarness) {
  late RepositoryHarness harness;
  late WorkoutRepository repo;

  setUp(() async {
    harness = makeHarness();
    repo = await harness.open();
  });

  tearDown(() async {
    await harness.close();
  });

  String titled(String base) => '$base ($name)';

  test(
    titled('S-4412 a finished round keeps its length, the later ones follow'),
    () async {
      await _seedThreeRounds(
        repo,
        firstRoundState: RoundState.finished,
        firstRoundSecs: 240,
      );
      final state = await loadState(repo, 's-4412');

      final touched = await state.updatePlannedDurationFrom(
        'e-bag',
        1,
        120,
      );

      expect(touched, [1, 2]);
      expect(await _storedPlannedSecs(repo, 'e-bag'), [240, 120, 120]);
    },
  );

  test(titled('S-4412 a running round keeps the length it started with'), () async {
    await _seedThreeRounds(repo, firstRoundState: RoundState.notStarted);
    final state = await loadState(repo, 's-4412');

    await state.startRound('e-bag', 1);
    final touched = await state.updatePlannedDurationFrom('e-bag', 0, 300);

    expect(touched, [0, 2]);
    expect(await _storedPlannedSecs(repo, 'e-bag'), [300, 180, 300]);
  });
}

void main() {
  group('Mock', () {
    _parityBodies('Mock', MockRepositoryHarness.new);
  });
  group('Hive', () {
    _parityBodies('Hive', HiveRepositoryHarness.new);
  });
}
