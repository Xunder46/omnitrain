# Plan 290 — The Wear wrist holds the day's water count (plan 280 open item 5, part 1; with `holdsBests`)

Plan 280's item 5 is water: the Apple wrist shows a water bar at the bottom of its Nutrition screen (series 94-96: `docs/plans/2026-11-01-94-watch-water-logging-plan/`, `…-95-watch-water-bar-plan/`, `…-96-watch-water-follow-up-plan/`). The owner's decisions there are binding and this series matches them: the bar sits at the bottom of the Foods list (also when the list is empty), minus, a drop with the glass count, plus; a press is one glass added or removed, stored on the wrist first and sent as a `water_glass` event; the wrist asks for the phone's count on every sync and shows the phone's count plus its own taps the phone has not counted yet; 0 before the first sync; no water from inside a workout (the Nutrition screen only). Like the Apple series it is split: **this part (290) builds the data and the sync flags and shows nothing; 291 adds the bar.** It also finishes the `holdsBests` request flag that plan 288 left (series 87c: a wrist that already holds the bests says so, so the phone sends the frame only when it changed). Wrist only (`lib/watch/`, plus a pin in two existing tests); no wire, phone, schema or Swift change (`water_down`, `water_glass`, `wantsWater` and `holdsBests` are in the contract, the validators and the phone, plans 87c and 94). Base commit: `.work/2026-11-22-290-wear-water-count/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

What a user sees after 290: nothing different. What is true underneath: when a Wear watch asks the phone to sync it says it holds the bests (when it does) and wants the water count; the phone's `water_down` frame is kept (the newest copy; older dropped; the same numbers write nothing; unreadable refused whole; only the newest row stored); the wrist can log one tap of the water bar, stored first and sent under the day's nutrition id until the phone receipts it (never as part of a workout); and the count the bar will show is computed on every read from the held frame and the stored taps: the phone's count when the frame is for the wrist's local today, else 0, plus the wrist's own taps of local today that the frame does not list, in time order, an add +1 and a remove -1 but never below 0; the plus is refused once today's own taps reach 500, the minus also when the count is 0.

Acceptance: S-29001..S-29030 green under the in-memory store and Hive where storage is involved, each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; the Wear files and the readers named in the Impact list no new red; Docs delta applied.

## Feature invariants

- The count is computed on every read, never stored (Apple I-6): a relaunch, a receipt or local midnight never leaves a stale number.
- A water tap never enters a workout: its session id is always `nutrition-<UTC date of the tap>`, even while a session runs (unlike a food quick-log); a session's `observations`, `entries` and snapshot never carry one.
- At most one stored water frame row after any apply; every stored tap stays readable (the confirmed-observation prune has no production caller: only the debug surface, `watch_session_debug_surface.dart` 270).
- The store stays append-only: bests-style, the one new way a row leaves is `pruneWater`, gated on keeping the newest frame.
- A wrist without a water owner sends the pre-water request frames byte for byte.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-29001 | New record `WatchWaterRecord` (`type` `water`, `sessionId` empty, `generatedAt`, `day`, `glasses`, `appliedTapIds` in order) in `watch_records.dart`, a `water` list on `WatchStoreContents` (in `isEmpty`), a case in `WatchRecord.fromJson`, in both stores' `readAll`, the Hive box list `_allRows`, and a fourth prune `pruneWater({required String keepingRecordId})` with `pruneBests`' semantics (an unknown id drops nothing; every other water row goes) on the store contract and both stores. The S-004 guard's allowed set gains it on purpose; the `_SuspendingStore` test double forwards it. | plan 95 D-23; plan 288 D-28801/2; `test/watch_session_engine_test.dart` S-004; `test/watch_dialled_per_exercise_test.dart` |
| D-29002 | `WatchGlassChange` (`add`, `remove`: string constants, the wire's `glassChange` values) and the engine's `logWaterGlass(change, {loggedAt})`: builds exactly the plan 94 D-2 event (`entryId` = `eventId` = a new id, `kind` `water_glass`, `loggedAt` UTC, `glassChange`), stored before emitted through the same `_appendObservation` path as `logNutrition`, its session id ALWAYS `WatchNutritionSession.idFor(loggedAt)`; a change that is neither value throws `ArgumentError`. `waterLog` returns the stored `water_glass` observations in store order, confirmed or not. `water_glass` joins `WatchObservationKind.all` (not `efforts`); the two tests that pinned it out (`watch_water_log_test.dart` D-14 and `watch_nutrition_quick_log_test.dart` closed set) change on purpose. | plan 95 D-22; `watch_session_engine.dart` 1700-1735; `watch_records.dart` 80-100; Apple `WatchObservationKind.all` |
| D-29003 | New class `WatchWaterState` (`lib/watch/nutrition/watch_water_state.dart`): `restore()`, `applyWaterDown(envelope)`, `snapshot`, `press(change)`, `onWaterChanged`, with the limits and copy classes `WatchWaterLimits` (`tapsPerDay` 500, equal to `appliedTapIds.maxItems` in `water_down.schema.json`) and `WatchWaterCopy` (`Add one glass`, `Remove one glass`, `Water`, `1 glass`/`N glasses`). The frame applies and the presses run one at a time through an async gate, so two frames cannot both pass the "newer" check and two presses cannot both pass the cap. | `WatchWater.swift` 24-279 |
| D-29004 | `applyWaterDown` rules in order: the validator refuses a bad envelope (nothing stored); `messageId`, a `payload` map, a UTC `generatedAt`, a `day` string, a whole non-negative `glasses` (a Dart `int`) and an `appliedTapIds` list of strings are required, else false with nothing stored; a frame older than the held one is dropped; a frame with the same `day`, `glasses` and `appliedTapIds` (same order) writes nothing and only advances the held `generatedAt` in memory; else it is appended (`recordId` `water-<messageId>`), held (a tie in `generatedAt` with different content goes to the later received) and `pruneWater` keeps its row. `onWaterChanged` fires after `restore()`, an applied frame and a stored tap, never for a refused, dropped or unchanged frame. `restore()` holds the stored row with the greatest (`generatedAt`, `sequence`). | `WatchWater.swift` 149-215; plan 95 D-24 |
| D-29005 | The count (`snapshot`) exactly as plan 95 D-25 and plan 96 D-40/D-41: one clock read (the state's clock, read as local time) and one read of `engine.waterLog` per snapshot; only taps stored under a session id local today can carry (the UTC dates the local day touches) are parsed; a tap counts for today when its `loggedAt` falls on the local date; the frame's `day` is compared with the zero-padded local `YYYY-MM-DD`; a listed tap id (in the held `appliedTapIds`) is skipped; fold order `loggedAt`, then store sequence, then store position. `canAdd` = today's own taps < 500; `canRemove` = `canAdd` and the count > 0; `spokenCount` the copy's string. | `WatchWater.swift` 217-340; plan 96 D-40, D-41 |
| D-29006 | `press(change)` stores nothing, emits nothing and returns false when its button's rule is false (or the change is not `add`/`remove`), or when the write throws; true when a tap was stored. | `WatchWater.swift` 257-279 |
| D-29007 | `WatchSyncOrchestrator` takes an optional `WatchWaterState? water` and routes `water_down` to `applyWaterDown` (false with none). | plan 95 D-29; `watch_sync_orchestrator.dart` `receive` |
| D-29008 | The routines request: `WearWatchTransport` gains two public fields, `holdsBests` (a `bool Function()?`, null = no) and `wantsWater` (a `bool`, default false), read on every `requestRoutines` and passed to `WatchTransportRequest.routinesFrame(holdsBests:, wantsWater:)`, which already omits a false key. **Technical call, no interface change:** `WatchSyncTransport.requestRoutines({since})` keeps its signature because eight implementers (two in `lib`, six test doubles) would all have to change; the Wear transport is the only sender that has these flags, and `wear_main.dart` sets them: `transport.holdsBests = () => bests.hasFrame` and `transport.wantsWater = true`. | `watch_request_frames.dart` 40-65; `wear_watch_transport.dart` 148; plan 95 D-28; series 87c |
| D-29009 | `WearApp` takes an optional `WatchWaterState? water` and restores it in `_boot` after the nutrition restore; `wear_main.dart` builds one, gives it to the orchestrator and the shell, and sets the two transport flags. | plan 95 D-35; `wear_app.dart` `_boot`; `wear_main.dart` |
| D-29010 | Not in scope: the bar (291); the launch prune of old confirmed taps (plan 96 D-43/D-44 `pruneWaterTaps`, a fifth prune): the stored taps grow by at most 500 a day and every read filters by session id first (D-29005), so it is a later, separate change recorded as open in the evidence; a reinstalled wrist and a time-zone split (plan 94 D-7). | plan 96 |

## Input-reality checklist

1. **Writers.** The held frame: only `applyWaterDown` and `restore`. Stored taps: only `logWaterGlass` (through `press`), and the phone's receipts mark them confirmed without removing them. Frame rows: `append` and `pruneWater` (this class only).
2. **Units.** Glasses are whole counts; the phone owns the millilitres (plan 132); the wrist shows a count, never a volume.
3. **Lifecycle.** Never synced (0 plus own taps); synced then relaunched (restore); a frame for yesterday (base 0, only today's taps); a receipt that arrives before the next frame (the tap still counts: only the frame's list takes it out); two frames close together (the gate); the app killed between the frame append and its prune (two rows; restore reads the newest; the next frame prunes).
4. **Settings changing while open.** The phone's water volume unit does not reach the wrist (counts only).
5. **Time.** Local midnight with the bar open: the snapshot reads the clock each time, so the next read after midnight is the new day's (291 re-reads once a minute). A tap's day is its `loggedAt` in the device's local zone; its session id is its UTC date, so one local day touches at most three session ids.
6. **Load.** One pass over today's candidate taps per read (at most 500 plus a few); the rest of the history is skipped unread by the session-id filter.
7. **Wording.** Stale wording: `docs/wear_os_app.md` lists the water bar among the Apple-only items (stays until 291: the bar is not on the Wear wrist yet); the `D-14` comment in `watch_records.dart` and the two pinned tests.
8. **Slot competition.** None (no UI).

## Scenarios

Store (`test/watch_water_store_test.dart`, new, plain `test()`, under the in-memory store and Hive):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29001 | append a `WatchWaterRecord` (day, glasses 3, two applied ids); `readAll` | `water` holds it with every field, an assigned sequence; `isEmpty` false; the same id again is one row | the record or the list does not exist |
| S-29002 | three water rows, a bests row, a session row; `pruneWater(keepingRecordId: 'w3')` | returns the two dropped ids; `water` is `[w3]`; the other record types untouched; a second call returns `[]` | the prune does not exist or drops other types |
| S-29003 | `pruneWater(keepingRecordId: 'not-stored')` | `[]`, both rows stay | a stale id empties the frame |
| S-29004 | Hive: a water row, close, reopen | the row is back with `appliedTapIds` in order | Hive does not list the type |

Engine (`test/watch_water_engine_test.dart`, new):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29010 | `logWaterGlass('add', loggedAt: T)` with no session | one stored observation `water_glass`, session id `nutrition-<UTC date of T>`, payload keys exactly `entryId`, `eventId`, `kind`, `loggedAt` (UTC ISO), `glassChange`; one `observations_up` frame emitted after it was stored | the method does not exist, or the shape differs from `observations_up_water.json` |
| S-29011 | the same with a workout running | the session id is still the nutrition id; the workout's `observations`, `entries` and `sessionSnapshot()` carry no tap | a tap rides the workout |
| S-29012 | `logWaterGlass('stir')` | throws `ArgumentError`; nothing stored or emitted | an unknown change is stored |
| S-29013 | three taps (add, add, remove), two confirmed through `confirmObservations` | `waterLog` returns all three in store order, confirmed or not | a confirmed tap leaves the log |
| S-29014 | a tap, then relaunch the engine over the same store | `waterLog` is rebuilt | the log is memory only |
| S-29015 | the tap event validated against the shared schema (`observations_up_water.json` is the shape reference) | the envelope the engine emits passes the validator | the event is malformed |
| S-29016 | `WatchObservationKind.all` | contains `water_glass`; `efforts` does not | the kind is not in the set, or counts as an effort |

State (`test/watch_water_state_test.dart`, new; in-memory engine and store, a state clock the test moves, the clock's zone the test machine's local zone, the frame's `day` built from the same local clock):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29020 | nothing held, nothing tapped | `snapshot` 0 glasses, `canAdd` true, `canRemove` false, `spokenCount` `0 glasses` | the defaults differ |
| S-29021 | frame for local today, glasses 3, no ids | 3; `spokenCount` `3 glasses`; with 1 glass `1 glass` | the base is not the frame |
| S-29022 | the same frame, then `press(add)` | `press` true; 4 at once; `onWaterChanged` fired once; one tap in `waterLog` | the fold does not include the wrist's tap |
| S-29023 | frame glasses 3 listing tap `a`; the wrist's tap `a` (add) and tap `b` (add) stored | 4: `a` is skipped (listed), `b` counts | a listed tap is counted twice, or an unlisted one is dropped |
| S-29024 | a tap confirmed by a receipt, frame not listing it yet | the tap still counts | a receipt removes a tap from the fold |
| S-29025 | adds and removes in time order: base 1; remove, remove, add | 0 (the second remove stops at 0), then 1; the order is the `loggedAt` order, not the store order (store the later-stamped tap first) | the floor or the ordering is missing |
| S-29026 | the frame's day is yesterday | the base is 0; only today's taps count; yesterday's taps are ignored | a stale day shows its count |
| S-29027 | local midnight passes (the clock moves past it) with a held frame of the old day and a tap of the old day | the next `snapshot` is 0 | the day is cached |
| S-29028 | 500 taps stored today | `canAdd` false and `canRemove` false; `press(add)` and `press(remove)` store nothing, emit nothing, return false; at 499: `canAdd` true | the cap is missing or off by one |
| S-29029 | count 0 | `press(remove)` returns false, nothing stored | minus below zero stores a tap |
| S-29030 | a tap stored under a session id local today cannot carry (a hand-built old tap) and malformed taps (no `glassChange`, a bad `loggedAt`) | ignored; the count unchanged; one `waterLog` read per `snapshot` | an unrelated or malformed tap is counted or throws |
| S-29031 | frame rules: an older frame (generatedAt before) is dropped; a tie with different content applies; the same content writes nothing but a later `generatedAt` is kept in memory (so a following older-than-that frame is dropped); an unreadable frame (missing `day`; `glasses` -1; `glasses` 2.0 as a double; `appliedTapIds` containing a number) is refused; the store holds one water row after each applied frame | each as stated; `onWaterChanged` fires only for the applied ones | a rule is missing |
| S-29032 | the real validator with `fixtures/valid/water_down.json` and `water_down_empty_day.json`; a copy with an extra field | the fixtures apply; the extra field is refused, nothing stored | the validator is not consulted |
| S-29033 | restart: a new state over the same store, `restore()` | the held frame and count are back (the engine's own restore first); `onWaterChanged` fires | restore does not read the row |
| S-29034 | two frames applied together (`Future.wait`), both orders; and two presses together at 499 taps | the newer frame decides and one row remains; exactly one of the two presses is stored | the gate is missing |

Wiring (`test/wear_water_wiring_test.dart`, new):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-29040 | the orchestrator with a water owner: `receive(water_down)`; without one | true and the frame held; false | the route does not exist |
| S-29041 | the Wear transport with both flags set, `requestRoutines(since: T)` captured at the method channel; with none set | the frame has `holdsBests: true` and `wantsWater: true` plus `since`; with none set neither key and the frame equals the old one byte for byte | the flags are not sent, or `false` is sent |
| S-29042 | `holdsBests` a closure that changes from false to true between two requests | the second frame carries the key and the first does not | the flag is read once |
| S-29043 | the shell given a water owner over a store holding a frame, opened | the owner holds it after the boot frames | `_boot` does not restore |
| S-29044 | a scan of `wear_main.dart` | one `WatchWaterState(store`... construction, `water: water` twice (orchestrator and shell), `transport.wantsWater = true`, `transport.holdsBests = () => bests.hasFrame` once each | the entry point does not wire it |

Guard families the lead proves by mutation: the record, store and prune guards, the engine's session id and shape and validation, the cap (and its off-by-one), the zero floor, the listed-tap skip, the fold order, the day comparison, the local-day session-id filter, every frame rule, the gate, the two flags and their reads, the route, the restore.

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "do not run any command through the gateway; write the report FIRST as a skeleton, then fill it and stop".

1. **P1 — records, stores, engine** (`crew-builder-watch`; scope `lib/watch/session/watch_records.dart`, `lib/watch/session/watch_session_store.dart`, `lib/watch/session/hive_watch_session_store.dart`, `lib/watch/session/in_memory_watch_session_store.dart`, `lib/watch/session/watch_session_engine.dart`). Exact code in the brief. About 160 lines.
2. **P2 — the state, the flags, the wiring** (`crew-builder-watch`; scope `lib/watch/nutrition/watch_water_state.dart` (new), `lib/watch/start/watch_sync_orchestrator.dart`, `lib/watch/app/wear_watch_transport.dart`, `lib/watch/app/wear_app.dart`, `lib/watch/wear_main.dart`). Exact code in the brief. About 260 lines. After P1 (it uses P1's engine methods).
3. **P3 — tests** (lead, as in plans 287-289): the four new files, the S-004 edit, the `_SuspendingStore` forwarder and the two pinned-test edits.
4. **P4 — docs** (lead).
5. **Lead:** analyze, readers, mutation pass, plan-lint.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | ADDED | - | ## The water count | S-29022 |
| docs/wear_os_app.md | ADDED | - | `test/watch_water_state_test.dart` | S-29022 |

Plan 280's open item 5 is a plan record (annotated "part 1, the count and the flags, built by plan 290; `holdsBests` closed"). Stale-term sweep: `grep -rIn -i "water bar\|holdsBests" docs | grep -v "docs/plans\|docs/history\|docs/releases"` reviewed: the Apple and phone pages stay true; `docs/wear_os_app.md` is edited by the rows above.

## Assumption Log

- Impact readers of the changed surfaces: `WatchStoreContents(` is built with named, defaulted parameters (no call site edited); `WatchSessionStore` implementers are the two stores and `_SuspendingStore` (`test/watch_dialled_per_exercise_test.dart`, found by the analyzer in plan 288); `WatchObservationKind.all` has no `lib` reader, two test readers (D-29002); `WatchSyncTransport` is untouched (D-29008).
- The Dart engine's `_observations` holds every session's observations and `observations` filters by the current session, so a tap under a nutrition id never appears in a workout's `observations`/`entries`; S-29011 proves it rather than assuming it.
- `pruneConfirmed()` has no production caller (`watch_session_debug_surface.dart` is a QA surface), so a confirmed tap stays in `waterLog`.

## Progress

- [x] P1 records, stores, engine (crew builder)
- [x] P2 state, flags, wiring (crew builder, in parallel)
- [x] P3 tests (lead; S-29001..S-29044 plus S-29017, S-29035)
- [x] P4 docs (lead)
- [x] Verify and prove (analyze 174; Wear set green; every non-equivalent mutant killed)
