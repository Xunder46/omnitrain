/// The Wear wrist's session menu screen (plan 281).
///
/// The Dart counterpart of `WatchMenuView.swift`: one row per exercise (a jump),
/// then Add Exercise, End Session and Discard Session. There is no remove
/// control (D-28102). While a work clock runs the exercise rows are disabled
/// and the caption says why; a running rest never locks them. The screen
/// refreshes itself once a second so a clock the phone stopped, a slot the
/// phone removed, or a session the phone ended is noticed (D-28109).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../session/watch_records.dart';
import '../start/watch_exercise_picker.dart';
import '../start/watch_start_screen.dart';
import 'watch_menu_state.dart';

class WatchMenuScreen extends StatefulWidget {
  const WatchMenuScreen({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final WatchMenuState state;

  /// Called after anything the menu did that the shell must redraw: a jump, an
  /// add, an End or a Discard, or the session ending under the menu.
  final VoidCallback onChanged;

  static const double surfaceInset = 8;
  static const double rowGap = 4;

  @override
  State<WatchMenuScreen> createState() => _WatchMenuScreenState();
}

class _WatchMenuScreenState extends State<WatchMenuScreen> {
  static const Duration _refresh = Duration(seconds: 1);

  Timer? _ticker;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_refresh, (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted || _closing) return;
    if (widget.state.engine.session?.status != WatchSessionStatus.active) {
      _closeToStart();
      return;
    }
    setState(() {});
  }

  /// Back to the shell's first route (the start surface once the session is
  /// over), closing a dialog or the Add list that sits above the menu too.
  void _closeToStart() {
    if (_closing) return;
    _closing = true;
    _ticker?.cancel();
    widget.onChanged();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _jump(WatchMenuRow row) async {
    final moved = await widget.state.jump(row.slotId);
    if (!mounted || !moved) return;
    widget.onChanged();
    Navigator.of(context).pop();
  }

  Future<void> _add() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => WatchExercisePickerScreen(
          paths: widget.state.paths,
          keepPosition: true,
          onExerciseAdded: (_) {
            if (mounted) setState(() {});
            widget.onChanged();
          },
        ),
      ),
    );
  }

  Future<void> _end() async {
    final finish = widget.state.hasWorkToSave;
    final confirmed = await _confirm(
      title: finish
          ? WatchMenuCopy.confirmTitle
          : WatchMenuCopy.discardConfirmTitle,
      body: finish
          ? WatchMenuCopy.confirmBody
          : WatchMenuCopy.discardConfirmBody,
      cancel: finish
          ? WatchMenuCopy.confirmCancel
          : WatchMenuCopy.discardConfirmCancel,
      action: finish
          ? WatchMenuCopy.confirmFinish
          : WatchMenuCopy.discardConfirmDiscard,
      destructive: !finish,
    );
    if (!confirmed || !mounted) return;
    await widget.state.finish();
    if (mounted) _closeToStart();
  }

  Future<void> _discard() async {
    final confirmed = await _confirm(
      title: WatchMenuCopy.discardConfirmTitle,
      body: WatchMenuCopy.discardConfirmBody,
      cancel: WatchMenuCopy.discardConfirmCancel,
      action: WatchMenuCopy.discardConfirmDiscard,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await widget.state.discard();
    if (mounted) _closeToStart();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String cancel,
    required String action,
    required bool destructive,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmScreen(
        title: title,
        body: body,
        cancel: cancel,
        action: action,
        destructive: destructive,
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final rows = state.rows;
    final locked = state.isLocked;
    final theme = Theme.of(context);
    final shape = WidgetStateProperty.all<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
      ),
    );
    final minimum = WidgetStateProperty.all<Size>(
      const Size.fromHeight(OmniTheme.buttonPrimaryHeight),
    );

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: WatchMenuScreen.surfaceInset,
            vertical: 4,
          ),
          children: [
            for (final row in rows) ...[
              _ExerciseRow(
                row: row,
                enabled: !locked,
                shape: shape,
                minimum: minimum,
                onPressed: () => _jump(row),
              ),
              const SizedBox(height: WatchMenuScreen.rowGap),
            ],
            if (locked)
              Padding(
                padding: const EdgeInsets.only(bottom: WatchMenuScreen.rowGap),
                child: Text(
                  WatchMenuCopy.lockedCaption,
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ),
            WatchUtilityButton(
              label: WatchMenuCopy.addExerciseLabel,
              onPressed: _add,
            ),
            const SizedBox(height: WatchMenuScreen.rowGap),
            WatchUtilityButton(
              label: WatchMenuCopy.finishLabel,
              onPressed: _end,
            ),
            const SizedBox(height: WatchMenuScreen.rowGap),
            OutlinedButton(
              style: ButtonStyle(
                shape: shape,
                minimumSize: minimum,
                foregroundColor: WidgetStateProperty.all(theme.colorScheme.error),
                side: WidgetStateProperty.all(
                  BorderSide(color: theme.colorScheme.error),
                ),
              ),
              onPressed: _discard,
              child: const Text(WatchMenuCopy.discardLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// One exercise row: the name, `N logged` under it when N is above zero, and
/// the current exercise's row drawn as the prominent one.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.row,
    required this.enabled,
    required this.shape,
    required this.minimum,
    required this.onPressed,
  });

  final WatchMenuRow row;
  final bool enabled;
  final WidgetStateProperty<OutlinedBorder> shape;
  final WidgetStateProperty<Size> minimum;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (row.countLabel != null)
          Text(row.countLabel!, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
    final style = ButtonStyle(shape: shape, minimumSize: minimum);
    final callback = enabled ? onPressed : null;
    return row.isCurrent
        ? FilledButton.tonal(style: style, onPressed: callback, child: label)
        : OutlinedButton(style: style, onPressed: callback, child: label);
  }
}

/// The Finish / Discard question as a full-screen, scrollable page: a watch has
/// no room for a centred dialog (the stock `AlertDialog` cuts the body and the
/// buttons off at 227 dp and is unreadable at 192 dp). Pops `true` for the
/// action and `false` for Cancel.
class _ConfirmScreen extends StatelessWidget {
  const _ConfirmScreen({
    required this.title,
    required this.body,
    required this.cancel,
    required this.action,
    required this.destructive,
  });

  final String title;
  final String body;
  final String cancel;
  final String action;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = WidgetStateProperty.all<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
      ),
    );
    final minimum = WidgetStateProperty.all<Size>(
      const Size.fromHeight(OmniTheme.buttonPrimaryHeight),
    );
    return Dialog.fullscreen(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: WatchMenuScreen.surfaceInset,
              vertical: 4,
            ),
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: WatchMenuScreen.rowGap),
              Text(
                body,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: WatchMenuScreen.rowGap * 2),
              OutlinedButton(
                style: ButtonStyle(shape: shape, minimumSize: minimum),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(cancel),
              ),
              const SizedBox(height: WatchMenuScreen.rowGap),
              FilledButton(
                style: ButtonStyle(
                  shape: shape,
                  minimumSize: minimum,
                  backgroundColor: destructive
                      ? WidgetStateProperty.all(theme.colorScheme.error)
                      : null,
                  foregroundColor: destructive
                      ? WidgetStateProperty.all(theme.colorScheme.onError)
                      : null,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
