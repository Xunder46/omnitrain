# Plan 36b — planned sets and presets (evidence)

Written by Phase D (docs keeper) from the builders' reports and the lead's
mutation log. Every code claim below was re-read in the file named this run.

## Baselines (plan floor -> measured after Phases A1 + A2 + B)

| Check | Floor at seed | Measured |
| --- | --- | --- |
| `flutter analyze` | not above 182 | 182 (unchanged) |
| `flutter test` (full suite) | not below `+4697 ~1` | `+4708 ~1` |
| `swift test` (`watch/watchos`) | not below 580 | 591 |

All 11 new Swift tests are in
`watch/watchos/Tests/WatchSessionEngineTests/WatchPlannedSetsTests.swift`
(S-3623 x1, S-3624 x1, S-3625 x4, S-3626 x1, S-3627 x1, S-3628 x1, S-3631 x1,
S-3632 x1). The Dart side adds the group `S-3621 the phone sends the planned
sets` (7 tests) in `test/watch_session_projection_test.dart` and
`S-3622 a planned-value edit moves the revision` in
`test/watch_session_adoption_bridge_test.dart`, plus the three generated
S-001 fixture tests in `test/sync_protocol_fixtures_test.dart`.

## Red before green

- **A1 (wire) — red output kept** (`.work/crew/2026-10-15-36b-planned-sets/report-A1.md`):
  the three fixtures were built and the walker run before the schema declared
  the field — `flutter test test/sync_protocol_fixtures_test.dart` →
  `00:00 +89 -3: Some tests failed.`, the valid fixture refused
  `unexpected_field at $.payload.exercises[0].plannedSets`, the bad-reps
  fixture refused `unexpected_field` instead of `constraint_violation`, and the
  unknown-key fixture's reason named the missing `setNumber`. After the schema
  change: `00:00 +121: All tests passed!` (118 before → +3).
- **A2 (phone) and B (wrist) — written red-first; the red output was not
  kept.** The new tests (S-3621, S-3622; S-3623..S-3628, S-3631, S-3632) were
  written and run against the unmodified production code and failed there
  before the production change was made, but the lead did not preserve the red
  run's output. The proof of red-before-green for these phases is the mutation
  list below, which re-creates each production change's absence one at a time
  and shows the tests fail without it.

## Proof mutations (applied by the lead, each restored byte for byte, each re-run green)

| # | Mutation | Site (read this run, restored form) | Result when applied |
| --- | --- | --- | --- |
| P1 | `if (groups.isNotEmpty)` → `if (false)` | `projectSession`, `lib/state/watch/watch_session_adoption_bridge.dart:238` | 6 failures across `test/watch_session_projection_test.dart` + `test/watch_session_adoption_bridge_test.dart` |
| P2 | `reps >= 1` → `reps >= 0` | `_plannedSetOf`, same file `:566` | 2 failures |
| P3 | drop `weightKg != 0 &&` | `_plannedSetOf`, same file `:567` | 1 failure |
| P4 | drop the `plannedSets` segment of `_ladderOf` | same file `:588` | 1 failure (`S-3622 a planned-value edit moves the revision`) |
| W1 | disable the planned branch in `initialValue(for:)` | `WatchLoggingState.swift:606` | 14 failures in `WatchPlannedSetsTests` (11 tests) |
| W2 | planned index + 1 (`planned[setsHeld]` → `planned[setsHeld + 1]`) | `WatchLoggingState.swift:607` | 6 failures |
| W3 | `setsHeld` not kind-filtered | `WatchLoggingState.swift:512` | 6 failures |
| W4 | caption `max(planned.count, setsHeld + 1)` → `planned.count` | `WatchLoggingState.swift:278` | 2 failures |
| W5 | drop the `effortKind == set` gate | `WatchLoggingState.swift:502` | 3 failures |
| C1 | schema `reps` `minimum` 1 → 0 | `watch/sync_protocol/schemas/envelope.schema.json:144` | the invalid-fixture test fails: `+120 -1` in `test/sync_protocol_fixtures_test.dart` |

