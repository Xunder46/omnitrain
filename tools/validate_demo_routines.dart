// Build-time validator entry point for the bundled demo-routine seed.
//
// Invoked by `scripts/pre_release_check.sh` to gate an Xcode Archive
// against dangling references and missing kind-appropriate targets.
// The same rule set also runs at runtime from `lib/main.dart` on every
// debug / profile launch (see `_validateBundledDemoRoutines`).
//
// Exits with a non-zero status when any rule fails; the full list of
// failures is printed to stdout so CI / pre-release logs stay readable.
import 'dart:io';

import 'package:omnitrain/core/services/bundled_catalog_source.dart';
import 'package:omnitrain/core/services/demo_routines_validator.dart';

Future<void> main() async {
  final source = BundledCatalogSource();
  final result = DemoRoutinesValidator.validate(
    source.routineTemplates,
    source.exercises.map((e) => e.id).toSet(),
  );
  if (result.isValid) {
    stdout.writeln('Demo routine validator: ok');
  } else {
    stdout.writeln('Demo routine validator: ${result.summary}');
    for (final failure in result.failures) {
      stdout.writeln('  - $failure');
    }
    exitCode = 1;
  }
}
