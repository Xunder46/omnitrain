/// Modality configuration - maps session modalities to their metric requirements and exercise ranking.
/// Supports both UI (metric tracking) and data layer (exercise ranking by capability affinity).
/// Pure Dart - no platform dependencies.
library;

/// Threshold score for determining "Recommended" exercises during exercise selection.
/// Exercises with relevanceScore >= this threshold are considered well-suited for the modality.
/// Scoring range is 0-100. A threshold of 50.0 means:
/// - Exercise has good discipline affinity + primary capability match, OR
/// - Multiple secondary capabilities + affinity bonus
const double RECOMMENDED_SCORE_THRESHOLD = 50.0;

class ModalityConfig {
  final String? primaryMetric;
  final List<String> secondaryMetrics;
  final List<String> optionalMetrics;
  final String defaultInputType;
  final String structure;
  final String effortKind;

  // Exercise ranking fields
  final String? categoryId; // SportCategory.id for discipline affinity scoring
  final List<String> primaryCapabilities; // Core capabilities defining this modality
  final List<String> secondaryCapabilities; // Bonus/optional capabilities
  final List<String> antiCapabilities; // Signals poor fit for this modality

  const ModalityConfig({
    required this.primaryMetric,
    this.secondaryMetrics = const [],
    this.optionalMetrics = const [],
    required this.defaultInputType,
    required this.structure,
    required this.effortKind,
    // Ranking fields
    this.categoryId,
    this.primaryCapabilities = const [],
    this.secondaryCapabilities = const [],
    this.antiCapabilities = const [],
  });

