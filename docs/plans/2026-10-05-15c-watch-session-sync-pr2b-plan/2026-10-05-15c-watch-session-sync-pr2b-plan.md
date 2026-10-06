# Feature: watch-session-sync PR 2b — the wrist logs its own session

> Status: DRAFT (planned; owner Q&A carried in `## Open questions` — no answers needed before
> Phase 1, which is owned by the package)
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md`; series: `docs/plans/2026-10-05-15-watch-session-sync-index.md`;
> protocol: `watch/sync_protocol/PROTOCOL.md`
> Builds on: PR 1 (`2026-10-05-15a-…`, D-1–D-12, S-1–S-8) and PR 2a (`2026-10-05-15b-…`, D-13–D-20,
> S-9–S-19), base `612b356`.

## Overview

Until now the wrist can start a session and show it, but every surface that *logs* — the value
screen, End, the effort-rating question — exists in the `WatchSessionEngine` package and is not
hosted by the watch app. This PR makes the wrist usable on its own: pick or move to an exercise,
log a set (the values the kind asks for), End, and answer the rating question when the phone's
setting says so.

**One finding corrects the series index and PR 2a's "What PR 2b carries".** Both say the engine
"lacks" the outgoing sink. It does not: `WatchSessionEngine.swift:24` declares
`public typealias WatchMessageSink = ([String: Any]) -> Void`, line 37 stores `onEmit`, the `init`
(line 86) takes it, and every emission point already calls it — `appendObservation` (observations),
`captureSessionEnd` + `emitLifecycle` (the session end and the lifecycle), `appendTimer`, and the
rating path. **What is missing is the wiring**: `ios/OmniTrain Watch App/ContentView.swift` builds
`WatchSessionEngine(store: store)` with no `onEmit`, so every frame the wrist produces is silently
dropped. Phase 1 supplies the adapter; Phase 2 passes it. S-28a records the correction.

**What this PR does not do.** No `lib/` change at all (the phone already reads what the wrist
sends — PR 1 + PR 2a). No new phone screen, modal or button. No phone→wrist set (PR 3). No protocol
change, no new message or field. No durability, no pruning, no schemas in the app bundle, no sensor
recording, no Wear OS. The wrist keeps `InMemoryWatchSessionStore`, so a session — and an owed
rating question — is lost when the watch app quits (D-27; QA step 17 cannot pass yet).

## Requirements

- **R-1** From the wrist, with no phone present: open the session it is in, move to another exercise
  in it, add one it does not hold, log a set of the kind the exercise asks for, End the session.
- **R-2** Everything logged leaves the wrist **as it is logged** and reaches the phone over the
  existing Manual-Sync channel (`WatchConnectivityBridge` → `observations_up` → the phone's inbox),
  using the ids PR 1 established. A Sync is still the only action that *asks* the phone for anything
  (`WatchSyncOrchestrator.sync`).
- **R-3** When the phone's setting asks for it, End presents the effort-rating question and only an
  answer closes it; the answer reaches the phone as an `effort_rating` observation for that session.
- **R-4** Nothing the wrist logs can land in a session that is over, on either device.
- **R-5** A frame that cannot cross — the phone out of reach, or a value the radio cannot carry — is
  reported through the existing failure hook and dropped; the row stays owed and the next Sync
  re-sends it. No queue, no retry loop, no partial write.
- **R-6** The phone needs no change: no `lib/` file, no screen, no button, no migration.

## Acceptance Criteria

| # | Criterion | Scenarios |
|---|---|---|
| AC-1 | A set logged on the wrist reaches the phone without a Sync, in a free session and in a session the phone adopted | S-20, S-21 |
| AC-2 | End closes the session on both devices, and the rating question follows only when the phone's setting asks | S-22, S-23 |
| AC-3 | An answer records exactly one rating, on the wrist and on the phone's history | S-22 |
| AC-4 | A session with nothing logged is never asked about | S-24 |
| AC-5 | A finished session cannot be logged into, from the surface or from the state | S-29 |
| AC-6 | The wrist picks and moves between exercises with no phone round trip | S-30 |
| AC-7 | Unreachable phone: the row stays owed and a later Sync delivers it once | S-26 |
| AC-8 | A frame the radio refuses is reported and dropped, and its row stays owed | S-27 |
| AC-9 | Tapping Sync while a countdown runs stops the countdown (documented, not new) | S-25 |
| AC-10 | The documentation describes what the wrist can do, and the series index no longer claims a missing sink | S-28, S-28a |

## Feature Invariants

Only the invariants that bite here; project-wide rules stay in `docs/global_conventions.md`.

- **I-1 Loop-back safety.** Everything the wrist emits is something the phone's inbox already
  accepts (PR 1's `WatchSessionInbox._stageable` and `_requiredFields`), so an emission can never
  make the phone refuse a frame it needs. An unsolicited `observations_up` is the normal case.
- **I-2 No new authority.** The wrist never asserts session structure to the phone except through the
  paths PR 1 built (its own `session_snapshot` when the phone asks, and its observations). Nothing in
  this PR makes the phone's own copy of a held session wrong.
- **I-3 The log path stays idempotent.** A frame sent twice, or re-sent at a Sync, materialises the
  same entry once (`entryId` / put-if-absent staging), so sending eagerly cannot duplicate work.
- **I-4 The store stays append-only.** No row is updated; a session end is a new row.

## Existing-Functionality Impact

| Touched surface | What already reads it (the grep) | Effect of the change | Guarded by |
|---|---|---|---|
| `WatchSessionEngine.init(onEmit:)` (`WatchSessionEngine.swift:24,37,86`) | `grep -n "onEmit" watch/watchos/Tests -r` → six harnesses (`WatchSessionEngineTests`, `WatchConnectivityBridgeTests:67`, `WatchEffortRatingTests:63`, `WatchCaptureContractTests:191`, `WatchSessionStartPathsTests:90`, `WatchNutritionQuickLogTests:109`); the shell omits it | The shell passes one; emissions leave the wrist instead of vanishing. The test harnesses are unchanged (they pass their own recorder) | S-20, S-26, S-27 |
| `WatchLoggingState.canLog` (`WatchLoggingState.swift:193`) | `WatchLoggingView.swift:185` (`.disabled(!model.state.canLog)`), `fields` (line 317), `log()` (line 547), `WatchLoggingSurfacesTests.swift:380` | One added condition: the session must be **active**. The existing test asserts the no-session case, so it stays green | S-29 |
| `ios/OmniTrain Watch App/ContentView.swift` (`WatchAppHost`, `startedPlaceholder`) | The watch app target only; `docs/watch-app-setup-and-qa.md` §3.6, `.github`-free; `docs/state_management/watch_surface.md` §"The wrist shell's second surface" | The placeholder is replaced by the real surfaces; the host owns two more states and passes `onEmit` | S-20…S-30, walkthrough |
| `WatchEffortRatingState.restore()/isPromptOwed/end()` (`WatchEffortRating.swift:128,148,186`) | Nothing in production; `WatchEffortRatingTests` (S-211–S-220) | Now reachable in the app: End can owe a question and the launch can present it | S-22, S-24, S-28 |
| `WatchPhonePreferences.asksForEffortRating` (`WatchPhonePreferences.swift:111`) | `grep -n "asksForEffortRating" watch/watchos` → `WatchEffortRatingState` only | Unchanged; now fed by real `preferences_down` in the app, so the setting reaches the question | S-22, S-23 |
| `adoptTimers(authoritative:)` (`WatchSessionEngine.swift:619`) + `LiveSessionMirrorState._sameTimers` (`live_session_mirror_state.dart:543`) | `WatchLoggingModel.countdown` (`WatchLoggingModel.swift:69`), PR 1's timer tests, the phone's snapshot answer | Unchanged by this PR (D-26). Logging does **not** clear a countdown; a Sync answer does, because the phone projects `'timers': {}` | S-25 |
| `WatchSessionStartPaths.selectExercise/pickerRows` (`WatchStartPaths.swift:385,396`) | `WatchExercisePickerView` (hosted by `WatchStartView` line 176; now also by the logging surface) | The same view gains a second host; the move/append rule is untouched | S-30 |
| Phone inbox / importer / router | `grep -rn "receive(frame)\|_stageable\|apply(.*phoneOwnsSession" lib/state/watch lib/core/services` → the router, the inbox, the importer, PR 2a's suites | **Unchanged** — read-only dependency. The frames simply arrive without a Sync first | PR 1's + PR 2a's suites stay green (S-27's phone half), `flutter test` count unchanged |
| `scripts/sqlite_schema.sql` / `lib/data/models/models.dart` | the schema contract test `test/db_seed_test.dart` | Untouched — this PR persists nothing on the phone | `flutter test` (count unchanged) |

Standing invariant check: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core`
must stay empty — this PR adds no Dart at all.

