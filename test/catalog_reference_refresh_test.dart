// Plan 116, Phase 2b1 — the v16 reference-data refresh, on both
// implementations.
//
// Scenarios S-19102 (a v15 install missing reference rows refreshes to v16),
// S-19103 (user rows that share a name or key stay byte-identical) and S-19104
// (app-owned drift is corrected; timestamp-only and order-only differences are
// not) of
// `docs/plans/2026-11-04-116-catalog-delivery-plan/2026-11-04-116-catalog-delivery-plan.md`.
//
// The refresh delivers app-authored reference data by id upsert: sport
// categories, disciplines, tags, units, metrics and metric effort kinds
// (D-19101, D-19107). A v15 device that never received a bundled row gets it
// back; a user row whose name or key clashes with a bundled row is never read
// or written (D-19102); and a row the app owns is restored to the bundle while
// its timestamps and the stored order of its effort kinds are left alone.
// Mock cannot remove reference rows, so the D-19108 hook stages the missing
// row there and the Hive box does it on the store. Both stores must agree, so
// the shared cases run over `harnessFactories` with plain `test()`: a Hive
// write inside a widget test's FakeAsync never completes.

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:omnitrain/core/constants/catalog_version.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';

import 'helpers/repository_harness.dart';

/// The production catalog source, so the refresh runs the same legs it runs on
/// a device.
const BundledCatalogSource _source = BundledCatalogSource();

/// A fixed timestamp: the fixtures take no clock reading.
const int _atMs = 1700000000000;

/// The D-19102 compared fields of each model. Timestamps are never compared,
/// because bundled rows carry `DateTime.now()` from class load.
const List<String> _categoryFields = [
  'key',
  'name',
  'description',
  'icon_name',
  'sort_order',
  'deleted_at_ms',
];
const List<String> _disciplineFields = ['category_id', 'key', 'name'];
const List<String> _tagFields = ['name'];
const List<String> _unitFields = ['key', 'name', 'unit_type'];
const List<String> _metricFields = [
  'key',
  'name',
  'data_type',
  'default_unit_id',
  'is_core',
  'applies_to_effort_kind',
];

/// The D-19102 compared fields of [map], so two rows can be compared without
/// their timestamps.
Map<String, dynamic> _pick(Map<String, dynamic> map, List<String> fields) => {
  for (final field in fields) field: map[field],
};

/// Stage a device that never received [id]: removes the row from the store
/// [box] names (the Hive box name). Mock goes through the D-19108 hook, Hive
/// through the box.
Future<void> _stageMissing(
  RepositoryHarness harness,
  WorkoutRepository repo,
  String box,
  String id,
) async {
  if (harness.name == 'Mock') {
    await (repo as MockWorkoutRepository).deleteReferenceRowForTest(box, id);
  } else if (box == 'metric_effort_kinds') {
    await Hive.box<List>(box).delete(id);
  } else {
    await Hive.box<Map>(box).delete(id);
  }
}

/// The bundled sport category [id].
SportCategory _bundledCategory(String id) =>
    SeedData.sampleSportCategories.firstWhere((row) => row.id == id);

/// The bundled discipline [id].
Discipline _bundledDiscipline(String id) =>
    SeedData.sampleDisciplines.firstWhere((row) => row.id == id);

/// The bundled tag [id].
Tag _bundledTag(String id) =>
    SeedData.sampleTags.firstWhere((row) => row.id == id);

/// The bundled unit [id].
UnitModel _bundledUnit(String id) =>
    SeedData.defaultUnits.firstWhere((row) => row.id == id);

/// The bundled metric [id].
MetricDefinition _bundledMetric(String id) =>
    SeedData.defaultMetrics.firstWhere((row) => row.id == id);

/// The bundled effort kinds of [metricId], in bundled order.
List<String> _bundledKinds(String metricId) =>
    const BundledCatalogSource().metricEffortKinds[metricId] ?? const [];

/// The tag row [id], read through the list getter the interface offers.
Future<Tag?> _tagById(WorkoutRepository repo, String id) async {
  final rows = await repo.getTags();
  final matches = rows.where((t) => t.id == id);
  return matches.isEmpty ? null : matches.first;
}

/// A copy of the bundled discipline [id] with an optional rename.
Discipline _disciplineAs(String id, {String? name, int atMs = _atMs}) {
  final bundled = _bundledDiscipline(id);
  return Discipline(
    id: bundled.id,
    categoryId: bundled.categoryId,
    key: bundled.key,
    name: name ?? bundled.name,
    createdAtMs: atMs,
    updatedAtMs: atMs,
  );
}

