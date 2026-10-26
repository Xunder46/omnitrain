# Review: 47a watch-link plugin · P1-P4 · base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 3 · tests: governor-run, green (the three review files plus
`test/watch_link_state_test.dart`, 72 tests; not re-run per brief)
Diff vs Predicted Files: conforms — all 18 changed files fall in the P1-P4 write scopes
(`packages/omnitrain_watch_link/**`, `lib/core/platform/**`, `pubspec.yaml`, `pubspec.lock`,
`ios/Podfile.lock`, the three test files, `docs/state_management/watch_surface.md`); nothing outside.
## Findings
1. [Minor] packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift:91 — the
   `errorHandler` closure captures `[weak self]` and calls `result(self?.failure(...))`: if `self`
   were ever nil, `self?.failure(...)` evaluates to nil and `result(nil)` reports the failed send as
   a success, so Dart's `sendMessage` completes normally and the transport answers `delivered` for a
   frame the radio refused. Unreachable while the engine retains the registered plugin instance, but
   the guard invites the wrong-success path. Fix: capture strongly (`{ [self] error in ... }`) or
   `guard let self`. Guard: none required (path unreachable in practice).
2. [Minor] packages/omnitrain_watch_link/ios/Classes/OmniTrainWatchLinkPlugin.swift:12,20 —
   `static var shared` is assigned in `register` and never read anywhere (grepped the package: the
   only two occurrences). Dead state a maintainer has to reason about. Fix: delete it, or give it a
   reader (a debug/test accessor) if 47d needs one. Guard: none.
3. [Minor] lib/core/platform/watch_transport.dart:207 — `_reachabilityChanged` sets the flag, then
   `await _channel.info`, then `_linkChanges.add(...)`. A `close()` during that await closes the
   controller, and the resumed `add` throws `StateError: Cannot add event after closing`, which the
   surrounding catch reports as a transport failure — a spurious error report during teardown that a
   maintainer would see in the failure channel. Fix: `if (!_linkChanges.isClosed) { ... }` around the
   add. Guard: a test that closes the transport while a reachability event is in flight and asserts
   nothing is reported.
