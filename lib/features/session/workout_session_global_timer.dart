part of 'workout_session_screen.dart';

/// Global session timer, rest-ping, coach-mark, and exercise info/note helpers
/// for [WorkoutSessionScreen].
///
/// Extension on [_WorkoutSessionScreenState] — because this file is a `part of`
/// the same library, all private fields and methods of the state class are
/// directly accessible without any forwarding or getters.
extension _SessionGlobalTimerExt on _WorkoutSessionScreenState {
  void _tick() {
    // Calculate elapsed time from session start time (not from a local stopwatch)
    // This ensures the timer doesn't reset when navigating away and back
    final session = widget.workoutState.currentSession;
    if (session == null) return;
    if (session.endedAtMs != null) return;

    // Hold at 00:00 until the first exercise is added.
    if (_exercises.isEmpty) {
      _updateUi(() => _elapsedFormatted = '00:00');
      return;
    }

    final elapsedMs =
        DateTime.now().millisecondsSinceEpoch - session.startedAtMs;
    final elapsedSeconds = (elapsedMs / 1000).toInt();
    final mm = (elapsedSeconds ~/ 60).remainder(60).toString().padLeft(2, '0');
    final ss = (elapsedSeconds % 60).toString().padLeft(2, '0');
    _updateUi(() {
      _elapsedFormatted = '$mm:$ss';
    });
    _checkRestPings();
  }

  void _checkRestPings() {
    final pingInterval = widget.settingsState.restPingInterval;
    if (pingInterval == 0) return;
    final pingSound = widget.settingsState.restPingSound;

    for (final exercise in _exercises) {
      final effortId = exercise['id'] as String;
      final entryIndex = _currentSet - 1;
      if (!widget.workoutState.hasRestRecord(effortId, entryIndex)) continue;
      final elapsed = widget.workoutState.getRestElapsedSeconds(
        effortId,
        entryIndex,
      );
      final lastPinged = _lastRestPingFiredAt[effortId] ?? 0;
      if (shouldFireRestPing(
        elapsed: elapsed,
        interval: pingInterval,
        lastPinged: lastPinged,
      )) {
        _lastRestPingFiredAt[effortId] = elapsed;
        unawaited(widget.timerAlertService.fireRestPingAlert(pingSound));
      }
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

  ({String effortId, int entryIndex})? _getMostRecentOpenRestKey() {
    ({String effortId, int entryIndex})? latest;
    int? latestStartMs;

    for (final exercise in _exercises) {
      final effortId = exercise['id'] as String;
      final rests = widget.workoutState.getEntryRests(effortId);
      for (final rest in rests) {
        if (rest.restEndMs != null) continue;
        if (latestStartMs == null || rest.restStartMs > latestStartMs) {
          latestStartMs = rest.restStartMs;
          latest = (effortId: effortId, entryIndex: rest.entryIndex);
        }
      }
    }

    return latest;
  }

  bool _hasGlobalRestToDisplay() => _getMostRecentOpenRestKey() != null;

  String _formatGlobalRestElapsed() {
    final restKey = _getMostRecentOpenRestKey();
    if (restKey == null) return '00:00';
    return _formatRestElapsed(restKey.effortId, restKey.entryIndex);
  }

  // ── Exercise info / note sheets ───────────────────────────────────────────

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
        final isBilateral =
            exercise.capabilities.contains(ExerciseCapability.bilateral);

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
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
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

                // Bilateral logging note
                if (isBilateral) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text(
                      'LOGGING NOTE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      'This exercise is performed one side at a time. '
                      'Log both sides as a single combined set. '
                      'Example: 15 lb × 10 reps on each arm = log as 30 lb × 10 reps.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],

                // How-to section
                if (hasSteps) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text(
                      'HOW TO PERFORM',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.45),
                        letterSpacing: 2.0,
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
                if (!hasImage && !hasSteps && !isBilateral)
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

  // ── Coach marks ───────────────────────────────────────────────────────────

  void _maybeShowExerciseCoachMark() {
    if (_coachMarkEntry != null) return;
    if (!mounted) return;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (widget.workoutState.shouldShowExerciseInfoHint) {
      _showExerciseCoachMark(
        targetKey: _infoIconKey,
        label: 'View exercise info',
        primaryColor: primary,
        onDismiss: () {
          unawaited(widget.workoutState.markExerciseInfoHintSeen());
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeShowExerciseCoachMark();
          });
        },
      );
    } else if (widget.workoutState.shouldShowExerciseNotesHint) {
      _showExerciseCoachMark(
        targetKey: _notesIconKey,
        label: 'Add notes for this exercise',
        primaryColor: primary,
        onDismiss: () =>
            unawaited(widget.workoutState.markExerciseNotesHintSeen()),
      );
    }
  }

  void _showExerciseCoachMark({
    required GlobalKey targetKey,
    required String label,
    required Color primaryColor,
    required VoidCallback onDismiss,
  }) {
    final overlay = Overlay.of(context);
    final renderBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _coachMarkEntry == null) {
          _showExerciseCoachMark(
            targetKey: targetKey,
            label: label,
            primaryColor: primaryColor,
            onDismiss: onDismiss,
          );
        }
      });
      return;
    }

    final iconCenter = renderBox.localToGlobal(
      Offset(renderBox.size.width / 2, renderBox.size.height / 2),
    );

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ExerciseCoachMarkOverlay(
        iconCenter: iconCenter,
        label: label,
        primaryColor: primaryColor,
        onDismiss: () {
          entry.remove();
          _coachMarkEntry = null;
          onDismiss();
        },
      ),
    );

    _coachMarkEntry = entry;
    overlay.insert(entry);
  }
}

