/// Exercise capability constants
/// Defines what types of metrics an exercise can support
class ExerciseCapability {
  /// Continuous duration tracking (running, cycling, swimming)
  static const String time = 'time';

  /// Isometric hold duration (plank, wall sit, static holds)
  static const String hold = 'hold';

  /// Repetition counting
  static const String reps = 'reps';

  /// Set grouping
  static const String sets = 'sets';

  /// External weight or resistance
  static const String load = 'load';

  /// One side at a time; log both sides as a single combined set
  static const String bilateral = 'bilateral';

  /// Distance covered
  static const String distance = 'distance';

  /// Round or period based segments
  static const String rounds = 'rounds';

  /// All available capabilities
  static const List<String> all = [
    time,
    hold,
    reps,
    sets,
    load,
    bilateral,
    distance,
    rounds,
  ];

  /// Get display name for a capability
  static String getDisplayName(String capability) {
    switch (capability) {
      case time:
        return 'Time';
      case hold:
        return 'Hold Time';
      case reps:
        return 'Reps';
      case sets:
        return 'Sets';
      case load:
        return 'Load';
      case bilateral:
        return 'Bilateral';
      case distance:
        return 'Distance';
      case rounds:
        return 'Rounds';
      default:
        return capability;
    }
  }

  /// Get description for a capability
  static String getDescription(String capability) {
    switch (capability) {
      case time:
        return 'Continuous duration (running, cycling)';
      case hold:
        return 'Isometric contraction (plank, wall sit)';
      case reps:
      case sets:
      case load:
        return 'Repetitions with optional weight and set grouping';
      case bilateral:
        return 'One side at a time; log both sides as a single combined set';
      case distance:
        return 'Distance covered';
      case rounds:
        return 'Round or period based';
      default:
        return '';
    }
  }

  /// Get icon for a capability (Flutter icon names)
  static String getIconName(String capability) {
    switch (capability) {
      case time:
        return 'timer';
      case hold:
        return 'pause_circle';
      case reps:
        return 'repeat';
      case sets:
        return 'view_list';
      case load:
        return 'fitness_center';
      case bilateral:
        return 'swap_horiz';
      case distance:
        return 'straighten';
      case rounds:
        return 'replay';
      default:
        return 'help';
    }
  }
}
