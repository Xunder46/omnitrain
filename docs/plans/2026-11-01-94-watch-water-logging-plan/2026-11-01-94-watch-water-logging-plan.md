# Feature: 94 — water on the watch (step 2 of the wrist Home split). This file: series index + PR 94a (wire contract and phone)

> Status: Iteration 1 planned 2026-11-01 — DRAFT decisions D-1..D-21 binding; Open questions Q1, Q2 carry recommended defaults that the phases are built on (vetoable before Phase 3).
> Next handoff: @code-reviewer — Phases 1-4 Complete (PR 94a built)
> Binding conventions: docs/global_conventions.md; .github/copilot/pr-scope-budget.md; watch/sync_protocol/PROTOCOL.md; docs/state_management/watch_reference_data.md; docs/state_management/nutrition_state.md; docs/db_integration.md
> Branch: the one checked out (`claude_develop`); never create or switch branches; never commit, stash, reset or check out (the governor owns git).
> Shared tree (2026-11-01): another session holds uncommitted files — `docs/session_summary.md`, `docs/state_management/workout_state.md`, `lib/features/exercise/exercise_editor_screen.dart`, `lib/features/session/session_summary_screen.dart`, `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/state/workout/session_core_entry.dart`, `lib/state/workout/workout_state.dart`, `test/interaction_flow_test.dart`, `test/muscle_editor_screen_test.dart`, `test/pr8_exercise_library_test.dart`, `test/screen_widget_test.dart`, `test/watch_live_refresh_screen_test.dart`, `test/watch_routine_adoption_test.dart`, `test/watch_session_merge_test.dart`, `test/session_summary_planned_link_test.dart`, `scripts/*.sh`. Step 1 of this series (wrist Home) is uncommitted too: `watch/watchos/Sources/WatchSessionEngine/WatchStartView.swift`, `WatchNutritionWiringSourceTests.swift`, `docs/state_management/watch_surface_wrist.md`, `ios/OmniTrain Watch App/ContentView.swift`. None of these is a predicted file: do not edit, format or revert them. Re-read a file before quoting a line number: the tree moves.

## Series 94 (index)

Owner request (2026-11-01): on the watch's Nutrition screen (the Foods I Eat list, shown whether or not the list is empty) a water bar is pinned at the bottom — minus on the left, the glass count in the middle, plus on the right, like the phone's `WaterTrackerControl` (`lib/features/nutrition/widgets/water_tracker_control.dart`). One glass = `kWaterGlassMl` (250 ml, `lib/core/constants/water_constants.dart`). Owner decisions already made, not re-asked: the bar is on the list only (not on `WatchFoodPortionView`); it shows with an empty foods list; no access to food or water from inside a workout (Home only); before the first sync the watch shows 0 until the phone says otherwise.

Budget (`.github/copilot/pr-scope-budget.md` §1): the whole feature is 7 phases on two tracks (phone `lib/`, wrist `watch/watchos/`) plus the sync contract, about 35 scenarios. Hard limit "more than 5 phases" is hit, so it ships as two PRs, the 87a/87b precedent:

| PR | Order | Scope | Depends on | Track | Status |
|---|---|---|---|---|---|
| 94a | 1 | The wire (`water_down`, the `water_glass` tap event, the `wantsWater` request key) in schemas, fixtures, both validators, PROTOCOL.md; the phone stores taps idempotently, applies them to its day's water, sends receipts and the count. Nothing visible on the watch yet; the phone's Nutrition screen shows wrist taps live once a wrist sends them. Safe alone: a wrist that does not know `water_down` ignores it (`WatchSyncOrchestrator.receive` default returns false). | none | contract + phone | built, Phases 1-4 Complete; awaiting review (this file) |
| 94b | 2 | The wrist: `water_glass` taps stored and sent as observations (always under the day's nutrition id, never a workout's), the held `water_down` (stored, newest wins, pruned), the displayed count (D-7), the pinned bar on `WatchNutritionView`'s list (not the portion screen), `wantsWater: true` on every routines request, `WatchSyncProgressCopy.replyTypes`, the "waiting for your phone" line's treatment of unsent taps, haptics and VoiceOver, QA steps, docs. Planned on its turn against the code as it is then. | 94a | watch (Swift) | planned: `docs/plans/2026-11-01-95-watch-water-bar-plan/` |
| 94c | 3 | Follow-up: bar redraw cost, old confirmed taps pruned at launch, test fixes F8/F9. | 94b | watch | planned: `docs/plans/2026-11-01-96-watch-water-follow-up-plan/` |

Shared decisions both PRs bind to: D-2 (tap event), D-3 (apply rule), D-6 (frame), D-7 (how the wrist counts), D-8/D-9 (when the count is sent). 94b may add decisions but never edits these; a change is a superseding entry.

**PR 94b handoff (facts from 94a).** The phone sends `water_down` only to a request carrying `wantsWater: true` (contract row `routinesWater`; the Swift request builder must add it, pinned against that row) and after every tap message, duplicates included (A-10) — so the wrist sees repeats and keeps the newest by `generatedAt` (D-7). In a routines answer it arrives after the last `exercises_down` and before `bests_down`, and is absent when the phone's water read failed or the radio dropped it (no retry): the wrist must not wait for it. Both validators already accept `water_down` and `water_glass`; only Swift `WatchObservationKind.all` lacks `water_glass`.
94b decides (review suggestion): a tap past the D-3 cap is receipted but never in `appliedTapIds`, so D-7's fold keeps counting it; leave receipted taps out of the fold, or accept the drift.

## Overview (PR 94a)

The phone is the owner of the day's water (`app_water_log`, milliliters). The wrist will send each tap as a one-glass change, never a total, so taps made on both devices while apart all count. The phone applies each tap exactly once — keyed by the tap's id, kept in the same storage row as the volume — and tells the wrist the day's glass count plus which of the wrist's taps that count already includes. With that list the wrist can show an exact count: the phone's number plus its own taps the phone has not counted yet.

| What happens | Phone after 94a |
|---|---|
| A wrist tap "add" arrives | +250 ml on the day the glass was tapped; the open Nutrition screen updates; receipt + `water_down` back |
| The same tap arrives again (lost receipt, relaunch) | nothing changes; receipt + `water_down` again |
| A "remove" at 0 ml | stays 0; the tap is recorded as applied |
| Phone holds 600 ml (2 glasses) | add → 850 ml (3); remove → 350 ml (1); same math as the phone's own buttons |
| Wrist routines request with `wantsWater: true` | one `water_down` for the phone's today, every time |
| Phone user taps + / − | unchanged; the wrist learns it at its next sync (Q1) |

## Resolved Decisions (Ledger)

Plan-local IDs; cite as "plan 94 D-n".

