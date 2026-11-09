# Plan 36b — Routine start sync, PR 2: the watch shows the planned sets and presets

Status: SEEDED by the lead. Base commit `295dd71` (branch `claude_develop`; plan 36a is committed there: `docs/plans/2026-10-14-36-routine-start-sync-plan/`). Tree clean at seed time.
Owner answers (2026-10-14): a routine started on the phone shows the watch each exercise's planned sets and preset values ("Set 1 of 3, 10 reps, 40 kg") ready to dial in, nothing logged; the "N logged" count counts only sets really logged (36a did that). Commits for plan 36 are authorised (`.work/2026-10-15-36b-planned-sets/commit-ok.txt`); never push.

## Goal and acceptance

- A1. A phone session's `set` slot carries `plannedSets`: the reps and load of EVERY set row the exercise holds, in set order (index = set number; the same number as the entry ids `entry-<slot>-<n>`), logged rows included.
- A2. On the wrist, for a `set` effort whose slot carries `plannedSets`, the value screen starts the user's next set from the planned values of that set (reps and load), not from the previous set's values or the kind's default 10 reps / 0 kg. The next set is the one whose index equals the number of the slot's `set` entries the wrist holds (the phone's logged ones plus its own).
- A3. The header of the wrist's logging screen shows one extra caption line "Set k of N" for such a set effort: k = entries held + 1, N = the larger of the planned count and k (an extra set reads "Set 4 of 4"). No caption for any other effort kind, and none for a slot with no `plannedSets` (a wrist-started free session behaves exactly as today).
- A4. A slot with no set rows, a non-`set` slot, or an old phone sends no `plannedSets` key; the wrist behaves as before. The key is optional on the wire; the schema stays closed (`additionalProperties: false`), so the field is declared.
- A5. A change to the planned values on the phone (the user edits a preset, adds a set, logs a set with other values) reaches the wrist: the projected revision rises and the snapshot is pushed.
- A6. Units: planned load is in kilograms on the wire; the wrist shows it through the saved weight unit as it already does for every load.
- A7. `flutter analyze` not above 182; `flutter test` not below `+4697 ~1` (plus new); `swift test` not below 580 (plus new); no `ui_standards` allowlist entry added.

## Decision Ledger

- D-1 Wire: `sessionExercise.plannedSets` (`watch/sync_protocol/schemas/envelope.schema.json` `$defs.sessionExercise.properties`, next to `roundDurationSecs`): `{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"reps":{"type":"integer","minimum":1},"loadKg":{"type":"number","minimum":-200}}},"description": ...}`. No `minItems`, no `maxItems` (no slot array has bounds today). Both properties optional: `reps` omitted for a row with fewer than 1 rep (a skipped row), `loadKg` omitted when 0. Additive amendment in `PROTOCOL.md` ("1 (amended)" row, same pattern as the 2026-10-11 accent row and 36a's units row).
- D-2 Phone: in `WatchSessionAdoptionBridge.projectSession` (`lib/state/watch/watch_session_adoption_bridge.dart:217-227` loop), after `_slotFor` and only when `_wireKind(slot) == PhoneEntries.setKind`, read `EntryRows.setGroups(await _repository.getEffortObservations(effort.id))` and set `slot['plannedSets'] = [for (final g in groups) {if reps >= 1 'reps': reps, if load != 0 'loadKg': load}]` (reps/load read exactly as `PhoneEntries._entry` reads them: `group.entry['reps'] as int?`, `group.entry['weight'] as double?`); omit the key when there are no groups. `_slotFor` stays synchronous and untouched.
- D-3 Revision: `_ladderOf` (`:536-548`) appends `jsonEncode(slot['plannedSets'] ?? const [])` to each slot's string so A5 holds; `revision` therefore rises when planned values change. (Auto-push compares the whole encoded payload, so a push happens either way; the revision is what the wrist's replace-structure rule needs.)
- D-4 Wrist state (`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`): a private `plannedSets: [[String: Any]]?` read from `slot` (`:483`, the raw dict) — nil unless the effort kind is `set` and the key is a non-empty array; a private `setsHeld: Int` = the count of `observations` (`:476`) whose `kind == "set"`; `initialValue(for:)` (`:545`): for `reps` and `weight` of a `set` effort, when `plannedSets` is non-nil and `setsHeld < plannedSets.count` and the planned row carries the key (`reps` -> reps, `loadKg` -> weight), return that value BEFORE the `lastLogged ?? target` chain; otherwise the chain as today. A row without `loadKg` yields 0 for weight (a planned zero load), a row without `reps` falls through to the chain.
- D-5 Caption: `public var setCaption: String?` on `WatchLoggingState`: nil unless `plannedSets` is non-nil; else `"Set \(setsHeld + 1) of \(max(plannedSets.count, setsHeld + 1))"`. `WatchLoggingView.header` (`WatchLoggingView.swift:101`) adds, after the name and before `roundLine`: `if let caption = model.state.setCaption { Text(caption).font(.caption2).foregroundStyle(.secondary) }`. (The view is `#if os(watchOS)`; the string logic is tested through `setCaption`.)
- D-6 No change to the wrist's snapshot validation code: the incoming gate already validates against the schema, so declaring the field is what lets the snapshot in (scout W Q1: until declared, the whole snapshot is refused and nothing is stored). Tests that validate use the schema files from `watch/sync_protocol/schemas/`.
- D-7 Not in this plan: planned timed/hold/round durations and distances, the Dart wrist client `lib/watch/**` (Wear OS), a wrist-side "add a set" count, and 36c (watch-started routine adoption).

## Readers of what this plan changes

- Slot shape on the phone: `test/watch_session_adoption_bridge_test.dart:1519` `S-1411 the same number twice is the same bytes` (pins a slot map whole; stays equal while nothing changes), `:1349`, `:1389`, `:1446`, `:1482` (field-by-field, unaffected), `test/watch_session_projection_test.dart:670` S-2 (field-by-field). Phone slots with set rows now carry `plannedSets`; any test that compares a whole phone slot or whole `exercises` list of a session with set rows (re-grep `'capabilities'` next to `'sessionExerciseId'` in `test/watch_session_*`, and `projectSession` users: auto-push, finish, live-refresh, merge, round-trip) must be re-read.
- Wire fixtures: every fixture with a slot (`valid/session_snapshot*.json` listed in `fixtures/manifest.json`) stays valid (the field is optional); the walkers are `test/sync_protocol_fixtures_test.dart` (group `S-001 fixtures`) and `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift` (`testEveryValidFixtureConforms`, `testEveryInvalidFixtureIsRejectedAsStated`). The PROTOCOL doc test `S-007 specification links only to schema and fixture paths that exist` and `documents every rejection code` read `PROTOCOL.md`.
- Wrist value defaults: `WatchLoggingSurfacesTests.testS001TheNextSetCarriesOverTheValuesJustLogged` (`:109`) must stay green for slots with no `plannedSets`; every Swift test that builds a slot with `capabilities` only (`WatchPhoneEntriesTests.swift:410`, `WatchLoggingSurfacesTests.swift:38`, `WatchLoggingTimersTests.swift:35`) is unchanged and is the "old behaviour" guard.
- Docs: `docs/watch_session_sync.md`, `docs/watch_session_capture.md` (the wrist's logging screen), `docs/modality_based_exercise_ui.md` only if it describes the wrist; the architect greps `reps`/`load` + "wrist" before Phase D.

## Core scenarios (exact fixtures)

Fixture P: slot `sx-bench` (exercise `ex-bench`, capabilities `["sets","reps","load"]`, `effortKind` omitted), three planned rows reps 10 / 10 / 8 and loads 40 / 40 / 42.5 kg, no entries.

- S-3620 (contract, `watch/sync_protocol/fixtures/valid/session_snapshot_planned_sets.json`, new; `invalid/session_snapshot_planned_sets_bad.json`, new; manifest entries; both test walkers): the valid snapshot carries P's `plannedSets` `[{"reps":10,"loadKg":40},{"reps":10,"loadKg":40},{"reps":8,"loadKg":42.5}]` and conforms; the invalid one has `"reps": 0` in one item -> `constraint_violation`, message contains `expected at least 1`; a second invalid fixture `..._planned_sets_unknown_key.json` with `"setNumber": 1` in an item -> `unexpected_field`. (Fails without D-1: the unknown key is refused.)
- S-3621 (phone, `test/watch_session_projection_test.dart`, new group): a live phone session with P's three rows (built like 36a's fixture F: `LoggedEntryRows.setObservations`), no rests: the projected slot's `plannedSets` equals the list above (loads as doubles); with rests at 1 and 2 (two sets logged) the list is the same three items; a row with reps 0 projects `{loadKg: 40.0}` only; an exercise without the `load` capability projects `{reps: 10}` only; a `timed` slot has no `plannedSets` key; an effort with no rows has none either. (Fails without D-2.)
- S-3622 (phone revision, `test/watch_session_adoption_bridge_test.dart`, pattern of `S-1409 a length-only change moves the revision`): `projectSession` twice with nothing changed -> same revision; update row 1's reps from 10 to 12 -> the revision rises by one and the second payload differs; the same call again -> same revision. (Fails without D-3.)
- S-3623 (wrist, new `watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift`; pattern `WatchPhoneEntriesTests.swift` `phoneEntriesSnapshot`/`slot`): snapshot with P and no entries; logging surface: reps field value 10, weight field value 40 (kilograms), `setCaption == "Set 1 of 3"`. Log reps 12 / 45 kg through the surface (`log`): next fields reps 10 / weight 40 (the planned set 2 wins over what was just logged), caption "Set 2 of 3"; log again: reps 8 / weight 42.5, "Set 3 of 3"; log a third: fields fall back to the last logged (reps 8 / 42.5), caption "Set 4 of 4". (Fails without D-4/D-5.)
- S-3624 (wrist): a phone-logged set counts: snapshot with P plus ONE `set` entry for `sx-bench` (id `entry-sx-bench-0`, reps 10, loadKg 40): caption "Set 2 of 3", fields reps 10 / weight 40.
- S-3625 (wrist): a slot with no `plannedSets`: `setCaption == nil` and values as before (the existing S-001 carry-over test is the guard); a `timed` slot carrying `plannedSets` ignores it: caption nil; a `plannedSets` item with no `loadKg`: weight 0; no `reps`: reps from the old chain.
- S-3626 (wrist units): weight unit `lbs` (`WatchUnitPreferences(weightUnit: "lbs")`), planned load 45 kg: the field's DISPLAY text is the pound conversion of 45 kg (`WatchMetricStepping.fromKilograms(45, unit: "lbs")` formatted `%.1f` by the state), the stored value stays 45.

Why they fail without the change: S-3620 snapshot refused (`unexpected_field`); S-3621 no key; S-3622 no revision change; S-3623 reps 10 / weight 0 and no caption; S-3624 no caption; S-3626 no planned value.

## Phase outline

- Phase A1 — `crew-builder-watch`; scope `watch/sync_protocol/schemas/envelope.schema.json,watch/sync_protocol/fixtures/**,watch/sync_protocol/PROTOCOL.md`: D-1 + S-3620 (the fixtures and manifest entries; the two walkers prove them red-then-green). Serial first.
- Phase A2 — `crew-builder-app`; scope `lib/state/watch/watch_session_adoption_bridge.dart,test/watch_session_projection_test.dart,test/watch_session_adoption_bridge_test.dart`: D-2, D-3 + S-3621, S-3622, plus migrating any whole-slot comparisons the readers list shows. After A1; parallel with B.
- Phase B — `crew-builder-watch`; scope `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift,watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift`: D-4, D-5 + S-3623..S-3626. After A1; parallel with A2. Only one of A2/B runs a full suite.
- Phase D — `crew-docs-keeper`; docs named by the architect + plan evidence.
- After D: lead mutations (see the architect's proof list), reviewer, commit.

## Code pointers (current lines)

- Phone: `lib/state/watch/watch_session_adoption_bridge.dart`: `projectSession :204` (loop `:217-227`), `_slotFor :471-503` (returns the slot map), `_wireKind` (used at `:~262`), `_countRevision :515-531`, `_ladderOf :536-548`, `_entriesFor :259`. `lib/core/utils/entry_rows.dart`: `setGroups :158`, `SetRows :20` (`.entry` map with `reps`/`weight`), `loggedSetNumbers :170`. `PhoneEntries._entry` (`lib/core/sync_protocol/phone_entries.dart:434`) for how reps/load are read.
- Wire: `watch/sync_protocol/schemas/envelope.schema.json` `$defs.sessionExercise` `:96-137` (`additionalProperties:false` at `:105`); `messages/session_snapshot.schema.json:28-34`; `fixtures/valid/session_snapshot.json` (slot at `:15-20`); `fixtures/manifest.json`; PROTOCOL changelog rows at the end of `PROTOCOL.md`.
- Wrist: `WatchLoggingState.swift`: `fields :464`, `field(for:) :515-523`, `targetsByKind :209-215`, `observations :476-480`, `slot :483`, `initialValue(for:) :545`, `lastLogged :~572`, `log(now:) :710` (clears `dialled` at `:746`). `WatchLoggingView.swift:101-113` `header`. `WatchSessionEngine.swift:471-532` `applySnapshot` (slots replaced raw, entries merged by id).
- Tests: `WatchPhoneEntriesTests.swift:313` `testS145…`, helpers `phoneEntriesSnapshot ~425`, `slot :410`; `WatchLoggingSurfacesTests.swift:109`; `SyncProtocolFixturesTests.swift:37,55`; `test/sync_protocol_fixtures_test.dart:212-224`; `test/watch_session_adoption_bridge_test.dart:1317` (`slotOf :1319`), `:1482`, `:1519`.

## Not in this plan

36c: a routine started on the watch becomes a routine session on the phone (routine id on the wire, the phone's current template supplies title, intent, planned entries and presets).

## Architect expansion (2026-10-15)

### Claim checks (every file quoted was read this run)

- (a) VERIFIED — `WatchLoggingState.log` appends through `engine.appendObservation(event)` (`WatchLoggingState.swift:744`); `appendObservation` stores the row in `storedObservations` before emitting (`WatchSessionEngine.swift:1254-1258`); `engine.entries` projects `storedObservations` for the current session (`WatchSessionEngine.swift:199-208`) and `observations` filters that by slot id (`WatchLoggingState.swift:476-480`). The wrist's own just-logged set is in `setsHeld` before the phone confirms; `confirmObservations` drops it only when a snapshot carries its id.
- (b) WRONG as D-3's reason states it — `applySnapshot` (`WatchSessionEngine.swift:487-532`) compares no revision. Its only gates are the schema gate in `applyMessage` (`:442`) and the foreign-session refusal (`:502-506`):
```swift
if let held = current,
   held.status == WatchSessionStatus.active,
   !held.exercises.isEmpty,
   held.sessionId != sessionId {
    return false
}
```
A same-session snapshot with the same revision and different `plannedSets` IS applied: a new row `snapshot-<messageId>` is stored and `exercises` is replaced wholesale (`:517-532`); only the identical messageId is a no-op (`testS81AReDeliveredSnapshotLeavesTheStoreAsItWas`, `WatchSessionEngineTests.swift:1745`). D-3 is kept; see Open questions 1.
- (c) VERIFIED — `PhoneEntries._entry` reads `(set['reps'] as int?) ?? 0` and `(set['weight'] as double?) ?? 0.0` (`lib/core/sync_protocol/phone_entries.dart:440,446`) over `SetRows.entry`, which stores `valueInt`/`valueReal` (`lib/core/utils/entry_rows.dart:36-46`); a weight of 0 rides without `loadKg` (`:457`), so D-2's omission rule matches how entries omit load.
- (d) VERIFIED — the field's `value` stays canonical kilograms; only `displayValue` converts, `WatchMetricStepping.fromKilograms` formatted `%.1f` (`WatchLoggingState.swift:649-654`). S-3626's expectation matches.
- (e) VERIFIED — `log(now:)` runs `dialled.removeAll()` after the append (`WatchLoggingState.swift:746`), and `field(for:)` reads `dialled[metricKey] ?? initialValue(for:)` (`:517-519`), so the next set re-enters `initialValue`.

### Feature invariants (this plan only; project-wide rules stay in docs/global_conventions.md)

- I-1 `plannedSets` is a read-only projection of the phone's stored rows: built only in `projectSession` from `EntryRows.setGroups`, never written or edited on the wrist (a wrist log writes observations, never planned rows).
- I-2 Index is set number: `plannedSets[k]` is set k+1, the numbering of `entry-<slot>-<n>` and `EntryRows.setGroups` (`entry_rows.dart:158`).
- I-3 Omission rules match the entry rules: reps < 1 and load 0 are omitted (`PhoneEntries._entry`, `phone_entries.dart:434-458`) — the wire keeps "no load" and "load 0" indistinguishable.
- I-4 The wrist counts entries held, not planned rows: `setsHeld` counts the slot's `set` observations in `engine.entries`, the wrist's own unconfirmed ones included (claim a).
- I-5 No planned value and no caption for a non-`set` effort: the kind gate sits before every read (D-4/D-5).
- I-6 Planned load travels in kilograms and is converted only at display (conventions "Units + canonical storage"; claim d).
- I-7 The schema object stays closed: the field is declared, `additionalProperties: false` stays (`envelope.schema.json:105`).

### Existing-functionality impact

| Touched surface | What already reads it (search run this run) | Effect | Guarded by |
| --- | --- | --- | --- |
| `sessionExercise` schema gains `plannedSets` (D-1) | Slot fixtures `valid/session_snapshot.json` (:15-20), `…_session_capture`, `…_with_entries`, `…_band_assist`, `…_round_length` (manifest :13, :36-37, :51-52, :62-63, :85-86); walkers `test/sync_protocol_fixtures_test.dart` S-001 (:212-224, one generated test per fixture) and `SyncProtocolFixturesTests.swift` `testEveryValidFixtureConforms` (:37) / `testEveryInvalidFixtureIsRejectedAsStated` (:55); the PROTOCOL doc tests S-007 read `PROTOCOL.md` | Field optional → every existing fixture stays valid; three new fixtures + one changelog row | S-3620 |
| Phone slot shape (D-2) | Whole-slot: `test/watch_session_adoption_bridge_test.dart:1519` S-1411 (`slotOf` equality :1532-1536) — its slot is a round effort with no set rows (:1493-1496), so `plannedSets` is absent and it stays green. `exercises`-list: `test/watch_reconciliation_cross_stack_test.dart:132-138` compares `_structureOf` (ids/index/revision/status/timer keys, :78-91); `test/live_mirroring_test.dart:820` ids only; `test/sync_protocol_fixtures_test.dart:723` fixture-driven. `test/watch_session_projection_test.dart:2479,:2613` record `jsonEncode(payload)` per store into `parity` but nothing compares the values (grep `parity` → 3 hits, assignments only). Field-by-field: projection S-2 (:670-708), adoption :1349/:1389/:1446/:1482/:806, finish :903 — an added optional key breaks none. `projectSession` users (grep, 27 matches / 6 files): auto-push, finish :147, live_refresh :126, merge :192, round_trip :100 | Slots with set rows gain `plannedSets`; the auto-push baseline differs on the first push after the change (expected); `plannedSets` must stay deterministic | S-3621, S-3622 |
| `initialValue(for:)` planned branch (D-4) | Swift tests reading `fields` for a `set` effort (grep `.fields`, 27 matches / 6 files): `WatchLoggingSurfacesTests` testS001Rotary…(:63), testS001TheNextSetCarriesOver…(:109), testS001ABodyweight…(:120, reps default 10 at :128); `WatchPhoneEntriesTests:405` (testS145); `WatchLoggingTimersTests:506-516`; `WatchCaptureContractTests:167,171`. All build slots with `capabilities` only (helpers `WatchPhoneEntriesTests.swift:410`, `WatchLoggingSurfacesTests.swift:38`, `WatchLoggingTimersTests.swift:35`) → `plannedSets` nil → chain unchanged; they are the old-behaviour guard | Planned values win only when the key is present | S-3623, S-3625 |
| `setCaption` + header (D-5) | No Swift test renders `WatchLoggingView` (`#if os(watchOS)`, compiled into the watch target, not `swift test`); the string logic is tested through `setCaption` | One optional `caption2` line after the name, before `roundLine` | S-3623 |
| Docs | `docs/watch_session_sync.md:24` (projection row: "a planned row is sent as nothing") and :70-73 (the planned-rows paragraph) describe what the ladder carries. `docs/watch_session_capture.md` describes the import, not the wrist logging screen (grep `reps\|load\|default` → no hits). `docs/state_management/watch_surface.md:484` mentions the logging screen (sensors/rest only). `docs/modality_based_exercise_ui.md` is phone-side (`Exercise.defaultRoundDurationSecs`) | Phase D: one sentence + test names in `watch_session_sync.md` | — |

### Edge scenarios (after S-3626)

- S-3627 All rows logged on the phone: snapshot with P plus three `set` entries `entry-sx-bench-0..2` (reps 10/10/8, loads 40/40/42.5): `setsHeld` 3 ≥ count → caption "Set 4 of 4" and fields fall back to the last logged (reps 8 / 42.5); k > N appears only once held ≥ count. Fails without D-4's `setsHeld < plannedSets.count` gate (planned set 1 would win forever).
- S-3628 A wrist-logged set not yet acknowledged: snapshot with P, no entries; the wrist logs 12/45 through the surface: caption "Set 2 of 3" and fields reps 10 / weight 40 BEFORE the phone confirms — `setsHeld` counts the wrist's own observation (claim a). Fails if `setsHeld` counted only snapshot-carried entries.
- S-3629 A stale snapshot with the same revision and different `plannedSets` IS applied: `applySnapshot` compares no revision (claim b, gate quoted above); a new messageId stores a new row and replaces `exercises` wholesale, so the wrist shows the stale planned values until the newer snapshot arrives. Existing behaviour, no new code; the identical messageId stays a no-op (`testS81AReDeliveredSnapshotLeavesTheStoreAsItWas`, `WatchSessionEngineTests.swift:1745`).
- S-3630 The user adds a set on the phone mid-session: P plus a fourth row (`LoggedEntryRows.setObservations`, entryIndex 3): the projected `plannedSets` has four items, the revision rises (D-3), and the wrist's next snapshot shows "Set k of 4". Guard: S-3621's list assertion extended + S-3622.
- S-3631 Kind `set` by capability but the slot declares `effortKind` of another kind (hand-built slot `{"effortKind":"timed","capabilities":["sets","reps","load"],"plannedSets":[…]}`): the wrist's `effortKind` prefers the declaration (`WatchLoggingState.swift:434-438`) → `plannedSets` ignored, caption nil, values from the old chain. The phone never sends the key for such a slot (`_wireKind` prefers the declaration too, `watch_session_adoption_bridge.dart:341-344`); the wrist gate is the defence.
- S-3632 A hold or timed effort with `plannedSets` present: caption nil, values unchanged (D-4's kind gate). Fixture: slot `effortKind: "hold"`, capabilities `["time","hold"]`, `plannedSets` present.

### Phases

- Phase A1 — `crew-builder-watch`; scope `watch/sync_protocol/schemas/envelope.schema.json,watch/sync_protocol/fixtures/**,watch/sync_protocol/PROTOCOL.md` (serial first):
  1. [ ] Red: build the three fixtures below and watch the walkers fail at base — `watch/sync_protocol/fixtures/**`
  2. [ ] Declare `plannedSets` in `$defs.sessionExercise.properties` after `roundDurationSecs` — `envelope.schema.json` · `$defs.sessionExercise`
  3. [ ] Valid fixture `valid/session_snapshot_planned_sets.json`: P's slot, three planned rows, no entries
  4. [ ] Invalid `invalid/session_snapshot_planned_sets_bad.json`: `"reps": 0` → `constraint_violation`, reason contains `expected at least 1`
  5. [ ] Invalid `invalid/session_snapshot_planned_sets_unknown_key.json`: `"setNumber": 1` → `unexpected_field`
  6. [ ] Register all three in `fixtures/manifest.json` (valid entry with `scenario`, invalid entries with code + reason)
  7. [ ] Changelog row "1 (amended)" (pattern of the 2026-10-09 `roundDurationSecs` row) — `PROTOCOL.md` · Version history
  - Done criteria: `flutter test test/sync_protocol_fixtures_test.dart` green with the three new generated tests (S-001, :212-224); `swift test` in `watch/watchos`: both fixture walkers green; prove-red: before item 2 the unknown-key fixture is refused `unexpected_field`.
  - Predicted files: the six above, nothing else.
- Phase A2 — `crew-builder-app`; scope `lib/state/watch/watch_session_adoption_bridge.dart,test/watch_session_projection_test.dart,test/watch_session_adoption_bridge_test.dart` (after A1; parallel with B):
  1. [ ] Red group in `test/watch_session_projection_test.dart`: P's rows via `LoggedEntryRows.setObservations`, projected `plannedSets` equals the three-item list; rests at 1 and 2 → same list; reps-0 row → `{loadKg: 40.0}`; no `load` capability → `{reps: 10}`; `timed` slot → no key; no rows → no key (S-3621)
  2. [ ] Red test in `test/watch_session_adoption_bridge_test.dart`: twice → same revision; row 1 reps 10→12 → revision +1 and payload differs; again → same revision (S-3622, pattern S-1409 :1482)
  3. [ ] D-2 in `projectSession`'s loop after `_slotFor`, only when `_wireKind(slot) == PhoneEntries.setKind` — `watch_session_adoption_bridge.dart` · `projectSession` (:217-227)
  4. [ ] D-3: append `jsonEncode(slot['plannedSets'] ?? const [])` to the per-slot string — `watch_session_adoption_bridge.dart` · `_ladderOf` (:536-548)
  5. [ ] Re-read the whole-slot readers (S-1411 :1519; parity :2479/:2613) and migrate any a set-row fixture breaks — `test/*`
  - Done criteria: `flutter test test/watch_session_projection_test.dart test/watch_session_adoption_bridge_test.dart` green; S-3621/S-3622 proven red at base; `flutter analyze` not above 182.
  - Predicted files: the three in scope, nothing else.
- Phase B — `crew-builder-watch`; scope `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift,watch/watchos/Sources/WatchSessionEngine/WatchLoggingView.swift,watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift` (after A1; parallel with A2; only one of A2/B runs a full suite):
  1. [ ] Red `WatchPlannedSetsTests.swift`: S-3623 (P, no entries → reps 10 / weight 40, caption "Set 1 of 3"; log 12/45 → planned set 2; log → set 3; third log → last-logged 8/42.5, "Set 4 of 4")
  2. [ ] Red: S-3624 (one phone entry → "Set 2 of 3"), S-3625 (no key → nil caption; timed slot with key → nil; item without `loadKg` → weight 0; without `reps` → old chain), S-3626 (lbs display, stored 45), S-3627, S-3628, S-3631, S-3632
  3. [ ] D-4: `plannedSets`, `setsHeld`, the planned branch before the `lastLogged ?? target` chain — `WatchLoggingState.swift` · `initialValue(for:)` (:545)
  4. [ ] D-5: `setCaption` — `WatchLoggingState.swift`; the header line after the name, before `roundLine` — `WatchLoggingView.swift` · `header` (:101)
  5. [ ] Old-behaviour guards green unchanged: `WatchLoggingSurfacesTests` S-001 trio, `WatchPhoneEntriesTests` testS145, `WatchLoggingTimersTests` reps field
  - Done criteria: `swift test` in `watch/watchos` green, not below 580 plus new; S-3623..S-3626 red at base; the S-001 carry-over test stays green.
  - Predicted files: the three in scope, nothing else.
- Phase D — `crew-docs-keeper` (after A2 and B):
  1. [ ] `docs/watch_session_sync.md`: the projection row (:24) and the planned-rows paragraph (:70-73) gain the plannedSets sentence + the new test names
  2. [ ] Confirm `docs/watch_session_capture.md` and `docs/state_management/watch_surface.md` state nothing now false (grep run: neither describes the wrist's starting values) — no edit expected
  3. [ ] Write the plan's `.evidence.md`: baselines, red→green rows, mutation results
  - Done criteria: every behaviour sentence names an existing test; docs stay below 52 KB.

Parallelism: A1 serial first (the declared field is what lets the wrist's gate accept the snapshot and what both walkers prove). A2 and B run in parallel after A1 — disjoint write scopes (`lib/`+`test/` vs `watch/watchos/`). D waits for both.

### Proof list (mutation per guard, by line and substring)

- S-3620: delete the `plannedSets` property block in `envelope.schema.json` → the valid fixture is refused `unexpected_field`; change `"minimum": 1` on `reps` to `"minimum": 0` → the bad fixture validates.
- S-3621: delete the `slot['plannedSets'] = …` assignment in `projectSession` → the key disappears; `if (reps >= 1` → `if (reps >= 0` → the skipped row projects `{"reps":0,…}`; `if (load != 0` → `if (load >= -200` → a 0 load projects `loadKg: 0.0`.
- S-3622: drop the `'${jsonEncode(slot['plannedSets'] ?? const [])}'` segment from `_ladderOf` (:544-546) → the revision does not move on a reps edit.
- S-3623: "ignore plannedSets in initialValue" (delete the planned branch) → reps 10 / weight 0 defaults; "setsHeld off by one" (`setsHeld` → `setsHeld + 1` in the planned index) → set 2's values shown for set 1; drop the `kind == "set"` filter in `setsHeld` → a non-set observation shifts the numbering.
- S-3624: in `setsHeld`, filter to the wrist's own records only (exclude snapshot-confirmed ids) → a phone-logged set stops counting, caption stays "Set 1 of 3".
- S-3625: "plannedSets for non-set slots" (drop the `effortKind == set` condition) → a timed slot shows a caption; accept an empty array → caption "Set 1 of 1" where nil is expected.
- S-3626: in `displayValue` (:649-654), return `String(format: "%.1f", value)` without `fromKilograms` → the lbs display shows 45.0.
- D-5: in `setCaption`, `max(plannedSets.count, setsHeld + 1)` → `plannedSets.count` → the extra set reads "Set 4 of 3".

## Progress / Assumption Log / Feedback / Open questions

### Progress

| Item | Result |
| --- | --- |
| A1 items 1–7 | pending |
| A2 items 1–5 | pending |
| B items 1–5 | pending |
| D items 1–3 | pending |

### Assumption Log

- A-1 The seed's test pointers re-read this run and match: `WatchPhoneEntriesTests.swift:410` `slot`, `WatchLoggingTimersTests.swift:35` slot with `roundDurationSecs:`, `SyncProtocolFixturesTests.swift:37,55`, `test/sync_protocol_fixtures_test.dart:212-224`.
- A-2 `WatchLoggingView` has no Swift test (grep `.fields` over the test target shows no view test); the caption is tested through `setCaption` only, as D-5 states.

### Feedback

Review: `2026-10-15-36b-planned-sets-plan.review.md` (APPROVE WITH FIXES: 1 blocker, 2 major, 2 minor).
- [x] 1 (blocker): doc + code comment claimed a loadKg-less row falls to the chain; now says a planned load of 0 (doc `watch_session_sync.md`, comment in `WatchLoggingState.swift`).
- [x] 2 (major): `testS3625APlannedRowWithoutALoadShowsZero` made non-vacuous (a 40 kg phone entry precedes it); lead mutation W6 fails it.
- [x] 3 (major): S-3630 added (`S-3630 a set the user adds mid-session joins the planned sets`); lead mutation P5 (cap at three) fails it.
- [x] 4 (minor): reps-less row now also covers the "last logged" half (reps 7).
- [x] 5 (minor): `testS3632ADrillSlotOnTheWireIgnoresTheKey` added.

### Open questions

1. D-3's parenthetical reason — "the revision is what the wrist's replace-structure rule needs" — is imprecise: `applySnapshot` (`WatchSessionEngine.swift:487-532`) compares no revision; its only gates are the schema gate (`applyMessage` :442) and the foreign-session refusal (:502-506), and a same-session snapshot with an unchanged revision is applied wholesale (claim b, S-3629). The decision itself (append `plannedSets` to `_ladderOf`) is kept: the rise is what keeps "a changed ladder states a newer revision" uniform (D-1410's principle, pinned by S-1409/S-3622). Proposed wording: "(the revision is what keeps the phone's stated revision monotonic against the wrist's own announcements, and what S-3622 pins)".
2. RESOLVED by the lead: this plan's scenario ids were renumbered from S-3701..S-3713 to S-3620..S-3632 (S-3701..S-3714 belong to the accent plan 23d and S-3901..S-3905 to the units change); manifest `scenario` fields use the new ids.
3. `test/watch_session_projection_test.dart:2479` and `:2613` record `jsonEncode(payload)` into `parity` but no test compares the recorded values (grep `parity` → 3 hits, all assignments) — a pre-existing dead assertion, untouched here.
4. `docs/watch-app-setup-and-qa.md:213` ("What the wrist cannot do yet") still lists the kilograms-labelling gap the 2026-10-14 units amendment closed — pre-existing drift outside this plan's surface; flagged for the docs keeper's next pass.
