/// Sensor recording: what the watch listens to while a session runs.
///
/// Plan: `.github/agents/plans/2026-07-13-11-d-watch-sensor-recording-plan.md`,
/// scenarios S-002, S-003, S-004 and S-006.
///
/// Two rules shape this layer:
///
/// 1. **A reading is stored, not held.** Every sample goes into the same
///    append-only store as everything else, and the live readout is derived from
///    the newest stored row rather than from a field kept in memory. A kill
///    mid-run therefore costs the user nothing: what was measured is on disk.
/// 2. **Denial is not failure.** A permission the user refused, or hardware the
///    device does not have, skips the subscription and nothing else. Logging is
///    the primary action of the watch and never depends on a sensor (S-006).
///
/// The GPS decision is not made here either: [WatchGpsPolicy] reads the
/// session's capability profile, so a lift never wakes the radio and a run
/// always does.
library;

import 'dart:async';

import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import 'watch_platform_workout.dart';

/// What the platform says about one sensor.
enum WatchSensorPermission {
  /// The user has allowed it, and the hardware is there.
  granted,

  /// The user said no. Asking again is the platform's business, not the watch's.
  denied,

  /// There is nothing to ask: no radio, no sensor, no watch face for it.
  unavailable,
}

/// One location fix, reduced to the only thing a training session needs from
/// it: how far the user has covered in total.
///
/// Route geometry is out of scope on purpose. The watch is an instrument panel,
/// not a map, and a polyline is the largest thing this app could store for the
/// least information.
class WatchLocationFix {
  const WatchLocationFix({required this.distanceMeters});

  /// Metres covered since the session started, cumulative — the platform
  /// already tracks the running total, and the wrist only has to carry it.
  final double distanceMeters;
}

/// The device's sensors, behind the one interface the watch is allowed to see.
///
/// The native clients satisfy this with HealthKit and CoreLocation on watchOS
/// and Health Services plus the fused location provider on Wear OS; tests
/// satisfy it with a pair of streams they drive by hand.
abstract interface class WatchSensorSource {
  Future<WatchSensorPermission> heartRatePermission();

  Future<WatchSensorPermission> locationPermission();

  /// Beats per minute, as the sensor reports them.
  Stream<double> heartRate();

  /// Location fixes, whenever the platform produces one.
  Stream<WatchLocationFix> location();
}

/// What the sensors are reading right now, resolved together because a readout
/// shows them together.
class WatchSensorReadings {
  const WatchSensorReadings({this.heartRate, this.distanceMeters});

  /// Nothing measured yet: the state a session starts in, and the state a
  /// surface with no sensors at all stays in.
  static const WatchSensorReadings none = WatchSensorReadings();

  /// The newest stored beat, or null when none has been recorded.
  final double? heartRate;

  /// Metres covered: the settled total once recording has stopped, and the
  /// latest fix while it runs.
  final double? distanceMeters;
}

/// The sensors of a running session, writing what they read into the session's
/// own storage.
class WatchSensorRecorder {
  WatchSensorRecorder({
    required WatchSessionEngine engine,
    required WatchSensorSource source,
    DateTime Function()? clock,
  }) : _engine = engine,
       _source = source,
       _clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  final WatchSessionEngine _engine;
  final WatchSensorSource _source;
  final DateTime Function() _clock;

  StreamSubscription<double>? _beats;
  StreamSubscription<WatchLocationFix>? _fixes;

  bool _measuringDistance = false;

  /// Whether a location subscription is live. False for work that has no
  /// distance, and false when the user refused permission.
  bool get isMeasuringDistance => _measuringDistance;

  /// What the sensors are reading, as one resolution of stored rows.
  WatchSensorReadings get readings {
    final newest = _engine.newestSensorSamples();
    return WatchSensorReadings(
      heartRate: newest[WatchSensorKind.heartRate]?.value,
      distanceMeters:
          newest[WatchSensorKind.distance]?.value ??
          newest[WatchSensorKind.gps]?.value,
    );
  }

  /// Starts listening to whatever [session]'s modality calls for.
  ///
  /// Heart rate is recorded for every session that has a sensor to record it
  /// with. Location is recorded only where the modality can cover distance, so
  /// a lift does not drain the battery warming up a radio it will never use
  /// (S-001, S-002).
  Future<void> start(WatchSessionRecord session) async {
    await _startHeartRate();

    if (!WatchGpsPolicy.isRequired(session.modality)) return;
    if (await _source.locationPermission() != WatchSensorPermission.granted) {
      return;
    }

    _measuringDistance = true;
    _fixes = _source.location().listen(_onFix);
  }

  /// Stops listening, and settles the session's distance.
  ///
  /// The settled total is written as a `distance` sample rather than left as the
  /// last fix: "what the session measured" is then one row the phone can read
  /// without replaying the GPS log, and a fix that arrived a metre before the
  /// user pressed finish does not have to be treated as the final answer.
  Future<void> stop() async {
    await _beats?.cancel();
    await _fixes?.cancel();
    _beats = null;
    _fixes = null;

    if (!_measuringDistance) return;
    _measuringDistance = false;

    final measured = _engine.newestSensorSample(WatchSensorKind.gps)?.value;
    if (measured == null) return;

    await _engine.appendSensorSample(
      kind: WatchSensorKind.distance,
      value: measured,
    );
  }

  Future<void> _startHeartRate() async {
    if (await _source.heartRatePermission() != WatchSensorPermission.granted) {
      return;
    }
    _beats = _source.heartRate().listen(_onBeat);
  }

  void _onBeat(double beatsPerMinute) =>
      _record(WatchSensorKind.heartRate, beatsPerMinute);

  void _onFix(WatchLocationFix fix) =>
      _record(WatchSensorKind.gps, fix.distanceMeters);

  /// Stores one reading. Deliberately not awaited: the subscription must not
  /// queue behind storage, and the append is idempotent, so a reading the store
  /// is still writing cannot be lost or doubled.
  void _record(String kind, double value) {
    unawaited(
      _engine.appendSensorSample(
        kind: kind,
        value: value,
        recordedAt: _clock(),
      ),
    );
  }
}

/// Everything a session has running on the platform: its workout registration
/// and its sensors, started and stopped together.
///
/// One object rather than two so that no caller can remember to start the
/// sensors and forget the workout — the pairing is the behaviour.
class WatchSessionSensors {
  WatchSessionSensors({
    required WatchPlatformWorkout platform,
    required WatchSensorRecorder recorder,
  }) : _platform = platform,
       _recorder = recorder;

  final WatchPlatformWorkout _platform;
  final WatchSensorRecorder _recorder;

  /// The recorder behind this session: what the live readout reads, and what
  /// [stop] settles the distance through.
  WatchSensorRecorder get recorder => _recorder;

  /// Registers the session with the platform and starts its sensors.
  Future<void> start(WatchSessionRecord session) async {
    await _platform.start(session);
    await _recorder.start(session);
  }

  /// Stops the sensors and closes the platform workout.
  Future<void> stop() async {
    await _recorder.stop();
    await _platform.end();
  }

  /// Ends any workout a previous process left open. Call at launch, before
  /// anything starts.
  Future<List<String>> recoverInProgress() => _platform.recoverInProgress();
}
