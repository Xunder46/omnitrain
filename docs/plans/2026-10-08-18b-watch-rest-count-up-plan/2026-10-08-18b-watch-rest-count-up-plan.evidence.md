# Evidence — 18b the watch's rest is a count-up

Plan: `2026-10-08-18b-watch-rest-count-up-plan.md`. Implementers append to this file; the reviewer
reads it and appends its findings. One row per checklist item, with the command and the pasted
counts. The reviewer's own checklist lives in `2026-10-08-18b-watch-rest-count-up-plan.review.md`.

## Baselines (taken before Phase 1)

| Check | Command | Result |
|---|---|---|
| Dart tests | `.github/copilot/scripts/macos/gateway.sh test` | 4061 tests, ~1 pre-existing failure (record the exact name here when re-measured) |
| Analyzer | `.github/copilot/scripts/macos/gateway.sh lint` | 196 issues / 0 errors |
| Swift tests | `.github/copilot/scripts/macos/gateway.sh swift-test` | 335 tests / 0 failures |

## Phase 1 — the wrist's rest stops having a length (@developer)

| Item | Command | Result |
|---|---|---|
| `restSeconds` deleted, both stacks | | pending |
| `countdown` / `_countdown()` rest fallback gone | | pending |
| `WatchRestIsCountUpTests.swift` (Swift source scan) | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| S-160 / S-161 / S-164 in both stacks | | pending |

## Phase 2 — the rest screen, with one control (@developer)

| Item | Command | Result |
|---|---|---|
| `isResting` / `endRest()` / `log()` ends the rest | | pending |
| `WatchRestView.swift` + `ContentView` branch | governor's `xcodebuild` build (app target is not `swift-test`-covered) | pending |
| `watch_rest_screen.dart` (Dart twin) | | pending |
| S-161 / S-162 / S-163 in both stacks | `.github/copilot/scripts/macos/gateway.sh test test/watch_rest_surface_test.dart` | pending |

## Phase 3 — the wire refuses a rest length (@dba)

| Item | Command | Result |
|---|---|---|
| Both validators' rest clause | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| `envelope.schema.json` conditional | | pending |
| Fixtures updated additively | `.github/copilot/scripts/macos/gateway.sh test test/sync_protocol_fixtures_test.dart` | pending |
| `PROTOCOL.md` row | | pending |
| S-165 both halves | | pending |

## Phase 4 — the rule where agents will hit it (@developer)

| Item | Command | Result |
|---|---|---|
| `docs/global_conventions.md` row | | pending |
| Doc sweep (rest, sync, watch surface, QA walkthrough, settings, README) | `watch_surface.md` size before/after (ceiling 51.2 KB) | pending |
| `test/rest_is_count_up_contract_test.dart` | `.github/copilot/scripts/macos/gateway.sh test test/rest_is_count_up_contract_test.dart` | pending |
| Residue sweep + grep | the grep's output, pasted | pending |

## Red → green (prove-red)

| Scenario | Command | At the base | After |
|---|---|---|---|
| S-160/S-164 | `gateway.sh prove-red <base-ref> test test/watch_logging_timers_test.dart -- lib/watch/logging/watch_logging_state.dart lib/watch/logging/watch_logging_screen.dart` | pending | pending |
| S-161/S-162/S-163 | `gateway.sh prove-red <base-ref> test test/watch_rest_surface_test.dart -- lib/watch/logging/watch_logging_state.dart lib/watch/logging/watch_rest_screen.dart` | pending | pending |
| S-165 | `gateway.sh prove-red <base-ref> test test/sync_protocol_fixtures_test.dart -- lib/core/sync_protocol/message_validator.dart watch/sync_protocol/schemas/envelope.schema.json` | pending | pending |
| S-166 | `gateway.sh prove-red <base-ref> test test/rest_is_count_up_contract_test.dart -- lib/watch watch/watchos/Sources watch/sync_protocol/schemas` | pending | pending |

## Swift-side evidence

| Scenario | Command | Result |
|---|---|---|
| S-160/S-161/S-164 | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| S-162/S-163 | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| S-165 | `.github/copilot/scripts/macos/gateway.sh swift-test` | pending |
| `ContentView` branch (S-161/S-162) | governor's watchOS simulator build — agents must not claim it | pending |

## Reviewer findings

[empty — the reviewer fills this: diff versus Predicted Files, per-S-x conformance, the Impact Check
rows re-run, cross-stack agreement (Swift package vs Dart twin), quantified defects, Assumption Log
adjudication.]
