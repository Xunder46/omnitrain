import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/constants/workout_constants.dart';
import '../../state/settings/settings_state.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../state/workout/workout_state.dart';
import '../../widgets/pickers/exercise_picker_dialog.dart';
import '../../widgets/pickers/metric_chooser_dialog.dart';
import '../../widgets/pickers/modality_picker_dialog.dart';
import '../../core/constants/modality_config.dart';
import '../../data/models/models.dart';
import '../../widgets/session/inline_metric_editor.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../state/routine/routine_state.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/models/session_edit_snapshot.dart';
import 'session_summary_screen.dart';

/// Actions surfaced by the "Unsaved changes" dialog shown when the user
/// tries to leave edit mode without saving.
enum _EditBackAction { save, discard, close }

class WorkoutSessionScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;
  final Future<void> Function(String sessionId)? onSessionSaved;
  final String? initialFocusId;
  final SettingsState? settingsState;

  /// When true the screen shows a frozen review/edit view of a completed session:
  /// no timers run, no set logging, values remain editable for correction.
  final bool editMode;

  const WorkoutSessionScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
    this.onSessionSaved,
    this.initialFocusId,
    this.settingsState,
    this.editMode = false,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  // Constants
  static const Duration _timerUpdateInterval = Duration(seconds: 1);

  List<Map<String, dynamic>> _exercises = [];
  int _currentExerciseIndex = 0;
  int _currentSet = 1;
  bool _isLoading = true;
  bool _showListView =
      true; // Toggle between list view and detail view - default to list
  bool _hasError = false;
  String _errorMessage = '';

  // Track skipped sets per effort (UI-only state)
  final Map<String, Set<int>> _skippedSets = {};

  // Track which set keys have been logged this session (effortId-entryIndex).
  // Prevents the rest timer from restarting when navigating back/forward
  // through already-logged sets.
  final Set<String> _loggedSetKeys = {};

  Timer? _ticker;
  String _elapsedFormatted = '00:00';

  // Per-effort timer state for timed and round exercises
  final Map<String, Timer?> _effortTimers = {};
  final Map<String, bool> _effortRunning = {};
  final Map<String, int> _effortElapsed =
      {}; // Elapsed seconds (UI display cache)
  final Map<String, bool> _effortAlerted = {}; // Timer expiry alert fired
  final Map<String, int> _effortTargetDuration =
      {}; // Target seconds for countdown/expiry

  // Guards against rapid double-taps dispatching duplicate state transitions
  // before the first async write resolves.
  final Set<String> _pendingRoundTransitions = {};
  final Set<String> _pendingTimedTransitions = {};

  // Edit mode buffer: tracks pending changes that haven't been saved yet.
  // Key: 'effortId-entryIndex', Value: map of metricKey -> value.
  // Changes are flushed to the repository only when Save is clicked.
  final Map<String, Map<String, dynamic>> _editBuffer = {};

  // Prevent duplicate finish flows from double taps.
  bool _isFinishingSession = false;

  // Edit-mode snapshot captured once after session data first loads.
  // Used by _discardEditChanges() to roll back structural mutations
  // (add/remove exercise, add/remove set) that bypass the edit buffer.
  // Null when not in edit mode or after a successful Save.
  SessionEditSnapshot? _editSnapshot;

  // True when any structural change (add/remove exercise, add/remove set)
  // was made during this edit session. Combined with _editBuffer to decide
  // whether to show the "Discard changes?" dialog on back.
  bool _hasStructuralChanges = false;

  // Pending session-duration override in edit mode (seconds from start).
  // Initialised from persisted timestamps when entering edit mode.
  // Null in live (non-edit) mode.
  int? _pendingDurationSecs;
  int? _originalDurationSecs;
  int _focusRequestId = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.editMode) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _tick();
    } else {
      _computeStaticElapsed();
    }
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    setState(() => _isLoading = true);
    try {
      int? initialDetailIndex;
      int initialDetailSet = 1;

      if (!widget.workoutState.hasSession) {
        await widget.workoutState.createNewSession();
      }
      await widget.workoutState.loadSessionData();
      final exercises = widget.workoutState.getExercisesWithEntries();
      setState(() {
        _exercises = exercises;

        // Pre-populate timer state from persisted entries for all timer-based exercises
        for (final exercise in exercises) {
          final effortId = exercise['id'] as String;
          final effortKind = exercise['effortKind'] as String? ?? 'set';
          final entries =
              exercise['entries'] as List<Map<String, dynamic>>? ?? [];

          // Restore timer values for all timer-based effort kinds
          if (effortKind == 'timed' || effortKind == 'drill') {
            // Restore from TimedInstance records (wall-clock based — background resilient).
            for (int i = 0; i < entries.length; i++) {
              final timerKey = '$effortId-$i';
              final instance = _getTimedInstance(effortId, i);
              if (instance == null) continue;

              _effortTargetDuration[timerKey] = instance.targetDurationSecs;

              switch (instance.state) {
                case TimedState.active:
                  // Derive elapsed from wall-clock timestamps
                  final elapsedSecs = (instance.elapsedMs / 1000).round();
                  final targetSecs = instance.targetDurationSecs;
                  if (targetSecs > 0 && elapsedSecs >= targetSecs) {
                    // Should have finished while app was backgrounded — auto-finish.
                    unawaited(
                      widget.workoutState.finishTimedEntry(effortId, i),
                    );
                    _effortElapsed[timerKey] = targetSecs;
                    _effortAlerted[timerKey] = true;
                  } else {
                    _effortElapsed[timerKey] = elapsedSecs;
                    // Do NOT auto-resume — user must tap play.
                    // ??= so a _loadExercises() re-run never clobbers a true user tap.
                    _effortRunning[timerKey] ??= false;
                  }
                  break;
                case TimedState.paused:
                  _effortElapsed[timerKey] = (instance.elapsedMs / 1000)
                      .round();
                  _effortRunning[timerKey] = false;
                  break;
                case TimedState.finished:
                  _effortElapsed[timerKey] = instance.actualDurationSecs;
                  _effortAlerted[timerKey] = instance.targetDurationSecs > 0;
                  break;
                case TimedState.notStarted:
                  _effortElapsed[timerKey] = 0;
                  break;
              }
            }
          } else if (effortKind == 'round') {
            // Round timers: restore from RoundInstance state.
            for (int i = 0; i < entries.length; i++) {
              final timerKey = '$effortId-$i';
              final round = _getRoundInstance(effortId, i);
              if (round == null) continue;

              _effortTargetDuration[timerKey] = round.plannedDurationSecs;

              switch (round.state) {
                case RoundState.active:
                  // Recalculate elapsed from timestamps
                  final elapsedMs = round.elapsedMs;
                  final elapsedSecs = (elapsedMs / 1000).round();
                  if (elapsedSecs >= round.plannedDurationSecs) {
                    // Should have completed while backgrounded — auto-complete
                    unawaited(widget.workoutState.completeRound(effortId, i));
                    _effortElapsed[timerKey] = round.plannedDurationSecs;
                    _effortAlerted[timerKey] = true;
                  } else {
                    _effortElapsed[timerKey] = elapsedSecs;
                    // Do NOT auto-resume — user must tap play.
                    // Use ??= so a _loadExercises() re-run (e.g. from _updateMetricValue)
                    // never clobbers a true that was set when the user tapped play.
                    _effortRunning[timerKey] ??= false;
                  }
                  break;
                case RoundState.paused:
                  // Show remaining based on elapsed at pause time
                  _effortElapsed[timerKey] = (round.elapsedMs / 1000).round();
                  _effortRunning[timerKey] = false;
                  break;
                case RoundState.finished:
                  _effortElapsed[timerKey] = round.actualDurationSecs;
                  _effortAlerted[timerKey] = round.completed;
                  break;
                case RoundState.notStarted:
                  _effortElapsed[timerKey] = 0;
                  break;
              }
            }
          }
        }

        // Pre-populate _loggedSetKeys from persisted data to prevent rest timer
        // resets when navigating through already-completed exercises.
        for (final exercise in _exercises) {
          final effortId = exercise['id'] as String;
          final effortKind = exercise['effortKind'] as String? ?? 'set';
          final entries =
              exercise['entries'] as List<Map<String, dynamic>>? ?? [];

          for (int i = 0; i < entries.length; i++) {
            final logKey = '$effortId-$i';
            if (_isSetLogged(effortId, i, effortKind)) {
              _loggedSetKeys.add(logKey);
            }
          }
        }

        // Restore focus to the exercise and set number if requested
        final initialId = widget.initialFocusId;
        if (initialId != null && initialId.isNotEmpty) {
          final idx = _exercises.indexWhere((e) => e['id'] == initialId);
          if (idx != -1) {
            final exercise = _exercises[idx];
            final entries =
                exercise['entries'] as List<Map<String, dynamic>>? ?? [];
            // Restore to the current/last entry position
            initialDetailIndex = idx;
            initialDetailSet = entries.isNotEmpty ? entries.length : 1;
          }
        }

        if (_currentExerciseIndex >= _exercises.length &&
            _exercises.isNotEmpty) {
          _currentExerciseIndex = 0;
          _currentSet = 1;
        }
        _isLoading = false;
      });

      // Capture a rollback snapshot the FIRST time _loadExercises() completes
      // in edit mode.  Subsequent re-runs (after add/remove set) must NOT
      // overwrite it — the null-check guard ensures the snapshot always
      // reflects the state the user started editing from, not a mid-edit reload.
      if (widget.editMode && _editSnapshot == null) {
        _editSnapshot = widget.workoutState.snapshotSessionState();
      }

      if (initialDetailIndex != null) {
        await _focusExerciseDetail(
          initialDetailIndex!,
          setNumber: initialDetailSet,
        );
      }
    } catch (e) {
      print('Error loading exercises: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic>? _getExerciseById(String effortId) {
    try {
      return _exercises.firstWhere((exercise) => exercise['id'] == effortId);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _getEntryData(String effortId, int entryIndex) {
    final exercise = _getExerciseById(effortId);
    if (exercise == null) return null;
    final entries = exercise['entries'] as List<Map<String, dynamic>>? ?? [];
    if (entryIndex < 0 || entryIndex >= entries.length) return null;
    return entries[entryIndex];
  }

  String? _exerciseIdForIndex(int index) {
    if (index < 0 || index >= _exercises.length) return null;
    return _exercises[index]['exerciseId'] as String?;
  }

  Future<void> _loadExerciseNoteForIndex(int index) async {
    final exerciseId = _exerciseIdForIndex(index);
    if (exerciseId == null) return;
    await widget.workoutState.loadExerciseNote(exerciseId);
  }

  Future<void> _focusExerciseDetail(int index, {int setNumber = 1}) async {
    if (!mounted || index < 0 || index >= _exercises.length) return;
    final requestId = ++_focusRequestId;

    // **Await** note load BEFORE transitioning to detail mode.
    // This guarantees cache is populated before rendering note-dependent UI.
    await _loadExerciseNoteForIndex(index);

    if (!mounted || requestId != _focusRequestId) return;

    setState(() {
      _currentExerciseIndex = index;
      _currentSet = setNumber;
      _showListView = false;
    });
  }

  /// Get the RoundInstance for a specific round (effortId + roundIndex).
  /// Returns null if the round doesn't exist or isn't a round-kind effort.
  RoundInstance? _getRoundInstance(String effortId, int roundIndex) {
    final rounds = widget.workoutState.getRoundsForEffort(effortId);
    if (roundIndex < 0 || roundIndex >= rounds.length) return null;
    return rounds[roundIndex];
  }

  /// Get the TimedInstance for a specific timed/drill entry (effortId + entryIndex).
  /// Returns null if the entry doesn't exist or isn't a timed/drill effort.
  TimedInstance? _getTimedInstance(String effortId, int entryIndex) {
    final instances = widget.workoutState.getTimedInstancesForEffort(effortId);
    if (entryIndex < 0 || entryIndex >= instances.length) return null;
    return instances[entryIndex];
  }

  String _getEffortKind(String effortId) {
    final exercise = _getExerciseById(effortId);
    return exercise?['effortKind'] as String? ?? 'set';
  }

  /// Check if a set/entry has been logged (completed) based on persisted state.
  /// Used to pre-populate _loggedSetKeys and prevent rest timer resets.
  bool _isSetLogged(String effortId, int entryIndex, String effortKind) {
    if (effortKind == 'set') {
      // Set is logged only if rest was created for the NEXT entry.
      // This ensures we only detect sets that went through the full Log Set flow,
      // not just sets where reps were entered. Prevents premature rest skipping.
      final rests = widget.workoutState.getEntryRests(effortId);
      final nextEntryIndex = entryIndex + 1;
      return rests.any((r) => r.entryIndex == nextEntryIndex);
    } else if (effortKind == 'timed' || effortKind == 'drill') {
      // Timed/drill is logged if TimedInstance is finished
      final instance = _getTimedInstance(effortId, entryIndex);
      return instance?.state == TimedState.finished;
    } else if (effortKind == 'round') {
      // Round is logged if RoundInstance is finished
      final round = _getRoundInstance(effortId, entryIndex);
      return round?.state == RoundState.finished;
    }
    return false;
  }

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
    // For timed/drill, the authoritative source is the TimedInstance lifecycle
    // state. A finished instance is always expired, regardless of UI map values.
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

    if (mounted) {
      setState(() {});
    }

    if (effortKind == 'round') {
      // Natural completion — countdown reached zero.
      // Stop the tick timer directly WITHOUT going through _pauseEffortTimer.
      // Calling _pauseEffortTimer here would fire pauseRound() concurrently with
      // completeRound(), creating a write race where the last async write wins
      // non-deterministically and can leave the round stuck in 'paused'.
      _effortTimers[timerKey]?.cancel();
      _effortRunning[timerKey] = false;
      unawaited(TimerAlertService.fireTimerExpiredAlert());
      unawaited(widget.workoutState.completeRound(effortId, entryIndex));
    } else {
      // Open-ended efforts (timed/drill) — finish the TimedInstance and alert user.
      // Cancel the tick timer directly (no _pauseEffortTimer, which would call
      // pauseTimedEntry and create a write race with finishTimedEntry).
      _effortTimers[timerKey]?.cancel();
      _effortRunning[timerKey] = false;
      unawaited(TimerAlertService.fireTimerExpiredAlert());
      unawaited(widget.workoutState.finishTimedEntry(effortId, entryIndex));
    }
  }

  Future<void> _logSet() async {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    // If this set was already logged (navigating through completed exercises),
    // just advance without re-persisting or resetting the rest timer.
    final logKey = '$effortId-${_currentSet - 1}';
    if (_loggedSetKeys.contains(logKey)) {
      setState(() {
        if (_currentSet < entries.length) {
          _currentSet++;
        } else {
          // Move to next exercise
          if (_currentExerciseIndex < _exercises.length - 1) {
            _currentExerciseIndex++;
            _currentSet = 1;
          } else {
            // All exercises complete - show finish option
            _showFinishDialog();
          }
        }
      });
      return;
    }

    // Get current entry data to persist
    final currentEntry = _currentSet <= entries.length
        ? entries[_currentSet - 1]
        : <String, dynamic>{};

    // Set-kind entries with zero reps are treated as skipped. In that case,
    // keep any existing rest window running instead of closing/restarting it.
    final isSkippedSetKindEntry =
        effortKind == 'set' && ((currentEntry['reps'] as int?) ?? 0) <= 0;

    // For round/timed/drill, advancing without ever starting the entry is a skip.
    // Keep the existing rest window running (do not create a new rest record).
    final roundInstance = effortKind == 'round'
        ? _getRoundInstance(effortId, _currentSet - 1)
        : null;
    final timedInstance = (effortKind == 'timed' || effortKind == 'drill')
        ? _getTimedInstance(effortId, _currentSet - 1)
        : null;
    final isSkippedRoundEntry =
        effortKind == 'round' && roundInstance?.state == RoundState.notStarted;
    final isSkippedTimedEntry =
        (effortKind == 'timed' || effortKind == 'drill') &&
        timedInstance?.state == TimedState.notStarted;
    final isSkippedEntry =
        isSkippedSetKindEntry || isSkippedRoundEntry || isSkippedTimedEntry;

    // On real set logs, close the latest open rest window first.
    if (effortKind == 'set' && !isSkippedSetKindEntry) {
      final rests = widget.workoutState.getEntryRests(effortId);
      int? openRestEntryIndex;
      for (final rest in rests) {
        if (rest.restEndMs == null &&
            (openRestEntryIndex == null ||
                rest.entryIndex > openRestEntryIndex)) {
          openRestEntryIndex = rest.entryIndex;
        }
      }
      if (openRestEntryIndex != null) {
        await widget.workoutState.recordRestEnd(effortId, openRestEntryIndex);
      }
    }

    // For timed/drill: finish the TimedInstance to persist wall-clock duration.
    // Safe no-op if already finished via timer expiry.
    if ((effortKind == 'timed' || effortKind == 'drill') &&
        !isSkippedTimedEntry) {
      unawaited(
        widget.workoutState.finishTimedEntry(effortId, _currentSet - 1),
      );
    }

    // Round persistence via RoundInstance (not observations):
    // If countdown completed naturally, completeRound() was already called in
    // _handleEffortTimerExpired. Otherwise, call endRoundEarly now.
    if (effortKind == 'round') {
      final round = roundInstance;
      if (round != null && round.state != RoundState.finished) {
        // End early if not already finished
        unawaited(widget.workoutState.endRoundEarly(effortId, _currentSet - 1));
      }
    }

    // Persist observation-based entries (set / timed / drill only; round uses RoundInstance)
    if (effortKind != 'round') {
      await _persistEntryValues(
        effortId,
        _currentSet - 1,
        effortKind,
        currentEntry,
      );
    }

    // Haptic feedback on successful log
    if (!kIsWeb) {
      HapticFeedback.lightImpact();
    }

    // Stop and reset timer UI state; user must explicitly start timer for the next entry.
    if (effortKind == 'timed' ||
        effortKind == 'drill' ||
        effortKind == 'round') {
      _resetTimerState(effortId, _currentSet - 1);
    }

    // Start rest tracking on first real log of this set, persisting to database.
    // Navigating back and re-pressing forward must NOT restart rest tracking.
    if (!_loggedSetKeys.contains(logKey) && !isSkippedEntry) {
      _loggedSetKeys.add(logKey);
      final nextEntryIndex = _currentSet; // 0-based index
      if (effortKind == 'set') {
        await widget.workoutState.recordRestStart(effortId, nextEntryIndex);
      } else {
        unawaited(
          widget.workoutState.recordRestStart(effortId, nextEntryIndex),
        );
      }
    }

    // Advance to next set or next exercise
    int? nextExerciseIndex;
    setState(() {
      if (_currentSet < entries.length) {
        _currentSet++;
      } else {
        // Move to next exercise
        if (_currentExerciseIndex < _exercises.length - 1) {
          _currentExerciseIndex++;
          _currentSet = 1;
          nextExerciseIndex = _currentExerciseIndex;
        } else {
          // All exercises complete - show finish option
          _showFinishDialog();
        }
      }
    });

    if (nextExerciseIndex != null) {
      unawaited(_loadExerciseNoteForIndex(nextExerciseIndex!));
    }
  }

  void _previousSet() {
    if (_exercises.isEmpty) return;
    if (_currentSet <= 1 && _currentExerciseIndex == 0) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    // Stop timer for the current set if it's running
    if (effortKind == 'timed' ||
        effortKind == 'drill' ||
        effortKind == 'round') {
      final timerKey = '$effortId-${_currentSet - 1}';
      if (_effortRunning[timerKey] == true) {
        _pauseEffortTimer(effortId, _currentSet - 1);
      }
      _resetEffortAlertState(effortId, _currentSet - 1);
    }

    // Simply move back to previous set without clearing values
    int? previousExerciseIndex;
    setState(() {
      if (_currentSet > 1) {
        _currentSet--;
      } else if (_currentExerciseIndex > 0) {
        _currentExerciseIndex--;
        final previousExercise = _exercises[_currentExerciseIndex];
        final previousEntries =
            previousExercise['entries'] as List<Map<String, dynamic>>;
        _currentSet = previousEntries.isNotEmpty ? previousEntries.length : 1;
        previousExerciseIndex = _currentExerciseIndex;
      }
    });

    if (previousExerciseIndex != null) {
      unawaited(_loadExerciseNoteForIndex(previousExerciseIndex!));
    }
  }

  void _skipSet() {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    // Stop timer if running
    if (effortKind == 'timed' ||
        effortKind == 'drill' ||
        effortKind == 'round') {
      final timerKey = '$effortId-${_currentSet - 1}';
      if (_effortRunning[timerKey] == true) {
        _pauseEffortTimer(effortId, _currentSet - 1);
      }
    }

    // Mark this set as skipped (don't log or fill the dot)
    _skippedSets.putIfAbsent(effortId, () => {}).add(_currentSet - 1);

    // Reset timer display state for the skipped entry
    final skippedKey = '$effortId-${_currentSet - 1}';
    _effortElapsed[skippedKey] = 0;
    _effortTargetDuration.remove(skippedKey);
    _effortAlerted[skippedKey] = false;

    // Just advance to next set, don't auto-finish
    setState(() {
      if (_currentSet < entries.length) {
        _currentSet++;
      }
    });
  }

  /// Pre-fill the next set entry with values from the previous set
  /// Persist current entry values to the repository
  Future<void> _persistEntryValues(
    String effortId,
    int entryIndex,
    String effortKind,
    Map<String, dynamic> currentEntry,
  ) async {
    switch (effortKind) {
      case 'set':
        // Persist reps and weight
        await widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'reps',
          currentEntry['reps'] as int? ?? 0,
        );
        await widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'weight',
          currentEntry['weight'] as double? ?? 0.0,
        );
        break;
      case 'timed':
        // Duration is tracked in TimedInstance (wall-clock); persist companion distance only.
        await widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'distance',
          currentEntry['distance'] as double? ?? 0.0,
        );
        break;
      case 'round':
        // Round tracking is handled by RoundInstance records via
        // WorkoutState.completeRound() / endRoundEarly() — not by observations.
        // This case should never be reached (callers guard with effortKind != 'round').
        break;
      case 'drill':
        // Duration is tracked in TimedInstance (wall-clock); persist companion extra weight only.
        await widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'extra-weight',
          currentEntry['extra-weight'] as double? ?? 0.0,
        );
        break;
    }
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Workout Complete'),
        content: const Text('All exercises completed! Finish this workout?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _showListView = true;
              });
            },
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _finishSession();
            },
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSet() async {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;

    // Mark structural change so the discard-confirmation fires on Back.
    if (widget.editMode) _hasStructuralChanges = true;
    await widget.workoutState.addEntry(effortId);
    await _loadExercises();
  }

  Future<void> _deleteLastSet() async {
    if (_exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final exerciseName = exercise['name'] as String;
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    if (entries.isEmpty) return;

    // If this is the last entry, warn that the exercise will be removed
    if (entries.length == 1) {
      final setLabel = effortKind == 'round'
          ? 'round'
          : (effortKind == 'timed'
                ? 'interval'
                : (effortKind == 'drill' ? 'hold' : 'set'));

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove Exercise?'),
          content: Text(
            'This is the last $setLabel for "$exerciseName". '
            'Deleting it will remove the entire exercise from your session.\n\n'
            'Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Delete the entry and remove the exercise
      if (widget.editMode) _hasStructuralChanges = true;
      await widget.workoutState.deleteEntry(effortId, entries.length - 1);
      await widget.workoutState.removeExerciseFromSession(effortId);
      await _loadExercises();

      // Navigate back to list view
      if (mounted) {
        setState(() {
          _showListView = true;
          _currentExerciseIndex = 0;
          _currentSet = 1;
        });
      }
      return;
    }

    // Not the last entry - delete normally
    if (widget.editMode) _hasStructuralChanges = true;
    await widget.workoutState.deleteEntry(effortId, entries.length - 1);
    await _loadExercises();

    // Adjust current set if needed
    setState(() {
      if (_currentSet > entries.length - 1) {
        _currentSet = (entries.length - 1).clamp(1, entries.length);
      }
    });
  }

  Future<void> _updateMetricValue(
    String effortId,
    int entryIndex,
    String metricKey,
    dynamic value,
  ) async {
    if (widget.editMode) {
      // Edit mode: buffer changes locally without persisting to repository.
      // Changes are saved only when the user clicks "Save".
      final key = '$effortId-$entryIndex';
      _editBuffer.putIfAbsent(key, () => {});
      _editBuffer[key]![metricKey] = value;

      // Update local state immediately for live UI feedback
      final exercise = _getExerciseById(effortId);
      if (exercise != null) {
        final entries = exercise['entries'] as List<Map<String, dynamic>>;
        if (entryIndex >= 0 && entryIndex < entries.length) {
          setState(() {
            entries[entryIndex][metricKey] = value;
          });
        }
      }
      return;
    }

    // Normal mode: persist immediately
    await widget.workoutState.updateEntryValue(
      effortId,
      entryIndex,
      metricKey,
      value,
    );

    // Reload exercises to reflect updated values
    await _loadExercises();

    // Sync the local _effortElapsed state with the newly loaded value
    // This ensures the timer starts from the user-set value, not the old one
    if (_exercises.isNotEmpty && _currentExerciseIndex < _exercises.length) {
      final exercise = _exercises[_currentExerciseIndex];
      final entries = exercise['entries'] as List<Map<String, dynamic>>;
      if (entries.isNotEmpty && entryIndex < entries.length) {
        final entry = entries[entryIndex];
        final timerKey = '$effortId-$entryIndex';

        // Update _effortTargetDuration to match the newly persisted target value.
        // Do NOT overwrite _effortElapsed — the TimedInstance tracks elapsed via
        // wall-clock timestamps; clobbering elapsed here would corrupt the display.
        if (metricKey == 'duration') {
          _effortTargetDuration[timerKey] = entry['duration'] as int? ?? 0;
          _effortAlerted[timerKey] = false;
        }
        if (metricKey == 'round-duration') {
          _effortTargetDuration[timerKey] =
              entry['round-duration'] as int? ?? 0;
          _effortAlerted[timerKey] = false;
        }
      }
    }
  }

  void _toggleEffortTimer(String effortId) {
    final entryIndex = _currentSet - 1;
    final timerKey = '$effortId-$entryIndex';
    final effortKind = _getEffortKind(effortId);

    if (effortKind == 'round') {
      final round = _getRoundInstance(effortId, entryIndex);
      if (round == null) return;

      // Guard: ignore taps while a transition is already in-flight.
      // Without this, rapid double-taps dispatch two concurrent writes that both
      // read the same stale state, causing duplicate or conflicting transitions.
      if (_pendingRoundTransitions.contains(timerKey)) return;

      switch (round.state) {
        case RoundState.finished:
          // Immutable — disable play/pause
          return;
        case RoundState.active:
          // Pause the round.
          // Snap _effortElapsed to the current wall-clock value NOW, before the tick
          // timer is cancelled. This makes the stopped display stable and consistent
          // with what was showing while running — no jump when pauseRound resolves.
          _effortElapsed[timerKey] = (round.elapsedMs / 1000).round();
          _pendingRoundTransitions.add(timerKey);
          _effortTimers[timerKey]?.cancel();
          _effortRunning[timerKey] = false;
          if (mounted) setState(() {});
          widget.workoutState
              .pauseRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
          break;
        case RoundState.paused:
          // Resume the round
          _pendingRoundTransitions.add(timerKey);
          _effortRunning[timerKey] = true;
          _effortTimers[timerKey]?.cancel();
          _effortTimers[timerKey] = Timer.periodic(
            _timerUpdateInterval,
            (_) => _onEffortTick(effortId, entryIndex),
          );
          if (mounted) setState(() {});
          widget.workoutState
              .resumeRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
          break;
        case RoundState.notStarted:
          // Start fresh round; close rest window first
          _pendingRoundTransitions.add(timerKey);
          _effortRunning[timerKey] = true;
          _effortTimers[timerKey]?.cancel();
          _effortTimers[timerKey] = Timer.periodic(
            _timerUpdateInterval,
            (_) => _onEffortTick(effortId, entryIndex),
          );
          if (mounted) setState(() {});
          unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
          widget.workoutState
              .startRound(effortId, entryIndex)
              .whenComplete(() => _pendingRoundTransitions.remove(timerKey));
          break;
      }
      return;
    }

    // For timed/drill — dispatch to TimedInstance lifecycle methods (wall-clock based).
    // Guard: ignore taps while a transition is already in-flight.
    if (_pendingTimedTransitions.contains(timerKey)) return;

    final instance = _getTimedInstance(effortId, entryIndex);
    if (instance == null) return;

    switch (instance.state) {
      case TimedState.finished:
        // Immutable — play/pause disabled once finished.
        return;
      case TimedState.active:
        // Pause: snap elapsed to current wall-clock value before cancelling tick.
        _effortElapsed[timerKey] = (instance.elapsedMs / 1000).round();
        _pendingTimedTransitions.add(timerKey);
        _effortTimers[timerKey]?.cancel();
        _effortRunning[timerKey] = false;
        if (mounted) setState(() {});
        widget.workoutState
            .pauseTimedEntry(effortId, entryIndex)
            .whenComplete(() => _pendingTimedTransitions.remove(timerKey));
        break;
      case TimedState.paused:
        // Resume from where we left off.
        _pendingTimedTransitions.add(timerKey);
        _effortRunning[timerKey] = true;
        _effortTimers[timerKey]?.cancel();
        _effortTimers[timerKey] = Timer.periodic(
          _timerUpdateInterval,
          (_) => _onEffortTick(effortId, entryIndex),
        );
        if (mounted) setState(() {});
        widget.workoutState
            .resumeTimedEntry(effortId, entryIndex)
            .whenComplete(() => _pendingTimedTransitions.remove(timerKey));
        break;
      case TimedState.notStarted:
        // Start fresh timed entry; close rest window first
        _pendingTimedTransitions.add(timerKey);
        _effortRunning[timerKey] = true;
        _effortTimers[timerKey]?.cancel();
        _effortTimers[timerKey] = Timer.periodic(
          _timerUpdateInterval,
          (_) => _onEffortTick(effortId, entryIndex),
        );
        if (mounted) setState(() {});
        unawaited(widget.workoutState.recordRestEnd(effortId, entryIndex));
        widget.workoutState.startTimedEntry(effortId, entryIndex).whenComplete(
          () {
            _pendingTimedTransitions.remove(timerKey);
            if (!mounted) return;
            setState(() {
              // Timed/drill are open-ended count-up timers; clear any pre-start
              // cached preset so display and expiry checks don't enter countdown.
              _effortTargetDuration[timerKey] = 0;
            });
          },
        );
        break;
    }
  }

  void _onEffortTick(String effortId, int entryIndex) {
    final session = widget.workoutState.currentSession;
    if (session == null || session.endedAtMs != null) {
      return;
    }

    final timerKey = '$effortId-$entryIndex';
    final effortKind = _getEffortKind(effortId);
    final targetSeconds = _getEffortTargetDuration(
      effortId,
      entryIndex,
      effortKind,
    );

    final int elapsed;
    if (effortKind == 'round') {
      // Derive elapsed from RoundInstance.elapsedMs (wall-clock based).
      // Skip the update while a state transition is in-flight: during the resume
      // window, totalPausedDurationMs has not yet been written, so elapsedMs would
      // include the paused time and produce a wrong (too-high) elapsed value.
      if (_pendingRoundTransitions.contains(timerKey)) return;
      final round = _getRoundInstance(effortId, entryIndex);
      if (round == null || round.state != RoundState.active) return;
      elapsed = (round.elapsedMs / 1000).round();
    } else {
      // Derive elapsed from TimedInstance.elapsedMs (wall-clock based — never drifts).
      // Skip while a transition is in-flight: pausedAtMs / totalPausedDurationMs may
      // not have been written yet, producing a stale elapsed value.
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
      // Persist pause state via WorkoutState.pauseRound().
      unawaited(widget.workoutState.pauseRound(effortId, entryIndex));
      return;
    }

    // Open-ended efforts (timed/drill) — dispatch pauseTimedEntry to persist
    // the wall-clock pause timestamp into the TimedInstance record.
    if (effortKind == 'timed' || effortKind == 'drill') {
      unawaited(widget.workoutState.pauseTimedEntry(effortId, entryIndex));
    }
  }

  void _jumpToSet(int setNumber) {
    setState(() {
      _currentSet = setNumber;
    });

    if (_exercises.isEmpty || _currentExerciseIndex >= _exercises.length) {
      return;
    }
    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    _resetEffortAlertState(effortId, _currentSet - 1);
  }

  void _switchExercise(int delta) {
    final newIndex = _currentExerciseIndex + delta;
    if (newIndex < 0 || newIndex >= _exercises.length) return;
    unawaited(_focusExerciseDetail(newIndex));
  }

  Future<void> _addExercise({String? segmentId}) async {
    final modality = widget.workoutState.currentSession?.modality;

    final selectedExercise = await showDialog<Exercise>(
      context: context,
      builder: (context) => ExercisePickerDialog(
        workoutState: widget.workoutState,
        sessionModality: modality,
      ),
    );

    if (selectedExercise != null) {
      String? chosenMetric;
      String? effortKindOverride;

      // If Free Training or Routine session (null modality), ask user to pick a modality
      if (modality == null) {
        final modalityResult = await showDialog<(bool, String?)>(
          context: context,
          builder: (context) => const ModalityPickerDialog(),
        );

        if (!context.mounted || modalityResult == null) {
          return; // user cancelled
        }

        final (_, pickedModality) = modalityResult;

        if (pickedModality != null) {
          // User picked a specific modality — derive effort kind from its config
          effortKindOverride =
              ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';
        } else {
          // User picked "General" — fall back to metric chooser
          final deduped = _deduplicateCapabilities(
            selectedExercise.capabilities,
          );
          if (deduped.length == 1) {
            chosenMetric = deduped.first;
          } else {
            chosenMetric = await showDialog<String>(
              context: context,
              builder: (context) =>
                  MetricChooserDialog(exercise: selectedExercise),
            );

            if (chosenMetric == null) return; // User cancelled metric selection
          }
        }
      }

      String effortId = '';
      try {
        effortId = await widget.workoutState.addExerciseToSession(
          selectedExercise,
          chosenMetric: chosenMetric,
          effortKindOverride: effortKindOverride,
          segmentId: segmentId,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to add exercise: $e')));
        }
      }

      // Mark structural change AFTER we know the add succeeded.
      if (widget.editMode && effortId.isNotEmpty) _hasStructuralChanges = true;
      await _loadExercises();

      if (effortId.isNotEmpty) {
        final idx = _exercises.indexWhere((e) => e['id'] == effortId);
        if (idx != -1) {
          unawaited(_focusExerciseDetail(idx));
        }
      }
    }
  }

  /// Compute final session duration from persisted timestamps (used in edit mode).
  /// Shows total duration from session start to session end.
  void _computeStaticElapsed() {
    final session = widget.workoutState.currentSession;
    if (session == null) return;
    final endMs = session.endedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = endMs - session.startedAtMs;
    final elapsedSeconds = (elapsedMs / 1000).toInt();
    final mm = (elapsedSeconds ~/ 60).remainder(60).toString().padLeft(2, '0');
    final ss = (elapsedSeconds % 60).toString().padLeft(2, '0');
    _elapsedFormatted = '$mm:$ss';
    // Capture original so dirty detection and discard work correctly.
    _pendingDurationSecs = elapsedSeconds;
    _originalDurationSecs = elapsedSeconds;
  }

  /// Navigate forward in edit mode: advance to the next set/exercise without
  /// logging, starting timers, or resetting the rest timer.
  void _nextSetInEditMode() {
    if (_exercises.isEmpty) return;
    final exercise = _exercises[_currentExerciseIndex];
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    int? nextExerciseIndex;
    setState(() {
      if (_currentSet < entries.length) {
        _currentSet++;
      } else if (_currentExerciseIndex < _exercises.length - 1) {
        _currentExerciseIndex++;
        _currentSet = 1;
        nextExerciseIndex = _currentExerciseIndex;
      }
      // At the very end: stay on the last set (no finish dialog in edit mode)
    });

    if (nextExerciseIndex != null) {
      unawaited(_loadExerciseNoteForIndex(nextExerciseIndex!));
    }
  }

  void _tick() {
    // Calculate elapsed time from session start time (not from a local stopwatch)
    // This ensures the timer doesn't reset when navigating away and back
    final session = widget.workoutState.currentSession;
    if (session == null) return;
    if (session.endedAtMs != null) return;

    final elapsedMs =
        DateTime.now().millisecondsSinceEpoch - session.startedAtMs;
    final elapsedSeconds = (elapsedMs / 1000).toInt();
    final mm = (elapsedSeconds ~/ 60).remainder(60).toString().padLeft(2, '0');
    final ss = (elapsedSeconds % 60).toString().padLeft(2, '0');
    if (mounted) {
      setState(() {
        _elapsedFormatted = '$mm:$ss';
      });
    }
  }

  String _formatRestElapsed(String effortId, int entryIndex) {
    final secs = widget.workoutState.getRestElapsedSeconds(
      effortId,
      entryIndex,
    );
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  int? _getRestDisplayEntryIndex(String effortId, int currentEntryIndex) {
    final rests = widget.workoutState.getEntryRests(effortId);
    int? exactEntryIndex;
    int? latestOpenEntryIndex;

    for (final rest in rests) {
      if (rest.entryIndex == currentEntryIndex) {
        exactEntryIndex = currentEntryIndex;
      }
      if (rest.restEndMs == null) {
        if (latestOpenEntryIndex == null ||
            rest.entryIndex > latestOpenEntryIndex) {
          latestOpenEntryIndex = rest.entryIndex;
        }
      }
    }

    return latestOpenEntryIndex ?? exactEntryIndex;
  }

  bool _hasRestToDisplay(String effortId, int currentEntryIndex) {
    return _getRestDisplayEntryIndex(effortId, currentEntryIndex) != null;
  }

  String _formatRestElapsedForDisplay(String effortId, int currentEntryIndex) {
    final displayEntryIndex = _getRestDisplayEntryIndex(
      effortId,
      currentEntryIndex,
    );
    if (displayEntryIndex == null) return '00:00';
    return _formatRestElapsed(effortId, displayEntryIndex);
  }

  // ── Edit-mode duration editing ───────────────────────────────────────────

  bool _hasDurationChanged() =>
      _pendingDurationSecs != null &&
      _originalDurationSecs != null &&
      _pendingDurationSecs != _originalDurationSecs;

  void _reformatElapsed(int durationSecs) {
    final h = durationSecs ~/ 3600;
    final m = (durationSecs % 3600) ~/ 60;
    final s = durationSecs % 60;
    if (h > 0) {
      _elapsedFormatted =
          '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      _elapsedFormatted =
          '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
  }

  /// Opens a dialog letting the user correct the total session duration.
  /// Updates [_pendingDurationSecs] and reformats the elapsed display;
  /// the change is persisted only when the user taps "Save Changes".
  Future<void> _editSessionDuration() async {
    if (!widget.editMode) return;
    final current = _pendingDurationSecs ?? 0;
    final h = current ~/ 3600;
    final m = (current % 3600) ~/ 60;
    final s = current % 60;

    final hhCtrl = TextEditingController(text: h.toString());
    final mmCtrl = TextEditingController(text: m.toString().padLeft(2, '0'));
    final ssCtrl = TextEditingController(text: s.toString().padLeft(2, '0'));

    int? result;
    try {
      result = await showDialog<int>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Edit Session Duration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adjust the total duration of this session.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: OmniTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hhCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Hours',
                        suffixText: 'h',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: mmCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Min',
                        suffixText: 'm',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ssCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Sec',
                        suffixText: 's',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final hVal = int.tryParse(hhCtrl.text.trim()) ?? 0;
                final mVal = int.tryParse(mmCtrl.text.trim()) ?? 0;
                final sVal = int.tryParse(ssCtrl.text.trim()) ?? 0;
                Navigator.pop(context, hVal * 3600 + mVal * 60 + sVal);
              },
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
    } finally {
      hhCtrl.dispose();
      mmCtrl.dispose();
      ssCtrl.dispose();
    }

    if (result != null && result > 0 && mounted) {
      setState(() {
        _pendingDurationSecs = result;
        _reformatElapsed(result as int);
      });
    }
  }

  // ── Edit-mode navigation helpers ────────────────────────────────────────

  /// Handles the Back gesture / arrow-button press while in edit mode.
  ///
  /// Pops immediately when nothing has changed. Otherwise shows an unsaved
  /// changes dialog with close, discard, and save actions.
  Future<void> _handleEditModeBack() async {
    final hasUnsaved =
        _editBuffer.isNotEmpty ||
        _hasStructuralChanges ||
        _hasDurationChanged();
    if (!hasUnsaved) {
      Navigator.of(context).pop();
      return;
    }

    final action = await showDialog<_EditBackAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Unsaved changes')),
            IconButton(
              onPressed: () => Navigator.pop(context, _EditBackAction.close),
              tooltip: 'Keep editing',
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: const Text(
          'You have unsaved edits. Save them or discard to return to the summary.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'Discard changes',
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, _EditBackAction.discard),
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              OmniTheme.buttonUtilityRadius,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Discard'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Tooltip(
                    message: 'Save changes',
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _EditBackAction.save),
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              OmniTheme.buttonUtilityRadius,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    switch (action) {
      case _EditBackAction.save:
        await _saveEditChanges();
      case _EditBackAction.discard:
        await _discardEditChanges();
      case null:
      case _EditBackAction.close:
        break; // stay on screen
    }
  }

  /// Rolls back all changes made during this edit session and pops to the
  /// summary screen.
  ///
  /// Metric-value changes buffered in [_editBuffer] are simply dropped — they
  /// were never written to the repository.  Structural changes (added/removed
  /// exercises, added/removed sets) are reversed by restoring [_editSnapshot]
  /// through [WorkoutState.restoreSessionSnapshot], which uses only existing
  /// abstract repository primitives and therefore works identically on both
  /// HiveWorkoutRepository (web) and the future SqliteWorkoutRepository.
  Future<void> _discardEditChanges() async {
    _editBuffer.clear();

    // Restore the pending duration to the original value captured at edit entry.
    if (_hasDurationChanged()) {
      _pendingDurationSecs = _originalDurationSecs;
      if (_pendingDurationSecs != null) _reformatElapsed(_pendingDurationSecs!);
    }

    final snapshot = _editSnapshot;
    if (snapshot != null && _hasStructuralChanges) {
      if (!mounted) return;
      // Show a progress indicator while the async rollback completes.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        await widget.workoutState.restoreSessionSnapshot(snapshot);
      } finally {
        if (mounted) Navigator.of(context).pop(); // dismiss progress indicator
      }
    }

    _hasStructuralChanges = false;
    _editSnapshot = null;
    if (mounted) Navigator.of(context).pop();
  }

  /// Save all buffered metric changes from edit mode and navigate back.
  ///
  /// Structural changes (add/remove exercise, add/remove set) were already
  /// persisted immediately to the repository when they occurred, so only the
  /// metric edit buffer needs to be flushed here.
  Future<void> _saveEditChanges() async {
    // Persist all buffered metric changes to the repository.
    for (final entry in _editBuffer.entries) {
      final parts = entry.key.split('-');
      if (parts.length < 2) continue;
      // Reconstruct effortId (may contain hyphens; entryIndex is always last)
      final effortId = parts.sublist(0, parts.length - 1).join('-');
      final entryIndex = int.tryParse(parts.last);
      if (entryIndex == null) continue;

      final metrics = entry.value;
      for (final metricEntry in metrics.entries) {
        await widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          metricEntry.key,
          metricEntry.value,
        );
      }
    }

    // Persist session duration change if any.
    if (_hasDurationChanged()) {
      await widget.workoutState.updateSessionEndTime(_pendingDurationSecs!);
      _originalDurationSecs = _pendingDurationSecs;
    }

    // Commit: clear rollback state so the snapshot is never used accidentally.
    _editBuffer.clear();
    _hasStructuralChanges = false;
    _editSnapshot = null;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showFinishSessionDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish Workout?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have completed:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ${_exercises.length} exercise${_exercises.length != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Elapsed time: $_elapsedFormatted',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action will save and close the workout session.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withAlpha((0.6 * 255).round()),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            child: const Text('Finish'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _finishSession();
    }
  }

  Future<void> _finishSession() async {
    if (!mounted || _isFinishingSession) return;

    setState(() => _isFinishingSession = true);

    // Deterministic finish order:
    // 1) freeze all local UI timers
    // 2) persist all active timer-based entries (round + timed/drill)
    // 3) end session (set endedAtMs)
    // 4) replace route with summary so Back cannot resume an active session screen
    try {
      _freezeAllLocalTimers();
      await _persistActiveEffortTimers();
      await widget.workoutState.endSession();

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SessionSummaryScreen(
            workoutState: widget.workoutState,
            routineState: widget.routineState,
            sessionSummaryService: widget.sessionSummaryService,
            onSessionSaved: widget.onSessionSaved,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to finish workout: $e')));
    } finally {
      if (mounted) {
        setState(() => _isFinishingSession = false);
      }
    }
  }

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
  /// the repository.
  /// Must be called before navigating away from the session (e.g., Finish Workout).
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

        // Stop any local per-entry tick timer.
        _effortTimers[timerKey]?.cancel();
        _effortRunning[timerKey] = false;

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

        // Reset per-entry alert state after explicit finish.
        _effortAlerted[timerKey] = false;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Cancel all effort timers
    for (final timer in _effortTimers.values) {
      timer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // In edit mode, intercept the system back gesture so we can show the
    // "Unsaved changes" dialog before popping.  Non-edit sessions pop freely.
    final content = _buildContent(theme);
    if (!widget.editMode) return content;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (!_showListView) {
          setState(() => _showListView = true);
        } else {
          _handleEditModeBack();
        }
      },
      child: content,
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: const OmniGradientBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: OmniGradientBackground(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error Loading Session',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: OmniTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _loadExercises,
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonBorderRadius,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: OmniGradientBackground(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error Loading Session',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _loadExercises,
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonBorderRadius,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_showListView) {
      return _buildListView(theme);
    }

    if (_exercises.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: OmniGradientBackground(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'No exercises yet',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: OmniTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _addExercise,
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonBorderRadius,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Add First Exercise'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final exercise = _exercises[_currentExerciseIndex];
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final currentEntry = entries.isNotEmpty && _currentSet <= entries.length
        ? entries[_currentSet - 1]
        : (effortKind == 'set' ? {'reps': 0, 'weight': 0.0} : {'duration': 0});

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: OmniGradientBackground(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity! > 200) {
              if (widget.editMode) {
                _nextSetInEditMode();
              } else {
                _skipSet();
              }
            } else if (details.primaryVelocity! < -200) {
              _previousSet();
            }
          },
          onVerticalDragEnd: (details) {
            // Up swipe = next exercise; down swipe = previous exercise
            if (details.primaryVelocity! < -200) {
              // Swipe up = next exercise
              _switchExercise(1);
            } else if (details.primaryVelocity! > 200) {
              // Swipe down = previous exercise
              _switchExercise(-1);
            }
          },
          child: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(theme),

                    const SizedBox(height: 0),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildMetricWidget(
                                exercise,
                                currentEntry,
                                effortKind,
                                theme,
                              ),
                              const SizedBox(height: 24),
                              _buildSetProgress(
                                entries.length,
                                effortKind,
                                theme,
                              ),
                              const SizedBox(height: 16),
                              _buildPreviousSetStats(
                                exercise,
                                effortKind,
                                theme,
                              ),
                              const SizedBox(height: 16),
                              _buildSetIndicator(
                                entries.length,
                                effortKind,
                                theme,
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildSetControls(theme),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
              // Rest timer overlay in lower half (hide in edit mode or when exercise timer is running)
              if (!widget.editMode &&
                  _hasRestToDisplay(
                    exercise['id'] as String,
                    _currentSet - 1,
                  ) &&
                  !(_effortRunning['${exercise['id']}-${_currentSet - 1}'] ??
                      false))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 110,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withAlpha(
                              (0.2 * 255).round(),
                            ),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.self_improvement,
                            size: 24,
                            color: theme.colorScheme.onPrimary,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatRestElapsedForDisplay(
                                  exercise['id'] as String,
                                  _currentSet - 1,
                                ),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final currentSegmentName = !_showListView && _exercises.isNotEmpty
        ? _exercises[_currentExerciseIndex]['segmentName'] as String?
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: OmniTheme.textPrimary),
            onPressed: () {
              // Detail view → back to list view
              // List view   → exit (with unsaved-changes check in edit mode)
              if (!_showListView) {
                setState(() {
                  _showListView = true;
                });
              } else if (widget.editMode) {
                _handleEditModeBack();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showListView
                      ? 'Exercises'
                      : (_exercises.isNotEmpty
                            ? _exercises[_currentExerciseIndex]['name']
                                  as String
                            : ''),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: OmniTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _showListView
                      ? '${widget.editMode ? 'EDITING · ' : ''}${_exercises.length} exercise${_exercises.length != 1 ? 's' : ''}'
                      : (_exercises.isNotEmpty
                            ? 'Exercise ${_currentExerciseIndex + 1} / ${_exercises.length}'
                            : ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: widget.editMode
                        ? Theme.of(context).colorScheme.primary
                        : OmniTheme.textSecondary,
                  ),
                ),
                if (!_showListView && (currentSegmentName?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      currentSegmentName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!_showListView && _exercises.isNotEmpty)
            _buildExerciseHeaderActions(theme),
        ],
      ),
    );
  }

  Widget _buildExerciseHeaderActions(ThemeData theme) {
    return ListenableBuilder(
      listenable: widget.workoutState,
      builder: (context, _) {
        final exerciseMap = _exercises[_currentExerciseIndex];
        final exerciseId = exerciseMap['exerciseId'] as String?;
        final exercise = exerciseId != null
            ? widget.workoutState.getExercise(exerciseId)
            : null;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('exercise-info-button'),
              icon: Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurface.withOpacity(0.45),
              ),
              onPressed: exercise == null
                  ? null
                  : () => _showExerciseInfoSheet(context, exercise),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  key: const Key('exercise-note-button'),
                  icon: Icon(
                    Icons.edit_note,
                    size: 18,
                    color: theme.colorScheme.onSurface.withOpacity(0.45),
                  ),
                  onPressed: exercise == null
                      ? null
                      : () => _showExerciseNoteSheet(context, exercise),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                if (exerciseId != null &&
                    widget.workoutState.hasExerciseNote(exerciseId))
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      key: const Key('exercise-note-indicator'),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSegmentHeader(String name, ThemeData theme) {
    final textMuted = OmniTheme.colorsForTheme(
      widget.settingsState?.appTheme ?? OmniTheme.activeTheme,
    ).textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        name,
        style: theme.textTheme.titleSmall?.copyWith(
          color: textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSegmentHeaderRow(
    SessionSegment segment,
    ThemeData theme, {
    required bool showAddButton,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              segment.name ?? 'Block ${segment.orderIndex + 1}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: OmniTheme.colorsForTheme(
                  widget.settingsState?.appTheme ?? OmniTheme.activeTheme,
                ).textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (showAddButton)
            OutlinedButton.icon(
              onPressed: () => _addExercise(segmentId: segment.id),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Exercise'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                side: BorderSide(color: theme.colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _buildExerciseSubtitle(Map<String, dynamic> exercise) {
    final entries = exercise['entries'] as List<dynamic>? ?? [];
    final effortKind = exercise['effortKind'] as String? ?? 'set';

    switch (effortKind) {
      case 'set':
        return '${entries.length} set${entries.length != 1 ? 's' : ''}';
      case 'timed':
        // Sum elapsedSecs (actual duration) for completed/in-progress entries;
        // fall back to 'duration' (target) for entries not yet started.
        final totalDuration = entries.fold<int>(0, (sum, e) {
          final elapsed = e['elapsedSecs'] as int? ?? 0;
          final target = e['duration'] as int? ?? 0;
          return sum + (elapsed > 0 ? elapsed : target);
        });
        final minutes = totalDuration ~/ 60;
        final seconds = totalDuration % 60;
        return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} total';
      case 'round':
        return '${entries.length} round${entries.length != 1 ? 's' : ''}';
      case 'drill':
        return '${entries.length} hold${entries.length != 1 ? 's' : ''}';
      default:
        return '${entries.length} ${entries.length != 1 ? 'entries' : 'entry'}';
    }
  }

  Widget _buildExerciseTile(Map<String, dynamic> exercise, ThemeData theme) {
    final subtitle = _buildExerciseSubtitle(exercise);
    final effortId = exercise['id'] as String;
    final idx = _exercises.indexWhere((e) => e['id'] == effortId);

    final tileColors = OmniTheme.colorsForTheme(
      widget.settingsState?.appTheme ?? OmniTheme.activeTheme,
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tileColors.surface.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tileColors.surfaceBorder),
      ),
      child: ListTile(
        title: Text(
          exercise['name'] as String,
          style: theme.textTheme.titleMedium?.copyWith(
            color: OmniTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: OmniTheme.textSecondary,
          ),
        ),
        onTap: idx == -1 ? null : () => unawaited(_focusExerciseDetail(idx)),
      ),
    );
  }

  void _showExerciseInfoSheet(BuildContext context, Exercise exercise) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bottomPadding = MediaQuery.of(ctx).padding.bottom + 24;
        final hasImage = exercise.imageAssetPath != null;
        final hasSteps =
            exercise.howToSteps != null && exercise.howToSteps!.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

                // Hero image
                if (hasImage)
                  Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 200,
                        child: Image.asset(
                          exercise.imageAssetPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      // Bottom gradient overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 60,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Exercise name
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    exercise.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),

                // How-to section
                if (hasSteps) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text(
                      'HOW TO PERFORM',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                        letterSpacing: 2.0,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  ...exercise.howToSteps!.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key + 1}.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Empty state
                if (!hasImage && !hasSteps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No information available yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.45),
                        ),
                      ),
                    ),
                  ),

                SizedBox(height: bottomPadding),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showExerciseNoteSheet(BuildContext context, Exercise exercise) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseNoteSheet(
        workoutState: widget.workoutState,
        exercise: exercise,
        currentSessionId: widget.workoutState.currentSession?.id,
      ),
    );
  }

  /// Session time chip used in both the empty-exercises and the normal list
  /// views. In edit mode it gains a border, tinted text, and an edit icon,
  /// and wraps itself in a [GestureDetector] that opens [_editSessionDuration].
  Widget _buildSessionTimeWidget(ThemeData theme) {
    final chipColors = OmniTheme.colorsForTheme(
      widget.settingsState?.appTheme ?? OmniTheme.activeTheme,
    );
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chipColors.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: widget.editMode
            ? Border.all(
                color: theme.colorScheme.primary.withAlpha(
                  (0.45 * 255).round(),
                ),
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Session Time',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: OmniTheme.textSecondary,
                ),
              ),
              if (widget.editMode) ...[
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 12, color: theme.colorScheme.primary),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.timer, size: 16, color: OmniTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                _elapsedFormatted,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: widget.editMode
                      ? theme.colorScheme.primary
                      : OmniTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (!widget.editMode) return chip;
    return GestureDetector(onTap: _editSessionDuration, child: chip);
  }

  Widget _buildListView(ThemeData theme) {
    final segments = widget.workoutState.segments.toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final showPerBlockAdd =
        widget.workoutState.currentSession?.intent == 'routine' &&
        segments.length > 1;

    if (_exercises.isEmpty && !showPerBlockAdd) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: OmniGradientBackground(
          child: Stack(
            children: [
              // Full screen center for text
              Center(
                child: Text(
                  'No exercises',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: OmniTheme.textPrimary,
                  ),
                ),
              ),
              // Header and controls overlay
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(theme),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(children: [_buildSessionTimeWidget(theme)]),
                    ),
                    Spacer(),
                  ],
                ),
              ),
              Positioned(
                right: 10,
                bottom: 110,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: OmniTheme.buttonIconSize,
                    height: OmniTheme.buttonIconSize,
                    child: FilledButton(
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              OmniTheme.buttonIconRadius,
                            ),
                          ),
                        ),
                      ),
                      onPressed: _addExercise,
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: double.infinity,
                      height: OmniTheme.buttonPrimaryHeight,
                      child: FilledButton(
                        onPressed: widget.editMode
                            ? _saveEditChanges
                            : _showFinishSessionDialog,
                        style: ButtonStyle(
                          shape: WidgetStateProperty.all(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                OmniTheme.buttonBorderRadius,
                              ),
                            ),
                          ),
                        ),
                        child: Text(
                          widget.editMode ? 'Save Changes' : 'Finish Workout',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: OmniGradientBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [_buildSessionTimeWidget(theme)]),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 140),
                      children: [
                        if (showPerBlockAdd)
                          for (final segment in segments) ...[
                            _buildSegmentHeaderRow(
                              segment,
                              theme,
                              showAddButton: true,
                            ),
                            if (_exercises
                                .where((e) => e['segmentId'] == segment.id)
                                .isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  12,
                                ),
                                child: Text(
                                  'No exercises in this block yet.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: OmniTheme.textSecondary,
                                  ),
                                ),
                              ),
                            for (final ex in _exercises.where(
                              (e) => e['segmentId'] == segment.id,
                            )) ...[
                              _buildExerciseTile(ex, theme),
                              const SizedBox(height: 8),
                            ],
                          ]
                        else
                          for (
                            int index = 0;
                            index < _exercises.length;
                            index++
                          ) ...[
                            if (index == 0 ||
                                _exercises[index]['segmentId'] !=
                                    _exercises[index - 1]['segmentId'])
                              _buildSegmentHeader(
                                _exercises[index]['segmentName'] as String? ??
                                    'Block',
                                theme,
                              ),
                            _buildExerciseTile(_exercises[index], theme),
                            const SizedBox(height: 8),
                          ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Rest timer overlay (hide in edit mode or when exercise timer is running)
            if (!widget.editMode &&
                _hasRestToDisplay(
                  _exercises[_currentExerciseIndex]['id'] as String,
                  _currentSet - 1,
                ) &&
                !(_effortRunning['${_exercises[_currentExerciseIndex]['id']}-${_currentSet - 1}'] ??
                    false))
              Positioned(
                left: 0,
                right: 0,
                bottom: 110,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withAlpha(
                            (0.2 * 255).round(),
                          ),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.self_improvement,
                          size: 24,
                          color: theme.colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatRestElapsedForDisplay(
                                _exercises[_currentExerciseIndex]['id']
                                    as String,
                                _currentSet - 1,
                              ),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!showPerBlockAdd)
              Positioned(
                right: 10,
                bottom: 110,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: FilledButton(
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      onPressed: () => _addExercise(),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: widget.editMode
                          ? _saveEditChanges
                          : _showFinishSessionDialog,
                      style: ButtonStyle(
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      child: Text(
                        widget.editMode ? 'Save Changes' : 'Finish Workout',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricWidget(
    Map<String, dynamic> exercise,
    Map<String, dynamic> entryData,
    String effortKind,
    ThemeData theme,
  ) {
    final effortId = exercise['id'] as String;
    final entryIndex = _currentSet - 1;

    switch (effortKind) {
      case 'set':
        final reps = entryData['reps'] as int? ?? 0;
        final weight = entryData['weight'] as double? ?? 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            InlineMetricEditor(
              metricType: 'reps',
              currentValue: reps,
              unitLabel: 'REPS',
              onValueChanged: (value) =>
                  _updateMetricValue(effortId, entryIndex, 'reps', value),
            ),
            InlineMetricEditor(
              metricType: 'weight',
              currentValue: weight,
              unitLabel: 'LBS',
              onValueChanged: (value) =>
                  _updateMetricValue(effortId, entryIndex, 'weight', value),
            ),
          ],
        );

      case 'timed':
        // ── State-aware display (mirrors the round effort pattern) ─────────
        // Single source of truth: _effortElapsed[timerKey] (snapped on pause,
        // updated each tick from wall-clock TimedInstance.elapsedMs).
        //
        //   notStarted            → preset target (editable)
        //   active/paused, target > 0 → remaining countdown (target − elapsed)
        //   active/paused, target == 0 → elapsed count-up (open-ended)
        //   finished              → actualDurationSecs, COMPLETED label
        final timedTimerKey = '$effortId-$entryIndex';
        final timedElapsed = _effortElapsed[timedTimerKey] ?? 0;
        final timedIsRunning = _effortRunning[timedTimerKey] ?? false;
        final timedInstance = _getTimedInstance(effortId, entryIndex);
        final timedEntryState = timedInstance?.state ?? TimedState.notStarted;
        final isTimedFinished = timedEntryState == TimedState.finished;
        final isTimedStarted = timedEntryState != TimedState.notStarted;

        final int timedDisplayValue;
        final String timedUnitLabel;
        final Color? timedUnitLabelColor;
        if (isTimedFinished) {
          timedDisplayValue = timedInstance?.actualDurationSecs ?? timedElapsed;
          timedUnitLabel = 'COMPLETED';
          timedUnitLabelColor = theme.colorScheme.primary;
        } else {
          // Always count up from zero — no preset editing for timed efforts.
          timedDisplayValue = timedElapsed;
          timedUnitLabel = 'ELAPSED';
          timedUnitLabelColor = timedIsRunning
              ? theme.colorScheme.primary.withOpacity(0.8)
              : null;
        }

        if (widget.editMode) {
          // Edit mode: show actual elapsed duration as an editable value.
          final editDuration =
              timedInstance?.actualDurationSecs ??
              (entryData['elapsedSecs'] as int? ?? timedElapsed);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 48),
              InlineMetricEditor(
                metricType: 'duration',
                currentValue: editDuration,
                unitLabel: 'ELAPSED',
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'elapsedSecs',
                  value,
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 48),
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: timedDisplayValue,
              unitLabel: timedUnitLabel,
              unitLabelColor: timedUnitLabelColor,
              // Timed efforts always count up from zero — never user-editable.
              isReadOnly: true,
              onValueChanged: (_) {},
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isTimedFinished
                      ? 'COMPLETED'
                      : (timedIsRunning
                            ? 'RUNNING'
                            : (isTimedStarted ? 'PAUSED' : 'STOPPED')),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isTimedFinished
                        ? theme.colorScheme.primary
                        : (timedIsRunning
                              ? theme.colorScheme.primary.withOpacity(0.8)
                              : theme.colorScheme.onSurface.withAlpha(
                                  (0.5 * 255).round(),
                                )),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        );

      case 'round':
        final rounds = entryData['rounds'] as int? ?? 1;
        final roundDuration =
            entryData['round-duration'] as int? ??
            WorkoutConstants.defaultRoundDurationSecs;
        final timerKey = '$effortId-$entryIndex';
        final elapsed = _effortElapsed[timerKey] ?? 0;
        final targetSeconds = _getEffortTargetDuration(
          effortId,
          entryIndex,
          effortKind,
        );
        final effectiveTarget = targetSeconds > 0
            ? targetSeconds
            : roundDuration;
        final remaining = (effectiveTarget - elapsed).clamp(0, effectiveTarget);
        final isExpired = _isEffortExpired(effortId, entryIndex, effortKind);
        final round = _getRoundInstance(effortId, entryIndex);

        // What to show when the timer is not actively ticking:
        //   finished (natural or early) → actualDurationSecs  (COMPLETED)
        //   paused or active-but-restored (loaded without auto-resume) → remaining  (REMAINING)
        //   notStarted → full planned duration  (DURATION)
        final bool isFinished =
            isExpired || round?.state == RoundState.finished;
        // isMidRound: started but not yet finished (covers paused, active-restored,
        // and the brief async transition window between state writes).
        final bool isMidRound =
            !isFinished &&
            round != null &&
            round.state != RoundState.notStarted;

        // _effortElapsed[timerKey] is the single source of truth for the stopped
        // display.  It is:
        //   • Updated every second by _onEffortTick while running.
        //   • Snapped to the exact wall-clock value in _toggleEffortTimer when
        //     the user presses pause (before the tick is cancelled).
        //   • Set at load time by _loadExercises for restored sessions.
        // This means we never read round.elapsedMs / round.remainingMs here,
        // so notifyListeners() rebuilds cannot cause a value jump.
        final int stoppedDisplayValue;
        if (isFinished) {
          // Prefer the persisted actual duration; fall back to effectiveTarget for
          // the brief window between UI expiry detection and async completeRound().
          stoppedDisplayValue = (round != null && round.actualDurationSecs > 0)
              ? round.actualDurationSecs
              : effectiveTarget;
        } else if (isMidRound) {
          stoppedDisplayValue =
              (effectiveTarget - (_effortElapsed[timerKey] ?? 0)).clamp(
                0,
                effectiveTarget,
              );
        } else {
          // notStarted: show the full planned duration as the editable default.
          stoppedDisplayValue = roundDuration;
        }

        // Unit label: COMPLETED when done, REMAINING when mid-round, DURATION otherwise.
        final String stoppedUnitLabel = isFinished
            ? 'COMPLETED'
            : (isMidRound ? 'REMAINING' : 'DURATION');

        if (widget.editMode) {
          // Edit mode: show actual recorded duration as an editable value.
          final editRoundDuration =
              (round != null && round.actualDurationSecs > 0)
              ? round.actualDurationSecs
              : roundDuration;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 48),
              Text(
                'ROUND $rounds',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: -2,
                  fontSize: theme.textTheme.displayMedium?.fontSize,
                ),
              ),
              const SizedBox(height: 15),
              InlineMetricEditor(
                metricType: 'duration',
                currentValue: editRoundDuration,
                unitLabel: 'DURATION',
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'round-duration',
                  value,
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 48),
            // Round count (read-only, controlled by add/delete buttons)
            Text(
              'ROUND $rounds',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: -2,
                fontSize: theme.textTheme.displayMedium?.fontSize,
              ),
            ),
            const SizedBox(height: 15),
            // Scrollable round duration control
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: _effortRunning[timerKey] ?? false
                  ? remaining
                  : stoppedDisplayValue,
              unitLabel: _effortRunning[timerKey] ?? false
                  ? 'RUNNING'
                  : stoppedUnitLabel,
              unitLabelColor: _effortRunning[timerKey] ?? false
                  ? theme.colorScheme.primary.withOpacity(0.8)
                  : (isFinished
                        ? theme.colorScheme.primary
                        : (isExpired ? theme.colorScheme.error : null)),
              onValueChanged: (value) => _updateMetricValue(
                effortId,
                entryIndex,
                'round-duration',
                value,
              ),
            ),
          ],
        );

      case 'drill':
        // ── State-aware display (same pattern as 'timed') ─────────────────
        // Extra-weight editor remains always editable (independent of timer state).
        final drillTimerKey = '$effortId-$entryIndex';
        final drillElapsed = _effortElapsed[drillTimerKey] ?? 0;
        final drillIsRunning = _effortRunning[drillTimerKey] ?? false;
        final drillInstance = _getTimedInstance(effortId, entryIndex);
        final drillEntryState = drillInstance?.state ?? TimedState.notStarted;
        final isDrillFinished = drillEntryState == TimedState.finished;
        final isDrillStarted = drillEntryState != TimedState.notStarted;
        final drillExtraWeight = entryData['extra-weight'] as double? ?? 0.0;

        final int drillDisplayValue;
        final String drillUnitLabel;
        final Color? drillUnitLabelColor;
        if (isDrillFinished) {
          drillDisplayValue = drillInstance?.actualDurationSecs ?? drillElapsed;
          drillUnitLabel = 'COMPLETED';
          drillUnitLabelColor = theme.colorScheme.primary;
        } else {
          // Always count up from zero — no preset editing for drill efforts.
          drillDisplayValue = drillElapsed;
          drillUnitLabel = 'ELAPSED';
          drillUnitLabelColor = drillIsRunning
              ? theme.colorScheme.primary.withOpacity(0.8)
              : null;
        }

        if (widget.editMode) {
          // Edit mode: show actual hold duration as editable, keep extra-weight editable.
          final editDrillDuration =
              drillInstance?.actualDurationSecs ??
              (entryData['elapsedSecs'] as int? ?? drillElapsed);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InlineMetricEditor(
                metricType: 'duration',
                currentValue: editDrillDuration,
                unitLabel: 'ELAPSED',
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'elapsedSecs',
                  value,
                ),
              ),
              InlineMetricEditor(
                metricType: 'extra-weight',
                currentValue: drillExtraWeight,
                unitLabel: 'EXTRA WEIGHT',
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'extra-weight',
                  value,
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: drillDisplayValue,
              unitLabel: drillUnitLabel,
              unitLabelColor: drillUnitLabelColor,
              // Drill efforts always count up from zero — never user-editable.
              isReadOnly: true,
              onValueChanged: (_) {},
            ),
            InlineMetricEditor(
              metricType: 'extra-weight',
              currentValue: drillExtraWeight,
              unitLabel: 'EXTRA WEIGHT',
              onValueChanged: (value) => _updateMetricValue(
                effortId,
                entryIndex,
                'extra-weight',
                value,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isDrillFinished
                      ? 'COMPLETED'
                      : (drillIsRunning
                            ? 'RUNNING'
                            : (isDrillStarted ? 'PAUSED' : 'STOPPED')),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isDrillFinished
                        ? theme.colorScheme.primary
                        : (drillIsRunning
                              ? theme.colorScheme.primary.withOpacity(0.8)
                              : theme.colorScheme.onSurface.withAlpha(
                                  (0.5 * 255).round(),
                                )),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        );

      default:
        return Text('—', style: theme.textTheme.displayLarge);
    }
  }

  Widget _buildSetProgress(
    int totalEntries,
    String effortKind,
    ThemeData theme,
  ) {
    String label;
    switch (effortKind) {
      case 'set':
        label = 'Set $_currentSet of $totalEntries';
        break;
      case 'timed':
        label = 'Interval $_currentSet of $totalEntries';
        break;
      case 'round':
        final modality = widget.workoutState.currentSession?.modality;
        final isWorkoutLabel = modality == 'sports' ? 'Period' : 'Round';
        label = '$isWorkoutLabel $_currentSet of $totalEntries';
        break;
      case 'drill':
        label = 'Hold $_currentSet of $totalEntries';
        break;
      default:
        label = 'Set $_currentSet of $totalEntries';
    }

    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(
        letterSpacing: 2,
        color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildPreviousSetStats(
    Map<String, dynamic> exercise,
    String effortKind,
    ThemeData theme,
  ) {
    // Only show if we're not on the first set
    if (_currentSet <= 1) {
      return const SizedBox.shrink();
    }

    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    if (_currentSet - 2 >= entries.length) {
      return const SizedBox.shrink();
    }

    final previousEntry = entries[_currentSet - 2];
    String statsText = '';

    switch (effortKind) {
      case 'set':
        final prevReps = previousEntry['reps'] as int? ?? 0;
        final prevWeight = previousEntry['weight'] as double? ?? 0.0;
        statsText =
            'Previous: $prevReps reps @ ${prevWeight.toStringAsFixed(1)} lbs';
        break;
      case 'timed':
        // Use elapsedSecs (actual duration) rather than 'duration' (target preset)
        // so the previous-set banner shows what actually happened.
        final prevTimedSecs =
            previousEntry['elapsedSecs'] as int? ??
            previousEntry['duration'] as int? ??
            0;
        final prevDistance = previousEntry['distance'] as double? ?? 0.0;
        final prevTimedMins = prevTimedSecs ~/ 60;
        final prevTimedRemSecs = prevTimedSecs % 60;
        statsText =
            'Previous: ${prevTimedMins.toString().padLeft(2, '0')}:${prevTimedRemSecs.toString().padLeft(2, '0')} @ ${prevDistance.toStringAsFixed(1)} m';
        break;
      case 'round':
        final prevRounds = previousEntry['rounds'] as int? ?? 1;
        final prevRoundDur =
            previousEntry['round-duration'] as int? ??
            WorkoutConstants.defaultRoundDurationSecs;
        final mins = prevRoundDur ~/ 60;
        final secs = prevRoundDur % 60;
        statsText =
            'Previous: $prevRounds rounds @ ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        break;
      case 'drill':
        // Use elapsedSecs (actual hold duration) rather than 'duration' (target)
        // so the previous-set banner shows what actually happened.
        final prevDrillSecs =
            previousEntry['elapsedSecs'] as int? ??
            previousEntry['duration'] as int? ??
            0;
        final prevExtraWeight = previousEntry['extra-weight'] as double? ?? 0.0;
        final prevDrillMins = prevDrillSecs ~/ 60;
        final prevDrillRemSecs = prevDrillSecs % 60;
        final ewSign = prevExtraWeight > 0 ? '+' : '';
        statsText =
            'Previous: ${prevDrillMins.toString().padLeft(2, '0')}:${prevDrillRemSecs.toString().padLeft(2, '0')} hold @ $ewSign${prevExtraWeight.toStringAsFixed(1)} lbs';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Text(
      statsText,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
        fontStyle: FontStyle.italic,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSetIndicator(int totalSets, String effortKind, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Set dots indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(totalSets, (index) {
            final isCompleted = index < _currentSet - 1;
            final isCurrent = index == _currentSet - 1;
            final isSkipped =
                _skippedSets[_exercises[_currentExerciseIndex]['id']]?.contains(
                  index,
                ) ??
                false;

            return GestureDetector(
              onTap: () => _jumpToSet(index + 1),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: isCurrent ? 14 : 10,
                height: isCurrent ? 14 : 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted && !isSkipped
                      ? theme.colorScheme.primary.withOpacity(0.8)
                      : isCurrent
                      ? theme.colorScheme.primary.withAlpha((0.5 * 255).round())
                      : theme.colorScheme.onSurface.withAlpha(
                          (0.2 * 255).round(),
                        ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSetControls(ThemeData theme) {
    if (_exercises.isEmpty) return const SizedBox.shrink();

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final isTimerBased =
        effortKind == 'timed' || effortKind == 'round' || effortKind == 'drill';
    final timerKey = '$effortId-${_currentSet - 1}';
    final isTimerRunning = _effortRunning[timerKey] ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Previous set button
        _buildArrowButton(
          icon: Icons.arrow_back,
          label: 'Previous Set',
          isEnabled: _currentSet > 1 || _currentExerciseIndex > 0,
          onPressed: (_currentSet > 1 || _currentExerciseIndex > 0)
              ? _previousSet
              : null,
          theme: theme,
          isPrimary: false,
        ),

        // Center controls (add, delete, play/pause)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Play/pause icon - only for timer-based exercises (hidden in edit mode)
            if (isTimerBased && !widget.editMode) ...[
              _buildIconButton(
                isTimerRunning ? Icons.pause : Icons.play_arrow,
                theme,
                () => _toggleEffortTimer(effortId),
                tooltip: isTimerRunning ? 'Pause' : 'Start',
              ),
              const SizedBox(width: 24),
            ],
            // Add entry/set button
            _buildIconButton(
              Icons.playlist_add,
              theme,
              _addSet,
              tooltip: 'Add set',
            ),
            const SizedBox(width: 24),
            // Delete last set button
            _buildIconButton(
              Icons.delete_outline,
              theme,
              _deleteLastSet,
              tooltip: 'Delete Last Set',
            ),
          ],
        ),

        // Forward action: Log Set in live mode; plain navigation in edit mode
        _buildArrowButton(
          icon: Icons.arrow_forward,
          label: widget.editMode ? 'Next' : 'Log Set',
          isEnabled: true,
          onPressed: widget.editMode ? _nextSetInEditMode : _logSet,
          theme: theme,
          isPrimary: true,
        ),
      ],
    );
  }

  Widget _buildArrowButton({
    required IconData icon,
    required String label,
    required bool isEnabled,
    required VoidCallback? onPressed,
    required ThemeData theme,
    required bool isPrimary,
  }) {
    return Tooltip(
      message: label,
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle),
        child: Material(
          shape: const CircleBorder(),
          color: isEnabled
              ? (isPrimary
                    ? theme.colorScheme.primary.withOpacity(0.8)
                    : theme.colorScheme.onSurface.withAlpha(
                        (0.1 * 255).round(),
                      ))
              : theme.colorScheme.onSurface.withAlpha((0.05 * 255).round()),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                size: isPrimary ? 28 : 24,
                color: isEnabled
                    ? (isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface.withAlpha(
                              (0.5 * 255).round(),
                            ))
                    : theme.colorScheme.onSurface.withAlpha(
                        (0.2 * 255).round(),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    ThemeData theme,
    VoidCallback onPressed, {
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: theme.colorScheme.onSurface.withAlpha((0.5 * 255).round()),
        iconSize: 28,
      ),
    );
  }
}

class _ExerciseNoteSheet extends StatefulWidget {
  final WorkoutState workoutState;
  final Exercise exercise;
  final String? currentSessionId;

  const _ExerciseNoteSheet({
    required this.workoutState,
    required this.exercise,
    required this.currentSessionId,
  });

  @override
  State<_ExerciseNoteSheet> createState() => _ExerciseNoteSheetState();
}

class _ExerciseNoteSheetState extends State<_ExerciseNoteSheet> {
  late TextEditingController _controller;
  Timer? _debounce;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.workoutState.getExerciseNote(widget.exercise.id)?.note ?? '',
    );
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _hasUnsavedChanges = true);
    _debounce = Timer(const Duration(milliseconds: 500), () {
      widget.workoutState.saveExerciseNote(
        widget.exercise.id,
        value,
        sessionId: widget.currentSessionId,
      );
      if (mounted) setState(() => _hasUnsavedChanges = false);
    });
  }

  void _forceSave() {
    if (!_hasUnsavedChanges) return;
    _debounce?.cancel();
    _debounce = null;
    widget.workoutState.saveExerciseNote(
      widget.exercise.id,
      _controller.text,
      sessionId: widget.currentSessionId,
    );
    _hasUnsavedChanges = false;
  }

  @override
  void dispose() {
    _forceSave();
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom +
        16;
    final showCounter = _controller.text.length > 500;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // Exercise name label
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              widget.exercise.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
                letterSpacing: 0.4,
              ),
            ),
          ),

          // Text field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _controller,
              maxLines: null,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.9),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Add notes, cues, reminders…',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
              onChanged: _onChanged,
            ),
          ),

          // Character counter (only when > 500 chars)
          if (showCounter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_controller.text.length}/∞',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.45),
                    fontSize: 11,
                  ),
                ),
              ),
            ),

          SizedBox(height: bottomPadding),
        ],
      ),
    );
  }
}

/// Deduplicate reps/sets/load capabilities into a single reps option
List<String> _deduplicateCapabilities(List<String> capabilities) {
  final strSet = capabilities.toSet();
  final repsLoadSetVariants = {'reps', 'sets', 'load'};

  // Remove sets and load if any of the reps/sets/load variants exist
  if (strSet.any((cap) => repsLoadSetVariants.contains(cap))) {
    strSet.removeWhere((cap) => cap == 'sets' || cap == 'load');
    // Ensure 'reps' is included as the canonical value
    if (!strSet.contains('reps') &&
        strSet.any((cap) => repsLoadSetVariants.contains(cap))) {
      strSet.add('reps');
    }
  }

  return strSet.toList();
}
