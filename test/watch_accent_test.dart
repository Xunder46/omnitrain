// The unit tests for plan 286: the wrist's accent class, `WatchAccent`
// (`lib/watch/widgets/watch_accent.dart`), held to the shared contract table.
//
// Scenario mapping (plan
// `docs/plans/2026-11-21-286-wear-accent-theming-plan/2026-11-21-286-wear-accent-theming-plan.md`,
// section "Scenarios"):
//   S-28601 the contract's six accents read the table's contrast figures
//           → `S-28601 ...`
//   S-28602 the parser accepts `#RRGGBB` and nothing else → `S-28602 ...`
//   S-28603 the wearability floor is 3.0 → `S-28603 ...`
//   S-28604 the label rule compares the two contrasts → `S-28604 ...`
//   S-28605 `worn` falls back or wears the accent → `S-28605 ...`
//   S-28606 the channels are not mixed → `S-28606 ...`
//
// The shell half (the theme the shell wears) is `test/wear_accent_theme_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/watch/widgets/watch_accent.dart';

/// `watch/contract/watch_accent_contract.json`, parsed.
Map<String, Object?> _contract() =>
    jsonDecode(
          File('watch/contract/watch_accent_contract.json').readAsStringSync(),
        )
        as Map<String, Object?>;

/// The table's rows, in file order.
List<Map<String, Object?>> _rows() =>
    (_contract()['themes']! as List<Object?>).cast<Map<String, Object?>>();

void main() {
  test('S-28601 the contract\'s six accents parse and read the table\'s '
      'contrast figures', () {
    const againstBlack = <double>[13.133, 8.171, 10.981, 6.709, 6.377, 8.079];
    final rows = _rows();
    expect(
      rows.length,
      againstBlack.length,
      reason: 'S-28601 the figures below are per row, in table order',
    );

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final hex = row['hex']! as String;
      final accent = WatchAccent.tryParse(hex);

      expect(
        accent,
        isNotNull,
        reason: 'S-28601 $hex is one of the agreed accents and parses',
      );
      expect(
        accent!.isUsable,
        isTrue,
        reason: 'S-28601 $hex is above the floor the table sets',
      );
      expect(
        accent.labelIsDark,
        row['labelIsDark'],
        reason: 'S-28601 $hex takes the label the row names',
      );
      expect(
        WatchAccent.minContrastAgainstBlack,
        (_contract()['minContrastAgainstBlack']! as num).toDouble(),
        reason: 'S-28601 the floor in code is the floor in the table',
      );
      expect(
        accent.contrastAgainstBlack,
        moreOrLessEquals(againstBlack[i], epsilon: 0.01),
        reason: 'S-28601 $hex\'s contrast against black is the figure the '
            'plan derived from the WCAG formula',
      );
    }
  });

  test('S-28602 the parser accepts #RRGGBB and nothing else', () {
    for (final hex in const <String>['#2DE2E6', '#2de2e6']) {
      final accent = WatchAccent.tryParse(hex);
      expect(
        accent,
        isNotNull,
        reason: 'S-28602 $hex parses whatever case it arrives in',
      );
      expect(accent!.red, 45, reason: 'S-28602 $hex red');
      expect(accent.green, 226, reason: 'S-28602 $hex green');
      expect(accent.blue, 230, reason: 'S-28602 $hex blue');
    }

    for (final hex in const <String>[
      '2DE2E6',
      '#2DE2E',
      '#2DE2E6F',
      '#2DE2E6FF',
      '#GGGGGG',
      ' #2DE2E6',
      '#2DE2E6 ',
      '',
      '#',
    ]) {
      expect(
        WatchAccent.tryParse(hex),
        isNull,
        reason: 'S-28602 "$hex" is not #RRGGBB and is refused',
      );
    }
  });

  test('S-28603 the wearability floor is 3.0', () {
    // #5A5A5A reads 3.0448 against black; #595959 reads 2.998: the pair
    // straddles the floor by one grey step.
    final above = WatchAccent.tryParse('#5A5A5A')!;
    expect(above.isUsable, isTrue, reason: 'S-28603 3.0448 clears 3.0');
    expect(
      WatchAccent.usable('#5A5A5A'),
      isNotNull,
      reason: 'S-28603 an accent above the floor is one the wrist may wear',
    );

    final below = WatchAccent.tryParse('#595959')!;
    expect(below.isUsable, isFalse, reason: 'S-28603 2.998 does not clear 3.0');
    expect(
      WatchAccent.usable('#595959'),
      isNull,
      reason: 'S-28603 an accent below the floor is refused',
    );

    expect(
      WatchAccent.usable(null),
      isNull,
      reason: 'S-28603 no string, no accent',
    );
  });

  test('S-28604 the label rule compares the two contrasts', () {
    // #757575: black 4.5578 < white 4.6075, so white labels read better.
    final grey = WatchAccent.tryParse('#757575')!;
    expect(
      grey.labelIsDark,
      isFalse,
      reason: 'S-28604 #757575 reads better with white text',
    );
    expect(
      grey.labelColor,
      Colors.white,
      reason: 'S-28604 #757575\'s label is the one that reads',
    );

    // #777777: black 4.6895 > white 4.4781, so black labels read better.
    final darkerGrey = WatchAccent.tryParse('#777777')!;
    expect(darkerGrey.labelIsDark, isTrue, reason: 'S-28604 #777777 black');
    expect(darkerGrey.labelColor, Colors.black, reason: 'S-28604 #777777');

    // #767676, the next grey step: black 4.6233 > white 4.5422. With #757575
    // above it pins the switch to one grey step, so a white numerator that is
    // a few percent off flips one of the two.
    expect(
      WatchAccent.tryParse('#767676')!.labelIsDark,
      isTrue,
      reason: 'S-28604 #767676 is the first grey that takes black',
    );

    // #038901: black 4.582574 < white 4.582577. Its small red and blue channels
    // sit on the linear branch (value/255 <= 0.03928, divided by 12.92), so a
    // wrong divisor there moves the luminance enough to flip the label.
    final green = WatchAccent.tryParse('#038901')!;
    expect(green.isUsable, isTrue, reason: 'S-28604 #038901 clears the floor');
    expect(
      green.labelIsDark,
      isFalse,
      reason: 'S-28604 #038901 reads a hair better with white text',
    );

    expect(
      WatchAccent.tryParse('#FFFFFF')!.labelIsDark,
      isTrue,
      reason: 'S-28604 black on white is the extreme case',
    );
  });

  test('S-28605 worn falls back or wears the accent', () {
    for (final hex in const <String?>[
      null,
      '',
      'garbage',
      '#202020',
      '#000000',
      '#595959',
    ]) {
      expect(
        WatchAccent.worn(hex).color,
        const Color(0xFF2DE2E6),
        reason: 'S-28605 "$hex" is no accent the wrist wears, so it wears the '
            'phone\'s default theme accent',
      );
    }

    expect(
      WatchAccent.worn('#FF7B45').color,
      const Color(0xFFFF7B45),
      reason: 'S-28605 a usable accent is worn as itself',
    );
    expect(
      WatchAccent.worn('#757575').color,
      const Color(0xFF757575),
      reason: 'S-28605 a usable accent is worn as itself',
    );
  });

  test('S-28606 the channels are not mixed', () {
    expect(
      WatchAccent.tryParse('#FF7B45')!.color,
      Color.fromARGB(255, 255, 123, 69),
      reason: 'S-28606 FF→red, 7B→green, 45→blue',
    );
  });
}
