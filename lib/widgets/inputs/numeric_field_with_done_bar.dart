import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import 'select_all_on_focus.dart';

/// A TextField wrapper that displays a "Done" accessory bar above the numeric keyboard.
///
/// The Done bar appears only when this field is focused and contains a button that
/// dismisses the keyboard and unfocuses the field. The Done bar does not appear on web.
///
/// By default the wrapper also selects the full current contents on focus
/// (see [selectAllOnFocus]). This is the right behavior for value-entry
/// fields (weight, reps, durations, logged amounts, body measurements,
/// height) where the user's intent on focus is to overwrite the existing
/// value in one tap. Pass `selectAllOnFocus: false` to disable per
/// instance — the caller is then responsible for the field's selection
/// behavior.
///
/// This widget passes through all TextField properties and behavior unchanged.
class NumericFieldWithDoneBar extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType keyboardType;
  final InputDecoration? decoration;
  final TextAlign textAlign;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final bool? enabled;
  final TextCapitalization textCapitalization;

  /// When true (default) and this wrapper creates its own internal
  /// [FocusNode] (i.e. the caller did not pass one in), the wrapper
  /// selects the full contents of [controller] on focus gain. The
  /// behavior is skipped when an external [focusNode] is provided —
  /// the caller's node is used as-is and the caller is responsible
  /// for any selection behavior on it.
  final bool selectAllOnFocus;

  /// When true, the field requests focus as soon as it is built. Combined
  /// with [selectAllOnFocus] (default true), this immediately highlights
  /// the current value so the user can start typing without an extra tap
  /// — the right behavior for fields inside a modal/dialog whose entire
  /// purpose is editing this one value.
  final bool autofocus;

  const NumericFieldWithDoneBar({
    super.key,
    this.controller,
    this.focusNode,
    this.keyboardType = TextInputType.number,
    this.decoration,
    this.textAlign = TextAlign.start,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.obscureText = false,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.enabled,
    this.textCapitalization = TextCapitalization.none,
    this.selectAllOnFocus = true,
    this.autofocus = false,
  });

  @override
  State<NumericFieldWithDoneBar> createState() =>
      _NumericFieldWithDoneBarState();
}

class _NumericFieldWithDoneBarState extends State<NumericFieldWithDoneBar> {
  FocusNode? _internalFocusNode;
  late final FocusNode _effectiveFocusNode;
  OverlayEntry? _doneBarEntry;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      // When we own the focus node, use a SelectAllOnFocusNode so
      // the wrapper's value-entry contract (select-all on focus) is
      // honored for the common case where the caller did not pass a
      // controller-aware focus node. We need a controller to bind
      // the select-all listener; if the caller did not provide one,
      // we fall back to a plain FocusNode and the caller can
      // opt-in via `selectAllOnFocus: false` plus their own
      // SelectAllOnFocus / SelectAllOnFocusNode.
      if (widget.selectAllOnFocus && widget.controller != null) {
        _internalFocusNode = SelectAllOnFocusNode(
          selectAllController: widget.controller!,
        );
      } else {
        _internalFocusNode = FocusNode();
      }
    }
    _effectiveFocusNode = widget.focusNode ?? _internalFocusNode!;

    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    // SelectAllOnFocusNode detaches its own listener on dispose,
    // so disposing the underlying FocusNode is sufficient for both
    // the select-all variant and the plain FocusNode fallback.
    _internalFocusNode?.dispose();
    _doneBarEntry?.remove();
    _doneBarEntry = null;
    super.dispose();
  }

  void _handleFocusChange() {
    if (_effectiveFocusNode.hasFocus && !kIsWeb) {
      _showDoneBar();
    } else {
      _hideDoneBar();
    }
  }

  void _showDoneBar() {
    _hideDoneBar();

    // Use WidgetsBinding to ensure the overlay is shown after keyboard is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_effectiveFocusNode.hasFocus || kIsWeb) return;

      _doneBarEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).viewInsets.bottom,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 0,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          OmniTheme.buttonUtilityRadius,
                        ),
                      ),
                    ),
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                    child: const Text('Done'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      );

      Overlay.of(context).insert(_doneBarEntry!);
    });
  }

  void _hideDoneBar() {
    _doneBarEntry?.remove();
    _doneBarEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _effectiveFocusNode,
      keyboardType: widget.keyboardType,
      decoration: widget.decoration,
      textAlign: widget.textAlign,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onEditingComplete: widget.onEditingComplete,
      onSubmitted: widget.onSubmitted,
      obscureText: widget.obscureText,
      textInputAction: widget.textInputAction,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      enabled: widget.enabled,
      textCapitalization: widget.textCapitalization,
    );
  }
}
