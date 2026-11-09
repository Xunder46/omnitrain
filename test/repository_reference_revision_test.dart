// The repository's reference revision (plan 74, D-1..D-3): a number that
// changes whenever a food, routine or exercise row was written, so a caller can
// skip re-reading storage when it stands still.
//
// Scenario mapping:
//   S-10401 Hive: every written kind moves the revision → `S-10401 ...`
//   S-10402 Hive: writes that are not reference data leave it alone
//   S-10403 Hive: no write, no move; a second initialize does not stack
//   S-10404 Mock: the Mock answers null, before and after writes
//   S-87c-8 Mock: the history revision is unknowable → `S-87c-8 ...`
//   S-87c-15 Hive: the history listeners count every event kind on the four
//         history boxes → `S-87c-15 ...` (plan 87c)
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

/// Lets every listener the box write queued run: a zero-duration timer starts
/// after the microtasks that deliver the events (plain `test()`, no FakeAsync).
Future<void> _settle() => Future<void>.delayed(Duration.zero);

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

    test('S-87c-8 the history revision is null too', () async {
      expect(repo.historyRevision, isNull);

      await seedSession(repo, sessionId: 'rev-history-session');
      expect(repo.historyRevision, isNull);

      await repo.createFood(_food(id: 'rev-history-food'));
      expect(repo.historyRevision, isNull);
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

  group('S-87c-15 Hive: the four history boxes move the number', () {
    late HiveRepositoryHarness harness;
    late WorkoutRepository repo;

    setUp(() async {
      harness = HiveRepositoryHarness();
      repo = await harness.open();

      final at = fixtureStart;
      for (var n = 0; n < 2; n++) {
        await repo.createSession(
          TrainingSession(
            id: 'hist-session-$n',
            ownerUserId: 'user-1',
            startedAtMs: at + n,
            endedAtMs: at + n + 3600000,
            createdAtMs: at,
            updatedAtMs: at,
          ),
        );
        await repo.createSegment(
          SessionSegment(
            id: 'hist-seg-$n',
            sessionId: 'hist-session-$n',
            orderIndex: 0,
            segmentType: 'workout',
            name: 'Main Workout',
            createdAtMs: at,
            updatedAtMs: at,
          ),
        );
        await repo.createEffort(
          SegmentEffort(
            id: 'hist-effort-$n',
            segmentId: 'hist-seg-$n',
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: 'hist-ex-$n',
            createdAtMs: at,
            updatedAtMs: at,
          ),
        );
      }
      // The two observation rows both hang on effort 0, so one deleteAll path
      // can prove the per-key count.
      await repo.createObservation(repsRow('hist-effort-0', 0, 5, atMs: at));
      await repo.createObservation(repsRow('hist-effort-0', 1, 5, atMs: at));
      await repo.createTimedInstance(
        timedInstance('hist-effort-1', 0, durationSecs: 60, entryIndex: 0),
      );
      await _settle();
    });

    tearDown(() => harness.close());

    /// [write] moves the history counter by exactly [by] and the reference
    /// counter not at all.
    Future<void> expectHistoryMoved(
      String what,
      int by,
      Future<void> Function() write,
    ) async {
      final historyBefore = repo.historyRevision!;
      final referenceBefore = repo.referenceRevision;
      await write();
      await _settle();
      expect(
        repo.historyRevision! - historyBefore,
        by,
        reason:
            '$what moved the history revision by '
            '${repo.historyRevision! - historyBefore}',
      );
      expect(
        repo.referenceRevision,
        referenceBefore,
        reason: '$what moved the reference revision',
      );
    }

    test('S-87c-15 session, segment, effort and observation writes move it', () async {
      expect(repo.historyRevision, isNotNull);

      await expectHistoryMoved(
        'one session row',
        1,
        () => repo.createSession(
          TrainingSession(
            id: 'hist-session-new',
            ownerUserId: 'user-1',
            startedAtMs: fixtureStart,
            endedAtMs: fixtureStart + 3600000,
            createdAtMs: fixtureStart,
            updatedAtMs: fixtureStart,
          ),
        ),
      );

      // Written outside a measured step: this one is deleted later and must
      // carry no rows, so the delete counts one event.
      await repo.createEffort(
        SegmentEffort(
          id: 'hist-effort-empty',
          segmentId: 'hist-seg-0',
          orderIndex: 1,
          effortKind: 'set',
          exerciseId: 'hist-ex-0',
          createdAtMs: fixtureStart,
          updatedAtMs: fixtureStart,
        ),
      );
      await _settle();

      await expectHistoryMoved('two segment rows', 2, () async {
        for (var n = 0; n < 2; n++) {
          await repo.createSegment(
            SessionSegment(
              id: 'hist-seg-new-$n',
              sessionId: 'hist-session-new',
              orderIndex: n,
              segmentType: 'workout',
              name: 'Main Workout',
              createdAtMs: fixtureStart,
              updatedAtMs: fixtureStart,
            ),
          );
        }
      });

      await expectHistoryMoved(
        'one deleted effort',
        1,
        () => repo.deleteEffort('hist-effort-empty'),
      );

      await expectHistoryMoved(
        'two observation rows deleted in one call',
        2,
        () => repo.deleteObservationsForEffort('hist-effort-0'),
      );
    });

    test('S-87c-15 timed instances, foods and exercises leave it alone', () async {
      final historyBefore = repo.historyRevision;
      final referenceBefore = repo.referenceRevision;

      await repo.createTimedInstance(
        timedInstance('hist-effort-1', 1, durationSecs: 60, entryIndex: 1),
      );
      await _settle();
      expect(
        repo.historyRevision,
        historyBefore,
        reason: 'a timed instance is not history the bests read',
      );
      expect(
        repo.referenceRevision,
        referenceBefore,
        reason: 'a timed instance is not reference data either',
      );

      await repo.createFood(_food(id: 'hist-food'));
      await _settle();
      expect(
        repo.historyRevision,
        historyBefore,
        reason: 'a food write moved the history revision',
      );
      expect(
        repo.referenceRevision,
        isNot(referenceBefore),
        reason: 'a food write must move the reference revision',
      );

      final referenceAfterFood = repo.referenceRevision;
      await repo.createExercise(
        Exercise(
          id: 'hist-ex-new',
          name: 'History Row',
          capabilities: const ['reps'],
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await _settle();
      expect(
        repo.historyRevision,
        historyBefore,
        reason: 'an exercise write moved the history revision',
      );
      expect(
        repo.referenceRevision,
        isNot(referenceAfterFood),
        reason: 'an exercise write must move the reference revision',
      );
    });
  });
}
