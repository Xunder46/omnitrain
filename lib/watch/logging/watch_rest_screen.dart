/// The Wear OS rest surface: the exercise, the elapsed rest, one Next.
///
/// Plan: `docs/plans/2026-10-08-18b-watch-rest-count-up-plan.md`, D-160 and
/// D-161.
///
/// Rest is a count-up from the moment a set is logged; there is no preset
/// length. The elapsed is derived from the persisted timer row on every tick,
/// so a screen that was off comes back showing the truth. The same tick asks the
/// ping rule how far through the phone's Rest Ping interval the rest is, and
/// taps through the injected haptics when one is owed. One control, Next: it
/// ends the rest and returns to logging (D-161). No End, no picker, no dial,
/// no pause.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import '../session/watch_records.dart';
import 'watch_logging_screen.dart';
import 'watch_logging_state.dart';
import 'watch_rest_ping.dart';

class WatchRestScreen extends StatefulWidget {
  const WatchRestScreen({
    super.key,
    required this.state,
    required this.onNext,
    this.haptics = const SystemWatchHaptics(),
  });

  final WatchLoggingState state;
  final VoidCallback onNext;

  /// Where the rest's ping goes. The default is the platform channel, as the
  /// logging surface defaults it.
  final WatchHaptics haptics;

  /// Wrist-scale layout, as the logging surface carries it.
  static const double surfaceInset = 8;
  static const double surfaceInsetCompact = 4;

  @override
  State<WatchRestScreen> createState() => _WatchRestScreenState();
}

class _WatchRestScreenState extends State<WatchRestScreen> {
  /// One second is enough to watch the count-up move without a rebuild storm.
  static const Duration _tick = Duration(seconds: 1);

  /// The ping rule, held across ticks so `lastPinged` follows the rest row being
  /// walked.
  final WatchRestPing _ping = WatchRestPing();

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_tick, (_) {
      _pingIfOwed();
      if (mounted) setState(() {});
    });
  }

  /// The ping, asked once per tick through the surface's own preferences. The
  /// rule owns whether this second is one the interval names — it is a tap of
  /// its own, never a countdown that ended (D-251).
  void _pingIfOwed() {
    final owed = _ping.isOwed(
      restId: widget.state.timerFor(WatchTimerKind.rest)?.recordId,
      elapsed: widget.state.restElapsedSeconds(),
      interval: widget.state.units.restPingSeconds,
    );
    if (owed) widget.haptics.playRestPing();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _next() async {
    await widget.state.endRest();
    if (mounted) setState(() {});
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WatchRestScreen.surfaceInset,
            vertical: WatchRestScreen.surfaceInsetCompact,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.state.exerciseName ?? 'No exercise',
                style: styles.labelLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _elapsed(),
                    style: styles.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              _nextButton(context),
            ],
          ),
        ),
      ),
    );
  }

  /// The rest's elapsed time as "m:ss", read from the persisted row at this
  /// instant rather than counted by the screen.
  String _elapsed() =>
      OmniDateUtils.formatClock((widget.state.restElapsedSeconds() ?? 0) * 1000);

  /// The surface's one control: ending the rest and returning to logging. The
  /// shape is set explicitly, as the design system requires of every button.
  Widget _nextButton(BuildContext context) {
    return FilledButton(
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OmniTheme.buttonBorderRadius),
          ),
        ),
        minimumSize: WidgetStateProperty.all(
          const Size.fromHeight(OmniTheme.buttonPrimaryHeight),
        ),
      ),
      onPressed: _next,
      child: const Text('Next'),
    );
  }
}
