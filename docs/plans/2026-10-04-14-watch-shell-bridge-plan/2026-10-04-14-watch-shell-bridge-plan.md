# Feature: watch shell bridge

> Status: Iteration 1 active
> Next handoff: @developer (Phase 1)
> Binding conventions: `docs/global_conventions.md`. Index entries this feature
> reads: `docs/watch-app-setup-and-qa.md`, `docs/state_management/watch_surface.md`,
> `docs/design_system.md`, `docs/navigation_and_screens.md`, `docs/README.md`.
> Plan folder: `docs/plans/2026-10-04-14-watch-shell-bridge-plan/`.
> Executors write evidence to `2026-10-04-14-watch-shell-bridge-plan.evidence.md`
> and reviewers write findings to `...review.md` — never into this file.

## Overview

The wrist is a complete engine with no radio. `watch/watchos` holds the session
engine, the start surface, the sync orchestrator, the protocol validator and the
`WatchSyncTransport` seam — and nothing implements that seam. The shell target
(`ios/OmniTrain Watch App`) builds the engine, the store and the start paths, and
shows a placeholder once a session starts. So the wrist can start a free workout
and log it, and it can never hear from the phone.

This unit gives the wrist a radio: a `WCSession` transport behind the existing
seam, wired into the existing orchestrator, so the Sync button asks the phone for
routines and preferences and an exercise push lands in the live session. It also
gives the watch app an icon matching the phone's, and makes the start surface
honest when the phone cannot be reached.

**Defect found while planning.** A phone-side `exercise_push` that arrives when
the wrist has no live session does not fail — it *traps*.
`WatchSessionEngine.applyExercisePush` → `insertExercise` → `requireSession()`
calls `preconditionFailure("no session: create one, or restore the in-progress
session first")` (`WatchSessionEngine.swift:1573`). The owner's own walkthrough
reaches this: the phone offers "Send to watch session" whenever the mirror
exists, which on iOS is always. Phase 4 fixes it in the package.

## Resolved Decisions (Ledger)

- **D-1 — The bridge lives in the package, behind a seam.** The transport is a
  `WatchSyncTransport` conformance in `watch/watchos`, over a new
  `WatchConnectivitySession` protocol (send / receive / reachability). The real
  `WCSession` class is compiled only where `WatchConnectivity` exists, so
  `swift test` on macOS exercises the whole bridge against a fake session. The
  app target supplies the real session and nothing else.
- **D-2 — A request frame is byte-for-byte the Dart shape.** `{"request":
  "routines"}`; `{"request": "routines", "since": "<utcIso>"}`; `{"request":
  "snapshot"}`. No `type` key (its presence is what makes a frame a message, per
  `WatchTransportRequest.nameOf`). `since` is omitted, not null, when the wrist
  has never synced. These three shapes are pinned in
  `watch/contract/watch_start_paths_contract.json` under `transportRequests` and
  read by both suites.
- **D-3 — `since` is formatted by the package's own `utcIso`** (UTC, three
  fractional digits). Noted divergence, not fixed: Dart's `toIso8601String()`
  emits six digits when microseconds are non-zero, so a `since` the wrist builds
  and one the phone would build can differ in precision. The phone ignores
  `since` today, so nothing reads the difference.
- **D-4 — Outbound frames are checked for plist safety, and a frame that fails
  the check is reported, never sent and never queued.** A `WCSession` message
  dictionary holds property-list values only, and `NSNull` is not one — the
  platform rejects the whole message, so the check must refuse it, not strip
  it. The check converts `Date` to `utcIso` and accepts `String`, `Bool`,
  `NSNumber` (an `Int` stays an `Int`, a `Double` stays a `Double` — D-5),
  `[Any]` and `[String: Any]` of accepted values. `NSNull`, `Data` and anything
  else make the send fail through the transport's failure hook. Refusing
  `NSNull` costs nothing: the wrist's wire encoders never emit one — they omit
  absent optional fields rather than nulling them — so the refusal turns a
  future regression into a reported failure instead of a silently dropped
  message.
