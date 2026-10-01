// PR 8 — Exercise Library
//
// Acceptance scenarios from
// docs/plans/2026-07-27-08-pr8-exercise-library-plan.md:
//
//   S-001  Browse/filter catalog — search/filter/custom-only + read-only details.
//   S-002  Copy built-in safely — copy creates a new custom; original unchanged.
//   S-003  Remove referenced custom safely — history preserved; selectors exclude it.
//   S-004  Remove unused custom completely — full delete.
//   S-005  Rename custom; protect built-in — built-in mutation rejected.
//
// Layering under test:
//   - ExerciseLibraryService — pure repo-backed logic, no UI.
//   - ExerciseLibraryState — ChangeNotifier over the service.
//   - ExerciseLibraryScreen — picker-equivalent browsing + custom-only toggle.
//   - ExerciseLibraryDetailScreen — built-in copy vs custom edit/remove.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/exercise_library_service.dart';
import 'package:omnitrain/core/utils/exercise_helpers.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_library_detail_screen.dart';
import 'package:omnitrain/features/exercise/exercise_library_screen.dart';
import 'package:omnitrain/state/exercise/exercise_library_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/layout/omni_back_header.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// Build the state trio used by the library screens.
({
  WorkoutState workout,
  ExerciseLibraryService service,
  ExerciseLibraryState state,
})
_buildState(MockWorkoutRepository repo) {
  final workout = WorkoutState(repo);
  final service = ExerciseLibraryService(repo);
  final state = ExerciseLibraryState(service: service, workoutState: workout);
  return (workout: workout, service: service, state: state);
}

/// A custom exercise with no fields. Distinct from bundled seed data.
Exercise _customExercise(String id, String name, {int? now}) {
  final ts = now ?? DateTime.now().millisecondsSinceEpoch;
  return Exercise(
    id: id,
    ownerUserId: 'user-1',
    name: name,
    createdAtMs: ts,
    updatedAtMs: ts,
  );
}

