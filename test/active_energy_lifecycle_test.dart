// Plan 134 P2B — a WorkoutState that carries ActiveEnergyService stores the
// estimate when a session ends or its duration is edited (S-13401, S-13406,
// S-13407, S-13408, S-13417 of
// docs/plans/2026-11-08-134-calories-burned-plan/2026-11-08-134-calories-burned-plan.md).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/core/services/active_energy_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

ActiveEnergyService _energy(WorkoutRepository repo) =>
    ActiveEnergyService(repo, () => StatsProgressService(repo));

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// S-13401/S-13406 need real elapsed time: the state's `endSession` stamps the
/// real `now` as the end, so the session sits in the store with its start in
/// the past and the state adopts it (the route of the S-155 future-start test).
Future<void> _seedInProgressSession(
  WorkoutRepository repo, {
  required String id,
  required String? modality,
  required int startedAtMs,
}) async {
  await repo.createSession(
    TrainingSession(
      id: id,
      ownerUserId: 'user-1',
      modality: modality,
      startedAtMs: startedAtMs,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
}

Future<void> _seedWeight(
  WorkoutRepository repo, {
  required String id,
  required double kg,
  required int recordedAtMs,
}) async {
  await repo.saveMeasurementEntry(
    BodyMeasurementEntry(
      id: id,
      measurementType: ProfileMeasurements.bodyweight.type,
      value: kg,
      unitId: MetricIds.unitKg,
      recordedAtMs: recordedAtMs,
    ),
  );
}

void main() {
  _mainWiringGuard();

  test('S-13401: endSession on a resistance session stores the estimated row', () async {
    final repo = await _freshRepo();
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - 3600000;
    await _seedInProgressSession(
      repo,
      id: 's-resistance',
      modality: Modality.resistanceLifting,
      startedAtMs: start,
    );
    await _seedWeight(repo, id: 'bw1', kg: 80.0, recordedAtMs: start);

    final state = WorkoutState(
      repo,
      activeEnergy: _energy(repo),
    );
    await state.loadHistoricalSession('s-resistance');
    await state.endSession();

    final row = await repo.getSessionEnergy('s-resistance');
    expect(row, isNotNull, reason: 'the end of the session wrote no row');
    expect(row!.source, SessionEnergy.sourceEstimated);
    expect(row.activeKcal, closeTo(200.0, 0.05));
    expect(row.bodyWeightKg, 80.0);
    expect(state.error, isNull);
  });

  test('S-13406: a duration edit recomputes an estimated row at its stored weight', () async {
    final repo = await _freshRepo();
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - 1102000;
    await _seedInProgressSession(
      repo,
      id: 's-isometric',
      modality: Modality.isometricStretching,
      startedAtMs: start,
    );
    await _seedWeight(repo, id: 'bw1', kg: 80.0, recordedAtMs: start);

    final state = WorkoutState(
      repo,
      activeEnergy: _energy(repo),
    );
    await state.loadHistoricalSession('s-isometric');
    await state.endSession();

    final atEnd = await repo.getSessionEnergy('s-isometric');
    expect(atEnd, isNotNull);
    expect(atEnd!.source, SessionEnergy.sourceEstimated);
    expect(atEnd.activeKcal, closeTo(48.9778, 0.05));

    await _seedWeight(repo, id: 'bw2', kg: 90.0, recordedAtMs: start + 1200000);
    await state.updateSessionEndTime(1500);

    final row = await repo.getSessionEnergy('s-isometric');
    expect(row, isNotNull);
    expect(row!.source, SessionEnergy.sourceEstimated);
    // 2 x 80 x 1500 / 3600: the stored 80 kg, never the newer 90 kg.
    expect(row.activeKcal, closeTo(66.6667, 1e-3));
    expect(row.bodyWeightKg, 80.0);
    expect(state.error, isNull);
  });

  test('S-13407: a measured row survives an end and a duration edit', () async {
    final repo = await _freshRepo();
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - 3600000;
    await _seedInProgressSession(
      repo,
      id: 's-measured',
      modality: Modality.resistanceLifting,
      startedAtMs: start,
    );
    await _seedWeight(repo, id: 'bw1', kg: 80.0, recordedAtMs: start);
    await repo.putSessionEnergy(
      SessionEnergy(
        sessionId: 's-measured',
        activeKcal: 250.4,
        source: SessionEnergy.sourceMeasured,
        bodyWeightKg: null,
        updatedAtMs: now,
      ),
    );

    final state = WorkoutState(
      repo,
      activeEnergy: _energy(repo),
    );
    await state.loadHistoricalSession('s-measured');
    await state.endSession();
    await state.updateSessionEndTime(1500);

    final row = await repo.getSessionEnergy('s-measured');
    expect(row, isNotNull);
    expect(row!.source, SessionEnergy.sourceMeasured);
    expect(row.activeKcal, 250.4);
    expect(row.bodyWeightKg, isNull);
    expect(state.error, isNull);
  });

  test('S-13408: discardCurrentSession takes the session energy row with it', () async {
    final repo = await _freshRepo();
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - 3600000;
    await _seedInProgressSession(
      repo,
      id: 's-discarded',
      modality: Modality.resistanceLifting,
      startedAtMs: start,
    );
    await _seedWeight(repo, id: 'bw1', kg: 80.0, recordedAtMs: start);

    final state = WorkoutState(
      repo,
      activeEnergy: _energy(repo),
    );
    await state.loadHistoricalSession('s-discarded');
    await state.endSession();
    expect(await repo.getSessionEnergy('s-discarded'), isNotNull);

    await state.discardCurrentSession();

    expect(await repo.getSessionEnergy('s-discarded'), isNull);
    expect(await repo.getSession('s-discarded'), isNull);
    expect(state.error, isNull);
  });

  test('S-13417: a throwing putSessionEnergy never fails the end', () async {
    final repo = _ThrowingRepo();
    await repo.initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - 3600000;
    await _seedInProgressSession(
      repo,
      id: 's-throwing',
      modality: Modality.resistanceLifting,
      startedAtMs: start,
    );
    await _seedWeight(repo, id: 'bw1', kg: 80.0, recordedAtMs: start);

    final state = WorkoutState(
      repo,
      activeEnergy: _energy(repo),
    );
    await state.loadHistoricalSession('s-throwing');

    await state.endSession();

    final stored = await repo.getSession('s-throwing');
    expect(stored, isNotNull);
    expect(stored!.endedAtMs, isNotNull);
    expect(state.error, isNull);
    expect(await repo.getSessionEnergy('s-throwing'), isNull);
  });

  test('S-13401 without activeEnergy: the end writes no row and works as before', () async {
    final repo = await _freshRepo();
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - 3600000;
    await _seedInProgressSession(
      repo,
      id: 's-unwired',
      modality: Modality.resistanceLifting,
      startedAtMs: start,
    );
    await _seedWeight(repo, id: 'bw1', kg: 80.0, recordedAtMs: start);

    final state = WorkoutState(repo);
    await state.loadHistoricalSession('s-unwired');
    await state.endSession();

    final stored = await repo.getSession('s-unwired');
    expect(stored, isNotNull);
    expect(stored!.endedAtMs, isNotNull);
    expect(await repo.getSessionEnergy('s-unwired'), isNull);
    expect(state.error, isNull);
  });
}

// The app's one WorkoutState is built in lib/main.dart; no test boots main(),
// so the wiring that makes a finished session store its energy at all is
// pinned by reading the statement (whitespace-insensitive, so a reformat of
// the file does not break it).
void _mainWiringGuard() {
  test('D-13408 lib/main.dart gives WorkoutState the ActiveEnergyService', () {
    final source = File('lib/main.dart').readAsStringSync().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    const declaration =
        'finalactiveEnergy=ActiveEnergyService(repository,()=>StatsProgressService(repository)';
    final declAt = source.indexOf(declaration);
    expect(
      declAt,
      greaterThan(0),
      reason: 'main.dart lost the activeEnergy wiring',
    );
    // D-13420: the same store reaches the watch graph and WorkoutState, so an
    // inbox pass that landed the wrist's work re-settles the estimate.
    const wiring = 'activeEnergy:activeEnergy';
    expect(
      wiring.allMatches(source).length,
      greaterThanOrEqualTo(2),
      reason: 'main.dart lost the activeEnergy wiring for the watch graph',
    );
    final call = source.indexOf('WorkoutState(repository,');
    expect(call, greaterThan(0), reason: 'the wiring must sit in the WorkoutState call');
    final at = source.indexOf(wiring, call);
    expect(at, greaterThan(call), reason: 'the wiring must sit in the WorkoutState call');
    expect(
      source.substring(call, at).contains(');'),
      isFalse,
      reason: 'the wiring belongs to the WorkoutState(...) call, not a later one',
    );
  });

  test('D-13420 the watch graph gives its inbox the settle callback', () {
    final source = File('lib/state/watch/watch_sync_wiring.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), '');
    expect(
      source.contains('onSessionHistoryChanged:activeEnergy?.settle,'),
      isTrue,
      reason: 'the inbox lost the callback that prices a watch-imported session',
    );
  });
}

class _ThrowingRepo extends MockWorkoutRepository {
  @override
  Future<bool> putSessionEnergy(SessionEnergy energy) async =>
      throw StateError('boom');
}