- **D-5 — Numbers are never coerced.** An `Int` stays an `Int` and a `Double`
  stays a `Double`. The protocol's integer fields are integers, and the phone's
  validator refuses a whole-number `Double` (witness:
  `fixtures/invalid/observations_up_steps_as_double.json`). The bridge does not
  paper over a wrong type; the tests prove the frames the wrist sends today are
  already right.
- **D-6 — Nothing is queued.** A send that fails is reported and dropped.
  Recovery is the next `sync()`, which re-sends from storage. This mirrors the
  phone transport's documented rule and keeps the wrist from inventing a second
  delivery path.
- **D-7 — Arrivals go to `WatchSyncOrchestrator.receive(_:)` unmodified**, and
  every arrival bumps the host's revision so the surface re-reads. WCSession
  already hands over plist dictionaries; the bridge does not re-encode them.
- **D-8 — Reachability is three-state: unknown, reachable, unreachable.** The
  host subscribes to the seam's reachability and starts at *unknown*. The
  surface says the phone is unreachable only when the watch has *observed* it
  unreachable. A fresh launch that has never asked the radio says nothing —
  `paths.phoneReachable` is only ever set by `orchestrator.sync()`, so a naive
  "not reachable" sentence would lie on every cold start.
- **D-9 — The Sync button is always present and always enabled** when a
  transport exists. A disabled button explains nothing, and the Dart client
  keeps its button enabled too. The existing "No automatic sync" label always
  stays. The new unreachable sentence is added to `WatchStartSurfaceCopy` and
  shown only per D-8; its wording is an Open question.
- **D-10 — The free-workout picker lists the session's own slots first**, then
  the fallback list minus the exercises already in the session. A session-slot
  row moves the session to that exercise and emits the same lifecycle event a
  `+1` advance emits. A pushed exercise therefore appears in the picker while it
  is open, and is selectable.
- **D-11 — The post-start surface lists the session's slots and marks the
  current one**, replacing the session-id-only placeholder. It stays a
  placeholder: no logging surface, no End, no rating prompt.
- **D-12 — An `exercise_push` with no live session changes nothing and does not
  crash.** It is reported as not applied. Scoped to the package in this unit;
  the Dart client throws `StateError` on the same path — recorded as a finding,
  not fixed here.
- **D-13 — Protocol schemas are not bundled for the wrist.** No runtime
  constructs `SyncProtocolValidator` in `lib/` either, and
  `SyncProtocolValidator.incomingRejections(nil, _)` accepts by design ("a
  receiver that cannot read is not a receiver that should refuse"). Bundling
  would make the wrist the only client that validates at runtime and would need
  resource work in the Xcode target. Moved scope.
- **D-14 — The watch icon is the phone's 1024 PNG, flattened if it carries
  alpha.** The governor copies the binary; the agent sets `filename` in the
  watch `Contents.json` and adds a guard test that reads the PNG header.
- **D-15 — The wrist's session must exist before the phone can push into it**,
  and the phone's push needs a live *phone* session (its envelope requires
  `sessionId`). The walkthrough states the order. The phone-side gaps this
  exposes are listed, not fixed.
- **D-16 — Sync is watch-initiated only.** The bridge never sends unsolicited;
  the phone never pushes except in answer to a request or a user action.

## Feature Invariants

- **I-1** Nothing arrives at the wrist unless the user asked (D-16).
- **I-2** The wrist keeps every copy it accepts and reads the newest; accepted
  rows are appended, never rewritten.
- **I-3** A frame the wrist *sends* is built by the wire encoders, which omit
  absent optional fields. The store encoders may carry nulls; they are for
  storage round-trip, not for the radio.
- **I-4** A frame the wrist cannot read is refused with nothing stored.
- **I-5** The start surface's two labels are contract values; the Wear OS client
  reads the same file.
