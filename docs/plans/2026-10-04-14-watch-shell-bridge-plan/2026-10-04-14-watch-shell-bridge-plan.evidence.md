# Evidence — watch shell bridge (Iteration 1)

Executors write run output here; findings go in `...review.md`. Never into the plan.

## Phase 1 — the watch icon (@developer)

Guard: `test/watch_app_icon_test.dart` — S-101 (D-14). Plain `test()`; reads the
PNG IHDR directly (width bytes 16–19, height 20–23, colour type 25); no image
package. The phone icon's colour type is named in every failure message.

### RED — before the `Contents.json` edit

Command: `.github/copilot/scripts/macos/gateway.sh test test/watch_app_icon_test.dart`

```
00:00 +0: loading /Users/irinakutsenko/Developer/omnitrain/test/watch_app_icon_test.dart
00:00 +0: S-101 the watch icon slot names the flattened phone icon and it is opaque
00:00 +0 -1: S-101 the watch icon slot names the flattened phone icon and it is opaque [E]
  Expected: not null
    Actual: <null>
  the 1024 watchos slot must name a file (phone icon colour type: 6)
  
  package:matcher                                     expect
  package:flutter_test/src/widget_tester.dart 473:18  expect
  test/watch_app_icon_test.dart 61:5                  main.<fn>
  
00:00 +0 -1: Some tests failed.
```

