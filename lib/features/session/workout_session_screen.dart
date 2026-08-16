import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/constants/workout_constants.dart';
import '../../core/constants/capability.dart';
import '../../state/settings/settings_state.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../core/utils/unit_formatter.dart';
import '../../core/utils/rest_ping_utils.dart';
import '../../state/workout/workout_state.dart';
import '../exercise/exercise_picker_screen.dart';
import '../../widgets/pickers/modality_picker_dialog.dart';
import '../../core/constants/modality_config.dart';
import '../../core/services/stats_progress_service.dart';
import '../../data/models/models.dart';
import '../../widgets/session/inline_metric_editor.dart';
import '../../widgets/session/duration_entry_dialog.dart';
import '../../widgets/session/pr_toast.dart';
import '../../widgets/layout/omni_bottom_cta.dart';
import '../../state/routine/routine_state.dart';
import '../../core/services/session_summary_service.dart';
import '../../core/navigation/navigation.dart';
import '../../core/models/session_edit_snapshot.dart';
import 'rest_timer_strip.dart';
import 'session_summary_screen.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';

part 'workout_session_timer_mixin.dart';
part 'workout_session_list_view.dart';
part 'workout_session_detail_view.dart';
part 'workout_session_edit_mode.dart';
part 'workout_session_finish.dart';
part 'workout_session_global_timer.dart';

// Library-level constants used across part files.
const double _kSessionScrollBottomExtra = 24.0;
const double _kBottomControlsClearance = 140.0 + _kSessionScrollBottomExtra;
const double _kBackFromDetailBottomPeekFraction = 0.05;
const Duration _kTimerUpdateInterval = Duration(seconds: 1);
/// Animation duration used to coordinate the rest-timer strip's
/// appearance and disappearance with the scrollable's bottom
/// padding so the content does not jolt underneath the user. The
/// strip itself uses the same duration via
/// [RestTimerStrip.animationDuration].
const Duration _kRestStripAnimationDuration = RestTimerStrip.animationDuration;

Future<T?> _pushSessionReplacement<T, TO>(
  BuildContext context,
  WidgetBuilder builder, {
  TO? result,
}) {
  return OmniNavigator.pushReplacement<T, TO>(context, builder, result: result);
}

class WorkoutSessionScreen extends StatefulWidget {
  final WorkoutState workoutState;
  final RoutineState routineState;
  final SessionSummaryService sessionSummaryService;
  final Future<void> Function(String sessionId)? onSessionSaved;
  final String? initialFocusId;
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  /// When true the screen shows a frozen review/edit view of a completed session:
  /// no timers run, no set logging, values remain editable for correction.
  final bool editMode;

  /// Optional modality hint injected from the home screen when navigating into
  /// a rolling session via a modality tile.  Passed straight through to
  /// [ExercisePickerScreen] as [sessionModality] so the picker pre-filters
  /// exercises by the chosen modality even though the session itself has a
  /// null modality field.  Has no effect when the session already has a modality.
  final String? preferredModality;

