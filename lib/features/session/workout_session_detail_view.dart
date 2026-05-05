part of 'workout_session_screen.dart';

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
              key: _infoIconKey,
              child: IconButton(
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
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  key: _notesIconKey,
                  child: IconButton(
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

  // ── Weight unit label + weight adjustment section ─────────────────────────

  String get _preferredWeightUnitLabel =>
      UnitFormatter.weightLabelUpper(widget.settingsState);

  Widget _buildWeightAdjustmentSection({
    required ThemeData theme,
    required String effortId,
    required int entryIndex,
    required double currentValue,
    required ValueChanged<double> onValueChanged,
  }) {
    final key = '$effortId-$entryIndex';
    final isExpanded = _weightAdjustExpanded[key] ?? false;
    final isNonZero = currentValue != 0.0;
    final linkColor = !isExpanded && !isNonZero
        ? OmniTheme.textSecondary.withOpacity(0.7)
        : theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _weightAdjustExpanded[key] = !isExpanded;
          }),
          style: ButtonStyle(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            ),
            minimumSize: WidgetStateProperty.all(Size.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonUtilityRadius,
                ),
              ),
            ),
          ),
          child: Text(
            'Weight adjustment',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: linkColor),
          ),
        ),
        if (isExpanded)
          InlineMetricEditor(
            metricType: 'extra-weight',
            currentValue: currentValue,
            unitLabel: _preferredWeightUnitLabel,
            showUnitInline: true,
            onValueChanged: (value) =>
                onValueChanged((value as num).toDouble()),
          ),
      ],
    );
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
        final weight = entryData['weight'] as double? ?? 0.0;
        final exerciseId = exercise['exerciseId'] as String?;
        final exerciseObj = widget.workoutState.getExercise(exerciseId);
        final hasLoad = exerciseObj?.capabilities.contains('load') ?? false;
        final extraWeight =
            (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0;

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
              unitLabel: _preferredWeightUnitLabel,
              onValueChanged: (value) =>
                  _updateMetricValue(effortId, entryIndex, 'weight', value),
            ),
            if (!hasLoad)
              _buildWeightAdjustmentSection(
                theme: theme,
                effortId: effortId,
                entryIndex: entryIndex,
                currentValue: extraWeight,
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'extra-weight',
                  value,
                ),
              ),
          ],
        );

      case 'timed':
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
          timedDisplayValue = timedElapsed;
          timedUnitLabel = 'ELAPSED';
          timedUnitLabelColor = timedIsRunning
              ? theme.colorScheme.primary.withOpacity(0.8)
              : null;
        }

        if (widget.editMode) {
          final editDuration =
              timedInstance?.actualDurationSecs ??
              (entryData['elapsedSecs'] as int? ?? timedElapsed);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 24 + _kSessionScrollBottomExtra),
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
              if (entryData['extra-weight'] != null)
                _buildWeightAdjustmentSection(
                  theme: theme,
                  effortId: effortId,
                  entryIndex: entryIndex,
                  currentValue:
                      (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0,
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
            SizedBox(height: 24 + _kSessionScrollBottomExtra),
            GestureDetector(
              key: const Key('timer-gesture-detector'),
              onTap: isTimedFinished ? null : () => _toggleEffortTimer(effortId),
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  InlineMetricEditor(
                    metricType: 'duration',
                    currentValue: timedDisplayValue,
                    unitLabel: timedUnitLabel,
                    unitLabelColor: timedUnitLabelColor,
                    isReadOnly: true,
                    onValueChanged: (_) {},
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isTimedFinished) ...[
                        Icon(
                          timedIsRunning
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          size: 18,
                          color: timedIsRunning
                              ? theme.colorScheme.primary.withOpacity(0.6)
                              : theme.colorScheme.onSurface.withAlpha(
                                  (0.35 * 255).round(),
                                ),
                        ),
                        const SizedBox(width: 6),
                      ],
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
              ),
            ),
            if (entryData['extra-weight'] != null)
              _buildWeightAdjustmentSection(
                theme: theme,
                effortId: effortId,
                entryIndex: entryIndex,
                currentValue:
                    (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0,
                onValueChanged: (value) => _updateMetricValue(
                  effortId,
                  entryIndex,
                  'extra-weight',
                  value,
                ),
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

        final String stoppedUnitLabel = isFinished
            ? 'COMPLETED'
            : (isMidRound ? 'REMAINING' : 'DURATION');

        if (widget.editMode) {
          final editRoundDuration =
              (round != null && round.actualDurationSecs > 0)
              ? round.actualDurationSecs
              : roundDuration;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 24 + _kSessionScrollBottomExtra),
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
            SizedBox(height: 24 + _kSessionScrollBottomExtra),
            Text(
              'ROUND $rounds',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: -2,
                fontSize: theme.textTheme.displayMedium?.fontSize,
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: isFinished ? null : () => _toggleEffortTimer(effortId),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  const SizedBox(height: 8),
                  if (!isFinished)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          (_effortRunning[timerKey] ?? false)
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          size: 18,
                          color: (_effortRunning[timerKey] ?? false)
                              ? theme.colorScheme.primary.withOpacity(0.6)
                              : theme.colorScheme.onSurface.withAlpha(
                                  (0.35 * 255).round(),
                                ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );

      case 'drill':
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
          drillDisplayValue = drillElapsed;
          drillUnitLabel = 'ELAPSED';
          drillUnitLabelColor = drillIsRunning
              ? theme.colorScheme.primary.withOpacity(0.8)
              : null;
        }

        if (widget.editMode) {
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
              _buildWeightAdjustmentSection(
                theme: theme,
                effortId: effortId,
                entryIndex: entryIndex,
                currentValue: drillExtraWeight,
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
            GestureDetector(
              onTap: isDrillFinished ? null : () => _toggleEffortTimer(effortId),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InlineMetricEditor(
                    metricType: 'duration',
                    currentValue: drillDisplayValue,
                    unitLabel: drillUnitLabel,
                    unitLabelColor: drillUnitLabelColor,
                    isReadOnly: true,
                    onValueChanged: (_) {},
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isDrillFinished) ...[
                        Icon(
                          drillIsRunning
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          size: 18,
                          color: drillIsRunning
                              ? theme.colorScheme.primary.withOpacity(0.6)
                              : theme.colorScheme.onSurface.withAlpha(
                                  (0.35 * 255).round(),
                                ),
                        ),
                        const SizedBox(width: 6),
                      ],
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
              ),
            ),
            _buildWeightAdjustmentSection(
              theme: theme,
              effortId: effortId,
              entryIndex: entryIndex,
              currentValue: drillExtraWeight,
              onValueChanged: (value) => _updateMetricValue(
                effortId,
                entryIndex,
                'extra-weight',
                value,
              ),
            ),
          ],
        );

      default:
        return Text('—', style: theme.textTheme.displayLarge);
    }
  }

  // ── Set progress / previous stats / indicator / controls / buttons ────────

  Widget _buildSetProgress(
    int totalEntries,
    String effortKind,
    ThemeData theme,
  ) {
    String label;
    switch (effortKind) {
      case 'set':
        label = 'Set $_currentSet of $totalEntries';
      case 'timed':
        label = 'Interval $_currentSet of $totalEntries';
      case 'round':
        final modality = widget.workoutState.currentSession?.modality;
        final isWorkoutLabel = modality == 'sports' ? 'Period' : 'Round';
        label = '$isWorkoutLabel $_currentSet of $totalEntries';
      case 'drill':
        label = 'Hold $_currentSet of $totalEntries';
      default:
        label = 'Set $_currentSet of $totalEntries';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Minus — remove-set (secondary, lower prominence)
        Tooltip(
          message: 'Remove set',
          child: InkWell(
            onTap: _deleteCurrentSet,
            customBorder: const CircleBorder(),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              child: Icon(
                Icons.remove,
                size: 20,
                color: theme.colorScheme.onSurface
                    .withAlpha((0.35 * 255).round()),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            letterSpacing: 2,
            color: theme.colorScheme.onSurface.withAlpha((0.6 * 255).round()),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        // Plus — add-set (primary, higher prominence)
        Tooltip(
          message: 'Add set',
          child: InkWell(
            onTap: _addSet,
            customBorder: const CircleBorder(),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              child: Icon(
                Icons.add,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviousSetStats(
    Map<String, dynamic> exercise,
    String effortKind,
    ThemeData theme,
  ) {
    if (_currentSet <= 1) return const SizedBox.shrink();

    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    if (_currentSet - 2 >= entries.length) return const SizedBox.shrink();

    final previousEntryIndex = _currentSet - 2;
    final previousEntry = entries[previousEntryIndex];
    final isPreviousLogged = _isSetLogged(
      exercise['id'] as String,
      previousEntryIndex,
      effortKind,
    );
    String statsText = '';

    switch (effortKind) {
      case 'set':
        final prevReps = previousEntry['reps'] as int? ?? 0;
        final prevWeight = previousEntry['weight'] as double? ?? 0.0;
        if (!isPreviousLogged) {
          statsText = 'Previous: —';
          break;
        }
        statsText =
            'Previous: $prevReps reps @ ${UnitFormatter.formatWeightValue(prevWeight, widget.settingsState)} ${UnitFormatter.weightLabel(widget.settingsState)}';
      case 'timed':
        final prevTimedSecs =
            previousEntry['elapsedSecs'] as int? ??
            previousEntry['duration'] as int? ??
            0;
        final prevDistance = previousEntry['distance'] as double? ?? 0.0;
        if (!isPreviousLogged) {
          statsText = 'Previous: —';
          break;
        }
        final prevTimedMins = prevTimedSecs ~/ 60;
        final prevTimedRemSecs = prevTimedSecs % 60;
        statsText =
            'Previous: ${prevTimedMins.toString().padLeft(2, '0')}:${prevTimedRemSecs.toString().padLeft(2, '0')} @ ${UnitFormatter.formatDistanceValue(prevDistance, widget.settingsState)} ${UnitFormatter.distanceLabel(widget.settingsState)}';
        final prevTimedExtraWeight =
            previousEntry['extra-weight'] as double?;
        if (prevTimedExtraWeight != null && prevTimedExtraWeight != 0.0) {
          statsText +=
              ' + ${UnitFormatter.formatWeightValue(prevTimedExtraWeight, widget.settingsState)} ${UnitFormatter.weightLabel(widget.settingsState)}';
        }
      case 'round':
        final prevRounds = previousEntry['rounds'] as int? ?? 1;
        final prevRoundDur =
            previousEntry['round-duration'] as int? ??
            WorkoutConstants.defaultRoundDurationSecs;
        if (!isPreviousLogged) {
          statsText = 'Previous: —';
          break;
        }
        final mins = prevRoundDur ~/ 60;
        final secs = prevRoundDur % 60;
        statsText =
            'Previous: $prevRounds rounds @ ${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
      case 'drill':
        final prevDrillSecs =
            previousEntry['elapsedSecs'] as int? ??
            previousEntry['duration'] as int? ??
            0;
        final prevExtraWeight = previousEntry['extra-weight'] as double? ?? 0.0;
        if (!isPreviousLogged) {
          statsText = 'Previous: —';
          break;
        }
        final prevDrillMins = prevDrillSecs ~/ 60;
        final prevDrillRemSecs = prevDrillSecs % 60;
        final ewSign = prevExtraWeight > 0 ? '+' : '';
        statsText =
            'Previous: ${prevDrillMins.toString().padLeft(2, '0')}:${prevDrillRemSecs.toString().padLeft(2, '0')} hold @ $ewSign${UnitFormatter.formatWeightValue(prevExtraWeight.abs(), widget.settingsState)} ${UnitFormatter.weightLabel(widget.settingsState)}';
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

  Widget _buildSetIndicator(
    int totalSets,
    String effortKind,
    ThemeData theme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                      ? theme.colorScheme.primary.withAlpha(
                          (0.5 * 255).round(),
                        )
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
    final entries = exercise['entries'] as List<Map<String, dynamic>>;

    // Determine whether current set has already been logged.
    final isLogged = _isSetLogged(effortId, _currentSet - 1, effortKind);

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

    // Center content: Log Set button OR nav arrow if already logged
    Widget center;
    if (widget.editMode) {
      // In edit mode, center is a plain nav arrow (no logging)
      center = _buildNavArrow(
        icon: Icons.arrow_forward,
        label: 'Next',
        isEnabled: true,
        onPressed: _nextSetInEditMode,
        theme: theme,
      );
    } else if (isLogged) {
      // Already logged — show forward nav arrow in center
      center = _buildNavArrow(
        icon: Icons.arrow_forward,
        label: 'Next Set',
        isEnabled: true,
        onPressed: _nextSet,
        theme: theme,
      );
    } else {
      // Not yet logged — show Log Set FilledButton
      center = _buildLogSetButton(effortKind, theme);
    }

    if (widget.editMode) {
      // Edit mode: back | center (nav arrow) | forward
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          backArrow,
          center,
          forwardArrow,
        ],
      );
    }

    // Live mode: back | Log Set (expanded) OR nav arrow (compact) | forward
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        backArrow,
        if (!isLogged)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: center,
            ),
          )
        else
          center,
        forwardArrow,
      ],
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
      _switchExercise(1);
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
            const Size(double.infinity, 48),
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
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                size: 24,
                color: isEnabled
                    ? theme.colorScheme.onSurface.withAlpha((0.5 * 255).round())
                    : theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
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
