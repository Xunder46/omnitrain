import 'package:flutter/foundation.dart';

import '../../core/constants/omni_theme.dart';
import '../../data/repositories/workout_repository.dart';

class SettingsState extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _preferredWeightUnitKey = 'preferred_weight_unit';
  static const String _preferredDistanceUnitKey = 'preferred_distance_unit';

  final WorkoutRepository _repository;

  SettingsState(this._repository);

  AppTheme _appTheme = AppTheme.abyssalNeon;
  String _preferredWeightUnit = 'kg';
  String _preferredDistanceUnit = 'km';

  AppTheme get appTheme => _appTheme;
  String get preferredWeightUnit => _preferredWeightUnit;
  String get preferredDistanceUnit => _preferredDistanceUnit;

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

    notifyListeners();
  }
}
