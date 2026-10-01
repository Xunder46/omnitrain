import 'package:flutter/widgets.dart';

/// A widget wrapper that, when its child field is focused, selects the
/// entire current contents of the supplied [controller].
///
/// Use this for value-entry fields (weight, reps, durations, logged
/// amounts, body measurements, height, calories target) where the user's
/// intent on focus is to overwrite the existing value in one tap. Do NOT
/// use this for multi-line or free-text fields (notes, names,
/// descriptions) — selecting everything on focus would be a nuisance and
/// would break the user's ability to position the cursor freely.
///
/// The wrapper manages a [FocusNode] internally (created in `initState`,
/// disposed in `dispose`) unless the caller passes one via [focusNode].
/// The internal listener selects the full text in a post-frame callback
/// after focus is gained, so Flutter's focus machinery has time to settle
/// before the selection is overridden. The selection is re-applied on
/// every focus gain, not just the first one — so re-focusing a field
/// after blur still highlights the value.
///
/// The user can still place the cursor manually: select-all is a
/// one-shot focus event. Any subsequent tap inside the field moves the
/// cursor to the tapped position via Flutter's standard selection model.
class SelectAllOnFocus extends StatefulWidget {
  /// The controller whose text will be selected on focus. Required.
  final TextEditingController controller;

  /// Optional externally-managed focus node. If `null`, the wrapper
  /// creates and disposes its own [FocusNode]. Pass an external node
  /// when the caller already owns one (e.g. to share focus state with
  /// other widgets).
  final FocusNode? focusNode;

  /// Builds the child widget that consumes the managed [FocusNode]. The
  /// builder receives the [BuildContext] and the [FocusNode] the
  /// wrapper has wired up; the caller is responsible for passing the
  /// node to its `TextField` / `TextFormField`.
  final Widget Function(BuildContext context, FocusNode focusNode) builder;

  const SelectAllOnFocus({
    super.key,
    required this.controller,
    required this.builder,
    this.focusNode,
  });

  @override
  State<SelectAllOnFocus> createState() => _SelectAllOnFocusState();
}

class _SelectAllOnFocusState extends State<SelectAllOnFocus> {
  FocusNode? _internalFocusNode;
  late final FocusNode _effectiveFocusNode;
  late final TextEditingController _trackedController;
  bool _ownsController = false;
  VoidCallback? _detachListener;

  @override
  void initState() {
    super.initState();
    _trackedController = widget.controller;
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode();
      _ownsController = true;
    }
    _effectiveFocusNode = widget.focusNode ?? _internalFocusNode!;
    _detachListener = bindSelectAllOnFocus(
      focusNode: _effectiveFocusNode,
      controller: _trackedController,
    );
  }

  @override
  void dispose() {
    _detachListener?.call();
    if (_ownsController) {
      _internalFocusNode?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _effectiveFocusNode);
  }
}

/// A [FocusNode] that selects the full contents of
/// [selectAllController] whenever it gains focus.
///
/// Drop-in replacement for `FocusNode` for value-entry fields whose
/// caller already owns a [FocusNode] (e.g. a form with multiple named
/// nodes). The selection is re-applied on every focus gain in a
/// post-frame callback, so Flutter's focus machinery has time to settle
/// before the selection is overridden.
///
/// The user can still place the cursor manually: select-all is a
/// one-shot focus event. Any subsequent tap inside the field moves the
/// cursor to the tapped position via Flutter's standard selection model.
///
/// Dispose the node in the calling widget's `State.dispose` — the
/// listener is detached automatically.
class SelectAllOnFocusNode extends FocusNode {
  SelectAllOnFocusNode({required TextEditingController selectAllController})
    : _controller = selectAllController {
    _detachListener = bindSelectAllOnFocus(
      focusNode: this,
      controller: _controller,
    );
  }

  final TextEditingController _controller;
  VoidCallback? _detachListener;

  @override
  void dispose() {
    _detachListener?.call();
    super.dispose();
  }
}

/// Wires a focus listener on [focusNode] that, when focus is gained,
/// schedules a post-frame callback to select the full text in
/// [controller]. Empty values are a no-op (Flutter's selection model
/// handles them, but skipping the assignment keeps cursor behavior
/// predictable for empty fields).
///
/// Returns a function the caller can invoke to detach the listener —
/// useful for the [SelectAllOnFocus] wrapper's `State.dispose` and
/// [SelectAllOnFocusNode.dispose`. Callers that prefer to manage the
/// listener manually can call this function from their own
/// `initState`/`dispose`.
VoidCallback bindSelectAllOnFocus({
  required FocusNode focusNode,
  required TextEditingController controller,
}) {
  void listener() {
    if (!focusNode.hasFocus) return;
    if (controller.text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-check both focus and text length in the post-frame
      // callback: the controller's text may have been mutated
      // (e.g. by `tester.enterText('')` or a programmatic
      // assignment) between the focus event and the frame
      // boundary, and the captured length would no longer match
      // the current value — `TextEditingController.selection=`
      // throws on an out-of-range selection.
      if (!focusNode.hasFocus) return;
      final length = controller.text.length;
      if (length == 0) return;
      controller.selection = TextSelection(baseOffset: 0, extentOffset: length);
    });
  }

  focusNode.addListener(listener);
  return () => focusNode.removeListener(listener);
}
