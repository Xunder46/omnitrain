import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

import 'helpers/fake_preferences_service.dart';

/// S-1, S-2, S-4: the profile body-measurement quick chart (sparkline) plots and
/// labels in the user's active display unit. A `unit-kg` measurement converts to
/// the preferred weight unit (kg/lbs); every other measurement plots unchanged.
///
/// The y-axis value labels carry the keys `measurement_sparkline_y_max` and
/// `measurement_sparkline_y_min`.
void main() {
  Future<SettingsState> settingsWithWeightUnit(
    MockWorkoutRepository repository,
    String unit,
  ) async {
    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();
    await settingsState.setPreferredWeightUnit(unit);
    return settingsState;
  }

  String axisText(WidgetTester tester, String key) {
    return tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Text),
          ),
        )
        .data!;
  }

  Future<void> pumpProfile(
    WidgetTester tester,
    ProfileState profileState,
    SettingsState settingsState,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileState: profileState,
          settingsState: settingsState,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('S-1: bodyweight sparkline labels in pounds under lbs', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    // 80 kg and 90 kg — a non-degenerate range so both axis labels differ.
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bw-1',
        measurementType: 'bodyweight',
        value: 80,
        unitId: 'unit-kg',
        recordedAtMs: 1000,
      ),
    );
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bw-2',
        measurementType: 'bodyweight',
        value: 90,
        unitId: 'unit-kg',
        recordedAtMs: 2000,
      ),
    );

    final profileState = ProfileState(repository);
    final settingsState = await settingsWithWeightUnit(repository, 'lbs');

    await pumpProfile(tester, profileState, settingsState);

    // 90 kg → 198.4 lbs, 80 kg → 176.4 lbs.
    expect(axisText(tester, 'measurement_sparkline_y_max'), '198.4');
    expect(axisText(tester, 'measurement_sparkline_y_min'), '176.4');
  });

  testWidgets('S-2: bodyweight sparkline labels in kg under kg', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bw-1',
        measurementType: 'bodyweight',
        value: 80,
        unitId: 'unit-kg',
        recordedAtMs: 1000,
      ),
    );
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bw-2',
        measurementType: 'bodyweight',
        value: 90,
        unitId: 'unit-kg',
        recordedAtMs: 2000,
      ),
    );

    final profileState = ProfileState(repository);
    final settingsState = await settingsWithWeightUnit(repository, 'kg');

    await pumpProfile(tester, profileState, settingsState);

    expect(axisText(tester, 'measurement_sparkline_y_max'), '90');
    expect(axisText(tester, 'measurement_sparkline_y_min'), '80');
  });

  testWidgets('S-4: non-weight measurement ignores the weight preference', (
    tester,
  ) async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bf-1',
        measurementType: 'body_fat_pct',
        value: 18.5,
        unitId: 'unit-pct',
        recordedAtMs: 1000,
      ),
    );
    await repository.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bf-2',
        measurementType: 'body_fat_pct',
        value: 20,
        unitId: 'unit-pct',
        recordedAtMs: 2000,
      ),
    );

    final profileState = ProfileState(repository);
    final settingsState = await settingsWithWeightUnit(repository, 'lbs');

    await pumpProfile(tester, profileState, settingsState);

    // Body fat is a percentage — the weight preference must not touch it.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    final maxTexts = find
        .descendant(
          of: find.byKey(const Key('measurement_sparkline_y_max')),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .toList();
    final minTexts = find
        .descendant(
          of: find.byKey(const Key('measurement_sparkline_y_min')),
          matching: find.byType(Text),
        )
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .toList();

    // The body-fat card labels its stored percentage values unchanged.
    expect(maxTexts, contains('20'));
    expect(minTexts, contains('18.5'));
  });
}
