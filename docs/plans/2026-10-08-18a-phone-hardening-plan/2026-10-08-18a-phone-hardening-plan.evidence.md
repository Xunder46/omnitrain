# Evidence — 18a: phone hardening (two crashes)

Implementers and the reviewer append here. One row per checklist item: command, result, and the raw
counts (pasted, not summarised). Baselines for this plan (measured 2026-10-08, pre-change):

| Check | Baseline |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` (full suite) | 4061 passing, ~1 failure |
| `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues, 0 errors (pre-existing info notices) |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 passing, 0 failures |

## Phase 1 — the build-phase notify

| Item | Command | Result |
|---|---|---|
| S-150 / S-151 red at base | `prove-red <base-ref> test test/session_screen_build_phase_notify_test.dart -- …` | _(pending)_ |
| S-150 / S-151 green after | | _(pending)_ |
| `initstate_notify_contract_test` | | _(pending)_ |
| The item-6 audit: every checked site and its verdict | | _(pending)_ |

## Phase 2 — the summary guard

| Item | Command | Result |
|---|---|---|
| S-153 / S-154 red at base | | _(pending)_ |
| S-153 / S-154 green after | | _(pending)_ |
| The `.clamp(` audit: every session-window clamp and its verdict | | _(pending)_ |

## Phase 3 — the writer rule

| Item | Command | Result |
|---|---|---|
| S-155 red at base | | _(pending)_ |
| S-155 green after | | _(pending)_ |
| The `endedAtMs:` writer sweep: every writer and its rule | | _(pending)_ |

## Phase 4 — the repair migration

| Item | Command | Result |
|---|---|---|
| S-156 red at base | | _(pending)_ |
| S-156 green after | | _(pending)_ |
| Hive↔Mock parity on the repaired rows | | _(pending)_ |
| `docs/db_integration.md` reading: does it enumerate steps? | | _(pending)_ |

## Red → green table

| Scenario | Assertion that fails at the base | Test name |
|---|---|---|
| S-150 | `tester.takeException()` returns `setState() or markNeedsBuild() called during build` | _(pending)_ |
| S-153 | `computeSessionRestTimeMs` throws `ArgumentError(1791419191803)` | _(pending)_ |
| S-155 | `endedAtMs >= startedAtMs` fails after `resetSessionTimerStart()` | _(pending)_ |
| S-156 | the repaired `endedAtMs` still precedes `startedAtMs` | _(pending)_ |

## Reviewer findings

_(empty — the reviewer writes its table in `2026-10-08-18a-phone-hardening-plan.review.md` and links
the phase here)_
