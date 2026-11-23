# Evidence — plan 310 (the Wear wrist sends the session's heart rate on `session_end`)

Measured by the lead. No gateway command and no test run by the docs keeper this run (the brief forbids them); the numbers below are the lead's.

## Build

- Built by `crew-builder-watch` (run `20261122-213403`, 6 min, glm-5.3-flash per the runner, exact-code brief, no gateway command); tests by the same run.
- The lead fixed the expected wire time form (`.000Z`, `utcIso` writes milliseconds) and four analyzer notes, reverted three formatter-only hunks in `watch_session_engine.dart`, and added `S-31009`.

## Checks

| Check | Result |
|---|---|
| `flutter analyze` | 174 issues, 0 errors (baseline 174) |
| `test/wear_heart_rate_session_end_test.dart` | 16 passed |

## Readers

All `test/watch_*.dart`, `test/wear_*.dart` and `test/live_mirroring_test.dart` ran: 1620 passed, 821 failed. Every failing test also fails on a clean checkout of `9e2a064c` (the Windows baseline: path separators, CRLF, Hive paths); none is new. The five files that were not in the lead's baseline name list (`watch_effort_rating_engine_test`, `watch_effort_rating_state_test`, `watch_phone_preferences_test`, `watch_session_engine_test`, `wear_os_config_test`) were re-run with the two source files stashed: the same failures.

## Mutation pass

21 mutants over: reading floor, finite check, window start, window end, kind filter, maximum, mean clamp, set-only blocks, strict lead-in, tie-break, session-start fallback, block end, empty-block key, session-pair presence, projection by session, deletions, samples by session, block start, block pair, window start, window end.

- 17 killed first time.
- M07 (mean clamp), M15 (projection ignores the session) and M17 (samples of any session) survived and were killed by two tests added in `S-31009`.
- M20 (window start taken raw instead of through `wireInstant`) is EQUIVALENT: `utcIso` keeps the instant (it writes `toIso8601String`), so `wireInstant` is an identity round trip in Dart and `heartRate` compares whole milliseconds either way.

## Not proven here

- Owner check 25 (needs a real watch).

## Standards seen, not fixed

- none.
