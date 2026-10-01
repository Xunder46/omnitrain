# Feature: Phone Manage-Bridge for Live Sessions

> **Tier 3 — Live sync, sensors, nutrition.**
> Platform: Flutter phone (iOS and Android).
> Depends on:
> - [watch-phone-sync-protocol](./watch-phone-sync-protocol-plan.md)
>   (item 5) — gate.
> - [watch-session-engine](./watch-session-engine-plan.md) (item 6)
>   — phone consumes the engine's reconciliation surface.
> - [live-session-mirroring](./live-session-mirroring-plan.md)
>   (item 9) — same batch.
> Last reconciled against source: 2026-07-13.

## Overview

The half of live sync that's easiest to forget: the phone must render
and manage a session that originated on the watch. This is where
"mobile does the heavy lifting" becomes concrete — full structure
management during a live workout, plus full-catalog exercise search
with a direct "send to watch session" action. During a live mirrored
session the phone may also correct or delete logged entries — fixing a
fat-fingered set is "managing something" — and the watch reflects the
corrected state. The watch itself still never originates an edit.

## Requirements

- When the watch has an active session, the phone surfaces it
  prominently and opens into a live session view showing everything
  logged so far, updating in real time.
- From that view the user has full structure management: add, remove,
  reorder, and swap exercises. Changes propagate to the watch live,
  per the protocol authority rules.
- Full-catalog exercise search on the phone gains a "send to watch
  session" action whenever a live watch session exists: the chosen
  exercise is inserted into the live session and appears on the watch.
- The phone may correct or delete logged entries during the live
  session; the corrected state propagates to the watch's display. The
  watch never originates edits.
- The session can be completed from either device; completing on the
  phone ends the watch's active session gracefully, producing one
  merged session record.
- Out of scope: new session-editing capabilities beyond what the phone
  already has (this item points existing management at a live
  session), watch UI, sensor data.

## Acceptance Criteria

- [x] With a watch session active, the phone shows an entry point to
      the live session within one screen of app launch.
- [x] Adding an exercise from full-catalog search on the phone lands it
      in the watch session in the chosen position.
- [x] Reordering exercises on the phone reorders them on the watch
      while a running rest timer continues undisturbed.
- [x] Correcting a logged entry's value on the phone updates the
      watch's displayed history on the next event or snapshot.
- [x] Completing the session from the phone closes it on the watch and
      produces exactly one merged session record containing all
      observations from both devices, correctly ordered.
- [x] Each structure-change operation emits the correct protocol
      event, validated against fixtures.

## Scenarios

### S-001: Phone entry point surfaces the live watch session
- Trigger: User opens the phone app while a watch session is active.
- Precondition: Transport is connected; watch has emitted
  session-started.
- Flow: Phone app foregrounds → home / status surface shows the
  live session entry → user taps it → live session view opens.
- Expected outcome: Live session view renders the current state
  within one screen of launch.
- Edge case of: none

### S-002: Add an exercise from full-catalog search
- Trigger: User searches the catalog on the phone and taps "Send to
  watch session."
- Precondition: Live session is active on the watch.
- Flow: Phone sends exercise-push → watch inserts at the chosen
  position.
- Expected outcome: Exercise appears in the watch session at the
  requested position.
- Edge case of: none

### S-003: Reorder while a rest timer runs
- Trigger: User reorders exercises on the phone.
- Precondition: A rest timer is running on the watch (in a different
  segment).
- Flow: Phone emits reorder → watch applies → timer continues.
- Expected outcome: Watch shows the new order; running rest timer is
  undisturbed.
- Edge case of: S-002

### S-004: Correct a logged entry
- Trigger: User edits a fat-fingered set's load on the phone.
- Precondition: Watch has a set entry that the user wants to correct.
- Flow: Phone emits entry-correction → watch applies.
- Expected outcome: Watch's displayed history shows the corrected
  value on the next event / snapshot.
- Edge case of: none

