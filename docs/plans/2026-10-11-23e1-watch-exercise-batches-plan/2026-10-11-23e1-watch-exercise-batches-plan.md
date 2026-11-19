# Plan 23e1: exercise batches on the wire, and the wrist that assembles them

Series: `docs/plans/2026-10-11-23e-watch-batched-exercise-list-series.md` (read it first; D-3801..D-3805 apply).
Base: `3fc1e256` (`.work/2026-10-11-23e1/base.txt`). Governor-seeded. Track: contract + watch (Swift wrist; Dart validator).

## Goal and acceptance (what the owner will see once 23e2 lands; in THIS PR nothing changes on screen)

1. The wire can carry the exercise list as batches of at most 100 (`exercises_down`) and a `routines_down` with no
   fallback list at all.
2. The wrist stores each batch as it arrives, in any order, and uses the new list only when every batch of one
   version is present. Until then it keeps the list it had. Closing the app half-way changes nothing: the next
   launch shows the old list, or the new one if it was complete.
3. When a list becomes active the wrist throws away every stored batch that is not part of it.
4. Every Sync request from the wrist says which list version it holds (omitted when it holds none).
5. The phone still sends the old full `routines_down` in this PR; the app behaves exactly as today.

## Decision ledger

- D-3810 Message `exercises_down`, phone to watch, payload (closed object, all required):
  `generatedAt` (timestamp), `catalogVersion` (string, minLength 1, maxLength 64), `batchIndex` (integer >= 0),
  `batchCount` (integer >= 1), `totalCount` (integer >= 1), `exercises` (array of `envelope.schema.json#/$defs/catalogExercise`,
  minItems 1, maxItems 100). Files: `watch/sync_protocol/schemas/messages/exercises_down.schema.json`; the `type` enum in
  `watch/sync_protocol/schemas/envelope.schema.json:~22`; `messageTypes` in `SyncProtocolValidator.swift:~49` and
  `lib/core/sync_protocol/message_validator.dart:~104`.
- D-3811 Semantic rules (both validators, code `semantic_violation`, same order and message text on both stacks):
  (a) `batchIndex < batchCount`; (b) `exercises.length <= totalCount` and `totalCount <= batchCount * 100`; (c) `exerciseId`s
  unique within the batch. Put them next to `fallbackCoverageRejections` (Swift `SyncProtocolValidator.swift:~192/522`,
  Dart `message_validator.dart:~297`).
- D-3812 `routines_down.fallbackExercises` becomes `minItems: 0` (schema line ~35); the coverage rule is unchanged (every routine
  exercise must be listed). Meaning in the schema/PROTOCOL text: "exercises the phone offers alongside the routines, always including every routine's
  own; the whole list may arrive separately as `exercises_down`". The existing invalid fixture
  `invalid/routines_down_empty_fallback.json` (routines [] and fallback []) turns into a VALID fixture
  `valid/routines_down_empty.json` ("you have no routines and nothing extra"): delete the invalid file, add the valid one, edit the manifest.
  Readers of the old fixture name to update: `watch/sync_protocol/fixtures/manifest.json`, `test/sync_protocol_fixtures_test.dart`,
  `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift`, PROTOCOL.md amendment row of 2026-10-11 (the "catalog with no routines" row names it),
  `watch/contract/watch_start_paths_contract.json` and `test/watch_start_paths_contract*` (grep the old file name, fix every hit).
- D-3813 Wrist storage: a new row kind `exercise_batch` (`StoredWatchRecord.exerciseBatch`, `recordType` "exercise_batch"):
  `recordId = "exb-<catalogVersion>-<batchIndex>"` (append is already idempotent per recordId and type, `InMemoryWatchSessionStore.append`,
  `FileWatchSessionStore.appendLocked`), `sessionId` "" like the catalog row, plus `catalogVersion`, `generatedAt`, `batchIndex`,
  `batchCount`, `totalCount`, `exercises` ([[String: Any]] in catalogExercise json). New field in `WatchStoreContents`
  (`exerciseBatches`, default empty; also in `isEmpty`), and in both `readAll` switches (InMemory and File). Files: `WatchRoutineRecords.swift`
  (next to `WatchRoutineCatalogRecord`), `WatchRecords.swift` (the `StoredWatchRecord` enum has ~9 switches: grep `routineCatalog` and add the case to each),
  `WatchSessionStore.swift`, `FileWatchSessionStore.swift`.
- D-3814 One new store operation, the only way batch rows leave:
  `pruneExerciseBatches(keepingVersion: String) async -> [String]` (record ids dropped): drops every `exercise_batch` row whose
  `catalogVersion != keepingVersion`; touches no other record kind; routine catalog rows are NOT pruned (their append-only property is pinned by
  `testS004SyncingAppendsARowAndRewritesNothing` and stays; after 23e2 those rows are small). Implement as the siblings are: `InMemory` removeAll;
  `FileWatchSessionStore` rewrites the file the way `pruneConfirmedLocked` does (read it and follow it exactly, including the torn-tail and marker handling).
  The two test doubles that conform to the protocol (`SuspendingStore` in `WatchEffortRatingTests.swift:160`, `ContendedWatchSessionStore`
  in `WatchSensorRecordingTests.swift:948`) must compile: forward to their inner store or return `[]`, as they do for the other prunes.
  The guard `testS004NoMutatingOperationExistsAnywhereInTheModule` (`WatchSessionEngineTests.swift:322`) lists the allowed names: add `pruneExerciseBatches`
  there ON PURPOSE and update its comment (the count of deliberate names and the gate sentence).
