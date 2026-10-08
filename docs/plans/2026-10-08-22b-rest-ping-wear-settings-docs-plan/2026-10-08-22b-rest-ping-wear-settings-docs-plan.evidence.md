# Evidence — the rest ping: Wear mirror, Settings copy, the rule and the docs (22b)

Companion to `2026-10-08-22b-rest-ping-wear-settings-docs-plan.md`. Implementers write the suite output and
the red→green tables here; the plan keeps one line per item and Assumption Log entries of at most 3 lines.
Suite output, not claims: paste the pass/fail counts.

This PR is plan 22's Phase 3, moved here whole by the governor's scope check on 2026-10-08. The phone and
Apple Watch halves of the same scenarios stay in
`docs/plans/2026-10-08-22-rest-ping-on-watch-plan/2026-10-08-22-rest-ping-on-watch-plan.evidence.md`; this
file records the Dart, Settings, rule and docs halves only.

## Baselines (recorded by the governor before the first phase)

| Check | Baseline |
|---|---|
| `.github/copilot/scripts/macos/gateway.sh test` (flutter, full) | 4152 passing, ~1 failing (pre-existing) |
| `.github/copilot/scripts/macos/gateway.sh swift-test` | 359 passing, 0 failing |
| `.github/copilot/scripts/macos/gateway.sh lint` (`flutter analyze`) | 196 issues, 0 errors (pre-existing infos) |

Record the same three numbers at the end of the phase and state the delta. A phase that moves one of them
without saying why is a finding. `test/docs_indexing_contract_test.dart` hard-fails above 64 KiB per doc and
warns above 80% (≈51.2 KiB).

## Red → green

The red column is the failure observed at the base commit for that scenario; the green column is the passing
run after the phase. Red for the *new* rule type is the first run of `test/watch_rest_ping_test.dart` at the
base commit: with `WatchRestPing` absent the file does not compile — record that run's output, not a later
one. S-226's red is `WatchHaptics` having no `playRestPing()` (the stub cannot conform and the assertions do
not compile).

| Scenario | Phase | Red (observed) | Green (suite output) | Test file · test name |
|---|---|---|---|---|
| S-241 the table, one-second polls (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-242 interval 0 / Off via `fromSettings` (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-243 gap catch-up fires once (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-244 interval change mid-rest (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-245 a rest ends, the next starts clean (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-221 same second pinged once (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-222 interval lands mid-rest (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-223 large interval (180) (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-224 a closed rest is never evaluated (Dart) | 1 | | | `test/watch_rest_ping_test.dart` |
| S-226 the Dart mirror's ping is its own tap | 1 | | | `test/watch_logging_surfaces_test.dart` |
| S-249 the Settings copy names the devices | 1 | | | `test/settings_sounds_test.dart` |
| S-250 the rule still bites | 1 | | | `test/rest_is_count_up_contract_test.dart` |

S-250 is a *negative* guard: its red is the reworded prose plus the new identifiers being *absent* from the
allowance, so the scanner flags `const restPingSeconds = 30;` — a later run in which the same red case
(countdown, stored rest length, planned rest) still fails is required evidence, not a substitute.

## Phase evidence

### Phase 1 — Wear mirror, Settings copy, rule and docs (@developer)

- `.github/copilot/scripts/macos/gateway.sh lint` (baseline 196 issues / 0 errors):
- `.github/copilot/scripts/macos/gateway.sh test test/watch_rest_ping_test.dart
  test/watch_rest_surface_test.dart test/watch_logging_surfaces_test.dart
  test/watch_logging_stepping_test.dart test/settings_sounds_test.dart
  test/rest_is_count_up_contract_test.dart test/docs_indexing_contract_test.dart`:
- `.github/copilot/scripts/macos/gateway.sh test` (full suite, 900 s):
- `.github/copilot/scripts/macos/gateway.sh swift-test` (expected unchanged; no Swift in this PR):
- `docs/state_management/watch_surface.md` size before → after (band: 51.2 KB warn, 64 KiB hard fail):
- Residue sweep (grep for a remaining reader of a rest *length* on the wrist; for a doc still calling the
  ping an alarm):
- Diff versus Predicted Files (out-of-bounds files, untouched predicted files):
- Assumption Log entries added:
