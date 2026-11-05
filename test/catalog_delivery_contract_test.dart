// Plan 116, S-19108: every public static member of `SeedData` is either
// delivered by the catalog refresh (COVERED, naming its `CatalogSource`
// getter) or excluded with a written reason (EXCLUDED); a new seed list that
// is neither fails here. The food catalog lives in `FoodCatalogSeed`, outside
// `SeedData`, and is carried by `foodCatalog`.
//
// Plain `test()`: no widgets and no Hive, so the whole file is pure parsing
// plus one in-memory Mock store.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/catalog_refresh_service.dart';
import 'package:omnitrain/core/services/catalog_source.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/mock/seed_data.dart';

const String _seedFile = 'lib/mock/seed_data.dart';
const String _sourceFile = 'lib/core/services/bundled_catalog_source.dart';
const List<String> _repositoryFiles = [
  'lib/data/repositories/hive_workout_repository.dart',
  'lib/data/repositories/mock_workout_repository.dart',
];

final RegExp _staticMember = RegExp(
  r'^  static\s+(?:(?:final|const)\s+)?(.+?)\s+(\w+)\s*(?:=|\()',
);
final RegExp _seedReference = RegExp(r'SeedData\.(\w+)');

/// One COVERED row: the [CatalogSource] getter that must carry the member,
/// plus the id sets both sides must agree on.
class _Covered {
  const _Covered(this.getter, this.seedIds, this.sourceIds);

  final String getter;
  final Set<String> Function() seedIds;
  final Set<String> Function(CatalogSource source) sourceIds;
}

/// The store-side counterpart of one row, used by the delivery test:
/// [present] is what the store already holds, [delivered] is what it holds in
/// the bundled shape.
class _StoreProbe {
  const _StoreProbe({required this.present, required this.delivered});

  final Future<Set<String>> Function(WorkoutRepository repo, Set<String> ids)
  present;
  final Future<Set<String>> Function(
    WorkoutRepository repo,
    CatalogSource source,
    Set<String> ids,
  )
  delivered;
}

final Set<String> _members = _parseSeedMembers();

final Map<String, _Covered> _covered = {
  'sampleSportCategories': _Covered(
    'sportCategories',
    () => {for (final row in SeedData.sampleSportCategories) row.id},
    (source) => {for (final row in source.sportCategories) row.id},
  ),
  'sampleDisciplines': _Covered(
    'disciplines',
    () => {for (final row in SeedData.sampleDisciplines) row.id},
    (source) => {for (final row in source.disciplines) row.id},
  ),
  'sampleTags': _Covered(
    'tags',
    () => {for (final row in SeedData.sampleTags) row.id},
    (source) => {for (final row in source.tags) row.id},
  ),
  'defaultUnits': _Covered(
    'units',
    () => {for (final row in SeedData.defaultUnits) row.id},
    (source) => {for (final row in source.units) row.id},
  ),
  'defaultMetrics': _Covered(
    'metricDefinitions',
    () => {for (final row in SeedData.defaultMetrics) row.id},
    (source) => {for (final row in source.metricDefinitions) row.id},
  ),
  'metricApplicability': _Covered(
    'metricEffortKinds',
    () => {for (final row in SeedData.metricApplicability) row.metricId},
    (source) => source.metricEffortKinds.keys.toSet(),
  ),
  'sampleExercises': _Covered(
    'exercises',
    () => {for (final row in SeedData.sampleExercises) row.id},
    (source) => {for (final row in source.exercises) row.id},
  ),
  'exerciseCapabilityRelationships': _Covered(
    'exerciseCapabilities',
    () => SeedData.exerciseCapabilityRelationships.keys.toSet(),
    (source) => source.exerciseCapabilities.keys.toSet(),
  ),
  'sampleMuscleGroups': _Covered(
    'muscleGroups',
    () => {for (final row in SeedData.sampleMuscleGroups) row.id},
    (source) => {for (final row in source.muscleGroups) row.id},
  ),
  'exerciseMuscleLinks': _Covered(
    'exerciseMuscleGroups',
    () => SeedData.exerciseMuscleLinks.keys.toSet(),
    (source) => source.exerciseMuscleGroups.keys.toSet(),
  ),
  'sampleDemoRoutineBundles': _Covered(
    'routineTemplates',
    () => {
      for (final bundle in SeedData.sampleDemoRoutineBundles)
        bundle.template.id,
    },
    (source) => {
      for (final bundle in source.routineTemplates) bundle.template.id,
    },
  ),
};

