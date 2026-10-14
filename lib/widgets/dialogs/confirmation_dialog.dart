import 'package:flutter/material.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';

/// Enum returned by three-choice unsaved-changes confirmation dialogs.
enum UnsavedChangesAction { keepEditing, discard, save }

/// A consolidated confirmation dialog component supporting two shapes:
/// - Two-choice: proceed/dismiss (returns bool)
/// - Three-choice: keep-editing/discard/save (returns UnsavedChangesAction)
///
/// Two-tier classification: destructive (error-colored confirm button) vs
/// routine (primary-colored confirm button).
///
/// Both shapes lay out the same way (owner decision, 2026-10-13): title and
/// body text, then right-aligned action buttons in the order dismissal,
/// destructive, confirming. Actions stay content-width; `AlertDialog`'s
/// `OverflowBar` stacks them when the row does not fit. There is no X control
/// in either title, so the dismissal action is visible by name.
///
/// Each action's style comes from [_dialogActionStyle], so the two shapes
/// cannot drift apart.
///
/// Barrier dismissal contract:
/// - Two-choice: barrier tap returns null, coalesces to false
/// - Three-choice: barrier tap returns null, coalesces to keepEditing
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

  /// Shows a three-choice unsaved-changes confirmation dialog with barrier-dismissal coalescing.
  ///
  /// Returns [Future<UnsavedChangesAction>]: keepEditing, discard, or save.
  /// Barrier tap yields null, which is coalesced to keepEditing.
  static Future<UnsavedChangesAction> showUnsavedChanges({
    required BuildContext context,
    required String title,
    required String body,
    required Key keepEditingKey,
    required Key discardKey,
    required Key saveKey,
  }) async {
    final result = await showDialog<UnsavedChangesAction>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ThreeChoiceDialog(
        title: title,
        body: body,
        keepEditingKey: keepEditingKey,
        discardKey: discardKey,
        saveKey: saveKey,
      ),
    );
    return result ?? UnsavedChangesAction.keepEditing;
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

  /// Constructs a three-choice unsaved-changes confirmation dialog widget.
  ///
  /// Prefer [showUnsavedChanges] for automatic barrier-dismissal coalescing.
  /// This builder is primarily for testing.
  static Widget threeChoice({
    required String title,
    required String body,
    required Key keepEditingKey,
    required Key discardKey,
    required Key saveKey,
  }) {
    return _ThreeChoiceDialog(
      title: title,
      body: body,
      keepEditingKey: keepEditingKey,
      discardKey: discardKey,
      saveKey: saveKey,
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

/// The one action-button style both dialog shapes use, so they cannot drift:
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

/// Implementation of three-choice unsaved-changes dialog using AlertDialog.
class _ThreeChoiceDialog extends StatelessWidget {
  const _ThreeChoiceDialog({
    required this.title,
    required this.body,
    required this.keepEditingKey,
    required this.discardKey,
    required this.saveKey,
  });

  final String title;
  final String body;
  final Key keepEditingKey;
  final Key discardKey;
  final Key saveKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        // Dismissal action first, then the destructive one, then the
        // confirming one — the same order and styles as _TwoChoiceDialog.
        TextButton(
          key: keepEditingKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
          ),
          onPressed: () =>
              Navigator.of(context).pop(UnsavedChangesAction.keepEditing),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          key: discardKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
            isDestructive: true,
          ),
          onPressed: () =>
              Navigator.of(context).pop(UnsavedChangesAction.discard),
          child: const Text('Discard'),
        ),
        FilledButton(
          key: saveKey,
          style: _dialogActionStyle(
            colorScheme: theme.colorScheme,
            shape: _dialogActionShape(),
          ),
          onPressed: () => Navigator.of(context).pop(UnsavedChangesAction.save),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
