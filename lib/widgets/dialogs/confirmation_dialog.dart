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
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonUtilityRadius,
                ),
              ),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(dismissLabel),
        ),
        // Confirming action last
        FilledButton(
          key: confirmKey,
          style: ButtonStyle(
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonUtilityRadius,
                ),
              ),
            ),
            backgroundColor: isDestructive
                ? WidgetStateProperty.all(theme.colorScheme.error)
                : null,
            foregroundColor: isDestructive
                ? WidgetStateProperty.all(theme.colorScheme.onError)
                : null,
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
      title: Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            key: keepEditingKey,
            icon: const Icon(Icons.close),
            tooltip: 'Keep editing',
            onPressed: () =>
                Navigator.of(context).pop(UnsavedChangesAction.keepEditing),
          ),
        ],
      ),
      content: Text(body),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: discardKey,
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                    side: WidgetStateProperty.all(
                      BorderSide(color: theme.colorScheme.error),
                    ),
                    foregroundColor: WidgetStateProperty.all(
                      theme.colorScheme.error,
                    ),
                  ),
                  onPressed: () =>
                      Navigator.of(context).pop(UnsavedChangesAction.discard),
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: saveKey,
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                  ),
                  onPressed: () =>
                      Navigator.of(context).pop(UnsavedChangesAction.save),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
