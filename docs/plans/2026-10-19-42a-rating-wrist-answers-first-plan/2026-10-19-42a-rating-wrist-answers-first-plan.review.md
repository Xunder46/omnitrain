# Review: plan 42a rating-wrist-answers-first · P1+P2+P3 · e6ff75b0..working tree
Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 0 · nit 2 · tests: full `flutter test` `+5045 ~1` all passed (lead's run after P1/P2, per the brief — not re-run, the brief says do not re-derive); the 8 plan-42a tests green per the evidence file; docs tests pass
Diff vs Predicted Files: conforms — the 11 changed files are exactly the P1+P2 scopes plus the three P3 docs; `docs/state_management/workout_state.md` is not in the plan's P3 scope line but the plan's Progress table records adding it, and the brief lists it in scope. Nothing outside.

## Findings

### Blockers
None.

### Majors
None.

### Minors
None.

### Nits
1. [Nit] `docs/watch_session_sync.md:253` — the new paragraph cites only the scenario ids (`S-4301`, `S-4303`) without naming the test file, while every neighbouring paragraph cites a backticked test name; a reader of this doc alone cannot tell where the tests live. Fix: name `test/rating_first_answer_state_test.dart` / `test/rating_first_answer_summary_test.dart` in the parenthesis. Check: `grep -rn "S-4301" test/` resolves the ids to the two new files.
2. [Nit] D-3 requires the builder to "report which pop it used"; neither the plan's Progress row nor the evidence file records it (the evidence describes only the `route.isCurrent` guard). The pop is `Navigator.of(context).pop()` at `lib/features/session/session_summary_screen.dart:316`. Fix: one line in the evidence file naming it. Check: read `session_summary_screen.dart:308-317`.

## Answers to the brief's five questions (no findings attached)

1. **Can the pop close something other than the rating sheet?** From the code I can show: no. The listener runs only while `_autoFeelingSheetOpen` is set, i.e. between `addListener` before `EffortRatingSheet.show` (:283) and the `finally` (:294-295). The sheet is pushed via `showModalBottomSheet` with no `useRootNavigator` (`effort_rating_sheet.dart:59-78`), so it sits on the same nearest navigator that `Navigator.of(context)` resolves (:316); while the flag is set the sheet is that navigator's top route, so `pop()` pops the sheet. The `route.isCurrent` guard only excludes the Summary itself being top (the prover's unobservable mutation 9 — defensive). If a foreign route ever sat above the sheet, `pop()` would close that route and leave the sheet open (the flag is cleared first, so no repeated pops and never the Summary) — but I found no code path that opens one: the Summary's own dialogs are behind the sheet's modal barrier (`isDismissible: false`, `canPop: false`), and no timer/sync dialog route is opened by the code read this run.
2. **Can the listener stay attached or fire after dispose?** No path found. Added at :283 immediately before the await; removed in `finally` (:295), which covers both normal completion and a synchronous throw from `show`; removed again in `dispose` (:168), a no-op if already removed. A fire after dispose is guarded by `!mounted` (:309). The only theoretical attach-after-dispose is the `initState` post-frame callback running on a defunct state, but that shape is pre-existing (the old code awaited the same `EffortRatingSheet.show` on the same context), and the `finally` still removes the listener when the show throws.
3. **Does `_WiringAdoptionBridge.bindWorkoutState` keep the base behaviour, and are the graph types unchanged?** Yes. The base method is a single assignment (`watch_session_adoption_bridge.dart:176-178`); the override assigns its own `_boundState` then calls `super`. `WatchSyncGraph.adoption` stays typed `WatchSessionAdoptionBridge` (`watch_sync_wiring.dart:63`) — the private subclass is a subtype and adds no public member outside the wiring library; `createWatchSync` still returns `Future<WatchSyncGraph?>`.
4. **Can the wrist's rating arrive for the shown session while `currentSession` is another one?** Not on this screen: the Summary renders `workoutState.currentSession` in both views (`_isHistoricalView` is only `openedFromCalendar`, :131; the calendar flow loads the session into `currentSession` before pushing — the state test's `loadHistoricalSession` path shows the same). So when the Summary shows session X, `adoptSessionFeeling(X, …)` matches and notifies. The residual case: a calendar-opened Summary with no automatic sheet has no listener, so an adopted rating leaves its EFFORT row stale until the next rebuild (opening the change sheet reads the adopted value and pre-selects it). The stored row is correct either way, this staleness is pre-existing (nothing notified Summaries before this change), and D-1 scopes adoption to the live session. The user reopens or rebuilds and sees the watch's number.
5. **Do the docs claims match code and test names?** Yes. Every named test exists with the exact name (the three S-4303 tests and the group `Summary automatic effort question, first answer wins (plan 42a)` in `test/rating_first_answer_summary_test.dart`; `S-4301 the wrist answer settles once and the live session adopts it`, `S-4302 the phone's answer already in the row wins, with no callback`, `S-4304 onlyIfUnrated leaves the stored rating alone, the default still writes` in `test/rating_first_answer_state_test.dart`). The absolute claim "the watch's number is never overwritten by it" is scoped to the prompt's own answer and matches `onlyIfUnrated` (`session_core_lifecycle.dart:191-194`); the Add/Change control is named as an explicit edit and `_saveEffortRating` (:366-371) is unchanged; `watch_session_sync.md`'s "Written only while the row has none (D-138)" matches `_topUpRating`. No contradicted absolute claim.

## Assumption Log rulings
- A-1 (the automatic prompt is the only first-answer-wins surface; Add/Change stays an explicit edit) — **ratified**: `_saveAutomaticRating` (:322-333, `onlyIfUnrated: true`) vs `_saveEffortRating` (:366-371, unguarded default) implement exactly that split, and S-4305's test is untouched and green.

## Scenario coverage
- S-4301 -> `test/rating_first_answer_state_test.dart` · `S-4301 the wrist answer settles once and the live session adopts it` (Mock + Hive), plus `S-4301 the shipping graph hands the imported rating to the bound session` (through `createWatchSync` + `bindWorkoutState`) and `S-4301 a wrist answer that reaches a session the phone still holds is adopted too` (the merge pass)
- S-4302 -> `test/rating_first_answer_state_test.dart` · `S-4302 the phone's answer already in the row wins, with no callback` (Mock + Hive)
- S-4303 -> `test/rating_first_answer_summary_test.dart` · `S-4303 the watch rating closes the automatic question and stays stored`, `S-4303 the user's own answer closes the sheet once`, `S-4303 a late tap on the open question cannot overwrite the watch's answer`
- S-4304 -> `test/rating_first_answer_state_test.dart` · `S-4304 onlyIfUnrated leaves the stored rating alone, the default still writes` (Mock + Hive)
- S-4305 -> `test/session_summary_effort_row_test.dart:307` · `Fresh session — Change replaces an existing rating (button path)` — file absent from the diff, untouched

No scenario without a test that would fail without the change: the prover's 8 red mutations each name one of the above (mutation 9, the `route.isCurrent` guard, is unobservable and documented as defensive in the evidence file).

