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
                  size: 30,
                  color: theme.colorScheme.onSurface.withOpacity(0.45),
                ),
                onPressed: exercise == null
                    ? null
                    : () => _showExerciseInfoSheet(context, exercise),
                padding: EdgeInsets.fromLTRB(0, 0, 5, 0),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
                      size: 30,
                      color: theme.colorScheme.onSurface.withOpacity(0.45),
                    ),
                    onPressed: exercise == null
                        ? null
                        : () => _showExerciseNoteSheet(context, exercise),
                    padding: EdgeInsets.fromLTRB(5, 0, 0, 0),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
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
    final isExpanded = _weightAdjustExpanded[key] ?? (currentValue > 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 50),
        OutlinedButton.icon(
          onPressed: () => _updateUi(() {
            _weightAdjustExpanded[key] = !isExpanded;
          }),
          icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
          label: const Text('Weight adjustment'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface.withAlpha(
              (0.6 * 255).round(),
            ),
            side: BorderSide(
              color: theme.colorScheme.onSurface.withAlpha((0.2 * 255).round()),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonUtilityRadius,
              ),
            ),
          ),
        ),
        if (isExpanded)
          InlineMetricEditor(
            metricType: 'extra-weight',
            currentValue: currentValue,
            unitLabel: _preferredWeightUnitLabel,
            showUnitInline: true,
            emphasisTier: MetricEmphasisTier.secondary,
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
        // Stored in canonical kg; convert to the user's preferred display unit.
        final weight = UnitFormatter.convertWeight(
          entryData['weight'] as double? ?? 0.0,
          widget.settingsState,
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            InlineMetricEditor(
              metricType: 'reps',
              currentValue: reps,
              unitLabel: 'REPS',
              emphasisTier: MetricEmphasisTier.dominant,
              onValueChanged: (value) =>
                  _updateMetricValue(effortId, entryIndex, 'reps', value),
            ),
            InlineMetricEditor(
              metricType: 'weight',
              currentValue: weight,
              unitLabel: _preferredWeightUnitLabel,
              emphasisTier: MetricEmphasisTier.secondary,
              onValueChanged: (value) =>
                  _updateMetricValue(effortId, entryIndex, 'weight', value),
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
          timedUnitLabelColor = null;
        }

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
              if (entryData['extra-weight'] != null)
                _buildWeightAdjustmentSection(
                  theme: theme,
                  effortId: effortId,
                  entryIndex: entryIndex,
                  currentValue: UnitFormatter.convertWeight(
                    (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0,
                    widget.settingsState,
                  ),
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
            Column(
              children: [
                InlineMetricEditor(
                  metricType: 'duration',
                  currentValue: timedDisplayValue,
                  unitLabel: timedUnitLabel,
                  unitLabelColor: timedUnitLabelColor,
                  emphasisTier: MetricEmphasisTier.dominant,
                  isReadOnly: true,
                  onTap: null,
                  onValueChanged: (_) {},
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isTimedFinished) ...[
                      Icon(
                        timedIsRunning
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 30,
                        color: OmniTheme.colors.textMuted,
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const SizedBox(
                        height: 30,
                      ), // keep space even when finished
                    Text(
                      isTimedFinished
                          ? ''
                          : (timedIsRunning
                                ? 'RUNNING'
                                : (isTimedStarted ? 'PAUSED' : 'STOPPED')),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: OmniTheme.colors.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (entryData['extra-weight'] != null)
              _buildWeightAdjustmentSection(
                theme: theme,
                effortId: effortId,
                entryIndex: entryIndex,
                currentValue: UnitFormatter.convertWeight(
                  (entryData['extra-weight'] as num?)?.toDouble() ?? 0.0,
                  widget.settingsState,
                ),
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
        final modality = widget.workoutState.currentSession?.modality;
        final roundLabel = modality == 'sports' ? 'PERIOD' : 'ROUND';
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
              Text(
                '$roundLabel $rounds',
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: -2,
                  fontSize: theme.textTheme.displayMedium?.fontSize,
                  color: OmniTheme.colors.textDominant,
                ),
              ),
              const SizedBox(height: 15),
              InlineMetricEditor(
                metricType: 'duration',
                currentValue: editRoundDuration,
                unitLabel: 'DURATION',
                emphasisTier: MetricEmphasisTier.dominant,
                onTap: () async {
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
              '$roundLabel $rounds',
              style: theme.textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.w300,
                letterSpacing: -2,
                fontSize: theme.textTheme.displayMedium?.fontSize,
                color: OmniTheme.colors.textDominant,
              ),
            ),
            const SizedBox(height: 15),
            Column(
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
                  emphasisTier: MetricEmphasisTier.dominant,
                  unitLabelColor: isExpired ? theme.colorScheme.error : null,
                  isReadOnly: isFinished,
                  onTap: isFinished
                      ? null
                      : () async {
                          final result = await showDurationEntryDialog(
                            context,
                            title: 'Edit Round Duration',
                            initialSecs: stoppedDisplayValue,
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
                  onValueChanged: (_) {},
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isFinished) ...[
                      Icon(
                        (_effortRunning[timerKey] ?? false)
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 30,
                        color: OmniTheme.colors.textMuted,
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const SizedBox(height: 30),
                    Text(
                      isFinished
                          ? ''
                          : ((_effortRunning[timerKey] ?? false)
                                ? 'RUNNING'
                                : (isMidRound ? 'PAUSED' : 'STOPPED')),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: OmniTheme.colors.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
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
        // Stored in canonical kg; convert to the user's preferred display unit.
        final drillExtraWeight = UnitFormatter.convertWeight(
          entryData['extra-weight'] as double? ?? 0.0,
          widget.settingsState,
        );

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
          drillUnitLabelColor = null;
        }

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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InlineMetricEditor(
                  metricType: 'duration',
                  currentValue: drillDisplayValue,
                  unitLabel: drillUnitLabel,
                  unitLabelColor: drillUnitLabelColor,
                  emphasisTier: MetricEmphasisTier.dominant,
                  isReadOnly: true,
                  onTap: null,
                  onValueChanged: (_) {},
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isDrillFinished) ...[
                      Icon(
                        drillIsRunning
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        size: 30,
                        color: OmniTheme.colors.textMuted,
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const SizedBox(
                        height: 30,
                      ), // keep space even when finished
                    Text(
                      isDrillFinished
                          ? ''
                          : (drillIsRunning
                                ? 'RUNNING'
                                : (isDrillStarted ? 'PAUSED' : 'STOPPED')),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: OmniTheme.colors.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
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
    final canAddEntry = totalEntries < WorkoutConstants.maxEntriesPerEffort;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactSpacing = constraints.maxWidth < 320 ? 2.0 : 4.0;
        final compactLetterSpacing = constraints.maxWidth < 320 ? 1.0 : 2.0;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Minus / trash — remove-set or remove-exercise (secondary, lower prominence)
            Tooltip(
              message: totalEntries == 1 ? 'Remove exercise' : 'Remove set',
              child: InkWell(
                onTap: _deleteCurrentSet,
                customBorder: const CircleBorder(),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 50,
                    minHeight: 50,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    totalEntries == 1 ? Icons.delete_outline : Icons.remove,
                    size: 24,
                    color: theme.colorScheme.onSurface.withAlpha(
                      (0.35 * 255).round(),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: compactSpacing),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  letterSpacing: compactLetterSpacing,
                  color: OmniTheme.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(width: compactSpacing),
            // Plus — add-set (primary, higher prominence)
            Tooltip(
              message: canAddEntry
                  ? 'Add set'
                  : 'Max ${WorkoutConstants.maxEntriesPerEffort} entries',
              child: InkWell(
                onTap: canAddEntry ? _addSet : null,
                customBorder: const CircleBorder(),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 50,
                    minHeight: 50,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: 24,
                    color: canAddEntry
                        ? theme.colorScheme.onSurface.withAlpha(
                            (0.35 * 255).round(),
                          )
                        : theme.colorScheme.onSurface.withAlpha(
                            (0.2 * 255).round(),
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSetIndicator(int totalSets, String effortKind, ThemeData theme) {
    final effortId = _exercises[_currentExerciseIndex]['id'] as String;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(totalSets, (index) {
            final isCurrent = index == _currentSet - 1;
            final isLogged = _isSetLogged(effortId, index, effortKind);
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
                  color: effortKind == 'round'
                      ? (isCurrent
                            ? theme.colorScheme.primary
                            : (isLogged
                                  ? OmniTheme.colors.textMuted
                                  : theme.colorScheme.onSurface.withAlpha(
                                      (0.2 * 255).round(),
                                    )))
                      : ((isLogged || isSkipped)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withAlpha(
                                (0.2 * 255).round(),
                              )),
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
    // 3) Otherwise show log button.
    Widget centerControl;
    if (isLogged) {
      centerControl = _buildLoggedLabel(theme);
    } else if (_isTimerEntryNotStarted(effortKind, effortId, entryIndex)) {
      centerControl = _buildStartTimerButton(effortId, theme);
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

  Widget _buildStartTimerButton(String effortId, ThemeData theme) {
    return Tooltip(
      message: 'Start',
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
        child: const Text('Start'),
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