## Assumption Log rulings
The plan carries no Assumption Log section and the evidence file records none; nothing to rule on.
(The builders' decisions I could check all match the plan text — see Scenario coverage.)
## Scenario coverage
S-6801 -> test/watch_link_package_test.dart · group `S-6801 status` (decodes the map; missing keys
      read false) | covered
S-6802 -> test/watch_link_package_test.dart · group `S-6802 sendMessage` (null result completes;
      `not_reachable` becomes `WatchLinkException`; timeout under `fakeAsync`, never the real clock)
      | covered
S-6803 -> test/watch_link_package_test.dart · group `S-6803 transferUserInfo` (`queued`,
      `already_queued`) | covered
S-6804 -> test/watch_link_package_test.dart · group `S-6804 events` (four kinds in order, unknown
      kind skipped) | covered
S-6805 -> test/watch_link_package_test.dart · group `S-6805 one broadcast stream` (two listeners,
      one native listen) | covered
S-6810 -> test/watch_transport_test.dart · `S-6810 an unreachable receipt is queued, not sent`
      (frame in `queued`, not `sent`; no report) | covered
S-6811 -> same group · one test per type (`session_snapshot`, `timer_state`, request) | covered
S-6812 -> same group · reachable receipt whose send throws is queued and reported once; reachable
      `session_snapshot` whose send throws is undelivered | covered
S-6813 -> same group · reachability events move the flag both ways and `linkChanges` emits the info
      | covered
S-6814 -> same group · a failed send lowers `isPhoneReachable` | covered
S-6815 -> same group · `heard` once per frame the handler took, injected clock, never for a dropped
      frame (asserts the clock is not even read for the drop) | covered
S-6816 -> test/watch_connectivity_channel_test.dart · group `S-6816 the channel over the plugin`
      (messages merges both kinds in order; reachability yields the bool; queue hands
      `transferUserInfo` the frame; info maps onto `WatchLinkInfo`) | covered
S-6817 -> test/watch_transport_test.dart · group `S-6817 the transport attaches its listeners when
      it starts receiving` (no listener before `onIncoming`; both attached in the same turn,
      messages first) | covered
Mutation list: `isDurable` true for every type -> S-6811 fails; queue never called -> S-6810/S-6812
fail; reachability stream ignored -> S-6813 fails; `heard` before the drop check -> S-6815 fails
(clock-read assertion); the 500 cap and the flush order are native, assigned by the plan to the
paired-simulator/owner checks, not unit tests — unproven here, as the plan intends.
## Brief questions, answered
1. `FlutterResult` exactly once on every path: yes. `sendMessage`: four guard returns
   (`not_supported`, `not_activated`, `not_reachable`, non-dict -> `send_failed`), then exactly one
   of replyHandler (`result(nil)`) / errorHandler (WCSession's contract is mutually exclusive), both
   hopped to the main queue. `transferUserInfo`: three guard returns, then `already_queued` or
   `queued`, synchronously on the platform thread. No path calls `result` twice or off the main
   thread — except the latent weak-self path in finding 1.
2. Event buffer: no loss or duplication. `emit` always hops to the main queue, so `pending` and
   `sink` are touched only there; `onListen` runs synchronously on the main thread, so an emit block
   enqueued before it runs before it (buffered, then flushed) and one enqueued after sees the set
   `sink` — never both, never neither. Cap arithmetic is right (count 501 -> removeFirst(1) -> 500).
   `onCancel` keeps `pending`, so events arriving between cancel and the next listen are flushed in
   order on re-listen.
3. `WatchLink.events`: when the last listener cancels, `asBroadcastStream` cancels the source
   subscription (native `onCancel`), and a new listener re-subscribes it (native `onListen` again,
   flush again) — the same broadcast stream object is reused (`_stream ??=`). The transport's two
   listeners attach in the same synchronous turn, and the native flush travels back as platform
   messages handled after both are attached, so neither listener misses the flush; the message
   listener being first is still the load-bearing order the plan pins.
4. Transport: no path queues and reports delivered (the three outcomes are mutually exclusive);
   `_queue` catches its own errors; `_heard.add` runs synchronously at delivery, before any await, so
   `close()` cannot interleave ahead of it. The one real race is finding 3.
5. Docs: every name in the new `watch_surface.md` text was searched and exists —
   `packages/omnitrain_watch_link/`, `watch_connectivity_channel.dart`, `watch_link_info.dart`,
   `lib/state/watch/watch_link_state.dart` (`WatchLinkState`, `WatchLinkPhase` with the four values,
   `lastSyncedLabel`, `persistEvery`, key `watch_last_heard_ms`), `OmniTrainWatchLinkPlugin.swift`,
   `bufferCap`, `WatchConnectivityChannel(link:)`, the seven `WatchMessageChannel` members,
   `isDurable`, `WatchLinkSource`, and the four test files with the exact group names quoted
   (`S-6801`..`S-6805`, `S-6816 the channel over the plugin`,
   `S-6810-6815 the transport over a link that queues`,
   `S-6817 the transport attaches its listeners when it starts receiving`, `S-6901`..`S-6905`).
## Project checks
- `lib/state`, `lib/features`, `lib/widgets`, `lib/core` import the package in exactly one file
  (`watch_connectivity_channel.dart`, grepped); no `hive_workout_repository` import under `lib/state`.
- `WatchDelivery` readers in `lib/` (grepped, 8 files): every comparison is `== delivered`,
  `!= delivered` or `== undelivered` on frames that never queue (state frames, reference batches);
  the one receipt sender (`watch_nutrition_log_bridge.dart:188`) ignores the delivery result, so
  `queued` changes no caller's meaning.
- No UI files touched; no allowlist entry added, no ratchet raised, no raw piece introduced.
- `platform_watch_transport_factory.dart` and `no_watch_transport.dart` need no change (the new
  constructor parameters are optional; `NoWatchTransport` implements `WatchTransport`, not the
  channel interface).

## Disposition (governor, 2026-10-21)

- Minor 1 (weak self in the native error handler): fixed (the handler no longer captures self).
- Minor 2 (`static var shared` unread): kept on purpose: it is what keeps the plugin instance, the WCSession delegate, alive (WCSession holds it weakly); a doc comment says so.
- Minor 3 (`add` after `close`): fixed with an isClosed guard; S-6818 added; mutation red.
