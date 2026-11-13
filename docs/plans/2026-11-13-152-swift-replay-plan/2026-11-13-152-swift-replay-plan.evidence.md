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

## Phases 3–4 — the Swift replay, the run, the docs

### What the Swift half does

`watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift` (new, 628 lines) loads every
recording through `Fixtures.json("fixtures/replay/<file>")` and replays it into a fresh
`WatchSessionEngine` over an `InMemoryWatchSessionStore`: `TestClock` set from the event's
`clockMs`, counter id and session factories (`rec-<n>`, `s-w-<n>`), `frame` → `applyMessage`
(a thrown `WatchEmissionRejected` is counted, not fatal — the Dart replayer swallows the same
refusal), `action` → `createSession`/`appendObservation`/`finishSession`/`abandonSession`/
`startTimer` behind the same no-op guards `HarnessRunner.perform` applies, `kill` → a new engine
over the same store plus `restore()`. The end state is read back from `store.readAll()` through
D-15205's rule (newest session row per id for the status, stored observations for the entry set,
newest row per kind for the timers, `engine.session` for `current`), with A-152a's session-end ids
excluded, and compared with the recording's `expected` block, bucketed into the manifest's classes.

Implementation names differ from the plan's shorthand: the loader is `corpus()`/`recording(named:)`
(not `loadCorpus`), the comparator is `outcome(_:expected:)` (not `compare(_:expected:recording:)`),
the reader is `readSummary(_:current:excludingSessionEnd:)`. Same items, same tests.

### The sweep: every recording, no divergence

`testS15208EveryRecordingReplaysWithNamedOutcome`, whole corpus, unmutated engine:

```
trace-s14501 classes=
trace-s14503 classes=
trace-f2 classes=
trace-f3 classes=
trace-f4 classes=
trace-f5 classes=
trace-f6 classes=
trace-f7 classes=
trace-a1 classes=
trace-a2 classes=
seed-1 classes=
seed-7 classes=
seed-50 classes=
seed-111 classes=
seed-408 classes=
seed-857 classes=
classes: none
```

16/16 identical to the Dart `expected` summary. No `refused=` annotation printed on any line, so no
frame was rejected on either side. Consequences for the plan's scenarios:

- **S-15205** (`trace-s14501`, no-fault story): green — one session, status `completed`, three
  entries, no timer, on both engines.
- **S-15206** (`trace-f2`): the recording does **not** carry F-2's absorbing signature, because the
  corpus is recorded post-146/146c. Both engines hold the session `completed`; the test asserts that
  shared end rather than a revival (A-152-10). A Swift revival would show as `status`.
- **S-15209** (A1/A2/A3): `trace-a1` and `trace-a2` replay clean on Swift — plan 151's ended-session
  fix is mirrored, so neither A1's absorbing shape nor A2's entry loss reproduces. A3 (the timer
  stop at a lifecycle end, A-152-01) is `trace-f3`, and its `timers` class is empty too.
- **Findings: none.** The `findings` table in the test file is empty because no recording diverged;
  it exists so the next divergence is recorded as data (name → class set) that goes red when the
  engine aligns (A-152-08).

### Sensitivity: the guards were proved red, not assumed

The comparison cannot be green because it looks at nothing: both mutations below are one-line edits,
restored byte-identically afterwards, and every run is pasted from the gateway.

**Mutation A — the applier drops frames** (records that the sweep reads real store rows):

```
-                try await rig.engine.applyMessage(envelope)
+                _ = envelope // MUTANT-A: frames not applied
```

```
testS15205TheNoFaultStoryReplaysGreen: error: XCTAssertTrue failed - trace-s14501 diverges
  [current,status]: current: Swift nil vs Dart x-2
testS15208…: trace-s14501 diverges [current,status] … trace-f6 diverges [status]: x-2: Swift
  holds no session … seed-408 diverges [current,status,timers] … seed-857 diverges
  [entries,status]
Executed 4 tests, with 19 failures (0 unexpected)
```

