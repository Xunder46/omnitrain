// filepath: test/decimal_comma_input_test.dart
//
// Plan 242 — a comma works as the decimal point in every number box
// (`docs/plans/2026-11-18-242-decimal-comma-input-plan/`).
//
// Scenarios covered here: S-24201..S-24206.
//
//   S-24201  pure: `parseDecimal` table + `DecimalInputFormatter`
//            accept/reject table (called directly).
//   S-24202  FoodForm: `12,5` in Fat, `3,25` in Protein save as
//            12.5 / 3.25 and the field keeps the comma on screen.
//   S-24203  FoodForm: `30,5` in the package-size box reaches the
//            draft's `referenceAmount` as 30.5.
//   S-24204  LogFoodRow: `1,5` in the amount box logs 1.5.
//   S-24205  pure: `MetricStepCalc.parseAndClamp` reads a comma.
//   S-24206  ProfileScreen: the height dialog and the body-weight
//            log sheet read `182,5` / `72,5` without a
//            "Enter a valid number." error.
//
// Mock repository only, per `docs/global_conventions.md`. Every
// expectation below is a value a point-only build would not
// produce: the typed text contains a comma and the expected number
// is non-default.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnitrain/core/utils/decimal_input.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/widgets/food_form.dart';
import 'package:omnitrain/features/nutrition/widgets/log_food_row.dart';
import 'package:omnitrain/features/profile/profile_screen.dart';
import 'package:omnitrain/state/food_library_state.dart';
import 'package:omnitrain/state/nutrition_state.dart';
import 'package:omnitrain/state/profile/profile_state.dart';
import 'package:omnitrain/state/settings/settings_state.dart';
import 'package:omnitrain/widgets/session/metric_crown_widget.dart';

import 'helpers/fake_preferences_service.dart';

/// Standard tall surface for the food form (image tile + 9 fields),
/// same as `test/food_form_decimals_and_autofocus_test.dart`.
const _formSurface = Size(420, 1800);

