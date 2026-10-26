// The repository's reference revision (plan 74, D-1..D-3): a number that
// changes whenever a food, routine or exercise row was written, so a caller can
// skip re-reading storage when it stands still.
//
// Scenario mapping:
//   S-10401 Hive: every written kind moves the revision → `S-10401 ...`
//   S-10402 Hive: writes that are not reference data leave it alone
//   S-10403 Hive: no write, no move; a second initialize does not stack
//   S-10404 Mock: the Mock answers null, before and after writes
//
// Plain `test()` only: a Hive write inside a widget test's FakeAsync never
// completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A library food with values unlike the seed defaults.
Food _food({
  String id = 'rev-food-1',
  String name = 'Revision Chicken',
  bool isArchived = false,
}) => Food(
  id: id,
  name: name,
  groupId: 'rev-group-1',
  unitType: FoodUnitType.grams,
  referenceAmount: 130,
  referenceLabel: 'g',
  protein: 27,
  carbs: 3,
  fat: 4,
  isArchived: isArchived,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

WorkoutTemplate _template({String id = 'rev-template-1'}) => WorkoutTemplate(
  id: id,
  name: 'Revision Routine',
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

void main() {
  group('S-10404 Mock: the revision is unknowable', () {
    late MockRepositoryHarness harness;
    late WorkoutRepository repo;

    setUp(() async {
      harness = MockRepositoryHarness();
      repo = await harness.open();
    });

    tearDown(() => harness.close());

    test('S-10404 null before and after writes', () async {
      expect(repo.referenceRevision, isNull);

      await repo.createFood(_food());
      expect(repo.referenceRevision, isNull);

      await repo.createTemplate(_template());
      expect(repo.referenceRevision, isNull);
    });
  });

  group('S-10401 Hive: every written kind moves the revision', () {
    late HiveRepositoryHarness harness;
    late WorkoutRepository repo;

    setUp(() async {
      harness = HiveRepositoryHarness();
      repo = await harness.open();
    });

    tearDown(() => harness.close());

    test('S-10401 a write to any of the nine kinds moves the number', () async {
      expect(repo.referenceRevision, isNotNull);

      Future<void> expectMoved(
        String what,
        Future<void> Function() write,
      ) async {
        final before = repo.referenceRevision;
        await write();
        final after = repo.referenceRevision;
        expect(
          after,
          isNot(equals(before)),
          reason: '$what left the revision at $before',
        );
      }

      await expectMoved('createFood', () async {
        await repo.createFood(_food());
      });
      await expectMoved('updateFood', () async {
        await repo.updateFood(_food(name: 'Revision Chicken, edited'));
      });
      await expectMoved('archiveFood', () async {
        await repo.archiveFood('rev-food-1');
      });
      await expectMoved('createCatalogFood', () async {
        await repo.createCatalogFood(_food(name: 'Revision Catalog Oats'));
      });
      await expectMoved('createFoodGroup', () async {
        await repo.createFoodGroup(
          FoodGroup(
            id: 'rev-group-1',
            name: 'Revision Group',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      });
      await expectMoved('createExercise', () async {
        await repo.createExercise(
          Exercise(
            id: 'rev-ex-1',
            name: 'Revision Row',
            capabilities: const ['reps'],
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      });
      await expectMoved('setExerciseCapabilities', () async {
        await repo.setExerciseCapabilities('rev-ex-1', const [
          'time',
          'distance',
        ]);
      });
      await expectMoved('createTemplate', () async {
        await repo.createTemplate(_template());
      });
      await expectMoved('createTemplateSegment', () async {
        await repo.createTemplateSegment(
          TemplateSegment(
            id: 'rev-segment-1',
            templateId: 'rev-template-1',
            orderIndex: 0,
            segmentType: 'main',
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      });
      await expectMoved('createTemplateEffort', () async {
        await repo.createTemplateEffort(
          TemplateEffort(
            id: 'rev-effort-1',
            templateSegmentId: 'rev-segment-1',
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: 'rev-ex-1',
            createdAtMs: 1000,
          ),
        );
      });
      await expectMoved('createTemplateTarget', () async {
        await repo.createTemplateTarget(
          TemplateTarget(
            id: 'rev-target-1',
            templateEffortId: 'rev-effort-1',
            metricId: MetricIds.reps,
            setIndex: 0,
            targetInt: 7,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          ),
        );
      });
      await expectMoved('deleteTemplate', () async {
        await repo.deleteTemplate('rev-template-1');
      });
    });
  });

  group('S-10402 Hive: other writes leave the revision alone', () {
    late HiveRepositoryHarness harness;
    late WorkoutRepository repo;

    setUp(() async {
      harness = HiveRepositoryHarness();
      repo = await harness.open();
    });

    tearDown(() => harness.close());

    test('S-10402 a session and a preference are not reference data', () async {
      final before = repo.referenceRevision;

      await seedSession(repo, sessionId: 'rev-session');
      expect(
        repo.referenceRevision,
        before,
        reason: 'a session write moved the revision',
      );

      await repo.setPreferenceBool('rev_pref', true);
      expect(
        repo.referenceRevision,
        before,
        reason: 'a preference write moved the revision',
      );
    });
  });

  group('S-10403 Hive: no write means no move', () {
    late HiveRepositoryHarness harness;
    late WorkoutRepository repo;

    setUp(() async {
      harness = HiveRepositoryHarness();
      repo = await harness.open();
    });

    tearDown(() => harness.close());

    test('S-10403 two reads agree; a second initialize moves by one', () async {
      final first = repo.referenceRevision;
      expect(repo.referenceRevision, first);

      await repo.initialize();
      final before = repo.referenceRevision;
      expect(before, first, reason: 'a second initialize moved the revision');

      await repo.createFood(_food(id: 'rev-food-init-twice'));
      final after = repo.referenceRevision;

      expect(after, isNotNull);
      expect(after, isNot(before));
      expect(
        after! - before!,
        1,
        reason: 'listeners stacked on a second initialize',
      );
    });
  });
}
