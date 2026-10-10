# 21b — evidence (implementers append; the Conductor seeds the baselines)

Plan: `docs/plans/2026-10-09-21b-watch-period-length-from-phone-plan/2026-10-09-21b-watch-period-length-from-phone-plan.md`
Base commit: `916f869` (develop) · Series: `docs/plans/2026-10-08-18-watch-qa-index.md` (row 21b)

Each phase appends: the exact command, the pass/fail counts, and the red→green pair for its scenario ids.
Counts, never claims. A phase that changes an expectation states which expectation moved and why.

## Baselines (from the 18-series QA index; re-measure at Phase 1 and overwrite)

| Check | 18-series baseline | Phase 1 measured | Notes |
|---|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` (full `flutter test`) | 4061 tests, 1 pre-existing failure | — | several minutes; 900 s timeout |
| `.github/copilot/scripts/macos/gateway.sh lint` (`flutter analyze`) | 196 issues, 0 errors | — | exits non-zero on pre-existing info notices — compare the count |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 tests, 0 failures | — | compiles the watch package only |
| watch app target (`xcodebuild`, watchOS simulator) | governor only | — | never run by an agent |

The one pre-existing `flutter test` failure is not this feature's; its name must be recorded here when Phase 1 runs, so a later
failure count can be read against the right baseline.

## Phase 1 — the contract

Command(s):

- `.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart test/watch_wire_limits_test.dart test/rest_is_count_up_contract_test.dart test/docs_indexing_contract_test.dart`
- `.github/copilot/scripts/macos/gateway.sh swift-test`
- `.github/copilot/scripts/macos/gateway.sh lint`
- `.github/copilot/scripts/macos/gateway.sh test` (full suite)

### Baselines re-measured (Phase 1, overwrite the seed row above)

| Check | Measured | Notes |
|---|---|---|
| full `flutter test` | `01:51 +4232 ~1: All tests passed!` | 4232 passed, 1 skipped, **0 failures** — the 18-series single pre-existing failure is no longer present |
| `lint` (`flutter analyze`) | `196 issues found. (ran in 2.6s)` | exactly the plan's 196 baseline; files touched: none listed |
| `swift-test` | `Executed 419 tests, with 0 failures (0 unexpected)` | 419, as the brief's baseline |
| four named suites | `00:00 +123: All tests passed!` | 123 passed, 0 failed |

### Red→green, observed

**Red (Dart walker) — `prove-red HEAD test test/sync_protocol_fixtures_test.dart -- <the 7 fixture files + manifest.json>`:**

```
gateway: prove-red: RED AT HEAD (exit 1).
00:00 +25 -1: S-001 fixtures valid/session_snapshot_round_length.json conforms to session_snapshot [E]
  Expected: empty
    Actual: ['unexpected_field at $.payload.exercises[0].roundDurationSecs: field "roundDurationSecs" is not defined by the schema']
00:00 +25 -2: S-001 fixtures valid/routines_down_round_length.json conforms to routines_down [E]
  Expected: empty
    Actual: ['unexpected_field at $.payload.fallbackExercises[0].roundDurationSecs: field "roundDurationSecs" is not defined by the schema']
00:00 +69 -3: invalid/session_snapshot_round_length_zero.json is rejected as constraint_violation [E]
  Expected: contains 'constraint_violation'   Actual: ['unexpected_field']
00:00 +69 -4: invalid/session_snapshot_round_length_negative.json is rejected as constraint_violation [E]
  Expected: contains 'constraint_violation'   Actual: ['unexpected_field']
00:00 +69 -5: invalid/session_snapshot_round_length_fractional.json is rejected as invalid_type [E]
  Expected: contains 'invalid_type'           Actual: ['unexpected_field']
00:00 +69 -6: invalid/session_snapshot_round_length_string.json is rejected as invalid_type [E]
  Expected: contains 'invalid_type'           Actual: ['unexpected_field']
