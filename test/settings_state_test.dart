import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'helpers/fake_preferences_service.dart';

// ---------------------------------------------------------------------------
// WCAG 2.1 contrast helpers used by contrast regression tests.
// ---------------------------------------------------------------------------
double _linearizeChannel(double c) {
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
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

    final settingsState = SettingsState(repository, fakePreferencesService());
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

      final settingsState = SettingsState(repository, fakePreferencesService());
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

      final settingsState = SettingsState(repository, fakePreferencesService());
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

      final settingsState = SettingsState(repository, fakePreferencesService());
      await settingsState.initialize();

      expect(settingsState.appTheme, AppTheme.abyssalNeon);
    },
  );

  test('SettingsState persists and reloads selected theme', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();

    await settingsState.setAppTheme(AppTheme.forgeEmber);
    expect(
      await repository.getPreferenceString('app_theme'),
      AppTheme.forgeEmber.name,
    );

    final reloaded = SettingsState(repository, fakePreferencesService());
    await reloaded.initialize();

    expect(reloaded.appTheme, AppTheme.forgeEmber);
  });

  test('SettingsState loads the preferred weight unit from prefs', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.setPreferenceString('preferred_weight_unit', 'lbs');

    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();

    expect(settingsState.preferredWeightUnit, 'lbs');
  });

  test('SettingsState defaults preferred distance unit to km', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();

    expect(settingsState.preferredDistanceUnit, 'km');
  });

  test('SettingsState persists and reloads preferred distance unit', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();
    await settingsState.setPreferredDistanceUnit('miles');

    expect(
      await repository.getPreferenceString('preferred_distance_unit'),
      'miles',
    );

    final reloaded = SettingsState(repository, fakePreferencesService());
    await reloaded.initialize();

    expect(reloaded.preferredDistanceUnit, 'miles');
  });

  // ─── Height unit preference — defaults, persistence, normalization ─────

  test('SettingsState defaults preferred height unit to cm', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();

    expect(settingsState.preferredHeightUnit, 'cm');
  });

  test(
    'SettingsState persists and reloads preferred height unit (ftin)',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final settingsState = SettingsState(repository, fakePreferencesService());
      await settingsState.initialize();
      await settingsState.setPreferredHeightUnit('ftin');

      expect(
        await repository.getPreferenceString('preferred_height_unit'),
        'ftin',
      );

      final reloaded = SettingsState(repository, fakePreferencesService());
      await reloaded.initialize();

      expect(reloaded.preferredHeightUnit, 'ftin');
    },
  );

  test(
    'SettingsState normalizes invalid stored height unit to cm',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setPreferenceString(
        'preferred_height_unit',
        'inches',
      );

      final settingsState = SettingsState(repository, fakePreferencesService());
      await settingsState.initialize();

      expect(settingsState.preferredHeightUnit, 'cm');
    },
  );

  test(
    'setPreferredHeightUnit normalizes unknown values to cm',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final settingsState = SettingsState(repository, fakePreferencesService());
      await settingsState.initialize();
      await settingsState.setPreferredHeightUnit('something_else');

      expect(settingsState.preferredHeightUnit, 'cm');
    },
  );

  test(
    'setPreferredHeightUnit normalizes FTIN (uppercase) to ftin',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final settingsState = SettingsState(repository, fakePreferencesService());
      await settingsState.initialize();
      await settingsState.setPreferredHeightUnit('FTIN');

      expect(settingsState.preferredHeightUnit, 'ftin');
    },
  );

  test('SettingsState defaults feeling survey to enabled', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();

    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();

    expect(settingsState.showFeelingSurvey, isTrue);
  });

  test(
    'SettingsState persists and reloads feeling survey preference',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final settingsState = SettingsState(repository, fakePreferencesService());
      await settingsState.initialize();
      await settingsState.setShowFeelingSurvey(false);

      expect(
        await repository.getPreferenceString('show_feeling_survey'),
        'false',
      );

      final reloaded = SettingsState(repository, fakePreferencesService());
      await reloaded.initialize();

      expect(reloaded.showFeelingSurvey, isFalse);
    },
  );

  test('SettingsState normalizes invalid saved distance unit to km', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    await repository.setPreferenceString('preferred_distance_unit', 'yards');

    final settingsState = SettingsState(repository, fakePreferencesService());
    await settingsState.initialize();

    expect(settingsState.preferredDistanceUnit, 'km');
  });

  test('Void Pulse uses a visible violet atmospheric gradient', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.voidPulse);

    expect(colors.backgroundTop, const Color(0xFF221C40));
    expect(colors.backgroundBottom, const Color(0xFF110D26));
  });

  test('Crimson Dojo uses a lifted sheet surface for tag contrast', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.crimsonDojo);

    expect(colors.surface, const Color(0xFF3A1A16));
  });

  test('Crimson Dojo textMuted is darker warm metadata tone', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.crimsonDojo);

    expect(colors.textMuted, const Color(0xFFC29380));
  });

  test(
    'Crimson Dojo secondary is bright blood red (3:1+ contrast against surface)',
    () {
      final colors = OmniTheme.colorsForTheme(AppTheme.crimsonDojo);

      expect(colors.secondary, const Color(0xFFD32F2F));
    },
  );

  // ─── Malachite Core ────────────────────────────────────────────────────────

  test('Malachite Core colorsForTheme returns brighter emerald primary', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
    expect(colors.primary, const Color(0xFF24B85A));
  });

  test('Malachite Core display name is verbatim', () {
    expect(
      OmniTheme.displayNameForTheme(AppTheme.malachiteCore),
      'Malachite Core',
    );
  });

  test('SettingsState persists and reloads malachiteCore theme', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();

    await state.setAppTheme(AppTheme.malachiteCore);
    expect(
      await repository.getPreferenceString('app_theme'),
      AppTheme.malachiteCore.name,
    );

    final reloaded = SettingsState(repository, fakePreferencesService());
    await reloaded.initialize();
    expect(reloaded.appTheme, AppTheme.malachiteCore);
  });

  // Phase 1B emphasis-tier retune darkens muted text to strengthen hierarchy.
  test('Malachite Core textMuted is darker metadata green (#7FAA7F)', () {
    final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
    expect(colors.textMuted, const Color(0xFF7FAA7F));
  });

  test(
    'Malachite Core textMuted contrast is verified by palette contract',
    () {
      // D-15: Re-pinned honestly at 5.5 per product ruling.
      // textMuted vs surface fell from 6.29 to 5.51 because Item 3 lightened
      // the surface while D-4 deliberately left textMuted alone. 5.51 clears
      // WCAG AA with margin; the old 6.0 was a self-imposed comfort bar.
      // This test remains as a sanity check complementing check 4 of the
      // palette_legibility_contract_test.dart.
      final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
      expect(
        _contrastRatio(colors.textMuted, colors.surface),
        greaterThanOrEqualTo(5.5),
      );
    },
  );

  test('Malachite Core secondary contrast is verified by palette contract', () {
    // D-16: Re-pinned at 3.0 per product ruling.
    // Malachite Core's secondary (#10863E per D-14) sits at 3.11:1 vs surface.
    // Contrast thresholds for secondary vs surface are covered by the
    // authoritative palette_legibility_contract_test.dart (check 8), which applies
    // to all themes uniformly. This test remains as a sanity check that
    // the secondary color maintains design-level contrast.
    final colors = OmniTheme.colorsForTheme(AppTheme.malachiteCore);
    final contrast = _contrastRatio(colors.secondary, colors.surface);
    expect(contrast, greaterThanOrEqualTo(3.0));
  });

  // ─── Startup theme adoption ───────────────────────────────────────────────

  group('readPersistedTheme', () {
    test('returns the saved theme without constructing a SettingsState', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();

      final settings = SettingsState(repo, fakePreferencesService());
      await settings.initialize();
      await settings.setAppTheme(AppTheme.crimsonDojo);

      // The startup path reads through this before any SettingsState exists,
      // so it must resolve the same key and value the state writes.
      expect(
        await SettingsState.readPersistedTheme(repo),
        AppTheme.crimsonDojo,
      );
    });

    test('falls back to the canonical theme when nothing is saved', () async {
      final repo = MockWorkoutRepository();
      await repo.initialize();

      expect(
        await SettingsState.readPersistedTheme(repo),
        AppTheme.abyssalNeon,
      );
    });
  });

  // ─── Sound preferences — defaults ─────────────────────────────────────────

  test('SettingsState defaults effortTimerSound to boxing_bell', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    expect(state.effortTimerSound, 'boxing_bell');
  });

  test('SettingsState defaults restPingInterval to 0 (Off)', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    expect(state.restPingInterval, 0);
  });

  test('SettingsState defaults restPingSound to soft_chime', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    expect(state.restPingSound, 'soft_chime');
  });

  // ─── Sound preferences — set/get round-trips ──────────────────────────────

  test('SettingsState persists and reloads effortTimerSound', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    await state.setEffortTimerSound('digital_buzzer');
    expect(state.effortTimerSound, 'digital_buzzer');

    final reloaded = SettingsState(repository, fakePreferencesService());
    await reloaded.initialize();
    expect(reloaded.effortTimerSound, 'digital_buzzer');
  });

  test('SettingsState persists and reloads restPingInterval', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    await state.setRestPingInterval(60);
    expect(state.restPingInterval, 60);

    final reloaded = SettingsState(repository, fakePreferencesService());
    await reloaded.initialize();
    expect(reloaded.restPingInterval, 60);
  });

  test('SettingsState persists and reloads restPingSound', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    await state.setRestPingSound('signal_tone');
    expect(state.restPingSound, 'signal_tone');

    final reloaded = SettingsState(repository, fakePreferencesService());
    await reloaded.initialize();
    expect(reloaded.restPingSound, 'signal_tone');
  });

  // ─── Sound preferences — validation / fallback ────────────────────────────

  test(
    'setEffortTimerSound with invalid id falls back to boxing_bell',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = SettingsState(repository, fakePreferencesService());
      await state.initialize();
      await state.setEffortTimerSound('not_a_real_sound');
      expect(state.effortTimerSound, 'boxing_bell');
    },
  );

  test(
    'SettingsState falls back effortTimerSound to boxing_bell on invalid stored value',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setPreferenceString('effort_timer_sound', 'garbage');
      final state = SettingsState(repository, fakePreferencesService());
      await state.initialize();
      expect(state.effortTimerSound, 'boxing_bell');
    },
  );

  test('setRestPingInterval with invalid value falls back to 0', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    await state.setRestPingInterval(999);
    expect(state.restPingInterval, 0);
  });

  test(
    'SettingsState falls back restPingInterval to 0 on invalid stored value',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setPreferenceString(
        'rest_ping_interval',
        'not_a_number',
      );
      final state = SettingsState(repository, fakePreferencesService());
      await state.initialize();
      expect(state.restPingInterval, 0);
    },
  );

  test('setRestPingSound with invalid id falls back to soft_chime', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();
    await state.setRestPingSound('not_a_real_sound');
    expect(state.restPingSound, 'soft_chime');
  });

  test(
    'SettingsState falls back restPingSound to soft_chime on invalid stored value',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      await repository.setPreferenceString('rest_ping_sound', 'garbage');
      final state = SettingsState(repository, fakePreferencesService());
      await state.initialize();
      expect(state.restPingSound, 'soft_chime');
    },
  );

  // ─── Sound preferences — static metadata ──────────────────────────────────

  test('SettingsState.validSoundIds contains exactly 5 entries', () {
    expect(SettingsState.validSoundIds.length, 5);
    expect(
      SettingsState.validSoundIds,
      containsAll([
        'boxing_bell',
        'digital_buzzer',
        'soft_chime',
        'double_tap',
        'signal_tone',
      ]),
    );
  });

  test('SettingsState.restPingIntervalOptions contains exactly 7 entries', () {
    expect(SettingsState.restPingIntervalOptions.length, 7);
    expect(
      SettingsState.restPingIntervalOptions.map((o) => o.value),
      containsAll([0, 30, 45, 60, 90, 120, 180]),
    );
  });

  test(
    'SettingsState.soundDisplayNames has an entry for each validSoundId',
    () {
      for (final id in SettingsState.validSoundIds) {
        expect(
          SettingsState.soundDisplayNames.containsKey(id),
          isTrue,
          reason: 'Missing display name for sound ID: $id',
        );
      }
    },
  );

  test('SettingsState defaults notificationPermissionAsked to false', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();

    expect(state.notificationPermissionAsked, isFalse);
  });

  test(
    'SettingsState persists and reloads notificationPermissionAsked',
    () async {
      final repository = MockWorkoutRepository();
      await repository.initialize();
      final state = SettingsState(repository, fakePreferencesService());
      await state.initialize();

      await state.setNotificationPermissionAsked();
      expect(state.notificationPermissionAsked, isTrue);

      final reloaded = SettingsState(repository, fakePreferencesService());
      await reloaded.initialize();
      expect(reloaded.notificationPermissionAsked, isTrue);
    },
  );

  test('setters call notifyListeners', () async {
    final repository = MockWorkoutRepository();
    await repository.initialize();
    final state = SettingsState(repository, fakePreferencesService());
    await state.initialize();

    var notifyCount = 0;
    state.addListener(() => notifyCount++);

    await state.setEffortTimerSound('soft_chime');
    await state.setRestPingInterval(60);
    await state.setRestPingSound('boxing_bell');

    expect(notifyCount, 3);
  });
}
