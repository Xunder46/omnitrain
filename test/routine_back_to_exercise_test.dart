// Scenario mapping (plan 139):
//   S-13903 back (header arrow) from an exercise in the middle of a long routine
//           returns with that exercise in view
//   S-13904 the same through the system back gesture (the screen's PopScope)
//   S-13905 after walking with the arrows (plan 138), back returns to the
//           exercise the user is on now, not the one they opened
//   S-13906 the last exercise lands as low as the list can scroll
//   S-13907 the raised cache extent is gone once the list is back (steady state)
//
// Mock repository only, no timers and no real delays (FakeAsync).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/routine/routine_setup_screen.dart';
import 'package:omnitrain/state/routine/routine_state.dart';
import 'package:omnitrain/state/workout/workout_state.dart';

/// The routine editor's list only lays out at this height in the test font.
const Size _listSize = Size(600, 1200);

/// The detail view runs at phone size (as in routine_detail_screen_test.dart).
const Size _detailSize = Size(402, 874);

class _Fixture {
  _Fixture(this.routineState, this.workoutState, this.exercises);
  final RoutineState routineState;
  final WorkoutState workoutState;
  final List<Exercise> exercises;
}

/// 24 distinct library exercises in six blocks of four, one set each. Cards
/// this tall put the fourth block beyond the lazy list's default build range,
/// so the raised cache extent is what makes its rows findable (plan 139 D-2).
Future<_Fixture> _manyExercises() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.setPreferenceBool('hint_seen_exercise_info', true);
  await repo.setPreferenceBool('hint_seen_exercise_notes', true);
  final workoutState = WorkoutState(repo);
  final routineState = RoutineState(repo);
  routineState.setAutosaveEnabled(false);
  await routineState.createNewRoutine('Back Routine');

  final names = <String>{};
  final picked = <Exercise>[];
  for (final exercise in await repo.getExercises()) {
    if (names.add(exercise.name)) picked.add(exercise);
    if (picked.length == 24) break;
  }
  expect(picked.length, 24, reason: 'the library has 24 distinct names');

  final blockIds = <String>[routineState.currentSegments.first.id];
  for (var block = 2; block <= 6; block++) {
    blockIds.add(await routineState.addSegment(name: 'Block $block'));
  }
  for (var i = 0; i < picked.length; i++) {
    await routineState.addExerciseToRoutine(
      picked[i],
      'set',
      segmentId: blockIds[i ~/ 4],
    );
  }
  return _Fixture(routineState, workoutState, picked);
}

Future<void> _pumpEditor(WidgetTester tester, _Fixture f) async {
  await tester.binding.setSurfaceSize(_listSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await f.routineState.saveRoutine();
  final templateId = f.routineState.currentTemplate!.id;
  await tester.pumpWidget(
    MaterialApp(
      home: RoutineSetupScreen(
        routineState: f.routineState,
        workoutState: f.workoutState,
        templateId: templateId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The row is built, laid out and fully inside the list.
///
/// Evaluates the plain text finder: a `.first` finder throws on evaluate
/// when the row is not built (far rows out of the lazy list do not exist).
bool _rowOnScreen(WidgetTester tester, Finder row) {
  final matches = row.evaluate();
  if (matches.isEmpty) return false;
  final renderObject = matches.first.renderObject;
  if (renderObject is! RenderBox || !renderObject.hasSize) return false;
  final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
  final list = _listRect(tester);
  // A row under the bottom actions overlay takes no taps, so demand clear
  // space above it.
  return rect.top >= list.top + 24 && rect.bottom <= list.bottom - 150;
}

/// Scrolls [exercise]'s row into view with the list's own controller, taps it
/// and switches to phone size.
Future<void> _openExercise(WidgetTester tester, Exercise exercise) async {
  final row = find.text(exercise.name);
  final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
  for (var step = 0; step < 20 && !_rowOnScreen(tester, row); step++) {
    controller.jumpTo(
      (controller.offset + 400).clamp(0.0, controller.position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  expect(_rowOnScreen(tester, row), isTrue, reason: '${exercise.name} reached');
  await tester.tap(row.first);
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(_detailSize);
  await tester.pumpAndSettle();
}

Future<void> _backToListWithHeader(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_listSize);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back));
  await tester.pumpAndSettle();
}

Future<void> _backToListWithGesture(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_listSize);
  await tester.pumpAndSettle();
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Rect _listRect(WidgetTester tester) => tester.getRect(find.byType(ListView));

Rect _rowRect(WidgetTester tester, Exercise exercise) => tester.getRect(
  find
      .ancestor(
        of: find.text(exercise.name).first,
        matching: find.byType(ExerciseCard),
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
  group('S-13903 header back returns to the exercise left', () {
    testWidgets('an exercise in the middle of a long routine is in view', (
      tester,
    ) async {
      final f = await _manyExercises();
      await _pumpEditor(tester, f);

      await _openExercise(tester, f.exercises[13]);
      expect(find.textContaining('Exercise 14 / 24'), findsOneWidget);
      await _backToListWithHeader(tester);

      expect(find.byType(ListView), findsOneWidget);
      _expectLanded(tester, f.exercises[13]);
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      expect(
        controller.offset,
        lessThan(controller.position.maxScrollExtent - 100),
        reason: 'it did not jump to the bottom',
      );
    });
  });

  group('S-13904 system back returns to the exercise left', () {
    testWidgets('the PopScope path lands the same way', (tester) async {
      final f = await _manyExercises();
      await _pumpEditor(tester, f);

      await _openExercise(tester, f.exercises[13]);
      await _backToListWithGesture(tester);

      expect(find.byType(ListView), findsOneWidget);
      _expectLanded(tester, f.exercises[13]);
    });
  });

  group('S-13905 back follows the arrows', () {
    testWidgets('after Next x3 back lands on the exercise reached', (
      tester,
    ) async {
      final f = await _manyExercises();
      await _pumpEditor(tester, f);

      await _openExercise(tester, f.exercises[12]);
      expect(find.textContaining('Exercise 13 / 24'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Next Set'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Exercise 16 / 24'), findsOneWidget);
      await _backToListWithHeader(tester);

      _expectLanded(tester, f.exercises[15]);
    });
  });

  group('S-13906 the last exercise', () {
    testWidgets('lands as low as the list can scroll', (tester) async {
      final f = await _manyExercises();
      await _pumpEditor(tester, f);

      await _openExercise(tester, f.exercises[23]);
      await _backToListWithHeader(tester);

      final list = _listRect(tester);
      final row = _rowRect(tester, f.exercises[23]);
      expect(row.top, greaterThanOrEqualTo(list.top));
      expect(row.bottom, lessThanOrEqualTo(list.bottom));
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      expect(controller.offset, controller.position.maxScrollExtent);
      expect(tester.takeException(), isNull);
    });
  });

  group('S-13907 steady state', () {
    testWidgets('the list is back to its default cache extent', (tester) async {
      final f = await _manyExercises();
      await _pumpEditor(tester, f);

      await _openExercise(tester, f.exercises[13]);
      await _backToListWithHeader(tester);

      expect(
        tester.widget<ListView>(find.byType(ListView)).cacheExtent,
        isNull,
      );
    });
  });
}
