// Plan 221 — Stats leaves out an exercise that has no work in it.
//
// An exercise added to a workout and never done has no readable value on any
// day: `StatsProgressService.computeExerciseMetrics` skips it, so it shows in
// no Instruments row and no Records & Trends entry.
//
// Scenarios S-22101..S-22105. Plain `test()` for the service ones; S-22105 is
// a Mock-only `testWidgets` (a Hive read never settles under FakeAsync).
// The Mock repository is seeded before the first pump.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/stats_progress_service.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/stats/records_and_trends_screen.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';
import 'package:omnitrain/widgets/common/omni_empty_state.dart';

import 'helpers/fake_preferences_service.dart';

const Size _kTallViewport = Size(400, 2400);

Future<(MockWorkoutRepository, WorkoutState)> _seedState({
  String? modality,
}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final state = WorkoutState(repo);
  await state.createNewSession(modality: modality);
  return (repo, state);
}

void main() {
  group('S-22101 a run added and never started', () {
    test('produces no summary and no instrument row', () async {
      final (repo, state) = await _seedState(modality: 'cardio_endurance');
      final run = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('time'),
      );
      final effortId = await state.addExerciseToSession(run);
      expect(effortId, isNotEmpty);
      await state.endSession();

      final service = StatsProgressService(repo);
      expect(await service.computeExerciseMetrics(), isEmpty);

      final sections = await service.computeInstrumentSections(
        window: StatsProgressService.statsWindow(),
      );
      expect(
        sections.where((section) => section.rows.isNotEmpty),
        isEmpty,
      );
    });
  });

  group('S-22102 a lift added and nothing logged', () {
    test('produces no summary and no instrument row', () async {
      final (repo, state) = await _seedState();
      final lift = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('load'),
      );
      final effortId = await state.addExerciseToSession(lift);
      expect(effortId, isNotEmpty);
      await state.endSession(writeToHealth: false);

      final service = StatsProgressService(repo);
      expect(await service.computeExerciseMetrics(), isEmpty);

      final sections = await service.computeInstrumentSections(
        window: StatsProgressService.statsWindow(),
      );
      expect(
        sections.where((section) => section.rows.isNotEmpty),
        isEmpty,
      );
    });
  });

  group('S-22103 a logged lift beside an untouched one', () {
    test('produces exactly one summary, the logged lift\'s', () async {
      final (repo, state) = await _seedState();
      final lifts = (await repo.getExercises())
          .where((e) => e.capabilities.contains('load'))
          .toList();
      final effortA = await state.addExerciseToSession(lifts[0]);
      final effortB = await state.addExerciseToSession(lifts[1]);
      expect(effortA, isNotEmpty);
      expect(effortB, isNotEmpty);
      expect(effortA, isNot(effortB));

      await state.updateEntryValue(effortA, 0, 'reps', 3);
      await state.updateEntryValue(effortA, 0, 'weight', 100.0);
      await state.recordRestStart(effortA, 1);
      await state.endSession(writeToHealth: false);

      final service = StatsProgressService(repo);
      final summaries = await service.computeExerciseMetrics();
      expect(summaries, hasLength(1));
      expect(summaries.single.exerciseId, lifts[0].id);
    });
  });

  group('S-22104 a timed exercise started and finished', () {
    test('produces a summary with at least one point', () async {
      final (repo, state) = await _seedState(modality: 'cardio_endurance');
      final run = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('time'),
      );
      final effortId = await state.addExerciseToSession(run);
      expect(effortId, isNotEmpty);
      await state.startTimedEntry(effortId, 0);
      // A short real elapsed time, so the finished entry holds a readable
      // duration (a plain test runs on the real clock).
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await state.finishTimedEntry(effortId, 0);
      await state.endSession();

      final service = StatsProgressService(repo);
      final summaries = await service.computeExerciseMetrics();
      expect(summaries, hasLength(1));
      expect(summaries.single.exerciseId, run.id);
      expect(summaries.single.points, isNotEmpty);
    });
  });

  group('S-22105 Records & Trends over a never-started run', () {
    testWidgets('shows the empty state and no exercise row', (tester) async {
      final (repo, state) = await _seedState(modality: 'cardio_endurance');
      final run = (await repo.getExercises()).firstWhere(
        (e) => e.capabilities.contains('time'),
      );
      final effortId = await state.addExerciseToSession(run);
      expect(effortId, isNotEmpty);
      await state.endSession();

      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();

      await tester.binding.setSurfaceSize(_kTallViewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: RecordsAndTrendsScreen(
            workoutState: state,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('records_entry_${run.id}')), findsNothing);
      expect(find.text('No sessions yet'), findsOneWidget);
      expect(
        find.text('Complete your first session to see stats here.'),
        findsOneWidget,
      );
      expect(find.byType(OmniEmptyState), findsOneWidget);
    });
  });
}