  WorkoutSessionScreen({
    super.key,
    required this.workoutState,
    required this.routineState,
    required this.sessionSummaryService,
    this.onSessionSaved,
    this.initialFocusId,
    required this.settingsState,
    required this.timerAlertService,
    RestNotificationService? restNotificationService,
    this.editMode = false,
    this.preferredModality,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen>
    with WorkoutSessionTimerMixin, WidgetsBindingObserver {
  // Constants

  @override
  List<Map<String, dynamic>> _exercises = [];
  int _currentExerciseIndex = 0;
  @override
  int _currentSet = 1;
  bool _isLoading = true;
  bool _showListView =
      true; // Toggle between list view and detail view - default to list
  bool _hasError = false;
  String _errorMessage = '';

  // Scroll controller for the exercise list view. Scrolled to the bottom
  // when returning from exercise detail so the user lands near 'Add Exercise'.
  final ScrollController _listScrollController = ScrollController();

  // Track skipped sets per effort (UI-only state)
  final Map<String, Set<int>> _skippedSets = {};

  // Track which set keys have been logged this session (effortId-entryIndex).
  // Prevents the rest timer from restarting when navigating back/forward
  // through already-logged sets.
  final Set<String> _loggedSetKeys = {};

  // D-8 throttle for the in-session PR toast. Tracks the session's running best
  // e1RM per exercise (keyed by exerciseId). The toast fires only when:
  // 1. The e1RM exceeds the standing best (all-time best from completed sessions)
  // 2. AND the e1RM exceeds the session's running best (highest e1RM logged in
  //    this session for this exercise)
  // This ensures:
  // - Re-saving an already-celebrated set does not re-trigger (same e1RM)
  // - A lesser set after a greater set does not trigger (doesn't exceed session best)
  // - Ascending bests each trigger once (each exceeds the previous session best)
  // See `.github/agents/plans/pr-celebration-throttle-plan.md`.
  final Map<String, double> _sessionRunningBestE1RM = {};
  /// Session-scoped running max-reps per exercise. Mirror of
  /// [_sessionRunningBestE1RM] for the bodyweight PR axis —
  /// populated by [_maybeShowPRToast] when a bodyweight set beats
  /// the standing / session best. Used so a second set at the
  /// same or lower reps never re-fires the toast for the same
  /// exercise (D-8 throttle applied symmetrically to both axes).
  final Map<String, int> _sessionRunningBestReps = {};

  @override
  Timer? _ticker;
  String _elapsedFormatted = '00:00';

  void _updateUi(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

  void _beginSetTransition(int direction) {
    _setTransitionResetTimer?.cancel();
    _setTransitionDirection = direction;
    _setTransitionResetTimer = Timer(OmniTheme.animationDuration, () {
      if (!mounted) return;
      setState(() {
        _setTransitionDirection = null;
      });
    });
  }

  void _clearSetTransition() {
    _setTransitionResetTimer?.cancel();
    _setTransitionResetTimer = null;
    _setTransitionDirection = null;
  }

  // Tracks the elapsed-seconds value at which the last rest ping fired per
  // effort. Entry is removed when rest ends (so next rest starts fresh).
  @override
  final Map<String, int> _lastRestPingFiredAt = {};

  // Edit mode buffer: tracks pending changes that haven't been saved yet.
  // Key: 'effortId-entryIndex', Value: map of metricKey -> value.
  // Changes are flushed to the repository only when Save is clicked.
  final Map<String, Map<String, dynamic>> _editBuffer = {};

  // Per-entry expand/collapse state for the optional weight adjustment editor.
  final Map<String, bool> _weightAdjustExpanded = {};

  // Prevent duplicate finish flows from double taps.
  bool _isFinishingSession = false;

  // Edit-mode snapshot captured once after session data first loads.
  // Used by _discardEditChanges() to roll back structural mutations
  // (add/remove exercise, add/remove set) that bypass the edit buffer.
  // Null when not in edit mode or after a successful Save.
  SessionEditSnapshot? _editSnapshot;

  // Horizontal set-navigation transition state used by the detail view.
  // ignore: unused_field
  int? _setTransitionDirection;
  Timer? _setTransitionResetTimer;

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

  // Guard against concurrent add/delete-set operations triggered by rapid taps.
  bool _isStructuralOp = false;

  // GlobalKeys used to locate the header icon buttons for coach mark positioning.
  final GlobalKey _notesIconKey = GlobalKey();
  final GlobalKey _infoIconKey = GlobalKey();
  // True once initExerciseHints() has been awaited at least once this session —
  // avoids redundant repository reads when navigating between exercises.
  bool _exerciseHintsLoaded = false;
  // The currently-visible coach mark overlay entry; at most one at a time.
  OverlayEntry? _coachMarkEntry;
  bool _isAppForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settingsState.addListener(_onSettingsChanged);
    if (!widget.editMode) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _tick();
    } else {
      _computeStaticElapsed();
    }
    _loadExercises();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.editMode) return;

    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      unawaited(widget.restNotificationService.cancelRestNotifications());
      _resyncEffortExpiryForLifecycle(appInForeground: true);
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _isAppForeground = false;
      _scheduleActiveRestNotifications();
      _resyncEffortExpiryForLifecycle(appInForeground: false);
    }
  }

  void _onSettingsChanged() {
    if (widget.editMode) return;
    _scheduleActiveRestNotifications();
  }

  void _scheduleActiveRestNotifications() {
    final restKey = _getMostRecentOpenRestKey();
    if (restKey == null) {
      unawaited(widget.restNotificationService.cancelRestNotifications());
      return;
    }

    EntryRest? openRest;
    final rests = widget.workoutState.getEntryRests(restKey.effortId);
    for (final rest in rests) {
      if (rest.entryIndex == restKey.entryIndex && rest.restEndMs == null) {
        openRest = rest;
        break;
      }
    }

    if (openRest == null) {
      unawaited(widget.restNotificationService.cancelRestNotifications());
      return;
    }

    unawaited(
      widget.restNotificationService.scheduleRestPings(
        restStartMs: openRest.restStartMs,
        intervalSecs: widget.settingsState.restPingInterval,
        soundId: widget.settingsState.restPingSound,
        playSound: !_isAppForeground,
      ),
    );
  }

  int _exerciseTopLevelOrder(Map<String, dynamic> exercise) {
    return (exercise['topLevelOrderIndex'] as int?) ??
        (exercise['executionOrder'] as int? ?? 0);
  }

  int _exerciseBlockOrder(Map<String, dynamic> exercise) {
    return (exercise['blockOrderIndex'] as int?) ??
        (exercise['executionOrder'] as int? ?? 0);
  }

  int _blockTopLevelOrder(SessionBlock block) {
    return block.topLevelOrderIndex ?? block.orderIndex;
  }

  int _compareExercisesByTopLevelOrder(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final topCompare = _exerciseTopLevelOrder(a).compareTo(
      _exerciseTopLevelOrder(b),
    );
    if (topCompare != 0) return topCompare;

    final aId = a['id'] as String? ?? '';
    final bId = b['id'] as String? ?? '';
    return aId.compareTo(bId);
  }