00:00 +95 -6: Some tests failed.
```

**Red (Swift walker) — `prove-red HEAD swift-test --filter SyncProtocolFixturesTests -- <manifest + the two valid fixtures + the zero fixture>`:**

```
gateway: prove-red: RED AT HEAD (exit 1).
error: SyncProtocolFixturesTests.swift:45: XCTAssertTrue failed - valid/session_snapshot_round_length.json ...
error: SyncProtocolFixturesTests.swift:45: XCTAssertTrue failed - valid/routines_down_round_length.json ...
error: SyncProtocolFixturesTests.swift:61: XCTAssertTrue failed - invalid/session_snapshot_round_length_zero.json ...
Executed 6 tests, with 5 failures (1 unexpected)
```

(The other three invalid files were not carried in that run — `Fixtures.swift:101` reports the missing file — so five of the six
cases fail on the undeclared field and one on the absent file; the Dart run carried all seven.)

**Green (both stacks, after the two schema properties):**

- Dart: `00:00 +123: All tests passed!` for the four named suites, with the new register rows inside `S-001 fixtures`.
- Swift: `Executed 419 tests, with 0 failures (0 unexpected)`.
- The actual rejection codes/reason text match the plan's precedents: `0` and `-5` → `constraint_violation` / `expected at least 1`;
  `12.5` and `"2400"` → `invalid_type` / `expected integer`. No row had to be bent.

**Diff footprint** (`.github/copilot/scripts/macos/gateway.sh git-diff --stat`): PROTOCOL.md +6, manifest.json +44,
envelope.schema.json +10 — 3 tracked files, 60 insertions, 0 deletions; six new untracked fixture files. Nothing outside the
Predicted Files.

| Scenario | Red before (paste) | Green after (paste) |
|---|---|---|
| S-1400 slot field travels/validates (valid fixture + 4 rejects) | the valid fixture is refused — `roundDurationSecs` is not a declared property of `sessionExercise` | both walkers accept the two valid fixtures and reject `0`, `-5`, `12.5`, `"2400"` with the manifest's codes |
| S-1412 the ends of the range (`1`, `86400` in both schema objects) | the register carries no boundary fixture; the omitted-property refusal is the same as S-1400's | the schema states `type: integer`, `minimum: 1`, no maximum; the register's values are 2400 and omitted. No boundary fixture was created — item 1.3 fixes the fixture's contents and the Predicted Files name no other file (Assumption Log) |

Facts to confirm here (they are the plan's assumptions, not findings):

- `lib/core/sync_protocol/message_validator.dart:89-97` and `:798`, and
  `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift:94-99` and `:677`, read the schema **document**; the
  documents are loaded by `test/helpers/sync_protocol_harness.dart:54`, `test/sync_protocol_fixtures_test.dart`
  (`_loadSchemaDocuments()`) and Swift `Fixtures.schemaDocuments()`. **No validator copy exists; no validator code changed.**
- No test pins the whole property list of `sessionExercise`: `test/watch_wire_limits_test.dart` reads `properties.loadKg`;
  `test/rest_is_count_up_contract_test.dart` reads `$defs.timer`.
- `test/watch_transport_test.dart:863` walks a hardcoded fixture list, so new fixture files are not exercised there.

## Phase 2 — the phone sends the number

Command(s):

- `.github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_reference_sync_test.dart` (red, then green)
- `.github/copilot/scripts/macos/gateway.sh prove-red HEAD test test/watch_session_adoption_bridge_test.dart test/watch_reference_sync_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test test/watch_session_projection_test.dart test/live_mirroring_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_transport_test.dart test/phone_manage_bridge_test.dart test/watch_session_start_test.dart test/sync_protocol_fixtures_test.dart`
- `.github/copilot/scripts/macos/gateway.sh test` (full suite)
- `.github/copilot/scripts/macos/gateway.sh lint`

Counts: red `00:00 +33 -5: Some tests failed.` (5 new tests, each on the absent key) → green `00:00 +37: All tests passed!`;
regression set `00:00 +300: All tests passed!`; full suite `01:53 +4238 ~1: All tests passed!` (Phase 1 was 4232 — the +6 are
this phase's new tests); `lint` `196 issues found. (ran in 3.1s)` — the plan's baseline, none in the four files touched;
`grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns nothing.

**Red — `prove-red HEAD test …`:** `gateway: prove-red: RED AT HEAD (exit 1)`, six assertion failures, every one the absent
field and not a load error:

```
00:00 +31 -2: S-1405 a round effort carries the exercise default, or its own round [E]
  Expected: <2400>    Actual: <null>
00:00 +31 -3: S-1405 a timed effort and an exercise with no length send no field [E]
  Expected: <2400>    Actual: <null>   the frame carries the field at all, so each absence below is that slot's
00:00 +31 -4: S-1405 the phone sends the number S-1408 a non-round kind never gets the field [E]
  Expected: <900>     Actual: <null>   the round effort's own 900 s is exactly what must travel
00:00 +31 -5: S-1405 the phone sends the number S-1409 a length-only change moves the revision [E]
  Expected: <180>     Actual: <null>
00:00 +31 -6: S-1405 the phone sends the number S-1411 the same number twice is the same bytes [E]
  Expected: <2400>    Actual: <null>
00:00 +15 -1: S-1406 a round exercise's default travels, a set exercise's does not [E]
  Expected: <2400>    Actual: <null>
```

