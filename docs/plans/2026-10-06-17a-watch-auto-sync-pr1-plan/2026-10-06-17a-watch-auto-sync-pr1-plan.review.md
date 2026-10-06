# Review — watch-auto-sync PR 1 (`17a`)

Plan: `2026-10-06-17a-watch-auto-sync-pr1-plan.md`. The reviewer (@code-reviewer) writes findings here;
one-line Progress items stay in the plan.

## Checks (each needs evidence, not a claim)

| # | Check | Expected | Actual |
|---|---|---|---|
| 1 | Diff versus the phase's Predicted Files — out-of-bounds files **and** untouched predicted files are both findings | | |
| 2 | Every Done Criteria command run, counts pasted | | |
| 3 | Per-S-x test and fixture conformance — the fixture names the held *different* session where the refusal is tested (S-77, S-78), and the adversarial rows (S-79's phone-written vs wrist-written timer) | | |
| 4 | Impact Check rows re-run: every grep in the plan's table re-executed; every named dependent's tests green; an unlisted reader is a finding | | |
| 5 | Two engines, one rule set: each D-78/D-79/D-80 rule present with identical refusal semantics in `WatchSessionEngine.swift` and `lib/watch/session/watch_session_engine.dart` | | |
| 6 | Append-only preserved: no refusal writes a row; no stored row is rewritten | | |
| 7 | No echo loop: a wrist frame never produces a frame (D-82), and a phone push is never a reply | | |
| 8 | `lib/state/` imports no concrete repository (`HiveWorkoutRepository` invariant) | | |
| 9 | PROTOCOL.md amendment is additive, dated 2026-10-06, and each rule names the test that proves it | | |
| 10 | Docs: no sentence claims sync is manual; every behaviour sentence names a real test; the touched docs stay under the 52 KB band | | |
| 11 | Assumption Log adjudication — every entry RATIFIED (promoted to a D-x) or REVERTED with a remediation sub-phase | | |

## Findings

(numbered; each with the count, examples and the root-cause line)

## Remediation sub-phases opened

(each must carry a structural guard: a permanent test that makes the defect class impossible to
reintroduce)
