# Evidence — plan 167 (a wrist-only workout's real start and duration on the phone)

Baseline for this run: HEAD `18e5dd2c`; `gateway.sh lint` issue count 181 (pre-existing); full suite
`+7599 ~4`. All commands below are `.github/copilot/scripts/macos/gateway.sh …`.

## Phase 1 — the register, written red first

Nine tests in four files, all before any `lib/` change:

| File | Group / test | Scenario |
|---|---|---|
| `test/watch_convergence_harness_test.dart` | `plan 167 the wrist’s own start on the phone` — `S-16701 …`, `S-16702 …` | S-16701, S-16702 |
| `test/watch_session_import_test.dart` | `plan 167 the held row’s start` — `S-16703 …`, `S-16704 A/B/C …`, `S-16705 …` | S-16703, S-16704, S-16705 |
| `test/watch_session_adoption_bridge_test.dart` | `S-16706 the report-opened row is born with the report’s at`, `S-16706 a report whose at cannot parse opens at the phone clock` | S-16706 + guard |
| `test/watch_session_finish_test.dart` | `S-16707 an old wrist whose end never arrived never writes an inverted row` | S-16707 |

### Red run at HEAD (before the fix)

`gateway.sh test test/watch_session_import_test.dart --plain-name "plan 167"`
→ `00:00 +1 -4: Some tests failed.`

- `S-16703` — Expected `<5>` Actual `<null>`: the fixture's effort id was the protocol id; the merge
  path keys efforts by slot id (`efforts[slot]`), so the effort is created under `sx-bench`. Fixture
  fixed; the test then passes at HEAD (it is a pin).
- `S-16704 B` — `Expected: <1790332200000> Actual: <1790333940000>` (start still the held one).
- `S-16704 C` — `Expected: <1790332800000> Actual: <1790333400000>`.
- `S-16705` — `Expected: <1790332200000> Actual: <1790333940000>`.
- `S-16704 A` passes at HEAD (pin).

`gateway.sh test test/watch_convergence_harness_test.dart --plain-name "plan 167"` →
`S-16701` passes, `S-16702` fails
`Expected: <1794694641000> Actual: <1794695842000>` (start = the adoption instant 22:37:22).

`gateway.sh test test/watch_session_adoption_bridge_test.dart --plain-name "S-16706"` →
`S-16706 … born with the report’s at` fails `Expected: <1791194400000> Actual: <1791201600000>`;
the unparseable-`at` guard passes.

`gateway.sh test test/watch_session_finish_test.dart --plain-name "S-16707"` → passes at HEAD (pin).

### prove-red verdicts (gateway)

```
gateway: prove-red: RED AT HEAD (exit 1).  — test/watch_session_import_test.dart --plain-name "plan 167"
gateway: prove-red: RED AT HEAD (exit 1).  — test/watch_convergence_harness_test.dart --plain-name "plan 167"
gateway: prove-red: RED AT HEAD (exit 1).  — test/watch_session_adoption_bridge_test.dart --plain-name "S-16706"
```

Fixture notes (A-167-05/A-167-06 in the Assumption Log):

- S-16701 is green at HEAD, not red as the plan predicted: with the link down for the whole workout
  the drained burst reaches the inbox, whose snapshot import calls `_createSession` — already correct —
  before any adoption opens a row. The correction paths are therefore proven red by S-16702 (harness),
  S-16704 B/C and S-16705 (unit) and S-16706 (bridge), which is five reds.
- S-16702's `advanceTime(1201) → 22:57:33` is a ten-second slip (22:37:22 + 1201 s = 22:57:23); the
  fixture advances 1211 s so the wrist's end is the owner's 22:57:33 and the span is 2 412 000 ms.

## Phase 2 — the fix

`lib/core/services/watch_session_importer.dart`: new
`static Future<TrainingSession?> _carryWristStart(repository, existing, end)` — a `!followed`
end whose start is EARLIER than the row's moves `started_at_ms` down to it (never later); a row whose
end equals its pre-correction start (the D-153 floor artifact) also takes the wrist's end. Called in
`_mergeHeld` right after `end`/`existing` are read and in `_Pass.run`'s existing-row branch.

`lib/state/watch/watch_session_adoption_bridge.dart`: `onSessionStarted` passes
`_instantMs(payload['at'])` into `_startSessionRow`, which stamps `startedAtMs` from it and falls back
to the phone clock; `createdAtMs`/`updatedAtMs` and the segment's `atMs` stay the arrival stamp.

### Green runs after the fix

```
test/watch_session_import_test.dart --plain-name "plan 167"        → 00:00 +5: All tests passed!
test/watch_convergence_harness_test.dart --plain-name "plan 167"   → 00:00 +2: All tests passed!
test/watch_session_adoption_bridge_test.dart --plain-name "S-16706" → 00:00 +2: All tests passed!
test/watch_session_finish_test.dart --plain-name "S-16707"         → 00:00 +1: All tests passed!
```

### Mutation proofs (guards the pins cover)| Mutation | Test | Result |
|---|---|---|
| drop `end.followed \|\|` from the guard (original line: `if (end.followed \|\| startMs == null \|\| startMs >= existing.startedAtMs) {`) | `S-16703` | FAILS `Expected: <1790333400000> Actual: <1790332200000>` — the followed end moved the phone's start |
| `startMs >= existing.startedAtMs` → `false` (earlier-only dropped) | `S-16704 A` | FAILS `Expected: <1790333400000> Actual: <1790333900000>` — a later start moved the row |
| `floored` → `false` (original: the `endMs != null && existing.endedAtMs != null && existing.endedAtMs == existing.startedAtMs` expression) | `S-16704 B` | FAILS `Expected: <1790333440000> Actual: <1790333940000>` — the floored end was kept |