### S-005: Complete from the phone
- Trigger: User taps "Finish" on the phone.
- Precondition: Live session is active on the watch.
- Flow: Phone emits session-completed → watch applies and exits the
  session gracefully → phone merges observations.
- Expected outcome: Exactly one merged session record contains all
  observations from both devices, correctly ordered.
- Edge case of: none

### S-006: Merge correctness — interleaved phone- and watch-originated
- Trigger: Both devices log during the same session.
- Precondition: Session is active on both; transport is connected.
- Flow: Phone logs entry A, watch logs entry B, phone logs entry C,
  watch logs entry D, both devices apply each other's events.
- Expected outcome: Final session record contains A, B, C, D in
  chronological order by wall-clock timestamp.
- Edge case of: S-005

### S-007: Entry correction propagates as the correct protocol event
- Trigger: User corrects an entry on the phone.
- Precondition: Reconciliation engine handles entry-correction events.
- Flow: Phone emits the correction event → validator checks shape
  against the protocol fixture.
- Expected outcome: Event validates against the fixture.
- Edge case of: S-004

## Iteration 1

### DB Changes

None for the schema. The session model already supports observations
and corrections via the existing reconciliation surface; this item
wires UI and event emission onto that surface.

### Backend Changes

- Reuse the existing `WorkoutSession` state owner for live sessions
  on the phone; add methods for live session structure operations
  (`addExercise`, `removeExercise`, `reorderExercises`, `swapExercise`,
  `correctEntry`) that emit protocol events as a side effect.
- The live-session state owner listens to observations-up from the
  watch and applies them via the same reconciliation engine from
  item 9.
- Merge logic on session completion: produces a single session record
  whose observations are sorted by wall-clock timestamp regardless of
  originating device.

### Frontend Changes

- Home / status surface gains a live-session entry point when the
  watch has an active session.
- Live session view renders the current state with management
  affordances: add / remove / reorder / swap / correct / complete.
- Exercise search gains a "Send to watch session" action when a live
  session exists.

### Implementation Steps

1. Add live-session-aware methods to the phone's `WorkoutSession`
   state owner.
2. Build the live session entry point on home / status.
3. Build the live session view with management affordances.
4. Wire the exercise-search "Send to watch session" action.
5. Implement the merge logic on session completion.
6. Verify every emitted event against protocol fixtures.

## Unit Tests Required

- `test/phone_manage_bridge_test.dart` — each structure-change
  operation emits the correct protocol event, validated against
  fixtures.
- `test/phone_manage_bridge_test.dart` — merge tests: a session with
  interleaved phone- and watch-originated observations produces a
  single correctly ordered record.
- `test/phone_manage_bridge_test.dart` — entry corrections are
  represented per the protocol and reconciliation applies them.
- `test/phone_manage_bridge_test.dart` — finishing the session from
  the phone emits session-completed and merges correctly.

## Progress

- [x] TDD: tests authored, red run recorded
      — `test/phone_manage_bridge_test.dart` (18 tests), plus the live-session
      and manage-bridge groups in `test/screen_widget_test.dart` and
      `test/interaction_flow_test.dart`. Red run: `No named parameter with the
      name 'liveSession'`, `The method 'reorderExercises' isn't defined for the
      type 'LiveSessionMirrorState'` — missing implementation, not a harness
      error.
- [x] Phase 1 — Data Layer (N/A — schema unchanged)
- [x] Phase 2 — Logic & UI (state methods + surfaces + merge)
- [x] Phase 3 — Code Review

### Implementation notes

- `LiveSessionMirrorState` gained the bridge: named operations
  (`addExercise`, `removeExercise`, `reorderExercises`, `swapExercise`,
  `correctEntry`, `deleteEntry`, `pushExercise`, `completeSession`), the read
  surface a view needs (`exercises`, `entries`, `currentExercise`,
  `currentExerciseIndex`, `isActive`, `completedRecord`), and `mintSlotId` —
  the phone owns slot identity.
