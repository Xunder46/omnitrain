# Feature: Live Session Mirroring

> **Tier 3 — Live sync, sensors, nutrition.**
> Codebases: native watchOS, Flutter Wear OS, Flutter phone.
> Depends on:
> - [watch-phone-sync-protocol](./watch-phone-sync-protocol-plan.md)
>   (item 5) — gate.
> - [watch-session-engine](./watch-session-engine-plan.md) (item 6).
> - [phone-manage-bridge-live-sessions](./phone-manage-bridge-live-sessions-plan.md)
>   (item 10) — same batch.
> Last reconciled against source: 2026-07-13.

## Overview

During an active workout, watch and phone show the same session in real
time, so the user can raise the wrist to log and pick up the phone to
manage. What makes this tractable rather than brutal is the protocol's
design: because the watch only appends and timers are timestamps, live
sync is an event stream plus a snapshot on reconnect — not a two-way
conflict-resolution problem. Connection loss is a normal state, not an
error; both devices continue independently and converge on reconnect
with nothing lost and nothing duplicated.

## Requirements

- When a session is active on either device and the other is
  reachable, both display the same session state — current exercise,
  logged entries, running timers — updating within a couple of seconds
  of any action.
- Watch actions (logging, advancing exercises) stream to the phone as
  append events. Phone-originated structure changes and entry
  corrections stream to the watch for display.
- If the phone removes the exercise the watch is currently on, the
  watch advances to the next valid exercise, visibly but without
  interrupting any running timer elsewhere in the session.
- Connection loss is a normal state: both devices continue
  independently, and on reconnect a snapshot reconciliation converges
  them with no lost watch observations and no duplicated entries.
- Timers remain correct through disconnects on both devices because
  all timer state is timestamp-based.
- A session started on the phone is joinable from the watch, and vice
  versa.
- Out of scope: the phone's management UI itself (separate item),
  sensor data, cloud relay — this is strictly device-to-device.

## Acceptance Criteria

- [ ] A set logged on the watch appears in the phone's live session
      view within 2 seconds while connected; a phone structure change
      appears on the watch within the same bound.
- [ ] Putting the phone in airplane mode mid-session, logging at
      least five entries on the watch, then reconnecting results in
      exactly those entries on the phone — no losses, no duplicates,
      verified by forcing redelivery of the same events.
- [ ] Removing the watch's current exercise from the phone advances
      the watch to the next exercise.
- [ ] A rest timer started on the watch shows the same end moment on
      the phone within 1 second of skew.
- [ ] Joining an in-progress phone session from the watch produces a
      fully populated watch session.
- [ ] Reconciliation engine on all three codebases is driven by the
      shared protocol fixtures.

## Scenarios

### S-001: Watch log appears on the phone within 2s
- Trigger: User logs a set on the watch while connected.
- Precondition: Live session is active; transport is connected.
- Flow: Watch appends observation → emits observations-up → phone
  receives and applies.
- Expected outcome: Phone's live session view shows the new entry
  within 2 seconds of the watch tap.
- Edge case of: none

### S-002: Phone structure change appears on the watch within 2s
- Trigger: User reorders exercises on the phone.
- Precondition: Live session is active; transport is connected.
- Flow: Phone emits structure-change → watch receives and applies.
- Expected outcome: Watch's exercise order updates within 2 seconds.
- Edge case of: none

### S-003: Reconnect after offline logging — no loss, no duplicates
- Trigger: Phone is in airplane mode; user logs 5 entries on the
  watch; phone comes back.
- Precondition: Transport is reconnecting; watch has buffered
  observations; phone has a snapshot.
- Flow: Watch emits buffered events → phone applies snapshot →
  applies events in order → phone checks for duplicates by event id.
- Expected outcome: Phone has exactly the 5 entries with matching
  identifiers; no duplicates introduced by transport retries.
- Edge case of: S-001

### S-004: Removing the watch's current exercise
- Trigger: Phone user removes the exercise the watch is on.
- Precondition: Watch session is active on exercise X.
- Flow: Phone emits remove event → watch applies → watch advances to
  next valid exercise.
- Expected outcome: Watch shows the next exercise. Any running rest
  timer in a different segment continues uninterrupted.
- Edge case of: S-002

