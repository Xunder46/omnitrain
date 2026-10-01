/// The protocol's wire shape for a timestamp, in one place.
///
/// `PROTOCOL.md` pins `sentAt`, `generatedAt` and every other instant on the
/// wire to `YYYY-MM-DDTHH:MM:SS(.sss)Z` — UTC, always with the zone suffix. The
/// shape belongs to the protocol rather than to either client, so a sender and
/// a receiver cannot drift.
library;

/// A UTC timestamp in the protocol's wire shape:
/// `YYYY-MM-DDTHH:MM:SS(.sss)Z`.
String utcIso(DateTime instant) {
  final iso = instant.toUtc().toIso8601String();
  return iso.endsWith('Z') ? iso : '${iso}Z';
}

DateTime parseUtcIso(Object? value) => DateTime.parse(value! as String).toUtc();

DateTime? parseOptionalUtcIso(Object? value) =>
    value == null ? null : parseUtcIso(value);
