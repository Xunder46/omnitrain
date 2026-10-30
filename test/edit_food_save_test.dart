// filepath: test/edit_food_save_test.dart
//
// S-92a.1..4 — Edit Food gets a bottom **Save** and the same unsaved-work
// guard New Food has (plan `2026-10-29-92a-edit-food-save-plan`).
//
// The rule these tests pin: nothing is written until Save is tapped, and a
// back path (header arrow) with edits asks "Unsaved changes" first. The
// form's text fields used to save on blur, so typing a name and leaving the
// field wrote the food without any confirmation.
//
// Mock-only: the screen writes through `FoodLibraryState` on a
// `MockWorkoutRepository`; no Hive, no real file I/O.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/edit_food_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';

const String _trailMixId = 'edit-food-trail-mix';

/// A user-created catalog food (`isCatalog: true`) — the one kind of row
/// `EditFoodScreen` edits in place, with no shipped original behind it.
const Food _trailMix = Food(
  id: _trailMixId,
  name: 'Trail Mix',
  groupId: null,
  unitType: FoodUnitType.grams,
  referenceAmount: 100,
  referenceLabel: 'g',
  isCatalog: true,
  protein: 12,
  carbs: 40,
  fiber: 4,
  fat: 18,
  createdAtMs: 1000,
  updatedAtMs: 1000,
);

typedef _Fixture = ({
  MockWorkoutRepository repo,
  FoodLibraryState foodLib,
  Food loaded,
});

Future<_Fixture> _seedTrailMix() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  await repo.seedCatalogFood(_trailMix);
  final foodLib = FoodLibraryState(repo);
  await foodLib.loadCatalogFoods();
  final loaded = foodLib.catalogFoods.firstWhere((f) => f.id == _trailMixId);
  return (repo: repo, foodLib: foodLib, loaded: loaded);
}

/// Pushes [EditFoodScreen] from a host route, so a pop lands back on a real
/// screen and `find.byType(EditFoodScreen)` tells us whether it is open.
class _Host extends StatelessWidget {
  const _Host({required this.food, required this.foodLibraryState});

  final Food food;
  final FoodLibraryState foodLibraryState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EditFoodScreen(
                food: food,
                foodLibraryState: foodLibraryState,
              ),
            ),
          ),
          child: const Text('open editor'),
        ),
      ),
    );
  }
}

Future<void> _openEditor(WidgetTester tester, _Fixture setup) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: _Host(food: setup.loaded, foodLibraryState: setup.foodLib),
    ),
  );
  await tester.tap(find.text('open editor'));
  await tester.pumpAndSettle();
  expect(find.byType(EditFoodScreen), findsOneWidget);
}

/// The stored name after a short real-time settle window, so an instant
/// write (blur save) has room to land before a "nothing was written"
/// assertion. No fixed sleep: the window ends as soon as the value shows up.
Future<String?> _storedNameAfterSettle(
  MockWorkoutRepository repo, [
  Duration window = const Duration(seconds: 1),
]) async {
  final deadline = DateTime.now().add(window);
  var name = (await repo.getCatalogFoodById(_trailMixId))?.name;
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    name = (await repo.getCatalogFoodById(_trailMixId))?.name;
  }
  return name;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S-92a.1: Save writes the edited food and closes the screen', (
    tester,
  ) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    expect(
      find.byKey(const Key('food_form_save')),
      findsOneWidget,
      reason: 'Edit Food must offer the bottom Save (D-92a.1)',
    );

    await tester.enterText(
      find.byKey(const Key('food_form_name')),
      'Trail Mix 2',
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('food_form_save')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        if ((await setup.repo.getCatalogFoodById(_trailMixId))?.name ==
            'Trail Mix 2') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(
      (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
      'Trail Mix 2',
      reason: 'Save must write the edited name through updateCatalogFood',
    );
    expect(
      find.byType(EditFoodScreen),
      findsNothing,
      reason: 'Save closes the screen after a successful write',
    );
  });

  testWidgets('S-92a.2: focus leaving the form writes nothing', (tester) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    await tester.enterText(
      find.byKey(const Key('food_form_name')),
      'Trail Mix 2',
    );
    await tester.pump();

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final stored = await tester.runAsync(
      () => _storedNameAfterSettle(setup.repo),
    );
    expect(
      stored,
      'Trail Mix',
      reason: 'blur must not save; only the Save button writes (D-92a.3)',
    );
    expect(
      find.byType(EditFoodScreen),
      findsOneWidget,
      reason: 'a blur is not an exit; the editor stays open',
    );
  });

  testWidgets(
    'S-92a.3: back with edits asks; Discard drops them and Keep editing stays',
    (tester) async {
      final setup = await _seedTrailMix();
      await _openEditor(tester, setup);

      // Discard leg.
      await tester.enterText(
        find.byKey(const Key('food_form_name')),
        'Trail Mix 2',
      );
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.text('Unsaved changes'),
        findsOneWidget,
        reason: 'an edited form must ask before it closes',
      );
      await tester.tap(find.byKey(const Key('edit-food-unsaved-discard')));
      await tester.pumpAndSettle();
      expect(find.byType(EditFoodScreen), findsNothing);
      expect(
        (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
        'Trail Mix',
        reason: 'Discard must leave the stored food alone',
      );

      // Keep-editing leg.
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('food_form_name')),
        'Trail Mix 3',
      );
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-food-unsaved-keep')));
      await tester.pumpAndSettle();
      expect(
        find.byType(EditFoodScreen),
        findsOneWidget,
        reason: 'Keep editing must leave the editor open',
      );
      expect(
        find.text('Trail Mix 3'),
        findsOneWidget,
        reason: 'Keep editing must preserve the typed name',
      );
      expect(
        (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
        'Trail Mix',
        reason: 'Keep editing must not write either',
      );
    },
  );

  testWidgets('S-92a.4: back on an untouched form closes with no dialog', (
    tester,
  ) async {
    final setup = await _seedTrailMix();
    await _openEditor(tester, setup);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.text('Unsaved changes'),
      findsNothing,
      reason: 'an untouched form has nothing to discard',
    );
    expect(find.byType(EditFoodScreen), findsNothing);
    expect(
      (await setup.repo.getCatalogFoodById(_trailMixId))!.name,
      'Trail Mix',
    );
  });
}