### S-005: Timer end moment matches across devices within 1s skew
- Trigger: Watch starts a rest timer; phone renders the same session.
- Precondition: Devices are time-synced.
- Flow: Watch emits timer start with wall-clock timestamps → phone
  derives end moment.
- Expected outcome: Phone's displayed timer end is within 1 second of
  the watch's end.
- Edge case of: none

### S-006: Join an in-progress phone session from the watch
- Trigger: Watch user joins a session that started on the phone.
- Precondition: Transport is connected; phone session is active.
- Flow: Watch sends a snapshot request → phone sends snapshot →
  watch rehydrates.
- Expected outcome: Watch shows the full session state including
  prior observations and current timer values.
- Edge case of: S-001, S-005

### S-007: Forced redelivery produces no duplicates
- Trigger: Transport retries the same observations-up events.
- Precondition: Reconciliation engine uses event id as the
  idempotency key.
- Flow: Phone receives each event twice.
- Expected outcome: End state is identical to a single delivery.
- Edge case of: S-003

## Iteration 1

### DB Changes

None for the phone repository. The watch on-watch storage from item 6
is unchanged. Transport buffers may add a small on-watch message
queue; that lives in the watch transport layer, not the model layer.

### Backend Changes

- Phone reconciliation engine (Dart) consumes observations-up events
  and applies them idempotently by event id.
- Phone reconciliation engine consumes structure-and-corrections-down
  events and applies them with the authority rules.
- Watch reconciliation engine (each platform) consumes snapshot and
  structure-and-corrections-down, advances position per protocol.
- A snapshot request / response pair is implemented on both sides.
- Transport layer is per platform: `WatchConnectivity` on iOS,
  `MessageClient` / `DataClient` on Android / Wear OS. The transport
  is fire-and-forget with retries; the protocol's idempotency
  guarantees at-least-once delivery semantics.

### Frontend Changes

- Phone: live session view surface (the surface itself is item 10;
  this item wires the reconciliation engine to it). Re-render
  triggered by `ChangeNotifier` notifications on the session state.
- Watch: session state re-render on every snapshot / event applied.
  No new screen — the existing session surfaces (items 7 + 8) react
  to the engine.

### Implementation Steps

1. Implement the reconciliation engine on the phone (Dart).
2. Implement the reconciliation engine on watchOS (Swift).
3. Implement the reconciliation engine on Wear OS (Dart).
4. Implement the snapshot request / response on all three sides.
5. Implement the transport layers.
6. Wire the engines to the existing UI surfaces.
7. Verify against the shared protocol fixtures.

### Platform Notes

- **watchOS (native)**: Swift transport via `WCSession`; Swift
  reconciliation engine consuming the same JSON fixtures shipped in
  item 5.
- **Wear OS (Flutter)**: Dart transport via `flutter_wear_os` or
  equivalent; Dart reconciliation engine.
- **Phone (Flutter)**: Dart transport + Dart reconciliation engine.

## Unit Tests Required

- `test/live_mirroring_test.dart` (phone) — reconciliation driven by
  shared protocol fixtures: snapshot plus divergent event streams
  produce an identical converged state.
- `test/live_mirroring_test.dart` (phone) — duplicate-delivery tests:
  replayed events change nothing.
- `test/live_mirroring_test.dart` (phone) — structure-conflict tests:
  removal of the current exercise, reordering during active logging.
- `watchTests/live_mirroring_test.swift` — same fixture-driven
  reconciliation tests on watchOS.
- `test/live_mirroring_test.dart` (Wear OS) — same fixture-driven
  reconciliation tests.

## Progress

- [x] TDD: tests authored, red run recorded
- [x] Phase 1 — Data Layer (N/A — reconciliation engines)
- [x] Phase 2 — Logic & UI (engines + transports + state wiring)
- [x] Phase 3 — Code Review
- [x] Behaviour parity verified across watchOS + Wear OS + phone

## Feedback

**Review returned: 3 critical, 5 warning, 4 suggestion. Fixed, with two items
deferred below.** No behavioural defect was found in the reconciliation work
itself — the fixture register, the redelivery guarantee, and the append-only
projection all hold. The criticals were documentation: a spec sentence no
implementation satisfied, and behavioural prose where a test pointer belongs.

### Fixed

