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

## Phase 3 — the docs (no source file changed)

Four docs, all predicted, plus the plan's Progress and this file. The shell was read as shipped
(`ContentView.swift`): the three-way branch, the D-21 build order (`WatchEmitForwarder` over the
connectivity bridge), the in-memory store, and the default units.

| File | What the change makes true |
|---|---|
| `docs/watch-app-setup-and-qa.md` | §1's table row says "logging surface", not "the session's slot list"; §3.6 describes the three surfaces in branch order, the effort kinds the logging surface logs, End and the picker on it, and the sink (with `WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder`); §3.6's "not a logging screen" and "one thing the shell still does not have" are replaced by "What the wrist cannot do yet" — the in-memory store (D-27), the kg label, and a Sync stopping a rest countdown (D-26); steps 15–18 lose the Phase 7 condition (15's `*(needs Phase 7)*` deleted), 17 gains `*(needs the durable store — PR 4)*` with the test that proves the mechanism, 19–20 keep Phase 8; step *(f)* is present tense; "What QA passed means" reads 15–18 now / 19–20 after Phase 8 / 17 after PR 4; a four-step *(owner, not yet run)* walkthrough is added before it |
| `docs/state_management/watch_surface.md` | §"The wrist shell's second surface" is no longer a placeholder: the package's logging view for the current exercise's effort kind, the rest countdown a logged set starts (`WatchLoggingTimersTests.testS005…`), rows leaving as logged (`WatchEmitForwarderTests…`), no logging into an ended session (`WatchLoggingSurfacesTests.testS029…`), and the relaunch loss plus the two smaller gaps. An edit of the existing section, no section added (file stays far under 52 KB) |
| `docs/watch_session_sync.md` | "What does not sync" opens by saying wrist logging is no longer on the list (`watch_session_merge_test.dart` `S-9`/`S-19`, `watch_session_finish_test.dart` `S-4`) and adds four bullets: relaunch loss, no sensor samples, a Sync stopping a rest countdown (D-26), the kg label. The pre-existing bullets stand |
| `docs/plans/2026-10-05-15-watch-session-sync-index.md` | The PR 2b row's present-tense consequence corrected to "was dropped until this PR wired it" (the planner's own correction and the plan link were already in place — verified, not rewritten) |

Every behaviour sentence names an existing test by class and method, read from the test files; the
known-limit sentences (kg label, stopped countdown, relaunch loss, no sensor samples) are plain.

### Residue sweep (read-only search tool; every hit outside the live docs explained)

