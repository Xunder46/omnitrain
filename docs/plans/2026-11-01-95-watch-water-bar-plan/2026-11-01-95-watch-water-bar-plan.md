# Feature: 95 — the water bar on the watch (series 94, PR 94b: the wrist)

> Status: DRAFT 2026-11-01 — decisions D-22..D-38 binding; Q1-Q3 carry recommended defaults the phases are built on (Q1 vetoable before Phase 3, Q2/Q3 before Phase 4). Phases 1-2 depend on no open question.
> Next handoff: @code-reviewer
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md; watch/sync_protocol/PROTOCOL.md (the water paragraph, ~l.677-714); docs/plans/2026-11-01-94-watch-water-logging-plan/2026-11-01-94-watch-water-logging-plan.md (Series 94 index, D-1..D-21 — read D-2, D-6, D-7, D-8, D-9); docs/state_management/watch_reference_data.md; docs/documentation_standard.md
> Branch: the one checked out; never create or switch branches; never commit, stash, reset or check out (the governor owns git). Evidence goes in `2026-11-01-95-watch-water-bar-plan.evidence.md` beside this file; review findings in `….review.md`.
> Shared tree: another session holds uncommitted Dart/doc files (food form, nutrition screens, exercise editor, workout state, `watch_session_adoption_bridge.dart`, `docs/state_management/workout_state.md`, several tests). None is a predicted file here. PR 94a and step 1 of the series (wrist Home) are uncommitted too; step 1 owns hunks in `ios/OmniTrain Watch App/ContentView.swift`, `WatchStartView.swift`, `WatchNutritionWiringSourceTests.swift`, `docs/state_management/watch_surface_wrist.md`. Phase 4 edits two of those files: edit on top of the step-1 hunks, never revert or reformat them. Re-read a file before quoting a line number.

## Overview

PR 94a built the wire and the phone. This PR builds the wrist: a water bar pinned at the bottom of the watch's Nutrition screen (the Foods I Eat list, `WatchNutritionView`), shown also when the list is empty, never on the single-food screen (`WatchFoodPortionView`). Minus on the left, the glass count in the middle, plus on the right, like the phone's `WaterTrackerControl` (`lib/features/nutrition/widgets/water_tracker_control.dart`). Each press is one glass added or removed, stored on the wrist first and sent as a `water_glass` event; the wrist asks for the phone's count on every sync and shows the phone's count plus its own taps the phone has not counted yet (plan 94 D-7). Owner decisions already made, not re-asked: list only; shown with an empty list; 0 before the first sync; no food or water from inside a workout (Home's Nutrition button only); a phone tap reaches the watch at the watch's next sync (plan 94 A-2).

| What the user does on the watch | What the bar shows |
|---|---|
| Never synced, taps + twice | 2 |
| Phone said 2 glasses today; taps + | 3 at once, before the phone answers |
| Phone unreachable; taps +, then − | the count moves at once; the taps wait and go at the next chance |
| Count shows 0 | minus does nothing (disabled) |
| Local midnight passes with the screen open | the new day's count (0 + today's own taps) within a minute |

## Resolved Decisions (Ledger)

Series numbering continues from plan 94 (D-1..D-21 live in the 94a file and bind here unchanged). Cite as "plan 94 D-n".

