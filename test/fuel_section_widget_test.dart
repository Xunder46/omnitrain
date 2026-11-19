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
  int trainingLoggedDays = 2,
  double? restCaloriesAverage,
  int restLoggedDays = 2,
  double? burnedKcalAverage,
  int burnedSessionCount = 0,
  bool burnedIsEstimate = false,
  double? burnedPerDayAverage,
  bool hasRecentFood = true,
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
    trainingLoggedDays: trainingLoggedDays,
    restCaloriesAverage: restCaloriesAverage,
    restLoggedDays: restLoggedDays,
    burnedKcalAverage: burnedKcalAverage,
    burnedSessionCount: burnedSessionCount,
    burnedIsEstimate: burnedIsEstimate,
    burnedPerDayAverage: burnedPerDayAverage,
    hasRecentFood: hasRecentFood,
    targetCalories: targetCalories,
    targetProtein: targetProtein,
    targetCarbs: targetCarbs,
    targetFat: targetFat,
  );
}

Future<void> _pumpFuel(
  WidgetTester tester,
  FuelSummary summary, {
  VoidCallback? onTap,
}) async {
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
            onTap: onTap ?? () {},
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
          restCaloriesAverage: 1600,
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
      expect(find.byKey(const Key('fuel_split')), findsNothing);
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
          restCaloriesAverage: 1600,
        ),
      );

      expect(find.byKey(const Key('fuel_not_enough_days')), findsNothing);
      expect(find.byKey(const Key('fuel_calories')), findsOneWidget);
      expect(find.byKey(const Key('fuel_split')), findsOneWidget);
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
    'S-20801 the split is one calories-only line and the burned line reads '
    'the window average',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          trainingCaloriesAverage: 1950,
          restCaloriesAverage: 1652,
          burnedKcalAverage: 310.4,
          burnedSessionCount: 5,
          burnedIsEstimate: true,
        ),
      );

      expect(
        _text(tester, 'fuel_split'),
        'Training days 1950 · Rest days 1652 kcal',
      );
      // Protein survives only as its own metric label: the split is
      // calories-only (D-1).
      final proteinTexts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('fuel_section')),
              matching: find.byType(Text),
            ),
          )
          .where((t) => (t.data ?? '').toLowerCase().contains('protein'))
          .map((t) => t.data)
          .toList();
      expect(proteinTexts, ['Protein']);
      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: ~310 kcal · 5 sessions',
      );
    },
  );

  testWidgets(
    'S-13434 the burned line rounds, drops the tilde when measured, and '
    'singles one session',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          trainingCaloriesAverage: 1950,
          restCaloriesAverage: 1652,
          burnedKcalAverage: 310.4,
          burnedSessionCount: 1,
        ),
      );

      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: 310 kcal · 1 session',
      );
    },
  );

  testWidgets(
    'S-13434 a burned average with no row in the window reads a dash',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          trainingCaloriesAverage: 1950,
          restCaloriesAverage: 1652,
        ),
      );

      expect(_text(tester, 'fuel_burned'), 'Burned per session: —');
    },
  );

  testWidgets(
    'S-20802 a rest side with no logged days draws no split at all',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          trainingCaloriesAverage: 1950,
          trainingLoggedDays: 3,
          restCaloriesAverage: null,
          restLoggedDays: 0,
        ),
      );

      expect(find.byKey(const Key('fuel_split')), findsNothing);
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('fuel_section')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList();
      expect(texts.where((t) => t.contains('Rest days')), isEmpty);
      expect(texts.where((t) => t.contains('Training days')), isEmpty);
    },
  );

  testWidgets(
    'S-20803 a card with no training day draws no split',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          trainingCaloriesAverage: null,
          trainingLoggedDays: 0,
          restCaloriesAverage: 1700,
          restLoggedDays: 3,
        ),
      );

      expect(find.byKey(const Key('fuel_split')), findsNothing);
    },
  );

  testWidgets(
    'S-20804 the split needs two logged days on each side',
    (tester) async {
      // One training day: below kFuelMinSplitDays on that side.
      await _pumpFuel(
        tester,
        _summary(
          trainingCaloriesAverage: 2000,
          trainingLoggedDays: 1,
          restCaloriesAverage: 1700,
          restLoggedDays: 5,
        ),
      );
      expect(find.byKey(const Key('fuel_split')), findsNothing);

      // One rest day: the same on the other side.
      await _pumpFuel(
        tester,
        _summary(
          trainingCaloriesAverage: 2000,
          trainingLoggedDays: 5,
          restCaloriesAverage: 1700,
          restLoggedDays: 1,
        ),
      );
      expect(find.byKey(const Key('fuel_split')), findsNothing);

      // Two logged days on each side: the split draws.
      await _pumpFuel(
        tester,
        _summary(
          trainingCaloriesAverage: 2000,
          trainingLoggedDays: 2,
          restCaloriesAverage: 1700,
          restLoggedDays: 2,
        ),
      );
      expect(
        _text(tester, 'fuel_split'),
        'Training days 2000 · Rest days 1700 kcal',
      );
    },
  );

  testWidgets(
    'S-20805 with only 2 logged days the burn line still draws',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 2,
          trainingCaloriesAverage: 1950,
          restCaloriesAverage: 1652,
          burnedKcalAverage: 300,
          burnedSessionCount: 1,
        ),
      );

      expect(find.byKey(const Key('fuel_not_enough_days')), findsOneWidget);
      expect(_text(tester, 'fuel_logged_days'), '2/7 days logged');
      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: 300 kcal · 1 session',
      );
      expect(find.byKey(const Key('fuel_split')), findsNothing);
    },
  );

  testWidgets(
    "S-13435 no text on the Fuel card says net, surplus, deficit or left to burn",
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          trainingCaloriesAverage: 1950,
          restCaloriesAverage: 1652,
          burnedKcalAverage: 310.4,
          burnedSessionCount: 5,
          burnedIsEstimate: true,
        ),
      );

      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('fuel_section')),
              matching: find.byType(Text),
            ),
          )
          .toList();
      expect(texts, isNotEmpty);
      for (final text in texts) {
        final lower = (text.data ?? '').toLowerCase();
        expect(lower, isNot(contains('net')));
        expect(lower, isNot(contains('surplus')));
        expect(lower, isNot(contains('deficit')));
        expect(lower, isNot(contains('left to burn')));
      }
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

  testWidgets(
    'S-20839 the caption lines read in the D-7 order and wording',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 7,
          caloriesAverage: 2000,
          proteinAverage: 100,
          carbsAverage: 250,
          fatAverage: 60,
          trainingCaloriesAverage: 2022,
          trainingLoggedDays: 3,
          restCaloriesAverage: 1850,
          restLoggedDays: 4,
          burnedPerDayAverage: 519.5,
          burnedKcalAverage: 89,
          burnedSessionCount: 9,
        ),
      );

      expect(_text(tester, 'fuel_logged_days'), '7/7 days logged');
      expect(
        _text(tester, 'fuel_split'),
        'Training days 2022 · Rest days 1850 kcal',
      );
      expect(
        _text(tester, 'fuel_burned_day'),
        'Burned per day: 520 kcal · active, all movement',
      );
      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: 89 kcal · 9 sessions',
      );

      final loggedDy =
          tester.getTopLeft(find.byKey(const Key('fuel_logged_days'))).dy;
      final splitDy = tester.getTopLeft(find.byKey(const Key('fuel_split'))).dy;
      final burnedDayDy =
          tester.getTopLeft(find.byKey(const Key('fuel_burned_day'))).dy;
      final burnedDy =
          tester.getTopLeft(find.byKey(const Key('fuel_burned'))).dy;
      expect(splitDy, greaterThan(loggedDy));
      expect(burnedDayDy, greaterThan(splitDy));
      expect(burnedDy, greaterThan(burnedDayDy));
    },
  );

  testWidgets(
    'S-20836 Burned per day draws with fewer than 3 food days',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(loggedDays: 2, burnedPerDayAverage: 480.4),
      );

      expect(find.byKey(const Key('fuel_not_enough_days')), findsOneWidget);
      expect(
        _text(tester, 'fuel_burned_day'),
        'Burned per day: 480 kcal · active, all movement',
      );
    },
  );

  testWidgets(
    'S-20839 Burned per day is absent when there is no figure',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          burnedKcalAverage: 89,
          burnedSessionCount: 9,
        ),
      );

      expect(find.byKey(const Key('fuel_burned_day')), findsNothing);
      expect(find.byKey(const Key('fuel_burned')), findsOneWidget);
    },
  );

  testWidgets(
    'S-20843 with recent food and no burn figure the card keeps its '
    'per-session dash and has no per-day line',
    (tester) async {
      await _pumpFuel(tester, _summary(loggedDays: 3));

      expect(_text(tester, 'fuel_burned'), 'Burned per session: —');
      expect(find.byKey(const Key('fuel_burned_day')), findsNothing);
    },
  );

  testWidgets(
    'S-20841 burn-only shows only the header, the window line and the '
    'per-session line',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 0,
          hasRecentFood: false,
          burnedKcalAverage: 400,
          burnedSessionCount: 2,
          burnedIsEstimate: true,
        ),
      );

      expect(find.text('FUEL'), findsOneWidget);
      expect(_text(tester, 'fuel_horizon'), 'Last 7 days');
      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: ~400 kcal · 2 sessions',
      );
      for (final key in [
        'fuel_logged_days',
        'fuel_not_enough_days',
        'fuel_calories',
        'fuel_protein',
        'fuel_carbs',
        'fuel_fat',
        'fuel_split',
        'fuel_burned_day',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('fuel_section')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList();
      expect(texts, isNot(contains('—')));
    },
  );

  testWidgets(
    'S-20841 burn-only is not tappable',
    (tester) async {
      var taps = 0;
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 0,
          hasRecentFood: false,
          burnedKcalAverage: 400,
          burnedSessionCount: 2,
        ),
        onTap: () => taps++,
      );
      final handle = tester.ensureSemantics();

      await tester.tap(find.byKey(const Key('fuel_section')), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0);
      expect(find.byKey(const Key('fuel_row')), findsNothing);
      expect(find.bySemanticsLabel('Nutrition trend'), findsNothing);
      handle.dispose();
    },
  );

  testWidgets(
    'S-20841 with recent food the card is still tappable',
    (tester) async {
      var taps = 0;
      await _pumpFuel(
        tester,
        _summary(loggedDays: 5),
        onTap: () => taps++,
      );

      expect(find.byKey(const Key('fuel_row')), findsOneWidget);
      await tester.tap(find.byKey(const Key('fuel_row')), warnIfMissed: false);
      await tester.pump();

      expect(taps, 1);
    },
  );

  testWidgets(
    'S-20844 burn-only with both burn lines reads them in the D-7 order',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 0,
          hasRecentFood: false,
          burnedPerDayAverage: 520,
          burnedKcalAverage: 400,
          burnedSessionCount: 2,
          burnedIsEstimate: true,
        ),
      );

      expect(
        _text(tester, 'fuel_burned_day'),
        'Burned per day: 520 kcal · active, all movement',
      );
      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: ~400 kcal · 2 sessions',
      );
      final burnedDayDy =
          tester.getTopLeft(find.byKey(const Key('fuel_burned_day'))).dy;
      final burnedDy =
          tester.getTopLeft(find.byKey(const Key('fuel_burned'))).dy;
      expect(burnedDy, greaterThan(burnedDayDy));
    },
  );

  testWidgets(
    'S-20848 burn-only with only a per-day figure draws no per-session '
    'line and no dash',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 0,
          hasRecentFood: false,
          burnedPerDayAverage: 520,
        ),
      );

      expect(
        _text(tester, 'fuel_burned_day'),
        'Burned per day: 520 kcal · active, all movement',
      );
      expect(find.byKey(const Key('fuel_burned')), findsNothing);
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('fuel_section')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? '')
          .toList();
      expect(texts, isNot(contains('—')));
    },
  );

  testWidgets(
    'S-20851 a summary built without hasRecentFood is the normal tappable card',
    (tester) async {
      var taps = 0;
      await _pumpFuel(
        tester,
        const FuelSummary(
          loggedDays: 5,
          caloriesAverage: 1800,
          proteinAverage: 100,
          carbsAverage: 300,
          fatAverage: 50,
          previousCaloriesAverage: null,
          previousProteinAverage: null,
          previousCarbsAverage: null,
          previousFatAverage: null,
          trainingCaloriesAverage: null,
          trainingLoggedDays: 0,
          restCaloriesAverage: null,
          restLoggedDays: 0,
          targetCalories: 0,
          targetProtein: 0,
          targetCarbs: 0,
          targetFat: 0,
        ),
        onTap: () => taps++,
      );

      expect(find.byKey(const Key('fuel_calories')), findsOneWidget);
      expect(find.byKey(const Key('fuel_row')), findsOneWidget);
      await tester.tap(find.byKey(const Key('fuel_row')));
      await tester.pump();
      expect(taps, 1);
    },
  );

  testWidgets(
    'S-20841 burn-only never draws intake figures, even from a summary that '
    'carries them',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 5,
          hasRecentFood: false,
          caloriesAverage: 1800,
          proteinAverage: 100,
          carbsAverage: 300,
          fatAverage: 50,
          burnedKcalAverage: 300,
          burnedSessionCount: 1,
        ),
      );

      for (final key in [
        'fuel_calories',
        'fuel_protein',
        'fuel_carbs',
        'fuel_fat',
        'fuel_logged_days',
        'fuel_not_enough_days',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: 300 kcal · 1 session',
      );
    },
  );

  testWidgets(
    'S-20848 burn-only with only a per-session figure draws no per-day line',
    (tester) async {
      await _pumpFuel(
        tester,
        _summary(
          loggedDays: 0,
          hasRecentFood: false,
          burnedKcalAverage: 310.4,
          burnedSessionCount: 1,
        ),
      );

      expect(
        _text(tester, 'fuel_burned'),
        'Burned per session: 310 kcal · 1 session',
      );
      expect(find.byKey(const Key('fuel_burned_day')), findsNothing);
    },
  );
}
