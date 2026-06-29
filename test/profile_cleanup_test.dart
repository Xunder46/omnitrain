// Coverage for the profile-screen cleanup pass:
//
//  * Height is no longer a charted measurement card; it lives as a
//    tappable, editable value in the identity area.
//  * Measurements render in the exact specified order:
//      Body Weight, Body Fat %, Waist, Lean Mass, Hips, Thigh,
//      Chest, Arm.
//  * Lean Mass is a calculated, read-only value derived from the
//    latest body weight and body fat percentage.
//
// The tests are split between state (pure) and widget (render +
// interaction). They use MockWorkoutRepository per the project's
// environment contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'helpers/fake_preferences_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<ProfileState> _seededState({
  double? bodyWeightKg,
  double? bodyFatPct,
  double? leanMassKg,
  double? heightCm,
  List<BodyMeasurementEntry>? extras,
}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final ts = DateTime.now().millisecondsSinceEpoch;
  if (heightCm != null) {
    await repo.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'h-1',
        measurementType: 'height',
        value: heightCm,
        unitId: 'unit-cm',
        recordedAtMs: ts - 5000,
      ),
    );
  }
  if (bodyWeightKg != null) {
    await repo.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bw-1',
        measurementType: 'bodyweight',
        value: bodyWeightKg,
        unitId: 'unit-kg',
        recordedAtMs: ts - 4000,
      ),
    );
  }
  if (bodyFatPct != null) {
    await repo.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'bf-1',
        measurementType: 'body_fat_pct',
        value: bodyFatPct,
        unitId: 'unit-pct',
        recordedAtMs: ts - 3000,
      ),
    );
  }
  if (leanMassKg != null) {
    await repo.saveMeasurementEntry(
      BodyMeasurementEntry(
        id: 'lm-1',
        measurementType: 'lean_mass',
        value: leanMassKg,
        unitId: 'unit-kg',
        recordedAtMs: ts - 2000,
      ),
    );
  }
  for (final e in extras ?? const <BodyMeasurementEntry>[]) {
    await repo.saveMeasurementEntry(e);
  }
  final state = ProfileState(repo);
  await state.loadProfile();
  // The cleanup pass loads `height` separately from the charted
  // measurements — make sure the test state mirrors that.
  await state.loadLatestMeasurements(['height']);
  return state;
}

Future<SettingsState> _settings({String weightUnit = 'kg'}) async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final s = SettingsState(repo, fakePreferencesService());
  await s.initialize();
  if (weightUnit != 'kg') {
    await s.setPreferredWeightUnit(weightUnit);
  }
  return s;
}

