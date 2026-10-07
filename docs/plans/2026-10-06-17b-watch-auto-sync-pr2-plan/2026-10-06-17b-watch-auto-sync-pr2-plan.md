# Feature: watch auto-sync PR 17b — the wrist announces its own session, and an out-of-reach device catches up by itself

> Status: DRAFT — Iteration 1 planned; questions answered on defaults (see **Open questions**)
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md`; `docs/watch_session_sync.md`; `docs/state_management/watch_surface.md`; `docs/documentation_standard.md`; `watch/sync_protocol/PROTOCOL.md`

## Overview

Owner's request: *a session started on the watch should reach the phone without pressing Sync, and a device that was out of reach should catch up by itself.*

Series context. PR 17a made **phone → watch** automatic: a phone-side session change is pushed as the user makes it. **Watch → phone** is still user-driven. The wrist's own session *shape* — that a session started, and the exercises the user adds on the wrist — reaches the phone only when somebody presses **Sync**. The watch shell says so in its own words: `ios/OmniTrain Watch App/ContentView.swift:131` — *"the one action that starts a sync, because nothing arrives unless the user asks (D-16, I-1)"*.

Why the wrist is silent (read 2026-10-06):

| Wrist action | Path | What leaves |
|---|---|---|
| Start from a routine or the picker | `WatchStartPaths.startFromRoutine` (`WatchStartPaths.swift:344`) / `startFreeWorkout` (`:356`) → `WatchSessionEngine.createSession` (`:253`) → `emitLifecycle(…, state: .started)` (`:993`) | a `session_lifecycle` only — no snapshot |
| Add an exercise mid-session | `WatchStartPaths.addExerciseToSession` (`WatchStartPaths.swift:366`) → `insertExercise(…, moveTo: true)` (`WatchSessionEngine.swift:336`) → `transitionTo(…, lifecycle: nil)` (`:939`) | **nothing at all** — `transitionTo` emits only when `lifecycle != nil` |
| Sync button / an inbound snapshot request | `WatchSyncOrchestrator.sync()` and `answerSnapshotRequest()` (`WatchSyncOrchestrator.swift:105`) | `sessionSnapshot()` (`WatchSessionEngine.swift:216`) |

The phone adopts a wrist session **only from a snapshot**: `WatchIncomingRouter.receive` calls `WatchSessionAdoptionBridge.consider` only when `envelope['type'] == 'session_snapshot'`. A lifecycle frame cannot adopt anything today, so item 1 is not a wiring gap — nothing about the wrist's own session leaves unprompted, and the frame that does leave would not be enough.

Second gap, found while reading: even when a snapshot does arrive, a wrist session the phone **already holds** is dropped. `consider` returns `WatchSessionAdoption.alreadyHeld` (`watch_session_adoption_bridge.dart:418`) and changes nothing, so an exercise added on the wrist after adoption never reaches the phone — including at the next Sync. Announcing the wrist's ladder (item 1) without fixing this would deliver a session shape the phone ignores.

17b closes four things:

1. **The wrist announces itself** — the engine emits its own snapshot when a session starts and when the user on the wrist changes the ladder (D-90, D-91, D-101). The phone's existing adoption path adopts a wrist-started session with no new phone code path.
2. **The phone accepts the wrist's later additions** to the session it already holds, add-only, timer-safe (D-92, D-93, D-94, D-95).
3. **Both directions catch up by themselves** after a gap — the wrist on the reachability edge, the phone on resume (D-96, D-97).
4. **Four items carried out of 17a's review** — the hung-send bound (D-98), the late-adoption push window (D-96), the timer path's unhandled error (D-99), and the Dart `captureSessionEnd` question (D-100) — plus the owner heads-up on an unended wrist session (D-102). All four land in functions 17b already touches.

**Scope (`.github/copilot/pr-scope-budget.md`).** Two soft signals fire: more than one track (`lib/` + `watch/watchos/`) and a contract amendment (`PROTOCOL.md`). Not split, and the reason is stated rather than assumed: the amendment is one additive dated paragraph riding on a phase that exists anyway (v1 is unreleased, so no version bump), and the two tracks carry **one** user-visible behaviour — announcing without catching up leaves exactly the out-of-reach case the item is about, and catching up without announcing has nothing to catch up. Five phases, no new state, no new screen, no new persisted field — Phases 3 and 4 are the Dart and the Swift halves of one workstream, split so each is a single agent run. If the governor prefers a cut, the natural one is Phase 5 (the watch shell, governor-built): one call site, and Phases 1–4 stand alone without it.

## Resolved Decisions (Ledger)

### D-90 — The wrist's own session leaves as a `session_snapshot`, emitted by the engine
The engine emits the snapshot its `sessionSnapshot()` (`WatchSessionEngine.swift:216`) already builds — through the `onEmit` sink it already has. Nothing new is invented: no new frame type, no new phone code path, and `WatchEmitForwarder` (`WatchEmitForwarder.swift`) and the shell's wiring (`ios/OmniTrain Watch App/ContentView.swift:63`) are untouched.

Rejected: **adopting from the lifecycle frame.** The phone's adoption is snapshot-only (`WatchIncomingRouter.receive`), so it would need a second phone code path; and a `session_lifecycle` carries no ladder, so the phone would still have to ask.
Rejected: **emitting from `WatchEmitForwarder`.** It is a generic sink — it forwards what the engine emits and knows nothing about sessions; and the Dart twin (`lib/watch/session/watch_session_engine.dart`) has no equivalent, so the rule would exist in one engine only, against the standing parity invariant.

### D-91 — The wrist emits on its own start and on its own ladder change, and on nothing else
Two moments, both **after** the frame that leaves today (so every existing frame keeps its position and every existing frame-order assertion still holds):

1. `createSession` (`WatchSessionEngine.swift:253`): the `session_lifecycle(started)` first, then one `sessionSnapshot()`.
2. `insertExercise` (`:336`): after applying, one `sessionSnapshot()` — and only when the call is the user's own. `insertExercise` gains `announce: Bool = true`; `WatchStartPaths.addExerciseToSession` (`WatchStartPaths.swift:366`) keeps the default; any call site that applies a phone-originated ladder change passes `announce: false`.

The wrist does **not** emit on finish, abandon, select, advance, a logged entry, or a timer. Ends already travel as lifecycle frames (17a), entries and timers already travel as their own frames through the same sink, and a phone-originated structure change (`applyExercisePush` `:372`, `applyStructureChange` `:508`, `applySnapshot` `:439`) must never announce: the phone wrote it, and PROTOCOL authority rule 2 keeps the phone the structure authority. A mistake at such a call site is harmless rather than a loop (D-11 answers only a shape that differs), but the rule is the rule.

### D-92 — The phone reconciles a wrist snapshot for the session it already holds: add-only, in order, nothing else
In `WatchSessionAdoptionBridge.consider` (`lib/state/watch/watch_session_adoption_bridge.dart:418`, the `alreadyHeld` branch) the phone now reconciles before returning `alreadyHeld`. For each slot in the snapshot's `payload.exercises` whose `sessionExerciseId` is (a) absent from the phone's ladder for that session and (b) absent from the session's ever-seen set (D-93), the phone appends **one** effort: `id` = the slot's `sessionExerciseId` (as `_effort` already does, `:547`), `exerciseId`, `name` and `capabilities` from the slot, `effortKind` by the existing rule (`_effort`, `:541`), `segmentId` = the segment `_adopt` created for that session (`WatchSessionImporter.segmentIdFor(sessionId)`, `:515`), and `orderIndex`/`topLevelOrderIndex` = the slot's index in the snapshot's ladder. The phone never deletes, reorders, renames or re-kinds a slot from a wrist snapshot, never writes an entry from one (entries are the importer's business), and never changes `currentExerciseIndex` or `status`. A snapshot naming no slot the phone lacks changes nothing and notifies nothing.

### D-93 — A slot the phone removed is never re-added
The **ever-seen set** for a session is the union of (a) every `sessionExerciseId` in the ladder of every snapshot the phone has applied for that session and (b) every `sessionExerciseId` in the phone's own ladder for that session at each `consider`. A slot that leaves the phone's ladder therefore stays in the set and a stale wrist snapshot carrying it appends nothing. Known residual (documented, not hidden): a slot the phone created itself *and* removed between two `consider` calls is not in the set, so a wrist snapshot composed in that window could resurrect it. The window is one debounce (250 ms) wide and needs a phone-side add, a phone-side remove, and a wrist snapshot in between; if the reviewer judges it material, the fix is a slot-id ledger fed by the phone's own structural writes — a remediation sub-phase, not a redesign.

### D-94 — The append is timer-safe and notifies once
The new efforts reach the held session through one new `WorkoutState` method (`appendSessionSlots(List<SessionEffort> efforts, {required String sessionId})`, `lib/state/workout/session_core_entry.dart`, beside `addExerciseToSession` `:161`). It inserts into the session's segment, preserves `status`, `currentExerciseIndex`, the segment's own timers and **every running rest/timed timer**, and calls `notifyListeners()` exactly once. It must not call `loadSessionData` or `clearAll` (`lib/state/workout/session_core_io.dart`) — those clear timers (D-26/D-80).

### D-95 — The phone keeps its own session
Everything in 17a's D-10 stands: a wrist snapshot naming a *different* session while the phone holds its own active session is still refused whole (`refusedConflict`), and a wrist session that already ended is still `alreadyEnded` (`:418` region, unchanged). 17b adds a reconcile to the `alreadyHeld` case only. Nothing a wrist sends takes the phone's session away, and the phone never adopts a wrist session on top of its own.

### D-96 — Catch-up is automatic in both directions, one sync per transition
- **Wrist.** The gate and the in-flight guard live in the tested package, not the shell: a new `WatchSyncOrchestrator.catchUp(reachable: Bool) async` (`watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`) holds **both** the gate (reachable **and** the wrist holds a session) and the guard, and calls the existing `sync(reconnect: paths.syncedAt != nil)` — the same call the Sync button makes. A second trigger while one is in flight is dropped, never queued and never cancels the running one; an unreachable radio and a wrist with no session start nothing. The shell's reachability handler is one forwarding line to it (`WatchConnectivityBridge.onReachabilityChange`, `WatchConnectivityBridge.swift:112`; shell `ios/OmniTrain Watch App/ContentView.swift:95-99`). A wrist with no session keeps its old behaviour (nothing is fetched until the user asks), so routines and settings are still only pulled when there is a reason.
- **Phone.** The app asks for a sync once per resume: `WatchSyncGraph` (`lib/state/watch/watch_sync_wiring.dart:61`) gains `Future<void> sync()`, calling the mirror's existing `LiveSessionMirrorState.sync()` (`live_session_mirror_state.dart:336` = `sendSnapshot()` then `requestSnapshot()`) — the sequence the debug harness already uses (`lib/state/watch/live_session_mirror_debug_main.dart:431`). The observer is its own small `WidgetsBindingObserver` widget (`lib/state/watch/watch_resume_sync.dart`, `WatchResumeSync`) constructed with the graph's `sync` callback, so the trigger is tested directly by driving `WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed)` (S-109); `lib/app.dart` mounts it around the shell. One call per resume, no timer, no polling.
- The phone's half of the out-of-reach case needs no new code: any inbound frame already ends in `await push.rebaseline()` (`watch_sync_wiring.dart:191`), so the phone's ladder is re-offered the moment the wrist speaks.
- **The Sync button keeps its remaining uses** (the first fetch on a fresh wrist, and a manual retry). This supersedes I-1's "nothing arrives unless the user asks" for the wrist's own session shape, and only for that.

### D-97 — `sendMessage` stays the carrier; `updateApplicationContext` is not used in 17b
`updateApplicationContext` is rejected for 17b, but not because a context is lost: WatchConnectivity delivers the newest context to the counterpart when its app next runs, and the newest replaces an older one — that is its purpose. It is rejected for four reasons read from source: **(a)** the shell implements **no** `didReceiveApplicationContext` (`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift` implements `didReceiveMessage` only) and the phone has no `contextStream` listener (`lib/core/platform/watch_connectivity_channel.dart`), so both receiving halves would be new platform surface; **(b)** for the wrist → phone direction a latest-wins context cannot carry the ordered backlog of unacknowledged observations the protocol requires (*"On sync, a wrist MUST re-send every observation the phone has not acknowledged … in the order it stored them"*) — the newest context replaces, it does not extend, the backlog; **(c)** the context size limit is undocumented, and an entry-heavy session risks it; **(d)** the wrist's reachability-edge catch-up and the phone's resume trigger reach the same outcome with no new platform surface. The wrist's own storage already gives the ordered replay. Follow-up, not 17b: **a latest-state context for the phone → watch direction alone is a viable later optimisation** (nothing in 17b forecloses it).

### D-98 — A send that never completes cannot wedge the push (carried: 17a G6/A-20)
`WatchSessionAutoPush` (`lib/state/watch/watch_session_auto_push.dart`) chains drains through `_draining` (`:88`, `:110-124`) and a hung `_pushOnce()` (`:136`) leaves that future — and therefore `flush()` (`:106`) — pending forever, so every later frame is dropped by the `_again` branch. The push gains an injected `sendTimeout` (default **10 s**); `_pushOnce` completes when the send does or when the timeout expires, whichever is first, and a timeout is reported through the failure hook (`onFailure`, `watch_sync_wiring.dart:118`) — never thrown at a caller, never retried, never queued (D-22 stands: the row is still owed and the next sync re-sends it from storage). The same bound goes on the wrist's serial chain in `WatchEmitForwarder.enqueue` (`WatchEmitForwarder.swift`), where a wedged radio otherwise silences the wrist for the rest of the session.

### D-99 — The debounce timer path never surfaces an unhandled async error (carried: 17a H5/A-21)
`watch_session_auto_push.dart:190` runs `unawaited(flush())` from the debounce timer, so anything `flush()` throws becomes an unhandled async error with no reporter. `flush()` becomes non-throwing: every failure inside `_pushOnce` is caught and handed to the injected failure hook, and the timer callback has nothing to swallow.

### D-100 — The Dart watch client is a debug harness; no `captureSessionEnd` twin (carried: 17a A-8/F5)
`captureSessionEnd` (`WatchSessionEngine.swift:1221`, called at `:467`, `:567`, `:950`) exists in Swift only. It is not built in Dart: `lib/watch/` is reachable only from its own subtree, `lib/core/platform/watch_transport.dart`, `lib/core/sync_protocol/session_reconciler.dart` and the debug mains (`live_session_mirror_debug_main.dart`, `lib/watch/debug/*`) — grep `package:omnitrain/watch/|/watch/start/watch_sync_orchestrator|watch_session_engine` over `lib/` returns no `lib/main.dart`, no `lib/app.dart`, no `lib/features/**`, no shipping host. The rule is **recorded as a rule**: a Swift-only rule is acceptable only while it changes no observable outcome in the Dart twin, and 17a's AC-11 keeps that condition. Nothing is built here.

### D-101 — A wrist-side change moves the snapshot's `revision`
`transitionTo` (`WatchSessionEngine.swift:939`) preserves `session.revision`; only `applySnapshot` (`:484`, from the payload) and `applyStructureChange` (`:533`, `+1`) write one. So today a wrist-side ladder change leaves `revision` where it was and the only thing that moves is the ladder itself. That is exactly what PROTOCOL's revision rule forbids (*"a `revision` that does not move is not a reason to speak"* — :452 region): a revision is the number a reader uses to tell one shape from another, and the wrist's own change must move it. The wrist's own structural change therefore bumps `revision` by 1, in both engines, and a snapshot with no shape change does not.

### D-102 — An unended wrist session keeps blocking a new phone session on the watch (owner heads-up; default: leave as is)
A wrist session left active (durable store) makes the wrist refuse a phone session for a different id (D-78), so a session the user starts on the phone afterwards does not appear on the watch until the wrist's own session ends. The default is to leave this as it is — the alternative (letting the phone take the wrist's screen) silently discards work the user did on the wrist — and to say so in `docs/watch_session_sync.md`. Recorded here as a decision so it is not re-litigated in 17c.

### D-103 — Which session id each rule keys on, and where each can be overwritten
One id per device, and every rule names its own:
- **The wrist's own** session is `engine.session` (`WatchSessionEngine.swift`), set by `createSession` (`:253`), and replaced only by a frame naming the same id — `applySnapshot` (`:439`) applies the phone's session onto it, `applyStructureChange`/`applyExercisePush` mutate it. D-78 refuses a snapshot naming a *different* id while the wrist holds one, so W is overwritten by W's own frames (or a lifecycle naming W) and by nothing else.
- **The phone's own** session is the id its own `WorkoutState` composed — the ladder `WatchSessionAutoPush` reads from `_mirror.projectedSession()` and the id it keys `_pendingEnds` on. It is written by `WorkoutState` alone (start, finish, discard); no wrist frame writes it.
- **The mirror's** id is `LiveSessionMirrorState.state['sessionId']`, adopted by `_adopt` from a wrist snapshot. It is overwritten only by an adopted snapshot naming a different id — which D-95's conflict guard permits only while the phone holds no session of its own.
Consequently, in the both-start-at-once case (S-115) each device keeps its own: the wrist keeps W (D-78), the phone keeps P (D-95), neither device's rules can be made to key on the other's id, and no lifecycle frame names the other device's session.

## Feature Invariants

Only the invariants that bite here. Project-wide rules stay in `docs/global_conventions.md`.

- **The phone is the structure authority** (PROTOCOL authority rule 2): no wrist frame deletes, reorders or renames a phone-side slot. The phone's ladder only ever grows from a wrist snapshot (D-92).
- **Two engines, one rule set**: every rule added here has the same observable outcome in `WatchSessionEngine.swift` and `lib/watch/session/watch_session_engine.dart`.
- **An equal snapshot is never answered** (17a D-11): `LiveSessionMirrorState.receive` answers only when `_shapeDiffers` **and** `_holdsLadder`, so the wrist's automatic snapshot cannot start a ping-pong.
- **Every frame is safe to deliver twice** (PROTOCOL idempotency): a repeated snapshot appends nothing (D-92), a repeated entry is merged by `entryId`, a repeated lifecycle is a no-op.
- **A sync never clears a running timer** (D-26/D-80/D-94).
- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` stays empty.

## Requirements

- **R-1** A session started on the wrist reaches the phone without any user action on either device.
- **R-2** An exercise the user adds on the wrist reaches the phone, whether the phone already holds the session or not.
- **R-3** A wrist session left active on the phone is not disturbed by a later wrist frame (17a D-10 keeps holding), and the phone's own session is never replaced by a wrist's.
- **R-4** A wrist that was out of reach catches up by itself when the phone comes back, without the user pressing Sync.
- **R-5** A phone that was out of reach catches up by itself when the app returns to the foreground.
- **R-6** Neither catch-up clears a running rest or timed timer, and neither changes the wrist's or the phone's position mid-session.
- **R-7** A send that never completes cannot wedge either device's outgoing queue (D-98), and no failure from the debounce path escapes as an unhandled async error (D-99).
- **R-8** The behaviour is documented where a reader looks for it, and every behaviour sentence names the test that proves it.

## Acceptance Criteria

| AC | Statement | Scenarios |
|---|---|---|
| AC-1 | A session started on the wrist is adopted by the phone, with its ladder, without a Sync press | S-100, S-101 |
| AC-2 | An exercise added on the wrist after adoption appears on the phone, in the wrist's order, exactly once | S-102, S-103 |
| AC-3 | A wrist snapshot naming no new slot changes nothing and notifies nothing | S-104, S-105 |
| AC-4 | A phone holding its own active session is unaffected by a wrist snapshot for another session | S-106, S-115 |
| AC-5 | A stale wrist snapshot cannot re-add a slot the phone removed | S-103 |
| AC-6 | The wrist syncs once per reachability edge, only while it holds a session, and never twice at once | S-107, S-108 |
| AC-7 | The phone asks for a sync once per resume | S-109 |
| AC-8 | An append from a wrist snapshot clears no running timer and moves no position | S-110, S-111 |
| AC-9 | A hung send cannot wedge the queue; a debounce-path failure is reported, not unhandled | S-112, S-113 |
| AC-10 | Both engines apply the same rules with the same outcomes | S-100…S-115 (run in both stacks) |
| AC-11 | The doc statements added here each name a test, and no `docs/` file crosses 64 KiB | S-114 |

## Existing-Functionality Impact

| Touched surface | What already reads it (grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchSessionEngine.createSession` / `insertExercise` (Swift) | `WatchStartPaths.startFromRoutine`/`startFreeWorkout`/`addExerciseToSession`; `WatchSessionEngineTests`, `WatchSessionStartPathsTests`, `WatchLiveMirroringTests` | Two extra frames on the user's own path; every existing frame keeps its position | D-91, S-100, S-101 |
| `WatchSessionEngine.transitionTo` / `revision` | `applySnapshot`, `applyStructureChange`, `applyLifecycle`; the Dart twin `lib/watch/session/watch_session_engine.dart` | A wrist-originated change now moves `revision`; a phone-originated one already did | D-101, S-101 |
| `WatchEmitForwarder` (`WatchEmitForwarder.swift`) | only `ios/OmniTrain Watch App/ContentView.swift:63` (`onEmit: forwarder.sink`) and its own tests | Carries the new frame unchanged; gains the D-98 bound on its serial chain | D-90, D-98, S-112 |
| `WatchSessionAdoptionBridge.consider` `alreadyHeld` (`:418`) | `lib/state/watch/watch_incoming_router.dart` (the only caller); `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_adoption_build_notify_test.dart`, `test/watch_session_start_test.dart` | No longer a silent no-op: it reconciles (D-92). A caller that relied on "nothing happens" would see a session grow | D-92, D-93, S-102, S-104 |
| `LiveSessionMirrorState.sync()` (`:336`) | the debug mains only (`live_session_mirror_debug_main.dart:431`, `watch_start_debug_main.dart:321`) — grep `\.sync()` in `lib/state/watch/` finds no shipping caller | Gains its first production caller (resume) | D-96, S-109 |
| `WatchSyncGraph` (`watch_sync_wiring.dart:61`) | `lib/main.dart` holds the graph; the debug mains build their own | Gains `Future<void> sync()`, delegating to the mirror | D-96, S-109 |
| `lib/app.dart` root widget (`MyApp`, stateless today) | nothing else observes app lifecycle in the shipping app | Mounts the `WatchResumeSync` observer (`lib/state/watch/watch_resume_sync.dart`, new) around the shell | D-96, S-109 |
| `WatchSyncOrchestrator` (`WatchSyncOrchestrator.swift`; `sync`/`answerSnapshotRequest`) | the shell's `requestSync()` (`ios/OmniTrain Watch App/ContentView.swift:131` region) and its reachability handler (`:95-99`); `WatchConnectivityBridgeTests`, `WatchLiveMirroringTests` | Gains `catchUp(reachable:)`, which gates on reachability + a held session and drops a second trigger while one is in flight | D-96, S-107, S-108 |
| `WatchSessionAutoPush.flush()` / `_draining` / `_pushOnce` (`:106`/`:88`/`:136`) | `lib/state/watch/watch_sync_wiring.dart` (`:182-191`), `test/watch_session_auto_push_test.dart`, `test/watch_session_projection_test.dart` | Bounded by `sendTimeout`; `flush()` stops throwing | D-98, D-99, S-112, S-113 |
| `WatchConnectivityBridge.onReachabilityChange` (Swift `:112`) | `ios/OmniTrain Watch App/ContentView.swift:95-99` | The handler forwards the reachability value to `catchUp`; the gate lives in the orchestrator, not the shell | D-96, S-107, S-108 |
| `WorkoutState` session entry (`session_core_entry.dart:161` region) | the session screens, `test/session_*`; the adoption bridge after this change | Gains `appendSessionSlots`, which adds efforts and touches no timer | D-94, S-110, S-111 |
| `watch/sync_protocol/PROTOCOL.md` | `test/watch_capture_contract_conformance_test.dart`, `test/watch_session_engine_test.dart`, the Swift protocol tests | One additive dated amendment; no version bump, no changed rule sentence | D-90, D-101, S-114 |
| `lib/watch/**` (Dart watch client) | grep above: no shipping host | Unchanged; the `captureSessionEnd` rule is recorded, not built | D-100 |
| **Unaffected, with the grep that proves it** | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → empty | The layer invariant holds after the change | Invariant |

## Scenarios

Fixtures are explicit. `MockWorkoutRepository` + plain `test()` for Dart; the Swift tests use the existing in-memory store and `FakeWatchConnectivitySession`.

### S-100: A wrist-started session reaches the phone by itself
- Fixture: phone holds **no** session (empty repository, no active session); wrist has a routine-derived session with slots `[A (reps), B (timed)]`, `status: active`, `currentExerciseIndex: 0`, `revision: 1`; transport connected.
- Trigger: `WatchStartPaths.startFromRoutine` runs.
- Flow: `createSession` emits `session_lifecycle(started)`, then `sessionSnapshot()`; the forwarder hands both to the transport; the phone's router sees `session_snapshot` → `consider` → `_adopt`.
- Expected outcome: the phone's session exists with efforts `[A, B]` in that order, `status: active`, index 0; the phone emitted no frame of its own back to the wrist; no Sync was pressed.
- **Red without the change because** `createSession` emits only its `session_lifecycle` today, so no `session_snapshot` reaches the router and `consider` is never called — the assertion that the phone holds a session with efforts `[A, B]` fails.
- Edge case of: none.

### S-101: A free wrist session with an empty ladder, then an exercise added
- Fixture: as S-100 but `startFreeWorkout` with **no** exercises (`exercises: []`); then the user picks exercise `C`.
- Trigger: `startFreeWorkout`, then `addExerciseToSession(slot C)`.
- Flow: start emits lifecycle + an empty-ladder snapshot; the phone adopts a session with zero efforts; the add emits a second snapshot whose ladder is `[C]` and whose `revision` is **2**.
- Expected outcome: the phone holds one session with exactly one effort `C`; the second snapshot's `revision` is strictly greater than the first's (D-101); the wrist emitted no third frame.
- **Red without the change because** the free start emits only its lifecycle and the add emits nothing, so the phone holds no session — the assertion that it holds exactly one effort `C` fails, and there is no second snapshot to compare `revision` with.
- Edge case of: S-100.

### S-102: An exercise added on the wrist after adoption reaches the phone
- Fixture: the S-100 end state on both devices (phone holds `[A, B]`, same ids); no timers running.
- Trigger: the user adds slot `C` on the wrist, then Sync (or the catch-up).
- Flow: the wrist emits a snapshot whose ladder is `[A, B, C]`; `consider` finds the phone already holds the session → reconciles (D-92) → appends `C`.
- Expected outcome: the phone's ladder is `[A, B, C]` with the same `sessionExerciseId` for each; the appended effort's `segmentId` equals the session's existing segment; `currentExerciseIndex` and `status` are unchanged; `notifyListeners()` fired exactly once.
- **Red without the change because** `consider` returns `alreadyHeld` (`watch_session_adoption_bridge.dart:418`) and appends nothing, so the assertion that the phone's ladder is `[A, B, C]` fails.
- Edge case of: S-100.

### S-103: The same snapshot twice, and a stale snapshot after a phone-side removal
- Fixture: as S-102 (phone holds `[A, B, C]`); the phone then removes `C` through the normal session UI.
- Trigger: the same snapshot (`[A, B, C]`) is delivered twice, then a stale copy of it arrives after the removal.
- Flow: delivery 2 finds every slot known → nothing; the stale frame finds `C` in the ever-seen set (D-93) → nothing.
- Expected outcome: the phone's ladder stays `[A, B]` after all three deliveries; no second effort with `C`'s id exists; no notification on the two no-op deliveries.
- **Red without the change because** the stale half fails without D-93: a `_reconcile` consulting only the phone's current ladder would re-add `C` from the stale frame, so the assertion that the ladder stays `[A, B]` fails. (The repeat-delivery half passes on today's code too — it is the guard, not the red.)
- Edge case of: S-102.

### S-104: A snapshot with no new slot changes nothing
- Fixture: phone holds `[A, B]`; wrist sends a snapshot with the same ladder but a different `sentAt` and a moved `revision` (a phone-originated change echoed back).
- Trigger: the snapshot arrives.
- Flow: reconcile finds no unknown slot; the mirror's `_shapeDiffers` is false for the answer it would give.
- Expected outcome: no effort added, no reorder, no notification from the bridge, and no answer frame sent to the wrist.
- **Red without the change because** `_shapeDiffers` compares `revision` (`live_session_mirror_state.dart:566`), so the fixture's moved `revision` makes the mirror answer the wrist with the phone's snapshot — the assertion that no answer frame is sent fails. (With the `revision` left unchanged every assertion passes on today's code and the scenario proves nothing, so the moved-`revision` fixture is the one to use.)
- Edge case of: S-102.

### S-105: A phone-side rename is not undone by a wrist snapshot
- Fixture: phone holds `[A, B]` and the user renames `B` on the phone; the wrist still calls it by the old name.
- Trigger: a wrist snapshot with the old name arrives.
- Flow: reconcile matches by `sessionExerciseId`, so the slot is known.
- Expected outcome: the phone's name for `B` is the user's; no duplicate `B`; the ladder order is unchanged.
- **Red without the change because** nothing is reconciled today, so every assertion passes on today's code — it is a guard, and it fails under the mutation that matches slots by `name` instead of `sessionExerciseId` (a duplicate `B` appears).
- Edge case of: S-102.

### S-106: The phone's own session is not taken away
- Fixture: the phone holds an active session `P` (its own); a wrist snapshot names session `W` (different id) with an active status.
- Trigger: the snapshot arrives.
- Flow: `consider` → `hasActiveSession` with a different id → `refusedConflict`.
- Expected outcome: the phone still holds `P` with its ladder and index intact; nothing was appended; the wrist's `W` is unchanged on the wrist; no answer frame.
- **Red without the change because** today `consider` refuses the foreign session before any reconcile, so this passes on today's code — it is the 17a D-10 regression guard, and it fails under the mutation that runs `_reconcile` before the conflict guard (`P`'s ladder grows by `W`'s slots).
- Edge case of: 17a D-10 (regression). S-115 covers the both-start-at-once pair.

### S-107: The wrist catches up on a reachability edge, once
- Fixture: the wrist holds an active session; the phone was out of reach; the wrist logged two entries and added one exercise while unreachable.
- Trigger: the radio reports reachable (once), then a second reachability notification with the same value.
- Flow: `catchUp(reachable: true)` passes the gate and starts `sync(reconnect: true)`; the second call finds one in flight and is dropped.
- Expected outcome: exactly one sync ran; the phone received the wrist's snapshot and the owed entries; the wrist's session is unchanged; no overlapping send.
- **Red without the change because** the shell's reachability handler only assigns `phoneReachability` and bumps `revision` (`ContentView.swift:95-99`) — no sync runs — so the assertion that exactly one sync ran fails.
- Edge case of: none.

### S-108: A wrist with no session does not sync on its own
- Fixture: fresh wrist, no session, no prior sync.
- Trigger: the reachability callback reports reachable.
- Flow: `catchUp(reachable: true)` reaches the gate ("holds a session") and it fails.
- Expected outcome: no sync was started; the routines and settings surfaces are still empty; the user's Sync still fetches everything.
- **Red without the change because** there is no `catchUp` and no call site, so this passes vacuously on today's code — it is the guard for D-96's session gate, and it fails under the mutation that drops the `engine.session != nil` clause from `catchUp` (a fresh wrist syncs and its routines surface stops being empty).
- Edge case of: S-107.

### S-109: The phone catches up on resume, once
- Fixture: the phone holds an active session; the wrist holds the same session; the phone was backgrounded while the wrist added an exercise.
- Trigger: the app resumes (once), then resumes again with nothing in flight.
- Flow: the `WatchResumeSync` observer sees `resumed` → `graph.sync()` → `sendSnapshot()` + `requestSnapshot()`.
- Expected outcome: the phone sent exactly one snapshot request per resume, the wrist answered, and the phone's ladder contains the wrist's exercise once; no timer was cleared.
- **Red without the change because** nothing observes `AppLifecycleState.resumed` and `WatchSyncGraph` has no `sync()`, so the assertion that the phone sent exactly one snapshot request per resume fails.
- Edge case of: S-107.

### S-110: A running rest timer survives the append
- Fixture: the phone holds `[A, B]` with a running rest timer on `A` (wall-clock, `EntryRest` row); a wrist snapshot adds `C`.
- Trigger: the snapshot arrives.
- Flow: `consider` → `appendSessionSlots` (D-94).
- Expected outcome: `C` exists; the rest timer's remaining time is unchanged (still counting to the same end); `currentExerciseIndex` unchanged; no `EntryRest` row was deleted.
- **Red without the change because** `consider` returns `alreadyHeld` and appends nothing, so the assertion that `C` exists fails; the timer assertion only becomes observable once the append lands, which is the point of the fixture.
- Edge case of: S-102.

### S-111: An append while the phone is on another screen
- Fixture: as S-110 but the phone is showing the summary of the session in question (not the session screen).
- Trigger: the snapshot arrives.
- Flow: `appendSessionSlots` notifies once.
- Expected outcome: the session's effort count grew by one, the summary re-reads it, and no navigation or screen change occurred.
- **Red without the change because** nothing is appended today, so the effort count does not grow and that assertion fails; the screen half is the guard that the append notifies once without navigating.
- Edge case of: S-110.

### S-112: A hung send cannot wedge the queue
- Fixture: a `WatchSessionAutoPush` whose transport's `send` never completes; a session change is made.
- Trigger: the debounce fires; a second change is made while the first send is hung.
- Flow: `_pushOnce` completes at `sendTimeout`; the failure is reported through the hook; the `_again` branch runs.
- Expected outcome: `flush()` completed; the second frame was pushed; exactly one failure was reported; nothing was queued for retry.
- **Red without the change because** `_pushOnce` awaits the never-completing send, so `_draining` never settles, `flush()` never returns and the `_again` branch never runs — the assertion that the second frame was pushed (and that one failure was reported) fails.
- Edge case of: 17a G6.

### S-113: A debounce-path failure is reported, not unhandled
- Fixture: a push whose send throws (the test seam).
- Trigger: the debounce timer fires.
- Flow: `flush()` catches and reports.
- Expected outcome: the failure hook received it; no unhandled async error was raised; the push still works on the next change.
- **Red without the change because** the push takes no failure hook and `_pushOnce` swallows the `Exception` (`on Exception`), so nothing reports it — the assertion that the hook received the failure fails.
- Edge case of: 17a H5.

### S-114: The documentation statements name their tests
- Fixture: the doc set as shipped by this PR.
- Trigger: reading the changed sections against the test names.
- Flow: each behaviour sentence added here cites a real test name, and no `docs/` file exceeds 64 KiB.
- Expected outcome: `test/docs_indexing_contract_test.dart` is green; every new sentence's named test exists and passes.
- Edge case of: none.

### S-115: Both devices start their own session at once
- Fixture: the phone holds its own active session `P` (composed by its `WorkoutState`, part-way down its ladder); the wrist holds its own active session `W` (started from the wrist's picker), with a ladder of its own; both connected; the phone pushes `P` and the wrist announces `W` in the same run.
- Trigger: the phone's debounce fires and the wrist's `createSession` announcement leaves, near-simultaneously (the order of the two arrivals is not asserted).
- Flow: the phone's snapshot for `P` reaches the wrist's `applySnapshot` → D-78's guard (the wrist holds `W`, a different id) refuses it whole, silently, with no answer frame; the wrist's snapshot for `W` reaches the phone's `consider` → `hasActiveSession` with a different id → `refusedConflict` (D-95), no answer frame.
- Expected outcome: the phone still holds `P` — same ladder, same order, same `currentExerciseIndex`, same status — and stores nothing of `W`; the wrist still holds `W` — same ladder, same index — and stores nothing of `P`; neither session's rows change; no lifecycle frame (completed or abandoned) names the other device's session.
- **Red without the change because** the wrist half cannot happen on today's code (nothing announces `W`), so the scenario is vacuous there; its fixture is the point — build it by making both announcements land in one run, where it fails if D-78's or D-95's identity guard is missing (the phone adopts `W`, or the wrist applies `P`).
- Edge case of: S-106 (the same conflict, one direction).

## Iteration 1

Five phases: Phase 3 is the Dart half and Phase 4 the Swift half of one workstream, split so each is a single agent run; Phase 5 is governor-built. Phase 1 and Phase 2 are independent of each other (Phase 2 alone makes a wrist-started session appear on the phone; Phase 1 alone makes a wrist-added exercise land on a session the phone already holds — which, before Phase 2, only happens at a Sync). Phase 3 is independent of Phases 1–2 (its S-109 outcome assumes Phase 2's announcement, so it is verified after them); Phase 4 needs Phase 3 only for the docs it writes; Phase 5 needs Phase 4's `catchUp`.

### Phase 1: The phone accepts the wrist's additions (@developer)
1. [ ] `lib/state/watch/watch_session_adoption_bridge.dart`, `consider` `alreadyHeld` branch (`:418`): before returning `alreadyHeld`, call a new private `_reconcile(sessionId, slots)`; keep the return value and the ordering of the existing guards (D-92).
2. [ ] Same file: `_reconcile` — match slots by `sessionExerciseId`, skip any slot in `_everSeen[sessionId]` (D-93), build efforts with the existing `_effort(slot, segmentId: WatchSessionImporter.segmentIdFor(sessionId), orderIndex:, atMs:)` (`:541`), and return the new efforts.
3. [ ] Same file: maintain `_everSeen` — union of every applied snapshot's slot ids and the phone's ladder at each `consider`; clear an entry when the session is no longer held.
4. [ ] `lib/state/workout/session_core_entry.dart`, beside `addExerciseToSession` (`:161`): add `appendSessionSlots(List<SessionEffort> efforts, {required String sessionId})` — insert into the session's segment, preserve `status` and `currentExerciseIndex`, touch no timer, `notifyListeners()` once (D-94).
5. [ ] `lib/state/workout/workout_state.dart`: expose `appendSessionSlots` on the state's public surface (delegating to the core file), documented in one line.
6. [ ] `lib/state/watch/watch_session_adoption_bridge.dart`: after a non-empty `_reconcile`, call it and notify once; an empty result calls nothing and notifies nothing (D-92).
7. [ ] `test/watch_session_adoption_bridge_test.dart`: S-102 (append, order, segment, index/status unchanged, one notify), S-104 (no-op, no notify, no answer frame), S-105 (rename survives), S-106 (D-10 regression).
8. [ ] `test/watch_session_adoption_build_notify_test.dart`: S-103 (twice, then a stale copy after a phone-side removal), S-111 (notify while another screen is showing).
9. [ ] `test/` — a plain `test()` for S-110: a running `EntryRest` survives `appendSessionSlots` and its remaining time is unchanged.
10. [ ] `docs/watch_session_sync.md`: state **only** the add-only reconcile rule where the adoption rules are described — what the phone does when a wrist snapshot for the session it already holds arrives, whenever it arrives (D-92/D-93) — naming its test (S-114). Do **not** claim the wrist's session arrives automatically yet: Phase 1 alone delivers nothing unprompted, so the "reaches the phone by itself" wording is Phase 2's and the catch-up wording is Phase 4's.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`; `.github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_session_adoption_build_notify_test.dart test/watch_session_start_test.dart` (if the check does not accept paths, run `.github/copilot/scripts/macos/gateway.sh test` and read the counts); the new S-110 test must be shown **failing** with `_reconcile`'s call site commented out, then passing with it restored.

**Predicted Files**: `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/workout/session_core_entry.dart`, `lib/state/workout/workout_state.dart`, `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_adoption_build_notify_test.dart`, `test/watch_session_rest_timer_append_test.dart` (new), `docs/watch_session_sync.md`. Nothing else.

### Phase 2: The wrist announces its own session (@developer)
1. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `createSession` (`:253`): after the existing `emitLifecycle(live, state: .started)`, emit one `sessionSnapshot()` (D-91).
2. [ ] Same file, `insertExercise` (`:336`): add `announce: Bool = true`; after applying, emit one `sessionSnapshot()` when `announce` (D-91).
3. [ ] Same file, the revision rule: a wrist-originated structural change moves `session.revision` by 1 (`transitionTo` `:939` must not be the only writer) — the snapshot that announces it therefore carries the new number (D-101).
4. [ ] Same file, guard the phone-originated paths: `applyExercisePush` (`:372`), `applyStructureChange` (`:508`) and `applySnapshot` (`:439`) emit nothing and, where they already move `revision`, keep doing exactly that (D-91).
5. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`: **no edit expected** — `startFromRoutine` (`:344`) and `startFreeWorkout` (`:356`) both return `engine.createSession(…)` (steps 1–2), and `addExerciseToSession` (`:366`) calls `insertExercise` (`:370`) with the default `announce`. Verify this and say so in the Progress line rather than changing the file.
6. [ ] `lib/watch/session/watch_session_engine.dart`: mirror steps 1–4 in the Dart twin — `createSession` (`:273`), `insertExercise` (`:330`), the snapshot builder beside `:238-242` (same `_messageIdFor('snapshot-…')` scheme), `_emitLifecycleIfConformant` (`:1060`) and `_emit` (`:1524`); a wrist-originated change moves `revision` (the twin's writers are `:482` from a payload, `:533` on a structure change, `:577` preserving) (invariant: two engines, one rule set).
7. [ ] `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`: S-100 (start emits lifecycle **then** snapshot, in that order, one each), S-101 (empty free start, then an add: two snapshots, `revision` strictly increasing), S-104 (a phone-originated `applyExercisePush`/`applyStructureChange` emits nothing).
8. [ ] `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`: the start paths' frame counts, updated with a comment naming D-91.
9. [ ] `watch/watchos/Tests/WatchSessionEngineTests/WatchEmitForwarderTests.swift`: the new frame travels the same serial chain and keeps its order relative to the lifecycle frame (S-112's ordering half).
10. [ ] `test/watch_session_engine_test.dart`: the Dart twin's S-100/S-101/S-104 equivalents.
11. [ ] `docs/state_management/watch_surface.md` and `docs/watch_session_sync.md`: state that the wrist announces its own start and ladder change — the "automatic" wording is true only now that this phase lands — naming the tests (S-114). The catch-up wording is Phase 4's, not here.

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh lint`; `.github/copilot/scripts/macos/gateway.sh swift-test` (expect 315 + the new tests, 0 failures — the baseline was 315 passed / 0 failed on 2026-10-06); `.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_reconciliation_cross_stack_test.dart`. S-100's test must be shown failing with the new emission removed, then passing.

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, `lib/watch/session/watch_session_engine.dart`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchEmitForwarderTests.swift`, `test/watch_session_engine_test.dart`, `docs/state_management/watch_surface.md`, `docs/watch_session_sync.md`. Nothing else.

### Phase 3: The Dart half — the push's bounds and the phone's resume trigger (@developer)
1. [ ] `lib/state/watch/watch_session_auto_push.dart`, `_pushOnce` (`:136`) and the constructor (`:52` region): add an injected `sendTimeout` (default 10 s) and an injected failure hook; the drain completes when the send does or the timeout expires; a timeout is reported, never thrown (D-98).
2. [ ] Same file, `flush()` (`:106`): catch every failure inside the drain and hand it to the hook; `flush()` never throws; the timer callback at `:190` then has nothing to swallow (D-99).
3. [ ] `lib/state/watch/watch_sync_wiring.dart`, `createWatchSync` (`:110`): pass the graph's existing `onFailure` (`:118`) into the push, and add `Future<void> sync()` to `WatchSyncGraph` (`:61`) delegating to the mirror's `LiveSessionMirrorState.sync()` (`live_session_mirror_state.dart:336` = `sendSnapshot()` then `requestSnapshot()`) (D-96).
4. [ ] `lib/state/watch/watch_resume_sync.dart` (new): `WatchResumeSync`, a small `WidgetsBindingObserver` widget constructed with the graph's `sync` callback — on `AppLifecycleState.resumed` it calls it once, on any other transition it does nothing; it registers in `initState` and removes itself in `dispose` (D-96). A null graph (no watch) means no observer is mounted at all.
5. [ ] `lib/app.dart` (`MyApp.build`, `:75`) / `lib/main.dart`: mount `WatchResumeSync` around the shell with the graph's `sync` as its callback — no timer, no polling (D-96).
6. [ ] `test/watch_session_auto_push_test.dart`: S-112 (hung send, the second frame still leaves, one failure reported, nothing queued) and S-113 (a throwing send is reported, not unhandled).
7. [ ] `test/watch_resume_sync_test.dart` (new): S-109's observer — a `testWidgets` that pumps `WatchResumeSync`, drives `WidgetsBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed)` (no real delays, so no FakeAsync hang), and asserts one `sync()` per resume and none while the app stays resumed or goes `inactive`.
8. [ ] `test/watch_session_projection_test.dart`: S-109's graph half — `WatchSyncGraph.sync()` sends one snapshot then one request, in that order.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`; `.github/copilot/scripts/macos/gateway.sh test test/watch_session_auto_push_test.dart test/watch_session_projection_test.dart test/watch_resume_sync_test.dart` (if the check does not accept paths, run `.github/copilot/scripts/macos/gateway.sh test` and read the counts); S-112 must be shown **failing** without the timeout, then passing.

**Predicted Files**: `lib/state/watch/watch_session_auto_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/state/watch/watch_resume_sync.dart` (new), `lib/app.dart`, `lib/main.dart`, `test/watch_session_auto_push_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_resume_sync_test.dart` (new). Nothing else.

### Phase 4: The Swift half and the contract (@developer)
1. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift`, `enqueue`: bound each chained send with the same 10 s timeout so a wedged radio cannot silence the wrist for the rest of the session (D-98).
2. [ ] `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`: add `public func catchUp(reachable: Bool) async` — it holds **both** the gate (only when `reachable` **and** `engine.session != nil`) and the in-flight guard (a trigger while one is running is dropped, never queued, never cancels the running one), and calls the existing `sync(reconnect: paths.syncedAt != nil)`. The shell passes only the reachability value (D-96).
3. [ ] `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift` and `WatchLiveMirroringTests.swift`: S-107 (reachable twice in a row → one sync; the owed entries leave) and S-108 (a wrist with no session → none), asserted on `catchUp(reachable:)`: reachable, unreachable, no session, and a second trigger while one is in flight (dropped, never queued).
4. [ ] `watch/sync_protocol/PROTOCOL.md`: one **additive, dated** amendment recording that a wrist announces its own session with a snapshot and that a wrist-originated structure change moves `revision` (D-101) — no version bump (v1 unreleased), no existing rule sentence changed.
5. [ ] `docs/watch-app-setup-and-qa.md` (the walkthrough step that says a wrist session reaches the phone at a Sync, `:342-345`, and the out-of-reach note, `:500-503`): both become automatic; each sentence names its test. `docs/watch_session_sync.md`: the catch-up triggers (both directions) and D-102's heads-up — this is where the "catches up by itself" wording lives; Phase 2's docs state only the announcement.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`; `.github/copilot/scripts/macos/gateway.sh swift-test` (expect 315 + the new tests, 0 failures — the baseline was 315 passed / 0 failed on 2026-10-06); then `.github/copilot/scripts/macos/gateway.sh test` (full suite) with the counts pasted. S-107 must be shown **failing** with `catchUp`'s body reduced to a bare `sync(reconnect:)` (no gate, no guard), then passing.

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`, `watch/watchos/Tests/WatchSessionEngineTests/WatchLiveMirroringTests.swift`, `watch/sync_protocol/PROTOCOL.md`, `docs/watch_session_sync.md`, `docs/watch-app-setup-and-qa.md`. Nothing else.

### Phase 5: The watch shell starts the catch-up — GOVERNOR-BUILT (@governor)
The watch app target is not writable by agents, and this is the one step that needs it.

1. [ ] `ios/OmniTrain Watch App/ContentView.swift`, the reachability handler (`:95-99`): forward the value to `orchestrator.catchUp(reachable: reachable)` — one line, not awaited, so the handler is never blocked — and keep the existing `phoneReachability` assignment. The gate and the guard live in `catchUp` (Phase 4), not here.
2. [ ] Same file: the comment at `:131` ("nothing arrives unless the user asks (D-16, I-1)") is corrected to point at D-96 for the session shape; the Sync button keeps its remaining uses.
3. [ ] `xcodebuild` for a watchOS simulator is the governor's check (never an agent's): the target still builds.

**Done Criteria**: the watch app target builds under the governor's `xcodebuild`; the agent-run checks of Phases 1–4 stay green.

**Predicted Files**: `ios/OmniTrain Watch App/ContentView.swift`.

## Files Affected

Production: `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/watch/watch_session_auto_push.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/state/watch/watch_resume_sync.dart` (new), `lib/state/workout/session_core_entry.dart`, `lib/state/workout/workout_state.dart`, `lib/main.dart`, `lib/app.dart`, `lib/watch/session/watch_session_engine.dart`, `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift`, `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift`, `ios/OmniTrain Watch App/ContentView.swift` (governor-built).

Tests: `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_adoption_build_notify_test.dart`, `test/watch_session_auto_push_test.dart`, `test/watch_session_projection_test.dart`, `test/watch_resume_sync_test.dart` (new), `test/watch_session_engine_test.dart`, `test/watch_session_rest_timer_append_test.dart` (new), `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`, `…/WatchSessionStartPathsTests.swift`, `…/WatchEmitForwarderTests.swift`, `…/WatchConnectivityBridgeTests.swift`, `…/WatchLiveMirroringTests.swift`.

Docs/contract: `watch/sync_protocol/PROTOCOL.md`, `docs/watch_session_sync.md`, `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`, this plan folder, the series index.

Dependents that only read a touched surface (no change expected; their tests are the regression guard): `lib/state/watch/watch_incoming_router.dart`, `lib/state/watch/live_session_mirror_state.dart`, `lib/state/watch/watch_session_importer.dart`, `test/watch_session_start_test.dart`, `test/watch_session_finish_test.dart`, `test/watch_session_merge_test.dart`, `test/watch_capture_contract_conformance_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`, `test/docs_indexing_contract_test.dart`.

## Notes

- **Dependency graph**: Phases 1 and 2 are independent; Phase 3 (the Dart half) is independent of them; Phase 4 (the Swift half and the contract) needs Phase 3 only for the docs it writes; Phase 5 needs Phase 4's `catchUp` and is governor-built. Running Phase 2 first gives the visible win (a wrist-started session appears on the phone) with no dependency on Phase 1; Phase 1 first gives a smaller, invisible win (a wrist-added exercise stops being dropped at a Sync).
- **Why Phases 3 and 4 are two runs**: the old single phase was eleven steps across two languages; the split keeps each run to about one agent-sized change and keeps the Swift half (which needs `swift-test`) in a run that does not also touch `lib/`.
- **Predicted intermediate states**: after Phase 1 alone, a wrist-added exercise lands on the phone only at a Sync — a behaviour change no user can see yet. After Phase 2 alone, a wrist-started session and its ladder appear automatically, but an exercise added *after* adoption is still dropped until Phase 1 lands. After Phase 3 alone the push is bounded and the phone asks for a snapshot on resume, but the wrist still does not catch up until Phases 4–5 land. Each state leaves the suites green.
- **Why no new frame type**: PROTOCOL's snapshot is already the shape the phone's adoption reads, and a new type would need a validator rule, a version note and a phone reader — for the same bytes.
- **Why the emission sits after the existing frame**: every existing assertion about "the frame a start emits" keeps its index; the new frame is appended.
- **`revision` on the wrist**: today a wrist-side ladder change does not move it (only `applySnapshot` and `applyStructureChange` write it). D-101 makes the wrist's own change move it, which is what a reader of `revision` needs and what PROTOCOL's rule implies. If a test elsewhere asserts a fixed revision after a wrist-side change, that test is asserting the defect and its update is expected.
- **Baselines (2026-10-06, 17a's evidence)**: `flutter test` 4013 passed / 1 skipped / 0 failed; `flutter analyze` 196 issues / 0 errors (non-zero exit is normal for this repo); `swift test` in `watch/watchos` 315 passed / 0 failed. Compare, do not assume.
- **Test traps**: plain `test()` for state; `testWidgets` under FakeAsync never resolves a real `await Future.delayed` or Hive write — run widget tests Mock-first; a red Mock group can leave its Hive group hanging behind it, so fix the red group instead of re-running the file.
- **Carried from 17a's review** (all four land in functions this plan already touches): G6/A-20 → D-98, H5/A-21 → D-99, A-8/F5 → D-100, and the late-adoption push window (F3/A-17) → D-96's phone-side resume trigger.

## Progress

- [ ] Phase 1 — the phone accepts the wrist's additions (@developer)
- [ ] Phase 2 — the wrist announces its own session (@developer)
- [ ] Phase 3 — the Dart half: the push's bounds and the phone's resume trigger (@developer)
- [ ] Phase 4 — the Swift half and the contract (@developer)
- [ ] Phase 5 — the watch shell starts the catch-up (@governor, built)

## Assumption Log

Executors append here: decision made, options considered, choice and why. The Conductor marks each **RATIFIED** (promoted to a D-x) or **REVERT** (remediation sub-phase).

[empty]

## Feedback

[empty]

## Open questions

Owner-visible only. Each carries the default this plan proceeds on; the Conductor recorded the answer as the default.

1. **When a wrist session is left active, a later phone session never appears on the watch.** Default: leave it (D-102) and document it — the alternative silently discards wrist work. *Recommended: keep the default.*
2. **The wrist's automatic catch-up pulls routines and settings too, not only the session.** It is the existing Sync call, gated on the wrist holding a session. Default: accept it (a wrist mid-workout should have the current routines). *Recommended: keep the default; a session-only sync would be a new protocol request kind.*
3. **A wrist-added exercise is appended at the end of the phone's ladder, not where the wrist has it.** Default: append in the snapshot's order after the phone's known slots, never reorder the phone's own. *Recommended: keep the default — the phone is the structure authority.*
4. **The wrist's own ladder change now moves `revision`.** This is a contract-visible number. Default: bump it (D-101) and amend PROTOCOL additively. *Recommended: keep the default.*
5. **Should the phone's catch-up on resume also pull the routine list?** Default: no — routines stay a Sync-button action (D-72); the resume trigger asks only for the session snapshot. *Recommended: keep the default.*
