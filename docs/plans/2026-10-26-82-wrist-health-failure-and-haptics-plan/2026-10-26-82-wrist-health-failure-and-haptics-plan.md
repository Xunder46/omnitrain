# Feature: 82 — the wrist says when the Health workout did not start; each countdown end and the End Session confirm have their own tap

> Status: BUILT AND PROVED 2026-10-26 (uncommitted). Review nit fixed: a different session going live drops the previous session's failure (`acknowledgeOpenFailure`, test S-15110, shown red without the line). Seven mutations each turned their guard red. Feel of the three taps is an owner check. Earlier status: SEEDED 2026-10-26 (lead), architect done 2026-10-26 (line numbers verified and corrected, phases expanded, notes in `.work/crew/2026-10-26-82/architect-notes.md`). Base commit: `.work/2026-10-26-82/base.txt`. Team: the crew. Owner request (chat, 2026-10-26, "I'll go with your suggestions", audit findings W1 and W2). Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md. Package targets watchOS 9 (`Package.swift` `.watchOS(.v9)`): no watchOS 10-only API.

## What the owner sees

| Moment | Today | After |
|---|---|---|
| Health access is on, but the platform refuses to open the workout (another app holds one, the system throws) | nothing: logging looks normal, no heart rate, no Health workout, no Move ring credit | the logging header shows one small grey line: "Health workout didn't start". Logging itself is unaffected |
| Same failure, then the workout summary | "No heart rate" is shown with no reason, or (access off) "Health access is off" | the summary says "No heart rate, the Health workout did not start" when that is the cause. Access-off wording is unchanged |
| A round, a hold and a timed target each reach zero | the same tap every time | three different taps (round end keeps today's tap) |
| Confirm End Session in the menu | no tap | one tap on Finish (not on Cancel) |
| Health access off / location off | existing lines | unchanged |

(owner) On a real watch: (a) three countdowns ending feel different; (b) Finish gives one tap, Cancel none; (c) hard to trigger the Health failure on purpose: start a Run while a third-party workout app is mid-workout, or accept it as test-covered and unseen.

## Decision Ledger

- D-1 `WatchPlatformWorkoutStore` (`WatchPlatformWorkout.swift:250`) gains `var lastBeginFailed: Bool { get }`, with a default `false` in the protocol extension (`:270`), so existing fakes keep compiling. `HealthKitWorkoutStore.begin` (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift:105-155`) sets it `true` in the `catch` block (`:147-155`) and `false` at the top of `begin` and after a successful `beginCollection`. A `guard` that returns early because Health is unavailable or access is off is NOT a failure (the existing access-off lines own it).
- D-2 `WatchPlatformWorkout.start(_:)` (`:299-307`) copies the store's flag after `await store.begin(...)` into `public private(set) var openFailed: Bool`; `end()` leaves it set (the summary reads it after the session ends); the next `start` resets it first.
- D-3 `WatchWorkoutCoordinator` (`:386`) exposes `public var openFailed: Bool { platform.openFailed }` (read under no lock: the value changes only inside the serial `enqueue` chain; the host reads it on the main actor after `await workout.refresh(...)`).
- D-4 No retry. The coordinator already records `openedForSessionId` before asking, so a refused registration is not asked again within the session (comment at `:417-419`). A second try could open two workouts; not done.
- D-5 Surfacing: `WatchAppHost` (`ios/OmniTrain Watch App/ContentView.swift:55-81`) gets `@Published private(set) var workoutOpenFailed = false`, set from `workout.openFailed` after the `await self.workout.refresh(self.engine.session)` at `ContentView.swift:274` (inside the `$revision` sink's `Task { @MainActor in ... }`). `WatchLoggingState` (`WatchLoggingState.swift:319-327`, `sensorNotices`) gains an injected `workoutNotice: () -> Bool` (default `{ false }`, set by the host); when true it appends `WatchSensorNoticeCopy.noWorkout` ("Health workout didn't start") FIRST in the list, before the `guard let sensors` check, so the line shows even while no sensor recorder is attached. No separate `WatchHealthAccess != .off` condition is needed in the state: per D-1 an access-off `begin` returns early without setting `lastBeginFailed`, so the flag is already `false` in that case (see Architect notes). The view (`WatchLoggingView.swift:206`) already renders every entry of `sensorNotices`; no view change.
- D-6 `WatchSensorNoticeCopy` (`WatchHealthAccess.swift:30-32`) gains `noWorkout = "Health workout didn't start"` and `noHeartRateNoWorkout = "No heart rate, the Health workout did not start"`. `WatchWorkoutSummary.heartRateNote(healthOff:)` (`WatchWorkoutSummary.swift:93-95`) becomes `heartRateNote(healthOff: Bool, workoutFailed: Bool = false)`: access-off wins; else when `averageBpm == nil && workoutFailed` returns the new copy. `WatchWorkoutSummaryView.swift:47` and `ContentView.swift:420` pass `workoutFailed: host.workoutOpenFailed`. The summary view's init (`:25`) gains the parameter with default `false`. Two source-guard tests pin the exact strings this changes and are updated in the same phase: `WatchExercisePageFitTests.swift:299` pins `summary.heartRateNote(healthOff: healthOff)` and `WatchWorkoutSummaryWiringSourceTests.swift:58` pins the full `WatchWorkoutSummaryView(summary:...)` call.
- D-7 Haptics: add `public enum WatchHapticCue: Equatable { case roundEnd, holdEnd, targetReached }` and `WatchTimerHaptics.cue(for kind: String) -> WatchHapticCue?` (pure, in `WatchTimerHaptics.swift`; nil for `rest` and unknown kinds): `round` -> `.roundEnd`, `hold` -> `.holdEnd`, `elapsed` -> `.targetReached`. `WristHaptics.play(_ milestone:)` (`WatchLoggingView.swift:35-37`) switches on the cue: `.roundEnd` -> `.notification` (unchanged), `.holdEnd` -> `.stop`, `.targetReached` -> `.retry`. These three differ from `playLogged` (`.success`), `playRestPing` (`.click`) and `playNext` (`.directionUp`). The owner judges the feel on a device (owner check); the mapping is one switch, easy to change.
- D-8 `WatchHaptics` (`WatchLoggingModel.swift:244-256`) gains `func playFinished()` with a no-op default in a protocol extension; `WristHaptics` implements it as `.success`. `WatchMenuView` (`WatchMenuView.swift:203-218`; the Finish action closure is `:210-214`) takes `haptics: WatchHaptics = WristHaptics()` and calls `haptics.playFinished()` as the first statement of the alert's Finish action closure (before `await state.finish()`), never in the Cancel button. Reason first: the tap confirms the user's choice even when the rating prompt then takes the screen. Both `WatchMenuView.swift` and `WatchLoggingView.swift` are `#if os(watchOS)` files, so the `WristHaptics()` default compiles.
- D-9 New function names avoid the module's append-only verb guard (update, delete, remove, replace, edit, overwrite, write, clear, purge, wipe, reset, drop, truncate, erase, forget, modify, mutate, destroy, set, and any name starting with `set`): use `cue(for:)`, `playFinished`, `openFailed`, `lastBeginFailed`, `workoutNotice`.
- D-10 Out of scope: any retry, the radio / store-write / GPS silent failures (the "waiting for your phone" line already covers unacknowledged entries), the Dart Wear twin (`lib/watch/logging/watch_timer_haptics.dart` keeps one tap), the phone, the protocol.
- D-11 The two source-guard tests that pin strings D-6 rewrites (`WatchExercisePageFitTests.testS10006TheSummaryViewCarriesTheHeartRateLine`, `WatchWorkoutSummaryWiringSourceTests.testS9620TheShellShowsTheSummaryBetweenTheQuestionAndTheRest`) are readers of the changed contract, not new scope: P1 updates their pinned strings to the new call shapes in the same phase, so `swift test` stays green.

## Scenarios (exact fixtures; re-derive in the first run)

- S-15101 fake store whose `begin` ends with `lastBeginFailed == true`: `WatchPlatformWorkout.start(session)` leaves `openFailed == true` and `running` set (the existing registration contract); a second `start` with a store that succeeds leaves `openFailed == false`. Fails today: no such property.
- S-15102 `WatchWorkoutCoordinator.refresh(activeSession)` with the failing fake: `coordinator.openFailed == true`; after `refresh(nil)` (session over) it stays `true`; after the next active session with a succeeding store it is `false`.
- S-15103 `WatchLoggingState.sensorNotices` with `workoutNotice: { true }` and no sensors: `[WatchSensorNoticeCopy.noWorkout]`; with `workoutNotice: { false }`: `[]`; with the location-denied fixture of `WatchSensorAccessNoticeTests` and `workoutNotice: { true }`: `[noWorkout, noDistance]` in that order.
- S-15104 `heartRateNote(healthOff: true, workoutFailed: true)` == `noHeartRate` (access-off wins); `(false, true)` with `averageBpm == nil` == `noHeartRateNoWorkout`; `(false, true)` with an average present == nil; `(false, false)` == nil.
- S-15105 `WatchTimerHaptics.cue(for:)`: round -> `.roundEnd`, hold -> `.holdEnd`, elapsed -> `.targetReached`, rest -> nil, "bogus" -> nil; the three cues are pairwise distinct (`Set` of the three has count 3).
- S-15106 source guard on `WatchLoggingView.swift` `WristHaptics` (comment lines stripped, exact statements): `case .roundEnd`, `play(.notification)` inside it, `case .holdEnd`, `play(.stop)`, `case .targetReached`, `play(.retry)`, and `func playFinished()` with `play(.success)`. Exact statement, not a substring.
- S-15107 source guard on `WatchMenuView.swift`: the Finish button closure contains `haptics.playFinished()` BEFORE `await state.finish()`; the Cancel button line has no `playFinished`; the init has `haptics:`. Exact statements including braces.
- S-15108 source guard on `ContentView.swift`: `workoutOpenFailed = workout.openFailed` follows a `workout.refresh(` call; the `WatchWorkoutSummaryView(` call passes `workoutFailed: host.workoutOpenFailed`; `WatchLoggingState(` receives `workoutNotice:`.
- S-15109 `WatchLoggedHapticTests` still green; a fake `WatchHaptics` that does not implement `playFinished` still compiles (default exists).

Readers of the changed contracts (grep before building): `WatchWorkoutCoordinatorTests` (its `ScriptedPlatformStore(deniesBegins:)` at `:45` is the existing failing-store fixture), `WatchSensorAccessNoticeTests` (the location-denied fixtures at `:188-227`), `WatchExercisePageFitTests` (the four `heartRateNote(` calls at `:258, :266, :273, :280` and the pinned view string at `:299` — `WatchWorkoutSummaryTests` has no `heartRateNote(` calls), `WatchWorkoutSummaryWiringSourceTests` (the pinned ContentView summary call at `:58`), `WatchLoggedHapticTests` (its `RecordingHaptics` at `WatchLoggingModel.swift:218` does not implement `playFinished`, so the default keeps it compiling), `WatchHealthAccessWiringSourceTests` (it pins ContentView wiring; the new statements must not break its patterns), `WatchLoggingState(` constructor callers (tests and `ContentView.swift:177`; the new parameter has a default), `docs/state_management/watch_surface_wrist.md`, `docs/watch-app-setup-and-qa.md`.

Fakes conforming to the changed protocols (verified by grep, so the default-in-extension approach keeps them compiling): `WatchPlatformWorkoutStore` — `FakePlatformStore` (`WatchSensorRecordingTests.swift:90`), `RecordingOutdoorPlatformStore` and `LegacyShapePlatformStore` (`WatchOutdoorWorkoutTests.swift:26, :41`), `RecordingGpsOutdoorStore` (`WatchGpsByExerciseTests.swift:80`), `ScriptedPlatformStore` (`WatchWorkoutCoordinatorTests.swift:45`); `WatchHaptics` — `RecordingHaptics` (`WatchLoggingModel.swift:218`, used by `WatchLoggedHapticTests`, `WatchRestPingTests`, `WatchRestPingSchedulerTests`).

## Phases

- P1 `crew-builder-watch` — W1 (D-1..D-6, D-11, S-15101..S-15104, S-15108). Two builder runs, part A then part B (disjoint files, but B reads A's protocol members, so serial within P1). P2 waits for P1 (D-7's `WristHaptics.play` switch and D-8's `playFinished` sit in files P1 also shapes the haptics contract beside; and the source guards of S-15108 and S-15107 both read `ContentView.swift`).
- P2 `crew-builder-watch` — W2 (D-7..D-9, S-15105..S-15107, S-15109). Serial after P1.
- P3 lead — `xcodebuild` of the watch app (watchOS 9 API check), full `swift test`, mutation pass in an isolated copy of `watch/` and `ios/OmniTrain Watch App/`.
- P4 `crew-docs-keeper` — `docs/state_management/watch_surface_wrist.md`, QA step in the list that holds the newest wrist steps; then `crew-reviewer`.

### P1 part A — engine and host (D-1..D-4, S-15101, S-15102)

Write scope (pass to the governor as `--scope`):

```
"watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift"
"ios/OmniTrain Watch App/HealthKitWorkoutStore.swift"
"ios/OmniTrain Watch App/ContentView.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutCoordinatorTests.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchOpenFailureTests.swift"
```

Items:

1. [ ] Add `var lastBeginFailed: Bool { get }` with default `false` to the protocol extension — `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` · `WatchPlatformWorkoutStore` extension (`:270`)
2. [ ] Set `lastBeginFailed = false` at the top of `begin` and `true` in the `catch` (`:147-155`); leave the two early `guard` returns (`:106-107`) as non-failures — `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` · `begin(_:outdoors:)`
3. [ ] Add `public private(set) var openFailed: Bool`; reset at the top of `start`, copy from `store.lastBeginFailed` after `await store.begin(...)`; `end()` leaves it — `WatchPlatformWorkout.swift` · `WatchPlatformWorkout.start(_:)` (`:299`)
4. [ ] Add `public var openFailed: Bool { platform.openFailed }` — `WatchPlatformWorkout.swift` · `WatchWorkoutCoordinator` (`:386`)
5. [ ] Host: move the `WatchWorkoutCoordinator` construction above the `WatchLoggingState` construction in `init`, add `@Published private(set) var workoutOpenFailed = false`, and after `await self.workout.refresh(self.engine.session)` (`:274`) assign `workoutOpenFailed = workout.openFailed` — `ios/OmniTrain Watch App/ContentView.swift` · `WatchAppHost.init` / the `$revision` sink
6. [ ] Regression: assert the existing `ScriptedPlatformStore(deniesBegins:)` path still ends with `openFailed == false` when the store succeeds — `watch/watchos/Tests/WatchSessionEngineTests/WatchOpenFailureTests.swift` · new file, S-15101 second arm

Done criteria: `swift test --filter WatchOpenFailureTests`, `swift test --filter WatchWorkoutCoordinatorTests` green; `swift build` of the package green.

### P1 part B — state, copy, summary, pinned guards (D-5, D-6, D-11, S-15103, S-15104, S-15108)

Write scope:

```
"watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift"
"watch/watchos/Sources/WatchSessionEngine/WatchHealthAccess.swift"
"watch/watchos/Sources/WatchSessionEngine/WatchWorkoutSummary.swift"
"watch/watchos/Sources/WatchSessionEngine/WatchWorkoutSummaryView.swift"
"ios/OmniTrain Watch App/ContentView.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchSensorAccessNoticeTests.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchExercisePageFitTests.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutSummaryWiringSourceTests.swift"
```

Items:

1. [ ] Add `noWorkout` and `noHeartRateNoWorkout` copy constants — `WatchHealthAccess.swift` · `WatchSensorNoticeCopy` (`:30`)
2. [ ] Inject `workoutNotice: () -> Bool = { false }` into `init` (`:225`); in `sensorNotices` (`:319`) append `noWorkout` first, before the `guard let sensors` check — `WatchLoggingState.swift` · `WatchLoggingState.init` / `sensorNotices`
3. [ ] Host passes `workoutNotice: { [weak self] in self?.workout.openFailed ?? false }` (or captures the local) at the `WatchLoggingState(` call (`:177`) and the summary call passes `workoutFailed: host.workoutOpenFailed` (`:420`) — `ContentView.swift` · `WatchAppHost`
4. [ ] `heartRateNote(healthOff:workoutFailed:)` with the D-6 arm order — `WatchWorkoutSummary.swift` · `heartRateNote` (`:93`)
5. [ ] Summary view: `workoutFailed: Bool = false` parameter, stored, passed to `heartRateNote` — `WatchWorkoutSummaryView.swift` · `init` (`:25`) / body (`:47`)
6. [ ] Update the pinned string `summary.heartRateNote(healthOff: healthOff)` to the new call and add the `workoutFailed` arm tests — `WatchExercisePageFitTests.swift` · `testS10006TheSummaryViewCarriesTheHeartRateLine` (`:296-311`)
7. [ ] Update the pinned string `WatchWorkoutSummaryView(summary: pending, healthOff: host.healthAccess == .off, onDone: { host.summary.dismissPending() })` to the new call — `WatchWorkoutSummaryWiringSourceTests.swift` · `testS9620TheShellShowsTheSummaryBetweenTheQuestionAndTheRest` (`:58`)
8. [ ] S-15103 fixtures: `workoutNotice: { true }` with no sensors → `[noWorkout]`; `{ false }` → `[]`; the location-denied fixture of `WatchSensorAccessNoticeTests` (`:188-203`) with `{ true }` → `[noWorkout, noDistance]` — `WatchSensorAccessNoticeTests.swift` · new tests beside S-8905

Done criteria: `swift test --filter WatchSensorAccessNoticeTests`, `--filter WatchExercisePageFitTests`, `--filter WatchWorkoutSummaryWiringSourceTests`, `--filter WatchOpenFailureTests` green; `swift build` green.

Fixtures for the new `WatchOpenFailureTests.swift` (S-15101, S-15102, S-15104, S-15108):

- `FailingBeginStore: WatchPlatformWorkoutStore`: `begin(_:outdoors:)` sets `lastBeginFailed = true` and does nothing else; `SucceedingBeginStore`: records the begin and leaves the default `false`. Both rely on the extension defaults for the other `begin` shape, `end` and `inProgressActivityTypes` (return `[]`).
- S-15101: `WatchPlatformWorkout(store: FailingBeginStore())`, `start(session)` with a real `WatchSessionRecord` from the engine harness (modality `"sports"`, as `WatchWorkoutCoordinatorTests` builds them) → `openFailed == true` and `running != nil`; then a second platform over `SucceedingBeginStore`, `start` → `openFailed == false`.
- S-15102: `WatchWorkoutCoordinator(platform:)` over the failing store, `refresh(activeSession)` → `openFailed == true`; `refresh(nil)` → still `true`; a new active session over a succeeding store → `false`.
- S-15104: `WatchWorkoutSummary(sessionId: "s-1", startedAt:, endedAt:, effortCount: 3, allSets: true, averageBpm:)` as `WatchExercisePageFitTests.summary` builds it: `(healthOff: true, workoutFailed: true)` == `noHeartRate`; `(false, true)` with `averageBpm: nil` == `noHeartRateNoWorkout`; `(false, true)` with `averageBpm: 137` == nil; `(false, false)` with `averageBpm: nil` == nil.
- S-15108: source guard on `ios/OmniTrain Watch App/ContentView.swift` with the `strippingCommentLines` helper copied from `WatchHealthAccessWiringSourceTests.swift:31-41`: `workoutOpenFailed = workout.openFailed` appears after a `workout.refresh(` occurrence; `workoutFailed: host.workoutOpenFailed` inside the `WatchWorkoutSummaryView(` call; `workoutNotice:` inside the `WatchLoggingState(` call.

### P2 — haptics (D-7..D-9, S-15105..S-15107, S-15109)

Write scope:

```
"watch/watchos/Sources/WatchSessionEngine/WatchTimerHaptics.swift"
"watch/watchos/Sources/WatchSessionEngine/WatchLoggingModel.swift"
"watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift"
"watch/watchos/Sources/WatchSessionEngine/WatchMenuView.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchLoggedHapticTests.swift"
"watch/watchos/Tests/WatchSessionEngineTests/WatchTimerCueTests.swift"
```

Items:

1. [ ] Add `public enum WatchHapticCue: Equatable { case roundEnd, holdEnd, targetReached }` and the pure `cue(for kind: String) -> WatchHapticCue?` (`round`/`hold`/`elapsed` mapped, `rest` and unknown → nil) — `WatchTimerHaptics.swift` · new top-level enum + `WatchTimerHaptics.cue(for:)`
2. [ ] Add `func playFinished()` with a no-op default in a protocol extension — `WatchLoggingModel.swift` · `WatchHaptics` (`:244`)
3. [ ] `WristHaptics`: implement `playFinished()` as `.success` and turn `play(_:)` (`:35`) into a switch over `WatchTimerHaptics.cue(for: milestone.kind)`: `.roundEnd` → `.notification`, `.holdEnd` → `.stop`, `.targetReached` → `.retry`, nil → `.notification` (the old behaviour, kept for any unknown kind) — `WatchLoggingView.swift` · `WristHaptics`
4. [ ] `WatchMenuView`: add `haptics: WatchHaptics = WristHaptics()` to `init` (`:65`), store it, and call `haptics.playFinished()` as the first statement of the Finish action's `Task` (`:211`), before `await state.finish()`; Cancel (`:209`) untouched — `WatchMenuView.swift` · `init` / `finishRow`
5. [ ] S-15105 table test: `cue(for:)` over `"round"`, `"hold"`, `"elapsed"`, `"rest"`, `"bogus"`, and `Set([.roundEnd, .holdEnd, .targetReached]).count == 3` — `WatchTimerCueTests.swift` · new file
6. [ ] S-15106 source guard on `WatchLoggingView.swift` (comment lines stripped, exact statements): `case .roundEnd` with `play(.notification)`, `case .holdEnd` with `play(.stop)`, `case .targetReached` with `play(.retry)`, `func playFinished()` with `play(.success)` — `WatchTimerCueTests.swift`
7. [ ] S-15107 source guard on `WatchMenuView.swift`: the Finish closure contains `haptics.playFinished()` before `await state.finish()`; the Cancel line has no `playFinished`; `init` has `haptics:` — `WatchTimerCueTests.swift`
8. [ ] S-15109: `RecordingHaptics` (no `playFinished` witness) still compiles and `WatchLoggedHapticTests` stays green — run `swift test --filter WatchLoggedHapticTests` unchanged — `WatchLoggedHapticTests.swift` · no edit expected

Done criteria: `swift test --filter WatchTimerCueTests`, `--filter WatchLoggedHapticTests`, `--filter WatchRestPingTests`, `--filter WatchRestPingSchedulerTests` green; `swift build` green.

Fixtures for the new `WatchTimerCueTests.swift`: the cue table above uses string literals only (no engine); the source guards read `watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift` and `WatchMenuView.swift` through `Fixtures.sourcesRoot` with the same comment-stripping helper the other source tests carry.

## Assumption Log

- The 40 mm width: the notice line is `caption2`, one line, `minimumScaleFactor(0.7)`, shorter than the existing "No distance, Location access is off".
- Which `WKHapticType` per cue is a feel decision (D-7); mapping chosen only so the three differ from each other and from the log, rest, Next and finish taps.
- The summary reason uses the flag that survives until the next `begin` (D-2), so the summary shown after End still has it.
- The host builds `WatchLoggingState` in `init` (`ContentView.swift:177`) before the workout coordinator exists as a local, so P1 part A reorders the two constructions (workout first) and the `workoutNotice` closure captures the local coordinator; no stored-property dance needed.

## Architect notes (corrections made to the seed)

- D-1 line numbers corrected: `begin(_:outdoors:)` is `HealthKitWorkoutStore.swift:105-155`, the `catch` is `:147-155` (seed said `:96-135` / `:127-133`); the two non-failure guards are `:106-107`.
- D-2/D-3/D-4 line numbers corrected: `start` is `:299-307`, the coordinator class is `:386`, `refresh` `:401`, `apply` `:411`, the `openedForSessionId` comment `:417-419` (seed said `:289-301`, `:392`, `:421-424`).
- D-5 corrected: the seed conditioned the `noWorkout` line on `WatchHealthAccess != .off`, but `WatchLoggingState` holds no access state and needs none — per D-1 an access-off `begin` returns early at `HealthKitWorkoutStore.swift:106-107` without setting `lastBeginFailed`, so the flag is already `false` there. Also corrected: `sensorNotices` currently opens with `guard let sensors else { return [] }` (`WatchLoggingState.swift:320`), so the `noWorkout` append must go before that guard for S-15103's no-sensors fixture to hold. The single `workout.refresh` call is `ContentView.swift:274`, inside the `$revision` sink's `Task { @MainActor in ... }`; `WatchLoggingState(` is built at `:177` in `init`, not beside the refresh.
- D-6 corrected: the seed's reader list said `WatchWorkoutSummaryTests` holds the `heartRateNote(` calls; they are actually in `WatchExercisePageFitTests.swift:258, :266, :273, :280` (`WatchWorkoutSummaryTests` has none). Two source-guard tests pin the exact strings D-6 rewrites and must be updated in P1 (D-11): `WatchExercisePageFitTests.swift:299` and `WatchWorkoutSummaryWiringSourceTests.swift:58`.
- D-8 verified: `WatchMenuView.swift` is `#if os(watchOS)` (`:16`) like `WatchLoggingView.swift`, so the `WristHaptics()` default parameter compiles; the Finish action closure is `:210-214` and the Cancel button `:209`.
- D-7 verified: `WatchTimerKind.all = [rest, round, hold, elapsed]` (`WatchRecords.swift:23-29`), and `poll` already skips `rest` (`WatchTimerHaptics.swift:52`), so `cue(for:)` returning nil for `rest` matches the existing behaviour.

## Code pointers (current lines, read this run)

`HealthKitWorkoutStore.begin` catch (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift:147-155`):

```swift
        } catch {
            // Nothing is left registered: a session that started but whose
            // collection did not is a workout the user cannot see.
            session?.end()
            session = nil
            builder = nil
        }
```

`WatchPlatformWorkout.start` (`WatchPlatformWorkout.swift:299-307`):

```swift
    public func start(_ session: WatchSessionRecord) async -> WatchActivityType {
        if running != nil { await end() }

        let activityType = WatchActivityTypes.forSession(session) ?? WatchActivityTypes.generic
        await store.begin(
            activityType.watchOs,
            outdoors: WatchGpsPolicy.isRequired(session)
        )
        running = activityType
        return activityType
    }
```

`WatchWorkoutCoordinator.apply` (`WatchPlatformWorkout.swift:411-431`):

```swift
    private func apply(_ session: WatchSessionRecord?) async {
        if let opened = openedForSessionId, opened != session?.sessionId {
            await platform.end()
            openedForSessionId = nil
        }

        switch WatchWorkoutLifecycle.action(session: session, running: platform.running) {
        case .start:
            // Recorded before the store is asked, so a registration that never
            // arrives is not asked for a second time on the next refresh.
            openedForSessionId = session?.sessionId
            if let session { await platform.start(session) }
        case .end:
            await platform.end()
            openedForSessionId = nil
        case .none:
            break
        }
    }
```

`WatchWorkoutCoordinator.refresh` (`:401-403`): `public func refresh(_ session: WatchSessionRecord?) async { await enqueue { await self.apply(session) }.value }`

`WatchLoggingState.sensorNotices` (`WatchLoggingState.swift:319-327`):

```swift
    public var sensorNotices: [String] {
        guard let sensors else { return [] }
        var notices: [String] = []
        if sensors.locationAccess == .denied,
           WatchGpsPolicy.coversDistance(capabilities) {
            notices.append(WatchSensorNoticeCopy.noDistance)
        }
        return notices
    }
```

`WatchWorkoutSummary.heartRateNote` (`WatchWorkoutSummary.swift:93-95`) and its two callers:

```swift
    public func heartRateNote(healthOff: Bool) -> String? {
        averageBpm == nil && healthOff ? WatchSensorNoticeCopy.noHeartRate : nil
    }
```

- `WatchWorkoutSummaryView.swift:47`: `if let note = summary.heartRateNote(healthOff: healthOff) {`
- `ContentView.swift:420`: `WatchWorkoutSummaryView(summary: pending, healthOff: host.healthAccess == .off, onDone: { host.summary.dismissPending() })`

`WristHaptics` (`WatchLoggingView.swift:32-56`, file opens `#if os(watchOS)` at an earlier line; `play` at `:35-37`):

```swift
public struct WristHaptics: WatchHaptics {
    public init() {}

    public func play(_ milestone: WatchTimerMilestone) {
        WKInterfaceDevice.current().play(.notification)
    }
```

(also `playRestPing` → `.click` `:41-43`, `playLogged` → `.success` `:46-48`, `playNext` → `.directionUp` `:52-54`)

The `WatchHaptics` protocol (`WatchLoggingModel.swift:244-256`): `play(_:)`, `playRestPing()`, `playLogged()`, `playNext()` — no extension yet; `RecordingHaptics` (`:218-241`) is the only test fake.

The Finish alert in `WatchMenuView` (`WatchMenuView.swift:203-218`):

```swift
    private var finishRow: some View {
        Button(Self.finishLabel) {
            confirmingFinish = true
        }
        .buttonStyle(.bordered)
        .alert(WatchMenuCopy.confirmTitle, isPresented: $confirmingFinish) {
            Button(WatchMenuCopy.confirmCancel, role: .cancel) {}
            Button(WatchMenuCopy.confirmFinish) {
                Task {
                    await state.finish()
                    onFinish()
                }
            }
        } message: {
            Text(WatchMenuCopy.confirmBody)
        }
    }
```

`WatchTimerHaptics.poll` (`WatchTimerHaptics.swift:45-70`): loops `WatchTimerKind.all` (`WatchRecords.swift:29` = `[rest, round, hold, elapsed]`), skips `rest` at `:52`, appends a `WatchTimerMilestone(kind:at:)` per unannounced zero.

## Progress

| Item | Status |
|---|---|
| Verify every seed `file:line` and symbol against the code | done (corrections in Architect notes) |
| Check test fakes conforming to `WatchPlatformWorkoutStore` / `WatchHaptics` | done (5 store fakes, 1 haptics fake; defaults keep them compiling) |
| Check `workout.refresh` await site and `WatchLoggingState(` build site in ContentView | done (`:274` sink, `:177` init) |
| Check every `heartRateNote(` caller | done (view `:47`, ContentView `:420`, tests in `WatchExercisePageFitTests`) |
| Check `WatchHealthAccessWiringSourceTests` patterns survive | done (they pin other strings; the two that do break are covered by D-11) |
| Corrected decisions + Architect notes | done |
| P1/P2 files, items, scope globs, fixtures | done |
| Progress + Assumption Log | done |
| architect-notes.md report | done |
