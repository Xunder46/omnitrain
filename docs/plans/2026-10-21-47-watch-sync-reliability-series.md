# Series 47: watch data survives an out-of-range workout, and the phone says how the watch is doing

> Status: 47a, 47b, 47c BUILT 2026-10-21; 47d (device) pending the owner. Seeded 2026-10-21 (from the watch UX audit, `.work/crew/2026-10-20-45-watch-ux/FINDINGS.md` section 3, and scout sheets `.work/crew/2026-10-21-47/scout-{wrist,phone,status}.md`). Nothing built.
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md

## Owner decisions (2026-10-21, in chat)

O-1 Replace the phone's watch plugin so that watch data survives an out-of-range workout.
O-2 The phone shows a small watch status: connected, not reachable, last synced.
O-3 The watch keeps its start-screen status only (no new status on the logging or rest screens).
Wording and placement were left to the lead (decisions below).

## What the user sees after the series

- A workout logged on the watch while the phone is out of reach (gym, run) reaches the phone on its own when the two meet again, even if neither app is open: the phone imports it in the background, and the watch stops owing it once the phone says so.
- Settings has a new APPLE WATCH section (iPhone only, hidden when there is no watch support) with one row: "Apple Watch", a coloured status on the right (Connected / Not reachable / Not paired / Watch app not installed) and a line under it: "Last synced 5 min ago" or "Never synced". "Last synced" is the moment the phone last heard a frame from the watch.

## Why it does not work today (audit facts)

- Every frame travels by `sendMessage` only; unreachable means dropped; the wrist re-sends from storage only when it is awake near the phone.
- The phone plugin (`watch_connectivity` 0.2.8) cannot receive queued transfers, treats a failed send as delivered, has no reachability events, and forwards arrivals only to an attached Dart listener (earlier arrivals vanish).
- On a cold background launch the phone attaches its listener at the end of a long startup (`lib/main.dart`, `createWatchSync`), so anything arriving first is dropped (scout sheet phone Q4).

## Decisions

- D-1 One local Flutter plugin, `packages/omnitrain_watch_link/` (iOS only), replaces `watch_connectivity`: a Swift `WCSessionDelegate` that buffers every event until the first Dart listener attaches (bounded, oldest dropped past 500), answers every incoming `sendMessage` with an empty reply (so the sender learns it arrived), exposes `status`, `sendMessage` (completes on the peer's reply, fails on error or after 10 s), `transferUserInfo` (deduplicated by the frame's `messageId` against `outstandingUserInfoTransfers`) and one event stream (message, userInfo, reachability, state). Plan 47a.
- D-2 Durable frames travel by `transferUserInfo` when `sendMessage` is not possible: wrist `observations_up` and `session_lifecycle`; phone `receipt`. Everything else (timers, snapshots, requests, reference data) stays live-only and is re-offered at the next trigger, exactly as today: a queued snapshot or timer would arrive stale. The protocol already dedupes by `messageId`, `entryId` and `confirmedAt`, so a frame that arrives twice (once queued, once re-sent) is safe. Plans 47a (phone half) and 47b (wrist half).
- D-3 `WatchDelivery` gains `queued` ("handed to the OS queue; it will arrive when the devices meet"). A caller that treats only `undelivered` as "still owed" needs no change; the one phone frame that can be queued is `receipt`, whose caller ignores the result.
- D-4 Status: a `WatchLinkState` ChangeNotifier (`lib/state/watch/watch_link_state.dart`) over a small source interface (status, reachability changes, frames heard) and the repository's string preferences (key `watch_last_heard_ms`, written at most once every 30 s). The Settings row is read-only (`_SettingsRow` with `onTap: null`, the first user of that shape). Plan 47c.
- D-5 Verification: the Swift and Dart logic is covered by unit tests with fakes; the native plugin and the queued path are verified by the lead on the paired simulators (iPhone 17 Pro + Apple Watch Series 11 42mm, pair `A3B21BE3-...`), reading `NSLog` lines tagged `OmniTrainWatchLink`; a physical-watch check stays an owner check.
- D-6 Out of scope: Wear OS, background delivery of live state, a retry UI, changing the protocol (`watch/sync_protocol/PROTOCOL.md` needs no change: the envelope is the same dictionary), the wrist's logging/rest screens (O-3).

## Split (scope budget: one concern per PR)

- 47b wrist half (Swift package + watch app target): durable frames queue when the phone is unreachable; the wrist receives userInfo. Independent, buildable first.
- 47a phone half: the plugin package, the Dart channel/transport, the factory and pubspec swap.
- 47c status: `WatchLinkState`, DI hops, Settings row, docs. Needs 47a's channel members.
- 47d (lead, no code): end-to-end check on the paired simulators and the owner device checks.
