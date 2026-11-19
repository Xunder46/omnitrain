# Review: plan 255 (active-session list progress) · P4 · 4e62dd83 + working tree
Verdict: APPROVE WITH FIXES
Counts: blocker 0 · major 2 · minor 3 · tests: not run by this review — brief states the lead ran the suite and mutations (10/10 killed) and `flutter analyze` is at baseline (178, 0 errors); per brief the full `flutter test` must not be run again.
Diff vs Predicted Files: outside: `test/food_catalog_load_test.dart` (unrelated edit, finding 3). The plan file itself changed — expected. Predicted otherwise conforms (`lib/features/session/workout_session_list_view.dart`, `test/session_list_progress_test.dart`, `docs/modality_based_exercise_ui.md`).
## Findings
1. [Major] `docs/widget_catalog/session_widgets.md` — the plan's only `## Docs delta` row (ADDED marker `exercise_tile_done_`) was never applied: a grep of `docs` this run finds `exercise_tile_done_` only in the plan and this review file, and the session catalog holds no session-list-tile progress sentence. A maintainer reading the catalog sees no trace of the done mark. Fix: either add the sentence to the catalog's session-screen section naming `test/session_list_progress_test.dart` (`S-25503`), or re-point the Docs delta row at the doc that actually changed. Guard: the docs-keeper marker check.
2. [Major] `lib/features/session/workout_session_timer_mixin.dart:516-522` — the stale-count path D-25503 claims cannot exist. `_handleEffortTimerExpired` calls `setState(() {})` *before* `finishTimedEntry`/`completeRound` resolve, records the next-entry rest only inside the async `.then`, and the state's `notifyListeners` is then ignored by `_onWorkoutStateChanged` (`workout_session_screen.dart:351` — no watch-revision change). Scenario: the user starts a hold in the detail view, taps Back so the list is on stage, the hold auto-expires — the tile rebuilds too early and keeps the old count and no mark until the next navigation or watch revision (S-25505 in `test/session_list_progress_test.dart` passes only by calling `markNeedsBuild()` by hand — the test file's own comment admits the write does not rebuild). Fix: after the `finishTimedEntry`/`completeRound` future resolves, rebuild once (e.g. `_updateUi(() {})` in the `.then`). Guard: a test pumping the list with a running hold, driving expiry, asserting the count updates with no manual `markNeedsBuild`.
3. [Minor] `test/food_catalog_load_test.dart:270` — `byId['chicken_thigh']!.fat!` → `.fat` is outside the Predicted Files and unrelated to plan 255 (a null-assert tidy in the food catalog suite). Fix: revert to keep the diff scoped, or have the lead state why it rides along.
4. [Minor] `docs/modality_based_exercise_ui.md:580,583` — the two new behaviour sentences cite "(plan 255)" but no existing test; the project doc rule wants a behaviour sentence to name a test. `test/session_list_progress_test.dart` (`S-25501..S-25503`, `S-25505`) asserts them and exists. Fix: add the test names.
5. [Minor] `docs/modality_based_exercise_ui.md:491-493` — "the list-view title and the subtitle line stay one line" becomes more fragile with this change: the tile gained a trailing icon (title/subtitle ~40 dp narrower) and the subtitle grew from `3 sets` to e.g. `2 of 3 sets`; the tile's `Text`s set no `maxLines` (`workout_session_list_view.dart:206-224`), so a long name at text scale 1.3 on a 320 dp screen can wrap. The pinning test (S-5119 in `test/logger_feedback_layout_test.dart`) covers the detail header, not the list tile. Fix: either clamp the tile title/subtitle to one line with ellipsis or update the sentence; not falsified outright by this diff.

## Answers to the brief's five questions (evidence, not re-derivation)

