import 'package:flutter/services.dart';

/// Plan 242: typed decimals accept a comma as well as a point.
///
/// A phone set to a comma-decimal language (German, French, Spanish,
/// Russian, ...) shows a comma on its decimal keypad. Every number box in
/// the app reads typed text through [parseDecimal], and every free-typed
/// decimal box filters its keys with [DecimalInputFormatter], so `2,5`
/// means 2.5 everywhere. The text on screen stays exactly as typed.

/// Parses typed decimal text; a single comma counts as the decimal point.
///
/// Returns `null` for anything that is not one plain number. Text that has
/// both a point and a comma (`1,234.5`) is ambiguous and returns `null`, as
/// does more than one comma. A leading `+` is not accepted (callers that
/// allow it strip it first).
double? parseDecimal(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  // Only the first comma becomes a point, so a second comma, or a comma
  // beside a point, leaves a second separator and fails to parse.
  return double.tryParse(trimmed.replaceFirst(',', '.'));
}

/// Keeps only digits and at most one decimal separator (`.` or `,`);
/// optionally caps the digits after the separator.
///
/// An edit that would break the rule is rejected whole (the old text stays),
/// the same way the older per-field filters behaved.
class DecimalInputFormatter extends TextInputFormatter {
  const DecimalInputFormatter({this.maxFractionDigits});

  /// When set, an edit leaving more digits than this after the separator is
  /// rejected.
  final int? maxFractionDigits;

  static final RegExp _allowed = RegExp(r'^\d*[.,]?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (!_allowed.hasMatch(text)) return oldValue;
    final limit = maxFractionDigits;
    if (limit != null) {
      final sep = text.indexOf(RegExp(r'[.,]'));
      if (sep >= 0 && text.length - sep - 1 > limit) return oldValue;
    }
    return newValue;
  }
}
