// The parts of a watch ↔ phone test harness that are the same whichever side
// the file is testing: where the protocol lives, how to read it, and a clock
// that is not the wall clock.
//
// Used by `test/live_mirroring_test.dart` (convergence against the protocol's
// own fixtures) and `test/phone_manage_bridge_test.dart` (what the phone emits,
// judged by the protocol's own schemas).
//
// Only the genuinely shared pieces are here. The two files' *domain* fixtures
// (`_slot`, `_setEvent`, `_snapshotPayload`) differ on purpose — one side starts
// from the wrist's store, the other from the handset's — and stay local.
//
// `readProtocolJson` takes a path relative to the protocol root, so no caller
// has to know where the protocol is checked in.

import 'dart:convert';
import 'dart:io';

import 'package:omnitrain/core/sync_protocol/message_validator.dart';

/// Where the protocol's schemas and fixtures live, relative to the package
/// root.
const String syncProtocolRoot = 'watch/sync_protocol';

/// Deterministic clock. Neither device reads `DateTime.now()`, which is what
/// lets the tests assert wall-clock order and timer instants instead of
/// counters.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration delta) => now = now.add(delta);
}

/// An instant as the protocol writes it: UTC, seconds precision, `Z`-suffixed.
String isoUtc(DateTime instant) =>
    '${instant.toUtc().toIso8601String().split('.').first}Z';

/// A JSON object, as the protocol's own files and messages spell one.
Map<String, Object?> asObject(Object? value) =>
    (value as Map).cast<String, Object?>();

/// The objects of a JSON array.
List<Map<String, Object?>> objectsOf(Object? value) => [
  for (final element in (value! as List)) asObject(element),
];

/// Reads a protocol file, by a path relative to [syncProtocolRoot].
///
/// Callers name the file they want, not where the protocol is checked in.
Map<String, Object?> readProtocolJson(String pathRelativeToRoot) => asObject(
  jsonDecode(
    File(
      '${Directory.current.path}/$syncProtocolRoot/$pathRelativeToRoot',
    ).readAsStringSync(),
  ),
);

/// The protocol's shared schemas, keyed the way `$ref` addresses them.
SyncProtocolValidator loadProtocolValidator() {
  final root = Directory('${Directory.current.path}/$syncProtocolRoot/schemas');
  return SyncProtocolValidator({
    for (final file in root.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.json'))
        file.path.substring(root.path.length + 1): jsonDecode(
          file.readAsStringSync(),
        ),
  });
}