/// A copy of the bundled unit [id] with an optional rename.
UnitModel _unitAs(String id, {String? name, int atMs = _atMs}) {
  final bundled = _bundledUnit(id);
  return UnitModel(
    id: bundled.id,
    key: bundled.key,
    name: name ?? bundled.name,
    unitType: bundled.unitType,
    createdAtMs: atMs,
  );
}

/// A copy of the bundled tag [id] with an optional rename.
Tag _tagAs(String id, {String? name, int atMs = _atMs}) {
  final bundled = _bundledTag(id);
  return Tag(id: bundled.id, name: name ?? bundled.name, createdAtMs: atMs);
}

/// A copy of the bundled sport category [id] with an optional new sort order
/// or a soft-delete stamp.
SportCategory _categoryAs(
  String id, {
  int? sortOrder,
  bool deleted = false,
  int atMs = _atMs,
}) {
  final bundled = _bundledCategory(id);
  return SportCategory(
    id: bundled.id,
    key: bundled.key,
    name: bundled.name,
    description: bundled.description,
    iconName: bundled.iconName,
    sortOrder: sortOrder ?? bundled.sortOrder,
    createdAtMs: atMs,
    updatedAtMs: atMs,
    deletedAtMs: deleted ? atMs : bundled.deletedAtMs,
  );
}

/// A copy of the bundled metric [id] with an optional rename.
MetricDefinition _metricAs(String id, {String? name, int atMs = _atMs}) {
  final bundled = _bundledMetric(id);
  return MetricDefinition(
    id: bundled.id,
    key: bundled.key,
    name: name ?? bundled.name,
    dataType: bundled.dataType,
    defaultUnitId: bundled.defaultUnitId,
    isCore: bundled.isCore,
    appliesToEffortKind: bundled.appliesToEffortKind,
    createdAtMs: atMs,
  );
}

/// One single-field drift case: the stored row [id] gets [drifted] at [key]
/// (a `toMap` key), and the refresh must put the bundled value back. [field]
/// is the Dart field, for the test name.
class _Drift {
  const _Drift(this.model, this.field, this.id, this.key, this.drifted);
  final String model;
  final String field;
  final String id;
  final String key;
  final Object? drifted;
}

/// Every compared field of D-19102 once: a leg that skips one leaves its
/// drifted value in the store, so that case fails and names the field.
final List<_Drift> _driftCases = [
  const _Drift('SportCategory', 'key', 'category-cardio', 'key', 'drifted_key'),
  const _Drift('SportCategory', 'name', 'category-cardio', 'name', 'Drifted'),
  const _Drift(
    'SportCategory',
    'description',
    'category-cardio',
    'description',
    'Drifted description',
  ),
  const _Drift(
    'SportCategory',
    'iconName',
    'category-cardio',
    'icon_name',
    'drifted_icon',
  ),
  const _Drift(
    'Discipline',
    'categoryId',
    'discipline-running',
    'category_id',
    'category-drifted',
  ),
  const _Drift(
    'Discipline',
    'key',
    'discipline-running',
    'key',
    'drifted_key',
  ),
  const _Drift('UnitModel', 'key', 'unit-lbs', 'key', 'drifted_key'),
  const _Drift(
    'UnitModel',
    'unitType',
    'unit-lbs',
    'unit_type',
    'drifted_type',
  ),
  const _Drift('MetricDefinition', 'key', 'metric-reps', 'key', 'drifted_key'),
  const _Drift(
    'MetricDefinition',
    'dataType',
    'metric-reps',
    'data_type',
    'drifted_type',
  ),
  const _Drift(
    'MetricDefinition',
    'defaultUnitId',
    'metric-reps',
    'default_unit_id',
    'unit-drifted',
  ),
  _Drift(
    'MetricDefinition',
    'isCore',
    'metric-reps',
    'is_core',
    1 - (_bundledMetric('metric-reps').toMap()['is_core'] as int),
  ),
  const _Drift(
    'MetricDefinition',
    'appliesToEffortKind',
    'metric-reps',
    'applies_to_effort_kind',
    'drifted_kind',
  ),
];

/// The bundled [bundled] map with [drift] applied, checked to differ from the
/// bundle on its one field so the case can never pass vacuously.
Map<String, dynamic> _driftedMap(Map<String, dynamic> bundled, _Drift drift) {
  final map = Map<String, dynamic>.from(bundled)..[drift.key] = drift.drifted;
  expect(
    drift.drifted,
    isNot(equals(bundled[drift.key])),
    reason: '${drift.field} must drift away from the bundled value',
  );
  return map;
}

