# Review — 19a, the phone is the authority for the shared session

Companion to `2026-10-08-19a-phone-authority-plan.md` and its `.evidence.md`. The code reviewer
fills this file; the verdict line is what the governor reads.

Scope checked against `.github/copilot/pr-scope-budget.md`: one track's worth of production code
plus the sync contract; four phases (the seeded shape) against the budget's soft "more than
three" threshold — the governor measures, the planner keeps the seeded outline. Hard limits
(>800 lines, >5 phases, >1500 production lines) are not approached.

## 1. Diff versus Predicted Files

| Phase | Predicted files | Touched | Out of bounds | Untouched but predicted |
| --- | --- | --- | --- | --- |
| 1 | 4 production (2 Dart, 2 Swift) + 3 test files | | | |
| 2 | 3 `lib/state/watch/` files + 3 test files | | | |
| 3 | 1 screen file + 3 test files | | | |
| 4 | 4 doc files | | | |

A file outside the list, or a predicted file untouched without an Assumption Log entry, is a
finding. `lib/state/watch/watch_session_adoption_bridge.dart`, the wrist's engine and
`workout_session_finish.dart` are read-only surfaces this plan expects to find unchanged except
where Phase 3's item 5 says otherwise.

## 2. Ledger conformance

| Entry | Check (the mechanical question) | Result |
| --- | --- | --- |
| D-170 (supersedes D-10) | no feature page still states a both-hold-a-session rule older than D-170 | |
| D-171 | `createSession` refuses on both stacks, in both engines | |
| D-172 | one pass sends `abandoned(W)` then P's snapshot; the wrist ends on P | |
| D-173 | the phone's importer ignores an end for a session it does not hold (mutation reddens S-173) | |
| D-174 | the screen follows the end and shows the rating without a second prompt | |
| D-175 | the contract amendment is additive, dated, and changes no fixture | |
| D-176 | the predicate is `sessionId != null && sessionId != composedId && sessionId != placeholder`; the snapshot is sent even on an unchanged baseline; one reset per pass | |
| D-177 | the refusal's exit shape and the absorb, identical for `exercises: []` and a non-empty ladder | |
| D-178 | exactly two triggers (`_pushOnce`, `WatchSyncGraph.sync()`), no timer, no queue | |
| D-179 | the listener ignores foreign ids, `_isFinishingSession`, `editMode` and post-leave; leaves once | |
| D-180 | no rating prompt is owed for a phone-sent abandoned | |
| D-181 | 17b's D-95/S-115 superseded by record; the rest-timer line at `docs/watch_session_sync.md:497` untouched | |

Seeded entries D-170 … D-175 and S-170 … S-175 must appear word for word as seeded; any edit
to them is a finding.

## 3. Scenario conformance (S-170 … S-185)

For each scenario: the fixture exists as enumerated, the test name carries the S-id, and the
scenario is either red at base (`prove-red`) or paired with a mutation that makes it red.

| Scenario | Home | Fixture as enumerated | Red-at-base or mutation | Verdict |
| --- | --- | --- | --- | --- |
| S-170, S-171 (seeded) | Phase 1 suites | | | |
| S-172, S-173, S-174, S-175 (seeded) | Phases 2–3 | | | |
| S-176, S-177, S-178 | Phase 1 | | | |
| S-180, S-181, S-182, S-183 | Phase 2 | | | |
| S-184, S-185 | Phase 3 | | | |

AC coverage: AC-1 → S-170/S-171/S-176/S-177/S-178; AC-2 → S-172/S-175/S-180/S-181/S-182;
AC-3 → S-173/S-174/S-183; AC-4 → the Phase 4 doc table.

## 4. Impact Check, re-run

Each row of the plan's Impact table names a grep. Re-run all of them and compare with the diff.

| Surface | Grep re-run | New readers found | Verdict |
| --- | --- | --- | --- |
| `createSession` callers | | | |
| phone-sent lifecycle importers | | | |
| `WatchSyncGraph.sync()` callers | | | |
| `_pushOnce` and the push baseline | | | |
| `endSession` / `discardCurrentSession` readers | | | |
| docs consumers of the superseded rule | | | |
| the wrist's prompt queue | | | |
| S-109's `graph.sync()` cases | | | |

An unlisted reader is a finding, not a shrug. Every dependent named in the table must have its
own suite green (S-109 A/B/C, S-5, S-70 … S-84, S-73, S-78, S-81 in particular).

## 5. Cross-stack and repository parity

- The S-176/S-177/S-178 fixtures are byte-identical between `test/watch_session_start_test.dart`
  and `WatchSessionStartPathsTests.swift`; the evidence file's parity table has one row per
  fixture and reports both stacks' outcomes.
- The reset's frames are the same kinds both stacks already implement; the wrist's answer is
  produced by the twin under test, not by a stub the test wrote to fit.
- Phase 3's tests stay Mock-first; a Hive harness inside `testWidgets`, or a real
  `Future.delayed`, is a defect (it hangs rather than fails).

## 6. Assumption Log adjudication

| Entry (phase) | Ledger-consistent? | Ratify / Revert | Follow-up |
| --- | --- | --- | --- |
| | | | |

Expected entries: Phase 1's test repairs (each file), Phase 2's predicate and helper names,
Phase 3's helper placement, Phase 4's one known-limit wording. An empty log after Phases 1–3 is
itself suspicious.

## 7. Defects

| # | Defect | Count and examples | Root-cause line | Remediation phase | Structural guard |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

Every remediation sub-phase must include a permanent guard: a test that makes the defect class
impossible to reintroduce (this is the only check that gets cheaper over time).

## 8. Docs

- Every added or rewritten sentence appears in the evidence file's doc-sentence → test table
  with a test that exists by file and name.
- `watch/sync_protocol/PROTOCOL.md` gains exactly one dated row after the last one (`:565`); the
  row is additive, changes no fixture and no version.
- `docs/state_management/watch_surface.md` stays under the 80% band of
  `test/docs_indexing_contract_test.dart`; the before/after byte counts are in the evidence file.
- The residue sweep's grep output is pasted; a surviving "keeps its own" for a session (as
  opposed to the rest timer) is a finding.

## Verdict

`<PASS | PASS WITH REMEDIATION | FAIL — one line, dated, naming the open phases>`

## Open questions for the Conductor

<only items that genuinely need a planner decision; everything else is a remediation phase>
