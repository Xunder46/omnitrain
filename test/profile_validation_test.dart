// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/profile_measurements.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'helpers/fake_preferences_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<SettingsState> _settingsKg() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  final s = SettingsState(repo, fakePreferencesService());
  await s.initialize();
  return s;
}

Future<SettingsState> _settingsLbs() async {
  final s = await _settingsKg();
  await s.setPreferredWeightUnit('lbs');
  return s;
}

// ── Scenarios ────────────────────────────────────────────────────────────────

void main() {
  // ── S-001/S-002: bodyweight range per unit ────────────────────────────────

  group('validationRangeFor – bodyweight', () {
    test('returns kg range [20, 300] in kg mode', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(range.min, 20);
      expect(range.max, 300);
    });

    test('returns lbs range [40, 600] in lbs mode', () async {
      final s = await _settingsLbs();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(range.min, 40);
      expect(range.max, 600);
    });

    // S-003: too low in kg mode
    test('value 15 is below kg min of 20', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(15 < range.min, isTrue);
    });

    // S-004: too high in lbs mode
    test('value 700 is above lbs max of 600', () async {
      final s = await _settingsLbs();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(700 > range.max, isTrue);
    });

    // S-005: zero rejected
    test('value 0 is below kg min of 20', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(0 < range.min, isTrue);
    });

    // S-006: negative rejected
    test('value -10 is below kg min of 20', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(-10 < range.min, isTrue);
    });
  });

  // ── Lean mass unit-aware ranges ───────────────────────────────────────────

  group('validationRangeFor – lean_mass', () {
    test('returns kg range [20, 200] in kg mode', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'lean_mass',
        s.preferredWeightUnit,
      );
      expect(range.min, 20);
      expect(range.max, 200);
    });

    test('returns lbs range [40, 440] in lbs mode', () async {
      final s = await _settingsLbs();
      final range = ProfileMeasurements.validationRangeFor(
        'lean_mass',
        s.preferredWeightUnit,
      );
      expect(range.min, 40);
      expect(range.max, 440);
    });
  });

  // ── S-008: height fixed range ─────────────────────────────────────────────

  group('validationRangeFor – height', () {
    test('returns [50, 250] cm in cm mode', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'height',
        s.preferredWeightUnit,
        heightUnit: s.preferredHeightUnit,
      );
      expect(range.min, 50);
      expect(range.max, 250);
    });

    test('returns feet/inches range in ftin mode', () async {
      final s = await _settingsKg();
      await s.setPreferredHeightUnit('ftin');
      final range = ProfileMeasurements.validationRangeFor(
        'height',
        s.preferredWeightUnit,
        heightUnit: s.preferredHeightUnit,
      );
      // Total inches: 20 (= 1 ft 8 in = 50.8 cm) to 98 (= 8 ft 2 in
      // = 248.92 cm). Both round-trip cleanly with the compound
      // input.
      expect(range.min, 20);
      expect(range.max, 98);
    });

    test('49 is below min of 50 (cm mode)', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'height',
        s.preferredWeightUnit,
        heightUnit: s.preferredHeightUnit,
      );
      expect(49 < range.min, isTrue);
    });

    test('251 is above max of 250 (cm mode)', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'height',
        s.preferredWeightUnit,
        heightUnit: s.preferredHeightUnit,
      );
      expect(251 > range.max, isTrue);
    });

    test(
      '0 ft 0 in (0 in) is below min of 1 ft 8 in (20 in, ftin mode)',
      () async {
        final s = await _settingsKg();
        await s.setPreferredHeightUnit('ftin');
        final range = ProfileMeasurements.validationRangeFor(
          'height',
          s.preferredWeightUnit,
          heightUnit: s.preferredHeightUnit,
        );
        // 0 * 12 + 0 = 0 in < 20 in min
        expect((0 * 12 + 0) < range.min, isTrue);
      },
    );

    test(
      '9 ft 0 in (108 in) is above max of 8 ft 2 in (98 in, ftin mode)',
      () async {
        final s = await _settingsKg();
        await s.setPreferredHeightUnit('ftin');
        final range = ProfileMeasurements.validationRangeFor(
          'height',
          s.preferredWeightUnit,
          heightUnit: s.preferredHeightUnit,
        );
        // 9 * 12 + 0 = 108 in > 98 in max
        expect((9 * 12 + 0) > range.max, isTrue);
      },
    );

    test('1 ft 8 in (20 in) is the lower boundary (ftin mode)', () async {
      final s = await _settingsKg();
      await s.setPreferredHeightUnit('ftin');
      final range = ProfileMeasurements.validationRangeFor(
        'height',
        s.preferredWeightUnit,
        heightUnit: s.preferredHeightUnit,
      );
      expect((1 * 12 + 8) >= range.min, isTrue);
    });

    test('8 ft 2 in (98 in) is the upper boundary (ftin mode)', () async {
      final s = await _settingsKg();
      await s.setPreferredHeightUnit('ftin');
      final range = ProfileMeasurements.validationRangeFor(
        'height',
        s.preferredWeightUnit,
        heightUnit: s.preferredHeightUnit,
      );
      expect((8 * 12 + 2) <= range.max, isTrue);
    });
  });

  // ── S-009: body fat range ─────────────────────────────────────────────────

  group('validationRangeFor – body_fat_pct', () {
    test('returns [1, 100]', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'body_fat_pct',
        s.preferredWeightUnit,
      );
      expect(range.min, 1);
      expect(range.max, 100);
    });

    test('0 is below min of 1', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'body_fat_pct',
        s.preferredWeightUnit,
      );
      expect(0 < range.min, isTrue);
    });
  });

  // ── Circumference ranges ──────────────────────────────────────────────────

  group('validationRangeFor – circumference types', () {
    test('waist_cm returns [30, 200]', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'waist_cm',
        s.preferredWeightUnit,
      );
      expect(range.min, 30);
      expect(range.max, 200);
    });

    test('chest_cm returns [30, 200]', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'chest_cm',
        s.preferredWeightUnit,
      );
      expect(range.min, 30);
      expect(range.max, 200);
    });

    test('hips_cm returns [30, 200]', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'hips_cm',
        s.preferredWeightUnit,
      );
      expect(range.min, 30);
      expect(range.max, 200);
    });

    test('thigh_cm returns [20, 100]', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'thigh_cm',
        s.preferredWeightUnit,
      );
      expect(range.min, 20);
      expect(range.max, 100);
    });

    test('arm_cm returns [15, 80]', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'arm_cm',
        s.preferredWeightUnit,
      );
      expect(range.min, 15);
      expect(range.max, 80);
    });
  });

  // ── S-010: lean_mass lbs boundary ────────────────────────────────────────

  group('validationRangeFor – lean_mass lbs boundary', () {
    test('435 is within lbs range [40, 440]', () async {
      final s = await _settingsLbs();
      final range = ProfileMeasurements.validationRangeFor(
        'lean_mass',
        s.preferredWeightUnit,
      );
      expect(435 >= range.min && 435 <= range.max, isTrue);
    });

    test('441 is above lbs max of 440', () async {
      final s = await _settingsLbs();
      final range = ProfileMeasurements.validationRangeFor(
        'lean_mass',
        s.preferredWeightUnit,
      );
      expect(441 > range.max, isTrue);
    });
  });

  // ── validationUnitLabel ───────────────────────────────────────────────────

  group('validationUnitLabel', () {
    test('bodyweight in kg mode returns "kg"', () async {
      final s = await _settingsKg();
      expect(
        ProfileMeasurements.validationUnitLabel(
          'bodyweight',
          s.preferredWeightUnit,
        ),
        'kg',
      );
    });

    test('bodyweight in lbs mode returns "lbs"', () async {
      final s = await _settingsLbs();
      expect(
        ProfileMeasurements.validationUnitLabel(
          'bodyweight',
          s.preferredWeightUnit,
        ),
        'lbs',
      );
    });

    test('lean_mass in lbs mode returns "lbs"', () async {
      final s = await _settingsLbs();
      expect(
        ProfileMeasurements.validationUnitLabel(
          'lean_mass',
          s.preferredWeightUnit,
        ),
        'lbs',
      );
    });

    test('height in cm mode returns "cm"', () async {
      final s = await _settingsKg();
      expect(
        ProfileMeasurements.validationUnitLabel(
          'height',
          s.preferredWeightUnit,
          heightUnit: s.preferredHeightUnit,
        ),
        'cm',
      );
    });

    test('height in ftin mode returns "ft in"', () async {
      final s = await _settingsKg();
      await s.setPreferredHeightUnit('ftin');
      expect(
        ProfileMeasurements.validationUnitLabel(
          'height',
          s.preferredWeightUnit,
          heightUnit: s.preferredHeightUnit,
        ),
        'ft in',
      );
    });

    test('body_fat_pct returns "%"', () async {
      final s = await _settingsKg();
      expect(
        ProfileMeasurements.validationUnitLabel(
          'body_fat_pct',
          s.preferredWeightUnit,
        ),
        '%',
      );
    });

    test('waist_cm returns "cm"', () async {
      final s = await _settingsKg();
      expect(
        ProfileMeasurements.validationUnitLabel(
          'waist_cm',
          s.preferredWeightUnit,
        ),
        'cm',
      );
    });
  });

  // ── S-007: Decimal truncation ─────────────────────────────────────────────

  group('decimal truncation to 1dp', () {
    double truncate1dp(double v) => (v * 10).truncate() / 10;

    test('80.456 truncates to 80.4', () {
      expect(truncate1dp(80.456), closeTo(80.4, 0.0001));
    });

    test('80.15 truncates to 80.1 (no rounding)', () {
      expect(truncate1dp(80.15), closeTo(80.1, 0.0001));
    });

    test('80.9 stays 80.9', () {
      expect(truncate1dp(80.9), closeTo(80.9, 0.0001));
    });

    test('80.0 stays 80.0', () {
      expect(truncate1dp(80.0), closeTo(80.0, 0.0001));
    });

    test('integer 80 stays 80.0', () {
      expect(truncate1dp(80), closeTo(80.0, 0.0001));
    });

    test('75.555 truncates to 75.5 (not 75.6)', () {
      expect(truncate1dp(75.555), closeTo(75.5, 0.0001));
    });
  });

  // ── Error message format ──────────────────────────────────────────────────

  group('validationRangeFor – boundary values pass/fail', () {
    test('bodyweight min (20 kg) is in range', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(20 >= range.min && 20 <= range.max, isTrue);
    });

    test('bodyweight max (300 kg) is in range', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'bodyweight',
        s.preferredWeightUnit,
      );
      expect(300 >= range.min && 300 <= range.max, isTrue);
    });

    test('body_fat_pct min (1) is in range', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'body_fat_pct',
        s.preferredWeightUnit,
      );
      expect(1 >= range.min && 1 <= range.max, isTrue);
    });

    test('body_fat_pct max (100) is in range', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'body_fat_pct',
        s.preferredWeightUnit,
      );
      expect(100 >= range.min && 100 <= range.max, isTrue);
    });

    test('arm_cm min (15) is in range', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'arm_cm',
        s.preferredWeightUnit,
      );
      expect(15 >= range.min && 15 <= range.max, isTrue);
    });

    test('arm_cm 14 is below min', () async {
      final s = await _settingsKg();
      final range = ProfileMeasurements.validationRangeFor(
        'arm_cm',
        s.preferredWeightUnit,
      );
      expect(14 < range.min, isTrue);
    });
  });
}
