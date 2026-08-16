import 'package:flutter/material.dart';
import 'dart:math' as math;

/// WCAG 2.1 contrast ratio helpers used by contrast verification tests.

double _linearizeChannel(double c) {
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  final r = _linearizeChannel(color.red / 255);
  final g = _linearizeChannel(color.green / 255);
  final b = _linearizeChannel(color.blue / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Calculate the relative luminance contrast ratio between two colors.
///
/// Returns a value between 1 and 21, where 1 is no contrast and 21 is maximum.
double contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}
