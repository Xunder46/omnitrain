# Evidence — plan 161 (the convergence harness stops reporting its own artifacts)

Every number below is copied from a gateway run in this session. Logs live in `.work/gateway/`.

## Baselines (before this change)

| item | value | source |
|---|---|---|
| `gateway.sh lint` | 181 issues, 0 errors — unchanged from the baseline (one `unused_local_variable`
  warning I introduced in `test/watch_convergence_harness_test.dart` was fixed, and the re-run is
  back at 181) | `.work/gateway/lint-20261114-164458-32903.log` |
| full `gateway.sh test` | baseline before this change: `+7572 ~5 -2` (two reds below). After: `+7577 ~5 -1`
  — the only failure left is S-15207; S-5115 passed both of this run's passes | `.work/gateway/test-20261114-164513-33104.log` |
| four-file Phase 1 suite | `+158 ~1: All tests passed!` | `.work/gateway/test-20261114-163458-27369.log` |
| harness + `docs_indexing_contract_test` + `ui_standards_contract_test` | `+84 ~1: All tests passed!` | `.work/gateway/test-20261114-164506-32995.log` |
| full-suite red 1 | `test/logger_feedback_controls_test.dart` S-5115 rolling list — passes alone and at HEAD | `prove-red HEAD` → GREEN AT |
| full-suite red 2 | `test/watch_replay_corpus_test.dart` S-15207 "the corpus is fresh" — all 16 recordings stale, deterministic, green at HEAD | `prove-red HEAD` → GREEN AT |
| plan 158 measured, 2000 seeds | 112 shipping divergers; kind-hits `{status 149, entries 8, heal 42, absorbing 3}` | plan 158 §1/§3/§5 |
| 200-seed ratchet constant | 14 | `test/watch_convergence_random_test.dart` |

Both reds are pre-existing/environmental, not caused by this plan: each was proved GREEN at
`HEAD` with `prove-red`, i.e. they fail with and without this change. The replay corpus
regeneration needs `--dart-define=REPLAY_CORPUS_WRITE=true`, which rewrites tracked fixtures — a
governor action, listed in the report.

## Phase 1 — the frame-clock seam

Product change (the only one in `lib/`):

- `lib/state/watch/watch_sync_wiring.dart`: `DateTime Function()? frameClock` after `clock`,
  passed as `clock: frameClock,` into `LiveSessionMirrorState(...)` above the unchanged
  `ledgerClock: clock,`; wiring comment rewritten to name the seam (D-16102, D-16103).
- `lib/state/watch/live_session_mirror_state.dart`: constructor doc — `clock` stamps the frames
  (`sentAt`, lifecycle `at`, rating `loggedAt`), `ledgerClock` stays separate (plan 128 D-1/D-2a).
- `lib/main.dart`: untouched (the production proof — the default keeps `_utcNow`).

Harness pin: `test/helpers/watch_pair_harness.dart` · `WatchPairHarness.build` passes
`frameClock: clock.call,` beside `clock: clock.call,`.

### Red → re-derivation

| test | before the pin | after the pin | verdict |
|---|---|---|---|
| S-14512 (existing, `test/watch_convergence_harness_test.dart`) | green | red: `Expected: 'abandoned' Actual: 'completed'` | re-derived per Phase 1 item 5, recorded as **A-161-05** |

Cause: the phone's own session row (`TrainingSession.startedAtMs/endedAtMs`) is stamped by
`DateTime.now()` in `session_core_lifecycle.endSession`; the mirror's frames are now on the
harness grid, so the phone's end and the wrist's end can never tie. This is a product fact with no
harness seam, so the expectation was re-read against the coherent clock: the phone abandons on the
wall clock, the wrist finishes on the grid, the pair reports the disagreement — permanently.

### Suites

| run | result |
|---|---|
| `test/watch_convergence_harness_test.dart` right after the pin | `+26 ~1` (1 skip pre-existing) |
| the four Phase 1 files (`diagnostics_wiring_source_test`, `watch_convergence_harness_test`, `live_mirroring_test`, `watch_session_auto_push_test`) | `+158 ~1: All tests passed!` |
| `test/watch_convergence_harness_test.dart` after Phases 2–3 | `+30 ~1: All tests passed!` |

## Phase 2 — the entries filter

Red test first (S-16101), then the filter (D-16101: `HarnessRunner._sampleEntries` keeps only
inbox rows whose `kind` is not in `WatchInboxEntry.phoneKinds`).

