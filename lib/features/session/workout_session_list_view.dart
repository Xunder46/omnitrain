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

  // ── Block card ────────────────────────────────────────────────────────────

  Widget _buildSessionBlockCard(SessionBlock block, ThemeData theme) {
    final blockExercises = _exercises
        .where((e) => e['blockId'] == block.id)
        .toList();
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
                      color: OmniTheme.textPrimary,
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
                    color: OmniTheme.textSecondary,
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

  Widget _buildAddExerciseAndBlockBar(ThemeData theme, {String? segmentId}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            height: OmniTheme.buttonPrimaryHeight,
            child: FilledButton(
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
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await widget.workoutState.addSessionBlock();
                _updateUi(() {});
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: theme.colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
              child: const Text('Add Block'),
            ),
          ),
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
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            0,
                            0,
                            0,
                            _kBottomControlsClearance,
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
          if (!widget.editMode && _hasGlobalRestToDisplay())
            Positioned(
              left: 0,
              right: 0,
              bottom: 130,
              child: Center(
                child: _buildRestOverlayChip(theme, _formatGlobalRestElapsed()),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: OmniBottomCTA(
              label: widget.editMode ? 'Save Changes' : 'Finish Workout',
              onPressed: widget.editMode
                  ? _saveEditChanges
                  : _showFinishSessionDialog,
            ),
          ),
        ],
      ),
    );
  }

  // ── Standard (non-rolling) session list view ──────────────────────────────

  Widget _buildStandardSessionListView(ThemeData theme) {
    final blocks = widget.workoutState.getSessionBlocks();
    final standaloneExercises = _exercises
        .where((e) => e['blockId'] == null)
        .toList();
    final segmentId = widget.workoutState.segments.isNotEmpty
        ? widget.workoutState.segments.first.id
        : null;

    if (_exercises.isEmpty && blocks.isEmpty) {
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
                label: widget.editMode ? 'Save Changes' : 'Finish Workout',
                onPressed: widget.editMode
                    ? _saveEditChanges
                    : _showFinishSessionDialog,
              ),
            ),
          ],
        ),
      );
    }

    final List<({SessionBlock? block, Map<String, dynamic>? exercise})> items =
        [];
    for (final b in blocks) {
      items.add((block: b, exercise: null));
    }
    for (final ex in standaloneExercises) {
      items.add((block: null, exercise: ex));
    }
    items.sort((a, b) {
      if (a.exercise != null && b.exercise != null) {
        final aCreatedAt = a.exercise!['createdAtMs'] as int? ?? 0;
        final bCreatedAt = b.exercise!['createdAtMs'] as int? ?? 0;
        final createdCompare = aCreatedAt.compareTo(bCreatedAt);
        if (createdCompare != 0) return createdCompare;

        final aOrder = a.exercise!['executionOrder'] as int? ?? 0;
        final bOrder = b.exercise!['executionOrder'] as int? ?? 0;
        final executionCompare = aOrder.compareTo(bOrder);
        if (executionCompare != 0) return executionCompare;

        final aId = a.exercise!['id'] as String? ?? '';
        final bId = b.exercise!['id'] as String? ?? '';
        return aId.compareTo(bId);
      }

      final aMs =
          a.block?.createdAtMs ?? (a.exercise?['createdAtMs'] as int? ?? 0);
      final bMs =
          b.block?.createdAtMs ?? (b.exercise?['createdAtMs'] as int? ?? 0);
      return aMs.compareTo(bMs);
    });

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
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      8,
                      0,
                      _kBottomControlsClearance,
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
          if (!widget.editMode && _hasGlobalRestToDisplay())
            Positioned(
              left: 0,
              right: 0,
              bottom: 130,
              child: Center(
                child: _buildRestOverlayChip(theme, _formatGlobalRestElapsed()),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: OmniBottomCTA(
              label: widget.editMode ? 'Save Changes' : 'Finish Workout',
              onPressed: widget.editMode
                  ? _saveEditChanges
                  : _showFinishSessionDialog,
            ),
          ),
        ],
      ),
    );
  }

  // ── Rest overlay chip ─────────────────────────────────────────────────────

  Widget _buildRestOverlayChip(ThemeData theme, String elapsedText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withAlpha((0.2 * 255).round()),
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
                elapsedText,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
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
      extendBody: true,
      body: GestureDetector(
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
                            const SizedBox(height: 10),
                            _buildSetProgress(
                              entries.length,
                              effortKind,
                              theme,
                            ),
                            const SizedBox(height: 16),
                            _buildPreviousSetStats(exercise, effortKind, theme),
                            const SizedBox(height: 16),
                            _buildSetIndicator(
                              entries.length,
                              effortKind,
                              theme,
                            ),
                            SizedBox(height: 24 + _kSessionScrollBottomExtra),
                          ],
                        ),
                      ),
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
            // Rest timer overlay in lower half (hide in edit mode or when exercise timer is running).
            // Uses the global helper so the overlay persists after crossing an exercise
            // boundary (the open rest lives under the previous exercise's effortId).
            if (!widget.editMode &&
                _hasGlobalRestToDisplay() &&
                !(_effortRunning['${exercise['id']}-${_currentSet - 1}'] ??
                    false))
              Positioned(
                left: 0,
                right: 0,
                bottom: 130,
                child: Center(
                  child: _buildRestOverlayChip(
                    theme,
                    _formatGlobalRestElapsed(),
                  ),
                ),
              ),
          ],
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
                _updateUi(() {
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!_showListView && (currentSegmentName?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      currentSegmentName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}
