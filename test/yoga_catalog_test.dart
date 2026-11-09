// Plan 119, Phase 1 — S-19301: row conformance and the Yoga set.
//
// The bundled catalog must carry the Yoga rows of the plan's New-row table
// (D-19301) under `discipline-yoga` (D-19302) with the hold capability set
// (D-19303), Body Weight (D-19304), the planned muscles (D-19305) and readable
// text (D-19306), and the two existing poses must move to Yoga (D-19312).
// `docs/plans/2026-11-05-119-yoga-catalog-plan/2026-11-05-119-yoga-catalog-plan.md`.
//
// Pure: reads `SeedData` and the shared table in
// `test/helpers/yoga_catalog_rows.dart`, opens no store.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/mock/seed_data.dart';

import 'helpers/yoga_catalog_rows.dart';

void main() {
  final byId = {for (final e in SeedData.sampleExercises) e.id: e};

  group('S-19301 the yoga rows', () {
    for (final row in yogaCatalogRows) {
      test(
        '${row.suffix}: row, text, capabilities, muscles and equipment match '
        'the plan table',
        () => expectYogaRowMatchesPlan(row),
      );
    }

    test('the Yoga discipline lists exactly the new rows and the two moves', () {
      final yogaIds = {
        for (final exercise in SeedData.sampleExercises)
          if (exercise.disciplineId == 'discipline-yoga') exercise.id,
      };

      expect(yogaIds, {
        for (final row in yogaCatalogRows) 'exercise-${row.suffix}',
        'exercise-pigeon-pose',
        'exercise-childs-pose',
      });
    });

    test('Pigeon Pose and Child\'s Pose moved to Yoga, keeping their links', () {
      for (final id in ['exercise-pigeon-pose', 'exercise-childs-pose']) {
        expect(byId[id], isNotNull, reason: 'missing $id');
        expect(byId[id]!.disciplineId, 'discipline-yoga', reason: id);
        expect(
          SeedData.exerciseMuscleLinks[id],
          isNotEmpty,
          reason: '$id keeps its muscle links',
        );
        expect(
          SeedData.exerciseEquipmentRelationships[id],
          ['equipment-bodyweight'],
          reason: '$id keeps its equipment link',
        );
      }
    });

    test('names are unique ignoring case and surrounding spaces', () {
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
      for (final row in yogaCatalogRows) {
        expect(
          'exercise-${row.suffix}'.compareTo('exercise-2k-row-test') > 0,
          isTrue,
          reason: row.suffix,
        );
      }
    });
  });
}
