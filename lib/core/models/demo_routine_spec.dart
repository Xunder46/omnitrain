import '../../data/models/models.dart';

/// Lightweight immutable spec describing a single target value carried
/// by a demo routine effort. Used by the bundled-catalog data classes
/// and the [DemoRoutinesValidator] — kept separate from the
/// runtime [TemplateTarget] model so we can encode ergonomic per-effort
/// literals at the source level without forcing every effort to know
/// every metric's id.
class DemoRoutineTargetSpec {
  const DemoRoutineTargetSpec({
    required this.metricId,
    this.setIndex,
    this.unitId,
    this.targetMin,
    this.targetMax,
    this.targetInt,
    this.targetText,
  });

  final String metricId;
  final int? setIndex;
  final String? unitId;
  final double? targetMin;
  final double? targetMax;
  final int? targetInt;
  final String? targetText;
}

/// Lightweight immutable spec describing one demo routine effort and the
/// targets it declares.
class DemoRoutineEffortSpec {
  const DemoRoutineEffortSpec({required this.effort, required this.targets});

  final TemplateEffort effort;
  final List<DemoRoutineTargetSpec> targets;
}

/// Lightweight immutable spec describing one demo routine segment and the
/// efforts it owns.
class DemoRoutineSegmentSpec {
  const DemoRoutineSegmentSpec({required this.segment, required this.efforts});

  final TemplateSegment segment;
  final List<DemoRoutineEffortSpec> efforts;
}

/// The bundled shape delivered to [DemoRoutinesValidator] and to the
/// catalog refresh. `template` is the routine metadata; `segments`
/// contains the segment + effort + target hierarchy that gets persisted
/// alongside the template by the refresh orchestrator.
class DemoRoutineBundle {
  const DemoRoutineBundle({required this.template, required this.segments});

  final WorkoutTemplate template;
  final List<DemoRoutineSegmentSpec> segments;
}
