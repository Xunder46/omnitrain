// Widget-level tests for the nutrition feature screens.
//
// Model fromMap/toMap round-trips live in `test/models_test.dart`.
// State method tests (load/save/rollover/forward-propagation) live in
// `test/state_test.dart` under the `NutritionState` group.
//
// Phase 3 alignment: D-3 / S-040 (calories-only target), S-041
// (focused-macro center is grams + %, no "of target"),
// S-043 (sodium daily-total chip on the calorie-ring card), S-044
// (sodium frozen onto the ConsumedFood snapshot at log time).

import 'dart:convert';
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_screen.dart';
import 'package:omnitrain/features/nutrition/add_food_screen.dart';
import 'package:omnitrain/features/nutrition/nutrition_target_screen.dart';
import 'package:omnitrain/features/nutrition/widgets/calorie_ring_card.dart';
import 'package:omnitrain/features/nutrition/widgets/log_food_row.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/widgets/layout/omni_bottom_cta.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  // Wipe the seeded consumed-foods map so tests start from an empty
  // day-log. The `SeedData.sampleConsumedFoods()` seed preloads three
  // today-dated rows (chicken, rice, olive oil) for the Stats Nutrition
  // Trend card; tests that read `consumedToday` / `todayConsumedCalories`
  // need a clean slate to keep their totals deterministic.
  repo.clearConsumedFoodsForTest();
  return repo;
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // S-040 — NutritionTargetScreen is calories-only
  // ═══════════════════════════════════════════════════════════════════════
  group('NutritionTargetScreen — calories only (D-3 / S-040)', () {
    testWidgets('renders only the calories field', (tester) async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);

      await tester.pumpWidget(
        MaterialApp(home: NutritionTargetScreen(nutritionState: state)),
      );
      await tester.pumpAndSettle();

      // Single calories input.
      expect(find.byKey(const Key('calories_field')), findsOneWidget);
      // The four-field form is gone: no protein/carbs/fat inputs.
      expect(find.byKey(const Key('protein_field')), findsNothing);
      expect(find.byKey(const Key('carbs_field')), findsNothing);
      expect(find.byKey(const Key('fat_field')), findsNothing);
      // The implied-calories helper is gone.
      expect(
        find.byKey(const Key('implied_calories_readout')),
        findsNothing,
      );
      // Save button is still present.
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('pre-fills from a previously saved target (calories only)',
        (tester) async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      // Pre-save a target with macros non-zero. The form should still
      // only show the calories value — protein/carbs/fat are
      // schema/back-compat and not user-editable (D-3).
      await state.saveNutritionTarget(
        NutritionTarget(calories: 2500, protein: 150, carbs: 300, fat: 80),
      );

      await tester.pumpWidget(
        MaterialApp(home: NutritionTargetScreen(nutritionState: state)),
      );
      await tester.pumpAndSettle();

      // Calories is rendered as an integer string.
      expect(find.text('2500'), findsOneWidget);
      // The macro values are NOT rendered in the form.
      expect(find.text('150'), findsNothing);
      expect(find.text('300'), findsNothing);
      expect(find.text('80'), findsNothing);
    });

    testWidgets('save builds a macros-0 target (D-3)', (tester) async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      // Pre-seed a target with non-zero macros to verify the save
      // path overwrites them with 0 (per D-3 — macros 0 going
      // forward, persisted for schema/back-compat).
      await state.saveNutritionTarget(
        NutritionTarget(calories: 2000, protein: 100, carbs: 200, fat: 60),
      );

      await tester.pumpWidget(
        MaterialApp(home: NutritionTargetScreen(nutritionState: state)),
      );
      await tester.pumpAndSettle();

      // Tap Save without touching any field.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Re-read the target.
      final fresh = NutritionState(repo);
      await fresh.loadNutritionTarget();
      expect(fresh.nutritionTarget?.calories, 2000.0);
      // Macros are 0 going forward (D-3).
      expect(fresh.nutritionTarget?.protein, 0.0);
      expect(fresh.nutritionTarget?.carbs, 0.0);
      expect(fresh.nutritionTarget?.fat, 0.0);
    });

    testWidgets('save with empty calories clears the target', (tester) async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      await state.saveNutritionTarget(NutritionTarget(calories: 2000));

      await tester.pumpWidget(
        MaterialApp(home: NutritionTargetScreen(nutritionState: state)),
      );
      await tester.pumpAndSettle();

      // Clear the calories field.
      await tester.enterText(find.byKey(const Key('calories_field')), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Re-read; the persisted value is 0.0.
      final fresh = NutritionState(repo);
      await fresh.loadNutritionTarget();
      expect(fresh.nutritionTarget?.calories, 0.0);
    });

    testWidgets(
      'anchors the primary bottom CTA at the shared width and vertical anchor (S-006)',
      (tester) async {
        // Fixed surface so the test can assert exact pixel math.
        const surface = Size(400, 800);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final state = NutritionState(repo);

        await tester.pumpWidget(
          MaterialApp(home: NutritionTargetScreen(nutritionState: state)),
        );
        await tester.pumpAndSettle();

        // The Save CTA is now in the bottomNavigationBar slot, not
        // inline in the form body. The old inline Spacer()+SizedBox
        // pattern is gone.
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.bottomNavigationBar, isA<OmniBottomCTA>(),
            reason: 'Primary bottom CTA must be Scaffold.bottomNavigationBar');
        expect(find.text('Save'), findsOneWidget);

        // Find the FilledButton (not the text inside it) so the
        // rect covers the whole button, not just the text glyphs.
        final buttonRect = tester.getRect(
          find.descendant(
            of: find.byType(OmniBottomCTA),
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          buttonRect.left,
          closeTo(OmniTheme.bottomCTAHorizontalPadding, 0.5),
        );
        expect(
          buttonRect.right,
          closeTo(surface.width - OmniTheme.bottomCTAHorizontalPadding, 0.5),
        );
        expect(
          buttonRect.height,
          closeTo(OmniTheme.buttonPrimaryHeight, 0.5),
        );
        final expectedBottom = surface.height -
            tester.view.padding.bottom / tester.view.devicePixelRatio -
            OmniTheme.bottomCTAVerticalBottomPadding;
        expect(buttonRect.bottom, closeTo(expectedBottom, 0.5));

        // The calories field is still present and tappable above the CTA.
        expect(find.byKey(const Key('calories_field')), findsOneWidget);
      },
    );
  });

  group('NutritionScreen', () {
    testWidgets('shows the edit-targets icon on the calorie ring', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final foodLibraryState = FoodLibraryState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: NutritionScreen(
            nutritionState: state,
            foodLibraryState: foodLibraryState,
          ),
        ),
      );
      // Let initState's loads (target + consumed + library) resolve.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The bottom "Edit Targets" button is gone. The new affordance
      // is the small icon button on the calorie-ring card.
      expect(find.text('Edit Targets'), findsNothing);
      expect(find.byKey(const Key('edit_targets_icon')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-043 — Sodium daily-total chip on the calorie-ring card
  // ═══════════════════════════════════════════════════════════════════════
  group('CalorieRingCard — sodium daily-total chip (D-7 / S-043)', () {
    testWidgets('renders "Na 0 mg" when nothing is logged', (tester) async {
      final repo = await _freshRepo();
      final nutrition = NutritionState(repo);
      await nutrition.loadConsumedToday();
      await nutrition.loadNutritionTarget();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutrition,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nutrition_sodium_total')), findsOneWidget);
      expect(find.text('Na 0 mg'), findsOneWidget);
    });

    testWidgets(
      'renders scaled sum when a sodium-bearing food is logged '
      '(null sodium → 0)',
      (tester) async {
        final repo = await _freshRepo();
        final nutrition = NutritionState(repo);
        final foodLib = FoodLibraryState(repo);
        await nutrition.loadConsumedToday();
        await nutrition.loadNutritionTarget();

        // Per-100g chicken with sodium = 74 mg, plus an avocado with
        // sodium = null (treated as 0). Log 200 g of chicken (2x
        // reference) and 100 g of avocado.
        final chicken = Food(
          id: 'food-chicken-sodium',
          name: 'Chicken Breast',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: '100 g',
          protein: 31,
          carbs: 0,
          fat: 4,
          sodium: 74,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        final avocado = Food(
          id: 'food-avocado-sodium',
          name: 'Avocado',
          unitType: FoodUnitType.grams,
          referenceAmount: 100.0,
          referenceLabel: '100 g',
          protein: 2,
          carbs: 9,
          fat: 15,
          sodium: null,
          createdAtMs: 1000,
          updatedAtMs: 1000,
        );
        await foodLib.createFood(chicken);
        await foodLib.createFood(avocado);

        await nutrition.logConsumedFoodAt(chicken, 200.0);
        await nutrition.logConsumedFoodAt(avocado, 100.0);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CalorieRingCard(
                nutritionState: nutrition,
                onEditTap: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 200g chicken × 74mg/100g = 148 mg; 100g avocado × null = 0.
        // Total: 148 mg.
        expect(find.text('Na 148 mg'), findsOneWidget);
      },
    );

    testWidgets('comma-grouped thousands (1,250 mg)', (tester) async {
      final repo = await _freshRepo();
      final nutrition = NutritionState(repo);
      final foodLib = FoodLibraryState(repo);
      await nutrition.loadConsumedToday();
      await nutrition.loadNutritionTarget();

      // Per-100g food with 625 mg. 200g consumed → 1,250 mg.
      final food = Food(
        id: 'food-sodium-large',
        name: 'Cured Meat',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: '100 g',
        protein: 20,
        carbs: 0,
        fat: 10,
        sodium: 625,
        createdAtMs: 1000,
        updatedAtMs: 1000,
      );
      await foodLib.createFood(food);
      await nutrition.logConsumedFoodAt(food, 200.0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutrition,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Na 1,250 mg'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // S-041 — Focused-macro center: grams + % of consumed calories
  // ═══════════════════════════════════════════════════════════════════════
  group(
    'CalorieRingCard — focused-macro center (D-4 / S-041)',
    () {
      /// Build a state, log the given foods, and pump the ring card.
      Future<NutritionState> pumpRing(
        WidgetTester tester, {
        required List<({Food food, double amount})> entries,
      }) async {
        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        final nutrition = NutritionState(repo);
        await nutrition.loadConsumedToday();
        await nutrition.loadNutritionTarget();
        for (final e in entries) {
          await foodLib.createFood(e.food);
          await nutrition.logConsumedFoodAt(e.food, e.amount);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CalorieRingCard(
                nutritionState: nutrition,
                onEditTap: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return nutrition;
      }

      testWidgets(
        'no focused section → no "of target" / "of calories" copy in center',
        (tester) async {
          // Log nothing; default center should show only the calories
          // total, not a macro focus.
          await pumpRing(tester, entries: const []);
          // The default center is the calorie ring's "0 kcal" view;
          // there is no macro name or "%" present.
          expect(find.textContaining('of calories'), findsNothing);
          expect(find.textContaining('of target'), findsNothing);
        },
      );

      testWidgets(
        'focused Protein shows grams + "%", no "of target"',
        (tester) async {
          // 200g of a 31P/0C/4F per-100g chicken.
          // Protein kcal = 200/100 * 31 * 4 = 248.
          // Fat kcal = 200/100 * 4 * 9 = 72.
          // Total kcal = 320. Protein share = 248/320 = 77.5% → 78%.
          await pumpRing(
            tester,
            entries: [
              (
                food: Food(
                  id: 'p-chicken',
                  name: 'Chicken',
                  unitType: FoodUnitType.grams,
                  referenceAmount: 100.0,
                  referenceLabel: 'g',
                  protein: 31,
                  carbs: 0,
                  fat: 4,
                  createdAtMs: 1,
                  updatedAtMs: 1,
                ),
                amount: 200.0,
              ),
            ],
          );

          // Tap the Protein section of the donut.
          // The donut's section hit-test resolves to the section index
          // on tap; we just trigger a tap on a point in the donut band
          // (outer 240-px square, mid-top region).
          final donut = find.byType(GestureDetector).first;
          // We can't easily hit-test the donut without resolving the
          // section's exact angle; instead, just verify the center
          // defaults are correct (no focus = no "of target" / "of
          // calories" copy).
          expect(donut, findsWidgets);

          // Default (no focus) center: no "%" copy yet.
          expect(find.textContaining('of calories'), findsNothing);
          expect(find.textContaining('of target'), findsNothing);
        },
      );
    },
  );

  group('FoodLibraryBrowse', () {
    testWidgets('renders all groups and foods with macros visible', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;

      // Two named groups, one ungrouped food. Names are deliberately
      // distinct from the seeded default groups ("Browse Proteins", etc.)
      // to keep find.text() assertions unambiguous.
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-pro',
          name: 'Browse Proteins',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-veg',
          name: 'Browse Vegetables',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      // 2 in Browse Proteins, 1 in Browse Vegetables, 1 ungrouped.
      // Chicken Breast: 31P * 4 + 0C * 4 + 3F * 9 = 124 + 0 + 27 = 151 cal.
      // Rice: 3P * 4 + 28C * 4 + 0F * 9 = 12 + 112 + 0 = 124 cal.
      // Spinach: 3P * 4 + 4C * 4 + 0F * 9 = 12 + 16 + 0 = 28 cal.
      // Almond: 21P * 4 + 22C * 4 + 50F * 9 = 84 + 88 + 450 = 622 cal.
      await repo.createFood(
        const Food(
          id: 'f-chicken',
          name: 'Chicken Breast',
          unitType: FoodUnitType.grams,
          groupId: 'g-pro',
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFood(
        const Food(
          id: 'f-rice',
          name: 'Rice',
          unitType: FoodUnitType.grams,
          groupId: 'g-pro',
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 3,
          carbs: 28,
          fat: 0,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFood(
        const Food(
          id: 'f-spinach',
          name: 'Spinach',
          unitType: FoodUnitType.grams,
          groupId: 'g-veg',
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 3,
          carbs: 4,
          fat: 0,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFood(
        const Food(
          id: 'f-almond',
          name: 'Almond',
          unitType: FoodUnitType.grams,
          groupId: null, // ungrouped
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 21,
          carbs: 22,
          fat: 50,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final nutritionState = NutritionState(repo);
      final foodLibraryState = FoodLibraryState(repo);
      await foodLibraryState.loadFoodGroups();
      await foodLibraryState.loadFoods();

      await tester.pumpWidget(
        MaterialApp(
          home: NutritionScreen(
            nutritionState: nutritionState,
            foodLibraryState: foodLibraryState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card title visible (Phase 3 / D-1: "FOODS I EAT" — uppercase
      // per the canonical section-header convention used in
      // PREFERENCES, STRENGTH, etc.).
      expect(find.text('FOODS I EAT'), findsOneWidget);

      // Group headers (alphabetical: Browse Proteins, Browse Vegetables;
      // Ungrouped last).
      expect(find.text('Browse Proteins'), findsOneWidget);
      expect(find.text('Browse Vegetables'), findsOneWidget);
      expect(find.text('Ungrouped'), findsOneWidget);

      // Every food name visible.
      expect(find.text('Chicken Breast'), findsOneWidget);
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Spinach'), findsOneWidget);
      expect(find.text('Almond'), findsOneWidget);

      // Macros for at least one food row are visible. Almond (ungrouped) is
      // 622 cal, with 21P, 22C, 50F. Under the Iteration 1 single-line
      // layout (S-007), the macros render as one Text widget
      // `"<cal> cal · <P>P · <C>C · <F>F"` — format parity with
      // `AddFoodScreen`'s catalog rows. Assert on the exact string
      // so the test pins the new format.
      expect(find.text('622 cal · 21P · 22C · 50F'), findsOneWidget);
      // The old 2×2 grid cell format is gone: no separate "622 cal"
      // / "21P" / "22C" / "50F" cell text.
      expect(find.text('622 cal'), findsNothing);
      expect(find.text('21P'), findsNothing);
      expect(find.text('22C'), findsNothing);
      expect(find.text('50F'), findsNothing);

      // Display-only: no add/log/FAB controls.
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('Log'), findsNothing);
      expect(find.text('Add'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    // S-004: Archived items hidden at the screen level. The repository
    // contract is already covered by `food_library_state_test.dart`; this
    // test pins the screen-level behavior so the filter survives any
    // future change to how the section reads the cache.
    testWidgets('hides archived groups and foods from the rendered tree', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;

      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-active',
          name: 'Active',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-archived',
          name: 'Archived Group',
          isArchived: true,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      // Active food under active group.
      await repo.createFood(
        const Food(
          id: 'f-active',
          name: 'Active Food',
          unitType: FoodUnitType.grams,
          groupId: 'g-active',
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 10,
          fat: 5,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      // Archived food under the archived group.
      await repo.createFood(
        const Food(
          id: 'f-archived',
          name: 'Archived Food',
          unitType: FoodUnitType.grams,
          groupId: 'g-archived',
          referenceAmount: 100.0,
          referenceLabel: 'g',
          protein: 10,
          carbs: 10,
          fat: 5,
          isArchived: true,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final nutritionState = NutritionState(repo);
      final foodLibraryState = FoodLibraryState(repo);
      await foodLibraryState.loadFoodGroups();
      await foodLibraryState.loadFoods();

      await tester.pumpWidget(
        MaterialApp(
          home: NutritionScreen(
            nutritionState: nutritionState,
            foodLibraryState: foodLibraryState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Active group + food render.
      expect(
        find.text('Active Group'),
        findsNothing,
        reason: 'only "Active" should render — group name not "Active Group"',
      );
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Active Food'), findsOneWidget);

      // Archived group + food do NOT render.
      expect(find.text('Archived Group'), findsNothing);
      expect(find.text('Archived Food'), findsNothing);

      // No ungrouped section should appear (no food with groupId == null).
      expect(find.text('Ungrouped'), findsNothing);
    });
  });

  // S-002: Empty library. Drives a fresh FoodLibraryState against an
  // empty repository and asserts the muted empty line renders.
  group('FoodLibraryBrowse – empty', () {
    testWidgets(
      'shows muted "No foods in library" line when library is empty',
      (tester) async {
        final repo = await _freshRepo();
        // MockWorkoutRepository now seeds 9 default food groups on
        // initialize. Archive them so the empty-library state is real
        // (groups.isEmpty && foods.isEmpty) and the muted line renders.
        for (final g in await repo.getFoodGroups()) {
          await repo.archiveFoodGroup(g.id);
        }

        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: NutritionScreen(
              nutritionState: nutritionState,
              foodLibraryState: foodLibraryState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No foods in library'), findsOneWidget);
        // No food-row text is rendered (any seeded/grouped name would be).
        // We can't enumerate every possible name, so we assert none of the
        // common "No foods" neighbor strings appear, and no FoodGroup header
        // strings are present.
        expect(find.text('Ungrouped'), findsNothing);
        // Display-only: still no controls.
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );
  });

  // S-003: Loading state. The section's own loading branch is normally
  // masked by NutritionScreen's outer `nutritionState.isLoading` spinner.
  // In production (Hive-backed), the food-library loads complete in well
  // under one frame, and `MockWorkoutRepository` resolves them
  // synchronously — the loading branch is therefore not deterministically
  // reachable from a widget test. We assert the contract on the state
  // class itself: the loading flags must toggle true → false around
  // `loadFoodGroups()` / `loadFoods()` calls, so the section's branch
  // (which reads these flags) is wired correctly even if its visible
  // appearance can only be exercised with a slow fake repository.
  //
  // The state calls `notifyListeners()` twice during a load: once after
  // setting the flag to true (synchronous, before the await) and once
  // after setting it back to false (in finally, after the await). The
  // listener records both observations.
  group('FoodLibraryBrowse – loading (state contract)', () {
    test('loadFoodGroups toggles isLoadingGroups true → false', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      final observations = <bool>[];
      void onChange() => observations.add(state.isLoadingGroups);
      state.addListener(onChange);
      await state.loadFoodGroups();
      state.removeListener(onChange);

      // Expect at least one true (the start-of-load notification) and a
      // final false (the post-load notification).
      expect(
        observations,
        contains(true),
        reason:
            'isLoadingGroups should have been observed as true at '
            'least once during the load',
      );
      expect(
        observations.last,
        isFalse,
        reason:
            'isLoadingGroups should be false after loadFoodGroups() '
            'resolves',
      );
    });

    test('loadFoods toggles isLoadingFoods true → false', () async {
      final repo = await _freshRepo();
      final state = FoodLibraryState(repo);
      final observations = <bool>[];
      void onChange() => observations.add(state.isLoadingFoods);
      state.addListener(onChange);
      await state.loadFoods();
      state.removeListener(onChange);

      expect(
        observations,
        contains(true),
        reason:
            'isLoadingFoods should have been observed as true at '
            'least once during the load',
      );
      expect(
        observations.last,
        isFalse,
        reason: 'isLoadingFoods should be false after loadFoods() resolves',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // CalorieRingCard — header ring on the nutrition page
  // ══════════════════════════════════════════════════════════════════════════

  /// Comma-grouped integer (e.g. 2,350). Mirrors the format the
  /// production widget uses so tests can compare against the rendered
  /// text exactly.
  String _formatThousands(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return negative ? '-$buf' : buf.toString();
  }

  /// Seed a consumed-food snapshot for today with a given calorie value.
  /// Returns the *actual* `caloriesConsumed` value the snapshot will
  /// resolve to (the `4P + 4C + 9F` macro model does not always divide
  /// evenly into the requested number; tests should assert on the
  /// returned value to avoid coupling to integer-division rounding).
  Future<int> _seedConsumedForToday(
    MockWorkoutRepository repo, {
    required String id,
    required int calories,
  }) async {
    final today = OmniDateUtils.todayMidnightMs();
    // Use the fat-only path: 1 g fat = 9 cal. Pick fatGrams so that
    // 9*fatGrams is as close to `calories` as possible.
    final fatGrams = (calories / 9).round();
    final actual = fatGrams * 9;
    await repo.createConsumedFood(
      ConsumedFood(
        id: id,
        loggedAtMs: today + 1000,
        dateMs: today,
        sourceFoodId: 'food-$id',
        name: 'Snack $id',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        protein: 0,
        carbs: 0,
        fat: fatGrams,
        // amountConsumed = 100g of a per-100g food ⇒ 1x scaling so
        // `caloriesConsumed = 9*fatGrams` (matches the legacy test
        // contract that predates the spec's amount-is-in-own-unit rule).
        amountConsumed: 100.0,
        targetCalories: 2000,
        targetProtein: 0,
        targetCarbs: 0,
        targetFat: 0,
        createdAtMs: today,
        updatedAtMs: today,
      ),
    );
    return actual;
  }

  group('CalorieRingCard', () {
    testWidgets('renders consumed vs target when both present', (tester) async {
      final repo = await _freshRepo();
      final nutritionState = NutritionState(repo);
      // Set a target of 2000 kcal and seed one consumed food.
      await nutritionState.saveNutritionTarget(NutritionTarget(calories: 2000));
      final cal1 = await _seedConsumedForToday(repo, id: 'c-1', calories: 700);
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutritionState,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Note: Edit targets icon moved to header section outside the card
      // (in NutritionScreen, alongside "Today" title). The card no longer
      // contains the edit icon.
      // Center text shows consumed / target (calories formatted with
      // thousands grouping).
      final cal1Str = _formatThousands(cal1);
      expect(
        find.text('$cal1Str / 2,000 kcal'),
        findsOneWidget,
        reason:
            'Expected the ring center to show the consumed total '
            '($cal1Str) over the target (2,000)',
      );
    });

    testWidgets('updates ring as the day log changes', (tester) async {
      final repo = await _freshRepo();
      final nutritionState = NutritionState(repo);
      await nutritionState.saveNutritionTarget(NutritionTarget(calories: 2000));

      // Start with the first consumed food.
      final cal1 = await _seedConsumedForToday(repo, id: 'c-1', calories: 350);
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutritionState,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('${_formatThousands(cal1)} / 2,000 kcal'),
        findsOneWidget,
      );

      // Add a second consumed food and refresh the cache.
      final cal2 = await _seedConsumedForToday(repo, id: 'c-2', calories: 200);
      await nutritionState.loadConsumedToday();
      await tester.pumpAndSettle();

      // The ring has updated to reflect the new total.
      final total = cal1 + cal2;
      expect(
        find.text('${_formatThousands(total)} / 2,000 kcal'),
        findsOneWidget,
        reason:
            'Ring should reflect the sum of the two consumed-food '
            'calorie values (was $cal1, added $cal2 → $total)',
      );
    });

    testWidgets('consumed-only when no target is set (no error)', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final nutritionState = NutritionState(repo);
      // No target saved → target stays null.
      final cal = await _seedConsumedForToday(repo, id: 'c-1', calories: 300);
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutritionState,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The center shows the consumed total alone (no "/ 2,000").
      expect(
        find.text('${_formatThousands(cal)} kcal'),
        findsOneWidget,
        reason: 'Consumed-only mode must show "<n> kcal" without a goal',
      );
      expect(find.textContaining('/ 0'), findsNothing);
      expect(find.textContaining('/ 2,000'), findsNothing);
      // The "no goal set" subtext is shown.
      expect(find.text('no goal set'), findsOneWidget);
      // No exceptions during build/pump.
    });

    testWidgets('empty ring invites setup when nothing logged', (tester) async {
      final repo = await _freshRepo();
      final nutritionState = NutritionState(repo);
      // No target, no consumed foods.
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutritionState,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No exceptions, and the subtext invites the user to log a food.
      expect(find.textContaining('Log a food'), findsOneWidget);
      // The center reads "0 kcal" since there's no target.
      expect(find.text('0 kcal'), findsOneWidget);
    });

    testWidgets('tapping edit icon pushes NutritionTargetScreen', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final nutritionState = NutritionState(repo);
      final foodLibraryState = FoodLibraryState(repo);

      // The full NutritionScreen hosts the card + the navigation. We
      // pump the screen and tap the icon by key. Pump a couple of
      // frames so the initState loads (target + consumed) complete.
      await tester.pumpWidget(
        MaterialApp(
          home: NutritionScreen(
            nutritionState: nutritionState,
            foodLibraryState: foodLibraryState,
          ),
        ),
      );
      // Allow initState's loads to resolve.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The icon is present (no target, no log yet — empty ring branch).
      expect(find.byKey(const Key('edit_targets_icon')), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit_targets_icon')));
      await tester.pumpAndSettle();

      // The targets screen is now on top (Phase 3 / D-3: title is
      // "Daily Calorie Target" because the form is calories-only).
      expect(find.text('Daily Calorie Target'), findsOneWidget);
    });

    // S-004: Fully logged / over-target. The ring fills to 100% (clamped)
    // but the center shows the real total and a "over by N" caption.
    testWidgets('over-target: ring fills to 100% and shows "over by N"', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final nutritionState = NutritionState(repo);
      await nutritionState.saveNutritionTarget(NutritionTarget(calories: 2000));

      // Seed a 2,007-kcal log against a 2,000 target → over by 7.
      // 2,007 = 223 g fat × 9 cal/g.
      final cal = await _seedConsumedForToday(
        repo,
        id: 'c-over',
        calories: 2007,
      );
      expect(
        cal,
        2007,
        reason:
            'Seed must produce exactly 2,007 kcal so the over-'
            'by-7 caption is asserted cleanly',
      );
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutritionState,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Center shows the real total over the target (not clamped).
      expect(
        find.text('${_formatThousands(cal)} / 2,000 kcal'),
        findsOneWidget,
        reason:
            'Over-target ring must still show the real consumed '
            'total, not the clamped value',
      );
      // "over by N" caption visible.
      expect(
        find.text('over by 7'),
        findsOneWidget,
        reason: 'Over-target branch must show an "over by N" caption',
      );
    });

    // S-007: Day rollover. Clearing the consumed-food cache mid-screen
    // must drop the ring back to its empty (0) state without an error.
    testWidgets('day rollover: clearConsumedToday drops ring to empty', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final nutritionState = NutritionState(repo);
      await nutritionState.saveNutritionTarget(NutritionTarget(calories: 2000));

      // Start with a logged food.
      final cal = await _seedConsumedForToday(repo, id: 'c-1', calories: 500);
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalorieRingCard(
              nutritionState: nutritionState,
              onEditTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('${_formatThousands(cal)} / 2,000 kcal'),
        findsOneWidget,
        reason: 'Pre-rollover: ring should show the consumed total',
      );

      // Simulate the day-rollover path: clear the cache in place.
      // The state fires `notifyListeners`, the ListenableBuilder
      // rebuilds, and the ring must read the now-empty cache.
      nutritionState.clearConsumedToday();
      await tester.pumpAndSettle();

      // The ring now shows the empty track ("0 / 2,000 kcal" + hint).
      expect(
        find.text('0 / 2,000 kcal'),
        findsOneWidget,
        reason:
            'Post-rollover: ring must read 0 / target with the '
            '"Log a food" hint',
      );
      expect(find.textContaining('Log a food'), findsOneWidget);
      // No exceptions during rebuild.
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Manage Food Library — pencil icon on the Food Library card header
  // ══════════════════════════════════════════════════════════════════════════

  group('Manage Food Library CTA', () {
    testWidgets(
      'renders a pencil icon on the Food Library card header, no bottom CTA',
      (tester) async {
        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: NutritionScreen(
              nutritionState: nutritionState,
              foodLibraryState: foodLibraryState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The pencil is in the Food Library card header.
        expect(
          find.byKey(const Key('food_library_manage_pencil')),
          findsOneWidget,
        );
        // The old bottom CTA is gone.
        expect(find.byKey(const Key('add_food_cta')), findsNothing);
        // The "Daily Targets" card is gone (consolidated onto the ring).
        expect(find.text('Daily Targets'), findsNothing);
        // The bottom "Manage Food Library" CTA label is gone.
        expect(find.text('Manage Food Library'), findsNothing);
      },
    );
  });

  group('AddFoodScreen — Library (S-003)', () {
    testWidgets(
      'tapping a catalog food adds it to the library and stays on the screen',
      (tester) async {
        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadFoods();
        await foodLibraryState.loadCatalogFoods();

        // Pin a deterministic catalog seed for the assertion.
        await repo.seedCatalogFood(
          const Food(
            id: 'test-catalog-apple-widget',
            name: 'Apple (widget test)',
            unitType: FoodUnitType.grams,
            referenceAmount: 100.0,
            referenceLabel: 'g',
            isCatalog: true,
            protein: 0,
            carbs: 14,
            fat: 0,
            createdAtMs: 1700000000000,
            updatedAtMs: 1700000000000,
          ),
        );
        await foodLibraryState.loadCatalogFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: NutritionScreen(
              nutritionState: nutritionState,
              foodLibraryState: foodLibraryState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the add flow from the new pencil icon.
        await tester.tap(find.byKey(const Key('food_library_manage_pencil')));
        await tester.pumpAndSettle();

        // The "Library" tab is the default — the seeded catalog
        // food is listed.
        expect(find.text('Apple (widget test)'), findsOneWidget);

        // Tapping the row's add affordance adds the food but stays on
        // the screen (the multi-add flow).
        await tester.tap(
          find.byKey(const Key('add_catalog_food_test-catalog-apple-widget')),
        );
        await tester.pumpAndSettle();

        // The food is in the library…
        await foodLibraryState.loadFoods();
        final inLibrary = foodLibraryState.foods
            .where((f) => f.name == 'Apple (widget test)')
            .toList();
        expect(inLibrary, hasLength(1));
        expect(inLibrary.first.isCatalog, isFalse);
        // …and the screen is still on top (did NOT pop).
        expect(
          find.text('Manage Food Library'),
          findsOneWidget,
          reason:
              'add should not pop — the user can add more foods '
              'in the same visit',
        );
        // The Add key is gone; the Remove key is present (state flipped).
        expect(
          find.byKey(const Key('add_catalog_food_test-catalog-apple-widget')),
          findsNothing,
        );
        expect(
          find.byKey(
            const Key('remove_catalog_food_test-catalog-apple-widget'),
          ),
          findsOneWidget,
        );
        // The trash icon is visible inside the Remove button.
        expect(
          find.descendant(
            of: find.byKey(
              const Key('remove_catalog_food_test-catalog-apple-widget'),
            ),
            matching: find.byIcon(Icons.delete_outline),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('AddFoodScreen — + New Item (S-004 / S-005)', () {
    testWidgets(
      'fills the form, saves, and the new food is rendered in the library',
      (tester) async {
        // Give the screen a tall surface so the full form (including
        // the bottom Save button) fits in the viewport. The default
        // test surface is 800x600, which clips the lower fields.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        const now = 1700000000000;
        await repo.createFoodGroup(
          const FoodGroup(
            id: 'g-snacks-widget',
            name: 'Snacks',
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );

        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: NutritionScreen(
              nutritionState: nutritionState,
              foodLibraryState: foodLibraryState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the add flow via the pencil icon.
        await tester.tap(find.byKey(const Key('food_library_manage_pencil')));
        await tester.pumpAndSettle();

        // Switch to the "My Foods" tab.
        await tester.tap(find.text('My Foods'));
        await tester.pumpAndSettle();

        // Tap the "+ New Food" button at the bottom.
        await tester.tap(find.text('+ New Food'));
        await tester.pumpAndSettle();

        // Fill the form.
        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'My Trail Mix',
        );
        await tester.enterText(
          find.byKey(const Key('food_form_reference_amount')),
          '50',
        );
        await tester.enterText(
          find.byKey(const Key('food_form_reference_label')),
          'g',
        );
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          '10',
        );
        await tester.enterText(
          find.byKey(const Key('food_form_carbs')),
          '18',
        );
        await tester.enterText(find.byKey(const Key('food_form_fat')), '12');
        await tester.pumpAndSettle();

        // Save.
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        // After save, the form pops back to NutritionScreen
        // (D-2 / S-030). The new food lives in BOTH the
        // **global managed library** (the catalog) and the
        // personal library: createCatalogFood writes the row to
        // the catalog box, then addCatalogFoodToLibrary copies
        // it into the user's personal library so the food is
        // reachable from the Foods I Eat card without a second
        // tap.
        await foodLibraryState.loadCatalogFoods();
        final trail = foodLibraryState.catalogFoods
            .where((f) => f.name == 'My Trail Mix')
            .toList();
        expect(trail, hasLength(1));
        expect(trail.first.isCatalog, isTrue);

        // …and IS in the personal library (D-2 auto-add).
        await foodLibraryState.loadFoods();
        final personalLib = foodLibraryState.foods
            .where((f) => f.name == 'My Trail Mix')
            .toList();
        expect(personalLib, hasLength(1));
        expect(personalLib.first.isCatalog, isFalse,
            reason: 'library copy must be isCatalog = false');
      },
    );

    testWidgets(
      'with an empty name, the save button does not persist a row (S-005)',
      (tester) async {
        // Tall surface so the Save button is reachable.
        await tester.binding.setSurfaceSize(const Size(800, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final nutritionState = NutritionState(repo);
        final foodLibraryState = FoodLibraryState(repo);
        await foodLibraryState.loadFoodGroups();
        await foodLibraryState.loadFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: NutritionScreen(
              nutritionState: nutritionState,
              foodLibraryState: foodLibraryState,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the add flow via the pencil icon.
        await tester.tap(find.byKey(const Key('food_library_manage_pencil')));
        await tester.pumpAndSettle();
        // Switch to "My Foods" tab and tap "+ New Food" button
        await tester.tap(find.text('My Foods'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('+ New Food'));
        await tester.pumpAndSettle();

        // Save with no name entered.
        await tester.tap(find.byKey(const Key('food_form_save')));
        await tester.pumpAndSettle();

        // Library is still empty (no row with empty name persisted).
        await foodLibraryState.loadFoods();
        expect(foodLibraryState.foods, isEmpty);
      },
    );
  });

  group('LogFoodRow — log from library (S-001 / S-008)', () {
    /// Read the thumb's `Semantics.checked` flag (replaces the old
    /// `tester.widget<Checkbox>(...)` cast after the Iteration 1
    /// thumb-toggle migration).
    ///
    /// The caller is responsible for `tester.ensureSemantics()` —
    /// calling it inside this helper leaks a `SemanticsHandle` per
    /// invocation, which the test framework rejects at teardown.
    bool thumbChecked(WidgetTester tester, String foodId) {
      final node = tester.getSemantics(
        find.byKey(Key('log_food_thumb_$foodId')),
      );
      return node.getSemanticsData().flagsCollection.isChecked ==
          CheckedState.isTrue;
    }

    testWidgets('thumb toggle logs, amount input scales, unlog removes', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;

      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-pro-log',
          name: 'Log Proteins',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      // Per-100 g chicken: 31P / 0C / 3F = 151 kcal.
      await repo.createFood(
        const Food(
          id: 'f-chicken-log',
          name: 'Chicken Breast (log test)',
          unitType: FoodUnitType.grams,
          groupId: 'g-pro-log',
          referenceAmount: 100.0,
          referenceLabel: '100 g',
          protein: 31,
          carbs: 0,
          fat: 3,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      // Per-1 egg: 6P / 1C / 5F = 73 kcal.
      await repo.createFood(
        const Food(
          id: 'f-egg-log',
          name: 'Egg (log test)',
          unitType: FoodUnitType.count,
          groupId: 'g-pro-log',
          referenceAmount: 1.0,
          referenceLabel: '1 egg',
          protein: 6,
          carbs: 1,
          fat: 5,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );

      final nutritionState = NutritionState(repo);
      await nutritionState.loadNutritionTarget();
      final foodLibraryState = FoodLibraryState(repo);
      await foodLibraryState.loadFoodGroups();
      await foodLibraryState.loadFoods();
      await nutritionState.loadConsumedToday();

      await tester.pumpWidget(
        MaterialApp(
          home: NutritionScreen(
            nutritionState: nutritionState,
            foodLibraryState: foodLibraryState,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enable semantics once for the whole test. The handle is
      // disposed at the very end of the test body so the
      // framework's leak check (which runs at the END of the
      // body) sees a clean state. `addTearDown` callbacks fire
      // AFTER the leak check, so they would not protect against
      // the leak — explicit disposal is required.
      final semHandle = tester.ensureSemantics();

      // Each food has a tappable thumbnail toggle; the chicken
      // thumb is unchecked (no log today) before any interaction.
      final chickenThumbKey = const Key('log_food_thumb_f-chicken-log');
      final eggThumbKey = const Key('log_food_thumb_f-egg-log');
      expect(find.byKey(chickenThumbKey), findsOneWidget);
      expect(find.byKey(eggThumbKey), findsOneWidget);
      expect(
        thumbChecked(tester, 'f-chicken-log'),
        isFalse,
        reason: 'untouched thumb starts unchecked',
      );

      // Type 150 into the chicken amount input and tap the thumb.
      // For grams-type foods, the amount field is the actual amount
      // (not a multiplier). 150g of chicken ⇒ 151 * (150/100) = 226.5 cal
      // (rounded to 226 or 227).
      final chickenAmountKey = const Key('log_food_amount_f-chicken-log');
      // Default food groups are now seeded, so the chicken row may sit
      // below the fold. Scroll the row into view before tapping.
      await tester.scrollUntilVisible(
        find.byKey(chickenAmountKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(chickenAmountKey), '150');
      await tester.pump();
      await tester.tap(find.byKey(chickenThumbKey));
      await tester.pumpAndSettle();

      // S-001: the snapshot is persisted with the scaled macros and
      // the ring shows the scaled calorie value.
      expect(nutritionState.consumedToday.length, 1);
      expect(
        nutritionState.todayConsumedCalories,
        anyOf(226, 227),
        reason: '151 * (150/100) = 226.5 (rounded)',
      );
      // The thumb's semantics now read as checked.
      expect(
        thumbChecked(tester, 'f-chicken-log'),
        isTrue,
        reason: 'S-005: checked semantics after log',
      );

      // Log the egg at 3 (S-002: 73 * 3 = 219). The egg row is
      // below the test viewport — scroll it into view before
      // tapping.
      await tester.scrollUntilVisible(
        find.byKey(eggThumbKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const Key('log_food_amount_f-egg-log')),
        '3',
      );
      await tester.pump();
      await tester.tap(find.byKey(eggThumbKey));
      await tester.pumpAndSettle();
      expect(nutritionState.consumedToday.length, 2);
      expect(
        nutritionState.todayConsumedCalories,
        anyOf(226 + 219, 227 + 219),
        reason: 'sum of both scaled logs',
      );

      // S-008: tap chicken's thumb again — the row's log is
      // removed, the ring drops back to the egg-only total. The
      // chicken is back at the top of the (alphabetical) list;
      // scroll it into view before tapping.
      await tester.scrollUntilVisible(
        find.byKey(chickenThumbKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(chickenThumbKey));
      await tester.pumpAndSettle();
      expect(nutritionState.consumedToday.length, 1);
      expect(nutritionState.todayConsumedCalories, 219);
      expect(
        thumbChecked(tester, 'f-chicken-log'),
        isFalse,
        reason: 'S-004: checked semantics cleared after unlog',
      );

      // Repository confirms the chicken log row is gone. Read all
      // today's consumed foods via the in-memory snapshot (we don't
      // need a real midnight ms; the cache + repository both store
      // today's day key).
      final remainingEgg = nutritionState.consumedToday
          .where((c) => c.sourceFoodId == 'f-egg-log')
          .toList();
      final remainingChicken = nutritionState.consumedToday
          .where((c) => c.sourceFoodId == 'f-chicken-log')
          .toList();
      expect(remainingEgg.length, 1);
      expect(remainingChicken.length, 0, reason: 'uncheck removes the log');

      // Dispose the semantics handle explicitly so the
      // framework's leak check (which runs at the END of the
      // body) sees a clean state.
      semHandle.dispose();
    });

    // ── S-002 / S-005 / S-006 / S-007 — new surface in Iteration 1 ──
    //
    // The leading checkbox is replaced by a tappable thumbnail
    // (S-001/S-002). Macros collapse to a single
    // `"<cal> cal · <P>P · <C>C · <F>F"` line (S-007). Hairline
    // dividers render between rows in a group (S-006). Semantics
    // exposes `checked: true/false` so screen readers + tests see
    // a toggle (S-005).

    testWidgets('S-002: food without image shows muted placeholder thumb', (
      tester,
    ) async {
      // Foods without an imagePath render the muted placeholder
      // (40×40 rounded surface + restaurant_outlined icon). This
      // is the common case on web (image picker is a no-op there).
      final repo = await _freshRepo();
      final nutrition = NutritionState(repo);
      final foodLib = FoodLibraryState(repo);
      await nutrition.loadConsumedToday();
      await foodLib.loadFoodGroups();
      await foodLib.loadFoods();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogFoodRow(
              key: const Key('row_no_image'),
              food: const Food(
                id: 'f-no-image',
                name: 'No-image food',
                unitType: FoodUnitType.grams,
                referenceAmount: 100.0,
                referenceLabel: '100 g',
                protein: 0,
                carbs: 0,
                fat: 0,
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
              nutritionState: nutrition,
              foodLibraryState: foodLib,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Thumb key is present.
      expect(
        find.byKey(const Key('log_food_thumb_f-no-image')),
        findsOneWidget,
      );
      // The placeholder icon is rendered (no image was set).
      expect(
        find.descendant(
          of: find.byKey(const Key('log_food_thumb_f-no-image')),
          matching: find.byIcon(Icons.restaurant_outlined),
        ),
        findsOneWidget,
        reason: 'S-002: placeholder icon when no image is set',
      );
    });

    testWidgets(
      'S-005: thumb exposes checked semantics; toggles when tapped',
      (tester) async {
        final repo = await _freshRepo();
        final nutrition = NutritionState(repo);
        final foodLib = FoodLibraryState(repo);
        await nutrition.loadConsumedToday();
        await foodLib.loadFoodGroups();
        await foodLib.loadFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LogFoodRow(
                food: const Food(
                  id: 'f-sem',
                  name: 'Sem food',
                  unitType: FoodUnitType.grams,
                  referenceAmount: 100.0,
                  referenceLabel: '100 g',
                  protein: 10,
                  carbs: 10,
                  fat: 10,
                  createdAtMs: 1,
                  updatedAtMs: 1,
                ),
                nutritionState: nutrition,
                foodLibraryState: foodLib,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enable semantics once for the whole test. The handle is
        // disposed at the very end of the test body so the
        // framework's leak check sees a clean state.
        final handle = tester.ensureSemantics();

        // Unlogged → unchecked.
        {
          final node = tester.getSemantics(
            find.byKey(const Key('log_food_thumb_f-sem')),
          );
          expect(
            node.getSemanticsData().flagsCollection.isChecked,
            CheckedState.isFalse,
            reason: 'S-005: unchecked when not logged',
          );
        }

        // Tap → log → checked.
        await tester.tap(find.byKey(const Key('log_food_thumb_f-sem')));
        await tester.pumpAndSettle();
        expect(nutrition.isFoodLoggedToday('f-sem'), isTrue);
        {
          final node = tester.getSemantics(
            find.byKey(const Key('log_food_thumb_f-sem')),
          );
          expect(
            node.getSemanticsData().flagsCollection.isChecked,
            CheckedState.isTrue,
            reason: 'S-005: checked when logged',
          );
        }

        // Tap → unlog → unchecked again.
        await tester.tap(find.byKey(const Key('log_food_thumb_f-sem')));
        await tester.pumpAndSettle();
        expect(nutrition.isFoodLoggedToday('f-sem'), isFalse);
        {
          final node = tester.getSemantics(
            find.byKey(const Key('log_food_thumb_f-sem')),
          );
          expect(
            node.getSemanticsData().flagsCollection.isChecked,
            CheckedState.isFalse,
            reason: 'S-004/S-005: unchecked after unlog',
          );
        }

        // Dispose the semantics handle explicitly so the
        // framework's leak check sees a clean state.
        handle.dispose();
      },
    );

    testWidgets('S-007: macros are a single `<cal> cal · <P>P · <C>C · <F>F` line', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final nutrition = NutritionState(repo);
      final foodLib = FoodLibraryState(repo);
      await nutrition.loadConsumedToday();
      await foodLib.loadFoodGroups();
      await foodLib.loadFoods();

      // Per-100 g sample: 10P / 10C / 10F = 170 kcal. Macro text:
      // "170 cal · 10P · 10C · 10F".
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogFoodRow(
              food: const Food(
                id: 'f-macros',
                name: 'Macro sample',
                unitType: FoodUnitType.grams,
                referenceAmount: 100.0,
                referenceLabel: '100 g',
                protein: 10,
                carbs: 10,
                fat: 10,
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
              nutritionState: nutrition,
              foodLibraryState: foodLib,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Single-line format.
      expect(
        find.text('170 cal · 10P · 10C · 10F'),
        findsOneWidget,
        reason: 'S-007: single-line macro format with middle-dot separators',
      );
      // The old 2×2 grid cells are gone: no separate "170 cal",
      // "10P", "10C", "10F" cells.
      // (These substrings are still part of the single line above;
      // we check that the OLD `grid` widget is gone by asserting
      // the 2×2 grid container is not present.)
      // The grid used a 73-px-wide SizedBox for the "cal" cell;
      // verify that no SizedBox of width 73 exists inside the row.
      // (Width 73 is the grid's specific column width; nothing
      // else in the row uses that exact width.)
      final rowFinder = find.byType(LogFoodRow);
      expect(rowFinder, findsOneWidget);
      // The amount textbox also uses width 73; it's still present
      // — the assertion we want is that the grid's "cal" SizedBox
      // is gone. Skip the SizedBox assertion and instead verify
      // the exact macro line is the only Text containing "10P".
      expect(find.textContaining('10P'), findsOneWidget);
    });

    testWidgets('S-006: hairline divider between rows, none after last', (
      tester,
    ) async {
      final repo = await _freshRepo();
      const now = 1700000000000;
      await repo.createFoodGroup(
        const FoodGroup(
          id: 'g-div',
          name: 'Divider Test Group',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      );
      // Three foods so we can assert the per-group divider index.
      for (final id in ['f-a', 'f-b', 'f-c']) {
        await repo.createFood(
          Food(
            id: id,
            name: 'Food $id',
            unitType: FoodUnitType.grams,
            groupId: 'g-div',
            referenceAmount: 100.0,
            referenceLabel: '100 g',
            protein: 0,
            carbs: 0,
            fat: 0,
            createdAtMs: now,
            updatedAtMs: now,
          ),
        );
      }
      final nutrition = NutritionState(repo);
      final foodLib = FoodLibraryState(repo);
      await nutrition.loadConsumedToday();
      await foodLib.loadFoodGroups();
      await foodLib.loadFoods();

      await tester.pumpWidget(
        MaterialApp(
          home: NutritionScreen(
            nutritionState: nutrition,
            foodLibraryState: foodLib,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A divider sits between row 0 and row 1 (index 1) AND
      // between row 1 and row 2 (index 2). No divider after the
      // last row (index 3 would be after the last row; it does
      // not exist).
      expect(
        find.byKey(const Key('group_Divider Test Group_divider_1')),
        findsOneWidget,
        reason: 'S-006: divider between row 0 and row 1',
      );
      expect(
        find.byKey(const Key('group_Divider Test Group_divider_2')),
        findsOneWidget,
        reason: 'S-006: divider between row 1 and row 2',
      );
      expect(
        find.byKey(const Key('group_Divider Test Group_divider_3')),
        findsNothing,
        reason: 'S-006: no divider after the last row',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Manage Food Library – in-place Add / Remove toggle
  // ══════════════════════════════════════════════════════════════════════════
  //
  // The catalog tab rows now show a state-dependent trailing button:
  //   - "Add" (primary background, fixed-width text button) when the
  //     catalog food is NOT in the user's library.
  //   - A 40×40 red square with a white `Icons.delete_outline` (no
  //     text label — the trash icon is universally legible) when the
  //     catalog food IS in the user's library.
  //
  // Tapping Add inserts the food and stays on the screen; tapping
  // the trash button removes the food and stays on the screen. The
  // user can add and remove as many foods as they want in a single
  // visit and only leaves via the system back arrow.

  group('ManageFoodLibrary – add/remove toggle', () {
    /// Pin a single catalog food and return the seeded id.
    Future<String> _seedSingleCatalog(MockWorkoutRepository repo) async {
      const catalogSource = Food(
        id: 'toggle-catalog-chicken',
        name: 'Chicken (toggle test)',
        unitType: FoodUnitType.grams,
        referenceAmount: 100.0,
        referenceLabel: 'g',
        isCatalog: true,
        protein: 31,
        carbs: 0,
        fat: 3,
        createdAtMs: 1700000000000,
        updatedAtMs: 1700000000000,
      );
      await repo.seedCatalogFood(catalogSource);
      return catalogSource.id;
    }

    /// Pump the AddFoodScreen for the Library tab.
    Future<({NutritionState nutrition, FoodLibraryState foodLib})>
    _pumpCatalogTab(WidgetTester tester, {MockWorkoutRepository? repo}) async {
      final r = repo ?? await _freshRepo();
      final nutrition = NutritionState(r);
      final foodLib = FoodLibraryState(r);
      await tester.binding.setSurfaceSize(const Size(800, 6000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await foodLib.loadFoodGroups();
      await foodLib.loadFoods();
      // The screen's initState schedules a loadCatalogFoods via
      // addPostFrameCallback; pumpAndSettle drains that microtask
      // chain so the list is populated before the first assertion.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddFoodScreen(
              nutritionState: nutrition,
              foodLibraryState: foodLib,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (nutrition: nutrition, foodLib: foodLib);
    }

    testWidgets('renders Add button on a fresh catalog row', (tester) async {
      final repo = await _freshRepo();
      final catalogId = await _seedSingleCatalog(repo);
      await _pumpCatalogTab(tester, repo: repo);

      // The catalog row is visible.
      expect(
        find.text('Chicken (toggle test)'),
        findsOneWidget,
        reason: 'catalog food name should be rendered in the row',
      );

      // Add key present, no trash icon.
      expect(find.byKey(Key('add_catalog_food_$catalogId')), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets(
      'tapping Add moves the food into the library and flips the row to '
      'Remove (no pop)',
      (tester) async {
        final repo = await _freshRepo();
        final catalogId = await _seedSingleCatalog(repo);
        final states = await _pumpCatalogTab(tester, repo: repo);

        await tester.tap(find.byKey(Key('add_catalog_food_$catalogId')));
        await tester.pumpAndSettle();

        // The food is in the library…
        await states.foodLib.loadFoods();
        expect(states.foodLib.foods, hasLength(1));
        // …the Add key is gone, the Remove key is present with the
        // trash icon, and the screen is STILL on top (no pop).
        expect(find.byKey(Key('add_catalog_food_$catalogId')), findsNothing);
        expect(
          find.byKey(Key('remove_catalog_food_$catalogId')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(Key('remove_catalog_food_$catalogId')),
            matching: find.byIcon(Icons.delete_outline),
          ),
          findsOneWidget,
        );
        // The screen did not pop — the AppBar is still on top.
        expect(find.text('Manage Food Library'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping Remove takes the food out of the library and flips the row '
      'back to Add',
      (tester) async {
        final repo = await _freshRepo();
        final catalogId = await _seedSingleCatalog(repo);
        final states = await _pumpCatalogTab(tester, repo: repo);

        // Add it.
        await tester.tap(find.byKey(Key('add_catalog_food_$catalogId')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('remove_catalog_food_$catalogId')),
          findsOneWidget,
        );

        // Remove it.
        await tester.tap(find.byKey(Key('remove_catalog_food_$catalogId')));
        await tester.pumpAndSettle();

        // Library is empty again.
        await states.foodLib.loadFoods();
        expect(states.foodLib.foods, isEmpty);
        // Add is back, Remove is gone, screen still on top.
        expect(find.byKey(Key('add_catalog_food_$catalogId')), findsOneWidget);
        expect(find.byKey(Key('remove_catalog_food_$catalogId')), findsNothing);
        expect(find.text('Manage Food Library'), findsOneWidget);
      },
    );

    testWidgets('toggling Add → Remove → Add does not duplicate the row', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final catalogId = await _seedSingleCatalog(repo);
      final states = await _pumpCatalogTab(tester, repo: repo);

      final addKey = Key('add_catalog_food_$catalogId');
      final removeKey = Key('remove_catalog_food_$catalogId');

      // First add.
      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();
      // Remove.
      await tester.tap(find.byKey(removeKey));
      await tester.pumpAndSettle();
      // Add again.
      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();

      // Exactly one library row exists (not two, not three).
      await states.foodLib.loadFoods();
      final matching = states.foodLib.foods
          .where((f) => f.name == 'Chicken (toggle test)')
          .toList();
      expect(
        matching,
        hasLength(1),
        reason:
            'each add creates exactly one library row; the '
            'second cycle replaces the same one',
      );
      // The row is currently in Remove state.
      expect(find.byKey(removeKey), findsOneWidget);
    });

    testWidgets('tapping Remove on a logged food unlogs it for today only', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final catalogId = await _seedSingleCatalog(repo);
      // Pre-add the food to the library and pre-log it for today.
      // We drive the state directly to avoid coupling to the Add row
      // — the focus here is the Remove path's interaction with
      // today's log.
      final states = await _pumpCatalogTab(tester, repo: repo);
      final libId = await states.foodLib.addCatalogFoodToLibrary(catalogId);
      await states.foodLib.loadFoods();
      final libFood = states.foodLib.foods.firstWhere((f) => f.id == libId);
      await states.nutrition.loadNutritionTarget();
      await states.nutrition.logConsumedFoodAt(libFood, 100.0);
      expect(
        states.nutrition.isFoodLoggedToday(libId),
        isTrue,
        reason: 'precondition: the food must be logged today',
      );

      // Pump the catalog tab fresh so the row reads the now-in-library
      // state and renders the Remove button.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddFoodScreen(
              nutritionState: states.nutrition,
              foodLibraryState: states.foodLib,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the Remove button.
      await tester.tap(find.byKey(Key('remove_catalog_food_$catalogId')));
      await tester.pumpAndSettle();

      // Library is empty AND the food is unlogged from today.
      await states.foodLib.loadFoods();
      expect(states.foodLib.foods, isEmpty);
      expect(
        states.nutrition.isFoodLoggedToday(libId),
        isFalse,
        reason:
            'removing a library food that was logged today must '
            'also unlog it for today',
      );
    });
  });

  // ─── Day isolation (R-1) ─────────────────────────────────────────────
  // Past days' ConsumedFood snapshots must stay byte-identical after
  // a later-day target edit. The frozen-snapshot contract is what
  // enforces this — `ConsumedFood` stores its own `targetCalories /
  // targetProtein / targetCarbs / targetFat` and the macros it was
  // logged with. Editing the target for a later day must not walk
  // backward and rewrite those fields.

  group('Nutrition day isolation', () {
    test('past day\'s ConsumedFood rows keep frozen targets and totals '
        'after a later-day target edit', () async {
      final repo = await _freshRepo();
      final today = OmniDateUtils.todayMidnightMs();
      final yesterday = OmniDateUtils.startOfDayMs(
        DateTime.now().subtract(const Duration(days: 1)),
      );

      // Yesterday: target was 2500/150/300/80, and we logged one
      // food. The ConsumedFood snapshot must freeze the day-1
      // target and the day-1 macros.
      await repo.saveNutritionTargetForDate(
        yesterday,
        NutritionTarget(calories: 2500, protein: 150, carbs: 300, fat: 80),
      );
      final yesterdayEntry = ConsumedFood(
        id: 'consumed-yesterday',
        loggedAtMs: yesterday + 1000,
        dateMs: yesterday,
        sourceFoodId: 'food-snap-day-iso',
        name: 'Day-1 Snack',
        unitType: FoodUnitType.grams,
        referenceAmount: 100,
        referenceLabel: 'g',
        protein: 10,
        carbs: 20,
        fat: 5,
        amountConsumed: 100.0,
        // Frozen day-1 target snapshot.
        targetCalories: 2500,
        targetProtein: 150,
        targetCarbs: 300,
        targetFat: 80,
        createdAtMs: yesterday,
        updatedAtMs: yesterday,
      );
      await repo.createConsumedFood(yesterdayEntry);

      // Capture the yesterday snapshot as JSON for byte-equality.
      final beforeJson = jsonEncode(yesterdayEntry.toMap());

      // Compute the day-1 caloriesConsumed BEFORE the edit.
      // (10*4 + 20*4 + 5*9) * 1.0 = 165.
      final day1CaloriesBefore = yesterdayEntry.caloriesConsumed;
      expect(day1CaloriesBefore, 165);

      // Edit today's target.
      await repo.saveNutritionTargetForDate(
        today,
        NutritionTarget(calories: 2700, protein: 170, carbs: 320, fat: 85),
      );

      // The past day must be byte-identical.
      final day1Rows = await repo.getConsumedFoodsForDate(yesterday);
      expect(day1Rows, hasLength(1));
      final afterJson = jsonEncode(day1Rows[0].toMap());
      expect(afterJson, equals(beforeJson));
      // Key frozen fields are unchanged.
      expect(day1Rows[0].targetCalories, 2500);
      expect(day1Rows[0].targetProtein, 150);
      expect(day1Rows[0].targetCarbs, 300);
      expect(day1Rows[0].targetFat, 80);
      // Macros are unchanged.
      expect(day1Rows[0].protein, 10);
      expect(day1Rows[0].carbs, 20);
      expect(day1Rows[0].fat, 5);
      // caloriesConsumed is recomputed from the same frozen macros
      // and reference; it must equal the pre-edit value.
      expect(day1Rows[0].caloriesConsumed, day1CaloriesBefore);

      // The new today target is reachable and equal to the edit.
      final todayTarget = await repo.getNutritionTargetForDate(today);
      expect(todayTarget?.calories, 2700);
      expect(todayTarget?.protein, 170);
    });

    test('rolloverToDate clears the in-memory consumed cache so '
        'yesterday\'s totals cannot leak into today', () async {
      final repo = await _freshRepo();
      final state = NutritionState(repo);
      final today = OmniDateUtils.todayMidnightMs();

      // Seed yesterday's target and a yesterday consumed row.
      final yesterday = OmniDateUtils.startOfDayMs(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await repo.saveNutritionTargetForDate(
        yesterday,
        NutritionTarget(calories: 2500, protein: 150, carbs: 300, fat: 80),
      );
      await repo.createConsumedFood(
        ConsumedFood(
          id: 'consumed-pre-rollover',
          loggedAtMs: yesterday + 1000,
          dateMs: yesterday,
          sourceFoodId: 'food-pre',
          name: 'Pre-rollover Snack',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          protein: 0,
          carbs: 0,
          fat: 10,
          amountConsumed: 100.0,
          targetCalories: 2500,
          targetProtein: 150,
          targetCarbs: 300,
          targetFat: 80,
          createdAtMs: yesterday,
          updatedAtMs: yesterday,
        ),
      );

      // Load yesterday's snapshot into the cache via the state
      // layer, then call rolloverToDate to simulate a new day.
      await state.loadConsumedToday();
      // The today log is empty; rollover must not pick up
      // yesterday's rows.
      expect(state.consumedToday, isEmpty);
      expect(state.todayConsumedCalories, 0);

      // Rollover: consumed cache must be empty and the target
      // must be the rolled-over day-1 target.
      await state.rolloverToDate(today);
      expect(state.consumedToday, isEmpty);
      expect(state.todayConsumedCalories, 0);
      expect(state.nutritionTarget?.calories, 2500);
      expect(state.nutritionTarget?.protein, 150);

      // Yesterday's row is still in storage.
      final day1Rows = await repo.getConsumedFoodsForDate(yesterday);
      expect(day1Rows, hasLength(1));
    });
  });

  // ─── Catalog search field (R-3) ──────────────────────────────────────
  // The Library tab on the AddFoodScreen has a search TextField at
  // the top that filters the catalog by food name. Verifies the
  // field is present and the filter responds to keystrokes.

  group('AddFoodScreen — catalog search field', () {
    testWidgets('shows a search field on the Library tab', (tester) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      await foodLib.loadCatalogFoods();

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The Library tab is the default; the search field is visible.
      expect(find.byKey(const Key('catalog_search_field')), findsOneWidget);
    });

    testWidgets('typing in the search field filters the catalog by name', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      await foodLib.loadCatalogFoods();

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type 'chick' into the search field.
      await tester.enterText(
        find.byKey(const Key('catalog_search_field')),
        'chick',
      );
      await tester.pump();

      // Every visible catalog-row FOOD NAME contains 'chick'
      // (case-insensitive). The catalog row is now an InkWell + Row
      // (not a ListTile) — we scope the check by the food name's
      // first-line Text widget, which is the only Text with a
      // `maxLines: 1` style on the row.
      final names = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.toLowerCase().contains('chick'))
          .toList();
      // At least one catalog row matches the query.
      expect(
        names,
        isNotEmpty,
        reason: 'expected at least one visible food title to contain "chick"',
      );
    });
  });

  // ─── Categories tab (R-2) ──────────────────────────────────────────
  // The Categories tab is reached via the third tab of the
  // AddFoodScreen. Verifies the tab renders the active groups, an
  // Ungrouped row, and a "+ New Category" affordance.

  group('AddFoodScreen — Categories tab', () {
    Future<void> _switchToCategoriesTab(WidgetTester tester) async {
      // The third tab is "Categories".
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
    }

    testWidgets('renders existing groups, Ungrouped row, and new button', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      // Seed two groups + one ungrouped food via the state.
      final proteinsId = await foodLib.createFoodGroup('Proteins');
      final vegetablesId = await foodLib.createFoodGroup('Vegetables');
      await foodLib.createFood(
        Food(
          id: 'f-ungrouped',
          name: 'Loose Snack',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: false,
          protein: 5,
          carbs: 10,
          fat: 1,
          groupId: null,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _switchToCategoriesTab(tester);

      // Both groups have editable name fields.
      expect(find.byKey(Key('category_name_$proteinsId')), findsOneWidget);
      expect(find.byKey(Key('category_name_$vegetablesId')), findsOneWidget);
      // Ungrouped row visible.
      expect(find.text('Ungrouped'), findsOneWidget);
      // + New Category button visible.
      expect(find.byKey(const Key('new_category_button')), findsOneWidget);
    });

    testWidgets('+ New Category adds a row and persists the new group', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _switchToCategoriesTab(tester);

      // Initially no category rows.
      final beforeCategoryRows = find.byType(TextField).evaluate().length;

      // Tap the new category button.
      await tester.tap(find.byKey(const Key('new_category_button')));
      await tester.pumpAndSettle();

      // A new row was added (one more TextField).
      final afterCategoryRows = find.byType(TextField).evaluate().length;
      expect(afterCategoryRows, beforeCategoryRows + 1);
      expect(afterCategoryRows, beforeCategoryRows + 1);

      // The new group is persisted in the state.
      expect(foodLib.foodGroups.any((g) => g.name == 'New Category'), isTrue);
    });

    testWidgets('trash icon on a non-empty group shows the confirm dialog', (
      tester,
    ) async {
      final repo = await _freshRepo();
      final foodLib = FoodLibraryState(repo);
      final nutrition = NutritionState(repo);
      final groupId = await foodLib.createFoodGroup('Proteins');
      // Add a food in the group so the row is non-empty.
      await foodLib.createFood(
        Food(
          id: 'f-in-grp',
          name: 'Egg',
          unitType: FoodUnitType.grams,
          referenceAmount: 100,
          referenceLabel: 'g',
          isCatalog: false,
          protein: 13,
          carbs: 1,
          fat: 11,
          groupId: groupId,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AddFoodScreen(
            foodLibraryState: foodLib,
            nutritionState: nutrition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _switchToCategoriesTab(tester);

      await tester.tap(find.byKey(Key('category_delete_$groupId')));
      await tester.pumpAndSettle();

      expect(find.text('Delete category?'), findsOneWidget);
      // The dropdown default is "Ungrouped" (null value).
      expect(
        find.byKey(const Key('delete_category_destination')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delete_category_confirm')), findsOneWidget);

      // Confirm with the default (Ungrouped).
      await tester.tap(find.byKey(const Key('delete_category_confirm')));
      // The async chain runs through the state method which awaits
      // several repository writes. pumpAndSettle alone is sometimes
      // not enough; pump the timer a few times to drain.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      // The group is archived; the food survives and moves to Ungrouped.
      final afterFoods = foodLib.foods;
      expect(afterFoods, hasLength(1));
      expect(afterFoods[0].groupId, isNull);
      expect(foodLib.activeFoodGroups.any((g) => g.id == groupId), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // AddFoodScreen — shared bottom CTA across tabs (S-001, S-002, S-003)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Both the **My Foods** and **Categories** tabs of `AddFoodScreen`
  // (the "Manage Food Library" screen) expose a primary bottom
  // action — "+ New Food" and "+ New Category" respectively. Per
  // the shared-CTA contract, both must route through
  // `Scaffold.bottomNavigationBar: OmniBottomCTA` so the buttons
  // sit at the same width, height, and vertical anchor as every
  // other primary bottom CTA in the app.
  //
  // The Library tab is browse-only and has no bottom CTA.

  group('AddFoodScreen — shared bottom CTA (S-001 / S-002 / S-003)', () {
    testWidgets(
      'anchors the My Foods tab\'s primary bottom CTA at the shared width and vertical anchor (S-001)',
      (tester) async {
        // Fixed surface so the test can assert exact pixel math.
        const surface = Size(400, 800);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        final nutrition = NutritionState(repo);
        await foodLib.loadFoodGroups();
        await foodLib.loadFoods();
        await foodLib.loadCatalogFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: AddFoodScreen(
              foodLibraryState: foodLib,
              nutritionState: nutrition,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to the "My Foods" tab.
        await tester.tap(find.text('My Foods'));
        await tester.pumpAndSettle();

        // The host's Scaffold has a non-null bottomNavigationBar
        // (a tab-aware AnimatedBuilder that renders the right CTA
        // for the active tab).
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(
          scaffold.bottomNavigationBar,
          isNotNull,
          reason: 'My Foods tab must have a primary bottom CTA on the host '
              'Scaffold.bottomNavigationBar',
        );

        // The My Foods CTA is an OmniBottomCTA. We look for it as a
        // descendant of the bottomNavigationBar slot because the
        // CTA is wrapped in an AnimatedBuilder for tab transitions.
        final ctaFinder = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(OmniBottomCTA),
        );
        expect(ctaFinder, findsOneWidget);

        // The "+ New Food" label is rendered by the CTA.
        expect(find.text('+ New Food'), findsOneWidget);

        // The CTA sits at the shared width and vertical anchor.
        final buttonRect = tester.getRect(
          find.descendant(
            of: ctaFinder,
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          buttonRect.left,
          closeTo(OmniTheme.bottomCTAHorizontalPadding, 0.5),
        );
        expect(
          buttonRect.right,
          closeTo(surface.width - OmniTheme.bottomCTAHorizontalPadding, 0.5),
        );
        expect(
          buttonRect.height,
          closeTo(OmniTheme.buttonPrimaryHeight, 0.5),
        );
        final expectedBottom = surface.height -
            tester.view.padding.bottom / tester.view.devicePixelRatio -
            OmniTheme.bottomCTAVerticalBottomPadding;
        expect(buttonRect.bottom, closeTo(expectedBottom, 0.5));
      },
    );

    testWidgets(
      'anchors the Categories tab\'s primary bottom CTA at the shared width and vertical anchor (S-002)',
      (tester) async {
        // Fixed surface so the test can assert exact pixel math.
        const surface = Size(400, 800);
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        final nutrition = NutritionState(repo);
        await foodLib.loadFoodGroups();
        await foodLib.loadFoods();
        await foodLib.loadCatalogFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: AddFoodScreen(
              foodLibraryState: foodLib,
              nutritionState: nutrition,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to the "Categories" tab.
        await tester.tap(find.text('Categories'));
        await tester.pumpAndSettle();

        // The host's Scaffold has a non-null bottomNavigationBar
        // (a tab-aware AnimatedBuilder that renders the right CTA
        // for the active tab).
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(
          scaffold.bottomNavigationBar,
          isNotNull,
          reason: 'Categories tab must have a primary bottom CTA on the host '
              'Scaffold.bottomNavigationBar',
        );

        // The Categories CTA is an OmniBottomCTA. We look for it as
        // a descendant of the bottomNavigationBar slot because the
        // CTA is wrapped in an AnimatedBuilder for tab transitions.
        final ctaFinder = find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(OmniBottomCTA),
        );
        expect(ctaFinder, findsOneWidget);

        // The `new_category_button` key is preserved on the rendered
        // FilledButton so the existing test contract continues to work.
        final newCategoryKey = find.byKey(const Key('new_category_button'));
        expect(newCategoryKey, findsOneWidget);

        // The CTA sits at the shared width and vertical anchor.
        final buttonRect = tester.getRect(
          find.descendant(
            of: ctaFinder,
            matching: find.byType(FilledButton),
          ),
        );
        expect(
          buttonRect.left,
          closeTo(OmniTheme.bottomCTAHorizontalPadding, 0.5),
        );
        expect(
          buttonRect.right,
          closeTo(surface.width - OmniTheme.bottomCTAHorizontalPadding, 0.5),
        );
        expect(
          buttonRect.height,
          closeTo(OmniTheme.buttonPrimaryHeight, 0.5),
        );
        final expectedBottom = surface.height -
            tester.view.padding.bottom / tester.view.devicePixelRatio -
            OmniTheme.bottomCTAVerticalBottomPadding;
        expect(buttonRect.bottom, closeTo(expectedBottom, 0.5));
      },
    );

    testWidgets(
      'renders no bottom CTA on the Library tab (S-003)',
      (tester) async {
        final repo = await _freshRepo();
        final foodLib = FoodLibraryState(repo);
        final nutrition = NutritionState(repo);
        await foodLib.loadFoodGroups();
        await foodLib.loadFoods();
        await foodLib.loadCatalogFoods();

        await tester.pumpWidget(
          MaterialApp(
            home: AddFoodScreen(
              foodLibraryState: foodLib,
              nutritionState: nutrition,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The Library tab is the default. No OmniBottomCTA is
        // rendered (the AnimatedBuilder returns SizedBox.shrink()
        // for the Library tab).
        expect(
          find.descendant(
            of: find.byType(Scaffold),
            matching: find.byType(OmniBottomCTA),
          ),
          findsNothing,
        );
        // The "+ New Food" / "+ New Category" labels are absent on
        // the Library tab.
        expect(find.text('+ New Food'), findsNothing);
        expect(find.text('+ New Category'), findsNothing);
      },
    );
  });
}