- **I-6** No `lib/` behaviour changes in this unit. The phone side is read-only
  here; gaps are listed, not patched.

## Requirements and Acceptance Criteria

| # | Requirement | Criterion | Scenarios |
|---|---|---|---|
| A1 | The watch app has an icon matching the phone's | Declared and present, no alpha channel | S-101 |
| A2 | The wrist can ask for routines and preferences over WCSession | Request frames match the phone's shape exactly | S-102, S-103, S-104 |
| A3 | A sync fills the routine list and the preference | Both land, from the phone's own messages | S-105, S-106, S-107 |
| A4 | A pushed exercise appears on the wrist and can be added to the session | Visible in the picker, selectable, never duplicated | S-108, S-109, S-110 |
| A5 | The surface tells the truth about the phone | Sync button shown, "No automatic sync" kept, unreachable said only once observed | S-111 |
| A6 | The frames the wrist sends are plist-safe and schema-shaped | Round trip unchanged; unrepresentable frames reported | S-112, S-113 |
| A7 | Every suite stays green | `flutter analyze`, `flutter test`, `swift test`, watch `xcodebuild` | all |
| A8 | The paired-simulator walkthrough works | (owner) Completed on the paired simulators and recorded | Phase 4 |

## Scenarios

### S-101: the watch icon is declared, present and opaque
- Fixture: `ios/OmniTrain Watch App/Assets.xcassets/AppIcon.appiconset/Contents.json`
  with its 1024 `watchos` slot; the phone's
  `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`.
- Trigger: the guard test reads both files.
- Flow: parse the watch `Contents.json`; read the named PNG's IHDR.
- Expected outcome: the slot names a file; the file exists, is non-empty, its
  IHDR says 1024×1024 and its colour type is not 6 (RGBA). The phone icon's
  colour type is named in the failure message when the watch copy fails.
- Edge case of: none.

### S-102: a first sync asks for routines with no `since`
- Fixture: a fresh wrist — empty store, `paths.syncedAt == nil`, a fake session
  that records what it is asked to send.
- Trigger: `orchestrator.sync()`.
- Flow: the bridge builds the request frame and hands it to the session.
- Expected outcome: the frame is exactly `{"request": "routines"}` — no `since`
  key, no `type` key.
- Edge case of: none.

### S-103: a later sync carries `since`
- Fixture: the same wrist with `paths.syncedAt` set to a fixed instant.
- Trigger: `orchestrator.sync()`.
- Flow: as S-102.
- Expected outcome: `{"request": "routines", "since": "<utcIso of that
  instant>"}`, three fractional digits.
- Edge case of: S-102.

### S-104: a sync with no session asks for a snapshot
- Fixture: a wrist with no live session and no stored session.
- Trigger: `orchestrator.sync()`.
- Flow: the orchestrator requests routines, re-sends pending observations, then
  requests a snapshot.
- Expected outcome: the session is asked to send `{"request": "snapshot"}` after
  the routines request.
- Edge case of: S-102.

### S-105: a sync fills the routine list and the preference
- Fixture: `fixtures/valid/preferences_down.json` and
  `fixtures/valid/routines_down.json` through the protocol fixtures' validator; an empty store.
- Trigger: the fake session answers the routines request with both frames, in that order.
- Flow: `receive` routes preferences to `WatchPhonePreferences` and routines to
  `WatchSessionStartPaths`.
- Expected outcome: `paths.routines` holds the routine, and
  `preferences.asksForEffortRating` is the value the message carried.
- Edge case of: none.

### S-106: a phone with no routines still sends its preference
- Fixture: `preferences_down` alone, with `effortRatingPrompt: false`; a wrist
  that has never synced.
- Trigger: the fake session answers with preferences only.
- Flow: as S-105.
- Expected outcome: the routine list stays empty, the surface's empty-state
  sentence is unchanged, and `asksForEffortRating` is `false` — the wrist now
  knows the setting instead of guessing.
- Edge case of: S-105.

