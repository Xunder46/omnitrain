# Series 115 — Strength gaps in the bundled exercise library (index)

Owner request 2026-11-04: fill the strength-training gaps so users rarely need a custom exercise, and add
three muscles (Abductors under Legs, Rotator cuff under Shoulders, Brachialis under Arms). No new sports and
no sports re-tagging. This series is the first of three catalog efforts (later: conditioning/plyometrics,
then yoga; not planned here).

Why a series: 48 new exercises are about 1,000 production lines of seed data plus 6+ phases, which is over
`.github/copilot/pr-scope-budget.md` (more than 3 phases, a plan over 500 lines, and a missing prerequisite:
the catalog refresh does not deliver equipment). Each PR is planned when its turn comes, against the code as
it is by then.

| PR | Scope | Depends on | Plan |
|---|---|---|---|
| 115a | The three muscles; Cable Hip Abduction, Cable External Rotation and Hammer Curl re-tagged; 28 exercises: the 16 that use the new muscles or train arms, and 12 machine/isolation lifts; catalog version 14 | plan 114 committed | `2026-11-04-115a-strength-catalog-gaps-plan/` |
| 115b | 20 exercises: core (Sit-Up, Crunch, Reverse Crunch, Bicycle Crunch, Russian Twist, Hanging Knee Raise, Dead Bug, Bird Dog, Cable Side Bend), legs/hips (Trap-Bar Deadlift, Rack Pull, Lateral Lunge, Curtsy Lunge, Single-Leg Hip Thrust, Donkey Calf Raise, Leg Press Calf Raise, Reverse Hyperextension, Sled Push, Sled Drag), Push Press; two equipment rows (Trap Bar, Sled); catalog version 15 | 115a | not planned |

## Shared decisions (bind both PRs; full text in the 115a Ledger)

- Every new exercise is a bundled row in `SeedData` with discipline `discipline-bodybuilding`, a capability
  row, a muscle-link row and an equipment row. It reaches existing installs through a catalog version bump
  (D-18905, D-18906).
- The text rules (description, how-to steps) and the capability rules (D-18907, D-18908) apply to 115b too.
- Equipment is tagged in the seed only. The refresh does not deliver it, and no screen shows it (D-18909,
  owner Q1).
- Rows the user owns are never rewritten: touched bundled rows, copies, and custom exercises, including a
  custom one with the same name as a new bundled one (D-18910, owner Q4).
- Ids: 115a uses `S-18901..` and `D-18901..`; 115b uses `S-19001..` and `D-19001..`.

## Known for 115b (not decided here)

- `Trap Bar` and `Sled` equipment ids do not exist (`grep -n "equipment-" lib/mock/seed_data.dart`).
  Adding them costs about 10 seed lines and 2 SQL lines. Existing installs never receive new equipment rows
  either: `sampleEquipment` is written only at first install (`hive_workout_repository.dart:634`).
- `scripts/sqlite_seed.sql` lacks `Cable Machine` and `Machine` (8 equipment inserts versus 10 in the seed).
  115b fixes this in the same block (4 lines).
- Sled Push and Sled Drag follow Farmer's Carry: capabilities `time, distance, load`. With the bodybuilding
  discipline, the watch's Health mapping returns no activity type for them
  (`watch_reference_sync.dart:500-519`), the same as Farmer's Carry.

## Compatibility note for the later catalog PRs (conditioning, yoga)

The refresh delivers neither disciplines nor equipment. `CatalogSource`
(`lib/core/services/catalog_source.dart`) has exercises, capabilities, muscle groups, links, foods and
routines only. A **new** discipline (for example "Plyometrics") would reach new installs only, and on
updated installs its exercises would point at a discipline the device lacks: they rank lower in the picker
because they get no discipline points. Yoga already exists (`discipline-yoga`). The conditioning PR must
either reuse an existing discipline or first add discipline delivery to the refresh (about 1 @dba phase).