| # | Finding | Resolution |
|---|---------|------------|
| 1 | `PROTOCOL.md` claimed any disagreeing receiver answers with its own snapshot; only the phone does | Rewritten to name the phone as the only side that answers, and to say why (structure is the phone's to own; a watch re-asserting a ladder would be originating structure). Entries removed from the comparison — they merge, so a missing entry is convergence in progress, not disagreement. Cited to `S-008`. |
| 2 | "a device with no session answers nothing" cited to a test that ran *with* a session | Assertion added on both stacks — `S-009` and `WatchLiveMirroringTests.testASessionlessWatchAnswersNothing` — plus `testJoiningAsksForASnapshotRatherThanOfferingOne` for the joining path. Rule and tests now agree. |
| 3 | Behaviour described in prose in `services_and_utils.md` | Trimmed to structure and vocabulary with test pointers. Scope blocks added (doc standard §4.1). |
| 4 | `pushExercise` / `reportLifecycle` untested | `S-010 the phone drives the session it owns` covers both, including that the phone applies what it originates before telling the watch. |
| 5 | The answer-on-disagreement branch only exercised false | `S-008` drives the true direction. Writing it exposed two real bugs — see below. |
| 6 | `sync({bool reconnect = false})` ignored `reconnect` | Parameter removed. |
| 7 | `WatchMirrorTransport.isWatchReachable` never read | Removed; the transport is fire-and-forget by contract. |
| 8 | Debug harness buttons lacked the `shape:` override | Routed through one `_actionButton` helper using `OmniTheme.buttonUtilityRadius`. |
| 9 | Stale "no watch sync implementation yet" comment | Header rewritten to describe the register's actual ownership. |
| — | Same-language timer duplication (`timer_derivation.dart` vs `watch_timer_math.dart`) | Both delegate to one `TimerInstants`; no arithmetic remains in `watch_timer_math.dart`. |
| — | `watch_start_debug_main.dart` collected handed-over envelopes nothing read | Now displayed, since a desktop run carries nothing and the line is the only view of what a real transport would receive. |

**Two real bugs surfaced by the new tests** — both fixed:

- The phone answered a snapshot with the state it had *just adopted*, so a
  disagreeing peer was told its own shape back. `snapshotEnvelope` now takes the
  state to send, and the phone sends the shape it held before applying.
- `routines_down` was reported `applied` rather than `ignored`, so the
  reconciler was handed reference data. Consumption is now an explicit set.

### Deferred, with rationale

- **Acceptance criterion 1's two-second bound** — the in-process harness has no
  latency to measure, so any assertion would be theatre. Device-verified only.
- **Ladder-operation duplication** between `SyncSessionReconciler` and
  `WatchSessionEngine` — same language, two copies of the insert/remove/reorder
  rules. The append-only storage model is what forces the second copy, so it
  cannot simply be shared; unifying it is a refactor of both engines, not a
  review fix. Worth its own iteration.
- **Scope blocks on the remaining scope-less docs** — the standard requires one
  per document, but this iteration touched two. Converting the rest is
  mechanical and belongs in a docs-only change.

### Verified

- `flutter test` — 2656 passed, 1 skipped, 0 failed (full suite, exit 0).
- `swift test` in `watch/watchos` — 94 tests, 0 failures.
- The fixture-conformance gate and the docs size-ceiling gate both pass against
  the rewritten spec.

### Phase 0 Complete ✓

Red run recorded (2026-09-20). Both suites were written against the scenario
register and failed against the missing implementation:

- `test/live_mirroring_test.dart` — `WatchSessionEngine.applyMessage` /
  `entries`, `WatchSessionRecord.revision`, `LiveSessionMirrorState`, and the
  transport's `send` / `requestSnapshot` did not exist.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchLiveMirroringTests.swift` —
  the same surface, missing on the Swift side; `swift test` failed before any
  test ran.

### Phase 2 Complete ✓

Dart: 8 watch suites green (170 tests), plus the full `flutter test` run — 2656
passed, 1 skipped. Swift: 94 tests, 0 failures.

### Phase 3 Complete ✓

Review returned 3 critical, 5 warning, 4 suggestion. All fixed; two items
deferred with rationale (see `## Feedback`). Verification after the fixes:
`flutter test` 2656 passed / 1 skipped, `swift test` 94 passed / 0 failures.
