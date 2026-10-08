# Review — 18b the watch's rest is a count-up

The verification agent fills this file. It is the reviewer's checklist, not the implementer's: the
implementer's baselines and pasted counts belong in
`2026-10-08-18b-watch-rest-count-up-plan.evidence.md`. Nothing here is run by the planner.

## Scope check

| Check | Result |
|---|---|
| Diff versus `## Files Affected` / each phase's **Predicted Files** (out-of-bounds files are findings) | pending |
| Every predicted file actually touched (untouched predictions are findings) | pending |
| No file under `.github/agents/**`, `.github/copilot/**`, `.claude/**`, `CLAUDE.md`, `AGENTS.md` | pending |

## Per-phase evidence table

| Phase | Checklist item | Evidence (command + pasted counts) | Verdict |
|---|---|---|---|
| 1 | `restSeconds` gone in both stacks | | pending |
| 1 | rest timer has no `plannedDurationMs` | | pending |
| 1 | `WatchRestIsCountUpTests.swift` red at base, green now | | pending |
| 2 | `isResting` / `endRest()` / `log()` ends the rest | | pending |
| 2 | rest screen with exactly one control | | pending |
| 2 | `ContentView` branch (governor's build) | | pending |
| 3 | both validators refuse a rest length | | pending |
| 3 | fixtures additive; `PROTOCOL.md` row dated | | pending |
| 4 | conventions row verbatim | | pending |
| 4 | `watch_surface.md` shrank, still under 51.2 KB | | pending |
| 4 | contract test's failure message names why | | pending |
| 4 | residue sweep grep has no hit outside D-168's exclusions | | pending |

## Scenario conformance (S-160 … S-168)

| Scenario | Test file | Fixture matches the plan's enumeration | Verdict |
|---|---|---|---|
| S-160 | | | pending |
| S-161 | | | pending |
| S-162 | | | pending |
| S-163 | | | pending |
| S-164 | | | pending |
| S-165 | | | pending |
| S-166 | | | pending |
| S-167 | | | pending |
| S-168 | | | pending |

Negative guards (S-161, S-167, S-168) must state their mutation and show it fails the guard; a
negative guard without its mutation is a finding.

## Impact Check re-run

Every row of the plan's `## Existing-Functionality Impact` table: re-run its grep, confirm the named
dependents' tests are still green, and treat an unlisted reader as a finding. The `WorkoutRepository`
parity check does not apply to 18b (no repository change) — state that explicitly rather than leaving
it blank.

| Row | Grep re-run | Dependent tests | Verdict |
|---|---|---|---|
| `restSeconds` readers | | | pending |
| `WatchTimerKind.rest` readers | | | pending |
| `countdown` / `_countdown()` call sites | | | pending |
| `plannedDurationMs` on the timer shape | | | pending |
| `log()` callers | | | pending |
| `ContentView` branch chain | | | pending |
| countdown prose in the docs | | | pending |
| `TemplateEffort.restSeconds` (excluded, D-168) | | | pending |
| the phone's `EntryRest` write path (untouched) | | | pending |

## Cross-stack agreement

| Behaviour | Swift package | Dart twin | Agree? |
|---|---|---|---|
| rest row has no plan | | | pending |
| count-up value at 0 s / 7 s / 240 s | | | pending |
| Next sets `stoppedAt`, returns to logging | | | pending |
| a log ends a running rest | | | pending |
| no milestone ever owed for a rest | | | pending |
| a `rest` timer with a plan is refused | | | pending |

## Defects

Quantified reports only: count, examples, root-cause line (file:line). Each defect opens a Phase X.Y
sub-phase that must include a structural guard — a permanent test making that defect class impossible
to reintroduce.

| # | Severity | Count | Examples | Root cause | Remediation | Guard |
|---|---|---|---|---|---|---|
| | | | | | | |

## Assumption Log adjudication

| Entry | RATIFY (promote to D-x) / REVERT / escalate to `## Feedback` | Reason |
|---|---|---|
| | | |

## Verdict

[pending — green / green with remediation / blocked, with the one-line reason]
