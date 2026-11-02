# Evidence — plan 95 (watch water bar, PR 94b)

## Phase 1 — the tap and the frame's storage (2026-11-01, developer)

### Baseline (before any edit)

Every Phase 1 predicted file was clean in `git status` before editing (the shared tree's dirty watch files were `SyncProtocolValidator.swift`, `WatchStartView.swift`, `WatchNutritionWiringSourceTests.swift`, none touched).

`.github/copilot/scripts/macos/gateway.sh swift-test` → exit 0, `Executed 1139 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-210815-10080.log`).

### Tests written first

New `watch/watchos/Tests/WatchSessionEngineTests/WatchWaterStoreTests.swift` (10 tests) plus edits to existing tests:

| Test | Scenario |
|---|---|
| `testS94b1APressIsStoredThenSentShapedLikeTheFixture` | S-94b-1 (ids w-1/w-2, glassChange, loggedAt, fixture keys, two conformant `observations_up` under `nutrition-2026-11-01`, `msg-w-1`/`msg-w-2`, `waterLog`, `nutritionLog` empty, 2 pending) |
| `testS94b1TheWaterLogSurvivesARelaunch` | S-94b-1 (stored tap read back, still owed under `msg-w-1`) |
| `testS94b1TheGlassChangeRawValuesAreTheWireValues` | S-94b-1 / D-22 (`add`/`remove`, kind in `all`, not in `efforts`) |
| `testS94b2APressWhileASessionIsHeldNeverJoinsIt` | S-94b-2 (session `w9` active; emitted id nutrition; not in `observations`, `entries`, snapshot entries) |
| `testS94b3TheEnvelopeCarriesTheUtcDateNotTheLocalOne` | S-94b-3 envelope half (clock 2026-10-31T21:30Z → `nutrition-2026-10-31`) |
| `testS94b3AnExplicitLoggedAtDecidesTheIdAndTheField` | S-94b-3 / D-22 (`loggedAt:` argument decides id and field) |
| `testS94b4OneFrameRowAfterEachPruneOnBothStores` | S-94b-4 store half (F1..F3 + `pruneWater` on both stores → one row each time; relaunch reads glasses 3, ids in order; stores agree) |
| `testS94b4APruneNamingAnAbsentRowDropsNothingAndWritesNothing` | S-94b-4 (`water-missing` → `[]`, file bytes identical; keeping the only row writes nothing; never-written store creates no file) |
| `testS94b4ThePruneTouchesNoOtherKindOfRow` | D-23 (a `bests` row survives; prune reaches disk) |
| `testS94b4AWaterRowAloneMakesTheStoreNotEmptyAndRoundTrips` | D-23 (`isEmpty`, `recordType "water"`, JSON round trip) |

Edited: `WatchNutritionQuickLogTests.testTheKindsTheWristCanEmitAreAClosedSet` gains `"water_glass"`; S-004 allowed set gains `pruneWater` (comment: fifth prune, plan 95 D-23); `pruneWater` forwarders in `StaleReadStore`, `SuspendingStore`, `ContendedWatchSessionStore`.

### Red before implementation

1. Against the unmodified sources: the build fails only on the missing water API (`no member 'pruneWater'`, `cannot find 'WatchWaterRecord'`, `no member 'logWaterGlass'`, `no member 'waterLog'`, `no member 'waterGlass'`, `cannot find 'WatchGlassChange'`, `no member 'water'`/`'waterType'`) — no other error.
2. To read an assertion verdict, the structural surface was added with the behaviour absent (temporary skeletons: `logWaterGlass` threw, `waterLog` returned `[]`, `water_glass` not in `all`, `readAll` dropped water rows, `pruneWater` returned `[]`). Gateway `swift-test` → exit 1, `Executed 1149 tests, with 23 failures (5 unexpected)` (log `.work/gateway/swift-test-20261101-211239-11993.log`). Failing tests — exactly the 11 new/edited ones, nothing else:
   - `testTheKindsTheWristCanEmitAreAClosedSet` (set without `water_glass`)
   - S-94b-1 ×3, S-94b-2, S-94b-3 ×2: `caught error: "malformed("water taps are not stored yet")"` / `XCTAssertTrue failed` (kind not in `all`)
   - S-94b-4 ×4: e.g. `("[]") is not equal to ("["water-msg-water-1793520000000-2-1"]") - S-94b-4 (in-memory) after each apply…`, `XCTAssertFalse failed - S-94b-4 a store holding a frame is not an empty store`
   (An earlier skeleton run crashed on an unguarded `water[0]` in the test; the test was changed to `XCTUnwrap` before this run.)

