# The Watch Surface — the Transport and the Link

**Scope.** The platform transport the watch↔phone mirror rides on (`lib/core/platform/`) and the phone's view of the link to the watch:
the plugin, the channel, the queue and the status. Split from [The Watch Surface](watch_surface.md) on 2026-11-09 (that page crossed the
80% size band); the mirror, the router, the request handler and `createWatchSync` stay there.

> Part of [State Management & Services](../state_management.md). See that index for the full class list and dependency graph.

---

### The watch transport

**Files**: `lib/core/platform/watch_transport.dart`,
`lib/core/platform/watch_connectivity_channel.dart`,
`lib/core/platform/no_watch_transport.dart`,
`lib/core/utils/platform_watch_transport_factory.dart`

One object is both the watch's `WatchSyncTransport` and the phone's
`WatchMirrorTransport`, because they are one radio: `WatchTransport` extends both
and adds `onIncoming`, the single handler every arriving frame is handed to.

**The package boundary is `WatchMessageChannel` and nothing else.**
`omnitrain_watch_link` is imported in exactly one file
(`watch_connectivity_channel.dart`); `WatchConnectivityTransport` is written
against the `WatchMessageChannel` interface, which is what lets a hand-rolled
`MethodChannel` + `WCSession` layer, or a Wear OS data-layer one, replace it
without touching a caller.

**Nothing is queued in the app layer.** A queue here would be a second source of
truth about what has been delivered (PROTOCOL.md, "Idempotency and
reconciliation").

**A request is not a message.** PROTOCOL.md says so normatively, and
`WatchTransportRequest` is where that lives: a frame with no `type` is a request
(`routines` or `snapshot`), and a frame with one is a protocol message.
`WatchConnectivityTransport` implements the request calls over that one
vocabulary, so adding a request does not add a wire type.

**Platform choice happens once**, in `createPlatformWatchTransport`: iOS gets
`WatchConnectivityTransport`, and web, desktop, and Android get `null` — Android
until the Wear OS client is built. It reads `defaultTargetPlatform` rather than
`dart:io`'s `Platform`, because this file is compiled for web too, and a failure
to construct answers null rather than refusing to start the app.

Verified by `test/watch_transport_test.dart` (S-001, S-002, S-003, S-006, S-009;
group `S-206 a send answers whether the frame was handed over`,
`S-206 a reachable counterpart means delivered, and the radio carried the frame`,
`S-206 an unreachable counterpart is undelivered, unsent and unreported`,
`S-206 a send reads reachability again rather than trusting the last answer`,
`S-206 a radio that refuses the frame is undelivered and reported once`,
`S-218 a transport that cannot carry a frame is undelivered and quiet`) over an
in-memory two-ended channel.

**Frames are handled one at a time, and a stale snapshot is ignored.**
`WatchConnectivityTransport._dispatch` chains each incoming frame after the
previous frame's handling and counts the frame as heard on arrival; a handler
that does not finish within its handler timeout is reported and given up on, so
later frames are not stuck behind it. On the mirror,
`LiveSessionMirrorState.isStaleSnapshot` answers a `session_snapshot` whose
`sentAt` is earlier than the newest snapshot stamp the mirror has applied — one
stamp across all workouts — with `MirrorOutcome.ignored`: nothing applied,
nothing notified; an equal or later stamp applies, and an unreadable `sentAt` is
not stale, while the inbox still stages the entries of a stale snapshot.
Verified by `test/watch_message_order_test.dart` (`S-9301`..`S-9307`).

The wrist's half of this area — the Swift bridge over the same radio, the wrist's start surface and the wrist's logging surface (the Crown and the per-exercise dialled numbers included) — has its own page: [The Watch Surface — the Wrist's Half](watch_surface_wrist.md). The wrist's own record of what happened around a gap — `WatchDiagnosticsLog` and the Diagnostics screen that reads it — has its own page: [The Watch Diagnostics Log](watch_diagnostics.md).

### The phone's link: the plugin, the channel, the queue and the status

