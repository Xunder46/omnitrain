# Feature: Nutrition Quick-Log on the Watch

> **Tier 3 — Live sync, sensors, nutrition.**
> Platforms: native watchOS (first) and Flutter Wear OS (to identical
> behaviour in the same working context).
> Depends on:
> - [watch-phone-sync-protocol](./watch-phone-sync-protocol-plan.md)
>   (item 5) — gate.
> - [watch-session-engine](./watch-session-engine-plan.md) (item 6) —
>     nutrition events ride the same append-only persistence and sync
>     path as training observations.
> Last reconciled against source: 2026-07-13.

## Overview

"Foods I Eat," wrist edition: quick-adding from the user's frequent
and favorite foods, and nothing else. No search, no catalog, no macro
configuration — the phone owns all of that. The value is the
two-second log of a routine meal or snack without pulling out a phone.
It is reachable outside active workouts, since eating is not a training
event, and it rides the same append-only, kill-safe, deduplicated sync
path as everything else.

## Requirements

- The watch shows a compact list of the user's frequent and favorite
  foods, derived by the same rules the phone uses, proactively synced
  and fully available offline.
- Tapping a food logs it at its default portion; an optional portion
  adjustment via rotary input is available before confirming.
- Logged entries are appended locally with kill-safe persistence and
  sync to the phone's nutrition log per the protocol, with the same
  idempotent, exactly-once outcome as training observations.
- The surface is reachable outside of an active workout — nutrition
  logging is independent of training sessions.
- Out of scope: barcode scanning, food photos, creating foods,
  editing past entries, displaying macro totals or targets on the
  watch.

## Acceptance Criteria

- [ ] With the phone off, a food can be quick-logged from the watch
      and appears in the phone's nutrition log exactly once after
      reconnect.
- [ ] The watch's food list matches the phone's
      frequents-and-favorites derivation against a fixture dataset.
- [ ] Portion adjustment changes the logged quantity, and the synced
      entry reflects it.
- [ ] Nutrition entries survive a watch app kill before sync:
      restored on relaunch and delivered later.
- [ ] The surface is reachable outside of an active workout.
- [ ] No macro editing, no target configuration, no catalog browsing
      on the watch.

## Scenarios

### S-001: Quick-log a favorite food with the phone off
- Trigger: User taps a favorite food on the watch.
- Precondition: Phone is unreachable; food list is locally synced;
  food is in the favorites / frequents list.
- Flow: User taps → food is logged at default portion → observation
  is persisted on the watch.
- Expected outcome: Watch shows a confirmation. Observation is
  emitted to the phone when it reconnects.
- Edge case of: none

### S-002: Phone receives the nutrition event exactly once after reconnect
- Trigger: Phone reconnects after the offline log.
- Precondition: Watch has buffered the nutrition event.
- Flow: Watch emits the event → phone receives and applies.
- Expected outcome: Phone's nutrition log shows the entry exactly
  once; the entry matches the watch's local record.
- Edge case of: S-001

### S-003: Frequents / favorites parity with the phone
- Trigger: Watch derives its food list after a sync.
- Precondition: Fixture dataset defines a phone-side
  frequents-and-favorites derivation.
- Flow: Watch applies the same derivation rules to the synced food
  data.
- Expected outcome: Watch's list equals the fixture's expected list.
- Edge case of: none

### S-004: Portion adjustment changes the logged quantity
- Trigger: User adjusts the portion via rotary input before tapping
  Log.
- Precondition: Default portion exists for the food.
- Flow: Rotary adjusts portion → user taps Log.
- Expected outcome: Synced entry reflects the adjusted quantity.
- Edge case of: S-001

### S-005: Nutrition entry survives a watch kill before sync
- Trigger: Watch app is force-killed after the user logs a food but
  before sync.
- Precondition: Watch has the nutrition event persisted.
- Flow: Force-kill → relaunch → engine reads persisted state.
- Expected outcome: Event is restored; delivered later when the
  phone reconnects.
- Edge case of: S-002

### S-006: Surface is reachable outside an active workout
- Trigger: User opens the watch app with no active session.
- Precondition: App is foregrounded.
- Flow: User navigates to nutrition quick-log → food list is shown.
- Expected outcome: Surface is reachable; no session prerequisite.
- Edge case of: none

## Iteration 1

### DB Changes

- Add `local_nutrition_events` to the on-watch storage schema
  (event id, food id, portion, timestamp, confirmedAt nullable).
  This rides the same append-only store as observations from
  item 6.
- No changes to the phone repository.

### Backend Changes

- Frequents / favorites derivation logic ported to the watch and
  parity-tested against the phone.
- Nutrition event emission via the same observations-up pipeline as
  training observations, with the same idempotency contract.
- A "nutrition quick-log" entry point in the engine that emits the
  event and persists it.

### Frontend Changes

- Compact food list on the watch, with rotary portion adjustment and
  a primary Log action.
- Surface reachable outside the workout context (e.g. a top-level
  nutrition tile on the watch home).

### Implementation Steps

1. Add the on-watch nutrition-event storage schema.
2. Port the frequents / favorites derivation to the watch and write
   the parity test.
3. Implement the nutrition quick-log engine entry point.
4. Build the surface (watchOS first, then Wear OS).
5. Verify the surface is reachable outside an active workout.
6. Verify graceful degradation under permission denial (no app
   permissions are required for nutrition logging — this scenario
   is a no-op).

### Platform Notes

- **watchOS (native)**: SwiftUI list; `WKExtendedRuntimeSession` if
  needed.
- **Wear OS (Flutter)**: Flutter widgets; rotary / drag input.
- Both platforms consume the same protocol fixtures from item 5 and
  the same engine API from item 6.

## Unit Tests Required

- `test/watch_nutrition_quick_log_test.dart` — frequents / favorites
  derivation parity test against the phone logic (shared fixture).
- `test/watch_nutrition_quick_log_test.dart` — nutrition event
  serialization matches protocol fixtures.
