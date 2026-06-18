import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/profile/widgets/measurement_history_chart_sheet.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'helpers/fake_preferences_service.dart';

void main() {
  testWidgets('all measurement log sheets hide note input and date input', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository, fakePreferencesService());
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

    // Third add button (first additional measurement - BODY FAT)
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
    final settingsState = SettingsState(repository, fakePreferencesService());
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

    // Phase 4: the measurement name now lives in the
    // [OmniCardHeader] above the card; tapping the header text does
    // not open the history sheet. The sparkline area inside the
    // card body holds the [InkWell] (key `measurement_sparkline_tap`).
    // Tap the first sparkline to open the history sheet.
    await tester.tap(find.byKey(const Key('measurement_sparkline_tap')).first);
    await tester.pumpAndSettle();

    // The history sheet header shows the measurement label in uppercase.
    // A17: scope through the sheet — the uppercased `OmniCardHeader`
    // title on the underlying screen also renders 'BODY WEIGHT' so an
    // unscoped `find.text('BODY WEIGHT')` would match 2 widgets.
    expect(
      find.descendant(
        of: find.byType(MeasurementHistoryChartSheet),
        matching: find.text('BODY WEIGHT'),
      ),
      findsOneWidget,
    );
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
    final settingsState = SettingsState(repository, fakePreferencesService());
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

    // Phase 4: the card body no longer renders the formatted weight
    // value (it renders a sparkline). The lbs preference is still
    // honoured by the log sheet — which is what this assertion now
    // covers. Tap the `+` icon in the [OmniCardHeader] actions slot
    // (Phase 4: still keyed by the icon itself) to open the log
    // sheet and verify the unit + prefilled value.
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