**Files**: `packages/omnitrain_watch_link/` (a local path dependency, iOS
only), `lib/core/platform/watch_connectivity_channel.dart`,
`lib/core/platform/watch_link_info.dart`,
`lib/state/watch/watch_link_state.dart`

The radio under `WatchConnectivityTransport` is the local plugin
`packages/omnitrain_watch_link`, which replaced the `watch_connectivity`
dependency. Its Dart API is `WatchLink`: `status()`; `sendMessage`, which
completes on the watch's reply and fails with a `WatchLinkException` —
`not_supported`, `not_activated`, `not_reachable`, `send_failed`, or `timeout`
when no reply arrives within the call's `timeout`; `transferUserInfo`, which
answers `queued` or `already_queued` by the frame's `messageId`; and one
broadcast `events` stream of the sealed `WatchLinkEvent` kinds
(`WatchLinkMessage`, `WatchLinkUserInfo`, `WatchLinkReachability`,
`WatchLinkStateChanged`); `outstandingTransfers()`, which lists the transfers
the OS still holds as `WatchLinkTransfer` values (`messageId`, `type`,
`sessionId?`, `changeId?`); and `cancelTransfers(messageIds)`, which cancels
them and answers how many. The native half (`OmniTrainWatchLinkPlugin.swift`)
is one `WCSession` delegate that buffers events until Dart listens (bounded by
its `bufferCap`, oldest dropped past it), answers every incoming message so
the sender's send completes, and emits state and reachability; the buffer and
the reply are verified on the paired simulators (plan 47d), not by a unit
test; the two queue methods' native part is compiled by the iOS build but
verified against real queued transfers only by the owner device checks of
plan 67a. Verified by `test/watch_link_package_test.dart` (groups `S-6801` to
`S-6805`, `S-9701`, `S-9702`).

The app's seam is `WatchConnectivityChannel(link:)`, the implementer of the
seven-member `WatchMessageChannel` (`isPaired`, `isReachable`, `messages` —
message and userInfo frames merged into one stream — `send`, `queue`,
`reachability`, `info`); `WatchLinkInfo` is the core value type, so no plugin
type escapes the channel. The channel also implements the core
`WatchQueueControl`, so `WatchMessageChannel` keeps its seven members and no
plugin type escapes. Verified by
`test/watch_connectivity_channel_test.dart` (group `S-6816 the channel over
the plugin`, `S-9703`).

**A frame the OS may carry can be queued, not only delivered.** `WatchDelivery`
gained `queued` — handed to the OS queue (`transferUserInfo`); it arrives when
the devices meet — and `WatchConnectivityTransport.isDurable` is true for
`receipt` and the four workout messages `session_snapshot`, `session_lifecycle`,
`structure_change` and `exercise_push`: a durable frame the radio cannot reach
or refuses is queued instead of reported, while every other frame stays
live-only and is re-offered at its next trigger. Before it queues — and after
it delivers one live — the transport cancels the outstanding transfers the new
frame replaces: same type and `sessionId` for a snapshot or a lifecycle, same
`sessionId` and payload `changeId` for a `structure_change`; a `receipt` and an
`exercise_push` are never withdrawn, and a frame's own `messageId` is never
cancelled. The cancelling goes through `WatchQueueControl`
(`lib/core/platform/watch_queue_control.dart`: `outstandingTransfers()`,
`cancelTransfers(ids)`), which `WatchConnectivityChannel` implements; a channel
without the capability withdraws nothing, and the queue work (withdraw, then
queue) runs one call at a time. `timer_state`, requests and the static `*_down`
frames are never queued. A queued copy is a carrier, not a delivery: callers
advance bookkeeping only on `delivered`. Verified by
`test/watch_transport_test.dart` (S-9710..S-9719, S-9724),
`test/watch_session_queue_test.dart` (S-9720..S-9723),
`test/watch_link_package_test.dart` (S-9701, S-9702) and
`test/watch_connectivity_channel_test.dart` (S-9703).

