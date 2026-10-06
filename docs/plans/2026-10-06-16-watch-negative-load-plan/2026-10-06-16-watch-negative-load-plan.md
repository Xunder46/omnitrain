# Feature: a negative load (band assist) on a set works on the phone and the watch

> Status: Iteration 1 active
> Next handoff: @dba (Phase 1)
> Binding conventions: `docs/global_conventions.md`; this plan; `watch/sync_protocol/PROTOCOL.md`
> (normative wire rules); the docs this feature invalidates — `docs/watch_session_sync.md`,
> `docs/state_management/watch_surface.md`, `docs/watch-app-setup-and-qa.md`. Do not edit
> `.claude/`, `.github/`, `AGENTS.md` or `CLAUDE.md`.

## Overview

A set's load can be negative: a band or a partner assists the lift, so the logged resistance is
*below* bodyweight. The phone already stores such a set — its set editor lets the load dial below
zero — but nothing carries one across the watch↔phone wire:

- the protocol schema floors every `loadKg` at `0`, so a negative load is not a valid wire value; the
  phone's projection drops such a set instead of sending it; the wrist's crown floors the load at `0`,
  so the wrist cannot dial an assist at all; and the wrist's emitter omits a load unless it is `> 0`.

So the phone has a value it cannot show on the watch and the watch has no way to record what the
phone could store. This plan widens exactly those floors to one canonical floor of **−200 kg**, lets
a set carry a negative `loadKg` verbatim, and pins the contract, both clients and the docs to that
number. It adds no new field, no new message type and no version bump.

Owner decision: a negative load is a **load**, not an extra load. The signed `extraLoadKg` (a hold's
added or assisting load — `F1`/`A-14`, which already accepts negatives) is **not** the carrier: the
phone renders it as the `extra-weight` metric of a drill, so a negative there would surface as an
assisted *drill*, not as the set the user logged.

## Resolved Decisions (Ledger)

- **D-58 — the wire floor for a load is −200 kg.** Every `loadKg` the protocol defines accepts a
  negative number down to −200: `envelope.schema.json` `$defs.entry.loadKg` and
  `$defs.metricTargets.loadKg`, and `messages/structure_change.schema.json` `$defs.correction.loadKg`
  all become `"minimum": -200`. A value below −200 kg stays invalid. `extraLoadKg` is unchanged
  (it already accepts any number) and is not a carrier for a set's assist (Overview).
  *Why −200:* it is the bound the phone's editor already enforces, so the wire refuses no set the
  phone can produce. *Rejected:* "no minimum" (the two stacks' floors would drift unchecked) and
  "−100" (would refuse values the phone already stores).
- **D-59 — each stack names the floor once, and a test reads the schema to prove it matches.** Dart:
  `lib/core/sync_protocol/wire_limits.dart`, `abstract final class WireLimits`, `minLoadKg = -200.0`.
  Swift: `WatchMetricStepping.minimumLoadKg = -200`. `test/watch_wire_limits_test.dart` reads the two
  schema documents, pulls the three `loadKg` minimums and asserts each equals `WireLimits.minLoadKg`;
  the watchOS suite asserts the same against the same file. A literal in five places is five chances
  to drift.
- **D-60 — the projection's omission rule (supersedes D-40's negative rule; reverts the negative
  half of `A-14`/`F1`).** `PhoneEntries._entry` omits an entry when, and only when: (a) it has no
  reps (`reps < 1`), or (b) its load is below the wire floor (`weightKg < WireLimits.minLoadKg`).
  A loaded set with a `weightKg` in [−200, 0) is carried with `loadKg` verbatim — not rounded, not
  re-signed, not converted. `weightKg == 0`, or an entry with no weight, still omits `loadKg`
  entirely: the wire keeps "no load" and "load 0" indistinguishable, as today.
- **D-61 — the wrist sends a non-zero signed load, and omits it at exactly zero.**
  `WatchLoggingState._metricPayload` (Dart) and its Swift twin emit `loadKg` when the dial's weight
  is non-null and `!= 0` (today `> 0`); at exactly `0` the key is absent, unchanged from
  `S-001`. The emitted value is canonical kilograms, signed, at the dial's step. (`-0.0 != 0` is
  false in both languages, so a signed zero is omitted too — the wire never claims "load 0".)
