// filepath: test/helpers/fake_preferences_service.dart
import 'package:omnitrain/core/services/preferences_service.dart';

/// Test double for [PreferencesService].
///
/// In-memory implementation suitable for unit and widget tests that need
/// a `SettingsState` but should not touch real `shared_preferences`.
class FakePreferencesService implements PreferencesService {
  int _hubOpenCount = 0;

  @override
  Future<void> init() async {}

  @override
  int getHubOpenCount() => _hubOpenCount;

  @override
  Future<void> incrementHubOpenCount() async {
    _hubOpenCount += 1;
  }
}

/// Convenience factory used by tests that import this helper.
FakePreferencesService fakePreferencesService() => FakePreferencesService();
