// Plan 228 P1 — a watch-linked workout with nothing logged is discarded too.
//
// `finishWouldSaveNothing()` on a workout the wrist runs: true when nothing is
// logged and only non-activity rows are staged (a `session_end`, an
// `effort_rating` or a `rest` row alone is not work); false once the pending
// import passes have landed a set behind the seam, or a set is logged.
// Screen side: the `Discard Workout?` dialog discards the session.
//
// Scenarios S-22803..S-22806 of
// `docs/plans/2026-11-17-228-wrist-linked-nothing-logged-discards-plan/2026-11-17-228-wrist-linked-nothing-logged-discards-plan.md`.
// Both stores must end identical.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/data/repositories/workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_rest_notification_service.dart';
import 'helpers/fake_timer_alert_service.dart';
import 'helpers/repository_harness.dart';

void main() {
  for (final factory in harnessFactories) {
    final harness = factory();

    group(
      '${harness.name} — finishWouldSaveNothing on a wrist-run workout',
      () {
        late WorkoutRepository repo;
        late WorkoutState state;

        setUp(() async => repo = await harness.open());
        tearDown(() async => await harness.close());

        Future<String> seedAndAdd(String id, String name) async {
          await seedExercise(repo, id: id, name: name, capabilities: ['load']);
          final exercise = (await repo.getExercises()).firstWhere(
            (e) => e.id == id,
          );
          return state.addExerciseToSession(exercise);
        }

        /// A staged watch row of [kind] for the current session.
        Future<void> stageRow(
          String id,
          String kind,
          Map<String, Object?> payload,
        ) async {
          await repo.stageWatchInboxEntry(
            WatchInboxEntry(
              entryId: id,
              watchSessionId: state.currentSession!.id,
              kind: kind,
              origin: WatchInboxEntry.originWatch,
              payload: payload,
              receivedAtMs: fixtureStart,
            ),
          );
        }

        test('S-22803 a wrist-run session with only non-activity rows staged '
            'is nothing done', () async {
          state = WorkoutState(repo, wristRunsSession: (_) => true);
          await state.createNewSession();
          final xId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
          await state.updateEntryValue(xId, 0, 'reps', 3);
          await state.updateEntryValue(xId, 0, 'weight', 100.0);

          await stageRow('e-end', WatchInboxEntry.kindSessionEnd, {
            'eventId': 'e-end',
            'kind': 'session_end',
          });
          await stageRow('e-rating', WatchInboxEntry.kindEffortRating, {
            'eventId': 'e-rating',
            'kind': 'effort_rating',
          });

          expect(await state.finishWouldSaveNothing(), isTrue);
        });

        for (final kind in [
          WatchInboxEntry.kindSet,
          WatchInboxEntry.kindTimed,
          WatchInboxEntry.kindRound,
          WatchInboxEntry.kindHold,
        ]) {
          test('S-22803 a staged wrist $kind row is work, one row of each '
              'activity kind on its own', () async {
            state = WorkoutState(repo, wristRunsSession: (_) => true);
            await state.createNewSession();
            await seedAndAdd('ex-squat', 'Barbell Back Squat');

            await stageRow('e-$kind', kind, {
              'eventId': 'e-$kind',
              'kind': kind,
            });

            expect(await state.finishWouldSaveNothing(), isFalse);
          });
        }

        test(
          'S-22804 a set the pending imports land behind the seam is work',
          () async {
            late final String effort;
            await seedExercise(
              repo,
              id: 'ex-squat',
              name: 'Barbell Back Squat',
              capabilities: ['load'],
            );
            final exercise = (await repo.getExercises()).firstWhere(
              (e) => e.id == 'ex-squat',
            );

            state = WorkoutState(
              repo,
              wristRunsSession: (_) => true,
              // The stub lands a logged set the way the importer does (values,
              // then a rest at position + 1), then runs the action, so the
              // decision reads the caches after the set landed.
              afterPendingWristImports: (action) async {
                await state.updateEntryValue(effort, 0, 'reps', 5);
                await state.updateEntryValue(effort, 0, 'weight', 60.0);
                await state.recordRestStart(effort, 1);
                await action();
              },
            );
            await state.createNewSession();
            effort = await state.addExerciseToSession(exercise);

            expect(await state.finishWouldSaveNothing(), isFalse);
          },
        );

        test(
          'S-22804 the seam set and nothing lands is nothing done',
          () async {
            state = WorkoutState(
              repo,
              wristRunsSession: (_) => true,
              afterPendingWristImports: (action) => action(),
            );
            await state.createNewSession();
            await seedAndAdd('ex-squat', 'Barbell Back Squat');

            expect(await state.finishWouldSaveNothing(), isTrue);
          },
        );

        test(
          'S-22805 a wrist-run session with a logged set is not nothing done',
          () async {
            state = WorkoutState(repo, wristRunsSession: (_) => true);
            await state.createNewSession();
            final xId = await seedAndAdd('ex-squat', 'Barbell Back Squat');
            await state.updateEntryValue(xId, 0, 'reps', 5);
            await state.updateEntryValue(xId, 0, 'weight', 60.0);
            await state.recordRestStart(xId, 1);

            expect(await state.finishWouldSaveNothing(), isFalse);
          },
        );
      },
    );
  }

  testWidgets(
    'S-22806 Finish on a wrist-run workout with nothing logged asks to '
    'discard, then discards and pops',
    (WidgetTester tester) async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final workoutState = WorkoutState(
        repository,
        wristRunsSession: (_) => true,
      );
      final routineState = RoutineState(repository);
      final sessionSummaryService = SessionSummaryService(repository);

      await workoutState.createNewSession();

      final exercises = await repository.getExercises();
      final x = exercises.where((e) => e.capabilities.contains('load')).first;

      final xEffortId = await workoutState.addExerciseToSession(x);

      // The user typed values but never tapped Log Set: no rest marks the set.
      await workoutState.updateEntryValue(xEffortId, 0, 'reps', 3);
      await workoutState.updateEntryValue(xEffortId, 0, 'weight', 100.0);

      final restService = FakeRestNotificationService();

      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutSessionScreen(
            workoutState: workoutState,
            routineState: routineState,
            sessionSummaryService: sessionSummaryService,
            timerAlertService: FakeTimerAlertService(),
            settingsState: SettingsState(repository, fakePreferencesService()),
            restNotificationService: restService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Finish Workout'));
      await tester.pumpAndSettle();

      expect(find.text('Discard Workout?'), findsOneWidget);
      expect(
        find.byKey(const Key('session-finish-nothing-confirm')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('session-finish-nothing-confirm')));
      await tester.pumpAndSettle();

      expect(workoutState.currentSession, isNull);
      expect(await repository.getAllSessions(), isEmpty);
      expect(find.byType(WorkoutSessionScreen), findsNothing);
    },
  );
}
