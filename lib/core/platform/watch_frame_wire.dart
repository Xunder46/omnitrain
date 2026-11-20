/// Makes a frame safe for the radio (the 2026-11-19 diagnostics log).
///
/// iOS WatchConnectivity refuses a message dictionary that holds a null
/// (`NSNull` is not a property-list value), so a `timer_state` frame whose
/// `timers` says `{rest: null}` — the protocol's way to clear a timer — never
/// reached the watch: 451 of 644 such sends failed on the phone's own log.
///
/// The watch already stores a timer that carries `stoppedAt` as a stopped row,
/// and the newest row of a kind decides what runs, so a clear travels as that
/// stopped timer instead: `{kind, state: stopped, startedAt, stoppedAt}`, both
/// stamps the frame's own `sentAt`. Nothing else in the frame is touched.
library;

/// [frame] with every null in `payload.timers` replaced by a stopped timer of
/// that kind, stamped with the frame's `sentAt`.
///
/// A frame with no `timers` map, no null in it, or no readable `sentAt` is
/// returned as it came: a frame this cannot rewrite is the sender's to answer
/// for, never invented here.
Map<String, Object?> wireSafeFrame(Map<String, Object?> frame) {
  final sentAt = frame['sentAt'];
  final payload = frame['payload'];
  if (sentAt is! String || sentAt.isEmpty || payload is! Map) return frame;
  final timers = payload['timers'];
  if (timers is! Map || !timers.values.any((value) => value == null)) {
    return frame;
  }
  return {
    ...frame,
    'payload': {
      ...payload.cast<String, Object?>(),
      'timers': {
        for (final entry in timers.entries)
          entry.key as String: entry.value ?? _stopped(entry.key as String, sentAt),
      },
    },
  };
}

Map<String, Object?> _stopped(String kind, String at) => {
  'kind': kind,
  'state': 'stopped',
  'startedAt': at,
  'stoppedAt': at,
};
