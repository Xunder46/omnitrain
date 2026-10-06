/// The value screen's state: the effort the session is on, the values the user
/// has dialled in, and the observation that comes out of confirming them.
///
/// Plan: `docs/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`,
/// scenarios S-001 to S-006 and S-008.
///
/// Everything the screen shows is derived — from the slot the engine is on, the
/// observations already logged against it, and the timers it is running. The
/// only thing held in memory is an edit the user has made but not yet
/// confirmed, which is not data yet: a kill mid-turn costs a turn, never an
/// entry. The event this builds is the protocol's `observations_up` event
/// verbatim, so confirming goes straight to the engine's `appendObservation`
/// with nothing translated in between.
library;

import 'package:uuid/uuid.dart';

import '../../core/constants/capability.dart';
import '../../core/constants/effort_defaults.dart';
import '../../core/constants/metric_ids.dart';
import '../../core/constants/modality_config.dart';
import '../../core/constants/modality_display.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../sensors/watch_sensor_recording.dart';
import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_timer_math.dart';
import 'watch_metric_stepping.dart';

/// What the surfaces fall back on before the phone's prescription arrives.
abstract final class WatchLoggingDefaults {
  /// Length of the rest countdown after a set. A routine's per-effort rest
  /// supersedes it once the prescription reaches the watch; until then the
  /// wrist rests at the standing default.
  static const int restSeconds = 90;
}

/// The effort kinds a value screen can be, in the protocol's vocabulary. A hold
/// is a `drill` to the data layer and a `hold` on the wire, which is why both
/// names appear here.
abstract final class WatchEffortKind {
  static const String set = 'set';
  static const String timed = 'timed';
  static const String round = 'round';
  static const String drill = 'drill';

  /// Every kind a slot may declare, so a value that is not one of them is not
  /// mistaken for the routine's intent.
  static const List<String> declared = [set, timed, round, drill];

  /// The `observations_up` event a surface of this kind emits.
  static String eventKind(String effortKind) =>
      effortKind == drill ? 'hold' : effortKind;
}

/// One adjustable value on a logging surface. [value] is canonical — the unit
/// the protocol and the store speak — while [displayValue] is what the wrist
/// prints, already converted through `UnitFormatter`.
class WatchMetricField {
  const WatchMetricField({
    required this.metricKey,
    required this.label,
    required this.value,
    required this.displayValue,
    required this.step,
    required this.unitLabel,
    this.isMeasured = false,
  });

  /// One of [WatchMetricKey].
  final String metricKey;

  /// The phone's word for it, so the wrist never invents a synonym.
  final String label;

  final double value;
  final String displayValue;

  /// Canonical change per rotary detent.
  final double step;

  final String unitLabel;

  /// Whether a sensor is keeping this value, rather than the user.
  ///
  /// A measured value is not dial-able: the row shows what the sensor read, and
  /// the surface leaves its controls inert so a stray turn cannot replace a
  /// measurement with a guess (S-002).
  final bool isMeasured;

  @override
  String toString() => 'WatchMetricField($metricKey: $displayValue $unitLabel)';
}

/// The pace floor: below this, a first fix a few metres from the start would
/// print a number that is not a pace at all.
///
/// The value is not the wrist's to choose — `watch/contract/watch_sensor_contract.json`
/// carries it and both clients' suites assert against it, so the two cannot
/// disagree about when a pace appears.
abstract final class WatchSensorPace {
  static const double minDistanceMeters = 50;
}

/// What the sensors are reading, as the wrist prints it: the beat, the distance
/// in the saved unit, and the pace it is being covered at.
///
/// Three strings ready to render, not measurements — the raw values are
/// [WatchSensorReadings], which the sensors layer owns.
class WatchSensorLabels {
  const WatchSensorLabels({this.heartRate, this.distance, this.pace});

  /// Nothing to show — what a session with no sensors stays at.
  static const WatchSensorLabels none = WatchSensorLabels();

  /// Beats per minute, without a unit: the label beside it says what it is.
  final String? heartRate;

  /// Distance in the saved display unit.
  final String? distance;

  /// Minutes per display unit of distance.
  final String? pace;
}

