import '../models/exercise_metric.dart';
import 'modality.dart';

/// Metabolic equivalents (MET) per section, D-13403. The one place the
/// intensity figures live; the active energy of a session is
/// (MET - 1) x body weight in kg x hours.
const Map<ExerciseSection, double> kActiveEnergyMets = {
  ExerciseSection.resistance: 3.5,
  ExerciseSection.cardio: 6.0,
  ExerciseSection.isometric: 3.0,
  ExerciseSection.sports: 6.0,
};

/// The section a modality id stands for, or null for any other value
/// (Free Training's null modality and the legacy ids), D-13413.
ExerciseSection? sectionForModality(String modality) {
  switch (modality) {
    case Modality.resistanceLifting:
      return ExerciseSection.resistance;
    case Modality.cardioEndurance:
      return ExerciseSection.cardio;
    case Modality.isometricStretching:
      return ExerciseSection.isometric;
    case Modality.sports:
      return ExerciseSection.sports;
    default:
      return null;
  }
}
