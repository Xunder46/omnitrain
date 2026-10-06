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

Starting point is Phase 1's committed HEAD (`69bddeb`): `gateway.sh test` `01:40 +3963 ~1`, `lint`
196 issues / 0 errors, `swift-test` 294 / 0 (no Swift source changed in this phase, so it was not
re-run).

### Files

| File | Change |
|---|---|
| `lib/core/sync_protocol/wire_limits.dart` | new — `abstract final class WireLimits { static const double minLoadKg = -200.0; }`, the one constant (D-59) |
| `lib/core/sync_protocol/phone_entries.dart` | `_entry` floors at `WireLimits.minLoadKg` and writes `loadKg` only when it is non-zero (D-58, D-60) |
| `lib/core/services/watch_session_importer.dart` | the correction floor `>= 0` → `>= WireLimits.minLoadKg` (D-63) |
| `test/watch_wire_limits_test.dart` | new — S-061 |
| `test/watch_session_projection_test.dart` | S-59/S-60 replace S-42; S-2 now asserts the zero-load key is absent |
| `test/watch_session_import_test.dart` | S-58, S-63, S-65 |
| `test/watch_reference_sync_test.dart` | S-66 |
| `docs/watch_session_sync.md` | the "cannot carry" bullet rewritten (item 9) |

### Done Criteria — observed

| Command | Result |
|---|---|
| `gateway.sh test test/watch_wire_limits_test.dart test/watch_session_projection_test.dart test/watch_session_import_test.dart test/watch_reference_sync_test.dart test/watch_reconciliation_cross_stack_test.dart` | `00:00 +112: All tests passed!` (112 passed / 0 failed) |
| `gateway.sh test test/watch_reconciliation_cross_stack_test.dart` (step 7) | `00:00 +19: All tests passed!` — S-67 was already green from Phase 1 (A-P2-3) |
| `gateway.sh test` (full) | `01:40 +3973 ~1: All tests passed!` — 3973 passed / 1 skipped / 0 failed (Phase 2 start 3963; delta +10 = the new tests) |
| `gateway.sh lint` | `196 issues found` — unchanged from the baseline; every issue `info`, none in a touched file |
| `gateway.sh format` | `0 changed` (new file formatted by explicit path only) |
| invariant grep | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → only `lib/main.dart`, unchanged |
| `git-diff --stat` | 7 files, `+439 / -57` |

### Red first (each mutation reverted to the exact original; green re-run after)

| # | Mutation | Observed red | Restored |
|---|---|---|---|
| A | `phone_entries.dart`: drop the floor (`if (weightKg < WireLimits.minLoadKg) return null;` removed) | `S-60 the floor is carried, one step below it is not [E]` — `Expected: ['entry-slot-bench-0', 'entry-slot-bench-3']` / `Actual: ['entry-slot-bench-0', 'entry-slot-bench-1', 'entry-slot-bench-2', 'entry-slot-bench-3']` | yes |
| B | `watch_session_importer.dart`: correction floor back to `>= 0` | `S-65 a band assist corrects down to the floor and no further [E]` — `Expected: <-200.0>` / `Actual: <-20.0>` (the −200 correction is refused, so the field keeps its previous value) | yes |
| C | `wire_limits.dart`: `minLoadKg = -100.0` | all three S-061 tests `[E]` — `Expected: <-100.0>` / `Actual: <-200.0>` | yes, `-200.0` |
| D | `phone_entries.dart`: `<` → `<=` on the floor | `S-60 … [E]` — `Actual: ['entry-slot-bench-3']`, `at location [0] is 'entry-slot-bench-3' instead of 'entry-slot-bench-0'` (the −200 row is dropped instead of carried) | yes |
| E | `phone_entries.dart`: the pre-change `if (weightKg < 0) return null;` | `S-59 a snapshot carries the assist, and omits only the row without reps [E]` — `Expected: {'entry-slot-bench-0': -20.0, 'entry-slot-bench-1': 60.0}` / `Actual: {'entry-slot-bench-1': 60.0}`, `missing map key 'entry-slot-bench-0'` | yes |
| F | `phone_entries.dart`: the pre-change unconditional `entry['loadKg'] = weightKg;` | `S-2 a running phone session is answered with its own ladder [E]` — `Expected: false` / `Actual: <true>` (D-60: a zero weight still sends no `loadKg`) | yes |

A and D were run as `gateway.sh test test/watch_session_projection_test.dart --plain-name "S-60 the
floor is carried"`; B inside the full suite; C as `gateway.sh test test/watch_wire_limits_test.dart`;
E and F as `gateway.sh test test/watch_session_projection_test.dart --plain-name "<the test>"`.

### The S-65 fixed-clock discovery (a full-suite failure that only the full suite could show)

`gateway.sh test` run #1 came back `+3972 ~1 -1`: S-65 failed in the full run while passing alone in
its own file. Cause is a real rule, not flakiness — `WatchSessionInbox` stamps every correction with
its clock and `WatchSessionImporter._effectiveEntry` accepts a correction only when
`correction.receivedAtMs > at` for that field, so with the file's fixed `_phoneNow` the second
correction to one metric was a silent no-op. Fix: the file-local `_inbox` helper takes an optional
`clock`, and S-65 advances a second between messages (A-P2-2). Any later multi-correction test must
do the same.

## Phase 3 — the wrist and the residue sweep (@developer)

(to be filled by the implementer)

## Red → green (required for every rule this feature reverses)

D-60 reverses the negative half of `A-14`/`F1`, D-61 and D-62 change two floors. For each, paste the
failing run taken **before** the source change and the passing run after, same command both times:

| Rule | Test | Before the fix | After the fix |
|---|---|---|---|
| D-60 projection | `test/watch_session_projection_test.dart` S-59/S-60 | `S-59 … [E]` — `Expected: {'entry-slot-bench-0': -20.0, 'entry-slot-bench-1': 60.0}` / `Actual: {'entry-slot-bench-1': 60.0}`, `missing map key 'entry-slot-bench-0'`; `S-60 … [E]` — `Actual: ['entry-slot-bench-0', 'entry-slot-bench-1', 'entry-slot-bench-2', 'entry-slot-bench-3']` | `00:00 +112: All tests passed!` (five Phase 2 suites) |
| D-62 floor | `test/watch_logging_stepping_test.dart` S-61 | (Phase 3) | (Phase 3) |
| D-61 emitter | `test/watch_logging_surfaces_test.dart` S-62 | (Phase 3) | (Phase 3) |
| D-63 correction floor | `test/watch_session_import_test.dart` S-65 | `S-65 … [E]` — `Expected: <-200.0>` / `Actual: <-20.0>` (floor `>= 0` refuses the correction) | `00:00 +48: All tests passed!` (`test/watch_session_import_test.dart`) |
