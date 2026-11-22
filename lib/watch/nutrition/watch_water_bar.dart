/// The water bar at the bottom of the Wear nutrition screen: minus, a drop with
/// the glass count, plus.
///
/// Plan: `docs/plans/2026-11-22-291-wear-water-bar-plan/2026-11-22-291-wear-water-bar-plan.md`
/// (D-29101..D-29103). The Dart twin of the Apple client's `WatchWaterBar`
/// (plan 95). It draws what `WatchWaterState.snapshot` says, read once per
/// build, and computes nothing: the count, both buttons' rules and the spoken
/// count come from the same instant and the same taps.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session/watch_records.dart';
import '../widgets/watch_controls.dart';
import 'watch_water_state.dart';

class WatchWaterBar extends StatefulWidget {
  const WatchWaterBar({super.key, required this.state});

  final WatchWaterState state;

  static const Key removeKey = Key('watch_water_remove');
  static const Key addKey = Key('watch_water_add');
  static const Key countKey = Key('watch_water_count');

  /// How often the bar re-reads on its own, so the count after local midnight is
  /// the new day's within a minute (plan 95 D-34).
  static const Duration refreshEvery = Duration(minutes: 1);

  @override
  State<WatchWaterBar> createState() => _WatchWaterBarState();
}

class _WatchWaterBarState extends State<WatchWaterBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.state.onWaterChanged = _changed;
    _ticker = Timer.periodic(WatchWaterBar.refreshEvery, (_) => _changed());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // The owner has one listener slot: clear it only if it is still this bar's.
    if (widget.state.onWaterChanged == _changed) {
      widget.state.onWaterChanged = null;
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// One press: a click only when a tap was stored, nothing otherwise (plan 95
  /// D-32). The rebuild comes from the owner's change callback.
  Future<void> _press(String change) async {
    final stored = await widget.state.press(change);
    if (stored) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.state.snapshot;
    final styles = Theme.of(context).textTheme;
    final compact = WatchLayout.isCompact(context);
    return Row(
      children: [
        WatchStepButton(
          key: WatchWaterBar.removeKey,
          icon: Icons.remove,
          label: WatchWaterCopy.removeLabel,
          compact: compact,
          onPressed: snapshot.canRemove
              ? () => _press(WatchGlassChange.remove)
              : null,
        ),
        Expanded(
          child: Semantics(
            key: WatchWaterBar.countKey,
            label: WatchWaterCopy.countLabel,
            value: snapshot.spokenCount,
            excludeSemantics: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.water_drop,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${snapshot.glasses}',
                    style: styles.labelLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        WatchStepButton(
          key: WatchWaterBar.addKey,
          icon: Icons.add,
          label: WatchWaterCopy.addLabel,
          compact: compact,
          onPressed: snapshot.canAdd
              ? () => _press(WatchGlassChange.add)
              : null,
        ),
      ],
    );
  }
}
