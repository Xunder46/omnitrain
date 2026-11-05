// filepath: test/food_form_pick_saves_test.dart
//
// S-92a.5 / S-92a.6 — a picked or cleared photo waits for Save.
//
// History: this file began as the regression test for "a picked photo never
// persists", when `FoodForm` carried an `onImageSave` callback that made
// `EditFoodScreen` write the new `imagePath` the moment the picker returned.
// Plan 92a reversed the rule: on every `FoodForm` host nothing writes until
// the user taps Save (D-92a.2). The pick and the clear stay form-local; the
// Save draft carries `imagePath`, and the state method's D-7 cleanup deletes
// the managed file it replaces.
//
// What these tests pin, at the *form* layer:
//   * a pick or a clear reports the new path (or null) through
//     `onImageChanged`, which is how a host's unsaved-work probe sees it;
//   * nothing reaches the repository before Save — the stored path and its
//     managed file survive a pick or a clear;
//   * Save carries the picked path (or the null) in the draft, and the state
//     method deletes the file it replaced (D-7).
//
// The state layer's own D-7 behaviour is covered by
// `image_persistence_round_trip_test.dart`; the screen wiring by
// `test/edit_food_save_test.dart` and
// `test/food_photo_clear_legacy_edit_test.dart`.
//
// The **imagePath** written by the service is the **basename**
// (D-1 in
// `docs/plans/image-persistence-relocation-fix-plan.md`):
// a portable identifier under the managed directory that survives
// OS-driven relocations. Tests assert this contract by checking
// that the path has no directory separator and resolves to a
// real file under the service's managed dir.

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

  // ─── A picked photo waits for Save ──────────────────────────────────────

  group('FoodForm: a picked photo waits for Save (S-92a.5)', () {
    testWidgets(
      'handlePickedImage records the file and marks the probe dirty; nothing saves until Save',
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

        // The wiring every host has now: Save writes the whole draft, and
        // the photo signal carries the path the form holds.
        final controller = FoodFormController();
        String? reportedPath;
        var reportedCalls = 0;

        // Pump the form in edit mode (initial != null).
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: foodLibraryState,
                controller: controller,
                skipPopOnSave: true,
                onImageChanged: (path) {
                  reportedCalls++;
                  reportedPath = path;
                },
                onSave: (draft) async {
                  await foodLibraryState.updateCatalogFood(initial, draft);
                  return true;
                },
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

        // The host was told which path the form now holds: the persisted
        // managed basename (D-1), not the picker's temp path.
        expect(reportedCalls, 1);
        final persisted = reportedPath;
        expect(persisted, isNotNull, reason: 'onImageChanged was not called');
        expect(
          persisted,
          isNot(equals(picked.path)),
          reason:
              'the reported path must be the persisted managed basename, '
              'not the raw picker path',
        );
        expect(
          persisted,
          isNot(contains('/')),
          reason: 'imagePath must be a basename, not a path',
        );

        // Nothing reached the data layer: the stored photo is still unset.
        expect(
          (await repo.getCatalogFoodById('food-pick-save-1'))!.imagePath,
          isNull,
          reason: 'a picked photo must not be written before Save (D-92a.2)',
        );

        // Save carries the picked path in the draft, and only then does it
        // land in the data layer.
        await tester.runAsync(() async {
          controller.submit();
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (DateTime.now().isBefore(deadline)) {
            final food = await repo.getCatalogFoodById('food-pick-save-1');
            if (food?.imagePath == persisted) break;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();

        final updated = (await repo.getCatalogFoodById('food-pick-save-1'))!;
        expect(updated.imagePath, persisted);
        final managedPath = File(
          p.join(imageStorage.service.managedDirectoryPath, persisted!),
        );
        expect(managedPath.existsSync(), isTrue);
        expect(managedPath.readAsBytesSync(), equals(sourceBytes));
      },
    );

    testWidgets(
      'handlePickedImage replaces the previous managed file (D-7 round-trip)',
      (WidgetTester tester) async {
        // With an existing image, picking a new one changes nothing in the
        // data layer until Save; Save writes the new path and the state
        // method's D-7 cleanup deletes the file it replaced.
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

        final controller = FoodFormController();
        String? reportedPath;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: initial,
                foodLibraryState: foodLibraryState,
                controller: controller,
                skipPopOnSave: true,
                onImageChanged: (path) => reportedPath = path,
                onSave: (draft) async {
                  await foodLibraryState.updateCatalogFood(initial, draft);
                  return true;
                },
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

        // Nothing written yet: the stored path is the first basename and its
        // managed file is still on disk.
        expect(
          (await repo.getCatalogFoodById('food-pick-replace-1'))!.imagePath,
          firstBasename,
          reason: 'the stored photo must wait for Save',
        );
        expect(
          firstManagedPath.existsSync(),
          isTrue,
          reason: 'D-7 cleanup must not run on an unwritten pick',
        );
        final secondBasename = reportedPath;
        expect(secondBasename, isNotNull);
        expect(secondBasename, isNot(equals(firstBasename)));

        // Save writes the second path; D-7 deletes the first file.
        await tester.runAsync(() async {
          controller.submit();
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (DateTime.now().isBefore(deadline)) {
            final food = await repo.getCatalogFoodById('food-pick-replace-1');
            if (food?.imagePath == secondBasename &&
                !firstManagedPath.existsSync()) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();

        expect(
          firstManagedPath.existsSync(),
          isFalse,
          reason: 'previous managed file should be deleted by D-7 on Save',
        );
        final updated = (await repo.getCatalogFoodById(
          'food-pick-replace-1',
        ))!;
        expect(updated.imagePath, secondBasename);
        final newManagedPath = File(
          p.join(imageStorage.service.managedDirectoryPath, secondBasename!),
        );
        expect(newManagedPath.existsSync(), isTrue);
      },
    );

    testWidgets(
      'handlePickedImage in create mode (initial == null) reports the path through onImageChanged and saves nothing',
      (WidgetTester tester) async {
        // In create mode the form has no source food to write against; the
        // image is stored in local state and reported to the guard, and the
        // user saves the whole form via the Save button.
        final imageStorage = TestImageStorage.create();
        addTearDown(imageStorage.dispose);
        final repo = MockWorkoutRepository();
        await repo.initialize();
        final foodLibraryState = FoodLibraryState(
          repo,
          imageStorage: imageStorage.service,
        );

        var saveCalls = 0;
        String? reportedPath;
        var reportedCalls = 0;

        final sourcePath = '${imageStorage.tempDir.path}/create.jpg';
        File(sourcePath).writeAsBytesSync([9, 9, 9]);
        final picked = XFile(sourcePath, name: 'create.jpg');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null, // create mode
                foodLibraryState: foodLibraryState,
                skipPopOnSave: true,
                onImageChanged: (path) {
                  reportedCalls++;
                  reportedPath = path;
                },
                onSave: (_) async {
                  saveCalls++;
                  return true;
                },
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

        expect(reportedCalls, 1);
        expect(
          reportedPath,
          isNotNull,
          reason: 'a pick must reach the host guard in create mode too',
        );
        expect(
          saveCalls,
          0,
          reason: 'a pick must not trigger a save in create mode',
        );
      },
    );
  });

  // ─── A cleared photo waits for Save ─────────────────────────────────────
  //
  // History: tapping × used to clear the photo from the form but leave the
  // stored row untouched (the clear only setState'd `_imagePath = null`).
  // The first fix made the clear write immediately through `onImageSave`;
  // plan 92a replaced that rule — the clear is form-local until Save, and
  // the state method's `previousPath != draft.imagePath` branch handles the
  // D-7 cleanup of the replaced managed file.

  group('FoodForm: a cleared photo waits for Save (S-92a.6)', () {
      testWidgets(
        'clearImage reports null through onImageChanged; the stored path and its file wait for Save (D-7)',
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

          // The host's wiring now: Save writes the whole draft, and the
          // photo signal carries the path the form holds.
          final controller = FoodFormController();
          String? reportedPath;
          var reportedCalls = 0;

          // Pump the form in edit mode (initial != null).
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FoodForm(
                  initial: loaded,
                  foodLibraryState: foodLibraryState,
                  controller: controller,
                  skipPopOnSave: true,
                  onImageChanged: (path) {
                    reportedCalls++;
                    reportedPath = path;
                  },
                  onSave: (draft) async {
                    await foodLibraryState.updateCatalogFood(loaded, draft);
                    return true;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Drive the clear via the @visibleForTesting seam.
          // ignore: avoid-dynamic
          final formState = tester.state(find.byType(FoodForm)) as dynamic;
          // clearImage touches no real I/O itself, but it runs on the
          // form's zone; keep the call symmetric with the pick tests.
          await tester.runAsync(() async {
            await formState.clearImage();
          });
          await tester.pumpAndSettle();

          // The host was told the form now holds no photo — this is what a
          // host guard compares against the stored path.
          expect(reportedCalls, 1);
          expect(
            reportedPath,
            isNull,
            reason: 'a clear must report null through onImageChanged',
          );

          // Nothing reached the data layer: the stored path is unchanged
          // and its managed file survives (D-92a.2).
          final stillStored = (await repo.getCatalogFoodById(existingId))!;
          expect(
            stillStored.imagePath,
            basename,
            reason: 'a cleared photo must not be written before Save (D-92a.2)',
          );
          expect(
            managedPath.existsSync(),
            isTrue,
            reason: 'the managed file must survive until Save',
          );

          // Save carries the null in the draft, and only then does the row
          // lose the path and the state method delete the replaced file.
          await tester.runAsync(() async {
            controller.submit();
            final deadline = DateTime.now().add(const Duration(seconds: 5));
            while (DateTime.now().isBefore(deadline)) {
              final food = await repo.getCatalogFoodById(existingId);
              if (food?.imagePath == null) break;
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();

          final updated = (await repo.getCatalogFoodById(existingId))!;
          expect(updated.imagePath, isNull);
          expect(
            managedPath.existsSync(),
            isFalse,
            reason: 'Save must delete the replaced managed file (D-7)',
          );
        },
      );

      testWidgets(
        'clearImage in create mode (initial == null) reports null and saves nothing',
        (WidgetTester tester) async {
          // Create mode has no stored food, so the clear only unsets the
          // form-local photo; the user saves the whole food via the Save
          // button.
          final imageStorage = TestImageStorage.create();
          addTearDown(imageStorage.dispose);
          final repo = MockWorkoutRepository();
          await repo.initialize();
          final foodLibraryState = FoodLibraryState(
            repo,
            imageStorage: imageStorage.service,
          );

          var saveCalls = 0;
          String? reportedPath;
          var reportedCalls = 0;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: FoodForm(
                  initial: null, // create mode
                  foodLibraryState: foodLibraryState,
                  skipPopOnSave: true,
                  onImageChanged: (path) {
                    reportedCalls++;
                    reportedPath = path;
                  },
                  onSave: (_) async {
                    saveCalls++;
                    return true;
                  },
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

          expect(reportedCalls, 1);
          expect(reportedPath, isNull);
          expect(
            saveCalls,
            0,
            reason: 'a clear must not trigger a save in create mode',
          );
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
