// The wrist's empty food list names the phone's "Choose foods" button
// (plan 78, S-13121). The Dart screen mirrors the Swift view
// (`WatchNutritionView.swift`, guarded by S-13120 in
// `WatchNutritionWiringSourceTests.swift`).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S-13121: the Dart wrist screen prints the Choose foods line', () {
    final source = File(
      'lib/watch/nutrition/watch_nutrition_screen.dart',
    ).readAsStringSync();
    expect(
      source.contains(
        "'No foods yet. On your phone, open Nutrition and tap Choose foods.',",
      ),
      isTrue,
      reason: 'the empty list must name the phone button',
    );
    expect(
      source.contains('Sync with your phone to get them'),
      isFalse,
      reason: 'the old sync line must be gone',
    );
  });
}
