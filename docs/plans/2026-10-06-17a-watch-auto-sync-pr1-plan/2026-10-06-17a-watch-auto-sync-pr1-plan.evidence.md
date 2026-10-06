# Evidence — watch-auto-sync PR 1 (`17a`)

Plan: `2026-10-06-17a-watch-auto-sync-pr1-plan.md`. Implementers and the reviewer paste real command
output here; the plan holds no evidence.

## Baselines (before this PR, on the branch point)

| Command | Result | Date |
|---|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` | 3949 passing, ~1 skipped, 0 failures | 2026-10-06 |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing info notices) | 2026-10-06 |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 294 passing, 0 failures | 2026-10-06 |

## Per-phase results

| Phase | Command | Result | Notes |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

## Red → green (a bug-fix test must fail without its fix)

| Scenario | What was stashed | Failing run | Passing run |
|---|---|---|---|
| S-76 (D-77) | the `projectedSession()` place-keeping change | | |
| S-77 (D-78) | the foreign-snapshot refusal | | |
| S-79 (D-80) | the timer-ownership rule | | |
| S-74 (D-76) | the payload-equality gate | | |

## Residue sweeps

| Sweep | Command | Result |
|---|---|---|
| copy removed from all three sources | grep `noAutoSyncLabel` under `lib/`, `test/`, `watch/` | |
| the hint widget cannot return | grep `NoAutomaticSyncHint` under `lib/`, `test/`, `watch/` | |
| no doc still claims sync is manual | grep (list the terms used) in `docs/` | |
| nothing outside the Predicted Files changed | `.github/copilot/scripts/macos/gateway.sh git-diff develop --name-only` | |

## Historical note (do not edit the old file)

`docs/plans/2026-10-04-14-watch-shell-bridge-plan/…evidence.md:308` records a mutation check "delete
`WatchNoAutomaticSyncHint()` from `WatchStartView.body`". That struct no longer exists after Phase 1;
the row is history.
