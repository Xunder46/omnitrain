# Review — watch auto-sync PR 3 (17c): a deletion on the phone reaches the wrist

Plan: `2026-10-06-17c-watch-auto-sync-pr3-plan.md`
Evidence: `2026-10-06-17c-watch-auto-sync-pr3-plan.evidence.md`

The reviewer (the Code Reviewer agent) writes findings here. One table per phase, plus the checks the
plan assigns to the reviewer. Findings are quantified: count, examples, the root-cause line.

## Phase 1 — the phone announces its deletions

### Checklist conformance

| Phase item | Evidence in the evidence file | Verdict | Note |
|---|---|---|---|
| 1 `heldWristEntryIds` | | | |
| 2 `deleteEntryAs` | | | |
| 3 ledger + `_pushOnce` order | | | |
| 4 `_announceDeletions` | | | |
| 5 seam + wiring | | | |
| 6 S-35 flip | | | |
| 7 the new cases | | | |
| 8 Progress + evidence | | | |

### Diff vs Predicted Files

| Predicted | Touched | Out-of-bounds file |
|---|---|---|
| `lib/state/watch/watch_session_auto_push.dart` | | |
| `lib/state/watch/watch_session_adoption_bridge.dart` | | |
| `lib/state/watch/live_session_mirror_state.dart` | | |
| `lib/state/watch/watch_sync_wiring.dart` | | |
| `test/watch_session_auto_push_test.dart` | | |
| `test/watch_session_projection_test.dart` | | |

### Scenario conformance (fixture, then assertion)

| S-id | Fixture present as specified | Assertion as specified | Verdict |
|---|---|---|---|
| S-120 | | | |
| S-121 | | | |
| S-122 | | | |
| S-123 | | | |
| S-126 (first half) | | | |

### Impact Check re-run

| Plan row | Grep re-run | Dependent suite still green | Verdict |
|---|---|---|---|
| `LiveSessionMirrorState.deleteEntry` readers | | | |
| `_pushOnce` send-count assertions | | | |
| `_wristRowStamps` / `claimedBy` readers | | | |

## Phase 2 — the Dart twin keeps the deletion

`<same three tables>`

## Phase 3 — the Swift twin, PROTOCOL, docs

`<same three tables, plus:>`

### Doc conformance (S-127) — reviewer-owned

| Claim in the docs | Named test | Test exists | Test green |
|---|---|---|---|
| a deletion reaches the wrist | | | |
| the deletion survives a wrist relaunch | | | |
| a re-created id is not swallowed | | | |
| a skipped set is not sent | | | |
| a set's added weight is not sent separately | | | |

| Doc file | Size | Under 64 KiB | Under the 52 KB band |
|---|---|---|---|
| `docs/watch_session_sync.md` | | | |
| `docs/state_management/watch_surface.md` | | | |

### Structural guards required by this review

Every defect class this review finds converts into **one** permanent test. List them:

| Defect class | Guard test | File | Landed |
|---|---|---|---|
| | | | |

## Parity check (I-1)

| Frame sequence | Dart twin | Swift twin | Equal | Verdict |
|---|---|---|---|---|
| | | | | |

## Invariant check

- I-2 layer boundary: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → `<nothing / hits>`
- I-3 append-only: the delete path touches no row removal → `<grep / read>`
- I-5 session scoping: S-126 green → `<count>`

## Assumption Log adjudication

| Entry | Statement | Ledger-consistent? | Verdict (RATIFIED → D-x / REVERT + remediation / ESCALATE to Feedback) |
|---|---|---|---|
| | | | |

## Remediation sub-phases opened

| Sub-phase | Defect | Root cause line | Structural guard it must add |
|---|---|---|---|
| | | | |

## Escalated to Feedback

`<anything genuinely ambiguous — the only trigger to re-invoke the planner>`