## Doc-claim → test table (`docs/watch_session_sync.md`, Phase D edits)

| Claim (as the doc states it) | Test (exact name, read this run) |
| --- | --- |
| A `set` slot carries `plannedSets`, one item per set row, in set order, logged rows included | `test/watch_session_projection_test.dart` · group `S-3621 the phone sends the planned sets` · `S-3621 a set slot carries every planned row, in set order` |
| A logged set keeps its place in the plan | same file · `S-3621 a logged set is a planned set too` |
| `reps` omitted for a row with fewer than 1 rep | same file · `S-3621 a row with no reps carries only its load` |
| `loadKg` omitted at 0 | same file · `S-3621 a bodyweight row carries only its reps` |
| `loadKg` omitted below the wire's floor, never clamped | same file · `S-3621 a load below the wire's floor is omitted, never clamped` |
| A non-`set` slot carries no key | same file · `S-3621 a timed slot carries no key, whatever rows it holds` |
| A slot with no rows carries no key | same file · `S-3621 an effort with no rows carries no key` |
| A change to a planned value raises the projected revision | `test/watch_session_adoption_bridge_test.dart` · `S-3622 a planned-value edit moves the revision` |
| The wrist starts each set from `plannedSets[setsHeld]` (reps, load) | `WatchPlannedSetsTests.swift` · `testS3623TheWristStartsEachSetFromItsPlannedValues` |
| A phone-logged set counts towards the set number | same file · `testS3624APhoneLoggedSetCountsTowardsK` |
| No key → no caption, kind defaults stand | same file · `testS3625ASlotWithNoPlannedSetsHasNoCaption` |
| A timed slot carrying the key ignores it | same file · `testS3625ATimedSlotCarryingTheKeyIgnoresIt` |
| A row without `loadKg` is a planned zero load | same file · `testS3625APlannedRowWithoutALoadShowsZero` |
| A row without `reps` falls back to the old chain | same file · `testS3625APlannedRowWithoutRepsFallsBackToTheOldChain` |
| The planned load shows through the saved unit (stored in kg) | same file · `testS3626APlannedLoadShowsThroughTheSavedUnit` |
| Every row logged → the extra set reads "Set 4 of 4" and carries the last logged | same file · `testS3627AFullyLoggedSlotReadsSetFourOfFour` |
| The wrist's own unconfirmed set counts in `setsHeld` | same file · `testS3628AWristLoggedSetCountsBeforeThePhoneConfirms` |
| A slot declaring another kind ignores the key | same file · `testS3631ASlotThatDeclaresAnotherKindIgnoresTheKey` |
| A hold ignores the key | same file · `testS3632AHoldSlotIgnoresTheKey` |
| The logging header shows "Set k of N" | `WatchLoggingView.swift` `header` renders `model.state.setCaption`; the string is pinned by `testS3623TheWristStartsEachSetFromItsPlannedValues` (no view test exists — `WatchLoggingView` is `#if os(watchOS)`, outside `swift test`) |
| Planned rows are still sent as nothing in `entries` | `test/watch_session_projection_test.dart` · `S-3601 a session of planned rows sends no entry`, `S-3602 only the set a rest follows is sent`, `S-3603 a logged set with no reps is still no entry` (kept from plan 36a, re-verified this run) |

## Not done yet (stated plainly)

- Planned timed/hold/round durations are not sent: the wire gives a non-`set`
  slot no planned rows, and a round slot's only planned value is the round
  length `roundDurationSecs` it already carried (verified against
  `envelope.schema.json` and `WatchRoutineRecords.toSlot` this run).
- A routine started on the wrist still opens on the phone as a free session
  without sets (plan 36c). The wrist's `startFromRoutine` builds its slots
  without `plannedSets` (`WatchStartPaths.swift:522`,
  `WatchRoutineRecords.swift:187`), so the adopted phone session holds no
  planned rows; no test pins the adoption of a wrist-started routine session.
- The Wear OS client `lib/watch/**` is unchanged by this plan.
- The plan file's Progress table is outside this phase's write scope and was
  not ticked; the governor or lead does that.
