// Plan 35 (muscle display) — Phase A2.
//
//   S-2  The picker's Muscle filter is grouped by region and indented.
//   S-3  Picker and library rows show MAIN muscles only.
//   S-7  A row with four main muscles wraps instead of overflowing.
//   S-8  A region-only main link shows the region's own name.
//   S-9  Main muscle chips follow link order, never a secondary-only tag.
//   S-10 Choosing "All" restores the unfiltered list.
//   S-11 Clear Filters resets the muscle dropdown to "All".
//
// Mock-first: every case pumps the Mock repository, Hive is never opened
// inside a testWidgets body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_library_screen.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

const Size _pickerSurface = Size(800, 1400);

/// The 24 rows of the Muscle filter, top to bottom (S-2).
const List<String> _displayOrder = [
  'All',
  'Chest',
  'Neck',
  'Back',
  'Lats',
  'Traps',
  'Lower back',
  'Shoulders',
  'Front delts',
  'Side delts',
  'Rear delts',
  'Arms',
  'Biceps',
  'Triceps',
  'Forearms',
  'Core',
  'Abs',
  'Obliques',
  'Legs',
  'Quadriceps',
  'Hamstrings',
  'Glutes',
  'Calves',
  'Adductors',
];

/// The rows that are indented one step under their region.
const List<String> _indentedOrder = [
  'Lats',
  'Traps',
  'Lower back',
  'Front delts',
  'Side delts',
  'Rear delts',
  'Biceps',
  'Triceps',
  'Forearms',
  'Abs',
  'Obliques',
  'Quadriceps',
  'Hamstrings',
  'Glutes',
  'Calves',
  'Adductors',
];

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

Future<WorkoutState> _pumpPicker(
  WidgetTester tester,
  MockWorkoutRepository repo, {
  Size surface = _pickerSurface,
}) async {
  await tester.binding.setSurfaceSize(surface);
  final workoutState = WorkoutState(repo);
  await tester.pumpWidget(
    MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
  );
  await tester.pumpAndSettle();
  return workoutState;
}

/// The Muscle dropdown (the second of the picker's two dropdown fields).
Finder _muscleField() => find.ancestor(
  of: find.text('Muscle'),
  matching: find.byType(DropdownButtonFormField<String>),
);

/// The name the closed Muscle field displays.
Finder _closedMuscleFieldValue(String name) =>
    find.descendant(of: _muscleField(), matching: find.text(name));

/// One row of the open Muscle menu (the menu's own `ListView` is the last one).
Finder _menuItem(String name) =>
    find.descendant(of: find.byType(ListView).last, matching: find.text(name));

/// Type a search term and let the picker's 300 ms debounce run out.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _openMuscleMenu(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).last);
  await tester.pumpAndSettle();
}

Future<void> _chooseMuscle(WidgetTester tester, String name) async {
  await _openMuscleMenu(tester);
  await tester.tap(_menuItem(name));
  await tester.pumpAndSettle();
}

/// The list row that carries [exerciseName] as its title.
Finder _row(String exerciseName) =>
    find.ancestor(of: find.text(exerciseName), matching: find.byType(ListTile));

/// A chip / tag label rendered inside [row].
Finder _chipIn(Finder row, String label) =>
    find.descendant(of: row, matching: find.text(label));

/// The chip labels of [row], in the order the row builds them.
List<String> _chipLabelsInRow(WidgetTester tester, Finder row) {
  final labels = <String>[];
  for (final chip in tester.widgetList<Chip>(
    find.descendant(of: row, matching: find.byType(Chip)),
  )) {
    final label = chip.label;
    if (label is Text && label.data != null) labels.add(label.data!);
  }
  return labels;
}

/// The names of the main (primary) links of [links], in link order.
List<String> _primaryNames(
  List<ExerciseMuscleLink> links,
  List<MuscleGroup> groups,
) {
  final nameById = {for (final group in groups) group.id: group.name};
  return [
    for (final link in links)
      if (link.role == MuscleRole.primary)
        nameById[link.muscleGroupId] ?? link.muscleGroupId,
  ];
}

