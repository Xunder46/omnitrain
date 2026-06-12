import 'package:shared_preferences/shared_preferences.dart';

/// A service for managing simple key-value preferences.
///
/// This is abstracted to allow for mock implementations in tests.
abstract class PreferencesService {
  Future<void> init();
  int getHubOpenCount();
  Future<void> incrementHubOpenCount();
}

class PreferencesServiceImpl implements PreferencesService {
  static const _hubOpenCountKey = 'hub_open_count';
  late SharedPreferences _prefs;

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  int getHubOpenCount() {
    return _prefs.getInt(_hubOpenCountKey) ?? 0;
  }

  @override
  Future<void> incrementHubOpenCount() async {
    final currentCount = getHubOpenCount();
    await _prefs.setInt(_hubOpenCountKey, currentCount + 1);
  }
}
