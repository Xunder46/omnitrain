// Widget tests for `FuelSection` in isolation (99c P3, S-17205 and S-17206):
// the not-enough-logged-days sentence and the comparison colours.
//
// No repository, no Hive harness: the `FuelSummary` is hand-built, so the
// widget's own rendering rules are what is under test, not the service that
// computes the summary.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/fuel_summary.dart';
import 'package:omnitrain/features/stats/widgets/fuel_section.dart';

/// Tall enough that the whole Fuel row is laid out, so an assertion on a
/// widget's absence is never just an off-screen miss.
const Size _kTallViewport = Size(400, 2400);

/// The colours the row is handed, matching what `OmniSurface` inside it
/// resolves from `OmniTheme.activeTheme` (abyssalNeon by default).
final OmniThemeColors _themeColors = OmniTheme.colorsForTheme(
  AppTheme.abyssalNeon,
);

/// A `FuelSummary` with every field defaulted to null / 0, so a scenario
/// names only the figures it cares about.
FuelSummary _summary({
  int loggedDays = 5,
  double? caloriesAverage,
  double? proteinAverage,
  double? carbsAverage,
  double? fatAverage,
  double? previousCaloriesAverage,
  double? previousProteinAverage,
  double? previousCarbsAverage,
  double? previousFatAverage,
  double? trainingCaloriesAverage,
  double? trainingProteinAverage,
  double? restCaloriesAverage,
  double? restProteinAverage,
  double targetCalories = 0,
  double targetProtein = 0,
  double targetCarbs = 0,
  double targetFat = 0,
}) {
  return FuelSummary(
    loggedDays: loggedDays,
    caloriesAverage: caloriesAverage,
    proteinAverage: proteinAverage,
    carbsAverage: carbsAverage,
    fatAverage: fatAverage,
    previousCaloriesAverage: previousCaloriesAverage,
    previousProteinAverage: previousProteinAverage,
    previousCarbsAverage: previousCarbsAverage,
    previousFatAverage: previousFatAverage,
    trainingCaloriesAverage: trainingCaloriesAverage,
    trainingProteinAverage: trainingProteinAverage,
    restCaloriesAverage: restCaloriesAverage,
    restProteinAverage: restProteinAverage,
    targetCalories: targetCalories,
    targetProtein: targetProtein,
    targetCarbs: targetCarbs,
    targetFat: targetFat,
  );
}

Future<void> _pumpFuel(WidgetTester tester, FuelSummary summary) async {
  await tester.binding.setSurfaceSize(_kTallViewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: FuelSection(
            summary: summary,
            themeColors: _themeColors,
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

/// The `Text` keyed [key]'s own data.
String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// The resolved colour of the `Text` keyed [key].
Color _textColor(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).style!.color!;

/// The pumped tree's `ThemeData`, read from the `FuelSection` element itself.
ThemeData _pumpedTheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(FuelSection)));

void main() {
  testWidgets(
    'S-17205 Fuel with 2 logged days says so in words and draws no figures',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 2,
          caloriesAverage: 1800,
          proteinAverage: 100,
          carbsAverage: 300,
          fatAverage: 50,
          trainingCaloriesAverage: 2000,
          trainingProteinAverage: 120,
          restCaloriesAverage: 1600,
          restProteinAverage: 90,
        ),
      );

      expect(
        _text(tester, 'fuel_not_enough_days'),
        'Log food on 3 days to see a weekly average',
      );
      expect(_text(tester, 'fuel_logged_days'), '2/7 days logged');
      expect(find.byKey(const Key('fuel_calories')), findsNothing);
      expect(find.byKey(const Key('fuel_protein')), findsNothing);
      expect(find.byKey(const Key('fuel_carbs')), findsNothing);
      expect(find.byKey(const Key('fuel_fat')), findsNothing);
      expect(find.byKey(const Key('fuel_calories_change')), findsNothing);
      expect(find.byKey(const Key('fuel_split_training')), findsNothing);
      expect(find.byKey(const Key('fuel_split_rest')), findsNothing);
    },
  );

  testWidgets(
    'S-17205 Fuel with 3 logged days draws the averages and no sentence',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 3,
          caloriesAverage: 1800,
          proteinAverage: 100,
          carbsAverage: 300,
          fatAverage: 50,
          trainingCaloriesAverage: 2000,
          trainingProteinAverage: 120,
          restCaloriesAverage: 1600,
          restProteinAverage: 90,
        ),
      );

      expect(find.byKey(const Key('fuel_not_enough_days')), findsNothing);
      expect(find.byKey(const Key('fuel_calories')), findsOneWidget);
      expect(find.byKey(const Key('fuel_split_training')), findsOneWidget);
      expect(_text(tester, 'fuel_logged_days'), '3/7 days logged');
    },
  );

  testWidgets(
    'S-17206 protein under its target is the error colour; the other comparisons are neutral',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          caloriesAverage: 1800,
          targetCalories: 2000,
          proteinAverage: 100,
          targetProtein: 150,
          carbsAverage: 300,
          targetCarbs: 250,
          fatAverage: 50,
          previousFatAverage: 60,
        ),
      );

      expect(_text(tester, 'fuel_protein_change'), '↓ -50 g');
      expect(_text(tester, 'fuel_calories_change'), '↓ -200 kcal');
      expect(_text(tester, 'fuel_carbs_change'), '↑ +50 g');
      expect(_text(tester, 'fuel_fat_change'), '↓ -10 g');

      final theme = _pumpedTheme(tester);
      expect(
        _textColor(tester, 'fuel_protein_change'),
        theme.colorScheme.error.withValues(alpha: 0.8),
      );
      expect(_textColor(tester, 'fuel_calories_change'), _themeColors.textSecondary);
      expect(_textColor(tester, 'fuel_carbs_change'), _themeColors.textSecondary);
      expect(_textColor(tester, 'fuel_fat_change'), _themeColors.textSecondary);
    },
  );

  testWidgets(
    'S-17206 protein over its target is neutral even though it rose',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          proteinAverage: 200,
          targetProtein: 150,
        ),
      );

      expect(_text(tester, 'fuel_protein_change'), '↑ +50 g');
      expect(_textColor(tester, 'fuel_protein_change'), _themeColors.textSecondary);
    },
  );

  testWidgets(
    'S-17206 protein with no target is neutral even when it fell',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          proteinAverage: 100,
          previousProteinAverage: 150,
        ),
      );

      expect(_text(tester, 'fuel_protein_change'), '↓ -50 g');
      expect(_textColor(tester, 'fuel_protein_change'), _themeColors.textSecondary);
    },
  );

  testWidgets(
    'S-17206 a comparison too small to survive rounding reads as absent and muted',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          proteinAverage: 150.2,
          targetProtein: 150,
        ),
      );

      expect(_text(tester, 'fuel_protein_change'), '—');
      expect(_textColor(tester, 'fuel_protein_change'), _themeColors.textMuted);
    },
  );
}
