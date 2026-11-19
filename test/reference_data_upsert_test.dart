// Plan 116, Phase 1 — the repository surface the catalog refresh writes
// through, on both implementations.
//
// Scenario S-19101 (upsert and effort-kind round-trip) of
// `docs/plans/2026-11-04-116-catalog-delivery-plan/2026-11-04-116-catalog-delivery-plan.md`.
//
// The refresh delivers app-authored reference data by id upsert: sport
// categories, disciplines, tags, units, metrics and metric effort kinds
// (D-19101, D-19107). This file covers the seven repository members alone — an
// upserted row reads back unchanged, an upsert replaces in place, effort kinds
// keep their order and are copied on write, and Hive survives a restart. Mock
// cannot remove reference rows, so the D-19108 delete hook is asserted there
// only. Both stores must agree, so the shared cases run over
// `harnessFactories` with plain `test()`: a Hive write inside a widget test's
// FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';

import 'helpers/repository_harness.dart';

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

SportCategory _category([String name = 'Test']) => SportCategory(
  id: 'category-test',
  key: 'test_cat',
  name: name,
  sortOrder: 99,
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

Discipline _discipline([String name = 'Test Discipline']) => Discipline(
  id: 'discipline-test',
  categoryId: 'category-test',
  key: 'test_disc',
  name: name,
  createdAtMs: _atMs,
  updatedAtMs: _atMs,
);

Tag _tag([String name = 'Test Tag']) =>
    Tag(id: 'tag-test', name: name, createdAtMs: _atMs);

UnitModel _unit([String name = 'Testunits']) => UnitModel(
  id: 'unit-test',
  key: 'tst',
  name: name,
  unitType: 'count',
  createdAtMs: _atMs,
);

MetricDefinition _metric([String name = 'Test Metric']) => MetricDefinition(
  id: 'metric-test',
  key: 'test',
  name: name,
  dataType: 'int',
  defaultUnitId: 'unit-test',
  createdAtMs: _atMs,
);

/// The tag row [id], read through the list getter the interface offers.
Future<Tag?> _tagById(WorkoutRepository repo, String id) async {
  final rows = await repo.getTags();
  final matches = rows.where((t) => t.id == id);
  return matches.isEmpty ? null : matches.first;
}

/// Asserts every row S-19101 writes reads back as [renamed] implies.
Future<void> _expectRows(
  WorkoutRepository repo, {
  required bool renamed,
}) async {
  final suffix = renamed ? ' 2' : '';

  expect(
    (await repo.getSportCategoryById('category-test'))?.toMap(),
    equals(_category('Test$suffix').toMap()),
  );
  expect(
    (await repo.getDisciplineById('discipline-test'))?.toMap(),
    equals(_discipline('Test Discipline$suffix').toMap()),
  );
  expect(
    (await _tagById(repo, 'tag-test'))?.toMap(),
    equals(_tag('Test Tag$suffix').toMap()),
  );
  expect(
    (await repo.getUnitById('unit-test'))?.toMap(),
    equals(_unit('Testunits$suffix').toMap()),
  );
  expect(
    (await repo.getMetricById('metric-test'))?.toMap(),
    equals(_metric('Test Metric$suffix').toMap()),
  );
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — reference data upsert', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test('S-19101 an upserted row reads back, then the rename', () async {
        // A fresh install starts with no row of the fixture's ids.
        expect(await repo.getSportCategoryById('category-test'), isNull);
        expect(await repo.getDisciplineById('discipline-test'), isNull);
        expect(await _tagById(repo, 'tag-test'), isNull);
        expect(await repo.getUnitById('unit-test'), isNull);
        expect(await repo.getMetricById('metric-test'), isNull);

        await repo.upsertSportCategory(_category());
        await repo.upsertDiscipline(_discipline());
        await repo.upsertTag(_tag());
        await repo.upsertUnit(_unit());
        await repo.upsertMetricDefinition(_metric());

        await _expectRows(repo, renamed: false);

        await repo.upsertSportCategory(_category('Test 2'));
        await repo.upsertDiscipline(_discipline('Test Discipline 2'));
        await repo.upsertTag(_tag('Test Tag 2'));
        await repo.upsertUnit(_unit('Testunits 2'));
        await repo.upsertMetricDefinition(_metric('Test Metric 2'));

        await _expectRows(repo, renamed: true);

        // An upsert replaces the row under the same id rather than adding one.
        final disciplines = await repo.getDisciplines();
        expect(
          disciplines.where((d) => d.id == 'discipline-test'),
          hasLength(1),
          reason: 'the second upsert replaces the row in place',
        );
      });

      test(
        'S-19101 a fresh install carries the bundled effort kinds',
        () async {
          expect(
            await repo.getMetricEffortKinds('metric-pace'),
            equals(['interval']),
          );
          expect(await repo.getMetricEffortKinds('metric-none'), isEmpty);
        },
      );

      test('S-19101 effort kinds keep their order and are copied', () async {
        await repo.upsertMetricDefinition(_metric());

        final kinds = ['set', 'timed'];
        await repo.setMetricEffortKinds('metric-test', kinds);
        kinds.add('round');

        expect(
          await repo.getMetricEffortKinds('metric-test'),
          equals(['set', 'timed']),
        );
        final timedIds = (await repo.getMetricsForEffortKind(
          'timed',
        )).map((m) => m.id);
        expect(timedIds, contains('metric-test'));
      });

      test('S-19101 a Hive restart keeps every value', () async {
        await repo.upsertSportCategory(_category());
        await repo.upsertDiscipline(_discipline());
        await repo.upsertTag(_tag());
        await repo.upsertUnit(_unit());
        await repo.upsertMetricDefinition(_metric());
        await repo.setMetricEffortKinds('metric-test', ['set', 'timed']);

        if (harness.name != 'Hive') return;

        repo = await harness.restart();

        await _expectRows(repo, renamed: false);
        expect(
          await repo.getMetricEffortKinds('metric-test'),
          equals(['set', 'timed']),
        );
        expect(
          await repo.getMetricEffortKinds('metric-pace'),
          equals(['interval']),
        );
      });

      test('S-19101 the Mock delete hook removes one row only', () async {
        if (harness.name != 'Mock') return;

        final mock = repo as MockWorkoutRepository;
        await repo.upsertDiscipline(_discipline());

        await mock.deleteReferenceRowForTest('disciplines', 'discipline-test');
        expect(await repo.getDisciplineById('discipline-test'), isNull);

        await expectLater(
          mock.deleteReferenceRowForTest('equipment', 'x'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  }
}
