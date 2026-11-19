# Plan 164 evidence — end-time upper bound

Executor: @developer (Copilot CLI), 2026-11-14. Every count below is copied from a gateway run.

## Baselines (before this run's edits)

- `lint` baseline stated by the brief: **181** issues (pre-existing info notices; `flutter analyze`
  exits non-zero while they stand).
- `test/watch_session_adoption_bridge_test.dart`: 40 passed, 0 failed at HEAD.
- `test/watch_session_import_test.dart` (Mock filter): 14 passed at HEAD.
- `test/watch_session_import_end_clamp_test.dart`: does not exist at HEAD.

## Phase 1 — clamp primitive + adoption bridge

### Red run (tests written first)

`gateway.sh test test/watch_session_adoption_bridge_test.dart` after adding the S-164 group, before
the implementation:

```
00:01 +38 -1: S-16401 a completed a day ahead ends the held workout at now + 5 min [E]
  Expected: <1791203700000>
    Actual: <1791289800000>
  S-16401 the held end is the bound, not the claim
00:01 +38 -2: S-16402 an hour ahead ends an open held workout at now + 5 min [E]
  Expected: <1791202500000>
    Actual: <1791205800000>
```

Both failed for the clamp's reason (the claim stored verbatim), not a compile or fixture error.

### prove-red

```
gateway.sh prove-red HEAD test test/watch_session_adoption_bridge_test.dart
gateway: prove-red: RED AT HEAD (exit 1).
```
Counts: 40 passed, 2 failed (S-16401, S-16402). S-16403 and S-16409(b) pass at HEAD by design —
they guard "no report for an in-bound end" and "a past end stands", which HEAD already satisfies;
they are non-regression guards, not red-proofs.

### Mutation (the report guard, which cannot go red in a prove-red)

- Original line, `lib/state/watch/watch_session_adoption_bridge.dart`:
  `if (boundedMs != atMs) _reportClampedEnd(atMs, boundedMs);`
- Mutated to `if (boundedMs != atMs || boundedMs == atMs) _reportClampedEnd(atMs, boundedMs);`
- Result: `S-16403 an end inside the bound applies untouched` failed with
  `Watch session sync: bounded an end claimed at 2026-10-05T12:32:00.000Z to ...` where the test
  expects no report line.
- Restored the exact original, re-ran: group 4/4 green.

### Green

`00:01 +43 -1: Some tests failed.` — 42 passed, 1 failed. The one failure is NOT a Phase 1
scenario: see "Existing test red (stop-and-report)" below.

## Phase 2 — importer clamp

### Red run (tests written first, implementation absent)

```
00:00 +0 -1: S-16404 [E] Expected: <1790337900000> Actual: <1790424000000>
00:00 +0 -2: S-16405 [E] Expected: <1790337900000> Actual: <1790424000000>
00:00 +0 -3: S-16406 [E] Expected: <1790337900000> Actual: <1790424000000>
00:00 +0 -4: S-16407 [E] Expected: <1790338200000> Actual: <1790424000000>
00:00 +0 -5: S-16408, S-16409 [E] session is null
```
S-16404..S-16407 failed on the claim being stored. S-16408 and S-16409 reported `null` because
their first fixtures carried only an end event: an end with no set row imports nothing (the pass
consumes it), so no session existed to assert on. Fixtures corrected to carry one set row inside the
window — a fixture defect, and the reason prove-red (below) is the proof, not this run.

### prove-red (after the fixture fix)

```
gateway.sh prove-red HEAD test test/watch_session_import_end_clamp_test.dart
gateway: prove-red: RED AT HEAD (exit 1).
```
Counts: 1 passed, 5 failed, every failure on the guard's own assertion:

| Scenario | At HEAD (unbounded) | Expected (bounded) |
|---|---|---|
| S-16404 creation | 1790424000000 | 1790337900000 |
| S-16405 catch-up | 1790424000000 | 1790337900000 |
| S-16406 set stamp | 1790424000000 | 1790337900000 |
| S-16407 no backward drag | 1790424000000 | 1790338200000 (the stored end stands) |
| S-16408 start floor | 1790424600000 (claim) | 1790424000000 (the start) |

S-16409(a) passes at HEAD by design: a past end is untouched, so it is a non-regression guard.

### Green

`00:00 +6: All tests passed!` — 6 passed, 0 failed. Run three times by the brief's rule: three
identical green runs (`+6`, `+6`, `+6`).

### Mutation note

No extra mutation was needed for Phase 2: the prove-red run above has the clamp's own assertions
failing at HEAD for all five bounded scenarios, including the start floor (S-16408), which the
pre-implementation red run could not distinguish from the model's rejection of a negative duration.

## Phase 3 — docs and residue sweep

### Residue sweep

`grep catchUpEndedSession|_catchUpEnd|atMs: atMs|endsBeforeHeldMsByMoreThanSkew` over `lib/`:

| Site | Bounded? |
|---|---|
| `watch_session_adoption_bridge.dart` → `catchUpEndedSession(_boundedEnd(atMs))` | yes — `clampFutureEndMs` |
| `watch_session_adoption_bridge.dart` → `endSession(atMs: atMs == null ? null : _boundedEnd(atMs))` | yes — `clampFutureEndMs` |
| `watch_session_importer.dart` `_End.parse` (creation, `_createSession`) | yes — `math.min(endedAtMs, nowMs + kFutureEndClampMs)`, floored at the start |
| `watch_session_importer.dart` `_catchUpEnd` | yes — `clampFutureEndMs(latest, nowMs)`, writes only when `bounded > row` |
| `watch_session_adoption_bridge.dart` `endsBeforeHeldMsByMoreThanSkew(atMs, held.endedAtMs!)` | comparison only, writes nothing (discard routing) |
| `session_core_lifecycle.dart` `endSession` | `atMs ?? DateTime.now()` — the phone's own clock, or the bridge's bounded value |
| `session_core_entry.dart` `seedFirstEntry(atMs:)`, bridge `_effort(atMs:)` | a set's stamp, not an end; a future stamp is bounded by `_catchUpEnd` |

Zero unbounded writers of a wrist-claimed end remain. The bridge's `seedFirstEntry` path stamps
entries, not the session end, and `_catchUpEnd` bounds the end it may later push.

### Docs

- `docs/state_management/workout_state.md` — `catchUpEndedSession` row gained the clamp clause.
- `docs/watch_session_sync.md` — the D-14604 bullet names both catch-up points and the bound.
- `watch/sync_protocol/PROTOCOL.md` — one sentence in "Idempotency and reconciliation (normative)"
  and one amendment row (2026-11-14); no wire, schema, validator, rejection-code or version change.
- `gateway.sh test test/docs_indexing_contract_test.dart`: 13 passed, 0 failed.

## Suites at handoff

- `lint`: 181 issues, the brief's baseline exactly; `grep` of the log for `end_skew`,
  `watch_session_importer`, `watch_session_adoption_bridge`, `end_clamp` finds no line.
- `test/ui_standards_contract_test.dart`: 41 passed, 0 failed (no UI file touched).
- `test/watch_session_import_test.dart --plain-name Mock`: 14 passed, 0 failed (regression on the
  importer's existing Mock groups; the clamp reports once per test that stamps an end after the
  test clock, and no stored end changed).
- Full `test`: see "Full suite" below.
- Invariant: `grep "import .*hive_workout_repository"` over `lib/` matches only `lib/main.dart` (the
  composition root), so `lib/state`, `lib/features`, `lib/widgets` and `lib/core` stay on the
  interface. Run with the file search tool — the gateway has no grep check.

## Existing test red (stop-and-report) — NOT fixed here

`test/watch_session_adoption_bridge_test.dart`, group `D-15402 the wrist's end instant is the
phone's end`, test `S-15403 a completed ends the open phone session at the wrist's own instant`
line ~2796:

