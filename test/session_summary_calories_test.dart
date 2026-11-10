import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/app.dart' show buildTheme;
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';

import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/session_summary_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

// Harness helpers copied from test/session_summary_heart_rate_test.dart
// (Mock repository only: never a Hive write inside testWidgets).
Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

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

Future<WorkoutState> _seedSession(
  MockWorkoutRepository repo, {
  bool rolling = false,
}) async {
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession(isRolling: rolling);
  return workoutState;
}

Future<Widget> _buildSessionSummaryScreen({
  required WorkoutState workoutState,
  required MockWorkoutRepository repo,
}) async {
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final prefs = fakePreferencesService();
  final settingsState = SettingsState(repo, prefs);
  await settingsState.setShowFeelingSurvey(false);

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

// The CALORIES pill of S-13412: an estimated row stores the weight used.
Future<void> _seedEstimatedEnergy(
  MockWorkoutRepository repo,
  String sessionId, {
  double kcal = 31.835555555555555,
}) async {
  await repo.putSessionEnergy(
    SessionEnergy(
      sessionId: sessionId,
      activeKcal: kcal,
      source: SessionEnergy.sourceEstimated,
      bodyWeightKg: 80.0,
      updatedAtMs: 1,
    ),
  );
}

// _pillValue copied from test/session_summary_effort_row_test.dart. The
// CALORIES pill has no caption, so the only non-value text is the label.
Text _pillValue(WidgetTester tester, String label) {
  final pill = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final values = tester
      .widgetList<Text>(find.descendant(of: pill, matching: find.byType(Text)))
      .where((t) => t.data != label)
      .toList();
  expect(values, hasLength(1), reason: '$label pill must have one value');
  return values.single;
}

const _penKey = Key('omni_session_effort_rating_button');
const _caloriesPillKey = Key('omni_session_calories_pill');
const _cardKey = Key('omni_session_info_card');
const _sheetTitle = 'How hard was this session?';

IntensityRampPalette get _ramp => OmniTheme.colors.intensityRamp;

// Rating-sheet helpers copied from test/session_summary_effort_row_test.dart.
Finder _inSheet(String text) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(text),
);

BoxDecoration _tileDecoration(WidgetTester tester, int n) {
  final tile = tester.widget<AnimatedContainer>(
    find.ancestor(of: _inSheet('$n'), matching: find.byType(AnimatedContainer)),
  );
  return tile.decoration! as BoxDecoration;
}

void main() {
  group('S-13402/S-13411 a rated session with an estimated energy row', () {
    testWidgets('the pen is icon-only and the Calories pill sits to its right', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;
      await workoutState.updateSessionFeeling(sessionId, 4);
      await _seedEstimatedEnergy(repo, sessionId);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('~32 kcal'), findsOneWidget);
      expect(find.text('CALORIES'), findsOneWidget);

      final pen = find.byKey(_penKey);
      expect(pen, findsOneWidget);
      expect(find.byTooltip('Change rating'), findsOneWidget);
      expect(
        find.descendant(of: pen, matching: find.byIcon(Icons.edit_outlined)),
        findsOneWidget,
      );
      expect(find.text('Change rating'), findsNothing,
          reason: 'the pen must not be a labelled button');

      // The pen is an outlined square with a 48 dp tap target.
      expect(tester.widget(pen), isA<OutlinedButton>());
      expect(tester.getSize(pen), const Size.square(48));
      // And it hugs the rating line: it sits on the same line as the "4 / 5"
      // value, a short step to its right, not pushed to the column's far edge.
      final value = find.text('4 / 5');
      final gap = tester.getRect(pen).left - tester.getRect(value).right;
      expect(gap, inInclusiveRange(0, 16),
          reason: 'the pen starts right after the value (gap $gap)');
      expect(
        (tester.getCenter(pen).dy - tester.getCenter(value).dy).abs(),
        lessThan(2),
        reason: 'the pen is centred on the value line',
      );

      // Layout: the Calories pill's left edge sits right of the pen's right
      // edge, and the pen stays in the card's left half.
      final pillLeft = tester.getTopLeft(find.byKey(_caloriesPillKey)).dx;
      final penRight = tester.getRect(pen).right;
      final cardCenter = tester.getCenter(find.byKey(_cardKey)).dx;
      expect(pillLeft > penRight, isTrue,
          reason: 'Calories pill opens right of the pen ($pillLeft <= $penRight)');
      expect(penRight < cardCenter, isTrue,
          reason: 'the pen must stay in the left half ($penRight >= $cardCenter)');

      // S-3212: tapping it opens the sheet on the stored rating.
      await tester.tap(pen);
      await tester.pumpAndSettle();
      expect(find.text(_sheetTitle), findsOneWidget);
      expect(
        _tileDecoration(tester, 4).color,
        _ramp.step4,
        reason: 'the stored rating is still pre-selected',
      );
    });
  });

  group('S-13411 an unrated session', () {
    testWidgets('the pen reads Add rating with a plus icon', (tester) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;
      await _seedEstimatedEnergy(repo, sessionId);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Add rating'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_penKey),
          matching: find.byIcon(Icons.add),
        ),
        findsOneWidget,
      );
      // The ratings state does not touch the Calories pill.
      expect(find.text('~32 kcal'), findsOneWidget);
    });
  });

  group('D-13412 a figure that rounds to zero', () {
    testWidgets('reads ~0 kcal, never an em dash', (tester) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;
      await _seedEstimatedEnergy(repo, sessionId, kcal: 0.28888888888888886);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(_pillValue(tester, 'CALORIES').data, '~0 kcal');
    });
  });

  group('S-13407 a measured energy row', () {
    testWidgets('reads plain kilocalories, no estimate mark', (tester) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;
      await repo.putSessionEnergy(
        SessionEnergy(
          sessionId: sessionId,
          activeKcal: 250.4,
          source: SessionEnergy.sourceMeasured,
          updatedAtMs: 2,
        ),
      );

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('250 kcal'), findsOneWidget);
      expect(find.textContaining('~'), findsNothing,
          reason: 'a measured row is not an estimate');
      expect(_pillValue(tester, 'CALORIES').data, '250 kcal');
    });
  });

  group('S-13412 every session shows the Calories pill', () {
    testWidgets('a rolling session shows the pill and no Duration/Rest row', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo, rolling: true);
      final sessionId = workoutState.currentSession!.id;
      await _seedEstimatedEnergy(repo, sessionId);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsNothing);
      expect(find.text('REST TIME'), findsNothing);
      expect(find.text('CALORIES'), findsOneWidget);
      expect(_pillValue(tester, 'CALORIES').data, '~32 kcal');
    });

    testWidgets('a session with no energy row reads an em dash', (tester) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_caloriesPillKey), findsOneWidget);
      expect(_pillValue(tester, 'CALORIES').data, '—');
    });

    testWidgets('a late measured row lands through noteWristSummary', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;
      await _seedEstimatedEnergy(repo, sessionId);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('~32 kcal'), findsOneWidget);

      await repo.putSessionEnergy(
        SessionEnergy(
          sessionId: sessionId,
          activeKcal: 250.4,
          source: SessionEnergy.sourceMeasured,
          updatedAtMs: 2,
        ),
      );
      workoutState.noteWristSummary(sessionId);
      await tester.pumpAndSettle();

      expect(find.text('250 kcal'), findsOneWidget);
      expect(find.textContaining('~'), findsNothing,
          reason: 'the pill must not show the stale estimate mark');
    });
  });
}
