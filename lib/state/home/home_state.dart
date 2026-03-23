import 'package:flutter/foundation.dart';
import '../../data/repositories/workout_repository.dart';

class HomeState extends ChangeNotifier {
  final WorkoutRepository _repository;

  bool _maintenanceHintSeen = false;

  HomeState(this._repository);

  bool get shouldShowMaintenanceHint => !_maintenanceHintSeen;

  Future<void> init() async {
    _maintenanceHintSeen = await _repository.getPreferenceBool(
      'hint_seen_maintenance',
    );
    notifyListeners();
  }

  Future<void> markMaintenanceHintSeen() async {
    if (_maintenanceHintSeen) return;
    _maintenanceHintSeen = true;
    notifyListeners();
    await _repository.setPreferenceBool('hint_seen_maintenance', true);
  }
}
