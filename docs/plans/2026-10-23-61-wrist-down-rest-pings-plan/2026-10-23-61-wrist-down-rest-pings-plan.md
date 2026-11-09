# Feature: 61 — the wrist pings on time with the screen down, and a dimmed screen shows a correct rest clock

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (APPROVE WITH MINORS; uncommitted; owner device checks open). Owner: watch audit 3 (2026-10-23), fix order item 5, in chat. Series: with plan 62 (full sync on every raise). Base commit: `.work/2026-10-23-61/base.txt`. Working branch: the one checked out (`claude_develop`); never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 61 |
|---|---|---|
| Log a set with the phone's Rest Ping on 30 s, lower your wrist and let the screen turn off or dim | the tap comes late or not at all: the ping is asked only while the rest screen is being drawn, and a screen that is off or dimmed is not redrawn | the wrist taps at 30 s, 60 s, 90 s on time while the workout runs with the screen off or dimmed (device check: owner, QA step) |
| Raise the wrist after a long rest | the first tap is owed the moment the screen redraws | the missed boundaries are caught up with one tap at once, as today for a gap (S-243); nothing taps twice for one boundary |
| Look at the rest screen while the watch is in its dimmed (always-on) state | the large m:ss clock is shown and shows the second it was last drawn | the dimmed screen shows whole minutes only ("3 min") and changes exactly when the rest reaches the next full minute; the m:ss clock returns when you raise the wrist |
| Rest Ping is Off on the phone | no taps | unchanged: no taps |
| Leave the rest with Next, or log the next set | the ping stops | unchanged: the ping stops at once and the next rest starts its own count |
| The phone's own rest notification (phone locked, watch on the wrist) | unknown whether the watch taps for it as well | unchanged in this plan: **owner check** (QA step): if the watch taps twice at a boundary, the phone's notification is the second tap and a follow-up plan decides which one yields (product decision) |

Not in this plan: Health workout type, any change to what the phone schedules, the phone-side notification text, the Dart twin in `lib/watch`.

## Facts from the scouts (`.work/crew/2026-10-23-61/scout-ping.md`, `scout-phone-notify.md`; two items spot-checked against files)

- The only producer of a wrist ping is `WatchRestView.pingIfOwed()` (`watch/watchos/Sources/WatchSessionEngine/WatchRestView.swift:93-100`), asked from inside `TimelineView(.periodic(from: .now, by: 1))` (l.59). Nothing else reaches `WatchRestPing.isOwed` / `haptics.playRestPing()`.
- The wrist app is kept alive with the wrist down by the workout: `ios/OmniTrainWatchApp-Info.plist` declares `WKBackgroundModes = workout-processing`, and the `HKWorkoutSession` follows the session, so it is open during a rest (`WatchPlatformWorkout.swift:364-383`). Nothing in the wrist code reads `isLuminanceReduced` or `isAlwaysOn`. So the process runs; the view does not redraw.
- The rest clock is already derived from the persisted row (`restElapsedSeconds()` -> `activeElapsedMs(rest, now: clock())`, `WatchLoggingState.swift:387-390`), so a redrawn screen is correct; only the dimmed redraw cadence and format are missing.
- Phone side: `RestNotificationService.scheduleRestPings` (`lib/core/utils/rest_notification_service.dart:268`) schedules plain local notifications (no thread id, no interruption level) at every boundary when the phone app is not in the foreground; it is also scheduled for a rest the wrist started (`workout_session_screen.dart` `_scheduleActiveRestNotifications`, called from `_onWorkoutStateChanged`); nothing is suppressed because the watch is paired or pinging. iOS mirrors such a notification to the wrist when the phone is locked. This is the double-tap surface; it cannot be seen without the device.
- Haptic from a backgrounded workout app: Apple's workout apps do this; unprovable on the simulator -> owner check.

## Decision Ledger

