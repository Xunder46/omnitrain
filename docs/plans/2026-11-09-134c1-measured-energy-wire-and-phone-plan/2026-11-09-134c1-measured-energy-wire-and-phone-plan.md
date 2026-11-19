# Plan — 134c1: the wire can carry the watch's measured active energy and the phone stores it

**Status**: built, reviewed (phone review: 134d folder) and verified 2026-11-09; uncommitted. Evidence: `docs/plans/2026-11-09-134e-wrist-rest-calories-plan/2026-11-09-134e-wrist-rest-calories-plan.evidence.md` (one file for 134b to 134e).
**Binding conventions**: `docs/global_conventions.md`, `watch/sync_protocol/PROTOCOL.md`.
**Base commit**: `ff398e1a7ec18409d9fc8c890bf35d2fde656e69` (branch `claude_develop`; the uncommitted 134a is in the tree and required).
**Pattern followed**: plan 71 (`docs/plans/2026-10-24-71-followed-session-heart-rate-plan/`), the last additive `session_end` field.
**Parent plan**: `docs/plans/2026-11-08-134-calories-burned-plan/2026-11-08-134-calories-burned-plan.md`. Next: 134c2 (the watch measures and sends it), 134e (the wrist's rest screen).

## Overview

Owner (2026-11-08): when the watch has active energy for a session, push it to the phone so the phone never estimates and every surface shows the same number. This unit is the half the phone and the contract own: a `session_end` may carry `activeEnergyKcal`, both validators accept it only there, and the importer stores it as a `measured` energy row (which replaces an estimate and is never replaced by one: 134a D-13402).

Nothing the user can see changes until 134c2 makes the watch send the field. After both, a session the watch ran shows its Calories pill without `~` on the phone's Session Summary, and the phone's own session that the watch followed does too.

## Goal and acceptance

The contract, both validators and the importer accept and store `activeEnergyKcal` on a `session_end`. Acceptance: S-13460 .. S-13468.

## Decision Ledger

| ID | Decision | Backing |
|---|---|---|
| D-13460 | New optional wire field `activeEnergyKcal`: JSON `number`, `minimum` 0, on a `session_end` entry only. Meaning: the active energy, in kilocalories, the wrist's workout measured over the whole session (above resting, pauses excluded, as the platform counts it). Absent when nothing was measured; a total of zero is never sent (the receiver also treats a value `<= 0` as absent: D-13463). Not summarised per entry or per set block | `envelope.schema.json` `$defs` entry properties ~285-345 (`avgHeartRateBpm`, `steps`); plan 71 |
| D-13461 | Both validators gate it by kind exactly like `followed`: Dart `message_validator.dart` `_captureFieldKinds` (`:129-141`) gains `'activeEnergyKcal': ['session_end'],` after `'maxHeartRateBpm'`; Swift `SyncProtocolValidator.swift` `captureFieldKinds` (`:82-95`) gains `("activeEnergyKcal", ["session_end"]),` at the same position. A value on any other kind is `semantic_violation` ("activeEnergyKcal is carried only by session_end entries") in an `observations_up` event and in a `session_snapshot` entry alike | scout WIRE Q1c; both tables quoted there |
| D-13462 | Fixtures (+ manifest, which both suites walk): `valid/observations_up_session_end_energy.json` (a `completed` `session_end` with `avgHeartRateBpm` 140, `maxHeartRateBpm` 168, `activeEnergyKcal` 412.6), `invalid/observations_up_energy_on_set.json` (a `set` event carrying `activeEnergyKcal` 100: `semantic_violation`, reason contains `activeEnergyKcal`), `invalid/observations_up_energy_negative.json` (a `session_end` with `activeEnergyKcal` -1: `constraint_violation`, reason contains `activeEnergyKcal`). No existing fixture changes | `manifest.json` entry shape (`path`, `type`, `scenario`, `expectedCode`, `expectedReasonContains`, `note`); `fixtures/valid/observations_up_session_end_followed.json`, `invalid/observations_up_steps_on_round.json` as models |
| D-13463 | Importer: `_End` gains `final double? activeEnergyKcal` parsed with the existing `_real(payload['activeEnergyKcal'])` (non-numbers and non-finite values become null). `_Pass._attachSessionSummary` (the ONE place all four paths reach: import create, import top-up, followed end, merge) calls a new `_attachMeasuredEnergy()` after its summary attach. `_attachMeasuredEnergy` stores nothing unless `end.status == 'completed'` and `activeEnergyKcal` is non-null, finite and `> 0`; builds `SessionEnergy(sessionId: sessionId, activeKcal: kcal, source: SessionEnergy.sourceMeasured, bodyWeightKg: null, updatedAtMs: end.loggedAtMs)` (a model refusal is swallowed like `_attach` does); skips when the session already holds a `measured` row with the same `activeKcal` (idempotent, no spurious change); otherwise `putSessionEnergy` and, when it returns true, `changed = true; summaryWritten = true;` so the pass reports history changed and the open Session Summary re-reads (`sensorSummaryAttached`, 134a D-13411) even for an end with no heart rate | `watch_session_importer.dart:1712-1727` `_attachSessionSummary`, `:2193-2251` `_End`, `:2279` `_real`, `:481-487` counters |
| D-13464 | A phone-owned session (the merge path and the followed path) gets the measured row too: the wrist's measurement replaces the phone's estimate. The wrist's end for a session the phone has not ended (still running) also stores it; the phone's own end later keeps it (`settle` never overwrites `measured`, 134a). Accepted edge, listed in the Assumption Log | owner decision 1 of the parent plan |
| D-13465 | The inbox hand-off of 134a (`onSessionHistoryChanged` → `ActiveEnergyService.settle`) stays as is: after an import the settle finds the `measured` row and returns | 134a D-13420 |

## Scenarios

Importer scenarios run on Mock AND Hive (`harnessFactories`), plain `test()`, in a new `test/watch_energy_import_test.dart` that copies the helpers of `test/active_energy_import_test.dart` (`_iso`, `_start`, `_wristEnd`, `_wristSet`, `_observationsUp`) and `test/watch_followed_end_import_test.dart` (the followed and held fixtures).

| ID | Fixture | Expect | Fails without the change because |
|---|---|---|---|
| S-13460 | a wrist-created session (`session_end` `resistance_lifting`, 3600 s, one set, `activeEnergyKcal` 412.6, no heart rate) imported through `WatchSessionImporter.apply` | the session exists; `getSessionEnergy` is `measured`, 412.6 exact, `bodyWeightKg` null, `updatedAtMs` = the end's `loggedAt`; the result has `sensorSummaryAttached` true and `historyChanged` true | no field, no row |
| S-13461 | the phone's own session already ended with an `estimated` row (200.0, 80 kg) and a wrist `session_end` (held path: `apply(id, phoneOwnsSession: true)`) with `activeEnergyKcal` 150.0 | the row is `measured` 150.0 (replaced; no weight) | an estimate would stay |
| S-13462 | the end carries: no field; `0`; `-5`; `"412"` (a string); `1e999`-style non-finite is not representable in JSON so `double.nan` is passed through the in-memory payload; each on a session with an `estimated` 200.0 row (and once on a session with no row) | the estimated row is unchanged (and no row appears for the row-less session) in every case | non-positive and non-numeric values must not store |
| S-13463 | a followed completed end (`followed: true`) with `activeEnergyKcal` 300.0 for a session the phone holds with an `estimated` row; and the same end abandoned (`status: abandoned`) | completed: `measured` 300.0; abandoned: the estimate stays | no followed handling; abandoned must not store |
| S-13464 | the same end delivered twice (a second `apply`) | one row, `activeKcal`/`updatedAtMs` unchanged by the second pass; the second result has `sensorSummaryAttached` false | no idempotence |
| S-13465 | through `WatchSessionInbox(repository, onSessionHistoryChanged: ActiveEnergyService(repo, () => StatsProgressService(repo)).settle)` a wrist session with energy 412.6 (80 kg logged) | after the pass the row is still `measured` 412.6 (settle did not overwrite it) | the hand-off could overwrite |
| S-13466 | validators, valid: `valid/observations_up_session_end_energy.json` | Dart and Swift both accept | the schema rejects an unknown property |
| S-13467 | invalid: `activeEnergyKcal` on a `set` event | both reject with `semantic_violation`, reason containing `activeEnergyKcal` | no kind gate |
| S-13468 | invalid: `activeEnergyKcal` -1 on a `session_end` | both reject with `constraint_violation`, reason containing `activeEnergyKcal` | no minimum |

S-13466 .. S-13468 are carried by the two fixture walks (`test/sync_protocol_fixtures_test.dart`, `watch/watchos/Tests/WatchSessionEngineTests/SyncProtocolFixturesTests.swift`), which iterate `manifest.json`; the manifest rows carry the scenario ids.

## Phases (outline)

| Phase | Agent | Write scope | Parallel |
|---|---|---|---|
| P1 contract + Swift validator | crew-builder-watch | `watch/sync_protocol/**`, `watch/watchos/Sources/WatchSessionEngine/SyncProtocolValidator.swift` | parallel with P2 (disjoint) |
| P2 Dart validator + importer | crew-builder-app | `lib/core/sync_protocol/message_validator.dart`, `lib/core/services/watch_session_importer.dart`, new `test/watch_energy_import_test.dart` | parallel with P1 |
| P3 docs | crew-docs-keeper | the Docs delta rows | after both |

### P1 (one crew-builder-watch run)

Write the report FIRST as a skeleton. Never run the full `flutter test`; for Swift run only the named filter.

1. `watch/sync_protocol/schemas/envelope.schema.json`: add the property after `maxHeartRateBpm` (same `$defs` object as `avgHeartRateBpm`):
   `"activeEnergyKcal": { "type": "number", "minimum": 0, "description": "On a session_end entry only: the active energy, in kilocalories, the wrist's workout measured over the whole session, above resting and without pauses, as the platform counts it. Absent when nothing was measured; a total of zero is never sent." },`
2. `SyncProtocolValidator.swift`: the table row of D-13461.
3. The three fixtures of D-13462 (copy the envelope of the two model fixtures; `messageId`, `sessionId`, ids unique) and their `manifest.json` rows (valid: `path`, `type`, `scenario`, `note`; invalid: also `expectedCode`, `expectedReasonContains`). Scenario ids S-13466, S-13467, S-13468.
4. `watch/sync_protocol/PROTOCOL.md`: (a) in the Summary fields table add the row `| \`activeEnergyKcal\` | \`session_end\` | The active energy, in kilocalories, the wrist's workout measured over the whole session. Absent when nothing was measured; a zero total is never sent |` after the `avgHeartRateBpm, maxHeartRateBpm` row; (b) in the `session_end` bullet (~line 443-450) say the entry also carries the measured active energy when there is one; (c) one amendment row in the changelog table after the 2026-11-07 row, in the style of the 2026-10-24 followed-end row (state: field, kind gate, no version change, additive, the three fixtures, and "plan `docs/plans/2026-11-09-134c1-measured-energy-wire-and-phone-plan/`").
5. Run `bash .github/copilot/scripts/macos/gateway.sh swift-test --filter SyncProtocolFixturesTests` and paste the counts. The new fixtures must be seen RED first (item 3 before items 1-2: the valid one is rejected, the invalid ones are not rejected as stated).

### P2 (one crew-builder-app run)

Write the report FIRST as a skeleton. Never run the full suite. Do not touch `watch/**`.

1. New `test/watch_energy_import_test.dart` with S-13460 .. S-13465 as in the table (red first). Read `test/active_energy_import_test.dart` and `test/watch_followed_end_import_test.dart` and copy their helpers; the held-session fixture follows `S-10105` of the followed test.
2. `message_validator.dart`: the table entry of D-13461.
3. `watch_session_importer.dart`: `_End` field and parse, and `_attachMeasuredEnergy` called at the end of `_attachSessionSummary`, per D-13463.
4. Run `-- test/watch_energy_import_test.dart`, then `-- test/active_energy_import_test.dart`, `-- test/watch_followed_end_import_test.dart`, `-- test/watch_session_merge_test.dart`, `-- test/watch_session_import_test.dart`. Paste counts. (`test/sync_protocol_fixtures_test.dart` needs P1's fixtures: run it last, after checking `git status` shows the three new fixture files; if they are not there yet, say so and the lead runs it.)

### P3 docs (one crew-docs-keeper run, after P1 and P2)

Run no test. `watch/sync_protocol/PROTOCOL.md` is not in your scope (the watch builder wrote it). Execute the Docs delta rows.

## Readers to update (found by the lead)

| Reader | What it reads | Action |
|---|---|---|
| `test/sync_protocol_fixtures_test.dart`, `SyncProtocolFixturesTests.swift` | every manifest row | walk the three new rows; the test counts may be asserted: grep `valid.length` / `hasLength` for a fixed count before P1 and update if one exists |
| `test/watch_capture_contract_conformance_test.dart`, `watch/contract/watch_capture_contract.json` | one session end to end | unchanged (the wrist sends no energy until 134c2) |
| every exact-payload assertion on a `session_end` (`test/watch_*`) | key sets of emitted ends | unchanged in this unit (the wrist emits no new key until 134c2); 134c2 greps them |
| `lib/core/services/watch_session_importer.dart` readers (`WatchSessionInbox`, the adoption bridge) | `WatchSessionImport` flags | no new flag; `sensorSummaryAttached` now also means "an energy row was written" (doc comment) |

## Input-reality checklist

1. **Writers**: the wrist (134c2) is the only sender; the importer is the only writer of a `measured` row.
2. **Lifecycle**: an end is applied once per row (`appliedAtMs`); a re-delivery is a no-op (S-13464); a deleted session's row goes with it (134a cascade); an abandoned end stores nothing.
3. **Settings**: none.
4. **Time**: `updatedAtMs` is the end's own `loggedAt`, not the phone clock, so a replay is byte-identical.
5. **Cost**: one repository read and at most one write per end.
6. **Words**: none user-visible in this unit.
7. **Competition**: a `measured` row and the phone's `estimated` row for one session: measured wins and is final (134a D-13402).

## Feature invariants

- A field outside `session_end` is refused on both platforms.
- The importer never stores a non-positive or non-finite energy, and never lets an abandoned end store one.
- A stored `measured` row is never overwritten by an estimate.

## Existing-functionality impact

| Touch | What reads it today | Effect | Guarded by |
|---|---|---|---|
| `envelope.schema.json` | both validators, both fixture walks | one optional property | S-13466..S-13468 |
| `message_validator.dart`, `SyncProtocolValidator.swift` | every inbound frame | one table entry each | S-13467 |
| `watch_session_importer.dart` | the inbox, the adoption bridge | one field, one method, one call | S-13460..S-13465 and the importer suites |
| `PROTOCOL.md`, `manifest.json` | the fixture tests name them | one row each | `test/docs_indexing_contract_test.dart` (size ceiling) |

## Assumption Log

| ID | Assumption | Why |
|---|---|---|
| A-1 | A zero total is never sent and a received `<= 0` is treated as absent | a session that burned nothing is not a measurement, and storing `0 kcal` would block the estimate |
| A-2 | The wrist's `completed` end stores a measured row even when the phone's own session has not ended yet (the phone then keeps it) | the wrist ended first only in unusual races; the measured value covers the wrist's own run |

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/watch_session_capture.md | MODIFIED | `` `followed: true`: the phone stores only the heart-rate summary the end carries `` | `` `followed: true`: the phone stores only the heart-rate summary and the measured active energy the end carries `` | S-13463 |
| docs/watch_session_capture.md | ADDED | - | `**Measured active energy.**` | S-13460, S-13461, S-13462, S-13464 |
| docs/data_models.md | MODIFIED | `or steps. Storage: [DB Integration](db_integration.md#session-energy-storage).` | `activeEnergyKcal`. Storage: [DB Integration](db_integration.md#session-energy-storage). | S-13460 |

Stale-term sweep (2026-11-09): `grep -rIn "heart-rate summary the end carries\|nothing the phone lacks" docs` outside plans/history/releases found only `docs/watch_session_capture.md:244`. `docs/session_summary.md:106` ("The watch does not send measured energy yet") stays true until 134c2 and is changed there.

## Progress

| Item | What | Status |
|---|---|---|
| P1.1-P1.5 | schema, Swift validator, fixtures, manifest, PROTOCOL.md, Swift fixture walk | Planned |
| P2.1 | red `test/watch_energy_import_test.dart` | Planned |
| P2.2 | Dart validator entry | Planned |
| P2.3 | importer field + `_attachMeasuredEnergy` | Planned |
| P2.4 | green P2 and neighbours | Planned |
| P3 | Docs delta rows | Planned |
