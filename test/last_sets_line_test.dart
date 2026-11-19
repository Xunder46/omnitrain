// Plan 249 P4 — widget tests for the "last time" line (S-24911..S-24916).
//
// S-24911..S-24913 are plain `test()` unit checks of the pure
// `LastSetsLine.describe`; S-24914..S-24916 pump the logger (Mock repository
// only, every write awaited before `pumpWidget`, as
// `test/exercise_set_last_value_test.dart` does).
//
// Plan: `docs/plans/2026-11-19-249-last-time-line-plan.md`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/last_performance_service.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/session/last_sets_line.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

// ─── Fixture times ──────────────────────────────────────────────────────────

final _nov12 = DateTime(2026, 11, 12, 12).millisecondsSinceEpoch;
final _nov12End = DateTime(2026, 11, 12, 13).millisecondsSinceEpoch;

// ─── Seeding (copied from test/last_performance_service_test.dart) ──────────

/// A session with one segment and one `set` effort for [exerciseId], holding
/// [sets] as reps/weight rows the way the logger numbers them (entry 0 first).
/// `endedAtMs` null leaves the session running. The effort id
/// `eff-<segmentId>-<exerciseId>` keeps a second block's effort apart.
Future<void> seedBench(
  WorkoutRepository repo, {
  required String sessionId,
  required int startedAtMs,
  int? endedAtMs,
  required List<(int reps, double kg, {bool skipped})> sets,
  String exerciseId = 'ex-bench',
  String effortKind = 'set',
  int segmentOrder = 0,
  String? segmentId,
}) async {
  await repo.createSession(
    TrainingSession(
      id: sessionId,
      ownerUserId: 'user-1',
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final segId = segmentId ?? 'seg-$sessionId';
  await repo.createSegment(
    SessionSegment(
      id: segId,
      sessionId: sessionId,
      orderIndex: segmentOrder,
      segmentType: 'workout',
      name: 'Main Workout',
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  final effortId = 'eff-$segId-$exerciseId';
  await repo.createEffort(
    SegmentEffort(
      id: effortId,
      segmentId: segId,
      orderIndex: 0,
      effortKind: effortKind,
      exerciseId: exerciseId,
      createdAtMs: startedAtMs,
      updatedAtMs: startedAtMs,
    ),
  );
  for (var n = 0; n < sets.length; n++) {
    final at = startedAtMs + 1000 + n;
    await repo.createObservation(
      repsRow(effortId, n, sets[n].$1, atMs: at, skipped: sets[n].skipped),
    );
    await repo.createObservation(
      weightRow(effortId, n, sets[n].$2, atMs: at + 1),
    );
  }
}

// ─── Screen deps ────────────────────────────────────────────────────────────

/// The exercise the screen deps pick: the first one with sets, load and reps
/// capabilities (same `firstWhere` as `test/exercise_set_last_value_test.dart`).
Future<Exercise> _pickExercise(MockWorkoutRepository repo) async {
  final exercises = await repo.getExercises();
  return exercises.firstWhere(
    (e) =>
        e.capabilities.contains('sets') &&
        e.capabilities.contains('load') &&
        e.capabilities.contains('reps'),
    orElse: () => exercises.first,
  );
}

Future<
  ({
    WorkoutState workoutState,
    RoutineState routineState,
    SessionSummaryService sessionSummaryService,
    SettingsState settingsState,
    String exerciseName,
    String exerciseId,
  })
>
_buildSessionDeps({
  required MockWorkoutRepository repo,
  required String effortKind,
}) async {
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, FakePreferencesService());
  await settingsState.initialize();

  await workoutState.createNewSession(modality: 'resistance_lifting');
  final exercise = await _pickExercise(repo);
  await workoutState.addExerciseToSession(
    exercise,
    effortKindOverride: effortKind,
  );
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exerciseName: exercise.name,
    exerciseId: exercise.id,
  );
}

/// One finished session (Nov 12, one set (5, 90)) for [exerciseId].
Future<void> _seedHistory(MockWorkoutRepository repo, String exerciseId) async {
  await seedBench(
    repo,
    sessionId: 's-last',
    startedAtMs: _nov12,
    endedAtMs: _nov12End,
    sets: [(5, 90.0, skipped: false)],
    exerciseId: exerciseId,
  );
}

Future<void> _openSessionDetail(
  WidgetTester tester,
  String exerciseName,
) async {
  await tester.pumpAndSettle();
  final labelFinder = find.text(exerciseName).first;
  await tester.ensureVisible(labelFinder);
  final rowInkWell = tester.widget<InkWell>(
    find.ancestor(of: labelFinder, matching: find.byType(InkWell)).first,
  );
  expect(rowInkWell.onTap, isNotNull);
  rowInkWell.onTap!.call();
  await tester.pumpAndSettle();
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('LastSetsLine.describe (unit, no pump)', () {
    test('S-24911 three sets, kg, renders the date and every set', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final settings = SettingsState(repo, FakePreferencesService());
      await settings.initialize();

      final line = LastSetsLine.describe(
        LastSets(
          startedAtMs: _nov12,
          sets: [
            const LastSet(reps: 8, weightKg: 80),
            const LastSet(reps: 8, weightKg: 80),
            const LastSet(reps: 6, weightKg: 82.5),
          ],
        ),
        settings,
      );

      expect(line, 'Last (Nov 12): 8×80 · 8×80 · 6×82.5 kg');
    });

    test('S-24912 the lbs setting converts every load', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final settings = SettingsState(repo, FakePreferencesService());
      await settings.initialize();
      await settings.setPreferredWeightUnit('lbs');

      final line = LastSetsLine.describe(
        LastSets(
          startedAtMs: _nov12,
          sets: [
            const LastSet(reps: 8, weightKg: 80),
            const LastSet(reps: 8, weightKg: 80),
            const LastSet(reps: 6, weightKg: 82.5),
          ],
        ),
        settings,
      );

      // 80 kg = 176.4 lb, 82.5 kg = 181.9 lb (factor 2.20462).
      expect(line, 'Last (Nov 12): 8×176.4 · 8×176.4 · 6×181.9 lbs');
    });

    test('S-24913 no loads, mixed loads and more than six sets', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final settings = SettingsState(repo, FakePreferencesService());
      await settings.initialize();

      final noLoads = LastSetsLine.describe(
        LastSets(
          startedAtMs: _nov12,
          sets: const [
            LastSet(reps: 12, weightKg: 0),
            LastSet(reps: 10, weightKg: 0),
            LastSet(reps: 9, weightKg: 0),
          ],
        ),
        settings,
      );
      expect(noLoads, 'Last (Nov 12): 12 · 10 · 9 reps');

      final mixed = LastSetsLine.describe(
        LastSets(
          startedAtMs: _nov12,
          sets: const [
            LastSet(reps: 8, weightKg: 80),
            LastSet(reps: 8, weightKg: 0),
            LastSet(reps: 6, weightKg: 82.5),
          ],
        ),
        settings,
      );
      expect(mixed, 'Last (Nov 12): 8×80 · 8 · 6×82.5 kg');

      final eightSets = LastSetsLine.describe(
        LastSets(
          startedAtMs: _nov12,
          sets: List.filled(8, const LastSet(reps: 10, weightKg: 50)),
        ),
        settings,
      );
      expect(
        eightSets,
        'Last (Nov 12): 10×50 · 10×50 · 10×50 · 10×50 · 10×50 · 10×50 kg '
        '(+2 more)',
      );
    });
  });

  group('WorkoutSessionScreen — last time line (pumped, Mock only)', () {
    testWidgets('S-24914 the logger shows the line for a set effort with '
        'history', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final exercise = await _pickExercise(repo);
      await _seedHistory(repo, exercise.id);
      final deps = await _buildSessionDeps(repo: repo, effortKind: 'set');

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: deps.settingsState,
          ),
        ),
      );
      await _openSessionDetail(tester, deps.exerciseName);

      final lineFinder = find.byKey(const Key('last_sets_line'));
      expect(lineFinder, findsOneWidget);
      expect(tester.widget<Text>(lineFinder).data, 'Last (Nov 12): 5×90 kg');
    });

    testWidgets('S-24915a no seeded history: no line', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final deps = await _buildSessionDeps(repo: repo, effortKind: 'set');

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: deps.settingsState,
          ),
        ),
      );
      await _openSessionDetail(tester, deps.exerciseName);

      expect(find.byKey(const Key('last_sets_line')), findsNothing);
    });

    testWidgets('S-24915b a timed (hold) effort shows no line even with '
        'history', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final exercise = await _pickExercise(repo);
      await _seedHistory(repo, exercise.id);
      final deps = await _buildSessionDeps(repo: repo, effortKind: 'timed');

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: deps.workoutState,
            routineState: deps.routineState,
            sessionSummaryService: deps.sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: deps.settingsState,
          ),
        ),
      );
      await _openSessionDetail(tester, deps.exerciseName);

      expect(find.byKey(const Key('last_sets_line')), findsNothing);
    });

    testWidgets('S-24916 the line fits and sits above the reps controls at '
        '360x640, text scale 1.3', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final exercise = await _pickExercise(repo);
      await _seedHistory(repo, exercise.id);
      final deps = await _buildSessionDeps(repo: repo, effortKind: 'set');

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(1.3),
            ),
            child: WorkoutSessionScreen(
              workoutState: deps.workoutState,
              routineState: deps.routineState,
              sessionSummaryService: deps.sessionSummaryService,
              timerAlertService: FakeTimerAlertService(),
              settingsState: deps.settingsState,
            ),
          ),
        ),
      );
      await _openSessionDetail(tester, deps.exerciseName);

      expect(tester.takeException(), isNull);

      final lineFinder = find.byKey(const Key('last_sets_line'));
      expect(lineFinder, findsOneWidget);

      final lineRect = tester.getRect(lineFinder);
      expect(lineRect.left, greaterThanOrEqualTo(0));
      expect(lineRect.right, lessThanOrEqualTo(360));

      expect(
        tester.getCenter(lineFinder).dy,
        lessThan(tester.getCenter(find.byTooltip('Add set')).dy),
      );
    });
  });
}