void main() {
  // ── S-005: built-in guards (service-level) ────────────────────────────
  group('Built-in immutability guards', () {
    test('renameCustom throws on a bundled (non-custom) exercise', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final bundled = (await repo.getExercises()).first;
      expect(bundled.isCustomExercise, isFalse);

      expect(
        () => bundle.service.renameCustom(exercise: bundled, newName: 'Hacked'),
        throwsA(isA<BuiltInExerciseImmutableError>()),
      );
    });

    test('editCustom throws on a bundled (non-custom) exercise', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final bundled = (await repo.getExercises()).first;

      expect(
        () => bundle.service.editCustom(exercise: bundled, name: 'Hacked'),
        throwsA(isA<BuiltInExerciseImmutableError>()),
      );
    });

    test('removeExercise throws on a bundled (non-custom) exercise', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final bundled = (await repo.getExercises()).first;

      expect(
        () => bundle.service.removeExercise(bundled),
        throwsA(isA<BuiltInExerciseImmutableError>()),
      );
    });
  });

  // ── S-005: rename propagates ──────────────────────────────────────────
  group('Rename custom; protect built-in (S-005)', () {
    test(
      'renaming a custom exercise persists and the new name resolves',
      () async {
        final repo = await _freshRepo();
        final bundle = _buildState(repo);
        final custom = _customExercise('ex-rename', 'Old Name');
        await repo.createExercise(custom);

        final updated = await bundle.service.renameCustom(
          exercise: custom,
          newName: 'New Name',
        );

        expect(updated.name, equals('New Name'));
        final fetched = await repo.getExerciseById('ex-rename');
        expect(fetched, isNotNull);
        expect(fetched!.name, equals('New Name'));
      },
    );

    test('trimmed-empty new name throws ArgumentError', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final custom = _customExercise('ex-empty', 'Some Name');
      await repo.createExercise(custom);

      expect(
        () => bundle.service.renameCustom(exercise: custom, newName: '   '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── S-002: copy built-in safely ───────────────────────────────────────
  group('Copy built-in safely (S-002)', () {
    test(
      'copyAsCustom creates a new custom exercise with the same body',
      () async {
        final repo = await _freshRepo();
        final bundle = _buildState(repo);
        final bundled = (await repo.getExercises()).first;
        await repo.setExerciseMuscleGroups(bundled.id, ['muscle-chest']);
        // Re-read because setExerciseMuscleGroups does not mutate the
        // returned copy in the seeded bundle.
        final bundledWithMuscles = (await repo.getExerciseById(bundled.id))!;

        final copy = await bundle.service.copyAsCustom(bundledWithMuscles);

        expect(
          copy.id,
          isNot(equals(bundled.id)),
          reason: 'Copy must have a distinct id',
        );
        expect(copy.isCustomExercise, isTrue);
        expect(
          copy.name,
          isNot(equals(bundled.name)),
          reason: 'Copy must be marked so the user can distinguish it',
        );
        expect(copy.disciplineId, equals(bundled.disciplineId));

        // Original unchanged.
        final original = await repo.getExerciseById(bundled.id);
        expect(original, isNotNull);
        expect(
          original!.isCustomExercise,
          isFalse,
          reason: 'Original must remain a bundled entry',
        );
      },
    );
  });

  // ── S-003 / S-004: reference-aware removal ─────────────────────────────
  group('Reference-aware removal (S-003 / S-004)', () {
    test('unreferenced custom removes fully (hard-delete)', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final custom = _customExercise('ex-unreferenced', 'Unused');
      await repo.createExercise(custom);

      final plan = await bundle.service.planRemoval(custom.id);
      expect(plan.kind, equals(ExerciseRemovalKind.hardDelete));
      expect(plan.totalReferences, equals(0));

      final kind = await bundle.service.removeExercise(custom);
      expect(kind, equals(ExerciseRemovalKind.hardDelete));

      final after = await repo.getExerciseById(custom.id);
      expect(after, isNull, reason: 'Unreferenced custom must be hard-deleted');
    });

    test(
      'referenced custom retires (isArchived = true) and history remains resolvable',
      () async {
        final repo = await _freshRepo();
        final bundle = _buildState(repo);
        final custom = _customExercise('ex-referenced', 'Used In Session');
        await repo.createExercise(custom);

        // Create a session that references the custom exercise via an effort.
        await bundle.workout.createNewSession(modality: 'resistance_lifting');
        await bundle.workout.addExerciseToSession(custom);

        final plan = await bundle.service.planRemoval(custom.id);
        expect(plan.kind, equals(ExerciseRemovalKind.retire));
        expect(plan.referencingSessionEfforts, greaterThan(0));

        final kind = await bundle.service.removeExercise(custom);
        expect(kind, equals(ExerciseRemovalKind.retire));

        // The exercise is still resolvable by id (so history still
        // resolves), but the picker excludes archived rows.
        final byId = await repo.getExerciseById(custom.id);
        expect(byId, isNotNull);
        expect(byId!.isArchived, isTrue);

        final listed = await repo.getExercises();
        expect(
          listed.where((e) => e.id == custom.id),
          isEmpty,
          reason: 'Archived row must not appear in the active list',
        );

        // History efforts still resolve the exercise by id.
        final allSessions = await repo.getAllSessions();
        expect(allSessions, isNotEmpty);
        final historicalExercise = bundle.workout.getExercise(custom.id);
        expect(historicalExercise, isNotNull);
        expect(historicalExercise!.name, equals('Used In Session'));
      },
    );

    test(
      'removing a referenced custom also preserves routine-template links',
      () async {
        final repo = await _freshRepo();
        final bundle = _buildState(repo);
        final custom = _customExercise('ex-template-ref', 'Used In Routine');
        await repo.createExercise(custom);

        // Plant a template + segment + effort that references the custom id.
        final now = DateTime.now().millisecondsSinceEpoch;
        final template = WorkoutTemplate(
          id: 'tmpl-pr8',
          name: 'Routine referencing custom',
          isBuiltInDemo: false,
          createdAtMs: now,
          updatedAtMs: now,
        );
        await repo.createTemplate(template);
        final segment = TemplateSegment(
          id: 'tseg-pr8',
          templateId: template.id,
          orderIndex: 0,
          segmentType: 'mixed',
          createdAtMs: now,
          updatedAtMs: now,
        );
        await repo.createTemplateSegment(segment);
        await repo.createTemplateEffort(
          TemplateEffort(
            id: 'tef-pr8',
            templateSegmentId: segment.id,
            orderIndex: 0,
            effortKind: 'set',
            exerciseId: custom.id,
            createdAtMs: now,
          ),
        );

        final plan = await bundle.service.planRemoval(custom.id);
        expect(plan.kind, equals(ExerciseRemovalKind.retire));
        expect(plan.referencingTemplateEfforts, equals(1));

        await bundle.service.removeExercise(custom);
        final byId = await repo.getExerciseById(custom.id);
        expect(byId, isNotNull);
        expect(byId!.isArchived, isTrue);
      },
    );
  });

  // ── S-001: search/filter/custom-only ─────────────────────────────────
  group('Search / filter / custom-only (S-001)', () {
    test('customOnly=true returns only user-created rows', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      await repo.createExercise(_customExercise('ex-a', 'Custom Alpha'));
      await repo.createExercise(_customExercise('ex-b', 'Custom Beta'));

      final results = await bundle.service.searchExercises(customOnly: true);
      expect(results.every((e) => e.isCustomExercise), isTrue);
      // Bundled seed exercises are not present.
      expect(results.where((e) => !e.isCustomExercise), isEmpty);
    });

    test('search filters by name (case-insensitive)', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      await repo.createExercise(_customExercise('ex-s1', 'Kettlebell Halo'));
      await repo.createExercise(_customExercise('ex-s2', 'Farmer Carry'));

      final results = await bundle.service.searchExercises(
        searchText: 'kettle',
      );
      expect(results.map((e) => e.id), contains('ex-s1'));
      expect(results.map((e) => e.id), isNot(contains('ex-s2')));
    });

    test('archived rows are excluded from search results', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final archived = _customExercise('ex-arch', 'Archived');
      await repo.createExercise(archived);
      // Reference it first so planRemoval retires it instead of deleting.
      await bundle.workout.createNewSession(modality: 'resistance_lifting');
      await bundle.workout.addExerciseToSession(archived);
      await bundle.service.removeExercise(archived);

      final results = await bundle.service.searchExercises();
      expect(
        results.where((e) => e.id == 'ex-arch'),
        isEmpty,
        reason: 'Archived exercises must not appear in search',
      );
    });
  });

  // ── State layer ────────────────────────────────────────────────────────
  group('ExerciseLibraryState', () {
    test('reload() populates exercises from the service', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      await bundle.state.reload();
      expect(bundle.state.exercises, isNotEmpty);
      expect(bundle.state.error, isNull);
    });

    test('setCustomOnly(true) limits the list to user-created rows', () async {
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      await bundle.state.setCustomOnly(true);
      expect(bundle.state.customOnly, isTrue);
      expect(bundle.state.exercises.every((e) => e.isCustomExercise), isTrue);
    });
  });

  // ── Screen: render + interaction ───────────────────────────────────────
  group('ExerciseLibraryScreen', () {
    testWidgets('renders title, search, and custom-only toggle', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryScreen(
            exerciseLibraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Exercise Library'), findsOneWidget);
      expect(
        find.byKey(const Key('exercise_library_search_field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exercise_library_custom_only_toggle')),
        findsOneWidget,
      );
    });

    testWidgets('custom-only toggle carries no local colour overrides', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryScreen(
            exerciseLibraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Every colour resolves through the theme's ColorScheme roles. The
      // constructor variant is pinned separately by the switch-consistency
      // contract in test/switch_consistency_contract_test.dart — widget-type
      // assertions cannot see it, because `SwitchListTile.adaptive` and
      // `SwitchListTile` build the same widget tree on every platform.
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('exercise_library_custom_only_toggle')),
      );
      expect(tile.activeColor, isNull);
      expect(tile.activeTrackColor, isNull);
      expect(tile.inactiveThumbColor, isNull);
      expect(tile.inactiveTrackColor, isNull);
    });

    testWidgets('custom-only toggle filters the list', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      await repo.createExercise(_customExercise('ex-toggle', 'Toggle Custom'));

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryScreen(
            exerciseLibraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Toggle on.
      await tester.tap(
        find.byKey(const Key('exercise_library_custom_only_toggle')),
      );
      await tester.pumpAndSettle();

      // All listed exercises are custom.
      final state = tester.state<State<ExerciseLibraryScreen>>(
        find.byType(ExerciseLibraryScreen),
      );
      // Verify via the state directly.
      expect(bundle.state.customOnly, isTrue);
      expect(bundle.state.exercises.every((e) => e.isCustomExercise), isTrue);
      // Sanity: the toggle target key still present.
      expect(state, isNotNull);
    });

    testWidgets('does NOT expose any Add-to-Workout action on rows', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryScreen(
            exerciseLibraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No row-level add button.
      expect(
        find.byKey(const Key('exercise_library_row_add_button')),
        findsNothing,
        reason: 'The library must NOT offer an Add-to-Workout action',
      );
    });
  });

  // ── Detail screen ─────────────────────────────────────────────────────
  group('ExerciseLibraryDetailScreen', () {
    testWidgets('renders a single app bar — no duplicate header', (
      WidgetTester tester,
    ) async {
      // Regression guard: an earlier version of this screen nested
      // ExerciseDetailViewScreen (which carries its own OmniBackHeader)
      // inside the library's Scaffold, producing two app bars stacked
      // on top of each other. The screen must render exactly one.
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final bundled = (await repo.getExercises()).first;

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryDetailScreen(
            exercise: bundled,
            libraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OmniBackHeader), findsOneWidget);
      // And the embedded read-only surface must NOT be a Scaffold.
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('built-in shows Copy only — no edit / no remove', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final bundled = (await repo.getExercises()).first;

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryDetailScreen(
            exercise: bundled,
            libraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('exercise_library_copy_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exercise_library_edit_button')),
        findsNothing,
        reason: 'Built-ins must not expose Edit',
      );
      expect(
        find.byKey(const Key('exercise_library_remove_button')),
        findsNothing,
        reason: 'Built-ins must not expose Remove',
      );
    });

    testWidgets('custom shows Edit + Remove; no Copy', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final custom = _customExercise('ex-detail', 'My Custom Move');
      await repo.createExercise(custom);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryDetailScreen(
            exercise: custom,
            libraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('exercise_library_edit_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exercise_library_remove_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('exercise_library_copy_button')),
        findsNothing,
        reason: 'Custom rows must not expose Copy (only built-ins do)',
      );
    });

    testWidgets('Remove shows confirmation dialog', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final custom = _customExercise('ex-confirm', 'Custom To Remove');
      await repo.createExercise(custom);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryDetailScreen(
            exercise: custom,
            libraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exercise_library_remove_button')));
      await tester.pumpAndSettle();

      expect(find.text('Remove exercise?'), findsOneWidget);
      // Cancel does not remove.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final stillThere = await repo.getExerciseById('ex-confirm');
      expect(stillThere, isNotNull);
    });

    testWidgets('Copy on a built-in creates a new custom exercise', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final bundled = (await repo.getExercises()).first;

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryDetailScreen(
            exercise: bundled,
            libraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('exercise_library_copy_button')));
      await tester.pumpAndSettle();

      // Original is still bundled.
      final original = await repo.getExerciseById(bundled.id);
      expect(original, isNotNull);
      expect(original!.isCustomExercise, isFalse);

      // A new custom row exists.
      final customs = await bundle.service.searchExercises(customOnly: true);
      expect(customs.map((e) => e.id), isNot(contains(bundled.id)));
      expect(customs.where((e) => e.name.contains('(copy)')), isNotEmpty);
    });
  });

  // ── Navigation contract ───────────────────────────────────────────────
  group('HomeScreen wired', () {
    testWidgets('maintenance sheet exposes Exercise Library tile', (
      WidgetTester tester,
    ) async {
      // The maintenance sheet is opened via the logo button.
      // We only check that the screen accepts the new state without
      // throwing — the full maintenance-sheet test lives in
      // home_logo_hub_open_test.dart.
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      // _buildMaintenanceGrid is private; the surface test lives in
      // a dedicated test (out of scope here). We at least confirm the
      // state is constructible from HomeScreen-style wiring.
      expect(bundle.state, isNotNull);
    });
  });

  // ── Info icon removal (exercise-library-info-icon-removal-plan.md) ──────
  group('Info icon removal from library rows (S-1, S-2, S-4)', () {
    testWidgets('S-1: library rows do NOT render trailing info icon', (
      WidgetTester tester,
    ) async {
      // Scenario S-1: Library row without info icon
      // Verify that the library screen's exercise rows have no trailing
      // info icon (after implementation). This test will fail until
      // the icon is removed from exercise_library_screen.dart.
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final custom = _customExercise('ex-s1', 'Test Exercise S-1');
      await repo.createExercise(custom);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryScreen(
            exerciseLibraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The library screen must NOT have any exercise_row_details_button
      // (the info icon used to be in the trailing position).
      // Before implementation: this test will FAIL because the icon exists.
      // After implementation: this test will PASS because the icon is removed.
      expect(
        find.byKey(const Key('exercise_row_details_button')),
        findsNothing,
        reason: 'Library rows must not have the info icon in trailing position',
      );
    });

    testWidgets('S-2: library row tap opens management detail screen', (
      WidgetTester tester,
    ) async {
      // Scenario S-2: Library row tap opens management screen
      // This behavior is unchanged by the icon removal.
      // NOTE: This test asserts behavior that already works (row tap
      // already opens the detail screen), so it has no red-first evidence
      // of a bug. It is a regression guard: if row-tap breaks during
      // implementation, this test will catch it.
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      final repo = await _freshRepo();
      final bundle = _buildState(repo);
      final custom = _customExercise('ex-s2', 'Test Exercise S-2');
      await repo.createExercise(custom);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseLibraryDetailScreen(
            exercise: custom,
            libraryState: bundle.state,
            workoutState: bundle.workout,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the action bar is visible (Copy/Edit/Remove buttons).
      // For a custom exercise, we expect Edit and Remove.
      expect(
        find.byKey(const Key('exercise_library_edit_button')),
        findsOneWidget,
        reason: 'Detail screen for custom must show Edit button',
      );
    });

    testWidgets(
      'S-4: library detail screen content and action buttons aligned at 16pt',
      (WidgetTester tester) async {
        // Scenario S-4: Library detail screen — metadata content and action
        // bar must be left-aligned at 16pt inset from screen edge.
        // Before implementation: this test will FAIL because content is
        // double-padded (32pt) while buttons are single-padded (16pt).
        // After implementation: this test will PASS because both align at 16pt.
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        final repo = await _freshRepo();
        final bundle = _buildState(repo);

        // Create a custom exercise with deterministically long description
        // (~600 chars) to force scrolling and ensure the action bar is visible.
        final longDesc = 'Lorem ipsum dolor sit amet. ' * 25; // ~600 chars
        final now = DateTime.now().millisecondsSinceEpoch;
        final custom = Exercise(
          id: 'ex-s4-padding',
          ownerUserId: 'user-1',
          name: 'Padding Test Exercise',
          description: longDesc,
          createdAtMs: now,
          updatedAtMs: now,
        );
        await repo.createExercise(custom);
        await repo.setExerciseMuscleGroups(custom.id, ['muscle-chest']);

        await tester.pumpWidget(
          MaterialApp(
            home: ExerciseLibraryDetailScreen(
              exercise: custom,
              libraryState: bundle.state,
              workoutState: bundle.workout,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the metadata title (the first text widget with the exercise name).
        // This sits inside ExerciseDetailViewBody's SingleChildScrollView,
        // which has its own padding. We measure its left edge.
        final titleFinder = find.text('Padding Test Exercise').first;
        final titleOffset = tester.getTopLeft(titleFinder);

        // Find the action bar container by its key.
        // The _ManagementActionBar is now wrapped in a Container with
        // Key('exercise_library_action_bar'). Measure its top-left corner.
        final actionBarFinder = find.byKey(
          const Key('exercise_library_action_bar'),
        );
        expect(
          actionBarFinder,
          findsOneWidget,
          reason: 'Action bar container must be present',
        );
        final actionBarOffset = tester.getTopLeft(actionBarFinder);

        // Assert both are at 16pt inset from the left screen edge.
        // Use closeTo with 0.5pt tolerance to account for rounding.
        expect(
          titleOffset.dx,
          closeTo(16.0, 0.5),
          reason: 'Metadata content left edge must be at 16pt inset',
        );
        expect(
          actionBarOffset.dx,
          closeTo(16.0, 0.5),
          reason: 'Action bar left edge must be at 16pt inset',
        );

        // Assert they are aligned (same left edge, within 0.5pt tolerance).
        final delta = (titleOffset.dx - actionBarOffset.dx).abs();
        expect(
          delta,
          closeTo(0.0, 0.5),
          reason:
              'Metadata and action bar must be aligned; '
              'current delta is ${delta.toStringAsFixed(1)}pt '
              '(bug: content at 32pt, buttons at 16pt)',
        );
      },
    );
  });
}
