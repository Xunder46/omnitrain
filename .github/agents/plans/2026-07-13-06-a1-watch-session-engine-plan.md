# Feature: Watch Session Engine with Kill-Safe Persistence

> **Tier 2 — Watch foundation. Launch-critical on both watch platforms.**
> Platforms: native watchOS (first) and Flutter Wear OS (to identical
> behaviour in the same working context).
> Depends on: [watch-phone-sync-protocol](./watch-phone-sync-protocol-plan.md)
> (item 5) — gate.
> Last reconciled against source: 2026-07-13.

## Overview

Watch operating systems suspend and terminate apps aggressively, and a
watch can die from battery mid-workout. The product invariant already
established on the phone carries over unchanged: a logged set must
never be lost. This engine gives the watch apps a full session
lifecycle (create, advance, log, finish) that runs with no phone
reachable, persists every observation to on-watch storage the moment
it is logged, and restores an in-progress session exactly on relaunch —
including correct timer values derived from wall-clock timestamps
rather than frozen counters. Because the watch never edits or deletes
existing data, its storage layer is append-only: it has no update or
delete operations for synced entities and only the phone's explicit
receipt confirmation may let the watch prune what it has buffered.

## Requirements

- The watch can run a full training session with no phone reachable:
  create a session, move through exercises, log work, and finish.
- Every logged observation is persisted to on-watch storage the moment
  it is logged.
- If the app is suspended, killed by the OS, or the watch reboots,
  relaunching restores the in-progress session exactly: current
  exercise, all completed entries, and all timer state. Timers stored
  as timestamps remain correct after restore — not frozen at the
  moment of death.
- The watch never edits or deletes existing data. Its store is
  append-only, holding new sessions and observations awaiting sync.
- Completed and in-progress data is retained on-watch until the phone
  explicitly confirms receipt per the sync protocol; only confirmed
  data may be pruned.
- All data structures conform to the sync protocol specification and
  validate against its conformance fixtures.
- Out of scope: live mirroring with the phone (separate item), sensor
  recording (separate item), editing or management capability on the
  watch, sync behaviour not defined in the protocol.

## Acceptance Criteria

- [ ] Force-killing the watch app mid-session and relaunching restores
      the session with all logged entries and correct timer values,
      verified with a timer that was running at kill time.
- [ ] Rebooting the watch mid-session yields the same restoration.
- [ ] Logging an entire session with the phone unreachable, then
      reconnecting, delivers every entry to the phone exactly once.
- [ ] No watch code path can mutate or delete a previously persisted
      record — the storage layer exposes no update or delete operations
      for synced entities.
- [ ] Watch-side data validates against the protocol conformance
      fixtures on both platforms.
- [ ] Behaviour is identical on watchOS and Wear OS given the same
      input — verified by the same fixture suite on both.

## Scenarios

### S-001: Force-kill restores an in-progress session
- Trigger: Watch app is force-killed (debugger stop / OS termination)
  mid-session.
- Precondition: Session is active with at least three logged entries
  and a running rest timer.
- Flow: Force-kill → relaunch → engine reads persisted state →
  restores the session.
- Expected outcome: Current exercise matches the pre-kill state;
  all entries are present; running rest timer's remaining time
  matches the wall-clock difference from its `startedAt` timestamp
  (not a frozen counter).
- Edge case of: none

### S-002: Reboot restores the session identically
- Trigger: Watch is rebooted mid-session.
- Precondition: Same as S-001.
- Flow: Reboot → relaunch → engine reads persisted state.
- Expected outcome: Session restored exactly as in S-001.
- Edge case of: S-001

### S-003: Logging with phone unreachable delivers exactly once
- Trigger: Phone is unreachable; user logs an entire session on the
  watch; phone becomes reachable.
- Precondition: Transport channel (item 9 / batch C) is in place.
  Up to this item, we verify the on-watch buffer and the
  observations-up emission contract.
- Flow: User logs N entries → each is persisted and emitted as an
  observations-up event per the protocol → phone receives each event.
- Expected outcome: Phone records exactly N entries with the same
  identifiers as on the watch. Re-emitting the same event (e.g. on
  transport retry) does not duplicate.
- Edge case of: none

### S-004: Append-only enforcement at the storage API
- Trigger: Developer inspects the storage layer's public API.
- Precondition: Storage layer is implemented.
- Flow: Look for `update`, `delete`, or `remove` methods on synced
  entities.
- Expected outcome: No such methods exist. The only mutation entry
  points are `append` and `pruneConfirmed`. A compile-time or test
  guard fails if any new mutating method is added.
- Edge case of: none

### S-005: Unconfirmed data is never pruned
- Trigger: Local retention runs (e.g. on a low-storage warning).
- Precondition: Storage holds one session with two confirmed entries
  and three unconfirmed entries.
- Flow: Retention routine iterates → checks confirmation flags.
- Expected outcome: Unconfirmed entries remain. Confirmed entries
  may be pruned if a separate retention policy permits.
- Edge case of: S-004

### S-006: Confirmed data may be pruned
- Trigger: Phone confirms receipt of an entry.
- Precondition: Storage holds the entry with `confirmedAt` set.
- Flow: Retention routine runs.
- Expected outcome: Confirmed entry is pruned (or eligible for
  pruning per the retention policy).
- Edge case of: S-005

### S-007: Protocol fixture conformance on both platforms
- Trigger: CI runs the shared fixture suite on the watchOS unit
  target and the Wear OS Flutter target.
- Precondition: Fixture validator from item 5 is wired into both
  suites.
- Flow: Load fixtures → run engine over them → assert outputs.
- Expected outcome: All fixtures pass on both platforms.
- Edge case of: none

## Iteration 1

### DB Changes

