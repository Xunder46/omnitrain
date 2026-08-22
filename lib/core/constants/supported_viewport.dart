import 'package:flutter/widgets.dart';

/// The smallest portrait viewport supported by the app.
///
/// Screens below this floor are explicitly unsupported; do not add
/// size-specific handling for them.
class SupportedViewport {
  static const double minWidth = 360;
  static const double minHeight = 640;
  static const Size minimumSize = Size(minWidth, minHeight);
}
