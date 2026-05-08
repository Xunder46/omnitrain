import 'package:flutter/foundation.dart';

import '../../core/constants/omni_theme.dart';
import '../../data/repositories/workout_repository.dart';

class SettingsState extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _preferredWeightUnitKey = 'preferred_weight_unit';
  static const String _preferredDistanceUnitKey = 'preferred_distance_unit';
  static const String _preferredStartOfWeekKey = 'preferred_start_of_week';
  static const String _showFeelingSurveyKey = 'show_feeling_survey';
  static const String _effortTimerSoundKey = 'effort_timer_sound';
  static const String _restPingIntervalKey = 'rest_ping_interval';
  static const String _restPingSoundKey = 'rest_ping_sound';

  static const List<String> validSoundIds = [
    'boxing_bell',
    'digital_buzzer',
    'soft_chime',
    'double_tap',
    'signal_tone',
  ];

  static const Map<String, String> soundDisplayNames = {
    'boxing_bell': 'Boxing Bell',
    'digital_buzzer': 'Digital Buzzer',
    'soft_chime': 'Soft Chime',
    'double_tap': 'Double Tap',
    'signal_tone': 'Signal Tone',
  };

  static const List<({int value, String label})> restPingIntervalOptions = [
    (value: 0, label: 'Off'),
    (value: 30, label: '30s'),
    (value: 45, label: '45s'),
    (value: 60, label: '1 min'),
    (value: 90, label: '1.5 min'),
    (value: 120, label: '2 min'),
    (value: 180, label: '3 min'),
  ];

  final WorkoutRepository _repository;

  SettingsState(this._repository);

  AppTheme _appTheme = AppTheme.abyssalNeon;
  String _preferredWeightUnit = 'kg';
  String _preferredDistanceUnit = 'km';
  String _startOfWeek = 'monday';
  bool _showFeelingSurvey = true;
  String _effortTimerSound = 'boxing_bell';
  int _restPingInterval = 0;
  String _restPingSound = 'soft_chime';

  AppTheme get appTheme => _appTheme;
  String get preferredWeightUnit => _preferredWeightUnit;
  String get preferredDistanceUnit => _preferredDistanceUnit;
  String get startOfWeek => _startOfWeek;
  bool get showFeelingSurvey => _showFeelingSurvey;
  String get effortTimerSound => _effortTimerSound;
  int get restPingInterval => _restPingInterval;
  String get restPingSound => _restPingSound;

  Future<void> initialize() async {
    await _loadFromPrefs();
  }

  Future<void> setAppTheme(AppTheme theme) async {
    _appTheme = theme;
    await _repository.setPreferenceString(_themeKey, theme.name);
    notifyListeners();
  }

  Future<void> setPreferredWeightUnit(String unit) async {
    final normalized = unit.toLowerCase().trim();
    _preferredWeightUnit = normalized == 'lb' || normalized == 'lbs'
        ? 'lbs'
        : 'kg';
    await _repository.setPreferenceString(
      _preferredWeightUnitKey,
      _preferredWeightUnit,
    );
    notifyListeners();
  }

  Future<void> setPreferredDistanceUnit(String unit) async {
    final normalized = unit.toLowerCase().trim();
    _preferredDistanceUnit =
        normalized == 'mile' || normalized == 'miles' || normalized == 'mi'
        ? 'miles'
        : 'km';
    await _repository.setPreferenceString(
      _preferredDistanceUnitKey,
      _preferredDistanceUnit,
    );
    notifyListeners();
  }

  Future<void> setStartOfWeek(String value) async {
    final normalized = value.toLowerCase().trim();
    _startOfWeek = normalized == 'sunday' || normalized == 'sun'
        ? 'sunday'
        : 'monday';
    await _repository.setPreferenceString(
      _preferredStartOfWeekKey,
      _startOfWeek,
    );
    notifyListeners();
  }

  Future<void> setShowFeelingSurvey(bool value) async {
    _showFeelingSurvey = value;
    await _repository.setPreferenceString(
      _showFeelingSurveyKey,
      value.toString(),
    );
    notifyListeners();
  }

  Future<void> setEffortTimerSound(String soundId) async {
    final v = validSoundIds.contains(soundId) ? soundId : 'boxing_bell';
    _effortTimerSound = v;
    await _repository.setPreferenceString(_effortTimerSoundKey, v);
    notifyListeners();
  }

  Future<void> setRestPingInterval(int seconds) async {
    final validValues = restPingIntervalOptions.map((o) => o.value).toList();
    final v = validValues.contains(seconds) ? seconds : 0;
    _restPingInterval = v;
    await _repository.setPreferenceString(_restPingIntervalKey, v.toString());
    notifyListeners();
  }

  Future<void> setRestPingSound(String soundId) async {
    final v = validSoundIds.contains(soundId) ? soundId : 'soft_chime';
    _restPingSound = v;
    await _repository.setPreferenceString(_restPingSoundKey, v);
    notifyListeners();
  }

  Future<void> _loadFromPrefs() async {
    final savedTheme = await _repository.getPreferenceString(_themeKey);
    if (savedTheme != null) {
      _appTheme = AppTheme.values.firstWhere(
        (t) => t.name == savedTheme,
        orElse: () => AppTheme.abyssalNeon,
      );
    }

    final savedWeightUnit = await _repository.getPreferenceString(
      _preferredWeightUnitKey,
      defaultValue: 'kg',
    );
    final normalized = savedWeightUnit?.toLowerCase().trim();
    _preferredWeightUnit = normalized == 'lb' || normalized == 'lbs'
        ? 'lbs'
        : 'kg';

    final savedDistanceUnit = await _repository.getPreferenceString(
      _preferredDistanceUnitKey,
      defaultValue: 'km',
    );
    final normalizedDistance = savedDistanceUnit?.toLowerCase().trim();
    _preferredDistanceUnit =
        normalizedDistance == 'mile' ||
            normalizedDistance == 'miles' ||
            normalizedDistance == 'mi'
        ? 'miles'
        : 'km';

    final savedStartOfWeek = await _repository.getPreferenceString(
      _preferredStartOfWeekKey,
      defaultValue: 'monday',
    );
    final normalizedSow = savedStartOfWeek?.toLowerCase().trim();
    _startOfWeek = normalizedSow == 'sunday' || normalizedSow == 'sun'
        ? 'sunday'
        : 'monday';

    final savedShowFeelingSurvey = await _repository.getPreferenceString(
      _showFeelingSurveyKey,
      defaultValue: 'true',
    );
    _showFeelingSurvey = savedShowFeelingSurvey != 'false';

    final savedEffortSound = await _repository.getPreferenceString(
      _effortTimerSoundKey,
    );
    _effortTimerSound =
        savedEffortSound != null && validSoundIds.contains(savedEffortSound)
        ? savedEffortSound
        : 'boxing_bell';

    final savedPingIntervalStr = await _repository.getPreferenceString(
      _restPingIntervalKey,
    );
    final parsedInterval = int.tryParse(savedPingIntervalStr ?? '');
    final validIntervalValues = restPingIntervalOptions
        .map((o) => o.value)
        .toList();
    _restPingInterval =
        parsedInterval != null && validIntervalValues.contains(parsedInterval)
        ? parsedInterval
        : 0;

    final savedRestSound = await _repository.getPreferenceString(
      _restPingSoundKey,
    );
    _restPingSound =
        savedRestSound != null && validSoundIds.contains(savedRestSound)
        ? savedRestSound
        : 'soft_chime';

    notifyListeners();
  }
}
