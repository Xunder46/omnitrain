# Evidence — watch auto-sync PR 4 (17d): the phone's other entry kinds reach the wrist

Plan: `2026-10-07-17d-watch-auto-sync-pr4-plan.md`
Review: `2026-10-07-17d-watch-auto-sync-pr4-plan.review.md`
Predecessor: `docs/plans/2026-10-06-17c-watch-auto-sync-pr3-plan/` (PR 3 — deletions)

Executors append here. The plan keeps one-line Progress entries; measured output lives here.

## How to read this file

- **Paste real counts.** A hung, timed-out (gateway exit 124) or killed command is a failure, not an
  inconclusive result.
- **"Compiles" is not "passes".** `gateway.sh lint` green is not a test run.
- **A new assertion must be shown red without the fix.**

## Baselines

Base branch: `develop`. Rebase point (commit): `<fill in>`. Recorded by: `<phase 1 executor>`.

| Check | Command | Result | Date |
|---|---|---|---|
| lint | `.github/copilot/scripts/macos/gateway.sh lint` | `<issues/errors>` | |
| test | `.github/copilot/scripts/macos/gateway.sh test` | `<passed / failed / skipped>` | |
| swift | `.github/copilot/scripts/macos/gateway.sh swift-test` | `<passed / failed>` | |
| invariant | `grep -rln "import .*hive_workout_repository" lib/state lib/features lib/widgets lib/core` | `<nothing / hits>` | |

Start this PR **after** 17c has merged: the base here must include 17c's `heldWristEntryIds` and its
durable lens, otherwise Phase 2 has nothing to extend.

## Facts recorded before implementing (Phase 1, item 1)

| Fact | Where read | What it says | Rule this pins |
|---|---|---|---|
| The stamp the importer writes for an imported non-set entry | `lib/state/watch/watch_session_importer.dart` (`<line>`) | `<quote>` | D-133: `<the first rule / the pinned fallback>` |
| Whether a hold-effort window is derivable from the observation row alone | `<file:line>` | `<quote>` | D-130: `<the reconstructed window / omission>` |
| The wrist's own spelling for `timed`/`hold`/`round` | `WatchLoggingState.swift:600–700` (`windowPayload`, hold, round) | `<quote>` | D-130: field names, signs, units |

## Phase 1 — the phone projects its other kinds (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | the two recorded facts | | |
| 2 | `PhoneEntries.projectTimed` / `projectHold` / `projectRound` + `_window` | | |
| 3 | agreement with `WatchLoggingState.windowPayload` | | |
| 4 | `WatchInboxEntry.kindTimed/kindHold/kindRound` | | |
| 5 | `_entriesFor` per-kind dispatch | | |
| 6 | `_wristRowStamps` per-kind claim | | |
| 7 | S-140, S-141, S-142, S-143 | | |
| 8 | Progress + evidence | | |

Done Criteria run:

```
.github/copilot/scripts/macos/gateway.sh lint
.github/copilot/scripts/macos/gateway.sh test test/watch_session_projection_test.dart test/watch_session_adoption_bridge_test.dart test/sync_protocol_fixtures_test.dart test/watch_session_import_test.dart test/phone_manage_bridge_test.dart
```

Red→green table:

| Scenario | Red command / revert | Red output | Green output |
|---|---|---|---|
| S-140 | `prove-red` with the `_entriesFor` change reverted | | |
| S-143 | mutation: drop the zero-length-window guard | | |

## Phase 2 — the wrist shows them; 17c's deletion covers them (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | S-145 Dart twin | | |
| 2 | S-145 Swift | | |
| 3 | `heldWristEntryIds` filter dropped + S-144 | | |
| 4 | regression suites | | |
| 5 | Progress | | |

Done Criteria run:

```
.github/copilot/scripts/macos/gateway.sh lint
.github/copilot/scripts/macos/gateway.sh test test/watch_session_engine_test.dart test/watch_session_auto_push_test.dart test/watch_reconciliation_cross_stack_test.dart test/watch_session_import_test.dart
.github/copilot/scripts/macos/gateway.sh swift-test
```

Red→green table:

| Scenario | Red command / revert | Red output | Green output |
|---|---|---|---|
| S-144 | `prove-red` with the `kindSet` filter restored | | |

## Phase 3 — docs, contract sentence, residue sweep (@developer)

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | `docs/watch_session_sync.md` four kinds + the two omissions | | |
| 2 | PROTOCOL dated sentence | | |
| 3 | modality docs claim check | | |
| 4 | residue sweep | | |
| 5 | full suite + swift | | |
| 6 | final table | | |

Residue sweep output (paste both greps verbatim):

```
grep -rn "BlockTypes.set" lib/state/watch lib/core/sync_protocol
grep -rn "kindSet" lib/state/watch lib/data/models
```

| Hit | Set-specific rule, or documented boundary? | Verdict |
|---|---|---|
| | | |

## Final counts vs baseline

| Check | Baseline | After Phase 3 | Delta explained |
|---|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` | | | |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | | | |
| `.github/copilot/scripts/macos/gateway.sh lint` | | | |

## Parity check (I-1)

| Frame sequence | `HiveWorkoutRepository` payload | `MockWorkoutRepository` payload | Equal? |
|---|---|---|---|
| one `timed` instance | | | |
| one `round` instance with pauses | | | |
| one `hold` instance with an added weight | | | |

## Out-of-bounds writes found by the reviewer

`<reviewer fills>`
