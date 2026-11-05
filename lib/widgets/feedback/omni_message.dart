/// The one look for a small message at the bottom of a screen.
///
/// Every transient message the app shows — "saved", "could not save" — comes
/// through this class, so all of them read the same: the theme's surface
/// colour, the theme's text colour and the corner radius the dialog actions
/// use. Placement is Flutter's default bottom bar, unchanged (D-27.1).
///
/// Plan: `docs/plans/2026-10-13-27-ui-messages-plan/`.
library;

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// Info and failure messages, with one shared look.
class OmniMessage {
  OmniMessage._();

  /// Flutter's own `SnackBar.duration` default. `duration` is a non-nullable
  /// constructor argument, so leaving it unset here has to pass the same value
  /// explicitly — the on-screen behaviour is identical.
  static const Duration _defaultDuration = Duration(milliseconds: 4000);

  /// Shows [text] as an informational message.
  ///
  /// [action] and [duration] pass straight to the `SnackBar`; leaving both
  /// unset keeps Flutter's own defaults, so a message behaves exactly as it
  /// did before the shared look existed.
  static void show(
    BuildContext context,
    String text, {
    SnackBarAction? action,
    Duration? duration,
  }) {
    showOn(
      ScaffoldMessenger.of(context),
      Theme.of(context),
      text,
      action: action,
      duration: duration,
    );
  }

  /// Shows [text] as a failed action: the same look, with a leading
  /// `Icons.error_outline` in `colorScheme.error`.
  ///
  /// The copy is the caller's — `Could not ... Try again.` — never an
  /// exception's `toString()`, which this method cannot even receive
  /// (D-27.2).
  static void error(BuildContext context, String text) {
    errorOn(ScaffoldMessenger.of(context), Theme.of(context), text);
  }

  /// Shows [text] as an informational message on a `messenger` and `theme`
  /// captured **before** an `await`, for tap handlers that persist first and
  /// must not touch the `context` again afterwards.
  static void showOn(
    ScaffoldMessengerState messenger,
    ThemeData theme,
    String text, {
    SnackBarAction? action,
    Duration? duration,
  }) {
    _present(
      messenger,
      theme,
      text: text,
      isError: false,
      action: action,
      duration: duration,
    );
  }

  /// [error]'s counterpart to [showOn]: the failure look on a messenger and
  /// theme captured before an `await`.
  static void errorOn(
    ScaffoldMessengerState messenger,
    ThemeData theme,
    String text,
  ) {
    _present(messenger, theme, text: text, isError: true);
  }

  static void _present(
    ScaffoldMessengerState messenger,
    ThemeData theme, {
    required String text,
    required bool isError,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final colorScheme = theme.colorScheme;

    messenger.showSnackBar(
      SnackBar(
        duration: duration ?? _defaultDuration,
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        ),
        action: action,
        content: Row(
          children: [
            if (isError) ...[
              Icon(Icons.error_outline, color: colorScheme.error),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