1. Freshness: back from detail — `_returnToList` (`workout_session_screen.dart:1923-1943`) rebuilds twice (immediate + post-frame) and the subtitle reads live `getEntryRests`/timed instances at build time, so the count is fresh. Wrist logs a set — the merge wires `onSessionRowsChanged: adoption.refreshHeldEfforts` (`watch_sync_wiring.dart:288`) → `refreshEfforts` bumps `_watchRefreshRevision` (`session_core_io.dart:285`; other bump sites 322, 350, `session_core_entry.dart:109`) → `_onWorkoutStateChanged` resyncs and rebuilds. Delete/add set from the detail — both paths call `_loadExercises()` then `setState(_showListView = true)` (`workout_session_screen.dart:1479-1489`, 1608/1801). The one stale path found is finding 2 (auto-expiry while the list is on stage). Edit mode is excluded correctly.
2. Logged rule: a skipped set records no rest → not counted; a set logged then deleted leaves positional rests so the count agrees with the detail dots by construction (both call `_isSetLogged`, `workout_session_screen.dart:824-845`); a set added after the others were logged keeps the old last-set rest valid and reads `N of N+1` with the mark dropped (add path reloads); a wrist-logged set arrives with its rest and is counted after the resync. `3 of 3` is reachable: `_logSet` records `recordRestStart(effortId, _currentSet)` where `_currentSet` is the next entry's 0-based index (`workout_session_screen.dart:1046-1051`), so the final set's rest lands at `entries.length`. No observed case of a mark shown while a set is undone, or hidden while done, outside finding 2's timing window.
3. Layout/tap: the trailing is a plain `Icon` (not an `IconButton`), so the whole ListTile stays one tap target and no tooltip is owed; `Text` wraps rather than overflowing, so no crash — only the one-line claim loosens (finding 5). Colour is `tileColors.primary`, an `OmniTheme` token; no hex literal, no allowlist entry, no ratchet bump in this diff.
4. Assertions are behavioural: exact subtitle strings (`0 of 3 sets`, `2 of 3 sets`, `1 of 1 set`, `3 of 3 holds`, `00:00 total`, `1 round`), `semanticLabel: 'Done'`, key absence/presence per state. Mutation (a) (count always 0) is killed by S-25502; an effort-kind-blind mark by S-25502/S-25507b; edit-mode-blind by S-25506; zero-entry mark by S-25508. The untested state is finding 2's stale window.
5. Docs: `modality_based_exercise_ui.md:580/583` matches the code (progress text, mark, edit-mode exception) — true but untested-named (finding 4). A search of `docs` outside `plans`/`history`/`releases` for the old wording (`N sets`, `set count`, `subtitle`, `exercise list`) found no other sentence the change made false (`my_routines.md:136` describes routine data, not the live tile; `navigation_and_screens.md:194` names no subtitle).
## Assumption Log rulings
The plan has no Assumption Log; nothing to rule on (a simple, single-phase feature).
## Scenario coverage
S-25501 → `test/session_list_progress_test.dart` · S-25501
S-25502 → same file · S-25502
S-25503 → same file · S-25503
S-25504 → same file · S-25504
S-25505 → same file · S-25505 (with the `markNeedsBuild()` caveat of finding 2)
S-25506 → same file · S-25506
S-25507 → same file · S-25507 + extra guard S-25507b (finished timed)
extra: S-25508 (zero entries) — beyond the plan's table; kills mutation (h); noted, not a finding.
## Docs delta
| Doc | Change | Status |
|---|---|---|
| docs/widget_catalog/session_widgets.md | ADDED marker `exercise_tile_done_` | MISSING (finding 1) |

Doc edit the table does not name: `docs/modality_based_exercise_ui.md:580,583` (the two progress sentences, applied).

## UI standards scan
No allowlist entry added, no ratchet raised, no raw `Card`/`SnackBar`/tooltip-less `IconButton`/shapeless button/colour literal in the diff. `test/ui_standards_contract_test.dart` was NOT run: the gateway's only test check is the full `flutter test`, which this brief forbids; the lead's suite run covers it (no new reds reported).

## Lead dispositions

1. Major (the Docs delta row named the widget catalog, the edit went to `docs/modality_based_exercise_ui.md`): FIXED, the row names the doc that really changed and the two sentences name their tests.
2. Major (auto-expiry while the list is on stage left the tile stale with a slow store): FIXED in `workout_session_timer_mixin.dart` (a rebuild after `finishTimedEntry` resolves); S-25509 with a gated store proves it, mutant j killed.
3. Minor `test/food_catalog_load_test.dart:270`: not this plan's change; already modified before the unit started (the owner's), left unstaged.
4. Minor (the doc sentences should name tests): FIXED.
5. Minor (a trailing icon narrows the tile: a very long name could wrap at 320 dp): not changed; ListTile text wraps rather than overflows and nothing pins the tile to one line; noted.