- `test/watch_nutrition_quick_log_test.dart` — persistence and
  redelivery tests mirroring the item 6 patterns.
- `test/watch_nutrition_quick_log_test.dart` — portion adjustment
  changes the logged quantity and the synced entry.
- `test/watch_nutrition_quick_log_test.dart` — surface reachable
  outside an active workout (UI smoke test).
- `watchTests/watch_nutrition_quick_log_test.swift` — same
  fixture-driven tests on watchOS.

## Progress

- [x] TDD: tests authored, red run recorded
- [x] Phase 1 — Data Layer (nutrition-event storage)
- [x] Phase 2 — Logic & UI (derivation + engine + surface)
- [x] Phase 3 — Code Review
- [x] Review findings 1–8 remediated
- [x] Round 4 — router dispatch (both owners asked)
- [x] Round 5 — harness day-log readout
- [x] Round 6 — `receipt` message: a standalone quick-log is acknowledged
- [x] Round 7 — reviewer's findings on the round-6 work
- [x] Behaviour parity verified across watchOS + Wear OS

### Remediation of the review's findings

Red run (before the remediation), 2026-09-21:
`flutter test test/watch_nutrition_quick_log_test.dart` — compile failure:
`WatchNutritionLogBridge`, `WatchNutritionLogOutcome` and `WatchReferenceSync`
are undefined. Two further red assertions once it compiled: the Hive round-trip
of the synced list returns `[]`, and `LiveSessionMirrorState` folds a foreign
session's quick-log into the session it holds.

What closed each finding:

1. **The phone now applies a quick-log.** `WatchNutritionLogBridge`
   (`lib/state/watch/watch_nutrition_log_bridge.dart`) turns the wrist's
   `nutrition_quick_log` events into the phone's own day log through
   `NutritionState.logConsumedFoodAt`, whose one-row-per-food-per-day rule is
   what makes redelivery idempotent rather than a ledger of the bridge's own. A
   food the library no longer holds is reported, not invented. The latent
   mirror bug is fixed: `LiveSessionMirrorState.receive` ignores any consumed
   message whose `sessionId` is not the session it holds (`session_snapshot`
   excepted — it is how a wrist-started session becomes renderable).
   Verified by S-002.
2. **The surface is reachable on a device.** `WatchStartScreen.onOpenNutrition`
   is wired in the QA harness (`lib/watch/debug/watch_start_debug_main.dart`),
   which now constructs a `WatchNutritionState` over the same store, routes
   `foods_down` through the orchestrator, and opens the surface from the home
   tile. The shipping app entry stays blocked on the app target that does not
   exist in-repo — the same blocker as item 11's finding 4.
3. **The phone builds `foods_down`.** `WatchReferenceSync.buildFoodsDown`
   (`lib/core/utils/watch_reference_sync.dart`) sorts by the phone's own Foods
   I Eat rule, derives kcal from the macros, and carries the last portion as the
   default. It is exercised against the wrist by S-003 — the QA harness seeds
   its own literal, as it already does for `routines_down` — and its transport
   is the same missing carrier `routines_down` has needed since item 11 — one
   unwired reference-data path, not two.
4. **The portion steppers are named and shaped.** `WatchStepButton` and
   `WatchRotaryTurn` (`lib/watch/widgets/watch_controls.dart`) are the one
   owner of the wrist's step control and detent accumulation; both watch
   screens use them.
5. **The docs match the source.** `widget_catalog/home_screen.md` no longer
   claims a `_FoodRow` in `nutrition_screen.dart` or an "Ungrouped" heading,
   and points at `foods_i_eat_order.dart` and S-003 instead of restating the
   rule.
6. **The new record family round-trips.** `HiveWatchSessionStore._allRows` was
   not reading the food-catalog box at all, so a synced list was silently lost
   on the next launch; S-005 now proves it survives.
7. **The shared owners exist.** `SyncProtocolValidator.evaluateOrAccept`
   (`incomingRejections` in Swift) is the one incoming-message gate;
   `WatchRotaryTurn`, `WatchStepButton` and `WatchMetricStepping.pointsPerDetent`
   hold the wrist's rotary and control constants.
8. **The dead members are gone:** `WatchNutritionSession.isNutritionSession`
   and `WatchObservationKind.all` is now asserted by a test rather than unused.

### Test runs

- Red (before implementation), 2026-09-21: `flutter test test/watch_nutrition_quick_log_test.dart`
  failed to compile — `lib/watch/nutrition/watch_food_catalog.dart`,
  `watch_nutrition_state.dart`, `watch_nutrition_screen.dart` and
  `lib/core/utils/foods_i_eat_order.dart` do not exist, `WatchNutritionState`,
  `WatchNutritionScreen`, `WatchObservationKind`, `WatchNutritionSession` are
  undefined, and `WatchSessionEngine.nutritionLog` is missing.
- Green (after implementation): `flutter test test/watch_nutrition_quick_log_test.dart
  test/sync_protocol_fixtures_test.dart` — 61 passed; the full Dart suite — 2760
  passed, 1 skipped. watchOS: `swift test` in `watch/watchos` — 144 passed,
  including the 21 new `WatchNutritionQuickLogTests`.
- Green (after remediation): `flutter test test/watch_nutrition_quick_log_test.dart
  test/sync_protocol_fixtures_test.dart test/watch_session_engine_test.dart` — 86
  passed (30 in the feature file, up from 22); the full Dart suite — 2769 passed,
  1 skipped, 0 failed. watchOS: `swift test` — 145 passed, 0 failed. `flutter
  analyze lib test` — 0 errors, 11 warnings, all pre-existing in untouched files.

### Decisions taken in this iteration

1. **A nutrition quick-log is an observation, not a parallel table.** The row is
   the existing `WatchObservationRecord` (`kind: nutrition_quick_log`), so
   idempotency, the prune window and the `observations_up` pipeline are the
   item-6 ones. The acknowledgement is not: a standalone quick-log is
   confirmed by the v1 `receipt` message, because `session_snapshot` never
   carries a nutrition entry back — the phone's mirror does not hold a
   nutrition session. The plan's
   `local_nutrition_events` fields map onto the observation: `eventId`/`entryId`,
   `payload.foodId`, `payload.servings`, `loggedAt`, `confirmedAt`.
