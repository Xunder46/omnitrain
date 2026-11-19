// Plan 92b D-92b.1..D-92b.4 — the only place the food form's serving
// answer becomes the three stored fields (`Food.unitType`,
// `referenceAmount`, `referenceLabel`) and back.
//
// Pure Dart: no Flutter import, never a text comparison. The choice is
// derived from numeric stored values, so a device round-trip that
// produces `100.0` / `1.0` loads exactly like `100` / `1`.
//
// Verified by `test/food_serving_test.dart` (group `food_serving`).
import '../../data/models/models.dart';
import 'food_helpers.dart';

/// What one food's nutrition numbers are per (D-92b.5's control).
sealed class ServingChoice {
  const ServingChoice();
}

/// 100 g.
final class Per100G extends ServingChoice {
  const Per100G();
}

/// 100 ml.
final class Per100Ml extends ServingChoice {
  const Per100Ml();
}

/// A package serving size entered by the user, e.g. 30 g or 250 ml.
final class PackageServing extends ServingChoice {
  const PackageServing({required this.amount, required this.label});

  final double amount;

  /// The unit the package size is in: `g` or `ml`.
  final String label;
}

/// One counted serving with the name the user gave it, e.g. `slice`.
final class NamedServing extends ServingChoice {
  const NamedServing({required this.label});

  final String label;
}

/// A stored serving the four choices cannot express; carried verbatim
/// so opening and saving such a food changes nothing.
final class AsSavedServing extends ServingChoice {
  const AsSavedServing({
    required this.unitType,
    required this.amount,
    required this.label,
  });

  final FoodUnitType unitType;
  final double amount;
  final String label;
}

/// The serving choice an existing food's stored triple loads as.
///
/// Rules, in order (D-92b.2):
/// 1. grams, amount exactly 100, label `g` -> [Per100G].
/// 2. grams, amount exactly 100, label `ml` -> [Per100Ml].
/// 3. grams, amount > 0 and not 100, label `g` or `ml` -> [PackageServing].
/// 4. count, amount exactly 1, label non-empty and already trimmed
///    -> [NamedServing].
/// 5. anything else (legacy `per 100g` labels, a count food whose amount
///    is not 1, an empty label, a non-positive or NaN amount)
///    -> [AsSavedServing] carrying the triple untouched.
///
/// Verified by `test/food_serving_test.dart` tests `S-92b.1 round trip
/// over every shipped catalog triple`, `S-92b.1 stored serving loads as
/// the matching choice` and `S-92b.1 odd stored servings load as As
/// saved`.
ServingChoice servingChoiceFrom(
  FoodUnitType unitType,
  double amount,
  String label,
) {
  if (unitType == FoodUnitType.grams) {
    if (amount == 100) {
      if (label == 'g') return const Per100G();
      if (label == 'ml') return const Per100Ml();
    } else if (amount > 0 && (label == 'g' || label == 'ml')) {
      return PackageServing(amount: amount, label: label);
    }
  } else if (amount == 1 && label.isNotEmpty && label == label.trim()) {
    return NamedServing(label: label);
  }
  return AsSavedServing(unitType: unitType, amount: amount, label: label);
}

/// The stored triple [choice] writes (D-92b.1).
///
/// [AsSavedServing] returns its carried triple untouched, so an odd
/// stored serving survives an open-and-save. Verified by
/// `test/food_serving_test.dart` tests `S-92b.1 round trip over the odd
/// stored servings` and `S-92b.1 each choice stores its triple`.
(FoodUnitType, double, String) storedServingFrom(ServingChoice choice) {
  switch (choice) {
    case Per100G():
      return (FoodUnitType.grams, 100, 'g');
    case Per100Ml():
      return (FoodUnitType.grams, 100, 'ml');
    case PackageServing(:final amount, :final label):
      return (FoodUnitType.grams, amount, label);
    case NamedServing(:final label):
      return (FoodUnitType.count, 1, label);
    case AsSavedServing(:final unitType, :final amount, :final label):
      return (unitType, amount, label);
  }
}

/// The line above the macros, e.g. `Nutrition per 100 g` (D-92b.4).
///
/// A serving whose label is empty after trim reads
/// `Nutrition per 1 serving`. Verified by `test/food_serving_test.dart`
/// test `S-92b.1 heading strings`.
String servingHeading(ServingChoice choice) {
  switch (choice) {
    case Per100G():
      return 'Nutrition per 100 g';
    case Per100Ml():
      return 'Nutrition per 100 ml';
    case PackageServing(:final amount, :final label):
      return 'Nutrition per ${formatGrams(amount)} $label';
    case NamedServing(:final label):
      final trimmed = label.trim();
      return 'Nutrition per 1 ${trimmed.isEmpty ? 'serving' : trimmed}';
    case AsSavedServing(:final amount, :final label):
      return 'Nutrition per ${formatGrams(amount)} $label';
  }
}
