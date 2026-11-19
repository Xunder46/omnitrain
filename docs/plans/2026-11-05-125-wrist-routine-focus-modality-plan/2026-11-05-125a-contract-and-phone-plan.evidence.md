# 125a evidence

## Shared-file overlap with plan 129 (uncommitted, read before any run; base HEAD 268d127a)

Plan 129's uncommitted hunks (NOT 125a's; must stay byte-identical):
- `watch/sync_protocol/PROTOCOL.md`: `planned_down` and `session_started` table rows, two notes bullets, one history row (2026-11-06).
- `watch/sync_protocol/fixtures/manifest.json`: three `valid` entries (planned_down, planned_down_empty, session_started) and two `invalid` entries, appended at the tail of each array.
- `watch/sync_protocol/schemas/envelope.schema.json`: `planned_down`, `session_started` in the type enum.
- `watch/contract/watch_start_paths_contract.json`: `routinesPlans`, `plannedStart`. 125a does NOT touch this file (it does not enumerate routine keys beyond the sample message, which stays valid).
- `lib/core/sync_protocol/message_validator.dart`: two type names. 125a does NOT touch it: both validators read `schemas/messages/*.schema.json` at run time.
- `lib/state/watch/watch_session_adoption_bridge.dart`: hunks around adopt (new lines ~135-160, ~801-930, ~973) — `_routineFor` (~1029-1085) is in no uncommitted hunk.
- `test/watch_session_adoption_bridge_test.dart`, `test/watch_session_import_test.dart`: appended groups at the end. 125a adds NO test to these files; new test files only.
- `watch_reference_sync.dart`, `watch_sync_request_handler.dart`, Swift validator: 129's; 125a does not touch them (phone does not emit the field, D-125-2).

125a's own additive edits next to them:
- `PROTOCOL.md`: ONE new history row appended after the last line; one routines_down notes bullet is not added.
- `manifest.json`: new `valid`/`invalid` entries are INSERTED BEFORE 129's first appended entry of each array (pure insertion; no 129 line touched).
- No change to envelope.schema.json, the shared contract file, either validator, or the Swift package.

Pre-run snapshots: `.work/2026-11-05-125a/pre-*.diff`, `pre-sha.txt`.

## Results (lead-observed, 2026-11-06)

- Red: `flutter test test/sync_protocol_fixtures_test.dart` with the schema at HEAD: `+161 -3` (the three new fixtures); with the change: `+169 All tests passed`. `watch_routine_link_import_test.dart` against HEAD importer: `+6 -4`; with the change: `+10`. Wrist copy test red (getter missing) then `+5`.
- Green: bridge + import suites `+90` before and after (identical); `ui_standards_contract_test` + `docs_indexing_contract_test` pass; analyze on touched dirs: no issues; `swift test --filter SyncProtocolFixturesTests`: 6 tests, 0 failures. Invariant grep (hive_workout_repository in state/features/widgets/core) empty (review also found only `lib/main.dart`).
- Mutations (all killed after two tests were added for survivors): focus-over-wrist modality, dropped routineTemplateId / intent / title, `every`→`any` (added mixed-slots test), `lastIndexOf`→`indexOf` (added tilde-in-effort-id test), dropped `live` slot ids, wrist modality ignored, schema `minLength` removed, Dart `toJson` omit-guard removed.
- Plan 129 hunks: re-diffed after each run against the pre-run snapshots; only 125a's lines were added (manifest entries inserted before 129's entries, one PROTOCOL history row appended after 129's row, bridge `_routineFor` + const removal).
- Not done: Swift `WatchRoutine` parse (left to 125b per D-125-6); full Swift suite and full flutter suite (main session runs them).
- Noticed, not fixed: S-12512 `null` value has no own fixture (same schema branch as the number fixture); the S-12514 "phone does not emit" test is a pin 125b flips.
