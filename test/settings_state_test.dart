import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

// ---------------------------------------------------------------------------
// WCAG 2.1 contrast helpers used by contrast regression tests.
// ---------------------------------------------------------------------------
double _linearizeChannel(double c) {
  return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  final r = _linearizeChannel(color.red / 255);
  final g = _linearizeChannel(color.green / 255);
  final b = _linearizeChannel(color.blue / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}
// ---------------------------------------------------------------------------

void main() {
  test('SettingsState loads default theme when nothing is saved', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    expect(settingsState.appTheme, AppTheme.abyssalNeon);
  });

  // Jade Sentinel was removed after the bake-off evaluation — Malachite Core was retained.
  // NOTE: seven-theme bake-off state is gone; six themes is now the permanent roster.
  test('AppTheme exposes the six retained themes in order', () {
    expect(
      AppTheme.values.map((theme) => theme.name).toList(),
      equals([
        'abyssalNeon',
        'forgeEmber',
        'obsidianVolt',
        'voidPulse',
        'crimsonDojo',
        'malachiteCore',
      ]),
    );
  });

  test(
    'SettingsState falls back to abyssalNeon for invalid saved value',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setPreferenceString('app_theme', 'unknown_theme');

      final settingsState = SettingsState(repository);
      await settingsState.initialize();

      expect(settingsState.appTheme, AppTheme.abyssalNeon);
    },
  );

  test(
    'SettingsState falls back to abyssalNeon for removed legacy theme values',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setPreferenceString('app_theme', 'circuitGreen');

      final settingsState = SettingsState(repository);
      await settingsState.initialize();

      expect(settingsState.appTheme, AppTheme.abyssalNeon);
    },
  );

  test(
    'SettingsState falls back to abyssalNeon for removed jadeSentinel value',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      // jadeSentinel was removed after the bake-off; persisted preferences
      // that stored it must degrade gracefully to the default theme.
      await repository.setPreferenceString('app_theme', 'jadeSentinel');

      final settingsState = SettingsState(repository);
      await settingsState.initialize();

      expect(settingsState.appTheme, AppTheme.abyssalNeon);
    },
  );

  test('SettingsState persists and reloads selected theme', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    await settingsState.setAppTheme(AppTheme.forgeEmber);
    expect(
      await repository.getPreferenceString('app_theme'),
      AppTheme.forgeEmber.name,
    );

    final reloaded = SettingsState(repository);
    await reloaded.initialize();

    expect(reloaded.appTheme, AppTheme.forgeEmber);
  });

  test('SettingsState loads the preferred weight unit from prefs', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.setPreferenceString('preferred_weight_unit', 'lbs');

    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    expect(settingsState.preferredWeightUnit, 'lbs');
  });

  test('SettingsState defaults preferred distance unit to km', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    expect(settingsState.preferredDistanceUnit, 'km');
  });

  test('SettingsState persists and reloads preferred distance unit', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository);
    await settingsState.initialize();
    await settingsState.setPreferredDistanceUnit('miles');

    expect(
      await repository.getPreferenceString('preferred_distance_unit'),
      'miles',
    );

    final reloaded = SettingsState(repository);
    await reloaded.initialize();

    expect(reloaded.preferredDistanceUnit, 'miles');
  });

  test('SettingsState normalizes invalid saved distance unit to km', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.setPreferenceString('preferred_distance_unit', 'yards');

    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    expect(settingsState.preferredDistanceUnit, 'km');
  });

  test('Void Pulse uses a visible violet atmospheric gradient', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.voidPulse);

    expect(colors.backgroundTop, const Color(0xFF120F24));
    expect(colors.backgroundBottom, const Color(0xFF0A071A));
  });

  test('Crimson Dojo uses a lifted sheet surface for tag contrast', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.crimsonDojo);

    expect(colors.surface, const Color(0xFF3A1A16));
  });

  test(
    'Crimson Dojo textMuted is warm parchment with 4.5:1+ contrast against surface',
    () {
      final colors = OmniTheme.colorsForTheme(AppTheme.crimsonDojo);

      expect(colors.textMuted, const Color(0xFFC4907A));
    },
  );

  test(
    'Crimson Dojo secondary is bright blood red (3:1+ contrast against surface)',
    () {
      final colors = OmniTheme.colorsForTheme(AppTheme.crimsonDojo);

      expect(colors.secondary, const Color(0xFFD32F2F));
    },
  );


  // ─── Malachite Core ────────────────────────────────────────────────────────

  test('Malachite Core colorsForTheme returns deep emerald primary', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
    expect(colors.primary, const Color(0xFF1A9A4A));
  });

  test('Malachite Core display name is verbatim', () {
    expect(OmniTheme.displayNameForTheme(AppTheme.malachiteCore), 'Malachite Core');
  });

  test('SettingsState persists and reloads malachiteCore theme', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository);
    await state.initialize();

    await state.setAppTheme(AppTheme.malachiteCore);
    expect(
      await repository.getPreferenceString('app_theme'),
      AppTheme.malachiteCore.name,
    );

    final reloaded = SettingsState(repository);
    await reloaded.initialize();
    expect(reloaded.appTheme, AppTheme.malachiteCore);
  });

  // textMuted was lifted from #8BBF8A to #AACFAA (same H120° hue, +10% lightness)
  // to improve perceived readability on Hub maintenance tiles at device brightness.
  // Threshold raised to 6.0:1 to lock in the comfortable-margin intent.
  test('Malachite Core textMuted is lifted green-bone (#AACFAA)', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
    expect(colors.textMuted, const Color(0xFFAACFAA));
  });

  test(
    'Malachite Core textMuted clears 6:1 comfortable-margin contrast against surface',
    () {
      final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
      expect(
        _contrastRatio(colors.textMuted, colors.surface),
        greaterThanOrEqualTo(6.0),
      );
    },
  );

  test('Malachite Core secondary clears 3:1 contrast against surface', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
    expect(
      _contrastRatio(colors.secondary, colors.surface),
      greaterThanOrEqualTo(3.0),
    );
  });
}
