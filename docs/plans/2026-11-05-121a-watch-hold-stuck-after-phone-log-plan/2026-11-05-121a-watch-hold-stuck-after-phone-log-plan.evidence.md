# 121a evidence

Implementers write here: baselines, the D-9 gate table, red→green tables, the residue grep, details behind Assumption Log entries. Keep the plan free of output.

## Baseline (Phase 0, before any change)

- `flutter analyze` on the new test file: 0 issues (full-repo count not taken; Phase 1 compares production-file analysis).
- Base 22376d7e81ff98ecf6ba72e4f76a992390185d22; shared tree.

## D-9 gate table (Phase 0, unchanged code)

Run in isolation per test (`--name "(S-id)"`); in one whole-file run the RED tests leave state behind that also fails S-12110 (7 passed, 16 failed, 23 total). Full-file run after the harness fixes: `+7 -16`.

| S-id | Plan's "Today" | Observed | Failing line / reason |
|---|---|---|---|
| S-12101 | RED (a)(b)(c) | RED | (a) `Expected: not contains 'hold'  Actual: ['hold']` (projection); (c) shown by S-12102/S-12113: wrist `running` after the queued snapshot |
| S-12102 | RED | RED | `Expected: 'stopped' Actual: 'running'` after the late queued snapshot |
| S-12103a | RED | RED | reinstalled watch runs the logged hold (`Expected: true Actual: false`) |
| S-12103b | RED | RED | the answer to a snapshot request names the hold |
| S-12104 | RED | RED | snapshot timers carry extra key `hold` |
| S-12105 | RED | RED | names `hold` |
| S-12105b | RED | RED | names `rest` |
| S-12106 | GREEN | GREEN | |
| S-12107 | RED | RED | no `{hold: null}` after restart (length 0) |
| S-12108a-g | a,b,c,e,f GREEN; d,g RED | a,b,c,e,f GREEN; d,g RED | d,g: clears length 0 |
| S-12109 | RED (snapshot assertion) | RED | projection names `hold` |
| S-12110 | GREEN (gate) | GREEN | |
| S-12111 | GREEN (gate) | GREEN | |
| S-12112 | RED | RED | names `hold` before flush |
| S-12113 | record | RED today | wrist hold still `running` after every phone frame |
| S-12114 | RED | RED | snapshot names `hold` |
| S-12115 | RED | RED | projection names `hold` of a wrist-stopped copy |

Verdict: H1 CONFIRMED (S-12101 a, S-12103a RED; S-12110, S-12111 GREEN).

## Phase 1 red→green

Before the fix (isolated runs): S-12101, S-12102, S-12103a/b, S-12104, S-12105, S-12105b, S-12109, S-12112, S-12114, S-12115, S-12107, S-12108d, S-12108g RED (table above). After: `flutter test test/watch_logged_hold_stays_stopped_test.dart` -> `+24: All tests passed!`.
Dependents (each its own run): watch_timer_push_test +61 (S-6329 forced the one-sided match, see Assumption Log), watch_timer_adoption +23, watch_session_auto_push +62, watch_session_projection +60, live_mirroring +54, watch_reconciliation_cross_stack +20, watch_transport +65, all passed. `flutter analyze` on the three touched files: No issues found.
Docs: `flutter test test/docs_indexing_contract_test.dart test/ui_standards_contract_test.dart` -> `+54: All tests passed!` (before the last wording edit; docs_indexing re-run +13 passed).

## Residue sweep (D-11)

`grep -rn deliveredTimers lib test` -> empty. `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` -> empty.

## Mutations (governor)

Run in an isolated copy of the project (the tree is shared); each mutant ran `watch_logged_hold_stays_stopped_test.dart` + `watch_timer_push_test.dart`.

| # | Result | Killed by |
|---|---|---|
| M1 | KILLED | S-12101, S-12102, S-12103a/b, S-12104, S-12105, S-12105b, S-12112 |
| M2 | KILLED | S-12112 |
| M3 | KILLED | S-12114 |
| M4 | KILLED | S-12115 |
| M5 | KILLED | S-12105b |
| M6 | KILLED | S-12107, S-12108d, S-12108g, S-12113 |
| M7 | KILLED | S-12107, S-12108d |
| M8 | KILLED | S-6323, S-6329, S-12108h (S-12108a is green: it relies on the later-start side, now one-sided) |
| M9 | KILLED | S-12108f |
| M10 / M10b | SURVIVED, equivalent | a rest copy carries no `sessionExerciseId`, so `_loggedWristTimer` returns null at the slot check even with `rest` in `_workKinds` and the effort check removed |
| M11 | KILLED | S-12108g |
| M12 | SURVIVED, equivalent | an active or paused interval puts the kind in `wanted`, which the reconcile skips first (D-4 iii); and the `finished` flag is false without a finished one |
| M13 | SURVIVED, equivalent | as the plan predicted |
| M14 | KILLED | Swift `testS1310APhoneSnapshotLeavesTheWristsWorkClockRunning` (baseline copy passes 1/1; mutant fails: "running" is not equal to "stopped") |
| M15 (extra: two-sided match) | KILLED | S-6329, S-12108h |

