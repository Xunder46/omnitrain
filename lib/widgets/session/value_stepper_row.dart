import 'dart:async';

import 'package:flutter/material.dart';

import '../layout/omni_surface.dart';
import 'inline_metric_editor.dart';

/// Full-width `−  <value>  +` control for a reps, weight or duration metric.
///
/// The row is the shared piece for every stepper the session screens show: the
/// number in the middle is the existing [InlineMetricEditor], so tapping it
/// still opens `showMetricEditPopup`, and the two round buttons step the value
/// by [step] in the shown unit.
///
/// A `duration` row keeps the value an `int` number of seconds (the editor
/// shows `mm:ss`), steps 15 s by default and can be floored by [min] — the
/// 3600 s ceiling comes from `MetricStepCalc`. [onEditorTap] lets a caller
/// replace the generic popup, which is how the round-length row opens the
/// duration dialog.
///
/// Press and hold on a button repeats the step, faster the longer it is held
/// ([repeatInterval]); the number on screen follows the hold while
/// [onValueChanged] is called once, when the finger lifts. A single quick tap
/// commits at once.
///
/// The row owns its outer margin and is boxed in the shared [OmniSurface]
/// (plan 38f, L-6): 20 dp left and right, 4 dp above and below.
///
/// Plan: `docs/plans/2026-10-15-38b-reps-screen-plan/2026-10-15-38b-reps-screen-plan.md`
/// (decisions D-2..D-6); duration mode:
/// `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.md`
/// (D-7, A3). Covered by `test/value_stepper_row_test.dart`.
class ValueStepperRow extends StatefulWidget {
  /// The metric the row edits: `reps`, `weight` or `duration`.
  final String metricType;

  /// The value to show, in the unit the screen displays (`int` for reps and
  /// duration, `double` for weight).
  final num currentValue;

  /// The unit shown beside the number (`REPS`, `KG`, `LBS`, `ROUND LENGTH`).
  final String unitLabel;

  /// One step, in the shown unit (`MetricStepping.weightStepFor` for weight).
  /// Defaults to [durationStepSeconds] for `duration` and 1 otherwise.
  final double? step;

  /// When true the buttons are dimmed and do nothing and the number is not
  /// tappable (a logged set is locked).
  final bool isReadOnly;

  /// Optional floor for the stepped value: a step that would land below it
  /// lands on it, and a row already at the floor steps no further down.
  /// The ceiling stays `MetricStepCalc`'s.
  final num? min;

  /// Optional replacement for the number tap.
  ///
  /// When given it is handed to the inner [InlineMetricEditor] as its `onTap`,
  /// so tapping the number calls it instead of opening
  /// `showMetricEditPopup`; `null` keeps today's popup.
  final VoidCallback? onEditorTap;

  /// Called with the stepped value (`int` for reps and duration, `double` for
  /// weight) — the same shape [InlineMetricEditor] hands the session screen
  /// today.
  final ValueChanged<dynamic> onValueChanged;

  const ValueStepperRow({
    super.key,
    required this.metricType,
    required this.currentValue,
    required this.unitLabel,
    this.step,
    this.isReadOnly = false,
    this.min,
    this.onEditorTap,
    required this.onValueChanged,
  });

  /// One tap on a `duration` row moves this many seconds (plan 38d, A3).
  static const double durationStepSeconds = 15;

  /// One step for rows whose caller does not name one.
  double get effectiveStep =>
      step ?? (metricType == 'duration' ? durationStepSeconds : 1);

  /// The delay before the next repeat tick, slow to fast.
  static const Duration slowRepeatInterval = Duration(milliseconds: 200);
  static const Duration mediumRepeatInterval = Duration(milliseconds: 100);
  static const Duration fastRepeatInterval = Duration(milliseconds: 50);

  /// How many ticks the slow and medium tiers run for.
  static const int slowRepeatTicks = 5;
  static const int mediumRepeatTicks = 15;

  /// The delay before the tick after [tickNumber], counting the first tick —
  /// the one `onLongPressStart` fires at Flutter's long-press deadline — as 1:
  /// 200 ms for the first five ticks, 100 ms for the next ten, 50 ms after.
  static Duration repeatInterval(int tickNumber) {
    if (tickNumber <= slowRepeatTicks) return slowRepeatInterval;
    if (tickNumber <= mediumRepeatTicks) return mediumRepeatInterval;
    return fastRepeatInterval;
  }

  @override
  State<ValueStepperRow> createState() => _ValueStepperRowState();
}

class _ValueStepperRowState extends State<ValueStepperRow> {
  /// The latest intended value: set by a tap, then once per repeat tick. It
  /// keeps two quick taps from both reading a stale `currentValue` while the
  /// screen is still reloading, and it is what a lift commits.
  dynamic _pending;

  Timer? _repeatTimer;
  int _tickCount = 0;
  bool _holding = false;