- New on-watch persistence schema (platform-native, not the phone
  repository). The schema is identical on watchOS and Wear OS:
  - `local_sessions` (id, startedAt, modality, status)
  - `local_observations` (id, sessionId, kind, payload, createdAt,
    confirmedAt nullable)
  - `local_timers` (id, sessionId, kind, startedAt, pausedAt nullable,
    accumulatedPauseMs)
- Storage layer exposes only `append(...)`, `readAll()`, and
  `pruneConfirmed(...)`. No `update` or `delete` for synced entities.
- Pruning is gated on `confirmedAt != null`; unconfirmed data is
  retained indefinitely (subject to a future retention policy).

### Backend Changes

- New `watch/session/` module (path varies by platform; see Platform
  Notes below).
- `WatchSessionEngine` exposes: `createSession(modality, source)`,
  `advanceExercise()`, `appendObservation(observation)`,
  `startTimer(kind)`, `pauseTimer()`, `resumeTimer()`, `restore()`.
- All persistence calls happen synchronously inside `appendObservation`
  before the engine emits the observations-up event, so a crash after
  persistence but before emission does not lose data — the next
  emission reuses the persisted record.
- Wall-clock derivation for timer remaining time is implemented as a
  pure function (`remainingMs(timer, now)`) and unit-tested with
  synthetic timestamps.

### Frontend Changes

- Session list / detail surfaces consume the engine; the UI work
  itself belongs to item 7 (logging surfaces) and item 8 (start
  paths). This item delivers only the engine + persistence, exercised
  via tests and a minimal debug surface where useful.

### Implementation Steps

1. Implement the storage layer with the append-only contract. Add a
   compile-time / lint guard against mutating methods on synced
   entities.
2. Implement the engine with timestamp-based timer derivation.
3. Wire the protocol fixture validator into both platform test suites.
4. Add persistence round-trip tests simulating process death by
   constructing a fresh engine over the same storage.
5. Add a debug surface (build-flag-gated) that exercises create →
   log → kill → restore so QA can verify on hardware.

### Platform Notes

- **watchOS (native)**: Swift (or whichever native language is chosen)
  implementation; persistence via Core Data, SwiftData, or a flat-file
  store. The engine API mirrors the Dart version 1:1 so fixture parity
  is easy to maintain.
- **Wear OS (Flutter)**: Dart implementation in the same Flutter
  project; persistence via the same on-watch schema encoded for the
  Wear OS target. Storage backend selection (sqflite, Hive, or file)
  is decided in the iteration and reused by the Wear OS persistence
  layer.
- Default assumption: behaviour parity is the contract; if a platform
  detail forces a divergence, that divergence is documented in the
  spec as a normative exception, not a free choice.

## Unit Tests Required

- `test/watch_session_engine_test.dart` — persistence round-trip:
  write observations → simulate process death by constructing a fresh
  engine over the same storage → assert full restoration including
  timestamp-derived timer state.
- `test/watch_session_engine_test.dart` — append-only enforcement:
  storage API exposes no `update` / `delete` / `remove` for synced
  entities; a test guard asserts the absence.
- `test/watch_session_engine_test.dart` — pruning: unconfirmed data is
  never pruned; confirmed data is.
- `test/watch_session_engine_test.dart` — protocol fixture conformance:
  every valid fixture parses through the engine's emission pipeline;
  every invalid fixture is rejected.
- `watchTests/watch_session_engine_test.swift` (or platform
  equivalent) — the same persistence, append-only, pruning, and
  fixture tests on the watchOS native target, sharing the JSON
  fixtures shipped in item 5.

## Progress

- [x] TDD: tests authored, red run recorded
- [x] Phase 1 — Data Layer (storage schema + append-only contract)
- [x] Phase 2 — Logic & UI (engine + persistence + debug surface)
- [ ] Phase 3 — Code Review
- [x] Behaviour parity verified across watchOS + Wear OS

## Feedback

_(empty — fold contents into a new `## Iteration N` block if blocked.)_

### Phase 0 Complete ✓

Red run recorded: all seven scenario groups failed against the absent
`lib/watch/session/` module (missing-implementation failures, not
configuration errors), and the Swift suite failed on the validator's
boolean/number discrimination and the store-guard's anchoring. Both are
green now.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green (Dart 2528 passed / 1 skipped
full suite; Swift 16/16). Ready for Code Reviewer.

### Phase 3 review fixes applied ✓

Five warnings from the code review, all addressed:

1. S-004 guard (Dart) — the store contract is now pinned for every file ending
   `store.dart`, not just the interface, and the mutating-name list covers
   clear/purge/wipe/reset/drop/… with or without a leading `_`.
2. S-004 guard (Swift) — the declaration pattern tolerates access modifiers, so
   `public func` on an implementation is inspected at all; every `*Store.swift`
   is pinned.
3. Debug surface — pruning goes through the engine, so its summary cannot go
   stale, and a "Confirm all" button plays the phone's receipt: without one,
   nothing was ever prunable. Observation ids are minted per log rather than
   counted, because a count is reused after a prune and the phone silently drops
   a repeated `eventId`. The build flag now gates the entry point instead of
   printing a hint.
4. `abandonSession` covered on both platforms.
5. `stopTimer` covered on both platforms.

Verified by injection, not inference: `clearAll` (a forbidden verb) and
`compact` (an unlisted verb) were added to the in-memory Dart store and the
Swift store in turn; the corresponding guard failed on each run and the source
files were restored byte-identical (md5 compared).

Green after the fixes: Dart full suite 2531 passed / 1 skipped; Swift 18/18
(`abandonSession` and `stopTimer` added on both platforms). One Swift guard bug
was found by this exercise — the declaration pattern captured a `Range` and then
shadowed it with a `String` of the same name, which does not compile; the
captures are renamed. Ready for re-review.
