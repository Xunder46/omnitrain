// Plan 80 / S-14001, S-14002 — macro target helpers in
// `lib/core/utils/macro_targets.dart`. Plain state tests, no widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/macro_targets.dart';

void main() {
  group('defaultMacroTargets (S-14001)', () {
    test('2000 kcal → 150/200/67', () {
      expect(
        defaultMacroTargets(2000),
        const MacroTargets(protein: 150, carbs: 200, fat: 67),
      );
    });

    test('2400 kcal → 180/240/80', () {
      expect(
        defaultMacroTargets(2400),
        const MacroTargets(protein: 180, carbs: 240, fat: 80),
      );
    });

    test('1850 kcal → 139/185/62', () {
      expect(
        defaultMacroTargets(1850),
        const MacroTargets(protein: 139, carbs: 185, fat: 62),
      );
    });

    test('0 kcal → all zeros', () {
      expect(
        defaultMacroTargets(0),
        const MacroTargets(protein: 0, carbs: 0, fat: 0),
      );
    });

    test('negative calories → all zeros', () {
      expect(
        defaultMacroTargets(-5),
        const MacroTargets(protein: 0, carbs: 0, fat: 0),
      );
    });
  });

  group('impliedCalories (S-14002)', () {
    test('150/200/67 → 2003', () {
      expect(impliedCalories(protein: 150, carbs: 200, fat: 67), 2003);
    });

    test('180/240/80 → 2400', () {
      expect(impliedCalories(protein: 180, carbs: 240, fat: 80), 2400);
    });

    test('protein only → 4 kcal per gram', () {
      expect(impliedCalories(protein: 100), 400);
    });

    test('fat only → 9 kcal per gram', () {
      expect(impliedCalories(fat: 10), 90);
    });

    test('no macros → 0', () {
      expect(impliedCalories(), 0);
    });
  });

  group('round trip', () {
    test('impliedCalories of the 2400 split is exactly 2400', () {
      final split = defaultMacroTargets(2400);
      expect(
        impliedCalories(
          protein: split.protein.toDouble(),
          carbs: split.carbs.toDouble(),
          fat: split.fat.toDouble(),
        ),
        2400,
      );
    });

    test('impliedCalories of the 1850 split is 1854 (rounded grams)', () {
      final split = defaultMacroTargets(1850);
      expect(
        impliedCalories(
          protein: split.protein.toDouble(),
          carbs: split.carbs.toDouble(),
          fat: split.fat.toDouble(),
        ),
        1854,
      );
    });
  });
}
