// Behaviour tests for the Daily Targets screen (plan 80, P2b).
//
// Scenarios S-14010..S-14022a from
// docs/plans/2026-10-26-80-daily-targets-plan/2026-10-26-80-daily-targets-plan.md.
// Production under test: lib/features/nutrition/nutrition_target_screen.dart
// and lib/core/utils/macro_targets.dart. Mock repository only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/utils/date_utils.dart';
import 'package:omnitrain/data/models/models.dart';
import 'package:omnitrain/data/repositories/mock_workout_repository.dart';
import 'package:omnitrain/features/nutrition/nutrition_target_screen.dart';
import 'package:omnitrain/state/nutrition_state.dart';

Future<MockWorkoutRepository> _freshRepo() async {
  final repo = MockWorkoutRepository();
  await repo.initialize();
  repo.clearConsumedFoodsForTest();
  return repo;
}

Future<NutritionTarget?> _storedTarget(MockWorkoutRepository repo) async {
  final fresh = NutritionState(repo);
  await fresh.loadNutritionTarget();
  return fresh.nutritionTarget;
}

void main() {
  group('NutritionTargetScreen — daily targets behaviour (S-14010..S-14022a)', () {
    Finder field(String key) => find.byKey(Key(key));

    String text(WidgetTester tester, String key) =>
        tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

    Future<({MockWorkoutRepository repo, NutritionState state})> pumpScreen(
      WidgetTester tester, {
      NutritionTarget? stored,
      bool pushed = false,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final repo = await _freshRepo();
      final state = NutritionState(repo);
      if (stored != null) {
        await state.saveNutritionTarget(stored);
      }
      final screen = NutritionTargetScreen(nutritionState: state);
      await tester.pumpWidget(
        pushed
            ? MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => screen),
                        ),
                        child: const Text('open target screen'),
                      ),
                    ),
                  ),
                ),
              )
            : MaterialApp(home: screen),
      );
      if (pushed) {
        await tester.tap(find.text('open target screen'));
      }
      await tester.pumpAndSettle();
      return (repo: repo, state: state);
    }

    Finder dialog() => find.byType(AlertDialog);

    testWidgets('S-14010 empty target: empty fields, no readout', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Daily Targets'), findsOneWidget);
      expect(text(tester, 'calories_field'), '');
      expect(text(tester, 'protein_field'), '');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');
      expect(find.byKey(const Key('implied_calories_readout')), findsNothing);
    });

    testWidgets('S-14011 calories 2000 prefills the default split', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();

      expect(text(tester, 'protein_field'), '150');
      expect(text(tester, 'carbs_field'), '200');
      expect(text(tester, 'fat_field'), '67');
      expect(
        tester.widget<Text>(
          find.byKey(const Key('implied_calories_readout')),
        ).data,
        'Macros add up to 2003 Cal',
      );
    });

    testWidgets('S-14012 protein 180 moves calories to 2123', (tester) async {
      await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();
      await tester.enterText(field('protein_field'), '180');
      await tester.pump();

      expect(text(tester, 'calories_field'), '2123');
      expect(text(tester, 'carbs_field'), '200');
      expect(text(tester, 'fat_field'), '67');
      expect(
        tester.widget<Text>(
          find.byKey(const Key('implied_calories_readout')),
        ).data,
        'Macros add up to 2123 Cal',
      );
    });

    testWidgets('S-14013 calories 2200 refills non-manual macros', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();
      await tester.enterText(field('protein_field'), '180');
      await tester.pump();
      await tester.enterText(field('calories_field'), '2200');
      await tester.pump();

      expect(text(tester, 'protein_field'), '180');
      expect(text(tester, 'carbs_field'), '220');
      expect(text(tester, 'fat_field'), '73');
      expect(
        tester.widget<Text>(
          find.byKey(const Key('implied_calories_readout')),
        ).data,
        'Macros add up to 2257 Cal',
      );
    });

    testWidgets('S-14014 clearing fat empties it and resyncs calories', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();
      await tester.enterText(field('fat_field'), '');
      await tester.pump();

      expect(text(tester, 'fat_field'), '');
      expect(text(tester, 'calories_field'), '1400');
      expect(
        tester.widget<Text>(
          find.byKey(const Key('implied_calories_readout')),
        ).data,
        'Macros add up to 1400 Cal',
      );

      await tester.enterText(field('calories_field'), '1000');
      await tester.pump();
      expect(text(tester, 'protein_field'), '75');
      expect(text(tester, 'carbs_field'), '100');
      expect(text(tester, 'fat_field'), '');
    });

    testWidgets('S-14015 Save stores the typed target for today', (
      tester,
    ) async {
      final (:repo, :state) = await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await _storedTarget(repo);
      expect(stored?.calories, 2000.0);
      expect(stored?.protein, 150.0);
      expect(stored?.carbs, 200.0);
      expect(stored?.fat, 67.0);

      final byDate = await repo.getNutritionTargetForDate(
        OmniDateUtils.todayMidnightMs(),
      );
      expect(byDate?.calories, 2000.0);
      expect(byDate?.protein, 150.0);
      expect(byDate?.carbs, 200.0);
      expect(byDate?.fat, 67.0);
      expect(state.nutritionTarget?.calories, 2000.0);
    });

    testWidgets('S-14016 calories-only save stores zero macros', (
      tester,
    ) async {
      final (:repo, :state) = await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();
      await tester.enterText(field('protein_field'), '');
      await tester.pump();
      await tester.enterText(field('carbs_field'), '');
      await tester.pump();
      await tester.enterText(field('fat_field'), '');
      await tester.pump();
      await tester.enterText(field('calories_field'), '1800');
      await tester.pump();

      expect(text(tester, 'protein_field'), '');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');
      expect(text(tester, 'calories_field'), '1800');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await _storedTarget(repo);
      expect(stored?.calories, 1800.0);
      expect(stored?.protein, 0.0);
      expect(stored?.carbs, 0.0);
      expect(stored?.fat, 0.0);
      expect(state.nutritionTarget?.calories, 1800.0);
    });

    testWidgets('S-14017 load-time prefill is not an unsaved change', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        stored: NutritionTarget(calories: 2000),
        pushed: true,
      );

      expect(text(tester, 'calories_field'), '2000');
      expect(text(tester, 'protein_field'), '150');
      expect(text(tester, 'carbs_field'), '200');
      expect(text(tester, 'fat_field'), '67');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(find.byType(NutritionTargetScreen), findsNothing);
    });

    testWidgets('S-14018 stored macros are manual on load', (tester) async {
      await pumpScreen(
        tester,
        stored: NutritionTarget(
          calories: 2000,
          protein: 180,
          carbs: 220,
          fat: 70,
        ),
      );

      expect(text(tester, 'calories_field'), '2000');
      expect(text(tester, 'protein_field'), '180');
      expect(text(tester, 'carbs_field'), '220');
      expect(text(tester, 'fat_field'), '70');

      await tester.enterText(field('calories_field'), '2400');
      await tester.pump();
      expect(text(tester, 'protein_field'), '180');
      expect(text(tester, 'carbs_field'), '220');
      expect(text(tester, 'fat_field'), '70');
    });

    testWidgets('S-14019 protein-only save derives calories', (tester) async {
      final (:repo, :state) = await pumpScreen(tester);
      await tester.enterText(field('protein_field'), '100');
      await tester.pump();
      expect(text(tester, 'calories_field'), '400');

      await tester.enterText(field('calories_field'), '');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final stored = await _storedTarget(repo);
      expect(stored?.calories, 400.0);
      expect(stored?.protein, 100.0);
      expect(stored?.carbs, 0.0);
      expect(stored?.fat, 0.0);
      expect(state.nutritionTarget?.calories, 400.0);
    });

    testWidgets('S-14020 negative protein blocks Save', (tester) async {
      final (:repo, :state) = await pumpScreen(tester);
      await tester.enterText(field('protein_field'), '-5');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a non-negative number'), findsWidgets);
      final stored = await _storedTarget(repo);
      expect(
        stored == null || (stored.calories == 0 && stored.protein == 0),
        isTrue,
      );
      expect(state.nutritionTarget, isNull);
    });

    testWidgets('S-14021 keep editing keeps the screen and the typed fat', (
      tester,
    ) async {
      await pumpScreen(tester, pushed: true);
      await tester.enterText(field('fat_field'), '50');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(dialog(), findsOneWidget);
      expect(find.text('Unsaved changes'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nutrition-target-unsaved-keep')));
      await tester.pumpAndSettle();

      expect(dialog(), findsNothing);
      expect(find.byType(NutritionTargetScreen), findsOneWidget);
      expect(text(tester, 'fat_field'), '50');
    });

    testWidgets('S-14022a clearing calories clears non-manual macros only', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();
      await tester.enterText(field('calories_field'), '');
      await tester.pump();

      expect(text(tester, 'protein_field'), '');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');

      await tester.enterText(field('protein_field'), '100');
      await tester.pump();
      expect(text(tester, 'calories_field'), '400');

      await tester.enterText(field('calories_field'), '');
      await tester.pump();
      expect(text(tester, 'protein_field'), '100');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');
    });

    testWidgets('S-14023 clearing the last macro keeps calories', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '2000');
      await tester.pump();

      await tester.enterText(field('protein_field'), '');
      await tester.pump();
      expect(text(tester, 'calories_field'), '1403');

      await tester.enterText(field('carbs_field'), '');
      await tester.pump();
      expect(text(tester, 'calories_field'), '603');

      await tester.enterText(field('fat_field'), '');
      await tester.pump();
      expect(text(tester, 'calories_field'), '603');
      expect(text(tester, 'protein_field'), '');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');
    });

    testWidgets('S-14024 stored protein-only target keeps protein manual', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        stored: NutritionTarget(calories: 2000, protein: 150),
      );

      expect(text(tester, 'protein_field'), '150');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');

      await tester.enterText(field('calories_field'), '2400');
      await tester.pump();
      expect(text(tester, 'protein_field'), '150');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');
    });

    testWidgets('S-14025 stored carbs-only target keeps carbs manual', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        stored: NutritionTarget(calories: 2000, carbs: 220),
      );

      expect(text(tester, 'carbs_field'), '220');
      expect(text(tester, 'protein_field'), '');
      expect(text(tester, 'fat_field'), '');
    });

    testWidgets('S-14026 stored fat-only target keeps fat manual', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        stored: NutritionTarget(calories: 2000, fat: 70),
      );

      expect(text(tester, 'fat_field'), '70');
      expect(text(tester, 'protein_field'), '');
      expect(text(tester, 'carbs_field'), '');
    });

    testWidgets('S-14027 protein 0 leaves calories empty and no readout', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.enterText(field('protein_field'), '0');
      await tester.pump();

      expect(text(tester, 'calories_field'), '');
      expect(find.byKey(const Key('implied_calories_readout')), findsNothing);
    });

    testWidgets('S-14028 protein 1e400 (Infinity) blocks Save', (tester) async {
      final (:repo, :state) = await pumpScreen(tester);
      await tester.enterText(field('protein_field'), '1e400');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid number'), findsWidgets);
      final stored = await _storedTarget(repo);
      expect(
        stored == null || stored.calories == 0,
        isTrue,
      );
      expect(state.nutritionTarget, isNull);
    });

    testWidgets('S-14029 calories NaN blocks Save', (tester) async {
      final (:repo, :state) = await pumpScreen(tester);
      await tester.enterText(field('calories_field'), 'NaN');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid number'), findsWidgets);
      final stored = await _storedTarget(repo);
      expect(
        stored == null || stored.calories == 0,
        isTrue,
      );
      expect(state.nutritionTarget, isNull);
    });

    testWidgets('S-14029b calories 1e400 (Infinity) blocks Save', (
      tester,
    ) async {
      final (:repo, :state) = await pumpScreen(tester);
      await tester.enterText(field('calories_field'), '1e400');
      await tester.pump();

      expect(text(tester, 'protein_field'), '');
      expect(text(tester, 'carbs_field'), '');
      expect(text(tester, 'fat_field'), '');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid number'), findsWidgets);
      final stored = await _storedTarget(repo);
      expect(
        stored == null || stored.calories == 0,
        isTrue,
      );
      expect(state.nutritionTarget, isNull);
    });
  });
}
