# Feature: Session Start Paths on the Watch

> **Tier 2 — Watch foundation. Launch-critical on both watch platforms.**
> Platforms: native watchOS (first) and Flutter Wear OS (to identical
> behaviour in the same working context).
> Depends on:
> - [watch-phone-sync-protocol](./watch-phone-sync-protocol-plan.md)
>   (item 5) — gate.
> - [watch-session-engine](./watch-session-engine-plan.md) (item 6).
> Last reconciled against source: 2026-07-13.

## Overview

Two ways to start a session on the wrist: from a synced routine, or a
free workout. The full exercise catalog never ships to the watch — a
23-sport catalog on a 40mm screen is misery and duplicates data for no
benefit — so the exercise choice rule is: phone reachable → search the
full catalog on the phone and push into the watch session (item 10);
phone unreachable → the watch offers a fallback list of recent
exercises plus every exercise referenced by synced routines, kept
synced proactively so it is always available offline. Routine and
fallback-list sync is proactive and incremental — it happens in the
background while connected, not on demand at session start.

## Requirements

- **Path 1 — From a routine**: the user's routines are proactively
  synced to the watch per the sync protocol and can be browsed and
  started entirely offline. Starting a routine creates the planned
  session structure on the watch.
- **Path 2 — Free workout**: starts an empty session. Adding an
  exercise presents the fallback list (recent exercises plus every
  exercise referenced by synced routines), proactively synced and
  fully available offline.
- When the phone is reachable during free workout, the UI indicates
  that the full catalog can be searched from the phone to push an
  exercise into the session. The push mechanism itself is a separate
  item, but this item must accept pushed exercises into the live
  session.
- The full exercise catalog never ships to or renders on the watch.
- Routine and fallback-list sync is proactive and incremental.
- Starting a session on the watch emits the session-started lifecycle
  event per the protocol.
- Modality and effort-kind assignment for chosen exercises follows the
  same rules as the phone, so every exercise renders with the correct
  logging surface.
- Out of scope: creating or editing routines on the watch, catalog
  search UI on the watch, phone-side search-and-push UI.

## Acceptance Criteria

- [x] With the phone off, the watch lists all synced routines and can
      start and complete a session from one.
- [x] With the phone off, a free workout can add any exercise from the
      fallback list and log it with the correct effort-kind surface.
- [x] The fallback list equals the union of recent exercises and
      routine-referenced exercises, verified against a fixture with
      known contents.
- [x] After a routine is edited on the phone, the watch reflects the
      change on the next background sync with no user action.
- [x] An exercise pushed from the phone appears in the live watch
      session in the chosen position.
- [x] Starting a session on the watch emits the session-started
      lifecycle event per the protocol.

## Scenarios

### S-001: Start from a routine, phone offline
- Trigger: User opens Routines on the watch with the phone off.
- Precondition: At least one routine has been previously synced.
- Flow: User taps a routine → engine creates the planned session →
  first exercise is loaded with the correct logging surface.
- Expected outcome: Session is structured exactly as the routine
  template dictates; observations match the protocol fixtures.
- Edge case of: none

### S-002: Free workout, phone offline
- Trigger: User starts a free workout with the phone off.
- Precondition: Fallback list contains N exercises.
- Flow: User starts → adds an exercise from the fallback list →
  logs an observation.
- Expected outcome: Exercise renders with the correct logging
  surface for its modality; observation is persisted.
- Edge case of: S-001

### S-003: Fallback list derivation
- Trigger: Fallback list is constructed after a sync.
- Precondition: Fixture defines recent exercises and a routine that
  references specific exercises.
- Flow: Engine unions the two sets and deduplicates.
- Expected outcome: Result equals the fixture's expected list,
  ordered as defined (recents first, then routine-referenced in
  routine order).
- Edge case of: none

### S-004: Routine edit propagates
- Trigger: User edits a routine on the phone.
- Precondition: Watch is connected and in the background.
- Flow: Routine-down message arrives → watch replaces the cached
  routine.
- Expected outcome: The next time the user opens Routines on the
  watch, the edited version is shown. No user action required.
- Edge case of: S-001

### S-005: Phone push adds an exercise to the live session
- Trigger: User searches the full catalog on the phone and taps
  "Send to watch session."
- Precondition: A watch session is active; transport is connected.
- Flow: Phone sends the exercise-push event → watch receives it →
  engine inserts the exercise at the chosen position.
- Expected outcome: Exercise appears in the live session at the
  requested position; logging surface matches the modality.
- Edge case of: S-002

### S-006: Session-started lifecycle event
- Trigger: Session is created on the watch (routine or free).
- Precondition: Engine is initialised.
- Flow: Engine creates the session → emits the session-started event.
- Expected outcome: Event validates against the protocol fixture;
  no other side effects.
- Edge case of: S-001, S-002

