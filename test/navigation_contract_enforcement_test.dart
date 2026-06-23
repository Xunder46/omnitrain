// filepath: test/navigation_contract_enforcement_test.dart
//
// Automated enforcement of OmniTrain's navigation contract.
//
// Rule (see `.github/agents/docs/navigation_contract.md`):
//   Any `MaterialPageRoute` or `PageRouteBuilder` constructed outside
//   `lib/core/navigation/` is a code-review blocker. All screen-level
//   navigation in OmniTrain must go through `OmniNavigator`
//   (`lib/core/navigation/omni_navigator.dart`).
//
// This test walks `lib/` recursively and fails the build if any
// application feature or UI file contains a raw route construction.
// It mirrors the file-system-scan pattern used in
// `test/emphasis_tier_contract_test.dart` ("no frozen theme constants
// remain outside omni_theme.dart").
//
// The check deliberately:
//   * excludes `lib/core/navigation/` — that module legitimately
//     defines `OmniRoute<T> extends PageRoute<T>` and references the
//     forbidden primitives in doc comments explaining the contract.
//   * excludes `test/` — `MaterialPageRoute` is used as harness setup
//     inside test widgets (e.g. `pumpWidget(MaterialApp(home: ...))`).
//     This matches the policy captured in the original route-migration
//     audit (`docs/route-migration-audit.md`, "Test Files Reviewed").
//
// A failure message names every offending file and points the caller at
// the standard navigation path (`OmniNavigator` in
// `lib/core/navigation/`) as the required fix.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Navigation contract enforcement', () {
    test(
      'no MaterialPageRoute or PageRouteBuilder construction outside '
      'lib/core/navigation/',
      () async {
        final violations = <String>[];
        final libDir = Directory('lib');

        await for (final entity
            in libDir.list(recursive: true, followLinks: false)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;

          // Skip the navigation module itself — it is the sole legitimate
          // owner of route construction.
          if (entity.path.startsWith('lib/core/navigation/')) continue;

          final content = await entity.readAsString();

          // Match construction sites only — the open paren after the type
          // name. Bare type references in doc comments (e.g.
          // "raw MaterialPageRoute / PageRouteBuilder outside this module")
          // and `isA<MaterialPageRoute<...>>` checks do not contain `(`
          // immediately after the type name, so they are not flagged.
          if (content.contains('MaterialPageRoute(')) {
            violations.add('${entity.path}: MaterialPageRoute(');
          }
          if (content.contains('PageRouteBuilder(')) {
            violations.add('${entity.path}: PageRouteBuilder(');
          }
        }

        expect(
          violations,
          isEmpty,
          reason: violations.isEmpty
              ? null
              : 'Navigation contract violation: raw route construction '
                    'outside lib/core/navigation/ is not allowed. '
                    'Use OmniNavigator (in '
                    'lib/core/navigation/omni_navigator.dart) for every '
                    'screen-level push / pushReplacement. '
                    'See .github/agents/docs/navigation_contract.md.\n'
                    'Offending files:\n${violations.join('\n')}',
        );
      },
    );
  });
}