- D-3815 Assembly lives in `WatchSessionStartPaths` (`WatchStartPaths.swift`), next to `applyRoutinesDown`:
  `applyExercisesDown(_ envelope:) async -> WatchExerciseBatchResult` (`stored: Bool`, `activated: Bool`, `rejections`).
  Rules, in this order: (1) validate (`SyncProtocolValidator.incomingRejections`), refuse with rejections; (2) a batch older than the ACTIVE list
  (`generatedAt` earlier) is understood and dropped, nothing stored; (3) a batch whose `batchCount` or `totalCount` disagrees with a row already stored for the
  SAME version is refused whole (nothing stored; empty rejections list, like an unreadable catalog) — not a validator rule because it needs the store;
  (4) append the row (idempotent); (5) the version is COMPLETE when stored `batchIndex`es for it are exactly `0..<batchCount` and the exercise counts sum to `totalCount`;
  (6) if complete (and not already the active version): the active list = the batches' exercises concatenated in `batchIndex` order, active version/generatedAt set,
  then `pruneExerciseBatches(keepingVersion:)`. A batch that does not complete anything returns `stored: true, activated: false`.
- D-3816 `restore()` rebuilds the active list from the stored rows: among versions that are complete, the one with the greatest `generatedAt` (ties: greatest max row sequence); no
  complete version means no active list (not an error). Order matters: restore must not need the prune to have run (a kill between append and prune).
- D-3817 What the rest of the wrist reads: `exercisesVersion: String?` (active version, nil when none; public). `syncedFallback` becomes
  active-list exercises followed by the routine catalog's `fallbackExercises` not already present (dedupe by `exerciseId`, list first). Everything downstream
  (`fallbackExercises`, `addableExercises`, the free-workout picker) keeps using `deriveFallbackExercises`, so routine coverage and recents-first order are unchanged.
- D-3818 Routing and request: `WatchSyncOrchestrator.receive` routes `"exercises_down"` to `paths.applyExercisesDown(...)` and returns `result.stored`
  (`WatchSyncOrchestrator.swift:~157`). The transport protocol gains the version:
  `requestRoutines(since: Date?, exercisesVersion: String?) async` (Swift `WatchSyncTransport`, `WatchConnectivityBridge.requestRoutines`, and every Swift test double:
  `WatchSessionStartPathsTests.swift:41`, `WatchConnectivityBridgeTests.swift:197,1186,1240`); `WatchTransportRequest.routinesFrame(since:exercisesVersion:)`
  (`WatchConnectivityBridge.swift:59`) adds `"exercisesVersion"` only when non-nil; `sync(reconnect:)` passes `paths.exercisesVersion` (`WatchSyncOrchestrator.swift:94`).
  The Dart twin of the frame builder (`lib/core/platform/watch_transport.dart:~80`) and the phone's reading of it are 23e2 (the phone ignores an unknown key today, which is why 23e1 can ship alone).
- D-3819 Dart wrist client (`lib/watch`): untouched except that nothing may break: its orchestrator already ignores unknown types (`lib/watch/start/watch_sync_orchestrator.dart`, confirm).
- D-3820 The shared contract's `transportRequests` (`watch/contract/watch_start_paths_contract.json:346`) is NOT extended in 23e1: the Dart twin of the frame builder does not gain the key until 23e2 (`lib/core/platform/watch_transport.dart:73`), and a contract row one client cannot produce would describe a frame the phone never receives. S-3820 is pinned by a Swift-only test in `WatchConnectivityBridgeTests.swift`; 23e2 moves the pin into the contract when both stacks build the key. The existing S-102/S-103 pins are unchanged because the key is omitted while the wrist holds no list.
- D-3821 `pruneExerciseBatches` with an empty drop set returns `[]` and rewrites nothing (the guard `pruneSensorSamplesLocked` uses; unlike `pruneConfirmedLocked`, which compacts unconditionally). A prune that finds nothing is not a write.
- D-3822 The wrist's reference-data documentation goes to a new page `docs/state_management/watch_reference_data.md`, linked from `docs/state_management.md` (Pages table and Class → Page Lookup); `docs/state_management/watch_surface.md` gains nothing, so it stays clear of the docs-size ceiling. Every behaviour sentence on the new page names the test that pins it.
- D-3823 (added by the race fix) Completeness is judged on a read taken AFTER the append: `applyExercisesDown` re-reads the store's batch rows fresh after `store.append` and tests completeness and assembles the list on that read — never on the pre-append rows merged with the sent batch. Two frames of one version arriving interleaved (each `applyExercisesDown` task suspends inside the store between its read and its append) therefore still activate the list exactly once, in `batchIndex` order, by whichever task's append lands last. Pinned by S-3836.

## Scenarios (tests first; each must fail without the change)