**The listener order is load-bearing.** `onIncoming` attaches the message and
the reachability listener together, because listening is what makes the
native side flush its buffer: the message listener must attach first or in
the same turn. Verified by `test/watch_transport_test.dart` (group `S-6817
the transport attaches its listeners when it starts receiving`).

`WatchLinkState` (`lib/state/watch/watch_link_state.dart`) is the status
Settings shows: a `ChangeNotifier` over `WatchLinkSource` — implemented by
the transport — whose `phase` is `connected`, `notReachable`, `notPaired` or
`appNotInstalled`, whose `lastSyncedLabel` says when the phone last heard a
frame, and which persists that instant under the repository key
`watch_last_heard_ms` at most once per `persistEvery`. Verified by
`test/watch_link_state_test.dart` (groups `S-6901` to `S-6905`).

### Convergence testing

The pair is tested by replaying seeded action sequences against it, not only by
hand-written scenarios. `ConvergenceRun.runSeed(n)`
(`test/helpers/watch_pair_harness.dart`) draws 8 to 40 actions from a seeded
random source over the shipping action space, plays them through the real
transport on both sides, runs the heal, and reports four checks: the same
status per session, an ended session never returning to `active`, the same
entry set per session, and no rest timer on an ended session. `replay(n)` in
`test/watch_convergence_random_test.dart` re-runs one seed on its own; the same
seed reads the same twice — `S-14502 a seeded run reads the same twice`.

Two defines drive it: `--dart-define=CONVERGENCE_SEEDS=2000` sets how many
seeds the sweep runs (200 by default) and `--dart-define=CONVERGENCE_VERBOSE=true`
prints one `seed=N kinds=…` line per seed, so two runs can be diffed line by
line. The sweep — `S-14509 the random seeds: the harness is healthy and every
seed is accounted for` — prints how many seeds converge, the seeds per check,
the seeds whose heal never settles, and asserts only that no seed makes the
pair throw or time out. The contract is the second test, `S-14509 every random
seed converges, or diverges inside a class the plan names`: each seed runs on
`kShippingActions` and then on the full space, every divergence it prints must
belong to a class the test names with the fix that owns it, and shipping-action
divergences are held under a measured ratchet (see
`docs/plans/2026-11-11-146-ended-is-final-plan/`).

The entry check reads the wrist's whole store, not only the session it is on:
an entry merged for a session the wrist has already ended (the late-entry merge)
is held but is not in that session's projection, so a sweep that sampled only the
projection reported it as never held.

A failing trace is made readable before it is written down: `Shrinker.shrink`
removes actions one at a time while the named check still fails, and
`Shrinker.describeTrace` renders what is left as numbered sentences —
"S-14510 the shrinker reduces S-14503 padded with 20 unrelated actions" holds
it to six actions or fewer. Every distinct finding then becomes one replay test
named `F-n` with the shrunk trace in a comment above it, skipped with a
`skip: 'plan 146 …'` reason while the invariant still fails (`F-7` in
`test/watch_convergence_random_test.dart`; `F-1` is
`S-14503 a finished workout is never reopened by a queued started` in
`test/watch_convergence_harness_test.dart`). A finding that passes with the
`skip` removed is not a finding and is not kept.

`F-2` and `F-4` both say the same thing in different places: an ended session
is final, yet a newer active frame or a wrist `finishSession` revives it, so the
follow-up unit 146 — "ended is final" — is the fix for both. `F-6` — a set the
phone logs while apart never reaching a wrist that moved on — turned out to be
this harness reading fault, not the pair, and is unskipped and green.

The harness has one synthetic action, `phoneReassertsLive`, which no build can
send; it is excluded from `kShippingActions`, so a finding that needs it is
reported as such (`F-2`'s shrunk trace does; the shipping flavour of the same
hole is seed 50 in the plan's evidence file). A phone app killed and relaunched
is not modelled either — only `WristKilled` exists — so nothing here covers the
phone losing a session to its own process death.
