part of 'workout_session_screen.dart';

/// Session-finish and related dialog helpers for [WorkoutSessionScreen].
///
/// Extension on [_WorkoutSessionScreenState] — because this file is a `part of`
/// the same library, all private fields and methods of the state class are
/// directly accessible without any forwarding or getters.
extension _SessionFinishExt on _WorkoutSessionScreenState {
  Future<void> _showFinishSessionDialog() async {
    final hasExercises = widget.workoutState
        .getExercisesWithEntries()
        .isNotEmpty;
    if (!hasExercises) {
      // No exercises logged — discard the empty session and exit immediately.
      await widget.workoutState.discardCurrentSession();
      if (mounted) Navigator.of(context).pop();
      return;
    }

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

    _updateUi(() => _isFinishingSession = true);

    // Deterministic finish order:
    // 1) freeze all local UI timers
    // 2) persist all active timer-based entries (round + timed/drill)
    // 3) end session (set endedAtMs)
    // 4) replace route with summary so Back cannot resume an active session screen
    try {
      _freezeAllLocalTimers();
      await widget.restNotificationService.cancelRestNotifications();
      await widget.restNotificationService.cancelEffortTimerNotification();
      await _persistActiveEffortTimers();
      await widget.workoutState.endSession();

      if (!mounted) return;

      await _pushSessionReplacement(
        context,
        (_) => SessionSummaryScreen(
          workoutState: widget.workoutState,
          routineState: widget.routineState,
          sessionSummaryService: widget.sessionSummaryService,
          onSessionSaved: widget.onSessionSaved,
          settingsState: widget.settingsState,
          timerAlertService: widget.timerAlertService,
          restNotificationService: widget.restNotificationService,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to finish workout: $e')));
    } finally {
      if (mounted) {
        _updateUi(() => _isFinishingSession = false);
      }
    }
  }
}