/// The value screen for the effort the session is currently on.
class WatchLoggingState {
  WatchLoggingState({
    required WatchSessionEngine engine,
    DateTime Function()? clock,
    String Function()? idFactory,
    this.units = const WatchUnitPreferences(),
    this.restSeconds = WatchLoggingDefaults.restSeconds,
    WatchSensorRecorder? sensors,
  }) : _engine = engine,
       _clock = clock ?? _utcNow,
       _newId = idFactory ?? _uuid,
       _sensors = sensors;

  static const Uuid _uuidV4 = Uuid();

  static DateTime _utcNow() => DateTime.now().toUtc();

  static String _uuid() => _uuidV4.v4();

  /// Which capability decides the effort kind, in the order that matters: an
  /// isometric exercise usually carries `time` as well, and it is still a hold.
  static const List<String> _kindPrecedence = [
    ExerciseCapability.hold,
    ExerciseCapability.rounds,
    ExerciseCapability.reps,
    ExerciseCapability.sets,
    ExerciseCapability.load,
    ExerciseCapability.time,
    ExerciseCapability.distance,
  ];

  /// Values the user has dialled in but not confirmed, by metric key. Cleared
  /// on confirm, at which point the values come back from the logged
  /// observation (for a set) or start fresh (for measured work).
  final Map<String, double> _dialled = {};

  final WatchSessionEngine _engine;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// The session's live sensors, when the surface is wired to them. A surface
  /// with none behaves exactly as before: every value is the user's to dial.
  final WatchSensorRecorder? _sensors;

  /// The saved unit preferences the wrist reads in.
  final WatchUnitPreferences units;

  /// Rest countdown length after a set, in seconds.
  final int restSeconds;

  // ---------------------------------------------------------------------------
  // What the screen is showing
  // ---------------------------------------------------------------------------

  /// Whether there is an exercise in progress to log against. A session that is
  /// over — ended here or by the phone — is not a surface to log into (D-55).
  bool get canLog =>
      _engine.session?.status == WatchSessionStatus.active && _slot != null;

  /// The modality the session was started in, or null for free training.
  String? get modality => _engine.session?.modality;

  /// The engine this surface logs through.
  WatchSessionEngine get engine => _engine;

  /// The name of the exercise being logged, when there is one.
  String? get exerciseName => _slot?['name'] as String?;

  /// The newest timer of [kind], which is the one that applies.
  WatchTimerRecord? timerFor(String kind) => _engine.timerFor(kind);

  /// The current instant, read through this state's clock, so the screen and
  /// the events it logs agree on the time.
  DateTime now() => _clock();

  // ---------------------------------------------------------------------------
  // Live sensors
  // ---------------------------------------------------------------------------

  /// Whether the distance is being measured for the user rather than dialled by
  /// them.
  bool get isMeasuringDistance => _sensors?.isMeasuringDistance ?? false;

  /// What the sensors are reading, resolved once so the whole readout costs one
  /// pass over the session's stored rows.
  WatchSensorReadings get readings =>
      _sensors?.readings ?? WatchSensorReadings.none;

  /// The readout as the wrist prints it, resolved once — one pass over the
  /// stored rows for the beat, the distance and the pace together.
  WatchSensorLabels get sensorLabels {
    final readings = this.readings;
    return WatchSensorLabels(
      heartRate: readings.heartRate?.round().toString(),
      distance: _distanceLabelFor(readings.distanceMeters),
      pace: _paceLabelFor(readings.distanceMeters),
    );
  }

  /// The newest heart rate the sensors stored, or null when none has been.
  double? get heartRate => readings.heartRate;

  /// The distance covered so far, in metres, or null when nothing has measured
  /// any.
  double? get distanceMeters => readings.distanceMeters;

  /// The heart rate as the wrist prints it, without a unit: the label beside it
  /// says what the number is.
  String? get heartRateLabel => sensorLabels.heartRate;

  /// The measured distance in the saved unit, or null when nothing has been
  /// measured.
  String? get liveDistanceLabel => sensorLabels.distance;

  /// Minutes per display unit of distance, or null when there is not yet a
  /// distance and an elapsed time to divide it by.
  ///
  /// Pace is derived on read rather than stored: it is a ratio of two things the
  /// watch already keeps — the distance measured and the session's own clock —
  /// and a stored pace would be wrong the moment either moved.
  String? get paceLabel => sensorLabels.pace;

