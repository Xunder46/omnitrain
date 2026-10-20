// Plan 39 (P3) — a cardio interval's weight is stored as `extra-weight`, in
// canonical kg, and the session editor's Save rewrites that one row.
//
// S-4708 (the stored kilogram value) and S-4709 (the editor's saved value) of
// `docs/plans/2026-10-17-39-logger-polish-2-plan/2026-10-17-39-logger-polish-2-plan.md`.
// The write goes through `WorkoutRepository`, so `MockWorkoutRepository` and
// `HiveWorkoutRepository` must store the same value: it is read back from the
// store, and from a restarted repository, never from the state's cache.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A cardio session holding one finished interval on `e-run`.
Future<void> _seedInterval(WorkoutRepository repo) async {
  await seedSession(repo, sessionId: 's-4708', modality: 'cardio_endurance');
  await seedTimedEntries(
    repo,
    segmentId: 'seg-s-4708',
    effortId: 'e-run',
    entryCount: 1,
  );
}

/// The `extra-weight` rows the store holds for [effortId], by id.
Future<Map<String, double>> _storedWeights(
  WorkoutRepository repo,
  String effortId,
) async {
  final rows = await storedRows(repo, effortId, MetricIds.extraWeight);
  return {for (final row in rows) row.id: row.valueReal ?? 0.0};
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

  test(titled('S-4708 a logged interval weight is stored as kilograms'), () async {
    await _seedInterval(repo);
    final state = await loadState(repo, 's-4708');

    await state.updateEntryValue('e-run', 0, 'extra-weight', 2.5);

    expect(await _storedWeights(repo, 'e-run'), {
      'obs-e-run-0-extra-weight': 2.5,
    });

    final reopened = await harness.restart();
    expect(
      await _storedWeights(reopened, 'e-run'),
      {'obs-e-run-0-extra-weight': 2.5},
      reason: 'the stored value survives a restart',
    );
  });

  test(titled('S-4708 a pounds step is stored as its kilogram value'), () async {
    await _seedInterval(repo);
    final state = await loadState(repo, 's-4708');

    // 5 lb, the step a pounds user takes: the screen hands the canonical
    // kilogram value down (see test/count_up_screen_test.dart, S-4708).
    await state.updateEntryValue('e-run', 0, 'extra-weight', 2.26796);

    final stored = await _storedWeights(repo, 'e-run');
    expect(stored['obs-e-run-0-extra-weight'], closeTo(2.26796, 0.0001));
    expect(
      stored.values.single,
      isNot(closeTo(5.0, 0.001)),
      reason: 'the store keeps kilograms, never the pounds the row shows',
    );
  });

  test(titled('S-4709 the editor Save rewrites the interval row in place'), () async {
    await _seedInterval(repo);
    final state = await loadState(repo, 's-4708');

    // The row `addEntry` wrote is 0.0; the editor's Save overwrites that row.
    expect(await _storedWeights(repo, 'e-run'), {
      'obs-e-run-0-extra-weight': 0.0,
    });

    await state.updateEntryValue('e-run', 0, 'extra-weight', 2.5);

    expect(await _storedWeights(repo, 'e-run'), {
      'obs-e-run-0-extra-weight': 2.5,
    });

    final reopened = await harness.restart();
    expect(await _storedWeights(reopened, 'e-run'), {
      'obs-e-run-0-extra-weight': 2.5,
    });
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