- D-1 New file `watch/watchos/Sources/WatchSessionEngine/WatchRestPingScheduler.swift` (not `#if os(watchOS)`, so `swift test` covers it): `@MainActor public final class WatchRestPingScheduler` owning one `WatchRestPing` (the existing rule, unchanged). Init: `init(state: WatchLoggingState, interval: @escaping () -> Int, haptics: WatchHaptics, sleep: @escaping (TimeInterval) async -> Void = WatchRestPingScheduler.realSleep)`; `realSleep` is `{ seconds in try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }`.
  API (names avoid every verb the append-only source guard bans):
  - `public func step() -> TimeInterval?` — asks the rule once with `restId: state.engine.timerFor(WatchTimerKind.rest)?.recordId`, `elapsed: state.restElapsedSeconds()`, `interval: interval()`; plays `haptics.playRestPing()` if owed; returns `Self.nextWait(elapsedMs: state.restElapsedMilliseconds(), interval: interval())`, nil when no rest is open or the interval is Off.
  - `public func arm()` — cancels the pending loop, then starts `loop = Task { @MainActor [weak self] in while !Task.isCancelled, let self, let wait = self.step() { await self.sleep(wait) } }`. `step()` runs first, so arming also catches up a boundary crossed while nobody was looking.
  - `public func disarm()` — cancels and drops the loop.
  - `public func finished() async` — `await loop?.value` (tests wait on it).
  - `public static func nextWait(elapsedMs: Int, interval: Int) -> TimeInterval?` — nil for `interval <= 0` or `elapsedMs < 0`; else `Double(interval*1000 - elapsedMs % (interval*1000) + 50) / 1000` (the 50 ms lands the wake just after the boundary, never before it).
