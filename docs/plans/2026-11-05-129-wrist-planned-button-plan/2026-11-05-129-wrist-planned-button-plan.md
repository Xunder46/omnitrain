# Plan — 129: a "Planned" button on the wrist's start surface, and the plan marked started

**Status**: seeded plan, expanded by the architect (2026-11-05 run); no code written.
**Next handoff**: none — all phases done; review 1's findings fixed (plan 129, 2026-11-06). **Originally:** `crew-builder-watch` for P1 items 1–4 (the `watch/sync_protocol/**` wire) — those four items
and P1 items 5–8 (`crew-builder-app`, `lib/**` + `test/**`) have disjoint scopes and may run in the same pass
only after the schema files of items 1–3 are in place (item 5's validator test reads them). P2 waits for the
schema files; P3 waits for P2; P4 runs last.
**Binding conventions**: `docs/global_conventions.md`.
**Track**: the watch client plus its sync contract — one track per the scope budget's ride-with rule (a
contract change rides with its first consumers, `lib/watch` + `watch/watchos` + `watch/sync_protocol`).
**Evidence path**: `docs/plans/2026-11-05-129-wrist-planned-button-plan/2026-11-05-129-wrist-planned-button-plan.evidence.md`
**Review path (reserved)**: `docs/plans/2026-11-05-129-wrist-planned-button-plan/2026-11-05-129-wrist-planned-button-plan.review.md`
**Base commit**: `22376d7e81ff98ecf6ba72e4f76a992390185d22` (branch `claude_develop`).
**Slug**: `2026-11-05-129-wrist-planned-button`.

## Overview