### Green

Gateway `swift-test` after implementation → exit 0, `Executed 1149 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-211317-12499.log`). 1149 = baseline 1139 + 10 new.

### Mutation — S-94b-2 (session id from `current` first)

- Original line (`WatchSessionEngine.swift` l.1439): `        return try await appendObservation(event, sessionId: WatchNutritionSession.idFor(now))`
- Mutant: `sessionId: current?.sessionId ?? WatchNutritionSession.idFor(now)` (the `logNutrition` rule).
- `swift test --package-path watch/watchos --filter WatchWaterStoreTests` → exit 1, `Executed 10 tests, with 5 failures`, all in `testS94b2APressWhileASessionIsHeldNeverJoinsIt`: `("Optional("w9")") is not equal to ("Optional("nutrition-2026-11-01")") - S-94b-2 a tap carries the day's nutrition id even while a workout runs`; `the workout's observations never hold a tap`; `…entries never hold a tap`; `the session snapshot never carries a tap`.
- Restored; `cmp` against a copy taken before the mutation → identical (sha1 `926d6d09…` before and after).
- Final gateway `swift-test` after the restore → exit 0, `Executed 1149 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-211357-13174.log`).

### Invariants

- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1).
- No `lib/` or Dart `test/` file touched (D-36).
- `pruneConfirmed()` still has no production caller (D-37; enforced in Phase 4).

### Docs

No doc changes in Phase 1 (D-38 docs are Phase 4).

## Phase 2 — the count (2026-11-01, developer)

### Baseline (before any edit)

Both Phase 2 predicted files are new (`WatchWater.swift`, `WatchWaterStateTests.swift`); no tracked file edited. Gateway `swift-test` → exit 0, `Executed 1149 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-211717-15867.log`).

### Tests written first

New `watch/watchos/Tests/WatchSessionEngineTests/WatchWaterStateTests.swift` (18 tests; harness: UTC+3 calendar, `TestClock` 2026-11-01T09:00Z, ids `w-1`…, validator on):

| Test | Scenario |
|---|---|
| `testS94b3TheLocalDayNotTheUtcDayDecidesTheCount` | S-94b-3 count half (wire id `nutrition-2026-10-31`, shown 3) |
| `testS94b4OneFrameRowAfterEachApplyAndARelaunchHoldsTheNewest` | S-94b-4 restore half, InMemory and File (one row after each apply; relaunch shows 3; one `onWaterChanged` per restore) |
| `testS94b4ARestoreHoldsTheGreatestGeneratedAtThenSequence` | D-24 restore rule (tie → later row) |
| `testS94b5TheNewestFrameWinsAndARepeatWritesNothing` | S-94b-5 (a)-(d) |
| `testS94b6AFrameTheWristCannotReadChangesNothing` | S-94b-6 (manifest codes for both invalid fixtures; unvalidated `glasses: "3"`) |
| `testS94b6UnreadableFieldsAreNotAppliedEvenWhenNewer` | D-24 step 2 — added because the scenario's F2-with-`"3"` shares F2's instant and would also be dropped as "unchanged" by a lax reader; here every frame is newer (string/bool/fractional count, no messageId/day/generatedAt, non-string ids) |
| `testS94b7ThePhonesCountPlusTheWristsUncountedTaps` | S-94b-7 |
| `testS94b7TapsFoldInLoggedAtOrderTiesByStoreOrder` | D-25 ordering |
| `testS94b8BeforeTheFirstSync` | S-94b-8 (+ `onWaterChanged` after a stored tap only) |
| `testS94b9AFrameForYesterdayCountsFromZero`, `testS94b9APhoneAheadOfTheWristCountsFromZero` | S-94b-9 (a), (b) |
| `testS94b10MinusAtZeroAndBothDevicesRemovingWhileApart` | S-94b-10 |
| `testS94b11ALostReceiptThenTheAnswerAndItsRepeat` | S-94b-11 state half |
| `testS94b12TheReceiptArrivesTheFrameIsLost` | S-94b-12 |
| `testS94b13BothDevicesTappedWhileApart` | S-94b-13 |
| `testS94b14TheWatchsLocalMidnight` | S-94b-14 |
| `testS94b15TapsPastTheCap` | S-94b-15 (incl. `WatchWaterLimits.tapsPerDay` == schema `appliedTapIds.maxItems`) |
| `testS94b16ARelaunchWithUnsentTaps` | S-94b-16 state half (File store; shown 4; 2 unconfirmed; same `msg-w-1`, `msg-w-2`) |

