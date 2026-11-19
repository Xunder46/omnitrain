# Evidence — 125d (built 2026-11-07, base `3c857941`, uncommitted)

Owner decisions OQ-1..OQ-3: the plan defaults, FINAL (see Assumption Log A-2). Built: P1 + P2 + P3 in one change (the ONE-commit gate D-12595 held), P4 docs by the keeper. No architect and no prover run (the seed carried exact code and fixtures; the lead's mutation pass replaced the prover); no reviewer run (token spend), the lead read every production diff, see `.review.md`.

## Runs (crew, glm-5.3-flash)
- P1 `crew-builder-watch` (contract + Swift wrist): 13.8 min. Red first: 26 of 32 new Swift tests failed on the base (24 unexpected-field refusals on the undeclared key, stamp arms nil). No reason text needed adjusting.
- P2 `crew-builder-watch` (Dart wrist): 6.6 min. Red twice: `Member not found: 'WatchActivityTypes.knownModality'`, then `+10 -14` with only the stamping arms failing.
- P3 `crew-builder-app` (phone emits): 16.7 min. Red on the base: `+9 -4` (S-12599 (a) and (d) red on Mock and Hive; (b), (c), (e), (f) and S-12598 green on base as predicted: pins).
- `crew-docs-keeper`: 5.2 min. `pipeline-stats` for the window: 4 runs, 42 agent-minutes, 279 requests, 15.9M input tokens, 0 automatic stops.

## Lead re-runs (counts seen)
- Full `swift test` in `watch/watchos` after P1: `Executed 1263 tests, with 0 failures`.
- Full `flutter test` after P1+P2+P3 (before the docs run): `+7025 ~2: All tests passed!`.
- Final targeted re-run after the docs edits and `dart format` of the two new test files: `flutter test` rest_is_count_up_contract, sync_protocol_fixtures, watch_snapshot_focus_wrist, watch_snapshot_focus_send: `+219: All tests passed!`; `swift test --filter "WatchSnapshotFocusTests|SyncProtocolFixturesTests"`: `Executed 38 tests, with 0 failures`; `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart`: `+54: All tests passed!`.
- `flutter analyze` on `lib/watch`, the bridge and the two new tests: `No issues found!`. Builders' lint: 181 pre-existing notices, none in the touched files.
- Invariant grep (hive_workout_repository in lib/state, features, widgets, core): empty.
- `plan-lint after`: clean (10 scenarios, 6 docs-delta rows).

## Mutation pass (isolated copy in the scratchpad; the real tree was never mutated)
17 mutants: 14 killed, 3 survived, all three equivalent:
- Killed: S1 stamp on every snapshot (drop `existing == nil`) · S3 `modality: snapshotFocus` (null-out) · S4 drop the `byModality` filter · S6 never stamp (Swift, `WatchSnapshotFocusTests`); C1 schema `minLength` removed (Swift `SyncProtocolFixturesTests`); D1, D3, D4 (Dart wrist, `watch_snapshot_focus_wrist_test`); P1 drop `isNotEmpty` · P2 emit null · P3 only sports · P4 never emit · P5 key read from the wrong object (`watch_snapshot_focus_send_test`).
- Survived, equivalent: S2/D2 `snapshotFocus ?? existing?.modality` (the plan's own "swap" mutant): `snapshotFocus` is non-nil only when `existing == nil`, so both orders give the same value; S5/D5 drop `isEmpty`: the `byModality` lookup already refuses `""`. (The `existing == nil` gate, which is what makes the swap safe, is killed by S1/D1.)

## Shared-file hunks (the governor stages by hunk; line numbers are working-tree lines at the end of this build)
`git diff -U0` saved before and after (`.work/2026-11-06-125d/pre-P1-*.diff`, `post-P1-*.diff`): in every shared file all plan 129 lines are identical before and after; only the 125d lines below were added.
- `watch/sync_protocol/PROTOCOL.md`: 125d = notes bullet at lines 210-214 and the history row at line 860 (the hunk `@@ -833,0 +860`). 129 = rows 73/79, bullets 164-181, rows 858.
- `watch/sync_protocol/fixtures/manifest.json`: 125d = the valid hunk at lines 196-207 and the invalid hunk at lines 676-723 (both whole hunks). 129 = lines 213-230 and 891-906.
- `watch/watchos/Sources/WatchSessionEngine/WatchSessionEngine.swift`: 125d = lines 594-599 (comment + `let snapshotFocus`) and line 607 (`modality: existing?.modality ?? snapshotFocus,`). 129 = `emitSessionStarted` at ~1361-1397.
- `lib/state/watch/watch_session_adoption_bridge.dart`: 125d = lines 296-299 (comment + `final focus`), 303 (`if (focus != null && focus.isNotEmpty) 'modality': focus,`) and the one comment line ~1253. 129 = the rest of the file's diff.
- Docs: `docs/watch_session_sync.md` line 82 (125d) vs line 21 (129); the other three docs are single-plan.
Not shared (all 125d only): `session_snapshot.schema.json`, `WatchPlatformWorkout.swift`, `lib/watch/sensors/watch_platform_workout.dart`, `lib/watch/session/watch_session_engine.dart`, the eight fixtures, the three new test files, `docs/state_management/watch_sensors.md`, `docs/my_routines.md`, `docs/watch-app-qa-wrist-logging.md`, this plan folder.

## Deviations
- QA step 43 is in `docs/watch-app-qa-wrist-logging.md` (the QA list moved there; `watch-app-setup-and-qa.md` only points to it), and step 42 (d), written by 125b as a "known gap, plan 125d", was rewritten to say the gap is closed. Two Docs delta rows added for them.
- The wrist tests assert that an empty `modality` is refused by the validating engine (fixture S-12591 (a)) and ignored by the validator-less engine, instead of "applies on both" as S-12592 first read: the schema's `minLength` wins on a validating receiver.
- The keeper also rewrote one sentence of `docs/my_routines.md` line 475 (125b's "known gap, follow-up 125d") that the new sentence contradicted.
