import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/models/muscle_taxonomy.dart';
import 'package:omnitrain/mock/seed_data.dart';

import 'helpers/conditioning_catalog_rows.dart';
import 'helpers/yoga_catalog_rows.dart';

class _Row {
  const _Row(
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

const List<_Row> _rows = [
  _Row(
    'side-lying-external-rotation',
    'Side-Lying Dumbbell External Rotation',
    null,
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['rotator-cuff'],
    ['rear-delts'],
    ['dumbbell'],
  ),
  _Row(
    'cable-internal-rotation',
    'Cable Internal Rotation',
    null,
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['rotator-cuff'],
    [],
    ['cable'],
  ),
  _Row(
    'band-pull-apart',
    'Band Pull-Apart',
    'shoulder_isolation',
    ['reps', 'sets', 'time'],
    ['rear-delts'],
    ['traps', 'rotator-cuff'],
    ['resistance-band'],
  ),
  _Row(
    'machine-hip-abduction',
    'Machine Hip Abduction',
    null,
    ['reps', 'sets', 'load', 'time'],
    ['abductors'],
    ['glutes'],
    ['machine'],
  ),
  _Row(
    'banded-clamshell',
    'Banded Clamshell',
    null,
    ['reps', 'sets', 'bilateral', 'time'],
    ['abductors'],
    ['glutes'],
    ['resistance-band'],
  ),
  _Row(
    'banded-lateral-walk',
    'Banded Lateral Walk',
    null,
    ['reps', 'sets', 'time'],
    ['abductors'],
    ['glutes'],
    ['resistance-band'],
  ),
  _Row(
    'incline-dumbbell-curl',
    'Incline Dumbbell Curl',
    'arm_isolation',
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['biceps'],
    ['forearms'],
    ['dumbbell'],
  ),
  _Row(
    'cable-curl',
    'Cable Curl',
    'arm_isolation',
    ['reps', 'sets', 'load', 'time'],
    ['biceps'],
    ['forearms'],
    ['cable'],
  ),
  _Row(
    'concentration-curl',
    'Concentration Curl',
    'arm_isolation',
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['biceps'],
    [],
    ['dumbbell'],
  ),
  _Row(
    'reverse-curl',
    'Reverse Curl',
    'arm_isolation',
    ['reps', 'sets', 'load', 'time'],
    ['brachialis', 'forearms'],
    ['biceps'],
    ['barbell'],
  ),
  _Row(
    'zottman-curl',
    'Zottman Curl',
    'arm_isolation',
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['biceps', 'brachialis'],
    ['forearms'],
    ['dumbbell'],
  ),
  _Row(
    'cross-body-hammer-curl',
    'Cross-Body Hammer Curl',
    'arm_isolation',
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['biceps', 'brachialis'],
    ['forearms'],
    ['dumbbell'],
  ),
  _Row(
    'close-grip-bench-press',
    'Close-Grip Bench Press',
    'horizontal_push',
    ['reps', 'sets', 'load', 'time'],
    ['triceps'],
    ['chest', 'front-delts'],
    ['barbell'],
  ),
  _Row(
    'triceps-kickback',
    'Triceps Kickback',
    'arm_isolation',
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['triceps'],
    [],
    ['dumbbell'],
  ),
  _Row(
    'diamond-push-up',
    'Diamond Push-Up',
    'horizontal_push',
    ['reps', 'sets', 'time'],
    ['triceps', 'chest'],
    ['front-delts', 'abs'],
    ['bodyweight'],
  ),
  _Row(
    'bench-dip',
    'Bench Dip',
    'horizontal_push',
    ['reps', 'sets', 'load', 'time'],
    ['triceps'],
    ['chest', 'front-delts'],
    ['bodyweight'],
  ),
  _Row(
    'leg-extension',
    'Leg Extension',
    'squat',
    ['reps', 'sets', 'load', 'time'],
    ['quads'],
    [],
    ['machine'],
  ),
  _Row(
    'lying-leg-curl',
    'Lying Leg Curl',
    'posterior_chain',
    ['reps', 'sets', 'load', 'time'],
    ['hamstrings'],
    [],
    ['machine'],
  ),
  _Row(
    'seated-leg-curl',
    'Seated Leg Curl',
    'posterior_chain',
    ['reps', 'sets', 'load', 'time'],
    ['hamstrings'],
    [],
    ['machine'],
  ),
  _Row(
    'dumbbell-fly',
    'Dumbbell Fly',
    'horizontal_push',
    ['reps', 'sets', 'load', 'time'],
    ['chest'],
    ['front-delts'],
    ['dumbbell'],
  ),
  _Row(
    'incline-dumbbell-fly',
    'Incline Dumbbell Fly',
    'horizontal_push',
    ['reps', 'sets', 'load', 'time'],
    ['chest'],
    ['front-delts'],
    ['dumbbell'],
  ),
  _Row(
    'cable-crossover',
    'Cable Crossover',
    'horizontal_push',
    ['reps', 'sets', 'load', 'time'],
    ['chest'],
    ['front-delts'],
    ['cable'],
  ),
  _Row(
    'low-to-high-cable-fly',
    'Low-to-High Cable Fly',
    'horizontal_push',
    ['reps', 'sets', 'load', 'time'],
    ['chest'],
    ['front-delts'],
    ['cable'],
  ),
  _Row(
    'pec-deck-fly',
    'Pec Deck Fly',
    'horizontal_push',
    ['reps', 'sets', 'load', 'time'],
    ['chest'],
    [],
    ['machine'],
  ),
  _Row(
    'machine-shoulder-press',
    'Machine Shoulder Press',
    'vertical_push',
    ['reps', 'sets', 'load', 'time'],
    ['front-delts'],
    ['triceps', 'side-delts'],
    ['machine'],
  ),
  _Row(
    'cable-rear-delt-fly',
    'Cable Rear Delt Fly',
    'shoulder_isolation',
    ['reps', 'sets', 'load', 'time'],
    ['rear-delts'],
    ['traps'],
    ['cable'],
  ),
  _Row(
    'reverse-pec-deck',
    'Reverse Pec Deck',
    'shoulder_isolation',
    ['reps', 'sets', 'load', 'time'],
    ['rear-delts'],
    ['traps'],
    ['machine'],
  ),
  _Row(
    'dumbbell-shrug',
    'Dumbbell Shrug',
    null,
    ['reps', 'sets', 'load', 'time'],
    ['traps'],
    ['forearms'],
    ['dumbbell'],
  ),
];

const List<_Row> _rows115b = [
  _Row(
    'sit-up',
    'Sit-Up',
    'abs',
    ['reps', 'sets', 'time'],
    ['abs'],
    ['obliques'],
    ['bodyweight'],
  ),
  _Row(
    'crunch',
    'Crunch',
    'abs',
    ['reps', 'sets', 'time'],
    ['abs'],
    ['obliques'],
    ['bodyweight'],
  ),
  _Row(
    'reverse-crunch',
    'Reverse Crunch',
    'abs',
    ['reps', 'sets', 'time'],
    ['abs'],
    ['obliques'],
    ['bodyweight'],
  ),
  _Row(
    'bicycle-crunch',
    'Bicycle Crunch',
    'abs',
    ['reps', 'sets', 'time'],
    ['abs', 'obliques'],
    [],
    ['bodyweight'],
  ),
  _Row(
    'russian-twist',
    'Russian Twist',
    'loaded_core',
    ['reps', 'sets', 'load', 'time'],
    ['obliques'],
    ['abs'],
    ['bodyweight'],
  ),
  _Row(
    'hanging-knee-raise',
    'Hanging Knee Raise',
    'abs',
    ['reps', 'sets', 'time'],
    ['abs'],
    ['obliques'],
    ['pullup-bar'],
  ),
  _Row(
    'dead-bug',
    'Dead Bug',
    'abs',
    ['reps', 'sets', 'time'],
    ['abs'],
    ['obliques'],
    ['bodyweight'],
  ),
  _Row(
    'bird-dog',
    'Bird Dog',
    null,
    ['reps', 'sets', 'time'],
    ['lower-back', 'abs'],
    ['glutes'],
    ['bodyweight'],
  ),
  _Row(
    'cable-side-bend',
    'Cable Side Bend',
    'loaded_core',
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['obliques'],
    ['lower-back'],
    ['cable'],
  ),
  _Row(
    'push-press',
    'Push Press',
    'vertical_push',
    ['reps', 'sets', 'load', 'time'],
    ['front-delts'],
    ['triceps', 'side-delts', 'quads'],
    ['barbell'],
  ),
  _Row(
    'trap-bar-deadlift',
    'Trap-Bar Deadlift',
    'hinge',
    ['reps', 'sets', 'load', 'time'],
    ['glutes', 'quads', 'hamstrings'],
    ['lower-back', 'traps', 'forearms'],
    ['trap-bar'],
  ),
  _Row(
    'rack-pull',
    'Rack Pull',
    'hinge',
    ['reps', 'sets', 'load', 'time'],
    ['lower-back', 'glutes', 'traps'],
    ['hamstrings', 'forearms'],
    ['barbell'],
  ),
  _Row(
    'lateral-lunge',
    'Lateral Lunge',
    'lunge',
    ['reps', 'sets', 'load', 'time'],
    ['quads', 'glutes'],
    ['adductors'],
    ['dumbbell'],
  ),
  _Row(
    'curtsy-lunge',
    'Curtsy Lunge',
    'lunge',
    ['reps', 'sets', 'load', 'time'],
    ['glutes', 'quads'],
    ['abductors'],
    ['dumbbell'],
  ),
  _Row(
    'single-leg-hip-thrust',
    'Single-Leg Hip Thrust',
    'hinge',
    ['reps', 'sets', 'load', 'bilateral', 'time'],
    ['glutes'],
    ['hamstrings'],
    ['bodyweight'],
  ),
  _Row(
    'donkey-calf-raise',
    'Donkey Calf Raise',
    'calves',
    ['reps', 'sets', 'load', 'time'],
    ['calves'],
    [],
    ['machine'],
  ),
  _Row(
    'leg-press-calf-raise',
    'Leg Press Calf Raise',
    'calves',
    ['reps', 'sets', 'load', 'time'],
    ['calves'],
    [],
    ['machine'],
  ),
  _Row(
    'reverse-hyperextension',
    'Reverse Hyperextension',
    'hinge',
    ['reps', 'sets', 'load', 'time'],
    ['glutes', 'lower-back'],
    ['hamstrings'],
    ['machine'],
  ),
  _Row(
    'sled-push',
    'Sled Push',
    null,
    ['time', 'distance', 'load'],
    ['quads', 'glutes'],
    ['hamstrings', 'calves'],
    ['sled'],
  ),
  _Row(
    'sled-drag',
    'Sled Drag',
    null,
    ['time', 'distance', 'load'],
    ['quads', 'glutes'],
    ['hamstrings', 'calves'],
    ['sled'],
  ),
];

void main() {
  final byId = {for (final e in SeedData.sampleExercises) e.id: e};

  void expectRowMatchesPlan(_Row r) {
    final id = 'exercise-${r.suffix}';
    final exercise = byId[id];

    expect(exercise, isNotNull, reason: 'missing $id');
    expect(exercise!.name, r.name);
    expect(exercise.disciplineId, 'discipline-bodybuilding');
    expect(exercise.movementPattern, r.pattern);
    expect(exercise.ownerUserId, isNull);
    expect(exercise.description?.trim(), isNotEmpty);

    final steps = exercise.howToSteps;
    expect(steps, isNotNull);
    expect(steps!.length, inInclusiveRange(3, 4));
    for (final step in steps) {
      expect(step.trim(), isNotEmpty);
    }

    expect(
      SeedData.exerciseCapabilityRelationships[id],
      equals(r.caps),
    );
    expect(SeedData.exerciseEquipmentRelationships[id], [
      for (final name in r.equipment) 'equipment-$name',
    ]);
    expect(
      SeedData.exerciseMuscleLinks[id],
      MuscleTaxonomy.normalize([
        for (final name in r.main)
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-$name',
            role: MuscleRole.primary,
          ),
        for (final name in r.assist)
          ExerciseMuscleLink(
            muscleGroupId: 'muscle-$name',
            role: MuscleRole.secondary,
          ),
      ]),
    );
  }

  group('S-18909 new strength rows', () {
    for (final r in _rows) {
      test(
        '${r.suffix}: row, text, capabilities, muscles and equipment match the plan table',
        () => expectRowMatchesPlan(r),
      );
    }

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
      for (final r in [..._rows, ..._rows115b]) {
        expect(
          'exercise-${r.suffix}'.compareTo('exercise-2k-row-test') > 0,
          isTrue,
          reason: r.suffix,
        );
      }
    });

    test('catalog sizes', () {
      final added = _rows.length + _rows115b.length;
      final yogaLinks = yogaCatalogRows
          .where((r) => r.main.isNotEmpty)
          .length;
      final conditioningLinks = conditioningCatalogRows
          .where((r) => r.main.isNotEmpty)
          .length;
      expect(
        SeedData.sampleExercises.length,
        252 + added + yogaCatalogRows.length + conditioningCatalogRows.length,
      );
      expect(
        SeedData.exerciseCapabilityRelationships.length,
        252 + added + yogaCatalogRows.length + conditioningCatalogRows.length,
      );
      expect(
        SeedData.exerciseEquipmentRelationships.length,
        188 + added + yogaCatalogRows.length + conditioningCatalogRows.length,
      );
      expect(
        SeedData.exerciseMuscleLinks.length,
        178 + added + yogaLinks + conditioningLinks,
      );
    });
  });

  group('S-19001 new 115b rows', () {
    for (final r in _rows115b) {
      test(
        '${r.suffix}: row, text, capabilities, muscles and equipment match the plan table',
        () => expectRowMatchesPlan(r),
      );
    }
  });

  group('S-19002 the seed equipment rows', () {
    test('the seed carries 12 equipment rows in the planned order', () {
      expect(
        SeedData.sampleEquipment.map((e) => e.id).toList(),
        equals([
          'equipment-barbell',
          'equipment-dumbbell',
          'equipment-kettlebell',
          'equipment-resistance-band',
          'equipment-pullup-bar',
          'equipment-treadmill',
          'equipment-heavy-bag',
          'equipment-bodyweight',
          'equipment-cable',
          'equipment-machine',
          'equipment-trap-bar',
          'equipment-sled',
        ]),
      );
    });

    test('Trap Bar and Sled carry the planned names', () {
      final byId = {for (final e in SeedData.sampleEquipment) e.id: e};
      expect(byId['equipment-trap-bar']?.name, 'Trap Bar');
      expect(byId['equipment-sled']?.name, 'Sled');
    });

    test('the 12 equipment names are unique', () {
      final names = SeedData.sampleEquipment.map((e) => e.name).toSet();
      expect(names, hasLength(12));
    });
  });
}
