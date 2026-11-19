# Feature: 75 — a ride, a row or a walk is saved to Apple Health as a ride, a row or a walk

> Status: Iteration 1 active. Owner answer (2026-10-24, asked and answered): yes, save cycling, rowing, walking and hiking as their own Health types. One contract amendment, two tracks: wrist + contract first, phone second.
> Next handoff: `crew-builder-watch` (P1a contract, P1b wrist), then `crew-builder-app` (P2 phone).
> Base: `c1b1c5f0` on `claude_develop`. Never create or switch branches; git belongs to the governor.
> Binding: `docs/global_conventions.md`; `.github/copilot/pr-scope-budget.md`; `watch/sync_protocol/PROTOCOL.md`.

## Overview

| What you do | Now | After 75 |
|---|---|---|
| Do a Zone 2 Ride (or any exercise whose discipline is Cycling) on the watch | Health and Fitness record it as a Run | Recorded as Cycling |
| A rowing exercise (discipline Rowing) | Run | Rowing |
| A Brisk Walk or Incline Walk (discipline Walking) | Run | Walking |
| Hike or Rucking (the two built-in ones) | Run | Hiking |
| A custom cardio exercise | Run | Whatever discipline you picked in the exercise editor: Running, Cycling, Rowing or Walking record as that; any other discipline (or none) stays Run, as today. A custom hike cannot be told from a walk, so it records as Walking |
| A Free workout or routine that starts on a lifting exercise | Strength Training (first exercise decides, plan 58) | Unchanged |
| Swimming, elliptical, ski erg (discipline Swimming / Machine cardio) | Run | Run (unchanged, not asked for: tell me if you want Swimming or Other) |

