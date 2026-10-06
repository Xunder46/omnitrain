// Stats PR 10b, Phase 1 — the Stats primer's seen flag: it survives a restart,
// it is independent of the Nutrition primer's flag, marking it twice writes
// once, and a hydration failure leaves the primer unseen.
//
// Scenarios S-2705, S-2706, S-2710 and S-2711 of
// `docs/plans/2026-10-04-10b-stats-pr10b-primer-sheet-plan/2026-10-04-10b-stats-pr10b-primer-sheet-plan.md`.
// The persistence cases run over `harnessFactories` so Mock and Hive end
// identical, a Hive restart included, exactly as `test/entry_identity_test.dart`
// does. Plain `test()` bodies only: a Hive write inside a widget test's
// fake-async zone never drains (D-2017).

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/nutrition/nutrition_primer_state.dart';
import 'package:omnitrain/state/stats/stats_primer_state.dart';

import 'helpers/repository_harness.dart';

/// A repository that records the preference writes it receives, so S-2710 can
/// assert `markSeen` writes the flag exactly once.
class _RecordingPreferenceRepo extends MockWorkoutRepository {
  final List<(String, bool)> writes = <(String, bool)>[];

  @override
  Future<void> setPreferenceBool(String key, bool value) async {
    writes.add((key, value));
    return super.setPreferenceBool(key, value);
  }
}

/// A repository whose preference read always fails, so S-2711 can assert the
/// conservative unseen fallback.
class _ThrowingPreferenceRepo extends MockWorkoutRepository {
  @override
  Future<bool> getPreferenceBool(
    String key, {
    bool defaultValue = false,
  }) async {
    throw StateError('simulated hydration failure');
  }
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — S-2705: the seen flag survives a restart', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'a marked-seen Stats primer is seen again after a Hive restart',
        () async {
          final state = StatsPrimerState(repo);
          await state.init();
          expect(state.shouldShowPrimer, isTrue);

          await state.markSeen();

          final fresh = StatsPrimerState(await harness.restart());
          await fresh.init();

          expect(fresh.hasSeen, isTrue);
          expect(fresh.shouldShowPrimer, isFalse);
        },
      );
    });

    group('${harness.name} — S-2706: the two primer keys are independent', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'marking the Stats primer seen leaves the Nutrition primer unseen',
        () async {
          final stats = StatsPrimerState(repo);
          await stats.init();
          final nutrition = NutritionPrimerState(repo);
          await nutrition.init();

          await stats.markSeen();

          expect(
            await repo.getPreferenceBool(StatsPrimerState.preferenceKey),
            isTrue,
          );
          expect(
            await repo.getPreferenceBool(NutritionPrimerState.preferenceKey),
            isFalse,
          );

          await nutrition.markSeen();

          expect(
            await repo.getPreferenceBool(StatsPrimerState.preferenceKey),
            isTrue,
          );
        },
      );
    });
  }

  group('S-2710: markSeen is idempotent', () {
    test('two markSeen calls write the flag once and notify once', () async {
      final repo = _RecordingPreferenceRepo();
      await repo.initialize();
      final state = StatsPrimerState(repo);
      await state.init();

      var notifications = 0;
      state.addListener(() => notifications++);

      await state.markSeen();
      await state.markSeen();

      expect(repo.writes, hasLength(1));
      expect(repo.writes.single, (StatsPrimerState.preferenceKey, true));
      expect(notifications, 1);
    });
  });

  group('S-2711: a hydration failure falls back to unseen', () {
    test('a throwing getPreferenceBool leaves the primer unseen', () async {
      final repo = _ThrowingPreferenceRepo();
      await repo.initialize();
      final state = StatsPrimerState(repo);

      await state.init();

      expect(state.shouldShowPrimer, isTrue);
      expect(state.hasSeen, isFalse);

      await state.init();

      expect(state.shouldShowPrimer, isTrue);
    });
  });
}
