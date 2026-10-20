/// Display names and labels for modalities
class ModalityDisplay {
  /// Map of modality keys to user-friendly display names
  static const Map<String, String> names = {
    'cardio_endurance': 'Cardio / Endurance',
    'resistance_lifting': 'Resistance / Lifting',
    'isometric_stretching': 'Isometric / Stretching',
    'sports': 'Sports',
  };

  /// Get display name for a modality
  /// Returns 'Free Training' for null modality
  static String getName(String? modality) {
    if (modality == null) return 'Free Training';
    return names[modality] ?? modality;
  }

  /// Get label for rounds based on modality context
  static String getRoundsLabel(String? modality) {
    switch (modality) {
      case 'sports':
        return 'Periods'; // periods, halves, quarters
      case 'cardio_endurance':
        return 'Intervals';
      default:
        return 'Rounds';
    }
  }

  /// The singular word for one round-kind entry. Sports says "Period" — the one
  /// word that fits a half, a quarter or a bout for any sport, built-in or
  /// custom — and every other modality says "Round".
  static String roundNoun(String? modality) =>
      modality == 'sports' ? 'Period' : 'Round';

  /// "3 rounds" / "1 period": a count of round-kind entries, lower case.
  static String roundCount(String? modality, int count) {
    final noun = roundNoun(modality).toLowerCase();
    return '$count $noun${count != 1 ? 's' : ''}';
  }
}
