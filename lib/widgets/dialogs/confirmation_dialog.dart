import 'package:flutter/material.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';

/// A consolidated two-choice confirmation dialog: proceed/dismiss (returns
/// bool). The unsaved-changes prompt is the same dialog with fixed labels
/// ([ConfirmationDialog.showUnsavedChanges]); it has no Save action, because
/// every form it guards already has its own Save button, and three actions do
/// not fit one row on a phone (owner decision, 2026-10-18).
///
/// Two-tier classification: destructive (error-colored confirm button) vs
/// routine (primary-colored confirm button).
///
/// Layout (owner decision, 2026-10-13): title and body text, then
/// right-aligned content-width action buttons in the order dismissal,
/// confirming. There is no X control in the title, so the dismissal action is
/// visible by name.
///
/// Each action's style comes from [_dialogActionStyle].
///
/// Barrier dismissal contract: barrier tap returns null, coalesces to false.
///
/// All action buttons use [OmniTheme.buttonUtilityRadius] (8.0).
enum ThreeChoice { cancel, first, second }

class ConfirmationDialog {
  /// Shows a three-choice scope dialog: a repeating-series row can be acted
  /// on alone ([ThreeChoice.first]) or together with the rest of its series
  /// ([ThreeChoice.second]); [ThreeChoice.cancel] covers the cancel action,
  /// a barrier tap and the back gesture (showDialog null coalesces to
  /// cancel). This helper is for that scope choice only: the unsaved-changes
  /// prompt stays two-choice (owner decision, 2026-10-18, is about THAT
  /// prompt — it has no Save action and never gained a third choice).
  ///
  /// Action order: [cancelLabel] (TextButton), [firstLabel] (OutlinedButton),
  /// [secondLabel] (FilledButton; error pair when [isDestructive]). Three
  /// actions do not fit one row on a phone, so the actions stack downward
  /// when the row is too narrow.
  static Future<ThreeChoice> showThreeChoice({
    required BuildContext context,
    required String title,
    Widget? body,
    required String firstLabel,
    required String secondLabel,
    required String cancelLabel,
    required Key firstKey,
    required Key secondKey,
    required Key cancelKey,
    required bool isDestructive,
  }) async {
    final result = await showDialog<ThreeChoice>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ThreeChoiceDialog(
        title: title,
        body: body,
        firstLabel: firstLabel,
        secondLabel: secondLabel,
        cancelLabel: cancelLabel,
        firstKey: firstKey,
        secondKey: secondKey,
        cancelKey: cancelKey,
        isDestructive: isDestructive,
      ),
    );
    return result ?? ThreeChoice.cancel;
  }

  /// Constructs a three-choice confirmation dialog widget.
  ///
  /// Prefer [showThreeChoice] for automatic barrier-dismissal coalescing.
  /// This builder is primarily for testing.
  static Widget threeChoice({
    required String title,
    Widget? body,
    required String firstLabel,
    required String secondLabel,
    required String cancelLabel,
    required Key firstKey,
    required Key secondKey,
    required Key cancelKey,
    required bool isDestructive,
  }) {
    return _ThreeChoiceDialog(
      title: title,
      body: body,
      firstLabel: firstLabel,
      secondLabel: secondLabel,
      cancelLabel: cancelLabel,
      firstKey: firstKey,
      secondKey: secondKey,
      cancelKey: cancelKey,
      isDestructive: isDestructive,
    );
  }

  /// Shows a two-choice confirmation dialog with barrier-dismissal coalescing.
  ///
  /// Returns [Future<bool>]: true = confirm, false = dismiss/barrier/cancel.
  /// Barrier tap yields null, which is coalesced to false.
  ///
  /// [body] is optional; if omitted, dialog lays out with title and buttons only.
  ///
  /// [isDestructive] true: confirm button filled with error color.
  /// [isDestructive] false: confirm button filled with primary color.
  static Future<bool> showTwoChoice({
    required BuildContext context,
    required String title,
    Widget? body,
    required String dismissLabel,
    required String confirmLabel,
    required Key dismissKey,
    required Key confirmKey,
    required bool isDestructive,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _TwoChoiceDialog(
        title: title,
        body: body,
        dismissLabel: dismissLabel,
        confirmLabel: confirmLabel,
        dismissKey: dismissKey,
        confirmKey: confirmKey,
        isDestructive: isDestructive,
      ),
    );
    return result ?? false;
  }

  /// Shows the unsaved-changes prompt: "Keep editing" / "Discard".
  ///
  /// Returns true when the user chose Discard; false for Keep editing, the
  /// barrier or back.
  static Future<bool> showUnsavedChanges({
    required BuildContext context,
    required String title,
    required String body,
    required Key keepEditingKey,
    required Key discardKey,
  }) {
    return showTwoChoice(
      context: context,
      title: title,
      body: Text(body),
      dismissLabel: 'Keep editing',
      confirmLabel: 'Discard',
      dismissKey: keepEditingKey,
      confirmKey: discardKey,
      isDestructive: true,
    );
  }

  /// Constructs a two-choice confirmation dialog widget.
  ///
  /// Prefer [showTwoChoice] for automatic barrier-dismissal coalescing.
  /// This builder is primarily for testing.
  static Widget twoChoice({
    required String title,
    Widget? body,
    required String dismissLabel,
    required String confirmLabel,
    required Key dismissKey,
    required Key confirmKey,
    required bool isDestructive,
  }) {
    return _TwoChoiceDialog(
      title: title,
      body: body,
      dismissLabel: dismissLabel,
      confirmLabel: confirmLabel,
      dismissKey: dismissKey,
      confirmKey: confirmKey,
      isDestructive: isDestructive,
    );
  }
}

