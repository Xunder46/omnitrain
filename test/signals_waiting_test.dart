// The waiting lines (plan 103): the two pure rules, the service's collection
// of them and the Protein Consistency signal's own count.
//
// Scenarios S-17601 … S-17604 of
// `docs/plans/2026-11-03-103-signals-waiting-plan/`. Plain `test()`, never
// `testWidgets`: Hive's real file I/O settles only on the real event loop. The
// harness is opened in `setUp`.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/models/cardio_efficiency_drift.dart';
import 'package:omnitrain/core/models/protein_consistency.dart';
import 'package:omnitrain/core/models/signals.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/core/services/signals/protein_consistency_signal.dart';
import 'package:omnitrain/core/services/signals/signal.dart';
import 'package:omnitrain/core/services/signals_service.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A signal that does nothing but answer `waitingFor`.
class _WaitingSignal implements Signal {
  _WaitingSignal(this.id, {this.line, this.throwing = false});

  @override
  final String id;
  final String? line;
  final bool throwing;

  @override
  SignalKind get kind => SignalKind.caution;

  @override
  int get priority => 1;

  @override
  bool get needsRatedWeeks => false;

  @override
  Future<SignalCard?> evaluate(SignalContext context) async => null;

  @override
  Future<String?> waitingFor(SignalContext context) async {
    if (throwing) throw StateError('unreadable');
    return line;
  }
}

final StatsWindow _window = StatsWindow(
  fromMs: DateTime(2026, 3, 1),
  toMs: DateTime(2026, 3, 31),
  label: 'Test window',
  isPeriodScoped: false,
  recentDays: 30,
);

/// Local noon of the fixed "today" every fixture counts back from.
final DateTime _now = DateTime(2026, 3, 20, 12);

SignalContext _context(WorkoutRepository repo) => SignalContext(
  now: _now,
  window: _window,
  mix: null,
  progressService: StatsProgressService(repo),
  repository: repo,
);

/// The repository's food log, emptied: the Mock harness opens with sample
/// consumed foods already written, the Hive harness empty.
Future<void> _clearConsumedFoods(WorkoutRepository repo) async {
  const farFutureMs = 4102444800000; // 2100-01-01
  for (final row in await repo.getConsumedFoodsInRange(0, farFutureMs)) {
    await repo.deleteConsumedFood(row.id);
  }
}

/// One logged `ConsumedFood` on the local day [daysAgo] days before [_now].
Future<void> _seedFood(
  WorkoutRepository repo, {
  required String id,
  required int daysAgo,
}) async {
  final day = DateTime(_now.year, _now.month, _now.day - daysAgo);
  final dateMs = day.millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs: dateMs + (12 * 60 * 60 * 1000),
      dateMs: dateMs,
      sourceFoodId: id,
      name: id,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: 100,
      carbs: 400,
      fiber: 0,
      fat: 0,
      sodium: null,
      amountConsumed: 100,
      groupIdSnapshot: 'food-group-proteins',
      groupNameSnapshot: 'Proteins',
      targetCalories: 0,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: dateMs,
      updatedAtMs: dateMs,
    ),
  );
}

