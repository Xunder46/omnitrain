/// Build-flag-gated QA surface for the watch session engine.
///
/// Plan: `.github/agents/plans/2026-07-13-06-a1-watch-session-engine-plan.md`,
/// iteration 1 step 5 — exercise create → log → kill → restore by hand, on
/// hardware, so the kill-safety claims can be checked outside the test suite.
///
/// Nothing in the shipping app imports this file, and
/// `watch_session_debug_main.dart` is the only entry point that mounts it. The
/// "kill" button throws the engine away without handing anything across in
/// memory, which is exactly what an OS termination does.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/omni_theme.dart';
import '../sensors/watch_platform_workout.dart';
import '../sensors/watch_sensor_recording.dart';
import '../session/in_memory_watch_session_store.dart';
import '../session/watch_records.dart';
import '../session/watch_session_engine.dart';
import '../session/watch_session_store.dart';
import '../session/watch_timer_math.dart';

/// Whether the QA surface was compiled in. `watch_session_debug_main.dart`
/// refuses to mount the surface without it.
const bool watchSessionDebugEnabled = bool.fromEnvironment(
  'WATCH_SESSION_DEBUG',
);

/// Mints observation ids.
///
/// Ids are never derived from stored counts: a count falls back after a prune,
/// and a reused `eventId` is silently dropped by the phone's deduplication.
const Uuid _uuid = Uuid();

/// The slots a debug session is created with, so `advanceExercise` has
/// somewhere to go and the position is visible.
const List<Map<String, Object?>> _debugSlots = [
  {
    'sessionExerciseId': 'sx-1',
    'exerciseId': 'ex-back-squat',
    'name': 'Back Squat',
  },
  {
    'sessionExerciseId': 'sx-2',
    'exerciseId': 'ex-bench-press',
    'name': 'Bench Press',
  },
  {
    'sessionExerciseId': 'sx-3',
    'exerciseId': 'ex-barbell-row',
    'name': 'Barbell Row',
  },
];

/// How long a debug rest timer counts down from.
const int _debugRestMs = 90 * 1000;

/// The sensors a QA run has out of the box: none.
///
/// The platform source and health store belong to the app entry, which does not
/// exist in this repository yet — so the harness runs the real wiring against
/// hardware that is never there, which is also the shape permission denial takes
/// (S-006). Pass a real pair to exercise the readout on a device.
class _NoSensors implements WatchSensorSource {
  const _NoSensors();

  @override
  Future<WatchSensorPermission> heartRatePermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Future<WatchSensorPermission> locationPermission() async =>
      WatchSensorPermission.unavailable;

  @override
  Stream<double> heartRate() => const Stream.empty();

  @override
  Stream<WatchLocationFix> location() => const Stream.empty();
}

/// The health store a QA run has out of the box: nothing to open, nothing to
/// close.
class _NoPlatformWorkout implements WatchPlatformWorkoutStore {
  const _NoPlatformWorkout();

  @override
  Future<void> begin(String activityType) async {}

  @override
  Future<void> end() async {}

  @override
  Future<List<String>> inProgressActivityTypes() async => const [];
}

/// A mountable harness for the engine: session state on top, one button per
/// engine call below.
class WatchSessionDebugSurface extends StatefulWidget {
  const WatchSessionDebugSurface({
    super.key,
    this.store,
    this.sensorSource,
    this.platformWorkout,
  });

  /// Where the engine persists. Defaults to an in-memory store; pass a
  /// `HiveWatchSessionStore()` to exercise real on-device persistence.
  final WatchSessionStore? store;

  /// The device's sensors. Defaults to none, which is what a desk run has.
  final WatchSensorSource? sensorSource;

  /// The health store. Defaults to one that opens nothing.
  final WatchPlatformWorkoutStore? platformWorkout;

  @override
  State<WatchSessionDebugSurface> createState() =>
      _WatchSessionDebugSurfaceState();
}

