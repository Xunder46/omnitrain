import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

void main() {
  testWidgets('all measurement log sheets hide note input and date input', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Body Weight add button (first primary measurement)
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('Log Body Weight'), findsOneWidget);
    expect(find.text('DATE'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);

    Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
    await tester.pumpAndSettle();

    // Height add button (second primary measurement)
    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Log Height'), findsOneWidget);
    expect(find.text('DATE'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);

    Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
    await tester.pumpAndSettle();

    // Scroll down to make additional measurements visible
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // Third add button (first additional measurement - Body Fat)
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Log '), findsOneWidget);
    expect(find.text('DATE'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);
  });

  testWidgets('measurement history loads without note UI', (tester) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'history-entry',
        measurementType: 'bodyweight',
        value: 80,
        unitId: 'unit-kg',
        recordedAtMs: 123456,
      ),
    );

    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Body Weight'));
    await tester.pumpAndSettle();

    // The history sheet header shows the measurement label in uppercase
    expect(find.text('BODY WEIGHT'), findsOneWidget);
    expect(find.text('Note (optional)'), findsNothing);
  });

  testWidgets('body weight respects lbs preference in display and logging', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bodyweight-existing',
        measurementType: 'bodyweight',
        value: 80,
        unitId: 'unit-kg',
        recordedAtMs: 1000,
      ),
    );

    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository);
    await settingsState.initialize();
    await settingsState.setPreferredWeightUnit('lbs');

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('176.4 lbs'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('Value (lbs)'), findsOneWidget);

    final valueField = tester.widget<TextField>(find.byType(TextField).first);
    expect(valueField.controller?.text, '176.4');

    await tester.enterText(find.byType(TextField).first, '220.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final history = await profileState.getMeasurementHistory('bodyweight');
    expect(history.first.unitId, 'unit-kg');
    expect(history.first.value, closeTo(100.0, 0.1));
  });
}
