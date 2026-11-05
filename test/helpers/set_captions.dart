import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Readers for the set bar's captions (plan 38f, D-10).
///
/// `SetSegmentBar` keys every caption `set-caption-$i` with the 0-based segment
/// index, so a screen test reads one logged set's value without parsing the
/// old joined line.

/// The caption under segment [i].
Finder setCaption(int i) => find.byKey(Key('set-caption-$i'));

/// The text the caption under segment [i] shows (`''` when it is unlogged).
String setCaptionText(WidgetTester tester, int i) =>
    tester.widget<Text>(setCaption(i)).data ?? '';

/// Whether the bar renders a captions row at all (the first caption exists).
bool captionsPresent() => setCaption(0).evaluate().isNotEmpty;

/// Every non-empty caption on screen, in segment order.
List<String> captionTexts(WidgetTester tester) {
  final texts = <String>[];
  for (
    var i = 0;
    captionsPresent() && setCaption(i).evaluate().isNotEmpty;
    i++
  ) {
    final text = setCaptionText(tester, i);
    if (text.isNotEmpty) texts.add(text);
  }
  return texts;
}