Food _chicken({String id = 'food-comma-chicken'}) {
  return Food(
    id: id,
    name: 'Chicken Breast',
    groupId: null,
    unitType: FoodUnitType.grams,
    referenceAmount: 100.0,
    referenceLabel: 'g',
    protein: 31,
    carbs: 0,
    fat: 3,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

TextEditingValue _value(String text) => TextEditingValue(text: text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // S-24201 — pure parse + formatter tables
  // ══════════════════════════════════════════════════════════════════════
  group('S-24201: parseDecimal and DecimalInputFormatter', () {
    test('parseDecimal reads a single comma as the decimal point', () {
      expect(parseDecimal('2,5'), 2.5);
      expect(parseDecimal('2.5'), 2.5);
      expect(parseDecimal('12'), 12.0);
      expect(parseDecimal(',5'), 0.5);
      expect(parseDecimal('5,'), 5.0);
      expect(parseDecimal(' 2,5 '), 2.5);
      expect(parseDecimal('-2,5'), -2.5);
    });

    test('parseDecimal rejects empty, non-numbers and ambiguous text', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('1,2,3'), isNull);
      expect(parseDecimal('1,234.5'), isNull);
      expect(parseDecimal('1.234,5'), isNull);
    });

    test('DecimalInputFormatter accepts a comma or a point', () {
      const formatter = DecimalInputFormatter();
      final old = _value('');
      expect(formatter.formatEditUpdate(old, _value('12,5')).text, '12,5');
      expect(formatter.formatEditUpdate(old, _value('12.5')).text, '12.5');
    });

    test('DecimalInputFormatter rejects broken or ambiguous text', () {
      const formatter = DecimalInputFormatter();
      final old = _value('');
      // Rejected edits return the old value whole (the old text stays).
      expect(formatter.formatEditUpdate(old, _value('1,2,3')).text, '');
      expect(formatter.formatEditUpdate(old, _value('1.2,3')).text, '');
      expect(formatter.formatEditUpdate(old, _value('a')).text, '');
    });

    test('DecimalInputFormatter honours maxFractionDigits on both separators',
        () {
      const formatter = DecimalInputFormatter(maxFractionDigits: 3);
      final old = _value('');
      expect(formatter.formatEditUpdate(old, _value('1,2345')).text, '');
      expect(formatter.formatEditUpdate(old, _value('1,234')).text, '1,234');
      expect(formatter.formatEditUpdate(old, _value('1.234')).text, '1.234');
      expect(formatter.formatEditUpdate(old, _value('1.2345')).text, '');
      // An empty new text (clearing the field) is always accepted.
      expect(
        formatter.formatEditUpdate(_value('12,5'), _value('')).text,
        '',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-24202 — FoodForm: comma macros save as the right doubles
  // ══════════════════════════════════════════════════════════════════════
  group('S-24202: FoodForm comma macros', () {
    testWidgets(
      '12,5 in Fat and 3,25 in Protein save as 12.5 / 3.25 and the '
      'field keeps the comma (S-24202)',
      (tester) async {
        await tester.binding.setSurfaceSize(_formSurface);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        FoodDraft? capturedDraft;
        final controller = FoodFormController();
        addTearDown(controller.detach);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null,
                foodLibraryState: state,
                controller: controller,
                onSave: (draft) async {
                  capturedDraft = draft;
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'Comma Food',
        );
        await tester.enterText(find.byKey(const Key('food_form_fat')), '12,5');
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          '3,25',
        );
        await tester.pump();

        // The field text is never rewritten while typing (D-4): the
        // comma the user typed must still be on screen before saving.
        final fatField = tester.widget<TextFormField>(
          find.byKey(const Key('food_form_fat')),
        );
        expect(
          fatField.controller!.text,
          '12,5',
          reason: 'the typed comma must stay visible in the Fat field',
        );

        controller.submit();
        await tester.pumpAndSettle();

        expect(capturedDraft, isNotNull);
        expect(capturedDraft!.name, 'Comma Food');
        expect(capturedDraft!.fat, 12.5);
        expect(capturedDraft!.protein, 3.25);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-24203 — FoodForm: comma package size reaches the draft
  // ══════════════════════════════════════════════════════════════════════
  group('S-24203: FoodForm comma package size', () {
    testWidgets(
      '30,5 in the package-size box saves referenceAmount 30.5 '
      '(S-24203)',
      (tester) async {
        // Opening the package row adds fields below the fold, so the
        // serving-test harness uses a wider, taller surface
        // (test/food_form_serving_test.dart: Size(800, 3000)).
        await tester.binding.setSurfaceSize(const Size(800, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final repo = MockWorkoutRepository();
        await repo.initialize();
        final state = FoodLibraryState(repo);

        FoodDraft? capturedDraft;
        final controller = FoodFormController();
        addTearDown(controller.detach);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FoodForm(
                initial: null,
                foodLibraryState: state,
                controller: controller,
                onSave: (draft) async {
                  capturedDraft = draft;
                  return true;
                },
                skipPopOnSave: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('food_form_name')),
          'Package Food',
        );
        await tester.enterText(find.byKey(const Key('food_form_fat')), '12,5');
        await tester.enterText(
          find.byKey(const Key('food_form_protein')),
          '3,25',
        );
        await tester.tap(find.byKey(const Key('food_form_package_link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('food_form_package_amount')),
          '30,5',
        );
        await tester.pump();

        controller.submit();
        await tester.pumpAndSettle();

        expect(capturedDraft, isNotNull);
        expect(capturedDraft!.name, 'Package Food');
        expect(capturedDraft!.referenceAmount, 30.5);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-24204 — LogFoodRow: comma amount logs the right double
  // ══════════════════════════════════════════════════════════════════════
  group('S-24204: LogFoodRow comma amount', () {
    testWidgets(
      'typing 1,5 in the amount box and tapping log records 1.5 '
      '(S-24204)',
      (tester) async {
        final repo = MockWorkoutRepository();
        await repo.initialize();
        repo.clearConsumedFoodsForTest();
        final foodLib = FoodLibraryState(repo);
        final food = _chicken();
        await foodLib.createFood(food);
        final nutritionState = NutritionState(repo);
        await nutritionState.loadNutritionTarget();
        await foodLib.loadFoods();
        await nutritionState.loadConsumedToday();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LogFoodRow(
                food: food,
                foodLibraryState: foodLib,
                nutritionState: nutritionState,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final amountKey = Key('log_food_amount_${food.id}');
        // Clear the prefilled "100" and type a comma decimal.
        await tester.enterText(find.byKey(amountKey), '');
        await tester.enterText(find.byKey(amountKey), '1,5');
        await tester.pump();
        await tester.tap(find.byKey(Key('log_food_thumb_${food.id}')));
        await tester.pumpAndSettle();

        expect(nutritionState.consumedToday.length, 1);
        expect(nutritionState.consumedToday.first.amountConsumed, 1.5);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-24205 — MetricStepCalc.parseAndClamp reads a comma
  // ══════════════════════════════════════════════════════════════════════
  group('S-24205: MetricStepCalc.parseAndClamp', () {
    test('a comma decimal parses and clamps like a point decimal', () {
      expect(MetricStepCalc.parseAndClamp('weight', '72,5'), 72.5);
      expect(MetricStepCalc.parseAndClamp('distance', '5,25'), 5.25);
      expect(MetricStepCalc.parseAndClamp('reps', '8'), 8);
      expect(MetricStepCalc.parseAndClamp('weight', '+72,5'), 72.5);
      expect(MetricStepCalc.parseAndClamp('weight', '1,2,3'), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // S-24206 — ProfileScreen: height dialog + measurement log sheet
  // ══════════════════════════════════════════════════════════════════════
  group('S-24206: profile screens read a comma decimal', () {
    Future<(ProfileState, SettingsState)> pumpProfile(WidgetTester tester) async {
      final repository = MockWorkoutRepository();
      await repository.initialize();

      final profileState = ProfileState(repository);
      final settingsState = SettingsState(repository, fakePreferencesService());
      await settingsState.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(
            profileState: profileState,
            settingsState: settingsState,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (profileState, settingsState);
    }

    testWidgets(
      'height dialog: 182,5 saves and pops 182.5 cm, no error text '
      '(S-24206)',
      (tester) async {
        final (profileState, _) = await pumpProfile(tester);

        // The identity-area height line opens the compact dialog.
        await tester.tap(find.byKey(const Key('profile_identity_height_value')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('height_dialog_value_field')),
          '182,5',
        );
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Save'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Enter a valid number.'), findsNothing);
        expect(profileState.latestHeightCm, 182.5);
      },
    );

    testWidgets(
      'measurement log sheet (body weight): 72,5 saves 72.5 kg, no '
      'error text (S-24206)',
      (tester) async {
        final (profileState, _) = await pumpProfile(tester);

        // Body Weight is the first charted measurement; its add
        // button is the first `Icons.add` on the screen (same as
        // test/profile_screen_test.dart).
        await tester.tap(find.byIcon(Icons.add).first);
        await tester.pumpAndSettle();
        expect(find.text('Log Body Weight'), findsOneWidget);

        await tester.enterText(find.byType(TextField).first, '72,5');
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.text('Enter a valid number.'), findsNothing);
        expect(profileState.latestBodyWeightKg, 72.5);
      },
    );
  });
}
