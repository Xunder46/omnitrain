// Plan 118 — S-19201: the Conditioning discipline row; S-19202: the
// conditioning rows of the New-row table; S-19209: no Health kind for them.
//
// The bundled catalog must carry one Conditioning discipline
// (`discipline-conditioning`, key `conditioning`) under
// `category-resistance`, directly after Calisthenics in
// `SeedData.sampleDisciplines`, and the Resistance / Lifting discipline
// filter must list it last. Phase 2A's rows and Phase 2B's rows (D-19202)
// carry the planned name, pattern, capabilities, muscles and equipment, and
// the discipline lists exactly them. None of them carries a Health kind: no
// row has `distance`, so `healthActivityOf` is null and the wire object has
// no `healthActivity` key (D-19210).
// `docs/plans/2026-11-05-118-conditioning-catalog-plan/2026-11-05-118-conditioning-catalog-plan.md`.
//
// Pure except S-19209's wire check, which reads a fresh Mock and opens no
// Hive box.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_config.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';

import 'helpers/conditioning_catalog_rows.dart';

void main() {
  group('S-19201 the Conditioning discipline row', () {
    test('there is exactly one Conditioning row with the planned fields', () {
      final rows = SeedData.sampleDisciplines
          .where((d) => d.id == 'discipline-conditioning')
          .toList();
      expect(rows, hasLength(1));

      final row = rows.single;
      expect(row.categoryId, 'category-resistance');
      expect(row.key, 'conditioning');
      expect(row.name, 'Conditioning');
    });

    test('it sits directly after Calisthenics', () {
      final disciplines = SeedData.sampleDisciplines;
      final calisthenicsIndex = disciplines.indexWhere(
        (d) => d.id == 'discipline-calisthenics',
      );
      final conditioningIndex = disciplines.indexWhere(
        (d) => d.id == 'discipline-conditioning',
      );

      expect(calisthenicsIndex, isNot(-1));
      expect(conditioningIndex, calisthenicsIndex + 1);
    });

    test('ids are unique and the bundle carries 37 disciplines', () {
      final ids = SeedData.sampleDisciplines.map((d) => d.id).toList();

      expect(ids.toSet(), hasLength(ids.length));
      expect(SeedData.sampleDisciplines, hasLength(37));
    });

    test('the Resistance / Lifting filter lists it last', () {
      final ids = ModalityConfig.disciplinesForModality(
        'resistance_lifting',
        SeedData.sampleDisciplines,
      ).map((d) => d.id).toList();

      expect(ids, [
        'discipline-powerlifting',
        'discipline-bodybuilding',
        'discipline-weightlifting',
        'discipline-calisthenics',
        'discipline-conditioning',
      ]);
    });

    test('no other row shares its key or name, ignoring case', () {
      final others = SeedData.sampleDisciplines.where(
        (d) => d.id != 'discipline-conditioning',
      );

      expect(
        others.where((d) => d.key.toLowerCase() == 'conditioning'),
        isEmpty,
      );
      expect(
        others.where((d) => d.name.toLowerCase() == 'conditioning'),
        isEmpty,
      );
    });
  });

  group('S-19202 the conditioning rows', () {
    for (final row in conditioningCatalogRows) {
      test(
        '${row.suffix}: row, text, capabilities, muscles and equipment match '
        'the plan table',
        () => expectConditioningRowMatchesPlan(row),
      );
    }

    test('the Conditioning discipline lists exactly the new rows', () {
      final conditioningIds = {
        for (final exercise in SeedData.sampleExercises)
          if (exercise.disciplineId == 'discipline-conditioning') exercise.id,
      };

      expect(conditioningIds, {
        for (final row in conditioningCatalogRows) 'exercise-${row.suffix}',
      });
    });

    test('names are unique ignoring case and spaces', () {
      final seen = <String>{};
      final duplicates = <String>{};

      for (final exercise in SeedData.sampleExercises) {
        final key = exercise.name.trim().toLowerCase();
        if (!seen.add(key)) {
          duplicates.add(key);
        }
      }

      expect(duplicates, isEmpty);
    });

    test('every new id sorts after exercise-2k-row-test', () {
      for (final row in conditioningCatalogRows) {
        expect(
          'exercise-${row.suffix}'.compareTo('exercise-2k-row-test') > 0,
          isTrue,
          reason: row.suffix,
        );
      }
    });
  });

  group('S-19209 no Health kind for the conditioning rows', () {
    test('healthActivityOf is null for every row', () {
      for (final row in conditioningCatalogRows) {
        expect(
          WatchReferenceSync.healthActivityOf(
            disciplineId: 'discipline-conditioning',
            exerciseId: 'exercise-${row.suffix}',
            capabilities: row.caps,
          ),
          isNull,
          reason: row.suffix,
        );
      }
    });

    test('the wire object of exercise-burpee has no healthActivity', () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final batches = await WatchReferenceSync.buildExercisesDown(
        repository: repository,
        generatedAt: DateTime.utc(2026, 9, 21, 12, 30),
      );

      final wireRows = [
        for (final batch in batches)
          for (final exercise
              in (batch['payload']! as Map)['exercises']! as List)
            (exercise as Map).cast<String, Object?>(),
      ];
      final burpees = [
        for (final row in wireRows)
          if (row['exerciseId'] == 'exercise-burpee') row,
      ];

      expect(burpees, hasLength(1), reason: 'the catalog sends Burpee once');
      expect(burpees.single.containsKey('healthActivity'), isFalse);
    });
  });
}
