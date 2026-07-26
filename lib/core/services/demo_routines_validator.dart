import '../../core/constants/metric_ids.dart';
import '../../core/models/demo_routine_spec.dart';

/// Outcome of a [DemoRoutinesValidator.validate] call.
///
/// `isValid == true` means every demo template passed every rule.
/// `failures` is the human-readable list of rule violations — surfaced
/// at startup when the bundled catalog failed validation, and dumped
/// in full by the pre-release script when CI runs in production mode.
class DemoRoutinesValidationResult {
  DemoRoutinesValidationResult._({
    required this.isValid,
    required this.failures,
  });

  factory DemoRoutinesValidationResult.valid() =>
      DemoRoutinesValidationResult._(isValid: true, failures: const []);

  factory DemoRoutinesValidationResult.invalid(List<String> failures) =>
      DemoRoutinesValidationResult._(
        isValid: failures.isEmpty,
        failures: List.unmodifiable(failures),
      );

  final bool isValid;
  final List<String> failures;

  /// Compact one-line summary, suitable for a startup banner.
  String get summary => isValid
      ? 'ok (${failures.length} failures)'
      : 'FAIL (${failures.length} failures)';
}

/// Validates a bundled demo-routine list against the bundled exercise
/// catalog and against the per-effort target rules. Runs at:
///   - app startup (CI / `--debug` fail-fast mode)
///   - pre-release script (gating upload)
///
/// Keeps validation in one place so seed data never drifts from the
/// catalog.
class DemoRoutinesValidator {
  const DemoRoutinesValidator();

  /// Build-time / startup validator. Pure data-in / result-out.
  ///
  /// [exerciseIds] is the set of exercise ids present in the bundled
  /// catalog. The validator confirms every demo template references
  /// only those ids and that each declared effort carries the targets
  /// the runtime requires to render its UI correctly:
  ///
  ///   - `set` effort → at least one `reps` target
  ///   - `timed` effort → at least one `duration` target
  ///   - `round` effort → both `rounds` and `round-duration` targets
  ///   - `drill` effort → at least one `duration` target
  static DemoRoutinesValidationResult validate(
    List<DemoRoutineBundle> bundles,
    Set<String> exerciseIds,
  ) {
    final failures = <String>[];

    for (final bundle in bundles) {
      final templateId = bundle.template.id;

      if (!templateId.startsWith('demo-template-')) {
        failures.add(
          '$templateId: id must start with "demo-template-" to keep the '
          'namespaced prefix unambiguous against user-created templates',
        );
      }

      if (bundle.segments.isEmpty) {
        failures.add('$templateId: must declare at least one segment');
        continue;
      }

      final seenEffortIds = <String>{};
      for (final segmentSpec in bundle.segments) {
        final segment = segmentSpec.segment;
        if (segment.templateId != templateId) {
          failures.add(
            '$templateId: segment ${segment.id} has templateId '
            '${segment.templateId} (must match)',
          );
        }

        if (segmentSpec.efforts.isEmpty) {
          failures.add(
            '$templateId / ${segment.id}: segment must declare at least one effort',
          );
          continue;
        }

        for (final effortSpec in segmentSpec.efforts) {
          final effort = effortSpec.effort;

          if (effort.templateSegmentId != segment.id) {
            failures.add(
              '$templateId / ${segment.id}: effort ${effort.id} has '
              'templateSegmentId ${effort.templateSegmentId} (must match)',
            );
          }

          if (!seenEffortIds.add(effort.id)) {
            failures.add(
              '$templateId / ${segment.id}: duplicate effort id ${effort.id}',
            );
          }

          // Exercise reference must resolve into the bundled catalog.
          if (effort.exerciseId == null) {
            failures.add(
              '$templateId / ${segment.id} / ${effort.id}: effort must '
              'reference an exerciseId',
            );
          } else if (!exerciseIds.contains(effort.exerciseId)) {
            failures.add(
              '$templateId / ${segment.id} / ${effort.id}: exerciseId '
              '"${effort.exerciseId}" is not in the bundled catalog',
            );
          }

          // Effort-kind driven target requirements.
          _checkEffortTargets(
            templateId: templateId,
            segmentId: segment.id,
            effortId: effort.id,
            effortKind: effort.effortKind,
            targets: effortSpec.targets,
            failures: failures,
          );
        }
      }
    }

    return failures.isEmpty
        ? DemoRoutinesValidationResult.valid()
        : DemoRoutinesValidationResult.invalid(failures);
  }

  static void _checkEffortTargets({
    required String templateId,
    required String segmentId,
    required String effortId,
    required String effortKind,
    required List<DemoRoutineTargetSpec> targets,
    required List<String> failures,
  }) {
    if (targets.isEmpty) {
      failures.add(
        '$templateId / $segmentId / $effortId: $effortKind effort must '
        'declare at least one target',
      );
      return;
    }

    final metricIds = targets.map((t) => t.metricId).toSet();

    switch (effortKind) {
      case 'set':
        if (!metricIds.contains(MetricIds.reps)) {
          failures.add(
            '$templateId / $segmentId / $effortId: set effort must declare '
            'a metric-reps target',
          );
        }
        break;
      case 'timed':
        if (!metricIds.contains(MetricIds.duration)) {
          failures.add(
            '$templateId / $segmentId / $effortId: timed effort must declare '
            'a metric-duration target',
          );
        }
        break;
      case 'round':
        final hasRounds = metricIds.contains(MetricIds.rounds);
        final hasRoundDuration = metricIds.contains(MetricIds.roundDuration);
        if (!hasRounds || !hasRoundDuration) {
          failures.add(
            '$templateId / $segmentId / $effortId: round effort must declare '
            'metric-rounds and metric-round-duration targets '
            '(got: ${metricIds.join(", ")})',
          );
        }
        break;
      case 'drill':
        if (!metricIds.contains(MetricIds.duration)) {
          failures.add(
            '$templateId / $segmentId / $effortId: drill effort must declare '
            'a metric-duration target',
          );
        }
        break;
      default:
        failures.add(
          '$templateId / $segmentId / $effortId: unknown effortKind '
          '"$effortKind"',
        );
    }
  }
}
