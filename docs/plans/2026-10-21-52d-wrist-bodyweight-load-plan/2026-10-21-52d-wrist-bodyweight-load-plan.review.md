# Review: 52d wrist-bodyweight-load · P1-P3 · base..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: 744 passed / 0 failed (governor's full `swift test`, per brief; not re-run here)
Diff vs Predicted Files: conforms (6 files: WatchLoggingState.swift, WatchBodyweightLoadTests.swift new, WatchCrownArmingTests.swift, WatchLoggingSurfacesTests.swift, WatchPagerFocusTests.swift, watch_surface_wrist.md)

## Findings
1. [Minor] WatchLoggingState.swift:700-708 (`lastLogged`) — after a push-up set is dialled back to 0 and logged (no `loadKg` in its payload), the *following* set's weight tile starts at the last set that *carried* a load (e.g. 10 from set 1), not at 0: `lastLogged` skips observations lacking the key. A user who explicitly zeroed the assist may expect the next set to start at 0. Fix: none required — the Dart twin's `_lastLogged` (`lib/watch/logging/watch_logging_state.dart:470-478`) skips absent values the same way, so parity (the plan's criterion, D-2) holds; only worth a doc sentence if the owner reads "the next set starts where the last one logged" literally. No test pins either behaviour for this case.

## Question rulings
1. `metricKeysByKind` (WatchLoggingState.swift:209-214): only `set` prescribes `weight`; `timed` is `[]`, `round` is `roundDuration`, `drill` is `extraWeight`. No other kind gains a row. A slot whose capabilities resolve to nothing falls back to kind `set` (`effortKind`, :489-495) and now shows reps *and* weight; before the change it already showed reps (reps was never gated), and a declared-`set` slot is the phone's own prescription, so the weight tile matches the phone. No finding.
2. Payload: the set case (WatchLoggingState.swift:914-921) sends `loadKg` only when non-zero, signed, in canonical kg. `WatchMetricStepping.clamp` floors `weight` at `minimumLoadKg` = -200 and `quantize` keeps 3 decimals; the schema's set-entry `loadKg` is `type: number, minimum: -200` (envelope.schema.json:169-172, inclusive floor) and the phone's importer accepts `num >= WireLimits.minLoadKg` (-200, wire_limits.dart:20; watch_session_importer.dart:2061). Fractional pounds (fine step 1 lb → 0.454 kg) are a valid `number`. Nothing the wrist can dial is refused.
3. Edited tests: S-6406 (CrownArming) still tests re-check-on-exercise-change, now stronger (weight→extraWeight re-arm); S-001 (Surfaces) renamed to its new meaning and strengthened (fields list, weight 0, `loadKg` nil after log); S-7911/S-7914 (PagerFocus) keep their names and swap the missing-weight-row discriminator for `setCaption`, which is derived from `plannedSets` (WatchLoggingState.swift:283-291) — independent of the changed behaviour, so neither assertion is weakened.
4. New tests: none passes for a wrong reason. S-8102's zero case is dialled down explicitly before the log (not a default coincidence); S-8104's 5.0/7.5 differ from both the kind target (0) and the carry-over value (5), so planned dial-in is distinguished from carry-over; S-8105's 10 differs from the 0 target; S-8103's floor is asserted against the -200 constant with a -2520 raw value behind it.

## Assumption Log rulings
The plan carries no Assumption Log section; its Decision Ledger is ruled instead: D-1 implemented as exact text (the `weight → "load"` line gone, both docs corrected); D-2 ratified — no wire, phone or `lib/watch` file in the diff; D-3 ratified — the three named tests plus `WatchLoggingSurfacesTests` (which the plan left to the full run) updated, none weakened.

## Scenario coverage
S-8101 → WatchBodyweightLoadTests.testS8101ASetEffortOffersRepsAndWeightAHoldItsExtraWeightATimedEffortNothing
S-8102 → WatchBodyweightLoadTests.testS8102ADialledWeightIsLoggedAsLoadKgAndAZeroWeightSendsNone
S-8103 → WatchBodyweightLoadTests.testS8103AnAssistTravelsWithItsSignDownToTheWireFloor
S-8104 → WatchBodyweightLoadTests.testS8104APlannedRowStartsTheWeightTileAtItsOwnLoad
S-8105 → WatchBodyweightLoadTests.testS8105TheNextSetStartsAtTheWeightJustLogged
D-3 → WatchCrownArmingTests S-6406 · WatchLoggingSurfacesTests S-001 · WatchPagerFocusTests S-7911, S-7914
Docs claims checked against code: `capability(for:)`, `metricKeysByKind`, `WatchMetricStepping.minimumLoadKg`, `setCaption`, `_capabilityFor` (lib/watch/logging/watch_logging_state.dart:395, still ties weight to `load` — the stated parity gap is real), `docs/watch_session_sync.md`, `watch/sync_protocol/PROTOCOL.md`, `envelope.schema.json` loadKg floor — all exist as named.
