/// Modality configuration - maps session modalities to their metric requirements
class ModalityConfig {
  final String? primaryMetric;
  final List<String> secondaryMetrics;
  final List<String> optionalMetrics;
  final String defaultInputType;
  final String structure;
  final String effortKind;

  const ModalityConfig({
    required this.primaryMetric,
    this.secondaryMetrics = const [],
    this.optionalMetrics = const [],
    required this.defaultInputType,
    required this.structure,
    required this.effortKind,
  });

  /// Configuration map for all modalities
  static const Map<String?, ModalityConfig> configs = {
    // Cardio / Endurance - continuous time-based activity
    'cardio_endurance': ModalityConfig(
      primaryMetric: 'time',
      secondaryMetrics: ['distance', 'rounds'],
      optionalMetrics: [],
      defaultInputType: 'timer',
      structure: 'continuous',
      effortKind: 'timed',
    ),

    // Resistance / Lifting - set-based with reps and load
    'resistance_lifting': ModalityConfig(
      primaryMetric: 'reps',
      secondaryMetrics: ['sets'],
      optionalMetrics: ['load'],
      defaultInputType: 'reps_sets',
      structure: 'set_based',
      effortKind: 'set',
    ),

    // Martial Arts - round-based time tracking
    'martial_arts': ModalityConfig(
      primaryMetric: 'time',
      secondaryMetrics: ['rounds'],
      optionalMetrics: ['rpe'],
      defaultInputType: 'round_timer',
      structure: 'segmented',
      effortKind: 'round',
    ),

    // Isometric / Stretching - hold time tracking
    'isometric_stretching': ModalityConfig(
      primaryMetric: 'hold',
      secondaryMetrics: [],
      optionalMetrics: ['rpe'],
      defaultInputType: 'hold_timer',
      structure: 'hold_based',
      effortKind: 'drill',
    ),

    // Sports - segmented time with periods/halves/quarters
    'sports': ModalityConfig(
      primaryMetric: 'time',
      secondaryMetrics: ['rounds'], // "rounds" = periods/halves/quarters
      optionalMetrics: ['distance', 'rpe'],
      defaultInputType: 'segment_timer',
      structure: 'segmented',
      effortKind: 'round',
    ),

    // Free Training (null modality) - user chooses per exercise
    null: ModalityConfig(
      primaryMetric: null,
      secondaryMetrics: [],
      optionalMetrics: [],
      defaultInputType: 'chooser',
      structure: 'chooser',
      effortKind: 'set', // Default, will be overridden by user choice
    ),
  };

  /// Get configuration for a modality
  static ModalityConfig? forModality(String? modality) {
    return configs[modality];
  }

  /// Get all required metrics (primary + secondary)
  List<String> getRequiredMetrics() {
    if (primaryMetric == null) return [];
    return [primaryMetric!, ...secondaryMetrics];
  }

  /// Get all metrics (primary + secondary + optional)
  List<String> getAllMetrics() {
    if (primaryMetric == null) return [];
    return [primaryMetric!, ...secondaryMetrics, ...optionalMetrics];
  }

  /// Derive effort kind from chosen metric (for Free Training)
  static String effortKindFromMetric(String metric) {
    switch (metric) {
      case 'time':
        return 'timed';
      case 'hold':
        return 'drill';
      case 'reps':
      case 'sets':
      case 'load':
        return 'set';
      case 'rounds':
        return 'round';
      case 'distance':
        return 'timed'; // Distance usually paired with time
      default:
        return 'set'; // Default fallback
    }
  }

  /// Get display label for rounds based on modality
  static String getRoundsLabel(String? modality) {
    switch (modality) {
      case 'sports':
        return 'Periods'; // Can be periods, halves, quarters
      case 'martial_arts':
        return 'Rounds';
      case 'cardio_endurance':
        return 'Intervals';
      default:
        return 'Rounds';
    }
  }
}
