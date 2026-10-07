# Review — watch auto-sync PR 4 (17d): the phone's other entry kinds reach the wrist

Plan: `2026-10-07-17d-watch-auto-sync-pr4-plan.md`
Evidence: `2026-10-07-17d-watch-auto-sync-pr4-plan.evidence.md`

The reviewer writes findings here, quantified (count, examples, root-cause line). One section per
phase plus the checks the plan assigns to the reviewer.

## Phase 1 — the phone projects its other kinds

### Checklist conformance

| Phase item | Evidence in the evidence file | Verdict | Note |
|---|---|---|---|
| 1 the two recorded facts | | | |
| 2 the three projections + `_window` | | | |
| 3 agreement with `WatchLoggingState.windowPayload` | | | |
| 4 the kind constants | | | |
| 5 `_entriesFor` dispatch | | | |
| 6 `_wristRowStamps` per kind | | | |
| 7 the four scenarios | | | |
| 8 Progress + evidence | | | |

### Diff vs Predicted Files

| Predicted | Touched | Out-of-bounds file |
|---|---|---|
| `lib/core/sync_protocol/phone_entries.dart` | | |
| `lib/state/watch/watch_session_adoption_bridge.dart` | | |
| `lib/data/models/models.dart` (constants only) | | |
| `test/watch_session_projection_test.dart` | | |
| `test/sync_protocol_fixtures_test.dart` | | |

### Scenario conformance (fixture, then assertion)

| S-id | Fixture present as specified | Assertion as specified | Verdict |
|---|---|---|---|
| S-140 | | | |
| S-141 | | | |
| S-142 | | | |
| S-143 | | | |

### Impact Check re-run

| Plan row | Grep re-run | Dependent suite still green | Verdict |
|---|---|---|---|
| `PhoneEntries.project` callers | | | |
| `_entriesFor` callers | | | |
| `_wristRowStamps` / the set claim rule | | | |
| the validators / `$defs.entry` untouched | | | |

## Phase 2 — the wrist shows them; 17c's deletion covers them

`<checklist + diff + scenario + impact tables, same shape>`

| S-id | Fixture | Assertion | Verdict |
|---|---|---|---|
| S-144 | | | |
| S-145 (Dart) | | | |
| S-145 (Swift) | | | |

**Swift production files must be untouched** (D-134). Any diff under
`watch/watchos/Sources/WatchSessionEngine/` other than a test file is a finding.

## Phase 3 — docs, contract sentence, residue sweep

### Doc conformance

| Claim in the docs | Named test | Test exists | Test green |
|---|---|---|---|
| which kinds the phone projects | | | |
| a `round` carries its round number | | | |
| a `hold` carries its added load | | | |
| an unrepresentable entry is omitted | | | |
| a skipped set is not sent | | | |
| a set's added weight is not sent separately | | | |
| the rest timer does not travel | | | |

| Doc file | Size | Under 64 KiB | Under the 52 KB band |
|---|---|---|---|
| `docs/watch_session_sync.md` | | | |
| `docs/modality_tracking.md` (if touched) | | | |
| `docs/modality_based_exercise_ui.md` (if touched) | | | |

### Residue sweep

Every remaining `BlockTypes.set` / `kindSet` hit must be a set-specific rule or a documented boundary.
List the ones that are neither: `<...>`

### Structural guards required by this review

| Defect class | Guard test | File | Landed |
|---|---|---|---|
| | | | |

## Parity check (I-1)

| Frame sequence | `HiveWorkoutRepository` | `MockWorkoutRepository` | Dart twin | Swift twin | Verdict |
|---|---|---|---|---|---|
| one `timed` instance | | | | | |
| one `round` with pauses | | | | | |
| one `hold` with an added weight | | | | | |

## Invariant check

- I-2 layer boundary: `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` → `<nothing / hits>`
- I-3 omit, never placeholder: S-143 green, and no `0`/placeholder in the payload → `<read>`
- I-4 one entry per real record: S-142 green → `<count>`

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
