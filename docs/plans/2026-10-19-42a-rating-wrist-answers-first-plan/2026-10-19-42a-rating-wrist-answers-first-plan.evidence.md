# Evidence — plan 42a (the watch answers the effort question first)

Docs-keeper run 2026-10-19 (P3). The code was built and proved before this run;
the docs keeper verified every claim against the source files named below and
wrote the docs. The numbers are the lead's run results handed over in the brief;
the docs keeper did not re-run the suite.

## Baselines

| Check | Result |
|---|---|
| `flutter analyze` | 181 issues before and after the change — no new issue |
| Full `flutter test` | `+5045 ~1` all passed, after P1 and P2 (before the gap-round tests) |
| New test files | 8 tests, all pass |

## Test table

| Scenario | Test (exact name) | File |
|---|---|---|
| S-4301 | `S-4301 the wrist answer settles once and the live session adopts it` | `test/rating_first_answer_state_test.dart` |
| S-4301 | `S-4301 the shipping graph hands the imported rating to the bound session` | `test/rating_first_answer_state_test.dart` |
| S-4301 | `S-4301 a wrist answer that reaches a session the phone still holds is adopted too` | `test/rating_first_answer_state_test.dart` |
| S-4302 | `S-4302 the phone’s answer already in the row wins, with no callback` | `test/rating_first_answer_state_test.dart` |
| S-4303 | `S-4303 the watch rating closes the automatic question and stays stored` | `test/rating_first_answer_summary_test.dart` (group `Summary automatic effort question, first answer wins (plan 42a)`) |
| S-4303 | `S-4303 the user's own answer closes the sheet once` | `test/rating_first_answer_summary_test.dart` (group `Summary automatic effort question, first answer wins (plan 42a)`) |
| S-4303 | `S-4303 a late tap on the open question cannot overwrite the watch's answer` | `test/rating_first_answer_summary_test.dart` (group `Summary automatic effort question, first answer wins (plan 42a)`) |
| S-4304 | `S-4304 onlyIfUnrated leaves the stored rating alone, the default still writes` | `test/rating_first_answer_state_test.dart` |

The stored-data state scenarios (S-4301, S-4302, S-4304) run on
`MockWorkoutRepository` and on `HiveWorkoutRepository` (the
`test/helpers/repository_harness.dart` factories). S-4305
(`test/session_summary_effort_row_test.dart`, `Fresh session — Change replaces an
existing rating`) stayed untouched and green.

## Mutation checks (lead, 2026-10-19)

9 mutations applied by hand; 8 made a named test red and were restored byte for
byte.

| # | Mutation | Result |
|---|---|---|
| 1 | Importer drops `appliedRating` (history pass) | named test red; restored |
| 2 | Importer drops `appliedRating` (merge pass) | named test red; restored |
| 3 | Inbox never calls `onSessionRated` | named test red; restored |
| 4 | `onlyIfUnrated` ignored | named test red; restored |
| 5 | `adoptSessionFeeling` does not notify | named test red; restored |
| 6 | The Summary never adds its listener | named test red; restored |
| 7 | The open flag is not cleared on the user's own answer | named test red; restored |
| 8 | The automatic answer drops `onlyIfUnrated` | named test red; restored |
| 9 | `route.isCurrent` check in `_closeAutoSheetOnOutsideRating` | **unobservable, stays unproven** — defensive: it only matters if the flag were set with no sheet on top |

## Verified in code this run (docs keeper)

- `lib/core/services/watch_session_importer.dart` — `WatchSessionImport.appliedRating`
  (`int?`), set from both call sites (`appliedRating: pass.ratingWritten`);
  `_topUpRating` writes only while the row has none (D-138).
- `lib/state/watch/watch_session_inbox.dart` — optional `onSessionRated`, called
  in `_settleNow` beside `onSessionRowsChanged` only when
  `pass.appliedRating != null`.
- `lib/state/watch/watch_sync_wiring.dart` — `onSessionRated: adoption.adoptRating`;
  the bridge's `adoptRating` calls the bound state's `adoptSessionFeeling`.
- `lib/state/workout/session_core_lifecycle.dart` — `updateSessionFeeling` with
  `onlyIfUnrated` (reads the stored row first, returns when it holds a rating);
  `adoptSessionFeeling` updates `_currentSession` and notifies, writes nothing.
- `lib/features/session/session_summary_screen.dart` — the automatic sheet's
  `onRated` is `_saveAutomaticRating` (`onlyIfUnrated: true`, clears the open
  flag first); `_closeAutoSheetOnOutsideRating` is added for the sheet's
  lifetime, removed in `finally` and in `dispose`, and pops only when a route
  sits on top (`route.isCurrent` guard).

## Pending

- `crew-reviewer` review of the built code.
- Simulator look at the Summary's automatic sheet (watch answer closes it).
- Owner checks: finish on the watch, answer on the watch — the phone's sheet
  closes and the EFFORT row shows the watch's number; afterwards Change rating
  still changes the number.
- Plan 42b (`docs/plans/2026-10-19-42b-rating-phone-answers-first-plan/`): the
  phone telling the wrist when the phone answered first. Until it ships, a wrist
  question stays open after a phone answer and a late wrist answer is ignored by
  the phone.

## The pop used (D-3)

`Navigator.of(context).pop()` in `_closeAutoSheetOnOutsideRating` (`lib/features/session/session_summary_screen.dart`), guarded by `ModalRoute.of(context)` not being current, and run only while `_autoFeelingSheetOpen` is set; the sheet is a `showModalBottomSheet` on the same navigator, so it is the top route while the flag is set.