## Resolved Decisions (Ledger)

Immutable. Changes are new superseding entries (`D-nn supersedes D-nn`), never edits. Numbering
continues the series (PR 1 D-1–D-12, PR 2a D-13–D-20).

| # | Decision |
|---|---|
| **D-21** | **The sink exists; this PR wires it.** `WatchSessionEngine.onEmit` is already called by every emission point and is nil in the app target. Phase 1 adds a package adapter that turns the synchronous `WatchMessageSink` into calls on the `WatchSyncTransport` (`WatchConnectivityBridge`), and Phase 2 hands that adapter's sink to the engine's `init`. The adapter hands frames on **in emission order** (one serial tail, the pattern `WatchSensorWrites.enqueue` already uses at `WatchSensorRecording.swift:223`) and never blocks the caller. Rationale: the shell then adds no closure of its own across the package boundary, `WatchConnectivityBridge.send` already reports a refusal and drops the frame, and `sync()` already re-sends `pendingObservations()`. |
| **D-22** | **A frame leaves the wrist when the action happens.** The wrist does not batch, does not defer to a Sync, and keeps no outbound queue: each observation is sent as it is appended. A refused frame is reported through the existing failure hook and dropped; the row stays unconfirmed and the next Sync re-sends it from storage, in store order. This is safe because the log path is idempotent (I-3) and because a wrist session the phone does not hold is staged until its end anyway (PR 2a's unchanged path). |
| **D-23** | **The wrist never logs into a session that is not active.** `WatchLoggingState.canLog` additionally requires `engine.session?.status == WatchSessionStatus.active`. The engine's `appendObservation` keeps accepting a row for a completed session (it must: `session_end` and `effort_rating` are appended after the finish), so the guard belongs on the logging state, not the engine. Owner-visible: the moment a session ends — the wrist's End, the phone's finish, or a snapshot — the logging surface is gone and a stray tap cannot add a set to a session that is over. |
| **D-24** | **The shell shows one of three surfaces.** In order: (1) the owed rating question, alone, before anything else; (2) the logging surface, while `engine.session?.status == .active`; (3) `WatchStartView`. The branch reads the engine's session — not a locally remembered "the user started something" flag — so a session that arrives from the phone (PR 1's D-4) or ends behind the user's back switches the surface on its own. After End with the setting off, the wrist lands on `WatchStartView`; with the setting on it lands on the question, and the start surface follows the answer. |
| **D-25** | **End is one tap, no dialog.** The shell hosts the package's own `WatchEndSessionView`; the session ends immediately and the phone's copy ends through its ordinary finish at the next sync. Rationale: the surface is ~40 pt tall, the package's End view is the surface the shipping plan's O-1 names, and the QA walkthrough as written ("end the session there. The wrist asks…") assumes one tap. Owner-visible risk: an accidental tap on the wrist ends the session irreversibly (the alternative is in `## Open questions`). |
| **D-26** | **Timers keep being cleared by a snapshot answer (PR 1's A24 stands).** Logging does not touch a countdown; a Sync does. `WatchSessionAdoptionBridge.projectSession` answers with `'timers': const {}`, and the wrist adopts an authoritative empty timer set (`adoptTimers(…, authoritative: true)`), so a rest countdown running under a Sync stops: the "X left" line disappears and its milestone haptic never fires. Rationale: carrying timers needs the phone to project its own rest timer keyed by the wrist's slot ids — a new phone-side authority that belongs with PR 3's protocol work, not with hosting a logging screen. Owner-visible, and listed in `## Open questions`. |
| **D-27** | **The store stays in memory, and nothing is pruned.** The shell keeps `InMemoryWatchSessionStore`; PR 2b schedules no `pruneConfirmed`/`pruneSensorSamples` (this supersedes PR 2a's "What PR 2b carries" item 2, which pinned pruning here). Rationale: with an in-memory store nothing accumulates past the process, so there is nothing to prune; and pruning confirmed rows *during* a session changes values derived from those rows — `WatchLoggingState` reads the highest stored `roundNumber` to decide the next round (`WatchLoggingState.swift:306`), so pruning mid-session would restart the count. Owner-visible: force-quitting the watch app loses the session and its owed rating question (QA step 17 cannot pass yet). Pruning and durability move to PR 4 together. |
| **D-28** | **The phone is untouched.** No `lib/` file changes: PR 1 and PR 2a already accept and merge everything this PR sends. `flutter test`'s count must be unchanged at the end of every phase of this PR. |
| **D-29** | **The protocol schemas stay out of the app bundle.** The shell keeps `validator: nil` on the engine and `WatchConnectivityBridge` keeps whatever it has today. Rationale: bundling resources is app-target work no macOS test reaches, the phone's validator still refuses any non-conformant frame the wrist sends, and the package's fixture suites are what hold the wrist's *emissions* to the protocol. Owner-visible: none today (the phone it talks to is this build's). Carried to PR 4 / a later PR, together with any receiver-side judgement on the wrist. |
| **D-30** | **The wrist's own state is the only authority on the wrist.** The shell owns one `WatchLoggingState` and one `WatchEffortRatingState` for the life of the app and re-reads them on every arrival and on every action; `startedSessionId` (the placeholder's opt-in flag) disappears. Rationale: `WatchLoggingState.slot` already derives the current exercise live from `engine.currentExercise`, so one instance tracks the session, the exercise and the phone's own pushes without a second source of truth. |