/// Stage the drifted field of the stored category, refresh, expect the bundle.
Future<void> _expectCategoryDrift(WorkoutRepository repo, _Drift drift) async {
  final bundled = _bundledCategory(drift.id).toMap();
  final map = _driftedMap(bundled, drift);
  await repo.upsertSportCategory(SportCategory.fromMap(map));
  await repo.setCatalogVersion(15);
  await CatalogRefreshService(repo, _source).refresh();
  final stored = await repo.getSportCategoryById(drift.id);
  expect(stored, isNotNull);
  expect(stored!.toMap()[drift.key], equals(bundled[drift.key]));
}

/// Stage the drifted field of the stored discipline, refresh, expect the
/// bundle.
Future<void> _expectDisciplineDrift(WorkoutRepository repo, _Drift drift) async {
  final bundled = _bundledDiscipline(drift.id).toMap();
  final map = _driftedMap(bundled, drift);
  await repo.upsertDiscipline(Discipline.fromMap(map));
  await repo.setCatalogVersion(15);
  await CatalogRefreshService(repo, _source).refresh();
  final stored = await repo.getDisciplineById(drift.id);
  expect(stored, isNotNull);
  expect(stored!.toMap()[drift.key], equals(bundled[drift.key]));
}

/// Stage the drifted field of the stored unit, refresh, expect the bundle.
Future<void> _expectUnitDrift(WorkoutRepository repo, _Drift drift) async {
  final bundled = _bundledUnit(drift.id).toMap();
  final map = _driftedMap(bundled, drift);
  await repo.upsertUnit(UnitModel.fromMap(map));
  await repo.setCatalogVersion(15);
  await CatalogRefreshService(repo, _source).refresh();
  final stored = await repo.getUnitById(drift.id);
  expect(stored, isNotNull);
  expect(stored!.toMap()[drift.key], equals(bundled[drift.key]));
}

/// Stage the drifted field of the stored metric, refresh, expect the bundle.
Future<void> _expectMetricDrift(WorkoutRepository repo, _Drift drift) async {
  final bundled = _bundledMetric(drift.id).toMap();
  final map = _driftedMap(bundled, drift);
  await repo.upsertMetricDefinition(MetricDefinition.fromMap(map));
  await repo.setCatalogVersion(15);
  await CatalogRefreshService(repo, _source).refresh();
  final stored = await repo.getMetricById(drift.id);
  expect(stored, isNotNull);
  expect(stored!.toMap()[drift.key], equals(bundled[drift.key]));
}

/// Records `'<method>:<id>'` for every reference write, then calls super.
class _CountingReferenceRepo extends MockWorkoutRepository {
  final List<String> writes = [];

  @override
  Future<void> upsertSportCategory(SportCategory category) async {
    writes.add('upsertSportCategory:${category.id}');
    await super.upsertSportCategory(category);
  }

  @override
  Future<void> upsertDiscipline(Discipline discipline) async {
    writes.add('upsertDiscipline:${discipline.id}');
    await super.upsertDiscipline(discipline);
  }

  @override
  Future<void> upsertTag(Tag tag) async {
    writes.add('upsertTag:${tag.id}');
    await super.upsertTag(tag);
  }

  @override
  Future<void> upsertUnit(UnitModel unit) async {
    writes.add('upsertUnit:${unit.id}');
    await super.upsertUnit(unit);
  }

  @override
  Future<void> upsertMetricDefinition(MetricDefinition metric) async {
    writes.add('upsertMetricDefinition:${metric.id}');
    await super.upsertMetricDefinition(metric);
  }

  @override
  Future<void> setMetricEffortKinds(
    String metricId,
    List<String> effortKinds,
  ) async {
    writes.add('setMetricEffortKinds:$metricId');
    await super.setMetricEffortKinds(metricId, effortKinds);
  }
}

/// Throws on the 2nd upsertDiscipline call while [failing]; otherwise calls
/// super.
class _FailingDisciplineRepo extends MockWorkoutRepository {
  bool failing = true;
  int calls = 0;

  @override
  Future<void> upsertDiscipline(Discipline discipline) async {
    calls++;
    if (failing && calls == 2) {
      throw StateError('simulated mid-refresh failure');
    }
    await super.upsertDiscipline(discipline);
  }
}

