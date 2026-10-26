// filepath: test/stats_load_failure_test.dart
//
// S-2704 — a load that fails says so and offers "Try again"; it never reads as
// "no data". The three Stats-area screens that hold a `_loadFailed` flag.
//
// Plan: `docs/plans/2026-10-13-27-ui-messages-plan/`.
//
// Mock-only: a widget test body runs under `FakeAsync`, where a Hive read never
// settles, so the store under test is the in-memory `MockWorkoutRepository`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/exercise_progress_screen.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/features/stats/stats_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/repository_harness.dart';

/// A repository whose history read throws while [failing] is on, so a test can
/// break the load, check the failure screen, then heal the store for the retry.
class _FlakyRepository extends MockWorkoutRepository {
  bool failing = false;

  @override
  Future<List<TrainingSession>> getAllSessions() async {
    if (failing) throw StateError('the store cannot be read');
    return super.getAllSessions();
  }
}

/// The surface every scenario pumps at: tall enough that "Try again" sits well
/// inside the viewport and is hittable.
const Size _kViewport = Size(400, 1200);

void main() {
  group('S-2704: a failed load is not an empty state', () {
    late _FlakyRepository repo;
    late WorkoutState workoutState;
    late SettingsState settingsState;

    setUp(() async {
      repo = _FlakyRepository();
      await repo.initialize();
      // One completed session with one set effort, so the healthy load has real
      // content to show after the retry.
      await seedSession(repo, sessionId: 'sess-1', daysAgo: 1);
      await seedExercise(
        repo,
        id: 'ex-row',
        name: 'Row',
        capabilities: ['load'],
      );
      await seedSetEffort(
        repo,
        segmentId: 'seg-sess-1',
        effortId: 'eff-1',
        exerciseId: 'ex-row',
        entryCount: 2,
        hasExtraWeight: false,
      );
      workoutState = WorkoutState(repo);
      settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      repo.failing = true;
    });

    Future<void> pump(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(_kViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();
    }

    testWidgets('Stats: the failure text and Try again replace the empty state', (
      tester,
    ) async {
      await pump(
        tester,
        StatsScreen(workoutState: workoutState, settingsState: settingsState),
      );

      expect(find.text('Could not load your stats.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('No sessions yet'), findsNothing);

      repo.failing = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Could not load your stats.'), findsNothing);
      expect(find.text('ALL TIME'), findsOneWidget);
      expect(find.text('No sessions yet'), findsNothing);
    });

    testWidgets(
      'Records & Trends: the failure text and Try again replace the empty state',
      (tester) async {
        await pump(
          tester,
          RecordsAndTrendsScreen(
            workoutState: workoutState,
            settingsState: settingsState,
          ),
        );

        expect(find.text('Could not load your records.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('No sessions yet'), findsNothing);

        repo.failing = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        expect(find.text('Could not load your records.'), findsNothing);
        expect(find.text('ALL TIME'), findsOneWidget);
        expect(find.text('No sessions yet'), findsNothing);
      },
    );

    testWidgets(
      'Exercise Progress: the failure text and Try again replace the empty state',
      (tester) async {
        await pump(
          tester,
          ExerciseProgressScreen(
            workoutState: workoutState,
            settingsState: settingsState,
            exerciseId: 'ex-row',
          ),
        );

        expect(find.text('Could not load this exercise.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('No history for this exercise'), findsNothing);

        repo.failing = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        expect(find.text('Could not load this exercise.'), findsNothing);
        expect(find.text('ALL TIME'), findsOneWidget);
        expect(find.text('No history for this exercise'), findsNothing);
      },
    );
  });
}
