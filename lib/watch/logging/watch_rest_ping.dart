/// Whether the open rest is owed its next ping, and how far it has pinged.
///
/// Plan: `docs/plans/2026-10-08-22b-rest-ping-wear-settings-docs-plan/`
/// (D-261), the rule of
/// `docs/plans/2026-10-08-22-rest-ping-on-watch-plan/` D-243 and D-250.
///
/// A rest counts up, so there is no length to count down from and no
/// end-of-rest alarm: the ping is the one cue a rest gets, and it repeats at
/// each multiple of the interval the phone sent (0 = Off, and Off never pings).
/// The rule lives here, without UI, so the Wear surface can ask it once per
/// second and play the tap it is owed.
///
/// The state is per rest row: [lastPinged] belongs to the `recordId` being
/// walked, and a different row starts from nothing, so the next rest pings at
/// its own first boundary instead of inheriting the previous rest's.
library;

class WatchRestPing {
  /// The boundary the row being walked has already pinged at, in whole
  /// seconds.
  int _lastPinged = 0;

  /// The row [_lastPinged] belongs to.
  String? _pingingRestId;

  /// Whether a ping is owed at this instant of the rest.
  ///
  /// [restId] is the open rest row's `recordId`, null when no rest is running.
  /// [elapsed] is the elapsed whole seconds, null when no rest is running.
  /// [interval] is the phone's interval in seconds; 0 or less is Off.
  bool isOwed({
    required String? restId,
    required int? elapsed,
    required int interval,
  }) {
    // A closed rest is not evaluated at all: there is nothing to ping.
    if (restId == null || elapsed == null) return false;

    if (_pingingRestId != restId) {
      _pingingRestId = restId;
      _lastPinged = 0;
    }

    // Off, or a wrist that has not heard from the phone yet.
    if (interval <= 0) return false;

    // The multiple of the interval the rest has reached. A poll that lands
    // after a gap still catches up, once: the boundary is crossed rather than
    // counted, so the multiples the gap skipped are never pinged.
    final boundary = (elapsed ~/ interval) * interval;
    if (boundary <= 0 || boundary <= _lastPinged) return false;

    _lastPinged = boundary;
    return true;
  }
}