/// Records the stored state of every bundled-id row of the five reference
/// kinds, plus every bundled metric's effort kinds, keyed `'<kind>/<id>'`.
Future<Map<String, Map<String, dynamic>>> _recordReference(
  WorkoutRepository repo,
) async {
  final recorded = <String, Map<String, dynamic>>{};

  for (final row in SeedData.sampleSportCategories) {
    recorded['sport_categories/${row.id}'] =
        (await repo.getSportCategoryById(row.id))!.toMap();
  }
  for (final row in SeedData.sampleDisciplines) {
    recorded['disciplines/${row.id}'] =
        (await repo.getDisciplineById(row.id))!.toMap();
  }
  for (final row in SeedData.sampleTags) {
    recorded['tags/${row.id}'] = (await _tagById(repo, row.id))!.toMap();
  }
  for (final row in SeedData.defaultUnits) {
    recorded['units/${row.id}'] = (await repo.getUnitById(row.id))!.toMap();
  }
  for (final row in SeedData.defaultMetrics) {
    recorded['metrics/${row.id}'] = (await repo.getMetricById(row.id))!.toMap();
  }
  for (final metricId in const BundledCatalogSource().metricEffortKinds.keys) {
    recorded['metric_effort_kinds/$metricId'] = {
      'kinds': await repo.getMetricEffortKinds(metricId),
    };
  }

  return recorded;
}

/// The names of every stored equipment row, sorted.
Future<List<String>> _equipmentNames(WorkoutRepository repo) async {
  final names = (await repo.getEquipment()).map((row) => row.name).toList()
    ..sort();
  return names;
}

