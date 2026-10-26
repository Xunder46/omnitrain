import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart' show buildTheme;
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/effort_rating_sheet.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

/// The app's real ThemeData for the active theme, so `colorScheme.onPrimary`
/// (which the rating tiles read) is the production value, not Material's
/// default white.
ThemeData _appTheme() {
  final theme = OmniTheme.activeTheme;
  final colors = OmniTheme.colorsForTheme(theme);
  return buildTheme(
    theme: theme,
    brightness: Brightness.dark,
    secondary: colors.secondary,
    background: colors.backgroundBottom,
    surface: colors.surface,
    textPrimary: colors.textDominant,
    textSecondary: colors.textSecondary,
    divider: colors.divider,
    onPrimary: getOnPrimaryForTheme(theme),
    onSecondary: getOnSecondaryForTheme(theme),
  );
}

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Builds the Summary over the live session, with the automatic effort
/// question enabled.
Future<Widget> _buildSummary({
  required WorkoutState workoutState,
  required MockWorkoutRepository repo,
}) async {
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());

  return MaterialApp(
    theme: _appTheme(),
    home: SessionSummaryScreen(
      workoutState: workoutState,
      routineState: routineState,
      sessionSummaryService: sessionSummaryService,
      settingsState: settingsState,
      timerAlertService: FakeTimerAlertService(),
    ),
  );
}

/// [text] inside the open rating sheet (the Summary behind it also renders
/// digits, e.g. in the calendar grid).
Finder _inSheet(String text) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(text),
);

Future<void> _tapTile(WidgetTester tester, int n) async {
  final tile = _inSheet('$n');
  await tester.ensureVisible(tile);
  await tester.tap(tile.first);
  await tester.pumpAndSettle();
}

void main() {
  group('Summary automatic effort question, first answer wins (plan 42a)', () {
    testWidgets(
      'S-4303 the watch rating closes the automatic question and stays stored',
      (WidgetTester tester) async {
        _useTallSurface(tester);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.endSession();
        final sessionId = workoutState.currentSession!.id;

        await tester.pumpWidget(
          await _buildSummary(workoutState: workoutState, repo: repo),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(EffortRatingSheet),
          findsOneWidget,
          reason: 'the automatic question opens for an unrated fresh session',
        );

        // The watch answered first: the importer's rating reaches the live
        // session (D-1) with no phone tap.
        await workoutState.adoptSessionFeeling(sessionId, 4);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byType(EffortRatingSheet),
          findsNothing,
          reason: 'a rating from outside closes the automatic question (D-3)',
        );
        expect(
          find.text('4 / 5'),
          findsOneWidget,
          reason: 'the EFFORT row shows the watch answer',
        );
        expect(find.text('Change rating'), findsOneWidget);
        expect(
          find.byType(SessionSummaryScreen),
          findsOneWidget,
          reason: 'closing the sheet leaves the Summary on screen',
        );

        final stored = await repo.getSession(sessionId);
        expect(
          stored?.sessionFeeling,
          isNull,
          reason: 'adopt writes nothing: the importer already wrote the row',
        );
      },
    );

    testWidgets(
      "S-4303 the user's own answer closes the sheet once",
      (WidgetTester tester) async {
        _useTallSurface(tester);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.endSession();
        final sessionId = workoutState.currentSession!.id;

        await tester.pumpWidget(
          await _buildSummary(workoutState: workoutState, repo: repo),
        );
        await tester.pumpAndSettle();

        expect(find.byType(EffortRatingSheet), findsOneWidget);

        await _tapTile(tester, 4);

        expect(
          find.byType(EffortRatingSheet),
          findsNothing,
          reason: 'the answered question closes',
        );
        expect(
          find.byType(SessionSummaryScreen),
          findsOneWidget,
          reason: 'the user answer must not pop the Summary behind it',
        );
        expect(find.text('4 / 5'), findsOneWidget);
        expect(find.text('Change rating'), findsOneWidget);

        final stored = await repo.getSession(sessionId);
        expect(stored?.sessionFeeling, 4);
      },
    );

    testWidgets(
      "S-4303 a late tap on the open question cannot overwrite the watch's answer",
      (WidgetTester tester) async {
        _useTallSurface(tester);

        final repo = await _freshRepo();
        final workoutState = WorkoutState(repo);
        await workoutState.createNewSession();
        await workoutState.endSession();
        final sessionId = workoutState.currentSession!.id;

        await tester.pumpWidget(
          await _buildSummary(workoutState: workoutState, repo: repo),
        );
        await tester.pumpAndSettle();

        expect(find.byType(EffortRatingSheet), findsOneWidget);

        // The watch's answer is already in the row, written behind the state's
        // back: no notification reaches the sheet, so it stays open.
        await repo.updateSessionFeeling(sessionId, 4);
        expect(
          find.byType(EffortRatingSheet),
          findsOneWidget,
          reason: 'nothing told the open sheet about the stored answer',
        );

        await _tapTile(tester, 2);

        expect(
          find.byType(EffortRatingSheet),
          findsNothing,
          reason: 'the answered question closes',
        );
        expect(
          find.byType(SessionSummaryScreen),
          findsOneWidget,
          reason: 'the late answer must not pop the Summary behind it',
        );

        final stored = await repo.getSession(sessionId);
        expect(
          stored?.sessionFeeling,
          4,
          reason: 'first answer wins: the automatic tap writes nothing (D-2)',
        );
      },
    );
  });
}
