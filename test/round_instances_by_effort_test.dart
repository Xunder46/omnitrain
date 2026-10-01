// Stats PR 4a, Phase 1 — the bulk round-instance read.
//
// `getRoundInstances(String effortId)` reads one effort at a time, and the
// Sports native value needs every round on the device in one pass. The bulk
// read is the exact counterpart of `getTimedInstancesByEffort()`: grouped by
// `effortId`, each group in `roundIndex` order, and an effort with no instances
// absent rather than present as an empty list.
//
// Scenarios S-901, S-902 and S-903 of
// `docs/plans/2026-09-30-04a-stats-pr4a-records-and-exercise-progress-plan.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// S-901's population: `effort-a` holds three instances written out of order on
/// one completed session, `effort-b` holds one on another, and `effort-empty`
/// holds none.
Future<void> seedRoundPopulation(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-901a', modality: 'sports');
  await seedSession(repo, sessionId: 's-901b', modality: 'sports');
  await seedExercise(repo, id: 'ex-bjj', name: 'BJJ');

  await seedRoundEffort(
    repo,
    segmentId: 'seg-s-901a',
    effortId: 'effort-a',
    exerciseId: 'ex-bjj',
    rounds: [
      roundInstance('effort-a', 2),
      roundInstance('effort-a', 0),
      roundInstance('effort-a', 1),
    ],
  );
  await seedRoundEffort(
    repo,
    segmentId: 'seg-s-901b',
    effortId: 'effort-b',
    exerciseId: 'ex-bjj',
    rounds: [roundInstance('effort-b', 0)],
  );
  await repo.createEffort(
    SegmentEffort(
      id: 'effort-empty',
      segmentId: 'seg-s-901b',
      orderIndex: 1,
      effortKind: 'round',
      exerciseId: 'ex-bjj',
      createdAtMs: fixtureStart,
      updatedAtMs: fixtureStart,
    ),
  );
}

/// The keys, and each group's `roundIndex`-then-id sequence, as a value two
/// implementations can be compared by.
Map<String, List<String>> shapeOf(Map<String, List<RoundInstance>> grouped) => {
  for (final entry in grouped.entries)
    entry.key: [
      for (final round in entry.value) '${round.roundIndex}:${round.id}',
    ],
};

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — the bulk round read', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'S-901 groups by effort and orders each group by roundIndex',
        () async {
          await seedRoundPopulation(repo);

          final grouped = await repo.getRoundInstancesByEffort();

          expect(grouped.keys.toSet(), {'effort-a', 'effort-b'});
          expect(
            [for (final round in grouped['effort-a']!) round.roundIndex],
            [0, 1, 2],
          );
          expect(
            [for (final round in grouped['effort-a']!) round.id],
            ['ri-effort-a-0', 'ri-effort-a-1', 'ri-effort-a-2'],
          );
          expect(grouped['effort-b'], hasLength(1));
          expect(grouped['effort-b']!.single.id, 'ri-effort-b-0');
        },
      );

      test('S-902 an effort with no round instances has no key', () async {
        await seedRoundPopulation(repo);

        final grouped = await repo.getRoundInstancesByEffort();

        expect(grouped.containsKey('effort-empty'), isFalse);
      });
    });
  }

  test('S-903 Hive and Mock agree, a restart included', () async {
    final fresh = <String, Map<String, List<String>>>{};
    final afterRestart = <String, Map<String, List<String>>>{};

    for (final factory in harnessFactories) {
      final harness = factory();
      final repo = await harness.open();
      await seedRoundPopulation(repo);
      fresh[harness.name] = shapeOf(await repo.getRoundInstancesByEffort());
      final reopened = await harness.restart();
      afterRestart[harness.name] = shapeOf(
        await reopened.getRoundInstancesByEffort(),
      );
      await harness.close();
    }

    expect(afterRestart['Mock'], fresh['Mock']);
    expect(afterRestart['Hive'], fresh['Hive']);
    expect(fresh['Hive'], fresh['Mock']);
    expect(afterRestart['Hive'], afterRestart['Mock']);
  });
}
