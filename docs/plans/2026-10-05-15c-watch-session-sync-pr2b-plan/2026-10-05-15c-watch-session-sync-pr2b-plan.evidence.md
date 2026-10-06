# Evidence — watch-session-sync PR 2b, Phase 1 (the sink adapter and the active-session guard)

Developer run, Copilot CLI. Every figure below is observed output from
`.github/copilot/scripts/macos/gateway.sh`; nothing is inferred from a successful analyze.

## Baselines (plan-measured, before this phase)

| Check | Baseline |
|---|---|
| `gateway.sh swift-test` | `Executed 261 tests, with 0 failures` (measured on `612b356`) |
| `gateway.sh test` (full) | `+3913 ~1` — 0 failures |
| `gateway.sh lint` | 196 issues, 0 errors |

## Phase 0: the tests

Two test surfaces, both over the real engine and an in-memory store — no concrete production
implementation is mocked around.

- `testS029AnEndedSessionCannotBeLoggedInto` added to `WatchLoggingSurfacesTests.swift` (S-29, the
  wrist's own End). Fixture: a free session created with one explicit slot, one set logged, then
  `engine.finishSession()`. It asserts `canLog == false`, `fields.isEmpty`, a throwing `log()`, and
  that the refused log appended no row to `engine.observations`.
- `WatchEmitForwarderTests.swift` is new (5 tests): the emission-order proof with a slow first frame
  (S-20), the same for the engine's own session's frames through the real sink (S-20/S-22's emission
  half), a transport that refuses every frame (S-26, reported once each and never handed over), one
  refused frame followed by an accepted one (S-26, nothing queued behind the refusal), and a slow
  refusal that must not let the frame behind it overtake (S-26/S-27, "no retry, no reorder").

Recorded honestly: the fifth test failed on its first run — the assertion listed four frame types and
the engine sends five, because the log's own follow-on rest timer emits a `timer_state` frame between
the set and the session end. The fixture was corrected to the observed sequence
(`session_lifecycle`, `observations_up`, `timer_state`, `observations_up`, `session_lifecycle`) rather
than the assertion loosened; that is the emission order this fixture produces, and the engine's own
suites are what pin the frames themselves.

## Red-first proof 1 — the `canLog` guard (S-29)

Test added, source untouched:

`gateway.sh swift-test --filter WatchLoggingSurfacesTests/testS029AnEndedSessionCannotBeLoggedInto` →
`Executed 1 test, with 4 failures (0 unexpected) in 0.103`, exit 1.

```
WatchLoggingSurfacesTests.swift:409: XCTAssertFalse failed - a finished session is not a surface to log into
WatchLoggingSurfacesTests.swift:410: XCTAssertTrue failed
WatchLoggingSurfacesTests.swift:414: failed - logging into a finished session must throw
WatchLoggingSurfacesTests.swift:418: XCTAssertEqual failed: ("3") is not equal to ("2") - the refused log appended no observation row
```

The third and fourth are the defect: with the old guard `canLog` was true, `fields` was populated,
`log()` succeeded, and a set was appended to a session that was over.

With the one-condition edit in `WatchLoggingState.canLog` (`engine.session?.status ==
WatchSessionStatus.active && slot != nil`), same command → `Executed 1 test, with 0 failures
(0 unexpected) in 0.004`, exit 0.

## Red-first proof 2 — the forwarder's ordering (S-20)

Mutation applied to `WatchEmitForwarder.swift` — the serial tail removed from `enqueue`, i.e. the
frame is no longer chained behind the one before it:

```swift
-        let previous = tail
         let send = self.send
         let onFailure = self.onFailure
         let next = Task {
-            await previous?.value
             do {
```

`gateway.sh swift-test --filter
WatchEmitForwarderTests/testFramesAreHandedOverInEmissionOrderWhenTheFirstSendIsSlow` →
`Executed 1 test, with 1 failure (0 unexpected) in 0.066`, exit 1:

```
WatchEmitForwarderTests.swift:90: XCTAssertEqual failed: ("["second"]") is not equal to ("["first", "second"]")
```

The slow first frame was overtaken, which is the bug the test exists for. The exact original restored,
re-run green (below).

## The module's own append-only guard caught a name

The first full run with the new file in place was **not** green:

`gateway.sh swift-test` → `Executed 267 tests, with 1 failure (0 unexpected) in 1.072`, exit 1:

```
WatchSessionEngineTests.swift:286: error: testS004NoMutatingOperationExistsAnywhereInTheModule
  XCTAssertTrue failed - WatchEmitForwarder.swift declares a mutating …
```

The guard is a name-based scan for a `func` whose name begins with a mutating verb, and the test seam
was called `settle()` — `set` + `tle`. Renamed to `drain()`; no other line changed. The guard is
doing its job (a reader skimming the module should never meet a name that reads as a mutation), so the
name was changed rather than the guard.

## Green runs

| Check | Result |
|---|---|
| `gateway.sh swift-test` (full, after the rename) | `Executed 267 tests, with 0 failures (0 unexpected) in 1.024 (1.043)`, exit 0 — 261 baseline + 6 new |
| `gateway.sh test` (full) | `01:40 +3913 ~1: All tests passed!`, exit 0 — unchanged from the baseline (D-28: no Dart changed) |
| `gateway.sh lint` | `196 issues found. (ran in 3.0s)`, exit 1 — the plan's baseline 196/0; no Dart file in this phase, so the count cannot have moved and no issue names a file this phase touched |

## Footprint

`gateway.sh git-status` (this phase's rows only):

```
 M watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift
 M watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift
?? watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift
?? watch/watchos/Tests/WatchSessionEngineTests/WatchEmitForwarderTests.swift
```

`gateway.sh git-diff --stat`: `WatchLoggingState.swift | 9 +++++-`, `WatchLoggingSurfacesTests.swift |
35 ++++++++++++++++++++++` — the two files the plan predicted, nothing else. The two new files are
untracked (`git diff` does not list them). No scratch file was created; nothing was formatted (the
repository's formatter check is `dart format` on new Dart files, and this phase adds none).

Not run by this agent, and left to the governor: `xcodebuild` for the watch app target (Phase 2 hosts
these surfaces; Phase 1 is inert in the app because nothing constructs the adapter yet).

# Evidence — watch-session-sync PR 2b, Phase 2 (the shell hosts the surfaces)

Developer run, Copilot CLI, appended 2026-10-05. One file changed:
`ios/OmniTrain Watch App/ContentView.swift` — the plan's whole Predicted Files row.

## Why this phase has no red-first run of its own

The shell is SwiftUI behind `#if os(watchOS)` in the app target, which is not part of
`watch/watchos` and has no test target: no command available to an agent compiles it. Phase 2's items
are wiring, not new package logic, and the plan assigns it no test item — the register's shell
clauses (S-28 "the surface shown first", S-23/S-29 "lands on the start surface", S-30's pick) are
SwiftUI branches, and their state-level halves are the package's own tests
(`testS029AnEndedSessionCannotBeLoggedInto` plus `WatchEffortRatingTests`' owed-prompt pair). Those
branches are verified by the owner walkthrough, not asserted here.

## Signature audit — every package member the shell now calls

The shell cannot be compiled here, so each call site was matched against the package by hand.
Read from source, with the declaring file and line:

| Shell call | Package declaration |
|---|---|
| `WatchConnectivityBridge(session:onFailure:)` | `WatchConnectivityBridge.swift:86` |
| `WatchEmitForwarder(transport:onFailure:)` | `WatchEmitForwarder.swift:47` |
| `WatchEmitForwarder.sink` → `WatchMessageSink` = `([String: Any]) -> Void` | `WatchEmitForwarder.swift:66`, `WatchSessionEngine.swift:24` |
| `WatchSessionEngine(store:onEmit:)` | `WatchSessionEngine.swift:84` |
| `WatchSessionStartPaths(engine:store:)` | `WatchStartPaths.swift:252` |
| `WatchPhonePreferences(store:)` | `WatchPhonePreferences.swift:92` |
| `WatchSyncOrchestrator(transport:paths:engine:preferences:)` (`nutrition:` defaults nil) | `WatchSyncOrchestrator.swift:58` |
| `WatchLoggingState(engine:)` (clock, units, rest, sensors all default) | `WatchLoggingState.swift:174` |
| `WatchEffortRatingState(engine:store:preferences:)` | `WatchEffortRating.swift:114` |
| `WatchEffortRatingState.isPromptOwed` / `.objectWillChange` (`ObservableObject`) | `WatchEffortRating.swift:196` / `:91` |
| `WatchLoggingView(state:)` (`haptics:` defaults) | `WatchLoggingView.swift:53` |
| `WatchEffortRatingView(state:)`, `WatchEndSessionView(state:)` | `WatchEffortRatingView.swift:30`, `:102` |
| `WatchStartView(paths:onSessionStarted:onRequestSync:phoneReachability:revision:)` (`onOpenNutrition:` defaults nil) | `WatchStartView.swift:114` |
| `WatchExercisePickerView(paths:revision:onExerciseAdded:)` — trailing closure is the last parameter | `WatchStartView.swift:219` |
| `WatchSessionStatus.active` | `WatchRecords.swift:18` |
| `InMemoryWatchSessionStore()` | `WatchSessionStore.swift:137` |
| `OmniTrainWatchConnectivity(onSendFailure:)` | `OmniTrainWatchConnectivity.swift:65` |

Every one accepts the labels, order and defaults the shell passes. Two traps the audit was run for,
and both hold: the sink is a *non-`async`* `([String: Any]) -> Void`, so `forwarder.sink` fits
`onEmit` directly, and `onOpenNutrition`/`onRequestSync`/`phoneReachability`/`revision` all default,
so the start surface is called with the four arguments it needs.

## Green runs

| Check | Result |
|---|---|
| `gateway.sh swift-test` (full) | `Executed 267 tests, with 0 failures (0 unexpected) in 1.027 (1.046) seconds`, exit 0 — the Phase 1 count exactly (no package file changed; the shell is not in the package) |
| `gateway.sh test` (full) | `01:36 +3913 ~1: All tests passed!`, exit 0 — unchanged from the baseline (D-28: no Dart changed) |
| `gateway.sh lint` | `196 issues found. (ran in 3.2s)`, exit 1 — the plan's baseline 196/0, and no issue names a file this phase touched (it changes no Dart file) |
| `gateway.sh git-diff --stat` | `ios/OmniTrain Watch App/ContentView.swift | 134 ++++++--------`, "1 file changed, 100 insertions(+), 34 deletions(-)" |

`gateway.sh git-status` after the phase: ` M "ios/OmniTrain Watch App/ContentView.swift"` and nothing
else — no scratch file, no doc mutated (Phase 3 owns the docs), no Dart touched. Nothing was
formatted.

Not run by this agent, and named as such in `## Progress`: `xcodebuild` for the watch app target
*(governor)*, and the owner walkthrough *(owner)*. This agent cannot run either.

## What the shell does, and the two decisions behind it

The body branches in D-24's order — the owed question first (nothing else on screen, R-3), then the
logging surface, then `WatchStartView` — and the host bumps `revision` on an arrival (pre-existing),
on a rating-state change (a deferred `Task { @MainActor }`, because `objectWillChange` fires *before*
`end()`/`confirm()` mutate), and on a start/pick (`noteSurfaceChange()`).

Two decisions, both in the plan's Assumption Log as A-8 and A-9: the logging branch requires the
session to be active **and** hold at least one exercise (the brief's override of D-24 — a Free
workout has no slot, so it stays on the start surface until one lands), and the picker sheet closes
itself on the pick that switched the exercise.
