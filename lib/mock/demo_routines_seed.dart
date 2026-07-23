import '../core/constants/metric_ids.dart';
import '../core/constants/modality.dart';
import '../core/models/demo_routine_spec.dart';
import '../data/models/models.dart';

/// Bundled demo workout routines shipped with the app on first launch.
///
/// These land on a device through the versioned
/// [CatalogRefreshService] pipeline the same way bundled exercises and
/// food-catalog rows do — only when the device's stored catalog version
/// is older than [bundledCatalogVersion]. User edits are respected by
/// the per-entry tombstone returned by
/// [WorkoutRepository.isSeedEntryTouched] for
/// [SeedEntryType.routineTemplate]; user deletions set that tombstone
/// explicitly and the refresh subsequently skips the entry.
///
/// Eight routines span the app's primary modalities:
///   1. Push Day    — resistance (barbell)
///   2. Pull Day    — resistance (barbell / dumbbell)
///   3. Leg Day     — resistance (barbell)
///   4. Dumbbell Arms — resistance (dumbbell isolation)
///   5. Bodyweight Circuit — bodyweight (mixed)
///   6. Easy Run    — cardio / endurance
///   7. Boxing Rounds — sports (round-based)
///   8. Mobility Flow — isometric / stretching (drill)
class DemoRoutineSeed {
  DemoRoutineSeed._();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  static WorkoutTemplate _template({
    required String id,
    required String name,
    required String description,
    required String modality,
  }) {
    final t = _now();
    return WorkoutTemplate(
      id: id,
      name: name,
      description: description,
      focusModality: modality,
      isBuiltInDemo: true,
      createdAtMs: t,
      updatedAtMs: t,
    );
  }

  static TemplateSegment _segment({
    required String id,
    required String templateId,
    required String name,
    required String segmentType,
    int orderIndex = 0,
  }) {
    final t = _now();
    return TemplateSegment(
      id: id,
      templateId: templateId,
      orderIndex: orderIndex,
      segmentType: segmentType,
      name: name,
      createdAtMs: t,
      updatedAtMs: t,
    );
  }

  static TemplateEffort _effort({
    required String id,
    required String templateSegmentId,
    required int orderIndex,
    required String effortKind,
    required String? exerciseId,
  }) {
    return TemplateEffort(
      id: id,
      templateSegmentId: templateSegmentId,
      orderIndex: orderIndex,
      effortKind: effortKind,
      exerciseId: exerciseId,
      createdAtMs: _now(),
    );
  }

  /// The list of bundled demo routines. Consumed by
  /// [BundledCatalogSource.routineTemplates] and by the build-time
  /// [DemoRoutinesValidator].
  static final List<DemoRoutineBundle> bundles = [
    _pushDay(),
    _pullDay(),
    _legDay(),
    _dumbbellArms(),
    _bodyweightCircuit(),
    _easyRun(),
    _boxingRounds(),
    _mobilityFlow(),
  ];

  // ─── Routine 1: Push Day (resistance / barbell) ────────────────────────

