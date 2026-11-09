# Feature: 59 — the watch asks for Health access before the workout, and says when access is off

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (uncommitted; evidence and review beside the plan; reviewed together with plan 60, APPROVE; owner checks open, QA step 26). Owner: watch audit 3 (2026-10-23), fix order item 4 (first half), in chat. Series: 58 (workout type and calories, built), 59 (this), 60 (failed routine start and phone-link notices). Base commit: `.work/2026-10-23-59/base.txt`. Working branch: the one checked out; never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

Owner decisions (chat, 2026-10-23): Health access is asked the first time the Start screen shows; location stays asked at the first run (distance exercise); both say plainly when access is off.

| What you do | Now | After 59 |
|---|---|---|
| Open the watch app for the first time and reach the Start screen | nothing is asked | Health's permission sheet (workout, heart rate, steps, active energy) appears over the Start screen, once; later launches ask nothing (the system remembers) |
| Start a workout after allowing | unchanged | unchanged, and the sheet does not appear in the middle of a workout any more |
| Decline Health access, look at the Start screen | nothing says so | a small grey line under the buttons: "Health access is off. Turn it on in Health on your iPhone." |
| Decline, then start a workout | the logging screen shows a bare clock; no heart rate, no explanation | the logging screen's header shows an extra grey line: "No heart rate, Health access is off" (while access is off) |
| Decline location, then start or reach a distance exercise (run) | no distance, no explanation | the header shows "No distance, Location access is off" while that exercise is the current one; on a lift nothing is shown |
| Both declined, on a run | bare clock | both lines, heart rate first |
| Allow everything | unchanged | no extra lines |
| Resume a workout after a relaunch mid-session (no Start screen) | prompt appears mid-session as today | unchanged: the Start screen is not shown, so Health asks at the first workout open, as before |

Limits to tell the owner: Apple does not tell an app whether a *read* permission (heart rate) was refused; the watch reads "access is off" from the workout-share permission (the one that lets the workout be saved), so a user who allows the workout but refuses only heart rate gets no line. The simulator can show the sheet and the lines (the sim's Health permission can be reset by erasing the watch simulator).

## Decision Ledger

- D-1 `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift`, `WatchSensorRecorder` (class at l.100): two new `public private(set) var heartRateAccess: WatchSensorPermission?` and `locationAccess: WatchSensorPermission?`, nil until the platform was asked this session. `startHeartRate()` (current l.202-207: `guard await source.heartRatePermission() == .granted else { return }`) stores the answer in `heartRateAccess` before the guard. `startLocationIfNeeded` (current l.160-172: `guard await source.locationPermission() == .granted else { locationAnswered = true; return }`) stores the answer in `locationAccess` (only reached for a distance session, so a lift never asks and stays nil). `stop()` (l.180-200) sets both back to nil (next to `locationAnswered = false`). No banned new function names (these are properties).
- D-2 `WatchLoggingState` (`WatchLoggingState.swift`, near `sensorLabels` l.~300): new `public var sensorNotices: [String]` — "No heart rate, Health access is off" when `sensors?.heartRateAccess == .denied`; "No distance, Location access is off" when `sensors?.locationAccess == .denied` AND the current exercise's capabilities contain `WatchGpsPolicy.distanceCapability` (the private `capabilities` at l.596 is the current slot's); heart rate first; `[]` with no sensors. Strings live in a new `public enum WatchSensorNoticeCopy` (`noHeartRate`, `noDistance`) in the same file as D-3. `WatchSensorPermission.unavailable` shows nothing.
- D-3 New file `watch/watchos/Sources/WatchSessionEngine/WatchHealthAccess.swift` (the builder creates it; the directory exists): `public enum WatchHealthAccess: Equatable { case unknown, allowed, off, unavailable }` with `public static func answer(available: Bool, granted: Bool) -> WatchHealthAccess` (not available → `.unavailable`; granted → `.allowed`; else `.off`), `public enum WatchHealthAccessCopy { public static let offLine = "Health access is off. Turn it on in Health on your iPhone." }`, and `WatchSensorNoticeCopy` (D-2).
- D-4 `WatchLoggingModel.swift` (class holding `state`, `statusLine` l.133): `public var sensorNotices: [String] { state.sensorNotices }`. `WatchLoggingView.swift` (compiled only on watchOS; header block ending at l.~197, after `if let status = model.statusLine { Text(status) … }`): `ForEach(model.sensorNotices, id: \.self) { notice in Text(notice).font(.caption2).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.7) }`.
- D-5 `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`: new `func requestAccess() async -> WatchHealthAccess` next to `resolveAuthorization()` (l.~243): `guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }`, then `WatchHealthAccess.answer(available: true, granted: await resolveAuthorization())`. It reuses the memoised request, so the feed's and `begin`'s asks join the same one (no second sheet). The comment above `resolveAuthorization` (says the prompt is asked "on the first session that is about to open a workout and never at launch", D-1503) is amended: now asked when the Start screen first shows, and still at the first workout open for a relaunch into a live session.
- D-6 `ios/OmniTrain Watch App/ContentView.swift`: `WatchAppHost` gets `@Published private(set) var healthAccess = WatchHealthAccess.unknown` (beside `isSyncing`, l.72) and `func askHealthAccess() async { healthAccess = await healthStore.requestAccess() }` (near `refreshHeartRate`, l.331; `healthStore` is declared after `init`, keep the first `HealthKitWorkoutStore(` construction where it is). The `WatchStartView(` call (l.386-396) passes `healthAccess: host.healthAccess` and the view is followed by `.task { await host.askHealthAccess() }`.
- D-7 `WatchStartView.swift`: new init parameter `healthAccess: WatchHealthAccess = .unknown` after `isSyncing` (stored `private let`), and in the body's VStack, after the `syncNotice` block (l.172-177): `if healthAccess == .off { Text(WatchHealthAccessCopy.offLine).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }`.
- D-8 Not here: the location sheet's timing (kept), a Settings deep link (watchOS has none), failed routine start and phone link (plan 60), the Dart twin.