2. **The phone's food list needs a message, so `foods_down` was added to the
   protocol.** `routines_down` is strict and carries exercises; no v1 message
   could carry foods, and without one the wrist's list could never be synced
   (the requirement says "proactively synced"). It is reference data in the
   same idiom: schema, valid + invalid fixture, manifest entry, PROTOCOL.md row,
   and a shared contract fixture (`watch/contract/watch_nutrition_contract.json`)
   both clients' suites assert against.
3. **A standalone log carries the nutrition log's own session id**
   (`nutrition-<UTC date>`), because `observations_up` requires a non-empty
   `sessionId` and the surface is reachable with no session (S-006). While a
   session is running the log rides it instead, so a snack logged mid-workout is
   part of that session's record.
4. **The wrist's list order is a derivation, not a stored list.** The phone's own
   Foods I Eat ordering was extracted to `lib/core/utils/foods_i_eat_order.dart`
   so one rule serves the card and the wrist; the watch replays it over the
   synced rows and lifts its own recent logs to the front, the shape
   `deriveFallbackExercises` already uses.
5. **Portion bounds live in the shared contract, not in either client.** A
   detent is 0.5 servings, clamped to [0.5, 10], pinned by
   `watch/contract/watch_nutrition_contract.json`.

### Where the native suite actually lives

This plan named `watchTests/watch_nutrition_quick_log_test.swift`; the native
suite is `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift`,
because that is where `swift test` finds it and where the rest of the watchOS
register runs. Same correction the item-11 plan recorded.

### Files added or changed

- Protocol: `watch/sync_protocol/schemas/messages/foods_down.schema.json`,
  `schemas/envelope.schema.json`, `fixtures/valid/foods_down.json`,
  `fixtures/invalid/foods_down_missing_food_id.json`, `fixtures/manifest.json`,
  `PROTOCOL.md`.
- Shared contract: `watch/contract/watch_nutrition_contract.json`.
- Phone: `lib/core/utils/foods_i_eat_order.dart` (extracted from
  `lib/features/nutrition/nutrition_screen.dart`, which now renders it),
  `lib/core/sync_protocol/message_validator.dart`.
- Wear OS: `lib/watch/nutrition/` (`watch_food_catalog.dart`,
  `watch_nutrition_state.dart`, `watch_nutrition_screen.dart`),
  `lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_engine.dart`,
  `lib/watch/start/watch_start_screen.dart`, `lib/watch/start/watch_sync_orchestrator.dart`.
- watchOS: `WatchFoodCatalog.swift`, `WatchNutritionState.swift`,
  `WatchNutritionView.swift`, plus `WatchRecords.swift`, `WatchSessionStore.swift`,
  `WatchSessionEngine.swift`, `WatchStartPaths.swift`, `SyncProtocolValidator.swift`,
  `WatchSyncOrchestrator.swift`, `WatchStartView.swift`.
- Tests: `test/watch_nutrition_quick_log_test.dart`,
  `watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift`.
- Docs: `.github/agents/docs/state_management.md`,
  `.github/agents/docs/state_management/services_and_utils.md`.

Added by the remediation:

- `lib/state/watch/watch_nutrition_log_bridge.dart` (new),
  `lib/core/utils/watch_reference_sync.dart` (new),
  `lib/watch/widgets/watch_controls.dart` (new).
- `lib/watch/logging/watch_logging_screen.dart`,
  `lib/watch/session/hive_watch_session_store.dart`,
  `lib/watch/session/watch_records.dart`,
  `lib/watch/nutrition/watch_nutrition_screen.dart`,
  `lib/watch/start/watch_session_start_paths.dart`,
  `lib/watch/debug/watch_start_debug_main.dart`,
  `lib/core/sync_protocol/message_validator.dart`,
  `lib/core/utils/foods_i_eat_order.dart`,
  `lib/state/watch/live_session_mirror_state.dart`.
- watchOS: `SyncProtocolValidator.swift`, `WatchNutritionState.swift`,
  `WatchStartPaths.swift`, `WatchMetricStepping.swift`, `WatchLoggingModel.swift`,
  `WatchNutritionView.swift`, `WatchRecords.swift`.
- Tests: `test/watch_nutrition_quick_log_test.dart` (+8),
  `test/watch_logging_surfaces_test.dart` (the framing audit now scans the
  nutrition surfaces and `WatchNutritionView.swift`),
  `WatchNutritionQuickLogTests.swift` (+1).
- Docs: `.github/agents/docs/widget_catalog/home_screen.md`,
  `.github/agents/docs/widget_catalog/nutrition_widgets.md`,
  `.github/agents/docs/design_system.md`.

## Feedback

**Reviewer, 2026-09-21 — the watch half works and is tested; three decisions
about the phone half and the shipped entry point have to be made before this
feature is done. All eight findings were remediated later the same day; what
remains is listed under "Still open" below.**

Verified green: `test/watch_nutrition_quick_log_test.dart` + the protocol gate
(61 passed), watchOS `swift test` (144 passed, 20 of them
`WatchNutritionQuickLogTests`), and the full Dart suite (2760 passed). S-001 to
S-006 each have a passing test that asserts the register's stated outcome. The
gaps below are not test failures — they are places where the plan's Acceptance
Criteria describe an end-to-end outcome that nothing in this change reaches.

### Still open

The nutrition surface's shipping entry point is still unwired: no app target
exists in this repo, so `WatchStartScreen.onOpenNutrition` is called only by the
QA harness — the same blocker item 11's finding 4 records. The `foods_down`
producer has the same missing carrier `routines_down` has needed since item 11:
the harness sends a hand-written `foods_down` literal,
`WatchReferenceSync.buildFoodsDown` is exercised only by S-003, and no
production transport carries reference data down to a real wrist yet. Both want
one piece of work — the app target and its transport — not two. The return path
had the same shape: `WatchNutritionLogBridge` was called only by the test suite,
because the harness link handed every arriving message to
`LiveSessionMirrorState`, which now correctly ignores another session's news
without passing it on. (Round 3 gave the bridge a harness caller; see below.)

