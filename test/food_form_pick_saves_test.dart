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
// The **imagePath** written by the service is the **basename**
// (D-1 in
// `docs/plans/image-persistence-relocation-fix-plan.md`):
// a portable identifier under the managed directory that survives
// OS-driven relocations. Tests assert this contract by checking
// that the path has no directory separator and resolves to a
// real file under the service's managed dir.
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
// `FoodDraft` is re-exported by `food_form.dart`
// (`export '../../../core/models/food_draft.dart' show FoodDraft;`)
// so an explicit import here would be redundant.
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:path/path.dart' as p;

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
        // The form's handlePickedImage does real file I/O via
        // ImageStorageService.persistPickedImage. Flutter's
        // `testWidgets` runs in a fake async zone where real I/O
        // never completes — wrap the call in `tester.runAsync`
        // so the file copy actually runs (otherwise the test
        // hangs for the full 10-minute default timeout).
        await tester.runAsync(() async {
          await formState.handlePickedImage(picked);
        });
        await tester.pumpAndSettle();

        // onImageSave was called with a partial draft whose
        // imagePath is the persisted managed basename (D-1: the
        // reference is a basename, not the picker temp path) and
        // whose other fields are copied from initial.
        final draft = savedDraft;
        expect(draft, isNotNull, reason: 'onImageSave was not called');
        expect(draft!.imagePath, isNotNull);
        expect(
          draft.imagePath,
          isNot(equals(picked.path)),
          reason:
              'imagePath must be the persisted managed basename, '
              'not the raw picker path',
        );
        // D-1: a basename has no path separators and ends with .jpg.
        expect(
          draft.imagePath,
          isNot(contains('/')),
          reason: 'imagePath must be a basename, not a path',
        );
        expect(draft.name, initial.name);
        expect(draft.protein, initial.protein);

        // The food is reloaded with the new imagePath in the data
        // layer (i.e. the library + "foods I eat" view would now
        // render the photo, not the placeholder). The basename
        // resolves to a file under the managed dir.
        await foodLibraryState.loadCatalogFoods();
        final updated = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.id == 'food-pick-save-1',
        );
        expect(updated.imagePath, draft.imagePath);
        final managedPath = File(
          p.join(imageStorage.service.managedDirectoryPath, updated.imagePath!),
        );
        expect(managedPath.existsSync(), isTrue);
        expect(managedPath.readAsBytesSync(), equals(sourceBytes));
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
        // The helper does real async I/O (File.copy via the
        // service); wrap in `tester.runAsync` so it runs in
        // real async instead of `testWidgets`'s fake async zone.
        // `tester.runAsync<T>` returns `Future<T?>` in this
        // Flutter version (errors are nulled out); we assert
        // non-null with `firstBasename!` at each use site below.
        final firstBasename = await tester.runAsync(
          () => _pickAndPersist(imageStorage.service, 'first', [1, 1, 1]),
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
          imagePath: firstBasename,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        await repo.seedCatalogFood(firstFood);
        await foodLibraryState.loadCatalogFoods();
        final initial = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.id == 'food-pick-replace-1',
        );
        // The basename resolves to a file under the managed dir.
        final firstManagedPath = File(
          p.join(imageStorage.service.managedDirectoryPath, firstBasename!),
        );
        expect(firstManagedPath.existsSync(), isTrue);

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
        // See the first test for why we wrap in `tester.runAsync`:
        // handlePickedImage does real file I/O which never
        // completes in `testWidgets`'s fake async zone.
        await tester.runAsync(() async {
          await formState.handlePickedImage(picked);
        });
        await tester.pumpAndSettle();

        // Old managed file deleted (D-7).
        expect(
          firstManagedPath.existsSync(),
          isFalse,
          reason: 'previous managed file should be deleted by D-7',
        );
        // New managed file present.
        await foodLibraryState.loadCatalogFoods();
        final updated = foodLibraryState.catalogFoods.firstWhere(
          (f) => f.id == 'food-pick-replace-1',
        );
        expect(updated.imagePath, isNotNull);
        final newManagedPath = File(
          p.join(imageStorage.service.managedDirectoryPath, updated.imagePath!),
        );
        expect(newManagedPath.existsSync(), isTrue);
        expect(updated.imagePath, isNot(equals(firstBasename)));
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
        // See the first test for why we wrap in `tester.runAsync`:
        // handlePickedImage does real file I/O which never
        // completes in `testWidgets`'s fake async zone.
        await tester.runAsync(() async {
          await formState.handlePickedImage(picked);
        });
        await tester.pumpAndSettle();

        expect(
          onImageSaveCalls,
          0,
          reason: 'onImageSave must not fire in create mode',
        );
      },
    );
  });

  // ─── The clear-image fix (Phase 3.X.2) ────────────────────────────────
  //
  // Regression test for the **clear photo doesn't persist** bug.
  //
  // Symptom (reported by the user): tapping the × overlay on a
  // food's photo in the Edit Food screen clears the photo from
  // the form but does NOT clear it from the library / "foods I
  // eat" view. After a reload, the photo is back.
  //
  // Root cause: `EditFoodScreen` (which edits an existing catalog
  // food) uses `autoSaveOnBlur: true, skipPopOnSave: true` — there
  // is no Save button. The form's `_clearImage` only setState'd
  // `_imagePath = null` locally and never triggered a state save.
  // The user navigates back via the back button (not focus blur),
  // so the food's `imagePath` in the data layer remained the
  // previous value, and the previous managed file accumulated on
  // disk (no D-7 cleanup was triggered).
  //
  // Fix: `FoodForm` now exposes `clearImage()` (`@visibleForTesting`)
  // which, after `setState(_imagePath = null)`, fires
  // `onImageSave` with a partial draft (`imagePath: null`) in
  // edit mode. `EditFoodScreen` wires `onImageSave` to
  // `updateCatalogFood`, whose existing
  // `previousPath != draft.imagePath` branch handles D-7 cleanup
  // of the previous managed file. Create mode does NOT fire
  // `onImageSave` (no source food to partial-save against).

  group(
    'FoodForm: clear photo (× overlay) also triggers a state save in edit mode',
    () {
      testWidgets(
        'clearImage fires onImageSave with imagePath: null AND deletes the previous managed file (D-7)',
        (WidgetTester tester) async {
          final imageStorage = TestImageStorage.create();
          addTearDown(imageStorage.dispose);
          final repo = MockWorkoutRepository();
          await repo.initialize();
          final foodLibraryState = FoodLibraryState(
            repo,
            imageStorage: imageStorage.service,
          );

          // Seed an existing managed image first. The helper does
          // real async I/O (File.copy via the service); wrap in
          // `tester.runAsync` so it runs in real async instead of
          // `testWidgets`'s fake async zone.
          final basename = await tester.runAsync(
            () => _pickAndPersist(imageStorage.service, 'clear-target', [
              7,
              7,
              7,
            ]),
          );
          final managedPath = File(
            p.join(imageStorage.service.managedDirectoryPath, basename!),
          );
          expect(
            managedPath.existsSync(),
            isTrue,
            reason: 'seed image must exist on disk',
          );

          // Seed a catalog row that references the seeded basename.
          const existingId = 'food-clear-save-1';
          final existing = Food(
            id: existingId,
            name: 'Clear Save Test',
            groupId: null,
            unitType: FoodUnitType.grams,
            referenceAmount: 100,
            referenceLabel: 'g',
            isCatalog: true,
            protein: 10,
            carbs: 0,
            fiber: 0,
            fat: 1,
            imagePath: basename,
            createdAtMs: 1000,
            updatedAtMs: 1000,
          );
          await repo.seedCatalogFood(existing);
          await foodLibraryState.loadCatalogFoods();
          final loaded = foodLibraryState.catalogFoods.firstWhere(
            (f) => f.id == existingId,
          );
          expect(
            loaded.imagePath,
            basename,
            reason: 'seed imagePath must round-trip through the catalog',
          );

          // The host (EditFoodScreen) wires onImageSave to a
          // partial state save. The test mirrors that wiring.
          FoodDraft? savedDraft;
          Future<bool> onImageSave(FoodDraft draft) async {
            savedDraft = draft;
            await foodLibraryState.updateCatalogFood(loaded, draft);
            return true;
          }

          // Pump the form in edit mode (initial != null).
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FoodForm(
                  initial: loaded,
                  foodLibraryState: foodLibraryState,
                  onSave: (_) async => true,
                  onImageSave: onImageSave,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Drive the clear via the @visibleForTesting seam.
          // ignore: avoid-dynamic
          final formState = tester.state(find.byType(FoodForm)) as dynamic;
          // clearImage is async and may await the host's onImageSave
          // callback (which in turn awaits the state method's write).
          // Wrap in `tester.runAsync` so the awaits actually
          // progress.
          await tester.runAsync(() async {
            await formState.clearImage();
          });
          await tester.pumpAndSettle();

          // onImageSave was called with a partial draft whose
          // imagePath is null and whose other fields are copied
          // from initial (no clobber of in-flight edits).
          final draft = savedDraft;
          expect(draft, isNotNull, reason: 'onImageSave was not called');
          expect(
            draft!.imagePath,
            isNull,
            reason: 'clearImage must pass imagePath: null to onImageSave',
          );
          expect(draft.name, loaded.name);
          expect(draft.protein, loaded.protein);

          // The food is reloaded with imagePath == null in the
          // data layer — the library + "foods I eat" view would
          // now render the placeholder.
          await foodLibraryState.loadCatalogFoods();
          final updated = foodLibraryState.catalogFoods.firstWhere(
            (f) => f.id == existingId,
          );
          expect(updated.imagePath, isNull);

          // The previous managed file is deleted (D-7).
          expect(
            managedPath.existsSync(),
            isFalse,
            reason: 'previous managed file should be deleted by D-7',
          );
        },
      );

      testWidgets(
        'clearImage in create mode (initial == null) does NOT fire onImageSave',
        (WidgetTester tester) async {
          // Create mode has no source food to partial-save against.
          // The clear just unsets the local state; the user saves
          // the whole food via the existing Save button.
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

          // Seed an image so the × overlay is rendered and the
          // clear code path runs end-to-end (setState fires; the
          // guard skips the onImageSave branch).
          final basename = await tester.runAsync(
            () => _pickAndPersist(imageStorage.service, 'clear-create', [8]),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FoodForm(
                  initial: null, // create mode
                  foodLibraryState: foodLibraryState,
                  onSave: (_) async => true,
                  onImageSave: onImageSave,
                  // Seed an image via a child widget? No — we can't
                  // inject _imagePath directly. Skip: the × overlay
                  // is only rendered when an image is present, so
                  // invoking clearImage on a form with no image is
                  // testing a no-op. The interesting branch is the
                  // guard, which we cover regardless of whether an
                  // image is present.
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // ignore: avoid-dynamic
          final formState = tester.state(find.byType(FoodForm)) as dynamic;
          await tester.runAsync(() async {
            await formState.clearImage();
          });
          await tester.pumpAndSettle();

          expect(
            onImageSaveCalls,
            0,
            reason: 'onImageSave must not fire in create mode',
          );

          // Best-effort cleanup of the seeded basename (the service
          // is disposed via addTearDown, but tidy explicitly so the
          // managed dir doesn't carry the temp file forward).
          if (basename != null) {
            final f = File(
              p.join(imageStorage.service.managedDirectoryPath, basename),
            );
            if (f.existsSync()) f.deleteSync();
          }
        },
      );
    },
  );
}

// ─── Test helpers ────────────────────────────────────────────────────────

/// Persist a synthetic picked file into the managed dir. Returns
/// the new basename (D-1 — the modern reference format). Mirrors
/// the helper in `image_persistence_round_trip_test.dart`.
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