### S-107: a synced routine starts on the wrist
- Fixture: the contract's `fallback.routinesDown` and `routineSession.expectedSlots`.
- Trigger: sync, then start the routine from the start surface.
- Flow: the start path turns the routine into slots.
- Expected outcome: the slots match `expectedSlots`, including each slot's
  declared `effortKind`.
- Edge case of: S-105.

### S-108: a push into an open free workout lands
- Fixture: the contract's `exercisePush` envelope; a free-workout session started on the wrist.
- Trigger: the fake session delivers the push.
- Flow: `receive` → `applyExercisePush` → `insertExercise`.
- Expected outcome: the session gains the slot, the current exercise is the
  pushed one, and the picker's rows list it first.
- Edge case of: none.

### S-109: a re-delivered push does not duplicate the slot
- Fixture: the same envelope delivered twice.
- Trigger: as S-108, twice.
- Flow: as S-108.
- Expected outcome: one slot, not two.
- Edge case of: S-108.

### S-110: a push with no live session changes nothing
- Fixture: a wrist with no session, and the contract's `exercisePush` envelope.
- Trigger: the fake session delivers the push.
- Flow: `receive` → `applyExercisePush`.
- Expected outcome: no crash, no session created, the result reports not
  applied, and the next sync still asks for a snapshot.
- Edge case of: S-108.

### S-111: the surface says the phone is unreachable only after observing it
- Fixture: a fake session whose reachability starts unknown, goes unreachable, then reachable.
- Trigger: the host's reachability subscription.
- Flow: the host maps reachability to the surface's copy.
- Expected outcome: unknown → no sentence; unreachable → the sentence; reachable
  → no sentence. The Sync button is enabled in all three.
- Edge case of: none.

### S-112: the frames the wrist sends survive the plist round trip
- Fixture: a session with a logged set, a paused rest timer whose stored row
  carries a null `plannedDurationMs`, and a pushed slot.
- Trigger: the bridge sends `observations_up`, `timer_state` and
  `session_snapshot`.
- Flow: the plist-safety check runs over each frame.
- Expected outcome: every frame passes unchanged — no `NSNull` appears, every
  integer is an integer, every timestamp is a string.
- Edge case of: none.

### S-113: a frame that cannot be represented is reported
- Fixture: a frame carrying an `NSNull` value, and a second carrying a custom struct value.
- Trigger: the bridge sends each.
- Flow: the plist-safety check refuses each.
- Expected outcome: the session is never asked to send either, and the failure
  hook reports each. Nothing is queued.
- Edge case of: S-112.

## Iteration 1

### Phase 1: the watch icon (@developer)

**Done before this phase (governor).** The flattened, opaque copy of
`ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` already
sits at
`ios/OmniTrain Watch App/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
when Phase 1 starts. The phone icon is RGBA (verified), so the copy was
flattened — watchOS and the App Store reject an icon with an alpha channel. The
phone icon itself is not touched.

1. [x] Set the 1024 `watchos` slot's `filename` in
       `ios/OmniTrain Watch App/Assets.xcassets/AppIcon.appiconset/Contents.json`
       to the copied file's name. Change nothing else in that file.
2. [x] Add `test/watch_app_icon_test.dart`: read the watch `Contents.json`,
       assert the 1024 `watchos` slot names a file, assert the file exists and
       is non-empty, parse its IHDR (width at bytes 16–19, height at 20–23,
       colour type at byte 25) and assert 1024×1024 and colour type ≠ 6. Read
       the phone icon the same way and name its colour type in the failure
       message. No image package — the header is enough.
3. [x] Confirm the test fails first because the watch `Contents.json` has no
       `filename` yet, and passes after the edit (record both runs in the
       evidence file).

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/watch_app_icon_test.dart`; `flutter test`.
**Predicted Files**: `ios/OmniTrain Watch App/Assets.xcassets/AppIcon.appiconset/Contents.json`,
`test/watch_app_icon_test.dart`, and the governor's copied PNG.