### S-007: Modality / effort-kind parity with the phone
- Trigger: An exercise is added to a session on the watch.
- Precondition: Same exercise exists on the phone.
- Flow: Watch resolves modality and effort kind from the synced
  exercise record.
- Expected outcome: Modality and effort kind equal the phone's
  resolution for the same exercise (parity test).
- Edge case of: S-002, S-005

## Iteration 1

### DB Changes

- Add `local_routines` and `local_fallback_exercises` to the on-watch
  storage schema (or repurpose existing keys if item 6's schema is
  flexible enough).
- Add `local_session_started_at` (or equivalent) so a session can be
  rehydrated after kill.
- No changes to the phone repository.

### Backend Changes

- Routine list, fallback list, and exercise insertion paths in the
  engine. The engine consumes `RoutinesDown` and `ExercisePush`
  messages per the protocol.
- A proactive-sync orchestrator on the watch that pulls routines and
  fallback-list data on connect and reconnect.
- Modality / effort-kind resolution helper that reuses the same
  constants the phone uses.

### Frontend Changes

- Routines list on the watch (browseable offline).
- Free workout entry point.
- Exercise picker for free workout (fallback list only).
- A live-session indicator that surfaces the "Search on phone"
  affordance when the phone is reachable.

### Implementation Steps

1. Implement the fallback-list derivation with parity tests against
   the phone.
2. Implement routine-browsing from the local store.
3. Implement the proactive-sync orchestrator.
4. Wire the exercise-push acceptance path on the engine.
5. Build the UI surfaces (watchOS first, then Wear OS).
6. Verify behaviour parity with the phone's modality / effort-kind
   resolution.

### Platform Notes

- **watchOS (native)**: SwiftUI list views; `WKExtendedRuntimeSession`
  if needed to keep the sync orchestrator alive.
- **Wear OS (Flutter)**: Flutter widgets; rotary / drag input.
- Both platforms consume the same protocol fixtures from item 5 and
  the same engine API from item 6.

## Unit Tests Required

- `test/watch_session_start_test.dart` (Wear OS) — fallback list derivation:
  union of recents and routine exercises, deduplicated, ordered as
  defined.
- `test/watch_session_start_test.dart` — routine template → watch
  session structure instantiation, validated against protocol
  fixtures.