- **D-22 The tap on the wrist.** `WatchObservationKind.waterGlass = "water_glass"` joins `WatchObservationKind.all` (not `efforts`). `WatchSessionEngine.logWaterGlass(_ change: WatchGlassChange, loggedAt: Date? = nil)` (`WatchGlassChange`: `add`/`remove`, raw values `"add"`/`"remove"`) builds exactly the plan 94 D-2 event — `entryId` = `eventId` = `newId()`, `kind`, `loggedAt` = `utcIso(loggedAt ?? clock())`, `glassChange` — and stores it through the same private `appendObservation(_:sessionId:)` path as `logNutrition` (stored before emitted; needs no session). Its session id is ALWAYS `WatchNutritionSession.idFor(loggedAt)`, even when `current` holds a session (unlike `logNutrition`). `waterLog` = the stored observations of kind `water_glass`, store order, confirmed or not. Every press is its own event: never coalesced, never edited, re-sent by every `sync` (`pendingObservations`) until a receipt names it.
- **D-23 The held frame on disk.** New record `WatchWaterRecord` beside `WatchBestsRecord` (`WatchRoutineRecords.swift`): `recordId` `"water-<messageId>"`, `sessionId` `""`, `recordedAt` (wrist clock), `sequence`, `generatedAt`, `day` (String), `glasses` (Int), `appliedTapIds` ([String], order kept). `StoredWatchRecord.water`, `recordType` `"water"`; `WatchStoreContents.water` (defaulted `[]`, part of `isEmpty`). New store method `pruneWater(keepingRecordId:)` on `WatchSessionStore`, both stores, exactly `pruneBests`' semantics: an unknown id drops nothing; a prune that drops nothing writes nothing. It is the fifth prune: `testS004NoMutatingOperationExistsAnywhereInTheModule`'s allowed set gains it on purpose.
- **D-24 Applying a `water_down`.** In order: (1) `SyncProtocolValidator.incomingRejections(validator, envelope)` non-empty → refused, nothing stored, held frame unchanged. (2) Unreadable (no `messageId`, `generatedAt`/`day`/`glasses`/`appliedTapIds` missing or of the wrong type) → not applied, nothing stored. (3) `generatedAt` < the held `generatedAt` → dropped. (4) Same `day`, `glasses` and `appliedTapIds` (same order) as the held frame → nothing written; the held `generatedAt` advances in memory to the newer value; result not applied. (5) Otherwise store it, hold it (a tie in `generatedAt` with different content therefore goes to the later received), then `pruneWater(keepingRecordId:)`; result applied. `restore()` holds the stored row with the greatest (`generatedAt`, `sequence`). `onWaterChanged` fires after `restore()`, after an applied frame and after a stored tap — never for a refused, dropped or unchanged frame.
- **D-25 The shown count (plan 94 D-7, made exact).** Computed on every read, never cached. Local today = the date of `clock()` in the injected `calendar` (default `Calendar.current`); a tap's day = the date of its `loggedAt` in the same calendar; the frame's day = its `day` string compared with the zero-padded `YYYY-MM-DD` of local today. Base = held `glasses` when the days match, else 0 (also with no frame). Fold the wrist's taps of local today whose `entryId` is NOT in the held `appliedTapIds` — confirmed or not — ordered by `loggedAt`, ties by store `sequence`: add → n + 1, remove → max(0, n − 1). A receipt never removes a tap from the fold; only the frame's list does.
- **D-26 Taps past the phone's cap (the 94a reviewer's open question).** The fold keeps counting a receipted tap the frame does not list (D-25 unchanged). The wrist makes that state unreachable: it stores no tap once its own taps whose `loggedAt` falls on its local today number `WatchWaterLimits.tapsPerDay`, which equals `water_down.schema.json` `appliedTapIds.maxItems` (a test reads the schema; the phone's `kWatchWaterTapsPerDay` is the same contract number). The phone's ledger for a day holds only that wrist's taps, so every receipted tap is then listed. Rejected: dropping receipted taps from the fold — that undercounts whenever the `water_down` after a receipt is lost (plan 94 D-8: no retry), a reachable case, to fix an unreachable one. Out of scope, as in plan 94 D-7: a reinstalled wrist and a time-zone split.
- **D-27 The two buttons.** `canAdd` = today's own tap count < `tapsPerDay`. `canRemove` = shown count > 0 AND `canAdd`. A press while its button's rule is false stores nothing, emits nothing and returns false (`add()`/`remove()` return whether a tap was stored).
- **D-28 The request key.** `WatchSyncTransport.requestRoutines` gains `wantsWater: Bool`. `WatchSyncOrchestrator` takes an optional `water: WatchWaterState?` and passes `wantsWater: water != nil` on every `sync` (manual and catch-up alike). `WatchTransportRequest.routinesFrame(since:exercisesVersion:holdsBests:wantsWater:)` adds `"wantsWater": true` only when true (omitted, never `false`). Pinned against contract row `routinesWater`; a wrist built without a water state sends byte-identical pre-94b frames, so S-102, S-103, S-87c-16 and S-3820 pass unedited.
- **D-29 Routing and the sync window.** `WatchSyncOrchestrator.receive` routes `"water_down"` to `water.applyWaterDown` and returns its `applied`; no water state → false. `WatchSyncProgressCopy.replyTypes` gains `"water_down"` (it arrives inside an answer, before `bests_down`); `noteArrival`'s existing guard keeps a frame that follows a tap from reviving a finished sync.
- **D-30 The "waiting for your phone" line (Q1 default).** An unreceipted water tap counts as one entry, like a food: `deriveSyncNotice` is unchanged (only `rest` is excluded). A test pins it so a change is deliberate.
- **D-31 The bar (Q3 default).** `WatchNutritionView(model:water:)` draws `WatchWaterBar` once, after the list/empty branch and outside the `ScrollView`, so it sits at the bottom in both branches; nowhere else (`WatchFoodPortionView`, the menu, Home and the logging surfaces carry none). One row: minus (SF Symbol `minus`), the middle (SF Symbol `drop.fill` then the count), plus (SF Symbol `plus`); bordered buttons like the portion row's. Fits a 40 mm screen: the count `Text` has `.lineLimit(1)` and a `.minimumScaleFactor`; the buttons are icon-only.
- **D-32 Haptic (Q2 default).** `WKInterfaceDevice.current().play(.click)` after a press that stored a tap; nothing otherwise.
- **D-33 VoiceOver (derived from the phone's tooltips, vetoable).** Minus `"Remove one glass"`, plus `"Add one glass"`, the middle one element labelled `"Water"` with value `"1 glass"` / `"N glasses"` (`"0 glasses"`). Strings live in platform-independent `WatchWaterCopy`.
- **D-34 Midnight.** While the bar is on screen it re-reads at least once a minute (`TimelineView(.everyMinute)` around the bar) as well as on every tap and frame, so the count after local midnight is the new day's within a minute.
- **D-35 Ownership and wiring.** `WatchWaterState` (platform-independent, `WatchWater.swift`) owns the held frame, the count and the presses; constructor `engine`, `store`, optional `validator`, `clock`, `calendar`; its in-memory frame is lock-guarded like `WatchPersonalBests`. `WatchWaterModel` (`ObservableObject`, same file, outside `#if os(watchOS)` so `swift test` covers it) wraps it, hops `onWaterChanged` to the main queue. `WatchAppHost` builds one of each for the app's life, hands `water: water` to the orchestrator, calls `await water.restore()` right after `await nutrition.restore()`, and the sheet presents `WatchNutritionView(model: host.nutritionModel, water: host.waterModel)`; `S-8311`'s needle in `WatchNutritionWiringSourceTests.swift` is updated to that call (its purpose — the sheet uses the host's one model — is unchanged).
- **D-36 Unchanged: the phone and the Dart twin.** No `lib/` or `test/` Dart file changes. The phone already answers `wantsWater` and applies taps (94a). The Dart twin (`lib/watch`) emits no taps (plan 94 D-14) and never sends `wantsWater` (plan 94 D-9); `grep -rn "water" lib/watch` shows only `WatchObservationKind.waterGlass` outside `all`, and no Dart↔Swift parity test spans the record kinds, the request builder or `all` (`grep -rln "bestsType\|pruneBests" lib/watch test` → no `lib/watch` hit).
- **D-37 Taps are never pruned.** D-25 and D-26 read every stored tap, so `pruneConfirmed()` must keep having no production caller (`grep -rn "pruneConfirmed()" watch/watchos/Sources "ios/OmniTrain Watch App"` → its declarations only). A source test enforces it and names this decision; wiring a prune later needs a superseding entry that keeps today's taps.
- **D-38 Docs (sizes 2026-11-01 vs the 52,429 B band).** `docs/state_management/watch_surface.md` 50,865 B: a `### WatchWaterState` entry after `### WatchNutritionState` plus "water count" in the `WatchSyncOrchestrator` routing sentence, ≤ 1,200 B total. `docs/state_management/watch_reference_data.md` 21,266 B: section "### The wrist holds one water count" after "The water count rides an answer that asks", ≤ 1,800 B. `docs/nutrition.md` 37,910 B: ≤ 700 B appended to the "Glasses tapped on the watch" paragraph (the wrist shows the phone's count plus its own uncounted taps; a phone tap reaches the watch at its next sync — the clause the 94a review removed, now with its Swift test). `docs/watch-app-qa-wrist-logging.md` 30,053 B: step 40. `watch/sync_protocol/PROTOCOL.md` (outside `docs/`): one sentence in the water paragraph for D-26. NOT edited: `docs/state_management/watch_surface_wrist.md` (52,259 B, in the band, step-1 hunks) — nothing in it becomes false; splitting it is a separate docs PR. Docs name constants, never their values (§3.4), and carry no "in PR …" notes (§3.7).
- **D-39 The presses are one method (from A-4, ratified in review).** D-27's `add()`/`remove()` are `WatchWaterState.press(_ change: WatchGlassChange) -> Bool` (and the model's `press(_:)`), called as `press(.add)`/`press(.remove)`: S-004 forbids any `func remove…` in the module, and that guard is not relaxed. D-27's rules are otherwise unchanged.

## Feature Invariants (this PR)

- **I-6** The shown count is plan 94 D-7 at every read (D-25); no count is stored anywhere.
- **I-7** A water tap never enters a workout: its session id is the day's nutrition id; a session's `observations`, `entries` and snapshot never carry one (S-94b-2).
- **I-8** After any apply, the store holds at most one water frame row (S-94b-4).
- **I-9** A wrist without a water state sends the pre-94b request frames byte for byte (S-94b-17).
- **I-10** Every stored tap stays readable for the life of the store (D-37, S-94b-25).

## Requirements

- R-1 Each press is stored, sent under the day's nutrition id, and re-sent until receipted (D-22).
- R-2 The wrist asks for the count on every sync and holds one newest frame across relaunch (D-23, D-24, D-28, D-29).
- R-3 The bar shows the count by D-25, never below 0, and the presses follow D-26/D-27.
- R-4 The bar sits where the owner asked, with a haptic, VoiceOver and a 40 mm fit (D-31..D-35).

## Acceptance Criteria

- AC-1 A press is stored, shaped like the fixture, sent under the nutrition id and re-sent until receipted → S-94b-1, S-94b-2, S-94b-11, S-94b-16, S-94b-20.
- AC-2 The count follows D-25 across frames, receipts, apart taps and days → S-94b-3, S-94b-7, S-94b-8, S-94b-9, S-94b-12, S-94b-13, S-94b-14.
- AC-3 Never below 0; the cap → S-94b-10, S-94b-15.
- AC-4 One frame, newest wins, survives relaunch → S-94b-4, S-94b-5, S-94b-6, S-94b-16.
- AC-5 The wrist asks and routes → S-94b-17, S-94b-18.
- AC-6 The waiting line → S-94b-19.
- AC-7 The bar's place, model, haptic, VoiceOver, minute refresh, fit → S-94b-21..S-94b-24.
- AC-8 No tap is pruned → S-94b-25.

## Existing-Functionality Impact

| Touched surface | Readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchObservationKind.all` (Swift) | `grep -rn "WatchObservationKind.all" watch/watchos` → only `WatchNutritionQuickLogTests.swift` ~l.666 closed-set test; `efforts` readers (`WatchMenu.swift` l.264, engine l.1847, `WatchEffortRating.swift` l.181, `WatchRestLabels.swift` l.97, `WatchWorkoutSummary.swift` l.139, `WatchSensorSummaries.swift` l.277) filter by `efforts`, which does not change | closed-set test gains `water_glass` deliberately | S-94b-1 |
| Engine `storedObservations` readers | engine l.183 `observations`, l.250 `projectedEntries`, l.1508 sensor prune, l.1844 rest follow-on — all filter by `sessionId` of a workout; `nutritionLog` filters `nutrition_quick_log`; `WatchPersonalBests.rebuildOwnBests` reads `set` only | a tap's id `nutrition-…` is never a workout id: no effect | S-94b-2 |
| `pendingObservations` / `unconfirmedObservations` | `WatchSyncOrchestrator.sync` l.113; `ContentView.swift` `syncNotice` → `deriveSyncNotice` | taps are re-sent and counted in the waiting line | S-94b-11, S-94b-19 |
| `StoredWatchRecord` switches | `WatchRecords.swift` (7), `WatchSessionStore.swift` (4), `FileWatchSessionStore.swift` (4) | new case in each; exhaustive switches fail to compile if missed | S-94b-4 |
| `WatchSessionStore` protocol | `grep -rn "WatchSessionStore {" watch/watchos` → InMemory, File, and test wrappers `StaleReadStore` (`WatchNutritionQuickLogTests.swift` l.157), `SuspendingStore` (`WatchEffortRatingTests.swift` l.160), `ContendedWatchSessionStore` (`WatchSensorRecordingTests.swift` l.1046) | each gains a forwarding `pruneWater` | S-004 allowed set |
| `WatchStoreContents(` init | labelled, defaulted parameters | new defaulted `water:` last: no call site edited | compile |
| `WatchSyncTransport.requestRoutines` | `grep -rn "func requestRoutines" watch/watchos` → bridge + 4 fakes (`WatchSessionStartPathsTests.swift` l.54, `WatchConnectivityBridgeTests.swift` l.206, l.1426, l.1488) | parameter added; fakes record it | S-94b-17 |
| `routinesFrame` contract pins | `WatchConnectivityBridgeTests` S-102, S-103, S-87c-16, S-3820 read rows `routines`, `routinesSince`, `routinesBests`, `routinesExercises`; Dart `test/watch_transport_test.dart` reads the same JSON | default `wantsWater` false; `WatchBridgeHarness` builds the orchestrator without water; contract JSON unchanged | S-94b-17, those tests unedited |
| `WatchSyncProgressCopy.replyTypes` | `WatchSyncProgress.noteArrival` l.113; `ContentView.swift` `onIncoming` (clears `syncNoAnswer` on a reply type) | a `water_down` extends a running window and clears "no answer" (the phone did speak) | S-94b-18 |
| `WatchNutritionView(` | `ContentView.swift` sheet (one call); `WatchNutritionWiringSourceTests` S-7201 (`"WatchNutritionView("`, still true) and S-8311 (exact call) | init gains `water:`; S-8311 needle updated (D-35) | S-94b-23 |
| Phone (`lib/`) | `wantsWaterOf` in `watch_sync_wiring.dart`; `WatchWaterLogBridge` | now exercised by a real wrist; behaviour tested by 94a's S-94a-13..26 | no Dart change (D-36) |
| Standing invariants | hive import grep (AGENTS.md); `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart`; rest count-up rule (a water tap is not an effort and starts no rest — `rest` follows `efforts` only, engine l.1847) | — | Phase 4 Done Criteria |

## UI Standards Impact

None of `docs/design_system.md`'s Flutter pieces: the bar is SwiftUI on the wrist. It reuses the portion row's pattern (bordered icon buttons with `.accessibilityLabel`) and adds no colour of its own (the worn accent stays the environment's). No allowlist entry, no ratchet change; the accessibility ratchet in `WatchAccessibilitySourceTests` can only grow.

## Scenarios

Shared fixture **X** (wrist). Calendar `cal`: Gregorian, `TimeZone(secondsFromGMT: 10800)` (local = UTC+3, so the local day turns at 21:00Z). Clock `TestClock` at `2026-11-01T09:00:00Z` (12:00 local) unless stated. Id factory yields `w-1`, `w-2`, … in call order. Engine and `WatchWaterState` over one `InMemoryWatchSessionStore` with `Harness.validator()` unless stated; no workout session unless stated. `frame(gen, day, glasses, ids)` = `fixtures/valid/water_down.json` with `payload` = `{generatedAt: gen, day, glasses, appliedTapIds: ids}`, `sentAt` = gen, `messageId` = `msg-water-<genMs>-<glasses>-<ids.count>`. `receipt(ids)` = `fixtures/valid/receipt.json` with `entryIds` = ids, delivered through `engine.applyMessage`. "Tap at t" = `logWaterGlass(change, loggedAt: t)`. Times are UTC instants; local wall time in brackets.

### S-94b-1: a press is stored, then sent, shaped like the fixture
- Fixture: X; empty store. Trigger: `logWaterGlass(.add)`; then `logWaterGlass(.remove)`.
- Expected outcome: two observations `w-1` (`glassChange "add"`, `loggedAt "2026-11-01T09:00:00Z"`) and `w-2` (`"remove"`); payload keys of each = the keys of the first event of `fixtures/valid/observations_up_water.json`; two emitted `observations_up`, `sessionId "nutrition-2026-11-01"`, `messageId "msg-w-1"`/`"msg-w-2"`, both conformant; `waterLog` = [w-1, w-2]; `nutritionLog` empty; `pendingObservations().count` 2. Edge case of: none.

### S-94b-2: a press while a session is held never joins it
- Fixture: X; `createSession` with one lift slot (session id from the harness factory, `w9`), status active. Trigger: `logWaterGlass(.add)`.
- Expected outcome: emitted `sessionId "nutrition-2026-11-01"`; `engine.observations` and `engine.entries` contain no `w-1`; `engine.sessionSnapshot()` entries contain no `w-1`. Mutation: session id from `current` first (as `logNutrition`) → red. Edge case of: S-94b-1.

### S-94b-3: the local day, not the UTC day, decides the count
- Fixture: X with clock `2026-10-31T21:30:00Z` (00:30 local 11-01); held `frame("2026-10-31T21:20:00Z", "2026-11-01", 2, [])`. Trigger: tap add at the clock.
- Expected outcome: envelope `sessionId "nutrition-2026-10-31"` (D-2 uses the UTC date); shown count 2 + 1 = 3. Mutation: UTC calendar for the day → base 0, count 1 → red. Edge case of: S-94b-7.

### S-94b-4: one frame row, kept across relaunch, on both stores
- Fixture: InMemory store, and a `FileWatchSessionStore` in a fresh temp directory. Frames F1 `frame(08:00Z, "2026-11-01", 2, ["w-1"])`, F2 `frame(08:05Z, …, 3, ["w-1","w-2"])`, F3 `frame(08:10Z, …, 3, ["w-1","w-2","w-3"])`.
- Trigger: apply F1, F2, F3 in order on each store; then a new store + state over the same directory, `restore()`; then `pruneWater(keepingRecordId: "water-missing")`.
- Expected outcome: after each apply `readAll().water.count == 1` and it is the frame just applied; restored base 3 (no taps → shown 3); the unknown-id prune returns `[]` and the file's bytes are unchanged. Mutation: skip the prune → count 3 → red. Edge case of: none.

### S-94b-5: the newest frame wins; a repeat writes nothing
- Fixture: X holding F2 `frame(08:05Z, "2026-11-01", 3, ["w-1","w-2"])`.
- Trigger: (a) F1 `frame(08:00Z, …, 2, ["w-1"])`; (b) F2b `frame(08:05Z, …, 4, ["w-1","w-2","w-3"])`; (c) F4 `frame(08:20Z, …, 4, ["w-1","w-2","w-3"])`; (d) F3 `frame(08:15Z, …, 5, ["w-1","w-2","w-3","w-4"])`.
- Expected outcome: (a) not applied, base 3; (b) applied (tie → later received), base 4; (c) not applied, water rows still 1 (F2b), no `onWaterChanged`; (d) not applied (older than 08:20Z held in memory), base 4. Edge case of: S-94b-4.

### S-94b-6: a frame the wrist cannot read changes nothing
- Fixture: X holding F2. Trigger: `fixtures/invalid/water_down_unknown_field.json`; `fixtures/invalid/water_down_duplicate_tap.json`; then with a state built WITHOUT a validator, F2 with `glasses: "3"` (a string).
- Expected outcome: first two refused with the manifest's codes, nothing stored; the third not applied, nothing stored; base 3 throughout, no `onWaterChanged`. Edge case of: S-94b-5.

### S-94b-7: phone count plus the wrist's uncounted taps
- Fixture: X; taps w-1 add 07:00Z (10:00), w-2 add 07:30Z, w-3 remove 08:00Z, w-4 add 08:30Z; held `frame(08:40Z, "2026-11-01", 2, ["w-1"])`.
- Expected outcome: base 2; skip w-1 (listed); w-2 → 3; w-3 → 2; w-4 → 3. Shown 3. Edge case of: none.

### S-94b-8: before the first sync
- Fixture: X; no frame, no taps. Trigger: read; `remove()`; `add()` twice.
- Expected outcome: 0, `canRemove` false, `remove()` false with no observation and no emit; then 1, 2. Edge case of: S-94b-10.

### S-94b-9: a frame for another day
- Fixture (a): X; held `frame("2026-10-31T20:00:00Z", "2026-10-31", 5, ["w-0"])`; taps w-1 add `2026-10-31T19:00:00Z` (22:00 on 10-31), w-2 add `2026-10-31T21:30:00Z` (00:30 on 11-01). (b): clock `2026-11-01T20:59:00Z` (23:59 on 11-01); held `frame("2026-11-01T20:58:00Z", "2026-11-02", 4, [])` (phone a minute ahead); tap w-3 add `2026-11-01T20:00:00Z`.
- Expected outcome: (a) base 0 (day mismatch), w-1 is yesterday's, w-2 → 1; shown 1. (b) base 0, w-3 → 1; shown 1. Edge case of: S-94b-7.

### S-94b-10: minus at 0, and both devices removing while apart
- Fixture: X; held F1 `frame(08:00Z, "2026-11-01", 1, [])`.
- Trigger/flow: tap w-1 remove 08:30Z (shown 0, `canRemove` false, a further `remove()` stores nothing); the phone's own minus took it to 0 too, so its next answer is `frame(08:45Z, …, 0, [])`; then the phone applies w-1 at 0 ml and sends `frame(08:50Z, …, 0, ["w-1"])`.
- Expected outcome: shown 0 at every step (08:45Z frame: base 0, w-1 remove → max(0, −1) = 0); `waterLog.count` 1. Edge case of: S-94b-7.

### S-94b-11: the receipt is lost and the tap is delivered again
- Fixture: X; held `frame(08:00Z, …, 2, [])`; `RecordingTransport` orchestrator with `water:`. Trigger: tap w-1 add (shown 3); no receipt; `orchestrator.sync()`; deliver `receipt(["w-1"])` and `frame(09:01Z, …, 3, ["w-1"])`; deliver the same receipt again and `frame(09:02Z, …, 3, ["w-1"])`.
- Expected outcome: the sync re-sends the envelope with `messageId "msg-w-1"` identical to the first emission; after the answer shown 3 (not 4), `unconfirmedObservations` empty; the repeat changes nothing and writes no water row (D-24 (4)). Edge case of: S-94b-1.

### S-94b-12: the receipt arrives, the frame is lost
- Fixture: X; held `frame(08:00Z, …, 2, [])`. Trigger: tap w-1 add; `receipt(["w-1"])`; later `frame(09:05Z, …, 3, ["w-1"])`.
- Expected outcome: after the receipt w-1 is confirmed and shown stays 3; after the frame shown 3. Mutation: fold skips confirmed taps → 2 after the receipt → red. Edge case of: S-94b-11.

### S-94b-13: both devices tapped while apart
- Fixture: X; held `frame(08:00Z, …, 2, [])`; phone unreachable. Trigger: tap w-1 add 08:30Z (shown 3); the phone's own + took it to 3 there; on reconnect the phone applies w-1 (2 + 1 + 1 = 4) and sends `receipt(["w-1"])`, `frame(09:00Z, …, 4, ["w-1"])`.
- Expected outcome: shown 3 before, 4 after (base 4, w-1 listed). Edge case of: none.

### S-94b-14: the watch's local midnight
- Fixture: X with clock `2026-11-01T20:59:30Z` (23:59:30); held `frame(20:59:00Z, "2026-11-01", 3, ["w-1"])`; taps w-1 add 20:50Z, w-2 add 20:59:10Z.
- Trigger: read; advance the clock 60 s (00:00:30 on 11-02); read; `add()`.
- Expected outcome: 4 (3 + w-2); then 0 with `canRemove` false; then 1 — the new tap w-3 carries `sessionId "nutrition-2026-11-01"` (UTC date) and counts for local 11-02. Edge case of: S-94b-9.

### S-94b-15: taps past the cap
- Fixture: X; `tapsPerDay` read from `water_down.schema.json` (`appliedTapIds.maxItems`); taps: one add at `2026-10-31T20:00:00Z` (yesterday), then `tapsPerDay − 1` adds today at 06:00:00Z + i s.
- Trigger: read; `add()`; read; `add()`, `remove()`; advance the clock to `2026-11-01T21:00:01Z`; read.
- Expected outcome: `canAdd` true (yesterday's tap does not count); the add stores the last allowed tap; then `canAdd` and `canRemove` false, shown `tapsPerDay`, both presses return false with no new observation and no emit; after local midnight `canAdd` true, shown 0. Plus: `WatchWaterLimits.tapsPerDay` equals the schema's `maxItems`. Edge case of: S-94b-8.

### S-94b-16: relaunch with unsent taps
- Fixture: `FileWatchSessionStore` in a temp directory; held `frame(08:00Z, …, 2, [])`; taps w-1 add 09:00Z, w-2 add 09:01Z, no receipt.
- Trigger: build a new engine, `WatchWaterState` and `RecordingTransport` orchestrator over the same directory; `engine.restore()`, `water.restore()`; `sync()`.
- Expected outcome: shown 4; `unconfirmedObservations.count` 2; the sync sends the routines request with `wantsWater` true and the two envelopes with `messageId`s `msg-w-1`, `msg-w-2` equal to the first launch's. Edge case of: S-94b-11.

### S-94b-17: the wrist asks for the count
- Fixture: contract `watch/contract/watch_start_paths_contract.json` `transportRequests`; a `RecordingTransport` orchestrator with `water:`; `WatchBridgeHarness` (no water).
- Trigger: `sync()`; `catchUp(reachable: true)`; `routinesFrame(since: nil, wantsWater: true)`; `routinesFrame(since: nil)`; `routinesFrame(since: nil, holdsBests: true, wantsWater: true)`; harness `sync()`.
- Expected outcome: `requestedWantsWater` [true, true]; the first frame equals row `routinesWater` exactly; the second equals `routines`; the third carries both keys; the harness's first sent frame has no `wantsWater` and S-102/S-103/S-87c-16/S-3820 pass unedited. Edge case of: none.

### S-94b-18: the frame is routed and closes a sync like any reply
- Fixture: orchestrator with water; one without. `WatchSyncProgress` with a test clock t0.
- Trigger: `receive(fixtures/valid/water_down.json)` on each; progress `begin(at: t0)`, `noteArrival("routines_down", t0+1)`, `noteArrival("water_down", t0+2.5)`; later `noteArrival("water_down", t0+30)`.
- Expected outcome: true and base 3 with water; false and no row without; `isActive(t0+4)` true, `isActive(t0+4.6)` false; the late arrival leaves it false. Edge case of: S-94b-17.

### S-94b-19: unsent taps count in the waiting line (Q1)
- Fixture: X; taps w-1 add, w-2 remove; one stored `rest` observation unconfirmed. Trigger: `deriveSyncNotice(pending: engine.unconfirmedObservations, reachability: .unreachable, now:)`; `receipt(["w-1"])`; again; then `.reachable` with `now` = the clock.
- Expected outcome: `"2 entries waiting for your phone"`; `"1 entry waiting for your phone"`; nil (reachable, under `graceSeconds`). Edge case of: none.

### S-94b-20: a press while the phone is out of reach
- Fixture: X; `RecordingTransport` with `isPhoneReachable` false; held `frame(08:00Z, …, 2, [])`. Trigger: `add()`; `sync()`.
- Expected outcome: shown 3 at once; one emission; `unconfirmedObservations.count` 1; the sync still hands over `msg-w-1`. Edge case of: S-94b-11.

### S-94b-21: the model
- Fixture: X; `WatchWaterModel` over the state. Trigger: read at 0; `add()`; apply `frame(09:01Z, …, 3, ["w-1"])`.
- Expected outcome: `glasses` 0, `canRemove` false, spoken value `"0 glasses"`; after add `"1 glass"`, true returned; after the frame 3, `"3 glasses"`, and `objectWillChange` fires on the main queue (expectation). `WatchWaterCopy` labels equal D-33. Edge case of: none.

### S-94b-22: the bar is on the list only, empty list included
- Fixture: `WatchNutritionView.swift`, `WatchMenuView.swift`, `WatchStartView.swift` and every other source, comment lines stripped. Trigger: source scan.
- Expected outcome: `WatchWaterBar(` occurs once in `WatchNutritionView`'s body, after the `if model.foods.isEmpty` … `else` block and not inside the `ScrollView {` body; zero times in `WatchFoodPortionView`'s body and in every other file; inside the bar, the minus button precedes the count, which precedes the plus. Edge case of: none.

### S-94b-23: the host owns one water state and one model
- Fixture: `ios/OmniTrain Watch App/ContentView.swift`. Trigger: source scan.
- Expected outcome: `WatchWaterState(` and `WatchWaterModel(` once each, in `init() {`; the orchestrator call carries `water: water`; `restore()` holds `await water.restore()` after `await nutrition.restore()`; the content carries `WatchNutritionView(model: host.nutritionModel, water: host.waterModel)`; the `WatchMenuView` call carries no `water`. Edge case of: S-94b-22.

### S-94b-24: haptic, VoiceOver, minute refresh, 40 mm
- Fixture: `WatchNutritionView.swift`, comments stripped. Trigger: source scan of the `WatchWaterBar` body.
- Expected outcome: `.play(.click)` appears only inside a branch taken when `add()`/`remove()` returned true; `.accessibilityLabel(WatchWaterCopy.` for both buttons and the middle with `.accessibilityValue(`; `TimelineView(.everyMinute)`; the count `Text` chain has `.lineLimit(1)` and `.minimumScaleFactor(`; minus `.disabled(!` bound to `canRemove`, plus to `canAdd`. Edge case of: S-94b-22.

### S-94b-25: taps are never pruned
- Fixture: `watch/watchos/Sources` and `ios/OmniTrain Watch App`, comments stripped. Trigger: count `pruneConfirmed(` occurrences that are not `func pruneConfirmed` declarations or the engine's own delegation to its store.
- Expected outcome: zero; the failure message names plan 94 D-37. Edge case of: none.

Mutation checks (each must turn its test red; hand-revert your own hunk, run, restore, record in the evidence — never `git stash`): session id from `current` (S-94b-2); UTC day (S-94b-3, S-94b-14); no prune (S-94b-4); older frame applies (S-94b-5 d); fold skips confirmed taps (S-94b-12); no cap (S-94b-15); `wantsWater` always on (S-102 red) and never on (S-94b-17).

## Iteration 1

### Phase 1: The tap and the frame's storage (@developer)
1. [x] Kind and change — `WatchRecords.swift` · `WatchObservationKind.waterGlass` in `all`; `WatchGlassChange` (D-22); closed-set test `WatchNutritionQuickLogTests.testTheKindsTheWristCanEmitAreAClosedSet` gains `"water_glass"`.
2. [x] Record — `WatchRoutineRecords.swift` · `WatchWaterRecord` after `WatchBestsRecord` (D-23: fields, `withSequence`, `toJson`, `fromJson`).
3. [x] Record case — `WatchRecords.swift` · `StoredWatchRecord.waterType = "water"`, case `.water` through every switch (~l.697-840).
4. [x] Stores — `WatchSessionStore.swift` · `WatchStoreContents.water`, protocol `pruneWater(keepingRecordId:)` with its gate comment, InMemory `readAll` + `pruneWater`; header comment "five ways"; `FileWatchSessionStore.swift` · `readAllLocked` + `pruneWaterLocked` (bests semantics, D-3821 no-write rule).
5. [x] Test stores and S-004 — forward `pruneWater` in `StaleReadStore`, `SuspendingStore`, `ContendedWatchSessionStore`; `WatchSessionEngineTests.swift` S-004 allowed set + comment (fifth prune).
6. [x] Engine — `WatchSessionEngine.swift` · `logWaterGlass(_:loggedAt:)` and `waterLog` beside `logNutrition`/`nutritionLog` (~l.1384-1415) (D-22).
7. [x] Tests — `Tests/WatchSessionEngineTests/WatchWaterStoreTests.swift` (new): S-94b-1, S-94b-2, S-94b-3 (envelope half), and S-94b-4's store half (`pruneWater` on both stores, file bytes unchanged on an unknown id).

**Done Criteria** (run until green): record the `swift-test` baseline in the evidence file before editing; `.github/copilot/scripts/macos/gateway.sh swift-test` (0 failures, count = baseline + new tests); S-94b-2 mutant red→green in the evidence.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/{WatchRecords,WatchRoutineRecords,WatchSessionStore,FileWatchSessionStore,WatchSessionEngine}.swift`; `watch/watchos/Tests/WatchSessionEngineTests/{WatchNutritionQuickLogTests,WatchEffortRatingTests,WatchSensorRecordingTests,WatchSessionEngineTests}.swift`, `WatchWaterStoreTests.swift` (new); this plan; the evidence file.

### Phase 2: The count (@developer)
1. [x] Limits — `Sources/WatchSessionEngine/WatchWater.swift` (new) · `WatchWaterLimits.tapsPerDay` with a comment naming the schema and `kWatchWaterTapsPerDay` (D-26).
2. [x] State — same file · `WatchWaterState` (D-35 constructor), `restore()`, `applyWaterDown(_:) -> WatchCatalogSyncResult` (D-24), `onWaterChanged`.
3. [x] Count — same file · `glasses` (D-25), `canAdd`, `canRemove` (D-27).
4. [x] Presses — same file · `add()`/`remove()` (built as `press(_:)`, A-4) → `engine.logWaterGlass` with `clock()`, returning whether a tap was stored; `onWaterChanged` after a stored tap.
5. [x] Tests — `Tests/WatchSessionEngineTests/WatchWaterStateTests.swift` (new): S-94b-3 (count half), S-94b-4 (restore half), S-94b-5..S-94b-10, S-94b-14, S-94b-15 (incl. the schema-equality check).
6. [x] Tests — same file: S-94b-11 (state half: receipt then frames via `engine.applyMessage` and `applyWaterDown`), S-94b-12, S-94b-13, S-94b-16 (state half on a `FileWatchSessionStore`).

**Done Criteria**: `gateway.sh swift-test` (0 failures); mutants for S-94b-3/14 (UTC day), S-94b-5 d, S-94b-12, S-94b-15 red→green in the evidence.
**Predicted Files**: `WatchWater.swift` (new), `WatchWaterStateTests.swift` (new), this plan, the evidence file.

### Phase 3: Asking and routing (@developer)
1. [x] Request frame — `WatchConnectivityBridge.swift` · `routinesFrame(…, wantsWater: Bool = false)` and `requestRoutines(…, wantsWater:)` (D-28), doc comment in the `holdsBests` style.
2. [x] Orchestrator — `WatchSyncOrchestrator.swift` · protocol requirement gains `wantsWater`; init `water: WatchWaterState? = nil`; `sync` passes `water != nil`; `receive` case `"water_down"` (D-29); header comment.
3. [x] Fakes — `WatchSessionStartPathsTests.swift` (l.54) and `WatchConnectivityBridgeTests.swift` (l.206, l.1426, l.1488) · accept `wantsWater` and record it (`requestedWantsWater`); no assertion edited.
4. [x] Reply types — `WatchSyncProgress.swift` · `replyTypes` + `"water_down"`, comment beside the `bests_down` one.
5. [x] Tests — `Tests/WatchSessionEngineTests/WatchWaterSyncTests.swift` (new): S-94b-11 (sync half), S-94b-16 (sync half), S-94b-17, S-94b-18, S-94b-19, S-94b-20.
6. [x] Contract text — `watch/sync_protocol/PROTOCOL.md` · one sentence in the water paragraph (~l.692-711): a wrist emits no tap once its own taps of its local day reach `appliedTapIds`' `maxItems`, so every receipted tap is listed; a receipt does not take a tap out of the count, the frame's list does (D-25, D-26). No version row (no wire change).
7. [x] Verify-only — S-102, S-103, S-87c-16, S-3820 and `WatchSyncProgressTests` pass unedited.

**Done Criteria**: `gateway.sh swift-test` (0 failures); `gateway.sh test test/sync_protocol_fixtures_test.dart test/watch_transport_test.dart` (PROTOCOL path checks; contract rows unchanged); `wantsWater` always-on mutant shows S-102 red, never-on shows S-94b-17 red (evidence).
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/{WatchConnectivityBridge,WatchSyncOrchestrator,WatchSyncProgress}.swift`; `Tests/WatchSessionEngineTests/{WatchSessionStartPathsTests,WatchConnectivityBridgeTests}.swift`, `WatchWaterSyncTests.swift` (new); `watch/sync_protocol/PROTOCOL.md`; this plan; the evidence file.

### Phase 4: The bar, the host, docs and QA (@developer)
1. [x] Model and copy — `WatchWater.swift` · `WatchWaterModel` and `WatchWaterCopy` (D-33, D-35), outside any `#if`.
2. [x] View — `WatchNutritionView.swift` · `WatchNutritionView(model:water:)`; `WatchWaterBar` (D-31, D-32, D-34; Q2/Q3 defaults) drawn once after the list/empty branch; `WatchFoodPortionView` untouched.
3. [x] Host — `ios/OmniTrain Watch App/ContentView.swift` · D-35 wiring (one state, one model, `water: water`, restore order, the sheet call); step-1 hunks kept.
4. [x] Tests — `Tests/WatchSessionEngineTests/WatchWaterBarSourceTests.swift` (new): S-94b-22..S-94b-25 (the `WatchNutritionWiringSourceTests` comment-stripping helper copied, not shared); `WatchWaterStateTests.swift`: S-94b-21; `WatchNutritionWiringSourceTests.swift`: S-8311's needle only (D-35).
5. [x] Docs — `docs/state_management/watch_surface.md` and `docs/state_management/watch_reference_data.md` per D-38, each claim pointing at its Swift test by class and method name.
6. [x] Docs — `docs/nutrition.md` per D-38 (edit only the "Glasses tapped on the watch" paragraph; the file may carry another session's hunks).
7. [x] QA — `docs/watch-app-qa-wrist-logging.md` · step 40 *(owner)*: (a) Nutrition shows the bar at the bottom, with and without foods, not on a food's screen; (b) + / − move the count with a click, − is dim at 0; (c) phone count arrives after Sync; (d) offline taps show at once and in the waiting line, then reach the phone's Nutrition screen; (e) 40 mm fit; (f) VoiceOver reads "Add one glass", "Remove one glass", "Water, N glasses".
8. [x] Residue and close — `grep -rn "water_down\|wantsWater\|water_glass\|waterGlass\|WatchWater" watch/watchos "ios/OmniTrain Watch App" docs watch/sync_protocol` lists only predicted files; doc sizes recorded; Progress, Assumption Log, evidence "Docs" section (each implicated doc updated or "no update required", incl. `watch_surface_wrist.md`).

**Done Criteria**: `gateway.sh swift-test` (0 failures); `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart test/sync_protocol_fixtures_test.dart`; invariant grep `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty; no doc in `docs/` over 64 KiB and the three edited `docs/` files under 52,429 B. The views compile only for watchOS: the governor builds the watch target (`xcodebuild`, watchOS simulator) before review; the implementer states that the view was not compiled.
**Predicted Files**: `WatchWater.swift`, `WatchNutritionView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `WatchWaterBarSourceTests.swift` (new), `WatchWaterStateTests.swift`, `WatchNutritionWiringSourceTests.swift`, `docs/state_management/watch_surface.md`, `docs/state_management/watch_reference_data.md`, `docs/nutrition.md`, `docs/watch-app-qa-wrist-logging.md`, this plan, the evidence file.

## Files Affected (whole PR)

Production (Swift, ≈ 600 predicted lines): `watch/watchos/Sources/WatchSessionEngine/{WatchRecords,WatchRoutineRecords,WatchSessionStore,FileWatchSessionStore,WatchSessionEngine,WatchWater (new),WatchConnectivityBridge,WatchSyncOrchestrator,WatchSyncProgress,WatchNutritionView}.swift`; `ios/OmniTrain Watch App/ContentView.swift`.
Contract: `watch/sync_protocol/PROTOCOL.md` (one sentence). Schemas, fixtures and `watch_start_paths_contract.json` unchanged (read only).
Tests: `WatchWaterStoreTests.swift`, `WatchWaterStateTests.swift`, `WatchWaterSyncTests.swift`, `WatchWaterBarSourceTests.swift` (all new); edited: `WatchNutritionQuickLogTests.swift`, `WatchEffortRatingTests.swift`, `WatchSensorRecordingTests.swift`, `WatchSessionEngineTests.swift`, `WatchSessionStartPathsTests.swift`, `WatchConnectivityBridgeTests.swift`, `WatchNutritionWiringSourceTests.swift`.
Docs: `docs/state_management/watch_surface.md`, `docs/state_management/watch_reference_data.md`, `docs/nutrition.md`, `docs/watch-app-qa-wrist-logging.md`.
Read-only dependents (green, unedited): `WatchSyncNotice.swift`, `WatchSyncNoticeTests.swift`, `WatchSyncProgressTests.swift`, `WatchStartView.swift`, `WatchMenuView.swift`, every `lib/` and Dart `test/` file, `lib/watch/**` (D-36).

## Notes

- Dependency graph: 1 → 2 → 3 → 4. Phase 3 needs Phase 2's `WatchWaterState` type only for the orchestrator parameter; Phase 4 needs 2 and 3. No reordering gains a visible win: nothing shows until Phase 4.
- Intermediate states, all green and invisible to the owner: after 1 the wrist can store taps and frames but nothing calls it; after 2 the count exists in memory only; after 3 every sync asks the phone for the count and stores the frame (the phone already answers), and nothing is drawn; after 4 the bar is live.
- Prerequisite for Phase 4: ideally the governor commits step 1 (wrist Home) first, since Phase 4 edits two of its files; otherwise edit on top of its hunks.
- A wall clock moved backwards can order a remove before an add by `loggedAt` while the phone applied them in arrival order; the count then differs by one until the phone's next frame lists both taps. Accepted (plan 94 D-7 orders by `loggedAt`); no scenario.
- Governor steps after Phase 4: the watchOS build; the owner's device walk is QA step 40 (no simulator walk by default).
- Budget (`.github/copilot/pr-scope-budget.md` §1): 4 phases, one track (watch) plus a one-sentence contract note, 17 decisions, 25 scenarios, ≈ 600 production lines: one soft signal (> 3 phases), no hard limit. One PR.

## Progress

- [x] Phase 1 The tap and the frame's storage — @developer — **Complete**: swift-test 1149/0 failures (baseline 1139 + 10); red 23 failures in the 11 new/edited tests only; S-94b-2 mutant red→green (evidence).
- [x] Phase 2 The count — @developer — **Complete**: swift-test 1167/0 failures (1149 + 18); red 78 failures in the 17 new tests only (S-94b-10 passes on a zero skeleton); 4 mutants red→green (evidence).
- [x] Phase 3 Asking and routing — @developer — **Complete**: swift-test 1176/0 failures (1167 + 9); red 13 failures in 8 of the 9 new tests only (S-94b-19 pins unchanged D-30); wantsWater always-on → S-102/S-103 red, never-on → S-94b-17 red; Dart contract tests 221 passed (evidence).
- [x] Phase 4 The bar, the host, docs and QA — @developer — **Complete**: swift-test 1181/0 failures (1176 + 5); red 29 failures in S-8311 + S-94b-21..24 only (S-94b-25 guards today's state); 5 mutants red→green; Dart contract tests +210; full flutter test local +6021 ~2 -1 (94a A-8 DST only), TZ=UTC +6022 ~2; watch target built for the watch simulator (evidence).
- [ ] Review — @code-reviewer

## Assumption Log

- A-1 (owner, 2026-11-01): Q1-Q3 answered "all defaults" (taps count in the waiting line; light click; drop symbol then number). The VoiceOver labels were not vetoed.
- A-2 (Phase 1): `loggedAt` is `utcIso(...)` per D-22 (fractional `.000Z`); S-94b-1's literal `…09:00:00Z` read as the instant. Tests assert `utcIso(tapAt)` and the parsed instant.
- A-3 (Phase 1): `WatchWaterRecord.fromJson` throws on a missing/mistyped `day`, `glasses` or `appliedTapIds` (the file store then skips the row), instead of defaulting like bests' `entries`: a corrupt frame must not read as a 0 count.
- A-4 (Phase 2; ratified → D-39): the presses are `press(_ change: WatchGlassChange) -> Bool`, not `add()`/`remove()`: S-004 forbids any source `func remove…`. Options: rename, or widen S-004's guard (refused: a guard is not relaxed). Phase 4: S-94b-24 reads `press(.add)`/`press(.remove)`; the model must not declare `func remove…` either.
- A-5 (Phase 3): S-94b-18's late arrival (t0+30) lies past the 20 s cap, so it cannot tell `noteArrival`'s guard from the cap; kept as written (the guard is `WatchSyncProgressTests`'). S-94b-17 also drives the real bridge (first frame = `routinesWater`), beyond the fakes.
- A-6 (Phase 4): the empty-list line gets `.frame(maxHeight: .infinity)` so the bar sits at the bottom with no foods too (D-31 "at the bottom in both branches"); with foods the `ScrollView` already fills.
- A-7 (Phase 4): `### WatchWaterState` sits after the food-list subsection that follows `### WatchNutritionState`, keeping the nutrition topics together. S-94b-25's message cites "plan 95 D-37 (series 94)": D-37 lives in this file.
- A-8 (Phase 4): `docs/state_management.md`'s class table (lists `WatchNutritionState`) owes a `WatchWaterState` → `watch_surface.md` row; not added at Phase 4 — outside the Predicted Files. Resolved after Phase 4: the row was added (review A-8).
- A-9 (review fixes, F2): D-38 said `watch_surface_wrist.md` stays true; it did not (its `replyTypes` list omitted `water_down`). Options: keep the list and add `water_down`, or delete it. Chose delete + pointer to `WatchSyncProgressTests` and S-94b-18 (doc standard 4.2; no second copy to drift).
- A-10 (review fixes, F5, delegated by the owner): `watch_surface.md`'s receipt paragraph now says the Swift wrist does not prune after a receipt (`pruneConfirmed` has no production caller; S-94b-25), agreeing with `watch_reference_data.md`. Options: that, or say the wrist prunes — false in Swift (only the Dart twin's debug screen calls it).
- Executors append here (≤ 3 lines each: decision, options, choice + why); the reviewer ratifies (→ D-x) or reverts (→ remediation).

## Open questions (one batched round; the phases build the defaults)

1. **Q1 — Do water taps the phone has not received count in the "N entries waiting for your phone" line on the watch's Home?** Recommended default: yes, each tap counts as one entry, the same as a food — so three taps made away from the phone read "3 entries waiting for your phone" until the phone has them. Alternative: water taps never show in that line.
2. **Q2 — What does the wrist feel on a tap?** Recommended default: a light click on each + and − that counts; nothing on a press that does nothing (minus at 0). Alternative: no haptic, or the stronger "success" tap a food log gets.
3. **Q3 — What sits between the two buttons?** Recommended default: a small water-drop symbol followed by the number. Alternative: the number alone.

## Feedback

- Review 2026-11-01 (@code-reviewer): REJECT on docs only; code, tests and the watch build are green. Findings: `2026-11-01-95-watch-water-bar-plan.review.md`. Fix checklist (one round, this PR):
  - [x] F1 `docs/state_management/watch_sensors.md:416-418` — delete "Four prunes"/exact surface list → point at S-004 + `testS94b4APruneNamingAnAbsentRowDropsNothingAndWritesNothing`
  - [x] F2 `docs/state_management/watch_surface_wrist.md:257-258` — delete the `replyTypes` enumeration → point at `WatchSyncProgressTests` + `testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply`
  - [x] F3 `docs/state_management/watch_reference_data.md:327-328` — delete "…next sync, not before"
  - [x] F4 `docs/nutrition.md:431-432`, `docs/state_management/watch_surface.md:374` — drop control inventory/position → pointer to S-94b-22
  - [x] F5 conflict `watch_surface.md:757-761` vs `watch_reference_data.md:325-327` (`pruneConfirmed`) — planner/owner picks wording, then fix
  - [x] F7 `docs/state_management.md:50` — add `WatchWaterState`, `WatchWaterLogBridge`
  - Follow-up PR plan (not this PR): F6 render cost of the fold + D-37 refinement; F9; optionally F8.
