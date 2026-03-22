import 'package:flutter/foundation.dart';

import '../../core/constants/omni_theme.dart';
import '../../data/repositories/workout_repository.dart';

class SettingsState extends ChangeNotifier {
  static const String _themeKey = 'app_theme';

  final WorkoutRepository _repository;

  SettingsState(this._repository);

  AppTheme _appTheme = AppTheme.abyssalNeon;
  AppTheme get appTheme => _appTheme;

  Future<void> initialize() async {
    await _loadFromPrefs();
  }

  Future<void> setAppTheme(AppTheme theme) async {
    _appTheme = theme;
    await _repository.setPreferenceString(_themeKey, theme.name);
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

    notifyListeners();
  }
}
