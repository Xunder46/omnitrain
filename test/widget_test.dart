import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/workout_session_service.dart';
import 'package:omnitrain/main.dart';

void main() {
  testWidgets('Open exercise list -> open detail -> return focuses selected exercise', (WidgetTester tester) async {
    final service = WorkoutSessionService();
    await service.createNewSession();
    await service.addExercise('Squats');
    await service.addExercise('Press');

    await tester.pumpWidget(MaterialApp(home: WorkoutSessionScreen(sessionService: service)));
    await tester.pumpAndSettle();

    // List view should be shown by default
    expect(find.text('Exercises'), findsOneWidget);
    expect(find.text('Squats'), findsOneWidget);
    expect(find.text('Press'), findsOneWidget);

    // Tap 'Press' to open detail
    await tester.tap(find.text('Press'));
    await tester.pumpAndSettle();

    // WorkoutSessionScreen should show the exercise name in the header
    expect(find.text('Press'), findsWidgets);
  });

  testWidgets('Create exercise -> open detail -> back focuses new exercise', (WidgetTester tester) async {
    final service = WorkoutSessionService();
    await service.createNewSession();

    await tester.pumpWidget(MaterialApp(home: WorkoutSessionScreen(sessionService: service)));
    await tester.pumpAndSettle();

    // List view should be shown by default with floating add button
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Enter exercise name
    await tester.enterText(find.byType(TextField), 'Cleans');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // After adding, WorkoutSessionScreen should show the newly created exercise in detail view
    expect(find.text('Cleans'), findsWidgets);
  });
}