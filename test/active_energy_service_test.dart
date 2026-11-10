// Plan 134 phase P2A — the active-energy estimate and its read-out.
//
// Red reasons: `lib/core/constants/active_energy.dart` and
// `lib/core/services/active_energy_service.dart` do not exist yet.
//
// Plan: docs/plans/2026-11-08-134-calories-burned-plan/2026-11-08-134-calories-burned-plan.md.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/active_energy_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

var _entry = 0;

/// A finished (or running) session with its one segment.
Future<void> _seedSession(
  WorkoutRepository repo, {
  required String id,
  String? modality,
  bool isRolling = false,
  required int startedAtMs,
  int? endedAtMs,
}) async {
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      modality: modality,
      isRolling: isRolling,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  await repo.createSegment(
    SessionSegment(
      id: 'seg-$id',
      sessionId: id,
      orderIndex: 0,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
}

/// One finished timed effort ([kind] is `timed` for cardio, `drill` for
/// isometric) of [seconds] on [sessionId]'s segment.
Future<void> _seedTimedEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required String effortId,
  required String kind,
  required int seconds,
  required int atMs,
}) async {
  final exerciseId = 'ex-$effortId';
  await repo.createExercise(
    Exercise(
      id: exerciseId,
      name: 'Work $effortId',
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  );
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: 'seg-$sessionId',
      orderIndex: 0,
      effortKind: kind,
      exerciseId: exerciseId,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  );
  await repo.createTimedInstance(
    TimedInstance(
      id: 'ti-$effortId',
      effortId: effortId,
      entryIndex: 0,
      targetDurationSecs: seconds,
      actualDurationSecs: seconds,
      startedAtMs: atMs,
      finishedAtMs: atMs + seconds * 1000,
      state: TimedState.finished,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  );
}

/// One set effort with three loaded sets: an effort the energy split
/// measures nothing of (S-13416).
Future<void> _seedSetEffort(
  WorkoutRepository repo, {
  required String sessionId,
  required String effortId,
  required int atMs,
}) async {
  final exerciseId = 'ex-$effortId';
  await repo.createExercise(
    Exercise(
      id: exerciseId,
      name: 'Work $effortId',
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  );
  await seedSetEffort(
    repo,
    segmentId: 'seg-$sessionId',
    effortId: effortId,
    exerciseId: exerciseId,
    entryCount: 3,
    hasExtraWeight: false,
  );
}

/// A bodyweight entry; ids and timestamps are unique per call, so the later
/// entry is always the latest on file.
Future<void> _seedWeight(
  WorkoutRepository repo,
  double value, {
  String unitId = 'unit-kg',
}) async {
  final n = _entry++;
  await repo.saveMeasurementEntry(
    BodyMeasurementEntry(
      id: 'bm-$n',
      measurementType: 'bodyweight',
      value: value,
      unitId: unitId,
      recordedAtMs: fixtureStart + 9676800000 + n,
    ),
  );
}

/// Settles [sessionId] and reads the row back.
Future<SessionEnergy?> _settle(WorkoutRepository repo, String sessionId) async {
  await ActiveEnergyService(
    repo,
    () => StatsProgressService(repo),
  ).settle(sessionId);
  return repo.getSessionEnergy(sessionId);
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — ActiveEnergyService.settle', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
      });

      tearDown(() async {
        await harness.close();
      });

      test('S-13401 resistance 3600 s at 80 kg stores 200.0', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-01',
          modality: 'resistance_lifting',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );

        final row = (await _settle(repo, 's-01'))!;

        expect(row.source, 'estimated');
        expect(row.activeKcal, closeTo(200.0, 1e-9));
        expect(row.bodyWeightKg, 80.0);
      });

      test('S-13402 isometric 1102 s at 80 kg stores 48.9777… unrounded', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-02',
          modality: 'isometric_stretching',
          startedAtMs: 0,
          endedAtMs: 1102000,
        );

        final row = (await _settle(repo, 's-02'))!;

        expect(row.source, 'estimated');
        expect(row.activeKcal, closeTo(48.97777777777778, 1e-9));
        expect(row.bodyWeightKg, 80.0);
      });

      test('S-13403 cardio 1800 s at 80 kg stores 200.0', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-03a',
          modality: 'cardio_endurance',
          startedAtMs: 0,
          endedAtMs: 1800000,
        );

        final row = (await _settle(repo, 's-03a'))!;

        expect(row.activeKcal, closeTo(200.0, 1e-9));
        expect(row.bodyWeightKg, 80.0);
      });

      test('S-13403 sports 5400 s at 70 kg stores 525.0', () async {
        await _seedWeight(repo, 70);
        await _seedSession(
          repo,
          id: 's-03b',
          modality: 'sports',
          startedAtMs: 0,
          endedAtMs: 5400000,
        );

        final row = (await _settle(repo, 's-03b'))!;

        expect(row.activeKcal, closeTo(525.0, 1e-9));
        expect(row.bodyWeightKg, 70.0);
      });

      test('S-13404 Free Training 3600 s with measured cardio and isometric', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-04',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );
        await _seedTimedEffort(
          repo,
          sessionId: 's-04',
          effortId: 'ef-04-cardio',
          kind: 'timed',
          seconds: 1200,
          atMs: fixtureStart - 2000000,
        );
        await _seedTimedEffort(
          repo,
          sessionId: 's-04',
          effortId: 'ef-04-iso',
          kind: 'drill',
          seconds: 600,
          atMs: fixtureStart - 1000000,
        );

        final row = (await _settle(repo, 's-04'))!;

        expect(row.source, 'estimated');
        // 5 x 80 x 1200 s + 2 x 80 x 600 s + 2.5 x 80 x 1800 s remainder.
        expect(row.activeKcal, closeTo(260.0, 1e-9));
        expect(row.bodyWeightKg, 80.0);
      });

      test('S-13414 an unknown modality id takes the Free Training branch', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-14',
          modality: 'conditioning_mixed',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );
        await _seedTimedEffort(
          repo,
          sessionId: 's-14',
          effortId: 'ef-14-cardio',
          kind: 'timed',
          seconds: 1200,
          atMs: fixtureStart - 2000000,
        );
        await _seedTimedEffort(
          repo,
          sessionId: 's-14',
          effortId: 'ef-14-iso',
          kind: 'drill',
          seconds: 600,
          atMs: fixtureStart - 1000000,
        );

        final row = (await _settle(repo, 's-14'))!;

        expect(row.activeKcal, closeTo(260.0, 1e-9));
      });

      test('S-13416 Free Training with only set work: resistance remainder', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-16',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );
        await _seedSetEffort(
          repo,
          sessionId: 's-16',
          effortId: 'ef-16-set',
          atMs: fixtureStart - 3000000,
        );

        final row = (await _settle(repo, 's-16'))!;

        expect(row.activeKcal, closeTo(200.0, 1e-9));
        expect(row.bodyWeightKg, 80.0);
      });

      test('S-13405 no weight, then a lbs weight, then a kg weight', () async {
        await _seedSession(
          repo,
          id: 's-05',
          modality: 'resistance_lifting',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );

        // No bodyweight entry at all: no row.
        expect(await _settle(repo, 's-05'), isNull);

        // A latest entry in pounds: still no row.
        await _seedWeight(repo, 80, unitId: 'unit-lbs');
        expect(await _settle(repo, 's-05'), isNull);

        // A kg entry lands on top: the still-finished session gets its row.
        await _seedWeight(repo, 80);
        final row = (await _settle(repo, 's-05'))!;
        expect(row.activeKcal, closeTo(200.0, 1e-9));
        expect(row.bodyWeightKg, 80.0);
      });

      test('S-13415 a latest weight of 0 kg writes no row', () async {
        await _seedWeight(repo, 0);
        await _seedSession(
          repo,
          id: 's-15a',
          modality: 'resistance_lifting',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );

        expect(await _settle(repo, 's-15a'), isNull);
      });

      test('S-13415 a latest weight of −5 kg writes no row', () async {
        await _seedWeight(repo, -5);
        await _seedSession(
          repo,
          id: 's-15b',
          modality: 'resistance_lifting',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );

        expect(await _settle(repo, 's-15b'), isNull);
      });

      test('S-13406 a re-estimate reuses the stored weight; an edit recomputes', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-06',
          modality: 'isometric_stretching',
          startedAtMs: 0,
          endedAtMs: 1102000,
        );

        final first = (await _settle(repo, 's-06'))!;
        expect(first.activeKcal, closeTo(48.97777777777778, 1e-9));
        expect(first.bodyWeightKg, 80.0);

        // A newer bodyweight entry arrives: the stored 80 kg wins.
        await _seedWeight(repo, 90);
        final second = (await _settle(repo, 's-06'))!;
        expect(second.activeKcal, closeTo(48.97777777777778, 1e-9));
        expect(second.bodyWeightKg, 80.0);

        // The session duration is edited: recompute, still on the stored 80.
        final session = (await repo.getSession('s-06'))!;
        await repo.updateSession(
          TrainingSession(
            id: session.id,
            ownerUserId: session.ownerUserId,
            startedAtMs: session.startedAtMs,
            endedAtMs: 1500000,
            modality: session.modality,
            isRolling: session.isRolling,
            createdAtMs: session.createdAtMs,
            updatedAtMs: session.updatedAtMs,
          ),
        );
        final third = (await _settle(repo, 's-06'))!;
        expect(third.activeKcal, closeTo(66.66666666666667, 1e-9));
        expect(third.bodyWeightKg, 80.0);
      });

      test('S-13407 a measured row survives a settle untouched', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-07',
          modality: 'resistance_lifting',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );
        await repo.putSessionEnergy(
          SessionEnergy(
            sessionId: 's-07',
            activeKcal: 250.4,
            source: SessionEnergy.sourceMeasured,
            updatedAtMs: fixtureStart,
          ),
        );

        await ActiveEnergyService(
          repo,
          () => StatsProgressService(repo),
        ).settle('s-07');

        final row = (await repo.getSessionEnergy('s-07'))!;
        expect(row.source, 'measured');
        expect(row.activeKcal, 250.4);
        expect(row.bodyWeightKg, isNull);
      });

      test('S-13409 an unfinished session writes no row', () async {
        await _seedWeight(repo, 80);
        await _seedSession(repo, id: 's-09u', modality: 'sports', startedAtMs: 0);

        expect(await _settle(repo, 's-09u'), isNull);
      });

      test('S-13409 a finished rolling session with nothing measured writes no row', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-09r1',
          isRolling: true,
          startedAtMs: 0,
          endedAtMs: 3600000,
        );

        expect(await _settle(repo, 's-09r1'), isNull);
      });

      test('S-13409 a finished rolling session with measured isometric seconds', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-09r2',
          isRolling: true,
          startedAtMs: 0,
          endedAtMs: 3600000,
        );
        await _seedTimedEffort(
          repo,
          sessionId: 's-09r2',
          effortId: 'ef-09r2',
          kind: 'drill',
          seconds: 600,
          atMs: fixtureStart - 1000000,
        );

        final row = (await _settle(repo, 's-09r2'))!;
        expect(row.source, 'estimated');
        expect(row.activeKcal, closeTo(26.666666666666668, 1e-9));
        expect(row.bodyWeightKg, 80.0);
      });

      test(
        'S-13409 a rolling session counts its measured seconds even when it '
        'carries a modality id',
        () async {
          await _seedWeight(repo, 80);
          // A rolling session ends without a duration of its own (D-13404):
          // its wall-clock hour must not be priced at the modality's MET
          // (that would be 2 x 80 x 1 = 160 kcal).
          await _seedSession(
            repo,
            id: 's-09rm',
            modality: 'isometric_stretching',
            isRolling: true,
            startedAtMs: 0,
            endedAtMs: 3600000,
          );
          await _seedTimedEffort(
            repo,
            sessionId: 's-09rm',
            effortId: 'ef-09rm',
            kind: 'drill',
            seconds: 600,
            atMs: fixtureStart - 1000000,
          );

          final row = (await _settle(repo, 's-09rm'))!;
          expect(row.activeKcal, closeTo(26.666666666666668, 1e-9));
        },
      );

      test('S-13409 a session with a modality and no duration writes no row', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-09z',
          modality: 'resistance_lifting',
          startedAtMs: 5000,
          endedAtMs: 5000,
        );

        expect(await _settle(repo, 's-09z'), isNull);
      });

      test('read-out: estimated 48.9777 reads (49, not measured)', () async {
        await _seedWeight(repo, 80);
        await _seedSession(
          repo,
          id: 's-101',
          modality: 'isometric_stretching',
          startedAtMs: 0,
          endedAtMs: 1102000,
        );
        await _settle(repo, 's-101');

        final read = (await SessionSummaryService(
          repo,
        ).getSessionEnergy('s-101'))!;
        expect(read.kcal, 49);
        expect(read.measured, isFalse);
      });

      test('read-out: a tiny session reads 0 kcal, not null (D-13412)', () async {
        // 20 s of stretching at 40 kg: 1.3 x 40 x 20 / 3600 = 0.2889 kcal.
        await _seedWeight(repo, 40);
        await _seedSession(
          repo,
          id: 's-103',
          modality: 'isometric_stretching',
          startedAtMs: 0,
          endedAtMs: 20000,
        );
        final row = (await _settle(repo, 's-103'))!;
        expect(row.activeKcal, closeTo(0.4444444444444444, 1e-9));

        final read = (await SessionSummaryService(
          repo,
        ).getSessionEnergy('s-103'))!;
        expect(read.kcal, 0);
        expect(read.measured, isFalse);
      });

      test('read-out: a measured 250.4 row reads (250, measured)', () async {
        await _seedSession(
          repo,
          id: 's-102',
          modality: 'resistance_lifting',
          startedAtMs: 0,
          endedAtMs: 3600000,
        );
        await repo.putSessionEnergy(
          SessionEnergy(
            sessionId: 's-102',
            activeKcal: 250.4,
            source: SessionEnergy.sourceMeasured,
            updatedAtMs: fixtureStart,
          ),
        );

        final read = (await SessionSummaryService(
          repo,
        ).getSessionEnergy('s-102'))!;
        expect(read.kcal, 250);
        expect(read.measured, isTrue);
      });

      test('read-out: no row reads null', () async {
        expect(
          await SessionSummaryService(repo).getSessionEnergy('s-103'),
          isNull,
        );
      });
    });
  }
}