  /// The distance in the saved unit, as the wrist prints it.
  String? _distanceLabelFor(double? metres) => metres == null
      ? null
      : (metres / UnitFormatter.metresPerUnit(units.distanceUnit))
            .toStringAsFixed(1);

  /// The pace [metres] has been covered at, or null when there is not yet a
  /// distance worth dividing and a time to divide it by.
  String? _paceLabelFor(double? metres) {
    final startedAt = _engine.session?.startedAt;
    if (metres == null ||
        metres < WatchSensorPace.minDistanceMeters ||
        startedAt == null) {
      return null;
    }

    final elapsedSeconds = _clock().difference(startedAt).inSeconds;
    if (elapsedSeconds <= 0) return null;

    final unitsCovered =
        metres / UnitFormatter.metresPerUnit(units.distanceUnit);
    final secondsPerUnit = elapsedSeconds / unitsCovered;
    final clock = OmniDateUtils.formatClock((secondsPerUnit * 1000).round());
    return '$clock /${UnitFormatter.distanceLabelForUnit(units.distanceUnit)}';
  }

  /// The effort kind the current exercise is.
  ///
  /// A slot the routine produced says so itself: the routine's declared kind
  /// is what the user set up on the phone, and re-deriving it from capabilities
  /// would render a Plank in an isometric routine as something the routine
  /// never asked for. Only a slot with no declared kind — a free workout, or one
  /// the phone pushed — is resolved from its capabilities, the same way the
  /// phone decides, so the two agree without being told.
  String get effortKind {
    final declared = _slot?['effortKind'];
    if (declared is String && WatchEffortKind.declared.contains(declared)) {
      return declared;
    }

    final capabilities = _capabilities;
    for (final capability in _kindPrecedence) {
      if (capabilities.contains(capability)) {
        return ModalityConfig.effortKindFromMetric(capability);
      }
    }
    return WatchEffortKind.set;
  }

  /// The word this modality uses for a round, exactly as the phone says it
  /// (S-008).
  String get roundsLabel => ModalityDisplay.getRoundsLabel(modality);

  /// The number the next round will carry.
  int get nextRoundNumber {
    var highest = 0;
    for (final observation in _observations) {
      if (observation.payload['kind'] != 'round') continue;
      final number = observation.payload['roundNumber'];
      if (number is int && number > highest) highest = number;
    }
    return highest + 1;
  }

  /// The adjustable values for the current effort, in the order the wrist reads
  /// them. Empty when there is no exercise to log against.
  List<WatchMetricField> get fields => [
    if (canLog)
      for (final metricKey in _metricKeys) _field(metricKey),
  ];

  /// The current session's entries for the exercise being shown, with the
  /// phone's corrections folded in — what the wrist shows is the engine's
  /// projection, not the raw log.
  Iterable<WatchObservationRecord> get _observations {
    final slotId = _slot?['sessionExerciseId'];
    return _engine.entries.where(
      (observation) => observation.payload['sessionExerciseId'] == slotId,
    );
  }

  Map<String, Object?>? get _slot => _engine.currentExercise;

  List<String> get _capabilities =>
      ((_slot?['capabilities'] as List?) ?? const [])
          .whereType<String>()
          .toList();

  /// The metrics the effort kind calls for, minus the ones the exercise cannot
  /// fill: a bodyweight movement has no load row, a run that covers no distance
  /// has no distance row.
  ///
  /// Extra load is the exception: `EffortDefaults` gives a drill its
  /// extra-weight row whether or not the exercise carries `load`, because band
  /// assist is assistance rather than load.
  List<String> get _metricKeys {
    final targets = EffortDefaults.getDefaultTargets(effortKind);
    final metricIds = [
      ...EffortDefaults.getPrimaryMetrics(effortKind),
      ...EffortDefaults.getSecondaryMetrics(effortKind),
    ];
    final capabilities = _capabilities;
    final keys = <String>[];

    for (final metricId in metricIds) {
      if (!targets.containsKey(metricId)) continue;
      final metricKey = _metricKeyOf(metricId);
      final capability = _capabilityFor(metricKey);
      if (capability != null && !capabilities.contains(capability)) continue;
      keys.add(metricKey);
    }

    return keys;
  }

  /// The metric key for a metric id, or the id itself when it is unknown.
  static String _metricKeyOf(String metricId) =>
      MetricIds.metricIdToKey[metricId] ?? metricId;

