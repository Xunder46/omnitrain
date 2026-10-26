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
class ConfirmationDialog {
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
