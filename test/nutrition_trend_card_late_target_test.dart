// Plan 263: the dashed target lines on the nutrition trend charts begin on the
// first day with a saved target; nothing is drawn before it.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/omni_theme.dart';
import 'package:omnitrain/core/models/stats_progress.dart';
import 'package:omnitrain/features/nutrition/widgets/nutrition_trend_card.dart';

final _first = DateTime(2026, 11, 10);

List<NutritionTrendPoint> _trend() => [
  for (var i = 0; i < 6; i++)
    NutritionTrendPoint(
      date: DateTime(2026, 11, 10 + i),
      calories: 1800 + i * 10,
      protein: 100,
      carbs: 200,
      fat: 60,
    ),
];

NutritionAdherence _adherence() => NutritionAdherence(
  actuals: _trend(),
  targetLine: [
    // The first target is saved on the fourth logged day.
    NutritionAdherenceTargetPoint(
      date: DateTime(2026, 11, 13),
      calories: 2000,
      protein: 150,
      carbs: 220,
      fat: 70,
    ),
  ],
);

Future<List<LineChartBarData>> _dashed(
  WidgetTester tester,
  NutritionTrendView view,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: NutritionTrendCard(
            trend: _trend(),
            adherence: _adherence(),
            themeColors: OmniTheme.colors,
            view: view,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final chart = tester.widget<LineChart>(find.byType(LineChart).first);
  return chart.data.lineBarsData.where((b) => b.dashArray != null).toList();
}

void main() {
  testWidgets(
    'S-26305 the calories target line starts on the first target day',
    (tester) async {
      final dashed = await _dashed(tester, NutritionTrendView.calories);
      expect(dashed, hasLength(1));
      expect(dashed.first.spots.first.x, 3);
      expect(dashed.first.spots.map((s) => s.x), [3, 4, 5]);
      expect(dashed.first.spots.every((s) => s.y == 2000), isTrue);
      expect(_first.isBefore(DateTime(2026, 11, 13)), isTrue);
    },
  );

  testWidgets('S-26306 the macro target lines start on the first target day', (
    tester,
  ) async {
    final dashed = await _dashed(tester, NutritionTrendView.macros);
    expect(dashed, hasLength(3));
    for (final bar in dashed) {
      expect(bar.spots.map((s) => s.x), [3, 4, 5]);
    }
  });
}