- **D-1 Split.** 94a = contract + phone (this file); 94b = wrist. The Swift validator is the only `watch/watchos` source 94a touches (it is the contract's Swift half, as in 87a); `WatchObservationKind.all` (Swift) and every wrist view stay unchanged in 94a.
- **D-2 The tap on the wire.** A wrist tap is an `observations_up` event of the new kind `water_glass`, carrying exactly `entryId`, `eventId` (equal to `entryId`), `kind`, `loggedAt` (UTC instant of the tap) and the new field `glassChange` ∈ `{"add", "remove"}` — a string enum, not a signed number (NSNumber bridges 1 and `true` alike on the wrist). The envelope's `sessionId` is always `WatchNutritionSession.idFor(loggedAt)` (`nutrition-YYYY-MM-DD`), even while a workout runs (94b emits it so), so no session snapshot, inbox or mirror ever holds a tap. Additive: no version change, no new rejection code.
- **D-3 The phone's apply rule.** For each `water_glass` event of a conformant message, in message order: dayMs = `OmniDateUtils.startOfDayMs(DateTime.parse(loggedAt).toLocal())` (the phone's local calendar day of the tap; Q2 default). If `entryId` is already in that day's ledger, or the ledger already holds `kWatchWaterTapsPerDay` (500) ids, nothing changes. Otherwise, in ONE storage write: volume' = add ? v + 250 : (v − 250 < 0 ? 0 : v − 250) — exactly `NutritionState.incrementWaterForDate` / `decrementWaterForDate`'s math — and `entryId` is appended to the ledger. A remove at 0 ml is applied (volume stays 0, a row with 0 ml exists, the id is recorded). Every `water_glass` `entryId` of a conformant message is acknowledged in a `receipt`, applied, duplicate or over the cap alike. A refused message (validator rejection) applies nothing, acknowledges nothing and sends no `water_down`.
- **D-4 The ledger lives in the water row.** `app_water_log` gains `applied_tap_ids` (JSON array of strings, default `[]`); the Hive `water_log` map gains key `applied_tap_ids` (List<String>); `WaterLogEntry` gains `appliedTapIds` (`List<String>`, default `const []`, `fromMap` reads an absent key as `[]`). A row written before 94a has no key and reads as `[]` — no migration (no existing users). `saveWaterVolumeForDate` MUST carry the existing `applied_tap_ids` through (today's Hive implementation rewrites the map without it, `hive_workout_repository.dart` ~l.2498-2522). Why one row: volume and ledger change in one `put`, so a crash can neither double-count nor lose a tap.
- **D-5 Repository API (both implementations, value-for-value).** `Future<bool> applyWaterTap({required int dateMs, required String tapId, required int deltaMl})` — D-3's write; returns true when it wrote, false for a duplicate id or a full ledger; `deltaMl` is `kWaterGlassMl` or `-kWaterGlassMl` and the clamp is the repository's existing `< 0 → 0`. `Future<List<String>> getAppliedWaterTapIds(int dateMs)` — the day's ledger in append order, `[]` when no row. Hive: read the row with the synchronous `_waterLogBox.get` and issue the `put` with no `await` between them.
- **D-6 The `water_down` frame (phone → watch).** Closed payload: `generatedAt` (envelope timestamp), `day` (the phone's local calendar date at `generatedAt`, zero-padded `YYYY-MM-DD`, pattern `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`), `glasses` (integer ≥ 0 = `waterGlassesFor(volumeMl)` = `volumeMl ~/ kWaterGlassMl`, the phone's own displayed count), `appliedTapIds` (array, `maxItems` 500, items non-empty strings, unique, the day's ledger in append order). No `sessionId`. `origin: "phone"`. `messageId` = `msg-water-<generatedAtMs>-<glasses>-<appliedTapIds.length>`. One frame, never batched; not queueable (absent from `WatchConnectivityTransport._queueable`).
- **D-7 How the wrist counts (binding on 94b; written now so the wire cannot drift).** The wrist holds the newest `water_down` by `generatedAt` (a tie goes to the copy received later; an older copy arriving late replaces nothing — the `preferences_down` rule). Base = the held frame's `glasses` when its `day` equals the wrist's local calendar date, else 0 (no frame, or a frame for another day). Displayed count = fold, in `loggedAt` order, over the wrist's own `water_glass` taps whose `loggedAt` falls on the wrist's local today and whose `entryId` is not in the held frame's `appliedTapIds`: add → n + 1, remove → max(0, n − 1), starting from Base. Minus is disabled while the displayed count is 0, so the wrist never emits a remove at 0 itself (the phone still tolerates one, D-3). Both devices are assumed to share one time zone (paired devices); a mismatch is out of scope.
- **D-8 When the phone sends `water_down`.** (a) In answer to a routines request whose frame carries `wantsWater: true`: on every such request, whatever `since`, the bundle stamp, the exercise-list version or the bests skip (87c) decide; position: after `_sendExerciseList` and before `_sendBests`, so `bests_down` stays the last frame (87a D-11). (b) From the water bridge, after it handled at least one `water_glass` event of a conformant message: after the receipt. Built from storage read at send time for the phone's today (by the sender's clock). Never sent on the phone's own taps (Q1 default). A send the radio did not carry is not retried; a read that throws sends no frame; neither changes `_sendRoutines`' return value or the frames after it.
- **D-9 The request key.** The wrist's routines request MAY carry `wantsWater: true`; omitted, never `false` or null, otherwise. The phone reads it as asked only when the value is the boolean `true` (a string, a number, `false`, null, absent = not asked — the `holdsBests` rule, `watch_transport.dart` ~l.149). Contract row `transportRequests.routinesWater = {"request": "routines", "wantsWater": true}` in `watch/contract/watch_start_paths_contract.json`; existing rows stay byte-identical. The Dart twin (`lib/watch/start/watch_sync_orchestrator.dart`) never sends it. Why a key and not "always": every frame-sequence assertion of 87a/87c (`test/watch_sync_request_handler_test.dart` l.542-1167, `test/watch_sync_changed_only_test.dart` l.316, `test/watch_sync_idle_reads_test.dart` l.218, `test/watch_transport_test.dart` l.681) stays valid unedited.
- **D-10 Validator rules (Dart and Swift, identical messages).** Schema: `water_down.schema.json` per D-6; `envelope.schema.json` `type` enum gains `water_down`; `$defs.entry.properties.kind.enum` gains `water_glass`; `$defs.entry.properties` gains `glassChange: {"enum": ["add", "remove"], "description": …}`; `observations_up.schema.json`'s `oneOf` gains `{"required": ["kind", "glassChange"], "properties": {"kind": {"const": "water_glass"}}}`. Semantic: `water_glass` joins the slotless kinds (no `exerciseId`/`sessionExerciseId` needed); `glassChange` joins the capture-field table as carried only by `water_glass` (message `glassChange is carried only by water_glass entries; <id> is a <kind> entry`, the existing template); `water_down` refuses a repeated `appliedTapIds` entry with `semantic_violation` at `$.payload.appliedTapIds`, message `the same tap id appears twice: <id>` (the 87a duplicate wording). No new rejection code.
- **D-11 Constants: one owner each.** In `lib/core/constants/water_constants.dart`: `int waterGlassesFor(int volumeMl) => volumeMl ~/ kWaterGlassMl;` and `const int kWatchWaterTapsPerDay = 500;`. `NutritionState.waterTodayGlasses` and the `water_down` builder both call `waterGlassesFor`; no other file writes `~/ kWaterGlassMl` or the literal 250 for water (S-94a-24 grep).
- **D-12 `NutritionState`.** New `Future<bool> applyWatchWaterTap({required int dateMs, required String tapId, required bool add})` → `applyWaterTap(deltaMl: add ? kWaterGlassMl : -kWaterGlassMl)`. The state remembers the day its water cache belongs to (`loadWaterForDate(dateMs)` sets it; `rolloverToDate` goes through it). On a true return for that day it re-reads the volume, updates the cache and notifies once; for another day, or before any load, it neither touches the cache nor notifies. All water writes — `incrementWaterForDate`, `decrementWaterForDate`, `applyWatchWaterTap` — run one at a time through a single internal chain, so no read-modify-write interleaves another; a write that throws does not block later ones. Existing public signatures and their behaviour stay unchanged.
- **D-13 Phone receiving path.** New `WatchWaterLogBridge` (`lib/state/watch/watch_water_log_bridge.dart`): constructor `nutrition`, `repository`, optional `validator`, `transport`, `clock`, `idFactory` (the `WatchNutritionLogBridge` shape); `receive(envelope)` → validates with `SyncProtocolValidator.evaluateOrAccept`, applies D-3 via `NutritionState.applyWatchWaterTap`, sends the receipt (`WatchNutritionLogBridge.receiptFor` reused, not copied), then D-8(b). `WatchIncomingRouter` gains an optional `water:` parameter (null = water events ignored, so the ~20 existing constructions, several in the other session's files, compile unedited) and `WatchIncomingReceipt` gains `water` (default `ignored`). `watch_sync_wiring.dart` constructs the bridge beside `WatchNutritionLogBridge` (~l.276). A message carrying food and water gets two receipts, each naming its own kind's ids. The inbox (`_requiredFields` has no `water_glass`, `watch_session_inbox.dart` ~l.195) and the mirror (session id `nutrition-…` is never held) ignore taps without change.
- **D-14 The Dart twin.** `lib/watch/session/watch_records.dart` `WatchObservationKind` gains `static const String waterGlass = 'water_glass';` for the phone bridge to read, NOT added to `all` (the twin emits no taps — the precedent of `effort_rating` and `session_end`, absent from the Dart `all`); `test/watch_nutrition_quick_log_test.dart` "the kinds the wrist can emit are a closed set" stays green unedited.
- **D-15 Docs.** Byte sizes measured 2026-11-01 against the 52,429 B warning band: `docs/data_models.md` 46,764; `docs/db_integration.md` 40,030; `docs/state_management/nutrition_state.md` 30,074; `docs/nutrition.md` 37,344; `docs/state_management/watch_reference_data.md` 19,748. Each edit adds ≤ 1,500 B. NOT edited: `docs/state_management/watch_surface.md` (50,743 B), `docs/state_management/watch_surface_wrist.md` (52,259 B, in the band, and dirty from step 1). `watch/sync_protocol/PROTOCOL.md` is outside `docs/` (no ceiling).
- **D-16 Test style.** Plain `test()` only; no `testWidgets` in 94a. Repository scenarios run on both harnesses of `test/helpers/repository_harness.dart` (Mock and Hive, `restart()` for relaunch). Clocks are local wall times converted to UTC (`DateTime(2026, 11, 1, 12).toUtc()`), and expected `day` strings and `dateMs` are derived the same way, never hard-coded to a time zone.
- **D-17 Names pinned** so tests and docs agree: `water_down`, `water_glass`, `glassChange`, `wantsWater`, `routinesWater`, `applyWaterTap`, `getAppliedWaterTapIds`, `applyWatchWaterTap`, `waterGlassesFor`, `kWatchWaterTapsPerDay`, `WatchWaterLogBridge`, `WatchReferenceSync.buildWaterDown` (pure: `volumeMl`, `appliedTapIds`, `localDay` (DateTime), `generatedAt`), `WatchReferenceSync.readWaterDown({repository, generatedAt})` (reads today's row, then `buildWaterDown`), `WatchTransportRequest.wantsWaterOf` and `routinesFrame(wantsWater:)`.
- **D-18 The phone trusts the wrist's send-side validation** (governor, review warning; owner delegated technical calls). Production wiring injects no validator into `WatchWaterLogBridge`, as for every other phone-side receiver; AC-6/S-94a-17 hold for a validating receiver. Validating all receivers in production is a separate plan.
- **D-19** (was A-3) Wrist taps apply through `applyWaterTap` (one atomic write of volume + ledger), not `incrementWaterForDate`/`decrementWaterForDate`; same math (S-94a-3).
- **D-20** (was A-9) `loadWaterForDate` queues on the D-12 chain and records the cache day after its read.
- **D-21** (was A-10) Bridge outcome `applied` = the message carried ≥ 1 readable tap (new, duplicate or capped); it triggers D-8(b).

## Feature Invariants (this feature only)

- **I-1** A wrist tap changes the phone's stored water at most once, across redelivery, phone relaunch and the phone's own writes (S-94a-5, S-94a-6, S-94a-14).
- **I-2** `MockWorkoutRepository` and `HiveWorkoutRepository` give the same volume and ledger for the same calls (every storage scenario runs on both).
- **I-3** A wrist tap and a phone tap give the same volume from the same start (S-94a-3 parity).
- **I-4** Past days are written only by a tap logged on that day; a frame always describes the phone's today (S-94a-16).
- **I-5** Taps never enter workout history: the inbox stages nothing and the mirror applies nothing for them (S-94a-18).

## Requirements

- R-1 The wire carries taps up and the count down, closed and validated on both stacks (D-2, D-6, D-10).
- R-2 The phone applies each tap once, by D-3's math, and acknowledges it (D-3..D-5, D-13).
- R-3 The phone's Nutrition screen reflects wrist taps for today without a reload (D-12).
- R-4 The phone answers a wrist that asks with today's count on every sync and after every tap message (D-8, D-9).

## Acceptance Criteria

- AC-1 Both validators accept the valid fixtures and refuse each invalid one with its code → S-94a-1, S-94a-2.
- AC-2 Add/remove math, minus at 0, non-multiples of 250 and phone parity → S-94a-3, S-94a-4, S-94a-20.
- AC-3 Duplicate delivery and relaunch change nothing → S-94a-5, S-94a-14.
- AC-4 Taps from both devices made apart all count → S-94a-15.
- AC-5 A late tap counts on the day it was made → S-94a-8, S-94a-16.
- AC-6 Unknown or extra fields refuse the whole message → S-94a-17.
- AC-7 The count reaches a wrist that asks, independent of foods, routines, `since` and bests → S-94a-21, S-94a-22, S-94a-23, S-94a-24.

## Existing-Functionality Impact

| Touched surface | Readers (grep that found them) | Effect | Guarded by |
|---|---|---|---|
| `envelope.schema.json` `type` enum, `$defs.entry` kind enum + new field | both validators; manifest-driven suites `test/sync_protocol_fixtures_test.dart` l.148-196, `SyncProtocolFixturesTests.swift`; `grep -rn "\['enum'\]" test` → only `rest_is_count_up_contract_test.dart` l.188 (timer kinds, unaffected) | additive values; `session_snapshot` entries share `$defs.entry`, so a `water_glass` entry is shape-valid there too — no sender produces one (D-2) and the inbox ignores it | S-94a-1, S-94a-2, S-94a-18 |
| `messageTypes` (Dart l.106, Swift l.50) | `test/sync_protocol_fixtures_test.dart` l.170 requires a schema + valid fixture per type | schema and fixture land in Phase 1 | S-94a-1 |
| `_slotlessKinds` / `_captureFieldKinds` (Dart l.125/l.135; Swift l.69/l.86) | snapshot identity rule and capture rules of `observations_up` and `session_snapshot` | additive entries | S-94a-2 |
| `WatchObservationKind` Dart (`lib/watch/session/watch_records.dart` ~l.60-79) | `watch_nutrition_log_bridge.dart` l.204; closed-set test `test/watch_nutrition_quick_log_test.dart` ~l.1524 | constant added outside `all` (D-14) | closed-set test unedited |
| `WatchObservationKind.all` Swift | `WatchNutritionQuickLogTests.swift` ~l.664 | not touched in 94a (D-1) | — |
| `app_water_log` / `WaterLogEntry` / Hive `water_log` | `grep -rn "water_log\|WaterLogEntry\|getWaterVolumeForDate\|saveWaterVolumeForDate" lib test scripts` → the two repositories, `workout_repository.dart`, `nutrition_state.dart`, `scripts/sqlite_schema.sql`, `test/state_test.dart` (group "daily water log" ~l.4335), `test/nutrition_test.dart` (~l.513-600) | new column/key; `saveWaterVolumeForDate` preserves it; reads unchanged | S-94a-6, S-94a-9; both test files green unedited |
| `WorkoutRepository` (two new abstract methods) | `grep -rn "implements WorkoutRepository" lib test` → only Hive (l.40) and Mock (l.49); every test fake `extends MockWorkoutRepository` and inherits | non-breaking | S-94a-3..S-94a-9 |
| `NutritionState` water methods | `grep -rn "incrementWaterForDate\|decrementWaterForDate\|waterTodayGlasses\|loadWaterForToday\|rolloverToDate" lib` → `calorie_ring_card.dart` l.305-312, `nutrition_screen.dart` l.46/66/96, `home_screen.dart` l.293; tests `state_test.dart` (61 refs), `nutrition_test.dart` | signatures and results unchanged; writes serialized (D-12) | S-94a-10..S-94a-12; those suites green unedited |
| `WatchIncomingRouter` / `WatchIncomingReceipt` | `grep -rn "WatchIncomingRouter(" lib test` → `watch_sync_wiring.dart`, `live_session_mirror_debug_main.dart`, 19 test files (several dirty, other session); `WatchIncomingReceipt(` built only inside the router | optional parameter + defaulted field; no construction site edited except wiring | S-94a-18, S-94a-19 |
| `WatchSyncRequestHandler._sendRoutines` frame stream (l.173-244) | 87a/87c suites listed in D-9; `rest_ping_contract_test.dart` l.314, `watch_accent_contract_test.dart` l.148/162 | `water_down` only when `wantsWater` is passed; no existing call passes it | S-94a-21, S-94a-22 |
| `WatchTransportRequest.routinesFrame` (Dart l.106) + contract `transportRequests` | exact-equality pins S-102/S-3856 Dart (`watch_transport_test.dart` l.1589-1660), Swift `WatchConnectivityBridgeTests.swift` l.276-475 read rows by name | key added only when true; new row only | S-94a-26 |
| wiring `onIncoming` (`watch_sync_wiring.dart` ~l.322-335) | single production `handle` call | passes `wantsWater: WatchTransportRequest.wantsWaterOf(frame)` | S-94a-26 |
| Swift wrist `receive` (`WatchSyncOrchestrator.swift` l.173-205) | `default: return false` | ignores `water_down` until 94b | S-94a-1 (fixture exists; no Swift source change beyond the validator) |
| PROTOCOL.md spec tests (`test/sync_protocol_fixtures_test.dart` ~l.820-860) | every referenced path must exist; every code documented | new rows reference only real paths, no new code | Phase 1 Done Criteria |
| Standing invariants | hive import sweep (AGENTS.md); `ui_standards_contract_test` + `docs_indexing_contract_test`; rest count-up rule (untouched) | — | every Done Criteria |

## UI Standards Impact

None in 94a: no Flutter screen or widget changes (`WaterTrackerControl` and `CalorieRingCard` are read-only dependents; they rebuild from `NutritionState`'s notify as today). The wrist's bar is 94b and is SwiftUI, outside `docs/design_system.md`'s Flutter pieces.

## Scenarios

Shared fixture **W** (phone): `D` = `DateTime(2026, 11, 1)` local, `dMs` = its `millisecondsSinceEpoch`; `P` = `DateTime(2026, 10, 31)` local; `N` = `DateTime(2026, 11, 2)` local. Clock `DateTime(2026, 11, 1, 12).toUtc()` unless stated. Tap ids are literal strings (`w-1`…). A tap event `tap(id, change, local)` = `{entryId: id, eventId: id, kind: "water_glass", loggedAt: utcIso(local.toUtc()), glassChange: change}` inside `observations_up` with `sessionId: "nutrition-2026-11-01"`, `origin: "watch"`, one event per message unless stated. Storage scenarios run on Mock AND Hive (`repository_harness.dart`).

### S-94a-1: the new shapes conform on both stacks
- Fixture: `fixtures/valid/water_down.json` (`day "2026-11-01"`, `glasses 3`, `appliedTapIds ["w-1","w-2"]`); `fixtures/valid/water_down_empty_day.json` (`glasses 0`, `appliedTapIds []`); `fixtures/valid/observations_up_water.json` (two events: `w-1 add`, `w-2 remove`, session `nutrition-2026-11-01`).
- Trigger: both manifest-driven suites. Expected outcome: all three conform in Dart and Swift. Edge case of: none.

### S-94a-2: refusals, each with its code
- Fixture (invalid, each one defect): `water_down_unknown_field.json` (payload `volumeMl: 750`) → `unexpected_field`; `water_down_negative_glasses.json` (`glasses: -1`) → `constraint_violation`; `water_down_fractional_glasses.json` (`2.5`) → `invalid_type`; `water_down_bad_day.json` (`"1/11/2026"`) → `constraint_violation`; `water_down_duplicate_tap.json` (`["w-1","w-1"]`) → `semantic_violation` "the same tap id appears twice: w-1"; `water_down_watch_origin.json` → `invalid_const_value`; `water_down_over_500.json` (501 ids) → `constraint_violation`; `observations_up_water_missing_change.json` → `missing_required_field` "glassChange"; `observations_up_water_unknown_change.json` (`"double"`) → `invalid_enum_value`; `observations_up_water_extra_field.json` (event `volumeMl: 250`) → `unexpected_field`; `observations_up_glass_change_on_set.json` (a `set` event with `glassChange: "add"`) → `semantic_violation` "glassChange is carried only by water_glass entries".
- Trigger: both suites. Expected outcome: each refused with that code and a reason containing the stated text, on both stacks. Edge case of: S-94a-1.

### S-94a-3: add and remove math, including volumes that are not whole glasses
- Fixture: four fresh days on each harness at 0, 100, 600 and 600 ml (via `saveWaterVolumeForDate`).
- Trigger: `applyWaterTap` 0+add (`a1`), 100−remove (`a2`), 600+add (`a3`), 600−remove (`a4`).
- Expected outcome: 250 (1 glass); 0 (100 − 250 < 0 → 0; 0 glasses); 850 (850 ~/ 250 = 3); 350 (1). Each returns true. Parity: a `NutritionState` over a third repo seeded alike gives the same four volumes through `incrementWaterForDate`/`decrementWaterForDate`. Edge case of: none.

### S-94a-4: a remove at 0 is recorded
- Fixture: day `D` with no row. Trigger: `applyWaterTap(D, "w-0", -250)`, then again.
- Expected outcome: first true, volume 0, a row exists, ledger `["w-0"]`; second false, unchanged. Edge case of: S-94a-3.

### S-94a-5: duplicate delivery, before and after a relaunch
- Fixture: `D` at 500 ml. Trigger: `applyWaterTap(D, "w-1", +250)` twice; `restart()`; once more.
- Expected outcome: 750 after the first; false and 750 after the second; after restart false, 750, ledger `["w-1"]`. Edge case of: none.

### S-94a-6: the phone's own write keeps the ledger
- Fixture: `D`: `applyWaterTap(D, "w-1", +250)` → 250. Trigger: `saveWaterVolumeForDate(D, 500)`, then `applyWaterTap(D, "w-1", +250)`.
- Expected outcome: volume 500, ledger `["w-1"]`, the replay returns false and leaves 500. Red today on Hive (save rewrites the map). Edge case of: S-94a-5.

### S-94a-7: the per-day cap
- Fixture: `D` with 500 add taps `t-000`..`t-499` applied (volume 500 × 250 = 125,000 ml). Trigger: `applyWaterTap(D, "t-500", +250)`.
- Expected outcome: false; volume 125,000; ledger length 500. Edge case of: S-94a-5.

### S-94a-8: days are independent; an old row has no ledger
- Fixture: `P` at 250 ml; `D` row written raw on Hive without `applied_tap_ids` (`volume_ml 750`), and the same through `saveWaterVolumeForDate` on Mock. Trigger: `applyWaterTap(P, "w-p", +250)`; `getAppliedWaterTapIds(D)`; `applyWaterTap(D, "w-d", +250)`.
- Expected outcome: `P` 500, ledger `["w-p"]`; `D` ledger `[]` then `["w-d"]` with 1000 ml; `getAppliedWaterTapIds(D)` never contains `w-p`. Edge case of: none.

### S-94a-9: model and SQL contract agree
- Fixture: `WaterLogEntry(appliedTapIds: ["w-1"])` and one built by `fromMap` of a map without `applied_tap_ids`. Trigger: `test/db_seed_test.dart` schema database.
- Expected outcome: `toMap().keys` ⊆ `app_water_log` columns; the column exists with default `'[]'`; `fromMap` without the key gives `[]`. Edge case of: none.

### S-94a-10: a wrist tap for today updates the open screen's state
- Fixture: Mock, `D` at 500; `NutritionState.loadWaterForDate(dMs)`; a listener counter.
- Trigger: `applyWatchWaterTap(dateMs: dMs, tapId: "w-1", add: true)`.
- Expected outcome: true; `waterTodayMl` 750; `waterTodayGlasses` 3; exactly one notify. Edge case of: none.

### S-94a-11: a tap for another day leaves the cache alone
- Fixture: as S-94a-10. Trigger: `applyWatchWaterTap(dateMs: P, tapId: "w-p", add: true)`; separately a fresh state never loaded + a tap for `D`.
- Expected outcome: cache 500, no notify, repository `P` 250; the never-loaded state stays at 0 with no notify while the repository holds `D` 750. Edge case of: S-94a-10.

### S-94a-12: a phone tap and a wrist tap at the same moment both count
- Fixture: Mock, `D` at 0, state loaded for `D`. Trigger: `Future.wait([incrementWaterForDate(dMs), applyWatchWaterTap(dateMs: dMs, tapId: "w-1", add: true)])`.
- Expected outcome: repository 500, cache 500. Mutation: without the write chain the increment resumes on its stale read and writes 250 — the test must fail then. Edge case of: S-94a-10.

### S-94a-13: the bridge applies, acknowledges, then sends the count
- Fixture: Mock, `D` at 500; `FoodLibraryState` empty; recording transport; validator `loadProtocolValidator()`. Trigger: `receive(tap("w-1", "add", D 09:00))`.
- Expected outcome: `D` 750; sent frames in order: `receipt` with `entryIds ["w-1"]`, then `water_down` with `day "2026-11-01"`, `glasses 3`, `appliedTapIds ["w-1"]`; both pass the validator. Edge case of: none.

### S-94a-14: the same message twice
- Fixture: S-94a-13 after its first receive. Trigger: the identical envelope again.
- Expected outcome: `D` stays 750; a second receipt naming `w-1`; a second `water_down` with glasses 3 and `["w-1"]`. Edge case of: S-94a-5.

### S-94a-15: both devices tapped while apart
- Fixture: Mock, `D` at 500 (2 glasses); state loaded; phone tap `incrementWaterForDate(dMs)` → 750 (the phone's own +1 while apart). Trigger: two messages `tap("w-2", "add", D 10:00)`, `tap("w-3", "add", D 10:05)`.
- Expected outcome: 500 + 250 + 250 + 250 = 1250 ml; `waterTodayGlasses` 5; the last `water_down` has glasses 5 and `["w-2","w-3"]`. Nothing lost. Edge case of: none.

### S-94a-16: a glass tapped before midnight, delivered after
- Fixture: `D` at 500, `N` at 0; state loaded for `N`; clock `DateTime(2026, 11, 2, 0, 0, 30).toUtc()`. Trigger: `tap("w-4", "add", DateTime(2026, 11, 1, 23, 59, 30))`.
- Expected outcome (Q2 default): `D` 750; `N` 0; cache unchanged, no notify; `water_down` has `day "2026-11-02"`, glasses 0, `appliedTapIds []`. Edge case of: S-94a-11.

### S-94a-17: unknown or extra fields refuse the whole message
- Fixture: `D` at 500; validator wired. Trigger: three envelopes — event with `volumeMl: 250`; event `glassChange: "double"`; payload with an extra key `note`.
- Expected outcome: each `refused`; `D` 500; no receipt; no `water_down`; ledger `[]`. Edge case of: S-94a-2.

### S-94a-18: taps never touch workout history
- Fixture: the router with inbox, mirror (no session), nutrition bridge and water bridge over Mock. Trigger: `tap("w-5", "add", D 09:00)`; then the same through a router built WITHOUT `water:`.
- Expected outcome: first — inbox `ignored`, session `ignored`, nutrition `ignored`, water `applied`, no inbox row staged (`getWatchInboxEntries…` empty); second — all `ignored`, `D` unchanged, no exception. Edge case of: none.

### S-94a-19: food and water in one message
- Fixture: library holding `food-oat` (reference 100 g); one `observations_up` with a `nutrition_quick_log` (`f-1`, `food-oat`, 1 serving) and `tap("w-6","add")`. Trigger: router receive.
- Expected outcome: one consumed-food row; `D` +250; two receipts, `["f-1"]` and `["w-6"]`; one `water_down`. Edge case of: S-94a-13.

### S-94a-20: minus at 0 and a non-whole volume through the bridge
- Fixture: (a) `D` no row; (b) `D` at 600. Trigger: (a) `tap("w-7","remove")`; (b) `tap("w-8","remove")`.
- Expected outcome: (a) 0 ml, receipt `["w-7"]`, frame glasses 0 `["w-7"]`; (b) 350 ml, frame glasses 1 (350 ~/ 250). Edge case of: S-94a-3, S-94a-4.

### S-94a-21: a wrist that asks gets the count on every request
- Fixture: handler over Mock with `D` at 600 and ledger `["w-1"]` (via `applyWaterTap` from 350); request 1 `handle('routines', wantsWater: true)`; request 2 with `since` = the stamp of request 1 and `holdsBests: true` after a delivered bests frame.
- Expected outcome: each request sends exactly one `water_down` (`day "2026-11-01"`, glasses 2, `["w-1"]`); in request 1 it comes after the last `exercises_down` and before `bests_down`; request 2 sends no bundle, no batches, no bests and the one `water_down`. Edge case of: none.

### S-94a-22: a wrist that does not ask gets none
- Fixture: as S-94a-21. Trigger: requests with the key absent, `false`, `"true"`, `1`, null (through `wantsWaterOf` on raw frames).
- Expected outcome: no `water_down` in any answer; every pre-94a test in `watch_sync_request_handler_test.dart`, `watch_sync_changed_only_test.dart`, `watch_sync_idle_reads_test.dart`, `watch_transport_test.dart` passes unedited. Edge case of: S-94a-21.

### S-94a-23: no foods, no routines, still a count
- Fixture: Mock with no foods, no routines, `D` at 0. Trigger: `handle('routines', wantsWater: true)`.
- Expected outcome: one `water_down` with glasses 0 and `[]`, validated by `loadProtocolValidator()`. Edge case of: S-94a-21.

### S-94a-24: the frame is the phone's own number
- Fixture: S-94a-21's repo. Trigger: the sent `water_down`. Expected outcome: `glasses == NutritionState.waterTodayGlasses` after `loadWaterForDate(dMs)` (2 for 600 ml); `messageId == "msg-water-<ms>-2-1"`; residue grep `grep -rn "~/ kWaterGlassMl" lib` returns only `water_constants.dart`. Edge case of: S-94a-21.

### S-94a-25: a lost or failed count never breaks the answer
- Fixture: (a) a transport answering `undelivered` for `water_down` only; (b) a Mock subclass whose `getWaterVolumeForDate` throws. Trigger: `handle('routines', wantsWater: true)`.
- Expected outcome: (a) `bests_down` still sent after it, return true; (b) no `water_down`, the rest of the answer identical to a request without the key, return true. Edge case of: S-94a-21.

### S-94a-26: the request key on the wire
- Fixture: contract row `routinesWater`. Trigger: `WatchTransportRequest.routinesFrame(wantsWater: true)`; `routinesFrame()`; a raw `{"request":"routines","wantsWater":true}` frame through the wiring's `onIncoming` (the `test/watch_session_projection_test.dart` radio harness).
- Expected outcome: the first equals `routinesWater` exactly; the second equals `routines` exactly; the wiring answer contains one `water_down`. Edge case of: S-94a-22.

Mutation checks (each must turn its test red): drop the ledger check (S-94a-5); rebuild the Hive map without the ledger in `saveWaterVolumeForDate` (S-94a-6); skip the cap (S-94a-7); update the cache for any day (S-94a-11); remove the write chain (S-94a-12); send `water_down` before the receipt (S-94a-13 order); read `wantsWater` as truthy (S-94a-22); put `water_down` after `bests_down` (S-94a-21).

## Iteration 1

### Phase 1: Contract (@developer)
1. [x] Create the schema — `watch/sync_protocol/schemas/messages/water_down.schema.json` (new) · D-6 shape; style template `bests_down.schema.json` (`generatedAt` as `$ref` to `envelope.schema.json#/$defs/timestamp`, `day` with the D-6 `pattern`, `glasses` `{type: integer, minimum: 0}`, `appliedTapIds` `{type: array, maxItems: 500, items: {type: string, minLength: 1}}`, `additionalProperties: false`).
2. [x] Extend the shared shapes — `watch/sync_protocol/schemas/envelope.schema.json` (`type` enum + `water_down`; `$defs.entry` kind enum + `water_glass`; `glassChange` property) and `schemas/messages/observations_up.schema.json` (`oneOf` arm, D-10; update its `description` to name `water_glass`).
3. [x] Fixtures — `watch/sync_protocol/fixtures/valid/` the three of S-94a-1; `fixtures/invalid/` the eleven of S-94a-2 (`water_down_over_500.json` generated mechanically, committed). Envelope constants copied from `bests_down.json` / `observations_up.json`.
4. [x] Register them — `watch/sync_protocol/fixtures/manifest.json` (valid + invalid registers, `scenario: "S-94a-1"`/`"S-94a-2"`, `expectedCode`, `expectedReasonContains` = a substring BOTH validators emit).
5. [x] Dart validator — `lib/core/sync_protocol/message_validator.dart` · `messageTypes` (l.106) + `'water_down'`; `_slotlessKinds` (l.125) + `'water_glass'`; `_captureFieldKinds` (l.135) + `'glassChange': ['water_glass']`; `_semanticRejections` (l.276) + `case 'water_down': return _waterRejections(payload);` (duplicate rule, D-10).
6. [x] Swift validator — `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift` · `messageTypes` (l.50), `slotlessKinds` (l.69), `captureFieldKinds` (l.86), semantic switch (l.198) + `waterRejections` beside `bestsRejections` (l.636); same messages as Dart.
7. [x] Protocol text — `watch/sync_protocol/PROTOCOL.md` · message-family table row for `water_down` beside `bests_down` (l.71); a normative paragraph (under "Idempotency and reconciliation") stating D-2, D-3's at-most-once rule and receipt, D-7's counting rule, D-8's sending rule and D-9's `wantsWater` key; a version-history row dated the day written, additive wording as the 2026-10-26 `bests_down` row, naming every new fixture path and `routinesWater`.
8. [x] Contract row — `watch/contract/watch_start_paths_contract.json` · `transportRequests` gains `"routinesWater": { "request": "routines", "wantsWater": true }` after `routinesBests`; extend the file's `description` sentence about `transportRequests` by one clause; existing rows byte-identical.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint` (issue count ≤ the baseline you record in the evidence file before editing; no new warning or error); `.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart test/watch_transport_test.dart test/watch_nutrition_quick_log_test.dart`; `.github/copilot/scripts/macos/gateway.sh swift-test`.
**Predicted Files**: the schema (new), `envelope.schema.json`, `observations_up.schema.json`, 3 valid + 11 invalid fixtures (new), `manifest.json`, `message_validator.dart`, `SyncProtocolValidator.swift`, `PROTOCOL.md`, `watch_start_paths_contract.json`, this plan, the evidence file.

### Phase 2: Storage — constants, model, SQL contract, both repositories (@dba)
1. [x] Constants — `lib/core/constants/water_constants.dart` · `waterGlassesFor`, `kWatchWaterTapsPerDay` (D-11).
2. [x] Model — `lib/data/models/models.dart` · `WaterLogEntry.appliedTapIds` (D-4: field, constructor default `const []`, `fromMap` tolerant of an absent key, `toMap` `applied_tap_ids`, `copyWith`; header comment).
3. [x] SQL contract — `scripts/sqlite_schema.sql` · `app_water_log` gains `applied_tap_ids TEXT NOT NULL DEFAULT '[]'`; comment block gains the `applyWaterTap` / `getAppliedWaterTapIds` notes and drops the stale "SqliteWorkoutRepository implementation notes" heading wording (no such class exists) in favour of "contract notes".
4. [x] Interface — `lib/data/repositories/workout_repository.dart` · the two D-5 methods beside `saveWaterVolumeForDate` (l.661), with the D-3/D-5 contract in their doc comments.
5. [x] Hive — `lib/data/repositories/hive_workout_repository.dart` · `applyWaterTap` + `getAppliedWaterTapIds` beside l.2490-2522; `saveWaterVolumeForDate` carries `applied_tap_ids` through (D-4).
6. [x] Mock — `lib/data/repositories/mock_workout_repository.dart` · a `Map<int, List<String>>` ledger beside `_waterVolumesByDate` (l.1630), both methods, cleared where `_waterVolumesByDate.clear()` is (l.1683).
7. [x] Tests — `test/water_tap_ledger_test.dart` (new): S-94a-3..S-94a-8 on both harnesses (`test/helpers/repository_harness.dart`); `test/db_seed_test.dart` new test S-94a-9 beside the D-131/D-132 key-subset test (~l.470).
8. [x] Docs — `docs/data_models.md` (WaterLogEntry, ~l.533) and `docs/db_integration.md` ("Daily Water Log" table, ~l.264): the field, the two methods, the at-most-once rule, the 500 cap. Sizes stay under the band (D-15).

**Done Criteria**: `gateway.sh lint` (vs baseline); `gateway.sh test test/water_tap_ledger_test.dart test/db_seed_test.dart test/state_test.dart test/nutrition_test.dart test/docs_indexing_contract_test.dart`; prove S-94a-6 red with the old `saveWaterVolumeForDate` (stash only your own hunk, never `git stash`: revert the hunk by hand, run, restore) and record red→green in the evidence file.
**Predicted Files**: `water_constants.dart`, `models.dart`, `sqlite_schema.sql`, `workout_repository.dart`, `hive_workout_repository.dart`, `mock_workout_repository.dart`, `test/water_tap_ledger_test.dart` (new), `test/db_seed_test.dart`, `docs/data_models.md`, `docs/db_integration.md`, this plan, the evidence file.

### Phase 3: Phone applies taps (@developer)
1. [x] State — `lib/state/nutrition_state.dart` · `waterTodayGlasses` via `waterGlassesFor`; the cache-day field; the single write chain around `incrementWaterForDate`, `decrementWaterForDate` and the new `applyWatchWaterTap` (D-12); update the "future `SqliteWorkoutRepository`" comments to `HiveWorkoutRepository` while there (stale names, ≤ 4 lines).
2. [x] Twin constant — `lib/watch/session/watch_records.dart` · `WatchObservationKind.waterGlass` outside `all` (D-14).
3. [x] Builders — `lib/core/utils/watch_reference_sync.dart` · `buildWaterDown` and `readWaterDown` beside `buildBestsDown` (l.599), D-6/D-17 (day string from the local `DateTime`, `phoneEnvelope`, `utcIso`).
4. [x] Bridge — `lib/state/watch/watch_water_log_bridge.dart` (new) · `WatchWaterLogBridge` + outcome enum `applied | ignored | refused` (D-13, D-3, D-8(b)); receipt via `WatchNutritionLogBridge.receiptFor`.
5. [x] Router — `lib/state/watch/watch_incoming_router.dart` · optional `water:`; `WatchIncomingReceipt.water` defaulting to ignored; call it after the nutrition bridge.
6. [x] Wiring — `lib/state/watch/watch_sync_wiring.dart` · construct `WatchWaterLogBridge(nutrition: nutritionState, repository: repository, transport: resolved, clock: clock)` and pass `water:` (~l.274-282).
7. [x] Tests — `test/watch_water_log_test.dart` (new, plain `test()`): S-94a-10..S-94a-20.
8. [x] Docs — `docs/state_management/nutrition_state.md` (Key Methods: `applyWatchWaterTap`, the cache-day and one-write-at-a-time rules) and `docs/nutrition.md` (one paragraph under State or Persistence: glasses tapped on the watch, D-3 in plain words, Q1/Q2 outcomes).

**Done Criteria**: `gateway.sh lint`; `gateway.sh test test/watch_water_log_test.dart test/watch_nutrition_quick_log_test.dart test/state_test.dart test/nutrition_test.dart test/watch_session_import_test.dart test/docs_indexing_contract_test.dart`; S-94a-12 shown red with the chain removed and S-94a-11 red with the day check removed (evidence file); invariant grep `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` empty.
**Predicted Files**: `nutrition_state.dart`, `watch_records.dart` (Dart twin), `watch_reference_sync.dart`, `watch_water_log_bridge.dart` (new), `watch_incoming_router.dart`, `watch_sync_wiring.dart`, `test/watch_water_log_test.dart` (new), `docs/state_management/nutrition_state.md`, `docs/nutrition.md`, this plan, the evidence file.

### Phase 4: Phone sends the count on request (@developer)
1. [x] Request key — `lib/core/platform/watch_transport.dart` · `routinesFrame(wantsWater:)` (key only when true) and `wantsWaterOf(frame)` (boolean `true` only) beside `holdsBestsOf` (l.149) (D-9).
2. [x] Handler — `lib/state/watch/watch_sync_request_handler.dart` · `handle(..., bool wantsWater = false)`; `_sendRoutines` calls `_sendWater()` between `_sendExerciseList` (l.237) and `_sendBests` (l.242) when asked; `_sendWater` = `readWaterDown(repository, generatedAt: _clock())` inside try/catch, send, ignore the result (D-8(a)); header comment names the frame.
3. [x] Wiring — `lib/state/watch/watch_sync_wiring.dart` · pass `wantsWater: WatchTransportRequest.wantsWaterOf(frame)` beside `holdsBests` (l.331).
4. [x] Handler tests — `test/watch_sync_request_handler_test.dart` · new group S-94a-21..S-94a-25 (reuse `_RecordingTransport`, l.99, and its undelivered-type stub).
5. [x] Wire tests — `test/watch_transport_test.dart` · S-94a-26 contract pins beside S-87c-16 (~l.1639) and `wantsWaterOf` table beside the `holdsBestsOf` table; `test/watch_session_projection_test.dart` · S-94a-26 wiring arm (the S-87c-18 radio harness).
6. [x] Verify-only — S-94a-22's second half: run `test/watch_sync_changed_only_test.dart test/watch_sync_idle_reads_test.dart test/rest_ping_contract_test.dart test/watch_accent_contract_test.dart test/watch_message_order_test.dart` unedited; a failure means the default path changed — fix the code, never the assertion.
7. [x] Docs — `docs/state_management/watch_reference_data.md` · "Routing and the request frame" names `wantsWater` (D-9); a new "### The water count rides an answer that asks" section beside "The bests close every answer that needs them" (~l.237): D-8, D-6 in plain words, the 94b counting rule D-7 by reference.
8. [x] Residue sweep — `grep -rn "water_down\|wantsWater\|water_glass" lib watch/sync_protocol watch/contract test docs` lists only predicted files; full suite; Progress + Assumption Log + evidence.

**Done Criteria**: `gateway.sh lint`; `gateway.sh test` (full suite, 900 s); `gateway.sh swift-test` (validator unchanged since Phase 1, run once to close the PR); `test/ui_standards_contract_test.dart` and `test/docs_indexing_contract_test.dart` inside the full run; the invariant grep empty.
**Predicted Files**: `watch_transport.dart`, `watch_sync_request_handler.dart`, `watch_sync_wiring.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_transport_test.dart`, `test/watch_session_projection_test.dart`, `docs/state_management/watch_reference_data.md`, this plan, the evidence file.

## Files Affected (whole PR)

Production: `lib/core/constants/water_constants.dart`, `lib/data/models/models.dart`, `lib/data/repositories/{workout,hive_workout,mock_workout}_repository.dart`, `lib/state/nutrition_state.dart`, `lib/watch/session/watch_records.dart`, `lib/core/utils/watch_reference_sync.dart`, `lib/core/sync_protocol/message_validator.dart`, `lib/core/platform/watch_transport.dart`, `lib/state/watch/{watch_water_log_bridge (new),watch_incoming_router,watch_sync_wiring,watch_sync_request_handler}.dart`, `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`. Predicted production diff ≈ 600 lines.
Contract: `scripts/sqlite_schema.sql`, `watch/sync_protocol/{PROTOCOL.md, schemas/…, fixtures/…}`, `watch/contract/watch_start_paths_contract.json`.
Tests: `test/water_tap_ledger_test.dart` (new), `test/watch_water_log_test.dart` (new), `test/db_seed_test.dart`, `test/watch_sync_request_handler_test.dart`, `test/watch_transport_test.dart`, `test/watch_session_projection_test.dart`.
Docs: `docs/data_models.md`, `docs/db_integration.md`, `docs/state_management/nutrition_state.md`, `docs/nutrition.md`, `docs/state_management/watch_reference_data.md`.
Read-only dependents (green, unedited): `test/state_test.dart`, `test/nutrition_test.dart`, `test/watch_nutrition_quick_log_test.dart`, `test/watch_session_import_test.dart`, `test/watch_sync_changed_only_test.dart`, `test/watch_sync_idle_reads_test.dart`, `test/rest_ping_contract_test.dart`, `test/watch_accent_contract_test.dart`, `test/watch_message_order_test.dart`, `lib/features/nutrition/**`, `lib/watch/start/watch_sync_orchestrator.dart`, `WatchSyncOrchestrator.swift`, every Swift test.

## Notes

- Dependency graph: 1 → 2 → 3 → 4. Phase 2 needs nothing from 1 and may run first (no shared file); Phase 3 needs 1 (its tests validate through the real schema) and 2; Phase 4 needs 1, 2 and 3's builder. Running 2 before 1 is safe and costs nothing.
- Intermediate states: after 1 the wire is validatable but unused; after 2 the phone can store taps but nothing calls it; after 3 a wrist tap is applied and answered; after 4 a wrist that asks gets the count. Every state ships green; no state changes what the owner sees until a 94b wrist sends taps.
- 94b inherits: the wrist store for the held frame (new record kind + prune, the `bests` pattern in `WatchSessionStore.swift` / `FileWatchSessionStore.swift`), `WatchObservationKind.all` + its closed-set test, `wantsWater: true` on `WatchTransportRequest.routinesFrame` (Swift) pinned against `routinesWater`, `replyTypes`, the bar, QA. Also for 94b to decide with the owner: whether unsent water taps show the "waiting for your phone" line (plan 51d) as unsent foods do.
- `pruneConfirmed()` has no production caller (`grep -rn "pruneConfirmed()" watch/watchos/Sources "ios/OmniTrain Watch App"` → only its definition), so confirmed wrist taps stay stored and D-7's fold always sees them.

## Progress

- [x] Phase 1 Contract — @developer — Complete 2026-11-01: lint 181 (= baseline); 3 Dart suites +256 pass; swift-test 1139/0 fail; red→green in evidence
- [x] Phase 2 Storage — @dba — Complete 2026-11-01: lint 181 (= baseline); Done Criteria suites +370 -1 local / +371 under TZ=UTC (the 1 red is a pre-existing DST-day nutrition-target test, see evidence); S-94a-6 red→green
- [x] Phase 3 Phone applies taps — @developer — Complete 2026-11-01: lint 181 (= baseline); Done Criteria suites +451 -1 local (A-8 only) / +452 under TZ=UTC; S-94a-11/12 red→green in evidence
- [x] Phase 4 Phone sends the count — @developer — Complete 2026-11-01: lint 181 (= baseline); full suite +6021 ~2 -1 local (A-8 only) / +6022 ~2 under TZ=UTC; swift-test 1139/0; 4 mutants red→green in evidence
- [ ] Review — @code-reviewer

## Assumption Log

- A-1 (planner, derived — vetoable before Phase 3): a late tap counts on the day it was tapped (D-3; Q2).
- A-2 (planner, derived — vetoable before Phase 3): no push on the phone's own taps (D-8; Q1).
- A-3 (planner; → D-19): the request literally said "the phone applies them via `incrementWaterForDate`/`decrementWaterForDate`"; the plan applies them through a new atomic repository write with the same math instead, because the at-most-once ledger must be written with the volume in one `put` (D-4, D-5); S-94a-3 proves the math identical.
- A-5 (owner, 2026-11-01): Q1 and Q2 answered "both defaults" — A-1 and A-2 stand, no longer vetoable.
- A-4 (planner): the series index is the "Series 94" section of this file, not a separate index file, so the series stays inside this plan's own folder (shared tree).
- A-6 (developer, Phase 1): the duplicate-tap rule reports one `semantic_violation` per repeated occurrence at `$.payload.appliedTapIds` (D-10's path, no index), the 87a per-occurrence pattern; options: one rejection per frame, or indexed paths. Both stacks identical.
- A-7 (dba, Phase 2): `WaterLogEntry.toMap` writes `applied_tap_ids` as JSON text (the SQL `TEXT` column, the `Exercise.howToSteps` precedent); `fromMap` reads JSON text or a list (the Hive row keeps a `List<String>`, D-4) and an absent key as `[]`. Options: toMap writes a list (not insertable into the contract table).
- A-8 (dba, Phase 2): `state_test.dart` "saveNutritionTargetForDate does NOT modify past dates when forward-propagating" is red in America/New_York on 2026-11-01 (DST end, 25-hour day) and green under `TZ=UTC`; outside this plan, not edited — flagged for the governor.
- A-9 (developer, Phase 3; → D-20): `loadWaterForDate` also queues on the D-12 chain and records the cache day after its read, so a load cannot overwrite a newer tap with a stale volume; option rejected: load outside the chain (stale-cache race).
- A-10 (developer, Phase 3; → D-21): bridge outcome `applied` = the message carried ≥ 1 readable tap (new, duplicate or over the cap) — the D-8(b) trigger; `changedTapIds` names the ones that changed storage. A tap unreadable without a validator is neither applied nor acknowledged.
- A-11 (developer, Phase 3, for Phase 4): S-94a-24's residue grep `~/ kWaterGlassMl` in `lib` also hits doc comments in `water_tracker_control.dart` and `models.dart` (not Phase 3 files); Phase 4 decides whether comments count.
- A-12 (developer, Phase 4): resolves A-11 — the S-94a-24 scan reads code lines only (a line whose trimmed text starts with `//` is skipped), so the comments in `water_tracker_control.dart` and `models.dart` may name the rule; neither file edited. Option rejected: count comments (would need edits outside 94a).
- Executors append here (≤ 3 lines each); the reviewer ratifies (→ D-x) or reverts (→ remediation).

## Open questions (one batched round; defaults are what the phases build)

1. **Q1 — Phone taps reaching a watch that is already open.** When you tap + or − on the phone, should an open watch Nutrition screen change at once, or at the watch's next sync (whenever the watch app comes to the front, or you press Sync)? Recommended default: next sync — the food list already works that way, and pushing would mean the phone keeps talking to the watch while you drink.
2. **Q2 — A glass tapped just before midnight that reaches the phone after midnight.** Recommended default: it counts for the day you tapped it (yesterday), so today starts at 0 on both devices and yesterday's total is right in history.

## Feedback

Review 2026-11-01 (@code-reviewer): changes requested, docs only. Findings: `2026-11-01-94-watch-water-logging-plan.review.md`. Fix checklist (one round, no re-review loop):
- [x] `docs/state_management/watch_surface.md` :628, :675-676 — name `WatchWaterLogBridge` among the router's owners; point at `test/watch_water_log_test.dart` S-94a-18.
- [x] `docs/nutrition.md` :430-431 — delete "its own + and − reach the watch at the watch's next sync".
- [x] `docs/state_management/watch_reference_data.md` :168-169, :307-308 — delete the two "in PR 94b" sentences (§3.7).
- [x] `docs/data_models.md` :539, `docs/db_integration.md` :273, `docs/state_management/nutrition_state.md` :58 — drop "(500)" / "250 ml" after the constant names (§3.4).
- [x] `watch/contract/watch_start_paths_contract.json` description — drop "four" / "three" request-frame counts.
- [x] Evidence: add a Docs section (each implicated doc updated or "no update required").
- [x] Governor decision: production phone receivers run without a validator — recorded as D-18.
- [x] Warning: `applyWatchWaterTap` row in the data_models.md cache table; db_integration.md ledger-key sentence corrected. Checks: evidence "Review fixes".