## Scenarios

Fixtures are enumerated; every scenario's test lives in the phase named beside it. S-ids continue
the series (PR 2a ended at S-19).

### S-20: a set logged in a free workout leaves the wrist as it is logged
- Fixture: `InMemoryWatchSessionStore` with zero rows; a `WatchSessionEngine` whose `onEmit` is the
  adapter over a recording `WatchSyncTransport` (reachable); `paths.startFreeWorkout()` run once so the
  session holds the fallback exercise, current index 0; `WatchLoggingState(engine:)` with the default
  units, no sensors.
- Trigger: dial 3 reps (via `adjust`), then `log()`.
- Flow: `WatchLoggingState.log()` → `engine.appendObservation` → store first, `emit` second.
- Expected outcome: exactly one frame reached the transport, of type `observations_up`, naming the
  session and the same `sessionExerciseId`/`exerciseId` the session holds; its single event carries
  `entryId`, `kind: "set"`, `reps: 3`, a `loggedAt` and no `loadKg` (no load dialled). No Sync ran.
  The wrist's row is unconfirmed until a receipt arrives.
- Edge case of: none.

### S-21: the same, in a session the phone adopted
- Fixture: as S-20, plus the wrist has applied a phone `session_snapshot` (the phone holds the
  session) whose `entries` and `timers` are empty — the state `WatchSessionAdoptionBridge.projectSession`
  actually produces (`'entries': const <Object?>[]`, `'timers': const <String, Object?>{}`); the
  session's slot ids are the phone's.