### Red before implementation

1. Against the unmodified sources: `swift test --filter WatchWaterStateTests` fails to build only on the missing API (`cannot find 'WatchWaterState' in scope`, `cannot find type 'WatchWaterState'`, `cannot find 'WatchWaterLimits'`) — no other error.
2. Temporary skeleton `WatchWater.swift` with the behaviour absent (`tapsPerDay = 0`, `restore` no-op, `applyWaterDown` never applies, `glasses` 0, `canAdd` true, `canRemove` false, presses return false). First skeleton run also showed `testS004NoMutatingOperationExistsAnywhereInTheModule` red: `WatchWater.swift declares a mutating operation` — the skeleton's `func remove()` (→ A-4: presses are `press(_:)`). With `press(_:)`: gateway `swift-test` → exit 1, `Executed 1167 tests, with 78 failures (1 unexpected)` (log `.work/gateway/swift-test-20261101-212026-16927.log`). Failing: exactly 17 of the 18 new tests, nothing else, e.g. `("0") is not equal to ("3") - S-94b-12 a receipt never takes a tap out of the count…`, `("0") is not equal to ("500") - S-94b-15 the wrist's cap is water_down.schema.json's appliedTapIds.maxItems`, `XCTAssertNotNil failed - S-94b-12 w-1 is confirmed` (the skeleton stored no tap). `testS94b10…` passed on the skeleton (every value it asserts is 0/false); its red is not claimed — it guards the clamp against the real fold.

### Green

Gateway `swift-test` → exit 0, `Executed 1167 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-212117-17276.log`). 1167 = 1149 + 18.

### Mutations (hand-edited from a byte copy, run `swift test --package-path watch/watchos --filter WatchWaterStateTests`, copy restored, `cmp` identical; sha1 `1ad69fb7…` before and after)

| Mutant (original line in `WatchWater.swift`) | Result |
|---|---|
| UTC day — l.77 `        self.calendar = calendar` → a UTC Gregorian calendar | exit 1, 18 tests, 7 failures: S-94b-3 `("1") is not equal to ("3")`; S-94b-14 `("4") is not equal to ("0") - …the new day starts at 0`, `("5") is not equal to ("1")`; also S-94b-15 (midnight half) and S-94b-9 (a) |
| Older frame applies (S-94b-5 d) — l.131 `                if generatedAt < current.generatedAt { return .older }` removed | exit 1, 6 failures, all S-94b-5: `(d) older than the 08:20Z held in memory`, `("5") is not equal to ("4") - S-94b-5 (d) base 4`, row id F3 instead of F2b |
| Fold skips confirmed taps (S-94b-12) — l.242 `            guard let raw = record.payload["glassChange"] as? String,` → `guard record.confirmedAt == nil, let raw = …` | exit 1, 1 failure: `("2") is not equal to ("3") - S-94b-12 a receipt never takes a tap out of the count…` |
| No cap (S-94b-15) — l.196 `        todaysTaps(clock()).count < WatchWaterLimits.tapsPerDay` → `true` | exit 1, 7 failures, all S-94b-15: `the cap is reached`, `a plus past the cap stores nothing`, `("503") is not equal to ("501") - S-94b-15 no new observation` |