  static DemoRoutineBundle _pushDay() {
    const id = 'demo-template-push-day';
    const segId = 'demo-tseg-push-day-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Push Day',
        description:
            'A classic flat-bench / overhead-pressing / triceps day built around '
            'the barbell compounds with dumbbell accessory work.',
        modality: Modality.resistanceLifting,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Main Lifts',
            segmentType: 'strength_sets',
          ),
          efforts: [
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 0,
              exerciseId: 'exercise-bench-press',
              suffix: 'bench',
              sets: 4,
              reps: 5,
              weightTarget: 70,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 1,
              exerciseId: 'exercise-overhead-press',
              suffix: 'ohp',
              sets: 3,
              reps: 8,
              weightTarget: 40,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 2,
              exerciseId: 'exercise-triceps-pressdown',
              suffix: 'tri',
              sets: 3,
              reps: 12,
              weightTarget: 25,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Routine 2: Pull Day (resistance / barbell + dumbbell) ─────────────

  static DemoRoutineBundle _pullDay() {
    const id = 'demo-template-pull-day';
    const segId = 'demo-tseg-pull-day-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Pull Day',
        description:
            'Deadlift-driven horizontal and vertical pulling plus biceps. '
            'Pairs neatly with Push Day as the second half of a push/pull split.',
        modality: Modality.resistanceLifting,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Main Lifts',
            segmentType: 'strength_sets',
          ),
          efforts: [
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 0,
              exerciseId: 'exercise-deadlift',
              suffix: 'dl',
              sets: 3,
              reps: 5,
              weightTarget: 100,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 1,
              exerciseId: 'exercise-barbell-row',
              suffix: 'row',
              sets: 4,
              reps: 8,
              weightTarget: 60,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 2,
              exerciseId: 'exercise-dumbbell-curl',
              suffix: 'curl',
              sets: 3,
              reps: 12,
              weightTarget: 12,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Routine 3: Leg Day (resistance / barbell) ────────────────────────

  static DemoRoutineBundle _legDay() {
    const id = 'demo-template-leg-day';
    const segId = 'demo-tseg-leg-day-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Leg Day',
        description:
            'Squat-dominant lower-body session: quad, hip, and posterior chain '
            'work to set up the rest of the week.',
        modality: Modality.resistanceLifting,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Main Lifts',
            segmentType: 'strength_sets',
          ),
          efforts: [
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 0,
              exerciseId: 'exercise-barbell-squat',
              suffix: 'sq',
              sets: 4,
              reps: 5,
              weightTarget: 90,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 1,
              exerciseId: 'exercise-romanian-deadlift-barbell',
              suffix: 'rdl',
              sets: 3,
              reps: 8,
              weightTarget: 70,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 2,
              exerciseId: 'exercise-glute-bridge-hold',
              suffix: 'bridge',
              sets: 3,
              reps: 0, // unused on drill, kept for symmetry
              weightTarget: 0,
              effortKindOverride: 'drill',
              durationSec: 30,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Routine 4: Dumbbell Arms (resistance / dumbbell isolation) ────────

  static DemoRoutineBundle _dumbbellArms() {
    const id = 'demo-template-dumbbell-arms';
    const segId = 'demo-tseg-dumbbell-arms-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Dumbbell Arms',
        description:
            'A short, equipment-light session that hits biceps and triceps '
            'with dumbbell isolation work.',
        modality: Modality.resistanceLifting,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Arms',
            segmentType: 'strength_sets',
          ),
          efforts: [
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 0,
              exerciseId: 'exercise-dumbbell-curl',
              suffix: 'curl',
              sets: 3,
              reps: 12,
              weightTarget: 12,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 1,
              exerciseId: 'exercise-hammer-curl',
              suffix: 'hammer',
              sets: 3,
              reps: 12,
              weightTarget: 12,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Routine 5: Bodyweight Circuit (bodyweight / mixed) ────────────────

  static DemoRoutineBundle _bodyweightCircuit() {
    const id = 'demo-template-bodyweight-circuit';
    const segId = 'demo-tseg-bodyweight-circuit-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Bodyweight Circuit',
        description:
            'No-equipment circuit of three rounds across push-up, plank, and '
            'glute-bridge holds — fits inside 15 minutes including rests.',
        modality: Modality.resistanceLifting,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Circuit',
            segmentType: 'circuit',
          ),
          efforts: [
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 0,
              exerciseId: 'exercise-push-up',
              suffix: 'pushup',
              sets: 3,
              reps: 15,
              weightTarget: 0,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 1,
              exerciseId: 'exercise-plank-hold',
              suffix: 'plank',
              sets: 3,
              reps: 0,
              weightTarget: 0,
              effortKindOverride: 'drill',
              durationSec: 45,
            ),
            _setEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 2,
              exerciseId: 'exercise-glute-bridge-hold',
              suffix: 'bridge',
              sets: 3,
              reps: 0,
              weightTarget: 0,
              effortKindOverride: 'drill',
              durationSec: 30,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Routine 6: Easy Run (cardio / endurance) ──────────────────────────

  static DemoRoutineBundle _easyRun() {
    const id = 'demo-template-easy-run-30';
    const segId = 'demo-tseg-easy-run-30-1';
    const effortId = 'demo-teff-easy-run-30-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Easy Run — 30 min',
        description:
            'A 30-minute conversational-pace run. The backbone of any '
            'endurance program — runs end-to-end as a single timed effort.',
        modality: Modality.cardioEndurance,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Main Run',
            segmentType: 'timed_activity',
          ),
          efforts: [
            DemoRoutineEffortSpec(
              effort: _effort(
                id: effortId,
                templateSegmentId: segId,
                orderIndex: 0,
                effortKind: 'timed',
                exerciseId: 'exercise-easy-run',
              ),
              targets: [
                DemoRoutineTargetSpec(
                  metricId: MetricIds.duration,
                  setIndex: 0,
                  unitId: MetricIds.unitSeconds,
                  targetInt: 1800, // 30 minutes
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ─── Routine 7: Boxing Rounds (sports / round-based) ──────────────────

  static DemoRoutineBundle _boxingRounds() {
    const id = 'demo-template-boxing-rounds';
    const segId = 'demo-tseg-boxing-rounds-1';
    const effortId = 'demo-teff-boxing-rounds-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Heavy Bag — 5×3',
        description:
            'Five 3-minute rounds on the heavy bag. The classic boxing '
            'conditioning template.',
        modality: Modality.sports,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Heavy Bag',
            segmentType: 'round_based',
          ),
          efforts: [
            DemoRoutineEffortSpec(
              effort: _effort(
                id: effortId,
                templateSegmentId: segId,
                orderIndex: 0,
                effortKind: 'round',
                exerciseId: 'exercise-heavy-bag-rounds',
              ),
              targets: [
                DemoRoutineTargetSpec(
                  metricId: MetricIds.rounds,
                  setIndex: 0,
                  unitId: MetricIds.unitRounds,
                  targetInt: 5,
                ),
                DemoRoutineTargetSpec(
                  metricId: MetricIds.roundDuration,
                  setIndex: 0,
                  unitId: MetricIds.unitSeconds,
                  targetInt: 180, // 3 minutes
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ─── Routine 8: Mobility Flow (isometric / stretching drill) ───────────

  static DemoRoutineBundle _mobilityFlow() {
    const id = 'demo-template-mobility-flow';
    const segId = 'demo-tseg-mobility-flow-1';
    return DemoRoutineBundle(
      template: _template(
        id: id,
        name: 'Mobility Flow',
        description:
            'Coached-feeling mobility flow — a single sweeping block of '
            'spinal and hip holds to loosen up before or after training.',
        modality: Modality.isometricStretching,
      ),
      segments: [
        DemoRoutineSegmentSpec(
          segment: _segment(
            id: segId,
            templateId: id,
            name: 'Mobility',
            segmentType: 'drill_skill',
          ),
          efforts: [
            _drillEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 0,
              exerciseId: 'exercise-cat-cow-hold',
              suffix: 'cat-cow',
              sets: 2,
              durationSec: 45,
            ),
            _drillEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 1,
              exerciseId: 'exercise-thoracic-rotation-hold',
              suffix: 't-rotation',
              sets: 2,
              durationSec: 45,
            ),
            _drillEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 2,
              exerciseId: 'exercise-worlds-greatest-stretch-hold',
              suffix: 'wgs',
              sets: 2,
              durationSec: 45,
            ),
            _drillEffortSpec(
              templateId: id,
              segmentId: segId,
              effortIndex: 3,
              exerciseId: 'exercise-seated-butterfly-hold',
              suffix: 'butterfly',
              sets: 2,
              durationSec: 60,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Per-effort spec helpers ──────────────────────────────────────────

  /// Builds a `set` (or `drill`, when [effortKindOverride] is set) effort
  /// with parallel reps + weight targets per set.
  ///
  /// When [effortKindOverride] is `'drill'`, [durationSec] is required and
  /// the function emits a single duration target per set instead of a
  /// reps/weight pair.
  static DemoRoutineEffortSpec _setEffortSpec({
    required String templateId,
    required String segmentId,
    required int effortIndex,
    required String exerciseId,
    required String suffix,
    required int sets,
    required int reps,
    required double weightTarget,
    String effortKindOverride = 'set',
    int? durationSec,
  }) {
    final effortId = 'demo-teff-$templateId-$suffix';
    final kind = effortKindOverride;
    final targets = <DemoRoutineTargetSpec>[];

    for (var i = 0; i < sets; i++) {
      if (kind == 'drill') {
        assert(
          durationSec != null,
          'drill effort $effortId must declare a duration',
        );
        targets.add(
          DemoRoutineTargetSpec(
            metricId: MetricIds.duration,
            setIndex: i,
            unitId: MetricIds.unitSeconds,
            targetInt: durationSec!,
          ),
        );
      } else {
        targets.add(
          DemoRoutineTargetSpec(
            metricId: MetricIds.reps,
            setIndex: i,
            targetInt: reps,
          ),
        );
        targets.add(
          DemoRoutineTargetSpec(
            metricId: MetricIds.weight,
            setIndex: i,
            unitId: MetricIds.unitKg,
            targetMin: weightTarget,
          ),
        );
      }
    }

    return DemoRoutineEffortSpec(
      effort: _effort(
        id: effortId,
        templateSegmentId: segmentId,
        orderIndex: effortIndex,
        effortKind: kind,
        exerciseId: exerciseId,
      ),
      targets: targets,
    );
  }

  /// Shorthand for a drill effort with a parallel set of duration targets.
  static DemoRoutineEffortSpec _drillEffortSpec({
    required String templateId,
    required String segmentId,
    required int effortIndex,
    required String exerciseId,
    required String suffix,
    required int sets,
    required int durationSec,
  }) {
    final effortId = 'demo-teff-$templateId-$suffix';
    return DemoRoutineEffortSpec(
      effort: _effort(
        id: effortId,
        templateSegmentId: segmentId,
        orderIndex: effortIndex,
        effortKind: 'drill',
        exerciseId: exerciseId,
      ),
      targets: [
        for (var i = 0; i < sets; i++)
          DemoRoutineTargetSpec(
            metricId: MetricIds.duration,
            setIndex: i,
            unitId: MetricIds.unitSeconds,
            targetInt: durationSec,
          ),
      ],
    );
  }
}
