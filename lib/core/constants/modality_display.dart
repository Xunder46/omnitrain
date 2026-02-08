/// Display names and labels for modalities
class ModalityDisplay {
  /// Map of modality keys to user-friendly display names
  static const Map<String, String> names = {
    'cardio_endurance': 'Cardio / Endurance',
    'resistance_lifting': 'Resistance / Lifting',
    'martial_arts': 'Martial Arts',
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
      case 'martial_arts':
        return 'Rounds';
      case 'cardio_endurance':
        return 'Intervals';
      default:
        return 'Rounds';
    }
  }
}
