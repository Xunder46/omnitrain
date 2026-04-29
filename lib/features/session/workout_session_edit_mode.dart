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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: OmniTheme.textSecondary),
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
    // Defer controller disposal until the dialog exit animation completes.
    // Disposing immediately causes "used after being disposed" errors because
    // the dialog's TextField widgets briefly outlive the showDialog future.
    Future.delayed(const Duration(milliseconds: 300), () {
      hhCtrl.dispose();
      mmCtrl.dispose();
      ssCtrl.dispose();
    });

    if (result != null && result > 0 && mounted) {
      setState(() {
        _pendingDurationSecs = result;
        _reformatElapsed(result as int);
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
}
