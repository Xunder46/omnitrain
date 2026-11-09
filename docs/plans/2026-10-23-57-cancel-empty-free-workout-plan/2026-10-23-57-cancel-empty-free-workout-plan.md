# Feature: 57 — closing the Free workout picker without choosing cancels the workout

> Status: BUILT, PROVED, DOCUMENTED AND REVIEWED 2026-10-23 (uncommitted; evidence and review beside the plan; owner device checks open, QA step 20). Owner: watch audit 3 (2026-10-23), fix order item 2, in chat. Series: with plan 56. Base commit: `.work/2026-10-23-57/base.txt`. Working branch: the one checked out; never create or switch branches. Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md.

## Goal and acceptance

| What you do | Now | After 57 |
|---|---|---|
| On the watch start screen tap Free workout, then close the exercise picker (the sheet's close button or a swipe) without choosing an exercise | an empty workout stays running underneath; the start screen looks normal, nothing on the watch can end it, and the phone may see a live session | the empty workout is cancelled; you are back on the start screen exactly as before you tapped Free workout, and the phone treats it as given up (an abandoned empty session is consumed without history, `lib/core/services/watch_session_importer.dart:156`) |
| Tap Free workout again afterwards | works only because a second start is allowed over the stuck one | starts a fresh workout and opens the picker again |
| Tap Free workout and pick an exercise | the logging screen opens | unchanged |
| The phone pushes an exercise into the empty workout while the picker is open and you then close the picker | (the workout continues with that exercise once the screen refreshes) | unchanged: the workout is not cancelled because it is no longer empty |
| Add Exercise from the session menu, mid-workout | picker | unchanged (a different picker; this plan does not touch it) |

## Decision Ledger

- D-1 New `WatchSessionStartPaths.cancelEmptyFreeWorkout() async -> Bool` in `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, after `startFreeWorkout()` (current l.563-565: `public func startFreeWorkout() async -> WatchSessionRecord { await engine.createSession(modality: nil) }`): `guard let held = engine.session, held.status == WatchSessionStatus.active, held.exercises.isEmpty else { return false }; await engine.abandonSession(); return true`. The guard is the whole safety: a session that has an exercise, or is not active, is never touched. `engine.abandonSession()` (`WatchSessionEngine.swift:385`) writes status `abandoned`, lifecycle `abandoned`; entries logged stay logged (none here). The name starts with `cancel`, not a verb the append-only source guard bans. (Confirm the type name that holds `startFreeWorkout` before editing; the builder reads l.540-566.)
- D-2 `WatchStartView.swift`: the picker sheet (`.sheet(isPresented: $pickingExercise) { WatchExercisePickerView(...) }`, l.176-181) gets `onDismiss:` running `Task { if await paths.cancelEmptyFreeWorkout() { onFreeWorkoutCancelled() } }`. No "did the user pick" flag: after a pick the session has an exercise, so the guard in D-1 is false and nothing is cancelled. New init parameter `onFreeWorkoutCancelled: @escaping () -> Void = {}` stored as a `let`, placed after `onSessionStarted`.
- D-3 `ios/OmniTrain Watch App/ContentView.swift` (the `WatchStartView(` call, l.386-390: `paths: host.paths, onSessionStarted: { _ in host.noteSurfaceChange() }, onOpenNutrition: ...`): pass `onFreeWorkoutCancelled: { host.noteSurfaceChange() }` so the root re-reads the engine. The host already shows the start screen for a session that is not active-with-exercises (`ContentView.swift` l.~361-364), so no routing change.
- D-4 Not in this plan: the watch's HealthKit workout lifecycle on abandon (the governor checks on the simulator that no workout session is left running and reports it); a Cancel button inside the picker (the sheet's own close is the control the owner named).

## Readers listed

- `WatchStartView(` call sites: `ContentView.swift`; grep `WatchStartView(` in `watch/ ios/` for tests and previews (the new parameter has a default, so no caller breaks).
- Source-text readers of `WatchStartView.swift` / `ContentView.swift`: `WatchNutritionWiringSourceTests.swift` (S-7201/S-7205, S-8311/S-8312/S-8318): rerun it.
- Tests that call `startFreeWorkout`: `WatchSessionStartPathsTests.swift` (l.666, 704, 763, 774, 792): unchanged behaviour, rerun the file.
- `abandonSession()` callers: none in `Sources` besides the definition today (grep 2026-10-23); no existing wrist surface depends on it.
- Scenario ids S-8701..S-8720 checked free (grep 2026-10-23).

## Core scenarios

New `WatchCancelEmptyFreeWorkoutTests.swift`, built on `WatchStartHarness` (internal class in `WatchSessionStartPathsTests.swift`, l.~66; members `engine`, `paths`, `store`; start with `let harness = WatchStartHarness(); await harness.launch(); _ = try await harness.receive(try firstMessage())` as `testS002FreeWorkoutStartsEmptyAndAddsAFallbackExercise` does at l.696-704, and take a catalog exercise from `harness.paths.fallbackExercises`; do not invent a new harness; if `firstMessage()` is private to that file, copy its few lines):
- S-8701 `startFreeWorkout()` then `cancelEmptyFreeWorkout()` returns true; `engine.session?.status == WatchSessionStatus.abandoned`. Fails without the change (method missing; with a stub returning false, fails the assertion).
- S-8702 after S-8701, `startFreeWorkout()` returns a session with a different `sessionId`, status active, no exercises.
- S-8703 (arm: has an exercise) `startFreeWorkout()`, then `addExerciseToSession(<catalog exercise from the harness>)`; `cancelEmptyFreeWorkout()` returns false, status stays active, one exercise.
- S-8704 (arm: phone slot arrives) `startFreeWorkout()`, then `engine.insertExercise(slot, moveTo: false)` (the phone's push); cancel returns false, status active.
- S-8705 (arm: not active) `startFreeWorkout()`, `engine.finishSession()`; cancel returns false and status stays `completed`; and with no session at all cancel returns false.
- S-8706 source guards (comment lines stripped, like `WatchNutritionWiringSourceTests`): `WatchStartView.swift` contains `onDismiss:` on the picker sheet and `cancelEmptyFreeWorkout()` and `onFreeWorkoutCancelled()`; `ContentView.swift` contains `onFreeWorkoutCancelled: { host.noteSurfaceChange() }`.

## Phases

- P1 (≤6 items) `crew-builder-watch`: D-1, D-2, D-3 and the test file. Scope: `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`, `ios/OmniTrain Watch App/ContentView.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchCancelEmptyFreeWorkoutTests.swift`. Brief opens with "Never run the full `flutter test`", asks for the report first as a skeleton; Done: `swift test --filter WatchSessionEngineTests`, plus `--filter WatchSessionStartPathsTests` and `--filter WatchNutritionWiringSourceTests`.
- Runs after plan 56 P1-P3 (both touch `ContentView.swift`; one Swift package).
- P2 `crew-docs-keeper`: the docs that describe the Free workout flow (grep `docs/state_management/watch_surface*.md`, `watch/PROTOCOL.md` is outside its ceiling: only if a protocol sentence is wrong, the governor routes it to `crew-builder-watch`).

## Verify (governor)

`swift test` full, `xcodebuild`, invariant grep; mutations (guard `held.exercises.isEmpty` removed, `status ==` arm removed, `onDismiss` removed); simulator: tap Free workout, close the picker, see the start screen, confirm in the host log that the session is abandoned, tap Free workout again.

## Progress

All phases done 2026-10-23: see the evidence file.