- Trigger: log a set; then hand the recorded frame to the phone-side merge (PR 2a's `S-9` fixture).
- Expected outcome: one `observations_up` leaves immediately; PR 2a's merge places it in the effort
  the session already has (never creating one) and receipts it; the wrist confirms the row. Phone
  halves are PR 2a's existing tests, named here as the conformance target — no new phone test.
- Edge case of: S-20.

### S-22: End with the setting on asks, and one answer records one rating
- Fixture: `WatchPhonePreferences` holding a `preferences_down` record with `effortRatingPrompt: true`;
  a session with one logged set; `WatchEffortRatingState(engine:store:preferences:)` restored.
- Trigger: `end()`, then `select(4)`, then `confirm()`; then a second `confirm()`.
- Expected outcome: `end()` leaves exactly two frames — the `session_end` observation and the
  `completed` `session_lifecycle` — and then owes a prompt (one `WatchRatingPromptRecord`); the
  session's status is `completed`; `canLog` is false; `confirm()` emits one `effort_rating` event with
  `rating: 4`, `owedSessionIds` becomes empty, and the second `confirm()` records and emits nothing.
- Edge case of: none.

### S-23: End with the setting off ends silently
- Fixture: preferences with `effortRatingPrompt: false` (S-23a: no `preferences_down` ever arrived).
- Trigger: `end()`.
- Expected outcome: no prompt is owed, nothing but the `session_end` observation and the `completed`
  lifecycle left the wrist, and the shell (D-24) lands on the start surface.
- Edge case of: S-22.

### S-24: a session with nothing logged is never asked about
- Fixture: rating on, a session started and immediately ended — zero observations.
- Trigger: `end()`.
- Expected outcome: no prompt (`isRatingOwed` requires at least one effort entry); the phone's
  Summary shows Add rating (phone side unchanged, PR 1's behaviour).
- Edge case of: S-22.

### S-25: a Sync under a running countdown clears it (documented, not new)
- Fixture: a session with a set logged so a rest timer is running (`WatchLoggingModel.countdown` non-nil);
  a phone answer built by `projectSession` (`'timers': {}`).
- Trigger: `applySnapshot(envelope)` with that answer.
- Expected outcome: the timer for the kind is stopped authoritatively → `countdown` returns nil, the
  "X left" row disappears, and no later milestone haptic fires. **Logging alone does not do this**
  (S-20's frame is not a snapshot and the phone answers an `observations_up` only with a receipt).
- Edge case of: none. (Guards D-26 against a later "carry the timers" change.)

### S-26: the phone out of reach at Log time
- Fixture: a transport whose `send` throws (the phone unreachable), recording every attempt and every
  failure; two sets logged.
- Trigger: log twice while unreachable, then make it reachable and `sync(reconnect:)`.
- Expected outcome: both log calls still return (nothing blocks), each frame is reported once through
  the failure hook and dropped, and no queue holds them; at Sync both observations are re-sent from
  storage in store order, exactly once each; the phone materialises each entry once (I-3) and
  receipts them.
- Edge case of: S-20.

### S-27: a frame that cannot cross
- Fixture: two negative frames. (a) A frame the radio cannot carry: a payload holding a value
  `NSDictionary`/`NSArray` refuse (an `NSNull`, or `Data` where the phone expects text) — the check
  `WatchConnectivityBridge.send` performs, proved by `S-113`. (b) A frame the radio carries but the
  phone's schema refuses: `watch/sync_protocol/fixtures/invalid/observations_up_steps_as_double.json`
  (a `steps` value as a `Double`), which the phone's validator rejects and never receipts.
- Trigger: emit each frame.
- Expected outcome: (a) the bridge reports one failure and sends nothing; the adapter neither retries
  nor throws into the engine; (b) the frame crosses, the phone refuses it, no receipt names it, so the
  row stays owed. In both cases: no partial store write, no phone-side row, and the next Sync re-sends
  the still-owed rows from storage. A log line, never a crash and never a silent loss.
- Edge case of: S-26.

### S-28: the owed question at launch
- Fixture: a store **seeded** with a `WatchRatingPromptRecord` for a finished session (the store the
  shell actually has is in-memory, so this fixture is what proves the mechanism).
- Trigger: `restore()`.
- Expected outcome: the prompt is owed and is the surface shown first, before the start surface; the
  real app loses it on a relaunch (D-27) — the gap is stated in the docs, not hidden.
- Edge case of: S-22.

### S-28a: the sink claim is corrected
- Fixture: the series index and PR 2a's "What PR 2b carries".
- Trigger: review.
- Expected outcome: neither says the engine lacks an outgoing sink; both say what is true — the sink
  exists and was unwired. (`grep -rn "sink it lacks\|does not have today" docs/plans/2026-10-05-15*`
  returns only the historical quotation inside this plan.)
- Edge case of: none.

### S-29: nothing logs into a session that is over
- Fixture: a session with one set, then ended by the wrist's `finishSession()`; and (S-29a) ended by
  the phone's `completed` lifecycle arriving at the wrist.
- Trigger: re-read the surface; then call `log()` directly.
- Expected outcome: `canLog` is false, the Log button is disabled/gone (the package view's own rule),
  and the direct `log()` throws — no observation row is appended for the finished session, and the
  shell shows the start surface (D-24).
- Edge case of: S-22.

### S-30: the wrist moves between exercises and adds one
- Fixture: a free workout started (one fallback exercise in use) plus a pickable catalog row;
  `pickerRows` read.
- Trigger: `selectExercise(rowForAnExerciseTheSessionDoesNotHold)`, then `selectExercise(rowForTheOneItDoes)`,
  then log a set.
- Expected outcome: the first appends a slot and makes it current, the second moves the current index
  back without adding a second slot (`WatchStartPaths.swift:396`), and the logged set carries the slot
  it is on; nothing was asked of the phone.
- Edge case of: S-20.

## Iteration 1

Phase dependency graph: **1 → 2 → 3**. Phase 1 is package-only and inert in the app (nothing passes
the adapter yet); Phase 2 cannot be tested without Phase 1's adapter; Phase 3 documents Phases 1–2
and cannot be written first. Phase 2 has no dependency on Phase 3, and Phase 1's two items are
independent of each other (the guard could go first).

Every phase's suite command is run by whoever owns the implementation; the **governor** runs the
package suite and the watch build after each phase in any case, and the owner runs the walkthrough
after Phase 2. An agent that cannot run `swift test` (the brief's constraint) leaves that line of the
Done Criteria for the governor and says so in the Progress line — it must not claim it ran.

### Phase 1: the sink adapter and the active-session guard (package) (@developer)
1. [x] Add `WatchEmitForwarder` (name is the implementer's) to
   `watch/watchos/Sources/WatchSessionEngine/`: `init(transport: WatchSyncTransport, onFailure:)`,
   a `var sink: WatchMessageSink` handing each frame to the transport, and an emission-ordered serial
   tail — the pattern `WatchSensorWrites.enqueue` uses (`WatchSensorRecording.swift:223–234`). The
   caller never blocks; a throw from `transport.send` is reported through `onFailure` and ends that
   frame only.
   — Done: `init(transport:onFailure:)`, `var sink`, `enqueue` chained on the tail, `onFailure` per
   refused frame. Because `WatchSyncTransport.send` does **not** throw, the throw path is exercised
   through an internal `init(send:onFailure:)` seam (Assumption A-5).
2. [x] Give it tests in `watch/watchos/Tests/WatchSessionEngineTests/` (new file): a recording
   transport that delays the first frame proves the later ones do not overtake it (S-20's ordering
   half); a transport that throws reports once and drops (S-26); no queue survives a refused frame.
   — Done: 5 tests in `WatchEmitForwarderTests.swift`; the ordering test shown red under the
   serial-tail mutation.
3. [x] Tighten `WatchLoggingState.canLog` (`WatchLoggingState.swift:193`) to require
   `engine.session?.status == WatchSessionStatus.active` (D-23), and add the red-first test in
   `WatchLoggingSurfacesTests.swift`: an ended session's state has `canLog == false` and `log()`
   throws, asserting also that no observation row was appended (S-29). Paste the run in which this
   test fails without the edit.
   — Done: `testS029AnEndedSessionCannotBeLoggedInto`; red `Executed 1 test, with 4 failures`, green
   `Executed 1 test, with 0 failures` after the one-condition edit.
4. [x] Add the package test that the engine's existing emissions reach a sink it is given: start a
   free workout, log a set, End — the recorder received an `observations_up`, then the `session_end`
   `observations_up`, then the `completed` lifecycle, in that order (S-20, S-22's emission half).
   — Done: `testTheEnginesEmissionsReachTheSinkInOrder`. The observed sequence also carries the log's
   follow-on rest `timer_state` between the set and the session end, so the assertion names all five
   frames (Assumption A-6). The session is created with one explicit slot because
   `paths.startFreeWorkout()` creates a session holding none (Assumption A-7).
5. [x] Leave every other file untouched. If a change outside the predicted list turns out to be
   needed, log it in `## Assumption Log` and stop before making it.
   — Done: only the four predicted files. `settle()` was renamed `drain()` inside the new file because
   the module's append-only guard reads `settle` as a mutation (the plan's own scenario S-4).

**Done Criteria**
- `swift-test` — 261 + 6 = **267 tests, 0 failures** (baseline 261 / 0). Ran by the developer on
  2026-10-05 with `gateway.sh swift-test`, exit 0.
- `lint` — `196 issues found`, 0 errors (baseline 196 / 0); no Dart in this phase.
- The two red-first proofs, pasted in `<plan>.evidence.md` (item 2's via the serial-tail mutation,
  item 3's against the unedited `canLog`).
- `git-diff --stat` confined to the Predicted Files — the two new files are untracked.

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift` (new),
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchEmitForwarderTests.swift` (new),
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift`. Nothing else.

### Phase 2: the watch app hosts the surfaces (@developer)
1. [ ] In `ios/OmniTrain Watch App/ContentView.swift`, build in this order — `store` →
   `OmniTrainWatchConnectivity`/`WatchConnectivityBridge` → the Phase 1 adapter over the bridge →
   `WatchSessionEngine(store: store, onEmit: forwarder.sink)` → `paths` → `preferences` →
   `WatchSyncOrchestrator` → `WatchLoggingState(engine:)` → `WatchEffortRatingState(engine:store:preferences:)`.
   (The bridge must exist before the engine — unlike the test harnesses, which record emissions
   separately.)
2. [ ] Restore both new states in `restore()` (`await rating.restore()` alongside `paths.restore()`
   and `preferences.restore()`), so an owed question is known before the first frame.
3. [ ] Delete `startedPlaceholder(session:)` and `startedSessionId`, and branch the body in D-24's
   order: owed prompt → logging (active session) → `WatchStartView`. The body must re-run when the
   rating state changes or an arrival lands; the host already bumps `revision` on an arrival, and if
   the surface does not switch on End the host must bump it from the state change too (SwiftUI's
   `objectWillChange` timing is the trap — `WatchEffortRatingState.end()`/`confirm()` both send it).
4. [ ] Host the logging surface: `WatchLoggingView(state: host.logging)` inside a `NavigationStack`
   with a toolbar item opening `WatchExercisePickerView(paths:revision:onExerciseAdded:)` as a sheet
   (R-1, S-30), and the package's `WatchEndSessionView(state: host.rating)` reachable from the same
   screen (D-25).
5. [ ] Host the owed question: `WatchEffortRatingView(state: host.rating)` alone, with nothing else on
   screen and no way past it but an answer (R-3).
6. [ ] No new phone code, no new package API beyond Phase 1, no `validator`, no pruning, no second
   state instance.

**Done Criteria**
- `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' build`
  — succeeds. *(governor)*
- `.github/copilot/scripts/macos/gateway.sh swift-test` — still 0 failures. *(governor)*
- `.github/copilot/scripts/macos/gateway.sh test` — `flutter test`, **+3913 ~1, 0 failures**, count
  unchanged from the baseline (proves D-28: no `lib/` drift). *(governor or the implementer; 900 s)*
- `.github/copilot/scripts/macos/gateway.sh lint` — unchanged 196 / 0.
- The owner walkthrough below runs end to end. *(owner)*

**Predicted Files**: `ios/OmniTrain Watch App/ContentView.swift`. A new file beside it (for example
`WatchSessionSurfaces.swift`) is acceptable if the body would otherwise pass ~150 lines; anything
else is not.

### Phase 3: the docs say what the wrist can do (@developer)
1. [ ] `docs/watch-app-setup-and-qa.md`: step 15, 16 and 18 lose their "(needs Phase 7)" condition;
   step 17 gains an explicit "needs the durable store (PR 4)" note instead of implying it passes;
   steps 19–20 stay Phase 8; step 14's "(needs Phase 7)" parenthetical and the step *(f)* paragraph
   ("only once the wrist can log and finish a session from its own screen") are corrected to the
   present tense; §3.6's "deliberately not a logging screen — no sets, no End, no rating prompt"
   and its "one thing the shell still does not have: a durable store" are rewritten. Read the
   wording in the file; this plan states the intent, not the words.
2. [ ] `docs/state_management/watch_surface.md` §"The wrist shell's second surface": it is no longer
   a placeholder; state what the wrist logs and that a relaunch still loses everything (D-27). Keep
   the file inside the 52 KB band — it is 670 lines today, so this is an edit, not an addition of a
   section.
3. [ ] `docs/watch_session_sync.md` "What does not sync": the wrist's own logging is no longer a
   gap; what remains out is durability, sensor samples, phone→wrist sets, and the timers (D-26) and
   units (below) notes.
4. [ ] `docs/plans/2026-10-05-15-watch-session-sync-index.md`: correct the PR 2b row's "give the
   engine the outgoing sink it lacks" and link this plan (the index update is otherwise the planner's
   and is already written).
5. [ ] State plainly, in `watch-app-setup-and-qa.md` §3.6, the two gaps this PR leaves: the wrist
   shows the unit it dials (kg) even when the phone's saved unit is pounds — the payload is always
   kg on the wire, so history stays correct — and a rest countdown under a Sync is stopped (D-26).
6. [ ] Residue sweep, pasted as output: `grep -rn "startedPlaceholder\|not a logging screen\|sink it lacks"`,
   `grep -rn "needs Phase 7" docs/`, and the standing invariant
   `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` (empty).

**Done Criteria**
- `.github/copilot/scripts/macos/gateway.sh test` — `flutter test` **+3913 ~1, 0 failures**, which
  includes `test/docs_indexing_contract_test.dart` (the 64 KiB ceiling).
- The residue-sweep greps' output pasted above; each is empty or explained.
- `git-diff --stat` confined to the Predicted Files (docs only — no source file changes in Phase 3).

**Predicted Files**: `docs/watch-app-setup-and-qa.md`, `docs/watch_session_sync.md`,
`docs/state_management/watch_surface.md`, `docs/plans/2026-10-05-15-watch-session-sync-index.md`.

## Owner walkthrough (manual, after Phase 2) — **(owner)**

1. Watch and phone paired, watch app installed and launched once. Phone: start nothing.
2. On the wrist: **Free workout**. The logging screen appears with the session's exercise and its value
   rows (a set shows reps and, when the exercise has a load, the load).
3. Dial 3 reps and tap **Log**. The row is accepted; a rest countdown line appears.
4. Pick a different exercise from the list button; the logging screen follows it. Log another set.
5. Phone, without syncing anything: the phone's in-progress session for this wrist session shows the
   sets (PR 2a's merge). *(If it does not, the sink is not wired.)*
6. Enable Settings → Effort Rating on the phone and sync from the wrist.
7. On the wrist: **End**. The question appears alone — no skip, back or swipe. Answer 4.
8. The wrist returns to its start screen. On the phone, the session is in the calendar and its Summary
   shows 4 / 5.
9. Repeat with the phone in Airplane Mode from step 3: both sets and the rating arrive after the
   wrist's next Sync, once each.
10. With Effort Rating off: End asks nothing, and the phone's Summary offers Add rating.

## Scope check

- Tracks: **one** (`watch/watchos/` + the `ios/` shell are the watch client track; no `lib/`, no
  contract change).
- Hard limits (`.github/copilot/pr-scope-budget.md`): 3 phases (≤ 5 ✓), a shell file plus two small
  package files and their tests — well under 1500 production lines (✓), this plan at **467 lines**
  (≤ 800 ✓).
- Soft signals: length 467 lines (not > 500), phases 3 (not > 3), tracks 1, decisions 10 (≤ 20),
  scenarios 12 (≤ 30), no prerequisite missing — **zero soft signals**, so PR 2b is planned whole and
  is not split into 2b-i/2b-ii. If Phase 2 turns out to need a second agent run, it splits into "the
  sink + the branch" and "the two hosted surfaces" without touching this plan's decisions.

## Files Affected (whole feature)

- `watch/watchos/Sources/WatchSessionEngine/WatchEmitForwarder.swift` (new) — the sink adapter (D-21)
- `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` — `canLog` (D-23)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchEmitForwarderTests.swift` (new),
  `WatchLoggingSurfacesTests.swift` — the new coverage
- `ios/OmniTrain Watch App/ContentView.swift` — hosting, the branch, the sink (D-24, D-30)
- `docs/watch-app-setup-and-qa.md`, `docs/watch_session_sync.md`,
  `docs/state_management/watch_surface.md` — the docs it invalidates
- `docs/plans/2026-10-05-15-watch-session-sync-index.md` — corrected PR 2b row (done by the planner)
- Read-only dependents, no edit: `WatchConnectivityBridge`, `WatchSyncOrchestrator`,
  `WatchEffortRating*`, `WatchStartView`/`WatchExercisePickerView`, `WatchSessionStore`, and on the
  phone `lib/state/watch/*`, `lib/core/services/watch_session_importer.dart`

## Notes

- **Where the evidence lives.** Each phase's commands, counts and red→green proofs go in
  `2026-10-05-15c-watch-session-sync-pr2b-plan.evidence.md` beside this file; the reviewer's findings
  go in `2026-10-05-15c-watch-session-sync-pr2b-plan.review.md`. Neither is appended here — this file
  keeps one-line Progress items and Assumption Log entries of at most three lines.
- **Intermediate states.** After Phase 1 the adapter exists and nothing uses it: the app behaves
  exactly as today (keep committing at phase boundaries — no half-wired shell). After Phase 2 the
  wrist logs and the phone receives without a Sync; the phone is untouched throughout.
- **Build order in the shell is a real trap.** The harnesses in the package's tests record emissions
  in a separate array and never hand them to a bridge, so there is no existing example of
  store → engine → bridge ordering. D-21's order is the correct one; getting it wrong (engine before
  bridge) leaves the sink nil again and looks like a passing build.
- **A `testWidgets` trap does not apply here** — no Dart widget test is added. The watch app has no
  test target, so the only automated proof of the shell is the governor's build; everything that
  carries behaviour lives in the package (macOS-testable) on purpose.
- **`swift test` baseline**: 261 tests, 0 failures, measured on `612b356`. Every phase's package run
  must be reported with its count.
- **Known long-running commands**: `flutter test` ~900 s; `swift test` ~900 s (`gateway.sh swift-test`);
  `xcodebuild` for the watch scheme is the governor's and takes minutes.
- No formatter applies: the touched files are Swift and Markdown, and the repository's formatter check
  is `dart format` on new Dart files only.
- **Legacy handling**: the only removed artefact is `startedPlaceholder(session:)` and
  `startedSessionId`. No persisted representation changes anywhere, so nothing needs a migration.
- **Watch contract**: `watch/sync_protocol/PROTOCOL.md` and `watch/contract/*.json` are unchanged
  (D-20 of PR 2a stands; this PR is a consumer of them).

## Progress

- [x] Phase 1 — package: sink adapter + active-session guard — **Complete** (2026-10-05, developer:
  `swift-test` 267 tests / 0 failures; `flutter test` `+3913 ~1` unchanged; `flutter analyze` 196/0.
  Both red-first proofs pasted in `<plan>.evidence.md`)
- [x] Phase 2 — shell: hosting the three surfaces — **Complete** (2026-10-05, developer: body
  branched owed rating → logging (active session holding ≥1 exercise) → `WatchStartView`; the sink
  wired over the bridge in D-21's build order; `rating.restore()` alongside the other two;
  `swift-test` 267 / 0 (package untouched), `flutter test` `+3913 ~1`, `flutter analyze` 196/0 — all
  observed. The watch `xcodebuild` is the **governor's** and the end-to-end walkthrough is the
  **owner's**; this agent ran neither. Signature audit of every package call site in
  `<plan>.evidence.md`)
- [x] Phase 3 — docs, walkthrough, residue sweep — **Complete** (2026-10-05, developer: the four
  predicted docs only; the wrist's own logging now documented as shipped, the two gaps stated plainly
  in §3.6, the numbered owner walkthrough added (not run), residue greps empty. `swift-test` 267 / 0,
  `flutter test` `+3913 ~1` 0 failures, `flutter analyze` 196 / 0 (exit 1 on the pre-existing info
  notices, unchanged). `git-diff --stat` 4 files, docs only. Footprint in `<plan>.evidence.md`)
- [x] Fix round 1 — the review's seven bounded findings (F-1, F-2, F-3, F-4, F-5, F-7, F-8; F-6 and
  F-9 deliberately untouched) — **Complete** (2026-10-05, developer: the Sync tap out of the QA
  walkthrough's step 2, the false "without a sync" bullet deleted and reconciled with the paragraph
  above it, the dated 3881 count deleted, the 15b plan's stale sink clause corrected (its cited grep
  now hits only quotations of the phrase), S-29a's test added — red under the reverted D-23 condition
  (268 / 8 failures, four of them the new test) and green after the exact restore (268 / 0, and an
  empty `git-diff` on the source file), `pickingExercise` cleared when the logging surface
  disappears, and the four new limits plus the two known gaps pointed at the tests that hold them.
  `flutter test` `+3913 ~1` 0 failures, `flutter analyze` 196 / 0. F-7's `.onDisappear` is compiled
  by nothing this agent may run — the watch `xcodebuild` is the governor's. Details, sweep output and
  the red→green table in `<plan>.evidence.md`; assumptions A-14…A-17 below)
- Planner: plan written, series index corrected (S-28a's index half).

## Assumption Log

(Executors append: decision made, options considered, choice and why. The Conductor marks each
RATIFIED — promote to a D-x — or REVERT — open a remediation item.)

- **Planner A-1 — the sink's correction.** The brief and the index both describe a missing sink; the
  source shows the sink exists and is unwired. Chose to record the correction and plan the wiring.
  RATIFIED as D-21 (with the S-28a documentation row).
- **Planner A-2 — the `canLog` guard is in scope.** It is the difference between "hosts a screen" and
  "cannot log into a finished session", it is three lines in the package, and it is macOS-testable.
  Chose to include it rather than defer to PR 4. Vetoable — see `## Open questions`.
- **Planner A-3 — pruning moved out of 2b.** PR 2a's "What PR 2b carries" pinned it here; with an
  in-memory store it has nothing to prune and it would corrupt derived values mid-session. Chose to
  move it to PR 4 with the durable store and to record the supersession (D-27). Vetoable.
- **Planner A-4 — the wrist's own End has no confirmation.** One tap (D-25), because the package's
  End view and the QA walkthrough both assume it. Vetoable — see `## Open questions`.
- **Developer A-5 — the throwing send is a test seam, not the transport init.** Item 1 asks for a
  `transport.send` that throws, but `WatchSyncTransport.send` is non-throwing (a bridge reports a
  refusal through its own hook). Chose `init(transport:onFailure:)` for production plus an internal
  `init(send:onFailure:)` the tests use, rather than widening the protocol.
- **Developer A-6 — the ordered-emission test names five frames, not four.** The log's follow-on rest
  timer emits `timer_state` between the set and the session end. Chose to assert the observed
  sequence rather than loosen the assertion; no engine behaviour changed.
- **Developer A-7 — the fixture is an explicit slot, not `startFreeWorkout()`.** `startFreeWorkout()`
  calls `createSession(modality: nil)` with no exercises, so `canLog` is false there (as the existing
  no-exercise test asserts). S-20/S-30's "the session holds the fallback exercise" describes the
  picker's fallback list, not the session. Phase 2's shell should not assume the slot exists; the two
  Phase 1 tests create their slot with `createSession(modality:exercises:)`.

- **Developer A-8 — the logging branch also requires an exercise.** D-24 says "logging (active
  session)"; `startFreeWorkout()` builds a session with no slot at all (A-7), so `WatchLoggingView`
  would have nothing to show there. The brief overrides: chosen branch is *active and holds ≥1
  exercise*, which falls through to `WatchStartView` and its own picker until the first exercise
  lands. S-30's flow is unchanged — the pick appends the slot and the nudge switches the body.
- **Developer A-9 — the picker sheet closes itself on the pick that moved the session.** The package
  gives no "sheet dismissed" signal, and leaving it up would hide the surface it just switched to.
  Chose `onExerciseAdded` → `pickingExercise = false` plus `noteSurfaceChange()`. Vetoable.
- **Developer A-10 — "step 14's parenthetical" is step 15's.** Phase 3 item 1 names a step-14
  "(needs Phase 7)" parenthetical; step 14 has none, and step 15 carries the only one in the file.
  Chose to read them as the same parenthetical (an off-by-one in the plan) and remove it there.
- **Developer A-11 — the index's PR 2b row needed a tense fix beyond the planner's correction.** Its
  "every frame is dropped today" clause was made false by Phase 2. Chose the one-clause correction
  ("was dropped until this PR wired it"); the Status and Next-handoff lines are the planner's.
- **Developer A-12 — the QA guide's §1 table row and "What QA passed means" are in scope.** Item 1
  names §3.6 and the steps, but both would otherwise still describe the wrist as a slot list and
  claim steps 15–20 as runnable together. Chose to correct them to keep the file self-consistent.
- **Developer A-13 — the walkthrough is a Level 3 section of its own.** Item 1 asks for "one short,
  numbered owner walkthrough"; chose a four-step *(owner, not yet run)* section before "What QA
  passed means", closing with the two known gaps, rather than folding it into steps 15–18. (Its
  `*(owner, not yet run)*` tags are gone in fix round 1 — see A-15.)
- **Developer A-14 — F-5's mutation is the D-23 condition reverted, not a new guard.** The brief's
  parenthetical quotes the post-D-23 line as the "original"; the pre-D-23 form is `slot != nil` alone
  (this PR's own Phase 1 evidence calls D-23 a one-condition edit). Chose that revert, which turns
  S-029 and S-029a red together, then restored it exactly (empty `git-diff` on the file).
- **Developer A-15 — F-7 is in this round although the review filed it as a follow-up PR.** The fix
  brief lists it among the seven findings, so the brief governs. Chose the review's own suggestion —
  one `.onDisappear { pickingExercise = false }` on the logging surface — over resetting it at every
  surface switch. The Swift build is the governor's; F-8's `*(owner, not yet run)*` tags go with it.
- **Developer A-16 — the sensor and unit limits are stated as shell limitations, with a pointer.**
  The package's recording layer exists and does respect injected unit preferences, so the true claim
  is about the shell: `ContentView.swift` builds `WatchLoggingState(engine:)` with no recorder and no
  units. Chose to say that and point at `WatchSensorRecordingTests` / `testS007APoundPreferenceSteps
  InPoundsStoredInKilograms` rather than to keep describing behaviour. Vetoable.
- **Developer A-17 — F-4's sweep is reported with its remaining hits, not as an empty grep.** After
  the 15b correction the cited grep hits only this plan, its review and its evidence, each quoting the
  phrase. Chose to paste those hits and say why they are quotations, since an "empty" claim would be
  false. Vetoable.

## Open questions

Owner-facing; each with the default this plan proceeds on.

1. **The rest countdown is stopped by a Sync (D-26).** Default: accept for now — the phone's answer
   carries no timers, so tapping Sync during a rest stops the countdown and its haptic. Carrying it
   means the phone projecting its rest timer on the wrist's ids (PR 3's contract work). Alternative:
   make the wrist's own timer authoritative for the wrist and never adopt an absent timer (a
   `lib/` + package change, and the two devices could then show different rests).
2. **Force-quitting the watch app loses the session and an unanswered rating question (D-27).**
   Default: accept; QA step 17 stays unproven until the durable store (PR 4). Alternative: a small
   file-backed store in this PR (a track and a phase more).
3. **End is one tap with no confirmation (D-25).** Default: accept. Alternative: a
   `confirmationDialog` on the wrist (one extra tap before an irreversible end).
4. **The wrist shows the unit it dials, not the phone's saved unit.** Default: accept — values are
   kg on the wire, so the phone's history and conversions stay correct; only the wrist's own label
   differs. Alternative: carry units in `preferences_down` (a protocol field, PR 3).
5. **The `canLog` guard is a small package change inside a "hosting" PR (A-2).** Default: include.
   Alternative: defer, accepting that a stray tap could log into a session that is already over.
6. **Schemas stay out of the app bundle (D-29).** Default: accept — the phone validates what the
   wrist sends. Alternative: bundle them now (app-target resource work no macOS test reaches).

## Feedback

- **Review 1 (`@code-reviewer`, Copilot edition): CHANGES_REQUESTED** —
  `2026-10-05-15c-watch-session-sync-pr2b-plan.review.md`. Fix checklist for this PR, one round:
  F-1 `docs/watch-app-setup-and-qa.md:452` (drop the Sync tap from step 2 — it cannot fail, and it
  contradicts owner step 5), F-2 `docs/watch_session_sync.md:141` (delete the false "without a sync"
  claim), F-3 `docs/watch-app-setup-and-qa.md:245` (delete the stale 3881 count), F-4
  `2026-10-05-15b-…-plan.md:389` (S-28a's grep still hits), F-8 (`docs/watch_session_sync.md:155-166`
  and `docs/watch-app-setup-and-qa.md:441+`: point the limits at tests, drop the PR-4/Phase-8 tags),
  F-5 (`WatchLoggingSurfacesTests.swift:392`: add the S-29a fixture — the phone-ended session).
  Follow-up PR, planned not absorbed: F-6 (the deferred `revision` bump in `ContentView.swift:106-109`)
  and F-9 (the Dart twin's `canLog`). F-7 (`pickingExercise` surviving the surface) was filed here as a
  follow-up and fixed in fix round 1 instead — the fix brief lists it among the seven findings (A-15).