- One reconciliation change was required, not cosmetic: a phone whose own
  ladder is empty now **adopts** an incoming snapshot instead of re-asserting
  an empty one. Without it, joining a wrist-started session would wipe the
  wrist's ladder. `test/live_mirroring_test.dart` S-008 is unaffected (it
  asserts the re-assertion with a ladder held).
- Surfaces: `lib/features/session/live_session_screen.dart` (`LiveSessionScreen`),
  `lib/widgets/session/live_session_entry_point.dart`, the
  `liveSession*` parameters on `ExercisePickerScreen`, and an optional
  `LiveSessionMirrorState?` threaded through `MyApp` → `HomeScreen`.
- `main.dart` passes no mirror: no transport implementation exists yet in this
  repository, so there is nothing for one to receive from. The head is wired
  and exercised (tests, and the QA harness's "Manage on phone" button);
  connecting it to a real radio belongs to the transport item.

## Feedback

Code review of 2026-09-20 rejected the iteration on documentation-standard and
coverage grounds. All items below are now addressed; the feature's behaviour did
not change.

1. **Documentation standard (was blocking).** The control inventories are gone
   from both documents, and with them the false claim that a picker row tap
   always returns the exercise. `widget_catalog/session_widgets.md` now states
   the pop contract as conditional and points at
   `test/interaction_flow_test.dart`; `navigation_and_screens.md`'s picker row
   states the parameter contract only.
2. **Widget catalog index.** `LiveSessionEntryPoint` has its alphabetical row in
   `widget_catalog.md`.
3. **Home layout — the risk was real, and is now measured.** Adding a live
   session at 360×490 overflows the panel by 13 px. The cause is not the budget:
   `LiveSessionEntryPoint.budgetHeight` matches the rendered height exactly (46pt
   at scale 1.0, 58pt at 1.6). The cause is that the tile grid is *already* at
   its 56-point floor at that size, so there is nothing left to absorb the block.
   490pt is below `SupportedViewport`'s 640pt minimum, and that class forbids
   per-size handling below it, so `test/home_short_viewport_test.dart` asserts the
   live-session case at the supported floor (both scales) and records the 490
   finding in place. S-003 still guards the compressed path with no watch
   session. The three constants became one call, so the budget is no longer
   restated by the caller.
4. **Uncovered branches covered.** Empty ladder, a correction with nothing in it,
   a single-field correction with an unparseable value, and both entry-summary
   fallbacks. The empty-ladder case found that an empty ladder renders an empty
   card with no message while the LOGGED section below it says "Nothing logged
   yet." — left as-is, since adding copy is a product decision.
5. **Test duplication.** The two mirroring tests were not identical, but five
   helpers were: the schema loader, the fixture reader, the clock, the instant
   formatter, and the protocol root. Those now live in
   `test/helpers/sync_protocol_harness.dart`; the domain fixtures that genuinely
   differ stay local.

Also taken: `moveExercise` moved from the screen into `LiveSessionMirrorState`,
so the "a move is a whole order" rule is asserted against the wrist instead of
through a menu tap, and the screen's body builder was split into its two
sections.

### Second review pass — 2026-09-20

The follow-up review found the first pass half-done in three places. All
addressed:

- **The harness extraction had left a forwarding layer.** Five one-line shims
  stood in front of the shared helpers and the two JSON casts were still
  duplicated verbatim. The shims are gone and every call site names the helper
  directly; the helper now also owns the protocol root, so callers pass a path
  relative to it instead of building one from a constant they restate.
- **Two comments claimed a test that did not exist.** Both said the panel's
  live-session budget was proven against the rendered height; nothing asserted
  it. It does now — `_pumpAndAssertShortViewport` checks the entry point renders
  at `LiveSessionEntryPoint.budgetHeight`, and both comments point at that
  instead of at a measurement. Red-checked: a four-point error in the budget
  fails the test.
- **Doc hygiene.** The home screen's inventory row now names the entry point it
  renders; `widget_catalog.md` and the two date stamps in
  `navigation_and_screens.md` agree with each other and with today.

### Phase 2 Complete ✓
Implementation done. All Phase 0 tests green. Ready for Code Reviewer.