The failure is the missing `filename` (the plan's predicted red), and it already
carries the phone icon's colour type (`6`, RGBA).

### GREEN — after the `Contents.json` edit

Edit: set `"filename" : "Icon-App-1024x1024@1x.png"` in the 1024 `watchos` slot
of `ios/OmniTrain Watch App/Assets.xcassets/AppIcon.appiconset/Contents.json`;
nothing else in that file changed.

Command: `.github/copilot/scripts/macos/gateway.sh test test/watch_app_icon_test.dart`

```
00:00 +0: loading /Users/irinakutsenko/Developer/omnitrain/test/watch_app_icon_test.dart
00:00 +0: S-101 the watch icon slot names the flattened phone icon and it is opaque
00:00 +1: All tests passed!
```

The flattened copy at
`ios/OmniTrain Watch App/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
is 1024×1024 with a colour type other than 6 (no alpha channel), so the guard
passes.

### Done Criteria

`.github/copilot/scripts/macos/gateway.sh lint` — exit 1 (pre-existing info
notices), final line:

```
196 issues found. (ran in 3.3s)
```

Baseline is 196 issues / 0 errors; the count is unchanged, so the new test file
contributes none and no error was introduced.

`.github/copilot/scripts/macos/gateway.sh test` — final line:

```
01:35 +3875 ~1: All tests passed!
```

Baseline is `+3874 ~1`; the `+1` is `test/watch_app_icon_test.dart` (S-101).
The `~1` is the pre-existing skip, unchanged. No existing test went red.

## Phase 2 — the bridge in the package (@developer)

Scope: items 1–8. The Swift half cannot be executed here — `swift test` is the
governor's. Every Swift test below therefore carries the mutation that turns it
red, named as an exact line in a source file, instead of a run result.

### Item 4/5 — the contract block and the Dart agreement (S-102)

`watch/contract/watch_start_paths_contract.json` gained `transportRequests` (the
three D-2 frames) and a sentence in `description` saying what it pins.
`test/watch_transport_test.dart` gained the group
`S-102 the request frames match the contract`.

RED — before the contract block existed. Command:
`.github/copilot/scripts/macos/gateway.sh test test/watch_transport_test.dart`

```
00:00 +22 -1: S-102 the request frames match the contract S-102 the three frames equal the contract transportRequests [E]
  type 'Null' is not a subtype of type 'Map<dynamic, dynamic>' in type cast
  test/watch_transport_test.dart 729:12  _asObject
  test/watch_transport_test.dart 727:26  main.<fn>.<fn>
00:00 +22 -1: Some tests failed.
```

The failure is the missing `transportRequests` key, not a harness error.

GREEN — after the block was added. Same command:

```
00:00 +22: S-112 the fixtures the phone sends carry no null S-112 exercise_push has no JSON null anywhere
00:00 +23: All tests passed!
```

### Item 6 — the fixtures the phone sends carry no null (S-112)

The three fixtures the phone sends with `sendMessage` —
`fixtures/valid/routines_down.json`, `.../preferences_down.json`,
`.../exercise_push.json` — were walked for JSON nulls. None contains one, so
item 6's STOP condition does not apply and there is nothing to record under Open
questions.

Mutation proof that the walk can fail. Original line in
`test/watch_transport_test.dart`:

```dart
    for (final name in ['routines_down', 'preferences_down', 'exercise_push']) {
```

Mutant: `['routines_down', 'preferences_down', 'exercise_push', 'foods_down']`.
Command: `.github/copilot/scripts/macos/gateway.sh test test/watch_transport_test.dart`

```
00:00 +3 -1: S-112 the fixtures the phone sends carry no null S-112 foods_down has no JSON null anywhere [E]
  Expected: empty
    Actual: ['payload.foods[1].categoryId']
00:00 +3 -1: Some tests failed.
```

The line was restored exactly and the file re-run green (`+23: All tests
passed!`). `foods_down.json` is not one of the three fixtures the phone sends
with `sendMessage`, so its null is out of scope for this phase.

### Item 1/2/3 — the seam, the bridge and the plist check

`watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift` holds
`WatchConnectivitySession` (item 1), `WatchTransportRequest` and
`WatchConnectivityBridge` (item 2).
`watch/watchos/Sources/WatchSessionEngine/PropertyListFrames.swift` holds
`PropertyListFrames.plistSafe` and `PropertyListFrameError` (item 3).

Neither file imports `WatchConnectivity` and neither wraps anything in
`#if os(watchOS)`, so both compile on macOS; no package dependency was added.
The real `WCSession` conformance is Phase 3's, in the app target.

### Item 7/8 — the bridge tests

`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`
and `.../FakeWatchConnectivitySession.swift`. The fixtures go through
`Harness.validator()`, the same validator the protocol fixtures use.

| Test | Mutation that turns it red |
|---|---|
| `testS102FirstSyncAsksForRoutinesWithNoSince` | `WatchConnectivityBridge.swift`, in `WatchTransportRequest.routinesFrame`: `var frame: [String: Any] = ["request": routines]` → `["request": routines, "since": NSNull()]` |
| `testS103LaterSyncCarriesSince` | `WatchConnectivityBridge.swift`, in `WatchTransportRequest.routinesFrame`: `if let since { frame["since"] = utcIso(since) }` → `if let since { frame["since"] = since }` (a `Date` is not the contract's string) |
| `testS104SyncWithNoSessionAsksForASnapshot` | `WatchConnectivityBridge.swift`, in `WatchConnectivityBridge.requestSnapshot`: `await send(WatchTransportRequest.snapshotFrame())` → `await send(WatchTransportRequest.routinesFrame(since: nil))` |
| `testS105SyncFillsTheRoutineListAndThePreference` | `WatchConnectivityBridge.swift`, in `WatchConnectivityBridge.deliver`: `try await inbound(frame)` → `return` (the arrival is dropped, so nothing is applied) |
| `testS106APhoneWithNoRoutinesStillSendsItsPreference` | `WatchConnectivityBridge.swift`, in `WatchConnectivityBridge.deliver`: `try await inbound(frame)` → `return` (the preference never reaches `WatchPhonePreferences`, so `current` stays nil) |
| `testS107ASyncedRoutineStartsOnTheWrist` | `WatchConnectivityBridge.swift`, in `WatchConnectivityBridge.deliver`: `try await inbound(frame)` → `return` (no routine is stored, so `startFromRoutine` throws) |
| `testS112TheFramesTheWristSendsSurviveThePlistRoundTrip` | `PropertyListFrames.swift`, in `PropertyListFrames.any`: `case is NSNumber: return value` → `case is NSNumber: return (value as! NSNumber).doubleValue` (D-5: the coercion the check must not do) |
| `testS113AFrameThatCannotBeRepresentedIsReported` | `PropertyListFrames.swift`, in `PropertyListFrames.any`: `default: throw PropertyListFrameError.unsupportedValue(path)` → `default: return value` (the refusal becomes a pass-through) |
| `testASendThePlatformRefusesIsReported` | `WatchConnectivityBridge.swift`, in `WatchConnectivityBridge.send`: the second `catch { report(error) }` → `catch { }` (a refused send is swallowed) |
| `testReachabilityIsReadFromTheSeam` | `WatchConnectivityBridge.swift`, in `WatchConnectivityBridge.init`: `session.onReachabilityChange { [weak self] reachable in self?.reachabilityHandler?(reachable) }` → `session.onReachabilityChange { _ in }` |
| `testBridgeSendsNothingUntilAsked` | `WatchConnectivityBridge.swift`, in `WatchConnectivityBridge.deliver`: `try await inbound(frame)` → `await send(frame)` (an arrival is answered, which is the unsolicited send I-1 forbids) |

### Done Criteria

`.github/copilot/scripts/macos/gateway.sh test test/watch_transport_test.dart` —
final line:

```
00:00 +23: All tests passed!
```

`.github/copilot/scripts/macos/gateway.sh test` — final line:

```
01:32 +3881 ~1: All tests passed!
```

Baseline is `+3875 ~1`; the `+6` are the six new tests in
`test/watch_transport_test.dart` (three S-102, three S-112). The `~1` is the
pre-existing skip, unchanged. No existing test went red.

`.github/copilot/scripts/macos/gateway.sh lint` — final line:

```
196 issues found. (ran in 3.0s)
```

Baseline is 196 issues / 0 errors; the count is unchanged and
`grep -c "error •"` returns `0`.

`swift test` — not run here; the governor runs it. Baseline is 242 tests / 0
failures.

## Fix round 1 — two Swift compile errors (@developer)

`swift test` reported exactly two errors, both in `WatchConnectivityBridgeTests.swift`: `harness.session.sent.removeAll()` (a `private(set)` setter, now the fake's new `clearSent()`) and `XCTUnwrap(harness.store.readAll().timers.last)` (an `async` call in an autoclosure, now `let all = await harness.store.readAll()` first); a sweep of `watch/watchos` found no other occurrence of either mistake.

## Fix round 2 — one test bug and the D-5 coercion hazard (@developer)

`swift test` after fix round 1: compiles, 253 tests, 1 failure — `testS112TheFramesTheWristSendsSurviveThePlistRoundTrip`, `malformed("expected an object, found ...")` from the `bridgeObject` helper.

**F1 — the S-112 test's array-vs-object mistake.** The `events` array of
dictionaries was wrapped in `bridgeObject` (dictionary) instead of
`bridgeObjects`. Fixed:

```
let events = try bridgeObjects(try bridgeObject(try bridgeObject(observation["payload"])["events"]))
->
let events = try bridgeObjects(try bridgeObject(observation["payload"])["events"])
```

The test's other two nested lookups were checked and are correct as written:
`snapshotPayload["exercises"]` is an array of objects (already `bridgeObjects`),
and `timers[...]` / `timers[WatchTimerKind.rest]` are dictionaries (already
`bridgeObject`).

**F2 — the plist check no longer turns an integer into a `Bool`.**
`PropertyListFrames.any` tested `case let flag as Bool` before `case let number
as NSNumber`, so an `NSNumber` wrapping `0` or `1` (the JSONSerialization shape
of `sequence`, `exerciseIndex`, `accumulatedPauseMs: 0`) was returned as a
`Bool`. Now the switch is `String`, then `case is NSNumber: return value`, then
`Date`, `[Any]`, `[String: Any]` and the refusing `default`. Returning `value`
rather than the bridged binding keeps an integer an integer and a `Bool` a
`Bool`; a native `Bool` and `Int` still match `as NSNumber` on Apple platforms.
The redundant `Bool` case is deleted and the comment that claimed a `Bool` must
be recognised first is replaced with the opposite hazard.

**F3 — the test for F2.** `testD5NumbersAreNeverCoerced` in
`WatchConnectivityBridgeTests.swift`: a frame holding `NSNumber(value: 1)`,
`NSNumber(value: 0)`, a native `Int` 5, a native `Double` 5.5, a native `true`,
and the same set nested inside an array and a sub-dictionary, run through
`PropertyListFrames.plistSafe`. It asserts with `String(cString:
number.objCType)` that the integer-valued results are not `"c"` (the `Bool` type
code), that the native `true` is `"c"`, and that the `Double` is `"d"`.

| Test | Mutation that turns it red |
|---|---|
| `testD5NumbersAreNeverCoerced` | `PropertyListFrames.swift`, in `PropertyListFrames.any`: put `case let flag as Bool: return flag` back above the `NSNumber` case (`NSNumber(value: 1)` then reports `"c"`) |

Both Swift edits were re-read as the compiler would: `bridgeObjects` takes an
`Any?` and returns `[[String: Any]]` so the fixed line type-checks; the new test
casts the list to `[Any]` and the sub-dictionary to `[String: Any]` explicitly;
every `try` is on a `let` outside an `XCTAssert` argument and the test is
synchronous, so no `await` sits in an autoclosure.

Dart is untouched. `gateway.sh test test/watch_transport_test.dart` — final
line:

```
00:00 +23: All tests passed!
```

---

# Phase 3 — the shell gets a radio (@developer)

## What changed

- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` (+63):
  `WatchStartSurfaceCopy.unreachableLabel`, the three-state
  `WatchPhoneReachability` with its `observed(reachable:)` mapping, and the pure
  `WatchPhoneStatus` value (`sentence`, `offersSync`) that D-8 and D-9 are.
- `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` (+35): a
  `WatchPhoneUnreachableHint` and a `phoneReachability` init parameter
  (defaulted to `.unknown`, so no existing caller changes meaning). The sync
  button is now gated on `onRequestSync` *and* `phoneStatus.offersSync`; the
  sentence appears only when `phoneStatus.sentence != nil`, and
  `WatchNoAutomaticSyncHint()` stays unconditional.
- `ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift` (new, 6759 bytes):
  the real `WCSession` conformance. `RadioError.notActivated` when the session
  is not activated and `.phoneNotReachable` when it is not reachable; otherwise
  `sendMessage(_:replyHandler:errorHandler:)`. `activationDidCompleteWith`
  reports the initial reachability because a session can already be reachable
  with no change callback, and `sessionReachabilityDidChange` reports the rest.
  `onReachabilityChange` re-asks an already-activated session for its answer, so
  a report that landed before the host subscribed is not lost for good — it is
  the one report no later sync recovers. No iOS-only
  `sessionDidBecomeInactive`/`sessionDidDeactivate`.
- `ios/OmniTrain Watch App/ContentView.swift` (+75/-17): `WatchAppHost` builds
  the store → engine → paths → preferences → radio → bridge → orchestrator, and
  subscribes to arrivals and reachability. `restore()` now also restores the
  preferences; `requestSync()` runs `orchestrator.sync(reconnect: paths.syncedAt
  != nil)`. `ContentView` passes `onRequestSync` and `phoneReachability`.
- `ios/OmniTrain Watch App/OmniTrainApp.swift` (one comment word).

## The two new Swift tests, and the mutations that turn them red

`swift test` is the governor's to run, so neither test was executed here. Each
row names a mutation of the code under test, quoted from the line as it now
stands so it can be restored exactly, and the assertion in that test that the
mutation fails.

`testS111TheSurfaceSaysUnreachableOnlyAfterObservingIt`
(`WatchConnectivityBridgeTests.swift`):

| # | Mutation | Assertion that fails |
|---|---|---|
| a | `WatchStartPaths.swift`, `WatchPhoneStatus.sentence`: `case .unknown, .reachable:` → `case .unknown, .reachable, .unreachable:` and delete the `case .unreachable:` arm, so nothing is ever said | `XCTAssertEqual(WatchPhoneStatus(reachability: .unreachable).sentence, WatchStartSurfaceCopy.unreachableLabel)` |
| b | the same switch the other way: `case .unknown, .reachable:` → `case .reachable:`, and `case .unreachable:` → `case .unknown, .unreachable:` (the flag-starting-false bug D-8 names) | the test's first line, `XCTAssertNil(WatchPhoneStatus(reachability: .unknown).sentence)` |
| c | `public var offersSync: Bool { true }` → `{ reachability != .unreachable }` | the third iteration of the `for reachability in [.unknown, .reachable, .unreachable]` loop |
| d | `WatchPhoneReachability.observed(reachable:)`: `reachable ? .reachable : .unreachable` → `return .reachable` | `XCTAssertEqual(WatchPhoneReachability.observed(reachable: false), .unreachable)` |
| e | `public static let unreachableLabel = "Phone not reachable"` → `= "Phone unreachable"` | `XCTAssertEqual(WatchStartSurfaceCopy.unreachableLabel, "Phone not reachable")` |
| f | `WatchStartView.swift`, `WatchPhoneUnreachableHint.label`: `= WatchStartSurfaceCopy.unreachableLabel` → `= "Phone not reachable"`, so the view stops going through the constant | `XCTAssertTrue(view.contains("WatchStartSurfaceCopy.unreachableLabel"))` |
| g | delete `WatchNoAutomaticSyncHint()` from `WatchStartView.body` (it is the only occurrence of that text in the file), so the sentence would replace the no-auto-sync line instead of joining it | `XCTAssertTrue(view.contains("WatchNoAutomaticSyncHint()"))` |

`testTheContractLabelsMatchWatchStartSurfaceCopy`
(`WatchConnectivityBridgeTests.swift`):

| # | Mutation | Assertion that fails |
|---|---|---|
| h | `watch/contract/watch_start_paths_contract.json`, `startSurface.syncLabel`: `"Sync routines"` → `"Sync routines now"` | `XCTAssertEqual(surface["syncLabel"] as? String, WatchStartSurfaceCopy.syncLabel)` |
| i | the same file, `startSurface.noAutoSyncLabel` → any other wording | `XCTAssertEqual(surface["noAutoSyncLabel"] as? String, WatchStartSurfaceCopy.noAutoSyncLabel)` |
| j | add `"unreachableLabel": "Phone not reachable"` to the contract's `startSurface` block | `XCTAssertNil(surface["unreachableLabel"])` — the assertion that pins the label's deliberate absence |
| k | the package side of (h): `WatchStartSurfaceCopy.syncLabel = "Sync routines"` → `= "Sync now"` | the same `syncLabel` assertion, reached from the other end |

Mutations (h)–(j) were **not** applied and restored: the contract file is a
tracked Phase 2 artifact and (j) in particular would change a value the Wear OS
suite reads. They are stated as mutations, not as a performed experiment.

## Gateway checks (the Dart suites are the only ones this agent may run)

```
$ .github/copilot/scripts/macos/gateway.sh test
01:43 +3881 ~1: All tests passed!
```

```
$ .github/copilot/scripts/macos/gateway.sh lint
196 issues found. (ran in 3.1s)
```

Both match the Phase 2 baselines exactly (`+3881 ~1`; 196 issues, 0 errors).
Phase 3 changes no Dart, so no movement is the expected result — but it is a
read count, not an inference: the run finished with exit code 0 and the final
line above is its last line.

## Not verified here

- `swift test` (the package's 254-test suite, which owns the two tests above).
  The governor runs it. Nothing in this phase claims a Swift result.
- `xcodebuild` against the watch app target, so the new
  `OmniTrainWatchConnectivity.swift` is compiled only when the governor builds
  it. The file sits in the target's file-system-synchronized group beside
  `ContentView.swift`, so it needs no `project.pbxproj` entry.

## Fix round 3 — the watch target's `onReceive` witness (@developer)

`receiveHandler` and `onReceive` in `OmniTrainWatchConnectivity.swift` are now typed `@escaping @concurrent ([String: Any]) async -> Void`, matching the package's requirement; the governor's post-fix log `.work/watch-bridge/xcodebuild-p3b.log` (the same `xcodebuild -scheme "OmniTrain Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' build`, same `-swift-version 5 -default-isolation=MainActor NonisolatedNonsendingByDefault` flags) recompiles all three watch-app Swift files for arm64 and x86_64 and ends `** BUILD SUCCEEDED **` with 0 `error:` lines and no warning for any watch-app file.

# Phase 4 — pushed exercises are visible, and a push without a session is safe (@developer)

## What changed

- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` (+29):
  `applyExercisePush` now returns `WatchSessionRecord?`, and line 374 —
  `guard current != nil else { return nil }` — sits immediately after
  `try requireConformingIncoming(envelope)`. A new
  `selectExercise(slotId:) async -> WatchSessionRecord?` (line 296) looks the
  slot up in the session at the moment of the tap and reuses
  `Self.clampIndex` + `transitionTo(lifecycle: .exerciseAdvanced)`, so a pick
  from the ladder is the same lifecycle event a `+1` advance emits.
- `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` (+159):
  the module-level `WatchExercisePickerRow` (`id`/`name`/`exerciseId`/
  `isInSession`), `derivePickerRows(sessionExercises:fallback:)`,
  `WatchSessionStartPaths.pickerRows` (derived on every read, not cached) and
  `selectExercise(_ row:)`, which routes an in-session row to the engine and an
  available one to `addExerciseToSession`.
- `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift` (+?):
  `WatchStartView` and `WatchExercisePickerView` take `revision: Int = 0`, and
  the picker reads `paths.pickerRows`, keys `ForEach` on the row's own `id`, and
  styles an in-session row `.borderedProminent` against the others'
  `.bordered`. The defaulted parameter means no existing caller changes meaning.
- `ios/OmniTrain Watch App/ContentView.swift`: `startedSessionId` stays the
  in-session flag (so "Back" returns without ending the session), the branch is
  now `if startedSessionId != nil, let session = host.engine.session`, and
  `startedPlaceholder(session:)` renders the ladder with an SF Symbol marker and
  the current row in `Color.primary`. `revision: host.revision` is passed to
  `WatchStartView`.
- `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`:
  five tests appended before the class's closing brace, lines 529–679.

**New user-facing wording, for the owner.** One string, in
`ContentView.startedPlaceholder`: the fallback name `"Exercise"`, used only when
a ladder row carries no `name` key at all (an empty name renders empty, as
before). Everything else on the surface is pre-existing wording —
`"Session started"`, `"Back"`, `WatchStartSurfaceCopy.syncLabel`. The marker is
SF Symbols (`arrowtriangle.right.fill` for the current exercise, `circle.fill`
for the rest), not text.

## The five new Swift tests, and the mutation that turns each red

`swift test` is the governor's to run, so none of these was executed here. Each
row names a mutation of the code under test, quoted from the line as it stands so
it can be restored exactly, and the assertion in that test the mutation fails.
Line numbers are the current ones in the working tree.

`testS108APushIntoAnOpenFreeWorkoutLands`:

| # | Mutation | Assertion that fails |
|---|---|---|
| a | `WatchStartPaths.swift:197`, `onLadder.insert(exercise.exerciseId)` → deleted | `XCTAssertEqual(rows.filter { $0.exerciseId == "ex-front-squat" }.count, 1)` — the pushed exercise is also in the fallback list, so it appears twice |
| b | `WatchStartPaths.swift:152`, `case .inSession(let slotId, _): return slotId` → `return exercise.exerciseId` | `XCTAssertEqual(rows.first?.id, pushedSlotId)` — the contract's `pushedSlotId` is `sx-push-front-squat`, not the exercise's own `sx-ex-front-squat` |
| c | `WatchSessionEngine.swift:299`, `$0["sessionExerciseId"] as? String == slotId` → `true` | `XCTAssertEqual(harness.engine.currentExercise?["sessionExerciseId"] as? String, pushedSlotId)` only if the ladder held more than one slot; with one slot the mutation is not distinguishable, so the honest statement is: **not distinguishable in this test** |
| d | `WatchStartPaths.swift:387`, `sessionExercises: engine.session?.exercises ?? []` → `sessionExercises: []` | `XCTAssertEqual(rows.first?.id, pushedSlotId)` and `XCTAssertEqual(rows.first?.isInSession, true)` — with no session rows the list starts with the fallback list |

Row (c) is recorded as not distinguishable rather than left out: with one slot on
the ladder, "match this slot id" and "match anything" pick the same slot. The
fix's own mutation — deleting `guard current != nil else { return nil }` — leaves
S-108 green, because S-108's session is live; it is S-110's row (g) below.

`testS109AReDeliveredPushDoesNotDuplicateTheSlot`:

| # | Mutation | Assertion that fails |
|---|---|---|
| e | `WatchSessionEngine.swift:342-345`, the whole reuse block (`if let slotId = slot["sessionExerciseId"] as? String, session.exercises.contains(where: { $0["sessionExerciseId"] as? String == slotId }) { return session }`) → deleted | `XCTAssertEqual(harness.engine.session?.exercises.count, 1)` — the second delivery appends a second slot |
| f | `WatchSessionEngine.swift:352-357`, `Self.positionAfterInsert(...)` → `session.currentExerciseIndex` | `XCTAssertEqual(harness.engine.session?.currentExerciseIndex, after.currentExerciseIndex)` — the reuse path returns before this, so the mutation is only reachable on the *first* delivery; **not distinguishable in this test** |

The dedupe is not Phase 4 code: S-109 exists in the register to pin that the new
bridge path does not defeat it, and the mutation above is what shows the test
would notice.

`testS110APushWithNoLiveSessionChangesNothing` — this is the phase's fix, so its
mutation is the fix's own line:

| # | Mutation | Assertion that fails |
|---|---|---|
| g | `WatchSessionEngine.swift:374`, `guard current != nil else { return nil }` → deleted (the pre-Phase-4 state, restored exactly) | the first `await harness.deliver(...)` traps: `insertExercise` → `requireSession()` (`WatchSessionEngine.swift:1601`, `preconditionFailure("no session: create one, or restore the in-progress session first")`) aborts the test process. This is the "shown red without the fix" evidence for the bug fix. |
| h | the same line → `guard current != nil else { throw WatchEmissionRejected(message: "no session", rejections: []) }` | `XCTAssertTrue(harness.failures.isEmpty)` — the bridge catches it and reports it through `onFailure` |
| i | `WatchSessionEngine.swift:372`, `-> WatchSessionRecord?` → `-> WatchSessionRecord` | not a run: it fails to compile, because `return nil` has no value. Recorded so the type change is not mistaken for cosmetic. |
| j | `WatchSyncOrchestrator.swift:135`, `return try await engine.applyMessage(envelope)` → `return true` | `XCTAssertFalse(applied)` — the frame would report itself applied |

Row (g) is the mutation for the fix and needs a real run to be observed; the
governor's `swift test` is where it can be run. It is stated here as the mutation
to apply, not as a result.

`testPickerRowsListTheSessionFirstAndNeverTwice`:

| # | Mutation | Assertion that fails |
|---|---|---|
| k | `WatchStartPaths.swift:200`, `for exercise in fallback where !onLadder.contains(exercise.exerciseId)` → `for exercise in fallback` | `XCTAssertEqual(rows.filter { $0.exerciseId == "ex-barbell-bench-press" }.count, 1)`, and `XCTAssertEqual(rows.map(\.id).count, Set(rows.map(\.id)).count)` |
| l | `WatchStartPaths.swift:193-196`, the `rows.append(.inSession(...))` block → deleted | `XCTAssertEqual(rows.prefix(2).map(\.name), ["Barbell Bench Press", "Plank"])` |
| m | the two loops swapped (the fallback loop moved above the slot loop) | the same `rows.prefix(2)` assertion |
| n | `WatchStartPaths.swift:399`, `return await engine.selectExercise(slotId: slotId)` → `return nil` | `XCTAssertEqual(picked?.currentExerciseIndex, 0)` |
| o | `WatchSessionEngine.swift:305`, `lifecycle: WatchLifecycleState.exerciseAdvanced` → `nil` | `try bridgeObject(harness.emitted("session_lifecycle").last?["payload"])` — with no lifecycle emission `.last` is nil, so `bridgeObject` throws |
| p | `WatchSessionEngine.swift:299`, `$0["sessionExerciseId"] as? String == slotId` → `true` | `XCTAssertNil(refused)` — the stale `sx-gone` row would move the session instead of returning nil |
| q | `WatchStartPaths.swift:172-173`, `case .inSession: return true` / `case .available: return false` → both `false` | `XCTAssertEqual(rows.filter { $0.isInSession }.count, 2)` |
| r | `WatchStartPaths.swift:150-154`, `id` → `return "row"` for both arms | `XCTAssertEqual(rows.map(\.id).count, Set(rows.map(\.id)).count, "every row is keyed uniquely")` — the assertion the slot-id keying exists for |

`testPickerRowsFallBackToTheFallbackListWhileTheSessionIsEmpty`:

| # | Mutation | Assertion that fails |
|---|---|---|
| s | `WatchStartPaths.swift:200`, the `for exercise in fallback where ...` loop → `for exercise in fallback.prefix(0)` | `XCTAssertFalse(rows.isEmpty)` |
| t | `WatchStartPaths.swift:173`, `case .available: return false` → `return true` | `XCTAssertTrue(rows.allSatisfy { !$0.isInSession })` |
| u | `WatchStartPaths.swift:401`, `return await addExerciseToSession(exercise)` → `return nil` | `XCTAssertEqual(added?.exercises.count, 1)` |
| v | `WatchStartPaths.swift:387`, `engine.session?.exercises ?? []` → `[]` | **not distinguishable**: the session started by `startFreeWorkout()` has an empty ladder, so the two are the same list. Recorded rather than claimed. |

## Item 7's doc updates, and item 8's walkthrough

- `docs/watch-app-setup-and-qa.md` (item 7): the §1 status table's shell row now
  describes the real shell and a "Wrist store: in-memory only" row was added; the
  intro's "libraries with no host" paragraph was rewritten to match; §2's `@main`
  bullet is ticked; §3.6 became "The entry point and the shell" and names the
  three target files, the two surfaces it renders and the durable-store gap;
  Level 1's Flutter count is now `3881 passed, 1 skipped (2026-10-04)` and the
  Swift expectation is stated as "**0 failures** — read it off the run"; Level 3
  step 2's false claim that `routines_down` "currently has no phone-side producer
  at all" is replaced with the real producer and the tests that cover it.
- `docs/watch-app-setup-and-qa.md` (item 8): "A second walkthrough, for the push
  path" — numbered 1–7 in the plan's order, opening with the foreground and
  reachability requirement, and closing with the warning not to tap Sync again
  once the phone's session is live.
- `docs/state_management/watch_surface.md` (item 7): "The wrist's half of the
  same radio" gained the seam, the request-frame shape and the `since` precision
  divergence, the plist-safety rule with the no-coercion note, the
  nothing-queued/nothing-unsolicited rules and the three-state reachability — and
  a second subsection, "The wrist's start surface, and what an arrival does to
  it", carrying D-12 and the revision/picker-row rules. Every behaviour sentence
  names a `WatchConnectivityBridgeTests` test that exists.
- `docs/plans/2026-09-21-13-watch-integration-shipping.md`: the Phase 7 Progress
  block's template-`ContentView` bullet now records Phases 1–4 of the
  shell-bridge plan, and the remaining-human-steps bullet also names the durable
  wrist store.

**Not written into `watch_surface.md` on purpose**: the post-start ladder
(item 5). It is a view rule in the app target with no Swift test, and the
documentation standard forbids a behaviour sentence that names no test. It is
described in the setup guide, which is a record file and is exempt from the
content guards (`test/docs_indexing_contract_test.dart`'s `_recordFiles` lists
`watch-app-setup-and-qa.md`, so the walkthrough is outside the
flow-walkthrough guard by design).

## Gateway checks — Phase 4 (the Dart suites are the only ones this agent may run)

Three full-suite runs in this phase, the last two on the frozen tree (after the
last source and doc edit). The final run was taken without a pipe, so its exit
code is the gateway's own and not a downstream command's:

```
$ .github/copilot/scripts/macos/gateway.sh test        # unpiped, exit 0
01:34 +3881 ~1: All tests passed!
```

Re-run once more, unpiped and after the last edit in this file (a record file the
guards exclude, but the count is cheap to re-observe):

```
$ .github/copilot/scripts/macos/gateway.sh test        # unpiped, exit 0
01:36 +3881 ~1: All tests passed!
```

```
$ .github/copilot/scripts/macos/gateway.sh lint        # unpiped, exit 1
196 issues found. (ran in 3.1s)
```

The earlier runs ended `01:39 +3881 ~1: All tests passed!` (raced with the last
two `docs/state_management/watch_surface.md` edits — a file the
`docs_indexing_contract_test.dart` guards read — so it is superseded) and
`01:35 +3881 ~1: All tests passed!`; both were read through a pipe, so only the
runner's own final line is evidence from them, not their exit code. The unpiped
run closes that gap.

Both counts match the phase's baselines exactly (`+3881 ~1`; 196 issues, 0
errors), and the counts did not move because Phase 4 adds no Dart test and
touches no Dart source. `flutter analyze` exits 1 on any notice, so the lint exit
code is the pre-existing 196 `info` notices, not a failure; `grep` over the
analyzer output finds no `error •` line and the total is the same 196 as before
the phase's edits. The lint run predates the last evidence-file edit, which is a
record file no test reads (no test references `evidence.md`; the indexing
contract test excludes `plans/`).

## Not verified here (Phase 4)

- **`swift test` (governor).** The package suite owns the five tests above.
  Nothing in this phase claims a Swift result; each test is recorded as the
  mutation that would turn it red, not as a pass.
- **The watch `xcodebuild` (governor).** `ContentView.swift`'s new placeholder
  and the `revision` threading are compiled only when the governor builds the
  target. No new file was added, so the file-system-synchronized group needs no
  `project.pbxproj` entry.
- **The paired-simulator walkthrough (owner).** Item 8's steps are written into
  the setup guide; the run is the owner's. Recorded here as "owner step, not run
  by the agent".

## Residue sweep

No probe file remains: the one scratch probe this phase used to establish that
no Swift test calls `applyExercisePush` directly was removed with
`.github/copilot/scripts/macos/gateway.sh delete-scratch test/zz_probe_callers.dart`.
`gateway.sh git-status` lists only the modified files above; no file was created,
and no scratch file is left behind.

## Fix round 4 (review findings 1–7)

Mechanical only — no Swift, contract or production code changed.

- **Findings 1–3 (false doc passages).** `docs/watch-app-setup-and-qa.md` §1's
  Build-target row now says the target links `WatchSessionEngine` and points at
  the watch-scheme build as the proof; §3.5's body and its "One catch" paragraph
  are deleted, leaving a one-line pointer that the target already links the
  package. `docs/plans/2026-09-21-13-watch-integration-shipping.md`'s
  remaining-human-steps bullet drops "the Swift Package link".
- **Finding 4 (label clash).** The phone-fixture null-walk group in
  `test/watch_transport_test.dart` is relabelled `Phase 2 item 6: phone fixtures
  carry no null` — `S-112` is the register's wrist plist round trip — and the
  file's mapping comment is corrected. Labels only, no behaviour change.
- **Finding 5.** `docs/state_management/watch_surface.md`'s picker re-render
  claim is now an owner-run check pointing at step 7 of the push-path
  walkthrough, not a tested behaviour.
- **Finding 6.** The plan's Phase 1–3 checklists are ticked (13 items);
  owner/governor items are left unticked.
- **Finding 7.** `docs/state_management/watch_surface.md` gains the line that
  the unreachable label moves into the contract's `startSurface` block if the
  Wear OS client ever ships a transport, plus a two-sentence structural
  description of the shell's second surface and its in-memory store.

```
$ .github/copilot/scripts/macos/gateway.sh test test/watch_transport_test.dart
00:00 +23: All tests passed!

$ .github/copilot/scripts/macos/gateway.sh test        # unpiped, exit 0
01:50 +3881 ~1: All tests passed!

$ .github/copilot/scripts/macos/gateway.sh lint        # unpiped, exit 1
196 issues found. (ran in 3.1s)
```

Both counts match the pre-fix baseline (`+3881 ~1`; 196 issues, 0 errors).




