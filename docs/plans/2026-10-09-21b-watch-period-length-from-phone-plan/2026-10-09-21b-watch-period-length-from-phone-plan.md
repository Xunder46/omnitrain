# Plan 21b — the watch counts a period down from the phone's number

> Status: CLOSED — built in three phases (contract, phone senders, wrist); independent review round 1 CHANGES_REQUESTED (one prose blocker), findings 1–3 fixed, finding 4 (Wear client keeps its own preset) left open on purpose
> Next handoff: @code-reviewer (Phase 2 complete — the phone sends the number). Phase 3 (@developer, the wrist reads it) is
> still to run.
> Binding conventions: `docs/global_conventions.md`; `docs/README.md` (docs index), `docs/documentation_standard.md` (doc rules), `watch/sync_protocol/PROTOCOL.md` (the wire contract this plan amends).
> Series: `docs/plans/2026-10-08-18-watch-qa-index.md` (row 21b). Follows plan 21 (`2026-10-09-21-watch-timed-work-plan`). Base: `.work/watch-21b/base.txt`.
> Evidence: `2026-10-09-21b-watch-period-length-from-phone-plan.evidence.md` · Review: `…-plan.review.md` (both beside this file).
> Track: sync contract (`watch/sync_protocol/`, `watch/contract/`) as an additive field, its first consumers on both sides: phone senders (`lib/`) and the Apple Watch client (`watch/watchos/`). Docs.

## Goal (owner, 2026-10-09)

A sports or martial-arts period counts down from the number the phone has for that exercise; the wrist cannot change it. Plan 21 left the wrist on a fixed
3:00 preset because a slot on the wire carries no length. This plan adds the length to the wire and makes the wrist read it.

## Acceptance criteria

1. A round exercise started on the wrist from a **routine** counts down from the routine effort's round length (the phone's routine target).
2. A round exercise in a **session the phone holds and pushes** (snapshot, `exercise_push`, `add_exercise`) counts down from the length the phone's own round control would count down from for that effort.
3. A round exercise picked on the wrist for a **free workout** counts down from that exercise's default period length (soccer half, boxing round) the phone has.
4. No length known anywhere → the wrist keeps today's 3:00 (plan 21's preset). The wrist never offers a way to change the length.
5. The readout before Start shows the length ("40:00"), the countdown runs from it, and the end-of-countdown haptic fires as today. A timed (count-up) or drill effort is unaffected.
6. Both validators, the schema, the shared fixtures and `PROTOCOL.md` agree; `swift test`, `flutter test` and the watch scheme build stay green.

## Decision Ledger (seeded; do not edit, renumber or delete — append only)

- **D-1400** One new **optional** field, `roundDurationSecs` (integer, minimum 1), on two schema objects: `$defs.sessionExercise` (`watch/sync_protocol/schemas/envelope.schema.json:90`) and
  `$defs.catalogExercise` (`:67`). Both have `additionalProperties: false`, so the field MUST be declared in the schema. It is the length of ONE round / period in seconds; it is omitted when
  unknown and ignored by a receiver for any effort that is not a round. Name follows `Exercise.defaultRoundDurationSecs` (`lib/data/models/models.dart:141`).
- **D-1401** Additive, no `protocolVersion` bump: the same stance as `effortKind` and the session-capture amendment — the two clients ship from this repository in one release (`PROTOCOL.md` ~:130). The `PROTOCOL.md` version-history table gets one row; no legacy handling for an older receiver.
- **D-1402** Routine path: `routines_down` already carries the plan — `targets.durationMs` for a round effort (`lib/core/utils/watch_reference_sync.dart:269`, `_wireTargetKey` maps `MetricIds.roundDuration` → `durationMs`, ms). The wrist builds the slot in
  `WatchRoutineEffort.slot` (`watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift:~125`). That slot gains `roundDurationSecs = durationMs / 1000` (rounded, min 1) **only** when `effortKind == "round"` and the target exists. No change to `routines_down`'s shape.
- **D-1403** Live-session path: `_slotFor` (`lib/state/watch/watch_session_adoption_bridge.dart:~466`) adds `roundDurationSecs` for an effort whose kind is `round`. The value is the length the phone's round control counts down from for that effort: the effort's own round-duration entry when it has one
  (`'round-duration'` in the workout entries, see `lib/features/session/workout_session_timer_mixin.dart:~315`), else `Exercise.defaultRoundDurationSecs`, else omitted. The planner pins the exact read (`WorkoutState` accessor) with file:line; it MUST be the one function the phone's round control uses, not a copy of the rule.
- **D-1404** Free-workout path: the catalog entries the wrist picks from (`_SyncedExercise`, `watch_reference_sync.dart:40`, built by `_ExerciseResolver.resolve`) gain `defaultRoundDurationSecs` read from `Exercise.defaultRoundDurationSecs`; on the wire it is `catalogExercise.roundDurationSecs`. `WatchCatalogExercise` (`WatchRoutineRecords.swift:19`) carries it and `toSlot` writes it into a slot **only** when the picked exercise's resolved effort kind is `round`.
- **D-1405** Wrist read: `WatchLoggingState` resolves the period length when Start is pressed and when the idle readout is shown: the current slot's `roundDurationSecs` × 1000, else the `roundPresetMs` init seam (plan 21, D-1314), else `WatchLoggingDefaults.roundDurationSeconds` × 1000. `plannedRoundMs` (a stored value set once) becomes this per-slot read, so jumping between exercises changes the number. Nothing else reads the default.
- **D-1406** Validation parity: the field is validated by the schema walkers of BOTH `lib/core/sync_protocol/message_validator.dart` and `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift` (planner: say whether they read the shared schema file or carry a copy, with file:line, and update every copy). A zero, a negative, a non-integer or a string value is rejected by both.
- **D-1407** Fixtures: the shared valid fixtures that carry session slots / catalog exercises get one round slot with `roundDurationSecs` and one without; the rejection cases get the four bad values. Fixture files live in `watch/sync_protocol/fixtures/` and `watch/contract/`.
- **D-1408** Out of scope: any wrist control to change the length, pause/resume, a different length per period of the same exercise, the phone UI, 19c, and the Dart Wear client (`lib/watch/`) beyond what its tests need to stay green.

### Appended decisions (planner, 2026-10-09 — appended after D-1408, seeded entries untouched)

- **D-1409** The exact read behind D-1403, in `_slotFor` (`lib/state/watch/watch_session_adoption_bridge.dart:468`
  `_slotFor(SegmentEffort effort, WorkoutState target)` — it already holds `target`, so no new parameter):
  `final rounds = target.getRoundsForEffort(effort.id)` (`workout_state.dart:86` → `timer_manager.dart:41`, `List<RoundInstance>`,
  `RoundInstance.plannedDurationSecs` is `int` seconds); then
  `final secs = rounds.isNotEmpty ? rounds.last.plannedDurationSecs : target.getExercise(effort.exerciseId)?.defaultRoundDurationSecs`
  (`workout_state.dart:92` → `session_core.dart:145`, the same row `_slotFor` already reads for `name`/`capabilities`).
  Emitted **iff** `effort.effortKind == BlockTypes.round` (`lib/core/constants/block_types.dart:20`) and `secs != null && secs >= 1`.
  The last step of `SessionCore.addEntry`'s chain — `WorkoutConstants.defaultRoundDurationSecs`
  (`session_core_entry.dart:135-147`, 180 s) — is deliberately **not** reproduced: the phone's global default is the same 3:00 the
  wrist already presets, so the field is omitted instead of pinning it (`S-1402` keeps its meaning). *Derived from D-1403
  ("the one function the phone's round control uses"): `addEntry` reads `rounds.last.plannedDurationSecs` first for exactly this
  reason. Vetoable — if the owner wants the 180 s global default on the wire too, that is a superseding entry.*
- **D-1410** The length is part of the ladder's identity: `_ladderOf` (`watch_session_adoption_bridge.dart:530-541`) appends
  `':${slot['roundDurationSecs'] ?? ''}'` to each slot's segment, so a length-only change makes `_countRevision` (`:511-513`)
  state a newer revision. Reason: `_countRevision`'s own contract ("a ladder that has not changed keeps the revision already
  stated", `:495-497`) — the wrist renders the length, so a changed length is a changed ladder; without this a phone-side edit
  is invisible to a revision-gating peer.
