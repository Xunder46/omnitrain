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

| Scenario | Red before (paste) | Green after (paste) |
|---|---|---|
| S-1400 slot field travels/validates (valid fixture + 4 rejects) | the valid fixture is refused — `roundDurationSecs` is not a declared property of `sessionExercise` | both walkers accept the two valid fixtures and reject `0`, `-5`, `12.5`, `"2400"` with the manifest's codes |
| S-1412 the ends of the range (`1`, `86400` in both schema objects) | both values refused (undeclared property) | both accepted; no maximum |

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

- `.github/copilot/scripts/macos/gateway.sh test test/watch_session_adoption_bridge_test.dart test/watch_reference_sync_test.dart test/watch_session_projection_test.dart test/live_mirroring_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_transport_test.dart test/watch_session_start_test.dart test/sync_protocol_fixtures_test.dart`
- `.github/copilot/scripts/macos/gateway.sh lint`

| Scenario | Red before (paste) | Green after (paste) |
|---|---|---|
| S-1405 the phone sends the length (`_slotFor`) | no `roundDurationSecs` key, ever | `2400` from the exercise default; `900` after the round is re-timed; absent for `timed`; absent with no default and no rounds |
| S-1406 (Dart half) the catalog carries the default | the fallback entry has no number | Soccer's entry has `roundDurationSecs: 2400`; Squat's has none |
| S-1408 a non-round kind never gets the field | guard: absent for the right reason once the key exists | AMRAP at 900 s and a wire-`timed` effort: absent |
| S-1409 a length-only change moves the revision | the revision does not move (the ladder string ignores the length) | revision `n` → `n + 1` on the re-timing; a third projection stays `n + 1` |
| S-1411 the same number twice is the same bytes | — (idempotency guard) | two projections equal; two `toSlot`s equal |

Regression expectations that must be re-read, not assumed: revision assertions at
`test/watch_session_adoption_bridge_test.dart:717-730,786`, and the slot comparisons at
`test/watch_session_projection_test.dart:635-650` (per-field) and `test/watch_reconciliation_cross_stack_test.dart`
(id/exerciseId/position/revision/status/timers only).

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