/// The ids of every stored food group, archived included, sorted.
Future<List<String>> _foodGroupIds(WorkoutRepository repo) async {
  final rows = await repo.getFoodGroups(includeArchived: true);
  final ids = rows.map((row) => row.id).toList()..sort();
  return ids;
}

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group('${harness.name} — catalog reference refresh from a v15 install', () {
      late WorkoutRepository repo;

      setUp(() async => repo = await harness.open());
      tearDown(() async => await harness.close());

      test(
        'S-19102 a v15 install missing reference rows refreshes to v16',
        () async {
          // Step 1: the six rows a v15 device never received.
          await _stageMissing(
            harness,
            repo,
            'sport_categories',
            'category-recovery',
          );
          await _stageMissing(
            harness,
            repo,
            'disciplines',
            'discipline-climbing',
          );
          await _stageMissing(harness, repo, 'tags', 'tag-core');
          await _stageMissing(harness, repo, 'units', 'unit-cm');
          await _stageMissing(harness, repo, 'metrics', 'metric-pace');
          await _stageMissing(
            harness,
            repo,
            'metric_effort_kinds',
            'metric-pace',
          );

          // Step 2: each is absent before the refresh.
          expect(await repo.getSportCategoryById('category-recovery'), isNull);
          expect(await repo.getDisciplineById('discipline-climbing'), isNull);
          expect(await _tagById(repo, 'tag-core'), isNull);
          expect(await repo.getUnitById('unit-cm'), isNull);
          expect(await repo.getMetricById('metric-pace'), isNull);
          expect(await repo.getMetricEffortKinds('metric-pace'), isEmpty);

          // Step 3: the exercise that points at the missing discipline.
          final exercise = await repo.getExerciseById(
            'exercise-climbing-session',
          );
          expect(exercise, isNotNull);
          expect(
            exercise!.disciplineId,
            equals('discipline-climbing'),
            reason: 'the bundled exercise keeps its bundled discipline',
          );

          // Step 4: the literal version a v15 device holds.
          await repo.setCatalogVersion(15);

          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isTrue,
            reason: 'a v15 device is behind the bundled version',
          );
          expect(await repo.getCatalogVersion(), equals(16));
          expect(bundledCatalogVersion, equals(16));

          final category = await repo.getSportCategoryById('category-recovery');
          expect(
            category,
            isNotNull,
            reason: 'the refresh adds category-recovery',
          );
          expect(category!.key, equals('recovery_rehab'));
          expect(category.name, equals('Recovery / Rehab'));
          expect(category.sortOrder, equals(10));
          expect(
            _pick(category.toMap(), _categoryFields),
            equals(
              _pick(
                _bundledCategory('category-recovery').toMap(),
                _categoryFields,
              ),
            ),
            reason: 'category-recovery came back as the bundled row',
          );

          final discipline = await repo.getDisciplineById(
            'discipline-climbing',
          );
          expect(
            discipline,
            isNotNull,
            reason: 'the refresh adds discipline-climbing',
          );
          expect(discipline!.categoryId, equals('category-sports'));
          expect(discipline.key, equals('climbing'));
          expect(discipline.name, equals('Climbing'));
          expect(
            _pick(discipline.toMap(), _disciplineFields),
            equals(
              _pick(
                _bundledDiscipline('discipline-climbing').toMap(),
                _disciplineFields,
              ),
            ),
            reason: 'discipline-climbing came back as the bundled row',
          );

          final tag = await _tagById(repo, 'tag-core');
          expect(tag, isNotNull, reason: 'the refresh adds tag-core');
          expect(tag!.name, equals('Core'));
          expect(
            _pick(tag.toMap(), _tagFields),
            equals(_pick(_bundledTag('tag-core').toMap(), _tagFields)),
            reason: 'tag-core came back as the bundled row',
          );

          final unit = await repo.getUnitById('unit-cm');
          expect(unit, isNotNull, reason: 'the refresh adds unit-cm');
          expect(unit!.key, equals('cm'));
          expect(unit.name, equals('Centimeters'));
          expect(unit.unitType, equals('length'));
          expect(
            _pick(unit.toMap(), _unitFields),
            equals(_pick(_bundledUnit('unit-cm').toMap(), _unitFields)),
            reason: 'unit-cm came back as the bundled row',
          );

          final metric = await repo.getMetricById('metric-pace');
          expect(metric, isNotNull, reason: 'the refresh adds metric-pace');
          expect(metric!.key, equals('pace'));
          expect(metric.name, equals('Pace (min/km)'));
          expect(metric.dataType, equals('real'));
          expect(metric.defaultUnitId, isNull);
          expect(metric.isCore, isTrue);
          expect(
            _pick(metric.toMap(), _metricFields),
            equals(_pick(_bundledMetric('metric-pace').toMap(), _metricFields)),
            reason: 'metric-pace came back as the bundled row',
          );

          expect(
            await repo.getMetricEffortKinds('metric-pace'),
            equals(['interval']),
          );

          final restored = await repo.getDisciplineById(exercise.disciplineId!);
          expect(
            restored,
            isNotNull,
            reason: 'the exercise points at a discipline that exists again',
          );
          expect(restored!.name, equals('Climbing'));

          final intervalIds = (await repo.getMetricsForEffortKind(
            'interval',
          )).map((m) => m.id);
          expect(intervalIds, contains('metric-pace'));
        },
      );

      test(
        'S-19103 user rows that share a name or key stay byte-identical',
        () async {
          // The same staging as S-19102 steps 1 and 4.
          await _stageMissing(
            harness,
            repo,
            'sport_categories',
            'category-recovery',
          );
          await _stageMissing(
            harness,
            repo,
            'disciplines',
            'discipline-climbing',
          );
          await _stageMissing(harness, repo, 'tags', 'tag-core');
          await _stageMissing(harness, repo, 'units', 'unit-cm');
          await _stageMissing(harness, repo, 'metrics', 'metric-pace');
          await _stageMissing(
            harness,
            repo,
            'metric_effort_kinds',
            'metric-pace',
          );

          // The user's own rows, each a twin of a bundled row that is arriving.
          final userCategory = SportCategory(
            id: 'category-user-recovery',
            key: 'recovery_rehab',
            name: 'Recovery / Rehab',
            sortOrder: 10,
            createdAtMs: _atMs,
            updatedAtMs: _atMs,
          );
          final userDiscipline = Discipline(
            id: 'discipline-user-climbing',
            categoryId: 'category-sports',
            key: 'climbing',
            name: 'Climbing',
            createdAtMs: _atMs,
            updatedAtMs: _atMs,
          );
          final userTag = Tag(
            id: 'tag-user-core',
            name: 'Core',
            createdAtMs: _atMs,
          );
          final userUnit = UnitModel(
            id: 'unit-user-cm',
            key: 'cm',
            name: 'centimeters',
            unitType: 'length',
            createdAtMs: _atMs,
          );
          final userMetric = MetricDefinition(
            id: 'metric-user-pace',
            key: 'pace',
            name: 'Pace (min/km)',
            dataType: 'real',
            createdAtMs: _atMs,
          );

          await repo.upsertSportCategory(userCategory);
          await repo.upsertDiscipline(userDiscipline);
          await repo.upsertTag(userTag);
          await repo.upsertUnit(userUnit);
          await repo.upsertMetricDefinition(userMetric);
          await repo.setMetricEffortKinds('metric-user-pace', [
            'interval',
            'set',
          ]);

          final recordedCategory = userCategory.toMap();
          final recordedDiscipline = userDiscipline.toMap();
          final recordedTag = userTag.toMap();
          final recordedUnit = userUnit.toMap();
          final recordedMetric = userMetric.toMap();
          final recordedKinds = await repo.getMetricEffortKinds(
            'metric-user-pace',
          );

          await repo.setCatalogVersion(15);

          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isTrue,
            reason: 'a v15 device is behind the bundled version',
          );

          // Each user row is byte-identical to its recording.
          expect(
            (await repo.getSportCategoryById(
              'category-user-recovery',
            ))?.toMap(),
            equals(recordedCategory),
          );
          expect(
            (await repo.getDisciplineById('discipline-user-climbing'))?.toMap(),
            equals(recordedDiscipline),
          );
          expect(
            (await _tagById(repo, 'tag-user-core'))?.toMap(),
            equals(recordedTag),
          );
          expect(
            (await repo.getUnitById('unit-user-cm'))?.toMap(),
            equals(recordedUnit),
          );
          expect(
            (await repo.getMetricById('metric-user-pace'))?.toMap(),
            equals(recordedMetric),
          );
          expect(
            await repo.getMetricEffortKinds('metric-user-pace'),
            equals(recordedKinds),
          );

          // The bundled twins are back beside them, and there is no third row.
          expect(
            (await repo.getSportCategories()).where(
              (row) => row.key == 'recovery_rehab',
            ),
            hasLength(2),
          );
          expect(
            (await repo.getDisciplines()).where((row) => row.key == 'climbing'),
            hasLength(2),
          );
          expect(
            (await repo.getTags()).where((row) => row.name == 'Core'),
            hasLength(2),
          );
          expect(
            (await repo.getUnits()).where((row) => row.key == 'cm'),
            hasLength(2),
          );
          expect(
            (await repo.getMetricDefinitions()).where(
              (row) => row.key == 'pace',
            ),
            hasLength(2),
          );
        },
      );

      test(
        'S-19104 app-owned drift is corrected, timestamps and order are not',
        () async {
          // The bundled effort kinds of metric-rpe are set, timed, round, amrap —
          // the premise of the order-only case below.
          expect(
            _bundledKinds('metric-rpe'),
            equals(['set', 'timed', 'round', 'amrap']),
          );

          // Drifted rows: the app owns them, so the bundle wins (D-19101).
          await repo.upsertDiscipline(
            _disciplineAs('discipline-climbing', name: 'Bouldering'),
          );
          await repo.upsertUnit(_unitAs('unit-kg', name: 'Kilos'));
          await repo.upsertSportCategory(
            _categoryAs('category-sports', sortOrder: 99),
          );
          await repo.upsertSportCategory(
            _categoryAs('category-recovery', deleted: true),
          );
          await repo.upsertTag(_tagAs('tag-push', name: 'Pushing'));
          await repo.upsertMetricDefinition(
            _metricAs('metric-rpe', name: 'RPE'),
          );
          await repo.setMetricEffortKinds('metric-extra-weight', ['drill']);

          // Timestamp-only rows: every compared field equals the bundle.
          await repo.upsertDiscipline(_disciplineAs('discipline-running'));
          await repo.upsertUnit(_unitAs('unit-lbs'));
          await repo.upsertTag(_tagAs('tag-legs'));
          await repo.upsertSportCategory(_categoryAs('category-cardio'));
          await repo.upsertMetricDefinition(_metricAs('metric-reps'));

          // Order-only: the same kinds as the bundle, in another order.
          await repo.setMetricEffortKinds('metric-rpe', [
            'amrap',
            'round',
            'timed',
            'set',
          ]);

          // A row the bundle does not carry is never read or written (D-19102).
          final userDiscipline = Discipline(
            id: 'discipline-user-x',
            categoryId: 'category-sports',
            key: 'bouldering',
            name: 'Bouldering',
            createdAtMs: _atMs,
            updatedAtMs: _atMs,
          );
          await repo.upsertDiscipline(userDiscipline);
          final recordedUserDiscipline = userDiscipline.toMap();

          await repo.setCatalogVersion(15);
          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isTrue,
            reason: 'a v15 device is behind the bundled version',
          );

          // Every drifted row is the bundled row again. These rows have no user
          // edit surface, so the bundle owns them (D-19101).
          final climbing = await repo.getDisciplineById('discipline-climbing');
          expect(climbing, isNotNull);
          expect(climbing!.name, equals('Climbing'));
          expect(
            _pick(climbing.toMap(), _disciplineFields),
            equals(
              _pick(
                _bundledDiscipline('discipline-climbing').toMap(),
                _disciplineFields,
              ),
            ),
          );

          final kilo = await repo.getUnitById('unit-kg');
          expect(kilo, isNotNull);
          expect(kilo!.name, equals('Kilograms'));
          expect(
            _pick(kilo.toMap(), _unitFields),
            equals(_pick(_bundledUnit('unit-kg').toMap(), _unitFields)),
          );

          final sports = await repo.getSportCategoryById('category-sports');
          expect(sports, isNotNull);
          expect(sports!.sortOrder, equals(5));
          expect(
            _pick(sports.toMap(), _categoryFields),
            equals(
              _pick(
                _bundledCategory('category-sports').toMap(),
                _categoryFields,
              ),
            ),
          );

          final recovery = await repo.getSportCategoryById('category-recovery');
          expect(recovery, isNotNull);
          expect(recovery!.deletedAtMs, isNull);
          expect(
            _pick(recovery.toMap(), _categoryFields),
            equals(
              _pick(
                _bundledCategory('category-recovery').toMap(),
                _categoryFields,
              ),
            ),
          );

          final push = await _tagById(repo, 'tag-push');
          expect(push, isNotNull);
          expect(push!.name, equals('Push'));
          expect(
            _pick(push.toMap(), _tagFields),
            equals(_pick(_bundledTag('tag-push').toMap(), _tagFields)),
          );

          final rpe = await repo.getMetricById('metric-rpe');
          expect(rpe, isNotNull);
          expect(rpe!.name, equals('RPE (Rate of Perceived Exertion)'));
          expect(
            _pick(rpe.toMap(), _metricFields),
            equals(_pick(_bundledMetric('metric-rpe').toMap(), _metricFields)),
          );

          final extraWeightKinds = await repo.getMetricEffortKinds(
            'metric-extra-weight',
          );
          expect(extraWeightKinds.toSet(), equals({'drill', 'timed'}));
          expect(extraWeightKinds, hasLength(2));

          // The timestamp-only rows keep the timestamps the fixture wrote.
          expect(
            (await repo.getDisciplineById('discipline-running'))!.createdAtMs,
            equals(_atMs),
            reason: 'discipline-running differs only in its timestamp',
          );
          expect(
            (await repo.getUnitById('unit-lbs'))!.createdAtMs,
            equals(_atMs),
            reason: 'unit-lbs differs only in its timestamp',
          );
          expect(
            (await _tagById(repo, 'tag-legs'))!.createdAtMs,
            equals(_atMs),
            reason: 'tag-legs differs only in its timestamp',
          );
          expect(
            (await repo.getSportCategoryById('category-cardio'))!.createdAtMs,
            equals(_atMs),
            reason: 'category-cardio differs only in its timestamp',
          );
          expect(
            (await repo.getMetricById('metric-reps'))!.createdAtMs,
            equals(_atMs),
            reason: 'metric-reps differs only in its timestamp',
          );

          // The order-only row keeps the stored order.
          expect(
            await repo.getMetricEffortKinds('metric-rpe'),
            equals(['amrap', 'round', 'timed', 'set']),
          );

          // A row outside the bundle is identical to its recording.
          expect(
            (await repo.getDisciplineById('discipline-user-x'))?.toMap(),
            equals(recordedUserDiscipline),
          );
        },
      );

      // One case per D-19102 compared field: each starts from the group's
      // fresh store and drifts exactly one field.
      for (final drift in _driftCases) {
        test(
          'S-19104 drift: ${drift.model}.${drift.field} is corrected',
          () async {
            switch (drift.model) {
              case 'SportCategory':
                await _expectCategoryDrift(repo, drift);
              case 'Discipline':
                await _expectDisciplineDrift(repo, drift);
              case 'UnitModel':
                await _expectUnitDrift(repo, drift);
              case 'MetricDefinition':
                await _expectMetricDrift(repo, drift);
            }
          },
        );
      }

      // S-19105 (a): a second refresh is a no-op on both stores.
      test(
        'S-19105 (a) a second refresh leaves every reference row unchanged',
        () async {
          // S-19102's staging: the six rows a v15 device never received.
          await _stageMissing(
            harness,
            repo,
            'sport_categories',
            'category-recovery',
          );
          await _stageMissing(
            harness,
            repo,
            'disciplines',
            'discipline-climbing',
          );
          await _stageMissing(harness, repo, 'tags', 'tag-core');
          await _stageMissing(harness, repo, 'units', 'unit-cm');
          await _stageMissing(harness, repo, 'metrics', 'metric-pace');
          await _stageMissing(
            harness,
            repo,
            'metric_effort_kinds',
            'metric-pace',
          );

          await repo.setCatalogVersion(15);
          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isTrue,
            reason: 'a v15 device is behind the bundled version',
          );
          expect(await repo.getCatalogVersion(), equals(16));

          final recorded = await _recordReference(repo);

          expect(
            await CatalogRefreshService(repo, _source).refresh(),
            isFalse,
            reason: 'the device is already at the bundled version',
          );
          expect(await repo.getCatalogVersion(), equals(16));
          expect(
            await _recordReference(repo),
            equals(recorded),
            reason: 'a second refresh rewrites no reference row',
          );
        },
      );

      // S-19107 (a): a device that already has everything is left alone.
      test('S-19107 (a) a fresh install is unaffected by the refresh', () async {
        final recorded = await _recordReference(repo);
        final recordedEquipment = await _equipmentNames(repo);
        final recordedFoodGroups = await _foodGroupIds(repo);
        expect(recordedEquipment, isNotEmpty);
        expect(recordedFoodGroups, isNotEmpty);

        await repo.setCatalogVersion(15);

        expect(
          await CatalogRefreshService(repo, _source).refresh(),
          isTrue,
          reason: 'a v15 device is behind the bundled version',
        );
        expect(await repo.getCatalogVersion(), equals(16));

        expect(
          await _recordReference(repo),
          equals(recorded),
          reason: 'every bundled reference row is already correct',
        );
        expect(
          await _equipmentNames(repo),
          equals(recordedEquipment),
          reason: 'the refresh writes no equipment row',
        );
        expect(
          await _foodGroupIds(repo),
          equals(recordedFoodGroups),
          reason: 'the refresh writes no food group',
        );
      });
    });
  }

  test('S-19105 (b) Mock: a second run writes no reference row', () async {
    final repo = _CountingReferenceRepo();
    await repo.initialize();
    await repo.setCatalogVersion(15);

    expect(
      await CatalogRefreshService(repo, _source).refresh(),
      isTrue,
      reason: 'a v15 device is behind the bundled version',
    );

    repo.writes.clear();
    await repo.setCatalogVersion(15);

    expect(
      await CatalogRefreshService(repo, _source).refresh(),
      isTrue,
      reason: 'the version was behind again, so the refresh runs again',
    );
    expect(
      repo.writes,
      isEmpty,
      reason: 'a second run over a complete catalog writes no reference row',
    );
  });

  test('S-19107 (b) Mock: a fresh install writes no reference row', () async {
    final repo = _CountingReferenceRepo();
    await repo.initialize();
    await repo.setCatalogVersion(15);

    expect(
      await CatalogRefreshService(repo, _source).refresh(),
      isTrue,
      reason: 'a v15 device is behind the bundled version',
    );
    expect(
      repo.writes,
      isEmpty,
      reason: 'a fresh install already holds every bundled reference row',
    );
  });

  test(
    'S-19106 Mock: an interrupted refresh keeps version 15 and the next launch finishes',
    () async {
      // The failure on the 2nd upsertDiscipline call must land on climbing.
      final golfIndex = SeedData.sampleDisciplines.indexWhere(
        (row) => row.id == 'discipline-golf',
      );
      final climbingIndex = SeedData.sampleDisciplines.indexWhere(
        (row) => row.id == 'discipline-climbing',
      );
      expect(golfIndex, isNonNegative);
      expect(
        golfIndex,
        lessThan(climbingIndex),
        reason: 'golf precedes climbing in the bundled order',
      );

      final repo = _FailingDisciplineRepo();
      await repo.initialize();

      await repo.deleteReferenceRowForTest(
        'sport_categories',
        'category-recovery',
      );
      await repo.deleteReferenceRowForTest('disciplines', 'discipline-golf');
      await repo.deleteReferenceRowForTest(
        'disciplines',
        'discipline-climbing',
      );
      await repo.deleteReferenceRowForTest('units', 'unit-cm');

      await repo.deleteExercise('exercise-sit-up');
      await repo.setExerciseCapabilities('exercise-sit-up', const []);
      await repo.setExerciseMuscleLinks('exercise-sit-up', const []);

      await repo.setCatalogVersion(15);

      await expectLater(
        CatalogRefreshService(repo, _source).refresh(),
        throwsA(isA<StateError>()),
      );

      // The legs before the discipline leg ran; the ones after did not.
      expect(await repo.getCatalogVersion(), equals(15));
      expect(await repo.getSportCategoryById('category-recovery'), isNotNull);
      expect(await repo.getDisciplineById('discipline-golf'), isNotNull);
      expect(await repo.getDisciplineById('discipline-climbing'), isNull);
      expect(await repo.getUnitById('unit-cm'), isNull);
      expect(await repo.getExerciseById('exercise-sit-up'), isNull);

      // The next launch retries from the start and completes.
      repo.failing = false;
      expect(
        await CatalogRefreshService(repo, _source).refresh(),
        isTrue,
        reason: 'the stored version is still 15',
      );
      expect(await repo.getCatalogVersion(), equals(16));
      expect(await repo.getSportCategoryById('category-recovery'), isNotNull);
      expect(await repo.getDisciplineById('discipline-golf'), isNotNull);
      expect(await repo.getDisciplineById('discipline-climbing'), isNotNull);
      expect(await repo.getUnitById('unit-cm'), isNotNull);
      expect(await repo.getExerciseById('exercise-sit-up'), isNotNull);
    },
  );
}
