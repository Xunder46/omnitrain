import 'package:flutter/material.dart';

/// Dominant metric display widget for the session exercise screen.
///
/// Renders exactly ONE large metric. Identical layout across all modalities.
/// The metric *semantics* differ (time vs reps vs hold), but the visual
/// hierarchy is the same.
///
/// Tap to edit is supported for rep-based metrics (opens dialog).
/// Timer-based metrics toggle play/pause on tap.
///
/// Rules (from UI spec):
/// - Always exactly ONE dominant metric shown in large type
/// - No mixed metrics on screen
/// - No distance, load, or RPE inputs on this screen
class DominantMetricWidget extends StatelessWidget {
  /// The formatted string to display as the large metric.
  /// For reps: "10"
  /// For time/hold: "03:00" or "00:42"
  /// For rounds: "Round 1\n03:00"
  final String displayText;

  /// Whether this is a multiline display (e.g. round label + countdown).
  final bool isMultiline;

  /// Optional tap callback (e.g. to edit reps, toggle timer).
  final VoidCallback? onTap;

  const DominantMetricWidget({
    super.key,
    required this.displayText,
    this.isMultiline = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: theme.textTheme.displayLarge?.copyWith(
          fontSize: isMultiline ? 56 : 72,
          fontWeight: FontWeight.w300,
          letterSpacing: -2,
          height: isMultiline ? 1.3 : null,
        ),
      ),
    );
  }
}