- **D-62 — the wrist's floor is a flat −200 kg canonical; the step, the unit handling and the
  display do not change.** `clampTo` (Dart) and `clamp` (Swift) floor `WatchMetricKey.weight` at
  −200 kg instead of `0`. `extraWeight` keeps its current unbounded floor; `durationMs`,
  `distanceMeters` and `roundDurationMs` keep floor `0`; count-like keys keep floor `1`. Detent
  sizes stay 2.5 kg / 5 lb; the value and its label still go through `UnitFormatter`/
  `displayValue`, whose weight case already renders a leading `-` and keeps `kg`/`lbs`.
  *Rejected:* a floor of −200 *display* units (the phone editor's bound) — `clampTo` takes no `units`
  today, so the Swift twin's signature would change in lockstep for a difference no user can produce.
  *Accepted consequence:* in lbs the wrist reaches −200 kg ≈ −441 lb, deeper than the phone's editor;
  the phone stores and shows it (D-64) and re-clamps only if that set is edited on the phone.
- **D-63 — the importer's correction floor is the same floor.** `_effectiveEntry`'s validity check
  for a `loadKg` correction becomes `value is num && value >= WireLimits.minLoadKg` (today `>= 0`),
  and the existing apply path is untouched, so a correction to −20 kg lands on the set and a
  correction to −240 kg is refused as an invalid correction — refused, never clamped into range.
  `reps`, `durationMs` and `distanceMeters` corrections keep their current bounds.
- **D-64 — phone analytics, summary and stats are unchanged.** Volume and the summary/stats maths
  stay unfloored and a negative load contributes a negative weight. No filter for negatives is added
  to `session_summary_service.dart`, `state/workout/session_summary_builder.dart`,
  `stats_progress_service.dart` or `lib/features/stats/`. *Why:* the phone already stores a negative
  set, so those paths already have to live with one; whether volume should ignore band assist is a
  product question nobody has asked (Q4).
- **D-65 — routine targets need no filter, and one existing doc sentence stays true.** The phone
  maps a routine's `weight` target onto `loadKg`; that mapping is unchanged, so once D-58 lands a
  plan whose load target is an assist validates and reaches the wrist. The "metrics the wire has no
  key for (RPE, rest, band assist) are not sent" sentence in
  `docs/state_management/watch_surface.md` is about the `extra-weight` *metric* (which has no wire
  key) and remains true — this plan must not edit it.
- **D-66 — the contract amendment is additive and keeps `protocolVersion: 1`.** `PROTOCOL.md` gains a
  `1 (amended) | 2026-10-06` row in `## Version history` recording that a `loadKg` may be negative
  (band assist) with a floor of −200 kg, targets and corrections included. No version bump, no
  migration, no back-fill: the change only widens what is accepted, so nothing a v1 client accepted
  becomes invalid, both clients ship from this repository, and a receiver that predates the change
  simply never sees a negative load.

## Feature Invariants

Only the invariants that bite here (project-wide rules live in `docs/global_conventions.md`):

- **One floor, three schema sites, two stacks.** `WireLimits.minLoadKg` (Dart) and
  `WatchMetricStepping.minimumLoadKg` (Swift) both equal the `loadKg` minimum in
  `envelope.schema.json`; a schema-only or code-only edit is a defect (D-59).
- **Implementation parity.** `MockWorkoutRepository` and `HiveWorkoutRepository` keep returning the
  same set for a negative `weightKg`; nothing here special-cases either.
- **Layer boundaries.** `lib/state/`, `lib/features/`, `lib/widgets/` and `lib/core/` depend on
  `WorkoutRepository` and the protocol types only, never on a concrete persistence class.
- **The wire never says "load 0".** A missing weight and a zero weight are indistinguishable on the
  wire (D-60, D-61) — do not "fix" that here.
- **Nothing negative is invented.** Only a value the user dialled or the phone stored may be negative;
  no default, fallback or computed value becomes negative.

## Requirements

1. A negative load on a set travels wrist → phone and lands with its sign and value intact, and a
   re-statement of the snapshot that carries it neither duplicates nor zeroes it.
2. The same load travels phone → wrist in a `session_snapshot`.
3. The wire accepts any load from −200 kg up, targets and corrections included; below −200 kg stays
   invalid, and an invalid value is refused rather than clamped.
4. The wrist's crown dials an assist down to −200 kg, shows it with a leading minus in the user's
   unit, and keeps its existing detent sizes.
5. Nothing else about logging changes: duration, distance, rounds and counts keep their floors, a set
   with no load still sends no `loadKg`, and the user's unit over the kilogram payload is unchanged.
6. The contract, the phone, the wrist and the docs agree on the floor, enforced by a test that reads
   the schema rather than by prose.

## Acceptance Criteria

| # | Criterion | Scenarios |
|---|---|---|
| AC-1 | An assisted set logged on the wrist appears on the phone with the same negative load | S-58, S-63, S-67 |
| AC-2 | An assisted set already on the phone reaches the wrist; the snapshot omits only rows it must | S-59, S-60 |
| AC-3 | A load below −200 kg is refused, never clamped, at every gate (schema, projection, correction) | S-60, S-65 |
| AC-4 | The wrist's dial stops at −200 kg and its step is unchanged, in kg and in lbs | S-61 |
| AC-5 | Zero and absent loads behave exactly as before on both sides | S-62 |
| AC-6 | A negative load renders with a leading minus in the user's unit on both surfaces | S-64 |
| AC-7 | A routine whose plan is an assisted load reaches the wrist instead of rejecting the message | S-66 |
| AC-8 | The docs no longer say an assisted set cannot travel, and no reader of the old rule remains | all |

## Existing-Functionality Impact

Every row names the grep that found the readers (`grep` is the file-search tool, not a shell command).

| Touched surface | What already reads it (grep) | Effect | Guarded by |
|---|---|---|---|
| `envelope.schema.json` `$defs.entry.loadKg` | `minimum.*0` in `watch/sync_protocol/schemas`: the entry, the metric targets and the correction; readers of `loadKg` in `lib/core/sync_protocol/phone_entries.dart`, `lib/core/services/watch_session_importer.dart`, `lib/watch/logging/watch_logging_state.dart`, `watch/watchos/Sources/WatchSessionEngine/*.swift` | a negative load becomes valid instead of rejected | S-58, S-60, S-65 |
| `structure_change.schema.json` `$defs.correction.loadKg` (**not in the brief**) | grep `"minimum": 0` across `watch/sync_protocol/schemas` (three hits, one per `loadKg`) | a correction to an assist lands instead of being rejected | S-65 |
| `PhoneEntries._entry` | grep `_entry` / `PhoneEntries` in `lib/` and `test/`: `watch_reference_sync.dart` and the snapshot builder call it; `test/watch_session_projection_test.dart`, `WatchPhoneEntriesTests.swift` assert its rule | an assisted set is carried instead of dropped | S-59, S-60 |
| `clampTo` / `clamp` | grep `clampTo` in `lib/`: exactly one caller, `adjust` (units already in scope); grep `clamp(` in `watch/watchos/Sources`: only `adjust`. No test calls them directly | the load dial floors at −200 kg instead of 0 | S-61 |
| `_metricPayload` / `WatchLoggingState.swift` | grep `loadKg` in `lib/watch/` and `watch/watchos/Sources`: the emitter and `_lastLogged`/`_valueIn` (which read a stored load back) | an assist is emitted, and re-seeds the next set | S-58, S-62, S-63 |
| `_effectiveEntry` correction validity | grep `loadKg` in `lib/core/services/watch_session_importer.dart`: line ~1505 is the only floor; ~869/1010/1025/1077/1345/1533 already pass a negative load through untouched | a correction to an assist lands; below the floor is refused | S-65 |
| phone analytics | grep `weightKg` in `lib/core/services/session_summary_service.dart`, `lib/state/workout/session_summary_builder.dart`, `lib/core/services/stats_progress_service.dart`: their weight maths is unfloored (the `> 0` at `stats_progress_service.dart` ~357 gates a *positive* PR signal, untouched) | a negative load already flows through; deliberately unchanged | S-58, D-64 |
| routine targets | grep `_targetsJson` / `_wireTargetKey` in `lib/core/utils/watch_reference_sync.dart`: `MetricIds.weight → 'loadKg'`, no filter | an assisted plan validates and reaches the wrist | S-66 |
| `scripts/sqlite_schema.sql` | grep `CHECK` in `scripts/`: the set value's constraints are "at most one value column" and a distance-source check — there is **no** non-negativity check on a weight value | no schema-contract change is needed | D-58 |
| `docs/watch_session_sync.md` "A set the wire cannot carry is omitted." | grep `cannot carry` in `docs/` | the claim becomes false and must be rewritten | Phase 2 item 9 |
| `docs/state_management/watch_surface.md` "…band assist… are not sent" | grep `band assist` in `docs/` | still true (it is about the `extra-weight` metric) — **do not edit** | D-65 |
| `docs/watch-app-setup-and-qa.md` PR 2b walkthrough | grep `PR 2b` in `docs/` | gains one owner step for the assist | Phase 3 item 9 |

### Scope signals (`.github/copilot/pr-scope-budget.md`)

Two tracks are touched — the phone (`lib/`) and the watch client (`watch/watchos/`, `lib/watch/`) —
= **one** soft signal; the sync contract rides with its first consumer, which the budget exempts.
Phases (3), decisions (9), scenarios (10) and plan length are inside the soft band, so exactly one
signal fires: **no PR series and no index plan** — one PR (Q1).

## Scenarios

### S-58: an assisted set logged on the wrist lands on the phone
- Fixture: session `s-58`, slot `sx-bench` for `ex-bench` (capabilities `sets`, `reps`, `load`) with
  no entries; one `observations_up` from the wrist carrying one `set` event: `eventId`=`entryId`=
  `evt-assist-58`, `sessionExerciseId`=`sx-bench`, `reps`=8, `loadKg`=-20; no correction in the stream.
- Trigger: `WatchSessionImporter.apply` on the phone — validity → applicability → `_effectiveEntry`
  (no correction) → the set is written to the slot.
- Expected outcome: the slot holds one set, 8 reps, `weightKg == -20.0`; the summary's volume for it
  is `8 * -20 = -160` (D-64 maths unchanged); nothing is dropped or zeroed.
- Edge case of: none.

### S-59: a snapshot carries the assist; only the row without reps is omitted
- Fixture: one live session on the phone, slot `slot-bench` (`ex-bench`, `sets`/`reps`/`load`), three
  rows: `(reps 8, weightKg -20)`, `(reps 8, weightKg 60)`, `(reps 0, weightKg 0.0, skipped true)`;
  `PhoneEntries.of(sessionState)` is the input.
- Trigger: build the `session_snapshot` payload for the wrist — `PhoneEntries._entry` per row (D-60).
- Expected outcome: the payload's decoded entries are exactly the two ids of the loaded rows, with
  `loadKg` `-20` and `60`; the skipped row's id is absent (its `reps < 1`); `-20` is present.
- Edge case of: none.

### S-60: the floor is carried, one step below it is not
- Fixture: as S-59, plus four rows: `(reps 8, weightKg -200)`, `(reps 8, weightKg -200.1)`,
  `(reps 8, weightKg -240)`, `(reps 1, weightKg 0.0)`; the payload is decoded and compared as a map
  of id → `loadKg` (never a substring, so `-200` and `-200.1` cannot be confused).
- Trigger/Flow: as S-59 (the same projection and the same map comparison).
- Expected outcome: −200 is carried with `loadKg == -200.0`; −200.1 and −240 are omitted;
  the `weightKg 0.0` row is carried **without** a `loadKg` key.
- Edge case of: S-59.

### S-61: the wrist floor is −200 kg, and the step is unchanged
- Fixture: a fresh load dial, no history, exercise capabilities `sets`/`reps`/`load`; units `kg`, then
  units `lbs`; direct `clampTo`/`adjust` calls (no widget).
- Trigger/Flow: table of inputs, driven twice — once by the Dart test, once by the Swift twin:
  `(-100, -1 detent) → -102.5` (a normal step still works); `(-197.5, -1) → -200` (the last step
  lands exactly on the floor); `(-200, -1) → -200`; `(+2.5, -1) → 0` and `(0, -1) → 0` (a positive
  dial still stops at zero).
- Expected outcome: every value as listed, in kg and in lbs (in lbs one detent is 5 lb ≈ 2.27 kg, so
  the floor value is reached in a different number of detents but is the same −200 kg).
- Edge case of: none (new surface).

### S-62: zero still means "no load claim"
- Fixture: a load-capable exercise whose dial was never touched (weight 0); a bodyweight exercise
  with no `load` capability; one drill exercise whose `extraWeight` dial is set to −10.
- Trigger: log each row (`WatchLoggingState._metricPayload`).
- Expected outcome: neither the untouched load row nor the bodyweight row carries a `loadKg` key
  (`containsKey('loadKg')` false); the drill row carries `extraLoadKg: -10` and no `loadKg`
  (unchanged, D-61).
- Edge case of: none.

### S-63: the assist carries to the next set
- Fixture: a session history whose last logged set of the current exercise is `(reps 8, weightKg -20)`;
  a second exercise with no history and no routine target; the dial untouched.
- Trigger: open the logging screen for the exercise with history, then for the one without.
- Expected outcome: the first opens at −20 kg (the last-logged carry-over, D-61's stored value read
  back), the second at the existing EffortDefaults value — a negative carry-over must not fall back
  to 0 or to the routine's target.
- Edge case of: S-58.

### S-64: a leading minus renders in the user's unit
- Fixture: units `kg` and units `lbs`; a stored load of −20 kg.
- Trigger: render the phone's set row and the wrist's dial label.
- Expected outcome: `-20.0 kg` and `-44.1 lbs` respectively (the existing formatter, asserted because
  the negative path was never exercised before); the label's unit follows the user's setting.
- Edge case of: none.

### S-65: a correction to an assist lands; one below the floor is refused
- Fixture: entry `entry-58` holding `loadKg 60`; `structure_change` msg A with a `correct_entry`
  `{ "loadKg": -20 }` for it; `structure_change` msg B with `{ "loadKg": -240 }`; `structure_change`
  msg C with `{ "loadKg": -200 }`.
- Trigger/Flow: `Validate` then apply A, C and B, in that order — schema validation of each message,
  then `_effectiveEntry`'s validity per correction.
- Expected outcome: A and C validate and land (`weightKg == -20.0`, then `-200.0`); B fails schema
  validation (`constraint_violation`, below the floor) and the entry keeps its previous value — a
  refusal, not a clamp to −200.
- Edge case of: S-58.

### S-66: an assisted routine reaches the wrist
- Fixture: three `routines_down` messages built from a routine whose `efforts[0].targets` are
  `{ sets: 3, reps: 5, weight: -20 }` (what `_targetsJson` emits), then `weight: -200`, then
  `weight: -240`; no `fallbackExercises` mismatch.
- Trigger: build the message on the phone, then validate it.
- Expected outcome: the −20 and −200 messages validate and the wrist's stored routine target for that
  effort is −20 kg / −200 kg (not zeroed — this is the regression: today the whole message is
  rejected); the −240 message fails validation on the targets gate.
- Edge case of: none.

### S-67: a re-stated assist is neither duplicated nor zeroed
- Fixture: `reconciliation/band_assist_carried.json` — snapshot A carrying `entry-slot-bench-0`
  (`loadKg -20`); stream = an `observations_up` from the wrist logging its own assisted set
  (`-22.5`) under its own id, then snapshot B re-carrying `entry-slot-bench-0` (−20), the wrist's id
  (−22.5) and a new `entry-slot-bench-1` (−200).
- Trigger/Flow: replay the fixture through both stacks (the generic cross-stack walk, snapshot →
  observations → snapshot) plus the idempotency assertion below.
- Expected outcome: the phone's converged entries map `entryId → loadKg` is exactly
  `{bench-0: -20, wrist-id: -22.5, bench-1: -200}`; the wrist's projected entries carry the same ids
  and payload `loadKg` with no duplicates; no value becomes `0` or `+20`.
- Edge case of: S-59.

## Iteration 1

### Phase 1: the contract (@dba)
1. [ ] Widen both `loadKg` minimums in `watch/sync_protocol/schemas/envelope.schema.json` from
   `{ "type": "number", "minimum": 0 }` to `minimum: -200` — `$defs.entry.loadKg` (line ~199) and
   `$defs.metricTargets.loadKg` (line ~138) — each with a `description`: a set's load in kilograms,
   negative for a band- or partner-assisted set, floored at −200 (the phone's editor bound), the floor
   shared by an entry, a target and a correction (D-58). · `$defs.entry.loadKg`, `$defs.metricTargets.loadKg`
2. [ ] Widen `$defs.correction.loadKg` in `watch/sync_protocol/schemas/messages/structure_change.schema.json`
   (line ~38) from `{ "type": "number", "minimum": 0 }` to `minimum: -200` (D-58). · `$defs.correction.loadKg`
3. [ ] Add `watch/sync_protocol/fixtures/valid/observations_up_band_assist.json` (copy
   `valid/observations_up_distance_and_load.json`: keep one `timed` row, add `set` events for
   `sx-bench`/`ex-bench` at `loadKg: -20`, `reps` 8, and `loadKg: -200`, `reps` 5) and
   `valid/session_snapshot_band_assist.json` (copy `valid/session_snapshot_with_entries.json`, slot
   `slot-bench`, entries at `loadKg: -20` and `-200`). · `evt-assist-1`, `entry-slot-bench-0`
4. [ ] Add `valid/structure_change_band_assist.json` (copy `valid/structure_change.json`, add two
   `correct_entry` changes — `{ "loadKg": -20 }` and `{ "loadKg": -200 }` — and nothing else) and
   `valid/routines_down_band_assist.json` (copy `valid/routines_down.json`, bench `targets.loadKg`
   `-20`, goblet squat `-200`). · `correct_entry`, `eff-bench`
5. [ ] Add `fixtures/reconciliation/band_assist_carried.json` per S-67, on the
   `phone_entries_merge.json` shape: `name`, `description`, `snapshot`, `stream` (two messages),
   `expected`, every envelope at `protocolVersion: 1`, and no remaining-time field anywhere (S-003).
   · `band_assist_carried`
6. [ ] Add `fixtures/invalid/observations_up_load_below_floor.json`: S-58's shape with `loadKg: -240`,
   registered as `expectedCode: "constraint_violation"`. · `evt-assist-1`
7. [ ] Register all six new fixtures in `fixtures/manifest.json`: the five valid ones under `valid`
   (`type`, and `scenario` `S-58`/`S-59`/`S-65`/`S-66`), the reconciliation one under `scenarios`
   (`scenario: "S-67"` and a `property`), the invalid one under `invalid` with the exact
   `expectedReasonContains` **your validator emits** — the run prints it, do not guess the wording, and
   the watchOS suite reads the same manifest. · `manifest.json`
8. [ ] State the floor in `PROTOCOL.md`: in the entry-metrics bullet (line ~129) and in a new
   `1 (amended) | 2026-10-06` row in `## Version history` — a set's `loadKg` MAY be negative down to
   −200 (a band or partner assist), the same floor applies to a routine target and to a correction,
   below −200 MUST be rejected, `protocolVersion` unchanged (D-66); reference the new fixture.
   · `PROTOCOL.md`
9. [ ] Change no validator: `SyncProtocolValidator` is a generic schema walker with no `loadKg` code,
   and the phase passes with it untouched. · `SyncProtocolValidator`

**Done Criteria** (run until green):
`gateway.sh test test/sync_protocol_fixtures_test.dart` (valid fixtures validate, invalid ones are
rejected with the stated code and reason, the register lists every file exactly once),
`gateway.sh test test/watch_reconciliation_cross_stack_test.dart` (the new reconciliation fixture
converges), `gateway.sh lint`, `gateway.sh swift-test` (the watchOS conformance suite walks the same
manifest). If a check ignores a path argument it runs the whole suite; the gate is the same.

**Predicted Files**: `watch/sync_protocol/schemas/envelope.schema.json`,
`watch/sync_protocol/schemas/messages/structure_change.schema.json`,
`watch/sync_protocol/fixtures/manifest.json`,
`watch/sync_protocol/fixtures/valid/observations_up_band_assist.json`,
`watch/sync_protocol/fixtures/valid/session_snapshot_band_assist.json`,
`watch/sync_protocol/fixtures/valid/structure_change_band_assist.json`,
`watch/sync_protocol/fixtures/valid/routines_down_band_assist.json`,
`watch/sync_protocol/fixtures/reconciliation/band_assist_carried.json`,
`watch/sync_protocol/fixtures/invalid/observations_up_load_below_floor.json`,
`watch/sync_protocol/PROTOCOL.md`.

### Phase 2: the phone (@developer)
1. [ ] Add `lib/core/sync_protocol/wire_limits.dart`: `abstract final class WireLimits` with
   `static const double minLoadKg = -200.0;`, a doc comment naming D-59, the three schema sites it
   mirrors and the test that keeps them equal. · `WireLimits.minLoadKg`
2. [ ] Change `PhoneEntries._entry` in `lib/core/sync_protocol/phone_entries.dart` (~112–150): keep
   the `reps < 1` omission, replace the negative-load omission with
   `if (weightKg < WireLimits.minLoadKg) return null;`, carry the value verbatim (D-60), add the
   `wire_limits.dart` import, and rewrite the doc comment above it (it cites D-40/S-42 and states a
   negative load is not carried) to cite D-58/D-60 and S-58/S-60. · `PhoneEntries._entry`
3. [ ] Change the correction validity in `_effectiveEntry` in
   `lib/core/services/watch_session_importer.dart` (~1505) from `value >= 0` to
   `value >= WireLimits.minLoadKg` for `'loadKg'`, leaving `reps`/`durationMs`/`distanceMeters` alone,
   and add the import (D-63). · `_effectiveEntry`
4. [ ] Add `test/watch_wire_limits_test.dart`: read `envelope.schema.json` and
   `messages/structure_change.schema.json`, pull the three `loadKg` minimums from the decoded JSON (no
   regex over raw text), and assert each equals `WireLimits.minLoadKg` and differs from `0`; one test
   per site so a single reverted minimum fails by name. · `'S-061 the three schema loadKg floors are the one constant'`
5. [ ] Rewrite the S-42 test in `test/watch_session_projection_test.dart` (~1428–1480) as two tests,
   S-59 and S-60: the `_Set` fixture grows the rows listed in those scenarios (including `-200`,
   `-200.1`, `-240` and a `weightKg 0.0` row), the skipped row still vanishes, and the assertions
   decode the payload into `entryId → loadKg` instead of matching substrings. · `'S-59'`, `'S-60'`
6. [ ] Add `test/watch_session_import_test.dart` cases: `'S-58'` — one wrist `set` event at
   `loadKg: -20` lands with `weightKg == -20.0` and the summary volume is `-160`; `'S-63'` — the
   next-set carry-over reads a negative last-logged load back; extend the `S-267 live corrections
   carry into history` group with `'S-65'` — corrections of `-20` and `-200` land and `-240` is
   refused, the entry keeping its previous value. Reuse the group's `_set(entryId, {…})` helper. · `'S-58'`, `'S-63'`, `'S-65'`
7. [ ] Add `test/watch_reconciliation_cross_stack_test.dart` test `'S-67'`: replay
   `reconciliation/band_assist_carried.json`, then assert the phone's converged entries map
   `entryId → loadKg` equals the fixture's `expected` values and the wrist engine's
   `entries` (a `WatchObservationRecord`, `payload['loadKg']`) carry the same ids and values once
   each. · `'S-67 digits survive a re-carried snapshot'`
8. [ ] Extend `test/watch_reference_sync_test.dart` with `'S-66'`: a routine whose `weight` target is
   `-20` (then `-200`) produces a `routines_down` message that validates, and one at `-240` that
   does not; assert the built target JSON carries the sign. · `'S-66'`
9. [ ] Rewrite the "**A set the wire cannot carry is omitted.**" bullet in
   `docs/watch_session_sync.md` (~176–186): an assisted set now travels; only a row with no reps and
   a weighted row below −200 kg are omitted; name the tests that pin it
   (`test/watch_session_projection_test.dart` S-59/S-60) and cite D-58/D-60, and drop the band-assist
   limitation sentence. Keep both edited docs far under the 52 KB indexing ceiling. · `docs/watch_session_sync.md`

**Done Criteria** (run until green):
`gateway.sh test test/watch_wire_limits_test.dart`, `gateway.sh test test/watch_session_projection_test.dart`,
`gateway.sh test test/watch_session_import_test.dart`,
`gateway.sh test test/watch_reconciliation_cross_stack_test.dart`,
`gateway.sh test test/watch_reference_sync_test.dart`, then the **full** `gateway.sh test`
(baseline: 3949 passed / ~1 skipped / 0 failed — report the observed counts and any delta),
`gateway.sh format lib/core/sync_protocol/wire_limits.dart test/watch_wire_limits_test.dart`,
`gateway.sh lint` (baseline 196 issues, 0 errors — no new issues).
Invariants: a file search of `lib/state`, `lib/features`, `lib/widgets`, `lib/core` for
`import .*hive_workout_repository` returns nothing; and `docs/state_management/watch_surface.md` plus
the `extra-weight` entries in `docs/data_models.md`/`docs/modality_tracking.md`/
`docs/constants_reference.md` are untouched (D-65 — report it).

**Predicted Files**: `lib/core/sync_protocol/wire_limits.dart`,
`lib/core/sync_protocol/phone_entries.dart`, `lib/core/services/watch_session_importer.dart`,
`test/watch_wire_limits_test.dart`, `test/watch_session_projection_test.dart`,
`test/watch_session_import_test.dart`, `test/watch_reconciliation_cross_stack_test.dart`,
`test/watch_reference_sync_test.dart`, `docs/watch_session_sync.md`.

### Phase 3: the wrist and the residue sweep (@developer)
1. [ ] Floor the load at the shared constant in `clampTo` in
   `lib/watch/logging/watch_metric_stepping.dart` (~126–140): the `weight` case becomes
   `value < WireLimits.minLoadKg ? WireLimits.minLoadKg : value`; `extraWeight` keeps its current
   floor and `duration`/`distance`/`roundDuration` keep `0` (D-62). · `clampTo`
2. [ ] Do the same in `watch/watchos/Sources/WatchSessionEngine/WatchMetricStepping.swift`
   `clamp(_:metricKey:)` (~136–148): declare `static let minimumLoadKg: Double = -200` on
   `WatchMetricStepping` and floor the weight case at it, with a comment saying the value mirrors
   `envelope.schema.json` and `WireLimits.minLoadKg` (D-59). · `WatchMetricStepping.minimumLoadKg`
3. [ ] Emit a negative load in `lib/watch/logging/watch_logging_state.dart` `_metricPayload`
   (line ~646): `if (load != null && load != 0)` instead of `load > 0`, updating the comment above
   (line ~640–643) that explains the zero-omission choice (D-61). · `_metricPayload`
4. [ ] Do the same in `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` (~610). · `_metricPayload`
5. [ ] Split the S-007 test in `test/watch_logging_stepping_test.dart` into
   `'S-007 duration and distance never go negative'` (its duration/distance assertions unchanged) and
   a new `'S-61 an assisted load stops at the wire floor'` carrying S-61's table, in kg and in lbs. · `'S-61'`
6. [ ] Split `testS007LoadAndDistanceNeverGoNegative` in
   `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` the same way
   (`testS007DurationAndDistanceNeverGoNegative` + `testS061AnAssistedLoadStopsAtTheWireFloor` with
   the same table), and rename `testS007ExtraLoadIsSignedBecauseBandAssistIsALoad` to
   `testS061ExtraLoadStaysSignedAndUnbounded` — its `extraLoadKg` assertions stay, its name stops
   claiming band assist rides `extraLoadKg` (D-58). Keep the pound-preference test that pins kg
   storage. · `testS061AnAssistedLoadStopsAtTheWireFloor`
7. [ ] Add a schema-mirror test to the watchOS suite:
   `testS059TheWireFloorMatchesTheSchema` reads
   `watch/sync_protocol/schemas/envelope.schema.json` from the repository root, pulls
   `$defs.entry.loadKg.minimum`, and asserts it equals `WatchMetricStepping.minimumLoadKg`. · `testS059TheWireFloorMatchesTheSchema`
8. [ ] Add an assisted case on both logging surfaces: in `test/watch_logging_surfaces_test.dart` and
   `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift`, a load dial set to
   −20 emits `loadKg: -20` (and the existing no-load bodyweight case still emits no key, S-62). · `'S-062'`
9. [ ] Add step 5 to the "### The wrist's own logging (PR 2b)" list in
   `docs/watch-app-setup-and-qa.md` (~445–467), marked `*(owner)*`: dial the load below zero until
   the row shows a minus and the crown stops at −200; log the set; confirm the phone's session shows
   the same assisted value and its summary counts it. Note it under the walkthrough, not in "known
   gaps". · `### The wrist's own logging (PR 2b)`
10. [ ] Residue sweep — every hit is either fixed in this phase or listed in the phase report:
    search `lib/watch/`, `watch/watchos/Sources/` for load guards (`> 0`, `>= 0`, `< 0 ? 0`) on
    `loadKg`/`weight`; search `lib/`, `watch/`, `docs/` for the old rule's words
    (`cannot carry`, `never be negative`, `non-negative load`, `band assist is not sent`);
    search `test/`, `watch/watchos/Tests/` for `S-42`/`S-007 load` references that no longer hold.
    The only surviving mention of "band assist … not sent" must be
    `docs/state_management/watch_surface.md` (D-65). · sweep

**Done Criteria** (run until green):
`gateway.sh swift-test` (baseline 294 passed / 0 failed — report the observed count),
`gateway.sh test test/watch_logging_stepping_test.dart`,
`gateway.sh test test/watch_logging_surfaces_test.dart`, the **full** `gateway.sh test`,
`gateway.sh format lib/watch/logging/watch_metric_stepping.dart lib/watch/logging/watch_logging_state.dart`,
`gateway.sh lint`. The residue sweep is a Done Criterion of its own: the phase report lists every hit,
its disposition, and the observed counts against these baselines.

**Predicted Files**: `lib/watch/logging/watch_metric_stepping.dart`,
`lib/watch/logging/watch_logging_state.dart`,
`watch/watchos/Sources/WatchSessionEngine/WatchMetricStepping.swift`,
`watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift`,
`test/watch_logging_stepping_test.dart`, `test/watch_logging_surfaces_test.dart`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift`,
`watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift`,
`docs/watch-app-setup-and-qa.md`.

## Files Affected (whole feature; *italic* = reads a touched surface only)

Contract — `watch/sync_protocol/schemas/{envelope,messages/structure_change}.schema.json` (three
`loadKg` minimums), `PROTOCOL.md`, `fixtures/manifest.json`, six new fixtures under
`watch/sync_protocol/fixtures/`. Phone — `lib/core/sync_protocol/wire_limits.dart` (new),
`lib/core/sync_protocol/phone_entries.dart`, `lib/core/services/watch_session_importer.dart`,
`docs/watch_session_sync.md`. Wrist — `lib/watch/logging/{watch_metric_stepping,watch_logging_state}.dart`,
`watch/watchos/Sources/WatchSessionEngine/{WatchMetricStepping,WatchLoggingState}.swift`,
`docs/watch-app-setup-and-qa.md`. Tests — `test/watch_wire_limits_test.dart` (new), the five
`test/watch_*` files the phases name, `test/watch_logging_{stepping,surfaces}_test.dart`, and
`watch/watchos/Tests/WatchSessionEngineTests/WatchLogging{Timers,Surfaces}Tests.swift`;
*`SyncProtocolFixturesTests.swift`*, *`WatchPhoneEntriesTests.swift`* and
*`test/sync_protocol_fixtures_test.dart`* read the same fixtures and must stay green. Deliberately
untouched — `docs/state_management/watch_surface.md`, `lib/core/utils/watch_reference_sync.dart`, the
analytics services, `scripts/sqlite_schema.sql`, `lib/core/sync_protocol/sync_protocol_validator.dart`.

## Notes

- **Dependency graph.** Phase 1 → Phase 2 → Phase 3; Phase 1's schemas gate every later fixture and
  test, and Phase 3 before Phase 2 would leave the watch emitting a value the phone still drops.
- **Intermediate states.** After Phase 1 the wire accepts an assist and no client produces one (inert;
  suites green). After Phase 2 the phone carries an assist both ways and the wrist still cannot dial
  one; only Phase 3 makes an assist creatable on the wrist.
- **Legacy handling.** A negative load the phone already stores becomes visible on the wrist after
  Phase 2 — no migration, no back-fill. No wrist value below the floor can exist: the crown clamps
  before the emitter and the schema refuses it in transit.
- **Omission semantics are unchanged.** `reps < 1` and a below-floor load are the only omissions; a
  zero weight still sends no key. Do not add "omit an assisted set" back anywhere.
- **The version-mismatch path is untouched**: no `protocolVersion` bump, so its fixture and tests keep
  passing unchanged (D-66).
- **The dial does not seed from a routine's targets**: it carries the last logged load, else the
  `EffortDefaults` value; S-66 is a wire/storage scenario, not a dial-seeding one (Q6).
- **The SQL contract needs no change**: no non-negativity check on a set's weight (Impact table), so
  `test/db_seed_test.dart` is untouched and runs in the full suite.
- **Baselines** (re-observe before your first change): `flutter test` 3949 / ~1 skipped / 0 failed, `flutter analyze` 196 issues / 0 errors, `swift test` 294 / 0.

## Progress

- [ ] Phase 1 — not started.
- [ ] Phase 2 — not started.
- [ ] Phase 3 — not started.

## Assumption Log

(Implementers append: decision made, options considered, choice and why. The Planner marks each
RATIFIED — promoted to a D-x — or REVERT — opening a remediation item. Empty until the first run.)

## Feedback

(empty — owner feedback only; fold into a new Iteration block when non-empty, then clear)

## Open questions

Owner-visible, each with the default this plan proceeds on. Veto any before the handoff it affects.

- **Q1 — one PR or a series?** Default: **one PR** (one soft signal: two tracks; the contract rides with
  its first consumer). A veto moves the wrist UI to a second PR.
- **Q2 — negative `loadKg` as the carrier, and −200 as the floor?** Default: **yes to both** — not `extraLoadKg` (a hold's added load), and −200 kg because the phone's editor already enforces it (D-58).
- **Q3 — the third gate the brief omits:** `structure_change.schema.json`'s `correction.loadKg` is
  floored at `0` too — default **widen it** (D-58), else a valid set's correction is refused.
- **Q4 — does volume count an assist as negative?** Default: **leave analytics alone** (D-64); a veto
  makes it a follow-up PR.
- **Q5 — how deep may the wrist dial in pounds?** Default: a flat −200 **canonical kg** floor (≈ −441 lb in lbs, deeper than the phone's editor); a veto means a unit-aware floor in both stacks (D-62).
- **Q6 — should the dial open at a routine's assisted target?** Default: **no change** (D-65); this plan
  only makes the assisted target survive the wire. A veto is a follow-up.