Final gateway `swift-test` after the restores → exit 0, `Executed 1167 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-212200-17885.log`).

### Invariants

- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1).
- No `lib/` or Dart `test/` file touched (D-36); no tracked file edited in Phase 2.
- Nothing calls `WatchWaterState` yet (Phase 3 wires the orchestrator, Phase 4 the host).

### Docs

No doc changes in Phase 2 (D-38 docs are Phase 4).

## Phase 3 — asking and routing (2026-11-01, developer)

### Baseline (before any edit)

`git diff --stat` on the five tracked Swift predicted files (`WatchConnectivityBridge`, `WatchSyncOrchestrator`, `WatchSyncProgress`, `WatchSessionStartPathsTests`, `WatchConnectivityBridgeTests`) → empty (clean). `watch/sync_protocol/PROTOCOL.md` carries 94a's uncommitted hunks; only one sentence was added inside the water paragraph. Gateway `swift-test` → exit 0, `Executed 1167 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-212512-18794.log`).

### Tests written first

New `watch/watchos/Tests/WatchSessionEngineTests/WatchWaterSyncTests.swift` (9 tests; fixture X, `RecordingTransport` orchestrator with `water:` unless stated):

| Test | Scenario |
|---|---|
| `testS94b11ASyncResendsTheTapThenTheAnswerSettlesIt` | S-94b-11 sync half (re-sent envelope `==` first emission incl. `msg-w-1`; receipt + frame via `orchestrator.receive`; shown 3; repeat not applied, no new row; a receipted tap is not re-sent) |
| `testS94b16ARelaunchedWristResendsItsTapsAndAsksForTheCount` | S-94b-16 sync half (File store; shown 4; `requestedWantsWater` [true]; envelopes `msg-w-1`, `msg-w-2` equal to the first launch's) |
| `testS94b17EverySyncOfAWristWithAWaterStateAsksForTheCount` | S-94b-17 (`sync` + `catchUp` → [true, true]; no water → [false]) |
| `testS94b17TheRequestFrameMatchesTheContractRows` | S-94b-17 (`routinesWater`, `routines`, `wantsWater: false` omitted, both keys) |
| `testS94b17TheBridgeCarriesTheKeyOnlyForAWristThatAsks` | S-94b-17 / I-9 (real bridge: first frame = `routinesWater`; `WatchBridgeHarness` first frame = `routines`, no `wantsWater`) |
| `testS94b18TheFrameIsRoutedToTheWaterState` | S-94b-18 (true + base 3 with water; false + no row without) |
| `testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply` | S-94b-18 (`isActive` t0+4 true, t0+4.6 false; late arrival leaves it false) |
| `testS94b19UnsentTapsCountInTheWaitingLine` | S-94b-19 / D-30 (stored unconfirmed `rest` + 2 taps → "2 entries…"; receipt → "1 entry…"; reachable inside grace → nil) |
| `testS94b20APressWhileThePhoneIsOutOfReach` | S-94b-20 (shown 3 at once; one emission; 1 unconfirmed; sync hands over `msg-w-1`) |

Fakes edited (no assertion edited; the only removed lines are the three old `requestRoutines` signatures): `RecordingTransport` (`WatchSessionStartPathsTests.swift`), `WireLog`, `GatedTransport`, `GatedRequestTransport` (`WatchConnectivityBridgeTests.swift`) accept `wantsWater` and record it in `requestedWantsWater`.

### Red before implementation

1. Against the unmodified sources: `swift build --build-tests` fails only on the missing API — `type 'RecordingTransport'/'WireLog'/'GatedTransport'/'GatedRequestTransport' does not conform to protocol 'WatchSyncTransport'`, `extra argument 'wantsWater' in call` (×3), `extra argument 'water' in call` (×2). No other error.
2. Structural surface with the behaviour absent (protocol + bridge parameter, `routinesFrame(wantsWater:)` ignoring it, orchestrator storing `water` but passing `wantsWater: false`, no `water_down` route, `replyTypes` unchanged): gateway `swift-test` → exit 1, `Executed 1176 tests, with 13 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-212706-19554.log`). Failing: exactly 8 of the 9 new tests, nothing else, e.g. `("[false]") is not equal to ("[true]") - S-94b-11 the sync asks for the count`, `XCTAssertTrue failed - S-94b-18 a wrist with a water state applies the frame`, `("0") is not equal to ("3") - S-94b-18 base 3 from the fixture`, `XCTAssertTrue failed - S-94b-18 the water frame is the newest reply, so the sync is still running`. `testS94b19…` passed on the skeleton: it pins behaviour D-30 keeps unchanged (`deriveSyncNotice` is not edited); its red is not claimed.

