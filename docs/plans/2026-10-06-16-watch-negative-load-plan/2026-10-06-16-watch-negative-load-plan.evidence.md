# Evidence — a negative load (band assist) on a set works on the phone and the watch

Plan: `2026-10-06-16-watch-negative-load-plan.md`. Implementers append; the Planner does not fill
this in. One row per Done-Criterion command, with the **observed** counts pasted, not a claim.

## Baselines (from the brief, re-observe before your first change)

| Command | Baseline |
|---|---|
| `flutter test` | 3949 passed / ~1 skipped / 0 failed |
| `flutter analyze` | 196 issues / 0 errors |
| `swift test` | 294 passed / 0 failed |

## Phase 1 — the contract (@dba)

No `lib/` or Swift source changed: both validators are generic schema walkers (Dart
`lib/core/sync_protocol/message_validator.dart`, Swift `SyncProtocolValidator.swift`), so the phase is
schemas + fixtures + spec only. `SyncProtocolFixturesTests.swift` walks the manifest generically, so
the watchOS suite exercises the six new fixtures with no Swift edit.

### Done Criteria — observed

| Command | Result |
|---|---|
| `gateway.sh test test/sync_protocol_fixtures_test.dart` | `00:00 +85: All tests passed!` (85 passed / 0 failed) |
| `gateway.sh test test/watch_reconciliation_cross_stack_test.dart` | `00:00 +19: All tests passed!` (19 passed / 0 failed) |
| `gateway.sh test` (full) | `01:40 +3963 ~1: All tests passed!` — 3963 passed / 1 skipped / 0 failed (baseline 3949) |
| `gateway.sh lint` | `196 issues found` — unchanged from the baseline; all `info`, none in a touched file |
| `gateway.sh swift-test` | `Executed 294 tests, with 0 failures` (baseline 294; the suite walks the same manifest) |

### Red first (new fixtures against the old floors)

`gateway.sh test test/sync_protocol_fixtures_test.dart` before widening any schema —
`00:00 +76 -9: Some tests failed.`:

| Failing test | Reason |
|---|---|
| `S-001 fixtures valid/observations_up_band_assist.json conforms` | `constraint_violation at $.payload.events[1].loadKg: expected at least 0, found -20` |
| `S-001 fixtures valid/session_snapshot_band_assist.json conforms` | `constraint_violation at $.payload.entries[0].loadKg: expected at least 0, found -20` |
| `S-001 fixtures valid/structure_change_band_assist.json conforms` | `constraint_violation at $.payload.changes[6].correction.loadKg: expected at least 0, found -20` |
| `S-001 fixtures valid/routines_down_band_assist.json conforms` | `constraint_violation at $.payload.routines[0].segments[0].efforts[0].targets.loadKg: expected at least 0, found -20` |
| `S-001 fixtures invalid/observations_up_load_below_floor.json is rejected` | reason was `expected at least 0, found -240`, not `expected at least -200` |
| S-58 / S-59 / S-65/S-66 assertions (4) | same `expected at least 0` rejections |

### Mutations (each reverted to the exact original, green re-run after)

| # | Mutation | Red observed | Restored |
|---|---|---|---|
| a1 | `envelope.schema.json` `$defs.metricTargets.loadKg` `-200` → `0` | `+83 -2` — `valid/routines_down_band_assist.json` and S-65/S-66 "a routine target may carry an assist down to the floor" | yes, `-200` |
| a2 | `envelope.schema.json` `$defs.entry.loadKg` `-200` → `0` | `+80 -5` — both snapshot/observations fixtures, the invalid fixture (reason wording) and S-58 + S-59 | yes, `-200` |
| a3 | `structure_change.schema.json` `$defs.correction.loadKg` `-200` → `0` | `+83 -2` — `valid/structure_change_band_assist.json` and S-65 "a correction may carry an assist down to the floor" | yes, `-200` |
| b | `invalid/observations_up_load_below_floor.json` `loadKg` `-240` → `-200` | `+84 -1` — "is rejected as constraint_violation": `Expected: non-empty, Actual: []` | yes, `-240` |
| c | `reconciliation/band_assist_carried.json`, second snapshot's third entry re-stated under a new id (`entry-slot-bench-1` → `entry-slot-bench-9`) | `+17 -1` — S-67 "a re-stated assist is neither duplicated nor zeroed": map missing `entry-slot-bench-1` | yes, `entry-slot-bench-1` |

Re-run after all restores: `gateway.sh test test/sync_protocol_fixtures_test.dart
test/watch_reconciliation_cross_stack_test.dart` → `00:00 +104: All tests passed!`.

### Rejection wording (shared by both stacks)

Dart `message_validator.dart` renders `'expected at least $minimum, found $value'`; the Swift
validator renders the same with `trim(minimum)`. Both emit `expected at least -200, found -240`, so
the manifest's `expectedReasonContains` is the stack-neutral substring `expected at least -200`.

## Phase 2 — the phone (@developer)

(to be filled by the implementer)

## Phase 3 — the wrist and the residue sweep (@developer)

(to be filled by the implementer)

## Red → green (required for every rule this feature reverses)

D-60 reverses the negative half of `A-14`/`F1`, D-61 and D-62 change two floors. For each, paste the
failing run taken **before** the source change and the passing run after, same command both times:

| Rule | Test | Before the fix | After the fix |
|---|---|---|---|
| D-60 projection | `test/watch_session_projection_test.dart` S-59/S-60 | (paste failure) | (paste pass) |
| D-62 floor | `test/watch_logging_stepping_test.dart` S-61 | (paste failure) | (paste pass) |
| D-61 emitter | `test/watch_logging_surfaces_test.dart` S-62 | (paste failure) | (paste pass) |
| D-63 correction floor | `test/watch_session_import_test.dart` S-65 | (paste failure) | (paste pass) |
