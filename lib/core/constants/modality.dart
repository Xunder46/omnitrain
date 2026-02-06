/// Modality constants - functional classification of session types
/// Used for filtering, summaries, and progress grouping

class Modality {
  static const String cardioEndurance = 'cardio_endurance';
  static const String strengthResistance = 'strength_resistance';
  static const String skillTechnique = 'skill_technique';
  static const String conditioningMixed = 'conditioning_mixed';
  static const String mobilityFlexibility = 'mobility_flexibility';
  static const String recoveryRehab = 'recovery_rehab';
  static const String competitionMatch = 'competition_match';

  static const List<String> all = [
    cardioEndurance,
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