## Readers listed (grep 2026-10-23, builder re-greps)

- `WatchSensorRecorder` callers: `WatchSensorCoordinator.swift`, `WatchSessionSensors` (same file), `ContentView.swift`; tests `WatchSensorRecordingTests.swift` (FakeSensorSource at l.38 has `heartRateGrant`, `locationGrant`; S-006 tests l.425/449 pin that a denial skips the subscription: keep passing), `WatchDistanceTrackerTests.swift`, `WatchGpsByExerciseTests.swift`, `WatchSensorCoordinatorTests.swift`.
- `WatchLoggingState(` constructors: `ContentView.swift` and many tests (`sensors:` is an optional parameter: unchanged signature, no caller breaks).
- `WatchStartView(` call sites: `ContentView.swift` only (new parameter has a default).
- Source-text readers of the files touched: `WatchSensorSourceSourceTests.swift` (`testS3110…` scans `ContentView.swift` for the first `HealthKitWorkoutStore(` and `WatchLoggingState(engine: engine, sensors:`; S-3109 scans the store's `requestAuthorization` call), `WatchWorkoutStoreSourceTests.swift`, `WatchNutritionWiringSourceTests.swift`, `WatchCancelEmptyFreeWorkoutTests.swift` (`ContentView`/`WatchStartView` text). Rerun all.
- Scenario ids S-8901..S-8920 checked free (grep `S-89` in `test docs watch lib`, 2026-10-23).

## Core scenarios

New `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorAccessNoticeTests.swift` on `FakeSensorSource` and the helpers in `WatchSensorRecordingTests.swift` (`sensors(for:)`, `session(...)`; if private, copy the few lines) and `WatchLoggingState(engine:sensors:unitsSource:)`. Every scenario fails without the change (property or API missing).

- S-8901 recorder: before `start`, `heartRateAccess == nil`; with `heartRateGrant = .denied` after `start`, `.denied`; with `.granted`, `.granted`.
- S-8902 `stop()` returns both accesses to nil (denied run, then stop).
- S-8903 location, two arms: a distance session with `locationGrant = .denied` → `locationAccess == .denied`; a lift-only session with `locationGrant = .denied` → still nil (never asked).
- S-8904 state, heart rate: denied → `sensorNotices == [WatchSensorNoticeCopy.noHeartRate]`; granted → `[]`; and `WatchSensorNoticeCopy.noHeartRate == "No heart rate, Health access is off"` (exact text).
- S-8905 state, distance follows the current exercise: slots `[run, lift]`, location denied: current exercise run → contains `noDistance` (exact "No distance, Location access is off"); after moving to the lift (`engine.selectExercise` or the state's own index mover — builder finds it) → no `noDistance`; arm: heart rate denied too → `[noHeartRate, noDistance]` in that order.
- S-8906 state with no sensors → `[]`; `.unavailable` permission → `[]`.
- S-8907 `WatchHealthAccess.answer`: `(false,false)` and `(false,true)` → `.unavailable`; `(true,true)` → `.allowed`; `(true,false)` → `.off`; `WatchHealthAccessCopy.offLine` exact text.
- S-8908 source guards (comment lines stripped; exact statements): store has `func requestAccess() async -> WatchHealthAccess`, `guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }` and `await resolveAuthorization()` inside it; `ContentView.swift` has `func askHealthAccess() async`, `healthAccess = await healthStore.requestAccess()`, `healthAccess: host.healthAccess` and `.task { await host.askHealthAccess() }`; `WatchStartView.swift` has `if healthAccess == .off` and `WatchHealthAccessCopy.offLine`; `WatchLoggingView.swift` has `ForEach(model.sensorNotices`.

## Phases

- P1 `crew-builder-watch` (5 items): D-1, D-2, D-3, D-4 (model part only) and `WatchSensorAccessNoticeTests.swift` S-8901..S-8907. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchSensorRecording.swift`, `.../WatchLoggingState.swift`, `.../WatchLoggingModel.swift`, `.../WatchHealthAccess.swift` (new), `watch/watchos/Tests/WatchSessionEngineTests/WatchSensorAccessNoticeTests.swift` (new). Brief: "Never run the full `flutter test`", report skeleton first, new function names avoid banned verbs. Done: `--filter WatchSensorAccessNoticeTests`, `--filter WatchSensorRecordingTests`, `--filter WatchLoggingSurfacesTests`, `--filter WatchSessionEngineTests`.
- P2 `crew-builder-watch` (4 items, serial after P1): D-4 view part, D-5, D-6, D-7 as exact text, plus S-8908 in a new `WatchHealthAccessWiringSourceTests.swift`. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift`, `.../WatchStartView.swift`, `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`, `ios/OmniTrain Watch App/ContentView.swift`, the new test file. Done: `--filter WatchHealthAccessWiringSourceTests`, `--filter WatchSensorSourceSourceTests`, `--filter WatchNutritionWiringSourceTests`, `--filter WatchCancelEmptyFreeWorkoutTests`, `--filter WatchWorkoutStoreSourceTests`. The governor then runs `xcodebuild`.
- P3 `crew-docs-keeper`: `docs/state_management/watch_sensors.md` (permission section: asked on the Start screen; `sensorNotices`), `docs/watch-app-setup-and-qa.md` (QA step with the sheet and the two lines; amend step 23's "also with it declined once"), any doc that says the prompt appears at the first workout (grep `docs/`).

## Verify (governor)

`swift test` full; `xcodebuild` (workspace `ios/Runner.xcworkspace`, scheme "OmniTrain Watch App", destination watchOS Simulator, scratch `-derivedDataPath`); mutations: (a) `heartRateAccess` not stored, (b) `locationAccess` stored for a lift, (c) `stop()` no longer clears, (d) the distance notice ignores the current exercise, (e) notice order swapped, (f) `answer` branches swapped (each branch), (g) the Start line condition inverted (source guard), (h) `askHealthAccess` call removed. Simulator: erase the watch simulator's content, launch, see the Health sheet over the Start screen, decline, see the Start line; seed `watch-session.jsonl` with a running session to see the two lines (computer-use when unlocked, else owner check).

## Progress

P1, P2, P3 done 2026-10-23: see the evidence file. 15 of 15 lead mutants killed; the view wiring tests were tightened in a tests-only fix round (shared with plan 60).
