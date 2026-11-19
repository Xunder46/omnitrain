# Evidence — 129: a "Planned" button on the wrist's start surface, and the plan marked started

All numbers below were observed by the lead (Claude), not copied from an agent's report.

## Validation of the original build (2026-11-07, before the follow-up)

| Check | Observed |
|---|---|
| Invariant `grep "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | no match |
| `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` | `+54: All tests passed!` |
| `flutter analyze` | 181 issues (baseline) |
| `swift test` (`watch/watchos`) | Executed 1263 tests, 0 failures (the build-time count was 1221; later plan 125 commits add tests) |
| Review blocker (D-8972 conformance gate) | guard removed → `S-8973 …` failed (`Expected: null, Actual: TrainingSession`); restored → `watch_session_import_test.dart` + `watch_session_adoption_bridge_test.dart` `+90: All tests passed!` |
| Finding | report → first snapshot left the phone's session with **no exercises** (`hasActiveSession` false) until a second snapshot (throwaway test, removed) → D-8978 |
| Note | the D-8972 guard is real only where a `SyncProtocolValidator` is injected; production wires none (same as the phone's other receive paths). |
| Note | the `main.dart` wiring (`onPlanStarted`) was committed inside plan 120's commit `558cfb40`; HEAD does not compile without this plan's uncommitted `createWatchSync` parameter. |

## Follow-up F1 — D-8978, S-8980, S-8981 (2026-11-07)

Run `20261107-114637-crew-builder-app` (7 m 47 s, glm-5.3-flash), brief of three items, scope: the bridge and two test files.
The builder reverted its own early fix so the red runs were honest.

| Check | Observed |
|---|---|
| Red before the fix | `S-8980 the first snapshot fills a report-opened row with the ladder`: first snapshot left efforts `[]`; `S-8981`: `Expected: 'strength', Actual: <null>` (builder's pasted output) |
| `flutter test test/watch_session_adoption_bridge_test.dart test/watch_session_import_test.dart` | `+93: All tests passed!` (lead, after the guard test below) |
| Lead's mutation pass (in place, file restored and `cmp`-identical) | M1 `placeholder` never true → KILLED (S-8980 fill); M2 no first entries for a placeholder → KILLED (S-8980 fill); M4 report row drops the Focus → KILLED (S-8981); M3 every row counts as effortless → **SURVIVED** the builder's tests |
| Closing M3 (lead wrote the test) | `S-8980 a row that already holds an effort is loaded as it is, never filled from the snapshot` (a phone-trained row with one effort and a logged set meets a two-slot snapshot; efforts stay `[sl-1]`, rows unchanged; Mock and Hive). First version (a restart over an identical row) also survived: rewriting identical values is invisible. M3 re-run → KILLED. |
| Docs | `docs/watch_session_sync.md` Structure row names D-8978, the two S-8980 tests and S-8981; `plan-lint.py after` clean (15 scenarios, 10 docs-delta rows); stale-term sweep for "first snapshot brings the ladder": no hit outside `docs/plans`. |
| `flutter analyze` | 181 issues (unchanged) |
| Invariant grep | no match |
| Full `flutter test` (900 s cap) | `+7028 ~2: All tests passed!` |
| Residue | none: no `MUTATION` text, bridge file `cmp`-identical to the pre-mutation copy; git status entry count unchanged at 48 |

Not run: `swift test` (no Swift change in F1), `xcodebuild`, any device or simulator.
