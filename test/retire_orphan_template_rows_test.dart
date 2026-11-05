// Plan 117, Phase 2 — the one-time removal of the retired seed template rows,
// scenarios S-19201..S-19209 of
// `docs/plans/2026-11-04-117-retire-orphan-template-rows-plan/2026-11-04-117-retire-orphan-template-rows-plan.md`.
//
// The first-install seed used to write four template segments, six efforts and
// five targets for four templates nothing creates. Step 17
// `retireOrphanTemplateRows` removes exactly those rows, once, from phones that
// already hold them. That is a deliberate exception to the catalog refresh's
// never-delete rule (D-19201/D-19203): a row goes only when its id is one of
// the retired ids AND the retired template at the head of its chain does not
// exist, so a live parent or a user row under a retired segment keeps its
// chain. Both stores must agree, so the shared cases run over
// `harnessFactories` with plain `test()`: a Hive write inside a widget test's
// FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/data_version.dart';
import 'package:omnitrain/core/constants/retired_template_seed.dart';
import 'package:omnitrain/core/services/data_migration_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/hive_workout_repository.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

const String _stepName = 'retireOrphanTemplateRows';

/// The staged retired rows: 4 segments, 6 efforts, 5 targets.
const int _stagedRetiredRows = 15;

/// Records `deleteTemplate*` calls, then calls super.
class _CountingDeleteRepo extends MockWorkoutRepository {
  final List<String> deleted = [];

  @override
  Future<void> deleteTemplateSegment(String id) async {
    deleted.add('segment:$id');
    await super.deleteTemplateSegment(id);
  }

  @override
  Future<void> deleteTemplateEffort(String id) async {
    deleted.add('effort:$id');
    await super.deleteTemplateEffort(id);
  }

  @override
  Future<void> deleteTemplateTarget(String id) async {
    deleted.add('target:$id');
    await super.deleteTemplateTarget(id);
  }
}

/// Throws on every effort delete while [failing]; otherwise calls super.
class _FailingEffortDeleteRepo extends MockWorkoutRepository {
  bool failing = true;

  @override
  Future<void> deleteTemplateEffort(String id) async {
    if (failing) throw StateError('simulated');
    await super.deleteTemplateEffort(id);
  }
}

TemplateSegment _retiredSegment(String id, String templateId) =>
    TemplateSegment(
      id: id,
      templateId: templateId,
      orderIndex: 0,
      segmentType: 'strength_sets',
      name: 'Retired',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    );

TemplateEffort _retiredEffort(String id, String segmentId) => TemplateEffort(
  id: id,
  templateSegmentId: segmentId,
  orderIndex: 0,
  effortKind: 'set',
  createdAtMs: _atMs,
);

