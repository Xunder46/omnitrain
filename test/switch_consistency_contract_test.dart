// Switch consistency contract (D-13).
//
// Every toggle-family control in the app renders through the theme's
// ColorScheme roles, so a theme change moves all of them together.
//
// Why this is a source-scanning contract rather than a widget test: on the
// Flutter version this app targets, `SwitchListTile.adaptive` and
// `SwitchListTile` build an identical widget tree on every platform
// (`SwitchListTile > Switch > _MaterialSwitch`) — no `CupertinoSwitch` node
// ever appears. The difference is the *switch config* `Switch.adaptive`
// applies on Apple platforms, which paints a Cupertino-style white thumb and
// does not track the theme's `outline` / `surfaceContainerHighest` roles the
// way the Material config does. That divergence is invisible to
// `find.byType`, so a widget test cannot gate it. Scanning the source can.
//
// This is the regression that let one filter toggle stay visible while every
// themed switch faded behind an under-contrast `outline` role.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Constructors that opt a control out of Material theming.
const _forbiddenConstructors = <String>[
  'Switch.adaptive(',
  'SwitchListTile.adaptive(',
  'CheckboxListTile.adaptive(',
  'Checkbox.adaptive(',
  'CupertinoSwitch(',
];

/// Colour parameters that, when passed at a call site, bypass the
/// ColorScheme roles for that control.
const _forbiddenColorParams = <String>[
  'activeColor:',
  'activeTrackColor:',
  'inactiveThumbColor:',
  'inactiveTrackColor:',
  'thumbColor:',
  'trackColor:',
  'trackOutlineColor:',
];

/// Files whose controls are not theme-driven by design. Empty on purpose —
/// an entry here is a deliberate, reviewed exception, not a convenience.
const _exemptFiles = <String>[];

List<File> _libDartFiles() {
  final dir = Directory('lib');
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !_exemptFiles.contains(f.path))
      .toList();
}

void main() {
  group('Switch consistency contract', () {
    test('no toggle control opts out of Material theming', () {
      final violations = <String>[];

      for (final file in _libDartFiles()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final ctor in _forbiddenConstructors) {
            if (lines[i].contains(ctor)) {
              violations.add(
                '${file.path}:${i + 1}: uses `$ctor` — adaptive and Cupertino '
                'controls paint from a platform switch config instead of the '
                "theme's ColorScheme roles. Use the Material constructor.",
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Toggle controls must render through the theme so every switch in '
            'the app moves together when the theme changes.\n'
            '${violations.join('\n')}',
      );
    });

    test('no switch call site hardcodes its colours', () {
      final violations = <String>[];
      final switchLine = RegExp(r'\b(Switch|SwitchListTile)\s*\(');

      for (final file in _libDartFiles()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!switchLine.hasMatch(lines[i])) continue;

          // Scan the constructor's argument list to its closing paren.
          var depth = 0;
          var started = false;
          for (var j = i; j < lines.length && j < i + 40; j++) {
            for (final ch in lines[j].split('')) {
              if (ch == '(') {
                depth++;
                started = true;
              } else if (ch == ')') {
                depth--;
              }
            }
            if (j > i) {
              for (final param in _forbiddenColorParams) {
                if (lines[j].contains(param)) {
                  violations.add(
                    '${file.path}:${j + 1}: `$param` on the switch opened at '
                    'line ${i + 1} — colours belong to the ColorScheme roles.',
                  );
                }
              }
            }
            if (started && depth <= 0) break;
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Switch colours come from the theme, never from the call site.\n'
            '${violations.join('\n')}',
      );
    });
  });
}
