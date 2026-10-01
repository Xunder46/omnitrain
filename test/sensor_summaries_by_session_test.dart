// Stats PR 4b, Phase 1 — the bulk sensor-summary read (D-513).
//
// Plan: `docs/plans/2026-10-01-04b-stats-pr4b-instruments-data-plan/`.
//
// `getSensorSummariesBySession` returns every summary on the device grouped by
// session, each group in the same order `getSensorSummariesForSession` returns.
// Both repository implementations must agree value for value, so every
// scenario runs once per implementation through `harnessFactories`.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// S-1002's population, in the order it is written to the store — which is
/// deliberately not the order the read must return. `s-y` holds no summary, so
/// it is never written and must not appear as a key.
///
/// Built once: `fixtureStart` is a clock reading, so a second construction
/// would stamp different `createdAtMs` values.
final List<SensorSummary> _population = [
  sensorSummary(
    sessionId: 's-x',
    scope: SensorSummary.scopeTimedInstance,
    targetId: 't2',
    windowStartMs: 2000,
    windowEndMs: 2060,
    steps: 600,
  ),
  sensorSummary(
    sessionId: 's-x',
    scope: SensorSummary.scopeTimedInstance,
    targetId: 't1',
    windowStartMs: 1000,
    windowEndMs: 1060,
    steps: 300,
  ),
  sensorSummary(
    sessionId: 's-x',
    scope: SensorSummary.scopeSession,
    targetId: 's-x',
    windowStartMs: 500,
    windowEndMs: 560,
    avgHeartRateBpm: 120,
  ),
  sensorSummary(
    sessionId: 's-x',
    scope: SensorSummary.scopeEffort,
    targetId: 'e1',
    windowStartMs: 1000,
    windowEndMs: 1060,
    avgHeartRateBpm: 130,
  ),
  sensorSummary(
    sessionId: 's-z',
    scope: SensorSummary.scopeRoundInstance,
    targetId: 'r1',
    windowStartMs: 100,
    windowEndMs: 160,
    avgHeartRateBpm: 146,
  ),
];

/// The same population as the read must return it: keys are the sessions that
/// hold a summary, each list in `SensorSummary.scopes` order, then
/// `windowStartMs`, then `targetId`.
Map<String, List<SensorSummary>> _expected() {
  final byKey = {
    for (final summary in _population)
      '${summary.scope}|${summary.targetId}': summary,
  };
  return {
    's-x': [
      byKey['${SensorSummary.scopeSession}|s-x']!,
      byKey['${SensorSummary.scopeEffort}|e1']!,
      byKey['${SensorSummary.scopeTimedInstance}|t1']!,
      byKey['${SensorSummary.scopeTimedInstance}|t2']!,
    ],
    's-z': [byKey['${SensorSummary.scopeRoundInstance}|r1']!],
  };
}

/// Each group as the `scope|targetId` list the read must produce, so two reads
/// can be compared by shape alone.
Map<String, List<String>> _shape(
  Map<String, List<SensorSummary>> bySession,
) => {
  for (final entry in bySession.entries)
    entry.key: [
      for (final summary in entry.value) '${summary.scope}|${summary.targetId}',
    ],
};

Future<void> _seedPopulation(WorkoutRepository repo) async {
  for (final summary in _population) {
    await seedSensorSummary(repo, summary);
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Sensor summaries by session — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test(
        'S-1002 groups by session and orders like the single-session read',
        () async {
          await _seedPopulation(repo);

          final bySession = await repo.getSensorSummariesBySession();

          // `s-y` holds no summary, so it has no key.
          expect(bySession.keys.toSet(), {'s-x', 's-z'});
          expect(_shape(bySession), _shape(_expected()));
          expect(
            _shape({'s-x': await repo.getSensorSummariesForSession('s-x')}),
            _shape({'s-x': _expected()['s-x']!}),
          );
        },
      );

      test('S-1003 no summaries at all is an empty map', () async {
        await seedSession(repo, sessionId: 's-empty');
        await seedExercise(repo, id: 'ex-empty', name: 'Empty');

        final bySession = await repo.getSensorSummariesBySession();

        expect(bySession, isEmpty);
      });

      test('S-1004 Hive and Mock agree value-for-value', () async {
        await _seedPopulation(repo);

        final bySession = await repo.getSensorSummariesBySession();
        final expected = _expected();

        expect(bySession.keys.toSet(), expected.keys.toSet());
        for (final sessionId in expected.keys) {
          expect(
            bySession[sessionId]!.map((s) => s.toMap()).toList(),
            expected[sessionId]!.map((s) => s.toMap()).toList(),
            reason: 'session $sessionId must round trip value for value',
          );
        }
      });
    });
  }
}
