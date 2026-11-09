// avg and max travel together (model invariant), so there is no avg-only case.
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

Future<void> _seedHeartRate(
  MockWorkoutRepository repo,
  String sessionId, {
  double? avg,
  double? max,
  String scope = SensorSummary.scopeSession,
  String? targetId,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await repo.createSensorSummary(
    SensorSummary(
      sessionId: sessionId,
      scope: scope,
      targetId: targetId ?? sessionId,
      windowStartMs: now - 3600000,
      windowEndMs: now,
      avgHeartRateBpm: avg,
      maxHeartRateBpm: max,
      createdAtMs: now,
    ),
  );
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

void main() {
  group('SessionSummaryService.getSessionHeartRate (S-9651..S-9653)', () {
    test('S-9651 avg 127.6 / max 171.2 rounds to (128, 171)', () async {
      final repo = await _freshRepo();
      await _seedHeartRate(
        repo,
        's-1',
        avg: 127.6,
        max: 171.2,
      );

      final hr = await SessionSummaryService(repo).getSessionHeartRate('s-1');
      expect(hr, isNotNull);
      expect(hr!.avgBpm, 128, reason: '127.6 rounds up: round, not toInt');
      expect(hr.maxBpm, 171, reason: '171.2 rounds down: round, not ceil');
    });

    test('S-9652 no summaries, or only a non-session scope, answers null', () async {
      final repo = await _freshRepo();
      final service = SessionSummaryService(repo);

      // No summaries at all.
      expect(await service.getSessionHeartRate('s-empty'), isNull);

      // Only an effort-scope summary: the session scope is what counts.
      await _seedHeartRate(
        repo,
        's-effort',
        avg: 150,
        max: 160,
        scope: SensorSummary.scopeEffort,
        targetId: 'eff-1',
      );
      expect(await service.getSessionHeartRate('s-effort'), isNull);
    });
  });

  group('SessionSummaryScreen heart-rate row (S-9654..S-9657)', () {
    testWidgets('S-9654 seeded: the card shows avg and max side by side', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;
      await _seedHeartRate(repo, sessionId, avg: 127.6, max: 171.2);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('omni_session_heart_rate_row')),
        findsOneWidget,
      );
      expect(find.text('AVG HEART RATE'), findsOneWidget);
      expect(find.text('128 bpm'), findsOneWidget);
      expect(find.text('MAX HEART RATE'), findsOneWidget);
      expect(find.text('171 bpm'), findsOneWidget);
    });

    testWidgets('S-9654 not seeded: the card is unchanged, no row', (
      tester,
    ) async {
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

      expect(
        find.byKey(const Key('omni_session_heart_rate_row')),
        findsNothing,
      );
      expect(find.text('AVG HEART RATE'), findsNothing);
      expect(find.text('DURATION'), findsOneWidget);
    });

    testWidgets('S-9656 a rolling session shows the heart-rate row too', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo, rolling: true);
      final sessionId = workoutState.currentSession!.id;
      await _seedHeartRate(repo, sessionId, avg: 127.6, max: 171.2);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DURATION'), findsNothing);
      expect(
        find.byKey(const Key('omni_session_heart_rate_row')),
        findsOneWidget,
      );
      expect(find.text('128 bpm'), findsOneWidget);
      expect(find.text('171 bpm'), findsOneWidget);
    });

    testWidgets('S-9657 the row sits between Duration and Effort', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;
      await _seedHeartRate(repo, sessionId, avg: 127.6, max: 171.2);

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      final durationY = tester.getTopLeft(find.text('DURATION')).dy;
      final avgY = tester.getTopLeft(find.text('AVG HEART RATE')).dy;
      final effortY = tester.getTopLeft(find.text('EFFORT')).dy;
      expect(durationY < avgY, isTrue, reason: 'Duration above Avg heart rate');
      expect(avgY < effortY, isTrue, reason: 'Avg heart rate above Effort');
    });
  });
}