- **D-1411** The catalog emission rule behind D-1404's phone half: `_fallbackJson`
  (`lib/core/utils/watch_reference_sync.dart:143-153`) writes `'roundDurationSecs'` **iff** the resolved exercise's
  `defaultRoundDurationSecs != null && >= 1`, independent of its capabilities — `catalogExercise` declares no effort kind
  (PROTOCOL.md, "Exercise identity"), so the emission cannot depend on one; the wrist decides at pick time (D-1404, D-1413).
  `_SyncedExercise` (`:40`) gains the field, filled once per message in `_ExerciseResolver.resolve` (`:55-72`) from the
  `await _repository.getExercises()` pass it already makes.
- **D-1412** One capability→kind resolution on the wrist. `WatchLoggingState.kindPrecedence` (`WatchLoggingState.swift:200`)
  and the resolution in `effortKind` (`:~365`) move to `public enum WatchEffortKind`
  (`WatchLoggingState.swift:26-40`) as `static func resolved(_ capabilities: [String]) -> String?`, keeping the precedence list
  verbatim (`["hold","rounds","reps","sets","load","time","distance"]`, mirroring `ModalityConfig.effortKindFromMetric`).
  `WatchLoggingState.effortKind` and `WatchCatalogExercise.toSlot` both call it, so the wrist can never resolve a picked
  exercise to one kind for display and another for the length. The `effortKindParity` cases of
  `watch/contract/watch_start_paths_contract.json` stay the pin on both stacks
  (`test/watch_session_start_test.dart:1010`, `WatchSessionStartPathsTests.swift:925`).
- **D-1413** `WatchCatalogExercise.toSlot(sessionExerciseId:effortKind:roundDurationSecs:)`
  (`watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift:60-77`) writes the field iff the kind governing the slot
  is `round` — the passed `effortKind` when it is one (`WatchEffortKind.declared.contains`, `:38-40`; the routine path), else
  `WatchEffortKind.resolved(capabilities)` (the free-workout pick, `WatchStartPaths.swift:386`) — and a length is known
  (`roundDurationSecs`, min 1). `WatchRoutineEffort.slot` (`:123`) passes
  `(targets["durationMs"] as? NSNumber)?.intValue` divided by 1000 (min 1) only when `effortKind == "round"` (D-1402);
  the pick passes the catalog exercise's own value. `init?(slot:)` (`:43`) reads it back, so a wrist-built slot round-trips.
- **D-1414** Fixture register rules (D-1407): the new cases are **new files** and no existing fixture's `expected` changes —
  `valid/session_snapshot_round_length.json`, `valid/routines_down_round_length.json`,
  `invalid/session_snapshot_round_length_{zero,negative,fractional,string}.json`, each with exactly one row in
  `watch/sync_protocol/fixtures/manifest.json` (`valid` rows: `path`/`type`/`scenario`/`note`; `invalid` rows add
  `expectedCode`/`expectedReasonContains`). Codes follow the precedents at `manifest.json:236-248`: negative →
  `constraint_violation` / `"expected at least"`, non-integer (`12.5`, `"2400"`) → `invalid_type` / `"expected integer"`.
  `watch/contract/watch_start_paths_contract.json` gains one `roundRoutine` key (a `routines_down` message whose round effort
  carries `targets.durationMs: 600000`, plus the expected slot with `roundDurationSecs: 600`); both suites read named keys only
  (`test/watch_session_start_test.dart:70` `_contract()`, `WatchSessionStartPathsTests.swift:146` `startContract()`), so an
  added key is inert for the suite that does not read it.

## Core scenarios (seeded; each states why it is red without the change)