class _WatchSessionDebugSurfaceState extends State<WatchSessionDebugSurface> {
  /// One second is enough to watch a countdown move without a rebuild storm.
  static const Duration _tick = Duration(seconds: 1);

  late final WatchSessionStore _store =
      widget.store ?? InMemoryWatchSessionStore();
  final List<Map<String, Object?>> _emitted = [];

  late WatchSessionEngine _engine;
  Timer? _ticker;
  String? _note;
  String? _failure;

  /// The sensors of the process that is running. Rebuilt whenever the engine is,
  /// because a recorder writes through the engine it was given — and dropped on
  /// a simulated kill, exactly as a real kill drops the subscriptions.
  WatchSessionSensors? _sensors;

  @override
  void initState() {
    super.initState();
    _engine = _engineOver(_store);
    _attempt(_boot);
    // Every remaining-time read is derived from stored timestamps, which is the
    // behaviour QA is here to watch survive a kill.
    _ticker = Timer.periodic(_tick, (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  WatchSessionEngine _engineOver(WatchSessionStore store) =>
      WatchSessionEngine(store, onEmit: _emitted.add);

  WatchSessionSensors _sensorsFor(WatchSessionEngine engine) =>
      WatchSessionSensors(
        platform: WatchPlatformWorkout(
          store: widget.platformWorkout ?? const _NoPlatformWorkout(),
        ),
        recorder: WatchSensorRecorder(
          engine: engine,
          source: widget.sensorSource ?? const _NoSensors(),
        ),
      );

  /// What a watch app does at launch, in this order: end anything a previous
  /// process left running in the health store, then read the session back. This
  /// is the wiring the app entry copies.
  Future<void> _boot() async {
    _sensors = _sensorsFor(_engine);
    final ended = await _sensors!.recoverInProgress();
    if (ended.isNotEmpty) {
      _note = 'closed a stranded workout: ${ended.join(', ')}';
    }
    await _engine.restore();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _attempt(Future<void> Function() action) async {
    setState(() {
      _failure = null;
    });
    try {
      await action();
    } on Object catch (error) {
      _failure = '$error';
    } finally {
      _refresh();
    }
  }

  // -----------------------------------------------------------------------------
  // Actions — one per engine call, in the order a session uses them
  // -----------------------------------------------------------------------------

  Future<void> _startSession() => _attempt(() async {
    _emitted.clear();
    _note = 'session created';
    final session = await _engine.createSession(
      modality: 'resistance_lifting',
      exercises: _debugSlots,
    );
    await _sensors?.start(session);
  });

  Future<void> _logSet() => _attempt(() async {
    if (_engine.session == null) return;

    final slot = _engine.currentExercise ?? const <String, Object?>{};
    final id = _uuid.v4();
    _note = 'logged set ${_engine.observations.length + 1}';
    await _engine.appendObservation({
      'eventId': 'event-$id',
      'entryId': 'entry-$id',
      'kind': 'set',
      'loggedAt': DateTime.now().toUtc().toIso8601String(),
      'sessionExerciseId': slot['sessionExerciseId'] ?? 'sx-0',
      'exerciseId': slot['exerciseId'] ?? 'ex-0',
      'reps': 5,
      'loadKg': 80,
    });
  });

  Future<void> _advance() => _attempt(() async {
    _note = 'advanced';
    await _engine.advanceExercise();
  });

  Future<void> _startRest() => _attempt(() async {
    _note = 'rest started';
    await _engine.startTimer(
      WatchTimerKind.rest,
      plannedDurationMs: _debugRestMs,
    );
  });

  Future<void> _pauseRest() => _attempt(() async {
    _note = 'rest paused';
    await _engine.pauseTimer();
  });

  Future<void> _resumeRest() => _attempt(() async {
    _note = 'rest resumed';
    await _engine.resumeTimer();
  });

  Future<void> _finish() => _attempt(() async {
    _note = 'finished';
    await _engine.finishSession();
    await _sensors?.stop();
  });

  /// Plays the phone's receipt: nothing is prunable until something is
  /// confirmed, so a QA run needs one button that acknowledges what was logged.
  Future<void> _confirmAll() => _attempt(() async {
    final confirmed = await _engine.confirmObservations([
      for (final observation in _engine.observations) observation.entryId,
    ]);
    _note = 'phone confirmed ${confirmed.length} observation(s)';
  });

  /// Prunes through the engine, never the store: the engine's view of the
  /// session is what the summary above reads.
  Future<void> _prune() => _attempt(() async {
    final dropped = await _engine.pruneConfirmed();
    _note = 'pruned ${dropped.length} confirmed observation(s)';
  });

  /// What a relaunch after an OS kill looks like: the engine is discarded, no
  /// state crosses over, and a new one reads the store back.
  Future<void> _simulateKill() => _attempt(() async {
    _engine = _engineOver(_store);
    _emitted.clear();
    _note = 'engine discarded — restoring from storage';
    await _boot();
  });

  /// Releases the raw sensor log of every finished session the phone has
  /// recorded in full — the retention rule the store's second prune implements.
  Future<void> _releaseSensorLog() => _attempt(() async {
    final dropped = await _engine.pruneSettledSensorSamples();
    _note = 'released ${dropped.length} reading(s)';
  });

  // -----------------------------------------------------------------------------
  // Rendering
  // -----------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _summary(context),
            const SizedBox(height: 16),
            _actions(context),
            if (_note != null) ...[
              const SizedBox(height: 16),
              Text(_note!, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_failure != null) ...[
              const SizedBox(height: 8),
              Text(
                _failure!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    final session = _engine.session;

    if (session == null) {
      return Text('No session stored.', style: styles.titleMedium);
    }

    final slot = _engine.currentExercise;
    final remaining = _restRemainingMs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Session ${session.status}', style: styles.titleMedium),
        const SizedBox(height: 8),
        Text('modality: ${session.modality ?? 'free training'}'),
        Text(
          'exercise: ${session.currentExerciseIndex + 1} of '
          '${session.exercises.length} — ${slot?['name'] ?? 'unknown'}',
        ),
        Text('entries logged: ${_engine.observations.length}'),
        Text(
          'rest: ${_restState()}${remaining == null ? '' : ' · '
                    '${_formatMs(remaining)} left'}',
        ),
        Text('sensor readings: ${_engine.sensorSamples.length}'),
        Text('messages emitted: ${_emitted.length}'),
        Text(
          'unconfirmed owed to phone: ${_engine.pendingObservations().length}',
        ),
      ],
    );
  }

  Widget _actions(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _action('New session', _startSession, primary: true),
      _action('Log set', _logSet, primary: true),
      _action('Next exercise', _advance),
      _action('Rest 90s', _startRest),
      _action('Pause rest', _pauseRest),
      _action('Resume rest', _resumeRest),
      _action('Finish', _finish),
      _action('Confirm all', _confirmAll),
      _action('Prune confirmed', _prune),
      _action('Release sensor log', _releaseSensorLog),
      _action('Simulate kill', _simulateKill, primary: true),
    ],
  );

  Widget _action(
    String label,
    Future<void> Function() onPressed, {
    bool primary = false,
  }) {
    final shape = WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
      ),
    );
    return primary
        ? FilledButton(
            style: ButtonStyle(shape: shape),
            onPressed: onPressed,
            child: Text(label),
          )
        : OutlinedButton(
            style: ButtonStyle(shape: shape),
            onPressed: onPressed,
            child: Text(label),
          );
  }

  int? _restRemainingMs() {
    final rest = _engine.timerFor(WatchTimerKind.rest);
    return rest == null ? null : remainingMs(rest, DateTime.now().toUtc());
  }

  String _restState() => _engine.timerFor(WatchTimerKind.rest)?.state ?? 'none';

  String _formatMs(int milliseconds) {
    final seconds = (milliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
