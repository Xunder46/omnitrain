// The wire's floor for `loadKg` is one number: the three schema sites state it
// and `WireLimits` names it, because a literal in five places is five chances to
// drift (D-59).
//
// Plan: `docs/plans/2026-10-06-16-watch-negative-load-plan/` (D-58, D-59).
// Scenario mapping:
//   S-61 the floor is one constant, in kg → `S-061 ...`
//
// The minimums are read from the decoded schema documents, never matched as text
// over the raw files, so a reverted `minimum` fails by name and a reworded
// `description` cannot hide it.

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/sync_protocol/wire_limits.dart';

import 'helpers/sync_protocol_harness.dart';

/// The `minimum` [path] addresses in a decoded schema document.
double _minimum(Map<String, Object?> document, List<String> path) {
  Object? node = document;
  for (final key in path) {
    final parent = asObject(node);
    expect(
      parent.containsKey(key),
      isTrue,
      reason: 'S-061 the schema site `${path.join('.')}` exists',
    );
    node = parent[key];
  }
  return (asObject(node)['minimum']! as num).toDouble();
}

void main() {
  group('S-061 the three schema loadKg floors are the one constant', () {
    test('S-061 a set’s load floors at the wire limit', () {
      final minimum = _minimum(
        readProtocolJson('schemas/envelope.schema.json'),
        ['\$defs', 'entry', 'properties', 'loadKg'],
      );
      expect(
        minimum,
        WireLimits.minLoadKg,
        reason:
            'S-061 `\$defs.entry.loadKg` is what the projection and the wrist '
            'read; it and `WireLimits.minLoadKg` are one number (D-59)',
      );
      expect(
        minimum,
        isNot(0),
        reason: 'S-061 a floor of 0 refuses every band-assisted set (D-58)',
      );
    });

    test('S-061 a routine’s load target floors at the wire limit', () {
      final minimum = _minimum(
        readProtocolJson('schemas/envelope.schema.json'),
        ['\$defs', 'metricTargets', 'properties', 'loadKg'],
      );
      expect(
        minimum,
        WireLimits.minLoadKg,
        reason:
            'S-061 an assisted routine reaches the wrist instead of being '
            'rejected at the targets gate (D-65)',
      );
      expect(
        minimum,
        isNot(0),
        reason: 'S-061 a floor of 0 rejects an assisted routine (S-66)',
      );
    });

    test('S-061 a load correction floors at the wire limit', () {
      final minimum = _minimum(
        readProtocolJson('schemas/messages/structure_change.schema.json'),
        ['\$defs', 'correction', 'properties', 'loadKg'],
      );
      expect(
        minimum,
        WireLimits.minLoadKg,
        reason:
            'S-061 the same floor applies to a correction, so fixing a '
            'fat-fingered assist lands instead of being refused (S-65)',
      );
      expect(
        minimum,
        isNot(0),
        reason: 'S-061 a floor of 0 refuses every correction to an assist',
      );
    });
  });
}
