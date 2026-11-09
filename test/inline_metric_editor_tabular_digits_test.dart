// The live metric readout (timer, count-up, ring digits) uses fixed-width
// figures so it does not shift horizontally as different digits appear.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/session/inline_metric_editor.dart';

void main() {
  for (final tier in [null, ...MetricEmphasisTier.values]) {
    testWidgets('duration readout is tabular at tier $tier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineMetricEditor(
              metricType: 'duration',
              currentValue: 71,
              unitLabel: '',
              emphasisTier: tier,
              onValueChanged: (_) {},
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('01:11'));
      expect(
        text.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  }
}
