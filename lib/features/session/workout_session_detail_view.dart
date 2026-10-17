part of 'workout_session_screen.dart';

/// Bottom inset for the big duration readout in the timed/drill detail views.
///
/// Trimmed from the editor's default 32 px so the digits sit closer to the
/// controls below them, matching the reps screen's proportions.
const EdgeInsets _kTimedValuePadding = EdgeInsets.fromLTRB(32, 32, 32, 25);

/// Detail-view builders for [WorkoutSessionScreen].
///
/// Extension on [_WorkoutSessionScreenState] — because this file is a `part of`
/// the same library, all private fields and methods of the state class are
/// directly accessible without any forwarding or getters.
extension _SessionDetailViewBuilders on _WorkoutSessionScreenState {
  // ── Header actions ────────────────────────────────────────────────────────

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
            SizedBox(
              child: IconButton(
                key: const Key('exercise-info-button'),
                icon: Icon(
                  key: _infoIconKey,
                  Icons.info_outline,
                  size: 22,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
                onPressed: exercise == null
                    ? null
                    : () => _showExerciseInfoSheet(context, exercise),
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: OmniTheme.headerSecondaryActionSize,
                  minHeight: OmniTheme.headerSecondaryActionSize,
                ),
                tooltip: 'Exercise info',
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  child: IconButton(
                    key: const Key('exercise-note-button'),
                    icon: Icon(
                      key: _notesIconKey,
                      Icons.edit_note,
                      size: 22,
                      color: theme.colorScheme.onSurface.withOpacity(0.45),
                    ),
                    onPressed: exercise == null
                        ? null
                        : () => _showExerciseNoteSheet(context, exercise),
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: OmniTheme.headerSecondaryActionSize,
                      minHeight: OmniTheme.headerSecondaryActionSize,
                    ),
                    tooltip: 'Exercise note',
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

  // ── Weight unit label + hold weight row ───────────────────────────────────

  String get _preferredWeightUnitLabel =>
      UnitFormatter.weightLabelUpper(widget.settingsState);

  /// The hold's only input (D-2): one full-width weight row in the user's
  /// unit, underneath the digits. Always visible, never locked in the session
  /// editor, locked once a live hold is logged — a drill entry is logged
  /// exactly when its [TimedInstance] finished.
  Widget _buildHoldWeightRow(
    String effortId,
    int entryIndex,
    double currentValue,
  ) {
    return ValueStepperRow(
      key: ValueKey('$effortId-$entryIndex-weight'),
      metricType: 'weight',
      currentValue: currentValue,
      unitLabel: _preferredWeightUnitLabel,
      step: MetricStepping.weightStepFor(
        widget.settingsState.preferredWeightUnit,
      ),
      isReadOnly:
          !widget.editMode && _isSetLogged(effortId, entryIndex, 'drill'),
      onValueChanged: (value) =>
          _updateMetricValue(effortId, entryIndex, 'extra-weight', value),
    );
  }

  /// The caption value for one entry, or null when it is not logged.
  ///
  /// Resistance sets read `reps×weight` in the user's unit — a zero or a
  /// negative weight still reads, because the caption records what was carried;
  /// timed, drill and round entries read the locked time as `m:ss`.
  String? _loggedValueText(
    String effortId,
    int index,
    String effortKind,
    Map<String, dynamic> entry,
  ) {
    if (!_isSetLogged(effortId, index, effortKind)) return null;

    switch (effortKind) {
      case 'set':
        final reps = entry['reps'] as int? ?? 0;
        final weightKg = (entry['weight'] as num?)?.toDouble() ?? 0.0;
        final weightText = UnitFormatter.formatWeightValue(
          weightKg,
          widget.settingsState,
        );
        return '$reps×$weightText';
      case 'timed':
      case 'drill':
        final secs =
            _getTimedInstance(effortId, index)?.actualDurationSecs ?? 0;
        return OmniDateUtils.formatClock(secs * 1000);
      case 'round':
        final secs =
            _getRoundInstance(effortId, index)?.actualDurationSecs ?? 0;
        return OmniDateUtils.formatClock(secs * 1000);
    }
    return null;
  }

  // ── Metric widget (main per-effort-kind display) ──────────────────────────

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
        // Stored in canonical kg; convert to the user's preferred display unit.
        final weight = UnitFormatter.convertWeight(
          entryData['weight'] as double? ?? 0.0,
          widget.settingsState,
        );
        // O-2/D-5: in a live session a logged set is locked; the session
        // editor (widget.editMode) stays fully editable.
        final isLoggedNow =
            !widget.editMode &&
            _isSetLogged(effortId, entryIndex, effortKind);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            // The keys include the set, so navigating to another set throws the
            // row away — and with it any hold still running (S-4257).
            ValueStepperRow(
              key: ValueKey('$effortId-$entryIndex-reps'),
              metricType: 'reps',
              currentValue: reps,
              unitLabel: 'REPS',
              step: MetricStepping.repsPerStep.toDouble(),
              isReadOnly: isLoggedNow,
              onValueChanged: (value) =>
                  _updateMetricValue(effortId, entryIndex, 'reps', value),
            ),
            ValueStepperRow(
              key: ValueKey('$effortId-$entryIndex-weight'),
              metricType: 'weight',
              currentValue: weight,
              unitLabel: _preferredWeightUnitLabel,
              step: MetricStepping.weightStepFor(
                widget.settingsState.preferredWeightUnit,
              ),
              isReadOnly: isLoggedNow,
              onValueChanged: (value) =>
                  _updateMetricValue(effortId, entryIndex, 'weight', value),
            ),
          ],
        );

