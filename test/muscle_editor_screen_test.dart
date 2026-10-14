// Plan 34, Phases B2 and C — the editor's muscle section, modality grid,
// scroll-to-error and unsaved guard.
//
// Scenarios S-4, S-5, S-6, S-7, S-8, S-11, S-13, S-14 and S-15 of
// `docs/plans/2026-10-14-34-muscle-editor-plan/2026-10-14-34-muscle-editor-plan.md`.
//
// The editor holds a `MuscleSelection`: the picker's chips cycle off → main →
// assists → off, an assists-only selection is refused before the save call,
// edit mode loads the stored links (roles included, legacy shapes read as main
// muscles) and both save paths store the selection normalised. The modality
// chips fill a 2×2 grid, a failed save scrolls the first field in error into
// view, and leaving a dirty form asks first.
//
// Mock-first: every fixture is a `MockWorkoutRepository`, no Hive harness.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/exercise/exercise_editor_screen.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/exercise/muscle_picker.dart';
import 'package:omnitrain/widgets/layout/omni_card_header.dart';

ExerciseMuscleLink _link(String id, [MuscleRole role = MuscleRole.primary]) =>
    ExerciseMuscleLink(muscleGroupId: id, role: role);

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// A custom exercise of the one modality that shows the muscle section.
Exercise _customExercise(String id, {String name = 'Power Clean'}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Exercise(
    id: id,
    ownerUserId: 'user-1',
    name: name,
    modality: 'resistance_lifting',
    capabilities: const ['reps'],
    createdAtMs: now,
    updatedAtMs: now,
  );
}

/// A repository whose exercise write blocks until [release] is called, so a
/// second tap on Save can be observed while the first write is still in
/// flight. `createCount` counts the writes that were actually started.
class _HangingCreateExerciseRepo extends MockWorkoutRepository {
  final Completer<void> _gate = Completer<void>();
  int createCount = 0;

  void release() => _gate.complete();

  @override
  Future<String> createExercise(Exercise exercise) async {
    createCount++;
    await _gate.future;
    return super.createExercise(exercise);
  }
}

/// A repository whose exercise update blocks until [release] is called, so a
/// back gesture can be observed while the edit-mode write is still in flight.
/// `updateCount` counts the updates that were actually started.
class _HangingUpdateExerciseRepo extends MockWorkoutRepository {
  final Completer<void> _gate = Completer<void>();
  int updateCount = 0;

  void release() => _gate.complete();

  @override
  Future<void> updateExercise(Exercise exercise) async {
    updateCount++;
    await _gate.future;
    return super.updateExercise(exercise);
  }
}

/// The editor pushed over a blank host, so the route's pop result is visible
/// to the test (the screen pops with the saved exercise).
class _EditorHost {
  Exercise? popped;
  bool hasPopped = false;
}

/// A repository whose links read fails, so the editor cannot open on the
/// stored selection.
class _ThrowingLinksRepo extends MockWorkoutRepository {
  @override
  Future<List<ExerciseMuscleLink>> getExerciseMuscleLinks(
    String exerciseId,
  ) async {
    throw StateError('links read failed');
  }
}

Future<_EditorHost> _pumpEditor(
  WidgetTester tester, {
  required WorkoutState workoutState,
  Exercise? initial,
  String? contextModality,
  Size size = const Size(600, 1400),
  TextScaler? textScaler,
}) async {
  await tester.binding.setSurfaceSize(size);
  final host = _EditorHost();
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
  );
  unawaited(
    navigatorKey.currentState!
        .push<Exercise>(
          MaterialPageRoute(
            builder: (context) {
              final screen = ExerciseEditorScreen(
                workoutState: workoutState,
                initialExercise: initial,
                contextModality: contextModality,
              );
              if (textScaler == null) return screen;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: screen,
              );
            },
          ),
        )
        .then((value) {
          host.popped = value;
          host.hasPopped = true;
        }),
  );
  await tester.pumpAndSettle();
  return host;
}

/// Scrolls [finder] into the viewport, taps it and settles.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _muscleChip(String id) => find.byKey(MusclePicker.chipKey(id));