TemplateTarget _retiredTarget(String id, String effortId) => TemplateTarget(
  id: id,
  templateEffortId: effortId,
  metricId: 'metric-reps',
  setIndex: 0,
  targetInt: 5,
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

/// Stages one row for every retired id, with no parent template.
Future<void> _stageOrphans(WorkoutRepository repo) async {
  for (final entry in RetiredTemplateSeed.segmentTemplate.entries) {
    await repo.createTemplateSegment(_retiredSegment(entry.key, entry.value));
  }
  for (final entry in RetiredTemplateSeed.effortSegment.entries) {
    await repo.createTemplateEffort(_retiredEffort(entry.key, entry.value));
  }
  for (final entry in RetiredTemplateSeed.targetEffort.entries) {
    await repo.createTemplateTarget(_retiredTarget(entry.key, entry.value));
  }
}

/// The rows the four retired templates hold: segments, their efforts, their
/// targets.
Future<int> _retiredRowCount(WorkoutRepository repo) async {
  var count = 0;
  for (final templateId in RetiredTemplateSeed.templateIds) {
    final segments = await repo.getTemplateSegments(templateId);
    count += segments.length;
    for (final segment in segments) {
      final efforts = await repo.getTemplateEfforts(segment.id);
      count += efforts.length;
      for (final effort in efforts) {
        count += (await repo.getTemplateTargets(effort.id)).length;
      }
    }
  }
  return count;
}

/// The ordered migration steps of whichever store [repo] is.
List<DataMigrationStep> _steps(WorkoutRepository repo) =>
    repo is MockWorkoutRepository
    ? repo.dataMigrationStepsForTest()
    : (repo as HiveWorkoutRepository).dataMigrationStepsForTest();

/// Runs the cleanup step alone, as the migration service would.
Future<void> _runStep(WorkoutRepository repo) async {
  await _steps(repo).firstWhere((step) => step.name == _stepName).run();
}

/// The user's own routine: `tpl-user` → `seg-user` → `eff-user` → `tar-user`.
Future<void> _stageUserRoutine(WorkoutRepository repo) async {
  await repo.createTemplate(
    WorkoutTemplate(
      id: 'tpl-user',
      name: 'My routine',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  await repo.createTemplateSegment(
    TemplateSegment(
      id: 'seg-user',
      templateId: 'tpl-user',
      orderIndex: 0,
      segmentType: 'strength_sets',
      name: 'Main',
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
  await repo.createTemplateEffort(
    TemplateEffort(
      id: 'eff-user',
      templateSegmentId: 'seg-user',
      orderIndex: 0,
      effortKind: 'set',
      createdAtMs: _atMs,
    ),
  );
  await repo.createTemplateTarget(
    TemplateTarget(
      id: 'tar-user',
      templateEffortId: 'eff-user',
      metricId: 'metric-reps',
      setIndex: 0,
      targetInt: 8,
      createdAtMs: _atMs,
      updatedAtMs: _atMs,
    ),
  );
}

/// Every stored row of the user routine, in chain order, as maps.
Future<List<Map<String, dynamic>>> _userMaps(WorkoutRepository repo) async {
  final maps = <Map<String, dynamic>>[];
  final template = await repo.getTemplateById('tpl-user');
  if (template != null) maps.add(template.toMap());
  for (final segment in await repo.getTemplateSegments('tpl-user')) {
    maps.add(segment.toMap());
    for (final effort in await repo.getTemplateEfforts(segment.id)) {
      maps.add(effort.toMap());
      for (final target in await repo.getTemplateTargets(effort.id)) {
        maps.add(target.toMap());
      }
    }
  }
  return maps;
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — retire orphan template rows', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-19201 the staged orphans are removed', () async {
        await _stageOrphans(repo);
        expect(
          await _retiredRowCount(repo),
          _stagedRetiredRows,
          reason: '4 segments + 6 efforts + 5 targets are staged',
        );

        await _runStep(repo);

        expect(await _retiredRowCount(repo), 0);
      });

      test('S-19202 the user routine is untouched', () async {
        await _stageUserRoutine(repo);
        await _stageOrphans(repo);
        final before = await _userMaps(repo);
        expect(
          before,
          hasLength(4),
          reason: 'template, segment, effort, target',
        );

        await _runStep(repo);

        expect(await _userMaps(repo), equals(before));
        expect(await _retiredRowCount(repo), 0);
      });

      test('S-19203 a retired id under a live parent is kept', () async {
        await repo.createTemplate(
          WorkoutTemplate(
            id: 'template-easy-run',
            name: 'Mine',
            createdAtMs: _atMs,
            updatedAtMs: _atMs,
          ),
        );
        await _stageOrphans(repo);

        await _runStep(repo);

        expect(
          (await repo.getTemplateSegments(
            'template-easy-run',
          )).map((s) => s.id),
          contains('tseg-run-1'),
        );
        expect(
          (await repo.getTemplateEfforts('tseg-run-1')).map((e) => e.id),
          contains('teff-run-main'),
        );
        expect(
          (await repo.getTemplateTargets('teff-run-main')).map((t) => t.id),
          contains('ttar-run-duration'),
        );
        for (final templateId in RetiredTemplateSeed.templateIds) {
          if (templateId == 'template-easy-run') continue;
          expect(
            await repo.getTemplateSegments(templateId),
            isEmpty,
            reason: 'the 12 rows under the three missing parents are gone',
          );
        }
        expect(await _retiredRowCount(repo), 3);
      });

      test('S-19204 a user row under a retired segment keeps it', () async {
        await _stageOrphans(repo);
        await repo.createTemplateEffort(
          TemplateEffort(
            id: 'eff-user-under-retired',
            templateSegmentId: 'tseg-upper-1',
            orderIndex: 9,
            effortKind: 'set',
            createdAtMs: _atMs,
          ),
        );

        await _runStep(repo);

        expect(
          (await repo.getTemplateEfforts('tseg-upper-1')).map((e) => e.id),
          equals(['eff-user-under-retired']),
        );
        expect(
          (await repo.getTemplateSegments(
            'template-upper-strength',
          )).map((s) => s.id),
          equals(['tseg-upper-1']),
        );
        expect(
          await repo.getTemplateTargets('teff-upper-bench'),
          isEmpty,
          reason: 'the retired effort and its targets are gone',
        );
        expect(await _retiredRowCount(repo), 2);
      });

      test(
        'S-19208 a user segment under a retired template id is kept',
        () async {
          await _stageOrphans(repo);
          await repo.createTemplateSegment(
            TemplateSegment(
              id: 'seg-user-under-retired-template',
              templateId: 'template-mobility',
              orderIndex: 5,
              segmentType: 'strength_sets',
              name: 'Mine',
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );
          await repo.createTemplateEffort(
            TemplateEffort(
              id: 'eff-user-in-seg',
              templateSegmentId: 'seg-user-under-retired-template',
              orderIndex: 0,
              effortKind: 'set',
              createdAtMs: _atMs,
            ),
          );
          await repo.createTemplateSegment(
            TemplateSegment(
              id: 'seg-user-empty-under-retired-template',
              templateId: 'template-mobility',
              orderIndex: 6,
              segmentType: 'strength_sets',
              name: 'Mine too',
              createdAtMs: _atMs,
              updatedAtMs: _atMs,
            ),
          );

          await _runStep(repo);

          final segments = await repo.getTemplateSegments('template-mobility');
          expect(
            segments.map((s) => s.id),
            unorderedEquals([
              'seg-user-under-retired-template',
              'seg-user-empty-under-retired-template',
            ]),
            reason:
                'a segment id outside the retired set is kept, whether or '
                'not it holds rows',
          );
          expect(
            (await repo.getTemplateEfforts(
              'seg-user-under-retired-template',
            )).map((e) => e.id),
            equals(['eff-user-in-seg']),
          );
          expect(
            segments.map((s) => s.id),
            isNot(contains('tseg-mobility-1')),
            reason: 'the retired segment is gone',
          );
          expect(
            (await repo.getTemplateEfforts(
              'tseg-mobility-1',
            )).map((e) => e.id),
            isNot(contains('teff-mobility-stretch')),
            reason: 'the retired effort is gone',
          );
          expect(
            (await repo.getTemplateTargets(
              'teff-mobility-stretch',
            )).map((t) => t.id),
            isNot(contains('ttar-stretch-duration')),
            reason: 'the retired target is gone',
          );
        },
      );

      test('S-19209 a user target under a retired effort is kept', () async {
        await _stageOrphans(repo);
        await repo.createTemplateTarget(
          TemplateTarget(
            id: 'tar-user-under-retired',
            templateEffortId: 'teff-run-main',
            metricId: 'metric-reps',
            setIndex: 1,
            targetInt: 8,
            createdAtMs: _atMs,
            updatedAtMs: _atMs,
          ),
        );
        final beforeTarget = (await repo.getTemplateTargets('teff-run-main'))
            .firstWhere((t) => t.id == 'tar-user-under-retired')
            .toMap();

        await _runStep(repo);

        final targets = await repo.getTemplateTargets('teff-run-main');
        expect(
          targets.map((t) => t.id),
          equals(['tar-user-under-retired']),
          reason: 'the retired target goes, the user target stays',
        );
        expect(
          targets.single.toMap(),
          equals(beforeTarget),
          reason: 'the user target is stored unchanged',
        );
        expect(
          (await repo.getTemplateEfforts('tseg-run-1')).map((e) => e.id),
          equals(['teff-run-main']),
          reason: 'the retired effort is kept because a target remains',
        );
        expect(
          (await repo.getTemplateSegments('template-easy-run')).map((s) => s.id),
          equals(['tseg-run-1']),
          reason: 'the retired segment is kept because an effort remains',
        );
        for (final templateId in RetiredTemplateSeed.templateIds) {
          if (templateId == 'template-easy-run') continue;
          expect(
            await repo.getTemplateSegments(templateId),
            isEmpty,
            reason: 'the other three retired chains are gone',
          );
        }
        expect(await _retiredRowCount(repo), 3);
      });

      test('S-19205 a second run changes nothing', () async {
        await _stageUserRoutine(repo);
        await _stageOrphans(repo);

        await _runStep(repo);
        final countAfterFirst = await _retiredRowCount(repo);
        final mapsAfterFirst = await _userMaps(repo);
        expect(countAfterFirst, 0);

        await _runStep(repo);

        expect(await _retiredRowCount(repo), equals(countAfterFirst));
        expect(await _userMaps(repo), equals(mapsAfterFirst));
      });

      test('S-19205 a fresh install holds no retired row', () async {
        expect(await _retiredRowCount(repo), 0);
        for (final templateId in RetiredTemplateSeed.templateIds) {
          expect(await repo.getTemplateSegments(templateId), isEmpty);
        }
      });

      test('S-19207 the version sequence ends at the cleanup step', () async {
        expect(currentDataVersion, 17);
        final steps = _steps(repo);
        expect(steps.last.targetVersion, 17);
        expect(steps.last.name, _stepName);
      });

      test('S-19207 an install at version 16 lands at 17', () async {
        await repo.setDataVersion(16);
        await _stageOrphans(repo);

        await DataMigrationService(
          repository: repo,
          targetVersion: currentDataVersion,
          steps: _steps(repo),
        ).run();

        expect(await repo.getDataVersion(), 17);
        expect(await _retiredRowCount(repo), 0);
      });
    });
  }

  test(
    'S-19205 the counting store records no delete on the second run',
    () async {
      final repo = _CountingDeleteRepo();
      await repo.initialize();
      await _stageOrphans(repo);

      await _runStep(repo);

      expect(repo.deleted, hasLength(_stagedRetiredRows));
      expect(
        repo.deleted.where((id) => id.startsWith('segment:')),
        hasLength(4),
      );
      expect(
        repo.deleted.where((id) => id.startsWith('effort:')),
        hasLength(6),
      );
      expect(
        repo.deleted.where((id) => id.startsWith('target:')),
        hasLength(5),
      );

      repo.deleted.clear();
      await _runStep(repo);

      expect(repo.deleted, isEmpty, reason: 'nothing is left to delete');
    },
  );

  test('S-19206 an interrupted run leaves the chain and retries', () async {
    final repo = _FailingEffortDeleteRepo();
    await repo.initialize();
    await _stageOrphans(repo);

    await expectLater(_runStep(repo), throwsA(isA<StateError>()));

    expect(
      (await repo.getTemplateSegments(
        'template-upper-strength',
      )).map((s) => s.id),
      contains('tseg-upper-1'),
      reason: 'deletion is bottom-up, so the segment survives the throw',
    );
    expect(
      (await repo.getTemplateEfforts('tseg-upper-1')).map((e) => e.id),
      contains('teff-upper-bench'),
    );

    repo.failing = false;
    await _runStep(repo);

    expect(await _retiredRowCount(repo), 0);
  });
}