- **S-1400 Slot field travels.** A snapshot slot `{sessionExerciseId: "sx-soccer", exerciseId, name: "Soccer", capabilities: ["time","rounds"], effortKind: "round", roundDurationSecs: 2400}` validates in both validators; with `roundDurationSecs: 0`, `-5`, `12.5`, `"2400"` both reject it at `$.payload.session.exercises[0].roundDurationSecs` (or the schema's own path). *Red today:* the field is an undeclared property → the valid one is rejected too.
- **S-1401 Wrist counts down from the slot.** Sports session, round slot with `roundDurationSecs: 2400`: idle `model.workReadout == "40:00"`, Start at 10:00:00 creates a round timer with `plannedDurationMs == 2_400_000`, remaining at 10:10:00 is 1800 s. *Red today:* the preset is 180 s.
- **S-1402 No number, no change.** The same slot without the field keeps `"3:00"` and `plannedDurationMs == 180_000`; and a slot with `roundDurationSecs` on a **timed** effort leaves the count-up readout `0:00` with no planned duration. Negative guard.
- **S-1403 The number follows the slot.** Two round slots (2400 s and 600 s); jump from the first to the second: idle readout changes `"40:00"` → `"10:00"`; a started period on the first is not re-timed by the jump (the menu is locked while it runs, plan 21).
- **S-1404 Routine effort.** `routines_down` round effort with `targets.durationMs: 600000`: the wrist's slot has `roundDurationSecs == 600`; an effort of kind `timed` with `durationMs` does NOT get the field; a round effort with no `durationMs` target gets none.
- **S-1405 Phone sends it for a live session.** Dart: a workout whose Soccer effort has `Exercise.defaultRoundDurationSecs == 2400` and no entry override → `_slotFor` includes `roundDurationSecs: 2400`; with an entry override of 900 → 900; a `timed` effort → key absent; an exercise with no default and no entry value → key absent. *Red today:* never emitted.
- **S-1406 Free workout from the catalog.** `routines_down`'s referenced exercise Soccer (default 2400) arrives; the wrist's picker builds the round slot with `roundDurationSecs == 2400`; Squat (a set) → no field. *Red today:* the catalog entry has no field.

### Appended scenarios (planner, after S-1406)

### S-1407: The routine keeps the phone's number through the start paths
- Fixture: `watch/contract/watch_start_paths_contract.json` key `roundRoutine` — one routine
  `routine-soccer`, one segment, one effort `eff-soccer-half` (`exerciseId: ex-soccer`, capabilities
  `["time","rounds"]`, wire `effortKind: "round"`, `targets: {rounds: 2, durationMs: 600000}`), plus its fallback
  entry `ex-soccer` (`capabilities: ["time","rounds"]`, `roundDurationSecs: 2400`); `expectedSlots[0]` carries
  `roundDurationSecs: 600`. Also the stored-catalog path: the same `routines_down` written to a
  `WatchRoutineCatalogRecord` and read back.
- Trigger: `startFromRoutine("routine-soccer")` from a wrist holding nothing; then the same, after a relaunch that
  reads the catalog row instead of the message.
- Flow: `routines_down` → `WatchRoutinesDown` → `WatchRoutineEffort.slot` → the session's ladder.
- Expected outcome: the created slot is `roundDurationSecs == 600` in both runs (the stored row carries the raw
  catalog maps through `WatchRoutineCatalogRecord.toJson`/`fromJson`), and the wrist's idle readout for it is `"10:00"`.
- Edge case of: S-1404

### S-1408: A non-round kind never gets the field
- Fixture: an `amrap` session effort on the phone whose exercise capabilities are `["time","rounds"]` (its wire kind is not
  declared, so the receiver resolves `round`), with a round-duration entry of 900 s; an `interval` routine effort
  (`_wireEffortKind`, `watch_reference_sync.dart:220-232`) with `targets.durationMs: 300000`; and its mirror in
  `valid/routines_down_round_length.json`.
- Trigger: `projectSession(null)` on the phone; the wrist starting that routine; the wrist picking an `interval`-kind exercise.
- Flow: `_slotFor` kind test (D-1409) → `_wireEffortKind` (`round`/`amrap` are one wire kind) → `WatchCatalogExercise.toSlot`
  kind test (D-1413).
- Expected outcome: the AMRAP slot has no `roundDurationSecs` (the phone's own round control does not count an AMRAP down:
  `_getEffortTargetDuration` returns 0 for a kind that is not `timed`/`drill`/`round`,
  `workout_session_timer_mixin.dart:300-318`), and the interval effort — which travels with the wire kind `timed` — gets none
  either; its wrist readout stays the count-up `0:00`.
- Edge case of: S-1405, S-1404

### S-1409: A length-only change moves the revision
- Fixture: the same round slot projected twice — first with rounds `[{planned 180}]`, then, with nothing else changed, the
  stored round re-timed to `[600]` (the phone's own round editor, `WorkoutState.setRoundDuration`).
- Trigger: `projectSession(null)` before and after the edit.
- Flow: `_slotFor` → `_ladderOf` (D-1410) → `_countRevision`.
- Expected outcome: the first projection's revision is `n`; the second is `n + 1`; a third identical projection is still `n + 1`
  (D-1410 + the seeded `_countRevision` contract), and `roundDurationSecs` in the second projection is `600`.
- Edge case of: none

### S-1410: A wrist snapshot carries the number back and changes nothing
- Fixture: a wrist that started a free workout, picked Soccer (`roundDurationSecs: 2400`), and sends its snapshot with the
  slot `sx-ex-soccer` carrying `roundDurationSecs: 2400`; the phone holds the same session with the same slot at 2400.
- Trigger: the phone validates and applies the wrist's snapshot; the mirror compares shapes (`_shapeDiffers`,
  `lib/state/watch/live_session_mirror_state.dart:707-732`).
- Flow: `WatchCatalogExercise.init?(slot:)` (D-1413) keeps the value → the wrist's snapshot → the phone's validator → `_sameSlots`.
- Expected outcome: the snapshot validates (the field is declared on `sessionExercise`, D-1400); `_sameSlots` — which compares
  `sessionExerciseId`/`exerciseId`/`name` only — reports no disagreement, so a phone and a wrist that agree on four fields and
  differ on the length do not answer each other for ever (the documented reason at `:697-701`); the phone's next projection
  restates its own number, which is the correction.
- Edge case of: S-1400

### S-1411: The same number twice is the same bytes
- Fixture: one session with a round slot at 2400 s; the wrist's picker for the same catalog exercise.
- Trigger: `projectSession(null)` twice with no change between them; `toSlot` twice on the same `WatchCatalogExercise`.
- Flow: `_countRevision` (D-1410) → `WatchCatalogExercise.toSlot` (D-1413).
- Expected outcome: two projections are equal maps (`roundDurationSecs: 2400` both times) and the second states the same
  revision; two slots are equal maps. No dictionary-order or rounding drift.
- Edge case of: S-1401

### S-1412: The ends of the range
- Fixture: round slots with `roundDurationSecs: 1` and `roundDurationSecs: 86400`, in both schema objects
  (`sessionExercise` and `catalogExercise`), plus the wrist rendering each.
- Trigger: both validators on the two values; Start on each slot.
- Flow: schema `minimum: 1` (D-1400) → the wrist's read (D-1405).
- Expected outcome: both validate (no maximum); the readouts are `"0:01"` and `"24:00:00"`; `plannedDurationMs` is `1000` and
  `86_400_000`; and `0` (the value `minimum` rejects) is the only boundary the invalid fixtures need.
- Edge case of: S-1400, S-1401

## Feature Invariants (only the ones that bite here)

- **Wire additivity**: a field a receiver does not know is never a reason to reject a message the schema declares optional, and
  no `protocolVersion` bump (D-1401). The two clients ship from this repository in one release.
- **One number per length**: the phone is the only source (acceptance 4) — the wrist never invents one beyond the plan-21 preset
  and never offers a control (`WatchMenuTests` pin the menu's rows; no new row may appear).
- **Kind agreement**: the kind that decides whether a slot carries a length is the same resolution that decides how the wrist
  renders the slot (D-1412) — one resolver, two callers.
- **Repository parity**: `HiveWorkoutRepository` is the runtime everywhere (web included); `MockWorkoutRepository` must return the
  same `Exercise.defaultRoundDurationSecs` for the same seed, or the Dart tests lie about what the phone sends.
- **Schema contract**: `scripts/sqlite_schema.sql` / `scripts/sqlite_seed.sql` are unaffected — `roundDurationSecs` is a wire field
  whose local source (`Exercise.defaultRoundDurationSecs`) already exists in them (`scripts/sqlite_schema.sql:151`). No SQL change,
  so `test/db_seed_test.dart` must stay green untouched.
- **Layer boundary**: `lib/state/watch/` reads `WorkoutState` accessors, never a repository or Hive box (D-1409 goes through
  `WorkoutState.getRoundsForEffort` / `getExercise`).

## Existing-Functionality Impact

| Touched surface | What already reads it (grep that found it) | Effect of the change | Guarded by |
|---|---|---|---|
| `$defs.sessionExercise` (`envelope.schema.json:~87-100`) | `grep -n "additionalProperties" watch/sync_protocol/schemas/*.json` → the walkers at `message_validator.dart:798` and `SyncProtocolValidator.swift:677` read the schema **document** they are handed; `grep -rn "envelope.schema.json" lib/ test/ watch/` → `test/helpers/sync_protocol_harness.dart:54`, `test/sync_protocol_fixtures_test.dart` (`_loadSchemaDocuments`), `Fixtures.schemaDocuments()` | the field becomes legal; **no validator copy exists to update** (answers brief check 1) | S-1400 |
| `$defs.catalogExercise` (`:~62-70`) | same walkers; `_fallbackJson` produces the only production instance (`grep -n "'capabilities':" lib/core/utils/*.dart lib/state/watch/*.dart`) | additive; the catalog gains an optional number | S-1406, S-1412 |
| `_slotFor` (`watch_session_adoption_bridge.dart:468-483`) | `grep -rn "projectSession(" lib/ test/` → `projectSession` :204 (the one caller, inside the class), `test/watch_session_projection_test.dart:2026,2249,2345`, `test/watch_session_adoption_bridge_test.dart:805,835,868,1138` | slots gain a key; those tests read fields or ids, never whole-map equality (`watch_session_projection_test.dart:635-650` is per-field) | S-1405, S-1409 |
| `_ladderOf` (`:530-541`) | `grep -n "_ladderOf\|_projectedLadder" lib/state/watch/*.dart` → `_countRevision` :511-513 only | a length-only change states a newer revision; revision assertions at `test/watch_session_adoption_bridge_test.dart:717-730,786` and `test/live_mirroring_test.dart` must be re-run | S-1409, S-1411 |
| `live_session_mirror_state._sameSlots` (`:722-732`) | `grep -n "_sameSlots\|_shapeDiffers" lib/state/watch/live_session_mirror_state.dart` → `_shapeDiffers` :707, itself called from the disagreement path | **deliberately unchanged**: a length difference is not a shape disagreement, for the documented reason at `:697-701` (a comparison that disagreed about a field two peers may hold differently would answer for ever); the phone's projection is the correction | S-1410 |
| `_SyncedExercise` / `_ExerciseResolver` (`watch_reference_sync.dart:40-72`) | `grep -rn "_SyncedExercise\|_ExerciseResolver" lib/` → that file only (private typedef) | the record gains a field; every construction site is in the same file | S-1406 |
| `_fallbackJson` (`:143-153`) | `grep -n "fallbackExercises" lib/ watch/` → produced here, parsed by `WatchRoutinesDown.init(envelope:)` and asserted by `test/watch_reference_sync_test.dart` | the catalog JSON gains a key; contract/fixture-based assertions are per-field | S-1406, S-1411 |
| `WatchCatalogExercise` (`WatchRoutineRecords.swift:19-77`) | `grep -rn "WatchCatalogExercise" watch/watchos/Sources watch/watchos/Tests` → `WatchRoutinesDown.init(envelope:)`/`init(catalog:)`, `WatchRoutineEffort.catalogExercise` :131, the pick path `WatchStartPaths.swift:386`, `WatchConnectivityBridgeTests`, `WatchSessionStartPathsTests` | the struct gains a validated-through field; `toSlot` gains a parameter with a default, so existing call sites stay source-compatible; `WatchConnectivityBridgeTests.swift:380` compares against contract slots that are set/timed (no round), so it stays green | S-1406, S-1407 |
| `WatchRoutineEffort.slot` (`:123`) | `grep -rn "\.slot\b" watch/watchos/Sources/WatchSessionEngine` → the start paths' routine branch | the routine's round length reaches the slot; `WatchSessionStartPathsTests.swift:312-319,572-575` compare id/name/capabilities/effortKind per field | S-1404, S-1407 |
| `WatchLoggingState.plannedRoundMs` (`:144,:178-186`) | `grep -rn "plannedRoundMs" watch/watchos` → `workRemainingSeconds` :334-339, `startWork` :349-357, both private neighbours | becomes a per-slot computed read; the `roundPresetMs` seam (plan 21 D-1314) is preserved as the second source | S-1401, S-1402, S-1403 |
| `WatchTimedWorkTests` / `WatchCaptureContractTests:334` | `grep -rn "roundPresetMs" watch/watchos/Tests` | these pass no slot field, so `180_000` / `"3:00"` assertions keep passing; the round-duration dial (`WatchMetricStepping.roundDuration`) is untouched by this plan | S-1402 |
| `WatchSessionEngine.applySnapshot` (`:479-560`) | `grep -n "exercises: exercises" watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift` → the ladder is stored verbatim; revision is stored, never gated on | the field survives a snapshot with no engine change (answers brief check 3's round-trip half) | S-1410 |
| `lib/watch/start/watch_routine_catalog.dart` (Dart Wear client) | `grep -rn "toSlot\|catalogExercise" lib/watch/` → `WatchRoutineEffort.slot`, `WatchCatalogExercise.toJson` | out of scope per D-1408: its `toSlot` does not write the field, so a Wear session's round counts from its own preset; the shared suites stay green because they read named keys and per-field assertions (`test/watch_session_start_test.dart:377-400`) | open — Q2 |
| `watch/sync_protocol/fixtures/manifest.json` | `grep -rn "manifest.json" test/ watch/watchos/Tests` → `test/sync_protocol_fixtures_test.dart` (completeness + reconciliation convergence), `SyncProtocolFixturesTests.swift`; `test/watch_transport_test.dart:863` walks a **hardcoded** list, so it ignores new files | every new file needs exactly one row; the manifest is the register both stacks walk | S-1400, S-1404 |
| `PROTOCOL.md` | `grep -rn "PROTOCOL.md" docs/ watch/ lib/` → the docs that cite it; `test/docs_indexing_contract_test.dart` covers `docs/` only, not `watch/sync_protocol/` | one rule sentence + one version-history row; no size test applies (~60 KB file) | S-1400 |
| Debug entry points that hand-build slots: `lib/state/watch/live_session_mirror_debug_main.dart:48-60`, `lib/watch/debug/watch_logging_debug_main.dart:37-64`, `lib/watch/debug/watch_session_debug_surface.dart:43-53` | `grep -n "sessionExerciseId" lib/state/watch/live_session_mirror_debug_main.dart lib/watch/debug/*.dart` | each builds a literal map with no `roundDurationSecs`, and the field is optional — they stay silent and need no edit (they are runnable mains, not shipped surfaces) | none needed (optional field) |
| The Dart Wear engine's slot store: `lib/watch/session/watch_session_engine.dart:385,1070` (`_catalog`, `exercises` verbatim), `lib/watch/logging/watch_logging_state.dart:625` | `grep -n "sessionExerciseId" lib/watch/session/watch_session_engine.dart lib/watch/logging/watch_logging_state.dart` | the engine keeps whole slot maps, so an incoming field survives it untouched; only `test/watch_session_start_test.dart`'s named-key expectations are affected | S-1406, S-1411 |

### Producer and JSON-pin inventory (brief checks 3 and 4; planner, read, not inferred)

**Producers of a slot / catalog exercise.** Phone: `_slotFor` (`:468`, the only production slot builder for live sessions),
`_fallbackJson` (`:143`, the only catalog builder). The `pushExercise`/`addExercise` entry points of
`lib/state/watch/live_session_mirror_state.dart:366,406` are pass-throughs for a caller-supplied slot and are called only from
tests (`grep -rn "pushExercise\|addExercise" lib/ test/`), so they need no change; a test that pushes its own slot decides
whether *it* carries the field. Watch: `WatchCatalogExercise.init(json:)`/`init?(slot:)`/`toJson()` and
`WatchRoutineEffort.slot` (`WatchRoutineRecords.swift:19-77,123`); `WatchRoutinesDown.init(envelope:)`/`init(catalog:)`. Dart
Wear client: `WatchCatalogExercise.toSlot` / `toJson()` / `WatchRoutineEffort.slot`
(`lib/watch/start/watch_routine_catalog.dart:63-76,118-131`) — stays silent (D-1408), and it *could* compute the value from
`targets` it already parses (`fromJson` keeps `targets`, `:86-95`), which is what makes the follow-up cheap (Q2).

**Round-trip.** A wrist snapshot's slots are stored verbatim by `WatchSessionEngine.applySnapshot:479-560` and sent with the
field intact; the phone's validator accepts it (S-1400) and `_sameSlots`/`_shapeDiffers` (`live_session_mirror_state.dart:707-732`)
compare only `sessionExerciseId`/`exerciseId`/`name`, so the field neither drops silently nor starts a disagreement loop (S-1410).

**Tests that pin slot / catalog JSON (brief check 4): none compare a whole slot or catalog map.**
`grep -rn "jsonEncode(" test/` gives only entry-list and preference comparisons; the relevant per-field pins, all of which stay
green because they read named keys, are: `test/watch_session_projection_test.dart:635-650` (per-field), `:1376`
(`jsonEncode(payload)` only to assert the wrist's entry id is **absent**), `:1622-1627` (entries byte-identical twice plus
`second['revision'] == first['revision']` — an idempotency pin D-1410 must not move, since nothing changes between the two
projections), `test/watch_reconciliation_cross_stack_test.dart` (id/exerciseId/position/revision/status/timers),
`test/watch_session_adoption_bridge_test.dart:805-814` (ids) and `:717-730,786` (revisions — the ones D-1410 can move when a
length changes), `test/watch_session_start_test.dart:377-400` and the Swift bridge/start-path comparisons
(`WatchConnectivityBridgeTests.swift:380`, `WatchSessionStartPathsTests.swift:312-319,572-575`) — all per-field against
contract slots that are `set`/`timed`. `WatchFileStoreTests.swift` / `WatchRestPingTests.swift` compare `toJson()` per key, not
whole maps. No `toSlot`/`toJson` whole-map equality exists on either side. **One pre-existing oddity, recorded not fixed:**
`test/watch_session_projection_test.dart:2217` collects a `parity` map of `jsonEncode(payload)` per store but never asserts it
(the only writes are `:2263,:2397`), so the intended cross-store byte check is inert today.

## Requirements

1. The field exists, is optional, and both validators accept/reject it identically (D-1400, D-1406, D-1407).
2. Every producer that can know the number sends it: routine targets (`routines_down`), the phone's live projection, and the
   catalog default the picker reads (D-1402, D-1403, D-1404, D-1409, D-1411, D-1413).
3. The wrist reads it per slot, before Start and at Start, and keeps its preset when it is absent (D-1405).
4. Nothing else changes: no new wrist control, no phone UI, no `protocolVersion` bump (D-1401, D-1408).

## Phase outline (planner expands into items with file + symbol, Done Criteria, Predicted Files; none over 8 items)

- **Phase 1 — contract (dba/developer):** D-1400, D-1401, D-1406, D-1407: schema, both validators if they hold a copy, fixtures, `PROTOCOL.md` + version-history row; S-1400 in both stacks.
- **Phase 2 — phone senders (developer):** D-1403, D-1404 (`_slotFor`, `_SyncedExercise`/`_ExerciseResolver`, the routines/catalog builder); S-1405, and the Dart half of S-1406.
- **Phase 3 — wrist (developer):** D-1402, D-1404 (Swift side), D-1405: `WatchCatalogExercise`, `WatchRoutineEffort.slot`, `WatchLoggingState`; S-1401…S-1404, the Swift half of S-1406; then docs (`watch_surface.md` remove-before-add, `watch-app-setup-and-qa.md`, QA index row).

## Iteration 1 — expanded phases

Dependency graph: Phase 1 → Phase 2 → Phase 3 (each phase's tests need the previous phase's artifact: Phase 2's validators
need the schema, Phase 3's fixtures/contract need the phone's emission rule). Phase 1 is the only phase an agent can run with
no other phase done; Phase 2's `_ladderOf` item (1.2) is independent of 1.3-1.6 and could run first, but the phase's Done
Criteria are cleaner as one run. Phase 3.1 (`WatchEffortKind.resolved`) is independent of everything else and can be done first
inside its phase.

### Phase 1: the contract — schema, fixtures, PROTOCOL.md (@dba)

1. [x] Add `"roundDurationSecs": { "type": "integer", "minimum": 1 }` to `$defs.sessionExercise` properties, immediately after
   `effortKind` — `watch/sync_protocol/schemas/envelope.schema.json` · `$defs.sessionExercise`. Keep `additionalProperties:
   false` and the property order style of the neighbours. — done; `additionalProperties: false` kept.
2. [x] Add the same property to `$defs.catalogExercise` — `envelope.schema.json` · `$defs.catalogExercise` (D-1400: both objects
   are closed, so without this the valid fixture is rejected). — done; after `capabilities` (that def declares no `effortKind`).
3. [x] New fixture `watch/sync_protocol/fixtures/valid/session_snapshot_round_length.json` (copy the shape of
   `valid/session_snapshot.json`): `exercises[0]` a round slot — `sessionExerciseId: "sx-soccer"`, `exerciseId: "ex-soccer"`,
   `name: "Soccer"`, `capabilities: ["time","rounds"]`, `effortKind: "round"`, `roundDurationSecs: 2400`; `exercises[1]` the same
   shape without the field; entries empty · plus a `valid` row in `watch/sync_protocol/fixtures/manifest.json`
   (`{"path": "valid/session_snapshot_round_length.json", "type": "session_snapshot", "scenario": "S-1400", "note": …}`).
   — done; slot 2 is `sx-soccer-plain` (same shape, field omitted), `entries: []`, `timers: {}`.
4. [x] New fixture `watch/sync_protocol/fixtures/valid/routines_down_round_length.json`: one routine with three efforts — a
   round effort `targets {rounds: 2, durationMs: 600000}`, a round effort with `targets {rounds: 3}` and no `durationMs`, and a
   wire-`timed` effort with `durationMs: 300000`; `fallbackExercises` holds `ex-soccer` (`["time","rounds"]`,
   `roundDurationSecs: 2400`) and `ex-plank` (no number) · plus its `manifest.json` `valid` row (`scenario: "S-1404"`),
   keeping the schema's "every referenced exercise is in the fallback list" rule (`invalid/routines_down_unlisted_fallback_exercise.json`).
   — done; the fallback-coverage rule passes (both referenced ids are listed).
5. [x] Four rejection fixtures + rows: `invalid/session_snapshot_round_length_zero.json` (`expectedCode: "constraint_violation"`,
   `expectedReasonContains: "expected at least"`), `…_negative.json` (same codes), `…_fractional.json` and `…_string.json`
   (`expectedCode: "invalid_type"`, `expectedReasonContains: "expected integer"`) — each a copy of fixture 1.3 with
   `roundDurationSecs` set to `0`, `-5`, `12.5`, `"2400"` · plus four `manifest.json` `invalid` rows with
   `scenario: "S-1400"`, mirroring `manifest.json:236-248`. If the walker's actual code/reason text differs from these
   precedents, the row must state what the validator returns — a mismatched row is a failing test, not a passing one.
   — done; the walkers return exactly the precedents (`constraint_violation` / `expected at least 1`; `invalid_type` / `expected integer`).
6. [x] One normative sentence in the `effortKind` neighbourhood of the "Exercise identity (normative)" list: a slot MAY carry
   `roundDurationSecs` (integer, minimum 1) — the length of ONE round or period in seconds as the phone knows it, omitted when
   unknown, ignored by a receiver for any effort that is not a round, and never settable from the wrist — `watch/sync_protocol/PROTOCOL.md`
   (after the `effortKind` bullet, `:~203-215`). — done.
7. [x] One row in the version-history table: `| 1 (amended) | 2026-10-09 | The length of a period: a `sessionExercise` or
   `catalogExercise` MAY carry `roundDurationSecs` … additive for the same reason as the 2026-09-25 amendment; pinned by
   `fixtures/valid/session_snapshot_round_length.json`, `fixtures/valid/routines_down_round_length.json` and four
   `invalid/session_snapshot_round_length_*` fixtures |` — `PROTOCOL.md` version history (`:~580-598`, matching that table's
   prose style and length). — done; appended after the 2026-10-08 row, naming the walker groups/tests that exist.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart test/watch_wire_limits_test.dart test/rest_is_count_up_contract_test.dart test/docs_indexing_contract_test.dart`,
`.github/copilot/scripts/macos/gateway.sh swift-test`. Both validator suites walk the register, so S-1400's accept/reject pair is
the fixture rows themselves. Record in the evidence file: the two validator files read the schema document rather than a copy
(method call sites below), so **no validator code changes** in this phase.

**Predicted Files**: `watch/sync_protocol/schemas/envelope.schema.json`,
`watch/sync_protocol/fixtures/valid/session_snapshot_round_length.json`,
`watch/sync_protocol/fixtures/valid/routines_down_round_length.json`, four
`watch/sync_protocol/fixtures/invalid/session_snapshot_round_length_*.json`, `watch/sync_protocol/fixtures/manifest.json`,
`watch/sync_protocol/PROTOCOL.md`. (Nothing under `lib/`, `watch/watchos/` or `watch/contract/` — a hit outside this list is a
finding.)

**No-copy proof for D-1406 (planner, verified by reading):** `lib/core/sync_protocol/message_validator.dart:89-97` builds its
walker from the schema documents it is constructed with, and `:798` reads `additionalProperties` and the property maps out of
that document; `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift:94-99` and `:677` do the same. The
documents come from disk — `test/helpers/sync_protocol_harness.dart:54`, `test/sync_protocol_fixtures_test.dart`
(`_loadSchemaDocuments()`), Swift `Fixtures.schemaDocuments()` — so the schema file is the single property-list copy. No test
pins the whole property list of `sessionExercise`: `test/watch_wire_limits_test.dart` reads `properties.loadKg`,
`test/rest_is_count_up_contract_test.dart` reads `$defs.timer`.

### Phase 2: the phone sends the number (@developer)

1. [x] Emit it for a round effort exactly as D-1409 pins — `lib/state/watch/watch_session_adoption_bridge.dart` · `_slotFor`
   (`:468-483`): read `target.getRoundsForEffort(effort.id)`, take `rounds.last.plannedDurationSecs` when the list is not
   empty, else `target.getExercise(effort.exerciseId)?.defaultRoundDurationSecs`, and add
   `if (secs != null && secs >= 1) 'roundDurationSecs': secs` only when `effort.effortKind == BlockTypes.round`. No
   `WorkoutConstants.defaultRoundDurationSecs` step; no repository access.
2. [x] Make the length part of the ladder's identity — `watch_session_adoption_bridge.dart` · `_ladderOf` (`:530-541`): append
   `':${slot['roundDurationSecs'] ?? ''}'` to each slot's segment (D-1410).
3. [x] Carry the exercise's default into the sync view — `lib/core/utils/watch_reference_sync.dart` · `_SyncedExercise`
   (`:40-44`) gains `int? defaultRoundDurationSecs`, filled in `_ExerciseResolver.resolve` (`:55-72`) from the
   `await _repository.getExercises()` pass it already makes (`exercise.defaultRoundDurationSecs`), and returned in the record.
4. [x] Emit it on the catalog entry — `watch_reference_sync.dart` · `_fallbackJson` (`:143-153`): add
   `if (exercise.defaultRoundDurationSecs != null && exercise.defaultRoundDurationSecs! >= 1) 'roundDurationSecs': exercise.defaultRoundDurationSecs!`
   per D-1411. `_segmentsJson` needs no change: a round routine effort already travels as `targets.durationMs`
   (`_wireTargetKey` `:269`, `_targetValue` `:283-292`).
5. [x] Tests, Dart half — `test/watch_session_adoption_bridge_test.dart` (harness `_Phone`, `_seedPhoneSession`; add a round
   exercise via the seeded repository): `S-1405 phone sends it for a live session` (2400 from the exercise default; 900 after the
   round is re-timed; absent for a `timed` effort; absent for an exercise with no default and no rounds — the last needs the
   harness's `setExerciseCapabilities` call for `["time","rounds"]`), `S-1409 a length-only change moves the revision` (project,
   re-time the round through `WorkoutState`, project again → `+1`; project a third time → unchanged), `S-1411 the same number
   twice is the same bytes`, `S-1408 a non-round kind never gets the field` (AMRAP effort at 900 s → absent) ·
   `test/watch_reference_sync_test.dart` `S-1406 the catalog carries the default` (built from a repository whose Soccer has
   `defaultRoundDurationSecs: 2400` → the fallback entry has it; Squat → absent).
6. [x] Regression run and record (counts + any expectation touched): `test/watch_session_projection_test.dart`,
   `test/live_mirroring_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`, `test/watch_transport_test.dart`,
   `test/phone_manage_bridge_test.dart`, `test/watch_session_start_test.dart`, `test/sync_protocol_fixtures_test.dart` — the
   revision assertions at `test/watch_session_adoption_bridge_test.dart:717-730,786` are the ones D-1410 can move.
7. [x] Evidence: fill this plan's `.evidence.md` Phase 2 rows with the pasted test counts, the red→green pairs for S-1405/S-1406,
   and any Assumption Log entry this phase needed.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh lint`,
`.github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_reference_sync_test.dart test/watch_session_projection_test.dart test/live_mirroring_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_transport_test.dart test/watch_session_start_test.dart test/sync_protocol_fixtures_test.dart`,
`.github/copilot/scripts/macos/gateway.sh test --plain-name "Mock"` for the touched widget suites if any tap-driven test is added
(it is not expected: all of Phase 2 is state-level), and `flutter analyze` compared with the recorded baseline count.

**Predicted Files**: `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/core/utils/watch_reference_sync.dart`,
`test/watch_session_adoption_bridge_test.dart`, `test/watch_reference_sync_test.dart`, and this plan's `.evidence.md`.

### Phase 3: the wrist reads the number (@developer)

1. [x] One capability→kind resolver — `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` ·
   `WatchEffortKind` (`:26-40`) gains `static func resolved(_ capabilities: [String]) -> String?` carrying
   `WatchLoggingState.kindPrecedence` (`:200`) verbatim; `WatchLoggingState.effortKind` (`:~365`) and the new `toSlot` call it
   (D-1412). The precedence list and its comment move with it.
2. [x] The catalog exercise carries the phone's number — `watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift` ·
   `WatchCatalogExercise` (`:19-77`): `public let roundDurationSecs: Int?` (init parameter, written by `init(json:)` from
   `(json["roundDurationSecs"] as? NSNumber)?.intValue` when `>= 1`, by `init?(slot:)` the same way, and by `toJson()` only when
   non-nil), plus `Equatable` stays synthesized.
3. [x] Write it into the slot only for a round kind — `WatchRoutineRecords.swift` · `WatchCatalogExercise.toSlot`
   (`:60-77`) gains `roundDurationSecs: Int? = nil`; the slot gets `"roundDurationSecs"` iff the governing kind is round —
   `effortKind` when `WatchEffortKind.declared.contains(effortKind)`, else `WatchEffortKind.resolved(capabilities)` — and the
   length is `>= 1` (defaulting to the exercise's own value). D-1413.
4. [x] The routine's target as the slot's length — `WatchRoutineRecords.swift` · `WatchRoutineEffort.slot` (`:123`): pass
   `effortKind == WatchEffortKind.round ? roundSeconds(from: targets["durationMs"]) : nil`, where `roundSeconds` is
   `max(1, ms / 1000)` and nil when the target is missing or not numeric (D-1402; the app's own routine validator requires both
   `rounds` and `round-duration` for a round effort, `lib/core/services/demo_routines_validator.dart:198-202`).
5. [x] Read it per slot at Start and in the idle readout — `WatchLoggingState.swift` · `plannedRoundMs` (`:144`, set once at
   `:178-186`) becomes a private computed property: `Int(slot?["roundDurationSecs"] as? NSNumber) * 1000` when that is `>= 1000`,
   else the stored `roundPresetMs` captured in `init` (`:172-186`), else `WatchLoggingDefaults.roundDurationSeconds * 1000`
   (`:23-24`). `workRemainingSeconds` (`:334-339`) and `startWork` (`:349-357`) keep reading the same name (D-1405).
6. [x] Tests, Swift half — `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`: S-1401 (round slot at
   2400 → idle `"40:00"`, Start at 10:00:00 → `plannedDurationMs == 2_400_000`, remaining 1800 s at 10:10:00), S-1402
   (absent → `"3:00"`/`180_000`; a `timed` slot carrying the field → count-up `0:00`, no planned duration; keep the plan-21
   `roundPresetMs:` case green), S-1403 (jump 2400 → 600 changes the idle readout; a running period is not re-timed), S-1412
   (`1` → `"0:01"`/`1000`, `86400` → `"24:00:00"`/`86_400_000`) ·
   `WatchSessionStartPathsTests.swift`: S-1404/S-1407 (start `routine-soccer` from the contract's new `roundRoutine` key →
   `roundDurationSecs == 600` in the slot; the stored-catalog run after a relaunch); S-1406 (a pick of Soccer →
   `2400` in the slot, a pick of Squat → absent) · `WatchConnectivityBridgeTests.swift`: S-1410 (a wrist snapshot whose slot
   carries the field is accepted and applied) and the existing `:380` comparison stays per-field.
7. [x] Docs: in `docs/state_management/watch_surface.md` (`:436-438`) replace "a period counting down from the wrist's preset"
   with the phone's number — **remove before adding** (the file is near its 52 KB band) and keep the remove-before-add
   accounting in the evidence file · in `docs/watch-app-setup-and-qa.md` (`:608-613`) replace/extend one QA step: a round
   exercise started on the wrist shows the phone's period length (40:00 for a soccer half), and an exercise with no number
   still shows 3:00 · add the `21b` row to the PR table of `docs/plans/2026-10-08-18-watch-qa-index.md` (after the `21` row:
   plan, status, the checks run, the counts).
8. [x] Evidence and residue sweep: fill the `.evidence.md` Phase 3 rows; then
   `.github/copilot/scripts/macos/gateway.sh git-diff` plus a grep for `plannedRoundMs` and `roundDurationSecs` across
   `watch/watchos/Sources` and `lib/` showing every reader of the old preset is gone or intentionally kept, and that no test
   still asserts a fixed 3:00 for a slot that carries a number.

**Done Criteria** (run until green): `.github/copilot/scripts/macos/gateway.sh swift-test`,
`.github/copilot/scripts/macos/gateway.sh test test/watch_logging_surfaces_test.dart test/docs_indexing_contract_test.dart test/sync_protocol_fixtures_test.dart test/watch_session_start_test.dart test/watch_reconciliation_cross_stack_test.dart`,
`.github/copilot/scripts/macos/gateway.sh lint`. The watch app target is built by the governor with `xcodebuild`; no agent runs it.

**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift`,
`watch/contract/watch_start_paths_contract.json`, `docs/state_management/watch_surface.md`,
`docs/watch-app-setup-and-qa.md`, `docs/plans/2026-10-08-18-watch-qa-index.md`, this plan's `.evidence.md`.
`WatchStartPaths.swift` is predicted **only** if item 3's default parameter is not enough (it should be: the pick path calls
`toSlot(sessionExerciseId:)` at `:386`).

## Files Affected (whole feature)

- `watch/sync_protocol/schemas/envelope.schema.json`, `fixtures/manifest.json`, `fixtures/valid/*round_length.json`,
  `fixtures/invalid/session_snapshot_round_length_*.json`, `PROTOCOL.md`
- `lib/state/watch/watch_session_adoption_bridge.dart`, `lib/core/utils/watch_reference_sync.dart`
- `watch/watchos/Sources/WatchSessionEngine/{WatchRoutineRecords.swift,WatchLoggingState.swift}`,
  `watch/contract/watch_start_paths_contract.json`
- Tests: `test/{watch_session_adoption_bridge_test.dart,watch_reference_sync_test.dart}`, the Swift suites named per phase
- Docs: `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`,
  `docs/plans/2026-10-08-18-watch-qa-index.md`
- Read-only dependents (must stay green, no edit): `lib/state/watch/live_session_mirror_state.dart`,
  `WatchSessionEngine.swift`, `lib/watch/start/watch_routine_catalog.dart`, `test/watch_session_projection_test.dart`,
  `test/live_mirroring_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`, `test/watch_transport_test.dart`

## Notes

- Intermediate states: after Phase 1 the schema accepts the field and both validators pass (S-1400, S-1412 green) while nothing
  emits it — S-1401…S-1406 are still red. After Phase 2 the phone emits it and the wrist still ignores it: every wrist-side
  scenario stays red, and the Dart suites are green. Phase 3 turns the wrist scenarios green. No state in which both sides
  disagree about the wire.
- The wrist never gates on the revision, so a stale wrist applies any snapshot it receives; D-1410 matters for the peers that
  compare revisions (the mirror's `_shapeDiffers`, `live_session_mirror_state.dart:707-720`) and for honest revision storytelling.
- `_shapeDiffers`/`_sameSlots` are deliberately untouched (D-1410's rationale): the correction path is the phone's projection,
  not a disagreement about a field two peers may hold differently.
- Plan 21's `roundPresetMs` seam stays: it is the second source in D-1405, it is what plan 21's tests exercise, and it is the
  one place a future length choice would come from.
- The round-duration *dial* (`WatchMetricStepping.roundDuration`, `WatchCaptureContractTests:334`) is the wrist's own logging
  value, a different thing from this wire field, and stays as it is.
- The Dart Wear client keeps its behaviour (D-1408): its `toSlot` writes no field, so nothing in the shared suites changes; the
  divergence is raised as an open question rather than planned.
- Legacy handling: none (D-1401). An older watch build rejects a slot with the new field under `additionalProperties: false`;
  the two clients ship from this repository in one release.

## Feedback

[empty — the only trigger to re-invoke the planner]

**Review round 1 — see `2026-10-09-21b-watch-period-length-from-phone-plan.review.md`. Fix checklist (findings 1–3 fixed in fix
round 1, finding 4 left open on purpose — the round-by-round record is in the evidence file):**
1. S-1412's expected readout is `"24:00:00"` (both clients print hours as `h:mm:ss`), not the minute-count form — corrected at
   `:166`, `:382` and the evidence row (`:193`), and pinned by `WatchLoggingTimersTests.testS1412TheEndsOfTheRangeCountDown`.
2. A third `roundDurationSecs: 86400` slot (`sx-marathon`) added to `valid/session_snapshot_round_length.json` so the Dart walker
   pins the schema's "no maximum", with that fixture's `manifest.json` note updated.
3. The two valid fixture names added to `test/watch_transport_test.dart:863`'s hardcoded list (that list is valid-only, so the
   four `invalid/` files stay out).
No code change was required by any item; the shipped behaviour and both suites are correct.

## Code pointers

`envelope.schema.json` :67 catalogExercise, :90 sessionExercise. `message_validator.dart` (slot checks ~:408, schema walker ~:798). `SyncProtocolValidator.swift` (~:293). `watch_reference_sync.dart` :40 `_SyncedExercise`, :55-72 `_ExerciseResolver`, :183 efforts, :269 `_wireTargetKey`.
`watch_session_adoption_bridge.dart` :~466 `_slotFor`. `workout_session_timer_mixin.dart` :~315. `effort_defaults.dart` :14-38. `WatchRoutineRecords.swift` :19 `WatchCatalogExercise`, :~125 `WatchRoutineEffort.slot`. `WatchLoggingState.swift` `plannedRoundMs`, `init(roundPresetMs:)`, `startWork`, `workRemainingSeconds`.

## Open questions (seeded)

- An older watch build receiving a slot with the new field would reject the message (`additionalProperties: false`); accepted under D-1401 (clients ship together).
- The phone's per-effort round length in a live session (D-1403) may live in more than one place; the planner reports which one the phone's own round control reads.

## Open questions (planner) — each with the default this plan proceeds on

1. **Last round or first round?** D-1409 sends the **last** round's `plannedDurationSecs`. The routines half of the app drafts a
   new round from `rounds.first` (`session_summary_builder.dart:224-227`), so the two paths can disagree once a user has re-timed
   a mid-session round. Default: last (it is what `SessionCore.addEntry` would create next, `session_core_entry.dart:135-140`).
   Owner may veto before Phase 2.
2. **Is the Dart Wear client (`lib/watch/`) in scope?** D-1408 says no. Its `toSlot`
   (`lib/watch/start/watch_routine_catalog.dart`) writes only id/name/capabilities/kind, so a Wear session's round counts from
   that client's own preset while the Apple Watch's counts from the phone's number — a divergence in user-visible behaviour, and
   the two clients otherwise mirror each other. It is left out because no shared test forces it (both suites read named contract
   keys and per-field expectations, `test/watch_session_start_test.dart:377-400`) and the owner's criteria speak of the wrist.
   Default: out of scope, recorded as a defect-free divergence; a follow-up plan adds it in three lines.
3. **An older watch build rejects the field** (`additionalProperties: false`). Default: accepted under D-1401 (clients ship
   together). No legacy handling planned.
4. **`test/watch_transport_test.dart:863` walks a hardcoded fixture list**, so it never sees the new files. Default: leave it —
   it pins transport framing, and `test/sync_protocol_fixtures_test.dart` / `SyncProtocolFixturesTests.swift` are the register's
   own walk. A reviewer may call this a finding; if so, the fix is one line in that list.
5. **Phase 1.5's expected codes** are copied from the `restPingSeconds` precedents (`manifest.json:236-248`:
   `constraint_violation` / `"expected at least"`, `invalid_type` / `"expected integer"`). Default: the row must state what the
   walker actually returns; if the phrasing differs, the implementer aligns the row with the walker (a mismatched row is a red
   test, never a fixture edit to match an implementation).
6. **An AMRAP effort gets no length** (S-1408) even though a receiver resolves `round` from its capabilities. Default: correct —
   the phone's own round control does not count an AMRAP down (`workout_session_timer_mixin.dart:300-318` returns 0 for a kind
   other than `timed`/`drill`/`round`), so the wrist keeps its preset for it.
7. **`roundDurationSecs` is seconds, `durationMs` is milliseconds** — one name carries two units across the two wire sources
   (D-1402 converts, `_wireTargetKey` `:269`). Default: keep both names (the seeded D-1400 fixes `roundDurationSecs`, and
   `durationMs` is the routine target's own key); Phase 1.6's protocol sentence states the unit explicitly.
8. **`test/watch_session_projection_test.dart:2217` collects a cross-store `parity` map that is never asserted** (only written,
   at `:2263,:2397`). Default: out of scope — it is pre-existing, unrelated to this feature, and adding the assertion is a
   separate two-line fix. Raised here so a reviewer reads it as known, not as drift this plan introduced.

## Progress

| Phase | Status |
|---|---|
| 1 | Complete |
| 2 | Complete |
| 3 | Complete |
| Fix round 1 | Complete |

Phase 1 items (all done — `watch/sync_protocol/` only): 1.1 `roundDurationSecs` on `$defs.sessionExercise`; 1.2 the same on
`$defs.catalogExercise`; 1.3 `valid/session_snapshot_round_length.json` (2400 + omitted) + row; 1.4
`valid/routines_down_round_length.json` + row; 1.5 four `invalid/session_snapshot_round_length_*` files + rows; 1.6 the
normative bullet in PROTOCOL.md; 1.7 the version-history row. Red→green in the evidence file.

Phase 2 items (all done — the two sender files and their two test files): 2.1 `_slotFor` emits the number (D-1409); 2.2
`_ladderOf` carries it (D-1410); 2.3 `_SyncedExercise.defaultRoundDurationSecs` resolved in one pass; 2.4 `_fallbackJson`
emits it (D-1411); 2.5 the five Dart tests (S-1405 ×2, S-1408, S-1409, S-1411) and S-1406; 2.6 the seven-file regression run;
2.7 evidence. Counts and the red→green pairs are in the evidence file: red `+33 -5`, green `+37`, regression `+300`, full
suite `+4238 ~1`, `lint` 196 (baseline). No `.swift`, schema or doc file was touched.

Phase 3 items (all done — the watch package, its three test files, and three docs): 3.1 `WatchEffortKind.resolved` carries the
precedence list; 3.2 `WatchCatalogExercise.roundDurationSecs`; 3.3 `toSlot` writes the key only for a round kind; 3.4
`WatchRoutineEffort.slot` passes the routine's own target; 3.5 `plannedRoundMs` is a computed per-slot read; 3.6 the Swift tests
(S-1401/S-1402/S-1403/S-1412, S-1404/S-1407, S-1406, S-1410); 3.7 the three doc edits; 3.8 evidence and residue sweep. Counts and
the red→green pair are in the evidence file: `swift-test` 429 tests / 0 failures (429 / 3 with the leftover mutation still
applied), the phase's five-file `test` set 197 / 0, the full suite `+4238 ~1`, `lint` 196 (baseline). `flutter run` is not
available in Copilot mode, so the governor or the owner exercises the wrist.

Fix round 1 items (all done — the review's findings 1–3; no code, schema or doc file): 1 the readout corrected from the
minute-count form to `"24:00:00"` in this plan (`:166`, `:382`) and the evidence row; 2 item 1.3's fixture now carries a third
slot, `sx-marathon` at `roundDurationSecs: 86400`, with its `manifest.json` note extended, so the Dart walker pins the schema's
"no maximum" (S-1412); 3 the two valid `round_length` fixture names added to `test/watch_transport_test.dart`'s hardcoded list
(valid-only pattern). Counts, the mutation check and the footprint are in the evidence file. Finding 4 (the Wear client keeps
its own preset) is left open on purpose.

## Assumption Log

- (governor) The three sources for the number (routine target, live-session effort, catalog default) are the governor's reading of "picked up from the phone numbers"; the owner can narrow it.
- (conductor) D-1409's value is the **last** round's `plannedDurationSecs`, else the exercise default. Options considered: the first round's length (the routines draft path uses `rounds.first`, `session_summary_builder.dart:224-227`), the exercise default only, and the full `SessionCore.addEntry` chain including the 180 s global default. Chosen because `addEntry` itself reuses `existingRounds.last.plannedDurationSecs` (`session_core_entry.dart:135-140`) — the number the phone would count the next round down from. Derived from an ambiguous seeded D-1403: **vetoable before Phase 2**.
- (conductor) The phone's global 180 s default is deliberately not put on the wire (D-1409). Options: send 180 so the wrist always has a number, or omit. Omitted, because it duplicates the wrist's own preset and would make S-1402's "no number, no change" unreachable.
- (conductor) The length joins the ladder identity (D-1410) instead of leaving `_ladderOf` alone. Options: rely on the wrist applying every snapshot it receives (true today — no revision gate) versus stating a new revision. Chosen because `_countRevision`'s contract is "the identity of the ladder as the wrist can see it", and the wrist renders the length; the cost is one extra revision on a length-only edit.
- (conductor) The capability→kind resolution is extracted to `WatchEffortKind.resolved` (D-1412) rather than copied into `WatchCatalogExercise.toSlot`. Options: a private copy in the model, or the shared static. Chosen for the "kind agreement" invariant (`effortKindParity` is the existing pin, `watch_start_paths_contract.json`).
- (conductor) New fixture files rather than mutations of `valid/session_snapshot.json` / `valid/routines_down.json` (D-1414). Options: extend the existing fixtures (they have contract twins whose expectations would move) or add files. Added files: every existing row's `expected`/`expectedCode` stays pinned, and the register accepts additions.
- (dba) The register's valid round fixture carries 2400 s and an omitted slot; S-1412's boundary values (1 and 86400) got no
  fixture in this phase. Options: a boundary fixture file (outside the phase's Predicted Files) or none. None: item 1.3 fixes the
  fixture's contents, and the boundary is the schema's `minimum: 1` with no maximum, exercised by the same walker.
- (dba) Valid item 1.3's second slot is `sx-soccer-plain` (same exercise, same shape, field omitted) so the register holds a
  before/after pair in one file; the plan said only "the same shape without the field".
- (conductor) `live_session_mirror_state._sameSlots` is left untouched (impact row). Options: add the length to the compared fields, or keep the three identity fields. Kept, because the file's own comment (`:697-701`) says a comparison that disagrees about a field two peers may hold differently answers for ever; the correction is the phone's projection.
- (developer) The tests re-time a round through `WorkoutState.updateRoundPlannedDuration` (`workout_state.dart:233`), not `setRoundDuration` (`:284`). Options: the plan's S-1409 text names `setRoundDuration`, which writes `actualDurationSecs`; `updateRoundPlannedDuration` writes `plannedDurationSecs`, the field D-1409 reads and the one `getRoundsForEffort` returns. Chosen so the test drives the value the wire carries; the round is added with `addRound` first because `updateRoundPlannedDuration` refuses a finished round.
- (developer) `_seedPhoneSession` gained an optional parallel `List<String> kinds = const []` (default = the existing `BlockTypes.set` for every effort) rather than a new seeding helper, so its nine existing callers are unchanged.
- (developer) The fixture repository is built inside the new group (`roundRepository()`): `ex-soccer` at `defaultRoundDurationSecs: 2400` with `[time, rounds]`, plus `ex-squat` re-declared `[time, rounds]` for the no-number case. Options: reuse the seeded Soccer Match (2700 s, and its capabilities are not round) or seed per test. Seeded per test, so the number in each assertion is the one the fixture states and no seeded row is re-used as a length.
- (developer) No `docs/` file was touched in Phase 2 (outside its Predicted Files). Options: extend `docs/state_management/watch_surface.md`'s "revision rises only when the ladder changes" sentence with the length case, or leave it. Left: no sentence there became false — the doc enumerates no slot field, `watch/sync_protocol/PROTOCOL.md` already carries the field (Phase 1's normative bullet), and Phase 3 item 7 owns that file's edit (it records the size before and after). The behaviour is pinned by `test/watch_session_adoption_bridge_test.dart` (`S-1409 a length-only change moves the revision`) and `test/watch_reference_sync_test.dart` (`S-1406 a round exercise's default travels, a set exercise's does not`), which Phase 3's doc pass can cite.
- (developer) The leftover mutation in `WatchRoutineRecords.swift:56` (`roundDurationSecs: nil`) was restored to the catalog read
  and no new mutation checks were run: S-1406/S-1407's catalog path cannot compile without the field it writes, so a
  `prove-red HEAD` there proves nothing. The red proof for S-1401/S-1404/S-1406 is the recorded pre-restore `swift-test`
  (429 tests, 3 failures), with the three filter re-runs green afterwards.
- (developer) The one other in-repo `MUTANT` string is a `-`/`+` diff quote in
  `docs/plans/2026-10-05-15a-watch-session-sync-pr1-plan/2026-10-05-15a-watch-session-sync-pr1-plan.evidence.md:736` — an earlier
  plan's mutation-check record. Left untouched: it records a past phase's proof, not residue in shipped code.
- (developer) `watch_surface.md` fits its 52 KB band by deleting the superseded
  `…testS1303APeriodCountsDownAndLogIsNotARoundButton` citation from the same sentence it rewrites (+109 bytes, 51,018 → 51,127).
  Options: split the page into a part page — a doc-structure change no phase predicted — or swap the citation. Swapped, because
  D-1402 supersedes exactly that sentence.
