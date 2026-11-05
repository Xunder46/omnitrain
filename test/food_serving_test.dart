// filepath: test/food_serving_test.dart
//
// Plan 92b Phase 1 — the pure serving mapper (S-92b.1, D-92b.1..D-92b.4).
//
// Every stored serving triple the app can hold must map to exactly one
// serving choice and back, byte-identical, without any text comparison.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/food_serving.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/mock/food_catalog_seed.dart';

/// The three stored fields D-92b.1 derives from a serving choice.
typedef StoredServing = (FoodUnitType, double, String);

StoredServing _roundTrip(FoodUnitType unitType, double amount, String label) {
  return storedServingFrom(servingChoiceFrom(unitType, amount, label));
}

void main() {
  group('food_serving', () {
    test('S-92b.1 round trip over every shipped catalog triple', () {
      final triples = <StoredServing>{
        for (final food in FoodCatalogSeed.sampleCatalogFoods)
          (food.unitType, food.referenceAmount, food.referenceLabel),
      }.toList();

      // The shipped catalog holds 28 distinct serving triples: three
      // gram rows (100 g, 100 ml, 28 g) and 25 named count servings.
      expect(triples, hasLength(28));

      for (final triple in triples) {
        expect(
          _roundTrip(triple.$1, triple.$2, triple.$3),
          triple,
          reason: 'catalog triple must round-trip unchanged: $triple',
        );
      }
    });

    test('S-92b.1 round trip over the odd stored servings', () {
      final odd = <StoredServing>[
        (FoodUnitType.count, 3, 'tbsp'),
        (FoodUnitType.grams, 100, 'per 100g'),
        (FoodUnitType.grams, 100.5, 'g'),
        (FoodUnitType.count, 1, ''),
        (FoodUnitType.grams, 0, 'g'),
        (FoodUnitType.count, 1, ' slice'),
      ];

      for (final triple in odd) {
        expect(
          _roundTrip(triple.$1, triple.$2, triple.$3),
          triple,
          reason: 'odd triple must round-trip unchanged: $triple',
        );
      }
    });

    test('S-92b.1 stored serving loads as the matching choice', () {
      expect(servingChoiceFrom(FoodUnitType.grams, 100, 'g'), isA<Per100G>());
      expect(servingChoiceFrom(FoodUnitType.grams, 100, 'ml'), isA<Per100Ml>());

      final package = servingChoiceFrom(FoodUnitType.grams, 28, 'g');
      expect(package, isA<PackageServing>());
      expect((package as PackageServing).amount, 28);
      expect(package.label, 'g');

      // A fractional gram amount above zero is a package size, not an
      // odd stored serving: the round trip still holds.
      final fractional = servingChoiceFrom(FoodUnitType.grams, 100.5, 'g');
      expect(fractional, isA<PackageServing>());
      expect((fractional as PackageServing).amount, 100.5);

      final named = servingChoiceFrom(FoodUnitType.count, 1, 'slice');
      expect(named, isA<NamedServing>());
      expect((named as NamedServing).label, 'slice');
    });

    test('S-92b.1 odd stored servings load as As saved', () {
      final odd = <StoredServing>[
        (FoodUnitType.count, 3, 'tbsp'),
        (FoodUnitType.grams, 100, 'per 100g'),
        (FoodUnitType.count, 1, ''),
        (FoodUnitType.grams, 0, 'g'),
        (FoodUnitType.count, 1, ' slice'),
        (FoodUnitType.grams, double.nan, 'g'),
      ];

      for (final triple in odd) {
        final choice = servingChoiceFrom(triple.$1, triple.$2, triple.$3);
        expect(choice, isA<AsSavedServing>(), reason: 'for $triple');
        final asSaved = choice as AsSavedServing;
        expect(asSaved.unitType, triple.$1);
        if (triple.$2.isNaN) {
          expect(asSaved.amount.isNaN, isTrue);
        } else {
          expect(asSaved.amount, triple.$2);
        }
        expect(asSaved.label, triple.$3);
      }
    });

    test('S-92b.1 each choice stores its triple', () {
      expect(storedServingFrom(const Per100G()), (
        FoodUnitType.grams,
        100.0,
        'g',
      ));
      expect(storedServingFrom(const Per100Ml()), (
        FoodUnitType.grams,
        100.0,
        'ml',
      ));
      expect(storedServingFrom(const PackageServing(amount: 30, label: 'ml')), (
        FoodUnitType.grams,
        30.0,
        'ml',
      ));
      expect(storedServingFrom(const NamedServing(label: 'cup')), (
        FoodUnitType.count,
        1.0,
        'cup',
      ));
      expect(
        storedServingFrom(
          const AsSavedServing(
            unitType: FoodUnitType.count,
            amount: 3,
            label: 'tbsp',
          ),
        ),
        (FoodUnitType.count, 3.0, 'tbsp'),
      );
    });

    test('S-92b.1 heading strings', () {
      expect(servingHeading(const Per100G()), 'Nutrition per 100 g');
      expect(servingHeading(const Per100Ml()), 'Nutrition per 100 ml');
      expect(
        servingHeading(const PackageServing(amount: 30, label: 'g')),
        'Nutrition per 30 g',
      );
      expect(
        servingHeading(const PackageServing(amount: 100.5, label: 'g')),
        'Nutrition per 100.5 g',
      );
      expect(
        servingHeading(const NamedServing(label: 'slice')),
        'Nutrition per 1 slice',
      );
      expect(
        servingHeading(const NamedServing(label: '   ')),
        'Nutrition per 1 serving',
      );
      expect(
        servingHeading(
          const AsSavedServing(
            unitType: FoodUnitType.count,
            amount: 3,
            label: 'tbsp',
          ),
        ),
        'Nutrition per 3 tbsp',
      );
    });
  });
}
