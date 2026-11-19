# Feature: an exercise's discipline decides its Apple Health workout type (plan 170)

> Status: DRAFT (owner unavailable; defaults applied, each marked below)
> Next handoff: @developer (Phase 1)
> Binding conventions: docs/global_conventions.md
> Builds on: plan 168, **committed first** — plan 170 edits the symbols plan 168 created:
> `WatchActivityTypes.forSession` / `forNamedHealthKinds` / `distanceType` / `namedHealthKinds`
> (`watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` l.139–147, l.169–211) and
> their Dart mirror (`lib/watch/sensors/watch_platform_workout.dart` l.121–131, l.168–236), plus
> `healthActivityOf` (`lib/core/utils/watch_reference_sync.dart` l.596–614), which plan 168 left
> untouched. Owner decision 2026-11-14 (agreed): **no exercise-editor change, no new sync field** —
> extend what the phone already derives.

## Overview

Today the phone sends the wrist a Health "kind" per exercise only when the exercise carries the
`distance` capability and its discipline is one of four (`healthActivityOf`,
`lib/core/utils/watch_reference_sync.dart` l.596–614: running, cycling, rowing, walking; the seeded
Hike and Rucking ride the walking discipline into `hiking` via the `exerciseId` special case). A
custom or seeded exercise of any other discipline — yoga, swimming, soccer, boxing, a plank — sends
no kind, so the wrist falls back: modality first (plan 168 D-16803), and a Cardio session records as
a run, a sports session as Other, a plank as flexibility.

But the exercise editor already lets every exercise — custom included — carry a discipline
(`lib/features/exercise/exercise_editor_screen.dart` `_selectedDisciplineId`, saved at l.288/l.300;
the picker's list is the seeded 37 disciplines, `lib/mock/seed_data.dart` `sampleDisciplines`,
count pinned at 37 by `test/conditioning_catalog_test.dart` S-19201). The discipline is persisted on
the exercise row and read at sync time (`_ExerciseResolver.resolve`,
`watch_reference_sync.dart` l.70–95; `_slotFor`, `lib/state/watch/watch_session_adoption_bridge.dart`
l.589), so no migration is needed — the kind is derived when the message is built.

Plan 170 replaces the four-discipline switch with the full discipline → Health-kind table (D-17001),
removes the distance-capability gate (D-17002), widens the wire enum and the wrist's resolution
(D-17003/D-17004), and pins the store's name map to the widened contract (D-17005). Plan 168's
precedence (named kinds → modality → capability majority) and its majority/tie rule are unchanged —
they simply see far more named kinds.

## Resolved Decisions (Ledger)

