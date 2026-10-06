/// The wire's own bounds — the one place a client names a limit the schema
/// also states.
///
/// `loadKg` has a minimum of −200 kg in three places: a set's load and a
/// routine's target in `watch/sync_protocol/schemas/envelope.schema.json`
/// (`$defs.entry.loadKg`, `$defs.metricTargets.loadKg`), and a correction in
/// `watch/sync_protocol/schemas/messages/structure_change.schema.json`
/// (`$defs.correction.loadKg`). A negative load is a band or partner assist;
/// below −200 kg the wire refuses the value rather than clamping it (D-58,
/// D-59).
///
/// Verified by `test/watch_wire_limits_test.dart` (`S-061 ...`), which reads
/// those three minimums from the decoded documents and asserts each equals
/// [WireLimits.minLoadKg]; the watchOS suite asserts its own
/// `WatchMetricStepping.minimumLoadKg` against the same document.
library;

abstract final class WireLimits {
  /// The lowest `loadKg` the wire carries, in canonical kilograms.
  static const double minLoadKg = -200.0;
}