final Map<String, String> _excluded = {
  'sampleEquipment':
      'Owner decision (plans 115a D-18909, 115b D-19004): no screen reads '
      'equipment, so it reaches new installs only; existing equipment rows and '
      'links are never removed.',
  'exerciseEquipmentRelationships':
      'Owner decision (plans 115a D-18909, 115b D-19004): no screen reads '
      'equipment, so it reaches new installs only; existing equipment rows and '
      'links are never removed.',
  'defaultFoodGroups':
      'The user can rename, archive and delete food groups and there is no '
      'touched-entry marker for them, so delivering would bring back a group '
      'the user deleted; needs an owner decision.',
  'sampleTemplateSegments':
      'Orphan rows of a retired seed: they belong to templates '
      'template-upper-strength, template-easy-run, template-boxing-rounds and '
      'template-mobility, which nothing creates; the demo routines come from '
      'sampleDemoRoutineBundles.',
  'sampleTemplateEfforts':
      'Orphan rows of a retired seed: they belong to templates '
      'template-upper-strength, template-easy-run, template-boxing-rounds and '
      'template-mobility, which nothing creates; the demo routines come from '
      'sampleDemoRoutineBundles.',
  'sampleTemplateTargets':
      'Orphan rows of a retired seed: they belong to templates '
      'template-upper-strength, template-easy-run, template-boxing-rounds and '
      'template-mobility, which nothing creates; the demo routines come from '
      'sampleDemoRoutineBundles.',
  'samplePlannedSessions': 'User-data types; empty lists, never seeded.',
  'sampleTrainingPeriods': 'User-data types; empty lists, never seeded.',
  'sampleTrainingSessions':
      'Developer reference fixtures; never seeded on either store.',
  'sampleSessionSegments':
      'Developer reference fixtures; never seeded on either store.',
  'sampleSessionBlocks':
      'Developer reference fixtures; never seeded on either store.',
  'sampleSegmentEfforts':
      'Developer reference fixtures; never seeded on either store.',
  'sampleConsumedFoods':
      'A user food log; only the Mock store seeds it, for the web/QA build. '
      'User data is never delivered.',
};

final Map<String, _StoreProbe> _probes = {
  'sampleSportCategories': _entityProbe(
    (repo, id) => repo.getSportCategoryById(id),
  ),
  'sampleDisciplines': _entityProbe((repo, id) => repo.getDisciplineById(id)),
  'sampleTags': _idListProbe(
    (repo) async => [for (final row in await repo.getTags()) row.id],
  ),
  'defaultUnits': _entityProbe((repo, id) => repo.getUnitById(id)),
  'defaultMetrics': _entityProbe((repo, id) => repo.getMetricById(id)),
  'metricApplicability': _subCollectionProbe(
    stored: (repo, id) => repo.getMetricEffortKinds(id),
    bundled: (source, id) => source.metricEffortKinds[id] ?? const [],
  ),
  'sampleExercises': _entityProbe((repo, id) => repo.getExerciseById(id)),
  'exerciseCapabilityRelationships': _subCollectionProbe(
    stored: (repo, id) => repo.getExerciseCapabilities(id),
    bundled: (source, id) => source.exerciseCapabilities[id] ?? const [],
  ),
  'sampleMuscleGroups': _idListProbe(
    (repo) async => [for (final row in await repo.getMuscleGroups()) row.id],
  ),
  'exerciseMuscleLinks': _subCollectionProbe(
    stored: (repo, id) async => [
      for (final link in await repo.getExerciseMuscleLinks(id))
        '${link.muscleGroupId}:${link.role.name}',
    ],
    bundled: (source, id) => [
      for (final link
          in source.exerciseMuscleGroups[id] ?? const <ExerciseMuscleLink>[])
        '${link.muscleGroupId}:${link.role.name}',
    ],
  ),
  'sampleDemoRoutineBundles': _entityProbe(
    (repo, id) => repo.getTemplateById(id),
  ),
};