Contract (both stacks walk `watch/sync_protocol/fixtures/manifest.json`: `test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift`):
- S-3801 valid `valid/exercises_down.json`: version "v1-4-a1b2c3d4", batchIndex 0, batchCount 2, totalCount 4, two exercises (a set `["sets","reps","load"]`, a period `["time","rounds"]` with `roundDurationSecs: 2400`).
- S-3802 valid `valid/exercises_down_single_batch.json`: batchCount 1, batchIndex 0, totalCount 3, three exercises.
- S-3803 valid `valid/routines_down_empty.json` (D-3812).
- S-3804 invalid `exercises_down_batch_index_out_of_range.json` (batchIndex 2, batchCount 2): `semantic_violation`.
- S-3805 invalid `exercises_down_total_below_batch.json` (totalCount 1, two exercises): `semantic_violation`. And `exercises_down_total_above_capacity.json` (batchCount 1, totalCount 101): `semantic_violation`.
- S-3806 invalid `exercises_down_duplicate_exercise.json` (same exerciseId twice): `semantic_violation`.
- S-3807 invalid `exercises_down_empty_batch.json` (`exercises: []`) and `exercises_down_missing_version.json`: `constraint_violation` / the missing-required code (read how existing invalid fixtures name `expectedCode`).
- S-3808 (unit test, both stacks, no fixture file): the S-3801 message with 101 exercises (build programmatically; totalCount 101, batchCount 2) is rejected `constraint_violation` (maxItems 100).
Wrist (Swift, `WatchSessionStartPathsTests.swift` + `WatchFileStoreTests.swift`; use the harness there; build messages with a small helper that returns an `exercises_down` envelope for (version, generatedAt, index, count, total, ids)):
- S-3810 two batches arriving 1 then 0: after batch 1 `exercisesVersion == nil` and `fallbackExercises` is what it was; after batch 0 the list is batch 0's exercises then batch 1's (assert the id order), `exercisesVersion == "v1"`.
- S-3811 a half sync keeps the old list: v1 active (2 batches); v2 batch 0 of 2 arrives: `exercisesVersion == "v1"`, the exercise ids are still v1's, `result.stored == true`, `activated == false`.
- S-3812 v2 completes: version "v2", v2's list, and `store.readAll().exerciseBatches` contains only v2's two rows (v1's gone).
- S-3813 relaunch: a fresh `WatchSessionStartPaths` over the same store after (a) v1 complete + v2 batch 0 only restores v1; (b) after v2 completes restores v2; (c) v2 complete rows and v1 rows both still present (prune never ran: write them straight into the store) restores v2 (greatest generatedAt).
- S-3814 the same batch delivered twice stores one row and activates once (`activated` true only the first time the set completes).
- S-3815 a batch of version "v1" claiming batchCount 3 when stored v1 rows say 2: refused, not stored, the stored set unchanged.
- S-3816 a complete list older than the active one (generatedAt earlier) is dropped: nothing stored, version unchanged.
- S-3817 a routine whose exercise is not in the active list still appears in `fallbackExercises`/`addableExercises` (coverage from `deriveFallbackExercises`), and an exercise in both the list and `routines_down.fallbackExercises` appears once.
- S-3818 `orchestrator.receive(exercises_down)` routes to the paths (returns true for a stored batch) and an invalid one (index out of range) returns false with nothing stored.
- S-3819 `orchestrator.sync()` calls the transport with `exercisesVersion == nil` before any list and `"v1"` after one is active (test double records it).
- S-3820 `WatchTransportRequest.routinesFrame(since: nil, exercisesVersion: "v1")` equals `["request": "routines", "exercisesVersion": "v1"]`; with nil the key is absent; with a `since` both keys are present.
- S-3821 stores: `pruneExerciseBatches(keepingVersion: "v2")` on rows (v1 x2, v2 x1, plus a session row and a routine catalog row) returns the two v1 ids, leaves the v2 row and every other kind; File store: the same after closing and reopening the store on the same directory; a torn tail line before the prune is handled as `pruneConfirmed`'s test does (copy that test's pattern).
Guards:
- S-3822 `testS004NoMutatingOperationExistsAnywhereInTheModule` still passes with the one added name and fails if a fourth, unlisted prune is added (the existing test already pins that; just keep it honest).
- Dart: `test/sync_protocol_fixtures_test.dart` walks the new manifest entries (no new test needed) and one new Dart test for S-3808 next to it.
- S-3830 a single-batch list completes immediately: batchCount 1, batchIndex 0, totalCount == exercises.count → stored, activated, `exercisesVersion` set (the S-3802 fixture through the harness).
- S-3831 a version whose stored indexes are complete but whose counts do not sum to `totalCount` never activates and never prunes: `exercisesVersion` stays at the previous list; a corrected re-send for the SAME version is refused by D-3815 rule (3) (same recordId), so the wedge is bounded by D-3802 — the phone derives the version from content, so a fix arrives under a new version.
- S-3832 restore with batch rows stored but no complete version: no active list, no error, `exercisesVersion == nil`, `fallbackExercises` still the catalog's (write two v2 rows, batchCount 2, only index 0, straight into the store).
- S-3833 a batch whose `generatedAt` EQUALS the active list's is not dropped by rule (2) (only strictly earlier is dropped): it stores, and if it completes a version that is not the active one it activates.
- S-3834 `routines_down` with non-empty routines and `fallbackExercises: []` is still refused by the coverage rule (`semantic_violation`): the relax does not open a coverage hole (Swift unit test in `SyncProtocolValidatorTests.swift`; the existing invalid fixture `routines_down_unlisted_fallback_exercise.json` already walks both stacks for the coverage family).
- S-3835 `pruneExerciseBatches` on a store with no batch rows returns `[]` and writes nothing (file store: the file's bytes are unchanged — pins D-3821).
- S-3836 (added by the race fix, pins D-3823) two batches of one version arrive interleaved — each `applyExercisesDown` task suspends inside the store between its read and its append (harness over `SuspendingStore`, batch 0 parked mid-call, batch 1 delivered to completion, then the first resumed): the list still activates exactly once, `exercisesVersion` set and the exercises in `batchIndex` order. Red before the fix (mutation E13): the completeness read taken before the append saw neither task's row, so nothing activated.
- S-3837 (added by the guards fix, pins the index-set half of D-3815 rule 5) a gap in the indexes never activates: version "v3", `batchCount: 3`, `totalCount: 2`, batches 0 and 2 delivered (index 1 never arrives) — both stored, neither activates, `exercisesVersion == nil`, the store holds exactly `exb-v3-0` and `exb-v3-2`. Red without the `Set(rows.map(\.batchIndex)) == Set(0..<batchCount)` clause (mutation E1): the two delivered exercises sum to `totalCount`, so the count-only check activated a gapped list.

## Phases (serial: A, B, C, D; same Swift package, so builders do not overlap)

| # | Agent | Scope | Items |
|---|---|---|---|
| A | crew-builder-watch | `watch/sync_protocol/**`, `watch/watchos/**`, `watch/contract/**`, `test/sync_protocol_fixtures_test.dart`, `test/watch_start_paths_contract*`, `docs/**` | schema + envelope enum + manifest + 8 fixtures (S-3801..3807) + routines_down relax and fixture move (D-3812) + Swift validator (type + D-3811) + PROTOCOL.md amendment row + S-3808 Swift test |
| B | crew-builder-app | `lib/core/sync_protocol/**`, `test/**` | Dart validator (type + D-3811) + S-3808 Dart test; run Dart fixtures test |
| C | crew-builder-watch | `watch/watchos/**` | D-3813 record + store contents + readAll in both stores + D-3814 prune in both stores and the two doubles + S-004 guard edit + S-3821 |
| D | crew-builder-watch | `watch/watchos/**`, `docs/**` | D-3815..3818 assembly, restore, fallback union, routing, request frame; S-3810..3820; docs (watch_surface.md has 44 KB of 51 KB: put new text in a new section of `docs/state_management/watch_sensors.md`'s sibling or a new `docs/state_management/watch_reference_data.md` page and link it from `docs/state_management.md`, remove nothing else) |

## Verification (governor, observed)
`swift test --package-path watch/watchos`, `flutter analyze` (196), `flutter test` (+4267 ~1 plus new), `xcodebuild` watch scheme, invariant grep, docs guards. Mutations (governor applies, restores byte-identical):
activate on the first batch (drop the completeness check); concatenate in arrival order; prune keeps nothing / keeps everything; restore ignores completeness; request frame always omits the version;
validator accepts `batchIndex == batchCount`; coverage of routine exercises dropped from the union. (owner) Nothing visible yet; the device check belongs to 23e2.

## Feature invariants that bite here

- The store stays append-only with exactly the prunes the S-004 guard lists; `pruneExerciseBatches` joins that list on purpose (D-3814, S-3822).
- A half-received list never becomes active and never changes what the user sees (Goal 2, D-3803, S-3811).
- Versions are opaque strings the wrist echoes back; the wrist never derives version semantics beyond `generatedAt` ordering (D-3802, D-3815 rule 2).
- Routine coverage survives the union change: every exercise a routine references stays loggable offline, recents-first order unchanged (D-3817, S-3817, existing S-003 tests).
- Both validators print the same rejection text for the same defect, in the same order (convention read off `fallbackCoverageRejections`, Swift `SyncProtocolValidator.swift:522` / Dart `message_validator.dart:650`).
- `HiveWorkoutRepository`/`MockWorkoutRepository` parity is untouched: 23e1 writes no Dart-side persistence (D-3819; the Dart wrist client's store is a different interface, `lib/watch/session/watch_session_store.dart:63`).

## Existing-functionality impact

| Touched surface | Readers found (search run) | Effect | Guarded by |
|---|---|---|---|
| `StoredWatchRecord` enum (`WatchRecords.swift:675`) | 8 exhaustive switches in the same file (`recordType` 697, `recordId` 711, `sessionId` 725, `recordedAt` 739, `sequence` 753, `withSequence` 767, `toJson` 781, `fromJson` 794); `readAll` switches `WatchSessionStore.swift:169`, `FileWatchSessionStore.swift:124`; non-exhaustive `if case` accessor `WatchStartPaths.swift:488`; test constructors `WatchFileStoreTests.swift:49,441`, `WatchMenuTests.swift:176,199,624` | the new case must be added to the 8 + 2 switches or the module does not compile; the `if case` accessors and test constructors compile unchanged | S-3821 (round-trip), compile |
| `WatchStoreContents` (`WatchSessionStore.swift:19`) | `isEmpty` (same file); `fileFamilyJSON` (`WatchFileStoreTests.swift:44`) | new `exerciseBatches` field, default empty; `isEmpty` gains the conjunct; `fileFamilyJSON` gains the family so store-equality tests can tell batch rows apart | S-3821 |
| `WatchSessionStore` protocol (`WatchSessionStore.swift:80`) | conformers: `InMemoryWatchSessionStore` (`WatchSessionStore.swift:133`), `FileWatchSessionStore` (`FileWatchSessionStore.swift:21`), `SuspendingStore` (`WatchEffortRatingTests.swift:160`), `ContendedWatchSessionStore` (`WatchSensorRecordingTests.swift:948`) | new requirement breaks the two test doubles until they forward; S-004 guard's allowed set gains the name | S-3822, S-3821 |
| `routines_down` schema `fallbackExercises` (`routines_down.schema.json:35`) | both validators (schema-driven); manifest entry `manifest.json:112`; PROTOCOL.md:605 row; parsers already accept `[]` (`WatchRoutinesDown.init(envelope:)` `WatchRoutineRecords.swift:~319`, `WatchRoutinesDown.fromEnvelope` `lib/watch/start/watch_routine_catalog.dart:~245`) | the old invalid fixture becomes valid; manifest entry moves registers; the 2026-10-11 amendment row's "keeps minItems: 1" clause is superseded | S-3803, S-3834 |
| `SyncProtocolValidator.messageTypes` (Swift `:50`) / `message_validator.dart:105` + envelope `type` enum | `validateEnvelope` (both stacks); Dart manifest test "gives every message type a schema and a valid fixture" (`test/sync_protocol_fixtures_test.dart:169`) | unknown-type rejections stop for `exercises_down`; the manifest test forces schema + valid fixture presence | S-3801..S-3808 |
| `semanticRejections` switch (Swift `:173`, Dart `:268`) | `validateEnvelope` tail (Swift `:164`, Dart `:196`) | new case; rule order and text must match across stacks | S-3804..S-3806 (fixtures walked by both stacks) |
| `WatchSyncTransport.requestRoutines(since:)` (`WatchSyncOrchestrator.swift:34`) | caller `WatchSyncOrchestrator.sync:94`; conformers `WatchConnectivityBridge:118`, `RecordingTransport` (`WatchSessionStartPathsTests.swift:41`), `WireLog`/`GatedTransport`/`GatedRequestTransport` (`WatchConnectivityBridgeTests.swift:197,1186,1240`) | signature gains `exercisesVersion`; all five conformers compile-update | S-3819, S-3820 |
| `WatchTransportRequest.routinesFrame(since:)` (`WatchConnectivityBridge.swift:59`) | `WatchConnectivityBridge.requestRoutines:119`; contract pin `transportRequests` (`watch_start_paths_contract.json:346`) asserted by S-102/S-103 (`WatchConnectivityBridgeTests.swift:264,288`) and Dart S-102 (`test/watch_transport_test.dart:837`) | key added only when non-nil, so the contract-pinned frames (no list) are unchanged; the Dart twin (`lib/core/platform/watch_transport.dart:73`) is untouched and the phone reads only the request name (`watch_sync_wiring.dart:234`) | S-102/S-103 (unchanged), S-3820 |
| `WatchSessionStartPaths.restore()` (`WatchStartPaths.swift:283`) | harness `launch()` (`WatchSessionStartPathsTests.swift:58`), app shell | batch assembly added; catalog selection (greatest sequence) unchanged | S-3813, S-3832 |
| `syncedFallback` / `fallbackExercises` (`WatchStartPaths.swift:237,289`) | `deriveFallbackExercises` callers: `fallbackExercises`, `addableExercises`, the free-workout picker; `WatchMenuTests`, S-003 tests | union source changes; recents-first order and routine coverage unchanged | S-3810, S-3817, existing S-003 tests |
| `WatchSyncOrchestrator.receive` (`WatchSyncOrchestrator.swift:150`) | harness `receive`, bridge inbound | new route; unknown types still return false | S-3818 |
| Dart wrist client (`lib/watch/**`) | `receive` has `default: return false` (`lib/watch/start/watch_sync_orchestrator.dart`); phone reads only the request name (`watch_sync_wiring.dart:234`) | unaffected: unknown type ignored, unknown request key ignored | existing Dart suite (`flutter test`) |
| ios app (`ios/OmniTrain Watch App/OmniTrainWatchConnectivity.swift`) | grep `StoredWatchRecord`/`routineCatalog` — no exhaustive switch | unaffected | compile |

## Phases (expanded; the seeded table above is the contract)

Serial A → B → C → D; no phase runs in parallel. A → B because the Dart fixture walk consumes A's manifest entries (the Dart fixtures test is expected red between A and B; B's first item fixes it). A → C → D because all three write the same Swift package, and D's assembly reads C's store API and A's validator type.

### Phase A — contract: schema, fixtures, Swift validator (crew-builder-watch)

1. [ ] Add the `exercises_down` message schema (closed payload: `generatedAt`, `catalogVersion` 1..64, `batchIndex` >= 0, `batchCount` >= 1, `totalCount` >= 1, `exercises` 1..100 of `envelope.schema.json#/$defs/catalogExercise`; `type` const `exercises_down`, `origin` const `phone`) — watch/sync_protocol/schemas/messages/exercises_down.schema.json · exercises_down
2. [ ] Add `"exercises_down"` to the `type` enum — watch/sync_protocol/schemas/envelope.schema.json · properties.type.enum
3. [ ] Relax `fallbackExercises` to `minItems: 0` and rewrite its description to the D-3812 meaning — watch/sync_protocol/schemas/messages/routines_down.schema.json · payload.fallbackExercises
4. [ ] Add the 9 fixture files with the exact values of S-3801..S-3807 (valid: `exercises_down.json`, `exercises_down_single_batch.json`, `routines_down_empty.json`; invalid: `exercises_down_batch_index_out_of_range.json`, `exercises_down_total_below_batch.json`, `exercises_down_total_above_capacity.json`, `exercises_down_duplicate_exercise.json`, `exercises_down_empty_batch.json`, `exercises_down_missing_version.json`) — watch/sync_protocol/fixtures/ · valid/*.json, invalid/*.json
5. [ ] Rewrite the manifest: move the S-3603 entry to `valid/routines_down_empty.json` (scenario S-3803) and add the eight `exercises_down` entries with `expectedCode`/`expectedReasonContains`; the old `invalid/routines_down_empty_fallback.json` must be deleted (governor action if the builder cannot delete) — watch/sync_protocol/fixtures/manifest.json · valid[], invalid[]
6. [ ] Add `"exercises_down"` to `messageTypes` and the semantic case `exerciseBatchRejections(_:)` implementing D-3811 (a) batchIndex < batchCount, (b) exercises.count <= totalCount <= batchCount*100, (c) unique exerciseIds, in that order, paths `$.payload.batchIndex` / `$.payload.totalCount` / `$.payload.exercises[i]`, message text shared verbatim with the Dart twin — watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift · messageTypes, semanticRejections, exerciseBatchRejections
7. [ ] Add the 2026-10-11 amendment row for `exercises_down` + the relaxed fallback, and strike the superseded "keeps minItems: 1" sentence in the same-day "catalog with no routines" row (the file's strikethrough convention) — watch/sync_protocol/PROTOCOL.md · version history table
8. [ ] Add the S-3808 unit test: the S-3801 message rebuilt with 101 exercises (totalCount 101, batchCount 2) is rejected `constraint_violation` — watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolValidatorTests.swift · testS3808AABatchOverOneHundredExercisesIsRefused

**Done Criteria** `swift test --package-path watch/watchos` green for `SyncProtocolFixturesTests.swift` (the manifest walk) and `SyncProtocolValidatorTests.swift` (S-3808). The Dart fixtures test is expected red until Phase B (noted above).
**Predicted Files** `watch/sync_protocol/schemas/messages/exercises_down.schema.json` (new), `watch/sync_protocol/schemas/envelope.schema.json`, `watch/sync_protocol/schemas/messages/routines_down.schema.json`, `watch/sync_protocol/fixtures/manifest.json`, `watch/sync_protocol/fixtures/valid/*.json` (3 new), `watch/sync_protocol/fixtures/invalid/*.json` (6 new; 1 deleted — governor), `watch/sync_protocol/PROTOCOL.md`, `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift`, `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolValidatorTests.swift`.
**Write scope** `watch/sync_protocol/**`, `watch/watchos/**`, `watch/contract/**`, `test/sync_protocol_fixtures_test.dart`, `test/watch_start_paths_contract*`, `docs/**`

### Phase B — Dart validator twin (crew-builder-app)

1. [ ] Add `'exercises_down'` to `messageTypes` — lib/core/sync_protocol/message_validator.dart · messageTypes
2. [ ] Add the semantic case and `_exerciseBatchRejections` with the same rule order and message text as the Swift twin (D-3811) — lib/core/sync_protocol/message_validator.dart · _semanticRejections, _exerciseBatchRejections
3. [ ] Add the S-3808 Dart test (101 exercises → `constraint_violation`) next to the fixture walk — test/sync_protocol_fixtures_test.dart · S-3808

**Done Criteria** `flutter test test/sync_protocol_fixtures_test.dart` green (manifest walk + S-3808); `flutter analyze` at the 196-issue baseline.
**Predicted Files** `lib/core/sync_protocol/message_validator.dart`, `test/sync_protocol_fixtures_test.dart`.
**Write scope** `lib/core/sync_protocol/**`, `test/**`

### Phase C — wrist storage: record, contents, prune (crew-builder-watch)

1. [ ] Add `WatchExerciseBatchRecord` (recordId, sessionId "", recordedAt, sequence, catalogVersion, generatedAt, batchIndex, batchCount, totalCount, exercises [[String: Any]]) with `toJson`/`fromJson`, next to `WatchRoutineCatalogRecord` — watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift · WatchExerciseBatchRecord
2. [ ] Add `exerciseBatchType = "exercise_batch"`, the `StoredWatchRecord.exerciseBatch` case, and the case in all 8 exhaustive switches (`recordType`, `recordId`, `sessionId`, `recordedAt`, `sequence`, `withSequence`, `toJson`, `fromJson`) — watch/watchos/Sources/WatchSessionEngine/WatchRecords.swift · StoredWatchRecord
3. [ ] Add `exerciseBatches: [WatchExerciseBatchRecord]` to `WatchStoreContents` (init default empty, `isEmpty` conjunct) and the case in `InMemoryWatchSessionStore.readAll`'s switch — watch/watchos/Sources/WatchSessionEngine/WatchSessionStore.swift · WatchStoreContents, InMemoryWatchSessionStore.readAll
4. [ ] Add `pruneExerciseBatches(keepingVersion: String) async -> [String]` to the protocol with a doc comment, and the `InMemoryWatchSessionStore` implementation (removeAll of non-keeping rows, return dropped ids) — watch/watchos/Sources/WatchSessionEngine/WatchSessionStore.swift · WatchSessionStore, InMemoryWatchSessionStore
5. [ ] Add the `readAll` switch case and `pruneExerciseBatchesLocked` following `pruneConfirmedLocked` exactly (loadRows, guard !unsupported, dropped ids, survivors filter, compact, rows = survivors; empty drop set returns [] without a rewrite per D-3821) — watch/watchos/Sources/WatchSessionEngine/FileWatchSessionStore.swift · FileWatchSessionStore.readAll, pruneExerciseBatchesLocked
6. [ ] Forward the new method in the two test doubles — watch/watchos/Tests/WatchSessionEngineTests/WatchEffortRatingTests.swift · SuspendingStore; watch/watchos/Tests/WatchSessionEngineTests/WatchSensorRecordingTests.swift · ContendedWatchSessionStore
7. [ ] Add `"pruneExerciseBatches"` to the S-004 guard's allowed set and update its comment (five deliberate names) — watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift · testS004NoMutatingOperationExistsAnywhereInTheModule
8. [ ] Add the S-3821 tests (in-memory + file store: prune returns the v1 ids, leaves the v2 row and every other kind; close/reopen; torn tail per the S-49 pattern; empty store returns [] and writes nothing per S-3835) and add the batch family to `fileFamilyJSON` — watch/watchos/Tests/WatchSessionEngineTests/WatchFileStoreTests.swift · fileFamilyJSON, testS3821*

**Done Criteria** `swift test --package-path watch/watchos` green: `WatchSessionEngineTests.swift` (S-004 guard), `WatchFileStoreTests.swift` (S-3821), `WatchEffortRatingTests.swift`, `WatchSensorRecordingTests.swift` compile and pass.
**Predicted Files** `watch/watchos/Sources/WatchSessionEngine/WatchRoutineRecords.swift`, `WatchRecords.swift`, `WatchSessionStore.swift`, `FileWatchSessionStore.swift`; `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionEngineTests.swift`, `WatchEffortRatingTests.swift`, `WatchSensorRecordingTests.swift`, `WatchFileStoreTests.swift`.
**Write scope** `watch/watchos/**`

### Phase D — wrist assembly, restore, union, routing, request (crew-builder-watch)

1. [ ] Add batch state and `applyExercisesDown(_:) async -> WatchExerciseBatchResult` implementing D-3815 rules (1)-(6) in order; store the row with recordId `"exb-<version>-<index>"` — watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift · WatchSessionStartPaths.applyExercisesDown, WatchExerciseBatchResult
2. [ ] Extend `restore()` with the batch assembly per D-3816 (complete versions only; greatest `generatedAt`, ties by greatest max row sequence; no complete version means no active list, not an error) — watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift · WatchSessionStartPaths.restore
3. [ ] Add public `exercisesVersion: String?` and make `syncedFallback` the active list followed by the catalog's `fallbackExercises` not already present (dedupe by `exerciseId`, list first) — watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift · WatchSessionStartPaths.exercisesVersion, syncedFallback
4. [ ] Route `"exercises_down"` in `receive` (return `result.stored`) and pass `paths.exercisesVersion` in `sync(reconnect:)` — watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift · WatchSyncOrchestrator.receive, sync
5. [ ] Extend the transport protocol to `requestRoutines(since:exercisesVersion:)`, implement in `WatchConnectivityBridge`, and add the key to `WatchTransportRequest.routinesFrame` only when non-nil — watch/watchos/Sources/WatchSessionEngine/WatchSyncOrchestrator.swift · WatchSyncTransport; watch/watchos/Sources/WatchSessionEngine/WatchConnectivityBridge.swift · WatchConnectivityBridge.requestRoutines, WatchTransportRequest.routinesFrame
6. [ ] Update the four test doubles to the new signature and record both arguments — watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift · RecordingTransport; watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift · WireLog, GatedTransport, GatedRequestTransport
7. [ ] Add the S-3810..S-3819 tests (harness; helper returning an `exercises_down` envelope for (version, generatedAt, index, count, total, ids)) and the S-3820 frame test — watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift · testS3810..testS3819; watch/watchos/Tests/WatchSessionEngineTests/WatchConnectivityBridgeTests.swift · testS3820
8. [ ] Add `docs/state_management/watch_reference_data.md` (every behaviour sentence names its test) and link it from the Pages table and Class → Page Lookup — docs/state_management/watch_reference_data.md · new page; docs/state_management.md · Pages table, Class → Page Lookup

**Done Criteria** `swift test --package-path watch/watchos` full suite green (S-3810..S-3820); `flutter test test/docs_indexing_contract_test.dart` green; `flutter analyze` at the 196-issue baseline.
**Predicted Files** `watch/watchos/Sources/WatchSessionEngine/WatchStartPaths.swift`, `WatchSyncOrchestrator.swift`, `WatchConnectivityBridge.swift`; `watch/watchos/Tests/WatchSessionEngineTests/WatchSessionStartPathsTests.swift`, `WatchConnectivityBridgeTests.swift`; `docs/state_management/watch_reference_data.md` (new), `docs/state_management.md`.
**Write scope** `watch/watchos/**`, `docs/**`

## Progress

| Item | Status |
|---|---|
| A1 exercises_down schema | [x] |
| A2 envelope type enum | [x] |
| A3 routines_down relax | [x] |
| A4 nine fixture files | [x] |
| A5 manifest rewrite | [x] |
| A6 Swift validator type + rules | [x] |
| A7 PROTOCOL.md amendment row | [x] |
| A8 S-3808 Swift test | [x] |
| B1 Dart messageTypes | [x] |
| B2 Dart semantic rules | [x] |
| B3 S-3808 Dart test | [x] |
| C1 WatchExerciseBatchRecord | [x] |
| C2 StoredWatchRecord case + 8 switches | [x] |
| C3 WatchStoreContents + InMemory readAll | [x] |
| C4 protocol + InMemory prune | [x] |
| C5 File readAll + pruneExerciseBatchesLocked | [x] |
| C6 two test doubles | [x] |
| C7 S-004 guard | [x] |
| C8 S-3821 tests + fileFamilyJSON | [x] |
| D1 applyExercisesDown | [x] |
| D2 restore assembly | [x] |
| D3 exercisesVersion + syncedFallback union | [x] |
| D4 receive routing + sync version | [x] |
| D5 transport protocol + bridge + frame | [x] |
| D6 four test doubles | [x] |
| D7 S-3810..S-3820 tests | [x] |
| D8 docs page + links | [x] |

## Assumption Log

- The `maxItems`/`maxLength` schema keywords were missing from BOTH validators (the plan never names them), so the schema's `maxItems: 100` was inert and S-3808's `constraint_violation` was unreachable. Phase A added both to the Swift schema layer and Phase B added the same two keywords with the same messages to the Dart twin (`_validateArray` / `_validateString`); no other schema in `watch/sync_protocol/schemas` carries either keyword, so no existing behaviour changed.
- `WatchExerciseBatchRecord.fromEnvelope(_:validator:)` and `StoredWatchRecord.exerciseBatchRow` live in `WatchStartPaths.swift` (Phase D) rather than beside the record in `WatchRoutineRecords.swift`, because the phase's write-scope pointers name `WatchStartPaths.swift`; a reviewer may move them next to `WatchExerciseBatchRecord`.
- The Dart/Wear client (`lib/watch/**`) and the phone's sender are untouched in this PR: the Dart orchestrator's `default: return false` already ignores `exercises_down`, and the phone keeps sending the whole list in `routines_down.fallbackExercises` (so `routines_down` carrying the whole list stays TRUE here; 23e2 moves the sender).
- The Dart fixtures test was red between Phase A and Phase B exactly as the plan predicted (the manifest gained `exercises_down` entries before the Dart validator knew the type); Phase B's first items fixed it, and the full Dart suite ended green at +4278 ~1.

## Feedback

(empty)

## Open questions

1. D-3812's reader list overstates: only `watch/sync_protocol/fixtures/manifest.json:112` and `watch/sync_protocol/PROTOCOL.md:605` name the old fixture (grep `routines_down_empty_fallback`); `test/sync_protocol_fixtures_test.dart` and `SyncProtocolFixturesTests.swift` walk the manifest generically and need no edit; `watch/contract/watch_start_paths_contract.json` has no hit and the glob `test/watch_start_paths_contract*` matches no file (the contract's Dart readers are `test/watch_transport_test.dart`, `test/watch_session_start_test.dart`). No edit needed there.
2. D-3813 says the `StoredWatchRecord` enum has "~9 switches"; the count is 8 (`WatchRecords.swift:697,711,725,739,753,767,781,794`), plus the 2 `readAll` switches in the stores.
3. The S-004 guard's comment says "Exactly five names are deliberate" while the set lists four (`WatchSessionEngineTests.swift:322-330`); after adding `pruneExerciseBatches` the set is five and the comment's count becomes true — Phase C still rewrites the comment per D-3814.
4. Contract `transportRequests`: adding an `exercisesVersion` frame entry to the shared contract in 23e1 would pin a frame the Dart twin does not build until 23e2 (`lib/core/platform/watch_transport.dart:73`; the Dart S-102 test `test/watch_transport_test.dart:837` asserts only the three named entries, so an extra entry would not fail it, but the contract would describe a frame one client cannot produce). Resolved as D-3820: contract untouched in 23e1, S-3820 Swift-only, 23e2 moves the pin.
5. Docs ceiling: `test/docs_indexing_contract_test.dart:49` measures 64 KiB, not the 52 KB the phase-D note implies; the new-page decision (D-3822) stands regardless. File sizes were not re-measured this run (no gateway run).
6. Deleting `watch/sync_protocol/fixtures/invalid/routines_down_empty_fallback.json` is a file deletion the builder's tools may not perform — governor action if the builder cannot delete (the Dart walk test "lists every fixture file on disk, exactly once" fails while the file exists unlisted).
7. D-3815 rule (3) + idempotent recordId: a phone that stored a wrong `totalCount` for a version can never complete it (a corrected re-send is refused by rule 3; the recordId is the same). Bounded by D-3802 (the phone derives the version from content, so a fix arrives under a new version). Pinned as S-3831.
8. The Dart fixtures test goes red between Phase A and Phase B (the manifest gains `exercises_down` entries before the Dart validator knows the type) — inherent to the serial split; Phase B's first item fixes it.
9. Baselines note "flutter test +4267 ~1" — the "~1" meaning (1 skipped?) taken as-is from the brief.
