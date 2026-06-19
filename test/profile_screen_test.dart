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

  // ─── Height unit preference — display and entry ─────────────────────────

  testWidgets('height value column reflects cm mode (default)', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'height-existing-cm',
        measurementType: 'height',
        value: 180.0,
        unitId: 'unit-cm',
        recordedAtMs: 1000,
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

    // The height card's value column (key `measurement_value`)
    // shows the value text. Both bodyweight and height cards have
    // this key, so find the height one via the descendant
    // relationship to the surrounding card.
    expect(
      find.descendant(
        of: find.byKey(const Key('profile_height_card')),
        matching: find.text('180 cm'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('height value column reflects ftin mode', (tester) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'height-existing-ftin',
        measurementType: 'height',
        value: 180.0,
        unitId: 'unit-cm',
        recordedAtMs: 1000,
      ),
    );

    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();
    await settingsState.setPreferredHeightUnit('ftin');

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 180 cm = 70.866 in → rounds to 71 in = 5' 11".
    expect(
      find.descendant(
        of: find.byKey(const Key('profile_height_card')),
        matching: find.text("5' 11\""),
      ),
      findsOneWidget,
    );
  });

  testWidgets('height log sheet presents single cm field in cm mode', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'height-existing-cm-log',
        measurementType: 'height',
        value: 180.0,
        unitId: 'unit-cm',
        recordedAtMs: 1000,
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

    // The height card is the second primary measurement; tap its
    // add button. The first `Icons.add` is on the bodyweight card.
    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Log Height'), findsOneWidget);
    expect(find.text('Value (cm)'), findsOneWidget);
    // No feet/inches labels in cm mode.
    expect(find.text('Feet'), findsNothing);
    expect(find.text('Inches'), findsNothing);

    // The pre-filled value is the existing 180.0 cm.
    final valueField = tester.widget<TextField>(find.byType(TextField).first);
    expect(valueField.controller?.text, '180');

    // Save with the existing value, then assert the stored entry is
    // unchanged (still 180.0 cm in unit-cm).
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final history = await profileState.getMeasurementHistory('height');
    expect(history.first.unitId, 'unit-cm');
    expect(history.first.value, 180.0);
  });

  testWidgets('height log sheet presents feet/inches fields in ftin mode', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'height-existing-ftin-log',
        measurementType: 'height',
        value: 180.0,
        unitId: 'unit-cm',
        recordedAtMs: 1000,
      ),
    );

    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();
    await settingsState.setPreferredHeightUnit('ftin');

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The height card is the second primary measurement.
    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Log Height'), findsOneWidget);
    expect(find.text('Feet'), findsOneWidget);
    expect(find.text('Inches'), findsOneWidget);
    // The single cm field is NOT present in ftin mode.
    expect(find.text('Value (cm)'), findsNothing);

    // The pre-filled feet/inches pair is the current value
    // (180.0 cm = 5 ft 11 in).
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    final feetField = tester.widget<TextField>(fields.at(0));
    final inchesField = tester.widget<TextField>(fields.at(1));
    expect(feetField.controller?.text, '5');
    expect(inchesField.controller?.text, '11');
  });

  testWidgets('height log sheet rejects inches above 11 in ftin mode', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final profileState = ProfileState(repository);
    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();
    await settingsState.setPreferredHeightUnit('ftin');

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).at(1));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '6');
    await tester.enterText(fields.at(1), '12');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Validation error expressed in the active unit. Inches are
    // bounded to 0-11 as a per-field rule, so the error names the
    // field directly.
    expect(
      find.textContaining('0 and 11 inches'),
      findsOneWidget,
    );
    // No entry was saved.
    final history = await profileState.getMeasurementHistory('height');
    expect(history, isEmpty);
  });

  testWidgets(
    'height log sheet round-trips cm mode (no drift across unit toggle)',
    (tester) async {
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

      // Save 180 cm.
      await tester.tap(find.byIcon(Icons.add).at(1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '180');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Switch to ftin and re-render the screen.
      await settingsState.setPreferredHeightUnit('ftin');
      await tester.pumpAndSettle();

      // Profile card value reads in compound ftin.
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_height_card')),
          matching: find.text("5' 11\""),
        ),
        findsOneWidget,
      );

      // Switch back to cm and re-render.
      await settingsState.setPreferredHeightUnit('cm');
      await tester.pumpAndSettle();

      // Original value preserved exactly (no drift).
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_height_card')),
          matching: find.text('180 cm'),
        ),
        findsOneWidget,
      );
    },
  );
}
