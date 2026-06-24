import 'package:omnitrain/core/constants/omni_theme.dart';

/// Computes the centered content column's geometry for a given
/// surface width, mirroring the production cap in
/// `OmniGradientBackground`. Returns the column's left edge and
/// width — both measured from the surface's left edge.
///
/// Tests use this to assert the centered-column contract on a
/// phone-class surface (column fills the surface) and on a
/// tablet-class surface (column is `kColumnMaxWidth` dp wide and
/// horizontally centered) with a single helper.
({double left, double width}) contentColumnRectFor(double surfaceWidth) {
  if (surfaceWidth < OmniTheme.kColumnMinActivationWidth) {
    return (left: 0.0, width: surfaceWidth);
  }
  final width = OmniTheme.kColumnMaxWidth;
  return (left: (surfaceWidth - width) / 2, width: width);
}
