/// Modality constants - functional classification of session types
/// Used for filtering, summaries, and progress grouping
library;

class Modality {
  // Primary home screen modalities
  static const String cardioEndurance = 'cardio_endurance';
  static const String resistanceLifting = 'resistance_lifting';
  static const String martialArts = 'martial_arts';
  static const String isometricStretching = 'isometric_stretching';
  static const String sports = 'sports';
  // Free training has no modality preset (null)

  // Legacy/additional modalities (kept for compatibility)
  static const String strengthResistance = 'strength_resistance';
  static const String skillTechnique = 'skill_technique';
  static const String conditioningMixed = 'conditioning_mixed';
  static const String mobilityFlexibility = 'mobility_flexibility';
  static const String recoveryRehab = 'recovery_rehab';
  static const String competitionMatch = 'competition_match';

  /// Maps modality keys to their corresponding SportCategory IDs.
  /// Used for exercise ranking - disciplines belong to categories, which map to modalities.
  /// Example: Running discipline (discipline-running) → category-cardio → cardio_endurance modality
  static const Map<String, String> modalityToCategoryId = {
    cardioEndurance: 'category-cardio',
    resistanceLifting: 'category-resistance',
    martialArts: 'category-martial-arts',
    isometricStretching: 'category-isometric',
    sports: 'category-sports',
  };

  static const List<String> primaryHomeTiles = [
    cardioEndurance,
    resistanceLifting,
    martialArts,
    isometricStretching,
    sports,
    // Note: Free Training = null modality
  ];

  static const List<String> all = [
    cardioEndurance,
    resistanceLifting,
    martialArts,
    isometricStretching,
    sports,
    strengthResistance,
    skillTechnique,
    conditioningMixed,
    mobilityFlexibility,
    recoveryRehab,
    competitionMatch,
  ];

  static String getDisplayName(String modality) {
    switch (modality) {
      case cardioEndurance:
        return 'Cardio / Endurance';
      case resistanceLifting:
        return 'Resistance / Lifting';
      case martialArts:
        return 'Martial Arts';
      case isometricStretching:
        return 'Isometric / Stretching';
      case sports:
        return 'Sports';
      case strengthResistance:
        return 'Strength / Resistance';
      case skillTechnique:
        return 'Skill / Technique';
      case conditioningMixed:
        return 'Conditioning / Mixed';
      case mobilityFlexibility:
        return 'Mobility / Flexibility';
      case recoveryRehab:
        return 'Recovery / Rehab';
      case competitionMatch:
        return 'Competition / Match';
      default:
        return modality;
    }
  }
}