void main() {
  group('S-17601 proteinConsistencyWaitingLine', () {
    test('the constants the line is built from are the ones the plan names', () {
      expect(kProteinConsistencyMinLoggedDays, 10);
      expect(kProteinConsistencyWindowDays, 14);
    });

    test('no logged day is not nagged', () {
      expect(proteinConsistencyWaitingLine(0), isNull);
    });

    test('one logged day needs nine more', () {
      expect(
        proteinConsistencyWaitingLine(1),
        'Protein Consistency: log food on 9 more days of the last 14.',
      );
    });

    test('nine logged days need one more day, singular', () {
      expect(
        proteinConsistencyWaitingLine(9),
        'Protein Consistency: log food on 1 more day of the last 14.',
      );
    });

    test('ten logged days is the floor: no line', () {
      expect(proteinConsistencyWaitingLine(10), isNull);
      expect(proteinConsistencyWaitingLine(14), isNull);
    });
  });

  group('S-17602 cardioEfficiencyWaitingLine', () {
    const line =
        'Cardio Efficiency: needs heart rate from the watch on at least 3 '
        'workouts of the same kind in each of two periods.';

    test('the floor the line is built from is the one the plan names', () {
      expect(kCardioEfficiencyMinEffortsPerWindow, 3);
    });

    test('no eligible effort: nothing the user can supply without a watch', () {
      expect(cardioEfficiencyWaitingLine(0), isNull);
    });

    test('one to five eligible efforts show the line', () {
      expect(cardioEfficiencyWaitingLine(1), line);
      expect(cardioEfficiencyWaitingLine(5), line);
    });

    test('six or more eligible efforts show no line', () {
      expect(cardioEfficiencyWaitingLine(6), isNull);
      expect(cardioEfficiencyWaitingLine(9), isNull);
    });
  });

  group('S-17603 SignalsService.waitingLines', () {
    late MockWorkoutRepository repo;

    setUp(() async {
      repo = MockWorkoutRepository();
      await repo.initialize();
    });

    SignalsService service(List<Signal> signals) => SignalsService(
      repository: repo,
      progressService: StatsProgressService(repo),
      signals: signals,
    );

    Future<List<String>> lines(List<Signal> signals) =>
        service(signals).waitingLines(now: _now, window: _window, mix: null);

    test('the lines come back in registry order and nulls are dropped', () async {
      expect(
        await lines([
          _WaitingSignal('n'),
          _WaitingSignal('a', line: 'line a'),
          _WaitingSignal('b', line: 'line b'),
        ]),
        ['line a', 'line b'],
      );
    });

    test('a signal whose answer cannot be read is skipped, not fatal', () async {
      expect(
        await lines([
          _WaitingSignal('a', line: 'line a'),
          _WaitingSignal('x', throwing: true),
          _WaitingSignal('b', line: 'line b'),
        ]),
        ['line a', 'line b'],
      );
    });

    test('at most kSignalMaxWaitingLines lines, the first ones', () async {
      expect(kSignalMaxWaitingLines, 3);
      expect(
        await lines([
          for (var i = 1; i <= 5; i++) _WaitingSignal('s$i', line: 'line $i'),
        ]),
        ['line 1', 'line 2', 'line 3'],
      );
    });
  });

  for (final factory in harnessFactories) {
    final harness = factory();

    group('S-17604 the Protein Consistency count — ${harness.name}', () {
      late WorkoutRepository repo;

      setUp(() async {
        repo = await harness.open();
        await _clearConsumedFoods(repo);
      });

      tearDown(() async {
        await harness.close();
      });

      Future<String?> waiting() =>
          const ProteinConsistencySignal().waitingFor(_context(repo));

      test('no logged day gives no line', () async {
        expect(await waiting(), isNull);
      });

      test('four logged days, one with two foods, need six more', () async {
        await _seedFood(repo, id: 'f0', daysAgo: 0);
        await _seedFood(repo, id: 'f1', daysAgo: 1);
        await _seedFood(repo, id: 'f2', daysAgo: 2);
        await _seedFood(repo, id: 'f3a', daysAgo: 3);
        await _seedFood(repo, id: 'f3b', daysAgo: 3);
        expect(
          await waiting(),
          'Protein Consistency: log food on 6 more days of the last 14.',
        );
      });

      test('ten logged days give no line', () async {
        for (var d = 0; d < 10; d++) {
          await _seedFood(repo, id: 'f$d', daysAgo: d);
        }
        expect(await waiting(), isNull);
      });

      test('a food 14 days ago is outside the window', () async {
        await _seedFood(repo, id: 'f0', daysAgo: 0);
        await _seedFood(repo, id: 'f1', daysAgo: 1);
        await _seedFood(repo, id: 'f2', daysAgo: 2);
        await _seedFood(repo, id: 'old', daysAgo: 14);
        expect(
          await waiting(),
          'Protein Consistency: log food on 7 more days of the last 14.',
        );
      });

      test('a food 13 days ago is the window\'s first day', () async {
        await _seedFood(repo, id: 'f0', daysAgo: 0);
        await _seedFood(repo, id: 'f1', daysAgo: 1);
        await _seedFood(repo, id: 'f2', daysAgo: 2);
        await _seedFood(repo, id: 'edge', daysAgo: 13);
        expect(
          await waiting(),
          'Protein Consistency: log food on 6 more days of the last 14.',
        );
      });
    });
  }
}
