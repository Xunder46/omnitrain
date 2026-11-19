// filepath: test/food_photo_clear_legacy_edit_test.dart
//
// S-92a.8 — a photo cleared on the **legacy library-only** edit path waits
// for the Save tap.
//
// History: tapping × on a food's photo in My Foods cleared it from the form
// but the photo was still there after backing out and reopening the food.
// The first fix made the shim write the photo the moment it changed; plan
// 92a replaced that rule — nothing writes until Save on any `FoodForm`
// host, and Discard leaves the stored photo and its file untouched.
//
// The test drives the real screen (row tap → editor → × tap), so it
// covers the wiring, not just the state method — the state layer's clear
// path is already covered by `image_persistence_round_trip_test.dart`.

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
  return basename;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'clearing a legacy library food\'s photo waits for the Save tap',
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
      // catalog twin, so the Library list renders it and the row
      // tap opens the legacy shim editor.
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
      // The Library list is lazy: bring the legacy row into view
      // via the search field.
      await tester.enterText(
        find.byKey(const Key('catalog_search_field')),
        'Grandma\'s Stew',
      );
      await tester.pumpAndSettle();

      // Row tap opens the editor for this food. The row title is
      // scoped to the list because the search field's
      // EditableText carries the same text.
      await tester.tap(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Grandma\'s Stew'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Edit Food'),
        findsOneWidget,
        reason: 'row tap must open the food editor',
      );

      // Tap the × on the photo tile — and nothing else.
      Future<void> clearPhoto() async {
        final clearButton = find.byTooltip('Remove photo');
        expect(
          clearButton,
          findsOneWidget,
          reason: 'a user-set photo must offer a remove affordance',
        );
        await tester.tap(clearButton);
        await tester.pumpAndSettle();
      }

      // Reopen the legacy row. The search text still filters the list, so
      // the row is back in view after the editor pops.
      Future<void> reopenEditor() async {
        await tester.tap(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Grandma\'s Stew'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Edit Food'),
          findsOneWidget,
          reason: 'row tap must reopen the food editor',
        );
      }

      // Leg 1 of S-92a.8 — clearing writes nothing.
      await clearPhoto();
      // Give an instant write a real chance to land before asserting: a
      // save-on-clear (the behaviour this test replaces) completes well
      // inside this window, while a form-local clear never writes at all.
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 1));
        while (DateTime.now().isBefore(deadline)) {
          if ((await repo.getFoodById(foodId))!.imagePath != basename) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(
        (await repo.getFoodById(foodId))!.imagePath,
        basename,
        reason: 'a cleared photo must not reach the data layer before Save',
      );
      expect(
        managedFile.existsSync(),
        isTrue,
        reason: 'the managed file must survive an unwritten clear',
      );

      // Leg 2 — Discard drops the clear: the stored path and its file stay.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.text('Unsaved changes'),
        findsOneWidget,
        reason: 'a cleared photo is unsaved work, so back must ask',
      );
      await tester.tap(find.byKey(const Key('legacy-food-unsaved-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Edit Food'), findsNothing);
      expect(
        (await repo.getFoodById(foodId))!.imagePath,
        basename,
        reason: 'Discard must leave the stored photo alone',
      );
      expect(
        managedFile.existsSync(),
        isTrue,
        reason: 'Discard must leave the managed file on disk',
      );

      // Leg 3 — Save writes the clear and the state layer deletes the file.
      await reopenEditor();
      await clearPhoto();
      // Save runs a real repository write and a real file delete; neither
      // completes inside the fake-async zone, so drive the tap and poll the
      // end state against a deadline rather than sleeping a fixed time.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('food_form_save')));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(deadline)) {
          final food = await repo.getFoodById(foodId);
          if (food?.imagePath == null && !managedFile.existsSync()) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      final reloaded = (await repo.getFoodById(foodId))!;
      expect(
        reloaded.imagePath,
        isNull,
        reason: 'Save must write the cleared photo through to the data layer',
      );
      expect(
        managedFile.existsSync(),
        isFalse,
        reason: 'the orphaned managed file must be cleaned up on Save (D-7)',
      );
      expect(find.text('Edit Food'), findsNothing);
    },
  );
}