- **D-17001 The discipline → Health-kind table.** One wire kind per discipline, named for its honest
  `HKWorkoutActivityType` (lower-camel) except where the Health Connect twin diverges, where the
  kind gets a distinct canonical name so both platforms stay honest (D-17006). The Hike/Rucking
  special case stays (`exerciseId`-keyed, inside `healthActivityOf`). Unmapped or absent discipline
  → no kind (the modality default applies).

  | discipline id | wire kind | HK (`watchos`) | Health Connect (`wear`) |
  |---|---|---|---|
  | `discipline-running` | `running` | `running` | `exercise_type_running` |
  | `discipline-cycling` | `cycling` | `cycling` | `exercise_type_biking` |
  | `discipline-swimming` | `swimming` | `swimming` | `exercise_type_swimming` |
  | `discipline-rowing` | `rowing` | `rowing` | `exercise_type_rowing` |
  | `discipline-walking` | `walking` (`hiking` for `exercise-hike`, `exercise-rucking`) | `walking` / `hiking` | `exercise_type_walking` / `exercise_type_hiking` |
  | `discipline-powerlifting` | `traditionalStrengthTraining` | `traditionalStrengthTraining` | `exercise_type_strength_training` |
  | `discipline-bodybuilding` | `traditionalStrengthTraining` | `traditionalStrengthTraining` | `exercise_type_strength_training` |
  | `discipline-weightlifting` | `traditionalStrengthTraining` | `traditionalStrengthTraining` | `exercise_type_strength_training` |
  | `discipline-calisthenics` | `calisthenics` | `functionalStrengthTraining` | `exercise_type_calisthenics` * |
  | `discipline-isometric-holds` | `isometricHolds` | `functionalStrengthTraining` | `exercise_type_strength_training` * |
  | `discipline-conditioning` | `conditioning` | `crossTraining` | `exercise_type_cross_training` |
  | `discipline-machine-cardio` | `mixedCardio` | `mixedCardio` | `exercise_type_other_workout` * |
  | `discipline-active-recovery` | `preparationAndRecovery` | `preparationAndRecovery` | `exercise_type_other_workout` * |
  | `discipline-stretching` | `flexibility` | `flexibility` | `exercise_type_stretching` * |
  | `discipline-yoga` | `yoga` | `yoga` | `exercise_type_yoga` |
  | `discipline-boxing` | `boxing` | `boxing` | `exercise_type_boxing` * |
  | `discipline-muay-thai` | `kickboxing` | `kickboxing` | `exercise_type_martial_arts` * |
  | `discipline-bjj` | `martialArts` | `martialArts` | `exercise_type_martial_arts` |
  | `discipline-judo` | `martialArts` | `martialArts` | `exercise_type_martial_arts` |
  | `discipline-karate` | `martialArts` | `martialArts` | `exercise_type_martial_arts` |
  | `discipline-mma` | `martialArts` | `martialArts` | `exercise_type_martial_arts` |
  | `discipline-tennis` | `tennis` | `tennis` | `exercise_type_tennis` |
  | `discipline-badminton` | `badminton` | `badminton` | `exercise_type_badminton` |
  | `discipline-table-tennis` | `tableTennis` | `tableTennis` | `exercise_type_table_tennis` * |
  | `discipline-cricket` | `cricket` | `cricket` | `exercise_type_cricket` |
  | `discipline-ice-hockey` | `hockey` | `hockey` | `exercise_type_other_workout` * |
  | `discipline-baseball` | `baseball` | `baseball` | `exercise_type_baseball` |
  | `discipline-american-football` | `americanFootball` | `americanFootball` | `exercise_type_american_football` |
  | `discipline-rugby` | `rugby` | `rugby` | `exercise_type_rugby` * |
  | `discipline-lacrosse` | `lacrosse` | `lacrosse` | `exercise_type_other_workout` * |
  | `discipline-soccer` | `soccer` | `soccer` | `exercise_type_football` * |
  | `discipline-basketball` | `basketball` | `basketball` | `exercise_type_basketball` |
  | `discipline-volleyball` | `volleyball` | `volleyball` | `exercise_type_volleyball` |
  | `discipline-squash` | `squash` | `squash` | `exercise_type_squash` |
  | `discipline-golf` | `golf` | `golf` | `exercise_type_golf` |
  | `discipline-climbing` | `climbing` | `climbing` | `exercise_type_rock_climbing` |
  | `discipline-padel` | *null* (unmapped) | — | — |

  36 of 37 seeded disciplines map; `discipline-padel` is the only explicit null (HealthKit has no
  padel type; `racquetball` would mislabel — the sports-modality default Other applies). Where the
  table carries no honest Health Connect type, `wear` is the generic `exercise_type_other_workout`
  (hockey, lacrosse, mixedCardio, preparationAndRecovery) — the Android twin stays Other, exactly
  what the sports modality answers today. (*): owner to confirm the HC spelling/choice; a wrong
  spelling is a one-line contract fix — the contract tests pin every row, so the fix cannot drift.
  **Chosen mappings and why** (each owner to confirm by default):
  - `machine-cardio` → `mixedCardio`: the discipline covers treadmill, bike, elliptical and stair
    machines; `elliptical` would be dishonest for a treadmill or assault-bike row, and HealthKit's
    own `mixedCardio` exists for exactly this mix. HC has no mixed type → Other.
  - `active-recovery` → `preparationAndRecovery`: HealthKit's own type for warm-up/recovery work.
    `mindAndBody` or `flexibility` would claim meditation or stretching the user did not log.
  - `isometric-holds` → `functionalStrengthTraining`: planks and wall sits are bodyweight strength
    work; `flexibility` would be dishonest. **Intended flip**: a plank (seeded rows carry
    `discipline-isometric-holds`, `lib/mock/seed_data.dart` l.1809–1985) records Functional
    Strength Training instead of Flexibility — see the S-10503/S-19306/S-19209 flips in Impact.
  - `calisthenics` → kind `calisthenics` with HK `functionalStrengthTraining` but HC
    `exercise_type_calisthenics`: Health Connect is finer-grained here, so the kind is its own name.
  - `muay-thai` → `kickboxing`: Muay Thai is the kickboxing family and HealthKit has the type; HC
    has no kickboxing, so its twin is `martial_arts`. `bjj`/`judo`/`karate`/`mma` → `martialArts`
    (grappling/traditional arts; HC's honest bucket).
  - `stretching` → kind `flexibility`, HK `flexibility`, HC `exercise_type_stretching` (HC's honest
    name; the modality rows keep their pinned `exercise_type_flexibility` — untouched).
  - `soccer` → HC `exercise_type_football` (Health Connect's football = soccer); `ice-hockey` → HK
    `hockey`; both HC rows owner to confirm.
- **D-17002 The kind no longer depends on capabilities.** `healthActivityOf` derives the kind from
  the discipline alone: `({required String? disciplineId, required String exerciseId})` — the
  `capabilities` parameter is dropped, the `ExerciseCapability.distance` gate
  (`watch_reference_sync.dart` l.600) is removed, and the `exerciseId` special case for Hike/Rucking
  stays. A swimming exercise without `distance` still names `swimming`; a yoga exercise names `yoga`
  with no distance at all. Null when the discipline is null, an id the table does not carry, or a
  custom exercise the user gave no discipline to. **Owner to confirm.**
- **D-17003 The wrist resolves every contract kind, and an unknown name falls through.**
  `WatchPlatformWorkout.swift`'s `distanceType(_:)` (l.139–147) becomes `kindType(_:) ->
  WatchActivityType?` over the full table, nil for an unknown name; `forExercise` consults the kind
  **first** (it is the exercise's own claim, more specific than capability inference), then the
  existing chain unchanged — `hold` → flexibility, `distance` → running (a distance exercise that
  names no kind stays a run, exactly today's S-10502 answer), `reps/sets/load` → strength, else
  generic. `namedHealthKinds` (l.186–189) is dropped: `forNamedHealthKinds` maps every named kind
  through `kindType` and drops the nils. Consequence: **an unknown kind name never resolves to
  Running for a non-distance exercise** — it falls through to the capability chain at exercise
  level and to the modality at session level (plan 168's tiers, unchanged). **Owner to confirm.**
- **D-17004 Wire contract: the kind vocabulary widens, the enum stays closed.** The wire is a
  closed enum, not a free string (`envelope.schema.json` `#/$defs/healthActivity`, l.73–76, today
  the five names). Plan 170 amends it to the 31 kinds D-17001 lists, updates the field description
  (present whenever the phone can name the discipline's kind, regardless of capabilities), keeps
  protocol version 1, and follows the closed-object rules exactly: schema amendment + new valid
  fixture + one existing invalid fixture edited (`exercises_down_unknown_health_activity.json`
  carries `"swimming"`, which becomes valid — its payload changes to a never-valid name and the
  manifest's `expectedReasonContains` follows), and a dated amendment row in PROTOCOL.md superseding
  the 2026-10-24 row. A receiver that does not know a name treats it as absent (D-17003's
  fall-through) — additive, nothing a v1 client sends becomes invalid.
- **D-17005 The store's name map is the contract, exactly (D-1509 stays).** `HealthKitWorkoutStore`
  `activityType(for:)`/`name(for:)` (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`
  l.356–385) gains one arm per new `watchos` name the contract carries (23 new HK cases:
  swimming, functionalStrengthTraining, mixedCardio, preparationAndRecovery, boxing, kickboxing,
  martialArts, tennis, badminton, tableTennis, cricket, hockey, baseball, americanFootball, rugby,
  lacrosse, soccer, basketball, volleyball, squash, golf, climbing, yoga), reverse arms included;
  the unknown default stays `.other` (never Running). The S-1509 guard
  (`WatchWorkoutStoreSourceTests.testS1509TheStoreMapsEveryContractActivityName`) keeps asserting
  set equality against the contract union, so the store cannot drift.
- **D-17006 The contract section renames to `healthActivityTypes`.** The `distanceActivityTypes`
  key (`watch/contract/watch_sensor_contract.json` l.85) is no longer about distance. Renamed, all
  four readers follow: `WatchHealthActivityContractTests.swift` l.19/31/42,
  `WatchWorkoutStoreSourceTests.swift` l.44, the Dart helper
  `test/watch_sensor_recording_test.dart` l.994–997, and the doc comment
  `HealthKitWorkoutStore.swift` l.350–352. No message schema or fixture name changes with it.
- **D-17007 Majority, tie and start-fixing are unchanged.** Plan 168 D-16803's four-tier
  precedence and its majority/earliest-tie rule apply unchanged over the widened kind set, and the
  type stays fixed at workout start (S-17006). Plan 170 adds no new precedence rule.

## Feature Invariants

- **Implementation parity**: the Swift client and its Dart mirror resolve the same session to the
  same type — every kind row is pinned in `watch/contract/watch_sensor_contract.json` and asserted
  on both sides (S-17004/S-17009).
- **Schema contract**: the wire enum (`envelope.schema.json`), the resolution tables
  (`WatchPlatformWorkout.swift`, `watch_platform_workout.dart`) and the store's name map all step
  with `watch/contract/watch_sensor_contract.json`; each side's suite asserts against the contract
  file, so drift fails a test, not a workout (S-17003/S-17004/S-17008/S-17009).
- **The type is fixed at workout start** (plan 168 D-16803); plan 170 adds no retype path.
- **An unknown kind is inert**: on the phone (unmapped discipline → no key) and on the wrist
  (unknown name → capability/modality defaults), never a wrong Running.

## Requirements

1. Every seeded discipline either maps to a Health kind with both platform twins, or is explicitly
   listed as unmapped (padel); a custom exercise maps through its discipline the same way, and a
   custom exercise with no discipline sends none (D-17001/D-17002).
2. The wire accepts the 31-kind enum; the wrist resolves every name to its contract row and falls
   through on anything else (D-17004/D-17003).
3. Mixed routines resolve as plan 168 pinned them (majority, tie → earliest, fixed at start);
   plan 170 changes the set of kinds that can vote, not the rule (D-17007).
4. A sports-modality session with a typed discipline records as its sport; an unmapped discipline
   in the same modality stays Other (S-17007).
5. Existing stored exercises (seeded and custom) need no migration: the kind is derived at sync
   time from the persisted `disciplineId` (`watch_reference_sync.dart` l.70–95; the editor saves it
   at `exercise_editor_screen.dart` l.288/l.300) — confirmed, no model or schema change on the phone.

## Acceptance Criteria (each maps to ≥ 1 scenario)

| Criterion | Scenarios |
|---|---|
| The table covers every seeded discipline; custom exercises map the same way | S-17001 |
| The kind is independent of capabilities; null for no/unknown discipline | S-17002 |
| The wire enum, fixtures and PROTOCOL.md carry the widened rule | S-17003 |
| Every contract kind resolves on the wrist and in the mirror; unknown falls through | S-17004, S-17009 |
| The kind beats capability inference and the modality | S-17005 |
| Mixed-routine majority/tie and start-fixing unchanged over the widened set | S-17006 |
| Sports record as their sport; unmapped stays Other | S-17007 |
| The store maps every contract name; unknown → other | S-17008 |

## Existing-Functionality Impact

| Touched surface | Existing readers (grep) | Effect | Guarded by |
|---|---|---|---|
| `WatchReferenceSync.healthActivityOf` (`lib/core/utils/watch_reference_sync.dart` l.596–614) | `_ExerciseResolver.resolve` l.89 (feeds catalog, fallback list and efforts, l.294/l.429); `watch_session_adoption_bridge.dart` l.589; tests `watch_health_activity_test.dart` l.38, `watch_reference_sync_test.dart` l.687, `conditioning_catalog_test.dart` l.140 (grep `healthActivityOf` over `lib/` + `test/`) | Gate removed, signature loses `capabilities`, table widened, doc comment rewritten | S-17001, S-17002; the three flipped tests re-pin (below) |
| `WatchActivityTypes.distanceType` / `namedHealthKinds` (Swift l.139–147, l.186–189; Dart mirror `lib/watch/sensors/watch_platform_workout.dart` l.121–131, l.222–236) | `forExercise` l.160–175, `forNamedHealthKinds` l.193–207, `forSession` l.210–214 (plan 168's tiers — grep `forSession`/`forNamedHealthKinds` over both trees) | `kindType` replaces `distanceType` (nil for unknown), kind-first in `forExercise`, named tier widened | S-17004–S-17006; plan 168's S-16804–S-16807 stay green (their fixtures use the five original kinds) |
| `watch/contract/watch_sensor_contract.json` `distanceActivityTypes` (l.85) | `WatchHealthActivityContractTests.swift` l.19/31/42; `WatchWorkoutStoreSourceTests.swift` l.44; `test/watch_sensor_recording_test.dart` l.994–997; doc comment `HealthKitWorkoutStore.swift` l.350–352 (grep `distanceActivityTypes` over the repo — all hits listed) | Renamed `healthActivityTypes`, widened to 31 rows | S-17003, S-17004, S-17008, S-17009 |
| `envelope.schema.json` `#/$defs/healthActivity` (l.73–76) | both fixture walkers: `test/sync_protocol_fixtures_test.dart` (`S-001 fixtures`) and `SyncProtocolFixturesTests.swift` (`testEveryValidFixtureConforms`, `testEveryInvalidFixtureIsRejectedAsStated`) | Enum widened 5 → 31; description updated; `invalid/exercises_down_unknown_health_activity.json` payload `"swimming"` → `"unreal-kind"` (the only existing fixture edited) and its manifest row follows | S-17003 |
| `HealthKitWorkoutStore.activityType(for:)` / `name(for:)` (`ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` l.356–385) | S-1509 source-scan guard `WatchWorkoutStoreSourceTests.testS1509TheStoreMapsEveryContractActivityName`; diagnostics `workout_end discarded_held`/`workout_saved` notes name types through `name(for:)` (plan 168 D-16804, unchanged shape) | 23 new arms each way; unknown default stays `.other` | S-17008 |
| **Flipped pinned tests** (each is red at HEAD after its expectation is updated, green after its phase's fix): `watch_health_activity_test.dart` S-10511 "swimming records as nothing" → `'swimming'`; S-10511 "machine cardio records as nothing" → `'mixedCardio'`; S-10511 "cycling without distance records as nothing" → `'cycling'`. `watch_reference_sync_test.dart` S-19306 yoga rows carry no kind + `healthActivityOf(discipline-yoga)` null → the rows carry `'yoga'` | listed files | Re-pin to D-17002/D-17003 | S-17001, S-17002 |
| **Flipped pinned tests (Swift)**: `WatchHealthActivityTests.swift` S-10503 "hold beats distance even with a cycling kind" → the cycling kind now wins (kind-first, D-17003); S-10503 "reps only with a cycling kind is strength" → `cycling`; S-10502 "an unknown kind stays running" (`"swimming"`) → swimming now resolves, the unknown case re-pins with a never-valid name | `WatchHealthActivityTests.swift` l.87–130 | Re-pin to D-17003 | S-17004, S-17005 |
| **Flipped pinned test (Dart)**: `conditioning_catalog_test.dart` S-19209 "no Health kind for them" (l.11–12, l.137–172: seeded conditioning rows carry no `distance`, so the kind was null) → the rows now carry `'conditioning'` (plan 118 D-19210's expectation superseded) | `test/conditioning_catalog_test.dart` | Re-pin to D-17002 | S-17001 |
| Docs | `docs/state_management/watch_sensors.md` l.141–157 (the `forSession` paragraph: the five-kind list and the capability chain), l.525–533 (the "contract carries the modality table only" sentence) | Updated in Phase 5; doc is ~40.2 KB per plan 168's record — inside the 52 KB band, no split needed (re-check at edit time) | residue sweep (Phase 5 item 4) |

Unaffected, with the grep that proves it: `lib/features/**` (no editor change — grep
`_selectedDisciplineId` shows the picker only reads/saves `disciplineId`), `lib/data/models/`
(no field added — grep `healthActivity` over `lib/data/` returns nothing), `watch/sync_protocol`
message schemas beyond the one `$def` (grep `healthActivity` over `schemas/` = `envelope.schema.json`
only), the modality table `activityTypes` and `byModality` (untouched; `sports` stays
`other`/`exercise_type_other_workout` — Swift l.62–64, Dart l.80–82).

## UI Standards Impact

None. No surface, copy or shared UI piece changes; the exercise editor is explicitly out of scope
(owner decision). No `docs/design_system.md` exception.

## Scenarios

### S-17001: every seeded discipline is mapped or explicitly unmapped; custom exercises map the same way
- Fixture: the 37 rows of `SeedData.sampleDisciplines` (`lib/mock/seed_data.dart` l.68–364) as the
  table's key set; the adversarial extras: a custom exercise with `disciplineId: null`, and one
  carrying an id the table does not know (`'discipline-gone'`).
- Trigger: the table-driven Dart test over `WatchReferenceSync.healthActivityOf` (every seeded id,
  one assertion each) plus the set assertion `SeedData.sampleDisciplines ids ⊆ table keys`.
- Flow: each id maps to D-17001's kind or is in the explicit unmapped list (padel → null).
- Expected outcome: 36 kinds + padel null; null discipline → null; unknown id → null; a discipline
  added to seed later fails the test until the table decides. Custom exercises need no special path
  (the resolver reads the row's `disciplineId` the same way).
- Edge case of: S-10511's arms (kept for the original five; the flips are re-pinned here).

### S-17002: the kind does not depend on capabilities
- Fixture: `discipline-yoga` with capabilities `["hold","time","sets"]` (no distance — the seeded
  yoga rows' shape, `watch_reference_sync_test.dart` S-19306); `discipline-swimming` with
  `["time"]`; `discipline-conditioning` rows with no `distance` (the S-19209 rows).
- Trigger: `healthActivityOf` (and one `buildExercisesDown` wire check that the kind travels
  without distance and the envelope validates).
- Expected outcome: `'yoga'`, `'swimming'`, `'conditioning'` — the gate is gone; the envelope the
  kind rides in validates against the widened schema.
- Edge case of: S-17001 (capability-shape coverage).

### S-17003: the wire carries the widened enum, and an unknown name is refused
- Fixture: `watch/sync_protocol/schemas/envelope.schema.json` `$defs/healthActivity` = the 31 kinds;
  NEW `fixtures/valid/exercises_down_health_activity_kinds.json` (rows carrying `swimming`, `yoga`,
  `traditionalStrengthTraining`, `soccer`, `boxing`); EDITED
  `fixtures/invalid/exercises_down_unknown_health_activity.json` (payload value `"swimming"` →
  `"unreal-kind"`); manifest rows for both.
- Trigger: both fixture walkers — `test/sync_protocol_fixtures_test.dart` and
  `SyncProtocolFixturesTests.swift`.
- Expected outcome: every valid fixture conforms (including the new one); the invalid fixture is
  refused with a reason containing the offending value; no other fixture changed.
- Edge case of: S-001 fixtures (the register).

### S-17004: every contract kind resolves; an unknown name falls through, never to Running for a non-distance exercise
- Fixture: the contract's `healthActivityTypes` rows as a table (31 entries); adversarial: kind
  `"unreal-kind"` (a) on a `["reps","sets"]` exercise, (b) on a `["time","distance"]` exercise.
- Trigger: table-driven `forExercise(capabilities:healthActivity:)` on both clients; the unknown
  cases directly.
- Expected outcome: each kind resolves to its contract row (watchos AND wear); `"unreal-kind"` on a
  strength exercise → `traditionalStrengthTraining` (capability chain), on a distance exercise →
  `running` (the distance default, plan 75's rule for a nameless distance exercise); nil kind on
  distance → running; nil kind with `hold` → flexibility (unchanged).
- Edge case of: S-10502 (the five kinds re-pinned by the same table).

### S-17005: the named kind beats capability inference and the modality
- Fixture: a plank (`["hold","time","sets"]`, kind `isometricHolds`); a yoga exercise
  (`["hold","time"]`, kind `yoga`); a swim slot (`["time","distance"]`, kind `swimming`) inside a
  `cardio_endurance` session; a `mobility_flexibility` session of yoga exercises.
- Trigger: `forExercise` and `forSession` (both clients).
- Expected outcome: plank → `functionalStrengthTraining` (the discipline's claim wins over the hold
  inference — **intended flip of S-10503's hold-first rule, owner to confirm**); yoga → `yoga`;
  swim beats the Cardio modality's running; the mobility session of yoga records Yoga, not the
  modality's flexibility.
- Edge case of: S-16804 (named kind beats modality, original five).

### S-17006: majority and ties over the widened set; the type stays fixed at start
- Fixture: a `resistance_lifting` session of five `traditionalStrengthTraining` lifts + one swim
  slot (`swimming`); a free session `[swim slot, run slot]` (1–1 tie); an active session started on
  the swim, then a lift added.
- Trigger: `forSession` and one `refresh` after the insert.
- Expected outcome: `traditionalStrengthTraining` (majority 5–1); `swimming` (earliest of the tie);
  the insert never retypes the open workout (`store.begun.count == 1`).
- Edge case of: S-16805, S-16808 (the rule re-pinned over new kinds).

### S-17007: a sports session records as its sport; an unmapped discipline stays Other
- Fixture: a `sports` session whose slot names `soccer`; a `sports` session whose slot's discipline
  is padel (the phone sends no kind); a `sports` session of a discipline-less exercise.
- Trigger: `forSession` of each.
- Expected outcome: `soccer`; then `other` twice (tier 1 empty → the `sports` modality's generic
  answer, unchanged). **The Fable #9 rule (sports save as Other) now applies only to unmapped
  disciplines.**
- Edge case of: S-8809's sports arm (re-pinned with a typed slot).

### S-17008: the store maps every contract name; unknown is Other
- Fixture: the app target's source text via `storeSource()` (`WatchWorkoutStoreSourceTests.swift`)
  against the contract union.
- Trigger: `testS1509TheStoreMapsEveryContractActivityName` after the contract widens.
- Expected outcome: set equality — the store's `activityType(for:)`/`name(for:)` carry all 23 new
  arms and the reverse, unknown still lands `.other`; a swim named `swimming` opens a Swimming
  workout, a yoga session a Yoga workout.
- Edge case of: S-1509 (the same guard, widened).

### S-17009: the Dart mirror answers what the wrist answers
- Fixture: the same contract table read by the Swift tests
  (`test/watch_sensor_recording_test.dart`'s contract helper, l.994–997, renamed); the S-17005
  session shapes as `WatchSessionRecord`s.
- Trigger: `WatchActivityTypes.forSession` / `forExercise` over the renamed helper's table.
- Expected outcome: identical answers to S-17004/S-17005 on every kind.
- Edge case of: S-16810 (mirror parity, widened).

## Iteration 1

### Phase 1: the wire contract widens (@developer)
1. [ ] Schema amendment D-17004 — `watch/sync_protocol/schemas/envelope.schema.json` ·
  `$defs.healthActivity` (l.73–76): enum becomes the 31 kinds of D-17001; description rewritten to
  "named by the phone from the exercise's discipline; present whenever the phone can name the
  discipline's kind, regardless of capabilities; omitted otherwise (the receiver treats an unknown
  kind as absent)"
2. [ ] Contract D-17006 — `watch/contract/watch_sensor_contract.json` · `distanceActivityTypes`
  (l.85–91) renamed `healthActivityTypes` and widened to the 31 kind rows (watchos + wear per
  D-17001); no `activityTypes` or `genericActivityType` row changes
3. [ ] Valid fixture S-17003 — `watch/sync_protocol/fixtures/valid/exercises_down_health_activity_kinds.json`
  (new; `exercises_down` batch of five exercises carrying `swimming`/`yoga`/
  `traditionalStrengthTraining`/`soccer`/`boxing`, one without `distance`)
4. [ ] Invalid fixture S-17003 — `watch/sync_protocol/fixtures/invalid/exercises_down_unknown_health_activity.json` ·
  the exercise's `healthActivity` value `"swimming"` → `"unreal-kind"` (nothing else changes)
5. [ ] Manifest — `watch/sync_protocol/fixtures/manifest.json`: add the valid entry (path + note);
  update the invalid entry's `expectedReasonContains` (l.771) and `note` (l.772) to the new value —
  if the validator's enum reason does not embed the value, set the reason's actual text and log it
  (Assumption Log)
6. [ ] Narrative — `watch/sync_protocol/PROTOCOL.md` · the `healthActivity` paragraph (l.318–322):
  rewrite to the widened rule (31 kinds, no capability gate, unknown = absent)
7. [ ] Amendment row — same file · the amendment table (after l.925): dated 2026-11-14, superseding
  the 2026-10-24 row — widened enum, gate removed, the one edited invalid fixture and the new valid
  fixture, walkers named, additive, no version change
8. [ ] Verification — both walkers green: `.github/copilot/scripts/macos/gateway.sh test` focused
  on `test/sync_protocol_fixtures_test.dart` and (outside the gateway, or the full Swift run in
  Phase 3's gate) `swift test --package-path watch/watchos --filter SyncProtocolFixturesTests`

**Done Criteria** (run until green): focused `flutter test test/sync_protocol_fixtures_test.dart`;
`SyncProtocolFixturesTests` green; `git-diff` shows only the predicted files. Red at HEAD: the new
valid fixture and the edited invalid fixture fail their walkers before item 1 lands.
**Predicted Files**: `watch/sync_protocol/schemas/envelope.schema.json`,
`watch/contract/watch_sensor_contract.json`,
`watch/sync_protocol/fixtures/valid/exercises_down_health_activity_kinds.json` (new),
`watch/sync_protocol/fixtures/invalid/exercises_down_unknown_health_activity.json`,
`watch/sync_protocol/fixtures/manifest.json`, `watch/sync_protocol/PROTOCOL.md`.

### Phase 2: the store's name map follows the contract (D-17005) (@developer)
1. [ ] Forward arms — `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` ·
  `activityType(for:)` (l.356–369): the 23 new `case`s (each → its `HKWorkoutActivityType`), unknown
  default stays `.other`
2. [ ] Reverse arms — same file · `name(for:)` (l.374–385): the same 23 `case`s reversed
3. [ ] Doc comment — same file · l.348–355: section name becomes `healthActivityTypes`, the count
  and the D-17001/plan-170 references updated
4. [ ] Guard — `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutStoreSourceTests.swift` ·
  `contractActivityNames()` (l.37–56): read the renamed `healthActivityTypes` key;
  `testS1509TheStoreMapsEveryContractActivityName` (l.222) then proves set equality (red before
  items 1–2, green after — the S-1509 guard is the phase's own red/green proof)

**Done Criteria**: `swift test --package-path watch/watchos --filter WatchWorkoutStoreSourceTests`
green; full `swift-test` in Phase 3's gate; `git-diff` shows only the predicted files.
**Predicted Files**: `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutStoreSourceTests.swift`.

### Phase 3: the wrist resolves every kind (D-17003) (@developer)
1. [ ] Resolution — `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` ·
  `distanceType(_:)` (l.139–147) becomes `kindType(_:) -> WatchActivityType?` over the full kind
  table (nil for nil/unknown; the five originals keep their rows), the private per-kind constants
  gain the new ones
2. [ ] Kind-first — same file · `forExercise` (l.160–175): `if let t = kindType(healthActivity) { return t }`
  before the hold/distance/strength chain; drop `namedHealthKinds` (l.186–189) and map
  `forNamedHealthKinds` (l.193–207) through `kindType`, dropping nils; update `forSession`'s doc
  comment (l.208–214) to name plan 170
3. [ ] Flips re-pinned — `watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityTests.swift` ·
  S-10502 "an unknown kind stays running" → `"unreal-kind"` on distance (stays running) and on
  reps/sets (→ strength); S-10503 both tests → the kind wins (cycling kind on hold → cycling; on
  reps-only → cycling), each with the D-17003 reason
4. [ ] Table-driven tests S-17004, S-17005, S-17006, S-17007 — same file (new group
  `S-17004 the kind table resolves on the wrist`): every contract kind → its row; unknown
  fall-through; plank → functional strength; yoga beats hold and the mobility modality; swim beats
  cardio; 5-strength+1-swim majority, swim+run earliest tie; soccer and padel in a sports session
5. [ ] Contract tests D-17006 — `watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityContractTests.swift` ·
  all four tests (l.16–55): key renamed, key-set assertion becomes the 31 kinds, wear rows asserted
  per kind (table-driven over the file), `testS10507ActivityTypesRowsAreUnchanged` stays
6. [ ] Neighbours green: `WatchWorkoutTypeFromExercisesTests` (S-16804–S-16808, S-8801–S-8811),
  the rest of `WatchHealthActivityTests` (S-10504–S-10508 — the round-trip tests pass strings
  through and stay green), `WatchRoutineFocusTests`

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh swift-test` (full, 900 s) — up by the
new tests' count, zero regressions; focused filters `--filter WatchHealthActivityTests`,
`--filter WatchHealthActivityContractTests`, `--filter WatchWorkoutTypeFromExercisesTests`;
`git-diff` shows only the predicted files. Red at HEAD: items 4's new tests fail before items 1–2
land (the table only knows five names).
**Predicted Files**: `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityContractTests.swift`.

Phase 2 needs only Phase 1 (contract); Phase 3 needs only Phase 1; they may run in either order.
**Intermediate state after Phase 3 without Phase 4**: the wrist can resolve names the phone does
not send yet — harmless, no mislabeling.

### Phase 4: the phone derives the kind for every discipline (D-17001/D-17002) (@developer)
1. [ ] Mapping — `lib/core/utils/watch_reference_sync.dart` · `healthActivityOf` (l.596–614):
  signature `({required String? disciplineId, required String exerciseId})`, the distance gate
  removed, the switch replaced by the D-17001 table (a `static const Map<String, String>` of
  discipline → kind beside it, plus the Hike/Rucking `exerciseId` special case and the padel
  null), doc comment rewritten (no longer "a distance exercise")
2. [ ] Call site — same file · `_ExerciseResolver.resolve` (l.89): drop the `capabilities:` argument
3. [ ] Call site — `lib/state/watch/watch_session_adoption_bridge.dart` · `_slotFor` (l.589): drop
  the `capabilities:` argument
4. [ ] Table-driven tests S-17001, S-17002 — `test/watch_health_activity_test.dart` · new group
  `S-17001 the discipline table covers every seeded discipline` (imports `SeedData`; one assertion
  per seeded id + the subset assertion + null/unknown-id/custom cases; also the S-17002
  capability-independence cases and one `buildExercisesDown` wire check whose envelope validates —
  reuse the S-10512/S-10513 harness shapes); re-pin the three S-10511 arms that flip
  (swimming → `'swimming'`, machine-cardio → `'mixedCardio'`, cycling-without-distance →
  `'cycling'`)
5. [ ] Flip — `test/watch_reference_sync_test.dart` · S-19306 (l.655–693): the yoga rows carry
  `'yoga'` and `healthActivityOf(discipline-yoga, …)` answers `'yoga'`
6. [ ] Flip — `test/conditioning_catalog_test.dart` · S-19209 (l.11–12, l.137–172): the seeded
  conditioning rows carry `'conditioning'` on the wire and from `healthActivityOf`
7. [ ] Slot end-to-end — `test/watch_health_activity_test.dart` · group `S-10513 the session slot`:
  add one case — a custom yoga exercise slot carries `'yoga'` and the snapshot envelope validates

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test` (full `flutter test`, 900 s) —
zero regressions beyond the plan-167/168 in-flight reds already recorded in plan 168's Assumption
Log (`watch_session_import_test.dart`, `watch_session_adoption_bridge_test.dart`,
`watch_convergence_harness_test.dart`); focused runs `flutter test test/watch_health_activity_test.dart
test/watch_reference_sync_test.dart test/conditioning_catalog_test.dart`; `gateway.sh lint`
compared against the 183 pre-existing notices plan 168 recorded (no new issues); `git-diff` shows
only the predicted files. Red at HEAD: items 4–6 fail before item 1 lands.
**Predicted Files**: `lib/core/utils/watch_reference_sync.dart`,
`lib/state/watch/watch_session_adoption_bridge.dart`, `test/watch_health_activity_test.dart`,
`test/watch_reference_sync_test.dart`, `test/conditioning_catalog_test.dart`.

**Intermediate state after Phase 4 without Phase 5**: a distance swim's kind now reaches the wrist
but `distanceType`'s default still answers running — exactly today's behaviour for a swim (no kind
→ running), so no regression, just no win until Phase 5. The mirror is otherwise behind the wrist.

### Phase 5: the Dart mirror moves with the rule; docs (@developer)
1. [ ] Mirror D-17003 — `lib/watch/sensors/watch_platform_workout.dart` · `_distanceType`
  (l.121–131) → `_kindType` returning `WatchActivityType?` (nil unknown) over the full table (a
  `static const Map<String, WatchActivityType>` mirroring the contract rows, the five originals
  unchanged); `_forExercise` (l.206–219) consults it first; `_namedHealthKinds` (l.222–229) dropped,
  `_forNamedHealthKinds` maps through `_kindType` dropping nils; the file-header paragraph (l.10–11)
  names plan 170
2. [ ] Mirror parity S-17009 — `test/watch_sensor_recording_test.dart` · the contract helper
  (l.994–997) reads `healthActivityTypes`; new group `S-17009 the mirror maps every Health kind
  like the wrist`: every kind → its row via `forExercise`, plus the S-17005 session shapes through
  `forSession` and `WatchPlatformWorkout.start` over `_FakePlatformStore` (l.107)
3. [ ] Docs — `docs/state_management/watch_sensors.md` · the `forSession` paragraph (l.141–157):
  the five-kind list becomes the widened table (summarised, citing the contract file and D-17001),
  the capability chain reordered to kind-first, the plank/yoga consequences named; the
  "carries the modality table only" sentence (l.525–533) names the kind table too
4. [ ] Residue sweep — grep the repo for stale claims: `distanceActivityTypes`, "only for
  exercises with the distance capability", "swimming" as a refusal example outside history
  (`PROTOCOL.md` amendment rows are historical records and stay), `namedHealthKinds`,
  `distanceType` — zero readers of the replaced representations remain outside the plan-75/plan-168
  historical plan docs

**Done Criteria**: `.github/copilot/scripts/macos/gateway.sh test` (full, 900 s) — zero regressions
beyond the recorded in-flight reds; `.github/copilot/scripts/macos/gateway.sh swift-test` (full,
900 s) green; `gateway.sh lint` vs the 183-notice baseline; `git-diff --name-only` shows only the
predicted files. Red at HEAD: item 2's group fails before item 1 lands.
**Predicted Files**: `lib/watch/sensors/watch_platform_workout.dart`,
`test/watch_sensor_recording_test.dart`, `docs/state_management/watch_sensors.md`.

## Files Affected (whole feature; mark dependents that only read a touched surface)

- `watch/sync_protocol/schemas/envelope.schema.json` — Phase 1
- `watch/contract/watch_sensor_contract.json` — Phase 1
- `watch/sync_protocol/fixtures/valid/exercises_down_health_activity_kinds.json` — new, Phase 1
- `watch/sync_protocol/fixtures/invalid/exercises_down_unknown_health_activity.json` — Phase 1
- `watch/sync_protocol/fixtures/manifest.json` — Phase 1
- `watch/sync_protocol/PROTOCOL.md` — Phase 1
- `ios/OmniTrain Watch App/HealthKitWorkoutStore.swift` — Phase 2 (only its name tables; plan
  168's diagnostics notes read them but keep their shapes)
- `watch/watchos/Tests/WatchSessionEngineTests/WatchWorkoutStoreSourceTests.swift` — Phase 2
- `watch/watchos/Sources/WatchSessionEngine/WatchPlatformWorkout.swift` — Phase 3
- `watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityTests.swift` — Phase 3
- `watch/watchos/Tests/WatchSessionEngineTests/WatchHealthActivityContractTests.swift` — Phase 3
- `lib/core/utils/watch_reference_sync.dart` — Phase 4
- `lib/state/watch/watch_session_adoption_bridge.dart` — Phase 4 (one call site)
- `test/watch_health_activity_test.dart`, `test/watch_reference_sync_test.dart`,
  `test/conditioning_catalog_test.dart` — Phase 4
- `lib/watch/sensors/watch_platform_workout.dart`, `test/watch_sensor_recording_test.dart` — Phase 5
- `docs/state_management/watch_sensors.md` — Phase 5

## Notes

- **Phase graph**: 1 → {2, 3, 4}; 5 needs 3 + 4. Running 2 before 3 is safest (the store can name a
  type before the wrist starts producing it). Phase 4's fixture checks need Phase 1's schema only.
- **Intermediate states**: after 1–2 the wire and the store accept more than the phone sends; after
  3 the wrist resolves more than the phone sends; after 4 a distance swim still records running
  (today's behaviour) until 5 lands. No intermediate state is a regression against HEAD.
- **In-flight builders**: the tree carries plan 167/168 work (plan 168's Assumption Log records the
  pre-existing Dart reds and the 183-notice lint baseline). Compare counts, never absorb.
- **No deletions or directory creation needed**: the invalid fixture is edited in place (no rename),
  and the plan folder exists. No scratch files.
- **Owner device spot-check** (optional, after all phases): a swim and a yoga walk show Swimming /
  Yoga in Fitness; a plank shows Functional Strength Training (the intended flip).
- No new diagnostics note kinds; `watch_diagnostics.md` is untouched (Phase 2 reuses the existing
  `workout_saved`/`workout_end` note shapes through the widened name table).

## Progress

- [x] Phase 1 — wire contract widened — enum 32 names, `healthActivityTypes`, new valid fixture, edited invalid fixture, PROTOCOL row `1 (amended)`; fixtures 182 passed, RED AT HEAD
- [x] Phase 2 — store name map follows the contract — 23 forward + 23 reverse arms; `WatchWorkoutStoreSourceTests` 3 passed
- [x] Phase 3 — wrist resolves every kind — `kindTypes`/`kindType`, kind-first `forExercise`, S-17004–S-17007; 52 passed, RED AT HEAD (74 failures)
- [x] Phase 4 — phone derives the kind for every discipline — table of 36, capability gate gone, S-17001/S-17002/S-10513; 84 passed, RED AT HEAD (+72 −6)
- [x] Phase 5 — mirror parity, docs, residue sweep — `_kindTypes` mirror, S-17009; 45 passed; docs updated; full `test` `+7626 ~4 -1` (the only red is the pre-existing S-15207 corpus staleness), `swift-test` 1456/0, lint 181, UI standards 41 — see `2026-11-14-170-health-type-from-discipline-plan.evidence.md`

## Assumption Log

- **`expectedReasonContains` follows the payload value.** The manifest asserts the refusal reason
  contains `"swimming"` today, so the enum reason is assumed to embed the offending value; the
  edited fixture sets `"unreal-kind"` and the manifest follows. If the reason text does not embed
  the value, set the validator's actual text and record it here.
- **Health Connect spellings marked \*** are the implementer's best reading of the Health Connect
  `EXERCISE_TYPE_*` list (tableTennis, rugby, soccer→football, boxing, calisthenics,
  stretch/flexibility, kickboxing→martial_arts, the Other fallbacks). Each is pinned by the contract
  tests, so a correction is a one-line contract change plus the twin assertion. Owner to confirm.
- **Kind-first resolution flips three pinned rules** (S-10503 hold-first, S-19306 "a hold records
  as it always has", S-19209 "no Health kind"): planks record Functional Strength Training, yoga
  beats the hold inference and the mobility modality. The alternative (capability inference first)
  would keep the kind unconsulted for every hold exercise and contradict D-17002's capability
  independence at the wrist. Owner to confirm.
- **No migration** for existing stored exercises: the kind derives at sync time from the persisted
  `disciplineId`; no Hive field, model or seed-schema change (verified by grep: no `healthActivity`
  in `lib/data/`).
- **The contract has 32 rows, not 31.** `healthActivityTypes` carries the 31 discipline kinds plus
  `hiking` (the Hike/Rucking special case), and the schema enum lists the same 32 names; the plan's
  "31" counted the discipline kinds only. Every table assertion pins 32.
- **`expectedReasonContains` was left at the payload's value.** The enum refusal embeds the offending
  name, so the edited invalid fixture (`"unreal-kind"`) passes with the reason row updated to it.
- **The amendment row is numbered `1 (amended)`.** The PROTOCOL table is keyed by count, so the new
  dated row (2026-11-14) restates the row it supersedes.
- **`flexibility` wears `exercise_type_stretching`**, while the modality table's
  `_flexibility` rows keep `exercise_type_flexibility`: the kind row is the contract's, the modality
  rows are untouched (S-10507's wear pin and `testS007EveryMappedModalityNamesBothPlatforms`).

## Feedback

[empty]

Build after plan 168 is committed.
