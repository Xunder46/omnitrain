import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';

/// A TextField wrapper that displays a "Done" accessory bar above the numeric keyboard.
///
/// The Done bar appears only when this field is focused and contains a button that
/// dismisses the keyboard and unfocuses the field. The Done bar does not appear on web.
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
  });

  @override
  State<NumericFieldWithDoneBar> createState() => _NumericFieldWithDoneBarState();
}

class _NumericFieldWithDoneBarState extends State<NumericFieldWithDoneBar> {
  FocusNode? _internalFocusNode;
  late final FocusNode _effectiveFocusNode;
  OverlayEntry? _doneBarEntry;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
    }
    _effectiveFocusNode = widget.focusNode ?? _internalFocusNode!;

    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
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
                        borderRadius:
                            BorderRadius.circular(OmniTheme.buttonUtilityRadius),
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
