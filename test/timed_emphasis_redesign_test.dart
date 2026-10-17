import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart';
import 'package:omnitrain/core/constants/metric_ids.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/routine_session_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';
import 'package:omnitrain/widgets/session/value_stepper_row.dart';

import 'helpers/fake_timer_alert_service.dart';
import 'helpers/fake_preferences_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  return repo;
}

Widget _themeWrappedApp({required Widget home, required AppTheme theme}) {
  final colors = OmniTheme.colorsForTheme(theme);
  return MaterialApp(
    theme: buildTheme(
      theme: theme,
      brightness: Brightness.dark,
      secondary: colors.secondary,
      background: colors.backgroundTop,
      surface: colors.surface,
      textPrimary: colors.textDominant,
      textSecondary: colors.textSecondary,
      divider: colors.divider,
      onPrimary: getOnPrimaryForTheme(theme),
      onSecondary: getOnSecondaryForTheme(theme),
    ),
    home: home,
  );
}

String _modalityForEffortKind(String effortKind) {
  switch (effortKind) {
    case 'timed':
      return 'cardio_endurance';
    case 'drill':
      return 'isometric_stretching';
    default:
      return 'resistance_lifting';
  }
}

Exercise _testExercise(String effortKind, {required bool includeLoad}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final capabilities = <String>{
    if (effortKind == 'timed') ...['time', 'distance'],
    if (effortKind == 'drill') 'hold',
    if (includeLoad) 'load',
  }.toList();

  return Exercise(
    id: 'test-$effortKind-${includeLoad ? 'load' : 'noload'}-$now',
    modality: _modalityForEffortKind(effortKind),
    name: includeLoad
        ? 'Test ${effortKind.toUpperCase()} Load'
        : 'Test ${effortKind.toUpperCase()} No Load',
    createdAtMs: now,
    updatedAtMs: now,
    capabilities: capabilities,
  );
}

typedef _SessionDeps = ({
  MockWorkoutRepository repo,
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  Exercise exercise,
  String effortId,
});

typedef _RoutineSetupDeps = ({
  RoutineState routineState,
  WorkoutState workoutState,
  SettingsState settingsState,
  Exercise exercise,
  String templateId,
});

Future<_SessionDeps> _buildFreeSessionDeps({
  required AppTheme theme,
  required String effortKind,
  required bool includeLoad,
  double initialExtraWeight = 0.0,
  bool includeExtraWeightObservation = true,
}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  final exercise = _testExercise(effortKind, includeLoad: includeLoad);
  await repo.createExercise(exercise);

  await workoutState.createNewSession(
    modality: _modalityForEffortKind(effortKind),
  );
  final effortId = await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: effortKind,
  );

  if (includeExtraWeightObservation) {
    await workoutState.updateEntryValue(
      effortId,
      0,
      'extra-weight',
      initialExtraWeight,
    );
  } else {
    final observations = await repo.getEffortObservations(effortId);
    for (final observation in observations.where(
      (obs) => obs.metricId == MetricIds.extraWeight,
    )) {
      await repo.deleteObservation(observation.id);
    }
    await workoutState.loadSessionData();
  }

  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exercise: exercise,
    effortId: effortId,
  );
}

Future<_SessionDeps> _buildRoutineSessionDeps({
  required AppTheme theme,
  required String effortKind,
}) async {
  final repo = await _freshRepo();
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  final exercise = _testExercise(effortKind, includeLoad: true);
  await repo.createExercise(exercise);

  routineState.setAutosaveEnabled(false);
  await routineState.createNewRoutine('Timed emphasis template');
  await routineState.addExerciseToRoutine(exercise, effortKind);
  await routineState.saveRoutine();
  final templateId = routineState.currentTemplate!.id;

  final manifest = await RoutineSessionService(
    repo,
  ).buildSessionFromTemplate(templateId);
  await workoutState.createNewSession(
    modality: _modalityForEffortKind(effortKind),
    routineTemplateId: templateId,
  );
  await workoutState.populateSessionFromManifest(manifest);

  final effortId = workoutState.getExercisesWithEntries().first['id'] as String;

  return (
    repo: repo,
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exercise: exercise,
    effortId: effortId,
  );
}

