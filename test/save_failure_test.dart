// Plan 266: a save that fails in storage stays on its screen, says so, and
// leaves Save usable. Routine, daily target and training period.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_target_screen.dart';
import 'package:omnitrain/features/period/create_period_screen.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/period/period_state.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';

const _failText = 'Could not save. Try again.';

/// A repository whose three save writes can be made to throw.
class _FailingRepo extends MockWorkoutRepository {
  bool fail = true;

  @override
  Future<String> createTemplate(WorkoutTemplate template) async {
    if (fail) throw StateError('disk full');
    return super.createTemplate(template);
  }

  @override
  Future<void> saveNutritionTargetForDate(
    int dateMs,
    NutritionTarget target,
  ) async {
    if (fail) throw StateError('disk full');
    return super.saveNutritionTargetForDate(dateMs, target);
  }

  @override
  Future<void> updatePeriod(TrainingPeriod period) async {
    if (fail) throw StateError('disk full');
    return super.updatePeriod(period);
  }
}

Future<_FailingRepo> _repo() async {
  final repo = _FailingRepo();
  await repo.initialize();
  return repo;
}

void main() {
  testWidgets(
    'S-26601 a failed routine save stays, says so, and a retry works',
    (tester) async {
      final repo = await _repo();
      final routineState = RoutineState(repo)..setAutosaveEnabled(false);
      final settings = SettingsState(repo, fakePreferencesService());
      await settings.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: RoutineSetupScreen(
            routineState: routineState,
            workoutState: WorkoutState(repo),
            settingsState: settings,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Routine Name'),
        'Leg day',
      );
      final exercises = await repo.getExercises();
      await routineState.addExerciseToRoutine(
        exercises.firstWhere((e) => e.id == 'exercise-barbell-squat'),
        'set',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(_failText), findsOneWidget);
      expect(find.text('Routine saved successfully'), findsNothing);
      expect(find.byType(RoutineSetupScreen), findsOneWidget);
      expect(
        (await repo.getTemplates()).where((t) => t.name == 'Leg day'),
        isEmpty,
      );

      // Storage recovers: the same screen saves and closes.
      repo.fail = false;
    // The message sits over the bottom of the screen: let it clear first.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RoutineSetupScreen), findsNothing);
      expect(
        (await repo.getTemplates()).where((t) => t.name == 'Leg day'),
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'S-26602 a failed target save stays, keeps the old target, retries',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final repo = await _repo();
      repo.fail = false;
    // The message sits over the bottom of the screen: let it clear first.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
      final state = NutritionState(repo);
      await state.saveNutritionTarget(NutritionTarget(calories: 2000));
      repo.fail = true;

      await tester.pumpWidget(
        MaterialApp(home: NutritionTargetScreen(nutritionState: state)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('calories_field')), '2500');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(_failText), findsOneWidget);
      expect(find.byType(NutritionTargetScreen), findsOneWidget);
      // The target on screen elsewhere is not blanked by the failed write.
      expect(state.nutritionTarget?.calories, 2000);

      repo.fail = false;
    // The message sits over the bottom of the screen: let it clear first.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(NutritionTargetScreen), findsNothing);
      expect(state.nutritionTarget?.calories, 2500);
    },
  );

  testWidgets('S-26603 a failed period save leaves Save usable and says so', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = await _repo();
    final start = DateTime(2030, 3, 1);
    final end = DateTime(2030, 3, 28, 23, 59, 59, 999);
    final period = TrainingPeriod(
      id: 'p-266',
      name: 'Block',
      startDateMs: start.millisecondsSinceEpoch,
      endDateMs: end.millisecondsSinceEpoch,
      focusModalities: const [],
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    await repo.createPeriod(period);
    final periodState = PeriodState(repo);
    await periodState.load();
    await tester.pumpWidget(
      MaterialApp(
        home: CreatePeriodScreen(
          periodState: periodState,
          existingPeriod: period,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text(_failText), findsOneWidget);
    expect(find.byType(CreatePeriodScreen), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Save'), matching: find.byType(FilledButton)),
    );
    expect(save.onPressed, isNotNull, reason: 'Save is back on');

    repo.fail = false;
    // The message sits over the bottom of the screen: let it clear first.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(CreatePeriodScreen), findsNothing);
  });
}
