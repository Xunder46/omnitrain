import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/layout/omni_surface.dart';
import 'package:omnitrain/features/home/widgets/nutrition_summary_card.dart';
import 'package:omnitrain/core/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';


class _FakePrefs implements PreferencesService {
  @override
  Future<void> init() async {}
  @override
  int getHubOpenCount() => 0;
  @override
  Future<void> incrementHubOpenCount() async {}
}

void main() {
  testWidgets('measure card natural height', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: NutritionSummaryCard(
            consumedCalories: 1234,
            targetCalories: 2000,
            proteinKcal: 600, carbsKcal: 400, fatKcal: 234,
            onTap: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('nutrition_card')));
    debugPrint('CARD_TOTAL_HEIGHT=${rect.height}');

    final omni = tester.getRect(find.byType(OmniSurface));
    debugPrint('OMNI_HEIGHT=${omni.height}');

    final col = tester.getRect(find.byType(Column).first);
    debugPrint('FIRST_COL_HEIGHT=${col.height}');
  });
}
