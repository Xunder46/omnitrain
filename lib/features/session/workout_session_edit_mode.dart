part of 'workout_session_screen.dart';

/// Edit-mode helpers for [WorkoutSessionScreen].
///
/// Extension on [_WorkoutSessionScreenState] — because this file is a `part of`
/// the same library, all private fields and methods of the state class are
/// directly accessible without any forwarding or getters.
extension _SessionEditModeExt on _WorkoutSessionScreenState {
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
    _beginSetTransition(1);
    int? nextExerciseIndex;
    _updateUi(() {
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
    final result = await showDurationEntryDialog(
      context,
      title: 'Edit Session Duration',
      subtitle: 'Adjust the total duration of this session.',
      initialSecs: _pendingDurationSecs ?? 0,
    );
    if (result != null && result > 0 && mounted) {
      _updateUi(() {
        _pendingDurationSecs = result;
        _reformatElapsed(result);
      });
    }
  }

  // ── Edit-mode navigation helpers ─────────────────────────────────────────

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

    final action = await ConfirmationDialog.showUnsavedChanges(
      context: context,
      title: 'Unsaved changes',
      body:
          'You have unsaved edits. Save them or discard to return to the summary.',
      keepEditingKey: const Key('session-edit-unsaved-keep'),
      discardKey: const Key('session-edit-unsaved-discard'),
      saveKey: const Key('session-edit-unsaved-save'),
    );

    if (!mounted) return;
    switch (action) {
      case UnsavedChangesAction.save:
        await _saveEditChanges();
      case UnsavedChangesAction.discard:
        await _discardEditChanges();
      case UnsavedChangesAction.keepEditing:
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
  ///
  /// Duration metrics are routed to the appropriate instance-level write
  /// methods rather than to observation writes:
  ///   - `'elapsedSecs'` on timed/drill → [WorkoutState.setTimedEntryDuration]
  ///   - `'round-duration'` on round → [WorkoutState.setRoundDuration]
  /// All other metric keys continue to use [WorkoutState.updateEntryValue].
  Future<void> _saveEditChanges() async {
    // ── Step 1: flush metric edits ──────────────────────────────────────────
    for (final entry in _editBuffer.entries) {
      final parts = entry.key.split('-');
      if (parts.length < 2) continue;
      // Reconstruct effortId (may contain hyphens; entryIndex is always last)
      final effortId = parts.sublist(0, parts.length - 1).join('-');
      final entryIndex = int.tryParse(parts.last);
      if (entryIndex == null) continue;

      final effortKind = _getEffortKind(effortId);
      final metrics = entry.value;

      for (final metricEntry in metrics.entries) {
        if (metricEntry.key == 'elapsedSecs' &&
            (effortKind == 'timed' || effortKind == 'drill')) {
          // Write directly to the TimedInstance (in-memory + repository)
          // so computeSessionSummary picks up the updated elapsedMs.
          await widget.workoutState.setTimedEntryDuration(
            effortId,
            entryIndex,
            metricEntry.value as int,
          );
        } else if (metricEntry.key == 'round-duration' &&
            effortKind == 'round') {
          // Write directly to the RoundInstance (in-memory + repository)
          // so computeSessionSummary picks up the updated elapsedMs.
          await widget.workoutState.setRoundDuration(
            effortId,
            entryIndex,
            metricEntry.value as int,
          );
        } else {
          // All other metric keys (reps, weight, extra-weight, distance, etc.)
          await widget.workoutState.updateEntryValue(
            effortId,
            entryIndex,
            metricEntry.key,
            metricEntry.value,
          );
        }
      }
    }

    // ── Step 2: normalise all non-finished rounds to finished ───────────────
    // Ensures a historical session never contains rounds in notStarted / active
    // / paused states after the user saves.
    await widget.workoutState.normalizeRoundsToFinished();

    // ── Step 3: persist session duration change if any ──────────────────────
    if (_hasDurationChanged()) {
      await widget.workoutState.updateSessionEndTime(_pendingDurationSecs!);
      _originalDurationSecs = _pendingDurationSecs;
    }

    // ── Step 4: clear rollback state ────────────────────────────────────────
    _editBuffer.clear();
    _hasStructuralChanges = false;
    _editSnapshot = null;
    if (mounted) Navigator.of(context).pop();
  }
}
