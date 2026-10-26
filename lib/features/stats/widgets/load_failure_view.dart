import 'package:flutter/material.dart';

import '../../../core/constants/omni_theme.dart';

/// The centred "could not load" surface the Stats-area screens render when
/// their one load read throws (D-27.4).
///
/// It is deliberately not an empty state: the screen says the load failed and
/// offers the retry that re-runs the screen's own load method. The retry button
/// copies the look of the startup failure screen's Retry — full width, primary
/// height, `buttonBorderRadius` (D-26.2).
class LoadFailureView extends StatelessWidget {
  const LoadFailureView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  /// The plain-language failure line, e.g. "Could not load your stats." Never
  /// an exception's text (D-27.2).
  final String message;

  /// Re-runs the screen's load method.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: OmniTheme.buttonPrimaryHeight,
              width: double.infinity,
              child: FilledButton(
                key: const Key('load_failure_retry'),
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonBorderRadius,
                    ),
                  ),
                ),
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