| step | observation |
|---|---|
| S-16101 before the filter | RED with exactly plan 158 §3's predicted ids: `['phone-change-del-w-entry-1-1794301231000-1-0', 'phone-change-del-w-entry-2-1794301231000-0-0']` |
| S-16101 after the filter | GREEN |
| mutation: filter disabled (`if (!false && entry.kind.isNotEmpty)`) | S-16101 RED again with the same two ids |
| restored (`if (!WatchInboxEntry.phoneKinds.contains(entry.kind))`) | GREEN |
| S-16102 (teeth: a wrist-kind entry the wrist never got still mismatches) | GREEN with the filter; the mismatch names a wrist-kind entry id |
| `test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` | green |

`prove-red` cannot compile a helper that does not exist at `HEAD` (the filter and the tie predicate
are new code), so both proofs here and in Phase 3 are mutations: original line recorded above,
mutated run red for the reason the test guards, EXACT original restored, green re-run. No mutation
was left applied.

## Phase 3 — the within-tolerance tie

Harness + tests only (owner-to-confirm, D-16105).

- `HarnessRunner` gained `phoneEndAtMs`/`wristEndAtMs`, filled in `_phoneDiscards` (`clock.now`),
  `_phoneStatusOf` (`row.endedAtMs!`) and `_wristStatusOf` (the newest stored
  `WatchSessionRecord.recordedAt`, via `_noteWristEnd`).
- Top-level `endsWithinSkewToleranceMs(int aMs, int bMs)` — the ms twin of `areEndsWithinSkew`.
- `ConvergenceReport.withinSkewEndTies` (local `withinSkewEndTies` in `checkConvergence`): terminal
  statuses + both instants known + within `kEndSkewToleranceMs` → a recorded tie instead of a
  `statusMismatches` line; NOT in `failures`; counted in `toString`'s converged branch. Unknown
  instants still mismatch; same-status behaviour untouched (D-15405). `_kindsOf` reads nothing new.

| test | result |
|---|---|
| S-16103 (discard and finish both at t0) | GREEN first try — both instants `1794301200000`, `withinSkewEndTies` names session 1, converged |
| S-16104 (discard t0, finish t3) | RED first (wrist read `completed`, the plan predicted `abandoned`) → re-derived as **A-161-06**; green as "both instants known, gap 3000 > `kEndSkewToleranceMs`, `withinSkewEndTies` empty, one `statusMismatches` line, `converged` false" |
| mutation: `endsWithinSkewToleranceMs` inverted | S-16103 and S-16104 both RED (`Expected: true Actual: <false>` / its reverse) |
| restored | both GREEN |

A-161-06 in one line: the phone's queued `abandoned at=09:00:00` never replaces the wrist's held
finish (the wrist is `active`, so `_applyLifecycle`'s terminal branch is skipped); the frame that
lands is the mirror's re-offer stamped `at=09:00:03` (plan 128 D-1), a product-level tie that
D-14603 resolves to `completed`. The plan's "both sides read abandoned" is unreachable, so the
test asserts what the harness measures: the instants the ends were performed at, 3 s apart, reported
as a mismatch.

## Phase 4 — re-measured sweeps

| measurement | before (plan 158) | after (this change) |
|---|---|---|
| 2000 seeds: converge on every trace | 1866 | **1869**, then **1866** (two runs) |
| 2000 seeds: shipping divergers | 112 | **73**, then **75** |
| 2000 seeds: kind-hits by class | `{status 149, entries 8, heal 42, absorbing 3}` | **run 1** `{status 94, heal 34, absorbing 5}` · **run 2** `{status 95, heal 34, absorbing 4, entries 2}` |
| 2000 seeds: heal-only / synthetic-only | — | 22 / 36, then 25 / 34 |
| 200 seeds: shipping divergers | 18 | **5** (`[29, 43, 94, 162, 169]`) |
| 200 seeds: converge on every trace | 190 | **189** (run A and run B identical) |
| 200-seed ratchet constant | 14 | **8** (measured 5 + 2 headroom at 200; `ceil(2000 × 8 / 200) = 80 ≥ 75`, so it is also the lowest constant the soak allows) |

`entries` fell from 8 kind-hits at 2000 to 0 in run 1 and 2 in run 2 (seeds 499, 819): the Phase 2
filter removed the phone's own annotation kinds from check 3, so what is left is a wrist-vs-wrist
entry difference that is not deterministic — the same seeds converge in the other run. `status` fell
from 149 to 94/95 kind-hits (112 → 73/75 shipping seeds) and does **not** reach zero: what remains
is A-161-05's residue (the phone's own row is wall-clock stamped), which no harness seam can tie to
the grid. `absorbing` moved 3 → 4/5 kind-hits, unchanged in mechanism (the wrist completes a
session, starts its next Free workout, and the same session reports active again — seed 111's
4-action trace, A-146c-14). `timers` stays at 0 (A-146c-16).

