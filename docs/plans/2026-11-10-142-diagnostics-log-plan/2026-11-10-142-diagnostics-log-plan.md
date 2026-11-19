# Plan — 142: the watch keeps a diagnostics log (observation only)

**Status**: seeded by the lead 2026-11-10; not built.
**Base commit**: `f1e737cf` (branch `claude_develop`).
**Parent**: the watch overview of 2026-11-10 (recommendation A). Sibling: plan 143 (the phone's log and its Settings button).

## Overview

Owner (2026-11-10, real device): the watch app was closed and reopened in the middle of a session, and nothing on the device says why, when or what it was doing. This plan gives the watch its own record of what happened, and a screen on the wrist to read it. It changes no sync, workout or timer behaviour.

What the user sees: a small "Diagnostics" button at the bottom of the watch's Start screen. It opens a screen that says how the app last started ("Started 21:04 — restarted by the system"), what the app was last doing in the previous run ("Last seen in the background at 20:52"), and the newest 40 events, newest first, such as "21:04:11 sent timers (queued)", "21:03:50 phone reachable", "21:03:02 workout adopted".

What the log cannot do: it cannot say why the system closed the app (watchOS gives an app no crash hook; MetricKit does not exist in the watchOS SDK, checked in the 26.4 SDK). It shows the last thing the app recorded before the gap and how it started again.

## Goal and acceptance

Acceptance: S-14201 .. S-14215; the watch app builds (`xcodebuild`); every existing watch test stays green UNCHANGED.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-14201 | New `WatchDiagnosticsLog` in the package (`watch/watchos/Sources/WatchSessionEngine/WatchDiagnosticsLog.swift`): a file-backed JSONL of `{at, kind, session?, detail?}` in its own directory (`Application Support/watch-diagnostics/watch-diagnostics.jsonl`), opened with an injected directory and clock, one lock for all writers, newest 3000 events kept (compacted to 3000 when 3300 are reached), every failure swallowed (never throws; a caller waits for one small file append, and once per 300 events for the compaction's reread and rewrite, under the same lock) | scout: `FileWatchSessionStore.swift:429-443` append idiom; no logger exists |
| D-14202 | Nothing in the package or the app depends on the log: every collaborator takes `diagnostics: WatchDiagnosticsLog? = nil` as a trailing defaulted parameter, nil means no recording, so no existing call site or test changes | `WatchSessionEngine.swift:129-141` init |
| D-14203 | A frame type listed in `WatchDiagnosticsLog.chatty` (`energy_live`) is recorded at most once per 60 s, with the number of frames it stands for (`detail: "x12"`), so a long workout cannot push the interesting events out of the 3000 | `energy_live` every ≥5 s, plan 135 |
| D-14204 | Launch recording: `WatchAppHost.init` notes `launch`; `WatchAppDelegate.handleActiveWorkoutRecovery` also notes `recovery_relaunch` first thing; `launch` carries `detail: "previous=<kind>[/<detail>]@<ISO time>"` taken from the newest event of the previous run, or `previous=none` (`WatchDiagnosticsLog.noteLaunch()`) | `OmniTrainApp.swift:22-28`, `ContentView.swift:156-236` |
| D-14205 | The last-seen phase is the `scene` event: `ContentView`'s existing `scenePhase` handler notes `scene` with `detail` `active`, `inactive` or `background` for EVERY phase (today only `.active` acts); the existing action on `.active` is unchanged | `ContentView.swift:535-542` |
| D-14206 | Frames: `WatchConnectivityBridge.send` notes `frame_sent` with `detail` `live`, `queued` or `failed: <error>`, plus `frame_not_sent` when `plistSafe` fails; the receive consumer in `ContentView.swift:238-256` is NOT touched: `WatchConnectivityBridge.deliver` notes `frame_received` (type, session) and `frame_handler_failed` when the handler throws; the platform's late refusal (`OmniTrainWatchConnectivity.send` refusal closure) notes `frame_send_refused` before it queues | scout Q3 |
| D-14207 | The engine notes `frame_not_sent` at the three silent validator returns on frames it built (`WatchSessionEngine.swift:1340, 1352, 1611`) and `frame_rejected` where it refuses an incoming frame (`:2234`), each with the type, the session and the first rejection's CODE AND PATH only (never its message: review round 1, D-14211), and does nothing else there | scout Q3 |
| D-14208 | `WatchPlatformWorkout` notes `workout_begin`, `workout_end` (`detail: saving` or `discarded`), `workout_adopted`, `workout_recovered` (`detail: saving` or `discarded`) with the session id when it has one | `WatchPlatformWorkout.swift:353-400` |
| D-14209 | Reachability and link: the host's existing reachability handler notes `reachability` (`detail: reachable` or `unreachable`) and the link-problem handler notes `link_problem` (`detail: true|false`) | `ContentView.swift:259-275` |
| D-14210 | `WatchDiagnosticsSummary` (pure, package): from the stored events builds the header lines (how the app last started, what the previous run last did) and the newest-40 lines, newest first, times as local `HH:mm:ss`; `WatchDiagnosticsView` (package, watchOS 9 API only) renders it in a `ScrollView`; `WatchStartView` gets `onOpenDiagnostics: (() -> Void)? = nil` and, when set, a last `Button("Diagnostics")` in the bordered style after the health line; `ContentView` presents the view in a sheet like `showingFood` | `WatchStartView.swift:140-235`, `ContentView.swift:501-512` |
| D-14211 | Privacy: events carry types, session ids, outcomes and error descriptions cut to 120 characters (a refusal by its code and path only, any other handler error by domain and code); never an exercise name, a weight, a food or a number the user typed | owner policy: private data |

## Input-reality checklist

- **Writers and units.** Writers: the main actor, the WatchConnectivity delegate queue, tasks. One `NSLock` inside the log serialises append and compaction. Units: a time is an `Date` stored as UTC ISO-8601 (`2026-11-10T21:04:11Z`), shown local.
- **Lifecycle.** The log is opened once in `WatchAppHost.init`; a kill mid-append leaves a torn last line, skipped on read, and the next append starts on a fresh line (the store's own rule, copied). A relaunch reads the same file.
- **Settings changing while open.** None.
- **Time edges.** Events are ordered by append, not by timestamp, so a clock change reorders nothing. `previous=` uses the newest stored event at the moment of launch, before the launch event is appended.
- **Load cost.** At most one small line per frame, `energy_live` coalesced to one per minute (D-14203); one compaction per 300 events beyond the cap; the Diagnostics screen reads the file only when opened.
- **Wording.** The screen's words are plain ("Started 21:04 — restarted by the system", "Last seen in the background at 20:52"); raw kinds appear only in the event lines.
- **Slot competition.** One extra bordered button at the bottom of the Start screen, below everything that exists; nothing moves.
- **Readers that wait.** None: no spinner, timeout or retry reads this log.

## Scenarios

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-14201 | log A notes 3 events, a new log over the same directory reads them | same 3 events, same order | the type does not exist |
| S-14202 | cap 20 (compacts at 22), 30 notes | the newest 20 are kept, oldest first reading order intact; file has at most 22 lines | the type does not exist |
| S-14203 | a file whose last line is cut mid-record, then one note | the cut line is skipped and the new event reads back | the type does not exist |
| S-14204 | directory that cannot be created | `note` neither throws nor traps, `events()` is empty | the type does not exist |
| S-14205 | run 1 notes `scene background`, run 2 notes `launch` through `noteLaunch` | run 2's `launch` carries `previous=scene/background@<run 1 time>`; with an empty file `previous=none` | the type does not exist |
| S-14206 | bridge with a live-succeeding session; a durable frame whose live send throws and queues; a non-durable frame whose live send throws | `frame_sent` `live`; `frame_sent` `queued`; `frame_sent` `failed: ...` | the bridge records nothing |
| S-14207 | bridge sends 30 `energy_live` frames over 20 s | at most 1 `frame_sent` line for `energy_live`, `detail` `x30` once a minute has passed | no coalescing exists |
| S-14208 | bridge delivers a frame; a delivery whose handler throws | `frame_received` (type, session); `frame_handler_failed` | the bridge records nothing |
| S-14209 | engine receives a frame the validator refuses | one `frame_rejected` with the type; engine state unchanged | the engine records nothing |
| S-14210 | platform workout: start, end saving, continueInProgress true, recoverInProgress | `workout_begin`, `workout_end saving`, `workout_adopted`, `workout_recovered` | nothing is recorded |
| S-14211 | the S-14206 and S-14209 fixtures with a log over an unwritable directory, and again with `diagnostics: nil` | the send outcome and the engine state equal those with no log at all | guard of "observation only" |
| S-14214 | `note(..., coalesce: key)` 30 times over 20 s, then once more 61 s after the first line | one line `x1`, then one line `x30` | no coalescing exists |
| S-14215 | a detail of 300 characters with a newline | stored cut to 120 characters, newline flattened | no cut exists |
| S-14212 | summary over a fixed event list (launch with previous `scene@20:52`, 60 later events) | header lines name the start and the last-seen time; 40 lines, newest first, `HH:mm:ss` | no summary exists |
| S-14213 | source guards (exact statements with their braces) in `OmniTrainApp.swift`, `ContentView.swift`, `WatchStartView.swift`, `OmniTrainWatchConnectivity.swift` | `noteLaunch`, `recovery_relaunch`, the scene note for every phase, the reachability note, the Diagnostics button, the sheet | the app target has no diagnostics |

## Phases

| Phase | Agent | Items | Write scope | Parallel |
|---|---|---|---|---|
| P1 | crew-builder-watch | the lead wrote `WatchDiagnosticsLog.swift` (compiles); the builder adds its tests, the summary type and the view (S-14201..S-14205, S-14212) | `WatchDiagnosticsSummary.swift`, `WatchDiagnosticsView.swift`, `Tests/.../WatchDiagnosticsLogTests.swift`, `.../WatchDiagnosticsSummaryTests.swift` | serial |
| P2 | crew-builder-watch | the hooks in the bridge, engine, platform workout and their tests (S-14206..S-14211) | `WatchConnectivityBridge.swift`, `WatchSessionEngine.swift`, `WatchPlatformWorkout.swift`, `Tests/.../WatchDiagnosticsHooksTests.swift` | after P1 |
| P3 | crew-builder-watch | the app target wiring, the Start-screen button, the source guards (S-14213) | `ios/OmniTrain Watch App/*.swift`, `WatchStartView.swift`, `Tests/.../WatchDiagnosticsSourceTests.swift` | after P2 |

## Progress

| Item | Status |
|---|---|
| seed | Done |
| P1, P2, P3 | Not started |
| docs, review | Not started |
| device check QA step 38 | Open (owner) |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | Crash capture is not feasible on the watch: no MetricKit in the watchOS SDK (checked 26.4), no Sentry in the watch target; the log shows the last recorded phase before a gap instead | `find` over the SDK |
| A-2 | No architect phase; the lead seeded with exact decisions and read the two scout sheets | cost discipline, as for plans 140 and 141 |
| A-3 | The watch log reaches the phone only through plan 143's later transfer unit (not in this plan); until then it is read on the wrist | scope budget: two tracks |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/state_management/watch_diagnostics.md | ADDED | - | `WatchDiagnosticsLog` | S-14201 |
| docs/watch-app-setup-and-qa.md | ADDED | - | `Reading the watch diagnostics` | S-14213 |
| docs/README.md | ADDED | - | `watch_diagnostics.md` | S-14201 |
