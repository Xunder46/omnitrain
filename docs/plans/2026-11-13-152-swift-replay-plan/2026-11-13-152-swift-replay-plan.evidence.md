# Plan 152 — evidence

Baselines, run outputs and red→green tables. Dated `2026-11-13` (session clock).

## Phases 1–2 — the recorder and the corpus

### Lint

| Run | Issues | Note |
|---|---|---|
| Baseline (plan) | 181 | repo-wide, exits non-zero on info notices |
| Recorder + corpus landed | 187 | 6 new, all in files this change touched |
| After fixes (import, private-type ignore, null-aware elements) | 181 | back to baseline |

### The focused suite

`gateway.sh test test/watch_replay_corpus_test.dart test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart`

```
00:26 +100 ~2 -1: Some tests failed.
```

The one failure is S-15204's "every file is in the manifest" assertion naming
`seed-1814.json` — the retired recording described in A-152-06, which the governor deletes. Every
other assertion passes, including S-15201, S-15202, S-15203, S-15207, the two convergence files
(unchanged behaviour with the recorder off), the docs contract and the UI standards scan. Before the
retirement (17 sources) the same command was `00:0x +101 ~2: All tests passed!`.

(`~2` are the pre-existing skips in the convergence files.)

### The corpus (16 sources, regeneration run)

| File | Bytes | Tags |
|---|---|---|
| `trace-s14501.json` | 4512 | entry, frame-prefix |
| `trace-s14503.json` | 2033 | frame-prefix |
| `trace-f2.json` | 3623 | — |
| `trace-f3.json` | 3241 | timer, frame-prefix |
| `trace-f4.json` | 3067 | multi-session, frame-prefix |
| `trace-f5.json` | 2946 | multi-session |
| `trace-f6.json` | 3402 | multi-session, entry, frame-prefix |
| `trace-f7.json` | 7458 | multi-session, entry, refused-queued |
| `trace-a1.json` | 4317 | multi-session, refused-queued |
| `trace-a2.json` | 3201 | multi-session, refused-queued |
| `seed-1.json` | 3601 | kill, entry, refused-queued, frame-prefix |
| `seed-7.json` | 4815 | multi-session, timer, entry |
| `seed-50.json` | 4095 | multi-session, entry, refused-queued, frame-prefix |
| `seed-111.json` | 6649 | multi-session, entry, refused-queued |
| `seed-408.json` | 10528 | kill, multi-session, timer, entry, refused-queued |
| `seed-857.json` | 7877 | kill, multi-session, entry, refused-queued |

Largest file 10 528 B (limit 32 768); total ≈ 74 KB (limit 300 KB). `manifest.json` lists the same
16 sources in order.

### S-15202 replay verdicts (fresh Dart wrist, checked-in files)

```
trace-s14501 sessions=1 events=15
trace-s14503 sessions=1 events=6
trace-f2      sessions=1 events=11
trace-f3      sessions=1 events=9
trace-f4      sessions=2 events=8
trace-f5      sessions=2 events=7
trace-f6      sessions=2 events=8
trace-f7      sessions=3 events=19
trace-a1      sessions=2 events=14
trace-a2      sessions=2 events=7
seed-1        sessions=1 events=14
seed-7        sessions=3 events=11
seed-50       sessions=2 events=18
seed-111      sessions=4 events=24
seed-408      sessions=4 events=30
seed-857      sessions=3 events=27
```

### Red → green

The corpus test is a new file, so `prove-red HEAD` cannot compile it; every guard below is proved by
a mutation instead (original line recorded, changed, seen red, restored exactly, re-run green).

| Guard | Mutation | Red output | Restored |
|---|---|---|---|
| S-15203 (canonicalizer) | `_canonicalString`'s id branch returns `value` instead of the `x-<n>` alias | `Expected: empty / Actual: ['events[0].envelope.messageId = 14549389-…', 'events[0].envelope.sessionId = session-1794584934010', …]` — 20+ phone-minted values from `trace-s14501` | yes, green |
| S-15203 (positive control) | none — the test already records `trace-s14501` with `canonicalize: false` and asserts the scan *finds* values, so the scan sees what it guards | — | — |
| S-15207 (freshness) | `trace-f2.json`, one byte: `"revision":1` → `"revision":2` in the first snapshot | `Expected: empty / Actual: ['trace-f2.json']` | yes, green |
| S-15201 (byte identity) | covered by S-15203's mutation: the record path is the same code | — | — |

### Guards that needed a design change, and why

- **Stamp aliases rank distinct off-grid instants in value order** (A-152-04). Three attempts failed
  before this: appearance order replayed `trace-a2`'s `abandoned` session as `active`; occurrence
  counters re-aliased ids between passes and diverged on `trace-a2`/`seed-857`; value order over a
  first-appearance table made the whole run diverge on the phone's two stamp classes.
- **S-15201 and S-15207 mask alias-band instants** (A-152-05): the phone mints stamps from the real
  clock, so the number of distinct instants a run mints is not stable across processes.
- **`seed-1814` is not in the corpus** (A-152-06): its fresh recording was 701 serialised lines
  against the checked-in 541, diverging where a session's `entries` were empty on one side and
  populated on the other.

### Footprint

`gateway.sh git-diff --stat` over tracked files:

```
test/helpers/watch_pair_harness.dart | 122 +++++++++++++++++++++++++++++++++--
```

Additive, every hook behind `recordReplay` (default false). New, untracked:
`test/helpers/watch_replay_recorder.dart`, `test/watch_replay_corpus_test.dart`,
`watch/sync_protocol/fixtures/replay/` (17 files — 16 recordings + the manifest, plus the orphan
`seed-1814.json` listed for deletion in the plan's `## Feedback`).

No `lib/`, `watch/watchos/Sources/` or `ios/` file changed.