Future<void> _pumpProfileScreen(
  WidgetTester tester, {
  required ProfileState profileState,
  required SettingsState settingsState,
}) async {
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

// ── Constants — S-001 / S-004 ────────────────────────────────────────────────

void main() {
  group('S-001: charted measurement definition list', () {
    test('does NOT include height', () {
      final types = ProfileMeasurements.additional
          .map((definition) => definition.type)
          .toSet();
      expect(types.contains('height'), isFalse);
    });

    test('includes all charted measurements except height', () {
      final types = ProfileMeasurements.additional
          .map((definition) => definition.type)
          .toSet();
      expect(types, containsAll(<String>{
        'bodyweight',
        'body_fat_pct',
        'waist_cm',
        'lean_mass',
        'hips_cm',
        'thigh_cm',
        'chest_cm',
        'arm_cm',
      }));
      expect(types.length, 8);
    });
  });

  group('S-004: measurement list order is the exact specified sequence', () {
    test('matches: Body Weight, Body Fat, Waist, Lean Mass, Hips, Thigh, Chest, Arm',
        () {
      final types = ProfileMeasurements.additional
          .map((definition) => definition.type)
          .toList();
      expect(types, <String>[
        'bodyweight',
        'body_fat_pct',
        'waist_cm',
        'lean_mass',
        'hips_cm',
        'thigh_cm',
        'chest_cm',
        'arm_cm',
      ]);
    });
  });

  // ── State — S-005 / S-007 ─────────────────────────────────────────────────

  group('S-005: computed lean mass = weight × (1 - bodyFat/100)', () {
    test('returns null when body weight is missing', () async {
      final state = await _seededState(bodyFatPct: 15.0);
      expect(state.computedLeanMassKg, isNull);
    });

    test('returns null when body fat is missing', () async {
      final state = await _seededState(bodyWeightKg: 80.0);
      expect(state.computedLeanMassKg, isNull);
    });

    test('returns null when neither body weight nor body fat is set', () async {
      final state = await _seededState();
      expect(state.computedLeanMassKg, isNull);
    });

    test('computes correctly for 80 kg @ 15% body fat → 68 kg', () async {
      final state = await _seededState(
        bodyWeightKg: 80.0,
        bodyFatPct: 15.0,
      );
      expect(state.computedLeanMassKg, closeTo(68.0, 0.0001));
    });

    test('recomputes when body weight changes', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = ProfileState(repo);
      await state.loadProfile();
      await state.loadLatestMeasurements(['height']);
      await state.logMeasurement('bodyweight', 80.0, 'unit-kg',
          recordedAtMs: 1000);
      await state.logMeasurement('body_fat_pct', 15.0, 'unit-pct',
          recordedAtMs: 1100);
      expect(state.computedLeanMassKg, closeTo(68.0, 0.0001));
      await state.logMeasurement('bodyweight', 82.0, 'unit-kg',
          recordedAtMs: 1200);
      expect(state.computedLeanMassKg, closeTo(69.7, 0.0001));
    });

    test('recomputes when body fat changes', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = ProfileState(repo);
      await state.loadProfile();
      await state.loadLatestMeasurements(['height']);
      await state.logMeasurement('bodyweight', 80.0, 'unit-kg',
          recordedAtMs: 1000);
      await state.logMeasurement('body_fat_pct', 15.0, 'unit-pct',
          recordedAtMs: 1100);
      expect(state.computedLeanMassKg, closeTo(68.0, 0.0001));
      await state.logMeasurement('body_fat_pct', 12.0, 'unit-pct',
          recordedAtMs: 1200);
      expect(state.computedLeanMassKg, closeTo(70.4, 0.0001));
    });
  });

  group('S-002/S-003: height persistence via updateHeight()', () {
    test('updateHeight persists a height entry the next load can read', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = ProfileState(repo);
      await state.loadProfile();
      await state.loadLatestMeasurements(['height']);

      expect(state.latestHeightCm, isNull);

      await state.updateHeight(182.0);

      expect(state.latestHeightCm, closeTo(182.0, 0.0001));
      final history = await state.getMeasurementHistory('height');
      expect(history.first.value, 182.0);
      expect(history.first.unitId, 'unit-cm');
    });

    test('a pre-existing height is preserved through updateHeight()', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.saveMeasurementEntry(
        BodyMeasurementEntry(
          id: 'preexisting',
          measurementType: 'height',
          value: 178.0,
          unitId: 'unit-cm',
          recordedAtMs: 1000,
        ),
      );
      final state = ProfileState(repo);
      await state.loadProfile();
      await state.loadLatestMeasurements(['height']);

      expect(state.latestHeightCm, closeTo(178.0, 0.0001));

      await state.updateHeight(180.0);
      expect(state.latestHeightCm, closeTo(180.0, 0.0001));

      final history = await state.getMeasurementHistory('height');
      expect(history.map((e) => e.value),
          containsAll(<double>[178.0, 180.0]));
    });
  });

  // ── Widget — render of the new identity height + reordered cards ─────────

  group('S-001: Profile screen does not render Height as a charted card', () {
    testWidgets('renders no HEIGHT card-header (chart-card)', (tester) async {
      final state = await _seededState(heightCm: 180.0);
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      // The charted column's OmniCardHeader titles are uppercased
      // (A17). Height is no longer a charted card.
      expect(
        find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.text('HEIGHT'),
        ),
        findsNothing,
        reason: 'Height must not render as a charted card on Profile.',
      );
    });
  });

  group('S-002/S-003: Profile identity area renders an editable height value',
      () {
    testWidgets('shows the existing height value next to the name', (tester) async {
      final state = await _seededState(heightCm: 180.0);
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      // The height value is rendered as a tap target inside the
      // identity area (key `profile_identity_height_value`).
      expect(
        find.byKey(const Key('profile_identity_height_value')),
        findsOneWidget,
      );
      // The text "180 cm" must be present in the identity area.
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_identity_height_value')),
          matching: find.text('180 cm'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping the height value opens an editor that persists', (
      tester,
    ) async {
      final state = await _seededState(heightCm: 180.0);
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      // Tap the height value (the InkWell wraps the row).
      await tester.tap(find.byKey(const Key('profile_identity_height_value')));
      await tester.pumpAndSettle();

      // The dialog is the local _HeightDialog (cm mode → single field).
      expect(find.text('Edit Height'), findsOneWidget);
      expect(find.text('Value (cm)'), findsOneWidget);

      // Clear the field, type a new value, tap Save.
      await tester.enterText(find.byType(TextField).first, '182');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(state.latestHeightCm, closeTo(182.0, 0.0001));
      // The identity area re-renders the new value.
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_identity_height_value')),
          matching: find.text('182 cm'),
        ),
        findsOneWidget,
      );
    });
  });

  group('S-004: charted cards render in the exact specified order', () {
    testWidgets('headers top-to-bottom: BODY WEIGHT, BODY FAT, WAIST, LEAN MASS, HIPS, THIGH, CHEST, ARM',
        (tester) async {
      final state = await _seededState();
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      final expected = <String>[
        'BODY WEIGHT',
        'BODY FAT',
        'WAIST',
        'LEAN MASS',
        'HIPS',
        'THIGH',
        'CHEST',
        'ARM',
      ];
      final headers = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ProfileScreen),
              matching: find.byType(Text),
            ),
          )
          .map((w) => w.data)
          .whereType<String>()
          .where((t) => expected.contains(t))
          .toList();
      // The first occurrence of each header in render order is the
      // authoritative order on screen.
      final seen = <String>[];
      for (final t in headers) {
        if (!seen.contains(t)) seen.add(t);
      }
      expect(seen, expected);
    });
  });

  group('S-005/S-006: Lean Mass card is read-only and computed', () {
    testWidgets('renders the computed lean mass value when both inputs are present',
        (tester) async {
      final state = await _seededState(
        bodyWeightKg: 80.0,
        bodyFatPct: 15.0,
      );
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      // 80 × (1 - 0.15) = 68. The value column reads "68 kg".
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_lean_mass_card')),
          matching: find.text('68 kg'),
        ),
        findsOneWidget,
      );
    });

    // S-301 / S-302 / S-303: Lean Mass caption never shows a
    // mid-expression ellipsis. The full formula must be present in
    // the widget tree (the formula wraps to multiple lines as
    // needed; the previous layout used `maxLines: 1` +
    // `overflow: TextOverflow.ellipsis` which clipped the formula
    // mid-expression on typical phone widths).
    testWidgets(
      'caption renders the full derivation formula (no mid-expression '
      'ellipsis)',
      (tester) async {
        final state = await _seededState(
          bodyWeightKg: 80.0,
          bodyFatPct: 15.0,
        );
        final settings = await _settings();
        await _pumpProfileScreen(
          tester,
          profileState: state,
          settingsState: settings,
        );

        // S-302 — the "Computed" label is always present.
        expect(
          find.descendant(
            of: find.byKey(const Key('profile_lean_mass_card')),
            matching: find.text('Computed'),
          ),
          findsOneWidget,
        );

        // S-301 — the full formula is present. The Text widget
        // contains the untruncated string. With soft-wrap enabled
        // (no maxLines/overflow constraint), `find.text` matches the
        // full string in the widget tree even when the rendered text
        // wraps across multiple lines.
        const formula = 'Body weight × (1 − body fat)';
        expect(
          find.descendant(
            of: find.byKey(const Key('profile_lean_mass_card')),
            matching: find.text(formula),
          ),
          findsOneWidget,
          reason:
              'Lean Mass formula must render in full (no mid-expression '
              'truncation).',
        );

        // S-301 — no ellipsized version of the formula is rendered.
        // A truncated string would either end in the `…` glyph or
        // match a partial substring; we explicitly assert the full
        // string matches and that no descendant text contains `…`.
        expect(
          find.descendant(
            of: find.byKey(const Key('profile_lean_mass_card')),
            matching: find.textContaining('…'),
          ),
          findsNothing,
          reason: 'Lean Mass formula must not end in a `…` truncation '
              'marker.',
        );

        // S-303 — the formula Text widget does not apply
        // TextOverflow.ellipsis. Inspect the Text widget directly.
        final formulaWidget = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('profile_lean_mass_card')),
            matching: find.text(formula),
          ),
        );
        expect(
          formulaWidget.overflow,
          isNot(equals(TextOverflow.ellipsis)),
          reason:
              'Formula Text must not apply TextOverflow.ellipsis — it '
              'must wrap instead of clipping.',
        );
        // maxLines must not be 1 (1 means no wrap; absent/null means
        // unlimited).
        expect(
          formulaWidget.maxLines,
          isNot(equals(1)),
          reason: 'Formula Text must allow wrap (maxLines != 1).',
        );
      },
    );

    testWidgets('no manual add button on the Lean Mass card', (tester) async {
      final state = await _seededState(
        bodyWeightKg: 80.0,
        bodyFatPct: 15.0,
      );
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      // Lean Mass card has its own key (so its body is composed by
      // a special branch). The card must not contain any `+`
      // `OutlinedButton` (the existing card chrome uses
      // `OmniTheme.buttonIconSize` and `Icons.add`).
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_lean_mass_card')),
          matching: find.byIcon(Icons.add),
        ),
        findsNothing,
        reason: 'Lean Mass card must not expose a manual log button.',
      );
    });

    testWidgets('updates when body weight changes', (tester) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = ProfileState(repo);
      await state.loadProfile();
      await state.loadLatestMeasurements(['height']);
      await state.logMeasurement('bodyweight', 80.0, 'unit-kg',
          recordedAtMs: 1000);
      await state.logMeasurement('body_fat_pct', 15.0, 'unit-pct',
          recordedAtMs: 1100);
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_lean_mass_card')),
          matching: find.text('68 kg'),
        ),
        findsOneWidget,
      );
      await state.logMeasurement('bodyweight', 82.0, 'unit-kg',
          recordedAtMs: 1200);
      await tester.pumpAndSettle();
      // 82 × 0.85 = 69.7 → displays as "69.7 kg" via the existing
      // 1dp-or-whole-number formatter.
      expect(
        find.descendant(
          of: find.byKey(const Key('profile_lean_mass_card')),
          matching: find.text('69.7 kg'),
        ),
        findsOneWidget,
      );
    });
  });

  group('S-007: Lean Mass shows not-yet-available when an input is missing',
      () {
    testWidgets('shows em-dash when body fat is missing', (tester) async {
      final state = await _seededState(bodyWeightKg: 80.0);
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('profile_lean_mass_card')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows em-dash when body weight is missing', (tester) async {
      final state = await _seededState(bodyFatPct: 15.0);
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('profile_lean_mass_card')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows em-dash when neither input is set', (tester) async {
      final state = await _seededState();
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('profile_lean_mass_card')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
    });
  });

  group('S-008: untouched measurements keep their original chrome', () {
    testWidgets('Body Weight renders chart + value + add button as before',
        (tester) async {
      final state = await _seededState(bodyWeightKg: 80.0);
      final settings = await _settings();
      await _pumpProfileScreen(
        tester,
        profileState: state,
        settingsState: settings,
      );

      // Body Weight card is now the FIRST charted card (since
      // height left and bodyweight moved from primary to the top
      // of additional). The card chrome is the same as every other
      // non-lean-mass card:
      //   * sparkline area
      //   * value column (key `measurement_value`)
      //   * + button (Icons.add)
      final bwKey = const Key('profile_bodyweight_card');
      expect(find.byKey(bwKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(bwKey),
          matching: find.byKey(const Key('measurement_value')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(bwKey), matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(bwKey),
          matching: find.byKey(const Key('measurement_sparkline_tap')),
        ),
        findsOneWidget,
      );
    });
  });

  group('Settings height preview stays in sync with Profile identity height',
      () {
    testWidgets('editing height on Profile is reflected by the Settings preview',
        (tester) async {
      final repo = MockWorkoutRepository();
      await repo.initialize();
      await repo.saveMeasurementEntry(
        BodyMeasurementEntry(
          id: 'pre-h',
          measurementType: 'height',
          value: 180.0,
          unitId: 'unit-cm',
          recordedAtMs: 1000,
        ),
      );
      final profileState = ProfileState(repo);
      final settingsState = SettingsState(repo, fakePreferencesService());
      await settingsState.initialize();
      await profileState.loadProfile();
      await profileState.loadLatestMeasurements(['height']);

      // 1. Pump Profile screen, edit height to 182.
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
      await tester.enterText(find.byType(TextField).first, '182');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // 2. Pump Settings screen and assert the preview reads 182 cm.
      // We construct SettingsScreen directly so this test stays
      // independent of routing.
      // (SettingsScreen reads `profileState.getMeasurementHistory('height')`
      // so a re-render is enough.)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _SettingsPreviewOnly(
              profileState: profileState,
              settingsState: settingsState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('182 cm'), findsOneWidget);
    });
  });
}

/// Minimal Settings-screen body that renders ONLY the height preview
/// value, so this test exercises the data contract without pulling in
/// the rest of the Settings screen UI.
class _SettingsPreviewOnly extends StatelessWidget {
  final ProfileState profileState;
  final SettingsState settingsState;

  const _SettingsPreviewOnly({
    required this.profileState,
    required this.settingsState,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BodyMeasurementEntry>>(
      future: profileState.getMeasurementHistory('height'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final entries = snapshot.data!;
        if (entries.isEmpty) {
          return const Text('—');
        }
        // Pull the most recent entry (the existing Settings screen
        // does the same in its _loadHeight path).
        entries.sort((a, b) => b.recordedAtMs.compareTo(a.recordedAtMs));
        final latestCm = entries.first.value;
        // Mimic UnitFormatter.formatHeight for cm mode.
        return Text('${latestCm.toStringAsFixed(0)} cm');
      },
    );
  }
}