  /// The metric id for a metric key.
  static String _metricIdOf(String metricKey) =>
      MetricIds.keyToMetricId[metricKey] ?? metricKey;

  /// The capability a metric depends on, or null when it can always be offered.
  static String? _capabilityFor(String metricKey) {
    switch (metricKey) {
      case WatchMetricKey.weight:
        return ExerciseCapability.load;
      case WatchMetricKey.distance:
        return ExerciseCapability.distance;
      default:
        return null;
    }
  }

  WatchMetricField _field(String metricKey) {
    final measured = _isMeasured(metricKey);
    final value = measured
        ? _measuredValue(metricKey)
        : _dialled[metricKey] ?? _initialValue(metricKey);
    return WatchMetricField(
      metricKey: metricKey,
      label: _labelFor(metricKey),
      value: value,
      displayValue: _displayValueFor(metricKey, value),
      step: WatchMetricStepping.stepFor(metricKey, units: units),
      unitLabel: _unitLabelFor(metricKey),
      isMeasured: measured,
    );
  }

  /// Whether a sensor, rather than the user, is keeping [metricKey].
  bool _isMeasured(String metricKey) =>
      metricKey == WatchMetricKey.distance && isMeasuringDistance;

  /// What the sensors have measured for [metricKey], or zero before the first
  /// reading lands.
  double _measuredValue(String metricKey) {
    switch (metricKey) {
      case WatchMetricKey.distance:
        return distanceMeters ?? 0;
      default:
        return 0;
    }
  }

  /// Where a value starts: what was logged last for this exercise, or what the
  /// effort kind prescribes when nothing has been.
  double _initialValue(String metricKey) {
    switch (metricKey) {
      case WatchMetricKey.rounds:
        return nextRoundNumber.toDouble();
      case WatchMetricKey.roundDuration:
        final planned = _engine
            .timerFor(WatchTimerKind.round)
            ?.plannedDurationMs;
        return planned == null
            ? _targetFor(metricKey)
            : planned / Duration.millisecondsPerSecond;
      case WatchMetricKey.distance:
        // Measured work starts empty: the next run or ride is timed from zero
        // (S-002). A hold is prescribed rather than measured, so it carries the
        // length of the last one over. A distance the sensors are keeping never
        // reaches here — [WatchLoggingState._field] resolves it first.
        if (effortKind == WatchEffortKind.timed) return 0;
        return _lastLogged(metricKey) ?? _targetFor(metricKey);
      case WatchMetricKey.duration:
        // Measured work starts empty: the next run or ride is timed from zero
        // (S-002). A hold is prescribed rather than measured, so it carries the
        // length of the last one over.
        if (effortKind == WatchEffortKind.timed) return 0;
        return _lastLogged(metricKey) ?? _targetFor(metricKey);
      default:
        return _lastLogged(metricKey) ?? _targetFor(metricKey);
    }
  }

  /// What the previous effort of this kind logged for [metricKey], or null
  /// when this is the first.
  double? _lastLogged(String metricKey) {
    for (final observation in _observations.toList().reversed) {
      if (observation.payload['kind'] != _eventKind) continue;
      final value = _valueIn(observation.payload, metricKey);
      if (value != null) return value;
    }
    return null;
  }

  /// The protocol field [metricKey] lives in, read back as canonical units.
  double? _valueIn(Map<String, Object?> event, String metricKey) {
    final Object? raw;
    if (metricKey == WatchMetricKey.duration) {
      raw = _durationSecondsIn(event);
    } else {
      final field = _protocolFieldFor(metricKey);
      if (field == null) return null;
      raw = event[field];
    }

    switch (raw) {
      case final double value:
        return value;
      case final int value:
        return value.toDouble();
      default:
        return null;
    }
  }

  /// A timed or held entry's length, which the protocol carries as a window
  /// rather than as a number.
  double? _durationSecondsIn(Map<String, Object?> event) {
    final startedAt = event['startedAt'];
    final endedAt = event['endedAt'];
    if (startedAt is! String || endedAt is! String) return null;
    final window = DateTime.parse(
      endedAt,
    ).difference(DateTime.parse(startedAt));
    return window.inMilliseconds / Duration.millisecondsPerSecond;
  }