### Green

Gateway `swift-test` → exit 0, `Executed 1176 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-212743-20002.log`). 1176 = 1167 + 9. Verify-only, unedited and passing in that log: `testS102FirstSyncAsksForRoutinesWithNoSince`, `testS103LaterSyncCarriesSince`, both `testS87c16…`, `testS3820…`; suites `WatchSyncProgressTests` (10/0), `WatchSyncNoticeTests` (9/0).

### Mutations (hand-edited, `swift test --package-path watch/watchos --filter "WatchConnectivityBridgeTests|WatchWaterSyncTests"`, restored from a byte copy, `cmp` identical; sha1 `402f8d5b…` before and after)

Original line (`WatchSyncOrchestrator.swift` l.130): `            wantsWater: water != nil`

| Mutant | Result |
|---|---|
| Always on — `wantsWater: true` | 40 tests, 5 failures: `testS102FirstSyncAsksForRoutinesWithNoSince` and `testS103LaterSyncCarriesSince` (first sent frame ≠ the `routines`/`routinesSince` row), plus S-94b-17 ×3 (`("[true]") is not equal to ("[false]")`, `XCTAssertNil failed: "true" - S-94b-17 a wrist without a water state sends no wantsWater`) |
| Never on — `wantsWater: false` | 40 tests, 5 failures, all in `WatchWaterSyncTests`: S-94b-17 `("[false, false]") is not equal to ("[true, true]")` and the bridge frame ≠ `routinesWater`; S-94b-11, S-94b-16, S-94b-20 `("[false]") is not equal to ("[true]")`; bridge tests 31/0 |

Final gateway `swift-test` after the restore → exit 0, `Executed 1176 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-212821-20649.log`).

### Dart contract checks

`gateway.sh test test/sync_protocol_fixtures_test.dart test/watch_transport_test.dart` → `+221: All tests passed!` (log `.work/gateway/test-20261101-212828-20791.log`). Contract JSON and schemas not edited by this phase.

### Invariants

- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1).
- No `lib/` or Dart `test/` file touched (D-36).

### Docs

`watch/sync_protocol/PROTOCOL.md`: one sentence in the water paragraph (a receipt does not take a tap out of the count, the frame's list does; a wrist emits no tap once its own taps of its local day reach `appliedTapIds`' `maxItems`). No version row (no wire change). `docs/` edits are Phase 4 (D-38).

## Phase 4 — the bar, the host, docs and QA (2026-11-01, developer)

### Baseline (before any edit)

`git status` on the Phase 4 predicted files: `ContentView.swift`, `WatchNutritionView.swift`, `WatchNutritionWiringSourceTests.swift`, `docs/watch-app-qa-wrist-logging.md` clean (the step-1 Home change is committed, 4d6baa41); `WatchWater.swift`, `WatchWaterStateTests.swift` untracked (Phases 2-3); `docs/nutrition.md`, `docs/state_management/watch_surface.md`, `docs/state_management/watch_reference_data.md` carry 94a's uncommitted hunks — only new lines were added beside them. Gateway `swift-test` → exit 0, `Executed 1176 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-220057-23399.log`).

### Tests written first