Future<_RoutineSetupDeps> _buildRoutineSetupDeps({
  required AppTheme theme,
  required String effortKind,
}) async {
  final repo = await _freshRepo();
  final routineState = RoutineState(repo);
  final workoutState = WorkoutState(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await settingsState.setAppTheme(theme);
  OmniTheme.activeTheme = theme;

  final exercise = _testExercise(effortKind, includeLoad: true);
  await repo.createExercise(exercise);

  routineState.setAutosaveEnabled(false);
  await routineState.createNewRoutine('Routine emphasis setup');
  await routineState.addExerciseToRoutine(exercise, effortKind);
  await routineState.saveRoutine();

  return (
    routineState: routineState,
    workoutState: workoutState,
    settingsState: settingsState,
    exercise: exercise,
    templateId: routineState.currentTemplate!.id,
  );
}

Future<void> _openSessionDetail(
  WidgetTester tester,
  String exerciseName,
) async {
  await tester.pumpAndSettle();
  final labelMatches = find.text(exerciseName);
  if (labelMatches.evaluate().isEmpty) {
    return;
  }
  final labelFinder = labelMatches.first;
  await tester.ensureVisible(labelFinder);
  final rowTapTarget = find.ancestor(
    of: labelFinder,
    matching: find.byType(InkWell),
  );
  if (rowTapTarget.evaluate().isNotEmpty) {
    final rowInkWell = tester.widget<InkWell>(rowTapTarget.first);
    expect(rowInkWell.onTap, isNotNull);
    rowInkWell.onTap!.call();
  } else {
    await tester.tap(labelFinder);
  }
  await tester.pumpAndSettle();
}

Future<void> _openRoutineDetail(
  WidgetTester tester,
  String exerciseName,
) async {
  await tester.pumpAndSettle();
  final labelMatches = find.text(exerciseName);
  if (labelMatches.evaluate().isEmpty) {
    return;
  }
  final labelFinder = labelMatches.first;
  await tester.ensureVisible(labelFinder);
  final rowTapTarget = find.ancestor(
    of: labelFinder,
    matching: find.byType(InkWell),
  );
  final rowInkWell = tester.widget<InkWell>(rowTapTarget.first);
  expect(rowInkWell.onTap, isNotNull);
  rowInkWell.onTap!.call();
  await tester.pumpAndSettle();
}

Text _metricValueText(WidgetTester tester, {int editorIndex = 0}) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byType(InlineMetricEditor).at(editorIndex),
      matching: find.byType(Text),
    ),
  );
  return texts.first;
}