### Phase 2: the bridge in the package (@developer)

1. [x] Add `WatchConnectivitySession` to `watch/watchos` — the seam the bridge
       talks to: send a frame, report a send failure, report reachability, and
       deliver an arriving frame. It must compile on macOS.
2. [x] Add the `WatchSyncTransport` conformance: `isPhoneReachable` from the
       seam; `requestRoutines(since:)` and `requestSnapshot()` building the D-2
       frames; `send(_:)` running the D-4 plist-safety check and reporting a
       refusal through the failure hook.
3. [x] Add the plist-safety check as its own type so it is testable without a
       session: `Date` → `utcIso`, accept `String`/`Bool`/`NSNumber`/`[Any]`/
       `[String: Any]`, refuse `NSNull`/`Data`/anything else, never coerce a
       number (D-5).
4. [x] Add `transportRequests` to
       `watch/contract/watch_start_paths_contract.json` — the three frames of
       D-2 — and extend that file's `description` to say what the new block
       pins. This is the one contract change, and it rides with its first
       consumer.
5. [x] Add the Dart side of the agreement: one assertion group in
       `test/watch_transport_test.dart` that
       `WatchTransportRequest.routinesFrame()` and `snapshotFrame()` equal the
       contract's `transportRequests` entries, so a change on either platform
       fails the other's suite.
6. [x] Add one test to `test/watch_transport_test.dart` that walks the parsed
       JSON of `watch/sync_protocol/fixtures/valid/routines_down.json`,
       `.../preferences_down.json` and `.../exercise_push.json` and asserts no
       JSON null appears anywhere. The phone sends these with `sendMessage`, so
       a null in any of them would make the phone's send fail. If one contains a
       null, STOP and record it under Open questions as a blocker — do not work
       around it.
7. [x] Add `FakeWatchConnectivitySession` and the bridge tests to
       `watch/watchos/Tests/WatchSessionEngineTests/`: S-102, S-103, S-104,
       S-105, S-106, S-107, S-112, S-113. Feed the fixtures through the same
       validator the protocol fixtures use.
8. [x] Prove the bridge never sends unsolicited (I-1): a test that a bridge
       with no `sync()` call has sent nothing.

**Done Criteria** (run until green): `flutter analyze`;
`flutter test test/watch_transport_test.dart`; `flutter test`;
`swift test` **(governor)**.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift`,
`watch/watchos/Sources/WatchSessionEngine/PropertyListFrames.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/FakeWatchConnectivitySession.swift`,
`watch/contract/watch_start_paths_contract.json`, `test/watch_transport_test.dart`.

### Phase 3: the shell gets a radio (@developer)

1. [x] Add the real `WCSession` conformance in the app target
       (`ios/OmniTrain Watch App/`), guarded so it is compiled only where
       `WatchConnectivity` exists: activate the session, forward
       `didReceiveMessage` to the bridge, forward reachability changes, and
       report a send failure.
2. [x] Wire `WatchAppHost`: build the bridge, the orchestrator and
       `WatchPhonePreferences`; restore routines *and* preferences on launch;
       subscribe to reachability and keep the D-8 three-state value; bump
       `revision` on every arrival and on every reachability change.
3. [x] Add the unreachable sentence to `WatchStartSurfaceCopy` and the D-8 rule
       that decides when it shows, as a pure value the package can test. Do not
       add it to the contract's `startSurface` block — the Wear OS client has no
       transport; note in the doc that it moves into the contract if that client
       ever ships one.
4. [x] Pass `onRequestSync` into `WatchStartView` from `ContentView` so the Sync
       button appears, and keep it enabled (D-9).
5. [x] Add the S-111 test to the package suite (the reachability → copy rule),
       and a test that the two contract labels still match
       `WatchStartSurfaceCopy`.

**Done Criteria** (run until green): `flutter analyze`; `flutter test`;
`swift test` **(governor)**; `xcodebuild -project ios/Runner.xcodeproj -scheme
"OmniTrain Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch
Series 11 (42mm)' build` **(governor)**.
**Predicted Files**: `ios/OmniTrain Watch App/ContentView.swift`,
`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`.