1. **A quick-log never reaches the phone's nutrition log, which AC 1 requires.**
   "appears in the phone's nutrition log exactly once after reconnect": the
   phone receives the event, and the reference reconciler merges it into the
   *session's* entries, but nothing writes it to `NutritionState` /
   the consumed-food log, so the nutrition page never shows it. Worse, the one
   consumer there is (`LiveSessionMirrorState`, which applies `observations_up`
   with no `sessionId` check) would file a standalone log — whose `sessionId` is
   the nutrition log's own, not the session's — into whatever live session the
   mirror happens to hold.
   *Decision needed:* does this item own the phone-side apply (a
   `nutrition_quick_log` observation becoming a consumed-food row, idempotent on
   `entryId`), or is that a separate item? The plan's own DB Changes line ("No
   changes to the phone repository") cuts against the AC as written, so one of
   the two has to give. Do not close this item with the AC still asserting
   something no code does.

2. **The surface ships nowhere.** `WatchNutritionScreen` is reachable only from
   tests: `WatchStartScreen.onOpenNutrition` is passed by no production caller,
   including the QA harness at `lib/watch/debug/watch_start_debug_main.dart:233`,
   so the "Log food" tile never renders and AC 5 ("reachable outside of an
   active workout") is unmet on hardware. Same class of gap as item 11's
   finding 4. The tile must be wired by whatever owns the watch app entry.

3. **Nothing builds or sends `foods_down`.** The schema, fixtures, contract,
   both clients' apply paths and the orchestrator routing exist, but no phone-side
   producer does, so a real wrist's list stays empty and the surface reads
   "No foods yet" permanently. The requirement is that the list is *proactively
   synced*; either a producer lands in this item or the requirement is amended.

4. **Buttons checklist: the portion steppers bypass the design system.**
   `lib/watch/nutrition/watch_nutrition_screen.dart:190` is a bare `IconButton`
   with no explicit `shape`, so it takes the Material 3 default, and it carries
   no accessible label — while the sibling surface
   (`lib/watch/logging/watch_logging_screen.dart:297`) applies
   `OmniTheme.buttonIconRadius` and a tooltip. The two watch surfaces must use
   the same idiom.

5. **A document now asserts something untrue about the code.**
   `widget_catalog/home_screen.md:130` names a private `_FoodRow` helper in
   `nutrition_screen.dart`; that class does not exist — the row is `LogFoodRow`
   (`lib/features/nutrition/widgets/log_food_row.dart`). Line 133 also calls the
   card's last section "Ungrouped" where the card prints "Uncategorized".
   Remedy for the second half is deletion, not correction: the ordering rule now
   lives in `lib/core/utils/foods_i_eat_order.dart` and is verified by
   `test/watch_nutrition_quick_log_test.dart` (S-003), so the page should point
   there rather than restate labels. The stale class name is a structural claim
   and should simply be corrected.

6. **The new record's JSON encoding is unexercised.** The whole Dart suite for
   this feature runs on `InMemoryWatchSessionStore`, which never serialises, so
   `WatchFoodCatalogRecord.toJson`/`fromJson` (and `WatchFood` /
   `WatchFoodCategory`) never run. `test/watch_session_engine_test.dart` already
   proves the Hive store round-trips the other record families; the food catalog
   needs the same, or a first on-device sync is the first time that code runs.

7. **Duplication this iteration introduced.** The "message the watch has no
   schema set to judge" decision and the version-mismatch preamble are now
   copy-pasted four times (`lib/watch/start/watch_session_start_paths.dart:62`
   and `:141`, `lib/watch/nutrition/watch_nutrition_state.dart:63` and `:162`,
   and their Swift twins); `pointsPerDetent` is declared in both watch screens
   (`lib/watch/logging/watch_logging_screen.dart:57`,
   `lib/watch/nutrition/watch_nutrition_screen.dart:36`) together with the
   accumulation that reads it. Both belong on a shared owner — the version-check
   dance is a protocol rule and should not have four homes.

8. **Two members are dead in both languages:**
   `WatchNutritionSession.isNutritionSession` and `WatchObservationKind.all`
   (`lib/watch/session/watch_records.dart:82`, and the Swift equivalents). Either
   wire them or delete them.

Items 4–8 are mechanical. Items 1–3 are product decisions and are the reason
this review is blocked rather than approved.

### Round 2 — remediation re-review, 2026-09-21

All eight findings are closed at the level they claim, with a red run recorded
first. Green after remediation: feature + protocol + engine suites 86 passed;
full Dart suite 2769 passed, 1 skipped, 0 failed; watchOS `swift test` 145
passed, 0 failed; `flutter analyze` clean on every changed tree. The new
behaviour each has a passing test that asserts the register's outcome (S-002
bridge idempotency and the mirror guard, S-003 builder, S-004 stepper shape and
name, S-005 Hive round-trip, the closed kind set in both languages).

Three items remain before approval:

1. **The "one gate" invariant is not true yet**
   (`docs/state_management/services_and_utils.md:414`). The shared gate exists,
   but six receivers still hand-roll the version-plus-conformance preamble:
   `lib/state/watch/live_session_mirror_state.dart:153`,
   `lib/state/watch/watch_nutrition_log_bridge.dart:76` (new this cycle),
   `lib/watch/session/watch_session_engine.dart:1485`, and
   `WatchSessionEngine.swift:871`, `:1336`, `:1367`. Route them through
   `evaluateOrAccept` / `incomingRejections`, then point the invariant at a test
   that proves the gate — `test/live_mirroring_test.dart`, which it names today,
   does not.
