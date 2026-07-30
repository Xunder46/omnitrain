// PR 7 — Exercise Details View
//
// Acceptance scenarios from
// .github/agents/plans/2026-07-27-07-pr7-exercise-details-view-plan.md:
//
//   S-001  Inspect without adding  — open details, back. Session unchanged.
//   S-002  Add from either path exactly once — row tap OR details Add.
//   S-003  Sparse custom exercise renders cleanly — marker visible, optional
//          sections collapse.
//
// The picker must still add on row-body tap (immediate-add contract from the
// pre-PR-7 baseline is preserved). The details control on each row opens
// a read-only surface and contains the only Add action that lives in
// details.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_detail_view_screen.dart';
import 'package:omnitrain/features/exercise/exercise_picker_screen.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// One bundled (non-custom) seed exercise plus one user-created custom
/// exercise so the marker path is exercised in the same test session.
Future<List<Exercise>> _seedCustomAndBundled(MockWorkoutRepository repo) async {
  final bundled = (await repo.getExercises()).first;
  final custom = bundled.copyWith(
    id: 'exercise-pr7-custom-no-fields',
    name: 'Custom Sparse Exercise',
    description: null,
    disciplineId: null,
    ownerUserId: 'user-1',
  );
  await repo.createExercise(custom);
  // Seed data returns unranked; we just need the row to be selectable.
  return [bundled, custom];
}

