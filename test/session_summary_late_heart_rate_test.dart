// Late heart-rate notification tests (S-10204..S-10206).
import 'dart:async';

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

class _CountingRepo extends MockWorkoutRepository {
  int summaryReadCount = 0;

  /// When set, the next summary read waits for it, so a test can dispose the
  /// screen while a read is still in flight.
  Completer<void>? gate;

  @override
  Future<List<SensorSummary>> getSensorSummariesForSession(
    String sessionId,
  ) async {
    summaryReadCount++;
    final waiting = gate;
    if (waiting != null) await waiting.future;
    return super.getSensorSummariesForSession(sessionId);
  }
}

Future<_CountingRepo> _freshRepo() async {
  final repo = _CountingRepo();
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

Future<WorkoutState> _seedSession(_CountingRepo repo) async {
  final workoutState = WorkoutState(repo);
  await workoutState.createNewSession();
  return workoutState;
}

Future<void> _seedHeartRate(
  _CountingRepo repo,
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
  required _CountingRepo repo,
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
  group('SessionSummaryScreen late heart-rate notification (S-10204..S-10206)', () {
    testWidgets('S-10204 notification after pump: the row appears', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('omni_session_heart_rate_row')),
        findsNothing,
      );

      await _seedHeartRate(repo, sessionId, avg: 127.6, max: 171.2);
      workoutState.noteWristSummary(sessionId);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('omni_session_heart_rate_row')),
        findsOneWidget,
      );
      expect(find.text('AVG HEART RATE'), findsOneWidget);
      expect(find.text('128 bpm'), findsOneWidget);
      expect(find.text('MAX HEART RATE'), findsOneWidget);
      expect(find.text('171 bpm'), findsOneWidget);
    });

    testWidgets('S-10205 foreign notification: no row, no extra read', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pump();
      await tester.pump();

      await _seedHeartRate(repo, sessionId, avg: 127.6, max: 171.2);
      final countAfterFirstPump = repo.summaryReadCount;

      workoutState.noteWristSummary('some-other-session');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('omni_session_heart_rate_row')),
        findsNothing,
      );
      expect(repo.summaryReadCount, countAfterFirstPump);
    });

    testWidgets('S-10206 notification after dispose: no exception', (
      tester,
    ) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      workoutState.noteWristSummary(sessionId);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('S-10206b a read still in flight when the screen goes away '
        'does not touch the dead screen', (tester) async {
      _useTallSurface(tester);
      final repo = await _freshRepo();
      final workoutState = await _seedSession(repo);
      final sessionId = workoutState.currentSession!.id;

      await tester.pumpWidget(
        await _buildSessionSummaryScreen(
          workoutState: workoutState,
          repo: repo,
        ),
      );
      await tester.pump();
      await tester.pump();

      await _seedHeartRate(repo, sessionId, avg: 127.6, max: 171.2);
      final gate = Completer<void>();
      repo.gate = gate;
      workoutState.noteWristSummary(sessionId);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
