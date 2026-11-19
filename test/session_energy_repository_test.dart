// Plan 134a, Phase P1 — the active energy stored for a session (D-13401,
// D-13402).
//
// One row per session, keyed by its session id, in the Hive `session_energy`
// box and in Mock's in-memory twin. Every scenario runs once per
// implementation through `harnessFactories`, so the two must agree value for
// value (S-13410); a session delete removes its row in both (S-13408).
//
// Plan: `docs/plans/2026-11-08-134-calories-burned-plan/`.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// An estimate: unrounded kcal, and the body weight it was computed with
/// (S-13402's isometric 1102 s fixture at 80 kg).
SessionEnergy _estimated(String sessionId) => SessionEnergy(
  sessionId: sessionId,
  activeKcal: 31.835555555555555,
  source: SessionEnergy.sourceEstimated,
  bodyWeightKg: 80.0,
  updatedAtMs: fixtureStart,
);

/// A watch-measured row: the watch's own number, so no weight is stored.
SessionEnergy _measured(String sessionId) => SessionEnergy(
  sessionId: sessionId,
  activeKcal: 250.4,
  source: SessionEnergy.sourceMeasured,
  updatedAtMs: fixtureStart + 1000,
);

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('Session energy — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test(
        'S-13410 putSessionEnergy stores an estimated row and '
        'getSessionEnergy reads it back unrounded',
        () async {
          await seedSession(repo, sessionId: 's-energy');
          final row = _estimated('s-energy');

          expect(await repo.putSessionEnergy(row), isTrue);

          final stored = await repo.getSessionEnergy('s-energy');
          expect(stored, isNotNull);
          expect(stored!.toMap(), row.toMap());
          expect(stored.activeKcal, 31.835555555555555);
          expect(stored.source, SessionEnergy.sourceEstimated);
          expect(stored.bodyWeightKg, 80.0);
        },
      );

      test('S-13410 a measured row replaces an estimated one', () async {
        await seedSession(repo, sessionId: 's-energy');
        await repo.putSessionEnergy(_estimated('s-energy'));

        expect(await repo.putSessionEnergy(_measured('s-energy')), isTrue);

        final stored = await repo.getSessionEnergy('s-energy');
        expect(stored!.source, SessionEnergy.sourceMeasured);
        expect(stored.activeKcal, 250.4);
        expect(stored.bodyWeightKg, isNull);
      });

      test(
        'S-13410 an estimated put over a measured row returns false and '
        'writes nothing',
        () async {
          await seedSession(repo, sessionId: 's-energy');
          await repo.putSessionEnergy(_measured('s-energy'));

          expect(await repo.putSessionEnergy(_estimated('s-energy')), isFalse);

          final stored = await repo.getSessionEnergy('s-energy');
          expect(
            stored!.source,
            SessionEnergy.sourceMeasured,
            reason: 'D-13402: measured wins over an estimate',
          );
          expect(
            stored.activeKcal,
            250.4,
            reason: 'D-13402: the refused estimate wrote nothing',
          );
          expect(stored.bodyWeightKg, isNull);
        },
      );

      test('S-13410 getSessionEnergy of a session with no row is null', () async {
        await seedSession(repo, sessionId: 's-energy');

        expect(await repo.getSessionEnergy('s-no-energy'), isNull);
      });

      test('S-13408 deleteSession removes the session\'s energy row', () async {
        await seedSession(repo, sessionId: 's-energy');
        await seedSession(repo, sessionId: 's-other');
        await repo.putSessionEnergy(_estimated('s-energy'));
        await repo.putSessionEnergy(_estimated('s-other'));

        await repo.deleteSession('s-energy');

        expect(
          await repo.getSessionEnergy('s-energy'),
          isNull,
          reason: 'D-13402: no energy row outlives its session',
        );
        expect(
          await repo.getSessionEnergy('s-other'),
          isNotNull,
          reason: 'only the deleted session\'s row goes',
        );
      });

      test(
        'S-13408 deleteSession of a session without an energy row does not '
        'throw',
        () async {
          await seedSession(repo, sessionId: 's-energy');

          await repo.deleteSession('s-energy');

          expect(await repo.getSessionEnergy('s-energy'), isNull);
        },
      );

      test('S-13408 a full wipe of the repository removes the energy rows', () async {
        await seedSession(repo, sessionId: 's-wipe');
        await repo.putSessionEnergy(_estimated('s-wipe'));
        expect(await repo.getSessionEnergy('s-wipe'), isNotNull);

        final target = repo;
        if (target is MockWorkoutRepository) {
          target.clear();
        } else if (target is HiveWorkoutRepository) {
          await target.clear();
        } else {
          fail('unknown repository ${target.runtimeType}');
        }

        expect(await repo.getSessionEnergy('s-wipe'), isNull);
      });
    });
  }

  group('D-13401 SessionEnergy refuses what the contract refuses', () {
    SessionEnergy build({
      String sessionId = 's',
      double kcal = 10.5,
      String source = SessionEnergy.sourceEstimated,
      double? weight = 80.0,
    }) => SessionEnergy(
      sessionId: sessionId,
      activeKcal: kcal,
      source: source,
      bodyWeightKg: weight,
      updatedAtMs: 1,
    );

    test('a valid estimated row and a valid measured row are accepted', () {
      expect(build().activeKcal, 10.5);
      expect(build(source: SessionEnergy.sourceMeasured, weight: null).source,
          SessionEnergy.sourceMeasured);
    });

    test('negative, NaN and infinite kcal are refused', () {
      expect(() => build(kcal: -0.5), throwsArgumentError);
      expect(() => build(kcal: double.nan), throwsArgumentError);
      expect(() => build(kcal: double.infinity), throwsArgumentError);
    });

    test('a measured row carries no body weight', () {
      expect(
        () => build(source: SessionEnergy.sourceMeasured, weight: 80.0),
        throwsArgumentError,
      );
    });

    test('an estimated row names a body weight above zero', () {
      expect(() => build(weight: null), throwsArgumentError);
      expect(() => build(weight: 0.0), throwsArgumentError);
      expect(() => build(weight: -3.0), throwsArgumentError);
      expect(() => build(weight: double.nan), throwsArgumentError);
    });

    test('an unknown source and an empty session id are refused', () {
      expect(() => build(source: 'guessed'), throwsArgumentError);
      expect(() => build(sessionId: ''), throwsArgumentError);
    });
  });
}