### Phase 4: pushed exercises are visible, and a push without a session is safe (@developer)

1. [x] Guard the no-session push in the package (D-12): an `exercise_push` that
       arrives with no live session changes nothing, reports not applied, and
       does not trap. Follow the Dart client's own precedent — "structure
       without a session is nothing".
2. [x] Add the picker's row rule to `WatchSessionStartPaths` (D-10): the
       session's slots first, then the fallback list minus the exercises already
       in the session. Keep it a plain value so the package can test it.
3. [x] Make a session-slot row move the session to that exercise and emit the
       same lifecycle event a `+1` advance emits. Reuse the contract's position
       rule; do not change the contract.
4. [x] Make the picker re-read on a revision bump, so a push that arrives while
       the picker is open appears without the user leaving and re-entering it.
5. [x] Replace the post-start placeholder with the session's slots and a marker
       on the current one (D-11). No logging surface, no End, no rating prompt.
6. [x] Add the tests: S-108, S-109, S-110, and the picker row rule (session
       slots first, no duplicates, empty session falls back to the fallback
       list).
7. [x] Update the docs this invalidates: `docs/watch-app-setup-and-qa.md` — the
       §1 status table (the shell is no longer a template), §3.6, and Level 3
       step 2, which still claims `routines_down` "currently has no phone-side
       producer at all"; `docs/state_management/watch_surface.md` — the watch
       transport section gains the wrist's transport, the seam, the frame rules
       and the new invariants; `docs/plans/2026-09-21-13-watch-integration-shipping.md`
       — the Phase 7 Progress line. Every behaviour sentence names a real test.
