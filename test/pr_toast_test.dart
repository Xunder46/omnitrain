// Unit tests for the extracted `PRToast.buildPRSnackBar` factory.
//
// Plan: .github/agents/plans/in-session-pr-toast-plan.md
// Widget under test: lib/widgets/session/pr_toast.dart
//
// These tests pin the static builder's output (duration, behavior,
// content, action button) to the contract in Decision Ledger
// D-9, D-10, D-11, D-12. They run as pure unit tests — no widget
// pump, no `ScaffoldMessenger` — so the contract is testable in
// isolation from the full session screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/widgets/session/pr_toast.dart';

void main() {
  group('PRToast.buildPRSnackBar', () {
    final lightTheme = ThemeData.light();
    final darkTheme = ThemeData.dark();

    test(
      'duration is 4.0 s (long enough to read, never blocks the next set)',
      () {
        final bar = PRToast.buildPRSnackBar(lightTheme);
        expect(bar.duration, const Duration(milliseconds: 4000));
      },
    );

    test('behavior is floating (does not push the bottom controls up)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      expect(bar.behavior, SnackBarBehavior.floating);
    });

    test('has no action button (no required tap to dismiss — D-9)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      expect(
        bar.action,
        isNull,
        reason: 'toast must not require a tap to dismiss',
      );
    });

    test('background color is theme.colorScheme.surface (D-12)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      expect(bar.backgroundColor, lightTheme.colorScheme.surface);
    });

    test('background color tracks the active dark theme (D-12)', () {
      // Same factory, different theme → different surface color.
      final bar = PRToast.buildPRSnackBar(darkTheme);
      expect(bar.backgroundColor, darkTheme.colorScheme.surface);
    });

    test('margin anchors the toast above the bottom controls (D-10)', () {
      // 150 px bottom inset lifts the toast above the bottom controls
      // (numeric input row + rest-timer overlay) without overlapping
      // them. 16 px side insets match the D-10 horizontal padding
      // convention.
      const expectedMargin = EdgeInsets.only(bottom: 150, left: 16, right: 16);
      final bar = PRToast.buildPRSnackBar(lightTheme);
      expect(bar.margin, expectedMargin);
    });

    test('content is a Row containing the trophy icon and the copy (D-11)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      // Material wraps the content in a `MediaQuery`/`Theme` ancestor
      // when rendering, but the raw `content` field is the widget
      // we pass in.
      expect(bar.content, isA<Row>());
    });

    test('content copy is exactly "Congrats! New PR" (D-11)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      final row = bar.content as Row;
      // The Row has [Icon, SizedBox, Flexible<Text>]. The Text is
      // wrapped in Flexible for graceful overflow handling on
      // narrow phones; the helper unwraps it.
      final text = _firstTextUnder(row);
      expect(text, isNotNull);
      expect(text!.data, 'Congrats! New PR');
    });

    test('content icon is the trophy emoji icon (Icons.emoji_events)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      final row = bar.content as Row;
      final icon = row.children.whereType<Icon>().firstOrNull;
      expect(icon, isNotNull);
      expect(icon!.icon, Icons.emoji_events);
    });

    test('content icon is 2× the default size (18 → 36 px)', () {
      // "Twice bigger than now" — the trophy is the visual hook, so
      // it gets the full 2× bump from the 18 px convention.
      final bar = PRToast.buildPRSnackBar(lightTheme);
      final row = bar.content as Row;
      final icon = row.children.whereType<Icon>().first;
      expect(icon.size, 36.0);
    });

    test('content text is scaled up for the celebratory moment (18 px)', () {
      // Copy is bumped above bodyMedium's 14 px default so the
      // toast reads at a glance during a busy set log. The trophy
      // icon (36 px) and the copy size stay proportional.
      final bar = PRToast.buildPRSnackBar(lightTheme);
      final row = bar.content as Row;
      final text = _firstTextUnder(row)!;
      expect(text.style?.fontSize, 18.0);
    });

    test('icon color is theme.colorScheme.primary (D-12)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      final row = bar.content as Row;
      final icon = row.children.whereType<Icon>().first;
      expect(icon.color, lightTheme.colorScheme.primary);
    });

    test('text color is theme.colorScheme.onSurface (D-12)', () {
      final bar = PRToast.buildPRSnackBar(lightTheme);
      final row = bar.content as Row;
      final text = _firstTextUnder(row)!;
      // bodyMedium's default color is onSurface; our copyWith pins
      // it explicitly to make the test deterministic across themes.
      expect(text.style?.color, lightTheme.colorScheme.onSurface);
    });
  });
}

/// Returns the first `Text` widget found anywhere under [root], or
/// `null` if none exists. Recurses through `child` (single-child
/// wrappers like `Flexible`, `Expanded`, `Padding`) and `children`
/// (multi-child wrappers like `Row`, `Column`, `Stack`) so callers
/// don't have to know the exact depth at which the Text lives.
Text? _firstTextUnder(Widget widget) {
  if (widget is Text) return widget;
  // Single-child wrapper: `Flexible`, `Padding`, `Theme`, etc.
  try {
    final dynamic child = (widget as dynamic).child;
    if (child is Widget) {
      final found = _firstTextUnder(child);
      if (found != null) return found;
    }
  } on NoSuchMethodError {
    // Not a single-child wrapper — fall through to the children check.
  }
  // Multi-child wrapper: `Row`, `Column`, `Wrap`, `Stack`, etc.
  try {
    final dynamic children = (widget as dynamic).children;
    if (children is List) {
      for (final child in children) {
        if (child is Widget) {
          final found = _firstTextUnder(child);
          if (found != null) return found;
        }
      }
    }
  } on NoSuchMethodError {
    // Neither `child` nor `children` — terminal node.
  }
  return null;
}