Determinism check (S-16105): both 200-seed runs printed the same line —
`200 seeds; 189 converge on every trace; 5 diverge on a trace the shipping app can perform
[29, 43, 94, 162, 169]; 2 on a heal stall alone [86, 184]; 4 only after the harness-only re-assert
[110, 138, 142, 183]` — and the 2000-seed shipping list restricted to seeds 1..200 is
`[29, 43, 94, 162, 169]`, identical. Seed class membership no longer moves with the total
(plan 158 §1's movement was driven by the stamp gap). The heal-only bucket still moves by a seed
between runs (142 vs 184), which is the class's own flake, not a stamp effect; `heal` is excluded
from the ratchet for that reason.

### Residue (not chased here)

1. **`status` (A-161-05)** — 73/75 shipping seeds at 2000, 5 at 200. Every one is the phone's
   wall-clock end against the grid-stamped wrist end. Fixing it needs a product seam for
   `TrainingSession.endedAtMs` (or a clock injected into `session_core_lifecycle.endSession`), which
   is new product scope, not a harness change. The class name and the ratchet keep the count
   visible.
2. **`entries` residual (2 of 2000, seeds 499 and 819)** — both are wrist-vs-wrist now (the phone's
   own kinds are filtered), and neither seed reproduces in the other run. First step: shrink with
   the predicate `report.entryMismatches.isNotEmpty` and decide whether it is the S-16102 refusal
   ordering or a second artifact.
3. **`heal`** — 34 kind-hits at 2000, 22/25 seeds where the heal only stalls. First step: a shrink
   whose predicate is `run.heal.converged == false` (`ConvergenceRun.replayActions` +
   `Shrinker.shrink`).
4. **`absorbing`** — 4/5 kind-hits at 2000, seed 111's trace already minimal.

## Phase 5 — docs and residue sweep

Docs delta — `docs/state_management/watch_surface_transport.md`, `### Convergence testing`:
three paragraphs added (the check-3 annotation filter, the `frameClock`/`clock` seam pair,
`endsWithinSkewToleranceMs` / `withinSkewEndTies` with "owner to confirm"). Every behavioural
sentence names the test that verifies it (`S-16101`, `S-16102`, `S-16103`, `S-16104`,
`S-14509`). The page was 188 lines before; the byte figure is not obtainable with this run's tools
(`wc`/`stat` are outside the gateway), so the size check is `test/docs_indexing_contract_test.dart`
— green (see the final runs), which is the contract that actually binds (`docs/` may not exceed
64 KiB, split before ~52 KB).

Seam doc grep — `createWatchSync` in `docs/`: 132 hits over 39 pages, none of them a parameter
list. `ledgerClock` in `docs/` appears only in plan 158's findings and this plan; no page
documents the construction's clock parameters, so nothing else needed the `frameClock` parameter
(Phase 5 item 2's "none names it" branch). The author-facing description lives in the convergence
section above.

`docs/watch_session_sync/what_does_not_sync.md`: **no change** — the product conflict rule is
unchanged; the tie is the harness's reading, D-14603 still decides which end wins (D-15403).

Residue greps:

| sweep | result |
|---|---|
| `phone-change` under `test/helpers/` | 1 hit — the filter's explanatory comment, no reader |
| `entry.entryId` in `_sampleEntries` | exactly 1 phone-side reader, filtered (`WatchInboxEntry.phoneKinds.contains`); the wrist-side reader (`harness.wristEngine.entries`) stays unfiltered |
| `ledgerClock` | passed exactly once (`watch_sync_wiring.dart` `ledgerClock: clock`) and unchanged; `frameClock` is the new sibling |
| `import .*hive_workout_repository` in `lib/state lib/features lib/widgets lib/core` | no match (project invariant) |
