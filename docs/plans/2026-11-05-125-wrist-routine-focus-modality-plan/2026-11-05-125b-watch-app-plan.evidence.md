# Evidence — 125b (built 2026-11-06, base `19006457`, uncommitted)

Owner decision: relaunch EDGE cut (see the plan header). Built: the plain version.

## Runs (crew, glm-5.3-flash)
- crew-builder-watch Swift (phase A): 8.4 min, 76 requests. Red first: compile errors `no member 'focusModality'/'startModality'`.
- crew-builder-app (phase C): 7.5 min, 64 requests. Red first: emit assertions failed (`Expected: '<key>' Actual: <null>`).
- crew-builder-watch Dart (phase B): 10.8 min, 95 requests. Red first: `The getter 'startModality' isn't defined for the type 'WatchRoutine'`.
- crew-docs-keeper: 5.0 min, 57 requests. No prover, no reviewer run (token spend); the lead read every diff.

## Lead re-runs (counts seen)
- `swift test --filter "WatchRoutineFocusTests|WatchSessionStartPathsTests|WatchSlotTokenTests"`: 87 tests, 0 failures (7 new).
- `swift test --filter WatchSessionEngineTests`: 1231 tests, 0 failures (append-only guard included).
- `flutter test` watch_routine_focus_start_test, watch_session_start_test, watch_routine_focus_modality_test, watch_health_activity_test, sync_protocol_fixtures_test: `+238: All tests passed!`.
- `flutter test` watch_routine_focus_send_test, watch_routine_link_import_test, watch_reference_sync_test: `+54: All tests passed!`.
- `flutter test` docs_indexing_contract, ui_standards_contract, sync_protocol_fixtures, watch_reference_sync: `+253: All tests passed!`.
- `flutter analyze` on the five touched Dart files: No issues found.
- `plan-lint after`: clean (23 scenarios, 6 docs-delta rows).
- Invariant grep (hive_workout_repository in lib/state, features, widgets, core): empty.

## Mutation pass (isolated copy in the scratchpad; 14/14 killed)
S1 startModality unfiltered · S2 toJson drops focus · S3 focusKey keeps empty · S4 init ignores json focus · S5 start passes nil · S6 start passes raw focus (Swift, `WatchRoutineFocusTests`); D1 Dart startModality unfiltered · D2 start passes null · D3 start passes raw focus (`watch_routine_focus_start_test`); P1 emits empty · P2 emits null · P3 only sports · P4 filters unknown key · P5 never emits (`watch_routine_focus_send_test` + `watch_routine_link_import_test`). The real tree was never mutated.

## Plan 129 hunks (shared files)
`git diff -U0` saved before and after (`.work/2026-11-05-125b/pre-*.diff`, `post-*.diff`):
- `WatchStartPaths.swift`: every 129 line identical (only the last hunk's line numbers shifted by 3); 125b = doc comment (+6/-3) and `modality: routine.startModality,` (1 line).
- `watch_reference_sync.dart`: 129's lines identical; 125b = 6 added lines inside `buildRoutinesDown`, no removed line.
- `PROTOCOL.md`: 129's rows/bullets/history row identical; 125b = one sentence inside the committed 125a history row.
- `WatchSessionEngine.swift`: not touched (diff byte-identical before/after).