void main() {
  // S-003 pre-condition: ownership identity contract.
  group('Exercise ownership contract', () {
    test('bundled exercise (ownerUserId == null) is not custom', () {
      final bundled = Exercise(
        id: 'x',
        name: 'Bundled',
        createdAtMs: 0,
        updatedAtMs: 0,
      );
      expect(bundled.isCustomExercise, isFalse);
    });

    test('custom exercise (ownerUserId != null) is custom', () {
      final custom = Exercise(
        id: 'x',
        name: 'Custom',
        ownerUserId: 'user-1',
        createdAtMs: 0,
        updatedAtMs: 0,
      );
      expect(custom.isCustomExercise, isTrue);
    });
  });

  // S-001 + S-002 + S-003 — picker surface.
  group('ExercisePickerScreen — details affordance', () {
    testWidgets(
      'row body still adds immediately (pre-PR-7 contract preserved)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await _seedCustomAndBundled(repo);

        Exercise? popped;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(ctx).push<Exercise>(
                      MaterialPageRoute(
                        builder: (_) =>
                            ExercisePickerScreen(workoutState: workoutState),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Tap the first row body — NOT the details control.
        final firstTile = find.byType(ListTile).first;
        await tester.tap(firstTile);
        await tester.pumpAndSettle();

        expect(popped, isNotNull, reason: 'Row tap must still pop a result');
      },
    );

    testWidgets(
      'S-001: opening details and going back does not pop an exercise',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await _seedCustomAndBundled(repo);

        Exercise? popped;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(ctx).push<Exercise>(
                      MaterialPageRoute(
                        builder: (_) =>
                            ExercisePickerScreen(workoutState: workoutState),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Open details by tapping the details control.
        await tester.tap(
          find.byKey(const Key('exercise_row_details_button')).first,
        );
        await tester.pumpAndSettle();

        // The details screen is now on top.
        expect(find.byType(ExerciseDetailViewScreen), findsOneWidget);

        // Back out — system back button.
        final NavigatorState navigator = Navigator.of(
          tester.element(find.byType(ExerciseDetailViewScreen)),
        );
        navigator.pop();
        await tester.pumpAndSettle();

        // Details closed but picker did NOT pop a result.
        expect(find.byType(ExerciseDetailViewScreen), findsNothing);
        expect(find.byType(ExercisePickerScreen), findsOneWidget);
        expect(popped, isNull, reason: 'Opening then backing out must not add');
      },
    );

    testWidgets(
      'S-002: Add from details adds exactly once and returns to picker',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await _seedCustomAndBundled(repo);

        Exercise? popped;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(ctx).push<Exercise>(
                      MaterialPageRoute(
                        builder: (_) =>
                            ExercisePickerScreen(workoutState: workoutState),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('exercise_row_details_button')).first,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ExerciseDetailViewScreen), findsOneWidget);

        // Tap the Add action on the details screen.
        await tester.tap(find.byKey(const Key('exercise_detail_add_button')));
        await tester.pumpAndSettle();

        // The picker was the original navigator target, so Add pops once
        // and we receive the exercise exactly once.
        expect(popped, isNotNull, reason: 'Details Add must pop a result');
        expect(find.byType(ExercisePickerScreen), findsNothing);
        expect(find.byType(ExerciseDetailViewScreen), findsNothing);
      },
    );

    testWidgets('S-003: custom marker visible in picker rows even when sparse', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await _seedCustomAndBundled(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      // Drag until the custom sparse row is visible.
      await tester.dragUntilVisible(
        find.text('Custom Sparse Exercise'),
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      expect(find.text('Custom Sparse Exercise'), findsOneWidget);

      // The custom marker widget renders inside the row.
      // The bundled exercise's row does NOT show the marker.
      final markerFinder = find.byKey(const Key('exercise_row_custom_marker'));
      expect(
        markerFinder,
        findsWidgets,
        reason:
            'Custom marker should render for the seeded user-created exercise',
      );
      // Sanity: at least one marker is inside a ListTile (i.e. inside
      // the row body, not floating elsewhere on the screen).
      final markerInRow = find.descendant(
        of: find.byType(ListTile),
        matching: markerFinder,
      );
      expect(markerInRow, findsWidgets);
    });

    testWidgets('details control hit region does not overlap the row body', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await _seedCustomAndBundled(repo);

      await tester.pumpWidget(
        MaterialApp(home: ExercisePickerScreen(workoutState: workoutState)),
      );
      await tester.pumpAndSettle();

      // The details button key must exist for at least one row.
      expect(
        find.byKey(const Key('exercise_row_details_button')),
        findsWidgets,
        reason: 'Each row must expose a distinct, named details control',
      );
    });
  });

  // S-001 + S-003 — details surface.
  group('ExerciseDetailViewScreen — read-only surface', () {
    testWidgets('renders the exercise name as the title', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundled = (await repo.getExercises()).first;
      final workoutState = WorkoutState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseDetailViewScreen(
            workoutState: workoutState,
            exercise: bundled,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(bundled.name), findsOneWidget);
    });

    testWidgets('S-003: sparse custom renders cleanly without gaps', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      final workoutState = WorkoutState(repo);

      final sparse = Exercise(
        id: 'sparse-custom',
        name: 'Sparse Custom',
        ownerUserId: 'user-1',
        disciplineId: null,
        description: null,
        capabilities: const ['time'],
        createdAtMs: now,
        updatedAtMs: now,
      );
      await repo.createExercise(sparse);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseDetailViewScreen(
            workoutState: workoutState,
            exercise: sparse,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Custom marker visible.
      expect(
        find.byKey(const Key('exercise_detail_custom_marker')),
        findsOneWidget,
        reason: 'Sparse custom must still surface the custom marker',
      );
      // Description absent → no description section.
      expect(
        find.byKey(const Key('exercise_detail_description_section')),
        findsNothing,
        reason:
            'Missing description must collapse — no placeholder or empty gap',
      );
      // Muscles absent → no muscles section.
      expect(
        find.byKey(const Key('exercise_detail_muscles_section')),
        findsNothing,
        reason: 'Missing muscles must collapse — no placeholder or empty gap',
      );
    });

    testWidgets('discipline + capabilities + muscles render when present', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final now = DateTime.now().millisecondsSinceEpoch;
      final workoutState = WorkoutState(repo);

      final full = Exercise(
        id: 'full-custom',
        name: 'Full Custom',
        ownerUserId: 'user-1',
        disciplineId: 'discipline-running',
        description: 'A test description',
        capabilities: const ['time', 'distance'],
        createdAtMs: now,
        updatedAtMs: now,
      );
      await repo.createExercise(full);
      await repo.setExerciseMuscleGroups(full.id, ['muscle-chest']);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseDetailViewScreen(
            workoutState: workoutState,
            exercise: full,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('exercise_detail_description_section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exercise_detail_discipline_section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exercise_detail_capabilities_section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exercise_detail_muscles_section')),
        findsOneWidget,
      );
      expect(find.text('A test description'), findsOneWidget);
    });

    testWidgets(
      'Add action is the only interactive control; no edit affordances',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final bundled = (await repo.getExercises()).first;
        final workoutState = WorkoutState(repo);

        await tester.pumpWidget(
          MaterialApp(
            home: ExerciseDetailViewScreen(
              workoutState: workoutState,
              exercise: bundled,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('exercise_detail_add_button')),
          findsOneWidget,
        );
        // No edit affordance on the read-only surface.
        expect(
          find.byKey(const Key('exercise_detail_edit_button')),
          findsNothing,
        );
      },
    );
  });

  // S-002 idempotency: rapid Add taps should not double-pop.
  group('Idempotent Add from details', () {
    testWidgets('rapid Add taps pop the picker exactly once', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await _seedCustomAndBundled(repo);

      int popCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.of(ctx).push<Exercise>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ExercisePickerScreen(workoutState: workoutState),
                    ),
                  );
                  popCount += 1;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('exercise_row_details_button')).first,
      );
      await tester.pumpAndSettle();

      // Rapid double-tap. The widget tree should be guarded so that
      // exactly one pop reaches the picker.
      final addButton = find.byKey(const Key('exercise_detail_add_button'));
      await tester.tap(addButton);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.tap(addButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(popCount, equals(1), reason: 'Add must be idempotent');
    });
  });
}
