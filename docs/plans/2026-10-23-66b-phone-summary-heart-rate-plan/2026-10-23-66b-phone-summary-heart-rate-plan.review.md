# Review: plan 66b (heart rate on the phone summary) · phases per plan · HEAD..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 1 · tests: governor-run green (+5483, 2 skipped) per brief; lead mutations 6/7 red (seventh equivalent)
Diff vs Predicted Files: conforms (plan-66b paths only; the other working-tree files carry other plans and are not under review)

## Findings
1. [Minor] lib/core/services/session_summary_service.dart:66 — the plan's D-1 specified `({int avgBpm, int? maxBpm})?` with a max-null pill branch in D-3; the implementation returns a non-nullable `maxBpm` and skips any session summary lacking either value, so the plan's "average shows alone" acceptance row is unreachable rather than implemented. This matches the `SensorSummary` D-131 constructor invariant (lib/data/models/models.dart:2534-2539: avg and max are both present or both absent), which the doc states, and the governor already ruled the max-fallback mutant equivalent. Fix: none needed in code; the plan text could be annotated. Guard: the invariant is enforced by the model constructor itself.

## Answers to the brief's questions
1. The row uses only shared pieces: `_StatPill` twice inside a `Row` with `SizedBox(width: 16)` / `SizedBox(height: 16)` spacing that mirrors the Duration row (lib/features/session/session_summary_screen.dart:871-894); no colour, size or font literal, and the `Key('omni_session_heart_rate_row')` the tests pin. Absent without a session-scope summary: the whole block is behind `if (_heartRate case final heartRate?)`, and `test/session_summary_heart_rate_test.dart` `S-9654 not seeded: the card is unchanged, no row` asserts the key and the `AVG HEART RATE` text are absent while `DURATION` still shows.
2. n/a.
3. n/a.
4. `getSessionHeartRate` reads `_repository.getSensorSummariesForSession(...)` only; the diff added no import — the file imports `../../data/repositories/workout_repository.dart` (the interface) and `../../data/models/models.dart` (lib/core/services/session_summary_service.dart:3-11), no concrete storage.
5. Both docs edits agree with the code: `docs/session_summary.md` names only tests that exist verbatim (S-9651, S-9652, the two S-9654 tests, S-9656, S-9657 — all present in the new test file), the "model requires the two values together" claim matches models.dart:2534, the "load runs only while `currentSession` is non-null" claim matches the guard at session_summary_screen.dart:172-174, and `docs/watch_session_capture.md` (linked) exists. `docs/state_management/watch_surface.md` checked in the plan-64 review.

## Assumption Log rulings
Neither the plan nor the diff carries Assumption Log entries; nothing to rule on. The D-1 signature deviation above is ratified by the model invariant, not by an assumption entry.

## Scenario coverage
S-9651 -> test/session_summary_heart_rate_test.dart · `S-9651 avg 127.6 / max 171.2 rounds to (128, 171)`
S-9652 -> same file · `S-9652 no summaries, or only a non-session scope, answers null`
S-9653 -> MISSING — unconstructable: a `SensorSummary` with avg but no max throws at construction (models.dart:2534, D-131), so the scenario cannot exist; the doc states this and no test claims it
S-9654 -> same file · `S-9654 seeded: the card shows avg and max side by side` and `S-9654 not seeded: the card is unchanged, no row`
S-9655 -> MISSING — same reason as S-9653 (avg-without-max cannot be constructed); the non-nullable record makes the null-pill branch dead code that was correctly not written
S-9656 -> same file · `S-9656 a rolling session shows the heart-rate row too`
S-9657 -> same file · `S-9657 the row sits between Duration and Effort`
S-9658 -> covered by the governor's full-suite run (the existing `getSensorSummariesForSession` repository test stays green); the builder was to name it and the full suite is green