  /// The starting value `EffortDefaults` prescribes for [metricKey].
  double _targetFor(String metricKey) {
    final target = EffortDefaults.getDefaultTargets(
      effortKind,
    )[_metricIdOf(metricKey)];
    if (target is int) return target.toDouble();
    if (target is double) return target;
    return 0;
  }

  String _labelFor(String metricKey) {
    switch (metricKey) {
      case WatchMetricKey.reps:
        return ExerciseCapability.getDisplayName(ExerciseCapability.reps);
      case WatchMetricKey.weight:
        return 'Load';
      case WatchMetricKey.duration:
        return effortKind == WatchEffortKind.drill
            ? ExerciseCapability.getDisplayName(ExerciseCapability.hold)
            : 'Duration';
      case WatchMetricKey.distance:
        return ExerciseCapability.getDisplayName(ExerciseCapability.distance);
      case WatchMetricKey.rounds:
        return roundsLabel;
      case WatchMetricKey.roundDuration:
        return 'Round length';
      case WatchMetricKey.extraWeight:
        return 'Extra load';
      default:
        return metricKey;
    }
  }

  String _unitLabelFor(String metricKey) {
    switch (metricKey) {
      case WatchMetricKey.reps:
      case WatchMetricKey.rounds:
        return '';
      case WatchMetricKey.weight:
      case WatchMetricKey.extraWeight:
        return UnitFormatter.weightLabelForUnit(units.weightUnit);
      case WatchMetricKey.distance:
        return UnitFormatter.distanceLabelForUnit(units.distanceUnit);
      default:
        return '';
    }
  }

  /// The value as the wrist prints it, in the saved unit.
  String _displayValueFor(String metricKey, double value) {
    switch (metricKey) {
      case WatchMetricKey.reps:
      case WatchMetricKey.rounds:
        return value.round().toString();
      case WatchMetricKey.duration:
      case WatchMetricKey.roundDuration:
        return OmniDateUtils.formatClock((value * 1000).round());
      case WatchMetricKey.weight:
      case WatchMetricKey.extraWeight:
        final converted = UnitFormatter.fromKilograms(value, units.weightUnit);
        // A signed zero is a zero: `-0.0` must not print as "-0.0".
        return (converted == 0 ? 0.0 : converted).toStringAsFixed(1);
      case WatchMetricKey.distance:
        return (value / UnitFormatter.metresPerUnit(units.distanceUnit))
            .toStringAsFixed(1);
      default:
        return value.toString();
    }
  }

  // ---------------------------------------------------------------------------
  // Input
  // ---------------------------------------------------------------------------

  /// Applies [detents] rotary steps to [metricKey] — positive turns the value
  /// up. An unknown metric, or one the exercise does not carry, does nothing —
  /// and neither does a metric a sensor is keeping: a measurement outranks a
  /// dial, so the row is read-only while it is being measured (S-002).
  void adjust(String metricKey, double detents) {
    final field = _fieldOrNull(metricKey);
    if (field == null || field.isMeasured) return;

    _dialled[metricKey] = WatchMetricStepping.adjust(
      field.value,
      metricKey: metricKey,
      detents: detents,
      units: units,
    );
  }

