/// The Wear OS logging surface: one effort, its values, one confirm.
///
/// Plan: `.github/agents/plans/2026-07-13-07-a2-watch-wrist-logging-surfaces-plan.md`.
///
/// The four effort kinds are one screen varying by the fields the session hands
/// it (S-001 to S-004), because the wrist should not make the user learn four
/// layouts to log four kinds of work. Rotary input is primary — a turn arrives
/// as a scroll or a drag, both of which land in the same accumulation — and the
/// value row's own controls are the touch fallback. Nothing here counts down:
/// the readout is derived from stored timestamps on every tick, so a screen that
/// was off comes back showing the truth.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/unit_formatter.dart';
import '../session/watch_records.dart';
import '../session/watch_timer_math.dart';
import '../widgets/watch_controls.dart';
import 'watch_logging_state.dart';
import 'watch_timer_haptics.dart';

/// How the wrist is told a countdown ended.
abstract interface class WatchHaptics {
  void play(WatchTimerMilestone milestone);
}

/// The platform haptic channel, which Flutter already exposes on Wear OS: no
/// plugin, and the same call works on the phone during development.
class SystemWatchHaptics implements WatchHaptics {
  const SystemWatchHaptics();

  @override
  void play(WatchTimerMilestone milestone) {
    HapticFeedback.mediumImpact();
  }
}

class WatchLoggingScreen extends StatefulWidget {
  const WatchLoggingScreen({
    super.key,
    required this.state,
    this.haptics = const SystemWatchHaptics(),
  });

  final WatchLoggingState state;
  final WatchHaptics haptics;

  /// Points of turn that count as one detent, as [WatchRotaryTurn] counts them.
  static const double pointsPerDetent = WatchRotaryTurn.defaultPointsPerDetent;

  /// Wrist-scale layout. The phone's spacing tokens are sized for a full-width
  /// screen, so the watch carries its own two values rather than scaling a phone
  /// token down.
  static const double surfaceInset = 8;
  static const double surfaceInsetCompact = 4;

  @override
  State<WatchLoggingScreen> createState() => _WatchLoggingScreenState();
}

class _WatchLoggingScreenState extends State<WatchLoggingScreen>
    with WidgetsBindingObserver {
  /// One second is enough to watch a countdown move without a rebuild storm.
  static const Duration _tick = Duration(seconds: 1);

  /// Turn accumulated per field, waiting to add up to a whole detent.
  final Map<String, WatchRotaryTurn> _turn = {};

  Timer? _ticker;
  late WatchTimerHaptics _haptics;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _haptics = WatchTimerHaptics(widget.state.engine);
    _ticker = Timer.periodic(_tick, (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The poll after a suspension is the one that matters: the countdown kept
  /// running while the screen did not, and it fires at the instant it was due.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    for (final milestone in _haptics.poll(widget.state.now())) {
      widget.haptics.play(milestone);
    }
    if (mounted) setState(() {});
  }

  /// A turn of the rotary input: [travel] is signed movement in points, and a
  /// turn away from the wrist raises the value. Travel short of a detent is
  /// carried to the next event rather than rounding the value off its step.
  void _turnField(WatchMetricField field, double travel) {
    final detents = (_turn[field.metricKey] ??= WatchRotaryTurn()).detentsFor(
      travel,
    );
    if (detents == 0) return;

    widget.state.adjust(field.metricKey, detents.toDouble());
    setState(() {});
  }

  Future<void> _log() async {
    await widget.state.log();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WatchLoggingScreen.surfaceInset,
            vertical: WatchLoggingScreen.surfaceInsetCompact,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final field in widget.state.fields)
                      _row(context, field),
                  ],
                ),
              ),
              _logButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final styles = Theme.of(context).textTheme;
    final slot = widget.state.exerciseName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slot ?? 'No exercise',
          style: styles.labelLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (_countdown() case final countdown?)
          Text(
            '${OmniDateUtils.formatClock(countdown)} left',
            style: styles.bodySmall,
          ),
        if (_sensorLine() case final sensors?)
          Text(
            sensors,
            style: styles.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  /// What the sensors are reading, as one line: the heart rate, the distance,
  /// and the pace it is being covered at. Absent pieces are left out rather than
  /// shown as zero — a session with no reading has nothing to report, and the
  /// line disappears entirely when there is nothing at all.
  String? _sensorLine() {
    final readout = widget.state.sensorLabels;
    final units = widget.state.units;

    final parts = [
      if (readout.heartRate case final beats?) '$beats bpm',
      if (readout.distance case final distance?)
        '$distance ${UnitFormatter.distanceLabelForUnit(units.distanceUnit)}',
      ?readout.pace,
    ];

    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  /// What is left of the running countdown, or null when none is running. The
  /// round countdown wins when both kinds are live, because it is the one the
  /// user is working to.
  int? _countdown() {
    final running =
        widget.state.timerFor(WatchTimerKind.round) ??
        widget.state.timerFor(WatchTimerKind.rest);
    if (running == null || running.state == WatchTimerState.stopped) {
      return null;
    }
    return remainingMs(running, widget.state.now());
  }

  /// One value: the label, the numerals, and both ways to move it.
  /// One value: the label, the numerals, and both ways to move it. The crown
  /// drives whichever row carries focus, which is the row the user last
  /// touched.
  ///
  /// A row a sensor is keeping has neither: its controls are inert and its
  /// rotary handler is not attached, so a turn aimed at the row does nothing
  /// rather than replacing a measurement with a guess.
  Widget _row(BuildContext context, WatchMetricField field) {
    final styles = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final dialable = !field.isMeasured;

    return Listener(
      onPointerSignal: dialable
          ? (event) {
              if (event is PointerScrollEvent) {
                _turnField(field, event.scrollDelta.dy);
              }
            }
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: dialable
            ? (details) => _turnField(field, details.delta.dy)
            : null,
        child: Row(
          children: [
            WatchStepButton(
              icon: Icons.remove,
              label: 'Less ${field.label}',
              onPressed: dialable
                  ? () {
                      widget.state.adjust(field.metricKey, -1);
                      setState(() {});
                    }
                  : null,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    field.label,
                    style: styles.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    field.displayValue,
                    style: styles.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (field.unitLabel.isNotEmpty)
                    Text(field.unitLabel, style: styles.labelSmall),
                ],
              ),
            ),
            WatchStepButton(
              icon: Icons.add,
              label: 'More ${field.label}',
              onPressed: dialable
                  ? () {
                      widget.state.adjust(field.metricKey, 1);
                      setState(() {});
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// The primary action, and the largest thing on the screen: a wrist log is
  /// one glance and one confirm. The height comes from the token as a minimum
  /// rather than from a wrapping `SizedBox`, because the button already fills a
  /// stretching column and an extra wrapper would change nothing but the depth.
  Widget _logButton(BuildContext context) {
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
      onPressed: widget.state.canLog ? _log : null,
      child: const Text('Log'),
    );
  }
}