Every mutation was restored to the exact original line and the group re-run green
(`00:00 +5: All tests passed!`).

The current source reads `if (end.followed || startMs >= existing.startedAtMs) {` and
`final floored = existing.endedAtMs != null && existing.endedAtMs == existing.startedAtMs;`: lint
(`unnecessary_null_comparison` ×2) showed `_End.startedAtMs`/`_End.endedAtMs` are non-nullable `int`,
so the `startMs == null` / `endMs != null` disjuncts proven above were dead branches. They were
removed after the proofs; no reachable input changes, and the same three tests stayed green in the
§Phase 3 runs below.

## Phase 3 — docs, full suite, lint, sweep

### Docs

| Doc | What changed | Test it names |
|---|---|---|
| `docs/watch_session_sync.md` | the adoption-table row now says a wrist `session_started` report opens the row at the report's `at` (D-16703); new paragraph "A session the phone heard of late keeps the wrist's own start (D-16701/D-16702)" after "The two directions of ending" — the merge/drain correction, the floor-artifact drop, the import-path twin (D-16705), and that a `followed` end moves nothing and stored rows are not repaired (D-16706) | `S-16701`, `S-16702`, `S-16703`, `S-16704 A/B/C`, `S-16705`, `S-16706`, `S-16707` |
| `docs/watch_session_capture.md` | new "Why a wrist end may move an existing row's start" paragraph before "Why the rating and the end are observations of their own" | `S-16702`, `S-16703`, `S-16704 B/C`, `S-16705` |
| `docs/state_management/workout_state.md` | **no update required** (verify-no-change): `endSession` still writes `endedAtMs = max(startedAtMs, now)` and `catchUpEndedSession` still only moves an end later; the correction lowers start and end together (never below the new start), so the writer-window claim "a stored end never precedes its start" stays true — pinned by `S-155 writer table — every phone-owned writer leaves an ordered window` and by `S-16704 B/C` | — |

Doc sizes: `docs/watch_session_sync.md` 679 lines (was 657), `docs/watch_session_capture.md` 608
lines (was 595). The 52 KB band is automated as the warning ratchet in
`test/docs_indexing_contract_test.dart` (`_warnFraction = 0.80` of the 64 KiB ceiling ≈ 51.2 KiB):
`no documentation file is within the warning band of the ceiling` and
`no documentation file exceeds the indexing ceiling` both passed in the full run below, so neither
touched page is in the band. Exact byte counts are not measurable with the developer's tool set
(`wc -c` is not a gateway check); the two assertions above are the mechanical evidence.

### Three runs of each new test file

```
test/watch_session_adoption_bridge_test.dart + finish + import, --plain-name "S-1670"
  pass 1 → 00:00 +8: All tests passed!
  pass 2 → 00:00 +8: All tests passed!
  pass 3 → 00:00 +8: All tests passed!
test/watch_convergence_harness_test.dart --plain-name "plan 167"  → 00:00 +2: All tests passed!
  (run three times across the fix, the magnification check and this phase)
```

### Lint

```
gateway.sh lint → 181 issues found. (ran in 2.8s)   [baseline 181; 0 in the files this run touched]
```

The first lint run after Phase 2 reported 183: `unnecessary_null_comparison` ×2 at
`lib/core/services/watch_session_importer.dart:462:33` and `:466:15` — the dead `startMs == null` /
`endMs != null` disjuncts the mutations above were proven with. Removing them and the unused
`nowMs` parameter brought the count back to 181.

### Full suite (once, 900 s check timeout)

```
gateway.sh test → 05:29 +7612 ~4: All tests passed!
```
Baseline was `+7599 ~4`; +13 are this plan's 9 tests and plan 168's new ones (a parallel run editing
`watch/watchos/**`, `lib/watch/sensors/watch_platform_workout.dart` and
`test/watch_sensor_recording_test.dart` — none of its reds appeared).

### Convergence sweep, 200 seeds

```
gateway.sh test test/watch_convergence_random_test.dart            → 00:26 +15: All tests passed!
  S-14509 contract: 200 seeds; 191 converge on every trace; 4 diverge on a trace the shipping app
  can perform [94, 136, 162, 169]; 2 on a heal stall alone [86, 184]; 3 only after the harness-only
  re-assert [110, 138, 183]
gateway.sh prove-red HEAD test test/watch_convergence_random_test.dart → GREEN AT HEAD (the sweep is
  not a guard); the same run reports HEAD's baseline:
  S-14509 contract: 200 seeds; 194 converge on every trace; 3 diverge on a trace the shipping app
  can perform [94, 162, 169]; 1 on a heal stall alone [86]; 2 only after the harness-only re-assert
  [110, 138]
```

Against the brief's acceptance rule (the class counts must not get worse than plan 161's **5 shipping
divergers**): this tree has **4**, so it passes. The +1 is a seed moving *into* the class that
already owns the defect (136 joins 94/162/169, reported as `status`), plus one healer each in the
heal-stall (184) and harness-only (183) classes. Note that both `lib/` changes in this working tree
(this plan's importer/bridge and the parallel plan 168's sensor mirror) feed the same harness, so the
attribution of 183/184 between them cannot be isolated from a single sweep; the contract test's
per-class report is what the brief asks for and it passes.

### Residue sweeps

- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` — no
  matches (no concrete persistence in state/UI).
- `test/ui_standards_contract_test.dart` — untouched by this run (no widget, colour, button or copy
  changed) and green in the full suite above.
- No new allowlist entry, no ratchet raised, no change under `watch/**`, `ios/**`, `.claude/**`,
  `.github/**`, `test/helpers/watch_pair_harness.dart`, `test/watch_convergence_random_test.dart` or
  another plan's files; no commits.