void main() {
  group('Timed emphasis redesign', () {
    testWidgets(
      'free-session timed and drill stopped states show dominant digits only: no status chrome, no weight row on an interval, one on a hold, across all themes',
      (tester) async {
        for (final themeValue in AppTheme.values) {
          for (final effortKind in const ['timed', 'drill']) {
            final deps = await _buildFreeSessionDeps(
              theme: themeValue,
              effortKind: effortKind,
              includeLoad: true,
            );

            await tester.pumpWidget(
              _themeWrappedApp(
                theme: themeValue,
                home: WorkoutSessionScreen(
                  // A fresh key per iteration: the screen reads its states in
                  // initState, so reusing the State would keep showing the
                  // previous effort kind.
                  key: ValueKey('$themeValue-$effortKind'),
                  workoutState: deps.workoutState,
                  routineState: deps.routineState,
                  sessionSummaryService: deps.sessionSummaryService,
                  timerAlertService: FakeTimerAlertService(),
                  settingsState: deps.settingsState,
                ),
              ),
            );

            await _openSessionDetail(tester, deps.exercise.name);

            final timerValue = _metricValueText(tester);

            expect(timerValue.style?.color, OmniTheme.colors.textDominant);
            // D-3/D-4/D-1/D-2: no status chrome at all, an interval has no
            // weight control, a hold's weight row is its only input.
            expect(find.text('STOPPED'), findsNothing);
            expect(find.byIcon(Icons.play_circle_outline), findsNothing);
            expect(
              find.widgetWithText(OutlinedButton, 'Weight adjustment'),
              findsNothing,
            );
            expect(
              find.byKey(const Key('value-stepper-plus-weight')),
              effortKind == 'drill' ? findsOneWidget : findsNothing,
            );
            expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
          }
        }
      },
    );

    testWidgets(
      'free-session timed and drill running states keep dominant digits and show no status chrome across all themes',
      (tester) async {
        for (final themeValue in AppTheme.values) {
          for (final effortKind in const ['timed', 'drill']) {
            final deps = await _buildFreeSessionDeps(
              theme: themeValue,
              effortKind: effortKind,
              includeLoad: true,
            );

            await tester.pumpWidget(
              _themeWrappedApp(
                theme: themeValue,
                home: WorkoutSessionScreen(
                  // A fresh key per iteration: the screen reads its states in
                  // initState, so reusing the State would keep showing the
                  // previous effort kind.
                  key: ValueKey('$themeValue-$effortKind'),
                  workoutState: deps.workoutState,
                  routineState: deps.routineState,
                  sessionSummaryService: deps.sessionSummaryService,
                  timerAlertService: FakeTimerAlertService(),
                  settingsState: deps.settingsState,
                ),
              ),
            );

            await _openSessionDetail(tester, deps.exercise.name);
            await tester.tap(find.widgetWithText(FilledButton, 'Start'));
            await tester.pump();

            final timerValue = _metricValueText(tester);

            expect(timerValue.style?.color, OmniTheme.colors.textDominant);
            // D-3: running is conveyed by the digits ticking.
            expect(find.text('RUNNING'), findsNothing);
            expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
          }
        }
      },
    );

    testWidgets(
      'routine-backed timed and drill session details show dominant digits with no status chrome across all themes',
      (tester) async {
        for (final themeValue in AppTheme.values) {
          for (final effortKind in const ['timed', 'drill']) {
            final deps = await _buildRoutineSessionDeps(
              theme: themeValue,
              effortKind: effortKind,
            );

            await tester.pumpWidget(
              _themeWrappedApp(
                theme: themeValue,
                home: WorkoutSessionScreen(
                  // A fresh key per iteration: the screen reads its states in
                  // initState, so reusing the State would keep showing the
                  // previous effort kind.
                  key: ValueKey('$themeValue-$effortKind'),
                  workoutState: deps.workoutState,
                  routineState: deps.routineState,
                  sessionSummaryService: deps.sessionSummaryService,
                  timerAlertService: FakeTimerAlertService(),
                  settingsState: deps.settingsState,
                ),
              ),
            );

            await _openSessionDetail(tester, deps.exercise.name);

            final timerValue = _metricValueText(tester);

            expect(timerValue.style?.color, OmniTheme.colors.textDominant);
            expect(find.text('STOPPED'), findsNothing);
            expect(find.byIcon(Icons.play_circle_outline), findsNothing);
            expect(
              find.byKey(const Key('value-stepper-plus-weight')),
              effortKind == 'drill' ? findsOneWidget : findsNothing,
            );
          }
        }
      },
    );

    testWidgets(
      'routine setup shows no editor for a timed effort and one weight row for '
      'a drill across all themes',
      (tester) async {
        for (final themeValue in AppTheme.values) {
          for (final effortKind in const ['timed', 'drill']) {
            final deps = await _buildRoutineSetupDeps(
              theme: themeValue,
              effortKind: effortKind,
            );

            await tester.pumpWidget(
              _themeWrappedApp(
                theme: themeValue,
                home: RoutineSetupScreen(
                  routineState: deps.routineState,
                  workoutState: deps.workoutState,
                  templateId: deps.templateId,
                  settingsState: deps.settingsState,
                ),
              ),
            );

            await _openRoutineDetail(tester, deps.exercise.name);

            if (effortKind == 'timed') {
              // A5/O-11: an interval has no editable target in the routine
              // editor either — the body holds the bar and the sets control.
              expect(find.byType(ValueStepperRow), findsNothing);
              expect(find.byType(InlineMetricEditor), findsNothing);
            } else {
              // A4: a hold's only input is its single boxed weight row, still
              // dominant.
              expect(find.byType(ValueStepperRow), findsOneWidget);
              expect(find.byType(InlineMetricEditor), findsOneWidget);
              expect(
                _metricValueText(tester).style?.color,
                OmniTheme.colors.textDominant,
              );
            }
          }
        }
      },
    );

    testWidgets(
      'session detail hides the weight chip when extra-weight observation is absent',
      (tester) async {
        final deps = await _buildFreeSessionDeps(
          theme: AppTheme.abyssalNeon,
          effortKind: 'timed',
          includeLoad: false,
          includeExtraWeightObservation: false,
        );

        await tester.pumpWidget(
          _themeWrappedApp(
            theme: AppTheme.abyssalNeon,
            home: WorkoutSessionScreen(
              workoutState: deps.workoutState,
              routineState: deps.routineState,
              sessionSummaryService: deps.sessionSummaryService,
              timerAlertService: FakeTimerAlertService(),
              settingsState: deps.settingsState,
            ),
          ),
        );

        await _openSessionDetail(tester, deps.exercise.name);

        expect(find.text('Weight adjustment'), findsNothing);
      },
    );
  });
}