String _summary(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

/// The name, Resistance modality and Reps capability a valid save needs.
Future<void> _fillValidForm(
  WidgetTester tester, {
  String name = 'Power Clean',
}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Exercise name'), name);
  await tester.pumpAndSettle();
  await _tap(tester, find.text('Resistance / Lifting'));
  await _tap(tester, find.widgetWithText(FilterChip, 'Reps'));
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save exercise'));
  await tester.pumpAndSettle();
}

void main() {
  group('S-4 editor save rules', () {
    testWidgets('an assists-only selection is blocked and creates nothing', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final host = await _pumpEditor(tester, workoutState: workoutState);
      final countBefore = (await repo.getExercises()).length;

      await _fillValidForm(tester);
      await _tap(tester, _muscleChip('muscle-triceps'));
      await _tap(tester, _muscleChip('muscle-triceps'));
      expect(_summary(tester, MusclePicker.mainSummaryKey), 'Main: none');
      expect(
        _summary(tester, MusclePicker.assistsSummaryKey),
        'Assists: Triceps',
      );

      await _save(tester);

      expect(find.text('Pick at least one main muscle.'), findsOneWidget);
      expect(host.hasPopped, isFalse);
      expect((await repo.getExercises()).length, countBefore);

      await _tap(tester, _muscleChip('muscle-chest'));
      await _save(tester);

      expect(host.hasPopped, isTrue);
      final saved = host.popped!;
      expect(saved.name, 'Power Clean');
      expect(await repo.getExerciseMuscleLinks(saved.id), [
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
      ]);
    });

    testWidgets('saving with nothing chosen succeeds with no links', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final host = await _pumpEditor(tester, workoutState: workoutState);

      await _fillValidForm(tester);
      expect(_summary(tester, MusclePicker.mainSummaryKey), 'Main: none');

      await _save(tester);

      expect(host.hasPopped, isTrue);
      expect(await repo.getExerciseMuscleLinks(host.popped!.id), isEmpty);
    });

    testWidgets(
      'Sports hides the picker and a round trip clears the selection',
      (tester) async {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await _pumpEditor(tester, workoutState: workoutState);

        await _tap(tester, find.text('Sports'));
        expect(find.byKey(MusclePicker.hintKey), findsNothing);

        await _tap(tester, find.text('Resistance / Lifting'));
        expect(find.byKey(MusclePicker.hintKey), findsOneWidget);
        await _tap(tester, _muscleChip('muscle-chest'));
        expect(_summary(tester, MusclePicker.mainSummaryKey), 'Main: Chest');

        await _tap(tester, find.text('Sports'));
        await _tap(tester, find.text('Resistance / Lifting'));

        expect(_summary(tester, MusclePicker.mainSummaryKey), 'Main: none');
        expect(
          _summary(tester, MusclePicker.assistsSummaryKey),
          'Assists: none',
        );
      },
    );
  });

  group('S-5 edit mode', () {
    testWidgets('shows the stored roles and saves the tapped change', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final exercise = _customExercise('exercise-edit-muscles');
      await repo.createExercise(exercise);
      await repo.setExerciseMuscleLinks(exercise.id, [
        _link('muscle-chest'),
        _link('muscle-triceps', MuscleRole.secondary),
      ]);

      final host = await _pumpEditor(
        tester,
        workoutState: workoutState,
        initial: exercise,
      );

      expect(find.text('Edit Exercise'), findsOneWidget);
      expect(_summary(tester, MusclePicker.mainSummaryKey), 'Main: Chest');
      expect(
        _summary(tester, MusclePicker.assistsSummaryKey),
        'Assists: Triceps',
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Resistance / Lifting'),
            )
            .onSelected,
        isNull,
        reason: 'the stored modality is read-only in edit mode',
      );

      await _tap(tester, _muscleChip('muscle-triceps'));
      expect(_summary(tester, MusclePicker.assistsSummaryKey), 'Assists: none');

      await _save(tester);

      expect(host.hasPopped, isTrue);
      expect(await repo.getExerciseMuscleLinks(exercise.id), [
        _link('muscle-chest'),
      ]);
    });

    testWidgets('a failing links read shows the failure and leaves', (
      tester,
    ) async {
      final repo = _ThrowingLinksRepo();
      await repo.initialize();
      final workoutState = WorkoutState(repo);
      final exercise = _customExercise('exercise-failing-links');
      await repo.createExercise(exercise);

      final host = await _pumpEditor(
        tester,
        workoutState: workoutState,
        initial: exercise,
      );

      expect(
        find.text('Could not load this exercise. Try again.'),
        findsOneWidget,
      );
      expect(host.hasPopped, isTrue);
      expect(find.text('Edit Exercise'), findsNothing);
    });
  });

  group('S-11 legacy shape', () {
    testWidgets('all-primary links open as main muscles and re-store '
        'normalised', (tester) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final exercise = _customExercise('exercise-legacy-muscles');
      await repo.createExercise(exercise);
      // The pre-role storage shape: one id per muscle, each read as a main
      // muscle.
      await repo.putRawExerciseMuscleLinksForTest(exercise.id, [
        _link('muscle-chest'),
        _link('muscle-triceps'),
      ]);

      final host = await _pumpEditor(
        tester,
        workoutState: workoutState,
        initial: exercise,
      );

      expect(
        _summary(tester, MusclePicker.mainSummaryKey),
        'Main: Triceps, Chest',
      );
      expect(_summary(tester, MusclePicker.assistsSummaryKey), 'Assists: none');

      await _save(tester);

      expect(host.hasPopped, isTrue);
      expect(await repo.getExerciseMuscleLinks(exercise.id), [
        _link('muscle-triceps'),
        _link('muscle-chest'),
      ]);
    });
  });

  group('S-6 modality grid and headers', () {
    const labels = [
      'Cardio / Endurance',
      'Resistance / Lifting',
      'Sports',
      'Isometric / Stretching',
    ];

    testWidgets('the four chips fill two equal-width rows at 390 and 320', (
      tester,
    ) async {
      for (final size in const [Size(390, 844), Size(320, 568)]) {
        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await _pumpEditor(tester, workoutState: workoutState, size: size);

        expect(find.byType(ChoiceChip), findsNWidgets(4), reason: '$size');

        final chips = [
          for (final label in labels) find.widgetWithText(ChoiceChip, label),
        ];
        final widths = [for (final chip in chips) tester.getSize(chip).width];
        expect(widths.toSet(), hasLength(1), reason: 'equal widths at $size');
        // Two Expanded halves of the row less the 8 dp gap: the formula, not
        // just equality.
        expect(
          widths.first,
          closeTo((size.width - 32 - 8) / 2, 0.5),
          reason: 'half-row chip width at $size',
        );

        final tops = [for (final chip in chips) tester.getTopLeft(chip).dy];
        expect(tops[0], tops[1], reason: 'row 1 at $size');
        expect(tops[2], tops[3], reason: 'row 2 at $size');
        expect(tops[2], greaterThan(tops[0]), reason: 'two rows at $size');

        // Cell order, not just geometry: the row reads left to right in
        // `_modalityOptions` order.
        final lefts = [for (final chip in chips) tester.getTopLeft(chip).dx];
        expect(
          lefts[0],
          lessThan(lefts[1]),
          reason: 'Cardio / Endurance left of Resistance / Lifting at $size',
        );
        expect(
          lefts[2],
          lessThan(lefts[3]),
          reason: 'Sports left of Isometric / Stretching at $size',
        );

        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('the section headers are OmniCardHeader, the old title gone', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await _pumpEditor(tester, workoutState: workoutState);

      expect(find.byType(OmniCardHeader), findsNWidgets(2));
      expect(find.widgetWithText(OmniCardHeader, 'MODALITY'), findsOneWidget);
      expect(
        find.widgetWithText(OmniCardHeader, 'CAPABILITIES'),
        findsOneWidget,
      );
      expect(find.text('Muscle groups'), findsNothing);

      await _tap(tester, find.text('Resistance / Lifting'));

      expect(find.byType(OmniCardHeader), findsNWidgets(3));
      expect(find.widgetWithText(OmniCardHeader, 'MUSCLES'), findsOneWidget);
      expect(find.text('Muscle groups'), findsNothing);

      await _tap(tester, find.text('Sports'));

      expect(find.byType(OmniCardHeader), findsNWidgets(2));
      expect(find.widgetWithText(OmniCardHeader, 'MUSCLES'), findsNothing);
    });
  });

  group('S-7 scroll to the first error', () {
    testWidgets('a failed save brings the name error into the viewport', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await _pumpEditor(
        tester,
        workoutState: workoutState,
        size: const Size(390, 700),
      );

      await _tap(tester, find.text('Resistance / Lifting'));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save exercise'));
      await tester.pumpAndSettle();

      final viewport = Rect.fromLTWH(0, 0, 390, 700);
      final error = tester.getRect(find.text('Exercise name required.'));
      expect(viewport.contains(error.topLeft), isTrue, reason: '$error');
      expect(viewport.contains(error.bottomRight), isTrue, reason: '$error');
    });
  });

  group('S-8 unsaved guard', () {
    testWidgets('an untouched form leaves without asking', (tester) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final host = await _pumpEditor(tester, workoutState: workoutState);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsNothing);
      expect(host.hasPopped, isTrue);
      expect(host.popped, isNull);
    });

    testWidgets('a dirty form asks; keep editing stays, discard leaves', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final host = await _pumpEditor(tester, workoutState: workoutState);

      await tester.enterText(
        find.widgetWithText(TextField, 'Exercise name'),
        'Power Clean',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(
        find.byKey(const Key('exercise_editor_unsaved_keep')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('exercise_editor_unsaved_keep')));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsNothing);
      expect(find.text('New Exercise'), findsOneWidget);
      expect(host.hasPopped, isFalse);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('exercise_editor_unsaved_discard')),
      );
      await tester.pumpAndSettle();

      expect(host.hasPopped, isTrue);
      expect(host.popped, isNull);
    });

    testWidgets('Save in the dialog stores the exercise and leaves', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final countBefore = (await repo.getExercises()).length;
      final host = await _pumpEditor(tester, workoutState: workoutState);

      await _fillValidForm(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('exercise_editor_unsaved_save')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('exercise_editor_unsaved_save')));
      await tester.pumpAndSettle();

      expect(host.hasPopped, isTrue);
      expect(host.popped!.name, 'Power Clean');
      expect((await repo.getExercises()).length, countBefore + 1);
    });

    testWidgets('the system back asks on a dirty form', (tester) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final host = await _pumpEditor(tester, workoutState: workoutState);

      await tester.enterText(
        find.widgetWithText(TextField, 'Exercise name'),
        'Power Clean',
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('exercise_editor_unsaved_keep')),
        findsOneWidget,
      );
      expect(host.hasPopped, isFalse);
    });

    testWidgets('a save in flight blocks both ways out and asks nothing', (
      tester,
    ) async {
      final repo = _HangingCreateExerciseRepo();
      await repo.initialize();
      final workoutState = WorkoutState(repo);
      final host = await _pumpEditor(tester, workoutState: workoutState);

      await _fillValidForm(tester);

      await tester.tap(find.text('Save exercise'));
      await tester.pump();
      expect(repo.createCount, 1, reason: 'the write is still in flight');

      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(find.text('Unsaved changes'), findsNothing);
      expect(
        find.byKey(const Key('exercise_editor_unsaved_keep')),
        findsNothing,
      );
      expect(find.text('New Exercise'), findsOneWidget, reason: 'form shown');
      expect(host.hasPopped, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Unsaved changes'), findsNothing);
      expect(find.text('New Exercise'), findsOneWidget, reason: 'form shown');
      expect(host.hasPopped, isFalse);

      repo.release();
      await tester.pumpAndSettle();

      expect(host.hasPopped, isTrue);
      expect(host.popped!.name, 'Power Clean');
    });

    testWidgets(
      'a save in flight on an unchanged form is not interrupted by the system '
      'back',
      (tester) async {
        // Edit mode with nothing changed: `_isDirty` is false, so only the
        // `!_isSaving` term of `canPop` keeps the system back out while the
        // update write is in flight.
        final repo = _HangingUpdateExerciseRepo();
        await repo.initialize();
        final workoutState = WorkoutState(repo);
        final exercise = _customExercise('exercise-edit-save-in-flight');
        await repo.createExercise(exercise);
        await repo.setExerciseMuscleLinks(exercise.id, [_link('muscle-chest')]);

        final host = await _pumpEditor(
          tester,
          workoutState: workoutState,
          initial: exercise,
        );

        expect(find.text('Edit Exercise'), findsOneWidget);
        expect(
          _summary(tester, MusclePicker.mainSummaryKey),
          'Main: Chest',
          reason: 'the stored links are loaded and nothing was tapped',
        );

        await tester.tap(find.text('Save exercise'));
        await tester.pump();
        expect(repo.updateCount, 1, reason: 'the update is still in flight');

        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(find.text('Unsaved changes'), findsNothing);
        expect(
          find.text('Edit Exercise'),
          findsOneWidget,
          reason: 'form shown',
        );
        expect(host.hasPopped, isFalse);

        repo.release();
        await tester.pumpAndSettle();

        expect(host.hasPopped, isTrue);
        expect(host.popped!.id, exercise.id);
      },
    );
  });

  group('S-8 each dirty field asks on its own', () {
    Future<void> expectBackAsks(
      WidgetTester tester, {
      required WorkoutState workoutState,
      String? contextModality,
      required Future<void> Function(WidgetTester) dirty,
    }) async {
      final host = await _pumpEditor(
        tester,
        workoutState: workoutState,
        contextModality: contextModality,
      );
      await dirty(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(host.hasPopped, isFalse);
    }

    testWidgets('editing only the description asks', (tester) async {
      final repo = await _freshRepo();
      await expectBackAsks(
        tester,
        workoutState: WorkoutState(repo),
        dirty: (tester) async {
          await tester.enterText(
            find.widgetWithText(TextField, 'Description (optional)'),
            'A short note',
          );
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('changing only the modality asks', (tester) async {
      final repo = await _freshRepo();
      await expectBackAsks(
        tester,
        workoutState: WorkoutState(repo),
        dirty: (tester) async {
          await _tap(tester, find.text('Resistance / Lifting'));
        },
      );
    });

    testWidgets('changing only the discipline asks', (tester) async {
      final repo = await _freshRepo();
      await expectBackAsks(
        tester,
        workoutState: WorkoutState(repo),
        // The modality comes from the context, so picking a discipline is
        // the only difference from the initial state.
        contextModality: 'cardio_endurance',
        dirty: (tester) async {
          await _tap(
            tester,
            find.byType(DropdownButtonFormField<String?>),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Running').last);
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('toggling only a capability asks', (tester) async {
      final repo = await _freshRepo();
      await expectBackAsks(
        tester,
        workoutState: WorkoutState(repo),
        contextModality: 'resistance_lifting',
        dirty: (tester) async {
          await _tap(tester, find.widgetWithText(FilterChip, 'Reps'));
        },
      );
    });

    testWidgets('choosing only a muscle asks', (tester) async {
      final repo = await _freshRepo();
      await expectBackAsks(
        tester,
        workoutState: WorkoutState(repo),
        contextModality: 'resistance_lifting',
        dirty: (tester) async {
          await _tap(tester, _muscleChip('muscle-chest'));
        },
      );
    });
  });

  group('S-13 back to the initial text is not an edit', () {
    testWidgets('typing a name and clearing it leaves without asking', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      final host = await _pumpEditor(tester, workoutState: workoutState);
      final nameField = find.widgetWithText(TextField, 'Exercise name');

      await tester.enterText(nameField, 'Power Clean');
      await tester.pumpAndSettle();
      await tester.enterText(nameField, '');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsNothing);
      expect(host.hasPopped, isTrue);
    });
  });

  group('S-14 a double tap on Save creates one exercise', () {
    testWidgets('two quick taps without a pump create one exercise', (
      tester,
    ) async {
      final repo = _HangingCreateExerciseRepo();
      await repo.initialize();
      final workoutState = WorkoutState(repo);
      final countBefore = (await repo.getExercises()).length;
      final host = await _pumpEditor(tester, workoutState: workoutState);

      await _fillValidForm(tester);

      // The first write is still blocked, so the editor is on screen for both
      // taps and the second one is a real second press.
      await tester.tap(find.text('Save exercise'));
      await tester.tap(find.text('Save exercise'));
      expect(repo.createCount, 1);

      repo.release();
      await tester.pumpAndSettle();

      expect(host.hasPopped, isTrue);
      expect((await repo.getExercises()).length, countBefore + 1);
    });
  });

  group('S-15 text scale on a short phone', () {
    testWidgets('Resistance at text scale 1.3 on 320 dp does not overflow', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final workoutState = WorkoutState(repo);
      await _pumpEditor(
        tester,
        workoutState: workoutState,
        size: const Size(320, 568),
        textScaler: TextScaler.linear(1.3),
      );

      await _tap(tester, find.text('Resistance / Lifting'));
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
