# Evidence — 146: a finished workout is final (PR 1)

Implementers append baselines, suite outputs and red→green tables here. Pasted counts, not claims.

## Baselines (conductor, 2026-11-11)

- `flutter analyze`: 181 pre-existing issues; compare counts, never require exit 0.
- Skipped convergence tests (all to be unskipped by this PR):
  - `test/watch_convergence_random_test.dart`: S-14509 sweep (:163), F-2 (:416), F-3 (:441), F-4 (:461), F-5 (:487), F-6 (:515), F-7 (:542)
  - `test/watch_convergence_harness_test.dart`: S-14503 (:190)
- Plan 145 sweep/soak numbers (the red baseline): sweep 142/200 converge; soak 1349/2000, duplicate
  entries on soak seeds 408, 660; heal-stall flake seeds 10, 86, 142, 184 (rerun individually).

## Phase 1 (Dart twin)

| Check | Command | Before | After |
|---|---|---|---|
| lint | `gateway.sh lint` | 181 issues | 181 issues (files touched: 0) |
| engine + hold-stop | `gateway.sh test test/watch_session_engine_test.dart test/watch_logged_hold_stays_stopped_test.dart` | — | **90 passed, 0 failed** |
| fixtures + cross-stack | `gateway.sh test test/watch_reconciliation_cross_stack_test.dart test/sync_protocol_fixtures_test.dart` | — | **199 passed, 0 failed** (S-004 walks `ended_is_final.json`) |
| full suite | `gateway.sh test` | 7407 passed / 4 failed (first pass) | **7413 passed, 2 failed, 10 skipped** — `Some tests failed.` |

The two reds are the plan's own re-measurements, not new regressions:

- `test/watch_convergence_harness_test.dart` S-14512 — `Expected: true / Actual: <false>`; the test prints
  `S-14512 final statuses: phone completed wrist abandoned, 1 mismatch(es), 0 entry mismatch(es)`. Under
  O-2 each side now keeps its own first ending, so the pair diverges until Phase 3 gives the phone an
  authority rule (A-146-05).