void main() {
  test('1. every SeedData member and repository reference is classified', () {
    expect(
      _members,
      hasLength(24),
      reason:
          'SeedData has ${_members.length} public static members, not the 24 '
          'this table rows; members: ${_sorted(_members)}',
    );
    expect(
      _members,
      contains('sampleExercises'),
      reason: 'the member parser missed the field sampleExercises',
    );
    expect(
      _members,
      contains('sampleConsumedFoods'),
      reason: 'the member parser missed the method sampleConsumedFoods',
    );

    final rows = _rows();
    expect(
      rows,
      hasLength(24),
      reason:
          'the table has ${rows.length} rows; 11 COVERED + 13 EXCLUDED = 24',
    );

    for (final member in _members) {
      expect(
        rows,
        contains(member),
        reason:
            'SeedData.$member is neither COVERED nor EXCLUDED in this table; '
            'deliver it through the catalog refresh or write the reason it is '
            'not delivered',
      );
    }

    for (final name in _repositoryReferences()) {
      expect(
        rows,
        contains(name),
        reason:
            'the repositories read SeedData.$name, which this table does not '
            'classify',
      );
    }
  });

  test('2. every table row names a live SeedData member', () {
    for (final row in _rows()) {
      expect(
        _members,
        contains(row),
        reason:
            'row `$row` is stale: SeedData has no public static member with '
            'that name',
      );
    }
  });

  test('3. every EXCLUDED row carries a written reason', () {
    for (final entry in _excluded.entries) {
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: 'SeedData.${entry.key} is excluded without a written reason',
      );
    }
  });

  test('4. every COVERED row is served by BundledCatalogSource', () {
    final sourceText = File(_sourceFile).readAsStringSync();
    const source = BundledCatalogSource();

    for (final entry in _covered.entries) {
      final member = entry.key;
      final row = entry.value;

      expect(
        sourceText,
        contains('get ${row.getter}'),
        reason: '$_sourceFile has no `get ${row.getter}` for SeedData.$member',
      );
      expect(
        sourceText,
        contains('SeedData.$member'),
        reason: '$_sourceFile never reads SeedData.$member',
      );

      final seedIds = row.seedIds();
      expect(
        seedIds,
        isNotEmpty,
        reason: 'SeedData.$member is classified COVERED but has no ids',
      );
      expect(
        _sorted(row.sourceIds(source)),
        _sorted(seedIds),
        reason:
            'BundledCatalogSource.${row.getter} does not return the ids of '
            'SeedData.$member',
      );
    }
  });

  test(
    '5. the refresh delivers every COVERED row and no EXCLUDED row',
    () async {
      // `initialize()` is deliberately NOT called: an uninitialized Mock is
      // empty of every COVERED member without any wipe hook, and its catalog
      // version starts at 0, so the refresh walks every leg from zero.
      final repo = MockWorkoutRepository();
      const source = BundledCatalogSource();

      for (final entry in _covered.entries) {
        final ids = entry.value.seedIds();
        final present = await _probes[entry.key]!.present(repo, ids);
        expect(
          present,
          isEmpty,
          reason:
              'SeedData.${entry.key} is already stored before the refresh: '
              '${_sorted(present).take(5)}',
        );
      }

      expect(
        await CatalogRefreshService(repo, source).refresh(),
        isTrue,
        reason: 'the refresh did not run on an empty Mock at catalog version 0',
      );

      for (final entry in _covered.entries) {
        final ids = entry.value.seedIds();
        final delivered = await _probes[entry.key]!.delivered(
          repo,
          source,
          ids,
        );
        expect(
          _sorted(delivered),
          _sorted(ids),
          reason: 'the refresh did not deliver SeedData.${entry.key}',
        );
      }

      expect(
        await repo.getEquipment(),
        isEmpty,
        reason: 'the refresh delivered equipment rows, which are EXCLUDED',
      );
      expect(
        await repo.getFoodGroups(includeArchived: true),
        isEmpty,
        reason: 'the refresh delivered default food groups, which are EXCLUDED',
      );
    },
  );
}

Set<String> _rows() => {..._covered.keys, ..._excluded.keys};

List<String> _sorted(Set<String> values) => values.toList()..sort();

Set<String> _parseSeedMembers() {
  final lines = File(_seedFile).readAsLinesSync();
  final start = lines.indexOf('class SeedData {');
  if (start < 0) {
    throw StateError('$_seedFile has no `class SeedData {` line');
  }
  final end = lines.indexOf('}', start);
  if (end < 0) {
    throw StateError('$_seedFile has no closing `}` after class SeedData');
  }

  final names = <String>{};
  for (final line in lines.sublist(start, end)) {
    final match = _staticMember.firstMatch(line);
    if (match == null) continue;
    final name = match.group(2)!;
    if (!name.startsWith('_')) names.add(name);
  }
  return names;
}

Set<String> _repositoryReferences() => {
  for (final path in _repositoryFiles)
    for (final match in _seedReference.allMatches(
      File(path).readAsStringSync(),
    ))
      match.group(1)!,
};

_StoreProbe _entityProbe(
  Future<Object?> Function(WorkoutRepository repo, String id) row,
) {
  Future<Set<String>> existing(WorkoutRepository repo, Set<String> ids) async {
    final found = <String>{};
    for (final id in ids) {
      if (await row(repo, id) != null) found.add(id);
    }
    return found;
  }

  return _StoreProbe(
    present: existing,
    delivered: (repo, _, ids) => existing(repo, ids),
  );
}

_StoreProbe _idListProbe(
  Future<List<String>> Function(WorkoutRepository repo) storedIds,
) {
  Future<Set<String>> existing(WorkoutRepository repo, Set<String> ids) async {
    final stored = (await storedIds(repo)).toSet();
    return {
      for (final id in ids)
        if (stored.contains(id)) id,
    };
  }

  return _StoreProbe(
    present: existing,
    delivered: (repo, _, ids) => existing(repo, ids),
  );
}

_StoreProbe _subCollectionProbe({
  required Future<List<String>> Function(WorkoutRepository repo, String id)
  stored,
  required List<String> Function(CatalogSource source, String id) bundled,
}) {
  return _StoreProbe(
    present: (repo, ids) async {
      final found = <String>{};
      for (final id in ids) {
        if ((await stored(repo, id)).isNotEmpty) found.add(id);
      }
      return found;
    },
    delivered: (repo, source, ids) async {
      final found = <String>{};
      for (final id in ids) {
        if (_sameMultiset(await stored(repo, id), bundled(source, id))) {
          found.add(id);
        }
      }
      return found;
    },
  );
}

bool _sameMultiset(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final left = List<String>.from(a)..sort();
  final right = List<String>.from(b)..sort();
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
