// The Stats primer sheet's wording (the "?" on Stats, "A quick orientation").
//
// The sheet describes the screen in words, so it goes stale whenever a block
// is added or removed. These tests pin the shipped copy, and name the claims
// that were true once and are not any more: "all-time totals" left Stats for
// Records & Trends, and signals no longer all wait for four rated weeks.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/features/stats/widgets/stats_primer_sheet.dart';

String _bodyOf(WidgetTester tester, String blockKey) {
  final texts = find
      .descendant(
        of: find.byKey(Key(blockKey)),
        matching: find.byType(Text),
      )
      .evaluate()
      .map((e) => (e.widget as Text).data!)
      .toList();
  // The block is a header and one body sentence; the body is the longer one.
  texts.sort((a, b) => b.length.compareTo(a.length));
  return texts.first;
}

void main() {
  group('S-18001 the primer says what the Stats screen shows today', () {
    testWidgets('the page block names the four blocks and no all-time totals', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StatsPrimerSheet())),
      );

      final body = _bodyOf(tester, 'stats_primer_block_page');

      expect(
        body,
        'Your training mix over the last four weeks, the exercises you '
        'trained and how they changed against the four weeks before, your '
        'Fuel row once you log food, and your weight change once you have '
        'two weigh-ins at least a week apart in the last four weeks.',
      );
      expect(body, isNot(contains('all-time')));
    });

    testWidgets('the signals block says some speak at once and what is missing '
        'is shown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StatsPrimerSheet())),
      );

      final body = _bodyOf(tester, 'stats_primer_block_signals');

      expect(
        body,
        'Short notes about your own patterns, compared only with your own '
        'history. Some speak from your first sessions. Others need about '
        'four weeks of rating how hard each workout felt, a few weeks of '
        'history, food logging, or a watch. A line under the cards says what '
        'is still missing. Dismiss any card and it stays hidden for 14 days.',
      );
      expect(body, isNot(contains('They start after')));
    });
  });
}