| Pattern | Hits in live docs (`docs/*.md`, `docs/state_management/`) | Hits elsewhere |
|---|---|---|
| `startedPlaceholder\|not a logging screen\|sink it lacks` | none | `docs/plans/2026-10-05-15c-…-plan.md` (this plan's own Phase 2 item and sweep text), `docs/plans/2026-10-05-15b-…-plan.md:388`, `docs/plans/2026-10-04-14-watch-shell-bridge-plan.evidence.md:380,387` (that unit's record), `docs/plans/2026-10-01-04c2-…-plan.md:678` ("opens the trend screen, not a logging screen" — unrelated) |
| `needs Phase 7` | none | `docs/plans/2026-10-05-15c-…-plan.md:330,332,351` (this plan's own Phase 3 item text) |
| `import .*hive_workout_repository` over `lib/state lib/features lib/widgets lib/core` | no matches (invariant clean) | — |

Plans are history and stay, per the brief.

### Green runs

| Check | Result |
|---|---|
| `gateway.sh swift-test` (full) | `Executed 267 tests, with 0 failures (0 unexpected) in 1.043 (1.063) seconds`, exit 0 — the Phase 2 count exactly (no package file changed) |
| `gateway.sh test` (full) | `01:38 +3913 ~1: All tests passed!`, exit 0 — the baseline (D-28), and it includes `test/docs_indexing_contract_test.dart`, so the 64 KiB ceiling and the content prohibitions hold on the two guarded docs. Re-run after the last sentence was added to §5 of the QA guide: `01:38 +3913 ~1: All tests passed!`, same counts |
| `gateway.sh lint` | `196 issues found. (ran in 3.1s)`, exit 1 — the plan's baseline 196 / 0; every line is a pre-existing info notice and none names a file this phase touched |
| `gateway.sh git-diff --stat` | `docs/state_management/watch_surface.md | 24 +++++-`, `docs/watch-app-setup-and-qa.md | 98 +++++----`, `docs/watch_session_sync.md | 23 ++++`, `.../2026-10-05-15-watch-session-sync-index.md | 2 +-` — 4 files, docs only, and the plan file separately (`17 insertions(+), 1 deletion(-)`, Progress and Assumption Log) |

No source file was changed, so this phase has no red-first run: the plan's D-28 records that Phase 3
is docs-only and the suite counts are unchanged.

Not run by this agent, and said so in the docs: the walkthrough is the **owner's** and is marked
*not yet run* — the governor could not tap through the simulator (no Screen Recording permission), so
no doc claims it passed.

## Fix round 1 — the review's bounded findings (F-1, F-2, F-3, F-4, F-5, F-7, F-8)

One pass over `<plan>.review.md`'s seven findings, on the same uncommitted tree. **F-6 (the deferred
`revision` bump) and F-9 (the Dart twin's `canLog`) were not touched** — the brief excludes them.

| Finding | Change | What the change makes true |
|---|---|---|
| F-1 | `docs/watch-app-setup-and-qa.md` walkthrough step 2 | The step no longer taps Sync: the phone must show the set with the wrist untouched, with the line "The phone must show it before any Sync — only an untouched wrist proves the set is handed over as it is logged". Sync stays in step 4, where a re-send is the point. Matches the plan's owner step 5 |
| F-2 | `docs/watch_session_sync.md` — the "Nothing starts, changes or finishes without a sync" bullet | Deleted. Replaced by "**Starting a session, changing exercises and converging two sessions still need a manual Sync.**", which points at `test/watch_session_projection_test.dart` (`S-2`) / `test/watch_session_merge_test.dart` for what needs a Sync and at `WatchEmitForwarderTests.testTheEnginesEmissionsReachTheSinkInOrder` for what does not. The bullet no longer contradicts the paragraph twelve lines above it (tests named were read out of the files, not invented) |
| F-3 | `docs/watch-app-setup-and-qa.md` §Level 1 | The dated count is gone: "Expected: **all passed, no failures.** Read the counts off the run rather than against a number here." The 0-failures form elsewhere is untouched |
| F-4 | `docs/plans/2026-10-05-15b-…-plan.md:387-391` | The clause now reads "pass the engine the `onEmit` sink that already existed unused — PR 2b's D-21 wires it (what the wrist now emits leaves the wrist)". The planner's own correction blockquote above it (`:378-385`) already said the sink exists; the item below it was what still read as the opposite. Sweep output below |
| F-5 | `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift` — `testS029aAPhoneCompletionClosesTheLoggingSurface` (`:424-466`), plus `phoneLifecycle` promoted from a `RatingHarness` method to a free function beside `preferencesDown`/`instant` (`WatchEffortRatingTests.swift:32-44`, its two call sites updated) | S-29a is covered: an active session ended by the phone's `session_lifecycle(completed)` frame. Red→green below |
| F-7 | `ios/OmniTrain Watch App/ContentView.swift:214-216` | `.onDisappear { pickingExercise = false }` on the logging surface's `NavigationStack`, so a picker left open when the surface goes away (End, or the switch to the owed question) cannot reappear over the next session. One modifier, `@State` on the same `struct ContentView`; **the Swift build is the governor's** — this file is not compiled by any check this agent may run, so what is claimed here is a reading, not an observation |
| F-8 | `docs/watch_session_sync.md` (four new limit sentences) and `docs/watch-app-setup-and-qa.md` (the two known gaps and the walkthrough's heading) | Relaunch bullet: the future-PR clause ("a durable wrist store is a separate item") deleted, limit kept. Countdown bullet: pointed at `timer_cleared.json` / `WatchLiveMirroringTests.testEveryReconciliationFixtureConverges`. Sensor bullet: re-phrased to the shell ("The watch app wires no sensor source", `ContentView.swift:69` builds no recorder) and pointed at `WatchSensorRecordingTests` / `test/watch_sensor_recording_test.dart` for the layer that does exist. Units bullet: re-titled "The wrist labels load in kilograms", naming the absent unit preferences and pointing at `WatchLoggingTimersTests.testS007APoundPreferenceStepsInPoundsStoredInKilograms`, which holds the kilogram payload. QA guide: the same pointer added to the kg gap, and the heading's `*(owner, not yet run)*` tags removed ("It has not been run on hardware yet") |

### F-4 sweep output (the grep the plan cites, run scoped to `docs/plans/*2026-10-05-15*`)

Pattern `sink it lacks|does not have today`:

| File:line | Line |
|---|---|
| `…/2026-10-05-15c-…-plan.evidence.md:218` | this line's own `startedPlaceholder\|not a logging screen\|sink it lacks` sweep row |
| `…/2026-10-05-15c-…-plan.review.md:30` | F-4's finding, quoting the 15b bullet |
| `…/2026-10-05-15c-…-plan.md:211` | the plan's own citation of the grep |
| `…/2026-10-05-15c-…-plan.md:345` | the plan's Phase 3 item 4, quoting the index's old wording |
| `…/2026-10-05-15c-…-plan.md:350` | the plan's Phase 3 residue-sweep item |

**No hit in the 15b plan, and none in the series index**: every remaining hit is this PR's own plan
text, its review or this file, all of them quoting the phrase rather than claiming the engine lacks a
sink. So S-28a's second half now holds in the sense that matters — no live document says the sink is
missing — and the row above records the quotation hits honestly instead of claiming an empty grep.

### F-5 red → green (one mutation, reverted exactly)

Mutation: in `WatchLoggingState.swift`, `canLog`'s D-23 condition removed — `engine.session?.status
== WatchSessionStatus.active && slot != nil` → `slot != nil` (the pre-D-23 form).

| Run | Command | Observed |
|---|---|---|
| Red | `gateway.sh swift-test` | `Executed 268 tests, with 8 failures (0 unexpected) in 1.061 (1.078) seconds`, exit 1. Four are the new test — `WatchLoggingSurfacesTests.swift:449` "XCTAssertFalse failed - S-29a a session the phone ended is not a surface to log into", `:453` "XCTAssertTrue failed" (`fields` non-empty), `:457` "failed - logging into a phone-ended session must throw", `:461` "XCTAssertEqual failed: (\"3\") is not equal to (\"2\") - the refused log appended no observation row". The other four are the pre-existing `testS029AnEndedSessionCannotBeLoggedInto` (`:409,410,414,418`) — expected, same guard |
| Restore | `gateway.sh git-diff -- watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` | empty output, exit 0 — the file is byte-identical to its committed state |
| Green | `gateway.sh swift-test` | `Executed 268 tests, with 0 failures (0 unexpected) in 0.961 (0.980) seconds`, exit 0 |

The brief's parenthetical for F-5 quotes the post-D-23 line as the "original"; the pre-D-23 form is
`slot != nil` alone (the PR's own Phase 1 evidence, "one-condition edit"), and that is what the
mutation used. Logged as A-14.

### Fix-round green runs

| Check | Result |
|---|---|
| `gateway.sh swift-test` | `Executed 268 tests, with 0 failures (0 unexpected) in 0.961 (0.980) seconds`, exit 0 — the baseline 267 plus S-29a |
| `gateway.sh test` | `01:40 +3913 ~1: All tests passed!`, exit 0 (`.work/gateway/test-20261005-230601-2650.log`) — the baseline (D-28) exactly, over the final tree, including `test/docs_indexing_contract_test.dart` with the two edited docs, this plan and this file. An earlier run of the same check on the same code (`01:39 +3913 ~1`) cleared the doc edits before the plan and evidence were appended |
| `gateway.sh lint` | `196 issues found. (ran in 5.4s)`, exit 1 — the plan's baseline 196 / 0, every line a pre-existing info notice, none in a file this round touched. No Dart file changed after this run |

Not run by this agent: the watch app's `xcodebuild` (the governor's), so F-7's `.onDisappear` and the
whole shell remain compiled-nowhere claims until the governor builds the scheme.


