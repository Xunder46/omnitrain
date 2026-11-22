/// The Wear wrist's effort-rating prompt: the owed question, alone (plan 285,
/// series 283 unit c). The Dart counterpart of the Apple client's
/// `WatchEffortRatingView`.
///
/// Every decision is `WatchEffortRatingState`'s; this screen only binds to it.
/// It carries no control but the five numbers, Confirm and Skip: an answer or
/// Skip is the only way past it. The rotary (a scroll event or a drag) steps the
/// number, as on the logging surface. The whole body sits in a `FittedBox`, so
/// on a 192 or 227 dp watch it scales down rather than overflowing.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../widgets/watch_controls.dart';
import 'watch_effort_rating_state.dart';

class WatchEffortRatingScreen extends StatefulWidget {
  const WatchEffortRatingScreen({super.key, required this.state});

  final WatchEffortRatingState state;

  @override
  State<WatchEffortRatingScreen> createState() =>
      _WatchEffortRatingScreenState();
}

class _WatchEffortRatingScreenState extends State<WatchEffortRatingScreen> {
  /// Turn waiting to add up to a whole detent.
  final WatchRotaryTurn _turn = WatchRotaryTurn();

  /// A turn away from the wrist (negative travel) raises the number, as on the
  /// logging surface.
  void _rotate(double travel) {
    final detents = _turn.detentsFor(travel);
    if (detents != 0) widget.state.step(detents);
  }

  @override
  Widget build(BuildContext context) {
    final compact = WatchLayout.isCompact(context);

    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) _rotate(event.scrollDelta.dy);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) => _rotate(details.delta.dy),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: LayoutBuilder(
                  builder: (context, box) => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: box.maxWidth,
                      child: _content(context, compact),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, bool compact) {
    final styles = Theme.of(context).textTheme;
    final state = widget.state;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state.title,
          style: styles.titleSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (final value in state.scale) _number(value)],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                state.lowestLabel,
                style: styles.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Flexible(
              child: Text(
                state.highestLabel,
                style: styles.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FilledButton(
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonBorderRadius,
                ),
              ),
            ),
            minimumSize: WidgetStateProperty.all(
              Size.fromHeight(
                compact
                    ? WatchLayout.compactButtonHeight
                    : OmniTheme.buttonPrimaryHeight,
              ),
            ),
            tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
          ),
          onPressed: state.canConfirm ? () => state.confirm() : null,
          child: const Text('Confirm'),
        ),
        TextButton(
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonUtilityRadius,
                ),
              ),
            ),
            minimumSize: compact
                ? WidgetStateProperty.all(
                    const Size.fromHeight(WatchLayout.compactMenuHeight),
                  )
                : null,
            tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
          ),
          onPressed: state.skipPrompt,
          child: const Text(WatchEffortRatingCopy.skipLabel),
        ),
      ],
    );
  }

  /// One number of the scale: the picked one is the filled button.
  Widget _number(int value) {
    final picked = widget.state.selected == value;
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(EdgeInsets.zero),
      minimumSize: WidgetStateProperty.all(const Size(32, 36)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        ),
      ),
    );
    final label = Text('$value');

    return SizedBox(
      width: 32,
      height: 36,
      child: Semantics(
        label: '$value of ${WatchEffortRatingCopy.highest}',
        selected: picked,
        button: true,
        excludeSemantics: true,
        child: picked
            ? FilledButton(
                style: style,
                onPressed: () => widget.state.select(value),
                child: label,
              )
            : OutlinedButton(
                style: style,
                onPressed: () => widget.state.select(value),
                child: label,
              ),
      ),
    );
  }
}