  @override
  void didUpdateWidget(covariant ValueStepperRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentValue != oldWidget.currentValue) {
      _pending = null;
    }
    if (widget.isReadOnly && !oldWidget.isReadOnly) {
      // The set was locked mid-hold (the watch logged it): the intent is stale,
      // so the hold is dropped without storing it.
      _stopHold();
      _pending = null;
    }
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    super.dispose();
  }

  dynamic get _shownValue {
    final value = _pending ?? widget.currentValue;
    return widget.metricType == 'reps' || widget.metricType == 'duration'
        ? (value as num).toInt()
        : (value as num).toDouble();
  }

  /// The value one step from the current intent, clamped by the metric's own
  /// parse/clamp (the same owner the edit popup uses) and then by [min], or
  /// null when the step changes nothing (a limit).
  dynamic _steppedValue(int direction) {
    final current = _pending ?? widget.currentValue;
    final base = widget.metricType == 'weight'
        ? ((current as num).toDouble() * 10).roundToDouble() / 10
        : current;
    dynamic next = MetricStepCalc.parseAndClamp(
      widget.metricType,
      (base + direction * widget.effectiveStep).toString(),
    );
    if (next == null) return null;
    final floor = widget.min;
    if (floor != null && next < floor) {
      // Keep the value's own shape: reps and durations step in whole units.
      next = next is int ? floor.toInt() : floor.toDouble();
    }
    if (next == base) return null;
    return next;
  }

  void _handleTap(int direction) {
    if (widget.isReadOnly) return;
    final next = _steppedValue(direction);
    if (next == null) return;
    setState(() => _pending = next);
    widget.onValueChanged(next);
  }

  void _handleHoldStart(int direction) {
    if (widget.isReadOnly) return;
    _holding = true;
    _tickCount = 0;
    _tick(direction);
  }

  void _tick(int direction) {
    final next = _steppedValue(direction);
    if (next != null) setState(() => _pending = next);
    _tickCount += 1;
    _repeatTimer?.cancel();
    _repeatTimer = Timer(
      ValueStepperRow.repeatInterval(_tickCount),
      () => _tick(direction),
    );
  }

  /// End and cancel both commit, once: whichever arrives first clears
  /// [_holding], and a row whose hold was dropped by a lock commits nothing.
  void _handleHoldRelease() {
    if (!_holding) return;
    _stopHold();
    final pending = _pending;
    if (pending == null) return;
    widget.onValueChanged(pending);
  }

  void _stopHold() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _tickCount = 0;
    _holding = false;
  }

  void _handleEditorValue(dynamic value) {
    setState(() => _pending = value);
    widget.onValueChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: OmniSurface(
        showShadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _buildStepButton(isPlus: false),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: InlineMetricEditor(
                    metricType: widget.metricType,
                    currentValue: _shownValue,
                    unitLabel: widget.unitLabel,
                    showUnitInline: true,
                    emphasisTier: MetricEmphasisTier.dominant,
                    isReadOnly: widget.isReadOnly,
                    // The editor's outer GestureDetector fires `onTap` even when
                    // read-only, so a locked row hands it nothing.
                    onTap: widget.isReadOnly ? null : widget.onEditorTap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    onValueChanged: _handleEditorValue,
                  ),
                ),
              ),
            ),
            _buildStepButton(isPlus: true),
          ],
        ),
      ),
    );
  }

  Widget _buildStepButton({required bool isPlus}) {
    final noun = switch (widget.metricType) {
      'reps' => 'reps',
      'duration' => 'duration',
      _ => 'weight',
    };
    return _StepButton(
      key: Key(
        'value-stepper-${isPlus ? 'plus' : 'minus'}-${widget.metricType}',
      ),
      icon: isPlus ? Icons.add : Icons.remove,
      label: '${isPlus ? 'Increase' : 'Decrease'} $noun',
      isReadOnly: widget.isReadOnly,
      onTap: widget.isReadOnly ? null : () => _handleTap(isPlus ? 1 : -1),
      onLongPressStart: widget.isReadOnly
          ? null
          : () => _handleHoldStart(isPlus ? 1 : -1),
      onLongPressEnd: widget.isReadOnly ? null : _handleHoldRelease,
      onLongPressCancel: widget.isReadOnly ? null : _handleHoldRelease,
    );
  }
}

/// One 48 x 48 round step target.
///
/// Deliberately not an `IconButton`: its own long-press tooltip trigger would
/// fight the hold-to-repeat, so the tooltip is manual and the gestures are
/// owned here. The icon-only button rules therefore do not apply to it.
class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isReadOnly,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
  });

  final IconData icon;
  final String label;
  final bool isReadOnly;
  final VoidCallback? onTap;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.manual,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPressStart: onLongPressStart == null
              ? null
              : (_) => onLongPressStart!(),
          onLongPressEnd: onLongPressEnd == null
              ? null
              : (_) => onLongPressEnd!(),
          onLongPressCancel: onLongPressCancel,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Material(
              shape: const CircleBorder(),
              color: scheme.onSurface.withAlpha(
                isReadOnly ? (0.05 * 255).round() : (0.1 * 255).round(),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 28,
                  color: isReadOnly
                      ? scheme.onSurface.withAlpha(77)
                      : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
