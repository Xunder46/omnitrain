// filepath: lib/core/services/health_modality_mapper.dart
//
// Modality → platform activity kind mapping for the health integration.

import '../constants/health_constants.dart';
import '../constants/modality.dart';

/// Maps a session modality to the app-owned activity kind written to the
/// platform health store.
///
/// Modalities are broader than workout types (cardio covers running,
/// cycling, and rowing alike), so the mapping stays deliberately coarse:
/// specificity the app does not have is not invented. Anything
/// unrecognised — including the null modality of Free Training — resolves
/// to [HealthActivityKind.other], which the gateway writes as the generic
/// workout type without ever throwing (S-007).
HealthActivityKind mapModalityToActivityKind(String? modality) {
  switch (modality) {
    case Modality.resistanceLifting:
    case Modality.strengthResistance:
      return HealthActivityKind.strength;
    case Modality.cardioEndurance:
      return HealthActivityKind.cardio;
    case Modality.isometricStretching:
    case Modality.mobilityFlexibility:
    case Modality.recoveryRehab:
      return HealthActivityKind.flexibility;
    case Modality.sports:
    case Modality.competitionMatch:
    case Modality.skillTechnique:
      return HealthActivityKind.sport;
    case Modality.conditioningMixed:
      return HealthActivityKind.conditioning;
    default:
      return HealthActivityKind.other;
  }
}