| Test | Scenario |
|---|---|
| `WatchWaterStateTests.testS94b21TheModel` | S-94b-21 (0 / `canRemove` false / "0 glasses"; `press(.add)` true → 1, "1 glass", nudge on the main queue; frame 09:01Z → 3, "3 glasses", nudge on the main queue; `WatchWaterCopy` = D-33) |
| `WatchWaterBarSourceTests.testS94b22TheBarIsOnTheListOnlyEmptyListIncluded` | S-94b-22 (once in the list's body, after the whole if/else, not in `ScrollView {`; none in `WatchFoodPortionView` or any other engine/app file; minus → drop → count → plus) |
| `WatchWaterBarSourceTests.testS94b23TheHostOwnsOneWaterStateAndOneModel` | S-94b-23 (one `WatchWaterState(`/`WatchWaterModel(`, in `init() {`; `water: water`; `await water.restore()` the line right after `await nutrition.restore()`; the sheet call; no water in the `WatchMenuView` call) |
| `WatchWaterBarSourceTests.testS94b24HapticVoiceOverMinuteRefreshAndFit` | S-94b-24 (each `.play(.click)` directly under `if await model.press(.add/.remove)`; labels from `WatchWaterCopy`; middle one element with `.accessibilityValue(model.spokenCount)`; `TimelineView(.everyMinute)`; count chain `.lineLimit(1)` + `.minimumScaleFactor(`; `.disabled(!model.canRemove)` on minus, `.disabled(!model.canAdd)` on plus; icon-only, bordered) |
| `WatchWaterBarSourceTests.testS94b25TapsAreNeverPruned` | S-94b-25 (no `pruneConfirmed(` outside its declarations and the engine's delegation; message names D-37) |
| `WatchNutritionWiringSourceTests.testS8311TheHostOwnsTheOneNutritionModel` | needle only → `WatchNutritionView(model: host.nutritionModel, water: host.waterModel)` (D-35) |

### Red before implementation

1. Against the unmodified sources: `swift build --build-tests` fails only on the missing API — `cannot find 'WatchWaterModel' in scope`, `cannot find 'WatchWaterCopy' in scope`, `cannot infer contextual base in reference to member 'add'` (the press on the missing model). No other error.
2. Temporary skeleton appended to `WatchWater.swift` (model returning 0/false/"" and never forwarding, copy all ""; removed afterwards, file restored from a byte copy, `cmp` identical): gateway `swift-test` → exit 1, `Executed 1181 tests, with 29 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-220229-23961.log`). Failing: exactly S-8311 and S-94b-21, -22, -23, -24, nothing else, e.g. `XCTAssertTrue failed - S-8311 the sheet presents the surface over the host's one model`; `("0") is not equal to ("1") - S-94b-22 the list's body draws the water bar exactly once`; `("0") is not equal to ("1") - S-94b-23 one water state`; `XCTUnwrap failed … - the water bar is declared beside the Nutrition list (D-31)`; `("") is not equal to ("0 glasses") - S-94b-21 VoiceOver reads 0 glasses`; `Asynchronous wait failed … "S-94b-21 a stored tap redraws on the main queue"`. `testS94b25…` passed: it guards today's state (no caller exists); its red is shown by mutation M4 below.

### Green

Gateway `swift-test` → exit 0, `Executed 1181 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-220346-24777.log`). 1181 = 1176 + 5. No new warning in `WatchWater.swift`, `WatchNutritionView.swift` or the new tests.

### Mutations (hand-edited from byte copies, `swift test --package-path watch/watchos --filter …`, restored, `cmp` identical; sha1 before and after: `WatchNutritionView.swift` 431ad5ed…, `WatchWater.swift` e4afb65c…, `ContentView.swift` f6e7f601…)

