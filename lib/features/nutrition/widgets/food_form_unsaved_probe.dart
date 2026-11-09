// filepath: lib/features/nutrition/widgets/food_form_unsaved_probe.dart

import 'package:flutter/material.dart';

/// Unsaved-work probe for the screens that host a `FoodForm`.
///
/// `FoodForm` owns its controllers and its dropdown selections privately,
/// so a host cannot ask it whether the user changed anything. What a host
/// *can* read is what the form renders: every field is a keyed
/// [FormField] whose state carries the live value
/// ([FormFieldState.value] — a text field's controller text, a dropdown's
/// selection). The probe remembers the first value it sees per field key
/// and reports a later difference as unsaved work. A text field it has
/// seen also gets a controller listener, so typing still counts after the
/// field has scrolled out of the build window and its element is gone.
///
/// One probe serves every host: New Food, the legacy library edit shim and
/// `EditFoodScreen`, so the three guards cannot drift apart.
class FoodFormUnsavedProbe {
  FoodFormUnsavedProbe(this._formKey, {this.initialImagePath});

  /// Key on the host's `FoodForm`; it is the root of the field walk.
  final GlobalKey _formKey;

  /// The stored food's photo path when the screen opened; null for a
  /// create-mode form. Comparing against it is what makes a pick dirty an
  /// empty form while a pick-then-clear leaves it clean.
  final String? initialImagePath;

  /// First value seen per rendered field key (the untouched baseline).
  final Map<Key, Object?> _firstSeen = <Key, Object?>{};

  /// Text controllers already hooked; holding them keeps a typing signal
  /// alive after the field's element has been disposed.
  final Set<TextEditingController> _hooked = <TextEditingController>{};
  bool _typed = false;

  /// Latest photo path reported through `FoodForm.onImageChanged`; only
  /// meaningful once [_imageChanged] is true.
  bool _imageChanged = false;
  String? _reportedImagePath;

  /// Record a change to the form-local photo, reported by
  /// `FoodForm.onImageChanged` as the new path (null when cleared). The
  /// photo tile is neither a rendered [FormField] nor an [EditableText], so
  /// a pick or a clear is invisible to [_renderedFields] and would
  /// otherwise be dropped on the way out.
  void markImageChanged(String? path) {
    _imageChanged = true;
    _reportedImagePath = path;
  }

  bool _servingChanged = false;

  /// Record a change to how the food is measured (reported by
  /// `FoodForm.onServingChanged`). The serving toggle and chips are not
  /// rendered [FormField]s, and the serving-name and package-size boxes
  /// only appear after the toggle moves, so none of them is reachable
  /// through [_renderedFields].
  void markServingChanged() => _servingChanged = true;

  /// True when the form carries work the user has not saved.
  bool get isDirty {
    if (_typed || _servingChanged) return true;
    if (_imageChanged && _reportedImagePath != initialImagePath) return true;
    for (final field in _renderedFields()) {
      if (_firstSeen.containsKey(field.key) &&
          field.value != _firstSeen[field.key]) {
        return true;
      }
    }
    return false;
  }

  /// Record the values the form currently renders as the untouched
  /// baseline. Called once the form has laid out, and again after every
  /// scroll, so a field that scrolls into the build window is baselined
  /// before the user can type into it.
  void record() {
    for (final field in _renderedFields()) {
      _firstSeen.putIfAbsent(field.key, () => field.value);
      final controller = field.controller;
      if (controller != null && _hooked.add(controller)) {
        controller.addListener(_onTyped);
      }
    }
  }

  void _onTyped() => _typed = true;

  /// Release the controller hooks. [ChangeNotifier.removeListener] is safe
  /// on a controller `FoodForm` has already disposed.
  void dispose() {
    for (final controller in _hooked) {
      controller.removeListener(_onTyped);
    }
    _hooked.clear();
  }

  /// Every keyed [FormField] the form currently renders.
  List<_RenderedField> _renderedFields() {
    final root = _formKey.currentContext;
    if (root == null) return const <_RenderedField>[];
    final fields = <_RenderedField>[];

    void visit(Element element) {
      final widget = element.widget;
      if (widget is FormField) {
        final state = element is StatefulElement ? element.state : null;
        if (widget.key != null && state is FormFieldState<Object?>) {
          fields.add(
            _RenderedField(widget.key!, state.value, _controllerOf(element)),
          );
        }
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return fields;
  }

  /// The text controller a rendered text field edits, or null when the
  /// field is not a text field.
  TextEditingController? _controllerOf(Element field) {
    TextEditingController? controller;

    void visit(Element element) {
      final widget = element.widget;
      if (widget is EditableText) {
        controller = widget.controller;
        return;
      }
      element.visitChildren(visit);
    }

    field.visitChildElements(visit);
    return controller;
  }
}

/// A [FormField] the form renders, reduced to what the probe compares: the
/// value the user sees and the controller behind it.
class _RenderedField {
  const _RenderedField(this.key, this.value, this.controller);

  final Key key;
  final Object? value;
  final TextEditingController? controller;
}
