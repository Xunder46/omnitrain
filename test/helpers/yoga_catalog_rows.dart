import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/models/muscle_taxonomy.dart';
import 'package:omnitrain/mock/seed_data.dart';

/// One row of plan 119's **New-row table** (D-19301): id suffix, name, movement
/// pattern, capability set, main (P) and assisting (S) muscles, equipment.
class YogaCatalogRow {
  const YogaCatalogRow(
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

/// The Yoga rows the bundled catalog must carry, in table order.
///
/// Phase 1 of plan 119 ships rows 1–11 and Phase 2 rows 12–22; the global size
/// guards add this list's length (and, for links, its non-empty `main` count),
/// so the guard stays right whether plan 118 landed before or after.
const List<YogaCatalogRow> yogaCatalogRows = [
  YogaCatalogRow(
    'mountain-pose',
    'Mountain Pose',
    null,
    ['hold', 'time', 'sets'],
    ['abs'],
    ['quads', 'glutes'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'downward-facing-dog',
    'Downward-Facing Dog',
    null,
    ['hold', 'time', 'sets'],
    ['hamstrings'],
    ['front-delts', 'lats', 'calves'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'upward-facing-dog',
    'Upward-Facing Dog',
    null,
    ['hold', 'time', 'sets'],
    ['lower-back'],
    ['chest', 'triceps'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'cobra-pose',
    'Cobra Pose',
    null,
    ['hold', 'time', 'sets'],
    ['lower-back'],
    ['chest'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'warrior-i',
    'Warrior I',
    null,
    ['hold', 'time', 'sets'],
    ['quads', 'glutes'],
    ['front-delts'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'warrior-ii',
    'Warrior II',
    null,
    ['hold', 'time', 'sets'],
    ['quads'],
    ['glutes', 'adductors', 'side-delts'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'reverse-warrior',
    'Reverse Warrior',
    null,
    ['hold', 'time', 'sets'],
    ['quads', 'obliques'],
    ['lats'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'triangle-pose',
    'Triangle Pose',
    null,
    ['hold', 'time', 'sets'],
    ['hamstrings', 'obliques'],
    ['adductors'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'half-moon-pose',
    'Half Moon Pose',
    null,
    ['hold', 'time', 'sets'],
    ['glutes'],
    ['obliques', 'hamstrings'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'tree-pose',
    'Tree Pose',
    null,
    ['hold', 'time', 'sets'],
    ['glutes'],
    ['quads', 'abs'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'chair-pose',
    'Chair Pose',
    null,
    ['hold', 'time', 'sets'],
    ['quads'],
    ['glutes', 'front-delts'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'eagle-pose',
    'Eagle Pose',
    null,
    ['hold', 'time', 'sets'],
    ['quads', 'glutes'],
    ['rear-delts'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'goddess-pose',
    'Goddess Pose',
    null,
    ['hold', 'time', 'sets'],
    ['quads', 'adductors'],
    ['glutes'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'boat-pose',
    'Boat Pose',
    null,
    ['hold', 'time', 'sets'],
    ['abs'],
    ['obliques'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'bridge-pose',
    'Bridge Pose',
    null,
    ['hold', 'time', 'sets'],
    ['glutes'],
    ['hamstrings', 'lower-back'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'low-lunge',
    'Low Lunge',
    null,
    ['hold', 'time', 'sets'],
    ['quads'],
    ['glutes'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'crescent-lunge',
    'Crescent Lunge',
    null,
    ['hold', 'time', 'sets'],
    ['quads', 'glutes'],
    ['hamstrings'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'locust-pose',
    'Locust Pose',
    null,
    ['hold', 'time', 'sets'],
    ['lower-back', 'glutes'],
    ['hamstrings', 'rear-delts'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'camel-pose',
    'Camel Pose',
    null,
    ['hold', 'time', 'sets'],
    ['lower-back'],
    ['quads', 'chest'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'happy-baby',
    'Happy Baby',
    null,
    ['hold', 'time', 'sets'],
    ['adductors'],
    ['hamstrings'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'reclined-spinal-twist',
    'Reclined Spinal Twist',
    null,
    ['hold', 'time', 'sets'],
    ['lower-back'],
    ['glutes', 'obliques'],
    ['bodyweight'],
  ),
  YogaCatalogRow(
    'savasana',
    'Savasana',
    null,
    ['hold', 'time', 'sets'],
    [],
    [],
    ['bodyweight'],
  ),
];

/// The capability set every Yoga row carries (D-19303): the exact set of every
/// bundled Isometric Holds and Stretching row.
const List<String> yogaCapabilities = ['hold', 'time', 'sets'];

/// Asserts the shipped seed row for [row] matches the plan table (S-19301).
void expectYogaRowMatchesPlan(YogaCatalogRow row) {
  final id = 'exercise-${row.suffix}';
  final exercise = {
    for (final e in SeedData.sampleExercises)
      if (e.id == id) e,
  };

  expect(exercise, hasLength(1), reason: 'missing $id');
  final shipped = exercise.single;

  expect(shipped.name, row.name, reason: id);
  expect(shipped.disciplineId, 'discipline-yoga', reason: id);
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
  expect(
    SeedData.exerciseCapabilityRelationships[id],
    equals(yogaCapabilities),
    reason: '$id carries the hold capabilities',
  );
  expect(
    SeedData.exerciseCapabilityRelationships[id],
    equals(SeedData.exerciseCapabilityRelationships['exercise-pigeon-pose']),
    reason: '$id shares Pigeon Pose\'s capability set',
  );
  expect(SeedData.exerciseEquipmentRelationships[id], [
    for (final name in row.equipment) 'equipment-$name',
  ]);
  if (row.main.isEmpty) {
    // D-19305: a pose with no muscles carries no map entry at all — the map's
    // size guard and the S-3 "one entry per tagged exercise" check need the
    // absence, not an empty list.
    expect(
      SeedData.exerciseMuscleLinks.containsKey(id),
      isFalse,
      reason: '$id carries no muscle links',
    );
    return;
  }
  expect(
    SeedData.exerciseMuscleLinks[id],
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
}
