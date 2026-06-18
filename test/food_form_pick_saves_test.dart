// filepath: test/food_form_pick_saves_test.dart
//
// Regression test for the **food photo upload doesn't persist in the
// current session** bug.
//
// Symptom (reported by the user): after picking a photo on a food in
// the food library, the photo is not visible in the library or in
// the "foods I eat" view. The user has to re-open the food to see
// the photo, and the photo is gone after a reload.
//
// Root cause: `EditFoodScreen` (which edits an existing catalog
// food) uses `autoSaveOnBlur: true, skipPopOnSave: true` — there is
// no save button. The form's `_pickImage` setState'd a local
// `_imagePath` but never triggered `_onSave` because the picker
// does not change focus. The user closes the form via Navigator.pop
// (not focus blur), so the food's `imagePath` in the data layer
// was never updated. The photo file was on disk but the food
// record still had `imagePath: null`, so the library and
// "foods I eat" views rendered the placeholder.
//
// Fix: `FoodForm` now exposes a `handlePickedImage(XFile)` method
// (visibleForTesting) and an optional `onImageSave` callback. The
// callback fires after a successful pick with a partial draft
// built from `widget.initial` (so concurrent controller edits are
// not clobbered). `EditFoodScreen` wires `onImageSave` to
// `updateCatalogFood`, so the new imagePath lands in the data
// layer immediately.
//
// The scenario S-3 (replace food photo deletes the old managed
// file) and S-7 (clear imagePath deletes the managed file) are
// already covered at the state level in
// `image_persistence_round_trip_test.dart`. The tests here cover
// the *form* layer — the part that wires the pick handler to the
// state save path.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:omnitrain/core/models/food_draft.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';