  int _compareExercisesByBlockOrder(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final blockCompare = _exerciseBlockOrder(a).compareTo(_exerciseBlockOrder(b));
    if (blockCompare != 0) return blockCompare;

    final topCompare = _exerciseTopLevelOrder(a).compareTo(
      _exerciseTopLevelOrder(b),
    );
    if (topCompare != 0) return topCompare;

    final aId = a['id'] as String? ?? '';
    final bId = b['id'] as String? ?? '';
    return aId.compareTo(bId);
  }

  List<Map<String, dynamic>> _sortExercisesForBlock(
    List<Map<String, dynamic>> exercises,
  ) {
    final sorted = List<Map<String, dynamic>>.from(exercises);
    sorted.sort(_compareExercisesByBlockOrder);
    return sorted;
  }

  List<({SessionBlock? block, Map<String, dynamic>? exercise})>
  _buildNonRollingTopLevelItems(List<Map<String, dynamic>> source) {
    final blocks = widget.workoutState.getSessionBlocks();
    final standaloneExercises = source.where((e) => e['blockId'] == null).toList()
      ..sort(_compareExercisesByTopLevelOrder);

    final items = <({SessionBlock? block, Map<String, dynamic>? exercise})>[];
    for (final block in blocks) {
      items.add((block: block, exercise: null));
    }
    for (final exercise in standaloneExercises) {
      items.add((block: null, exercise: exercise));
    }

    items.sort((a, b) {
      if (a.exercise != null && b.exercise != null) {
        return _compareExercisesByTopLevelOrder(a.exercise!, b.exercise!);
      }

      final aTopLevel =
          a.block != null
          ? _blockTopLevelOrder(a.block!)
          : _exerciseTopLevelOrder(a.exercise!);
      final bTopLevel =
          b.block != null
          ? _blockTopLevelOrder(b.block!)
          : _exerciseTopLevelOrder(b.exercise!);

      final compareTop = aTopLevel.compareTo(bTopLevel);
      if (compareTop != 0) return compareTop;

      // Legacy rows can collide on top-level order. Prefer standalone efforts
      // so list/detail ordering stays deterministic without timestamp fallback.
      if (a.exercise != null && b.block != null) return -1;
      if (a.block != null && b.exercise != null) return 1;

      final aId = a.block?.id ?? (a.exercise?['id'] as String? ?? '');
      final bId = b.block?.id ?? (b.exercise?['id'] as String? ?? '');
      return aId.compareTo(bId);
    });

    return items;
  }

  List<Map<String, dynamic>> _buildNonRollingDisplayOrderedExercises(
    List<Map<String, dynamic>> source,
  ) {
    final items = _buildNonRollingTopLevelItems(source);

    final ordered = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item.exercise != null) {
        ordered.add(item.exercise!);
        continue;
      }

