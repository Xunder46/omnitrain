// Exercise detail — Primary / Secondary muscle rows (plan 35, S-4).
//
// The read-only surface and the library detail surface show the exercise's
// main muscles under "Primary" and its assisting muscles under "Secondary":
//   - a row with no muscles of its role is hidden;
//   - with neither role present the whole section collapses.
//
// Mock-first: every test drives the Mock repository; Hive is never opened.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_detail_view_screen.dart';
import 'package:omnitrain/features/exercise/exercise_library_detail_screen.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

const _sectionKey = Key('exercise_detail_muscles_section');
const _primaryKey = Key('exercise_detail_primary_muscles');
const _secondaryKey = Key('exercise_detail_secondary_muscles');

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

MuscleGroup _muscleGroup(String id, String name) =>
    MuscleGroup(id: id, name: name, createdAtMs: 0);

Exercise _bareExercise(String id) =>
    Exercise(id: id, name: id, createdAtMs: 0, updatedAtMs: 0);

Future<void> _pumpBody(
  WidgetTester tester, {
  required Exercise exercise,
  required List<MuscleGroup> primary,
  required List<MuscleGroup> secondary,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ExerciseDetailViewBody(
          exercise: exercise,
          discipline: null,
          primaryMuscles: primary,
          secondaryMuscles: secondary,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpViewScreen(
  WidgetTester tester,
  MockWorkoutRepository repo,
  Exercise exercise,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  await tester.pumpWidget(
    MaterialApp(
      home: ExerciseDetailViewScreen(
        workoutState: WorkoutState(repo),
        exercise: exercise,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpLibraryDetail(
  WidgetTester tester,
  MockWorkoutRepository repo,
  Exercise exercise,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  final workoutState = WorkoutState(repo);
  final libraryState = ExerciseLibraryState(
    service: ExerciseLibraryService(repo),
    workoutState: workoutState,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: ExerciseLibraryDetailScreen(
        exercise: exercise,
        libraryState: libraryState,
        workoutState: workoutState,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _chipIn(Key rowKey, String label) =>
    find.descendant(of: find.byKey(rowKey), matching: find.text(label));

// ── Tests ────────────────────────────────────────────────────────────────

void main() {
  group('ExerciseDetailViewBody — Primary / Secondary rows (S-4)', () {
    testWidgets('primary and secondary chips stay in their own row', (
      WidgetTester tester,
    ) async {
      await _pumpBody(
        tester,
        exercise: _bareExercise('body-two-roles'),
        primary: [_muscleGroup('muscle-chest', 'Chest')],
        secondary: [
          _muscleGroup('muscle-triceps', 'Triceps'),
          _muscleGroup('muscle-front-delts', 'Front delts'),
        ],
      );

      expect(find.byKey(_sectionKey), findsOneWidget);
      expect(find.byKey(_primaryKey), findsOneWidget);
      expect(find.byKey(_secondaryKey), findsOneWidget);

      expect(_chipIn(_primaryKey, 'Chest'), findsOneWidget);
      expect(_chipIn(_primaryKey, 'Triceps'), findsNothing);
      expect(_chipIn(_primaryKey, 'Front delts'), findsNothing);

      expect(
        _chipIn(_secondaryKey, 'Triceps'),
        findsOneWidget,
        reason: 'the secondary row must render its own chips',
      );
      expect(_chipIn(_secondaryKey, 'Front delts'), findsOneWidget);
      expect(_chipIn(_secondaryKey, 'Chest'), findsNothing);

      final gap =
          tester.getTopLeft(find.byKey(_secondaryKey)).dy -
          tester.getBottomLeft(find.byKey(_primaryKey)).dy;
      expect(
        gap,
        moreOrLessEquals(12.0),
        reason: 'the 12 pt spacer sits between the two rows',
      );
    });

    testWidgets('secondary empty → no secondary row, primary still rendered', (
      WidgetTester tester,
    ) async {
      await _pumpBody(
        tester,
        exercise: _bareExercise('body-primary-only'),
        primary: [_muscleGroup('muscle-chest', 'Chest')],
        secondary: const [],
      );

      expect(find.byKey(_sectionKey), findsOneWidget);
      expect(find.byKey(_primaryKey), findsOneWidget);
      expect(_chipIn(_primaryKey, 'Chest'), findsOneWidget);
      expect(
        find.byKey(_secondaryKey),
        findsNothing,
        reason: 'an empty Secondary row must be hidden, not empty-rendered',
      );
    });

    testWidgets('primary empty → no primary row, secondary still rendered', (
      WidgetTester tester,
    ) async {
      await _pumpBody(
        tester,
        exercise: _bareExercise('body-secondary-only'),
        primary: const [],
        secondary: [_muscleGroup('muscle-triceps', 'Triceps')],
      );

      expect(find.byKey(_sectionKey), findsOneWidget);
      expect(find.byKey(_primaryKey), findsNothing);
      expect(_chipIn(_secondaryKey, 'Triceps'), findsOneWidget);
    });

    testWidgets('both empty → the whole section is absent', (
      WidgetTester tester,
    ) async {
      await _pumpBody(
        tester,
        exercise: _bareExercise('body-no-muscles'),
        primary: const [],
        secondary: const [],
      );

      expect(
        find.byKey(_sectionKey),
        findsNothing,
        reason: 'with no muscles the section must collapse entirely',
      );
      expect(find.byKey(_primaryKey), findsNothing);
      expect(find.byKey(_secondaryKey), findsNothing);
      expect(find.text('body-no-muscles'), findsOneWidget);
    });
  });

  group('ExerciseDetailViewScreen — seeded muscles (S-4)', () {
    testWidgets('bench press shows Primary Chest and Secondary Triceps / '
        'Front delts', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final bench = await repo.getExerciseById('exercise-bench-press');
      expect(bench, isNotNull, reason: 'seed missing: exercise-bench-press');

      await _pumpViewScreen(tester, repo, bench!);

      expect(find.byKey(_sectionKey), findsOneWidget);
      expect(_chipIn(_primaryKey, 'Chest'), findsOneWidget);
      expect(_chipIn(_secondaryKey, 'Triceps'), findsOneWidget);
      expect(_chipIn(_secondaryKey, 'Front delts'), findsOneWidget);
      expect(_chipIn(_primaryKey, 'Triceps'), findsNothing);
    });

    testWidgets('tennis match shows Primary Legs / Shoulders / Core and no '
        'secondary row', (WidgetTester tester) async {
      final repo = await _freshRepo();
      final tennis = await repo.getExerciseById('exercise-tennis-match');
      expect(tennis, isNotNull, reason: 'seed missing: exercise-tennis-match');

      await _pumpViewScreen(tester, repo, tennis!);

      expect(find.byKey(_primaryKey), findsOneWidget);
      for (final chip in const ['Legs', 'Shoulders', 'Core']) {
        expect(
          _chipIn(_primaryKey, chip),
          findsOneWidget,
          reason: 'primary chip "$chip" missing',
        );
      }
      expect(find.byKey(_secondaryKey), findsNothing);
    });

    testWidgets('an exercise with no muscles shows no section', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final easyRun = await repo.getExerciseById('exercise-easy-run');
      expect(easyRun, isNotNull, reason: 'seed missing: exercise-easy-run');

      await _pumpViewScreen(tester, repo, easyRun!);

      expect(find.text('Easy Run'), findsOneWidget);
      expect(
        find.byKey(_sectionKey),
        findsNothing,
        reason: 'Easy Run has no muscle links, so the section collapses',
      );
    });
  });

  group('ExerciseLibraryDetailScreen — seeded muscles (S-4)', () {
    testWidgets('bench press shows both role rows', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final bench = await repo.getExerciseById('exercise-bench-press');
      expect(bench, isNotNull, reason: 'seed missing: exercise-bench-press');

      await _pumpLibraryDetail(tester, repo, bench!);

      expect(_chipIn(_primaryKey, 'Chest'), findsOneWidget);
      expect(_chipIn(_secondaryKey, 'Triceps'), findsOneWidget);
      expect(_chipIn(_secondaryKey, 'Front delts'), findsOneWidget);
    });

    testWidgets('tennis match shows primary chips only', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final tennis = await repo.getExerciseById('exercise-tennis-match');
      expect(tennis, isNotNull, reason: 'seed missing: exercise-tennis-match');

      await _pumpLibraryDetail(tester, repo, tennis!);

      expect(find.byKey(_primaryKey), findsOneWidget);
      expect(_chipIn(_primaryKey, 'Legs'), findsOneWidget);
      expect(find.byKey(_secondaryKey), findsNothing);
    });

    testWidgets('an exercise with no muscles shows no section', (
      WidgetTester tester,
    ) async {
      final repo = await _freshRepo();
      final easyRun = await repo.getExerciseById('exercise-easy-run');
      expect(easyRun, isNotNull, reason: 'seed missing: exercise-easy-run');

      await _pumpLibraryDetail(tester, repo, easyRun!);

      expect(find.text('Easy Run'), findsOneWidget);
      expect(find.byKey(_sectionKey), findsNothing);
    });
  });
}