  WatchMetricField? _fieldOrNull(String metricKey) {
    for (final field in fields) {
      if (field.metricKey == metricKey) return field;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  /// Confirms the effort: builds the protocol event, hands it to the engine,
  /// and starts whatever countdown the effort kind runs next.
  ///
  /// The event is stored before anything is emitted (the engine's contract), so
  /// a crash between the tap and the phone costs nothing.
  Future<WatchObservationRecord> log({DateTime? now}) async {
    final slot = _slot;
    if (!canLog || slot == null) {
      throw StateError(
        'no exercise is in progress, so there is nothing to log',
      );
    }

    final loggedAt = now ?? _clock();
    final id = _newId();
    final event = <String, Object?>{
      'entryId': id,
      'eventId': id,
      'kind': _eventKind,
      'loggedAt': utcIso(loggedAt),
      'sessionExerciseId': slot['sessionExerciseId'],
      'exerciseId': slot['exerciseId'],
      ..._metricPayload(loggedAt),
    };

    final stored = await _engine.appendObservation(event);
    _dialled.clear();
    await _startFollowOnTimer();
    return stored;
  }

  String get _eventKind => WatchEffortKind.eventKind(effortKind);

  /// The metrics of the effort just logged, in the protocol's field names.
  Map<String, Object?> _metricPayload(DateTime loggedAt) {
    switch (effortKind) {
      case WatchEffortKind.round:
        final window = _roundWindow(loggedAt);
        return {
          'startedAt': utcIso(window.startedAt),
          'endedAt': utcIso(window.endedAt),
          'roundNumber': (_valueOf(WatchMetricKey.rounds) ?? nextRoundNumber)
              .round(),
        };
      case WatchEffortKind.set:
        final reps = _valueOf(WatchMetricKey.reps) ?? 1;
        final load = _valueOf(WatchMetricKey.weight);
        // Unloaded work leaves `loadKg` off rather than sending a zero. The
        // phone sends 0.0 for the same case and the two are indistinguishable
        // once logged, so this is a choice, not an oversight: the field is
        // optional and a wrist log of bodyweight reps makes no load claim. A
        // negative load is a band assist and is emitted with its sign (D-61).
        return {
          'reps': reps.round() < 1 ? 1 : reps.round(),
          if (load != null && load != 0) 'loadKg': load,
        };
      case WatchEffortKind.timed:
        return _windowPayload(loggedAt, distance: true);
      default:
        // A drill: a held window, with the extra load the hold carried.
        final extraLoad = _valueOf(WatchMetricKey.extraWeight);
        return {
          ..._windowPayload(loggedAt),
          if (extraLoad != null && extraLoad != 0) 'extraLoadKg': extraLoad,
        };
    }
  }

  Map<String, Object?> _windowPayload(
    DateTime loggedAt, {
    bool distance = false,
  }) {
    final duration = _valueOf(WatchMetricKey.duration) ?? 0;
    final covered = distance ? _valueOf(WatchMetricKey.distance) : null;

    return {
      'startedAt': utcIso(
        loggedAt.subtract(Duration(milliseconds: (duration * 1000).round())),
      ),
      'endedAt': utcIso(loggedAt),
      if (covered != null && covered > 0) 'distanceMeters': covered,
    };
  }

  /// A round's window. The countdown is the round's clock: while one is
  /// running, the round started with it and — if it reached zero — ended with
  /// it, however long the user took to look down.
  ({DateTime startedAt, DateTime endedAt}) _roundWindow(DateTime loggedAt) {
    final countdown = _engine.timerFor(WatchTimerKind.round);
    if (countdown == null) {
      final length = _valueOf(WatchMetricKey.roundDuration) ?? 0;
      return (
        startedAt: loggedAt.subtract(
          Duration(milliseconds: (length * 1000).round()),
        ),
        endedAt: loggedAt,
      );
    }

    return (
      startedAt: countdown.startedAt,
      endedAt: remainingMs(countdown, loggedAt) == 0
          ? (completionInstant(countdown) ?? loggedAt)
          : loggedAt,
    );
  }

  double? _valueOf(String metricKey) => _fieldOrNull(metricKey)?.value;

  /// The countdown the effort kind runs next: rest after a set, the next round
  /// after a round, nothing after work that is measured rather than prescribed.
  Future<void> _startFollowOnTimer() async {
    switch (effortKind) {
      case WatchEffortKind.set:
        await _engine.startTimer(
          WatchTimerKind.rest,
          plannedDurationMs: restSeconds * Duration.millisecondsPerSecond,
        );
      case WatchEffortKind.round:
        final length = _valueOf(WatchMetricKey.roundDuration) ?? 0;
        await _engine.startTimer(
          WatchTimerKind.round,
          plannedDurationMs: (length * 1000).round(),
        );
      default:
        return;
    }
  }

  /// The protocol field a metric key travels in. Values the protocol carries as
  /// a window rather than a field have none.
  static String? _protocolFieldFor(String metricKey) {
    switch (metricKey) {
      case WatchMetricKey.reps:
        return 'reps';
      case WatchMetricKey.weight:
        return 'loadKg';
      case WatchMetricKey.extraWeight:
        return 'extraLoadKg';
      case WatchMetricKey.distance:
        return 'distanceMeters';
      case WatchMetricKey.rounds:
        return 'roundNumber';
      default:
        return null;
    }
  }
}