- D-2 `WatchLoggingState.swift`, beside `restElapsedSeconds()` (current l.387-390: `public func restElapsedSeconds() -> Int? { guard isResting, let rest = engine.timerFor(WatchTimerKind.rest) else { return nil }; return activeElapsedMs(rest, now: clock()) / 1000 }`): add `public func restElapsedMilliseconds() -> Int?` (same guard, returns `activeElapsedMs(rest, now: clock())`), `public var restStartedAt: Date?` (`isResting ? engine.timerFor(WatchTimerKind.rest)?.startedAt : nil`) and `public static func dimmedRestClock(seconds: Int) -> String` returning `"\(max(0, seconds) / 60) min"`. `restElapsedSeconds()` keeps its body.
- D-3 `WatchRestView.swift` stops pinging: remove `pingIfOwed()`, the `@State private var ping`, the `restPingSeconds` property and init parameter (the host owns the ping now). Dimmed clock: add `@Environment(\.isLuminanceReduced) private var dimmed`; the timeline becomes `TimelineView(.periodic(from: state.restStartedAt ?? Date(), by: dimmed ? 60 : 1))` (a minute schedule anchored on the rest's own start, so the label changes exactly when the rest reaches a full minute); the private `elapsed` property keeps its name and its `Text(elapsed)` call (S-8621 reads that chain) and becomes `let seconds = state.restElapsedSeconds() ?? 0; return dimmed ? WatchLoggingState.dimmedRestClock(seconds: seconds) : WatchLoggingState.clock(Double(seconds))`. The header's doc comment (l.13-18) is updated to say the ping belongs to the host's scheduler. watchOS 9 API only (`isLuminanceReduced` exists since watchOS 7).
- D-4 `ios/OmniTrain Watch App/ContentView.swift`: `WatchAppHost` owns `let restPings: WatchRestPingScheduler`, built in `init` after `logging` and `preferences` exist as `WatchRestPingScheduler(state: logging, interval: { preferences.restPingSeconds }, haptics: WristHaptics())` (the builder reads the init to find the local names). `restPings.arm()` is called (a) at the top of the existing `$revision` sink Task (l.249-257), before the awaits, and (b) in `catchUpOnActivation()` (l.~350). The `WatchRestView(` call (l.~220) loses its `restPingSeconds:` argument. Every rest start/end goes through `revision` (`noteSurfaceChange`, frame receipt, `rating.objectWillChange`); the builder greps `revision += 1` and `noteSurfaceChange` call sites and reports any rest open/close path that does not bump it.
- D-5 What stays: `WatchRestPing` (the rule), `WatchHaptics`/`WristHaptics.playRestPing` (`WKInterfaceDevice.current().play(.click)`), the preference sync, and the phone's notifications.
- D-6 Fallback if the device check shows the app does not tap with the wrist down: a local notification scheduled from the wrist at each boundary (not built: it would double-tap whenever the app does run). Decision deferred to the owner's result.

## Readers listed

- `WatchRestView(` call sites: `ContentView.swift` only (grep `WatchRestView(` in `watch/ ios/`; builder re-greps).
- Source-text readers of `WatchRestView.swift` / `ContentView.swift`: grep `WatchRestView.swift`, `restPingSeconds: {`, `pingIfOwed` in `watch/watchos/Tests` (the scout found none for the view; the wiring is pinned through the Dart twin S-226, which is unaffected: `lib/watch` is not edited).
- `WatchRestPing` readers: `WatchRestPingTests.swift` (unchanged, rerun), `test/watch_rest_ping_test.dart` and `watch/contract/watch_rest_ping_contract.json` (unchanged).
- `restElapsedSeconds` callers: unchanged body; rerun the whole `WatchSessionEngineTests`.
- Scenario ids S-9101..S-9120 checked free (grep of `S-[0-9]{4}` prefixes 2026-10-23: nothing at 91).

## Core scenarios (fixtures re-derived with a throwaway script)

New `watch/watchos/Tests/WatchSessionEngineTests/WatchRestPingSchedulerTests.swift`. Copy the harness block of `WatchRestPingTests.testS224AClosedRestIsNeverEvaluated` (it drives a real `WatchLoggingState` with a controllable clock and a logged set that opens a rest) and `RecordingHaptics` from `WatchLoggingModel.swift`. A rest with interval 30 s starts at `t0`.
- S-9101 `nextWait` table (interval 30): elapsedMs 0 -> 30.05; 12345 -> 17.705; 29990 -> 0.06; 30000 -> 30.05; 59999 -> 0.051; interval 0 -> nil; interval -5 -> nil; elapsedMs -1 -> nil. Fails without the change: the function does not exist.
- S-9102 `step()` at `t0+29.9 s`: no ping, returns 0.15; at `t0+30.05 s`: one ping, returns 29.95 + 0.05 = 30.0; again at `t0+30.06 s`: still one ping total (one ping per boundary).
- S-9103 a gap: first `step()` at `t0+95 s` pings once (boundaries 30, 60, 90 crossed), returns 25.05.
- S-9104 interval Off: the closure returns 0 -> `step()` never pings and returns nil; the closure then returns 30 and the clock is at `t0+31 s` -> the next `step()` pings once (a mid-rest sync is heard).
- S-9105 the loop: `arm()` with a sleeper that advances the test clock by the requested seconds, and on its 3rd call ends the rest (`await state.endRest()`); `await scheduler.finished()`; pings == 2, sleeper calls == 3, requested waits == [30.05, 30.0, ...] (first two asserted exactly).
- S-9106 `disarm()`: arm, then disarm before the sleeper returns -> after `finished()` no further ping and no further sleeper call; `arm()` twice in a row pings exactly as often as one `arm()` (the first loop is cancelled).
- S-9107 no rest open (session with no timer): `step()` returns nil and plays nothing; a stopped rest row is never evaluated.
- S-9108 `dimmedRestClock`: 0 -> "0 min"; 59 -> "0 min"; 60 -> "1 min"; 185 -> "3 min"; 3599 -> "59 min"; -4 -> "0 min".
- S-9109 source guards in `WatchRestPingWiringSourceTests.swift` (comment lines stripped, helper copied from `WatchNutritionWiringSourceTests`), each asserting the exact statement incl. braces, the rendered text AND the init storage (checklist ao): `WatchRestView.swift` contains `@Environment(\.isLuminanceReduced) private var dimmed`, `TimelineView(.periodic(from: state.restStartedAt ?? Date(), by: dimmed ? 60 : 1))` and `? WatchLoggingState.dimmedRestClock(seconds: seconds)` and `: WatchLoggingState.clock(Double(seconds))`, and contains none of `pingIfOwed`, `isOwed`, `restPingSeconds`; `ContentView.swift` contains `WatchRestPingScheduler(state: logging, interval: { preferences.restPingSeconds }, haptics: WristHaptics())` and exactly two `restPings.arm()` statements (one inside the `$revision` sink, one inside `catchUpOnActivation()`: asserted by slicing the function bodies) and no `restPingSeconds:` argument on the `WatchRestView(` call.

The lead proves the guards by mutation (see Verify). Each arm of a multi-arm guard has its own case: S-9102 (no ping before / one after / none twice), S-9104 (Off arm, mid-rest-sync arm).

## Phases

- P1 `crew-builder-watch` (6 items): D-1, D-2 and S-9101..S-9108 in `WatchRestPingSchedulerTests.swift`. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchRestPingScheduler.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchRestPingSchedulerTests.swift`. Brief: report first as a skeleton; never the full `flutter test`; Done: `swift test --filter WatchRestPingSchedulerTests`, `--filter WatchRestPingTests`, `--filter WatchSessionEngineTests`.
- P2 `crew-builder-watch` (after P1; both are in one Swift package): D-3, D-4 as exact replacement text, and S-9109 in `WatchRestPingWiringSourceTests.swift`. Scope: `WatchRestView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, the new test file. The lead builds with `xcodebuild` (checklist an).
- P3 `crew-docs-keeper` (after the last test-adding round): docs that describe the rest ping and the rest screen (grep `docs/state_management/watch_surface_wrist.md`, `docs/watch-app-setup-and-qa.md`): the ping moved from the view to the host scheduler; the dimmed minutes clock; the owner device checks as QA steps (the brief names the list).

## Verify (governor)

`swift test` full in `watch/watchos`; `xcodebuild` per checklist (an); invariant grep; `flutter analyze` unchanged count; the two contract tests. Mutations: `nextWait` margin removed; `step()` ping call removed; `arm()` without cancel; `step()` first call removed from the loop; `disarm` no-op; `by: dimmed ? 60 : 1` -> `by: 1`; the `arm()` call in the `$revision` sink removed; in `catchUpOnActivation` removed; `dimmedRestClock` `/ 60` -> `/ 1`. Simulator: seed a rest, check the rest screen still renders (m:ss) and the host log; the dimmed state and the haptic with the wrist down cannot be seen on the simulator: say so, mark `(owner)`.

## Owner device checks (owner)

1. Rest Ping 30 s on the phone, start a workout on the watch, log a set, lower the wrist so the screen goes dark: a tap at 30 s, 60 s, 90 s.
2. Same with the screen dimmed but on (Always On): the rest shows "N min"; raise the wrist: m:ss again and correct.
3. Phone locked and the watch on the wrist, phone app in the background: at a boundary count the taps. One tap = fine. Two taps close together = the phone's notification mirrors as a second tap; tell me and a follow-up plan decides which one yields.

## Progress

P1, P2 and P3 done 2026-10-23 (P3: docs and evidence). Owner device checks open. Reviewed 2026-10-23 (review file beside plan 62); fix 2 (one clock read per step, S-9110) done; final tree: `xcodebuild` BUILD SUCCEEDED, swift 875/0, flutter 5483 passed (2 skipped), analyze 180 (unchanged baseline).