      case 'timed':
        final timedTimerKey = '$effortId-$entryIndex';
        final timedElapsed = _effortElapsed[timedTimerKey] ?? 0;
        final timedInstance = _getTimedInstance(effortId, entryIndex);
        final isTimedFinished =
            (timedInstance?.state ?? TimedState.notStarted) ==
            TimedState.finished;

        // Q-1 (owner O-13) restores the caption D-4 dropped: plain digits
        // above `ELAPSED`, or `COMPLETED` once the interval is finished. A
        // finished interval reads its locked logged time, which is also what
        // the logged line shows.
        final timedDisplayValue = isTimedFinished
            ? (timedInstance?.actualDurationSecs ?? timedElapsed)
            : timedElapsed;

        if (widget.editMode) {
          // Prefer buffered value so the editor reflects pending edits immediately.
          final bufferedSecs =
              _editBuffer['$effortId-$entryIndex']?['elapsedSecs'] as int?;
          final editDuration =
              bufferedSecs ??
              timedInstance?.actualDurationSecs ??
              (entryData['elapsedSecs'] as int? ?? timedElapsed);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InlineMetricEditor(
                metricType: 'duration',
                currentValue: editDuration,
                unitLabel: 'ELAPSED',
                onTap: () async {
                  final result = await showDurationEntryDialog(
                    context,
                    title: 'Edit Interval Duration',
                    initialSecs: editDuration,
                  );
                  if (result != null && mounted) {
                    unawaited(
                      _updateMetricValue(
                        effortId,
                        entryIndex,
                        'elapsedSecs',
                        result,
                      ),
                    );
                  }
                },
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

        return InlineMetricEditor(
          metricType: 'duration',
          currentValue: timedDisplayValue,
          unitLabel: isTimedFinished ? 'COMPLETED' : 'ELAPSED',
          emphasisTier: MetricEmphasisTier.dominant,
          isReadOnly: true,
          onTap: null,
          padding: _kTimedValuePadding,
          onValueChanged: (_) {},
        );

      case 'round':
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

        final bool isFinished =
            isExpired || round?.state == RoundState.finished;
        final bool isMidRound =
            !isFinished &&
            round != null &&
            round.state != RoundState.notStarted;

        final int stoppedDisplayValue;
        if (isFinished) {
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
          stoppedDisplayValue = roundDuration;
        }

        final bool roundRunning = _effortRunning[timerKey] ?? false;
        final int shownSeconds = (roundRunning ? remaining : stoppedDisplayValue)
            .toInt();
        // D-2: the ring is full before Start, follows the digits while the round
        // runs, freezes at its fraction when restored paused, and is empty once
        // the round is finished (expired or logged early).
        final double ringProgress = isFinished
            ? 0.0
            : (!roundRunning && !isMidRound)
            ? 1.0
            : (effectiveTarget <= 0 ? 1.0 : remaining / effectiveTarget);
        final int lengthSeconds = (roundRunning || isMidRound || isFinished)
            ? effectiveTarget
            : roundDuration;
        Future<void> editRoundLength() async {
          final result = await showDurationEntryDialog(
            context,
            title: 'Edit Round Duration',
            initialSecs: lengthSeconds,
          );
          if (result != null && mounted) {
            unawaited(
              _updateMetricValue(effortId, entryIndex, 'round-duration', result),
            );
          }
        }

        if (widget.editMode) {
          // Prefer buffered value so the editor reflects pending edits immediately.
          final bufferedRoundSecs =
              _editBuffer['$effortId-$entryIndex']?['round-duration'] as int?;
          final editRoundDuration =
              bufferedRoundSecs ??
              ((round != null && round.actualDurationSecs > 0)
                  ? round.actualDurationSecs
                  : roundDuration);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 24 + _kSessionScrollBottomExtra),
              ValueStepperRow(
                key: ValueKey('$effortId-$entryIndex-round-length'),
                metricType: 'duration',
                currentValue: editRoundDuration,
                unitLabel: 'ROUND LENGTH',
                min: 15,
                onEditorTap: () async {
                  final result = await showDurationEntryDialog(
                    context,
                    title: 'Edit Round Duration',
                    initialSecs: editRoundDuration,
                  );
                  if (result != null && mounted) {
                    unawaited(
                      _updateMetricValue(
                        effortId,
                        entryIndex,
                        'round-duration',
                        result,
                      ),
                    );
                  }
                },
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'round-duration',
                  (value as num).toInt(),
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            TimerRing(
              progress: ringProgress,
              running: roundRunning,
              size: 232,
              // Scale the digits down rather than let them overflow the ring
              // when the ambient text theme is larger than the app's own.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: InlineMetricEditor(
                  metricType: 'duration',
                  currentValue: shownSeconds,
                  unitLabel: isFinished ? 'COMPLETED' : 'REMAINING',
                  unitLabelColor: isExpired ? theme.colorScheme.error : null,
                  emphasisTier: MetricEmphasisTier.dominant,
                  isReadOnly: true,
                  onTap: null,
                  padding: EdgeInsets.zero,
                  onValueChanged: (_) {},
                ),
              ),
            ),
            const SizedBox(height: 24),
            ValueStepperRow(
              key: ValueKey('$effortId-$entryIndex-round-length'),
              metricType: 'duration',
              currentValue: lengthSeconds,
              unitLabel: 'ROUND LENGTH',
              min: 15,
              isReadOnly: roundRunning || isMidRound || isFinished,
              onEditorTap: editRoundLength,
              onValueChanged: (value) => _updateMetricValue(
                effortId,
                entryIndex,
                'round-duration',
                (value as num).toInt(),
              ),
            ),
          ],
        );

      case 'drill':
        final drillTimerKey = '$effortId-$entryIndex';
        final drillElapsed = _effortElapsed[drillTimerKey] ?? 0;
        final drillInstance = _getTimedInstance(effortId, entryIndex);
        final isDrillFinished =
            (drillInstance?.state ?? TimedState.notStarted) ==
            TimedState.finished;
        // Stored in canonical kg; convert to the user's preferred display unit.
        final drillExtraWeight = UnitFormatter.convertWeight(
          (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0,
          widget.settingsState,
        );

        // Q-1 (owner O-13) restores the caption (see the timed branch).
        final drillDisplayValue = isDrillFinished
            ? (drillInstance?.actualDurationSecs ?? drillElapsed)
            : drillElapsed;

        if (widget.editMode) {
          // Prefer buffered value so the editor reflects pending edits immediately.
          final bufferedDrillSecs =
              _editBuffer['$effortId-$entryIndex']?['elapsedSecs'] as int?;
          final editDrillDuration =
              bufferedDrillSecs ??
              drillInstance?.actualDurationSecs ??
              (entryData['elapsedSecs'] as int? ?? drillElapsed);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InlineMetricEditor(
                metricType: 'duration',
                currentValue: editDrillDuration,
                unitLabel: 'ELAPSED',
                onTap: () async {
                  final result = await showDurationEntryDialog(
                    context,
                    title: 'Edit Hold Duration',
                    initialSecs: editDrillDuration,
                  );
                  if (result != null && mounted) {
                    unawaited(
                      _updateMetricValue(
                        effortId,
                        entryIndex,
                        'elapsedSecs',
                        result,
                      ),
                    );
                  }
                },
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'elapsedSecs',
                  value,
                ),
              ),
              _buildHoldWeightRow(effortId, entryIndex, drillExtraWeight),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineMetricEditor(
              metricType: 'duration',
              currentValue: drillDisplayValue,
              unitLabel: isDrillFinished ? 'COMPLETED' : 'ELAPSED',
              emphasisTier: MetricEmphasisTier.dominant,
              isReadOnly: true,
              onTap: null,
              padding: _kTimedValuePadding,
              onValueChanged: (_) {},
            ),
            _buildHoldWeightRow(effortId, entryIndex, drillExtraWeight),
          ],
        );

      default:
        return Text('—', style: theme.textTheme.displayLarge);
    }
  }

  // ── Set bar / set controls / buttons ──────────────────────────────────────

  /// The count line the sets control shows, worded per effort kind.
  String _setCountText(int totalEntries, String effortKind) {
    switch (effortKind) {
      case 'timed':
        return 'Interval $_currentSet of $totalEntries';
      case 'round':
        final modality = widget.workoutState.currentSession?.modality;
        final noun = modality == 'sports' ? 'Period' : 'Round';
        return '$noun $_currentSet of $totalEntries';
      case 'drill':
        return 'Hold $_currentSet of $totalEntries';
      default:
        return 'Set $_currentSet of $totalEntries';
    }
  }

  /// The bar block pinned under the header (D-8): one segment per entry, each
  /// carrying the logged value of its entry as a caption. The count line lives
  /// in the sets control below the exercise's controls.
  Widget _buildSetBar(int totalEntries, String effortKind) {
    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final entries = exercise['entries'] as List<Map<String, dynamic>>;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SetSegmentBar(
        count: totalEntries,
        focusedIndex: _currentSet - 1,
        isLogged: (index) => _isSetLogged(effortId, index, effortKind),
        onTap: (index) => _jumpToSet(index + 1),
        captions: [
          for (var i = 0; i < totalEntries; i++)
            _loggedValueText(effortId, i, effortKind, entries[i]),
        ],
      ),
    );
  }

  Widget _buildSetControls(ThemeData theme) {
    if (_exercises.isEmpty) return const SizedBox.shrink();

    final exercise = _exercises[_currentExerciseIndex];
    final effortId = exercise['id'] as String;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final entryIndex = _currentSet - 1;

    // Determine whether current set has already been logged.
    final isLogged = _isSetLogged(effortId, entryIndex, effortKind);

    // Back nav arrow (left side)
    final backArrow = _buildNavArrow(
      icon: Icons.arrow_back,
      label: 'Previous Set',
      isEnabled: _currentSet > 1 || _currentExerciseIndex > 0,
      onPressed: (_currentSet > 1 || _currentExerciseIndex > 0)
          ? _previousSet
          : null,
      theme: theme,
    );

    // Forward nav arrow (right side — always shown)
    final forwardArrow = _buildNavArrow(
      icon: Icons.arrow_forward,
      label: 'Next',
      isEnabled: true,
      onPressed: widget.editMode ? _nextSetInEditMode : _nextSet,
      theme: theme,
    );

    if (widget.editMode) {
      // Edit mode keeps simple navigation-only controls for every effort kind.
      // Saving is what commits values (and finishes timer instances), so a
      // per-set Log button would be cosmetic only.
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [backArrow, forwardArrow],
      );
    }

    // Live mode center control state:
    // 1) Logged entries show status label.
    // 2) Timer entries that never started show Start.
    // 3) Paused timer entries show Resume.
    // 4) Otherwise show log button.
    Widget centerControl;
    if (isLogged) {
      centerControl = _buildLoggedLabel(theme);
    } else if (_isTimerEntryNotStarted(effortKind, effortId, entryIndex)) {
      centerControl = _buildTimerToggleButton(effortId, theme, 'Start');
    } else if (_isTimerEntryPaused(effortKind, effortId, entryIndex)) {
      centerControl = _buildTimerToggleButton(effortId, theme, 'Resume');
    } else {
      centerControl = _buildLogSetButton(effortKind, theme);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        backArrow,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: centerControl,
          ),
        ),
        forwardArrow,
      ],
    );
  }

  bool _isTimerEntryNotStarted(
    String effortKind,
    String effortId,
    int entryIndex,
  ) {
    if (effortKind == 'timed' || effortKind == 'drill') {
      final instance = _getTimedInstance(effortId, entryIndex);
      return (instance?.state ?? TimedState.notStarted) ==
          TimedState.notStarted;
    }
    if (effortKind == 'round') {
      final round = _getRoundInstance(effortId, entryIndex);
      return (round?.state ?? RoundState.notStarted) == RoundState.notStarted;
    }
    return false;
  }

  Widget _buildLoggedLabel(ThemeData theme) {
    return SizedBox(
      height: 64,
      child: Center(
        child: Text(
          'LOGGED',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary.withValues(alpha: 0.9),
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// True when the entry's timer was started and is currently paused.
  ///
  /// Live navigation no longer pauses a running timer, so this is reached
  /// only by a session restored from storage that was persisted mid-pause.
  /// Without a Resume control such an entry is a dead end: the in-progress
  /// lock blocks every other timer and nothing can restart this one.
  bool _isTimerEntryPaused(String effortKind, String effortId, int entryIndex) {
    if (effortKind == 'timed' || effortKind == 'drill') {
      return _getTimedInstance(effortId, entryIndex)?.state ==
          TimedState.paused;
    }
    if (effortKind == 'round') {
      return _getRoundInstance(effortId, entryIndex)?.state ==
          RoundState.paused;
    }
    return false;
  }

  Widget _buildTimerToggleButton(
    String effortId,
    ThemeData theme,
    String label,
  ) {
    return Tooltip(
      message: label,
      child: FilledButton(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
            ),
          ),
          minimumSize: WidgetStateProperty.all(
            const Size(double.infinity, OmniTheme.buttonPrimaryHeight),
          ),
        ),
        onPressed: () => _toggleEffortTimer(effortId),
        child: Text(label),
      ),
    );
  }

  /// Navigate to the next set or exercise WITHOUT logging (used when set is
  /// already logged or user just wants to move forward).
  void _nextSet() {
    final exercise = _exercises[_currentExerciseIndex];
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    if (_currentSet < entries.length) {
      _jumpToSet(_currentSet + 1);
    } else if (_currentExerciseIndex < _exercises.length - 1) {
      _beginSetTransition(1);
      _switchExercise(1, preserveSetTransition: true);
    }
  }

  String _logSetLabel(String effortKind) {
    switch (effortKind) {
      case 'timed':
        return 'Log Interval';
      case 'round':
        final modality = widget.workoutState.currentSession?.modality;
        return modality == 'sports' ? 'Log Period' : 'Log Round';
      case 'drill':
        return 'Log Hold';
      default:
        return 'Log Set';
    }
  }

  Widget _buildLogSetButton(String effortKind, ThemeData theme) {
    final label = _logSetLabel(effortKind);
    return Tooltip(
      message: label,
      child: FilledButton(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
            ),
          ),
          minimumSize: WidgetStateProperty.all(
            const Size(double.infinity, OmniTheme.buttonPrimaryHeight),
          ),
        ),
        onPressed: _logSet,
        child: Text(label),
      ),
    );
  }

  Widget _buildNavArrow({
    required IconData icon,
    required String label,
    required bool isEnabled,
    required VoidCallback? onPressed,
    required ThemeData theme,
  }) {
    return Tooltip(
      message: label,
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Material(
          shape: const CircleBorder(),
          color: isEnabled
              ? theme.colorScheme.onSurface.withAlpha((0.1 * 255).round())
              : theme.colorScheme.onSurface.withAlpha((0.05 * 255).round()),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(
                icon,
                size: 24,
                color: isEnabled
                    ? theme.colorScheme.onSurface.withAlpha((0.5 * 255).round())
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
}
