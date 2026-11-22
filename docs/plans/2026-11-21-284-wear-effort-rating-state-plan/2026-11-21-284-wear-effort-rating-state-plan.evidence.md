# Evidence: plan 284 (series 283 unit b), the Wear wrist's effort-rating state (2026-11-21)

Base commit `8cda033a`, working tree, nothing committed.

## Suites (observed output)

- Full suite after the last change: `flutter test` -> `+8789 ~4: All tests passed!` (plan 283a's last run: +8759; 30 tests added: 10 engine, 20 state).
- `test/ui_standards_contract_test.dart` + `test/docs_indexing_contract_test.dart`: `+54: All tests passed!`.
- `flutter analyze`: 174 issues (the baseline), 0 errors. Invariant grep: no output. `plan-lint before` and `after`: clean (18 scenarios, 2 Docs delta rows).
- One existing test needed a one-line update: `test/watch_nutrition_quick_log_test.dart` "the kinds the wrist can emit are a closed set" pinned `WatchObservationKind.all` to seven kinds; the wrist now emits a rating, so `effortRating` joined the list.

## Mutation pass (the lead's, scripted)

32 mutants over the record ids, the efforts list, the acknowledged-id set (restore, extend, held, acknowledged), the second-rating guard, the event kind and stamp, both stores, and the whole state (owed conditions, End without a session, restore, order, answered and skipped prompts, every pick rule, Confirm and Skip). 30 killed. Two survive and are equivalent: deciding "owed" after `finishSession` instead of before (the engine's `entries` is not session-scoped and finishing keeps the deletion lens, so no observable difference today; the order is kept as a guard against a later engine change, as the Apple state does) and a mutant of mine that rewrote the Confirm null check into the same two lines.

## Not verified here

- No screen reads this state yet (283c); nothing was run on a watch.
- No separate reviewer run (about 310 production lines closely mirroring `WatchEffortRating.swift` and the engine's Swift hooks); the lead read the production diff: no finding.
