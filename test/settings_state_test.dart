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
}