Restored → `Executed 4 tests, with 0 failures`. All four classes (`current`, `status`, `entries`,
`timers`) were produced by real store differences, so each is reachable.

**Mutation B — the session-end filter off** (S-15210's guard, red naming A-152a):

```
-        excludingSessionEnd: Bool = true
+        excludingSessionEnd: Bool = false // MUTANT-B
```

```
testS15205TheNoFaultStoryReplaysGreen: trace-s14501 diverges [entries]: x-2: entries Swift
  [end-x-2,w-entry-1,…] vs Dart [w-entry-1,…] (extra on Swift ["end-x-2"])
testS15206F2ReproducesItsFinding: trace-f2 diverges [entries]: s-w-1: entries Swift
  [end-s-w-1] vs Dart []
testS15210TheAllowlistIsStructural: XCTAssertEqual failed (filtered vs result.summary)
classes: entries=16
Executed 4 tests, with 19 failures (0 unexpected)
```

Restored → 4 tests, 0 failures, `classes: none`. In-test positive control (no mutation needed):
`testS15210TheAllowlistIsStructural` reads the same store with the filter off and prints
`S-15210 filter-off classes=entries diffs=["x-2: entries Swift [end-x-2,w-entry-1,w-entry-2,x-7]
vs Dart [w-entry-1,w-entry-2,x-7] … extra on Swift [\"end-x-2\"]"]`.

### Suites and lint

| Check | Command | Result |
|---|---|---|
| Swift, focused | `gateway.sh swift-test --filter WatchReplayTests` | `Executed 4 tests, with 0 failures` (0.066 s) |
| Swift, package | `gateway.sh swift-test` | `Executed 1412 tests, with 0 failures (0 unexpected) in 11.810 s` — 1408 before, +4 new |
| Dart, full | `gateway.sh test` | `04:59 +7486 ~6: All tests passed!` (exit 0, 5 min 17 s wall) |
| Docs + UI contracts | `gateway.sh test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` | `+54: All tests passed!` |
| Lint | `gateway.sh lint` | `181 issues found` — the plan's baseline exactly (all `test/` notices) |

The Dart suite's plan-146 close baseline was `+7441 ~2`; this tree reads `+7486 ~6` because other
work landed since (this plan's 7 corpus tests plus the docs/standards tests other PRs added).
No existing test was edited or weakened; nothing went red.

### Docs

`docs/state_management/watch_surface_transport.md`: new `### Differential Swift replay` subsection
directly after `### Convergence testing` — 197 → 236 lines, and the docs contract's ceiling and
warning-band assertions pass. It states what the corpus is, the regeneration define, how to run and
read the Swift sweep, A-152a's session-end exclusion (naming
`testS15210TheAllowlistIsStructural`), and D-15211's cannot-catch list. Every behavioural sentence
names a test that exists: `S-15207 the corpus is fresh: every file matches a fresh recording`,
`testS15205TheNoFaultStoryReplaysGreen`, `testS15206F2ReproducesItsFinding`,
`testS15208EveryRecordingReplaysWithNamedOutcome`, `testS15210TheAllowlistIsStructural`.

### Footprint

`gateway.sh git-diff --stat` over tracked files after Phases 3–4:

```
.claude/crew.md                                    |  2 +      (not this plan's)
.../2026-11-13-152-swift-replay-plan.md            | 22 +++++++---
docs/state_management/watch_surface_transport.md   | 49 ++++++++++++++++++++++
```

Plus this evidence file and the new untracked
`watch/watchos/Tests/WatchSessionEngineTests/WatchReplayTests.swift`. That is the union of Phases 3
and 4's Predicted Files (`WatchReplayTests.swift`, the evidence file, the docs page; the manifest's
`classes` needed no addition because no new class surfaced). Nothing under `lib/`, `ios/`,
`watch/sync_protocol/` or `watch/watchos/Sources/` changed. `.claude/crew.md` and the untracked
`test/stats_gallery_render_test.dart` predate this run and are not touched.

