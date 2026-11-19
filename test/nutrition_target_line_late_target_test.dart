// Plan 263: the dashed target line starts on the first day that has a saved
// target, instead of vanishing when the earliest logged day is older than the
// first target.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

DateTime _daysAgo(int n) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - n);
}

Future<void> _food(MockWorkoutRepository repo, String id, DateTime day) async {
  final ms = day.millisecondsSinceEpoch;
  await repo.createConsumedFood(
    ConsumedFood(
      id: id,
      loggedAtMs: ms + 12 * 3600000,
      dateMs: ms,
      sourceFoodId: id,
      name: id,
      unitType: FoodUnitType.grams,
      referenceAmount: 100,
      referenceLabel: '100 g',
      protein: 20,
      carbs: 30,
      fat: 10,
      amountConsumed: 100,
      targetCalories: 0,
      targetProtein: 0,
      targetCarbs: 0,
      targetFat: 0,
      createdAtMs: ms,
      updatedAtMs: ms,
    ),
  );
}

Future<MockWorkoutRepository> _repo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  for (final e in await repo.getConsumedFoodsInRange(0, 9999999999999)) {
    if (e.id.startsWith('seed-consumed-')) await repo.deleteConsumedFood(e.id);
  }
  return repo;
}

void main() {
  test('S-26301 food older than the first target: the line starts on the '
      'first target day', () async {
    final repo = await _repo();
    await _food(repo, 'old', _daysAgo(6));
    await _food(repo, 'mid', _daysAgo(3));
    await _food(repo, 'new', _daysAgo(0));
    final targetDay = _daysAgo(2);
    await repo.saveNutritionTargetForDate(
      targetDay.millisecondsSinceEpoch,
      NutritionTarget(calories: 2000, protein: 150, carbs: 200, fat: 60),
    );

    final adherence = await StatsProgressService(
      repo,
    ).computeNutritionAdherence();

    expect(adherence.targetLine, hasLength(1));
    expect(adherence.targetLine.first.date, targetDay);
    expect(adherence.targetLine.first.calories, 2000);
  });

  test(
    'S-26302 a target before the first logged day still anchors on it',
    () async {
      final repo = await _repo();
      await _food(repo, 'old', _daysAgo(6));
      await _food(repo, 'new', _daysAgo(0));
      await repo.saveNutritionTargetForDate(
        _daysAgo(10).millisecondsSinceEpoch,
        NutritionTarget(calories: 2200),
      );

      final adherence = await StatsProgressService(
        repo,
      ).computeNutritionAdherence();

      expect(adherence.targetLine.first.date, _daysAgo(6));
      expect(adherence.targetLine.first.calories, 2200);
    },
  );

  test(
    'S-26303 a target saved only after the latest logged day gives no line',
    () async {
      final repo = await _repo();
      await _food(repo, 'old', _daysAgo(6));
      await _food(repo, 'new', _daysAgo(3));
      await repo.saveNutritionTargetForDate(
        _daysAgo(0).millisecondsSinceEpoch,
        NutritionTarget(calories: 2000),
      );

      final adherence = await StatsProgressService(
        repo,
      ).computeNutritionAdherence();

      expect(adherence.targetLine, isEmpty);
    },
  );

  test(
    'S-26304 the first target day is found whatever the history length',
    () async {
      final repo = await _repo();
      for (var n = 40; n >= 0; n -= 5) {
        await _food(repo, 'f$n', _daysAgo(n));
      }
      await repo.saveNutritionTargetForDate(
        _daysAgo(13).millisecondsSinceEpoch,
        NutritionTarget(calories: 1800),
      );

      final adherence = await StatsProgressService(
        repo,
      ).computeNutritionAdherence();

      expect(adherence.targetLine.first.date, _daysAgo(13));
    },
  );
}