8. [x] **(owner)** Walkthrough written into `docs/watch-app-setup-and-qa.md`
       as "A second walkthrough, for the push path" (numbered steps 1–7, in the
       plan's order, with the "do not tap Sync again" warning, and with which app
       must be foregrounded on each device). The run itself is the owner's and is
       not claimed here; see the evidence file. The step list is: boot the iPhone
       17 Pro and the Apple Watch Series 11 42mm simulators, pair them, foreground
       both apps; on the phone create a routine; on the watch tap "Sync routines"
       and confirm the routine and the preference arrive; on the watch start
       "Free workout" (the session the push will land in must exist first); on
       the phone start a session (the push's envelope requires a `sessionId`); on
       the phone tap the watch icon on a picker row; confirm the exercise appears
       on the wrist and can be added to the session.

**Done Criteria** (run until green): `flutter analyze`; `flutter test`;
`swift test` **(governor)**; the watch `xcodebuild` from Phase 3 **(governor)**;
the walkthrough above **(owner)**.
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`,
`ios/OmniTrain Watch App/ContentView.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`,
`docs/watch-app-setup-and-qa.md`, `docs/state_management/watch_surface.md`,
`docs/plans/2026-09-21-13-watch-integration-shipping.md`.

## Moved scope

- Bundling the protocol schemas for a wrist-side validator (D-13).
- A durable wrist store — the shell keeps `InMemoryWatchSessionStore`.
- Hosting the logging surface on the wrist; the post-start surface stays a
  placeholder.
- HealthKit, sensors, observation pruning, single-actor work, Wear OS.
- The phone-side gaps: no feedback when the watch is unreachable, and "Send to
  watch session" offered with no live phone session although the envelope
  requires a `sessionId`. The Dart wrist client's picker also does not gain the
  session-slot rows; it has no transport yet, so nothing reads the difference.
- Other phone-to-wrist messages that carry null by design (for example
  `foods_down.categoryId`) cannot cross the plugin as written; not this unit.

## Notes

**Dependency graph.** Phase 1 is independent of 2–4 and can run in any order.
Phase 2 must precede 3 (the shell needs a bridge) and 4 (the tests reuse the
fake session). Phase 3 must precede 4's walkthrough. Phase 4's items 1–5 are
independent of Phase 3 and could run first, at the cost of the walkthrough
having no radio to walk.

**Predicted intermediate states.** After Phase 2 the package has a tested bridge
that nothing constructs — `swift test` green, the app unchanged. After Phase 3
the wrist syncs and the start surface is honest, but a pushed exercise is
invisible until Phase 4. After Phase 4 the walkthrough is written and awaits the
owner's run.

**Verification ownership.** Done Criteria marked **(governor)** — `swift test`,
the watch `xcodebuild`, and any simulator install/launch smoke — are run and
recorded by the governor outside this plan; the developer must not write
"passed" for them. The walkthrough (A8) is an **(owner)** step.

## Progress

- [x] Phase 1 — the watch icon — Complete: `filename` set in the 1024 `watchos` slot; guard `test/watch_app_icon_test.dart` red→green (see evidence file)
- [x] Phase 2 — the bridge in the package — Complete: `WatchConnectivitySession` + `WatchConnectivityBridge` + `PropertyListFrames` in the package; `transportRequests` in the contract; Dart S-102/S-112 green (`+3881 ~1`); Swift tests written with per-test mutations (see evidence file)
- [x] Phase 3 — the shell gets a radio — Complete: real `WCSession` conformance in the app target, `WatchAppHost` wired to bridge/orchestrator/preferences with the D-8 three-state reachability, `WatchStartSurfaceCopy.unreachableLabel` + the pure `WatchPhoneStatus` rule, `onRequestSync` passed from `ContentView`; Swift tests written with per-test mutations (see evidence file)
- [x] Phase 4 — pushed exercises visible, no-session push safe, docs — Complete: no-session `exercise_push` returns `nil` instead of trapping (D-12), `WatchExercisePickerRow`/`pickerRows`/`selectExercise` carry the picker rule, the picker re-reads on a revision bump, the post-start placeholder is the session's slot ladder with the current one marked, five Swift tests written with per-test mutations, the three docs updated and the walkthrough written (see evidence file)

## Assumption Log

- **S-103's trigger is `sync(reconnect: true)`, not `sync()`.** The scenario says
  `orchestrator.sync()`, but `WatchSyncOrchestrator.sync` only passes `since`
  when `reconnect: true`, and Phase 2 does not change the orchestrator (not a
  Predicted File). The test uses the reconnect form; the frame it asserts is
  unchanged.
- **S-106's distinguishing observable is `preferences.current != nil`.** The
  fixture carries `effortRatingPrompt: false`, which is also
  `WatchEffortRatingCopy.promptBeforeFirstSync`, so `asksForEffortRating` reads
  `false` before and after. What the message changes is that the wrist now holds
  a copy instead of guessing; the test asserts that, plus the unchanged
  empty-state sentence.
- **The plist check tests `String`, then `NSNumber`, and returns the value
  unchanged.** A `Bool` is an `NSNumber` on Apple platforms, and an `NSNumber`
  wrapping `0` or `1` reports the `Bool` type code, so testing `Bool` first
  would hand the radio `true`/`false` where the protocol means `1`/`0` (D-5).
  Returning the original keeps an integer an integer and a `Bool` a `Bool`.
- **`WatchConnectivityBridge` reports a refused send through the same failure
  hook as a refused frame.** D-4 names the hook for the plist refusal; a send the
  platform itself refuses has no other owner, and D-6's "reported and dropped"
  covers it.
- **The bridge's inbound handler is set by the host, not by the initializer.**
  `onIncoming` mirrors `WatchSyncTransport`'s shape and keeps the bridge free of
  a dependency on the orchestrator; a frame that arrives before the host wires it
  is dropped, which is what the next `sync()` recovers from.
- **Phase 3 touches `WatchStartView.swift`, which its Predicted Files omit.**
  Items 3 and 4 require the surface to show the sentence and the button, and the
  file is Phase 4's, not Phase 3's. Edited anyway rather than leaving the phase's
  own Done Criteria unmet; the two files' diffs do not overlap.
- **Phase 3's doc note lives in the constant, not in `docs/`.** Item 3's "note in
  the doc that it moves into the contract" is written on
  `WatchStartSurfaceCopy.unreachableLabel`. The `docs/` updates are Phase 4 item
  7's, which names the same files; Phase 3 leaves them untouched.
- **`reportWatchRadioFailure` is a file-scope function, not a host method.** The
  host builds the session and the bridge before `self` is fully initialised, so
  neither failure hook can be `{ self.report($0) }`. Both point at one function.
- **The sync action passes `reconnect: paths.syncedAt != nil`.** "The first sync
  asks for everything, later ones say what the wrist has" is exactly the
  orchestrator's `reconnect` flag, so the button needs no state of its own.
- **`OmniTrainApp.swift`'s header comment changed by one word** ("and,
  eventually, the transport" → "and the transport"): the target now owns it, and
  Phase 3 is what made the old sentence false.
- **The no-session guard sits after `requireConformingIncoming`, so a malformed
  push still throws.** D-12 asks that a push with no session "changes nothing,
  reports not applied, and does not trap". A frame that cannot cross the radio is
  a different failure and keeps the bridge's failure hook; only a *conformant*
  push into no session is the silent `nil`.
- **The picker is keyed on the row's own `id`, not the exercise id.** Two slots
  can hold the same exercise (the second gets a `-2` slot id), so keying on the
  exercise would collapse them in `ForEach`.
- **The post-start placeholder reads the live `host.engine.session`.** A stored
  snapshot would freeze the ladder on the first frame; the session is the
  surface's only source, and the revision counter already forces the re-read.
- **`startedSessionId` stays the in-session flag rather than a session copy.**
  It is what tells "Back" that a session is open (so returning does not end it),
  and Phase 4 only changes what the branch renders.
- **The bridge tests borrow `routineEdit.routinesDown` as the picker fixture.**
  The picker rule is about slot ids and names, and that fixture is the list the
  wrist already receives; building a second list would test the fixture.

## Feedback

[empty]

## Resolved by the governor

1. **The unreachable sentence's wording.** Accepted as "Phone not reachable";
   the Sync button stays enabled. The owner may reword later — it is one
   constant in `WatchStartSurfaceCopy`.
2. **The phone icon's own alpha channel.** The guard test reports it; the phone
   icon is untouched.
3. **Whether the wrist must host the logging surface.** This unit stands as
   cut: the pushed exercise is visible and selectable, and the post-start
   surface is a placeholder. Hosting the logging surface is the next unit,
   planned separately after this ships.
4. **Whether the wrist should validate with bundled schemas.** Stays out
   (D-13).
5. **The phone-side gaps.** Listed under Moved scope, not fixed.

## Open questions

None. If the Phase 2 fixture-null test finds a JSON null in `routines_down`,
`preferences_down` or `exercise_push`, record it here as a blocker.

**Phase 2 result:** none of the three contains a JSON null, so there is no
blocker. (`foods_down.json` does carry one, but it is not one of the three
fixtures the phone sends with `sendMessage`.)

## Feedback

Review: `2026-10-04-14-watch-shell-bridge-plan.review.md` (iteration 1b).

Fix in one round, then stop:

- [ ] Findings 1–3 — delete the three passages that claim the Swift package is
      still unlinked (`docs/watch-app-setup-and-qa.md:23`, `:158-171`;
      `docs/plans/2026-09-21-13-watch-integration-shipping.md:1169`).
- [ ] Finding 4 — the Dart null walk is not S-112; give it its own label.
- [ ] Finding 5 — the picker re-render sentence: point it at the walkthrough or
      cut it.
- [ ] Finding 6 — tick the Phase 1–3 items, or say why they are unticked.
- [ ] Finding 7 — the label note goes in the doc, or the item says where it went.