/// Asserts the chips for [names] read left to right, then top to bottom (the
/// row's chips wrap, so a later chip is either further right or lower).
void _expectChipReadingOrder(
  WidgetTester tester,
  Finder row,
  List<String> names,
) {
  final positions = [
    for (final name in names) tester.getTopLeft(_chipIn(row, name)),
  ];
  for (var i = 1; i < positions.length; i++) {
    final previous = positions[i - 1];
    final current = positions[i];
    final sameLine = (current.dy - previous.dy).abs() < 1.0;
    expect(
      sameLine ? current.dx > previous.dx : current.dy > previous.dy,
      isTrue,
      reason:
          '${names[i]} must follow ${names[i - 1]}; '
          '${names[i - 1]}=$previous, ${names[i]}=$current',
    );
  }
}

Future<Exercise> _createCustom(
  MockWorkoutRepository repo,
  String id,
  String name,
) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final exercise = Exercise(
    id: id,
    name: name,
    ownerUserId: 'user-1',
    createdAtMs: now,
    updatedAtMs: now,
  );
  await repo.createExercise(exercise);
  return exercise;
}

ExerciseMuscleLink _link(String muscleGroupId, MuscleRole role) =>
    ExerciseMuscleLink(muscleGroupId: muscleGroupId, role: role);

/// A repository whose links read fails, so `WorkoutState` hands the picker
/// a null list — the case the cache fill's `?? const []` exists for.
class _ThrowingLinksRepo extends MockWorkoutRepository {
  @override
  Future<List<ExerciseMuscleLink>> getExerciseMuscleLinks(String exerciseId) =>
      Future.error(StateError('links read failed'));
}