/// The one shape every [ConfirmationDialog] action uses (D-26.2): a
/// content-width rounded rectangle at [OmniTheme.buttonUtilityRadius].
WidgetStateProperty<OutlinedBorder?> _dialogActionShape() =>
    WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
      ),
    );

/// The one action-button style the dialog actions use:
/// [shape] plus the error pair when [isDestructive], the theme defaults
/// otherwise.
///
/// [shape] is passed in rather than built here so every call site spells
/// `shape:` in its own text — the S-2601 scan in
/// `test/ui_standards_contract_test.dart` reads a button's call, not the
/// helper it delegates to.
ButtonStyle _dialogActionStyle({
  required ColorScheme colorScheme,
  required WidgetStateProperty<OutlinedBorder?> shape,
  bool isDestructive = false,
}) {
  return ButtonStyle(
    shape: shape,
    backgroundColor: isDestructive
        ? WidgetStateProperty.all(colorScheme.error)
        : null,
    foregroundColor: isDestructive
        ? WidgetStateProperty.all(colorScheme.onError)
        : null,
  );
}

/// Implementation of two-choice confirmation dialog using AlertDialog.
class _TwoChoiceDialog extends StatelessWidget {
  const _TwoChoiceDialog({
    required this.title,
    this.body,
    required this.dismissLabel,
    required this.confirmLabel,
    required this.dismissKey,
    required this.confirmKey,
    required this.isDestructive,
  });

  final String title;
  final Widget? body;
  final String dismissLabel;
  final String confirmLabel;
  final Key dismissKey;
  final Key confirmKey;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: body,
      actions: [
        // Dismissal action first
        TextButton(
          key: dismissKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
          ),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(dismissLabel),
        ),
        // Confirming action last
        FilledButton(
          key: confirmKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
            isDestructive: isDestructive,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Implementation of three-choice confirmation dialog using AlertDialog.
///
/// Actions in the order [cancelLabel] (TextButton), [firstLabel]
/// (OutlinedButton), [secondLabel] (FilledButton; error pair when
/// [isDestructive]). Three actions do not fit one row on a phone, so they
/// stack downward (`actionsOverflowDirection`,
/// `actionsOverflowButtonSpacing`) when the row is too narrow. Barrier tap
/// and the back gesture pop null, which [ConfirmationDialog.showThreeChoice]
/// coalesces to [ThreeChoice.cancel].
class _ThreeChoiceDialog extends StatelessWidget {
  const _ThreeChoiceDialog({
    required this.title,
    this.body,
    required this.firstLabel,
    required this.secondLabel,
    required this.cancelLabel,
    required this.firstKey,
    required this.secondKey,
    required this.cancelKey,
    required this.isDestructive,
  });

  final String title;
  final Widget? body;
  final String firstLabel;
  final String secondLabel;
  final String cancelLabel;
  final Key firstKey;
  final Key secondKey;
  final Key cancelKey;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: body,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        // Cancel action first
        TextButton(
          key: cancelKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
          ),
          onPressed: () => Navigator.of(context).pop(ThreeChoice.cancel),
          child: Text(cancelLabel),
        ),
        // "Just this one"
        OutlinedButton(
          key: firstKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
          ),
          onPressed: () => Navigator.of(context).pop(ThreeChoice.first),
          child: Text(firstLabel),
        ),
        // "This and all after it"
        FilledButton(
          key: secondKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
            isDestructive: isDestructive,
          ),
          onPressed: () => Navigator.of(context).pop(ThreeChoice.second),
          child: Text(secondLabel),
        ),
      ],
    );
  }
}
