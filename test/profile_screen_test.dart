import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/features/profile/widgets/measurement_history_chart_sheet.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'helpers/fake_preferences_service.dart';

void main() {
  testWidgets('all charted-measurement log sheets hide note and date input', (
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

    // Body Weight add button (first charted measurement — the
    // cleanup pass moved bodyweight from primary to the top of the
    // charted column and dropped height out of the column
    // entirely).
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('Log Body Weight'), findsOneWidget);
    expect(find.text('DATE'), findsNothing);
    expect(find.text('Note (optional)'), findsNothing);

    Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
    await tester.pumpAndSettle();

    // Scroll down to make the additional charted measurements
    // visible. The first additional card is BODY FAT.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    // Second add button (first additional charted measurement after
    // Body Weight — Body Fat). Lean Mass has no add button
    // (read-only computed row), so the second `Icons.add` lands
    // squarely on Body Fat's button.
    await tester.tap(find.byIcon(Icons.add).at(1));
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
  //
  // Cleanup pass: height lives in the identity area, not in a chart
  // card. The "value column" tests below assert that the identity
  // area renders the canonical height in the active unit. The
  // "log sheet" tests were rewritten to drive the new
  // identity-area editor dialog (`_HeightDialog`) — the cm / ftin
  // input shape is preserved (the dialog is the cm/ftin-aware
  // input) but the trigger is tapping the identity-area height
  // value rather than a chart-card `+` button.

  testWidgets('identity area reflects cm mode (default) for stored height', (
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

    // The identity area's height value is keyed
    // `profile_identity_height_value`. The text reads "180 cm" in
    // default cm mode.
    expect(
      find.descendant(
        of: find.byKey(const Key('profile_identity_height_value')),
        matching: find.text('180 cm'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('identity area reflects ftin mode for stored height', (
    tester,
  ) async {
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
        of: find.byKey(const Key('profile_identity_height_value')),
        matching: find.text("5' 11\""),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'identity-area height dialog presents single cm field in cm mode',
    (tester) async {
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

      // Tap the identity-area height value.
      await tester.tap(find.byKey(const Key('profile_identity_height_value')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Height'), findsOneWidget);
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
    },
  );

  testWidgets(
    'identity-area height dialog presents feet/inches fields in ftin mode',
    (tester) async {
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

      // Tap the identity-area height value.
      await tester.tap(find.byKey(const Key('profile_identity_height_value')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Height'), findsOneWidget);
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
    },
  );

  testWidgets(
    'identity-area height dialog rejects inches above 11 in ftin mode',
    (tester) async {
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

      await tester.tap(find.byKey(const Key('profile_identity_height_value')));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '6');
      await tester.enterText(fields.at(1), '12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Validation error expressed in the active unit. Inches are
      // bounded to 0-11 as a per-field rule, so the error names the
      // field directly. The dialog stays open.
      expect(find.textContaining('0 and 11 inches'), findsOneWidget);
      // No entry was saved.
      final history = await profileState.getMeasurementHistory('height');
      expect(history, isEmpty);
    },
  );

  testWidgets(
    'identity-area height round-trips cm mode (no drift across unit toggle)',
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

      // Save 180 cm via the identity-area editor.
      await tester.tap(find.byKey(const Key('profile_identity_height_value')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '180');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Switch to ftin and re-render the screen.
      await settingsState.setPreferredHeightUnit('ftin');
      await tester.pumpAndSettle();

      // Identity area reads in compound ftin.
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_identity_height_value')),
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
          of: find.byKey(const Key('profile_identity_height_value')),
          matching: find.text('180 cm'),
        ),
        findsOneWidget,
      );
    },
  );

  // ─── Horizontal identity header (S-004) ──────────────────────────────
  //
  // S-004: tapping the name opens the name editor; tapping the height
  // opens the height editor. Both tap targets are wired to their
  // existing dialog paths and persist via the existing repository
  // methods.

  group('S-004: horizontal identity header — name and height tap targets', () {
    testWidgets(
      'tapping the name opens the Edit Name dialog with the current value',
      (tester) async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await repository.saveProfile(
          UserProfile(id: 'local-user', displayName: 'Iris', createdAtMs: 1000),
        );
        final profileState = ProfileState(repository);
        await profileState.loadProfile();
        final settingsState = SettingsState(
          repository,
          fakePreferencesService(),
        );
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

        // The name tap target is a plain InkWell in the identity
        // header. Tap on the name text directly — that's the visible
        // surface of the name tap target.
        await tester.tap(find.text('Iris'));
        await tester.pumpAndSettle();

        expect(find.text('Edit Name'), findsOneWidget);
        final valueField = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        expect(valueField.controller?.text, 'Iris');
      },
    );

    testWidgets(
      'tapping the height line opens the Edit Height dialog and persists '
      'via the existing height path',
      (tester) async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await repository.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'profile-h-header-tap',
            measurementType: 'height',
            value: 180.0,
            unitId: 'unit-cm',
            recordedAtMs: 1000,
          ),
        );
        await repository.saveProfile(
          UserProfile(id: 'local-user', displayName: 'Iris', createdAtMs: 1000),
        );
        final profileState = ProfileState(repository);
        await profileState.loadProfile();
        await profileState.loadLatestMeasurements(<String>{
          ...ProfileMeasurements.additional.map((d) => d.type),
          'height',
        });
        final settingsState = SettingsState(
          repository,
          fakePreferencesService(),
        );
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

        // Tap the height line (the existing key still wraps the height
        // tap target — preserved from the previous layout).
        await tester.tap(
          find.byKey(const Key('profile_identity_height_value')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit Height'), findsOneWidget);
        expect(find.text('Value (cm)'), findsOneWidget);

        // Save 182 cm; the existing `BodyMeasurementEntry(type='height')`
        // path persists it and the identity area re-renders.
        await tester.enterText(find.byType(TextField).first, '182');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('profile_identity_height_value')),
            matching: find.text('182 cm'),
          ),
          findsOneWidget,
        );
        final history = await profileState.getMeasurementHistory('height');
        expect(history.first.unitId, 'unit-cm');
        expect(history.first.value, closeTo(182.0, 0.0001));
      },
    );
  });

  // ─── Iteration 3 — header height subtitle respects the height unit ────
  //
  // The horizontal header was rebuilt in Iterations 1/2. The
  // implementation already calls
  //   UnitFormatter.formatHeight(heightCm, widget.settingsState)
  // and the screen rebuilds on settingsState changes via
  //   Listenable.merge([widget.profileState, widget.settingsState]).
  //
  // These tests make the unit-aware behavior explicit against the
  // new horizontal-header layout (the prior `profile-cleanup` plan
  // added equivalent tests for the prior vertical-hero layout —
  // those still pass, but the user wants explicit coverage for the
  // new subtitle).

  group(
    'S-201: identity header height subtitle is unit-aware (cm vs ftin)',
    () {
      testWidgets('cm mode: subtitle renders with the cm suffix', (
        tester,
      ) async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await repository.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'iter3-h-cm',
            measurementType: 'height',
            value: 180.0,
            unitId: 'unit-cm',
            recordedAtMs: 1000,
          ),
        );
        final profileState = ProfileState(repository);
        await profileState.loadProfile();
        await profileState.loadLatestMeasurements(<String>{
          ...ProfileMeasurements.additional.map((d) => d.type),
          'height',
        });
        final settingsState = SettingsState(
          repository,
          fakePreferencesService(),
        );
        await settingsState.initialize();
        // Default unit is `cm` — assert the subtitle reads "180 cm".
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileScreen(
              profileState: profileState,
              settingsState: settingsState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('profile_identity_height_value')),
            matching: find.text('180 cm'),
          ),
          findsOneWidget,
          reason:
              'header height subtitle must read "180 cm" when the '
              'height unit setting is cm',
        );
        // The "cm" suffix must NOT be hardcoded — verify it is the
        // formatted output of the active unit, not a literal.
        expect(
          find.descendant(
            of: find.byKey(const Key('profile_identity_height_value')),
            matching: find.text('180'),
          ),
          findsNothing,
          reason:
              'subtitle must include the unit suffix; a bare "180" '
              'would mean a hardcoded value that ignored the unit',
        );
      });

      testWidgets('ftin mode: subtitle renders in compound feet/inches', (
        tester,
      ) async {
        final repository = MockWorkoutRepository();
        await repository.initialize();
        await repository.saveMeasurementEntry(
          BodyMeasurementEntry(
            id: 'iter3-h-ftin',
            measurementType: 'height',
            value: 180.0,
            unitId: 'unit-cm',
            recordedAtMs: 1000,
          ),
        );
        final profileState = ProfileState(repository);
        await profileState.loadProfile();
        await profileState.loadLatestMeasurements(<String>{
          ...ProfileMeasurements.additional.map((d) => d.type),
          'height',
        });
        final settingsState = SettingsState(
          repository,
          fakePreferencesService(),
        );
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

        // 180 cm = 5 ft 11 in (rounded).
        expect(
          find.descendant(
            of: find.byKey(const Key('profile_identity_height_value')),
            matching: find.text("5' 11\""),
          ),
          findsOneWidget,
          reason:
              'header height subtitle must read "5\' 11"" when the '
              'height unit setting is ftin',
        );
        // The cm suffix must NOT appear when ftin is selected.
        expect(
          find.descendant(
            of: find.byKey(const Key('profile_identity_height_value')),
            matching: find.textContaining('cm'),
          ),
          findsNothing,
          reason:
              'subtitle must drop the "cm" suffix when the active '
              'unit is ftin',
        );
      });
    },
  );

  group(
    'S-202: identity header height subtitle re-renders live on unit toggle',
    () {
      testWidgets(
        'toggling ftin → cm updates the subtitle without leaving the screen',
        (tester) async {
          final repository = MockWorkoutRepository();
          await repository.initialize();
          await repository.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: 'iter3-h-live-ftin-cm',
              measurementType: 'height',
              value: 180.0,
              unitId: 'unit-cm',
              recordedAtMs: 1000,
            ),
          );
          final profileState = ProfileState(repository);
          await profileState.loadProfile();
          await profileState.loadLatestMeasurements(<String>{
            ...ProfileMeasurements.additional.map((d) => d.type),
            'height',
          });
          final settingsState = SettingsState(
            repository,
            fakePreferencesService(),
          );
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

          // Initial render in ftin.
          expect(
            find.descendant(
              of: find.byKey(const Key('profile_identity_height_value')),
              matching: find.text("5' 11\""),
            ),
            findsOneWidget,
          );

          // Toggle to cm. The same screen instance rebuilds; the
          // subtitle must update in place (no navigation, no remount).
          await settingsState.setPreferredHeightUnit('cm');
          await tester.pumpAndSettle();

          expect(
            find.byType(ProfileScreen),
            findsOneWidget,
            reason: 'screen must remain mounted while the unit toggles',
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('profile_identity_height_value')),
              matching: find.text('180 cm'),
            ),
            findsOneWidget,
            reason:
                'subtitle must re-render to cm form immediately after '
                'the unit setting changes',
          );
        },
      );

      testWidgets(
        'toggling cm → ftin updates the subtitle without leaving the screen',
        (tester) async {
          final repository = MockWorkoutRepository();
          await repository.initialize();
          await repository.saveMeasurementEntry(
            BodyMeasurementEntry(
              id: 'iter3-h-live-cm-ftin',
              measurementType: 'height',
              value: 180.0,
              unitId: 'unit-cm',
              recordedAtMs: 1000,
            ),
          );
          final profileState = ProfileState(repository);
          await profileState.loadProfile();
          await profileState.loadLatestMeasurements(<String>{
            ...ProfileMeasurements.additional.map((d) => d.type),
            'height',
          });
          final settingsState = SettingsState(
            repository,
            fakePreferencesService(),
          );
          await settingsState.initialize();
          // Default cm unit at start.

          await tester.pumpWidget(
            MaterialApp(
              home: ProfileScreen(
                profileState: profileState,
                settingsState: settingsState,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Initial render in cm.
          expect(
            find.descendant(
              of: find.byKey(const Key('profile_identity_height_value')),
              matching: find.text('180 cm'),
            ),
            findsOneWidget,
          );

          // Toggle to ftin. The same screen instance rebuilds.
          await settingsState.setPreferredHeightUnit('ftin');
          await tester.pumpAndSettle();

          expect(
            find.byType(ProfileScreen),
            findsOneWidget,
            reason: 'screen must remain mounted while the unit toggles',
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('profile_identity_height_value')),
              matching: find.text("5' 11\""),
            ),
            findsOneWidget,
            reason:
                'subtitle must re-render to ftin form immediately after '
                'the unit setting changes',
          );
        },
      );
    },
  );
}
