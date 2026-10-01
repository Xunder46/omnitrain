/// The rows the phone writes for one logged entry, and the shell a free
/// session starts from — built here once, for every writer.
///
/// Two writers use them: the phone's own logging (`SessionCore`), and the
/// import of a session the wrist ran (`WatchSessionImporter`). Building both
/// from one place is what makes an imported row the same shape as one the
/// phone logged — metric ids, units, the id pattern and the companion rows
/// with their defaults — rather than a copy that could drift (Stats PR 2,
/// D-134; verified by `test/watch_session_import_test.dart`, S-274).
library;

import '../constants/metric_ids.dart';
import '../../data/models/models.dart';

abstract final class LoggedEntryRows {
  /// The owner id the phone's own sessions carry.
  static const String ownerUserId = 'user-1';

  /// The one segment a free session starts with.
  static SessionSegment defaultSegment({
    required String id,
    required String sessionId,
    required int atMs,
  }) => SessionSegment(
    id: id,
    sessionId: sessionId,
    orderIndex: 0,
    segmentType: 'workout',
    name: 'Main Workout',
    createdAtMs: atMs,
    updatedAtMs: atMs,
  );

  /// `obs-<effortId>-<entryIndex>-<metricKey>`: the id every entry-level
  /// observation carries. The phone reads the entry index back out of it, so
  /// it is part of the row's shape, not a naming choice.
  static String observationId(
    String effortId,
    int entryIndex,
    String metricKey,
  ) => 'obs-$effortId-$entryIndex-$metricKey';

  /// A set: reps and weight, plus an extra weight when the exercise carries no
  /// `load` capability — or is not known — because that is where a
  /// bodyweight movement's added load goes.
  static List<EffortObservation> setObservations({
    required String effortId,
    required int entryIndex,
    required int reps,
    required double weightKg,
    required bool exerciseHasLoad,
    double extraWeightKg = 0.0,
    required int atMs,
  }) => [
    EffortObservation(
      id: observationId(effortId, entryIndex, 'reps'),
      effortId: effortId,
      metricId: MetricIds.reps,
      unitId: MetricIds.unitReps,
      valueInt: reps,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
    EffortObservation(
      id: observationId(effortId, entryIndex, 'weight'),
      effortId: effortId,
      metricId: MetricIds.weight,
      unitId: MetricIds.unitKg,
      valueReal: weightKg,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
    if (!exerciseHasLoad)
      _extraWeightKg(effortId, entryIndex, extraWeightKg, atMs),
  ];

  /// Timed work's companions to its `TimedInstance`: distance and extra
  /// weight.
  ///
  /// [distanceSource] records where a distance came from (D-334, D-335): the
  /// source the wrist sent, or `entered` when it sent none. It is written on
  /// the distance row alone, and a distance with no value carries none.
  static List<EffortObservation> timedObservations({
    required String effortId,
    required int entryIndex,
    required double distanceMeters,
    String? distanceSource,
    double extraWeightKg = 0.0,
    required int atMs,
  }) => [
    EffortObservation(
      id: observationId(effortId, entryIndex, 'distance'),
      effortId: effortId,
      metricId: MetricIds.distance,
      unitId: MetricIds.unitMeters,
      valueReal: distanceMeters,
      valueSource: distanceSource,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
    _extraWeightKg(effortId, entryIndex, extraWeightKg, atMs),
  ];

  /// Added load in kilograms, as sets and timed work record it.
  static EffortObservation _extraWeightKg(
    String effortId,
    int entryIndex,
    double valueKg,
    int atMs,
  ) => EffortObservation(
    id: observationId(effortId, entryIndex, 'extra-weight'),
    effortId: effortId,
    metricId: MetricIds.extraWeight,
    unitId: MetricIds.unitKg,
    valueReal: valueKg,
    createdAtMs: atMs,
    updatedAtMs: atMs,
  );

  /// A hold's (`drill`) companion to its `TimedInstance`: extra weight. It
  /// carries no unit id, as the phone's drill rows never have.
  static List<EffortObservation> drillObservations({
    required String effortId,
    required int entryIndex,
    double extraWeightKg = 0.0,
    required int atMs,
  }) => [
    EffortObservation(
      id: observationId(effortId, entryIndex, 'extra-weight'),
      effortId: effortId,
      metricId: MetricIds.extraWeight,
      valueReal: extraWeightKg,
      createdAtMs: atMs,
      updatedAtMs: atMs,
    ),
  ];
}
