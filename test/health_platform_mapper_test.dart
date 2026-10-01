// filepath: test/health_platform_mapper_test.dart
//
// Scenario coverage for the platform health integration plan
// (`docs/plans/2026-07-13-04-pr3-platform-health-integration-plan.md`):
//
//   * S-001 / S-002 — a completed session's modality resolves to a
//     deterministic activity type before the platform write.
//   * S-007 — an unmapped modality falls back to the generic type
//     instead of throwing.
//
// The plugin-level assertions at the bottom guard the single rewrite
// hazard this codebase cannot catch at runtime on the host: the
// `health` package validates activity types per platform and throws
// `HealthException` for a type outside the current platform's set, so
// iOS-only / Android-only names must never be crossed over.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/health_constants.dart';
import 'package:omnitrain/core/constants/modality.dart';
import 'package:omnitrain/core/services/health_modality_mapper.dart';
import 'package:omnitrain/core/services/health_platform_gateway_io.dart'
    show pluginActivityTypeFor;

void main() {
  group('mapModalityToActivityKind', () {
    const expectations = <String, HealthActivityKind>{
      Modality.resistanceLifting: HealthActivityKind.strength,
      Modality.strengthResistance: HealthActivityKind.strength,
      Modality.cardioEndurance: HealthActivityKind.cardio,
      Modality.isometricStretching: HealthActivityKind.flexibility,
      Modality.mobilityFlexibility: HealthActivityKind.flexibility,
      Modality.recoveryRehab: HealthActivityKind.flexibility,
      Modality.sports: HealthActivityKind.sport,
      Modality.competitionMatch: HealthActivityKind.sport,
      Modality.skillTechnique: HealthActivityKind.sport,
      Modality.conditioningMixed: HealthActivityKind.conditioning,
    };

    test('has an expectation for every seeded modality', () {
      for (final modality in Modality.all) {
        expect(
          expectations.containsKey(modality),
          isTrue,
          reason: 'No mapping expectation recorded for "$modality"',
        );
      }
    });

    test('maps every seeded modality to its expected kind', () {
      for (final entry in expectations.entries) {
        expect(
          mapModalityToActivityKind(entry.key),
          entry.value,
          reason: 'modality "${entry.key}"',
        );
      }
    });

    test('free training (null modality) maps to the generic kind', () {
      expect(mapModalityToActivityKind(null), HealthActivityKind.other);
    });

    test('unknown or empty modality falls back, never throws (S-007)', () {
      expect(mapModalityToActivityKind(''), HealthActivityKind.other);
      expect(
        mapModalityToActivityKind('quantum_flexing'),
        HealthActivityKind.other,
      );
      expect(mapModalityToActivityKind('  '), HealthActivityKind.other);
    });
  });

  group('pluginActivityTypeFor', () {
    // Verified against health 13.3.1's `_isOnIOS` / `_isOnAndroid` sets:
    // TRADITIONAL_STRENGTH_TRAINING and FLEXIBILITY are iOS-only;
    // STRENGTH_TRAINING is Android-only. Everything else used here is in
    // both sets.
    test('strength resolves per platform (iOS-only vs Android-only type)', () {
      expect(
        pluginActivityTypeFor(HealthActivityKind.strength, isIOS: true).name,
        'TRADITIONAL_STRENGTH_TRAINING',
      );
      expect(
        pluginActivityTypeFor(HealthActivityKind.strength, isIOS: false).name,
        'STRENGTH_TRAINING',
      );
    });

    test('flexibility uses the iOS flexibility type', () {
      expect(
        pluginActivityTypeFor(HealthActivityKind.flexibility, isIOS: true).name,
        'FLEXIBILITY',
      );
    });

    test('every activity kind resolves on both platforms', () {
      for (final kind in HealthActivityKind.values) {
        for (final isIOS in [true, false]) {
          final type = pluginActivityTypeFor(kind, isIOS: isIOS);
          expect(
            type.name,
            isNotEmpty,
            reason: 'kind $kind, isIOS=$isIOS must resolve to a type',
          );
        }
      }
    });

    test('the generic fallback is the cross-platform OTHER type', () {
      expect(
        pluginActivityTypeFor(HealthActivityKind.other, isIOS: true).name,
        'OTHER',
      );
      expect(
        pluginActivityTypeFor(HealthActivityKind.other, isIOS: false).name,
        'OTHER',
      );
    });
  });
}
