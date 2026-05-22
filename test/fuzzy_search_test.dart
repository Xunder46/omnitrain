import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/fuzzy_search.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';

Exercise _exercise(String id, String name) => Exercise(
  id: id,
  ownerUserId: 'u-1',
  disciplineId: 'discipline-bodybuilding',
  name: name,
  description: '',
  movementPattern: 'push',
  isArchived: false,
  createdAtMs: 0,
  updatedAtMs: 0,
);

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('FuzzySearch', () {
    test('exact name match ranks before close fuzzy match', () {
      final exercises = [
        _exercise('1', 'Bench Press'),
        _exercise('2', 'Bensch Press'),
      ];

      final ranked = FuzzySearch.filterAndRank('bench press', exercises);

      expect(ranked, isNotEmpty);
      expect(ranked.first.name, 'Bench Press');
      expect(FuzzySearch.score('bench press', 'Bench Press'), 0);
    });

    test('single-character typo returns expected exercise', () {
      final exercises = [
        _exercise('1', 'Dumbbell Curl'),
        _exercise('2', 'Leg Press'),
      ];

      final ranked = FuzzySearch.filterAndRank('dumbel curl', exercises);

      expect(ranked.map((e) => e.name), contains('Dumbbell Curl'));
    });

    test('two-character typo returns expected exercise', () {
      final exercises = [
        _exercise('1', 'Incline Bench Press'),
        _exercise('2', 'Romanian Deadlift'),
      ];

      final ranked = FuzzySearch.filterAndRank('inclin bench prss', exercises);

      expect(ranked.map((e) => e.name), contains('Incline Bench Press'));
    });

    test('unrelated query returns no false positives', () {
      final exercises = [
        _exercise('1', 'Bench Press'),
        _exercise('2', 'Dumbbell Curl'),
      ];

      final ranked = FuzzySearch.filterAndRank('zzzzxyz', exercises);

      expect(ranked, isEmpty);
    });

    test('short tokens require exact matches', () {
      final exercises = [_exercise('1', 'Rum Day'), _exercise('2', 'Run Day')];

      final ranked = FuzzySearch.filterAndRank('run', exercises);

      expect(ranked.length, 1);
      expect(ranked.first.name, 'Run Day');
    });

    test('performance smoke test stays responsive', () {
      final exercises = List.generate(
        200,
        (i) => _exercise('id-$i', 'Exercise Variant $i'),
      )..add(_exercise('target', 'Incline Bench Press'));

      final stopwatch = Stopwatch()..start();
      final ranked = FuzzySearch.filterAndRank('inclin bench prss', exercises);
      stopwatch.stop();

      expect(ranked.any((e) => e.name == 'Incline Bench Press'), isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });

  group('Repository fuzzy ordering in modality flow', () {
    test(
      'uses fuzzy closeness as primary order and modality score as tie-breaker',
      () async {
        final repo = await _freshRepo();

        final exactButLow = _exercise('fx-exact-low', 'Bech Press Machine');
        final typoButHigh = _exercise('fx-typo-high', 'Bench Press');

        await repo.createExercise(exactButLow);
        await repo.createExercise(typoButHigh);

        await repo.setExerciseCapabilities(exactButLow.id, const []);
        await repo.setExerciseCapabilities(typoButHigh.id, const [
          'reps',
          'sets',
          'load',
        ]);

        final results = await repo.getExercisesRankedForModality(
          'resistance_lifting',
          searchText: 'bech press',
        );

        final names = results.map((e) => e.name).toList();
        expect(names, contains('Bech Press Machine'));
        expect(names, contains('Bench Press'));
        expect(
          names.indexOf('Bech Press Machine') < names.indexOf('Bench Press'),
          isTrue,
        );
      },
    );
  });
}