```
00:01 +38 -1: ... [E]
  Expected: <1791202200000>
    Actual: <1791201900000>
  D-15402 the held workout ends when the wrist ended it, not when the frame arrived
```

The fixture stamps the wrist's end at the bridge clock + 10 minutes and adopts at that clock, so the
5-minute bound legitimately fires and the session ends at the bound. The test is not in this plan's
Scenarios or Predicted Files and the file is also modified by the concurrent plan-160 run, so it was
left untouched per the stop-and-report rule. Options for the governor: (a) move the fixture's wrist
end inside the bound (+4 min), (b) inject a bridge `clock:` later than the wrist end for that test,
(c) accept it as a documented behaviour change. Full bridge file: 42 passed, 1 failed (this test).

## Full suite

`gateway.sh test` (no filter), 2026-11-14: **7594 passed, 4 skipped, 6 failed** (`-6`, exit 1).

| Red | File | Cause |
|---|---|---|
| `S-14609 a later completed moves the end to the later instant, and the session stays over` | `test/watch_session_finish_test.dart:1318` | **caused by this plan's clamp** — see below |
| `S-15403 a completed ends the open phone session at the wrist's own instant` | `test/watch_session_adoption_bridge_test.dart:2796` | **caused by this plan's clamp** — see below |
| `S-160xx`-class `SENTRY_PROJECT is missing` | `test/pre_release_gate_upload_destination_test.dart` | environment: no `SENTRY_PROJECT` in this checkout; not this plan's surface |
| `S-15202`, `S-15207` | `test/watch_replay_corpus_test.dart` | plan 160's replay-corpus reds (its own run is regenerating the corpus) |
| `S-165 a wrist-only walk keeps the wrist's own start` | `test/zz_wrist_only_start_test.dart` | another run's scratch file (untracked, deleted again during this run); not this plan's |

## Existing test red #2 (stop-and-report) — `S-14609`, `test/watch_session_finish_test.dart`

```
00:00 +16 -1: S-14609 a later completed moves the end ... [E]
Watch session sync: bounded an end claimed at 2026-11-15T00:14:56.268Z to
  2026-10-05T12:05:00.000Z (no later than this phone's clock plus 5 minutes)
  Expected: <1794701696268>
    Actual: <1794700196268>
  S-14610 the end is the latest instant either side has
  test/watch_session_finish_test.dart 1318:9
```

Why: the file injects `_phoneNow = DateTime.utc(2026, 10, 5, 12)` into the bridge and the inbox,
but the session's start comes from `WorkoutState.createNewSession`, which reads the real clock — and
this machine's real date is 2026-11-15. The fixture's `later = started + 45 min` therefore lies six
weeks beyond the injected bridge clock, the bound lowers it to 2026-10-05T12:05 (which is *before*
`t1 = started + 20 min`), and `catchUpEndedSession` correctly refuses to move an end backward, so the
end stays at `t1`. The clamp behaves as designed; the fixture mixes two clocks.

Left untouched (not in this plan's Scenarios, Predicted Files or the brief's editable list).
Options for the governor: (a) derive `t1`/`later` from `_phoneNow` in that test, (b) inject the
clock `createNewSession` reads, (c) accept a documented behaviour change.

## Files changed by this run

- `lib/core/sync_protocol/end_skew.dart` (+31)
- `lib/state/watch/watch_session_adoption_bridge.dart` (+44/-2)
- `lib/core/services/watch_session_importer.dart` (+41/-4)
- `test/watch_session_adoption_bridge_test.dart` (+295/-1)
- `test/watch_session_import_end_clamp_test.dart` (new, 6 tests)
- `docs/state_management/workout_state.md`, `docs/watch_session_sync.md`,
  `watch/sync_protocol/PROTOCOL.md`
- this evidence file, the plan's Progress and Assumption Log
