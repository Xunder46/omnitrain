import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/models/muscle_taxonomy.dart';
import 'package:omnitrain/mock/seed_data.dart';

/// One row of plan 118's **New-row table** (D-19202): id suffix, name,
/// movement pattern, capability set, main (P) and assisting (S) muscles,
/// equipment.
class ConditioningCatalogRow {
  const ConditioningCatalogRow(
    this.suffix,
    this.name,
    this.pattern,
    this.caps,
    this.main,
    this.assist,
    this.equipment,
  );

  final String suffix;
  final String name;
  final String? pattern;
  final List<String> caps;
  final List<String> main;
  final List<String> assist;
  final List<String> equipment;
}

/// The Conditioning rows the bundled catalog must carry, in table order.
///
/// Phase 2A of plan 118 shipped rows 1-9 and Phase 2B adds rows 10-17; the
/// global size guards add this list's length (and, for links, its non-empty
/// `main` count).
const List<ConditioningCatalogRow> conditioningCatalogRows = [
  ConditioningCatalogRow(
    'burpee',
    'Burpee',
    null,
    ['reps', 'sets', 'time'],
    ['quads', 'chest'],
    ['glutes', 'triceps', 'front-delts', 'abs'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'squat-thrust',
    'Squat Thrust',
    null,
    ['reps', 'sets', 'time'],
    ['quads', 'abs'],
    ['glutes', 'front-delts'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'box-jump',
    'Box Jump',
    'squat',
    ['reps', 'sets', 'time'],
    ['quads', 'glutes'],
    ['hamstrings', 'calves'],
    [],
  ),
  ConditioningCatalogRow(
    'jump-squat',
    'Jump Squat',
    'squat',
    ['reps', 'sets', 'time'],
    ['quads', 'glutes'],
    ['hamstrings', 'calves'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'tuck-jump',
    'Tuck Jump',
    'squat',
    ['reps', 'sets', 'time'],
    ['quads', 'glutes'],
    ['abs', 'calves'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'broad-jump',
    'Broad Jump',
    'squat',
    ['reps', 'sets', 'time'],
    ['glutes', 'quads'],
    ['hamstrings', 'calves'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'jump-lunge',
    'Jump Lunge',
    'lunge',
    ['reps', 'sets', 'time'],
    ['quads', 'glutes'],
    ['hamstrings', 'calves'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'skater-jump',
    'Skater Jump',
    'lunge',
    ['reps', 'sets', 'time'],
    ['glutes', 'quads'],
    ['hamstrings', 'calves'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'plyo-push-up',
    'Plyo Push-Up',
    'horizontal_push',
    ['reps', 'sets', 'time'],
    ['chest'],
    ['triceps', 'front-delts', 'abs'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'mountain-climber',
    'Mountain Climber',
    'abs',
    ['reps', 'sets', 'time'],
    ['abs'],
    ['quads', 'front-delts'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'bear-crawl',
    'Bear Crawl',
    null,
    ['reps', 'sets', 'time'],
    ['abs', 'front-delts'],
    ['quads', 'triceps'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'jumping-jack',
    'Jumping Jack',
    null,
    ['reps', 'sets', 'time'],
    ['calves'],
    ['glutes', 'side-delts'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'high-knees',
    'High Knees',
    null,
    ['reps', 'sets', 'time'],
    ['quads'],
    ['calves', 'abs'],
    ['bodyweight'],
  ),
  ConditioningCatalogRow(
    'battle-ropes',
    'Battle Ropes',
    null,
    ['reps', 'sets', 'time'],
    ['front-delts'],
    ['side-delts', 'forearms', 'abs'],
    [],
  ),
  ConditioningCatalogRow(
    'medicine-ball-slam',
    'Medicine Ball Slam',
    null,
    ['reps', 'sets', 'load', 'time'],
    ['lats', 'abs'],
    ['triceps', 'glutes'],
    [],
  ),
  ConditioningCatalogRow(
    'wall-ball',
    'Wall Ball',
    'squat',
    ['reps', 'sets', 'load', 'time'],
    ['quads', 'glutes'],
    ['front-delts', 'triceps'],
    [],
  ),
  ConditioningCatalogRow(
    'thruster',
    'Thruster',
    'squat',
    ['reps', 'sets', 'load', 'time'],
    ['quads', 'front-delts'],
    ['glutes', 'triceps', 'abs'],
    ['barbell'],
  ),
];

/// Muscle ids no Conditioning row may link (D-19205): the region ids and the
/// muscles whose 115a/115b exact sets must stay exact.
const List<String> _forbiddenMuscleIds = [
  'muscle-tibialis',
  'muscle-abductors',
  'muscle-adductors',
  'muscle-rotator-cuff',
  'muscle-brachialis',
  'muscle-biceps',
];

/// Asserts the shipped seed row for [row] matches the plan table (S-19202).
void expectConditioningRowMatchesPlan(ConditioningCatalogRow row) {
  final id = 'exercise-${row.suffix}';
  final exercise = {
    for (final e in SeedData.sampleExercises)
      if (e.id == id) e,
  };

  expect(exercise, hasLength(1), reason: 'missing $id');
  final shipped = exercise.single;

  expect(shipped.name, row.name, reason: id);
  expect(shipped.disciplineId, 'discipline-conditioning', reason: id);
  expect(shipped.movementPattern, row.pattern, reason: id);
  expect(shipped.ownerUserId, isNull, reason: id);
  expect(shipped.modality, isNull, reason: id);
  expect(shipped.description?.trim(), isNotEmpty, reason: id);

  final steps = shipped.howToSteps;
  expect(steps, isNotNull, reason: id);
  expect(steps!.length, inInclusiveRange(3, 4), reason: id);
  for (final step in steps) {
    expect(step.trim(), isNotEmpty, reason: id);
  }

  expect(SeedData.exerciseCapabilityRelationships[id], equals(row.caps));
  expect(SeedData.exerciseEquipmentRelationships[id], [
    for (final name in row.equipment) 'equipment-$name',
  ]);

  final links = SeedData.exerciseMuscleLinks[id];
  expect(
    links,
    MuscleTaxonomy.normalize([
      for (final name in row.main)
        ExerciseMuscleLink(
          muscleGroupId: 'muscle-$name',
          role: MuscleRole.primary,
        ),
      for (final name in row.assist)
        ExerciseMuscleLink(
          muscleGroupId: 'muscle-$name',
          role: MuscleRole.secondary,
        ),
    ]),
  );

  for (final link in links ?? const <ExerciseMuscleLink>[]) {
    expect(
      MuscleTaxonomy.isRegion(link.muscleGroupId),
      isFalse,
      reason: '$id links the region ${link.muscleGroupId}',
    );
    expect(
      _forbiddenMuscleIds,
      isNot(contains(link.muscleGroupId)),
      reason: '$id links ${link.muscleGroupId}',
    );
  }
}