Code facts (scouts + lead, 2026-10-24):
- The wrist receives only `capabilities` for an exercise, never a discipline: `_catalogExerciseJson` (`lib/core/utils/watch_reference_sync.dart` l.~152) writes `exerciseId`, `name`, `capabilities`, `roundDurationSecs`; the session slot map (`lib/state/watch/watch_session_adoption_bridge.dart` l.~533) writes `sessionExerciseId`, `exerciseId`, `name`, `effortKind`, `capabilities`, `roundDurationSecs`. `WatchActivityTypes.forExercise(capabilities:)` (`WatchPlatformWorkout.swift` l.117-123) returns Running for any `distance` exercise; `forExercises` takes the majority and `forSession` is what opens the Health workout (`WatchPlatformWorkout.start`, l.~261).
- `catalogExercise` and `sessionExercise` are CLOSED schema objects (`watch/sync_protocol/schemas/envelope.schema.json` l.68-160, `additionalProperties: false`), enforced by the Dart validator (`lib/core/sync_protocol/message_validator.dart` l.874) and the Swift one (`SyncProtocolValidator.swift` l.749). Precedent for widening: the `roundDurationSecs` amendment (PROTOCOL.md l.722, fixtures `routines_down_round_length.json` etc.).
- The Health store maps names in `HealthKitWorkoutStore.activityType(for:)` / `name(for:)` (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` l.~255-282) and the guard `WatchWorkoutStoreSourceTests` S-1509 pins the store's `case "<name>":` set to the `watchos` names in `watch/contract/watch_sensor_contract.json` `activityTypes` (+ `genericActivityType`). The Dart wrist twin (`lib/watch`) has no per-exercise type logic.
- Phone side: `Exercise.disciplineId` (`lib/data/models/models.dart` l.89-110) is the only field that separates the kinds; seeded distance exercises: `discipline-running` (14), `discipline-cycling` (11), `discipline-rowing` (6), `discipline-walking` (Brisk Walk, Incline Walk, Rucking, Hike), `discipline-swimming`, `discipline-machine-cardio`. The custom-exercise editor already offers a discipline dropdown (`lib/features/exercise/exercise_editor_screen.dart` l.296-300, l.507-510).

## Decision Ledger

- **D-1** New optional string field `healthActivity` on `catalogExercise`, `sessionExercise` (both in `envelope.schema.json`) AND the `routines_down` routine `effort` (`watch/sync_protocol/schemas/messages/routines_down.schema.json` l.~68-90, also closed: a wrist-started routine builds its slots from efforts, which carry only `capabilities` today): one shared definition `$defs.healthActivity` in `envelope.schema.json`, enum `["running", "cycling", "rowing", "walking", "hiking"]`, referenced from all three. Present only on exercises whose `capabilities` contain `distance` and whose kind the phone can name (D-3); omitted otherwise. Additive, no protocol version change; the same fixtures-and-amendment treatment as `roundDurationSecs`.
- **D-2** Wrist: `WatchCatalogExercise` gains `healthActivity: String?` (read in `init(json:)` and `init(slot:)`, written by `toSlot` and `toJson` only when non-nil — a nil keeps today's payloads byte for byte). `WatchRoutineEffort` (`WatchRoutineRecords.swift` l.~141-215) gains `healthActivity: String?` too (init parameter defaulted nil, read in `init(json:)`, written by its `toJson` only when non-nil, carried by `catalogExercise` so `slot` includes it). `WatchActivityTypes.forExercise(capabilities:healthActivity:)` (second parameter defaults to nil so existing callers compile): `hold` first (unchanged), then when `distance` is present the type for the value — `cycling` → (`cycling`, `exercise_type_biking`), `rowing` → (`rowing`, `exercise_type_rowing`), `walking` → (`walking`, `exercise_type_walking`), `hiking` → (`hiking`, `exercise_type_hiking`), `running` / nil / an unknown string → running (unchanged); then reps/sets/load → strength; else generic. `forExercises` passes each exercise dictionary's `healthActivity` string. The existing "first exercise decides a Free workout" and majority rules (plans 58/ar) are untouched.
- **D-3** Phone: `WatchReferenceSync.healthActivityOf({required String? disciplineId, required String exerciseId, required List<String> capabilities}) -> String?` — null unless `capabilities` contains `distance`; `discipline-running` → `running`; `discipline-cycling` → `cycling`; `discipline-rowing` → `rowing`; `discipline-walking` → `hiking` when `exerciseId` is `exercise-hike` or `exercise-rucking`, else `walking`; every other discipline or null → null. `_SyncedExercise` carries it; `_catalogExerciseJson` writes `'healthActivity'` only when non-null; the session slot map writes it the same way (the slot's exercise is looked up in the same resolver; the builder reads how `exercise?.name`/`capabilities` are obtained there).
- **D-4** Health store: `HealthKitWorkoutStore.activityType(for:)` gains `case "cycling": return .cycling`, `case "rowing": return .rowing`, `case "walking": return .walking`, `case "hiking": return .hiking`; `name(for:)` gains the reverse arms. `watch_sensor_contract.json` gains a new section `"distanceActivityTypes"` with the four new names (and `running`) as `{ "watchos": ..., "wear": ... }` rows; the S-1509 guard's expected set becomes the union of `activityTypes`, `genericActivityType` and `distanceActivityTypes` names. The existing guard in `WatchSensorRecordingTests` l.510-520 (modality table vs contract) is unchanged. No `Info.plist` or capability change.
- **D-5** GPS: unchanged. `WatchGpsPolicy` still keys on the `distance` capability, so an indoor Stationary Bike or an elliptical still starts GPS as today (pre-existing; Cycling and Walking now carry a route map through plan 76). The Dart wrist twin gets no per-exercise logic.
- **D-6** Waiting readers: none (the field only changes which Health type opens).
- **D-7** Deviation told to the owner: hiking only for the two built-in exercises (a custom hike is Walking).

## Feature Invariants

- Every payload that carries no `healthActivity` is byte for byte what it is today.
- A phone that does not send the field (an older build) still opens Running for distance exercises.
- A lifting-first session opens Strength Training regardless.

## Scenarios (ids `S-105xx`; grep 2026-10-24: unused)

Contract and wrist:
- **S-10501 schema accepts and rejects.** Valid fixtures: `exercises_down_health_activity.json` (one exercise `{ exerciseId, name, capabilities: ["time","distance"], healthActivity: "cycling" }` and one without the field) and `session_snapshot_health_activity.json` (one `sessionExercise` slot with `healthActivity: "hiking"`); invalid fixture `exercises_down_unknown_health_activity.json` (`healthActivity: "swimming"`) is rejected with the code the sibling `exercises_down_*` invalid fixtures show for an enum miss (the builder confirms from `invalid_enum_value`). Walked by both stacks' fixture tests (`test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift`).
- **S-10502 (wrist) the type table, one test per value.** `forExercise(capabilities: ["time","distance"], healthActivity: v)` for v in cycling / rowing / walking / hiking → watchOS names `cycling` / `rowing` / `walking` / `hiking` and the four wear names; v = "running", nil and "swimming" → `running`. Fails today: no parameter.
- **S-10503 (wrist) `hold` still beats distance**: `["hold","time","distance"]` with `cycling` → flexibility; and reps-only with `cycling` → strength (the field is read only with `distance`).
- **S-10504 (wrist) majority with mixed activities**: three slots [cycling, cycling, strength] → cycling; [cycling, running, strength] tie → the earliest exercise's type (cycling); a Free workout whose first slot is cycling → cycling.
- **S-10505 (wrist) records round-trip**: `WatchCatalogExercise(json:)` → `toJson` / `toSlot` keep `healthActivity`; absent stays absent (assert the dictionary has no key); `init(slot:)` reads it.
- **S-10506 (source guards)** `HealthKitWorkoutStore.swift` contains the exact arms `case "cycling": return .cycling`, `case "rowing": return .rowing`, `case "walking": return .walking`, `case "hiking": return .hiking` in `activityType(for:)` and `case .cycling: return "cycling"` (and the three others) in `name(for:)`; S-1509 updated to the union (reader list: `WatchWorkoutStoreSourceTests.swift` only; `WatchSensorRecordingTests` l.510-520 reads `activityTypes` only and stays).
- **S-10507 (contract JSON) `distanceActivityTypes` has exactly the five rows** with the `wear` names above; no `activityTypes` row changed.

Phone:
- **S-10511 `healthActivityOf`, one test per arm**: (running discipline, distance) → running; cycling → cycling; rowing → rowing; (walking, `exercise-brisk-walk`) → walking; (walking, `exercise-hike`) → hiking; (walking, `exercise-rucking`) → hiking; (walking, a custom id `custom-trek`) → walking; `discipline-swimming` → null; `discipline-machine-cardio` → null; null discipline → null; cycling WITHOUT `distance` capability → null.
- **S-10512 the catalog builder**: `buildExercisesDown` for a repository with `exercise-zone-2-ride` and a custom cycling-less exercise: the ride's wire map has `'healthActivity': 'cycling'`, the other has no such key (exact maps, like test S-3844 does); the existing S-3844 vector (`test/watch_reference_sync_test.dart` l.612-618) stays green untouched.
- **S-10513 the session slot**: an adopted session slot for a cycling exercise carries `healthActivity: 'cycling'` through `LiveSessionMirrorState.snapshotEnvelope` and validates (the sync-protocol validator accepts it); a lifting slot has no key.
- **S-10514 `routines_down` fallback list** carries the key for a distance exercise (the same builder), and every routine `effort` of a cycling exercise carries `'healthActivity': 'cycling'` (`_encodeEfforts`-style builder at `watch_reference_sync.dart` l.~296-335: the `efforts.add({...})` map); an effort of a lifting exercise has no key.
- **S-10508 (wrist) a routine effort round-trips and starts the right Health type**: `WatchRoutineEffort(json:)` with `healthActivity: "cycling"` and capabilities `["time","distance"]` → `slot["healthActivity"] == "cycling"`; a routine of [bench, ride] started on the wrist: session opens Strength (first exercise) and a routine of [ride, bench] opens Cycling; absent key → absent in the slot.

## Phase 1a: contract (`crew-builder-watch`)

1. [ ] Schema: `$defs.healthActivity` + the property on `catalogExercise` and `sessionExercise` — `watch/sync_protocol/schemas/envelope.schema.json` (beside `roundDurationSecs`); on the routine effort — `watch/sync_protocol/schemas/messages/routines_down.schema.json`.
2. [ ] Fixtures (S-10501): the three files under `watch/sync_protocol/fixtures/valid|invalid/` (copy the shape of `exercises_down.json` and `session_snapshot.json`).
3. [ ] `watch/sync_protocol/PROTOCOL.md`: a dated amendment entry after the 2026-10-09 one, naming the field, its enum and "no version change".
4. [ ] Contract JSON `distanceActivityTypes` (S-10507) — `watch/contract/watch_sensor_contract.json`.

**Done**: `flutter test test/sync_protocol_fixtures_test.dart`, `swift test --package-path watch/watchos --filter SyncProtocolFixturesTests`.

## Phase 1b: wrist (`crew-builder-watch`)

1. [ ] D-2: `WatchRoutineRecords.swift` (`WatchCatalogExercise`), `WatchPlatformWorkout.swift` (`forExercise`, `forExercises`).
2. [ ] D-4: `HealthKitWorkoutStore.swift` arms; S-1509 guard union.
3. [ ] Tests S-10502..S-10506 — new `WatchHealthActivityTests.swift`.
4. [ ] Report FIRST as a skeleton.

**Done**: `--filter WatchSessionEngineTests` (whole target, append-only guard: new names avoid the banned verbs), `--filter WatchWorkoutStoreSourceTests`, `--filter WatchSensorRecordingTests`; the lead builds with xcodebuild.

## Phase 2: phone (`crew-builder-app`, after 1a)

1. [ ] D-3: `watch_reference_sync.dart` (`healthActivityOf`, `_SyncedExercise`, `_catalogExerciseJson`) and `watch_session_adoption_bridge.dart` (slot map).
2. [ ] Tests S-10511..S-10514 — new `test/watch_health_activity_test.dart`.
3. [ ] Docs: `docs/state_management/watch_surface.md` or `docs/watch_session_capture.md` (grep `roundDurationSecs` in docs for where the exercise dictionary is described): one sentence for `healthActivity`.

**Done**: `flutter test test/watch_health_activity_test.dart test/watch_reference_sync_test.dart test/watch_session_projection_test.dart test/watch_sync_request_handler_test.dart test/sync_protocol_fixtures_test.dart test/docs_indexing_contract_test.dart`.

## Owner device checks

- (owner) ODC-1 Start a Zone 2 Ride on the watch and finish it: Fitness / Health shows Cycling (not Run). Same for a rowing exercise and a Brisk Walk.
- (owner) ODC-2 A custom cardio exercise with discipline Cycling records as Cycling; with no discipline it records as a Run.

## Progress
- [x] Phase 1a
- [x] Phase 1b
- [x] Phase 2

## Assumption Log
- Provider stopped the crew (429 Go usage limit) after the contract and wrist code were written and tested but before their reports and the phone docs: the lead finished (docs sentence, three analyzer fixes, one doc-block move) and verified every file.
- Swift mutants D1..D7b killed; Dart mutants P1..P6 killed.

## Feedback