import 'helpers/test_image_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── The bug fix ────────────────────────────────────────────────────────

  group('FoodForm: photo pick triggers a state save in edit mode', () {
    testWidgets(
      'handlePickedImage persists the file AND fires onImageSave with a partial draft',
      (WidgetTester tester) async {
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final foodLibraryState = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );

        // Seed: existing catalog food with no image.
        const existing = Food(
          id: 'food-pick-save-1',
          name: 'Pick Save Test',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 10,
          carbs: 0,
          fiber: 0,
          fat: 1,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        await repo.seedCatalogFood(existing);
        await foodLibraryState.loadCatalogFoods();
        final initial = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.id == 'food-pick-save-1',
        );

        // Source file outside the managed dir.
        final sourceBytes = [1, 2, 3, 4, 5];
        final sourcePath = '${imageStorage.tempDir.path}/picked.jpg';
        File(sourcePath).writeAsBytesSync(sourceBytes);
        final picked = XFile(sourcePath, name: 'picked.jpg');

        // The host (EditFoodScreen) wires onImageSave to a partial
        // state save. The test mirrors that wiring.
        FoodDraft? savedDraft;
        Future<bool> onImageSave(FoodDraft draft) async {
          savedDraft = draft;
          await foodLibraryState.updateCatalogFood(initial, draft);
          return true;
        }

        // Pump the form in edit mode (initial != null).
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: foodLibraryState,
                onSave: (_) async => true,
                onImageSave: onImageSave,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Drive the pick via the visibleForTesting entry point.
        // The state class is library-private; dynamic cast is the
        // cleanest way to invoke it from a test in a different
        // library. Production callers go through the form's
        // _pickImage (the image_picker platform channel).
        // ignore: avoid-dynamic
        final formState = tester.state(find.byType(FoodForm)) as dynamic;
        await formState.handlePickedImage(picked);
        await tester.pumpAndSettle();

        // onImageSave was called with a partial draft whose
        // imagePath is the persisted managed path and whose other
        // fields are copied from initial.
        final draft = savedDraft;
        expect(draft, isNotNull, reason: 'onImageSave was not called');
        expect(draft!.imagePath, isNotNull);
        expect(draft.imagePath, isNot(equals(picked.path)),
            reason: 'imagePath must be the persisted managed path, '
                'not the raw picker path');
        expect(draft.name, initial.name);
        expect(draft.protein, initial.protein);

        // The food is reloaded with the new imagePath in the data
        // layer (i.e. the library + "foods I eat" view would now
        // render the photo, not the placeholder).
        await foodLibraryState.loadCatalogFoods();
        final updated = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.id == 'food-pick-save-1',
        );
        expect(updated.imagePath, draft.imagePath);
        expect(File(updated.imagePath!).existsSync(), isTrue);
        expect(File(updated.imagePath!).readAsBytesSync(), equals(sourceBytes));
      },
    );

    testWidgets(
      'handlePickedImage replaces the previous managed file (D-7 round-trip)',
      (WidgetTester tester) async {
        // With an existing image, picking a new one should fire
        // onImageSave (which the production EditFoodScreen wires
        // to updateCatalogFood). updateCatalogFood's D-7 cleanup
        // deletes the previous managed file.
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final foodLibraryState = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );

        // Seed: existing food with a first managed image.
        final firstPath = await _pickAndPersist(
          imageStorage.service,
          'first',
          [1, 1, 1],
        );
        final firstFood = Food(
          id: 'food-pick-replace-1',
          name: 'Pick Replace Test',
          groupId: null,
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: true,
          protein: 10,
          carbs: 0,
          fiber: 0,
          fat: 1,
          imagePath: firstPath,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        await repo.seedCatalogFood(firstFood);
        await foodLibraryState.loadCatalogFoods();
        final initial = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.id == 'food-pick-replace-1',
        );
        expect(File(firstPath).existsSync(), isTrue);

        // Pick a second image.
        final sourcePath = '${imageStorage.tempDir.path}/second.jpg';
        File(sourcePath).writeAsBytesSync([2, 2, 2]);
        final picked = XFile(sourcePath, name: 'second.jpg');

        Future<bool> onImageSave(FoodDraft draft) async {
          await foodLibraryState.updateCatalogFood(initial, draft);
          return true;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: foodLibraryState,
                onSave: (_) async => true,
                onImageSave: onImageSave,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ignore: avoid-dynamic
        final formState = tester.state(find.byType(FoodForm)) as dynamic;
        await formState.handlePickedImage(picked);
        await tester.pumpAndSettle();

        // Old managed file deleted (D-7).
        expect(File(firstPath).existsSync(), isFalse,
            reason: 'previous managed file should be deleted by D-7');
        // New managed file present.
        await foodLibraryState.loadCatalogFoods();
        final updated = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.id == 'food-pick-replace-1',
        );
        expect(File(updated.imagePath!).existsSync(), isTrue);
        expect(updated.imagePath, isNot(equals(firstPath)));
      },
    );

    testWidgets(
      'handlePickedImage in create mode (initial == null) does NOT fire onImageSave',
      (WidgetTester tester) async {
        // In create mode the form has no source food to partial-save
        // against. The image is just stored in local state; the
        // user saves the whole form via the Save button.
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final foodLibraryState = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );

        var onImageSaveCalls = 0;
        Future<bool> onImageSave(FoodDraft draft) async {
          onImageSaveCalls++;
          return true;
        }

        final sourcePath = '${imageStorage.tempDir.path}/create.jpg';
        File(sourcePath).writeAsBytesSync([9, 9, 9]);
        final picked = XFile(sourcePath, name: 'create.jpg');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null, // create mode
                foodLibraryState: foodLibraryState,
                onSave: (_) async => true,
                onImageSave: onImageSave,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ignore: avoid-dynamic
        final formState = tester.state(find.byType(FoodForm)) as dynamic;
        await formState.handlePickedImage(picked);
        await tester.pumpAndSettle();

        expect(onImageSaveCalls, 0,
            reason: 'onImageSave must not fire in create mode');
      },
    );
  });
}

// ─── Test helpers ────────────────────────────────────────────────────────

/// Persist a synthetic picked file into the managed dir. Returns
/// the new path. Mirrors the helper in
/// `image_persistence_round_trip_test.dart`.
Future<String> _pickAndPersist(
  dynamic service,
  String tag,
  List<int> bytes,
) async {
  final tempDir = Directory.systemTemp.createTempSync('picker_src_');
  final sourcePath = '${tempDir.path}/$tag.jpg';
  File(sourcePath).writeAsBytesSync(bytes);
  final picked = XFile(sourcePath, name: '$tag.jpg');
  return await service.persistPickedImage(picked) as String;
}