      final blockId = item.block!.id;
      final blockExercises = _sortExercisesForBlock(
        source.where((e) => e['blockId'] == blockId).toList(),
      );
      ordered.addAll(blockExercises);
    }

    return ordered;
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
        if (widget.workoutState.isRollingSession) {
          _exercises = _exercises.where((e) => e['blockId'] != null).toList();
          final blocks = widget.workoutState.getSessionBlocks();
          final reordered = <Map<String, dynamic>>[];
          for (final block in blocks) {
            reordered.addAll(_exercises.where((e) => e['blockId'] == block.id));
          }
          _exercises = reordered;
        } else {
          // Keep detail navigation in the exact same sequence as the list view.
          _exercises = _buildNonRollingDisplayOrderedExercises(_exercises);
        }

        // Pre-populate timer state from persisted entries for all timer-based exercises
        _restoreTimerStateFromPersisted(_exercises);

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
            initialDetailIndex = idx;
            initialDetailSet = _initialSetForExerciseIndex(idx);
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

      // Auto-open exercise picker on first load if session has no exercises
      if (_shouldAutoOpenPicker()) {
        _scheduleAutoOpenPicker();
      }
    } catch (e) {
      debugPrint('Error loading exercises: $e');
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

  @override
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

  Future<void> _focusExerciseDetail(
    int index, {
    int setNumber = 1,
    bool preserveSetTransition = false,
  }) async {
    if (!mounted || index < 0 || index >= _exercises.length) return;
    final requestId = ++_focusRequestId;

    // **Await** note load BEFORE transitioning to detail mode.
    // This guarantees cache is populated before rendering note-dependent UI.
    await _loadExerciseNoteForIndex(index);

    if (!mounted || requestId != _focusRequestId) return;

    final entries =
        _exercises[index]['entries'] as List<Map<String, dynamic>>? ?? [];
    final maxSet = entries.isNotEmpty ? entries.length : 1;
    final safeSetNumber = setNumber.clamp(1, maxSet).toInt();

    if (!preserveSetTransition) {
      _clearSetTransition();
    }
    setState(() {
      _currentExerciseIndex = index;
      _currentSet = safeSetNumber;
      _showListView = false;
    });

    // Load hint flags once per session, then schedule the coach mark.
    if (!_exerciseHintsLoaded) {
      await widget.workoutState.initExerciseHints();
      _exerciseHintsLoaded = true;
    }
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowExerciseCoachMark();
      });
    }
  }

  /// Get the RoundInstance for a specific round (effortId + roundIndex).
  /// Returns null if the round doesn't exist or isn't a round-kind effort.
  @override
  RoundInstance? _getRoundInstance(String effortId, int roundIndex) {
    final rounds = widget.workoutState.getRoundsForEffort(effortId);
    if (roundIndex < 0 || roundIndex >= rounds.length) return null;
    return rounds[roundIndex];
  }

  /// Get the TimedInstance for a specific timed/drill entry (effortId + entryIndex).
  /// Returns null if the entry doesn't exist or isn't a timed/drill effort.
  @override
  TimedInstance? _getTimedInstance(String effortId, int entryIndex) {
    final instances = widget.workoutState.getTimedInstancesForEffort(effortId);
    if (entryIndex < 0 || entryIndex >= instances.length) return null;
    return instances[entryIndex];
  }

  @override
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

  int _initialSetForExerciseIndex(int exerciseIndex) {
    if (exerciseIndex < 0 || exerciseIndex >= _exercises.length) {
      return 1;
    }

    final exercise = _exercises[exerciseIndex];
    final effortId = exercise['id'] as String?;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final entries = exercise['entries'] as List<Map<String, dynamic>>? ?? [];

    if (effortId == null || effortId.isEmpty || entries.isEmpty) {
      return 1;
    }

    for (int i = 0; i < entries.length; i++) {
      if (!_isSetLogged(effortId, i, effortKind)) {
        return i + 1;
      }
    }

    return entries.length;
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
        unawaited(widget.restNotificationService.cancelRestNotifications());
        _lastRestPingFiredAt.remove(effortId);
      }
    }

    // For timed/drill: finish the TimedInstance to persist wall-clock duration.
    // Safe no-op if already finished via timer expiry.
    if ((effortKind == 'timed' || effortKind == 'drill') &&
        !isSkippedTimedEntry) {
      unawaited(widget.restNotificationService.cancelEffortTimerNotification());
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
        await widget.restNotificationService.cancelEffortTimerNotification();
        await widget.workoutState.endRoundEarly(effortId, _currentSet - 1);
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

    // In-session personal-record check. Fires the brief, non-blocking
    // "Congrats! New PR" toast when the just-logged strength set's Epley
    // e1RM strictly exceeds the user's all-time best for the exercise
    // (per the Stats screen's PR definition). The check is gated on
    // `set` only (D-5) and skips skipped entries (D-7); edit mode is
    // also blocked inside the helper (D-6). The SnackBar is fire-and-
    // forget — it never awaits and never blocks the rest timer or the
    // set advance below.
    //
    // Plan: .github/agents/plans/in-session-pr-toast-plan.md
    // Decision Ledger: D-1 (Epley), D-2 (standing best), D-3 (strict
    // greater), D-5 (set only), D-6 (no edit), D-7 (no skip),
    // D-8 (one toast per beating set).
    if (effortKind == 'set' && !isSkippedSetKindEntry) {
      final exerciseId = (exercise['exerciseId'] as String?) ?? '';
      final reps = (currentEntry['reps'] as int?) ?? 0;
      final weight = (currentEntry['weight'] as double?) ?? 0.0;
      await _maybeShowPRToast(
        effortId: effortId,
        exerciseId: exerciseId,
        entryIndex: _currentSet - 1,
        reps: reps,
        weight: weight,
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
      unawaited(
        widget.restNotificationService.scheduleRestPings(
          restStartMs: DateTime.now().millisecondsSinceEpoch,
          intervalSecs: widget.settingsState.restPingInterval,
          soundId: widget.settingsState.restPingSound,
          playSound: !_isAppForeground,
        ),
      );
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
        }
      }
    });

    if (nextExerciseIndex != null) {
      unawaited(_loadExerciseNoteForIndex(nextExerciseIndex!));
    }
  }

  /// Checks if the just-logged strength set is a new personal record
  /// and, if so, shows the brief, non-blocking "Congrats! New PR"
  /// SnackBar.
  ///
  /// Returns silently (no toast) when the set is not eligible or is
  /// not a PR. The call is fire-and-forget from `_logSet` — it never
  /// blocks the rest timer or the set advance.
  ///
  /// Decision Ledger references (in
  /// `.github/agents/plans/in-session-pr-toast-plan.md`):
  /// - D-1: Epley e1RM = weight × (1 + reps / 30)
  /// - D-2: Standing best via `StatsProgressService.getAllTimeBestE1RM`
  ///   (completed sessions only — in-progress sets are excluded)
  /// - D-3: Strictly greater than the standing best
  /// - D-5: Strength (`set`) sets only — gated by the caller
  /// - D-6: Suppressed in edit mode
  /// - D-7: Skipped sets (zero reps) are excluded — gated by the caller
  /// - D-8: One toast per beating set (default); throttle hook is
  ///   `_sessionRunningBestE1RM` (declared alongside `_loggedSetKeys`)
  Future<void> _maybeShowPRToast({
    required String effortId,
    required String exerciseId,
    required int entryIndex,
    required int reps,
    required double weight,
  }) async {
    // D-6: no toast in edit mode.
    if (widget.editMode) return;
    if (exerciseId.isEmpty) return;

    // Two axes:
    //   - Weight axis (e1RM) when the set has added external weight
    //     (`weight > 0`). Standing best comes from
    //     `getAllTimeBestE1RM`.
    //   - Reps axis (bodyweight) when the set has no added weight
    //     (`weight == 0`) and positive reps. Standing best comes
    //     from `getAllTimeBestReps`.
    //
    // Both axes share the strict `>` comparison (D-3) and the D-8
    // throttle (`_sessionRunningBestE1RM` for the weight axis,
    // `_sessionRunningBestReps` for the reps axis). The reps-axis
    // logic mirrors the e1RM-axis logic so the in-session toast,
    // the post-workout summary, and the Stats screen always agree
    // on the same verdict for the same set
    // (`.github/agents/plans/stats-summary-fix-pack-plan.md`,
    // Item 2 — rep-based record parity).
    final hasAddedWeight = weight > 0;
    if (hasAddedWeight) {
      final newE1rm = StatsProgressService.epley1RM(weight, reps);
      // `null` means reps or weight was non-positive — the set
      // has no meaningful e1RM and the PR check is skipped.
      if (newE1rm != null) {
        final standingBest = await StatsProgressService(
          widget.workoutState.repository,
        ).getAllTimeBestE1RM(exerciseId);

        // D-3: strictly greater. A set equal to the standing best
        // is NOT a PR (matches the Stats screen's ">" comparison).
        if (newE1rm > standingBest) {
          // D-8 throttle: also beats the session's running best.
          final sessionBest = _sessionRunningBestE1RM[exerciseId] ?? 0.0;
          if (newE1rm > sessionBest) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(
              PRToast.buildPRSnackBar(Theme.of(context)),
            );
            _sessionRunningBestE1RM[exerciseId] = newE1rm;
          }
        }
      }
    } else if (reps > 0) {
      // Reps-axis (bodyweight) path. Mirrors the e1RM check above
      // using `StatsProgressService.getAllTimeBestReps`.
      final standingReps = await StatsProgressService(
        widget.workoutState.repository,
      ).getAllTimeBestReps(exerciseId);

      if (reps > standingReps) {
        final sessionBest = _sessionRunningBestReps[exerciseId] ?? 0;
        if (reps > sessionBest) {
          if (!mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(
            PRToast.buildRepPRSnackBar(Theme.of(context)),
          );
          _sessionRunningBestReps[exerciseId] = reps;
        }
      }
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
    _beginSetTransition(-1);
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
        // Persist reps, weight, and optional weight adjustment.
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
        if (currentEntry['extra-weight'] != null) {
          await widget.workoutState.updateEntryValue(
            effortId,
            entryIndex,
            'extra-weight',
            (currentEntry['extra-weight'] as num).toDouble(),
          );
        }
        break;
      case 'timed':
        // Duration is tracked in TimedInstance (wall-clock); persist companion metrics.
        await widget.workoutState.updateEntryValue(
          effortId,
          entryIndex,
          'distance',
          currentEntry['distance'] as double? ?? 0.0,
        );
        if (currentEntry['extra-weight'] != null) {
          await widget.workoutState.updateEntryValue(
            effortId,
            entryIndex,
            'extra-weight',
            currentEntry['extra-weight'] as double,
          );
        }
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

  Future<void> _addSet() async {
    if (_isStructuralOp || _exercises.isEmpty) return;

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final cachedEntries =
        exercise['entries'] as List<Map<String, dynamic>>? ?? const [];
    final hasLoad = (exercise['capabilities'] as List?)?.contains('load') ??
        false;

    if (cachedEntries.length >= WorkoutConstants.maxEntriesPerEffort) return;

    _isStructuralOp = true;
    try {
      // Mark structural change so the discard-confirmation fires on Back.
      if (widget.editMode) _hasStructuralChanges = true;

      // Source-of-truth read for the prior entry's values: pull
      // fresh from the state layer (not the screen's cached
      // `_exercises`, which is only refreshed on explicit
      // `_loadExercises()` calls). The state layer is kept in sync
      // by every successful `updateEntryValue` → repository write,
      // so this reads whatever the user has typed so far in the
      // current session.
      final liveEntries = widget.workoutState
          .getExercisesWithEntries()
          .firstWhere((e) => e['id'] == effortId)['entries']
          as List;
      final lastEntry = liveEntries.isEmpty
          ? null
          : liveEntries.last as Map<String, dynamic>;

      // Build the `previousValues` map from the last entry's values
      // so the new set/interval/round/drill pre-fills with the
      // user's prior values (June 2026, exercise-set-last-value-
      // plan). One map per effort kind — only keys the state layer
      // accepts for that kind are included. When there is no prior
      // entry (the freshly-added-exercise case), no map is passed
      // and the state layer's app-wide defaults apply.
      final previousValues = lastEntry == null
          ? null
          : _buildPreviousValues(lastEntry, effortKind, hasLoad);

      await widget.workoutState.addEntry(
        effortId,
        previousValues: previousValues,
      );
      await _loadExercises();
    } finally {
      _isStructuralOp = false;
    }
  }

  /// Build the `previousValues` map for the new entry from the prior
  /// entry's stored values. Pure function — no side effects, no
  /// repository calls. Returns `null` when no carry-forward key is
  /// available (e.g. the prior entry has no values for any of the
  /// supported metrics), which lets the state layer fall back to its
  /// app-wide defaults.
  ///
  /// Per-effort-kind contract:
  ///
  ///  * `set`: `reps` (int), `weight` (double); `extra-weight`
  ///    (double) is also carried when the exercise lacks `load`
  ///    capability (parity with `SessionCore.addEntry`, which
  ///    creates an `extra-weight` observation in that case).
  ///  * `round`: `round-duration` (int seconds).
  ///  * `timed`: `extra-weight` (double).
  ///  * `drill`: `extra-weight` (double).
  ///
  /// Unknown / missing keys on the prior entry are silently skipped;
  /// the state layer's `(previousValues?['k'] as T?) ?? default`
  /// pattern then falls back to the app-wide default for that key.
  Map<String, dynamic>? _buildPreviousValues(
    Map<String, dynamic> lastEntry,
    String effortKind,
    bool hasLoad,
  ) {
    final values = <String, dynamic>{};

    void putInt(String key) {
      final v = lastEntry[key];
      if (v is int) values[key] = v;
    }

    void putDouble(String key) {
      final v = lastEntry[key];
      if (v is double) values[key] = v;
    }

    switch (effortKind) {
      case 'set':
        putInt('reps');
        putDouble('weight');
        if (!hasLoad) {
          putDouble('extra-weight');
        }
        break;
      case 'round':
        final v = lastEntry['round-duration'];
        if (v is int) values['round-duration'] = v;
        break;
      case 'timed':
      case 'drill':
        putDouble('extra-weight');
        break;
      default:
        putInt('reps');
        putDouble('weight');
    }

    return values.isEmpty ? null : values;
  }

  Future<void> _deleteCurrentSet() async {
    if (_isStructuralOp || _exercises.isEmpty) return;
    _isStructuralOp = true;

    try {
      final exercise = _exercises[_currentExerciseIndex];
      final effortId = exercise['id'] as String;
      final exerciseName = exercise['name'] as String;
      final entries = exercise['entries'] as List<Map<String, dynamic>>;
      final effortKind = exercise['effortKind'] as String? ?? 'set';
      final currentIndex = _currentSet - 1;

      if (entries.isEmpty) return;

      final setLabel = effortKind == 'round'
          ? 'Round'
          : (effortKind == 'timed'
                ? 'Interval'
                : (effortKind == 'drill' ? 'Hold' : 'Set'));

      final isLogged = _isSetLogged(effortId, currentIndex, effortKind);

      // If this is the last entry, always warn since it removes the entire exercise
      if (entries.length == 1) {
        final confirmed = await ConfirmationDialog.showTwoChoice(
          context: context,
          title: 'Remove Exercise?',
          body: Text(
            'This is the last ${setLabel.toLowerCase()} for "$exerciseName". '
            'Deleting it will remove the entire exercise from your session.\n\n'
            'Continue?',
          ),
          dismissLabel: 'Cancel',
          confirmLabel: 'Remove',
          dismissKey: const Key('workout-remove-exercise-cancel'),
          confirmKey: const Key('workout-remove-exercise-confirm'),
          isDestructive: true,
        );

        if (!confirmed) return;

        // Delete the entry and remove the exercise
        if (widget.editMode) _hasStructuralChanges = true;
        _inProgressKeys.removeWhere((k) => k.startsWith('$effortId-'));
        await widget.workoutState.deleteEntry(effortId, currentIndex);
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

      // Multi-set: only confirm if the set has been logged
      if (isLogged) {
        final confirmed = await ConfirmationDialog.showTwoChoice(
          context: context,
          title: 'Delete logged $setLabel?',
          body: const Text('This cannot be undone.'),
          dismissLabel: 'Cancel',
          confirmLabel: 'Delete',
          dismissKey: const Key('workout-delete-logged-entry-cancel'),
          confirmKey: const Key('workout-delete-logged-entry-confirm'),
          isDestructive: true,
        );

        if (!confirmed) return;
      }

      if (widget.editMode) _hasStructuralChanges = true;
      await widget.workoutState.deleteEntry(effortId, currentIndex);
      await _loadExercises();

      // Adjust current set if it now exceeds new entries length
      setState(() {
        final newCount = entries.length - 1;
        if (_currentSet > newCount) {
          _currentSet = newCount.clamp(1, newCount);
        }
      });
    } finally {
      _isStructuralOp = false;
    }
  }

  Future<void> _updateMetricValue(
    String effortId,
    int entryIndex,
    String metricKey,
    dynamic value,
  ) async {
    // Weight values come from InlineMetricEditor in the user's preferred display
    // unit. Convert to canonical kg before any persistence path (edit-mode buffer
    // or live repository write) so that SessionSummaryBuilder can treat all stored
    // weight observations as kg without a second conversion.
    if ((metricKey == 'weight' || metricKey == 'extra-weight') &&
        value is double) {
      value = UnitFormatter.toCanonicalWeight(value, widget.settingsState);
    }

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

  void _jumpToSet(int setNumber) {
    // Auto-pause timer if in progress before jumping to another set.
    if (_exercises.isNotEmpty && _currentExerciseIndex < _exercises.length) {
      final ex = _exercises[_currentExerciseIndex];
      final effortId = ex['id'] as String;
      final effortKind = ex['effortKind'] as String? ?? 'set';
      if (effortKind == 'timed' ||
          effortKind == 'drill' ||
          effortKind == 'round') {
        final timerKey = '$effortId-${_currentSet - 1}';
        if (_effortRunning[timerKey] == true) {
          _pauseEffortTimer(effortId, _currentSet - 1);
        }
      }
    }
    _beginSetTransition(setNumber > _currentSet ? 1 : -1);
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

  void _switchExercise(int delta, {bool preserveSetTransition = false}) {
    final newIndex = _currentExerciseIndex + delta;
    if (newIndex < 0 || newIndex >= _exercises.length) return;
    // Auto-pause timer if in progress before switching exercise.
    if (_exercises.isNotEmpty && _currentExerciseIndex < _exercises.length) {
      final ex = _exercises[_currentExerciseIndex];
      final effortId = ex['id'] as String;
      final effortKind = ex['effortKind'] as String? ?? 'set';
      if (effortKind == 'timed' ||
          effortKind == 'drill' ||
          effortKind == 'round') {
        final timerKey = '$effortId-${_currentSet - 1}';
        if (_effortRunning[timerKey] == true) {
          _pauseEffortTimer(effortId, _currentSet - 1);
        }
      }
    }
    unawaited(
      _focusExerciseDetail(
        newIndex,
        preserveSetTransition: preserveSetTransition,
      ),
    );
  }

  /// Check if the exercise picker should auto-open on first session load.
  ///
  /// PR 6 / S-003 contract: new workouts land on a neutral empty session
  /// rather than auto-opening the picker. The user picks Add Exercise or
  /// Add Block from the balanced empty state; the picker only opens when
  /// the user explicitly asks for it.
  bool _shouldAutoOpenPicker() => false;

  /// Schedule the exercise picker to open after the current frame renders.
  /// PR 6: no-op — see [_shouldAutoOpenPicker]. Unreachable while
  /// [_shouldAutoOpenPicker] returns false; kept so restoring the
  /// behaviour is a one-line change at the predicate.
  void _scheduleAutoOpenPicker() {}

  Future<void> _addExercise({String? segmentId, String? blockId}) async {
    // Capture before the dialog so we can detect when this is the first exercise.
    final isFirstExercise = _exercises.isEmpty;
    final sessionModality = widget.workoutState.currentSession?.modality;
    final modality = sessionModality ?? widget.preferredModality;

    final selectedExercise = await OmniNavigator.push<Exercise>(
      context,
      (_) => ExercisePickerScreen(
        workoutState: widget.workoutState,
        sessionModality: modality,
      ),
    );

    if (selectedExercise != null) {
      String? effortKindOverride;

      // If the session has its own modality, use it as-is (modality config already set in state)
      // If the session has null modality:
      if (sessionModality == null) {
        if (widget.preferredModality != null) {
          // Rolling session with a preferred modality hint from the tile
          // Derive effort kind from that modality without showing picker
          effortKindOverride =
              ModalityConfig.forModality(
                widget.preferredModality,
              )?.effortKind ??
              'set';
        } else {
          // True free training: show modality picker
          final modalityResult = await showDialog<(bool, String?)>(
            context: context,
            builder: (context) => const ModalityPickerDialog(),
          );

          if (!context.mounted || modalityResult == null) {
            return; // user cancelled
          }

          final (_, pickedModality) = modalityResult;
          effortKindOverride =
              ModalityConfig.forModality(pickedModality)?.effortKind ?? 'set';
        }
      }

      String effortId = '';
      try {
        effortId = await widget.workoutState.addExerciseToSession(
          selectedExercise,
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

      // Assign to block when adding within a rolling session block.
      if (effortId.isNotEmpty && blockId != null) {
        try {
          await widget.workoutState.assignEffortToBlock(effortId, blockId);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to assign exercise to block: $e')),
            );
          }
        }
      }

      // Rolling sessions display exercises grouped in blocks. Session-level add
      // actions (no explicit blockId) create a new time-named block per add.
      if (effortId.isNotEmpty &&
          blockId == null &&
          widget.workoutState.isRollingSession) {
        try {
          await widget.workoutState.addSessionBlock();
          final blocks = widget.workoutState.getSessionBlocks();
          if (blocks.isNotEmpty) {
            await widget.workoutState.assignEffortToBlock(
              effortId,
              blocks.last.id,
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to assign exercise to block: $e')),
            );
          }
        }
      }

      // Reset the session start time to now when the FIRST exercise is added so
      // the global elapsed timer begins from zero at the moment training starts.
      if (effortId.isNotEmpty && isFirstExercise && !widget.editMode) {
        await widget.workoutState.resetSessionTimerStart();
      }

      // Mark structural change AFTER we know the add succeeded.
      if (widget.editMode && effortId.isNotEmpty) _hasStructuralChanges = true;
      await _loadExercises();

      if (effortId.isNotEmpty) {
        final idx = _exercises.indexWhere((e) => e['id'] == effortId);
        if (idx != -1) {
          await _focusExerciseDetail(idx);
        }
      }
    }
  }

  // ── Rolling session block management helpers ────────────────────────────

  Future<void> _showBlockRenameDialog(SessionBlock block) async {
    final ctrl = TextEditingController(text: block.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Block'),
        content: TextField(
          textCapitalization: TextCapitalization.sentences,
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Block name'),
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
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
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
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 300), ctrl.dispose);
    if (newName != null && newName.isNotEmpty && mounted) {
      final updated = SessionBlock(
        id: block.id,
        sessionId: block.sessionId,
        name: newName,
        orderIndex: block.orderIndex,
        createdAtMs: block.createdAtMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.workoutState.updateSessionBlock(updated);
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmAndDeleteBlock(SessionBlock block) async {
    final count = _exercises.where((e) => e['blockId'] == block.id).length;

    if (count == 0) {
      // Empty block — no confirmation needed.
      if (!mounted) return;
      await widget.workoutState.deleteSessionBlock(block.id);
      await _loadExercises();
      return;
    }

    // Non-empty block — confirm before cascade-deleting all exercises.
    final confirmed = await ConfirmationDialog.showTwoChoice(
      context: context,
      title: 'Delete Block?',
      body: Text(
        'This block contains $count exercise${count != 1 ? 's' : ''}. '
        'All exercises inside will be permanently deleted.',
      ),
      dismissLabel: 'Cancel',
      confirmLabel: 'Delete',
      dismissKey: const Key('session-delete-block-cancel'),
      confirmKey: const Key('session-delete-block-confirm'),
      isDestructive: true,
    );
    if (confirmed && mounted) {
      await widget.workoutState.deleteSessionBlock(block.id);
      await _loadExercises();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settingsState.removeListener(_onSettingsChanged);
    _setTransitionResetTimer?.cancel();
    _ticker?.cancel();
    // Cancel all effort timers
    for (final timer in _effortTimers.values) {
      timer?.cancel();
    }
    unawaited(widget.restNotificationService.cancelRestNotifications());
    unawaited(widget.restNotificationService.cancelEffortTimerNotification());
    _lastRestPingFiredAt.clear();
    // Remove any visible coach mark overlay before the widget tree tears down.
    _coachMarkEntry?.remove();
    _coachMarkEntry = null;
    _listScrollController.dispose();
    super.dispose();
  }

  /// Scrolls the exercise list to the bottom after the current frame renders.
  /// Called when navigating back from a detail view to the list view so the
  /// user lands near the 'Add Exercise' button at the bottom.
  void _scrollListToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_listScrollController.hasClients &&
          _listScrollController.position.maxScrollExtent > 0) {
        final position = _listScrollController.position;
        final max = position.maxScrollExtent;
        final target = (max -
                (position.viewportDimension *
                    _kBackFromDetailBottomPeekFraction))
            .clamp(0.0, max);
        _listScrollController.jumpTo(target);

        // Re-apply on the next frame in case late layout changes alter extent.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_listScrollController.hasClients) return;
          final settled = _listScrollController.position;
          final settledMax = settled.maxScrollExtent;
          final settledTarget = (settledMax -
                  (settled.viewportDimension *
                      _kBackFromDetailBottomPeekFraction))
              .clamp(0.0, settledMax);
          _listScrollController.jumpTo(settledTarget);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeColors = OmniTheme.colorsForTheme(widget.settingsState.appTheme);
    // Explicitly anchor FilledButton background to the active accent token so
    // the "Finish Workout" button â€” and any dialog opened from this screen â€”
    // cannot inherit a stale or reset colorScheme.primary from an intervening
    // overlay context.
    final sessionTheme = theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(themeColors.primary),
          foregroundColor: WidgetStatePropertyAll(theme.colorScheme.onPrimary),
        ),
      ),
    );
    // In edit mode, intercept the system back gesture so we can show the
    // "Unsaved changes" dialog before popping.  Non-edit sessions pop freely.
    final content = _buildContent(theme);
    if (!widget.editMode) return Theme(data: sessionTheme, child: content);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (!_showListView) {
          setState(() => _showListView = true);
          _scrollListToBottom();
        } else {
          _handleEditModeBack();
        }
      },
      child: Theme(data: sessionTheme, child: content),
    );
  }
}
