// Exercise Library filters + smart search.
//
//   L-1  Searching keeps best-match-first order (typo-tolerant, like the picker).
//   L-2  Without a search the list stays alphabetical.
//   L-3  The Muscle filter narrows the list; Discipline + Muscle combine.
//   L-4  Clear Filters resets search, both dropdowns and Custom only.
//   L-5  The library shows the same Discipline / Muscle filter fields as the picker.
//
// Mock-first: Hive is never opened inside a testWidgets body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_library_screen.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

Future<
  ({
    MockWorkoutRepository repo,
    WorkoutState workout,
    ExerciseLibraryState state,
  })
>
_build() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final workout = WorkoutState(repo);
  await workout.loadMuscleGroups();
  await workout.loadDisciplines();
  final state = ExerciseLibraryState(
    service: ExerciseLibraryService(repo),
    workoutState: workout,
  );
  await state.reload();
  return (repo: repo, workout: workout, state: state);
}

Future<void> _pumpLibrary(
  WidgetTester tester,
  ({
    MockWorkoutRepository repo,
    WorkoutState workout,
    ExerciseLibraryState state,
  })
  bundle,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  await tester.pumpWidget(
    MaterialApp(
      home: ExerciseLibraryScreen(
        exerciseLibraryState: bundle.state,
        workoutState: bundle.workout,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ExerciseLibraryState filters', () {
    test(
      'L-1 a search ranks the best match first, not alphabetically',
      () async {
        final b = await _build();
        await b.state.setSearchText('incline barbell bench press');
        final names = b.state.exercises.map((e) => e.name).toList();
        // Alphabetically 'Barbell Bench Press' would lead; the exact match wins.
        expect(names.first, 'Incline Barbell Bench Press');
        },
    );

    test('L-2 no search keeps the list alphabetical', () async {
      final b = await _build();
      final names = b.state.exercises.map((e) => e.name.toLowerCase()).toList();
      expect(names, [...names]..sort());
    });

    test(
      'L-3 muscle filter narrows the list and combines with search',
      () async {
        final b = await _build();
        final all = b.state.exercises.length;

        final chest = b.workout.muscleGroups.firstWhere(
          (g) => g.name == 'Chest',
        );
        await b.state.setMuscleGroupId(chest.id);
        final chestOnly = b.state.exercises;
        expect(chestOnly, isNotEmpty);
        expect(chestOnly.length, lessThan(all));
        expect(chestOnly.map((e) => e.name), contains('Barbell Bench Press'));

        await b.state.setSearchText('squat');
        expect(
          b.state.exercises.map((e) => e.name),
          isNot(contains('Back Squat')),
        );
      },
    );

    test('L-4 clearFilters resets everything in one go', () async {
      final b = await _build();
      final all = b.state.exercises.length;
      final chest = b.workout.muscleGroups.firstWhere((g) => g.name == 'Chest');
      await b.state.setMuscleGroupId(chest.id);
      await b.state.setSearchText('press');
      await b.state.setCustomOnly(true);
      expect(b.state.hasActiveFilters, isTrue);

      await b.state.clearFilters();

      expect(b.state.hasActiveFilters, isFalse);
      expect(b.state.searchText, isNull);
      expect(b.state.muscleGroupId, isNull);
      expect(b.state.disciplineId, isNull);
      expect(b.state.customOnly, isFalse);
      expect(b.state.exercises.length, all);
    });
  });

  group('ExerciseLibraryScreen filters', () {
    testWidgets(
      'L-5 shows Discipline and Muscle fields; Clear Filters resets',
      (tester) async {
        final b = await _build();
        await _pumpLibrary(tester, b);

        expect(
          find.byKey(const Key('exercise_filter_discipline')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('exercise_filter_muscle')), findsOneWidget);
        expect(
          find.byKey(const Key('exercise_library_clear_filters_button')),
          findsNothing,
        );

        // Choose a muscle through the real dropdown.
        await tester.tap(find.byKey(const Key('exercise_filter_muscle')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ListView).last,
            matching: find.text('Chest'),
          ),
        );
        await tester.pumpAndSettle();

        expect(b.state.muscleGroupId, isNotNull);
        expect(
          find.byKey(const Key('exercise_library_clear_filters_button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('exercise_library_clear_filters_button')),
        );
        await tester.pumpAndSettle();

        expect(b.state.muscleGroupId, isNull);
        expect(
          find.byKey(const Key('exercise_library_clear_filters_button')),
          findsNothing,
        );
      },
    );
  });
}