void main() {
  group('S-2: Muscle filter grouped by region', () {
    testWidgets(
      'the open menu lists standalone, regions and muscles in display order, '
      'muscles indented one step',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        await _pumpPicker(tester, repo);
        await _openMuscleMenu(tester);

        final dys = [
          for (final name in _displayOrder)
            tester.getTopLeft(_menuItem(name)).dy,
        ];
        for (var i = 1; i < dys.length; i++) {
          expect(
            dys[i],
            greaterThan(dys[i - 1]),
            reason:
                '${_displayOrder[i]} must sit below ${_displayOrder[i - 1]} '
                '(dys=$dys)',
          );
        }

        final baseDx = tester.getTopLeft(_menuItem('Chest')).dx;
        expect(tester.getTopLeft(_menuItem('All')).dx, baseDx);
        expect(tester.getTopLeft(_menuItem('Neck')).dx, baseDx);
        expect(tester.getTopLeft(_menuItem('Legs')).dx, baseDx);
        for (final name in _indentedOrder) {
          expect(
            tester.getTopLeft(_menuItem(name)).dx,
            greaterThan(baseDx),
            reason: '$name must be indented one step under its region',
          );
        }

        expect(
          tester.widget<Text>(_menuItem('Chest')).style?.fontWeight,
          FontWeight.w600,
          reason: 'a depth-0 row label is bold',
        );
        expect(
          tester.widget<Text>(_menuItem('Lats')).style?.fontWeight,
          FontWeight.w400,
          reason: 'a depth-1 row label is regular',
        );
      },
    );

    testWidgets(
      'a region matches a region or one of its muscles; a muscle matches only '
      'itself',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        await _pumpPicker(tester, repo);

        await _search(tester, 'Squat');
        await _chooseMuscle(tester, 'Legs');
        expect(find.text('Barbell Back Squat'), findsOneWidget);

        await _search(tester, 'Tennis');
        await _chooseMuscle(tester, 'Legs');
        expect(find.text('Tennis Match'), findsOneWidget);

        await _chooseMuscle(tester, 'Quadriceps');
        expect(find.text('Tennis Match'), findsNothing);

        await _search(tester, 'Press');
        await _chooseMuscle(tester, 'Triceps');
        expect(find.text('Triceps Pressdown'), findsOneWidget);
        expect(find.text('Barbell Bench Press'), findsNothing);
      },
    );

    testWidgets('the closed field shows the plain name, unindented', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpPicker(tester, repo);

      final allDx = tester.getTopLeft(_closedMuscleFieldValue('All')).dx;

      await _chooseMuscle(tester, 'Quadriceps');
      expect(_closedMuscleFieldValue('Quadriceps'), findsOneWidget);
      expect(_closedMuscleFieldValue('All'), findsNothing);

      final closedDx = tester
          .getTopLeft(_closedMuscleFieldValue('Quadriceps'))
          .dx;
      expect(
        closedDx,
        allDx,
        reason:
            'the closed field must not indent a muscle the way the menu '
            'does',
      );
    });
  });

  group('S-10 / S-11: resetting the filter', () {
    testWidgets('choosing All restores the unfiltered list', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpPicker(tester, repo);

      await _search(tester, 'Barbell Bench Press');
      await _chooseMuscle(tester, 'Quadriceps');
      expect(find.text('No exercises found'), findsOneWidget);
      expect(_row('Barbell Bench Press'), findsNothing);

      await _chooseMuscle(tester, 'All');
      expect(_row('Barbell Bench Press'), findsOneWidget);
      expect(find.text('No exercises found'), findsNothing);
      expect(_closedMuscleFieldValue('All'), findsOneWidget);
    });

    testWidgets('Clear Filters resets the muscle dropdown to All', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpPicker(tester, repo);

      await _search(tester, 'Squat');
      await _chooseMuscle(tester, 'Quadriceps');
      expect(_closedMuscleFieldValue('Quadriceps'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();

      expect(_closedMuscleFieldValue('All'), findsOneWidget);
      expect(_closedMuscleFieldValue('Quadriceps'), findsNothing);
    });
  });

  group('S-3 / S-9: rows show main muscles only', () {
    testWidgets('bench press shows Chest and neither Triceps nor Front delts', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      await _pumpPicker(tester, repo);
      await _search(tester, 'Barbell Bench Press');

      final row = _row('Barbell Bench Press');
      expect(_chipIn(row, 'Chest'), findsOneWidget);
      expect(_chipIn(row, 'Triceps'), findsNothing);
      expect(_chipIn(row, 'Front delts'), findsNothing);
    });

    testWidgets(
      'Arnold press shows Front delts and no secondary delt or triceps chip',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        await _pumpPicker(tester, repo);
        await _search(tester, 'Arnold Press');

        final row = _row('Arnold Press');
        expect(_chipIn(row, 'Front delts'), findsOneWidget);
        expect(_chipIn(row, 'Triceps'), findsNothing);
        expect(_chipIn(row, 'Side delts'), findsNothing);
        expect(_chipIn(row, 'Rear delts'), findsNothing);
      },
    );

    testWidgets('tennis match shows its main muscles in link order', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = await _pumpPicker(tester, repo);
      await _search(tester, 'Tennis Match');

      final expected = _primaryNames(
        await repo.getExerciseMuscleLinks('exercise-tennis-match'),
        workoutState.muscleGroups,
      );
      final row = _row('Tennis Match');
      final labels = _chipLabelsInRow(tester, row);
      expect(
        labels.where(expected.contains).toList(),
        expected,
        reason: 'tennis chips=$labels, main links=$expected',
      );
      _expectChipReadingOrder(tester, row, ['Legs', 'Shoulders', 'Core']);
    });

    testWidgets(
      'a custom exercise shows its primary muscle and not its secondary one',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        await _createCustom(repo, 'ex-custom-chest', 'Zenith Chest Move');
        await repo.setExerciseMuscleLinks('ex-custom-chest', [
          _link('muscle-chest', MuscleRole.primary),
          _link('muscle-lats', MuscleRole.secondary),
        ]);
        await _pumpPicker(tester, repo);
        await _search(tester, 'Zenith Chest Move');

        final row = _row('Zenith Chest Move');
        expect(_chipIn(row, 'Chest'), findsOneWidget);
        expect(_chipIn(row, 'Lats'), findsNothing);
      },
    );

    testWidgets('a region-only main link shows the region name (S-8)', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      await _createCustom(repo, 'ex-custom-legs', 'Zenith Legs Move');
      await repo.setExerciseMuscleLinks('ex-custom-legs', [
        _link('muscle-legs', MuscleRole.primary),
      ]);
      await _pumpPicker(tester, repo);
      await _search(tester, 'Zenith Legs Move');

      final row = _row('Zenith Legs Move');
      expect(_chipIn(row, 'Legs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Conventional Deadlift shows its main muscles in link order and no '
      'secondary-only chip (S-9)',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        final workoutState = await _pumpPicker(tester, repo);
        await _search(tester, 'Conventional Deadlift');

        final expected = _primaryNames(
          await repo.getExerciseMuscleLinks('exercise-deadlift'),
          workoutState.muscleGroups,
        );
        final row = _row('Conventional Deadlift');
        final labels = _chipLabelsInRow(tester, row);
        expect(
          labels.where(expected.contains).toList(),
          expected,
          reason: 'deadlift chips=$labels, main links=$expected',
        );
        expect(_chipIn(row, 'Lats'), findsNothing);
        expect(_chipIn(row, 'Quadriceps'), findsNothing);
        expect(_chipIn(row, 'Forearms'), findsNothing);
      },
    );

    testWidgets(
      'a link to an unknown muscle group adds no chip and throws nothing',
      (WidgetTester tester) async {
        final repo = await _freshRepo();
        await _createCustom(repo, 'ex-ghost-muscle', 'Zenith Ghost Move');
        await repo.putRawExerciseMuscleLinksForTest('ex-ghost-muscle', [
          _link('muscle-nope', MuscleRole.primary),
        ]);
        await _pumpPicker(tester, repo);
        await _search(tester, 'Zenith Ghost Move');

        final row = _row('Zenith Ghost Move');
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.byType(Chip)),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a failing links read leaves rows chip-less, not crashed', (
      WidgetTester tester,
    ) async {
      final repo = _ThrowingLinksRepo();
      await repo.initialize();
      await _pumpPicker(tester, repo);
      await _search(tester, 'Barbell Bench Press');

      final row = _row('Barbell Bench Press');
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Chest')),
        findsNothing,
        reason: 'the failed links read must leave the row without muscle chips',
      );
      expect(
        find.descendant(of: row, matching: find.text('Triceps')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the library list row shows only the main muscle', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(_pickerSurface);
      final repo = await _freshRepo();
      final workout = WorkoutState(repo);
      final state = ExerciseLibraryState(
        service: ExerciseLibraryService(repo),
        workoutState: workout,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryScreen(
            exerciseLibraryState: state,
            workoutState: workout,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('exercise_library_search_field')),
        'Barbell Bench Press',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final row = _row('Barbell Bench Press');
      expect(_chipIn(row, 'Chest'), findsOneWidget);
      expect(_chipIn(row, 'Triceps'), findsNothing);
      expect(_chipIn(row, 'Front delts'), findsNothing);
    });
  });

  group('S-7: a four-muscle row wraps instead of overflowing', () {
    testWidgets('Volleyball Match shows four chips without an overflow', (
      WidgetTester tester,
    ) async {
      for (final surface in [_pickerSurface, const Size(390, 844)]) {
        final repo = await _freshRepo();
        await _pumpPicker(tester, repo, surface: surface);
        await _search(tester, 'Volleyball Match');

        final row = _row('Volleyball Match');
        for (final name in ['Shoulders', 'Arms', 'Core', 'Legs']) {
          expect(
            _chipIn(row, name),
            findsOneWidget,
            reason: '$name chip missing at $surface',
          );
        }
        expect(tester.takeException(), isNull, reason: 'at $surface');
      }
    });
  });
}
