part of 'workout_session_screen.dart';

/// Timer mixin for [WorkoutSessionScreen].
///
/// Owns all per-effort timer UI state (maps keyed by `$effortId-$entryIndex`)
/// and all timer lifecycle methods: toggle, tick, pause, freeze, persist, reset.
///
/// Added to [_WorkoutSessionScreenState] via `with WorkoutSessionTimerMixin`.
/// Because this is a `mixin on State<WorkoutSessionScreen>`, all mixin methods
/// have access to `widget`, `mounted`, and `setState` from [State].
mixin WorkoutSessionTimerMixin on State<WorkoutSessionScreen> {
  // ── Abstract dependencies provided by _WorkoutSessionScreenState ──────────

  List<Map<String, dynamic>> get _exercises;
  int get _currentSet;
  Timer? get _ticker;
  Map<String, int> get _lastRestPingFiredAt;

  String _getEffortKind(String effortId);
  Map<String, dynamic>? _getEntryData(String effortId, int entryIndex);
  TimedInstance? _getTimedInstance(String effortId, int entryIndex);
  RoundInstance? _getRoundInstance(String effortId, int entryIndex);

  // ── Per-effort timer UI state ─────────────────────────────────────────────

  /// Active [Timer] periodic ticks for each effort entry.
  final Map<String, Timer?> _effortTimers = {};

  /// Whether each effort timer is currently running.
  final Map<String, bool> _effortRunning = {};

  /// Elapsed seconds display cache (derived from wall-clock on each tick).
  final Map<String, int> _effortElapsed = {};

  /// Whether the expiry alert was already fired for this entry.
  final Map<String, bool> _effortAlerted = {};

  /// Target seconds for countdown / expiry check.
  final Map<String, int> _effortTargetDuration = {};

  /// Keys for round-state transitions in-flight (debounce double-taps).
  final Set<String> _pendingRoundTransitions = {};

  /// Keys for timed-state transitions in-flight (debounce double-taps).
  final Set<String> _pendingTimedTransitions = {};

  // ── Timer restore from persisted state ───────────────────────────────────

  /// Restore timer UI state from persisted [TimedInstance] and [RoundInstance]
  /// records after [_loadExercises()] fetches live data.
  ///
  /// Called from inside the [setState] block of [_loadExercises] so all map
  /// writes happen in a single synchronous batch before the next frame.
  void _restoreTimerStateFromPersisted(List<Map<String, dynamic>> exercises) {
    for (final exercise in exercises) {
      final effortId = exercise['id'] as String;
      final effortKind = exercise['effortKind'] as String? ?? 'set';
      final entries = exercise['entries'] as List<Map<String, dynamic>>? ?? [];

      if (effortKind == 'timed' || effortKind == 'drill') {
        for (int i = 0; i < entries.length; i++) {
          final timerKey = '$effortId-$i';
          final instance = _getTimedInstance(effortId, i);
          if (instance == null) continue;

          _effortTargetDuration[timerKey] = instance.targetDurationSecs;

          switch (instance.state) {
            case TimedState.active:
              final elapsedSecs = (instance.elapsedMs / 1000).round();
              final targetSecs = instance.targetDurationSecs;
              if (targetSecs > 0 && elapsedSecs >= targetSecs) {
                unawaited(widget.workoutState.finishTimedEntry(effortId, i));
                _effortElapsed[timerKey] = targetSecs;
                _effortAlerted[timerKey] = true;
              } else {
                _effortElapsed[timerKey] = elapsedSecs;
                _effortRunning[timerKey] ??= false;
              }
            case TimedState.paused:
              _effortElapsed[timerKey] =
                  (instance.elapsedMs / 1000).round();
              _effortRunning[timerKey] = false;
            case TimedState.finished:
              _effortElapsed[timerKey] = instance.actualDurationSecs;
              _effortAlerted[timerKey] = instance.targetDurationSecs > 0;
            case TimedState.notStarted:
              _effortElapsed[timerKey] = 0;
          }
        }
      } else if (effortKind == 'round') {
        for (int i = 0; i < entries.length; i++) {
          final timerKey = '$effortId-$i';
          final round = _getRoundInstance(effortId, i);
          if (round == null) continue;

          _effortTargetDuration[timerKey] = round.plannedDurationSecs;

          switch (round.state) {
            case RoundState.active:
              final elapsedMs = round.elapsedMs;
              final elapsedSecs = (elapsedMs / 1000).round();
              if (elapsedSecs >= round.plannedDurationSecs) {
                unawaited(widget.workoutState.completeRound(effortId, i));
                _effortElapsed[timerKey] = round.plannedDurationSecs;
                _effortAlerted[timerKey] = true;
              } else {
                _effortElapsed[timerKey] = elapsedSecs;
                _effortRunning[timerKey] ??= false;
              }
            case RoundState.paused:
              _effortElapsed[timerKey] = (round.elapsedMs / 1000).round();
              _effortRunning[timerKey] = false;
            case RoundState.finished:
              _effortElapsed[timerKey] = round.actualDurationSecs;
              _effortAlerted[timerKey] = round.completed;
            case RoundState.notStarted:
              _effortElapsed[timerKey] = 0;
          }
        }
      }
    }
  }

  // ── Timer state helpers ───────────────────────────────────────────────────

  /// Reset all timer UI state for a specific effort entry.
  /// Called after logging a set to prepare for the next entry.
  void _resetTimerState(String effortId, int entryIndex) {
    final timerKey = '$effortId-$entryIndex';
    _effortTimers[timerKey]?.cancel();
    _effortRunning[timerKey] = false;
    _effortElapsed[timerKey] = 0;
    _effortTargetDuration.remove(timerKey);
    _effortAlerted[timerKey] = false;
  }

  int _getEffortTargetDuration(
    String effortId,
    int entryIndex,
    String effortKind,
  ) {
    final timerKey = '$effortId-$entryIndex';
    final cachedTarget = _effortTargetDuration[timerKey];
    if (cachedTarget != null) return cachedTarget;
    final entry = _getEntryData(effortId, entryIndex);
    if (entry == null) return 0;
    switch (effortKind) {
      case 'timed':
      case 'drill':
        return entry['duration'] as int? ?? 0;
      case 'round':
        return entry['round-duration'] as int? ?? 0;
      default:
        return 0;
    }
  }

  bool _isEffortExpired(String effortId, int entryIndex, String effortKind) {
    if (effortKind == 'timed' || effortKind == 'drill') {
      final instance = _getTimedInstance(effortId, entryIndex);
      if (instance?.state == TimedState.finished) return true;
    }
    final timerKey = '$effortId-$entryIndex';
    final target = _getEffortTargetDuration(effortId, entryIndex, effortKind);
    final elapsed = _effortElapsed[timerKey] ?? 0;
    final isRunning = _effortRunning[timerKey] ?? false;
    return target > 0 && elapsed >= target && !isRunning;
  }

  void _resetEffortAlertState(String effortId, int entryIndex) {
    final timerKey = '$effortId-$entryIndex';
    _effortAlerted[timerKey] = false;
  }

  void _handleEffortTimerExpired(
    String effortId,
    int entryIndex,
    String effortKind,
    int targetSeconds,
  ) {
    final timerKey = '$effortId-$entryIndex';
    if (_effortAlerted[timerKey] == true) return;

    _effortAlerted[timerKey] = true;
    _effortElapsed[timerKey] = targetSeconds;

    if (mounted) setState(() {});

    if (effortKind == 'round') {
      _effortTimers[timerKey]?.cancel();
      _effortRunning[timerKey] = false;
      unawaited(widget.timerAlertService.fireEffortTimerAlert(
        widget.settingsState.effortTimerSound,
      ));
      unawaited(widget.workoutState.completeRound(effortId, entryIndex));
    } else {
      _effortTimers[timerKey]?.cancel();
      _effortRunning[timerKey] = false;
      unawaited(widget.timerAlertService.fireEffortTimerAlert(
        widget.settingsState.effortTimerSound,
      ));
      unawaited(widget.workoutState.finishTimedEntry(effortId, entryIndex));
    }
  }

  // ── Timer toggle / tick / pause ───────────────────────────────────────────

  void _toggleEffortTimer(String effortId) {
    final entryIndex = _currentSet - 1;
    final timerKey = '$effortId-$entryIndex';
    final effortKind = _getEffortKind(effortId);

    if (effortKind == 'round') {
      final round = _getRoundInstance(effortId, entryIndex);
      if (round == null) return;
      if (_pendingRoundTransitions.contains(timerKey)) return;

      switch (round.state) {
        case RoundState.finished:
          return;
        case RoundState.active:
          _effortElapsed[timerKey] = (round.elapsedMs / 1000).round();
          _pendingRoundTransitions.add(timerKey);
          _effortTimers[timerKey]?.cancel();
          _effortRunning[timerKey] = false;
          if (mounted) setState(() {});
          widget.workoutState
              .pauseRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
        case RoundState.paused:
          _pendingRoundTransitions.add(timerKey);
          _effortRunning[timerKey] = true;
          _effortTimers[timerKey]?.cancel();
          _effortTimers[timerKey] = Timer.periodic(
            _kTimerUpdateInterval,
            (_) => _onEffortTick(effortId, entryIndex),
          );
          if (mounted) setState(() {});
          widget.workoutState
              .resumeRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
        case RoundState.notStarted:
          _pendingRoundTransitions.add(timerKey);
          _effortRunning[timerKey] = true;
          _effortTimers[timerKey]?.cancel();
          _effortTimers[timerKey] = Timer.periodic(
            _kTimerUpdateInterval,
            (_) => _onEffortTick(effortId, entryIndex),
          );
          if (mounted) setState(() {});
          unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
          _lastRestPingFiredAt.remove(effortId);
          widget.workoutState
              .startRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
      }
      return;
    }

    if (_pendingTimedTransitions.contains(timerKey)) return;
    final instance = _getTimedInstance(effortId, entryIndex);
    if (instance == null) return;

    switch (instance.state) {
      case TimedState.finished:
        return;
      case TimedState.active:
        _effortElapsed[timerKey] = (instance.elapsedMs / 1000).round();
        _pendingTimedTransitions.add(timerKey);
        _effortTimers[timerKey]?.cancel();
        _effortRunning[timerKey] = false;
        if (mounted) setState(() {});
        widget.workoutState
            .pauseTimedEntry(effortId, entryIndex)
            .whenComplete(() => _pendingTimedTransitions.remove(timerKey));
      case TimedState.paused:
        _pendingTimedTransitions.add(timerKey);
        _effortRunning[timerKey] = true;
        _effortTimers[timerKey]?.cancel();
        _effortTimers[timerKey] = Timer.periodic(
          _kTimerUpdateInterval,
          (_) => _onEffortTick(effortId, entryIndex),
        );
        if (mounted) setState(() {});
        widget.workoutState
            .resumeTimedEntry(effortId, entryIndex)
            .whenComplete(() => _pendingTimedTransitions.remove(timerKey));
      case TimedState.notStarted:
        _pendingTimedTransitions.add(timerKey);
        _effortRunning[timerKey] = true;
        _effortTimers[timerKey]?.cancel();
        _effortTimers[timerKey] = Timer.periodic(
          _kTimerUpdateInterval,
          (_) => _onEffortTick(effortId, entryIndex),
        );
        if (mounted) setState(() {});
        unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
        _lastRestPingFiredAt.remove(effortId);
        widget.workoutState.startTimedEntry(effortId, entryIndex).whenComplete(
          () {
            _pendingTimedTransitions.remove(timerKey);
            if (!mounted) return;
            setState(() {
              _effortTargetDuration[timerKey] = 0;
            });
          },
        );
    }
  }

  void _onEffortTick(String effortId, int entryIndex) {
    final session = widget.workoutState.currentSession;
    if (session == null || session.endedAtMs != null) return;

    final timerKey = '$effortId-$entryIndex';
    final effortKind = _getEffortKind(effortId);
    final targetSeconds = _getEffortTargetDuration(
      effortId,
      entryIndex,
      effortKind,
    );

    final int elapsed;
    if (effortKind == 'round') {
      if (_pendingRoundTransitions.contains(timerKey)) return;
      final round = _getRoundInstance(effortId, entryIndex);
      if (round == null || round.state != RoundState.active) return;
      elapsed = (round.elapsedMs / 1000).round();
    } else {
      if (_pendingTimedTransitions.contains(timerKey)) return;
      final instance = _getTimedInstance(effortId, entryIndex);
      if (instance == null || instance.state != TimedState.active) return;
      elapsed = (instance.elapsedMs / 1000).round();
    }

    if (targetSeconds > 0 && elapsed >= targetSeconds) {
      _handleEffortTimerExpired(
        effortId,
        entryIndex,
        effortKind,
        targetSeconds,
      );
      return;
    }

    if (mounted) {
      setState(() {
        _effortElapsed[timerKey] = elapsed;
      });
    }
  }

  void _pauseEffortTimer(
    String effortId,
    int entryIndex, {
    String? effortKindOverride,
  }) {
    final timerKey = '$effortId-$entryIndex';
    _effortRunning[timerKey] = false;
    _effortTimers[timerKey]?.cancel();

    final effortKind = effortKindOverride ?? _getEffortKind(effortId);
    if (effortKind == 'round') {
      unawaited(widget.workoutState.pauseRound(effortId, entryIndex));
      return;
    }
    if (effortKind == 'timed' || effortKind == 'drill') {
      unawaited(widget.workoutState.pauseTimedEntry(effortId, entryIndex));
    }
  }

  // ── Session finish / freeze ───────────────────────────────────────────────

  /// Cancels all effort [Timer]s and marks every key as not running.
  /// Also cancels the global [_ticker]. Call before finishing or discarding.
  void _freezeAllLocalTimers() {
    _ticker?.cancel();
    for (final timer in _effortTimers.values) {
      timer?.cancel();
    }
    for (final key in _effortTimers.keys) {
      _effortRunning[key] = false;
    }
  }

  /// Ends any in-progress round/timed/drill timers and persists elapsed to
  /// the repository. Must be called before navigating away (e.g. Finish Workout).
  Future<void> _persistActiveEffortTimers() async {
    for (final exercise in _exercises) {
      final effortId = exercise['id'] as String;
      final effortKind = exercise['effortKind'] as String? ?? 'set';
      if (effortKind != 'round' &&
          effortKind != 'timed' &&
          effortKind != 'drill') {
        continue;
      }

      final entries = exercise['entries'] as List<Map<String, dynamic>>? ?? [];
      for (int i = 0; i < entries.length; i++) {
        final timerKey = '$effortId-$i';

        if (effortKind == 'round') {
          final round = _getRoundInstance(effortId, i);
          if (round != null &&
              (round.state == RoundState.active ||
                  round.state == RoundState.paused)) {
            await widget.workoutState.endRoundEarly(effortId, i);
          }
        } else {
          final instance = _getTimedInstance(effortId, i);
          if (instance != null &&
              (instance.state == TimedState.active ||
                  instance.state == TimedState.paused)) {
            await widget.workoutState.finishTimedEntry(effortId, i);
          }
        }

        _effortAlerted[timerKey] = false;
      }
    }
  }
}