2. **The browse card's heading is documented as "Ungrouped"**
   (`docs/state_management/nutrition_state.md:166`, `docs/data_models.md:302`)
   where the card prints "Uncategorized"
   (`lib/core/utils/foods_i_eat_order.dart`, asserted by
   `test/nutrition_test.dart:747`). Delete the prose and point at the owner and
   at `test/watch_nutrition_quick_log_test.dart` (S-003). This predates the
   iteration, but the change touches the same card, so the doc cannot be left
   describing the shape it had before.
3. **AC 1 has no caller outside tests.** `WatchNutritionLogBridge` is referenced
   only by `test/watch_nutrition_quick_log_test.dart`. Close the harness half the
   way finding 2 was closed — `lib/state/watch/live_session_mirror_debug_main.dart`
   should hand the foreign-session envelope the mirror now ignores to the bridge
   — or record it here as open, as the surface entry point and the `foods_down`
   carrier are.

Also: `SyncProtocolValidator.evaluateOrAccept` is new public API with no test
naming it and no verifier for its no-schema branch; add a direct test.

The two sentences above that claimed the harness calls
`WatchReferenceSync.buildFoodsDown` have been corrected in place — the harness
seeds its own literal, as it already does for `routines_down`.

### Round 3 — findings closed, 2026-09-21

Closed since round 2:

1. **Every incoming receiver goes through one gate.** The live mirror, the
   nutrition log bridge and both engines' `_requireConformingIncoming` /
   `requireConformingIncoming` now call
   `SyncProtocolValidator.evaluateOrAccept` / `incomingRejections`. The engines
   keep their own policy (throw), so the shared part is the verdict, not the
   reaction. `test/sync_protocol_fixtures_test.dart` (`the receiver gate`) tests
   the gate directly, no-schema branch included. The invariant names that test.
   One correction to finding 5 as written: `WatchSessionEngine.swift:871` is an
   *outbound* conformance check, not a second incoming gate; the doc now states
   the two questions separately rather than lumping them together.
   The Swift engine's refusal message for a version mismatch changed wording
   ("refusing to apply a message that advertises X" → the rejection's own
   description). The code, path and rejections thrown are unchanged, and no test
   asserted the old string.
2. **The card's heading is no longer described in prose.**
   `state_management/nutrition_state.md` and `data_models.md` now point at
   `foodsIEatSections` and its verifier instead of naming a heading; the
   remaining "Ungrouped" mentions elsewhere are the Categories tab and the group
   dropdown, which really do say that.
3. **The bridge has a caller inside `lib/`.** `WatchIncomingRouter`
   (`lib/state/watch/watch_incoming_router.dart`) owns the handoff — both owners
   are asked about every message and each answers for itself (see round 4) — and
   `lib/state/watch/live_session_mirror_debug_main.dart` uses it as its transport
   callback, counting what lands. The phone harness also builds its own
   `foods_down` with `WatchReferenceSync.buildFoodsDown` from a seeded library,
   so the producer is exercised by hand as well as by S-003, and it logs food on
   the wrist from a "Log a food" action, which is the whole loop. The shipping
   app's own entry point is still the missing app target (above).
4. **`WatchReferenceSync` moved** out of the state layer to
   `lib/core/utils/watch_reference_sync.dart`, beside the ordering rule it uses;
   the wire timestamp shape it needs moved to
   `lib/core/sync_protocol/wire_timestamps.dart`, re-exported from
   `watch_records.dart` so every existing reader is unchanged.

Verified after round 3: `flutter test` (full) — 2773 passed, 1 skipped, 0
failed; watchOS `swift test` — 145 passed, 0 failed; `flutter analyze` on every
changed tree — no issues.

Still open, unchanged: the app target and its transport. Both the watch's entry
point for the surface and the production `foods_down` carrier wait on it.

### Round 4 — the router's dispatch was wrong, 2026-09-21

Red first: `test/watch_nutrition_quick_log_test.dart` (`S-002 ... a quick-log
taken mid-session reaches the day log too`) failed with `hasLength(0)`.

The round-3 router asked the day log **only** for messages the mirror had
ignored, using "the mirror consumed it" as a proxy for "this is a session
message". That is wrong for the one case that matters most: a quick-log taken
while a workout is running rides that session (`WatchSessionEngine.logNutrition`
uses the live `sessionId`), so the mirror applies it and the day log was never
consulted. A snack mid-workout therefore reached the session's entries and
nothing else — `NutritionState.consumedToday` stayed empty, the day's calories
were short by it, and the user's only recourse was to log the food a second
time by hand. AC 1 says the entry appears in the phone's nutrition log; it did
not.

The fix removes the proxy rather than refining it: both owners are asked about
every message, and each decides for itself what is its own — the mirror by
session identity, the day log by observation kind, which the bridge already
filters. `WatchIncomingReceipt.nutrition` is now non-nullable, and `ignored` is
the ordinary answer for a session's own message.

Verified after round 4: `flutter test` (full) — 2774 passed, 1 skipped, 0
failed; watchOS `swift test` — 145 passed, 0 failed; `flutter analyze` on every
changed tree — no issues. The plan's round-2 and round-3 sentences describing
the old split have been corrected in place.

### Round 5 — the remaining suggestion applied, 2026-09-21

The round-4 review reported the mid-session dispatch defect as still open. It
was not: the fix landed in the same round, and the finding list was written
from the pre-fix state. Confirmed by running the case on its own —
`flutter test test/watch_nutrition_quick_log_test.dart --plain-name "a quick-log
taken mid-session reaches the day log too"` — 1 passed. The nullable
`WatchIncomingReceipt.nutrition` the review flagged as a warning was likewise
made non-nullable by that same change.

The one item still open was the harness's day-log readout: it kept its own
`_filedToday` tally of messages, which is a second copy of a fact the day log
already holds, and which would count a food the wrist logged twice as two. The
harness now reads the day log's own `consumedToday.length` through a
`_dayLogRows` getter, so the readout cannot drift from the log it describes.

### Round 6 — a standalone quick-log is never acknowledged, 2026-09-21

**Blocking. Not a test failure — a path nothing in the product performs.**

