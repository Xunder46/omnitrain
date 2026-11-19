# Evidence — plan 244 (a watch hold timer never outlives its stop on the phone)

Base commit b94a549a (branch `claude_develop`). Baselines: `flutter analyze` 181 issues, 0 errors (unchanged after); the adoption tests (`watch_timer_adoption_test`, `stale_watch_timer_adoption_test`, `wrist_pause_resume_adoption_test`, `watch_timer_adoption_screen_test`) 130 green before and after the production edit.

## Production (lead)

`TimerManager.releaseRemoteTimer`, `SessionCore.releaseRemoteWorkTimer`, `WorkoutState.releaseRemoteWorkTimer`, the `_adopted` memory and `_releaseWhatTheWristLeft` in `WatchTimerAdoption`, `diagnostics:` through `createWatchSync`, `_Pass._noteIntervalPlaced` in the importer.

## The regression the full suite found, and the narrowing

First rule: release when the wire stops naming the held interval, including a LATER start for the same slot. First full run: `test/watch_timer_push_test.dart` S-6323 red (the phone's finish of the old interval cleared the wrist's new clock). Confirmed against the base: the same test passes with the six production files from `git show HEAD:` in an isolated copy. Final rule: only a stop, or another exercise's timer, ends the claim; the same exercise keeps it whatever the start. `S-24421b` now pins that.

## Builder runs

| Run | Result |
|---|---|
| P2a `crew-builder-app`: `test/workout_release_remote_timer_test.dart`, Mock and Hive | +18 green |
| P2b `crew-builder-app`: `test/watch_timer_release_test.dart` | +8 green |
| Fix round 1 (tests-only, six surviving mutants) | +22 and +16 green after it |

## Mutation pass (lead; isolated copy of the Dart tree, originals `cmp`-restored)

First pass 21 of 27 killed; survivors: round tolerance `>=`, bookkeeping even when nothing written, slot arm of the same-interval check, adoption tolerance `<`, session-change memory, importer label swap. Fix round 1 added S-24409a/b, S-24419..S-24423; re-run: all six killed. After the narrowing the adoption mutants were re-run with the new lines (13 of 13 killed: A1 bookkeeping, A2 bookkeeping without a write, A3 slot arm, A4 any frame ends the claim, A5 pause counts as stopped, A6 release never runs, A7 wrong start, A8 claim kept after release, A9/A10 notes dropped, A11 memory across sessions, A12 reason text, A13 a stop keeps the claim). State-level mutants T1..T9 (finished reset, tolerance both branches, state, pause bookkeeping, start, revision, notify, persisted write): killed.

## Verification (lead, observed)

| Check | Result |
|---|---|
| timer readers after the narrowing (`watch_timer_release_test`, `workout_release_remote_timer_test`, `watch_timer_push_test`, the four adoption files) | 231 passed, 0 failed |
| full `flutter test` (JSON reporter, 4th run) | 8111 passed, 4 skipped, 0 failed |
| earlier full runs | run 1: 1 red in `pre_release_gate_ios_artifact_test` (tearDownAll), green alone (12 tests), attributed to a peer's concurrent work in the tree; run 2: 3 red, unnamed (reporter), the same set later green; run 3: S-6323 (real, fixed) |
| `flutter analyze` | 181 issues (baseline), none in the changed files |
| invariant grep `import .*hive_workout_repository` in `lib/state lib/features lib/widgets lib/core` | no hits |
| `plan-lint after` | clean (19 scenarios, 5 docs-delta rows) |

## Docs (lead wrote the sentences; no keeper run)

`docs/watch_session_capture.md` (the stop sentence, the plan 244 release), `docs/state_management/workout_state.md` (the `releaseRemoteWorkTimer` row), `docs/state_management/watch_diagnostics.md` (nine kinds, the three new ones, the verifying tests).