| Mutant | Result |
|---|---|
| M1 `WatchWater.swift`: `            DispatchQueue.main.async { self?.objectWillChange.send() }` → `            self?.objectWillChange.send()` | S-94b-21 red: `the nudge after a tap is on the main queue`, `the nudge after a frame is on the main queue` |
| M2 `WatchNutritionView.swift`: `if await model.press(.add) { …play(.click) }` → `await model.press(.add)` then an unguarded `play(.click)` | S-94b-24 red: `the click plays only when the press stored a tap`, `("0") is not equal to ("1")` (4 tests, 2 failures) |
| M3 `WatchNutritionView.swift`: `            WatchWaterBar(model: water)` moved inside the `ScrollView`'s `VStack` | S-94b-22 red: `("14") is not greater than ("17") - …follows the whole empty/list branch`, `the bar is pinned, not scrolled away` |
| M4 `ContentView.swift`: `        _ = await engine.pruneConfirmed()` added after `        await water.restore()` | S-94b-25 red: `("["ContentView.swift: _ = await engine.pruneConfirmed()"]") is not equal to ("[]") - S-94b-25 plan 95 D-37 …` |
| M5 `ContentView.swift`: `        await water.restore()` moved above `        await nutrition.restore()` | S-94b-23 red: `("Optional(3)") is not equal to ("Optional(5)") - …restored right after the food list` |

### Done Criteria runs

- Gateway `swift-test` (final, after the docs) → exit 0, `Executed 1181 tests, with 0 failures (0 unexpected)` (log `.work/gateway/swift-test-20261101-220813-27362.log`); `WatchWaterBarSourceTests` 4/0, `WatchNutritionWiringSourceTests` 6/0, `WatchAccessibilitySourceTests` 6/0, `WatchSyncNoticeTests` 9/0, `WatchSyncProgressTests` 10/0.
- `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart test/sync_protocol_fixtures_test.dart` → `+210: All tests passed!` (log `.work/gateway/test-20261101-220819-27513.log`).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1).
- Full `flutter test` (900 s cap), local time → exit 1, `+6021 ~2 -1`; the one failure is the known 94a A-8 DST test `state_test.dart: NutritionState saveNutritionTargetForDate does NOT modify past dates when forward-propagating`. With `TZ=UTC` → exit 0, `+6022 ~2: All tests passed!`. No Dart file touched (D-36).

### watchOS build

`xcodebuild build -project ios/Runner.xcodeproj -target "OmniTrain Watch App" -sdk watchsimulator -configuration Debug SYMROOT/OBJROOT=<scratch> CODE_SIGNING_ALLOWED=NO` (600 s cap) → `** BUILD SUCCEEDED **`, exit 0; the log shows `SwiftCompile` of `WatchNutritionView.swift`, `WatchWater.swift` (target `WatchSessionEngine`) and `ContentView.swift` (target `OmniTrain Watch App`) for arm64 and x86_64, with no warning in them. No simulator booted, nothing installed, nothing written into the repository. (The scheme form, `-scheme "OmniTrain Watch App" -destination 'generic/platform=watchOS Simulator'`, also builds `Runner` and stopped at `Module 'app_settings' not found` in `GeneratedPluginRegistrant.m` — the Flutter app without its pods, unrelated to the watch.) The governor's own build before review still stands.

### Docs (sizes in bytes; band 52,429, ceiling 65,536)

- `docs/state_management/watch_surface.md` 50,865 → 51,878 (+1,013): `### WatchWaterState` placed after the food-list subsection that follows `### WatchNutritionState` (A-7); "the water count to the water state" in the orchestrator's routing sentence.
- `docs/state_management/watch_reference_data.md` 21,266 → 22,641 (+1,375): `### The wrist holds one water count`; `requestRoutines(since:exercisesVersion:holdsBests:)` → `…:wantsWater:)` (made false by Phase 3).
- `docs/nutrition.md` 37,910 → 38,464 (+554): appended to "Glasses tapped on the watch" (the wrist's count, offline taps, a phone tap at the watch's next sync).
- `docs/watch-app-qa-wrist-logging.md` 30,053 → 31,038: step 40 (a)-(f), owner.
- `docs/state_management/watch_surface_wrist.md` 52,259: no update required (nothing in it became false; plan D-38).
- `docs/navigation_and_screens.md`, `docs/widget_catalog.md`: no update required (Flutter-only; no phone screen, route or widget changed). `docs/state_management.md`: NOT edited (outside the Predicted Files) though its class table lists `WatchNutritionState` → a `WatchWaterState` row pointing at `watch_surface.md` is owed (A-8).
- `find docs -size +65535c` lists only pre-existing files under `docs/plans/` (not indexed; `docs_indexing_contract_test` green).

