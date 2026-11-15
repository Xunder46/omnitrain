// The one phone gate on the Diagnostics entry points (plan 177, D-17702):
// debug ∪ profile ∪ explicit owner override. The log itself records in every
// build; only the entry points are gated.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/diagnostics_entry.dart';

void main() {
  // S-17701: the truth table the release gate and the widget test both read.
  test('S-17701 the visibility predicate is debug or profile or override', () {
    expect(
      diagnosticsEntryVisibleFor(
        debugBuild: true,
        profileBuild: false,
        override: false,
      ),
      isTrue,
      reason: 'a debug build shows the entry point',
    );
    expect(
      diagnosticsEntryVisibleFor(
        debugBuild: false,
        profileBuild: true,
        override: false,
      ),
      isTrue,
      reason: 'a profile build shows the entry point',
    );
    expect(
      diagnosticsEntryVisibleFor(
        debugBuild: false,
        profileBuild: false,
        override: false,
      ),
      isFalse,
      reason: 'a release build with no override hides the entry point',
    );
    expect(
      diagnosticsEntryVisibleFor(
        debugBuild: false,
        profileBuild: false,
        override: true,
      ),
      isTrue,
      reason: 'the owner override reveals the entry point in a release build',
    );
    expect(
      diagnosticsEntryVisibleFor(
        debugBuild: true,
        profileBuild: false,
        override: true,
      ),
      isTrue,
      reason: 'the override never turns a visible entry point off',
    );
  });

  // S-17706: a const environment read cannot be flipped at runtime, so the one
  // spelling the owner passes on the command line is pinned as text. Whitespace
  // is collapsed first, so a formatter reflow cannot soften the assertion.
  test('S-17706 the override reads OMNITRAIN_DIAGNOSTICS once', () {
    final source = File(
      'lib/core/constants/diagnostics_entry.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    expect(
      RegExp(
        r"const bool kOmnitrainDiagnosticsOverride = "
        r"bool\.fromEnvironment\(\s*'OMNITRAIN_DIAGNOSTICS',?\s*\);",
      ).hasMatch(source),
      isTrue,
      reason: 'the owner passes --dart-define=OMNITRAIN_DIAGNOSTICS=true',
    );
    expect(
      source,
      contains('const bool kDiagnosticsEntryVisible ='),
      reason: 'main.dart reads one constant, not an ad-hoc build-mode check',
    );
    expect(
      source,
      contains('kDebugMode'),
      reason: 'a debug build shows the entry point',
    );
    expect(
      source,
      contains('kProfileMode'),
      reason: 'a profile build shows the entry point',
    );
  });
}
