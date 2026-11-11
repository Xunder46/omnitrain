// Scenario mapping (plan 139):
//   S-13908 header back from an exercise in the middle of a long live session
//           returns with that exercise in view, the list is back to its default
//           cache extent, and back follows the arrows
//   S-13909 the session editor's system back (PopScope) lands the same way
//   S-13910 the rolling session's list lands the same way
//
// Mock repository only, no timers and no real delays (FakeAsync).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/services/session_summary_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/session/workout_session_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

import 'helpers/fake_preferences_service.dart';
import 'helpers/fake_timer_alert_service.dart';

const Size _surface = Size(400, 700);

typedef _Deps = ({
  WorkoutState workoutState,
  RoutineState routineState,
  SessionSummaryService sessionSummaryService,
  SettingsState settingsState,
  List<Exercise> exercises,
});

/// A session with 24 distinct reps-capable exercises (one effort each).
/// [rolling] puts them in six blocks of four of a rolling session.
Future<_Deps> _manyExercises({bool rolling = false}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  final sessionSummaryService = SessionSummaryService(repo);
  final settingsState = SettingsState(repo, fakePreferencesService());
  await settingsState.initialize();
  await workoutState.createNewSession(
    modality: rolling ? null : 'resistance_lifting',
    isRolling: rolling,
  );

  final names = <String>{};
  final picked = <Exercise>[];
  for (final exercise in await repo.getExercises()) {
    if (!exercise.capabilities.contains('reps')) continue;
    if (names.add(exercise.name)) picked.add(exercise);
    if (picked.length == 24) break;
  }
  expect(picked.length, 24, reason: 'the library has 24 distinct names');

  // Six blocks of four: each block card is one child of the lazy rolling list,
  // so the fourth block lies beyond the default build range (plan 139 D-2).
  final blockIds = <String>[
    if (rolling)
      for (var b = 0; b < 6; b++) await workoutState.addSessionBlock(),
  ];
  for (var i = 0; i < picked.length; i++) {
    final effortId = await workoutState.addExerciseToSession(
      picked[i],
      chosenMetric: 'reps',
    );
    if (rolling) {
      await workoutState.assignEffortToBlock(effortId, blockIds[i ~/ 4]);
    }
  }
  return (
    workoutState: workoutState,
    routineState: routineState,
    sessionSummaryService: sessionSummaryService,
    settingsState: settingsState,
    exercises: picked,
  );
}

Future<void> _pumpSession(
  WidgetTester tester,
  _Deps deps, {
  bool editMode = false,
}) async {
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: WorkoutSessionScreen(
        workoutState: deps.workoutState,
        routineState: deps.routineState,
        sessionSummaryService: deps.sessionSummaryService,
        settingsState: deps.settingsState,
        timerAlertService: FakeTimerAlertService(),
        editMode: editMode,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [exercise]'s tile into view and taps it (opens its detail view).
Future<void> _openExercise(WidgetTester tester, Exercise exercise) async {
  await tester.scrollUntilVisible(
    find.text(exercise.name),
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(exercise.name).first);
  await tester.pumpAndSettle();
}

Rect _listRect(WidgetTester tester) => tester.getRect(find.byType(ListView));

Rect _rowRect(WidgetTester tester, Exercise exercise) => tester.getRect(
  find
      .ancestor(
        of: find.text(exercise.name).first,
        matching: find.byType(ListTile),
      )
      .first,
);

/// The row is fully inside the list and its top is in the upper third.
void _expectLanded(WidgetTester tester, Exercise exercise) {
  final list = _listRect(tester);
  final row = _rowRect(tester, exercise);
  expect(row.top, greaterThanOrEqualTo(list.top), reason: 'not above the list');
  expect(row.bottom, lessThanOrEqualTo(list.bottom), reason: 'not below it');
  final fraction = (row.top - list.top) / list.height;
  expect(
    fraction,
    inInclusiveRange(0.15, 0.40),
    reason: '${exercise.name} should land about a third down the list',
  );
}

void main() {
  group('S-13908 header back returns to the exercise left', () {
    testWidgets('an exercise in the middle of a long session is in view', (
      tester,
    ) async {
      final deps = await _manyExercises();
      await _pumpSession(tester, deps);
      expect(find.byType(ListView), findsOneWidget);

      await _openExercise(tester, deps.exercises[11]);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();

      _expectLanded(tester, deps.exercises[11]);
      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(
        listView.controller!.offset,
        lessThan(listView.controller!.position.maxScrollExtent - 100),
        reason: 'it did not jump to the bottom',
      );
      expect(listView.cacheExtent, isNull, reason: 'steady state (S-13907)');
    });

    testWidgets(
      'the next frame after the landing drops the raised cache extent',
      (tester) async {
        final deps = await _manyExercises();
        await _pumpSession(tester, deps);
        await _openExercise(tester, deps.exercises[11]);

        await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
        // Frame 1 builds the list with every row; its post-frame callback
        // reveals the row and asks for a rebuild. Frame 2 is that rebuild. No
        // time passes, so no timer can rebuild the screen for us.
        await tester.pump();
        await tester.pump();

        expect(
          tester.widget<ListView>(find.byType(ListView)).cacheExtent,
          isNull,
        );
      },
    );

    testWidgets('after walking with Next, back lands on the exercise reached', (
      tester,
    ) async {
      final deps = await _manyExercises();
      await _pumpSession(tester, deps);

      await _openExercise(tester, deps.exercises[9]);
      expect(find.textContaining('Exercise 10 / 24'), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        if (find.textContaining('Exercise 13 / 24').evaluate().isNotEmpty) {
          break;
        }
        await tester.tap(find.byTooltip('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Exercise 13 / 24'), findsOneWidget);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();

      _expectLanded(tester, deps.exercises[12]);
    });
  });

  group('S-13909 session editor system back', () {
    testWidgets('the PopScope path lands the same way', (tester) async {
      final deps = await _manyExercises();
      await _pumpSession(tester, deps, editMode: true);
      expect(find.byType(ListView), findsOneWidget);

      await _openExercise(tester, deps.exercises[11]);
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Edit Session'), findsOneWidget);
      _expectLanded(tester, deps.exercises[11]);
    });
  });

  group('S-13910 rolling session list', () {
    testWidgets('the rolling list lands the same way', (tester) async {
      final deps = await _manyExercises(rolling: true);
      await _pumpSession(tester, deps);
      expect(find.byType(ListView), findsOneWidget);

      await _openExercise(tester, deps.exercises[13]);
      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
      await tester.pumpAndSettle();

      _expectLanded(tester, deps.exercises[13]);
    });
  });
}