### Residue

`grep -rln "water_down\|wantsWater\|water_glass\|waterGlass\|WatchWater" watch/watchos "ios/OmniTrain Watch App" docs watch/sync_protocol` (excluding `watch/watchos/.build/`, build output) → plan 95's predicted files of Phases 1-4, plus 94a's own surfaces (`SyncProtocolValidator.swift`, the fixtures/schemas/manifest, `docs/constants_reference.md`, `data_models.md`, `db_integration.md`, `state_management.md`, `state_management/nutrition_state.md`, the plan-94 folder). Nothing else.

## Review fixes (2026-11-01, docs only)

Findings F1-F5 and F7 from `2026-11-01-95-watch-water-bar-plan.review.md`. No source or test file changed.

| # | File (line now) | Change |
|---|---|---|
| F1 | `docs/state_management/watch_sensors.md:416-419, 428-430` | "Four prunes … exactly `append`, … `pruneBests`" → "Every prune is gated …; the allowed set in `WatchSessionEngineTests.testS004NoMutatingOperationExistsAnywhereInTheModule` is the list"; water prune pointer `WatchWaterStoreTests.testS94b4APruneNamingAnAbsentRowDropsNothingAndWritesNothing` added to the prune pointers |
| F2 | `docs/state_management/watch_surface_wrist.md:257-258` | `replyTypes` enumeration deleted → `WatchSyncProgressTests`, `WatchWaterSyncTests.testS94b18AWaterFrameExtendsARunningSyncLikeAnyReply` (A-9) |
| F3 | `docs/state_management/watch_reference_data.md:327-328` | sentence "A glass tapped on the phone reaches the wrist at the wrist's next sync, not before." deleted |
| F4 | `docs/nutrition.md:431-432` | "the same minus/count/plus bar under its food list" → "carries the water count (`WatchWaterBarSourceTests.testS94b22TheBarIsOnTheListOnlyEmptyListIncluded`)" |
| F4 | `docs/state_management/watch_surface.md:373-376` | "whose bar sits under the Nutrition list (`WatchWaterBarSourceTests`)" → host ownership pointer `…testS94b23TheHostOwnsOneWaterStateAndOneModel` + "the watch's Nutrition screen carries the water count (`…testS94b22…`)" |
| F5 | `docs/state_management/watch_surface.md:759-764` | "and `pruneConfirmed`, which is the only way …" → "The Swift wrist does not prune after a receipt: `pruneConfirmed` … has no production caller there (`WatchWaterBarSourceTests.testS94b25TapsAreNeverPruned`). The receipt, and that a confirmed row is then droppable, are exercised by …" (A-10; agrees with `watch_reference_data.md` "The wrist holds one water count") |
| F7 | `docs/state_management.md:50` (CRLF) | `WatchWaterState` and `WatchWaterLogBridge` added to the Watch Surface row; edited in place byte-wise, CRLF kept (`file`: "with CRLF line terminators"); `git diff --numstat` for the file 2/0 before → 3/1 after (one line) |

Plan: D-39 added (A-4 promoted), A-4 marked ratified, A-8 text corrected (row now exists), A-9/A-10 logged, Feedback F1-F5/F7 ticked.

Sizes after: `watch_sensors.md` 31,559 B; `watch_surface_wrist.md` 52,261 B; `watch_reference_data.md` 22,557 B; `nutrition.md` 38,508 B; `watch_surface.md` 52,167 B; `state_management.md` 11,066 B. `find docs -name '*.md' -size +65535c -not -path 'docs/plans/*'` → none.

Checks (observed):
- `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` → `+54: All tests passed!`
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty (exit 1)
- `swift test --package-path watch/watchos` (900 s cap) → exit 0, `Executed 1181 tests, with 0 failures (0 unexpected)`
