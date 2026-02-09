/// Application-wide state management
class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    // Perform any app-wide initialization here
    _isInitialized = true;
  }

  void reset() {
    _isInitialized = false;
  }
}
