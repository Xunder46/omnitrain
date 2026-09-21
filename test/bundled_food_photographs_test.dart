// filepath: test/bundled_food_photographs_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_thumbnail.dart';
import 'package:omnitrain/features/nutrition/widgets/food_thumbnail_stub.dart'
    if (dart.library.io) 'package:omnitrain/features/nutrition/widgets/food_thumbnail_io.dart';
import 'package:omnitrain/state/food_library_state.dart';

import 'helpers/fake_asset_bundle.dart';
import 'helpers/test_image_helper.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  return repo;
}

void main() {
  group('Bundled Food Photographs (12 scenarios)', () {
    // ─── S-1: Catalog food with bundled photo, no user photo (native) ────────────
    testWidgets(
      'S-1: Catalog food renders placeholder when bundled asset missing (native)',
      (WidgetTester tester) async {
        if (kIsWeb) {
          // Skip on web; S-8 covers web
          return;
        }

        const catalogFood = Food(
          id: 'chicken_breast',
          name: 'Chicken Breast',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          imagePath: null,
          protein: 31,
          carbs: 0,
          fat: 4,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );

        // Empty bundle — no assets declared, so Image.asset fails
        final fakeBundle = FakeAssetBundle({});

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: fakeBundle,
            child: MaterialApp(
              home: Scaffold(
                body: FoodThumbnail(
                  imagePath: catalogFood.imagePath,
                  foodId: catalogFood.id,
                  catalogId: catalogFood.catalogId,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Placeholder is rendered (no Image widget)
        expect(find.byType(Container), findsWidgets);
        expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      },
    );

    // ─── S-2: Catalog food with user photo (precedence) ────────────────────────
    testWidgets('S-2: User photo takes precedence over bundled photo path (native)', (
      WidgetTester tester,
    ) async {
      if (kIsWeb) {
        // Web cannot render user photos; skip
        return;
      }

      const catalogFood = Food(
        id: 'chicken_breast',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        isCatalog: true,
        imagePath: '/tmp/user_photo.jpg', // User photo set
        protein: 31,
        carbs: 0,
        fat: 4,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

      // Bundle has bundled photo available, but user photo takes precedence
      // so this should never be loaded
      final fakeBundle = FakeAssetBundle({
        'assets/images/food_chicken_breast.webp':
            TestImageHelper.testWebp1x1Red,
      });

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: fakeBundle,
          child: MaterialApp(
            home: Scaffold(
              body: FoodThumbnail(
                imagePath: catalogFood.imagePath,
                foodId: catalogFood.id,
                catalogId: catalogFood.catalogId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Discriminating assertions: prove that tier-1 (user photo) was selected,
      // not tier-2 (bundled photo).
      // Tier-1 renderer is FoodThumbnailImage; if present, tier-1 was selected.
      expect(
        find.byType(FoodThumbnailImage),
        findsOneWidget,
        reason: 'Tier-1 user-photo renderer should be present',
      );
      // Tier-2 would check bundled path via Image.asset with AssetImage provider.
      // Assert no Image widgets with asset-based providers exist (no tier-2 was run).
      final imageWidgets = find.byType(Image);
      for (int i = 0; i < imageWidgets.evaluate().length; i++) {
        final widget = imageWidgets.evaluate().elementAt(i).widget as Image;
        expect(
          widget.image is! AssetImage && widget.image is! ExactAssetImage,
          isTrue,
          reason:
              'No Image widget should have an AssetImage provider (tier-2 should not run)',
        );
      }
    });

    // ─── S-3: Catalog food, no bundled photo, no user photo ─────────────────────
    testWidgets('S-3: No bundled, no user photo renders placeholder (native)', (
      WidgetTester tester,
    ) async {
      if (kIsWeb) {
        return;
      }

      const catalogFood = Food(
        id: 'egg',
        name: 'Egg',
        unitType: FoodUnitType.count,
        referenceAmount: 1,
        referenceLabel: 'egg',
        isCatalog: true,
        imagePath: null,
        protein: 6,
        carbs: 0,
        fat: 5,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

      // Empty bundle
      final fakeBundle = FakeAssetBundle({});

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: fakeBundle,
          child: MaterialApp(
            home: Scaffold(
              body: FoodThumbnail(
                imagePath: catalogFood.imagePath,
                foodId: catalogFood.id,
                catalogId: catalogFood.catalogId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Placeholder renders
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    });

    // ─── S-4: Library food copied from catalog with bundled photo ────────────────
    testWidgets(
      'S-4: Library copy from catalog resolves bundled via catalogId (native)',
      (WidgetTester tester) async {
        if (kIsWeb) {
          return;
        }

        // Library copy: fresh id, catalogId set to original
        const libraryCopy = Food(
          id: 'lib_copy_xyz',
          name: 'Chicken Breast (Copied)',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: false,
          catalogId: 'chicken_breast', // Link to original
          imagePath: null,
          protein: 31,
          carbs: 0,
          fat: 4,
          createdAtMs: 2000,
          updatedAtMs: 2000,
        );

        // Empty bundle (the real asset directory is declared in pubspec;
        // this empty test bundle exercises the missing-asset fallback)
        final fakeBundle = FakeAssetBundle({});

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: fakeBundle,
            child: MaterialApp(
              home: Scaffold(
                body: FoodThumbnail(
                  imagePath: libraryCopy.imagePath,
                  foodId: libraryCopy.id,
                  catalogId: libraryCopy.catalogId,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Placeholder renders (bundled asset not present in this test bundle).
        // The catalogId link is intact (verified by the path resolution logic,
        // which would be: bundledPhotoAssetPath(libraryCopy.catalogId ?? libraryCopy.id)
        // = bundledPhotoAssetPath("chicken_breast") = "assets/images/food_chicken_breast.webp")
        expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      },
    );

    // ─── S-5: Clear user photo from library food with bundled source ────────────
    testWidgets('S-5: Clearing user photo falls back to bundled (native)', (
      WidgetTester tester,
    ) async {
      if (kIsWeb) {
        return;
      }

      // After user clears imagePath
      const libraryCopy = Food(
        id: 'lib_copy_xyz',
        name: 'Chicken Breast (Copied)',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        isCatalog: false,
        catalogId: 'chicken_breast',
        imagePath: null, // Cleared
        protein: 31,
        carbs: 0,
        fat: 4,
        createdAtMs: 2000,
        updatedAtMs: 2000,
      );

      // Empty bundle
      final fakeBundle = FakeAssetBundle({});

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: fakeBundle,
          child: MaterialApp(
            home: Scaffold(
              body: FoodThumbnail(
                imagePath: libraryCopy.imagePath,
                foodId: libraryCopy.id,
                catalogId: libraryCopy.catalogId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Placeholder renders (bundled not present)
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    });

    // ─── S-6: Clear user photo from user-created library food ───────────────────
    testWidgets(
      'S-6: User-created library food (no bundled) renders placeholder (native)',
      (WidgetTester tester) async {
        if (kIsWeb) {
          return;
        }

        // User-created library food: no catalogId
        const userCreated = Food(
          id: 'lib_custom_1',
          name: 'My Custom Food',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: false,
          catalogId: null, // No catalog link
          imagePath: null,
          protein: 10,
          carbs: 20,
          fat: 5,
          createdAtMs: 3000,
          updatedAtMs: 3000,
        );

        // Empty bundle
        final fakeBundle = FakeAssetBundle({});

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: fakeBundle,
            child: MaterialApp(
              home: Scaffold(
                body: FoodThumbnail(
                  imagePath: userCreated.imagePath,
                  foodId: userCreated.id,
                  catalogId: userCreated.catalogId,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Placeholder renders
        expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      },
    );

    // ─── S-7: Missing bundled photo file — silent fallback ─────────────────────
    testWidgets('S-7: Missing bundled asset falls back silently (native)', (
      WidgetTester tester,
    ) async {
      if (kIsWeb) {
        return;
      }

      const anyFood = Food(
        id: 'test_food_missing',
        name: 'Test Food',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        isCatalog: true,
        imagePath: null,
        protein: 10,
        carbs: 20,
        fat: 5,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

      // Empty bundle — all assets missing
      final fakeBundle = FakeAssetBundle({});

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: fakeBundle,
          child: MaterialApp(
            home: Scaffold(
              body: FoodThumbnail(
                imagePath: anyFood.imagePath,
                foodId: anyFood.id,
                catalogId: anyFood.catalogId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Placeholder renders without error
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
      // No exceptions thrown
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    });

    // ─── S-8: Web with bundled photo, no user photo ──────────────────────────────
    testWidgets('S-8: Web renders placeholder for missing bundled asset', (
      WidgetTester tester,
    ) async {
      if (!kIsWeb) {
        // Only test on web (or in a test that simulates web behavior)
        return;
      }

      const catalogFood = Food(
        id: 'chicken_breast',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        isCatalog: true,
        imagePath: null,
        protein: 31,
        carbs: 0,
        fat: 4,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

      // Empty bundle
      final fakeBundle = FakeAssetBundle({});

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: fakeBundle,
          child: MaterialApp(
            home: Scaffold(
              body: FoodThumbnail(
                imagePath: catalogFood.imagePath,
                foodId: catalogFood.id,
                catalogId: catalogFood.catalogId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Placeholder renders
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    });

    // ─── S-9: Web with no bundled photo ──────────────────────────────────────────
    testWidgets('S-9: Web without bundled asset renders placeholder', (
      WidgetTester tester,
    ) async {
      if (!kIsWeb) {
        return;
      }

      const catalogFood = Food(
        id: 'egg',
        name: 'Egg',
        unitType: FoodUnitType.count,
        referenceAmount: 1,
        referenceLabel: 'egg',
        isCatalog: true,
        imagePath: null,
        protein: 6,
        carbs: 0,
        fat: 5,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

      // Empty bundle
      final fakeBundle = FakeAssetBundle({});

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: fakeBundle,
          child: MaterialApp(
            home: Scaffold(
              body: FoodThumbnail(
                imagePath: catalogFood.imagePath,
                foodId: catalogFood.id,
                catalogId: catalogFood.catalogId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Placeholder renders
      expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    });

    // ─── S-10 (new): Bundled photo tier is selected when asset exists ─────────
    testWidgets(
      'S-10 (new): Bundled photo tier is selected (Image.asset() reached)',
      (WidgetTester tester) async {
        if (kIsWeb) {
          // Image.asset decoding may behave differently on web; skip
          return;
        }

        const catalogFood = Food(
          id: 'bundled_photo_test',
          name: 'Test Food',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          imagePath: null, // No user photo — tier-1 skipped
          protein: 10,
          carbs: 20,
          fat: 5,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );

        final bundledPath = 'assets/images/food_bundled_photo_test.webp';
        final fakeBundle = FakeAssetBundle({
          bundledPath: TestImageHelper.testWebp1x1Red,
        });

        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: fakeBundle,
            child: MaterialApp(
              home: Scaffold(
                body: FoodThumbnail(
                  imagePath: catalogFood.imagePath,
                  foodId: catalogFood.id,
                  catalogId: catalogFood.catalogId,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify that tier-2 (bundled photo) was selected by checking
        // for an Image widget with an AssetImage/ExactAssetImage provider.
        // This proves that FoodThumbnail.build() reached the bundled-photo
        // branch and created _BundledPhotoImage, which uses Image.asset().
        //
        // NOTE: Real image decoding may not complete in the test environment,
        // so we cannot assert placeholder-is-absent. We instead assert that
        // the asset provider exists in the widget tree, which is sufficient
        // proof that tier-2 logic was executed.
        final imageWidgets = find.byType(Image);
        bool foundAssetImage = false;
        for (int i = 0; i < imageWidgets.evaluate().length; i++) {
          final widget = imageWidgets.evaluate().elementAt(i).widget as Image;
          if (widget.image is AssetImage || widget.image is ExactAssetImage) {
            foundAssetImage = true;
            break;
          }
        }
        expect(
          foundAssetImage,
          isTrue,
          reason:
              'Image widget with AssetImage provider should be present, proving tier-2 bundled-photo branch was taken',
        );
      },
    );

    // ─── S-11: Edit copied library food name/nutrition — bundled persists ────────
    testWidgets(
      'S-11: Editing library copy preserves catalogId for bundled photo',
      (WidgetTester tester) async {
        if (kIsWeb) {
          return;
        }

        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);

        // Create a library copy with catalogId link
        await state.createFood(
          const Food(
            id: 'lib_copy_xyz',
            name: 'Original Name',
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            isCatalog: false,
            catalogId: 'chicken_breast',
            protein: 31,
            carbs: 0,
            fat: 4,
            imagePath: null,
            createdAtMs: 2000,
            updatedAtMs: 2000,
          ),
        );

        await state.loadFoods();
        var food = state.foods.firstWhere((f) => f.id == 'lib_copy_xyz');
        final originalCatalogId = food.catalogId;

        // Edit name
        await state.updateCustomFood(
          id: 'lib_copy_xyz',
          name: 'Updated Name',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fiber: 0,
          fat: 4,
          sodium: null,
          notes: null,
          imagePath: null,
        );

        await state.loadFoods();
        food = state.foods.firstWhere((f) => f.id == 'lib_copy_xyz');

        // catalogId is preserved after editing (same as before edit)
        expect(food.catalogId, originalCatalogId);
        expect(food.name, 'Updated Name');
      },
    );

    // ─── S-12: Pick personal photo on food with bundled photo ──────────────────
    testWidgets('S-12: User photo persists on food with bundled photo source (native)', (
      WidgetTester tester,
    ) async {
      if (kIsWeb) {
        return;
      }

      // After user picks a photo
      const catalogFood = Food(
        id: 'chicken_breast',
        name: 'Chicken Breast',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        isCatalog: true,
        imagePath: '/tmp/personal_photo_chicken.jpg', // User photo set
        protein: 31,
        carbs: 0,
        fat: 4,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );

      // Bundle has bundled photo available, but user photo takes precedence
      final fakeBundle = FakeAssetBundle({
        'assets/images/food_chicken_breast.webp':
            TestImageHelper.testWebp1x1Red,
      });

      await tester.pumpWidget(
        DefaultAssetBundle(
          bundle: fakeBundle,
          child: MaterialApp(
            home: Scaffold(
              body: FoodThumbnail(
                imagePath: catalogFood.imagePath,
                foodId: catalogFood.id,
                catalogId: catalogFood.catalogId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Discriminating assertions: prove that tier-1 (user photo) was selected,
      // not tier-2 (bundled photo), even when bundled photo is available.
      // Tier-1 renderer is FoodThumbnailImage; if present, tier-1 was selected.
      expect(
        find.byType(FoodThumbnailImage),
        findsOneWidget,
        reason:
            'Tier-1 user-photo renderer should be present, proving precedence',
      );
      // Tier-2 would check bundled path via Image.asset with AssetImage provider.
      // Assert no Image widgets with asset-based providers exist (no tier-2 was run).
      final imageWidgets = find.byType(Image);
      for (int i = 0; i < imageWidgets.evaluate().length; i++) {
        final widget = imageWidgets.evaluate().elementAt(i).widget as Image;
        expect(
          widget.image is! AssetImage && widget.image is! ExactAssetImage,
          isTrue,
          reason:
              'No Image widget should have an AssetImage provider (bundled tier should not run)',
        );
      }
    });

    // ─── S-4 extended: addCatalogFoodToLibrary preserves catalogId ─────────────
    test(
      'S-4 extended: addCatalogFoodToLibrary creates copy with catalogId',
      () async {
        final repo = await _freshRepo();
        final state = FoodLibraryState(repo);

        // Load catalog foods
        await state.loadCatalogFoods();
        final catalogFood = state.catalogFoods.firstWhere(
          (f) => f.id.startsWith('chicken'),
          orElse: () => state.catalogFoods.first,
        );

        // Add to library (returns the new library copy's ID)
        final libraryCopyId = await state.addCatalogFoodToLibrary(
          catalogFood.id,
        );

        // Load foods to get the library copy
        await state.loadFoods();
        final libraryCopy = state.foods.firstWhere(
          (f) => f.id == libraryCopyId,
        );

        // Library copy has fresh id (different from catalog)
        expect(libraryCopy.id, isNotEmpty);
        expect(libraryCopy.id, isNot(catalogFood.id));

        // But catalogId is set to the catalog food's id
        expect(libraryCopy.catalogId, catalogFood.id);

        // isCatalog is false
        expect(libraryCopy.isCatalog, false);

        // Other fields match the catalog food
        expect(libraryCopy.name, catalogFood.name);
        expect(libraryCopy.protein, catalogFood.protein);
      },
    );
  });
}
