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

Starting point is Phase 2's committed HEAD (`49232ed`): `gateway.sh test` `01:40 +3973 ~1`, `lint`
196 issues / 0 errors, `swift-test` 294 / 0.

### Files

| File | Change |
|---|---|
| `lib/watch/logging/watch_metric_stepping.dart` | `clampTo`'s `weight` case split out of the `0`-floored group and floored at `WireLimits.minLoadKg`; `WireLimits` import; doc comment (D-58/D-62) |
| `lib/watch/logging/watch_logging_state.dart` | `_metricPayload` set case: `load > 0` → `load != 0` (D-61); `_displayValueFor` prints `0.0`, never `-0.0` |
| `watch/watchos/Sources/WatchSessionEngine/WatchMetricStepping.swift` | new `minimumLoadKg: Double = -200`; `clamp`'s `weight` case floored at it (D-59) |
| `watch/watchos/Sources/WatchSessionEngine/WatchLoggingState.swift` | `metricPayload` set case: `load > 0` → `load != 0` (D-61); `displayValue` prints `0.0`, never `-0.0` |
| `test/watch_logging_stepping_test.dart` | S-007 split into duration/distance; new S-61 floor table; the extra-load test renamed off `S-007` |
| `test/watch_logging_surfaces_test.dart` | new S-062 (emit), S-063 (carry-over), S-064 (display) cases |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingTimersTests.swift` | S-007 split; S-061 floor table; `testS061ExtraLoadStaysSignedAndUnbounded`; `testS059TheWireFloorMatchesTheSchema` |
| `watch/watchos/Tests/WatchSessionEngineTests/WatchLoggingSurfacesTests.swift` | the same S-062/S-063/S-064 cases on the watchOS surface |
| `docs/watch-app-setup-and-qa.md` | step 5 under "The wrist's own logging (PR 2b)" |

### Done Criteria — observed

| Command | Result |
|---|---|
| `gateway.sh swift-test` | `Executed 302 tests, with 0 failures` — 302 passed / 0 failed (baseline 294; delta +8 = the new cases) |
| `gateway.sh test test/watch_logging_stepping_test.dart` | `00:00 +17: All tests passed!` (17 passed / 0 failed) |
| `gateway.sh test test/watch_logging_surfaces_test.dart` | `00:00 +30: All tests passed!` (30 passed / 0 failed) |
| `gateway.sh test` (full) | `01:40 +3980 ~1: All tests passed!` — 3980 passed / 1 skipped / 0 failed (Phase 3 start 3973; delta +7 = the new tests) |
| `gateway.sh lint` | `196 issues found. (ran in 3.0s)` — unchanged from the baseline, every issue `info`, **none** in a touched file (grep of the log for `watch_logging`/`watch_metric`/`wire_limits` → no matches) |
| `gateway.sh format <the two lib files>` | **refused** — `'format' only runs on files this change created; 'lib/watch/logging/watch_metric_stepping.dart' is already tracked by git`. Phase 3 created no file, so no formatter ran; the edits are line-for-line matches of the surrounding style. Not retried (policy). |
| invariant grep | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → **no matches** |
| `git-diff --stat` | 9 files, `+395 / -31`, every one in the plan's Phase 3 Predicted Files |

### Mutations (each reverted to the exact original; green re-run after)

| # | Mutation | Observed red | Restored |
|---|---|---|---|
| a | `watch_metric_stepping.dart`: the `weight` case back to `value < 0 ? 0 : value` | `test/watch_logging_stepping_test.dart` → `+16 -1`: `S-61 an assisted load stops at the wire floor [E]` — `Expected: <-200>` / `Actual: <0.0>` | yes, `WireLimits.minLoadKg` |
| b | `WatchMetricStepping.swift`: `clamp`'s `weight` case back to `value < 0 ? 0 : value` (`minimumLoadKg` left at −200, so S-059 stays green) | `swift-test` → `Executed 302 tests, with 15 failures`: `testS061AnAssistedLoadStopsAtTheWireFloor` (10 assertions, `("0.0") is not equal to ("-200.0")`), `testS062AnAssistedLoadIsEmittedWithItsSign` (`("Optional(0.0)") is not equal to ("Optional(-20.0")`), `testS063TheNextSetCarriesTheAssist`, `testS064ANegativeLoadPrintsALeadingMinusInKgAndLbs` (`("0.0") is not equal to ("-44.1")`). `testS059TheWireFloorMatchesTheSchema` green | yes, `minimumLoadKg` |
| c | `watch_logging_state.dart`: the emitter back to `load > 0` | `+45 -2`: `S-062 an assisted load is emitted with its sign [E]` — `Expected: contains pair 'loadKg' => <-20>` / the payload has no `loadKg`; and `S-063 the next set opens at the assisted load just logged [E]` — `Expected: <-20>` / `Actual: <0.0>` (nothing was stored to carry). `S-61` green, proving (a)'s restore | yes, `load != 0` |
| d | `WatchLoggingState.swift`: the emitter back to `load > 0` | `swift-test` → `Executed 302 tests, with 10 failures`: `testS062AnAssistedLoadIsEmittedWithItsSign` (`("nil") is not equal to ("Optional(-20.0)")`) and `testS063TheNextSetCarriesTheAssist` (`("Optional(0.0)")`). `testS062AnUntouchedLoadDialSendsNoLoadKg`, `testS062ADrillSendsItsExtraLoadAndNeverALoadKg` and both `testS064…` green, proving (b)'s restore | yes, `load != 0` |
| e | `WatchMetricStepping.swift`: `minimumLoadKg` `-200` → `-100` | same run as (d) → `testS059TheWireFloorMatchesTheSchema` `("−200.0") is not equal to ("−100.0") — the dial's floor is the wire's own floor`, plus `testS061AnAssistedLoadStopsAtTheWireFloor` (`("−100.0") is not equal to ("−200.0")`) | yes, `-200` |

(b), (d) and (e) were run as `gateway.sh swift-test`; (a) and (c) as `gateway.sh test
test/watch_logging_stepping_test.dart test/watch_logging_surfaces_test.dart` (the pairing is what
shows the previous mutation's restore). Final run of both suites with every mutation reverted:
`swift-test` `Executed 302 tests, with 0 failures`, full `gateway.sh test` `+3980 ~1`.

### Residue sweep (step 10) — every hit and its disposition

| Search | Hits | Disposition |
|---|---|---|
| load guards (`> 0`, `>= 0`, `< 0 ? 0`) on `loadKg`/`weight` in `lib/watch/`, `watch/watchos/Sources/` | none on a load/weight metric. The only two load guards are the two floors themselves (`WireLimits.minLoadKg`, `minimumLoadKg`); `duration`/`distance`/`roundDuration` keep their `0` floor (D-62) and `extraWeight` stays unbounded | clean — nothing to fix |
| `never be negative`, `non-negative load`, `band assist is not sent` in `lib/`, `watch/`, `docs/` | **no matches** anywhere | clean |
| `cannot carry` in `lib/`, `watch/`, `docs/` | `docs/watch_session_sync.md:176`; `lib/core/sync_protocol/phone_entries.dart:9,113`; `lib/core/platform/watch_transport.dart:15`; `watch/watchos/Sources/…/WatchConnectivityBridge.swift:16,128`; `PropertyListFrames.swift:24,42`; plus `docs/plans/` history | all are the **transport** rule ("a frame the radio cannot carry is dropped") or Phase 2's rewritten projection bullet — the negative-load half of the bullet already reads "a band-assisted set reaches the wrist as a negative `loadKg` … (D-58)". No stale claim; nothing to fix |
| `band assist … are not sent` | `docs/state_management/watch_surface.md:240` and its source twin `lib/core/utils/watch_reference_sync.dart:230` | **the one surviving mention, as the plan predicts** — both are about the `extra-weight` *metric* having no wire key, which is still true (D-65). **Fix 1 (F4)** rewrote the doc sentence to name the `extra-weight` metric, because with S-66 shipping the "band assist" wording could read as "an assisted weight target is not sent", which is false now (A-P3-4). The source comment is unchanged — it already names the metric |
| `S-42` in `test/`, `watch/watchos/Tests/` | none in `watch/watchos/Tests/`; `test/watch_session_projection_test.dart:29` explains that S-59/S-60 replace it (Phase 2) | clean |
| `S-007 load` in `test/`, `watch/watchos/Tests/` | `test/watch_logging_stepping_test.dart:56` `'S-007 load steps by the saved increment'` (step sizes unchanged, D-62 — still true) | kept |
| `S-007 extra load is signed, because band assist is a load` (`test/watch_logging_stepping_test.dart`) | its assertions still hold, but the name repeated the claim Phase 3's Swift twin dropped | **renamed** to `'S-61 extra load stays signed and unbounded'` with the reason string naming D-58, so both stacks say the same thing |

## Red → green (required for every rule this feature reverses)

D-60 reverses the negative half of `A-14`/`F1`, D-61 and D-62 change two floors. For each, paste the
failing run taken **before** the source change and the passing run after, same command both times:

| Rule | Test | Before the fix | After the fix |
|---|---|---|---|
| D-60 projection | `test/watch_session_projection_test.dart` S-59/S-60 | `S-59 … [E]` — `Expected: {'entry-slot-bench-0': -20.0, 'entry-slot-bench-1': 60.0}` / `Actual: {'entry-slot-bench-1': 60.0}`, `missing map key 'entry-slot-bench-0'`; `S-60 … [E]` — `Actual: ['entry-slot-bench-0', 'entry-slot-bench-1', 'entry-slot-bench-2', 'entry-slot-bench-3']` | `00:00 +112: All tests passed!` (five Phase 2 suites) |
| D-62 floor | `test/watch_logging_stepping_test.dart` S-61 | `+16 -1` — `S-61 an assisted load stops at the wire floor [E]` — `Expected: <-200>` / `Actual: <0.0>` (the `weight` case back on the `0` floor) | `00:00 +17: All tests passed!` |
| D-61 emitter | `test/watch_logging_surfaces_test.dart` S-62 | `+45 -2` — `S-062 an assisted load is emitted with its sign [E]` — `Expected: contains pair 'loadKg' => <-20>` / the payload has no `loadKg` (the emitter back to `load > 0`) | `00:00 +30: All tests passed!` |
| D-63 correction floor | `test/watch_session_import_test.dart` S-65 | `S-65 … [E]` — `Expected: <-200.0>` / `Actual: <-20.0>` (floor `>= 0` refuses the correction) | `00:00 +48: All tests passed!` (`test/watch_session_import_test.dart`) |

## Fix 1 — review 1 (documentation + one assertion, no source change)

F1–F4 (plan row deleted, three doc sentences) and F6 (one assertion in S-65's test) plus the
A-P2-1 → D-67 promotion. **No source file changed**: `git-diff --stat` lists only the plan, the three
docs and the test file — `lib/` does not appear.

### Done Criteria — observed

| Command | Result |
|---|---|
| `gateway.sh test test/watch_session_import_test.dart test/docs_indexing_contract_test.dart` | `00:00 +57: All tests passed!` (57 passed / 0 failed; includes the docs indexing contract) |
| `gateway.sh test` (full) | `01:42 +3980 ~1: All tests passed!` (3980 passed / 1 skipped / 0 failed — +0 over Phase 3, the fix adds an assertion to an existing test, not a test) |
| `gateway.sh lint` | `196 issues found.` — the Phase 1–3 baseline; `lines that look like failures (0)`; no issue mentions any file this fix touched |
| invariant `hive_workout_repository` in `lib/state`, `lib/features`, `lib/widgets`, `lib/core` | **no matches** |
| residue sweep (re-run) | `never be negative` / `non-negative load` / `band assist is not sent` in `lib/`, `watch/`, `docs/` — **no matches** (F4 removed the last one; the only `band assist` prose left is D-65's own text in this plan). `cannot carry` hits are unchanged from Phase 3. `S-42` / `S-007 load` unchanged. |

### The one new guard, red first (mutation F6)

The assertion is the row-identity check added after S-65's `-200.0` assertion:

```dart
expect(
  (await observationAt(repository, bench, 0, 'weight'))?.toMap(),
  beforeRefusal?.toMap(),
  reason: 'S-65 refused, not clamped: the row is unchanged from before the '
      '−240 kg correction, value and stamp alike',
);
```

A bare `weightKg == -200.0` cannot separate the two behaviours — a clamp **also** ends at `-200.0`.
The stamp can: `_applyCorrections` writes `updated_at_ms: entry.stampFor(field)`, so a clamp that
*accepts* the `-240` correction re-stamps the row at that correction's time, where a refusal leaves
value and stamp untouched. `toMap()` carries `updated_at_ms`, so the whole-row comparison separates
them.

| Mutant | Original line (recorded) | Changed to | Observed red |
|---|---|---|---|
| F6 — clamp instead of refuse | `'loadKg' => value is num && value >= WireLimits.minLoadKg,` beside `effective[field] = value;` (`lib/core/services/watch_session_importer.dart:1508`) | `'loadKg' => value is num,` beside `effective[field] = field == 'loadKg' && value is num && value < WireLimits.minLoadKg ? WireLimits.minLoadKg : value;` | `gateway.sh test test/watch_session_import_test.dart --plain-name "S-65 a band assist corrects down to the floor and no further"` → `00:00 +0 -1: S-267 live corrections carry into history S-65 … [E]` — `Which: at location ['updated_at_ms'] is <1790334003000> instead of <1790334002000>`, reason string `S-65 refused, not clamped: the row is unchanged from before the −240 kg correction, value and stamp alike`. Every other field in the two maps is equal, so the stamp is the discriminator. |

Restored the exact original (comment included), re-ran: `00:00 +57: All tests passed!`, and
`git-diff --stat` shows no `lib/` entry — the mutation was not left applied.