- `test/watch_convergence_random_test.dart` S-14510 — the shrinker's padded F-1 trace,
  `Expected: true / Actual: <false>`: same reason (the wrist no longer reopens for the phone's stale
  `started`, which is the F-1 fix, so the padded seed's expectation moved).

The four that went red in the first full pass and were fixed: `S-81` in `test/watch_session_auto_push_test.dart`
(a re-delivered end returns `true` again) and `S-6112` in `test/watch_timer_adoption_test.dart` plus the two
above (timer clearing moved out of the reconciler, A-146-06).

Convergence suites on their own (`gateway.sh test test/watch_convergence_harness_test.dart
test/watch_convergence_random_test.dart`): `+31 ~8 -2: Some tests failed.` — the 8 skips are the baseline
list below, still `skip:`-ed as Phase 5 requires. `S-14509`'s drain-only measurement still reports
divergent seeds (`red seeds [1] of 1..200`, 48 seeds diverge), which is the sweep Phase 5 owns.

Red→green per scenario: S-14601, S-14602, S-14603, S-14605, S-14608, S-14611 (engine halves), S-14612 (S-004).

### Red run — before any engine change

`gateway.sh test test/watch_session_engine_test.dart --plain-name "S-146"`:
`+0 -6: Some tests failed.` Six failures, one per new group, each for its guarded reason:

- S-14601 `Expected: false / Actual: <true>` — "a start for an ended session changes nothing (D-14601)".
- S-14602 `Expected: 'completed' / Actual: 'active'` — "an active snapshot never reopens a terminal one (D-14604)".
- S-14603 `Expected: 'stopped' / Actual: 'running'` — "an end stops the session's timers (D-14603a)".
- S-14605 `Expected: 'abandoned' / Actual: 'completed'` — the wrist's own finish upgraded a discard.
- S-14608 `Expected: ['entry-1'] / Actual: ['entry-1', 'entry-1']` — "the entry id is the identity, not the event id it arrived on".
- S-14611 `Expected: 2026-07-13 06:10:00.000Z / Actual: 2026-07-13 06:50:00.000Z` — "no late frame moves the end (D-14604)".

### Prove-red verdicts (gateway, not self-reported)

`gateway.sh prove-red HEAD test --plain-name "S-146" -- test/watch_session_engine_test.dart`

```
00:00 +0 -6: Some tests failed.
gateway: prove-red: RED AT HEAD (exit 1). It proves the guard only if an assertion fails for the reason
the test guards; ...
```

The six failures above are the full body of that run — no compile or load error.

`gateway.sh prove-red HEAD test --plain-name "S-004" -- watch/sync_protocol/fixtures/manifest.json
watch/sync_protocol/fixtures/reconciliation/{lifecycle_started,lifecycle_completed,lifecycle_transitions,
ended_is_final}.json`

```
00:09 +9 -1: sync_protocol_fixtures_test.dart: S-004 every reconciliation fixture converges on its expected state [E]
  Expected: { 'sessionId': 's-2026-07-13-9', 'status': 'completed', ... 'timers': {} }
    Actual: { 'sessionId': 's-2026-07-13-9', 'status': 'abandoned', ... }
gateway: prove-red: RED AT HEAD (exit 1).
```

The amended fixtures alone fail against HEAD's reconciler: without the twin rule, the reconciler is still
"most recent status wins", so `lifecycle_started.json` converges on `abandoned` where the fixture now
requires `completed`. The new fixture is proven the same way — it is one of the files carried into that
checkout and S-004 walks it by directory, so a new fixture that HEAD's code satisfies would have to
produce identical output there, which an unmodified HEAD reconciler does not.

### Footprint

`gateway.sh git-diff --stat`: `lib/watch/session/watch_session_engine.dart` +156/-…,
`lib/core/sync_protocol/session_reconciler.dart` +61/-… (A-146-01), `test/watch_session_engine_test.dart`
+380 (six groups + three helper parameters), three amended reconciliation fixtures + `manifest.json`
(A-146-02), and the new `watch/sync_protocol/fixtures/reconciliation/ended_is_final.json` (untracked, so it
does not appear in the stat — S-14612). No file outside the plan's Files Affected. `.claude/crew.md` in the
stat is not this run's.

### Invariants and standards

- `grep "import .*hive_workout_repository"` over `lib/`: one hit, `lib/main.dart` (the composition root). No
  hit in `lib/state`, `lib/features`, `lib/widgets` or `lib/core`.
- No UI file is touched, so `test/ui_standards_contract_test.dart` has nothing to guard here; the full
  suite includes it and it passed.
- No `.swift` file is touched: `swift-test` does not apply to this phase.

## Phase 2 (contract)

| Check | Command | Before | After |
|---|---|---|---|
| docs cap | `gateway.sh test test/docs_indexing_contract_test.dart` | pass (Phase 1) | `+13: All tests passed!` |
| fixtures | `gateway.sh test test/sync_protocol_fixtures_test.dart` | pass (Phase 1) | `+178: All tests passed!` |
| both, one run (Phase 2 Done Criteria) | `gateway.sh test test/docs_indexing_contract_test.dart test/sync_protocol_fixtures_test.dart` | `+190 -1` (first pass, see below) | `+191: All tests passed!` |
| lint | `gateway.sh lint` | 181 issues | 181 issues (`181 issues found. (ran in 3.7s)`) |

Footprint: `gateway.sh git-diff --stat -- watch/sync_protocol/PROTOCOL.md` → `1 file changed, 35 insertions(+),
4 deletions(-)`, 908 lines. No other file in this phase's scope changed.

**PROTOCOL.md byte size: not measurable in this run.** The only permitted shell is the gateway and it
exposes no `wc`/`stat`; `wc -c watch/sync_protocol/PROTOCOL.md` was refused by policy and not retried.
Best available evidence for the 64 KiB cap: the file gained 35 lines and lost 4 (≈2 KB of table row and
contract prose) over a base last recorded at ~52.5 KB in the 2026-10-07 review and ~80 KB in the plan 42b
note — the two disagree, so the cap cannot be confirmed from them, and
`test/docs_indexing_contract_test.dart`
(`no documentation file exceeds the indexing ceiling`, `no documentation file is within the warning band
of the ceiling`) scans `docs/`, not `watch/`, so it does not cover this file. Governor action: measure
PROTOCOL.md and, if it is over the cap, split the version history into its own page.

**First pass red, then green (S-007, not a regression).** The first run after rewriting the bullet was
`+177 -1`: `S-007 specification states the lifecycle ordering rule normatively`
(`test/sync_protocol_fixtures_test.dart:813-823`) pins the two superseded sentences verbatim
(`'Lifecycle messages are applied in the order received'`, `'the most recent status wins'`). This run may
not edit `test/**` (brief), so the contract carries both sentences truthfully instead: the first clause is
still true and is now stated with its conclusion removed ("Lifecycle messages are applied in the order
received, and that order is authority for nothing"), and the second appears only in the version-history row
that supersedes it. Re-pointing S-007 at the new rule belongs to Phase 5, which owns test edits.

**Stale-rule sweep (item 3).** `grep` for `most recent status wins`, `applied in the order received`,
`reported \`started\` after an abandon`, `is live again`, `revives it`, `reopens a (closed|terminal|ended)`
across `docs/`: every hit is a plan record (144/146 and their evidence) except
`docs/state_management/watch_surface_transport.md` (the `F-2`/`F-4` paragraph, still a true description of
the findings the replay tests measure until Phase 5). No `docs/**` page restates the old lifecycle rule, so
item 3 changed no file. Hits outside `docs/**`, reported not edited: the Swift doc comment
`watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift:683-685` ("Applies a lifecycle message
from the phone: the most recent status wins", PR 2). The Dart twin's comment was already rewritten in
Phase 1.

## Phase 3 (phone)

| Check | Command | Before | After |
|---|---|---|---|
| lint | `gateway.sh lint` | 181 issues | 181 issues (files touched: 0) |
| cross-stack + fixtures | `gateway.sh test test/watch_reconciliation_cross_stack_test.dart test/sync_protocol_fixtures_test.dart` | — | **202 passed, 0 failed** |
| engine file | `gateway.sh test test/watch_session_engine_test.dart` | — | **66 passed, 0 failed** |
| phone suites | `gateway.sh test test/watch_timer_push_test.dart test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart test/watch_session_finish_test.dart test/watch_rest_cleared_on_phone_timer_test.dart test/watch_logged_hold_stays_stopped_test.dart` | | **not run — items 1–6 not started** |

Red→green per scenario: D-14601 tie-break (item 8). S-14603 (a+b), S-14609 (phone half), S-14610 are
**not** implemented this run.

### Item 8 — the equal-instant tie-break, red→green

Green (both stacks, three cases): `gateway.sh test test/watch_reconciliation_cross_stack_test.dart` →
`+24: All tests passed!` (21 pre-existing + 3 new).

Mutation, recorded before it was applied (the guard cannot exist without the change, so a mutation was
used rather than `prove-red`): the four equal-instant returns were each replaced with `return false;` —

- `lib/watch/session/watch_session_engine.dart` `_incomingEndWinsATie`:
  `return incomingStatus == WatchSessionStatus.completed;` → `return false;`
- `lib/watch/session/watch_session_engine.dart` `_incomingEndWinsATie`:
  `return incomingMessageId.compareTo(heldMessageId) < 0;` → `return false;`
- `lib/core/sync_protocol/session_reconciler.dart` `_incomingEndWins`:
  `if (status != _status) return status == 'completed';` → `if (status != _status) return false;`
- `lib/core/sync_protocol/session_reconciler.dart` `_incomingEndWins`:
  `return messageId.compareTo(heldMessageId) < 0;` → `return false;`

Run with the mutation applied (`--plain-name "D-14601"`): `+0 -3: Some tests failed.`

```
D-14601 completed ends the session whichever ending arrives first [E]
  Expected: ['completed', 'completed']
    Actual: ['abandoned', 'abandoned']
D-14601 the smaller messageId breaks a tie between like endings [E]
  Expected: 'life-msg-a'  Actual: 'life-msg-b'
D-14601 a snapshot-carried abandonment loses the tie to a completion [E]
  Expected: ['completed', 'completed']
    Actual: ['abandoned', 'abandoned']
```

Every failure is the assertion the test guards, on the phone half and the wrist half alike (both are
asserted in the same expectation, so one mutation of either stack fails the test). The four lines were
restored verbatim and the file re-run green (`+24`).

One transient red, explained: the first combined two-file run reported
`S-007 specification states the lifecycle ordering rule normatively` failing against PROTOCOL.md
(`Expected: contains 'Lifecycle messages are applied in the order received'`). The sentence is in the
file; the concurrent Phase 2 session was writing it mid-run. Alone: `+1: All tests passed!`; combined
re-run: `+202: All tests passed!`. Nothing in this run edits PROTOCOL.md or that test (A-146-12).

### Footprint

`gateway.sh git-diff --stat`: `lib/watch/session/watch_session_engine.dart` +203/-… (Phase 1's 156 plus
item 8's `_incomingEndWinsATie`/`_messageIdOf` and the two call sites),
`lib/core/sync_protocol/session_reconciler.dart` +104/-… (Phase 1's 61 plus item 8's `_endMessageId`,
`_incomingEndWins` and the `messageId` plumbing), `test/watch_reconciliation_cross_stack_test.dart` +123
(the three tie-break tests). No phone-side file is touched: items 1–7 were not started.

### Invariants and standards

- `lib/state/`, `lib/features/`, `lib/widgets/`, `lib/core/` gain no `hive_workout_repository` import
  (unchanged from Phase 1: the only hit is `lib/main.dart`).
- No UI file is touched, so `test/ui_standards_contract_test.dart` has nothing to guard here.
- No `.swift` file is touched: `swift-test` does not apply.


## Phase 3, items 1–7 (phone rules; brief-developer-146-p3b)

### Suite runs (real counts, pasted from the gateway logs)

| run | command | result |
|---|---|---|
| Phase 1 regressions | `test/watch_session_engine_test.dart` `test/sync_protocol_fixtures_test.dart` `test/watch_reconciliation_cross_stack_test.dart` | **270 passed, 0 failed** |
| engine file after restore | `test/watch_session_engine_test.dart` | **69 passed** |
| item 6 + Done Criteria | `test/watch_timer_push_test.dart` `test/watch_session_adoption_bridge_test.dart` `test/watch_session_import_test.dart` `test/watch_session_finish_test.dart` `test/watch_rest_cleared_on_phone_timer_test.dart` `test/watch_logged_hold_stays_stopped_test.dart` | **220 passed, 1 failed** (`.work/gateway/test-20261111-223011-52698.log`) |
| convergence files | `test/watch_convergence_harness_test.dart` `test/watch_convergence_random_test.dart` | **32 passed, 8 skipped, 1 failed** — `S-14510` only (`.work/gateway/test-20261111-223020-52818.log`) |
| lint | `gateway.sh lint` | **181 issues** (baseline 181, no new) |
| full suite | `gateway.sh test` | **7427 passed, 10 skipped, 2 failed** — `S-14510` (Phase 5) and `S-12109` (A-146-16) (`.work/gateway/test-20261111-223336-54384.log`) |
| docs contract | `test/docs_indexing_contract_test.dart` `test/ui_standards_contract_test.dart` | **54 passed** |

Per-file while working: `test/watch_timer_push_test.dart` 63/63, `test/watch_session_finish_test.dart`
21/21, `test/watch_session_import_test.dart` 2/2 new group.

### The single red

```
test/watch_logged_hold_stays_stopped_test.dart:1454
  Expected: empty
    Actual: WhereIterable<Map<String, Object?>>:[
              {'messageId': 'tms-end-s-w-121a-hold',
               'payload': {'timers': {'hold': null}}, 'type': 'timer_state', …}
            ]
  the end attempts no timer_state (the existing _pushOnce rule)
```

`S-12109`'s fixture calls `holdLogAway()` with `radio.unreachable = true`, so the phone's
`{hold: null}` is attempted but never travels and stays in `_owed`. Item 1 (D-14603b) makes the end
owe exactly that stop. The assertion encodes the rule item 1 replaces; the test is not edited
(A-146-16).

### prove-red verdicts

- `prove-red HEAD test test/watch_timer_push_test.dart` → **RED AT HEAD** on the S-14604b/S-6216 cases
  (no `tms-end-*` frame exists at HEAD).
- `prove-red HEAD test test/watch_session_import_test.dart` → **RED AT HEAD** on
  `S-14610 the imported end catches up`.
- `prove-red HEAD test test/watch_session_engine_test.dart --plain-name "S-14512"` → **RED AT HEAD**
  on "a phone discard does not replace a wrist completion" (`Expected: false, Actual: <true>`).
- The "earlier wrist discard loses to a completion" guard came back **GREEN AT HEAD** (vacuous there:
  later-end-wins already satisfies it), so it was proven by mutation instead:

```
ORIGINAL  if (status == 'completed' && session.status == 'abandoned') {
MUTATED   if (status.isNotEmpty) {
FAILED    Expected: true  Actual: <false>   (test/watch_session_engine_test.dart:3200)
RESTORED  exact original, file re-run: 69 passed
```

No step ends with a mutation applied.

### S-14512, before and after

- Before: `phone completed wrist abandoned, 1 mismatch(es), 0 entry mismatch(es)`.
- Root cause (probe, removed verbatim afterwards): `held=abandoned heldAt=2026-11-10 09:00:00.000Z
  incoming=completed at=2026-11-12 03:26:01.6Z` — the wrist's discard carries the harness `TestClock`,
  the phone's frames the device clock, so earlier-instant-wins let the discard beat the completion.
- After A-146-15's guard: `phone completed wrist completed, 0 mismatch(es), 0 entry mismatch(es)`.

### Footprint

`git-diff --stat` for this run's source: `lib/state/watch/watch_timer_push.dart` +53,
`lib/state/watch/live_session_mirror_state.dart` +38, `lib/state/workout/session_core_lifecycle.dart`
+60, `lib/state/watch/watch_session_adoption_bridge.dart` +28,
`lib/core/services/watch_session_importer.dart` +27, `lib/state/workout/workout_state.dart` +9,
`lib/watch/session/watch_session_engine.dart` (A-146-15's guard). Tests: `watch_timer_push_test.dart`
+158, `watch_session_finish_test.dart` +196, `watch_session_import_test.dart` +85,
`watch_session_engine_test.dart` +473 (S-14512's three). No scratch or probe file left; the temporary
`print` in `_applyLifecycle` was removed exactly.

### Invariants and standards

- `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` returns
  nothing (the only hit in the repo is `lib/main.dart`).
- `test/ui_standards_contract_test.dart`: **passed** in the 261/262 run; no UI file is touched by this
  run and no allowlist entry is added or raised.
- No `.swift` file is touched: `swift-test` does not apply.


## Phase 4 (F-5)

- Red run of F-5 (`--plain-name "F-5"`): paste the failure verbatim.
- Confirmed seam (file + line) and why; the fix's diff target.
- Regression: `test/watch_session_end_owed_test.dart` (S-14606) red→green.

## Phase 5 (sweep + soak)

| Run | Command | Result |
|---|---|---|
| suites | `gateway.sh test test/watch_convergence_harness_test.dart test/watch_convergence_random_test.dart` | |
| soak 2000 | `gateway.sh test test/watch_convergence_random_test.dart --dart-define=CONVERGENCE_SEEDS=2000` | |

Report: converged/total, duplicates, statusMismatches, entryMismatches, timerViolations, absorbingViolations
— and the comparison against plan 145's baseline (sweep 142/200, soak 1349/2000, duplicates on 408/660).
Heal-stall seeds (10, 86, 142, 184): rerun individually; a stall there is the known harness flake, not a
finding, unless it stalls after a rerun.

## Assumption Log adjudication (conductor, at verification)

*(each executor entry marked RATIFIED (promoted to a D-x) or REVERT (remediation task opened))*