  /// Configuration map for all modalities
  static const Map<String?, ModalityConfig> configs = {
    // Cardio / Endurance - continuous time-based activity
    // Primary exercises: Running, cycling, swimming, rowing
    // Discipline category: category-cardio
    'cardio_endurance': ModalityConfig(
      primaryMetric: 'time',
      secondaryMetrics: ['distance', 'rounds'],
      optionalMetrics: [],
      defaultInputType: 'timer',
      structure: 'continuous',
      effortKind: 'timed',
      categoryId: 'category-cardio',
      primaryCapabilities: ['time', 'distance'],
      secondaryCapabilities: ['rounds'],
      antiCapabilities: ['load', 'hold'],
    ),

    // Resistance / Lifting - set-based with reps and load
    // Primary exercises: Bodybuilding, powerlifting, weightlifting
    // Discipline category: category-resistance
    'resistance_lifting': ModalityConfig(
      primaryMetric: 'reps',
      secondaryMetrics: ['sets'],
      optionalMetrics: ['load'],
      defaultInputType: 'reps_sets',
      structure: 'set_based',
      effortKind: 'set',
      categoryId: 'category-resistance',
      primaryCapabilities: ['reps', 'sets', 'load'],
      secondaryCapabilities: ['time'],
      antiCapabilities: ['distance', 'rounds', 'hold'],
    ),

    // Martial Arts - round-based time tracking
    // Primary exercises: Boxing, BJJ, Muay Thai, wrestling
    // Discipline category: category-martial-arts
    'martial_arts': ModalityConfig(
      primaryMetric: 'time',
      secondaryMetrics: ['rounds'],
      optionalMetrics: ['rpe'],
      defaultInputType: 'round_timer',
      structure: 'segmented',
      effortKind: 'round',
      categoryId: 'category-martial-arts',
      primaryCapabilities: ['time', 'rounds'],
      secondaryCapabilities: [],
      antiCapabilities: ['load', 'hold', 'distance'],
    ),

    // Isometric / Stretching - hold time tracking
    // Primary exercises: Yoga, static holds, flexibility work
    // Discipline category: category-isometric
    'isometric_stretching': ModalityConfig(
      primaryMetric: 'hold',
      secondaryMetrics: [],
      optionalMetrics: ['rpe'],
      defaultInputType: 'hold_timer',
      structure: 'hold_based',
      effortKind: 'drill',
      categoryId: 'category-isometric',
      primaryCapabilities: ['hold', 'time'],
      secondaryCapabilities: ['sets'],
      antiCapabilities: ['load', 'distance', 'rounds'],
    ),

    // Sports - segmented time with periods/halves/quarters
    // Primary exercises: Soccer, basketball, team sports
    // Discipline category: category-sports
    'sports': ModalityConfig(
      primaryMetric: 'time',
      secondaryMetrics: ['rounds'], // "rounds" = periods/halves/quarters
      optionalMetrics: ['distance', 'rpe'],
      defaultInputType: 'segment_timer',
      structure: 'segmented',
      effortKind: 'round',
      categoryId: 'category-sports',
      primaryCapabilities: ['time', 'rounds'],
      secondaryCapabilities: ['distance'],
      antiCapabilities: ['load', 'hold'],
    ),

    // Free Training (null modality) - user chooses per exercise
    null: ModalityConfig(
      primaryMetric: null,
      secondaryMetrics: [],
      optionalMetrics: [],
      defaultInputType: 'chooser',
      structure: 'chooser',
      effortKind: 'set', // Default, will be overridden by user choice
      categoryId: null,
      primaryCapabilities: [],
      secondaryCapabilities: [],
      antiCapabilities: [],
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

  /// Calculate exercise relevance score for this modality (0-100).
  /// Scoring breakdown:
  /// - Discipline affinity (0-40): Exercise's category matches this modality's category
  /// - Primary capability match (0-30): Fraction of primary capabilities matched
  /// - Secondary capability bonus (0-10): Fraction of secondary capabilities matched
  /// - Isometric nature bonus (0-15): Special recognition for isometric exercises in isometric modalities
  /// - Anti-capability penalty (0 to -20): Fraction of anti-capabilities present
  /// - No-overlap penalty (0 or -10): Zero primary matches AND different category
  ///
  /// Final score is clamped to [0, 100].
  double calculateRelevanceScore({
    required List<String> exerciseCapabilities,
    required String? exerciseCategoryId,
  }) {
    double score = 0.0;

    // 1. Discipline affinity (strongest signal): 0-40 points
    if (exerciseCategoryId != null && exerciseCategoryId == categoryId) {
      score += 40.0;
    }

    // 2. Primary capability match: 0-30 points
    final primaryMatches = primaryCapabilities
        .where((cap) => exerciseCapabilities.contains(cap))
        .length;
    if (primaryCapabilities.isNotEmpty) {
      score += (primaryMatches / primaryCapabilities.length) * 30.0;
    }

    // 3. Secondary capability bonus: 0-10 points
    if (secondaryCapabilities.isNotEmpty) {
      final secondaryMatches = secondaryCapabilities
          .where((cap) => exerciseCapabilities.contains(cap))
          .length;
      score += (secondaryMatches / secondaryCapabilities.length) * 10.0;
    }

    // 4. Isometric nature bonus: 0-15 points
    // Special recognition for isometric exercises (hold + time) in isometric_stretching modality
    // This allows cross-category isometric exercises (e.g., calisthenics planks) to score well
    if (primaryCapabilities.contains('hold') && 
        exerciseCapabilities.contains('hold') && 
        exerciseCapabilities.contains('time')) {
      score += 15.0;
    }

    // 5. Anti-capability penalty: 0 to -20 points
    if (antiCapabilities.isNotEmpty) {
      final antiMatches = antiCapabilities
          .where((cap) => exerciseCapabilities.contains(cap))
          .length;
      score -= (antiMatches / antiCapabilities.length) * 20.0;
    }

    // 6. No-overlap penalty: 0 or -10 points
    // If no primary capabilities match and it doesn't belong to the category, it's a bad fit
    if (primaryMatches == 0 && exerciseCategoryId != categoryId) {
      score -= 10.0;
    }

    // Clamp to [0, 100] range
    return score.clamp(0.0, 100.0);
  }

  /// Determine if an exercise is recommended (score >= 50.0)
  bool isRecommended({
    required List<String> exerciseCapabilities,
    required String? exerciseCategoryId,
  }) {
    return calculateRelevanceScore(
      exerciseCapabilities: exerciseCapabilities,
      exerciseCategoryId: exerciseCategoryId,
    ) >= 50.0;
  }
}