| Scenario | Red before (paste) | Green after (paste) |
|---|---|---|
| S-1405 the phone sends the length (`_slotFor`) | `Expected: <2400> / Actual: <null>` — no `roundDurationSecs` key, ever | `2400` from the exercise default; `900` after the round is re-timed; absent for `timed`; absent with no default and no rounds (that frame's control slot carries `2400`, so each absence is the slot's) |
| S-1406 (Dart half) the catalog carries the default | `Expected: <2400> / Actual: <null>` in the `routines_down` fallback entry | Soccer's entry has `roundDurationSecs: 2400`; Squat's has none; `_rejections(message)` empty, so the amended schema accepts it |
| S-1408 a non-round kind never gets the field | `Expected: <900> / Actual: <null>` on the control round effort; the AMRAP absence alone was green at HEAD and proves nothing | AMRAP holding a 900 s round: absent, while the round effort beside it sends `900` |
| S-1409 a length-only change moves the revision | `Expected: <180> / Actual: <null>`; the ladder string ignored the length | revision `n` → `n + 1` on the re-timing; a third projection stays `n + 1` |
| S-1411 the same number twice is the same bytes | `Expected: <2400> / Actual: <null>` | two projections equal; the revision does not move for an unchanged ladder |

Two guards were strengthened during Phase 0 rather than left trivially green at HEAD: S-1405's absence test and S-1408 both now
assert a positive control (a `round` slot in the same frame carrying its number) beside the absences, which is what makes the
`Expected: <2400>` / `<900>` failures above possible.

Regression expectations re-read, not assumed: revision assertions at
`test/watch_session_adoption_bridge_test.dart:717-730,786`, and the slot comparisons at
`test/watch_session_projection_test.dart:635-650` (per-field) and `test/watch_reconciliation_cross_stack_test.dart`
(id/exerciseId/position/revision/status/timers only) — all green in the 300-test regression run and the full suite.

**Diff footprint** (`.github/copilot/scripts/macos/gateway.sh git-diff --stat`): `lib/core/utils/watch_reference_sync.dart` 21,
`lib/state/watch/watch_session_adoption_bridge.dart` 20, `test/watch_reference_sync_test.dart` 86,
`test/watch_session_adoption_bridge_test.dart` 239 — 4 files, 362 insertions, 4 deletions, all inside the Predicted Files.
No `.swift` file and no schema file was touched, so no `swift-test` run belongs to this phase.

## Phase 3 — the wrist reads the number

Command(s):

- `.github/copilot/scripts/macos/gateway.sh swift-test`
- `.github/copilot/scripts/macos/gateway.sh test test/watch_logging_surfaces_test.dart test/docs_indexing_contract_test.dart test/sync_protocol_fixtures_test.dart test/watch_session_start_test.dart test/watch_reconciliation_cross_stack_test.dart`
- `.github/copilot/scripts/macos/gateway.sh lint`

| Scenario | Red before (paste) | Green after (paste) |
|---|---|---|
| S-1401 the wrist counts down from the slot | idle readout `"3:00"`, `plannedDurationMs == 180_000` | `"40:00"`, `2_400_000`, 1800 s left at 10:10:00 |
| S-1402 no number, no change | — (must stay green) | `"3:00"`/`180_000`; a `timed` slot with the field still counts up `0:00`; plan 21's `roundPresetMs:` case green |
| S-1403 the number follows the slot | the readout cannot change between slots | `"40:00"` → `"10:00"` on the jump; a running period is not re-timed |
| S-1404 the routine effort's target | the slot has no number | `roundDurationSecs == 600`; a `timed` effort with `durationMs` gets none |
| S-1407 the routine keeps it through the start paths | — | the same slot after a relaunch that reads the stored catalog row |
| S-1406 (Swift half) the free-workout pick | the picked slot has no number | Soccer `2400`; Squat absent |
| S-1410 a wrist snapshot carries it back | — | the phone accepts and applies the snapshot; no disagreement loop |
| S-1412 the ends of the range on the wrist | — | `"0:01"`/`1000` and `"1440:00"`/`86_400_000` |

Doc constraints to record here: `docs/state_management/watch_surface.md` is near its 52 KB band — record the file's size before
and after the remove-before-add edit; `test/docs_indexing_contract_test.dart` caps every `docs/` file at 64 KiB and bans
walkthrough narration and roadmap phrasing. `watch/sync_protocol/PROTOCOL.md` is not covered by that test.

## Residue sweep (Phase 3.8)

Paste the outputs of:

- `grep -rn "plannedRoundMs" watch/watchos/Sources watch/watchos/Tests` — every remaining reader is the per-slot read (D-1405).
- `grep -rn "roundDurationSecs" lib/ watch/ test/` — every reader and writer of the new field, with the Dart Wear client
  (`lib/watch/`) intentionally absent (D-1408).
- `grep -rn "roundPresetMs" watch/watchos` — the plan-21 seam still honoured as the second source.
- `.github/copilot/scripts/macos/gateway.sh git-diff` — files touched versus the plan's Predicted Files (out-of-bounds files and
  untouched predicted files are both findings).
