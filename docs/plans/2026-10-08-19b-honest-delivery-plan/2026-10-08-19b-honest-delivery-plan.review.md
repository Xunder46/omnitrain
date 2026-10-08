# Review — 19b, a frame that did not get through is owed, never forgotten

Plan: `2026-10-08-19b-honest-delivery-plan.md`. Evidence: `2026-10-08-19b-honest-delivery-plan.evidence.md`.
This file is the Code Reviewer's; it stays empty until a phase runs. Append findings, never rewrite the
plan's or the evidence's text.

## What this review must check (the plan asks for all of these)

1. **Diff vs Predicted Files** — out-of-bounds files and untouched predicted files are both findings.
   Per file, the diff must match the phase item that predicts it (line ranges are the plan's estimate,
   not a promise; symbols are).
2. **Scenario conformance** — for each S-id in the phase's Done Criteria: the test exists, its fixture
   matches the plan's enumeration value-for-value, its expected outcome matches, and its red-at-base
   evidence is in the `.evidence.md`. A scenario asserted through a rule that cannot reach it on the
   fixture (a floor, a gate, a higher-priority signal) is a finding.
3. **Impact Check re-run** — every row of the plan's Impact table re-runs its own grep, and every named
   dependent's suites are green. An unlisted reader of a touched surface is a finding, not a shrug.
4. **Parity across the stacks** — the analogue here is the twin: `WatchSessionEngine` (Dart) and
   `WatchSessionEngine` (Swift) must produce the same replayed frame for the same stored row (S-212),
   and the two `sync` implementations must place the replay identically (S-216).
5. **Assumption Log adjudication** — RATIFY (promote to a D-x) or REVERT (open a remediation
   sub-phase). A RATIFY is required for: the doubles sweep's shape (D-200), the four rewritten existing
   cases (Phase 2 item 7), Phase 3's test-file choice, and any deviation from D-197's five sites.
6. **The deliberate AC-4 exception** (S-215) is read as designed: one extra `session_lifecycle` per
   catch-up while the wrist holds a terminal session, idempotent on the phone — not as a duplicate-frame
   defect. If the reviewer disagrees, it is a `## Feedback` line for the planner, not a remediation.
7. **Device-check honesty** — no agent claims a watch-app build or a paired run: `swift-test` covers the
   package only, and `ios/OmniTrain Watch App/ContentView.swift` is the governor's simulator build.
8. **Quantified defects** — every finding states the count, at least one example, and the root-cause line
   (`file:line` of the code that produced it). No "seems fragile".
9. **Every defect gets a structural guard** — a permanent test that makes the defect class impossible to
   reintroduce, inside a remediation sub-phase (`### Phase X.Y` in the plan, `BLOCKS Phase X closure`).

## Findings

[empty — numbered; each: what, where (`file:line`), root cause, quantified, the S-id or D-x it violates]

## Evidence re-run

| Checklist item | Check run | Result |
| --- | --- | --- |
|  |  |  |

## Assumption Log adjudication

| Entry (phase) | Verdict | Why / the D-x it was promoted to |
| --- | --- | --- |
|  |  |  |

## Remediation sub-phases opened

[empty — each names its structural guard]

## Verdict

[empty — one of: accepted; accepted with remediation Phase X.Y; blocked (with the blocker)]
