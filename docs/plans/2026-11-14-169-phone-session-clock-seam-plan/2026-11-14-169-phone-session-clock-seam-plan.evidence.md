# Plan 169 — evidence

Baseline carried into this run (from the plan and plan 161's evidence): `gateway.sh lint`
reports **181 issues** (all pre-existing info notices); full `gateway.sh test` baseline
`+7612 ~4`; 200-seed sweep shipping ratchet constant **8**.

## Phase 1 — the session-core clock seam

Prove-red for the new unit pin (S-16901), run as
`gateway.sh prove-red HEAD test test/workout_state_clock_seam_test.dart`:

```
00:00 +0 -1: S-16901 with a fixed injected clock every persisted session stamp carries it [E]
  Expected: 'session-1794301200000'
    Actual: 'session-1794704546325'
     Which: is different.
              Expected: ... ssion-1794301200000
                Actual: ... ssion-1794704546325
  test/workout_state_clock_seam_test.dart 23:7  main.<fn>
00:00 +0 -1: Some tests failed.
gateway: prove-red: RED AT HEAD (exit 1).
```

The failure is the row id minted from the wall clock, i.e. the behaviour the test guards, not a
compile or load error. After the seam: `flutter test test/workout_state_clock_seam_test.dart`
→ `+1: All tests passed!`.

## Phase 2 — the harness pin and the re-derivation

Three mutation proofs, each restored to the exact original line before the next step:

| # | Original line | Mutation | Test that failed | Restored |
|---|---|---|---|---|
| 1 | `final phone = WorkoutState(repository, clock: _gridClock(clock));` (`test/helpers/watch_pair_harness.dart`) | reverted to `WorkoutState(repository)` | S-16904 `the phone's own end lands on the pair clock` — `Actual: <402852964>` ms gap | yes, green |
| 2 | `final nextMs = max(gridMs, lastMs + 1);` (`_gridClock`) | `final nextMs = gridMs;` | S-16905 `a same-millisecond discard-and-restart mints a fresh session id` — `Expected: not 'session-1794301200000'` | yes, green |
| 3 | `_clock()` inside `TimerManager.recordRestStart` | `DateTime.now()` | S-16906 `rest and timer stamps land on the grid` — `Actual: <402881844>` ms gap | yes, green |

D-16905's statement, recorded as Phase 2 item 8 asks: today (before this plan) the phone's own
rows are stamped `DateTime.now()`, the harness cannot pin them, and a phone end lands ~4½ days
away from the grid — the gap above (≈402 852 000 ms) is that distance. The `_gridClock` default
is *not* the bare `clock.call`: a discard and a restart with no `TimeAdvances` between would
mint `session-$nowMs` twice and `HarnessRunner`'s per-id bookkeeping would read the new session
as the discarded one. The wrapper keeps every read at least 1 ms after the last and never behind
the grid, and a var/flag is not needed because the drift (≤ the number of reads per trace)
stays far inside `kEndSkewToleranceMs` (2000).

S-14512 re-derivation, observed on the seamed pair (not blind-patched):

```
S-14512 final statuses: phone completed wrist completed, 0 mismatch(es), 0 entry mismatch(es)
```

Both ends read `completed`, `statusMismatches` is empty and `converged` is true: the old
`abandoned`/`abandoned` disagreement was entirely the wall-clock row end (A-161-05), so the test
now asserts the standing rules — the finish and the discard inside the skew tolerance tie, the
finish wins, the workout survives (A-169-05, S-16908).

Whole harness file after the pin: `00:01 +36: All tests passed!` (S-16101–S-16104 still green;
S-14507's timer tally 0 at all three gaps).

## Phase 3 — re-measurement (D-16906)

Two 200-seed sweeps (`gateway.sh test test/watch_convergence_random_test.dart --dart-define=CONVERGENCE_SEEDS=200`),
logs `.work/gateway/test-20261114-195451-63573.log` and `.work/gateway/test-20261114-195627-64073.log`:

| Run | Converging | Shipping divergers | Heal stall only | Harness-only | by class |
|---|---|---|---|---|---|
| 1st 200 | 194 | 4 — `[94, 123, 145, 167]` | 1 `[142]` | 1 `[138]` | `{status: 3, entries: 2, heal: 1}` |
| 2nd 200 | 194 | 4 — `[94, 123, 145, 167]` | 1 `[142]` | 1 `[138]` | `{status: 3, entries: 2, heal: 1}` |
| 3rd 200 (after the `knownClasses` text edits) | 194 | 4 — `[94, 123, 145, 167]` | 1 `[142]` | 1 `[138]` | `{status: 3, entries: 2, heal: 1}` (`00:45 +3: All tests passed!`) |

The two runs agree seed for seed (S-16909), so the sample is reproducible on the seamed pair.

2000-seed soak (`--dart-define=CONVERGENCE_SEEDS=2000`, log
`.work/gateway/test-20261114-195739-64533.log`, exit 0):

```
S-14509 contract: 2000 seeds; 1933 converge on every trace; 31 diverge on a trace the shipping
app can perform [94, 123, 145, 167, 238, 246, 256, 287, 302, 319, 385, 437, 523, 541, 642, 680,
815, 823, 1137, 1142, 1189, 1253, 1285, 1362, 1458, 1496, 1561, 1596, 1754, 1798, 1895]; 13 on a
heal stall alone [142, 209, 270, 316, 899, 1441, 1479, 1598, 1662, 1893, 1974, 1977, 1985]; 23
only after the harness-only re-assert [138, 267, 277, 334, 489, 618, 629, 659, 768, 798, 925,
1271, 1297, 1313, 1395, 1425, 1433, 1477, 1550, 1558, 1568, 1790, 1875]
S-14509 contract: by class {status: 41, entries: 9, heal: 19}
```

Before/after, kind-hits at 2000 (before = plan 161 evidence §Phase 4):

| Class | Before (plan 161) | After (plan 169) |
|---|---|---|
| `status` | 94/95 over 73 seeds | **41** |
| `entries` | 0/2 | **9** |
| `heal` | 34 | **19** |
| `absorbing` | 4/5 | **0** |
| shipping divergers | 73/75 | **31 of 2000** (4 of 200) |

`status` did not reach 0, so per D-16906 its `knownClasses` text is **not** rewritten as fixed:
it keeps the class, gains the re-measured reading and names what the seam did remove (the
phone's own row end, A-161-05). `absorbing` and `entries` texts gained their re-measured figures
so they do not read as older numbers.

Ratchet: `(kSeedCount * 6 / 200).ceil()` — 6 per 200 seeds (60 at 2000), i.e. 4 measured + 2
headroom paced by D-161-03's policy, down from 8 and never up (D-16906/D-16306). The 31 shipping
divergers at 2000 sit under 60.

## Phase 4 — docs delta and residue sweep

| Doc | Delta |
|---|---|
| `docs/state_management/workout_state.md` | +10 lines: the `clock` seam after the `wristRunsSession` paragraph — one value feeds `TimerManager` and `SessionCore`, the named-instant paths keep the caller's `atMs`, `lib/main.dart` passes none, tests pin it (S-16901, S-16904, S-16905, S-16906) |
| `docs/state_management/watch_surface_transport.md` | +14 lines in `### Convergence testing`: the phone half's `WorkoutState(clock: _gridClock(clock))` pin and why it is strictly monotone, S-14512's re-derived reading, the ratchet 8 → 6 |

Both pages stay in the 52 KB band (`docs_indexing_contract_test.dart` green; the pages were
32.6 KB and ~12 KB before the delta).

Residue greps (`DateTime.now` over the seamed files):

```
lib/state/workout/session_core.dart:        _clock = clock ?? DateTime.now,
lib/state/workout/timer_manager.dart:       _clock = clock ?? DateTime.now;
```

`session_core_lifecycle.dart`, `session_core_io.dart`, `session_core_entry.dart` and
`workout_state.dart` have zero. The allowed remainder is exactly D-16902's list, unchanged:
`session_block_manager.dart` (2), `exercise_library.dart` (2), `session_summary_builder.dart` (1)
inside `lib/state/workout/`.

Project invariant: `import .*hive_workout_repository` over `lib/state`, `lib/features`,
`lib/widgets`, `lib/core` → no matches.

No-change records: `docs/watch_session_sync/what_does_not_sync.md` unchanged (the product
conflict rule is untouched — the seam changes which clock stamps, not who wins);
`lib/data/models/models.dart` and `scripts/sqlite_schema.sql` untouched (no schema drift).

## Plan-unpredicted red (reported, not absorbed)

The full suite has **one** failure, and it is this plan's: S-15207 the corpus is fresh
(`test/watch_replay_corpus_test.dart`) reports **`['seed-408.json']` stale**. D-16905 claimed
"the replay corpus is unaffected because it records the wrist's input timeline only, phone-side
stamps never enter a recording" — that is false for timer frames. The checked-in
`watch/sync_protocol/fixtures/replay/seed-408.json` holds the phone's rest stamp as
`startedAtMs: 1795301201000` (wall clock, ~11.6 days off the grid); with the seam it becomes a
grid instant, so the recorded `expected` no longer matches a fresh recording.

Attribution, by mutation (pin reverted to `WorkoutState(repository)`, restored after):

```
pin on:  00:00 +0 -1: S-15207 ... [E]  Expected: empty  Actual: ['seed-408.json']
pin off: 00:00 +1: All tests passed!
```

Remedy (not applied here — it writes a checked-in fixture and the Swift replay suite reads it, so
it is outside this phase's Predicted Files): regenerate once with
`flutter test --dart-define=REPLAY_CORPUS_WRITE=true test/watch_replay_corpus_test.dart` and run
`.github/copilot/scripts/macos/gateway.sh swift-test --filter WatchReplayTests`. Only
`seed-408.json` changes. Full-suite counts for the rest:
`07:14 +7626 ~4 -1: Some tests failed.` (the `-1` is this test).

## Residue

- **`status`, 41 kind-hits of 2000.** Not the seam's cause any more; not shrunk here (D-16906).
  Hands to plan 163's re-measure.
- **`entries`, 9 of 2000.** Rose from 0/2 as the phone's own rows joined the sample; still a
  wrist-vs-wrist difference that moves between runs (plan 161 Residue).
- **`heal`, 19 of 2000.** The known flake class; excluded from the ratchet, not deterministic.
- **No new class** arrived (the S-14509 `unknown` guard is green).
- **D-16907 (plan 163 resume).** Plan 163's Phase 2 re-measures on this baseline and inherits
  the constant 6 (down only). The stash's `relaunchPhone` must build
  `WorkoutState(repository, clock: _gridClock(clock))`; the note is on `_gridClock`'s doc
  comment so the rebase cannot miss it.
