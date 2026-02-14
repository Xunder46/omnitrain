import 'package:flutter/foundation.dart';

class HomeState extends ChangeNotifier {
  bool _maintenanceHintSeen = false;

  bool get shouldShowMaintenanceHint => !_maintenanceHintSeen;

  void markMaintenanceHintSeen() {
    if (_maintenanceHintSeen) return;
    _maintenanceHintSeen = true;
    notifyListeners();
  }
}
