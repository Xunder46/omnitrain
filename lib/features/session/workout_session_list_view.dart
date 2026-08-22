part of 'workout_session_screen.dart';

/// List-view builders for [WorkoutSessionScreen].
///
/// Extension on [_WorkoutSessionScreenState] — because this file is a `part of`
/// the same library, all private fields and methods of the state class are
/// directly accessible without any forwarding or getters.
extension _SessionListViewBuilders on _WorkoutSessionScreenState {
  // ── Session time widget ───────────────────────────────────────────────────

  Widget _buildSessionTimeWidget(ThemeData theme) {
    final chip = Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                  color: OmniTheme.colors.textSecondary,
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
              Icon(
                Icons.timer,
                size: 16,
                color: OmniTheme.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                _elapsedFormatted,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: widget.editMode
                      ? theme.colorScheme.primary
                      : OmniTheme.colors.textDominant,
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

  // ── List view dispatcher ──────────────────────────────────────────────────

  Widget _buildListView(ThemeData theme) {
    if (widget.workoutState.isRollingSession) {
      return _buildRollingSessionListView(theme);
    }
    return _buildStandardSessionListView(theme);
  }

  // ── Exercise subtitle (used by _buildExerciseTile) ────────────────────────

  String _buildExerciseSubtitle(Map<String, dynamic> exercise) {
    final entries = exercise['entries'] as List<dynamic>? ?? [];
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final effortId = exercise['id'] as String;

    switch (effortKind) {
      case 'set':
        return '${entries.length} set${entries.length != 1 ? 's' : ''}';
      case 'timed':
        int totalDuration = 0;
        for (int i = 0; i < entries.length; i++) {
          final instance = _getTimedInstance(effortId, i);
          if (instance != null) {
            if (instance.state == TimedState.finished) {
              totalDuration += instance.actualDurationSecs;
            } else {
              totalDuration += (instance.elapsedMs / 1000).round();
            }
          } else {
            final e = entries[i] as dynamic;
            final elapsed = e['elapsedSecs'] as int? ?? 0;
            final target = e['duration'] as int? ?? 0;
            totalDuration += (elapsed > 0 ? elapsed : target);
          }
        }
        final minutes = totalDuration ~/ 60;
        final seconds = totalDuration % 60;
        return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} total';
      case 'round':
        final totalRounds = widget.workoutState
            .getRoundsForEffort(effortId)
            .length;
        return '$totalRounds round${totalRounds != 1 ? 's' : ''}';
      case 'drill':
        return '${entries.length} hold${entries.length != 1 ? 's' : ''}';
      default:
        return '${entries.length} ${entries.length != 1 ? 'entries' : 'entry'}';
    }
  }

  // ── Exercise tile ─────────────────────────────────────────────────────────

  Widget _buildExerciseTile(Map<String, dynamic> exercise, ThemeData theme) {
    final subtitle = _buildExerciseSubtitle(exercise);
    final effortId = exercise['id'] as String;
    final idx = _exercises.indexWhere((e) => e['id'] == effortId);

    final tileColors = OmniTheme.colorsForTheme(widget.settingsState.appTheme);
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
            color: OmniTheme.colors.textDominant,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: OmniTheme.colors.textSecondary,
          ),
        ),
        onTap: idx == -1
            ? null
            : () => unawaited(
                _focusExerciseDetail(
                  idx,
                  setNumber: _initialSetForExerciseIndex(idx),
                ),
              ),
      ),
    );
  }

  // ── Block card ────────────────────────────────────────────────────────────

  Widget _buildSessionBlockCard(SessionBlock block, ThemeData theme) {
    final blockExercises = _sortExercisesForBlock(
      _exercises.where((e) => e['blockId'] == block.id).toList(),
    );
    final tileColors = OmniTheme.colorsForTheme(widget.settingsState.appTheme);
    final segmentId = widget.workoutState.segments.isNotEmpty
        ? widget.workoutState.segments.first.id
        : null;

    return Card(
      color: tileColors.surface.withOpacity(0.7),
      elevation: 2,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    block.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: OmniTheme.colors.textDominant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add exercise to block',
                  onPressed: () =>
                      _addExercise(segmentId: segmentId, blockId: block.id),
                ),
                PopupMenuButton<String>(
                  color: theme.colorScheme.surface,
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        await _showBlockRenameDialog(block);
                      case 'clone':
                        await widget.workoutState.cloneSessionBlock(block.id);
                        await _loadExercises();
                      case 'delete':
                        await _confirmAndDeleteBlock(block);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'clone',
                      child: Row(
                        children: [
                          Icon(
                            Icons.copy,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text('Clone'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete, size: 18, color: Colors.red),
                          const SizedBox(width: 8),
                          const Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (blockExercises.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No exercises in this block yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.colors.textSecondary,
                  ),
                ),
              )
            else
              for (final ex in blockExercises) ...[
                _buildExerciseTile(ex, theme),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  // ── Add exercise + block bar ──────────────────────────────────────────────

  /// PR 6 — Add Exercise and Add Block are ALWAYS secondary
  /// (OutlinedButton) CTAs, regardless of whether the session is empty
  /// or already has content. Neither choice should ever look like the
  /// "primary" action: the bottom Finish Workout CTA is the only
  /// FilledButton in the session screen. Visual consistency across
  /// empty-state and populated sessions keeps the user's attention on
  /// the logged work, not on chrome that competes with it.
  ///
  /// The picker only opens when the user explicitly taps Add Exercise.
  /// Add Block calls `workoutState.addSessionBlock()` directly.
  Widget _buildAddExerciseAndBlockBar(
    ThemeData theme, {
    String? segmentId,
  }) {
    final addExercise = SizedBox(
      width: double.infinity,
      height: OmniTheme.buttonPrimaryHeight,
      child: OutlinedButton(
        key: const Key('add-exercise'),
        onPressed: () => _addExercise(segmentId: segmentId),
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonBorderRadius,
              ),
            ),
          ),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Add Exercise'),
        ),
      ),
    );

    final addBlock = SizedBox(
      width: double.infinity,
      height: OmniTheme.buttonPrimaryHeight,
      child: OutlinedButton(
        key: const Key('add-block'),
        onPressed: () async {
          await widget.workoutState.addSessionBlock();
          _updateUi(() {});
        },
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonBorderRadius,
              ),
            ),
          ),
        ),
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Add Block'),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          addExercise,
          const SizedBox(height: 12),
          addBlock,
        ],
      ),
    );
  }

  // ── Rolling session list view ─────────────────────────────────────────────

  Widget _buildRollingSessionListView(ThemeData theme) {
    final blocks = widget.workoutState.getSessionBlocks();
    final segmentId = widget.workoutState.segments.isNotEmpty
        ? widget.workoutState.segments.first.id
        : null;

    final showRestStrip = _shouldShowRestOverlay();
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(theme),
                const SizedBox(height: 16),
                Expanded(
                  child: blocks.isEmpty
                      ? Center(
                          child: AnimatedPadding(
                            duration: _kRestStripAnimationDuration,
                            curve: Curves.easeOut,
                            padding: EdgeInsets.only(
                              bottom: _kBottomControlsClearance +
                                  (showRestStrip
                                      ? OmniTheme.restStripHeight
                                      : 0),
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: _buildAddExerciseAndBlockBar(
                                theme,
                                segmentId: segmentId,
                              ),
                            ),
                          ),
                        )
                      : ListView(
                          controller: _listScrollController,
                          padding: EdgeInsets.fromLTRB(
                            0,
                            0,
                            0,
                            _kBottomControlsClearance +
                                (showRestStrip
                                    ? OmniTheme.restStripHeight
                                    : 0),
                          ),
                          children: [
                            for (int i = 0; i < blocks.length; i++)
                              _buildSessionBlockCard(blocks[i], theme),
                            const SizedBox(height: 24),
                            _buildAddExerciseAndBlockBar(
                              theme,
                              segmentId: segmentId,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RestTimerStrip(
                  visible: showRestStrip,
                  child: _buildRestOverlayChip(
                    theme,
                    _formatGlobalRestElapsed(),
                  ),
                ),
                OmniBottomCTA(
                  label: widget.editMode ? 'Save Changes' : 'Finish Workout',
                  onPressed: widget.editMode
                      ? _saveEditChanges
                      : _showFinishSessionDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Standard (non-rolling) session list view ──────────────────────────────

  Widget _buildStandardSessionListView(ThemeData theme) {
    final blocks = widget.workoutState.getSessionBlocks();
    final segmentId = widget.workoutState.segments.isNotEmpty
        ? widget.workoutState.segments.first.id
        : null;

    if (_exercises.isEmpty && blocks.isEmpty) {
      // PR 6 / S-003 + S-004 — new workouts (modality or Free Training
      // start) land on the balanced empty state; routine-populated
      // sessions bypass it entirely (no neutral prompt mid-context).
      final isRoutineSession =
          widget.workoutState.currentSession?.routineTemplateId != null;
      if (isRoutineSession) {
        // Fall through to the populated list view — a routine session
        // should never show the neutral empty state, even if its manifest
        // happens to resolve to zero visible exercises. The bottom CTA
        // and rest overlay still mount in the populated path below.
      } else {
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: Stack(
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
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: _kBottomControlsClearance,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: _buildAddExerciseAndBlockBar(
                              theme,
                              segmentId: segmentId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: OmniBottomCTA(
                  label:
                      widget.editMode ? 'Save Changes' : 'Finish Workout',
                  onPressed: widget.editMode
                      ? _saveEditChanges
                      : _showFinishSessionDialog,
                ),
              ),
            ],
          ),
        );
      }
    }

    final items = _buildNonRollingTopLevelItems(_exercises);
    final showRestStrip = _shouldShowRestOverlay();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
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
                    controller: _listScrollController,
                    padding: EdgeInsets.fromLTRB(
                      0,
                      8,
                      0,
                      _kBottomControlsClearance +
                          (showRestStrip
                              ? OmniTheme.restStripHeight
                              : 0),
                    ),
                    children: [
                      for (final item in items)
                        if (item.block != null)
                          _buildSessionBlockCard(item.block!, theme)
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                            child: _buildExerciseTile(item.exercise!, theme),
                          ),
                      const SizedBox(height: 24),
                      _buildAddExerciseAndBlockBar(theme, segmentId: segmentId),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RestTimerStrip(
                  visible: showRestStrip,
                  child: _buildRestOverlayChip(
                    theme,
                    _formatGlobalRestElapsed(),
                  ),
                ),
                OmniBottomCTA(
                  label: widget.editMode ? 'Save Changes' : 'Finish Workout',
                  onPressed: widget.editMode
                      ? _saveEditChanges
                      : _showFinishSessionDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Rest overlay chip ─────────────────────────────────────────────────────

  /// Returns the most-recent open rest's `(effortId, entryIndex)` key
  /// for the live chip. Centralised here so the chip's tap handler
  /// and the underlying state plumbing stay in sync.
  ({String effortId, int entryIndex})? _openRestKeyForChip() =>
      _getMostRecentOpenRestKey();

  /// Toggles the live rest between running and stopped. Tap-stops
  /// within one second (the chip's underlying state-machine method
  /// completes in O(1) and the next _ticker tick, at most 1s later,
  /// repaints the chip with the new state). Tap-resumes without
  /// resetting the counted time — the elapsed formula subtracts
  /// the accumulated `restPausedDurationMs` so the resumption
  /// continues from where the rest was paused.
  Future<void> _toggleRestChip() async {
    final key = _openRestKeyForChip();
    if (key == null) return;
    final isPaused = widget.workoutState.isRestPaused(
      key.effortId,
      key.entryIndex,
    );
    if (isPaused) {
      await widget.workoutState.resumeRest(key.effortId, key.entryIndex);
    } else {
      await widget.workoutState.pauseRest(key.effortId, key.entryIndex);
    }
  }

  /// Tappable rest timer overlay.
  ///
  /// Three visually distinct states (spec: "Three rest states are
  /// visually distinct without reading the number"):
  ///   - **not started** — no chip shown (handled by
  ///     [_shouldShowRestOverlay], not the chip builder).
  ///   - **running** — primary-tinted background, meditation icon,
  ///     primary foreground.
  ///   - **stopped** — muted-tinted background, *pause* icon (or a
  ///     play-arrow icon when transitionable) so the user can read
  ///     the state at a glance.
  ///
  /// Tap behaviour: whole-tile Material + InkWell, no visual chrome
  /// outside the chip's own padding. Tap toggles the persisted
  /// pause/resume state on the underlying [EntryRest] record.
  Widget _buildRestOverlayChip(ThemeData theme, String elapsedText) {
    final key = _openRestKeyForChip();
    final isPaused = key == null
        ? false
        : widget.workoutState.isRestPaused(key.effortId, key.entryIndex);
    final tileColors = OmniTheme.colorsForTheme(widget.settingsState.appTheme);

    // Running state: prominent primary tint, meditation icon.
    // Stopped state: muted surface tint, a different (pause) icon.
    final baseColor = isPaused
        ? tileColors.surface.withOpacity(0.85)
        : theme.colorScheme.primary.withOpacity(0.8);
    final foregroundColor = isPaused
        ? tileColors.textDominant
        : theme.colorScheme.onPrimary;
    final iconData = isPaused ? Icons.pause : Icons.self_improvement;
    // No box shadow and no border in either state — both would
    // add spread/stroke padding to the bounding rect and make the
    // two states different sizes. Visual distinction between
    // running and paused is carried solely by background tint and
    // icon swap, which is sufficient (and per spec, the chip must
    // stay the same size across states).
    final boxShadow = null;
    final border = null;

    return Material(
      key: const Key('rest-overlay-chip'),
      color: Colors.transparent,
      // No MaterialTappability constraints — the whole chip is tappable
      // (PR 4 spec: "whole-tile tap"), but stays inside the natural
      // chip area thanks to the InkWell boundary below.
      child: InkWell(
        onTap: _toggleRestChip,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(12),
            border: border,
            boxShadow: boxShadow,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12, // taller than before so the chip hits the
              // 48-dp touch-target floor (vertical: 24 + 24 = 48)
            ),
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconData, size: 24, color: foregroundColor),
                const SizedBox(width: 12),
                Text(
                  elapsedText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Screen content and header builders ───────────────────────────────────

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(
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
                      color: OmniTheme.colors.textSecondary,
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
      );
    }

    if (_showListView) {
      return _buildListView(theme);
    }

    if (_exercises.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'No exercises yet',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: OmniTheme.colors.textDominant,
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
      );
    }

    final exercise = _exercises[_currentExerciseIndex];
    final entries = exercise['entries'] as List<Map<String, dynamic>>;
    final effortKind = exercise['effortKind'] as String? ?? 'set';
    final currentEntry = entries.isNotEmpty && _currentSet <= entries.length
        ? entries[_currentSet - 1]
        : (effortKind == 'set' ? {'reps': 0, 'weight': 0.0} : {'duration': 0});

    final showRestStrip = _shouldShowRestOverlay();
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      // PR 2 (Launch Quality Hotfix): removed the screen-level
      // GestureDetector that previously interpreted horizontal and
      // vertical drags as set / exercise navigation. Those gestures
      // fought the number-scroller (InlineMetricEditor) drag-to-edit
      // affordance and were a frequent source of accidental jumps
      // mid-set. Navigation is now exclusively via the explicit
      // Previous / Next arrows, the set dots, and the per-set
      // controls at the bottom of the detail view. See
      // `.github/agents/plans/2026-07-27-02-pr2-launch-quality-hotfix-plan.md`
      // scenario S-003.
      body: Stack(
        children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),

                  const SizedBox(height: 0),

                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: AnimatedPadding(
                            duration: _kRestStripAnimationDuration,
                            curve: Curves.easeOut,
                            padding: EdgeInsets.only(
                              bottom: showRestStrip
                                  ? OmniTheme.restStripHeight
                                  : 0,
                            ),
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildMetricWidget(
                                      exercise,
                                      currentEntry,
                                      effortKind,
                                      theme,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildSetProgress(
                                      entries.length,
                                      effortKind,
                                      theme,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildSetIndicator(
                                      entries.length,
                                      effortKind,
                                      theme,
                                    ),
                                    SizedBox(
                                      height:
                                          24 + _kSessionScrollBottomExtra,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Docked rest-timer strip directly above the
                        // set controls. Visibility is governed by the
                        // shared _shouldShowRestOverlay() helper
                        // (covers edit-mode, running effort, and
                        // cross-effort rest scenarios in one rule).
                        // The strip's height animates in sync with
                        // the scrollable's bottom padding so the
                        // content can scroll clear of it and the
                        // strip collapses to zero when no rest is
                        // open.
                        RestTimerStrip(
                          visible: showRestStrip,
                          child: _buildRestOverlayChip(
                            theme,
                            _formatGlobalRestElapsed(),
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                          child: _buildSetControls(theme),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  // ── Discard Session ────────────────────────────────────────────────────

  /// Confirmation dialog: states permanence.
  Future<void> _showDiscardDialog() async {
    if (!mounted) return;
    final confirmed = await ConfirmationDialog.showTwoChoice(
      context: context,
      title: 'Discard session?',
      body: const Text(
        'This will permanently delete this session and all its data. '
        'You will return to Home.',
      ),
      dismissLabel: 'Cancel',
      confirmLabel: 'Discard',
      dismissKey: const Key('session-list-discard-cancel'),
      confirmKey: const Key('session-list-discard-confirm'),
      isDestructive: true,
    );
    if (confirmed) {
      await _discardCurrentSession();
    }
  }

  /// Performs the discard + navigates home. Idempotent: if the user
  /// cancels mid-flow we don't pop anything; if the discard succeeds we
  /// unwind to the bottom of the navigation stack (the hub / home).
  Future<void> _discardCurrentSession() async {
    await widget.workoutState.discardCurrentSession();
    if (!mounted) return;
    // The session was pushed on top of the home stack; pop until first
    // so the user lands on Home. Safe when there's only the session
    // route — `popUntil((route) => route.isFirst)` pops exactly the
    // session and stops.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Compact hollow red "Discard" button for the header (PR 4 spec:
  /// secondary destructive, away from logging controls, error-tinted,
  /// utility radius). Replaces the trash-can icon button that PR 4
  /// originally introduced. Only the session-details (list) header
  /// renders it; the exercise-details (detail) header is unaffected
  /// so its action row stays focused on notes / info.
  ///
  /// Sized via `VisualDensity.compact` + utility radius — the same
  /// compact header-button style used by the calendar `+` button
  /// and the period-list add button — so it matches the notes /
  /// info [IconButton]s in the exercise-details header at exactly
  /// [OmniTheme.headerSecondaryActionSize] (40 dp). Do **not**
  /// set `tapTargetSize: shrinkWrap`; that would drop the button
  /// below the 40-dp floor (the VisualDensity.compact adjustment
  /// already keeps it there).
  Widget _buildDiscardHeaderButton(ThemeData theme) {
    return OutlinedButton(
      onPressed: widget.editMode ? null : _showDiscardDialog,
      style: OutlinedButton.styleFrom(
        foregroundColor: widget.editMode
            ? OmniTheme.colors.textDisabled
            : theme.colorScheme.error,
        side: BorderSide(
          color: widget.editMode
              ? OmniTheme.colors.textDisabled
              : theme.colorScheme.error,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        ),
      ),
      child: const Text('Discard'),
    );
  }

  /// Identity of the session for the list-view header.
  ///
  /// Routine-started sessions carry the routine name in `title` (and a null
  /// modality); every other entry point leaves `title` empty and carries the
  /// modality, which renders as 'Free Training' when it too is null.
  String get _sessionDisplayName {
    final session = widget.workoutState.currentSession;
    final title = session?.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    return ModalityDisplay.getName(session?.modality);
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
            icon: Icon(Icons.arrow_back, color: OmniTheme.colors.textDominant),
            onPressed: () {
              // Detail view → back to list view
              // List view   → exit (with unsaved-changes check in edit mode)
              if (!_showListView) {
                _updateUi(() {
                  _showListView = true;
                });
                _scrollListToBottom();
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
                      ? (widget.editMode ? 'Edit Session' : _sessionDisplayName)
                      : (_exercises.isNotEmpty
                            ? _exercises[_currentExerciseIndex]['name']
                                  as String
                            : ''),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: OmniTheme.colors.textDominant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _showListView
                      ? '${widget.editMode ? '$_sessionDisplayName · ' : ''}${_exercises.length} exercise${_exercises.length != 1 ? 's' : ''}'
                      : (_exercises.isNotEmpty
                            ? 'Exercise ${_currentExerciseIndex + 1} / ${_exercises.length}'
                            : ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: widget.editMode
                        ? Theme.of(context).colorScheme.primary
                        : OmniTheme.colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!_showListView && (currentSegmentName?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      currentSegmentName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          // PR 4 spec: Discard lives in the session-details (list)
          // header — replacing the trash-can icon button. Hidden in the
          // exercise-details (detail) header so its action row stays
          // focused on notes / info.
          if (_showListView) _buildDiscardHeaderButton(theme),
          if (!_showListView && _exercises.isNotEmpty)
            _buildExerciseHeaderActions(theme),
        ],
      ),
    );
  }
}
