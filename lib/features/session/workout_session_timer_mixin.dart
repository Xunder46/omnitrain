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
  Set<String> get _loggedSetKeys;

  String _getEffortKind(String effortId);
  Map<String, dynamic>? _getEntryData(String effortId, int entryIndex);
  TimedInstance? _getTimedInstance(String effortId, int entryIndex);
  RoundInstance? _getRoundInstance(String effortId, int entryIndex);
  Future<void> _logSet();

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

  /// Keys for effort entries whose timer has been started at least once and
  /// has not yet been logged (reset). Cleared by [_resetTimerState].
  /// Used to prevent starting a second concurrent timer.
  final Set<String> _inProgressKeys = {};

  bool get _isAppInForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null) return true;
    return state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
  }

  /// Returns the first in-progress timer key that is NOT [currentKey],
  /// or null if no other timer is in-progress.
  String? _getAnotherInProgressKey(String currentKey) {
    for (final key in _inProgressKeys) {
      if (key != currentKey) return key;
    }
    return null;
  }

  /// Eagerly clears stale entries from [_inProgressKeys] for efforts whose
  /// timer has already expired by wall-clock time but whose periodic tick has
  /// not yet fired (user navigated faster than the tick interval), and for
  /// efforts already persisted as finished.
  ///
  /// Must be called inside `_toggleEffortTimer` before the in-progress-lock
  /// check so that a stale key never blocks the next entry from starting.
  void _drainStaleInProgressKeys() {
    // Snapshot the set: _handleEffortTimerExpired modifies _inProgressKeys.
    for (final key in List.of(_inProgressKeys)) {
      final sep = key.lastIndexOf('-');
      if (sep <= 0 || sep >= key.length - 1) continue;
      final effortId = key.substring(0, sep);
      final entryIndex = int.tryParse(key.substring(sep + 1));
      if (entryIndex == null) continue;
      final effortKind = _getEffortKind(effortId);
      if (effortKind == 'round') {
        final round = _getRoundInstance(effortId, entryIndex);
        if (round == null) continue;
        if (round.state == RoundState.finished) {
          _inProgressKeys.remove(key);
        } else if (round.plannedDurationSecs > 0 &&
            (round.elapsedMs / 1000).round() >= round.plannedDurationSecs) {
          // Wall-clock expired before the next tick. Fire the expiry handler
          // now; _effortAlerted guards against double-execution.
          _handleEffortTimerExpired(
            effortId,
            entryIndex,
            effortKind,
            round.plannedDurationSecs,
          );
        }
      } else if (effortKind == 'timed' || effortKind == 'drill') {
        final instance = _getTimedInstance(effortId, entryIndex);
        if (instance == null) continue;
        if (instance.state == TimedState.finished) {
          _inProgressKeys.remove(key);
        } else {
          final targetSecs = _getEffortTargetDuration(
            effortId,
            entryIndex,
            effortKind,
          );
          if (targetSecs > 0 &&
              (instance.elapsedMs / 1000).round() >= targetSecs) {
            _handleEffortTimerExpired(
              effortId,
              entryIndex,
              effortKind,
              targetSecs,
            );
          }
        }
      }
    }
  }

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
                _inProgressKeys.add(timerKey);
              }
            case TimedState.paused:
              _effortElapsed[timerKey] = (instance.elapsedMs / 1000).round();
              _effortRunning[timerKey] = false;
              _inProgressKeys.add(timerKey);
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
                _inProgressKeys.add(timerKey);
              }
            case RoundState.paused:
              _effortElapsed[timerKey] = (round.elapsedMs / 1000).round();
              _effortRunning[timerKey] = false;
              _inProgressKeys.add(timerKey);
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
    _cancelEffortExpiryNotification();
    _effortElapsed[timerKey] = 0;
    _effortTargetDuration.remove(timerKey);
    _effortAlerted[timerKey] = false;
    _inProgressKeys.remove(timerKey);
  }

  void _scheduleEffortExpiryNotification(
    String effortId,
    int entryIndex,
    String effortKind, {
    bool playSound = true,
  }
  ) {
    final targetSeconds = _getEffortTargetDuration(
      effortId,
      entryIndex,
      effortKind,
    );
    if (targetSeconds <= 0) {
      _cancelEffortExpiryNotification();
      return;
    }

    final timerKey = '$effortId-$entryIndex';
    final elapsedSeconds = _effortElapsed[timerKey] ?? 0;
    final remainingSeconds = targetSeconds - elapsedSeconds;
    if (remainingSeconds <= 0) {
      _cancelEffortExpiryNotification();
      return;
    }

    final fireAtMs =
        DateTime.now().millisecondsSinceEpoch + (remainingSeconds * 1000);
    unawaited(
      widget.restNotificationService.scheduleEffortTimerExpiry(
        fireAtMs: fireAtMs,
        soundId: widget.settingsState.effortTimerSound,
        playSound: playSound,
      ),
    );
  }

  void _cancelEffortExpiryNotification() {
    unawaited(widget.restNotificationService.cancelEffortTimerNotification());
  }

  void _resyncEffortExpiryForLifecycle({required bool appInForeground}) {
    if (appInForeground) {
      _cancelEffortExpiryNotification();
      return;
    }

    String? activeTimerKey;
    for (final entry in _effortRunning.entries) {
      if (entry.value == true) {
        activeTimerKey = entry.key;
        break;
      }
    }
    if (activeTimerKey == null) {
      _cancelEffortExpiryNotification();
      return;
    }

    final sep = activeTimerKey.lastIndexOf('-');
    if (sep <= 0 || sep == activeTimerKey.length - 1) {
      _cancelEffortExpiryNotification();
      return;
    }
    final effortId = activeTimerKey.substring(0, sep);
    final entryIndex = int.tryParse(activeTimerKey.substring(sep + 1));
    if (entryIndex == null) {
      _cancelEffortExpiryNotification();
      return;
    }

    final effortKind = _getEffortKind(effortId);
    _scheduleEffortExpiryNotification(
      effortId,
      entryIndex,
      effortKind,
      playSound: true,
    );
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
    _cancelEffortExpiryNotification();

    if (mounted) setState(() {});

    if (effortKind == 'round') {
      _effortTimers[timerKey]?.cancel();
      _effortRunning[timerKey] = false;
      // Clear the in-progress lock so the next round can be started.
      // Without this, _isSetLogged returns true once completeRound resolves,
      // the UI shows "LOGGED" (skipping the Log Round button), and the user
      // navigates forward via the arrow — never calling _logSet/_resetTimerState.
      // The stale key then blocks _toggleEffortTimer for the next round entry.
      _inProgressKeys.remove(timerKey);
      unawaited(
        widget.timerAlertService.fireEffortTimerAlert(
          widget.settingsState.effortTimerSound,
        ),
      );
      unawaited(widget.workoutState.completeRound(effortId, entryIndex));
      // Start the rest timer immediately on auto-expiry — parity with the
      // manual Log Round path in _logSet(). Mark the key as logged so that
      // when the user taps "Log Round" (or the arrow), _logSet() takes the
      // early-return path and does not create a second rest record.
      _loggedSetKeys.add(timerKey);
      unawaited(
        widget.workoutState.recordRestStart(effortId, entryIndex + 1),
      );
      unawaited(
        widget.restNotificationService.scheduleRestPings(
          restStartMs: DateTime.now().millisecondsSinceEpoch,
          intervalSecs: widget.settingsState.restPingInterval,
          soundId: widget.settingsState.restPingSound,
          playSound: !_isAppInForeground,
        ),
      );
      // Auto-advance to the next set — same as tapping the Log Round button.
      // Only advance when the expired entry is the one currently on screen;
      // if _drainStaleInProgressKeys fires this handler for a stale key while
      // the user is already viewing a different set, skip the advance.
      if (entryIndex == _currentSet - 1) {
        unawaited(_logSet());
      }
    } else {
      _effortTimers[timerKey]?.cancel();
      _effortRunning[timerKey] = false;
      // Clear the in-progress lock for timed/drill auto-expiry (parity with
      // the round path above). Without this, navigating forward via the arrow
      // after a timed entry auto-completes leaves a stale key that blocks
      // starting the next interval.
      _inProgressKeys.remove(timerKey);
      unawaited(
        widget.timerAlertService.fireEffortTimerAlert(
          widget.settingsState.effortTimerSound,
        ),
      );
      unawaited(widget.workoutState.finishTimedEntry(effortId, entryIndex));
      // Auto-advance to the next set — same as tapping the Log button.
      // Only advance when the expired entry is the one currently on screen.
      if (entryIndex == _currentSet - 1) {
        unawaited(_logSet());
      }
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
      if (_pendingRoundTransitions.contains(timerKey) &&
          round.state != RoundState.paused) {
        return;
      }
      if (round.state == RoundState.paused) {
        _pendingRoundTransitions.remove(timerKey);
      }

      switch (round.state) {
        case RoundState.finished:
          return;
        case RoundState.active:
          _effortElapsed[timerKey] = (round.elapsedMs / 1000).round();
          _pendingRoundTransitions.add(timerKey);
          _effortTimers[timerKey]?.cancel();
          _effortRunning[timerKey] = false;
          _cancelEffortExpiryNotification();
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
          _scheduleEffortExpiryNotification(
            effortId,
            entryIndex,
            effortKind,
            playSound: !_isAppInForeground,
          );
          if (mounted) setState(() {});
          widget.workoutState
              .resumeRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
        case RoundState.notStarted:
          // Drain any stale keys for efforts that have wall-clock expired but
          // whose periodic tick hasn't fired yet (user navigated faster than
          // the tick interval). Must run before the in-progress-lock check.
          _drainStaleInProgressKeys();
          // In-progress lock: block if another set's timer is already running.
          final otherKey = _getAnotherInProgressKey(timerKey);
          if (otherKey != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Another set is still in progress. Pause or finish it before starting a new timer.",
                  ),
                ),
              );
            }
            return;
          }
          _inProgressKeys.add(timerKey);
          _pendingRoundTransitions.add(timerKey);
          _effortRunning[timerKey] = true;
          _effortTimers[timerKey]?.cancel();
          _effortTimers[timerKey] = Timer.periodic(
            _kTimerUpdateInterval,
            (_) => _onEffortTick(effortId, entryIndex),
          );
          _scheduleEffortExpiryNotification(
            effortId,
            entryIndex,
            effortKind,
            playSound: !_isAppInForeground,
          );
          if (mounted) setState(() {});
          unawaited(widget.workoutState.closeAllOpenRests(effortId));
          unawaited(widget.restNotificationService.cancelRestNotifications());
          _lastRestPingFiredAt.remove(effortId);
          widget.workoutState
              .startRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
      }
      return;
    }

    final instance = _getTimedInstance(effortId, entryIndex);
    if (instance == null) return;
    if (_pendingTimedTransitions.contains(timerKey) &&
        instance.state != TimedState.paused) {
      return;
    }
    if (instance.state == TimedState.paused) {
      _pendingTimedTransitions.remove(timerKey);
    }

    switch (instance.state) {
      case TimedState.finished:
        return;
      case TimedState.active:
        _effortElapsed[timerKey] = (instance.elapsedMs / 1000).round();
        _pendingTimedTransitions.add(timerKey);
        _effortTimers[timerKey]?.cancel();
        _effortRunning[timerKey] = false;
        _cancelEffortExpiryNotification();
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
        _scheduleEffortExpiryNotification(
          effortId,
          entryIndex,
          effortKind,
          playSound: !_isAppInForeground,
        );
        if (mounted) setState(() {});
        widget.workoutState
            .resumeTimedEntry(effortId, entryIndex)
            .whenComplete(() => _pendingTimedTransitions.remove(timerKey));
      case TimedState.notStarted:
        // Drain stale keys before the in-progress-lock check (same reason as
        // the round notStarted branch above).
        _drainStaleInProgressKeys();
        // In-progress lock: block if another set's timer is already running.
        final otherKey = _getAnotherInProgressKey(timerKey);
        if (otherKey != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Another set is still in progress. Pause or finish it before starting a new timer.",
                ),
              ),
            );
          }
          return;
        }
        _inProgressKeys.add(timerKey);
        _pendingTimedTransitions.add(timerKey);
        _effortRunning[timerKey] = true;
        _effortTimers[timerKey]?.cancel();
        _effortTimers[timerKey] = Timer.periodic(
          _kTimerUpdateInterval,
          (_) => _onEffortTick(effortId, entryIndex),
        );
        _scheduleEffortExpiryNotification(
          effortId,
          entryIndex,
          effortKind,
          playSound: !_isAppInForeground,
        );
        if (mounted) setState(() {});
        unawaited(widget.workoutState.closeAllOpenRests(effortId));
        unawaited(widget.restNotificationService.cancelRestNotifications());
        _lastRestPingFiredAt.remove(effortId);
        widget.workoutState.startTimedEntry(effortId, entryIndex).whenComplete(
          () {
            _pendingTimedTransitions.remove(timerKey);
            if (!mounted) return;
            setState(() {
              _effortTargetDuration.remove(timerKey);
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
    _cancelEffortExpiryNotification();

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