A quick-log taken with no workout running is stored under a day-shaped session id
(`WatchNutritionSession`), and the phone's mirror deliberately ignores it
(`lib/state/watch/live_session_mirror_state.dart:172`): the entry never enters
the phone's converged session, so it is never in the `entries` the phone sends
back (`:112`). That would be harmless if it were the end of it — the bridge makes
re-delivery a no-op — but acknowledgement in v1 has exactly one carrier, the
phone's snapshot, and the watch confirms from it:

- `lib/watch/session/watch_session_engine.dart:463` — the only
  `confirmObservations` call, inside `_applySnapshot`, confirming the `entryId`s
  present in the snapshot.
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:412` — the
  same, and the only call on that client.

So for every food logged outside a workout:

1. `pendingObservations()` keeps returning it, so
   `WatchSyncOrchestrator._sendOwedObservations` re-sends it on every connect and
   reconnect, for the life of the install.
2. `WatchSessionStore.pruneConfirmed` can never drop the row, and the store's
   contract (`append` / `readAll` / `pruneConfirmed` / `pruneSensorSamples`) has
   no other way to reclaim it — so the observation box grows monotonically with
   use, and `HiveWatchSessionStore.restore()` walks every row it holds.
3. Nothing is duplicated on the phone, because round 3's bridge is idempotent by
   the day-log rule. That is what keeps this invisible to a user and to the
   suite: the data outcome is right, the debt is not.

**Why four rounds of review missed it.** The receipt is supplied by the test that
claims to prove it: `test/watch_nutrition_quick_log_test.dart:358` and
`watch/watchos/Tests/WatchSessionEngineTests/WatchNutritionQuickLogTests.swift:246`
both call `confirmObservations` by hand. They prove the engine honours a receipt;
they do not prove a receipt arrives. A device run of the phone harness shows it
outright — `lib/state/watch/live_session_mirror_debug_main.dart:263` prints
`owed to phone: N`, which climbs and never falls.

**Falsified claims to fix either way:**

- `docs/state_management/services_and_utils.md:341` — "a quick-log is an
  observation with the item-6 idempotency, receipt and prune window". Idempotency
  yes; receipt and prune window no, for the standalone case.
- This plan's decision 1 (`:252`) makes the same claim, and its "by construction"
  is the part that turned out to be false: what was inherited is the pipeline, not
  the acknowledgement.

**Fix, and the choice it needs.** Two candidate directions, and neither is free:

- (A) Have the phone echo the entry back in a `session_snapshot` for the
  nutrition id. This stays inside v1 and reuses the existing confirm rule, but it
  is not viable as-is: `_applySnapshot` adopts the session it receives
  (`_appendSessionRow` sets the watch's current session), so the wrist would end
  up believing a workout named `nutrition-2026-09-21` is running — which would
  change what a later quick-log piggybacks on and what the start surface offers.
  Viable only with the adoption suppressed for these ids, which is itself a
  protocol-shaped rule.
- (B) Add an acknowledgement to the protocol — a `receipt` message type carrying
  `entryId`s, confirmed by the watch without touching session state. Honest and
  small, but it is a wire-contract change: schema, fixture, manifest, PROTOCOL.md
  and both clients' validators.

Recommend (B); (A) is recorded because it is the cheaper-looking option and the
reason it is not is worth keeping. Both need the owner's nod because they change
what crosses the wire, and the doc lines above change regardless of which lands.

**Owner's answers (2026-09-21), all four taken as recommended:**

1. Direction **(B)**, a `receipt` message — and it stays **v1**, because v1 has
   no deployed peers and the additive-since-v1 note is what the version policy
   asks for (PROTOCOL.md, "Versioning policy").
2. A food the phone **cannot place is acknowledged too**. The receipt asserts
   the phone holds the observation, not that the day log gained a row; the wrist
   must not re-send forever over a food the phone's library dropped.
3. **No pending-log indicator** on the wrist. The debt is an implementation
   fact, and the surface stays as designed.
4. **No echo back through `session_snapshot`** — option (A) is dead, not
   deferred, for the adoption reason above.

### Round 6 — the receipt lands, 2026-09-21

Red first, and the red run is the proof the test now drives the real path rather
than supplying the step it claims to test. With the wiring removed
(`'receipt'` out of both `messageTypes` lists and the two `applyMessage` arms),
the rewritten tests fail:

- `flutter test test/watch_nutrition_quick_log_test.dart --plain-name
  "the phone's receipt is what lets the watch drop the row"` — 1 failed
  (`Some tests failed`; the compile phase stayed green, so the failure is the
  behaviour).
- `swift test --filter testThePhonesReceiptIsWhatLetsTheWatchDropTheRow` —
  failed at `WatchNutritionQuickLogTests.swift:259` ("the receipt names a row
  the watch holds"), `:260` ("nothing is owed once the phone has taken
  responsibility for it") and `:265` (the prune).

What the receipt is, and why it carries no `sessionId`:

- `watch/sync_protocol/schemas/messages/receipt.schema.json` — `origin` const
  `phone`, payload `entryIds` (minItems 1, string items minLength 1),
  `additionalProperties: false`. `sessionId` is **not** in the payload on
  purpose: the observation it acknowledges may have no session, so naming one
  would be a lie a standalone quick-log cannot tell.
- `watch/sync_protocol/fixtures/valid/receipt.json` and
  `fixtures/invalid/receipt_missing_entry_ids.json` (`missing_required_field` on
  `entryIds`), both registered in `fixtures/manifest.json`, plus the envelope
  enum and a PROTOCOL.md table row and note.

Who sends and who reads it:

- **Sender** — `WatchNutritionLogBridge.receiptFor` and the `_acknowledge` step
  in `receive()`, `lib/state/watch/watch_nutrition_log_bridge.dart`. The
  bridge collects the `entryId` of **every** quick-log event it is handed,
  whether or not the food resolves, and answers once per message over the
  existing `WatchMirrorTransport`. `WatchNutritionLogResult.acknowledgedEntryIds`
  reports what went out. A bridge with no transport (a test, or a phone with no
  link yet) acknowledges nothing rather than pretending.
- **Reader** — `case 'receipt'` in both engines
  (`lib/watch/session/watch_session_engine.dart` → `_applyReceipt`,
  `WatchSessionEngine.swift` → `applyReceipt`), each returning
  `!(await confirmObservations(entryIds)).isEmpty`, so the message reports
  "changed something" only when it acknowledged a row the watch still owed. Both
  orchestrators route it to the engine. It touches no session state: `current`
  is neither read nor written.
- **Gate** — `'receipt'` added to `messageTypes` in both validators, with one
  semantic rule on each side (`_duplicateAcknowledgementRejections` /
  `duplicateAcknowledgementRejections`): the same `entryId` twice in one receipt
  is a `semantic_violation`, in the same idiom as the duplicate-`eventId` rule.

The tests, on both clients, now build the receipt as the phone builds it and
hand it to the real orchestrator — no `confirmObservations` call in the test:

- Dart: "the phone's receipt is what lets the watch drop the row" asserts the
  receipt's `type`, `origin` and `entryIds` off the phone's own transport, then
  that the wrist applies it, owes nothing, and can prune the row. "a food the
  phone cannot place is not owed forever" asserts the food is reported unplaced
  **and** still acknowledged.
- Swift: `testThePhonesReceiptIsWhatLetsTheWatchDropTheRow` (same path through
  `orchestrator.receive`) and
  `testAReceiptForARowTheWatchDoesNotHoldChangesNothing` (a receipt naming a row
  the watch does not hold applies nothing and reports no change).

The harness readout is now a fact that moves: `live_session_mirror_debug_main`
gives `WatchNutritionLogBridge` its `_PhoneTransport`, and a receipt arriving on
the wrist repaints with what is still owed. Log a food there — the harness runs a
session, so the log rides it — and watch `owed to phone` go to 0. (Round 7
corrects this paragraph: it first claimed the *sessionless* case, which the
harness cannot show, because `_launch` always creates a session and a finished
one is still adopted on restore. The sessionless drain is pinned by the two
suites' tests instead, not by the QA surface.)

**The two false claims are corrected, not softened.** Decision 1 above now says
which part of item 6's behaviour a quick-log actually inherits (the pipeline and
the prune window) and which part it does not (the acknowledgement), and
`docs/state_management/services_and_utils.md` no longer claims a receipt it does
not get: it states that a snapshot is not the acknowledgement for a standalone
quick-log, names the receipt as the one that is, and points at the tests above.

Verified after round 6: `flutter test` (full) — 2777 passed, 1 skipped, 0 failed
(up from 2774 — the Dart feature file gained the real-path assertions); the
feature and protocol suites together — 77 passed; watchOS `swift test` — 146
passed, 0 failed (up from 145); `flutter analyze` on every changed Dart tree — no
issues.

Still open, unchanged: the app target and its transport (the watch's entry point
for the surface and the production `foods_down` carrier).

### Round 7 — reviewer's findings on the round-6 work, 2026-09-21

The receipt itself is verified end to end on both clients (full Dart suite 2777
passed / 1 skipped, watchOS 146 passed, red proofs recorded for both rewritten
tests). What follows is what the round left behind; none of it is a behaviour
failure.

1. **A new member nothing reads.** `WatchNutritionLogResult.acknowledgedEntryIds`
   (`lib/state/watch/watch_nutrition_log_bridge.dart:59`) is written by the
   bridge and read by no caller, in `lib/`, `test/` or the harness — the same
   class of finding as round 2's dead members. Either assert it in the receipt
   test (which is what the round-6 record claims it is for) or delete it.
2. **Normative prose is broader than the code.** `watch/sync_protocol/PROTOCOL.md:95`
   calls the receipt "the only thing that lets the watch drop them". It is not:
   `_applySnapshot` / `applySnapshot` confirm the `entryId`s a snapshot carries,
   and the same file's next sentences rely on that. Word it as the
   acknowledgement for an entry no snapshot carries.
3. **The bridge's own doc section is silent about the receipt.** `The phone's
   half of a quick-log` (`services_and_utils.md:413`) describes the bridge
   without mentioning that it is the phone-side sender of the receipt; the only
   mention lives in the section above it, which never names the sender.
4. **The doc now says "Verified by" twice for one class.** `services_and_utils.md:358`
   (pre-existing) follows the new paragraph's own pointer at `:349-353`. Merge
   them.
5. **The harness cannot show the sessionless case.** The round-6 record
   (`:716`) says to log a food with no session and watch the debt fall.
   `live_session_mirror_debug_main.dart:229` always creates a session at launch
   and no action ends one, so the standalone path — the one this round was
   about — is not reachable from the QA surface. Add a way to reach it, or
   correct the record to what the harness actually shows.
6. **No test pins the no-ack-on-refusal rule.** The bridge returns before
   `_acknowledge` when the gate refuses a message
   (`watch_nutrition_log_bridge.dart:125`), which is the "never acknowledge what
   you did not read" guarantee a receipt makes load-bearing; nothing asserts it.
7. Smaller: the private `_RecordingMirrorTransport`
   (`test/watch_nutrition_quick_log_test.dart:1298`) duplicates the shared
   `RecordingMirrorTransport` (`test/helpers/live_session_fixtures.dart:13`);
   the receipt behaviour has no register entry of its own (S-002's tests carry
   it); and the phone now builds envelopes by hand in two places
   (`watch_nutrition_log_bridge.dart:107`, `live_session_mirror_state.dart:447`).

**All nine closed later the same day.** Two of them were red-proved before the
fix, because both new assertions could have been satisfied by writing the test
next to the wrong line:

- `acknowledgedEntryIds` — with `acknowledgedEntryIds: acknowledged,` removed
  from the bridge's result, the receipt test fails
  (`Expected: ['rec-1'] / Actual: []`).
- No-ack-on-refusal — with an `_acknowledge` call hoisted above the gate, "a
  message the phone refuses to read is not acknowledged" fails
  (`Expected: empty` on `reply.sent`, reason: "the wrist must keep owing what the
  phone could not read").

What each item got:

1. **`acknowledgedEntryIds` is asserted** — the receipt test now reads the
   bridge's result and expects the `entryId` back, before checking what crossed
   the wire. The field reports what the phone took on, which is what the receipt
   itself asserts.
2. **PROTOCOL.md now says which message acknowledges what**: a snapshot confirms
   the `entryId`s it carries too, so a receipt is what acknowledges an entry no
   snapshot carries, and an entry neither names stays owed.
3. **The bridge's doc section names it as the receipt's sender** — including the
   unplaceable case and the refusal case — instead of leaving that to the
   section above, which never named a sender.
4. **The harness claim is corrected to what the QA surface shows** (the
   paragraph above), and the record now says where the standalone drain is really
   pinned: the two suites' tests. Reaching a sessionless state from the harness
   would mean a second transport-wired surface, not a flag — `_launch` creates a
   session, `restore` adopts the newest session row, and `logNutrition` rides
   whatever session exists, finished or not.
5. **The refusal rule is pinned** by the new test above.
6. **The duplicate verification sentence is merged** — one "Verified by" per
   class in that section.
7. **The feature test uses the shared `RecordingMirrorTransport`**; its private
   copy is deleted. The receipt behaviour is documented as riding S-002 rather
   than given a register entry of its own, since it is S-002's outcome that a
   standalone quick-log is applied exactly once *and* released.
8. **The phone's envelopes are built in one place**:
   `lib/core/sync_protocol/phone_envelope.dart`, beside the timestamp shape it
   needs for the same reason — the fields belong to the protocol, not to a
   producer. Its four call sites are `buildFoodsDown`, `snapshotEnvelope`, the
   mirror's `_envelope` and `receiptFor`, which is what stops a fifth from
   spelling the envelope differently. Key order is unchanged, so no payload
   moved on the wire. The `const` seeds in `watch_start_debug_main.dart` stay
   literals: they stand in for the transport, and a `const` fixture cannot call
   a function. The invariant is recorded in
   `docs/state_management/services_and_utils.md` ("Outbound is a different
   question from inbound").

Verified after round 7: `flutter test` — the feature file alone 34 passed (up
from 33: the refusal test), the four watch/protocol suites together 137 passed,
and the full Dart suite 2778 passed, 1 skipped, 0 failed (up from 2777);
watchOS `swift test` — 146 passed, 0 failed; `flutter analyze` on every changed
Dart tree — no issues (the four remaining infos in that analysis run are
pre-existing, in files this round never touched:
`lib/core/constants/modality_config.dart`, `lib/core/constants/profile_measurements.dart`,
`lib/core/navigation/omni_route.dart`, `lib/core/services/exercise_library_service.dart`).

### Round 8 — reviewer's findings on the round-7 work, 2026-09-21

All nine round-7 items verified closed, including both red proofs. Three items
remain, all documentation plus one test-shaped suggestion:

1. **A dangling cross-reference, introduced by round 7.**
   `docs/state_management/services_and_utils.md:421` — "What the wrist does with
   the receipt is in the engine's confirmation path above". There is no engine
   section above (the sections are `WatchIncomingRouter`, `WatchReferenceSync`,
   `WatchNutritionState`, `WatchSyncOrchestrator`, `LiveSessionMirrorState`), and
   `confirmObservations` appears nowhere in the document. Name the entry points
   (`WatchSessionEngine.confirmObservations` / `pruneConfirmed`) instead of
   pointing "above", or delete the sentence.
2. **An over-broad invariant.** `:454-456` — "The envelope itself has one
   builder, `phoneEnvelope` …, so the phone-origin producers cannot spell its
   fields differently." `lib/watch/debug/watch_start_debug_main.dart:62` and
   `:149` hand-spell two phone-origin envelopes as `const` seeds. They are QA
   fixtures rather than runtime producers, which is why this is a warning and not
   a blocking claim — but the sentence should say "the messages the app builds"
   or name the fixture exception.
3. **The new builder has no test naming it.** `phoneEnvelope`'s present- and
   omit-sessionId branches are both covered through producers (the built
   `foods_down` is applied through the real gate at
   `test/watch_nutrition_quick_log_test.dart:963`, the receipt through the
   watch's gate in the receipt test), so this is a suggestion rather than a gap:
   a direct case would pin the omission contract that makes a receipt and a
   `foods_down` conformant.

Also noted, not a finding: the `receipt` schema documents the message as
session-free while permitting an envelope `sessionId`. The receiver ignores it,
so the gap is benign; the prose and the schema differ only for a sender that
would be wrong anyway.

**Warnings 1 and 2 closed later the same day**, documentation only; the
suggestion was left for the owner.

1. **The dangling pointer now names what it means.** The sentence reads
   `WatchSessionEngine.confirmObservations` — an append of its own, so a relaunch
   can still tell what it may drop — and `pruneConfirmed`, which is the only way
   the observation box gives rows back. It cites the three tests that exercise
   them (`test/watch_nutrition_quick_log_test.dart` two cases;
   `WatchNutritionQuickLogTests.testThePhonesReceiptIsWhatLetsTheWatchDropTheRow`)
   instead of pointing at a section that does not exist. The Dart test names are
   quoted as the reporter renders them, typographic apostrophe included.
2. **The invariant now scopes itself.** "Every message the app builds goes
   through one builder" plus the four named producers, and the exception stated
   with its reason: the QA harness's two `const` seeds
   (`lib/watch/debug/watch_start_debug_main.dart`) stand in for a transport no
   desktop run has, and a `const` cannot call a function. A repository-wide
   `grep` for a hand-spelled `'origin': 'phone'` now returns the builder and
   those two fixtures and nothing else.

Unchanged and accepted by the reviewer: the `phoneEnvelope` builder has no test
naming it directly; both branches are covered through producers.