A planned workout for today appears on the wrist's home (start) surface as a de-emphasised **Planned** button at the
very top, above the routine buttons and above the "No routines yet" line. It appears only when a plan is startable
today. One plan → the button is captioned with the plan's name. Two or more → it reads "Planned" and opens a picker of
today's plans by name. Zero → no button. Tapping it starts that workout on the wrist the way the wrist already starts a
routine (the routine's slots become the session), and the phone **marks the plan started** — the same state the phone's
calendar shows after a start on the phone (the plan leaves the planned list, linked to the session).

Owner answers (2026-11-05): the phone pushes the plans in a new `planned_down` message; a free-training plan tapped on the
wrist starts the wrist's plain free workout (no modality on the wrist); completion the way the phone does it, **including**
a wrist→phone `session_started` report so the link happens at the start; plans refresh on launch and each sync, not on a
midnight tick; a second start while a session is live stays refused (the owner: users cannot reach home during a session).

## Goal and acceptance

A planned workout for the wrist's today is offered on the start surface as the first, de-emphasised control; tapping it
starts that workout on the wrist and the phone marks the plan started (link to the wrist's session), the same state a
start on the phone produces. Acceptance: S-8965 (the button/picker table), S-8967 (a tap starts and reports once),
S-8963/S-8964/S-8971 (the phone adopts then links, idempotently), S-8960 (only today's unstarted plans travel),
S-8966 (the wrist keeps the newest list), S-8968 (the report is conformant), S-8969 (the surface's exact source rule).

## What the owner should know (plain language)

1. A plan for today is the first thing on the watch's start screen, in the quiet bordered style (not the filled,
   prominent style the routines use), so it never competes with "start your routine".
2. Tapping it starts that plan, with the same exercises the routine gives you on the wrist. On the phone's calendar the
   plan is no longer listed as merely planned: it is the workout you started, just as when you start it from the phone.
3. Two plans today → the button says "Planned" and asks which one.
4. A plan whose routine is no longer on the watch does not offer itself; a plan you already started (on either device) is
   not offered either.
5. A free-training plan on the wrist starts the wrist's plain free workout, because the phone's free start carries a
   modality the wrist does not (recorded deviation).
6. Already started, not un-done: like the phone today, nothing on either side un-completes a plan when a session is
   discarded; the discard repair the lead found is a follow-up, not this unit.

## Questions

1. **Does the wrist's host app change?** Default: no. `paths` is already handed to `WatchStartView` and the host
   re-runs the surface on every `revision` bump (the arrival arrives through the existing plumbing), so the planned
   button reads the same store the routine buttons read. A host change rides only if a build proves one necessary.
2. **Where does the seeded "sentence that lists what the wrist sends the phone" live?** Default: `docs/watch_session_sync.md:21`
   (the Structure table's first row). No sentence in that doc enumerates the wrist's sends; see Docs delta row 3.
3. **Emitted-at for the placeholder the phone adopts on `session_started`.** Default: the phone's adoption clock, as the
   snapshot path does today (`_adopt`, `startedAtMs: atMs`) — the report's `at` is not trusted for the row.

## Facts established before the build (the architect's open questions, decided)

1. **The wrist→phone channel already exists; only the message is new.** `session_lifecycle` with `state: "started"` is
   already emitted and is durable (`watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift:239`,
   `isDurable` lists `session_lifecycle`), and the contract pins it (`watch/contract/watch_start_paths_contract.json`,
   `sessionStarted` = `{type: session_lifecycle, origin: watch, state: started}`). The wrist emits on every start, so the
   owner's "the same as the phone" rules out completion from the `started` frame alone: the wrist starts a session from
   a routine button too. **D-8974** therefore adds `"session_started"` to `isDurable` (a report the wrist can retry
   after the workout must not be dropped by the radio rule) and a `plannedStart` block to the contract file.
2. **The session id the phone stores on `session_started` is the wrist's own (corrected by D-8977, 2026-11-06; this
   item first said "the phone's own minted id" and was stale).** The phone opens the row under `report.sessionId`, the
   id its first snapshot will carry, so the snapshot finds that row rather than a second one, and
   `CalendarState.completePlannedSession(planId, report.sessionId)` links the plan to it. The plan's `linkedSessionId`
   therefore always points at a row the phone owns. Since D-8978 the first snapshot also lands the ladder in that row.
3. **Nothing is reused.** The wrist never adopts an existing phone session on a start: that is the snapshot path's
   job, and a plan tapped while the phone holds a routine session must not append to it (the owner: no second start).
4. **Dart's wrist client gets the same `Start planned` path** (new `lib/watch/start/watch_planned_start.dart`, D-8975):
   its engine already exposes lifecycle emission (`replaySessionEnd()`, `watch_session_engine.dart:364`), so the report
   rides that seam the way D-8970 rides the Swift one. The surface (D-8976) is Swift-first; the Wear client is covered
   by the contract row and the shared engine test, not by a screen.

## Corrections to the seed's line numbers (seeded text above keeps its own numbers)

- `WatchStartPathError.unknownRoutine` is declared at `WatchStartPaths.swift:282` (`case unknownRoutine(String)`);
  D-8963's `:280` is the enum's opening brace. `startFromRoutine`'s throw is at `:563`, inside `:561` ✓.
- `WatchSessionAdoptionBridge.consider` begins at `watch_session_adoption_bridge.dart:662`; D-8966's `:709` sits
  inside its body (the skip-report). `onLifecycle` `:757` ✓, `_adopt` `:798` ✓.
- `day_session_list_screen.dart`: the seed's `:337`–`:380` (the form) was not re-checked this run; verified this run:
  `_submit` at `:921` and the routine-mode `modality: _mode == 'free' ? _selectedModality : null` line at `:923`
  (the seed's `:922` → `:923`).
- `watch_incoming_router.dart`: `receive` at `:121`; the `session_lifecycle` branch sits at `:170`–`:173` (seed's `:171` ok).
- All other seeded pointers verified this run: `WatchReferenceSync.buildRoutinesDown` `:119`,
  `WatchSyncRequestHandler._sendRoutines` `:184` / `_bundle` `:381`, `messageTypes` `message_validator.dart:106`,
  `SyncProtocolValidator.messageTypes` `:61`, `createSession` refusal `WatchSessionEngine.swift:336`,
  `emitLifecycle` `:1337`, `emit` `:2109`, `requireConformant` `:2115`, `restore`/`applyRoutinesDown`
  `WatchStartPaths.swift:379`/`:402`, `WatchRoutinesDown`/`WatchRoutineCatalogRecord` `WatchRoutineRecords.swift:339`/`:399`,
  `PlannedSession` `models.dart:1471`, `labelForModality` `modality_color_utils.dart:17`,
  `createPlannedSession`/`completePlannedSession`/linked-plan exclusion `calendar_state.dart:196`/`:235`/`:157`,
  `deletePlannedSessionsByTemplateId` `routine_state.dart:275`, `receive` `WatchSyncOrchestrator.swift:193`,
  `WatchStartView` body/`start(_:)`/`startFreeWorkout()` `WatchStartView.swift:114`/~`:231`/`:245`,
  `PROTOCOL.md` message families table `:64`–`:80`, `since` bullet `:161`, amendment table `:800+`,
  manifest `watch/sync_protocol/fixtures/manifest.json` (top `protocolVersion: 1`; the `water_down_watch_origin`
  invalid entry at `:745` is the invalid-entry template).

## Decision Ledger

| Id | Decision |
|---|---|
| D-8960 | **A new message `planned_down`, not a field on `routines_down`.** `routines_down`'s payload is pinned by `additionalProperties: false` (`watch/sync_protocol/schemas/messages/routines_down.schema.json`) and its `generatedAt` is the identity that makes a repeat the same message; a plan edit must not rebuild the routine catalog. The phone sends both frames from the one bundle it already answers a routine request with (`lib/state/watch/watch_sync_request_handler.dart`, `_bundle` and `_sendRoutines`). |
| D-8961 | **The plan row on the wire.** `plannedSessionId`, `name` (never empty), `scheduledDateMs` (the phone's local start of day, as stored), `routineTemplateId` (nullable), `modality` (nullable), `createdAtMs`, `updatedAtMs`. Name = the plan's own `title`, else its routine template's name, else the phone's modality label, else "Free Training" (`lib/core/utils/modality_color_utils.dart:17` `labelForModality`). Evidence for the model: `lib/data/models/models.dart:1471`. |
| D-8962 | **Which plans the phone sends.** Not started (`isCompleted == false && linkedSessionId == null`), scheduled from today − 1 day to today + 13 days inclusive, sorted by `scheduledDateMs` then id. The wrist filters to its own today; yesterday is sent so a timezone difference does not hide the wrist's own today. Evidence: a linked or completed plan is not a calendar entry (`lib/state/calendar/calendar_state.dart:157`). |
| D-8963 | **The rule, one function, table-tested.** Plans that are **startable** = scheduled in `[today, today + 1 day)` by the wrist's own clock AND (free, or their routine is among `paths.routines`). 0 → no button; 1 → a button captioned with its name; 2+ → a button captioned "Planned" opening a picker. Picker order: `scheduledDateMs`, then name, then id. A routine plan whose routine the wrist does not hold is never startable and never counted. Evidence: `startFromRoutine` throws `unknownRoutine` (`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift:282` — the seed's `:280` is the enum's brace; throw at `:563`). |
| D-8964 | **What a tap does.** Routine plan → `paths.startFromRoutine(routineTemplateId)`; free plan → `paths.startFreeWorkout()` (the owner accepted the wrist's plain free workout: its free start carries no modality). Both then report the start (D-8966) and hand the session to `onSessionStarted`, exactly as the routine buttons do (`watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift:~231`). A tap while a session is live emits nothing and changes nothing — the engine already refuses the second start (`WatchSessionEngine.swift:336`). |
| D-8965 | **Styling.** `.buttonStyle(.bordered)` like "Free workout" and "Sync"; never `.watchProminent()`. First child of the surface's `VStack`. |
| D-8966 | **`session_started`, and the phone's link order.** Watch→phone, origin `watch`, payload `sessionId` (the wrist's own id), `routineTemplateId` (nullable), `plannedSessionId` (nullable), `at` (ISO UTC). Emitted by `WatchSessionStartPaths.startPlanned` right after the session exists — not by the engine's generic start, so a start from a routine button sends nothing new. The phone: **adopt** when the wrist's session is not yet held (route through `WatchSessionAdoptionBridge.consider`, `watch_session_adoption_bridge.dart:662`, the same path a first snapshot uses), **then** `CalendarState.completePlannedSession(planId, sessionId)`. Adopt-then-link because a plan linked before its session row exists would point at nothing if the adopt failed. Evidence: `lib/state/watch/watch_incoming_router.dart:121`/`:170`–`:173`; `onLifecycle` `:757`, `_adopt` `:798`. |
| D-8967 | **Neither the start nor the link can break the workout.** The wrist emits on its existing channel, so the frame is queued and retried like any other wrist frame (`WatchConnectivityBridge`); the phone's link is best-effort: an unknown plan id is a no-op (`completePlannedSession` already returns after reloading), a session already linked is left as the first link set it, and no error reaches the user. |
| D-8968 | **Additive at protocolVersion 1.** Older peers drop the new types whole (Dart's `messageTypes` registry and the wrist's `receive` default); the plan says so in PROTOCOL.md and the manifest. |
| D-8969 | **Refresh on launch and sync only.** The surface reads `paths.startablePlannedSessions` in `body` and on every `revision` bump; no timer. A wrist left open across midnight keeps yesterday's answer until the next sync — recorded, owner-approved. |
| D-8970 | **The emission seam is the engine's existing sink (architect).** `session_started` is built and sent through `WatchSessionEngine`, not a second channel: one public method in the shape of `replaySessionEnd()` (`WatchSessionEngine.swift:1344`, `requireConformant` `:2115` + `emit` `:2109`), taking the session's own ids; `WatchSessionStartPaths.startPlanned` calls it right after the session exists, including the fill-in-place path (`WatchStartPaths.swift:558`–`:570`). Message id derived: `msg-session-started-<sessionId>`. `WatchStartPaths` holds no emit channel (engine, store, validator, clock, id factory only), so the seam lives on the engine; a refused frame throws `WatchEmissionRejected`, which the path swallows and the start stands (D-8967). |
| D-8971 | **`planned_down` rides the routine request outside the `since` gate (architect).** Sent on every routine request after the since-gated bundle, like `water_down` rides `wantsWater` (`_sendRoutines`, `watch_sync_request_handler.dart:184`), with the request's bundle stamp. It does **not** enter the handler's `referenceText` stamp cache: that cache rebuilds only when `referenceRevision` moves, and the reference listeners watch the reference-data boxes only (`hive_workout_repository.dart:266`–`:288`; `mock_workout_repository.dart:1936` returns null) — a plan started on the phone writes the plans box alone, so a cached plans frame would stay stale until restart. |
| D-8972 | **The link is idempotent (architect).** The bridge links only when the plan is `isCompleted == false && linkedSessionId == null`; a repeat report, a plan already linked, or an unknown `plannedSessionId` changes nothing and throws nothing. The report is judged conformant before anything is written. |
| D-8977 | **The report creates the phone's session row when there is none (lead, 2026-11-06).** The phone's own view of a wrist session is created by its snapshot path (`WatchSessionAdoptionBridge._adopt`, `watch_session_adoption_bridge.dart:798`–`:830`), and the first snapshot arrives after the plan was started. So `onSessionStarted` creates that row itself — `TrainingSession(id: report.sessionId, …)` with the routine's name/intent, plus `LoggedEntryRows.defaultSegment` — and copies **no** efforts: the wrist's ladder arrives with the first snapshot, and a second structure from the phone would double it. The plan links to `report.sessionId`, the id the phone will hold. Evidence: `_adopt`'s own comment "(D-2) a routine run opens as the routine it is"; the snapshot's add-only merge. |
| D-8974 | **The report is durable, and the contract pins it.** `WatchConnectivityBridge.isDurable` (`watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift:239`) gains `"session_started"`: a start report the radio cannot carry is handed to the OS queue and delivered when the two devices meet, like a lifecycle. The contract gains `plannedStart` (Docs delta row 8), which both suites read. Evidence: the existing `sessionStarted` block and `isDurable`'s `session_lifecycle` arm. |
| D-8975 | **The Dart wrist client starts plans through the same seam.** `lib/watch/start/watch_planned_start.dart` (new) holds `startPlanned(plan)` = `startFromRoutine`/`startFreeWorkout` + a `session_started` emission built like `replaySessionEnd()` (`lib/watch/session/watch_session_engine.dart:364`) and gated by the validator; its test is the parity test both clients' suites share (`test/watch_session_engine_test.dart`, contract row `plannedStart`). |
| D-8976 | **The surface is Swift-first, one shared rule.** The button and picker live in `WatchStartView` (P3). The Dart Wear surface is out of this unit (recorded under Noticed not planned): the owner's target is the Apple Watch, and the contract + engine parity keep the second client able to follow. |
| D-8973 | **The phone's link step is an optional callback (architect).** The bridge takes `onPlanStarted(plannedSessionId, sessionId)` (the shape of `onHistoryChanged`/`onSkipped`, `watch_sync_wiring.dart:208`), passed down `createWatchSync` and wired in `lib/main.dart:372` where `calendarState` already exists, to `CalendarState.completePlannedSession`. Tests pass a recorder; a graph built without it links nothing (D-8967). Keeps `WorkoutRepository` the bridge's only persistence dependency. |
| D-8978 | **A report-opened row takes the ladder from the first snapshot (follow-up fix, validated 2026-11-07).** D-8977's row is effort-less, but `WatchSessionAdoptionBridge.consider` skipped `_adopt` for any existing row ("a snapshot never rewrites its rows") and only loaded it, so after report → first snapshot the phone held the session with **no exercises** (`hasActiveSession` false) until a second snapshot grew the ladder through `_reconcile` (observed 2026-11-07). The radio makes the order real: the wrist queues only the newest active snapshot (`WatchConnectivityBridge.queueNewest`), so it can land behind the durable `session_started`. The fix: a row that is not ended, not held, and has **no effort in any segment** while the snapshot carries a non-empty ladder is a *placeholder*; `consider` writes the ladder into it exactly as `_adopt` writes one (efforts, routine planned rows, `_everSeen`) and seeds the first entries like a fresh adoption. A row that already holds an effort (adopted before, or trained on the phone) is untouched (D-2, D-10, G1 `alreadyEnded` unchanged). `_startSessionRow` also stamps the routine's Focus (`modality: template?.focusModality`) the way `_adopt` does (plan 122 D-12201c), so the two ways to open a routine row read the same. Evidence: `watch_session_adoption_bridge.dart` `consider` (existing-row branch), `_adopt`, `_startSessionRow`. |

## Scenarios

Every scenario below derives its date values at run time from `DateTime(2026, 11, 5)` local (Dart) or from an injected
clock (Swift); no epoch literal is hard-coded (the seed's numbers were machine-timezone-specific).

| Scenario | Fixture | Expect | Fails without the change |
|---|---|---|---|
| S-8960 | `tpl-push` (one segment, one `set` effort `ex-bench`, caps `reps,load,sets`), `tpl-legs` (`ex-squat`); plans `p-today` (tpl-push, today), `p-tomorrow` (tpl-legs, today+1), `p-linked` (today, `linkedSessionId 's-x'`), `p-done` (today, completed), `p-old` (today−5), `p-late` (today+13) | `buildPlannedDown` sends `[p-today, p-tomorrow, p-late]` in that order with names `Push`, `Legs`, `Legs`; payload carries `generatedAt` + `plans` | `WatchReferenceSync` has no builder: `buildPlannedDown` does not exist |
| S-8961 | `p-titled` (`title 'Hill sprints'`), `p-routine` (tpl-push), `p-free` (modality `sports`, no title), `p-bare` (nothing) | names `Hill sprints`, `Push`, `Sports`, `Free Training` | no builder exists |
| S-8962 | `tpl-empty` (one effort on an exercise with no capabilities, so `routines_down` omits the routine); plan `p-empty` on it | the plan row still carries `routineTemplateId 'tpl-empty'` | no builder exists |
| S-8963 | `test/watch_session_import_test.dart`'s graph + plan `p-today` (tpl-push); feed `session_started` (`w-1`, `tpl-push`, `p-today`) | a `TrainingSession` `w-1` with `routineTemplateId 'tpl-push'`, one segment, the routine's effort; `p-today.isCompleted` true, `linkedSessionId 'w-1'` | the router has no branch for the type |
| S-8964 | S-8963's graph; then `w-2` free with no plan; a report naming `p-missing`; a report with an empty `sessionId`; a report for a session the phone already holds | `w-2` adopted, no plan touched; `p-missing` links nothing and throws nothing; the empty id is dropped; the held session links only | nothing handles the type |
| S-8964b | S-8963 and S-8964 again under `HiveWorkoutRepository` in a temp box, reading the plan row back | the same outcomes, and the plan row reads completed after the graph's reload | nothing handles the type |
| S-8965 | `WatchSessionStartPaths` + held routines; case table: no plans; one routine plan for a held routine; one for a routine not held; two today; one free plan; yesterday+tomorrow; `today+23:59:59`; exactly `today` | none; one captioned `Push A`; none; picker ordered by date then name; one captioned its name; none; counts; counts | no `startablePlannedSessions` exists |
| S-8966 | `planned_down` at T (plan A), at T−60 s (plan B), at T+60 s (plan B); relaunch; a watch-origin frame; an unknown field | A, still A, B, B after `restore()`, both rejected before storing | no such apply or store |
| S-8967 | routine plan `p-1`; a free plan; a tap while a session is live | the same exercises as `startFromRoutine` (tokenised ids) and one `session_started` naming plan+routine; an empty session and one report with no routine id; nothing emitted, the held session returned | no `startPlanned` and no emission |
| S-8968 | the engine's emitted `session_started`; one with an extra field; one with no `sessionId`; one with phone origin | passes `SyncProtocolValidator.validateEnvelope`; the other three fail; the message id is derived from the record | the type is unknown to the validator |
| S-8969 | `WatchStartView.swift` source text | the planned button is the first button in the `VStack`; `.buttonStyle(.bordered)`; routine buttons keep `.watchProminent()`; caption exactly `plans.count > 1 ? WatchStartSurfaceCopy.plannedLabel : plans[0].name`; picker from `@State`; no other picker text; constants defined once | no such button or constants |
| S-8972 | `_sendRoutines` with a `since` set, with an empty `since`, and with the plans frame refused by the validator | the plans frame is sent in every case and is never served from `referenceText`; the exercise list is still sent when the plans frame is refused | nothing sends plans |
| S-8970 | engine queue harness (`WatchBridgeQueueTests`) | a `session_started` queued behind a live session's frames and delivered in order; a refused frame is not re-sent by the engine itself | no such emission exists |
| S-8971 | S-8963 harness: a second identical report, then `p-today` named from `w-9`, then `p-done` named by any report | `linkedSessionId` stays `w-1`, no second row, nothing thrown; `p-done` untouched | no handler exists |
| S-8980 | the adoption harness (`_phone`: real inbox + mirror + router + bridge + bound `WorkoutState`), Mock and Hive: a `session_started` for `s-w1` (no plan), then the S-1 snapshot (`sl-1` bench, `sl-2` squat, revision 3), then the same ladder at revision 4 | after the report: row, one segment, no effort. After the FIRST snapshot: efforts `[sl-1, sl-2]` in order 0,1, `phone.state.currentSession.id == 's-w1'`, `hasActiveSession` true, one first entry per effort as an ordinary adoption seeds; rows equal an ordinary S-1 adoption's (`importedRows` parity, ignoring the session row's own stamps). After the SECOND: rows unchanged, no doubled effort, no failure | the first snapshot loads the effort-less row only (`consider`'s existing-row branch skips the ladder): efforts `[]`, `hasActiveSession` false |
| S-8981 | the S-8963 harness with a routine whose Focus is `strength` (`focusModality`), `p-today` on it; the report names the routine | the report-opened row carries `modality: 'strength'` (the routine's Focus), a free report's row carries none | `_startSessionRow` writes no `modality` |

Protocol fixtures (registered in `watch/sync_protocol/fixtures/manifest.json`): `valid/planned_down.json`,
`valid/planned_down_empty.json`, `valid/session_started.json`, `invalid/planned_down_watch_origin.json`,
`invalid/session_started_missing_session.json`.

### Input-reality checklist (answered; copied from the seed)

1. **Writers.** Plans are written by `CalendarState.createPlannedSession` (`calendar_state.dart:196`) from the day-list
   form (`day_session_list_screen.dart:337`–`:380`); routine mode stores `modality: null` (`:923`: seeded `:922` —
   corrected, see the corrections list) and only `routineTemplateId` identifies the routine. A plan is marked started
   only by `CalendarState.completePlannedSession` (`:235`), called by the phone's `_tapPlanned` (`:280`–`:330`, on
   `onSessionSaved` ~`:303`–`:306`) and by this unit's router. A deleted routine deletes its plans
   (`lib/state/routine/routine_state.dart:275`). Nothing un-completes a plan today (owner-known follow-up).
2. **Lifecycle.** Unfinished → sent; linked or completed → not sent and not startable; routine deleted → its plans are gone
   with it; routine no longer on the wrist → not startable; free plan → startable as the free workout; a plan in the past but
   within yesterday → sent, not startable today.
3. **Settings.** None affects the answer. No unit, time format or accent is printed on this button.
4. **Time.** `scheduledDateMs` is the phone's local start of day; the wrist compares against its own start of day, so the
   boundary is the wrist's day (approved). Exactly midnight counts; `23:59:59.999` counts; a clock-change day compares date
   components, never elapsed ms.
5. **Cost.** The phone adds one `getPlannedSessions` read to the routine request answer outside the stamp cache
   (`getPlannedSessions`: `workout_repository.dart:367`, `hive_workout_repository.dart:2749`,
   `mock_workout_repository.dart:1787`); the wrist reads the stored catalog once per `restore()` and once per `planned_down`.
6. **Words.** Sweep run this run (grep, `docs/` minus `docs/plans`, `docs/history`, `docs/releases`): "No routines yet" →
   only plan docs (no REMOVED/MODIFIED row); "Free workout" → `watch-app-setup-and-qa.md` (the second-start sentence stops
   being complete — Docs delta row 6), `watch-app-qa-wrist-logging.md` and `watch_sensors.md:117` and
   `watch_surface_wrist.md:216` (all stay true — the free path is unchanged); "routines_down"/"three-frame bundle" →
   `state_management/watch_surface.md:517`–`:529` (stays literally true under D-8971; gains an ADDED row) and
   `watch/sync_protocol/PROTOCOL.md:161` (stays true — `planned_down` is outside the gate; gains an ADDED row).
7. **Competition.** The button takes the top slot of the start surface (owner's choice); the picker orders by date, then
   name, then id; the plans' `generatedAt` competes only inside their own store, never with the routine catalog's.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|
| `watch/sync_protocol/PROTOCOL.md` | ADDED | - | `planned_down` | S-8960, S-8968 |
| `watch/sync_protocol/PROTOCOL.md` | ADDED | - | 1 (amended) | S-8972, D-8971 |
| `docs/state_management/watch_surface.md` | ADDED | - | buildPlannedDown | S-8972, S-8965, S-8969 |
| `docs/state_management/watch_surface_wrist.md` | ADDED | - | Today's planned workout is the surface's first control. | S-8965, S-8969 |
| `docs/watch_session_sync.md` | ADDED | - | WatchSessionAdoptionBridge.onSessionStarted | S-8963, S-8964, S-8971 |
| `docs/watch-app-setup-and-qa.md` | ADDED | - | The Planned button's | S-8967, D-8964 |
| `docs/README.md` | ADDED | - | The Watch Surface — the Wrist's Logging Session | S-8965 |
| `watch/contract/watch_start_paths_contract.json` | ADDED | - | "plannedStart" | S-8968 |
| `watch/contract/watch_start_paths_contract.json` | ADDED | - | "routinesPlans" | S-8972, D-8971 |
| `docs/watch_session_sync.md` | MODIFIED | the first snapshot brings the ladder, D-8977 | writes the wrist's ladder into it and seeds the first entries | S-8980, D-8978 |

Notes: rows record where each sentence landed (the New marker is the phrase to grep). The seeded rows' prose is
kept in the phase list below; the keeper's report (`<feature>-plan.evidence.md`, P4 notes) names the exact sentences
and their test cites. Row order follows the file: the two PROTOCOL rows, the two surface rows, the sync row, the QA row
and the two contract rows.
- Row 3 (seeded) — the seed asked for "the sentence that lists what the wrist sends the phone"; no such sentence exists in
  `docs/watch_session_sync.md` (grep, this run). The closest sentence is the Structure table's first row (`:21`,
  "The session the wrist is running becoming the phone's own in-progress session"), which is what the row now cites;
  raised under Open questions (the plan builds against this default).
- `docs/watch_session_capture.md:35` ("Staging what a wrist sends: effort entries, the effort rating, the session end and
  the rests it observed (D-210), from `observations_up` and from a wrist `session_snapshot`") stays true: `session_started`
  is not staged through the inbox — it is routed to the adoption bridge — so the sentence is unchanged.
- No REMOVED rows: no doc sentence becomes false; the changes are additive (D-8968) or extend existing truths.

## Phases

### P1a — the wire (schema, fixtures, contract)

**Owner**: `crew-builder-watch`. Write scope: `watch/sync_protocol/schemas/**`, `watch/sync_protocol/fixtures/**`,
`watch/contract/watch_start_paths_contract.json`.

1. [ ] Envelope type enum — `watch/sync_protocol/schemas/envelope.schema.json` · `properties.type.enum` gains `planned_down` and `session_started`.
2. [ ] `planned_down.schema.json` (new) — origin `phone`, payload required `[generatedAt, plans]`, `additionalProperties: false`; each plan per D-8961 (`plannedSessionId`, `name` `minLength: 1`, `scheduledDateMs`, nullable `routineTemplateId`/`modality`, `createdAtMs`, `updatedAtMs`).
3. [ ] `session_started.schema.json` (new) — origin `watch`, payload required `[sessionId, routineTemplateId, plannedSessionId, at]`, `sessionId` `minLength: 1`, `additionalProperties: false`.
4. [ ] Five fixtures registered in `watch/sync_protocol/fixtures/manifest.json` (template: the `water_down_watch_origin` invalid entry): `valid/planned_down.json`, `valid/planned_down_empty.json`, `valid/session_started.json`, `invalid/planned_down_watch_origin.json`, `invalid/session_started_missing_session.json` — each with its `scenario` and its expected rejection code.
5. [ ] Contract row — `watch/contract/watch_start_paths_contract.json` · new `plannedStart` block (D-8974).

**Done criteria**: the Dart fixture walk (`flutter test test/sync_protocol_fixtures_test.dart`) and `swift test --filter SyncProtocolFixturesTests` see the entries — both run in P1b/P2, which wait for this phase.

### P1b — the phone's side

**Owner**: `crew-builder-app`. Write scope: `lib/core/sync_protocol/message_validator.dart`, `lib/core/utils/watch_reference_sync.dart`,
`lib/state/watch/watch_sync_request_handler.dart`, `lib/state/watch/watch_incoming_router.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/watch/watch_sync_wiring.dart`, `lib/main.dart`,
`test/watch_reference_sync_test.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_session_import_test.dart`,
`test/watch_session_adoption_bridge_test.dart`. Never run the full `flutter test`.

1. [ ] Registry — `message_validator.dart` · `messageTypes` (:106) gains both types, placed in the family order the list already follows.
2. [ ] Builder — `watch_reference_sync.dart` · new `buildPlannedDown` beside `buildRoutinesDown` (:119) with the D-8961 name cascade and the D-8962 window (today from `generatedAt`, phone-local), sorted date → id → name; tests in `test/watch_reference_sync_test.dart` (S-8960, S-8961, S-8962; all dates derived at run time).
3. [ ] Send it — `watch_sync_request_handler.dart` · `_bundle` (:381) gains `plans`, `_sendRoutines` (:184) sends it after the since-gated bundle and outside `referenceText` (D-8971); `test/watch_sync_request_handler_test.dart` gains S-8972 (sent whatever `since`, never cached, the exercise list still sent when the plans frame is refused). `test/watch_sync_changed_only_test.dart` stays green untouched.
4. [ ] Route it — `watch_incoming_router.dart` · `receive` (:121) gets a `session_started` branch beside the `session_lifecycle` block (:170–:173); `watch_session_adoption_bridge.dart` · new `onSessionStarted` (conformant first; empty id dropped; no session is adopted or reused — the snapshot path stays the only adopter; idempotent link per D-8972 through the D-8973 callback). No phantom session is created: the report names a session the wrist is running, whose first snapshot adopts it (plan 69's rules and the owner's "nothing stored on the phone" rule out a second pointer).
5. [ ] Wire the callback — `watch_sync_wiring.dart` · `_WiringAdoptionBridge` passes `onPlanStarted`; `main.dart` · the `createWatchSync` call (:372) wires `calendarState.completePlannedSession`; tests: `test/watch_session_import_test.dart` (S-8963, S-8964, S-8964b, S-8971 — Mock and Hive) and `test/watch_session_adoption_bridge_test.dart`.

**Done criteria**: `flutter analyze` at the plan's baseline; `flutter test test/watch_reference_sync_test.dart test/watch_sync_request_handler_test.dart test/watch_sync_changed_only_test.dart test/watch_session_import_test.dart test/watch_session_adoption_bridge_test.dart test/sync_protocol_fixtures_test.dart` green, counts pasted.

### P2 — the wrist's engine and storage (serial after P2's inputs: waits for the schema files of P1 items 1–3)

**Owner**: `crew-builder-watch`. Write scope: `watch/watchos/Sources/WatchSessionEngine/WatchPlannedRecords.swift` (new),
`WatchSessionStore.swift`, `WatchRecords.swift`, `FileWatchSessionStore.swift`, `WatchSessionEngine.swift`,
`WatchStartPaths.swift`, `WatchSyncOrchestrator.swift`, `SyncProtocolValidator.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/**` (new test files included).

1. [ ] Write the planned records — `watch/watchos/Sources/WatchSessionEngine/WatchPlannedRecords.swift` (new) · `WatchPlannedSession`, `WatchPlannedDown` (`init(envelope:)`, `init(catalog:)`, `toRecord(recordId:recordedAt:)`) and `WatchPlannedCatalogRecord` (`toJson`/`fromJson`), each mirroring `WatchRoutineRecords.swift`'s `WatchRoutinesDown` (:339) and `WatchRoutineCatalogRecord` (:399) field for field, with a JSON parser that reads `additionalProperties: false`-strictness via the validator's gate and never from memory.
2. [ ] Add the record type — `watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift` · the `.plannedCatalog` case (pattern of `.routineCatalog`, rows `:717`/`:854`) and `watch/watchos/Sources/WatchSessionEngine/WatchSessionStore.swift` · `WatchStoreContents` (`plannedCatalogs` beside `routineCatalogs` at :41).
3. [ ] Store and read the row — `watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift` · `appendLocked` (dedupe on `recordId` + `recordType`, as today) and `readAllLocked` (the `plannedCatalog` row switch).
4. [ ] Add the public emission seam — `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` · new public `emitSessionStarted(sessionId:routineTemplateId:plannedSessionId:at:)` in the shape of `replaySessionEnd()` (`:1344`): build the envelope, `requireConformant` (`:2115`), `emit` (`:2109`); message id `msg-session-started-<sessionId>` (D-8970). The name starts with none of the append-only guard's banned verbs (`WatchSessionEngineTests.swift:339`–`:341`).
5. [ ] Grow the start paths — `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` · `applyPlannedDown` (validate → parse → drop older than the stored `generatedAt` → append; pattern of `applyRoutinesDown` :402), `restore` (:379 also reads `plannedCatalogs` into `storedPlans`), `startablePlannedSessions` (D-8963's table, computed on every read from `clock()` — no cache, no timer) and `startPlanned` (D-8964: a routine plan routes through `startFromRoutine` — including the fill-in-place branch :558–:570, which emits too (D-8970); a free plan through `startFreeWorkout` :594; every successful start emits one `session_started` with the plan's `plannedSessionId` and the routine's template id when it names one; a second start while a session with exercises is live emits nothing and returns the held session). New names `applyPlannedDown`, `startablePlannedSessions`, `startPlanned` start with none of the banned verbs.
6. [ ] Route the frame — `watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift` · `receive` (:193, a `case "planned_down"` beside `routines_down` :196 returning `paths.applyPlannedDown(envelope).applied`).
7. [ ] Make the report durable — `WatchConnectivityBridge.swift` · `isDurable` (:239) gains `"session_started"` (D-8974); a test in `WatchBridgeQueueTests` (S-8970).
8. [ ] Add the types to the Swift registry — `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift` · `messageTypes` (:61, 13 → 15).
9. [ ] Write the wrist tests — `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedRecordsTests.swift` (new; S-8966 storage table), `WatchSessionStartPathsTests.swift` (S-8965 table; S-8967; both harnesses feed `generatedAt` values derived at run time from a `DateComponents`-built 2026-11-05, never hard-coded epoch ms), `WatchSessionEngineTests` (S-8968 conformance: the emitted frame passes `validateEnvelope`; extra field / missing `sessionId` / phone origin each rejected; `testS004NoMutatingOperationExistsAnywhereInTheModule` and the module-wide verb test stay green), `WatchBridgeQueueTests.swift` (S-8970's queue row, in the S-6702 shape), and `SyncProtocolFixturesTests.swift` picks the manifest's new entries up through the shared fixture loader.

**Done criteria (P2)**: `swift test --filter WatchPlannedRecordsTests`, `--filter WatchSessionStartPathsTests`, `--filter WatchSessionEngineTests`, `--filter WatchBridgeQueueTests`, `--filter SyncProtocolFixturesTests` all green (run through `.github/copilot/scripts/macos/gateway.sh`, check `swift-test`); append-only store contract (`s004`) and the verb guard untouched and green. No `xcodebuild` — that stays with the governor.

**Predicted files**: P2's write scope and nothing else.

### P3 — the wrist's surface (serial after P2)

**Owner**: `crew-builder-watch`. Write scope: `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift` (only `WatchStartSurfaceCopy`),
`watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSurfaceSourceTests.swift` (new). No design latitude (S-8969).

1. [ ] Add the copy — `WatchStartPaths.swift` · `WatchStartSurfaceCopy` (:34): `plannedLabel` (`"Planned"`) and `plannedPickerTitle`, each defined once.
2. [ ] Add the button — `WatchStartView.swift` · `body`'s first child (:114): `if !paths.startablePlannedSessions.isEmpty`, a `Button` captioned `plans.count > 1 ? WatchStartSurfaceCopy.plannedLabel : plans[0].name`, `.buttonStyle(.bordered)`, above the "No routines yet" line (:117) and the routine buttons (D-8965, S-8965's table decides whether it renders at all). Tapping opens the picker sheet rather than starting when two or more plans are startable.
3. [ ] Add the plan picker — `WatchStartView.swift` · `@State private var pickingPlan` (beside `pickingExercise` :108) and a `.sheet(isPresented:)` (pattern of the exercise sheet :156–:161) whose rows are the startable plans only, ordering `scheduledDateMs` → name → id, and nothing but the plan names; the row's tap runs `startPlanned(plan)`.
4. [ ] Wire the start — `WatchStartView.swift` · new `private func startPlanned(_ plan:)` (pattern of `start(_:)` ~:231): `await paths.startPlanned(plan.plannedSessionId)`, then `onSessionStarted(session)`; nothing is caught (the one throw is the emission gate's, and a start that could not report is still a start).
5. [ ] Pin the surface with a source test — `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSurfaceSourceTests.swift` (new; S-8969: the planned button is the first button in the `VStack`'s children, `.buttonStyle(.bordered)` and never `.watchProminent()`, the exact caption expression, the picker presented from `@State`, constants once in `WatchStartSurfaceCopy`); the host app target changes only if a build proves it must (P3's scope does not include it).

**Build note (lead)**: `swift test` never compiles `#if os(watchOS)` code, so no test can see the button compile. The
lead builds the app target before review (rule (an)): `xcodebuild -workspace ios/Runner.xcworkspace -scheme "OmniTrain
Watch App" -destination "platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)" -derivedDataPath <scratchpad>/dd
build`, then removes `watch/watchos/build/` if the build leaves one. The build's result goes in the evidence file; the
builder does not run it.

**Done criteria (P3)**: `swift test --filter WatchPlannedSurfaceSourceTests`, `--filter WatchSessionStartPathsTests` (the new source constants' consumers) green; `swift build` inside the gateway's build check.

**Predicted files**: P3's write scope and nothing else.

### P4 — the docs (last; after the code is final)

**Owner**: `crew-docs-keeper` (rows 2, 3, 6; row 4's `watch_session_sync.md` too), except row 1 — `PROTOCOL.md` is
`watch/**`, so the lead hands that row to `crew-builder-watch` in a docs-only run. Write scope: the five docs in the
table below plus nothing else. `docs/` stays below 52 KB per file; every behaviour sentence names an existing test.

1. [ ] `watch/sync_protocol/PROTOCOL.md` (docs-only, `crew-builder-watch`): the ADDED rows 1 and 4 — the two message families rows (:64–:80), their notes after the table, and the v1 amendment-table row (:800+) naming the fixtures and the `since`-gate exemption.
2. [ ] `docs/state_management/watch_surface.md`: the ADDED rows 2 and 5 — the home surface's Planned button rule and neutral style, and the handler's `planned_down` sentence in the `WatchSyncRequestHandler` section (:516).
3. [ ] `docs/state_management/watch_surface_wrist.md`: the ADDED row 6 — the Planned button paragraph in "The wrist's start surface, and what an arrival does to it" (:191).
4. [ ] `docs/watch_session_sync.md`: the MODIFIED row 3 — the Structure table's first row (:21) names `onSessionStarted` and the adopt-then-link; cite `test/watch_session_import_test.dart` (S-8963, S-8964, S-8971).
5. [ ] `docs/watch-app-setup-and-qa.md`: the MODIFIED row 7 — the second-start sentence (:398–:400) names the Planned button's tap; cite the wrist start tests (S-8967).
6. [ ] Every row proves itself: each doc sentence cites the test or source guard that pins it, and any sentence whose test does not exist at write time is reported as a gap in the plan's evidence file, not left silent.

**Done criteria (P4)**: each Old marker greps true in its doc before the edit; each doc stays under the 52 KB band; the
docs phase reports the marker list against the table above.

**Predicted files**: the five docs in the Docs delta table.

## Ordered QA steps (after all phases)

1. `flutter analyze` — compare the issue count with the run's baseline (the repo carries pre-existing info notices).
2. Targeted Dart selectors in one runner: `test/watch_reference_sync_test.dart test/watch_sync_request_handler_test.dart test/watch_sync_changed_only_test.dart test/watch_session_import_test.dart test/watch_session_adoption_bridge_test.dart test/sync_protocol_fixtures_test.dart`.
3. One `flutter test` full run (gateway `test` check), 900 s budget, only after step 2 is green; a red Mock group is fixed before its Hive sibling re-runs (a red Mock group can leave the Hive group hanging).
4. Swift: `swift test --filter WatchPlannedRecordsTests --filter WatchSessionStartPathsTests --filter WatchSessionEngineTests --filter WatchBridgeQueueTests --filter SyncProtocolFixturesTests` (gateway `swift-test`).
5. Marker audit: every Docs delta Old marker greps true before the docs edits, every New marker greps true after.

## Risks

- **The report can be lost.** The wrist's forwarder drops a refused frame without queueing (the `WatchEmitForwarder`
  contract), and the bridge queues only what its sink hands it. A wrist whose report never lands leaves the plan merely
  planned while the user is training its workout — the same failure mode a lost snapshot has always had. Owner-accepted
  (D-8967, best-effort link); the seam is chosen so the frame inherits the queue treatment of `session_lifecycle` (D-8970, S-8970).
- **Starting from a routine button, not the Planned button, leaves the plan planned.** D-8966 names this on purpose (no
  new frame for a generic start). Recorded in "Noticed not planned"; the owner knows.
- **The handler's tuple grows.** `_bundle` is a positional tuple record; adding `plans` touches every consumer of the
  type. `test/watch_sync_changed_only_test.dart` is the guard that the stamp rules did not move (D-8971).
- **Fixture timezones.** Every epoch value in every fixture and test in this plan is derived at run time from
  `DateTime(2026, 11, 5)` (Dart local; Swift from injected clock) — the seed's `1793854800000`-style values are
  machine-timezone-specific and are never hard-coded.
- **Widget-free change.** No Flutter UI is touched; the phone's calendar reads whatever `CalendarState` shows after
  `completePlannedSession`'s own `_loadMonth` reload.

## Noticed not planned

- The discard repair (nothing un-completes a plan when a session is discarded) — a follow-up unit, owner-stated.
- No `planned_done` or similar phone→watch frame: the wrist never learns a plan was completed; its list is only what
  `planned_down` last said.
- A phone-side schedule (pushing plans at midnight) is ruled out twice over: "Nothing here answers a request the wrist
  has not made" (`watch_surface.md:556`–`:558`) and D-8969's no-timer surface.
- The wrist's free start carries no modality (D-8961's `modality` is only a name source on the wrist) — recorded
  deviation, owner-approved.
- `docs/watch_session_capture.md` is unchanged (checked this run; `session_started` is not an inbox concern).
- The wrist's S-8969 `(owner)` simulator look is stood in for by the source guard test, per the seed's rule.

## Progress

| Phase | Items | State |
|---|---|---|
| P1a wire | 5 | done (crew-builder-watch 2026-11-06) — 2 schemas, 5 fixtures, `plannedStart` |
| P1b phone | 5 | done (crew-builder-app) — builder, send, route, link; S-8963/S-8964/S-8964b/S-8971/S-8972 |
| P2 wrist engine | 9 | done (crew-builder-watch) — records, store, paths, seam, durability |
| P3 surface | 6 | done (crew-builder-watch) — button, picker, source test |
| P4 docs | 6 | done (PROTOCOL.md run + docs keeper) — 9 Docs delta rows applied |
| F1 first-snapshot ladder | 3 | done (crew-builder-app run 20261107-114637 + lead, 2026-11-07) — D-8978; S-8980 (two tests), S-8981 |

Verification (lead, after the review fixes): `flutter analyze` 181 (baseline); `flutter test` +6784 ~2, all passed;
`swift test` 1221 tests, 0 failures; watch app target `xcodebuild` BUILD SUCCEEDED; marker lint `after` clean.
Review 1 findings: 1 Blocker (the D-8972 conformance gate) fixed with a guard proven by mutation; minors 2 and 3 fixed
(free-plan wording; corrupt-row recovery with both arms proven).

## Assumption Log

- The owner's "complete it as it starts on the watch" is implemented as the phone opening the wrist session's row when
  the report names none and linking the plan to it (D-8977); the wrist's first snapshot then lands the ladder in that
  effort-less row (D-8978; this line first said "add-only", which was only true from the second snapshot on).
- D-8978 also gives the report-opened row the routine's Focus (`modality`), a one-line parity with `_adopt` the owner did not
  ask for by name; it keeps a wrist routine start reading like a phone one in history (plan 122 D-12201c).
- `test/watch_session_adoption_bridge_test.dart`'s report fixture gained the payload `sessionId`/`at` the schema requires
  (the envelope's top-level `sessionId` alone is not what the schema reads).

## Feedback

- *(empty)*