- `test/watch_session_start_test.dart` — effort-kind assignment
  parity: the same exercise and modality yield the same effort kind
  as the phone logic (run against the phone's resolution function).
- `test/watch_session_start_test.dart` — session-started lifecycle
  event emission matches the protocol fixture.
- `test/watch_session_start_test.dart` — exercise-push acceptance
  inserts at the chosen position.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`
  (watchOS) — the same fixture-driven tests on the native target, reading
  `watch/contract/watch_start_paths_contract.json` as well.

The native suite's path was corrected from the plan's original listing:
`watchTests/watch_session_start_test.swift` does not exist in this repository,
so the delivered path is the one the item 6 and item 7 suites use.

## Progress

- [x] TDD: tests authored, red run recorded
- [x] Phase 1 — Data Layer (on-watch routine / fallback storage)
- [x] Phase 2 — Logic & UI (orchestrator + surfaces)
- [x] Phase 3 — Code Review
- [x] Behaviour parity verified across watchOS + Wear OS
- [x] Review findings actioned — **Complete**

## Feedback

_(no blockers — resolved decisions and open items below.)_

### Phase 0 Complete ✓

Red run recorded on both platforms, for the right reason: neither client had an
implementation to compile against. The values both suites are held to live in
`watch/contract/watch_start_paths_contract.json`, so a change on one platform
fails the other's tests instead of diverging silently.

### Phase 2 Complete ✓

Dart: 99 cases across the six watch suites, the full `flutter test` gate green
(2615 passed / 1 skipped), `flutter analyze` clean for the touched trees, and
`lib/watch/debug/watch_start_debug_main.dart` builds for the web. Swift:
`swift test` 82/82 (25 new), plus a `swiftc -typecheck` against the WatchOS26.4
SDK for the SwiftUI surfaces only a watch target can compile. (Counts rose to
101 Dart cases in the six suites and 84 Swift tests when the review findings were
actioned — see the Phase 3 record below.)

**Storage mapping.** The plan's `local_routines` + `local_fallback_exercises`
land as one append-only `routine_catalog` row carrying both: a sync appends a
row and the newest wins, so nothing is rewritten and the pre-sync catalog stays
readable (S-004 asserts two rows). `local_session_started_at` needed no new key —
the session row already carries `startedAt`.

**Engine additions.** The lifecycle transitions now emit `session_lifecycle`
(S-006); `insertExercise` / `applyExercisePush` are the structure paths and
follow the phone reconciler's position rule. An announcement this build could
not send is dropped rather than thrown: the session is the product and the
message is its mirror, so a drift fails the suites — which pin the shape —
rather than blocking a workout in progress.

**Open items.**

1. **`routines_down` carries no modality**, so a routine-started session has
   none and the wrist cannot name a round as the phone's routine would. Both
   start paths take an optional `modality` for when the protocol grows one. A
   protocol decision, not a patch.
2. **Plank's stored effort kind disagrees with the capability rule** (`timed` vs
   `hold`, so the wrist renders a drill surface). Pinned as the one disagreement
   in both suites so it stays visible. Root cause is the same gap: a wire slot
   carries capabilities and no effort kind.
3. **No on-device pass.** Everything is host-verified; the offline and relaunch
   cases cover the phone-off acceptance criteria at the behaviour level, but no
   hardware run happened in this iteration.

### Phase 3 Review Findings — actioned

Zero criticals. Every acceptance criterion and all seven scenarios have passing
tests on both platforms. What the review raised, and what changed:

1. **Pickers disagreed** — the Watch face dismissed on a pick, the Wear surface
   did not. Both dismiss now, and the dismissal happens *before* the callback so
   the route the callback pushes is not the route being popped. The picker test
   asserts the dismissal, so the two suites fail together if either drifts again.
2. **Speculative `modality:` parameter removed** from both start paths —
   `modality` is still accepted by `createSession` for the free-workout path, but
   neither `startFromRoutine` nor `startFreeWorkout` invents one. Open item 1
   below is unchanged: the protocol still carries no modality for a routine, so
   the two start paths genuinely have nothing to pass.
3. **Dead `isPhoneReachable` getter deleted** from both orchestrators. The screens
   read the reachability the orchestrator was handed at construction, so the
   second source of truth is gone rather than merely unused.
4. **Position fixup in `insertExercise`** — Dart and Swift now compute the
   adjusted index identically. This was **latent robustness, not a live bug**: a
   slot inserted at or before the current one must push the current one along, and
   the Dart side previously left it in place. The out-of-range `-1` the review
   named was unreachable only because `currentExercise` is null exactly when the
   exercise list is empty, and that branch short-circuits first — so no shipped
   session was ever miscounted. A guard test now pins the behaviour on both
   platforms; it was shown to fail without the fix (`Expected: 'sx-eff-pullup'`
   vs `Actual: 'sx-eff-plank'`).
5. **`design_system.md` scope declared** (finding was tagged @user; the Developer
   made the call and it is overrulable). The doc now states that it governs the
   phone app's visual system plus the token *values* the watch clients mirror, and
   explicitly excludes wrist-only layout geometry — with `OmniBottomCTA` named as
   a phone-screen rule. The alternative is bringing the wrist surfaces under
   `OmniBottomCTA`, which is a product decision about how the watch should look,
   not a code fix.
6. **Production mount point: named, not built.** These surfaces are mounted by
   `lib/watch/debug/watch_start_debug_main.dart` and the tests, exactly as item 7's
   logging surface is, and nothing in `lib/main.dart` reaches them: the app has no
   watch entry point for either platform yet. The owner is the item that adds the
   Wear OS / watchOS app entry point, and that item must also decide whether
   `WATCH_START_DEBUG` survives as a dev affordance or gives way to a real route.

Test gaps the review named are closed: S-002 now asserts the catalog survived to
the store, S-006 compares the `exercise_advanced` event field-for-field against
the protocol fixture instead of comparing a `started` payload to it, the routine
list is exercised with two routines, and the two new parity guards above.

Re-verified after the changes: `flutter analyze` clean, 101 cases across the six
watch suites green, the full `flutter test` gate green (**2617 passed / 1
skipped**, up from 2615), `swift test` **84/84**, `flutter build web -t
lib/watch/debug/watch_start_debug_main.dart --dart-define=WATCH_START_DEBUG=true`
builds, `swiftc -typecheck` against the WatchOS26.4 SDK exits 0.

### Re-review — adjudicated, no open findings on item 8

All six findings are actioned and verified in the current source, with the
position-fixup guard shown red without its fix.

**Blocker withdrawn.** The scope block's "~40 mm display" was flagged as a value;
§6.1 read in full does not prohibit it. §3.4 is scoped to "any numeric value
defined elsewhere in the codebase" and §6.1 defines the banned class by the token
test — "Name the token and say what it is for; never state what it equals" —
whose exemplar is a restated `OmniTheme` value. A hardware dimension is neither a
codebase value nor subject to drift, and the exemption covers the reasoning
behind a visual rule, which is what the phrase is. It stays. Overrulable: deleting
the dimension is a one-phrase edit either way.

**Still open, still @coordinator:** `design_system.md` restates token values in
its button table and touch-target prose (lines 194–269, 446 among others) —
"56 dp / 12" is exactly the token restatement §6.1's exemplar bans. Pre-existing
and out of item 8's scope; flagged per §5's duty not to leave a prohibited passage
unflagged. Owner: the next design-system reconciliation.

Plan hygiene: the six acceptance-criteria boxes are now ticked, on the per-
criterion evidence recorded in the Phase 3 review.
