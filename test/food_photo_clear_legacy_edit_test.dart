// filepath: test/food_photo_clear_legacy_edit_test.dart
//
// Regression test for the **can't remove a photo from a food in
// the library** bug, on the *legacy library-only* edit path.
//
// Symptom: tapping × on a food's photo in the My Foods tab
// cleared it from the form, but the photo was still there after
// backing out and reopening the food.
//
// Root cause: My Foods routes user-created catalog rows to
// `EditFoodScreen` (which wires `onImageSave`, so photo changes
// persist the moment they happen) but routes legacy
// library-only rows — `isCatalog = false`, created before the
// catalog-backed custom-food path — to a shim screen that only
// persisted on Save. Since the catalog editor needs no Save tap,
// backing out is the natural gesture, and on the legacy path that
// discarded the change.
//
// Fix: the legacy shim wires `onImageSave` to the same partial
// save, so picking and clearing a photo persist immediately on
// both paths.
//
// The test drives the real screen (row tap → editor → × tap), so
// it covers the wiring, not just the state method — the state
// layer's clear path is already covered by
// `image_persistence_round_trip_test.dart`.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:omnitrain/core/services/image_storage_service.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:path/path.dart' as p;

import 'helpers/test_image_storage.dart';

/// Copy a throwaway source file into the managed directory the
/// way the picker does, and return the stored basename.
Future<String> _persistSourceImage(
  ImageStorageService service,
  String name,
) async {
  final source = File(p.join(Directory.systemTemp.path, '$name.jpg'));
  await source.writeAsBytes(<int>[1, 2, 3, 4]);
  final basename = await service.persistPickedImage(XFile(source.path));
  return basename!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'clearing a legacy library food\'s photo persists without a Save tap',
    (tester) async {
      final imageStorage = TestImageStorage.create();
      addTearDown(imageStorage.dispose);

      final repo = MockWorkoutRepository();
      await repo.initialize();
      final state = FoodLibraryState(repo, imageStorage: imageStorage.service);
      await state.loadFoodGroups();
      await state.loadFoods();
      await state.loadCatalogFoods();
      final nutrition = NutritionState(repo);
      await nutrition.loadConsumedToday();
      await nutrition.loadNutritionTarget();

      final basename = await tester.runAsync(
        () => _persistSourceImage(imageStorage.service, 'legacy-food-photo'),
      );
      final managedFile = File(
        p.join(imageStorage.service.managedDirectoryPath, basename!),
      );
      expect(
        managedFile.existsSync(),
        isTrue,
        reason: 'seed photo must exist on disk',
      );

      // A legacy library-only custom: isCatalog = false and no
      // catalog twin, so My Foods renders it and the row tap
      // opens the legacy shim editor.
      final foodId = await state.createFood(
        Food(
          id: '',
          name: 'Grandma\'s Stew',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 250,
          referenceLabel: 'g',
          isCatalog: false,
          protein: 18,
          carbs: 22,
          fiber: 0,
          fat: 12,
          imagePath: basename,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        ),
      );
      await state.loadFoods();
      expect((await repo.getFoodById(foodId))!.imagePath, basename);

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: state,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Foods'));
      await tester.pumpAndSettle();

      // Row tap opens the editor for this food.
      await tester.tap(find.text('Grandma\'s Stew'));
      await tester.pumpAndSettle();
      expect(
        find.text('Edit Food'),
        findsOneWidget,
        reason: 'row tap must open the food editor',
      );

      // Tap the × on the photo tile — and nothing else. No Save.
      final clearButton = find.byTooltip('Remove photo');
      expect(
        clearButton,
        findsOneWidget,
        reason: 'a user-set photo must offer a remove affordance',
      );
      await tester.runAsync(() async {
        await tester.tap(clearButton);
        // The clear awaits a real repository write and a real
        // file delete; give them a turn of the real event loop.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // The photo is gone from the data layer, so it stays gone
      // when the user backs out and reopens the food.
      final reloaded = (await repo.getFoodById(foodId))!;
      expect(
        reloaded.imagePath,
        isNull,
        reason:
            'the × must clear the photo in the data layer, not just '
            'in the form',
      );
      expect(
        managedFile.existsSync(),
        isFalse,
        reason: 'the orphaned managed file must be cleaned up (D-7)',
      );
    },
  );
}
