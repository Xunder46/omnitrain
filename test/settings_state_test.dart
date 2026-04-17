import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';

void main() {
  test('SettingsState loads default theme when nothing is saved', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository);
    await settingsState.initialize();

    expect(settingsState.appTheme, AppTheme.abyssalNeon);
  });

  test('AppTheme only exposes the five shipping themes', () {
    expect(
      AppTheme.values.map((theme) => theme.name).toList(),
      equals([
        'abyssalNeon',
        'forgeEmber',
        'obsidianVolt',
        'voidPulse',
        'crimsonDojo',
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

  test('Void Pulse uses a visible violet atmospheric gradient', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.voidPulse);

    expect(colors.backgroundTop, const Color(0xFF120F24));
    expect(colors.backgroundBottom, const Color(0xFF0A071A));
  });

  test('Crimson Dojo uses a lifted sheet surface for tag contrast', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.crimsonDojo);

    expect(colors.surface, const Color(0xFF3A1A16));
  });
}