// ---------------------------------------------------------------------------
// Exercise note sheet
// ---------------------------------------------------------------------------

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
              textCapitalization: TextCapitalization.sentences,
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
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.45),
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

// ---------------------------------------------------------------------------
// Exercise coach mark overlay
// ---------------------------------------------------------------------------

/// Full-screen one-time coach mark that highlights a header icon.
///
/// Renders a dark semi-transparent backdrop, a pulsing primary-colored glow
/// centred on [iconCenter], and a short label below.  Tapping anywhere —
/// including the glow — dismisses the overlay and calls [onDismiss].
class _ExerciseCoachMarkOverlay extends StatefulWidget {
  final Offset iconCenter;
  final String label;
  final Color primaryColor;
  final VoidCallback onDismiss;

  const _ExerciseCoachMarkOverlay({
    required this.iconCenter,
    required this.label,
    required this.primaryColor,
    required this.onDismiss,
  });

  @override
  State<_ExerciseCoachMarkOverlay> createState() =>
      _ExerciseCoachMarkOverlayState();
}

class _ExerciseCoachMarkOverlayState extends State<_ExerciseCoachMarkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // Pulse twice then stop — gives a good visual without looping forever,
    // which would cause pumpAndSettle to time out in tests.
    _pulse.forward().whenComplete(() {
      if (!mounted) return;
      _pulse.reverse().whenComplete(() {
        if (!mounted) return;
        _pulse.forward().whenComplete(() {
          if (mounted) _pulse.reverse();
        });
      });
    });

    _scale = Tween<double>(
      begin: 1.0,
      end: 1.45,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _opacity = Tween<double>(
      begin: 0.55,
      end: 0.15,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double glowRadius = 22;
    const double labelWidth = 200;
    const double labelOffset = glowRadius + 12; // below glow centre
    const double triangleWidth = 10;
    const double triangleHeight = 6;
    const double screenMargin = 8.0;

    final cx = widget.iconCenter.dx;
    final cy = widget.iconCenter.dy;

    final screenWidth = MediaQuery.sizeOf(context).width;
    // Clamp label so it never overflows either edge of the screen.
    final rawLabelLeft = cx - labelWidth / 2;
    final clampedLabelLeft = rawLabelLeft.clamp(
      screenMargin,
      screenWidth - labelWidth - screenMargin,
    );

    return Stack(
      children: [
        // Dark backdrop — absorbs all taps so neither the overlay itself
        // nor underlying workout widgets react to incidental touches.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // absorb without action
          child: Container(color: const Color(0xBF000000)),
        ),

        // Pulsing glow ring
        Positioned(
          left: cx - glowRadius,
          top: cy - glowRadius,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scale.value,
                  child: Container(
                    width: glowRadius * 2,
                    height: glowRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.primaryColor.withOpacity(
                        _opacity.value * 0.6,
                      ),
                      border: Border.all(
                        color: widget.primaryColor.withOpacity(
                          _opacity.value + 0.2,
                        ),
                        width: 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Triangle pointer — always anchored to the icon center so it keeps
        // pointing at the icon even when the label box is clamped sideways.
        Positioned(
          left: cx - triangleWidth / 2,
          top: cy + labelOffset,
          child: IgnorePointer(
            child: CustomPaint(
              size: const Size(triangleWidth, triangleHeight),
              painter: _TrianglePointerPainter(
                color: widget.primaryColor.withOpacity(0.85),
              ),
            ),
          ),
        ),

        // Label box with "Got it!" button — clamped to stay within bounds.
        Positioned(
          left: clampedLabelLeft,
          top: cy + labelOffset + triangleHeight + 4,
          width: labelWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.primaryColor.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 30,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.primaryColor,
                          foregroundColor: Colors.black87,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: widget.onDismiss,
                        child: const Text('Got it!'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Draws a small downward-pointing triangle used as a callout pointer.
class _TrianglePointerPainter extends CustomPainter {
  final Color color;
  const _TrianglePointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePointerPainter old) => old.color != color;
}
