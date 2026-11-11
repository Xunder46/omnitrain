# Plan 139 — going back from an exercise returns to that exercise in the list

Slug `2026-11-09-139-back-to-focused-exercise`. Branch `claude_develop` (the working branch; never switched).
Base commit `11e38f8cd78a25334abb67de9a65023dae0222ed` (plan 138, "PR A", is committed in it). Series: **139 = "PR B"**.

## Goal and acceptance

Owner report (2026-11-09): after opening an exercise and pressing back, the list jumps to the bottom instead of showing
the exercise just left. Wanted: "focus on the exercise from which we click back, or something similar".

What the user sees after this plan, in BOTH the routine editor and the live session screen (standard list, rolling list,
and the session editor):

1. Pressing back from an exercise's detail (header arrow, or the system back gesture) returns to the list with **that
   exercise's row in view**, its top roughly a third of the way down the list area (30% of the free space), not at the very bottom.
2. If the user walked to another exercise with the arrows first (plan 138), back returns to the exercise they are **on
   now**, not the one they opened.
3. An exercise near the end of the list lands as low as the list can scroll (its Add Exercise / Add Block buttons stay
   reachable below); one near the top lands at the top.
4. A newly added exercise (opened right after adding) is the last row, so back lands at the end, as today.
5. Nothing else changes: removing an exercise still returns to the list from the top; the list's look, the header,
   gestures and animations are untouched; there is no new animation (the jump is instant, as today).

Acceptance: S-13901..S-13910 pass; the four old tests that pin "lands at the bottom" are replaced (D-9); `flutter analyze`
count not above baseline; invariant grep clean; `test/ui_standards_contract_test.dart` and
`test/docs_indexing_contract_test.dart` pass; every guard arm proven by a mutation the lead observed.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-1 | New helper `ListRowFocus` in `lib/widgets/layout/list_row_focus.dart` (exact code in the P1 brief). It keeps `Map<String, BuildContext>` filled by `track(id, child)` (a `Builder` that registers its context and returns the child), a pending id set by `request(id)`, `double? get cacheExtent` (`100000` while a request is pending, else `null`), and `bool reveal()` which calls `Scrollable.ensureVisible(context, alignment: 0.3, duration: Duration.zero)` and clears the request. It returns false (and clears the request) when nothing was requested, the id is unknown or the context is unmounted. | probe 2026-11-09, S-13901, S-13902 |
| D-2 | Lazy lists only build rows near the viewport, so a far row has no context. While a request is pending the list gets `cacheExtent: 100000`, so the first frame builds every row. A finite value is required: `double.infinity` trips Flutter's `value.isFinite` assertion (observed). The extent is raised for ONE frame only; the owner calls `setState` after `reveal()` and the list returns to the default, so steady-state build cost is unchanged (a live session rebuilds every second). | probe: default list leaves row 45 of 60 unbuilt; `100000` builds 60 of 60 and lands the row at the same offset as a non-lazy list; infinity asserts. S-13901, S-13907 |
| D-3 | Rows are registered by a `Builder`, not a `GlobalKey`: the routine editor's rows sit in a `ReorderableListView`, where a duplicated `GlobalKey` during a drag is a known clash. A `Builder` context map has no key to clash. | S-13903 (real screen) |
| D-4 | Each screen's back path becomes: `setState(show list, request(focusedId))`, then in a post-frame callback `if (!mounted) return; if (!_rowFocus.reveal()) _scrollListToBottom(); setState(() {});`. The existing `_scrollListToBottom` stays as the fallback (nothing focused, id unknown, row gone): never an error. The focused id is the exercise at `_currentExerciseIndex` at the moment of back (routine: `currentEfforts[i].id`; session: `_exercises[i]['id']`). | `routine_setup_screen.dart:160,637`; `workout_session_list_view.dart:1106`; `workout_session_screen.dart:1964` |
| D-5 | Routine editor wiring: field `_rowFocus`; the outer `ListView` (`:212`) gets `cacheExtent: _rowFocus.cacheExtent`; the `ReorderableListView` item is `KeyedSubtree(key: ValueKey('row-${effort.id}'), child: _rowFocus.track(effort.id, ExerciseCard(...unchanged, keeps its own key...)))`; the two back sites (`:160` system back, `:637` `onBack`) call one new method `_returnToList()`. The removal paths (`:766`, `:905`) are NOT changed (they return from the top today and keep doing so). | `routine_setup_screen.dart:212,495-521` |
| D-6 | Session wiring: one `track` call in `_buildExerciseTile` (`workout_session_list_view.dart:164`, shared by block cards and standalone rows, standard and rolling lists); `cacheExtent: _rowFocus.cacheExtent` on BOTH `ListView`s (`:421` rolling, `:589` standard); the header back (`:1106`) and the edit-mode `PopScope` (`workout_session_screen.dart:1964`) call one new method `_returnToList()` in the state class. The delete path (`workout_session_screen.dart:1462`) is NOT changed. | file:line as listed |
| D-7 | Where the row lands is a product choice made by default: 30% down from the top of the list area (constant `ListRowFocus.kRevealAlignment`). Reported to the owner; changing it is one constant. | owner may change |
| D-8 | Neither screen has collapsible blocks (checked), and no list here holds more than a few dozen rows, so building all rows for one frame is cheap; if a list ever grows to hundreds of rows the extent can be reduced to "viewport x N" without changing callers. | `workout_session_list_view.dart`, `routine_setup_screen.dart` (no expand/collapse state) |
| D-9 | Four existing tests pin the old landing and are replaced by this plan's tests, not edited around, all in `test/interaction_flow_test.dart`: group `Scroll to bottom when navigating back from exercise detail` · `scroll position moves to bottom after returning from exercise detail` (line 1937) and `system back gesture in edit mode returns to list view and scrolls to bottom` (1995); group `Scroll to bottom when navigating back from routine exercise detail` · `scroll position moves to bottom after returning from routine exercise detail` (2106) and `system back gesture returns to routine list view and scrolls to bottom` (2161). The two tests in those groups that do not assert the scroll (`back button from exercise detail returns to list view`, `back button from exercise detail returns to routine list view`) stay; the group titles keep the old wording unless P4 renames them (rename them to `Back returns to the focused exercise ...`). Their old assertions used the first of six identical rows, so they could not tell "focus" from "bottom". | `interaction_flow_test.dart:1847-2208` |
| D-10 | Tooltips, labels, headers: unchanged. No new user-visible text. | - |

## Scenarios

All Mock harness, no timers, no real delays. "Distinct exercises" = the first N library exercises with pairwise different
names (the library has 339; the test asserts the names are distinct before using them). A row's "landing" is
`rowRect.top - listRect.top` where `listRect = tester.getRect(find.byType(ListView))` and `rowRect` is the rect of the
tracked row widget (routine: the `ExerciseCard` that contains the name; session: the `ListTile` that contains it).
`ensureVisible` puts the row's top at `0.3 * (listHeight - rowHeight)` (probe: 159.6 px for a 600 px viewport and a 68 px
row, not 180), so on the real screens "lands at alignment" means the landing is between `0.15 * listHeight` and
`0.40 * listHeight`; only S-13901 (a plain list) pins the exact formula, within 1 px. Surface: `Size(600, 500)` for the routine editor
(as the old routine test), `Size(400, 500)` for the live session (as the old session test).

| ID | Fixture | Expectation | Fails without the change because |
|---|---|---|---|
| S-13901 | Plain widget test: `MaterialApp > Scaffold > ListView(controller, cacheExtent: focus.cacheExtent, children: 60 cards of height 60 + (i % 5) * 37 each wrapped in focus.track('c$i', card))`, 600 tall. `focus.request('c30')` + `setState` + pump, then `focus.reveal()` + pump. | `reveal()` returns true; card 30's top is at `0.3 * (viewportHeight - cardHeight)` from the list top, within 1 px; `focus.cacheExtent` was `100000` while pending and is `null` after `reveal()`. A second case: `request('c59')` lands at `maxScrollExtent` (clamped). | the class does not exist (compile error) |
| S-13902 | Same list. (a) `reveal()` with no request. (b) `request('nope')` then `reveal()`. (c) `request('c10')`, then rebuild the list WITHOUT card 10 and `reveal()`. | each returns false, the scroll offset is unchanged, `cacheExtent` is `null` afterwards, a second `reveal()` returns false. | no helper |
| S-13903 | Routine editor, 24 distinct exercises in six blocks of four (so the fourth block starts beyond the default build range) via `addSegment` + `addExerciseToRoutine(segmentId:)`, saved, screen pumped at 600x1200. Scroll the list with its own controller until exercise #14 (index 13) is on screen, tap it, tap the header back arrow. | the list is on screen; #14 lands in the band; `controller.offset` is more than 100 px below `maxScrollExtent`. | today the list jumps to the very bottom, #14 is far off screen |
| S-13904 | Same fixture; tap #14; system back via `tester.binding.handlePopRoute()` (the screen's `PopScope`). | same expectation as S-13903. | the other back path would still jump to the bottom |
| S-13905 | Same fixture, every exercise has 1 set. Tap #13, press `Next Set` three times (plan 138: it crosses to #14, #15, #16), tap back. | exercise #16 lands in the band; #13 would not. | back would return to the bottom, or to the exercise opened (#10) |
| S-13906 | Same fixture; tap the LAST exercise (#24); back. | #24 is fully inside the list rect; `controller.offset == maxScrollExtent`; no exception. | honest note: today also ends at the bottom, so this guards the clamp (the row must not need to scroll past the end), proven by mutation not by failing on old code |
| S-13907 | After S-13903's back: the `ListView` widget's `cacheExtent`. | `null` (steady state). | a build that left the raised extent on would rebuild every row every frame |
| S-13908 | Live session, standard list (`createNewSession` for `resistance_lifting` via the helper `buildScrollTestDeps` copied from `interaction_flow_test.dart`), 24 distinct exercises added with `addExerciseToSession`, 400x700. Scroll to #12, tap it, header back arrow. | #12 lands in the band; offset more than 100 px below max; `ListView.cacheExtent` is `null`. | today: bottom |
| S-13909 | Live session editor (`editMode: true`, the fixture of the old test `system back gesture in edit mode...`), 24 exercises, tap #12, system back (`handlePopRoute`). | #12 lands in the band. | the `PopScope` path is a separate call site |
| S-13910 | Live session, ROLLING (`createNewSession(isRolling: true)`, six blocks of four via `addSessionBlock` and `assignEffortToBlock`, so the fourth block is a lazy list child beyond the default build range), 400x700. Tap #14, back. | #14 lands in the band. | the rolling list is a second `ListView`; a build that forgot its `cacheExtent` would not find the row |

The lead re-derives the geometry numbers (card heights, the 0.3 landing) with the throwaway probe above before the briefs.

## Phases

| Phase | Agent | Items (max 8) | Write scope | Parallel |
|---|---|---|---|---|
| P1 | crew-builder-app | 1 `ListRowFocus` (exact code, D-1); 2 `test/list_row_focus_test.dart` S-13901, S-13902 (exact text); 3 routine editor wiring (D-4, D-5, exact text per site) | `lib/widgets/layout/list_row_focus.dart`, `test/list_row_focus_test.dart`, `lib/features/routine/routine_setup_screen.dart` | serial, first |
| P2 | crew-builder-app | routine screen tests S-13903..S-13907 as a NEW file `test/routine_back_to_exercise_test.dart` (helpers copied from `routine_detail_screen_test.dart`, named in the brief) | `test/routine_back_to_exercise_test.dart` | after P1; parallel with P3 (disjoint scopes, neither needs the other) |
| P3 | crew-builder-app | session wiring (D-4, D-6, exact text per site) | `lib/features/session/workout_session_screen.dart`, `lib/features/session/workout_session_list_view.dart` | after P1; parallel with P2 |
| P4 | crew-builder-app | session tests S-13908..S-13910 as a NEW file `test/session_back_to_exercise_test.dart`; delete the four old tests of D-9 from `interaction_flow_test.dart` | `test/session_back_to_exercise_test.dart`, `test/interaction_flow_test.dart` | after P3 |
| P5 | crew-docs-keeper | the Docs delta below | the three docs named, this plan's evidence file | after P4 |

Five phases is the hard limit, not over it; one soft signal (more than 3 phases). Predicted production code: about 90
lines (helper 45, routine 20, session 25). Shared-tree note: both session files were clean at the base commit; if a peer
session edits them before P3, hunks mix at commit time and need `git add -p`.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| `docs/modality_based_exercise_ui.md` | MODIFIED | Back button returns to list view | Back returns to the list view with the exercise you left in view | S-13908 |
| `docs/my_routines.md` | ADDED | - | Back from an exercise returns to that exercise in the list | S-13903 |
| `docs/widget_catalog/layout_and_inputs.md` | ADDED | - | ### `ListRowFocus` | S-13901 |

`docs/modality_based_exercise_ui.md` is 50,627 bytes (80% band is 52,428): the keeper's edit there must add under 600 bytes.
Stale-term sweep run 2026-11-09: `grep -rIn "scroll.*bottom\|lands near\|scrolls the list\|Back button returns" docs | grep -v "docs/plans\|docs/history\|docs/releases"`
returned only the Old marker above (the bottom landing is not documented anywhere today).

## Input-reality checklist

- Writers and units: no stored value is read. The row ids are effort ids (routine: `TemplateEffort.id`; session: the effort id string), written by the app when an exercise is added.
- Lifecycle: an exercise removed while its detail is open returns from the top (unchanged paths). A row whose context is gone is detected (`mounted`) and falls back to the bottom jump. A watch-driven refresh of the session list while in detail only rebuilds rows; the registry is refilled on every build.
- Settings changing while open: none read. (The theme can change; rows rebuild and re-register.)
- Time: the live session rebuilds once a second; the raised cache extent exists for one frame only (S-13907), so no steady cost.
- Cost: one frame builds every row (a few dozen) once per back press.
- Words: no new text. Docs wording is in the Docs delta.
- Competition: the bottom rest strip and the controls overlay the lower part of the list; the row lands at 30% from the top, well above them. The routine editor's name/description fields sit above the list and are outside its scroll.

## Progress

- [x] P1 helper + routine wiring (builder, 16 requests; lead keyed the helper's `Builder` by id after the builder's test showed unkeyed rows reuse an element)
- [x] P2 routine tests (builder; lead rewrote the fixture to six blocks of four and the scroll helper to the list's own controller after the mutation pass)
- [x] P3 session wiring (builder, parallel with P2)
- [x] P4 session tests + replace the four old tests (builder; lead added the next-frame test and the six-block rolling fixture after the mutation pass)
- [x] P5 docs (keeper; plan-lint after clean)
- [x] Verify: `flutter analyze` 181 (baseline 181, one new curly-braces issue fixed); affected test files green; ui standards + docs indexing green; invariant grep clean; **full suite `+7325 ~2: All tests passed!` in a quiet tree**
- [x] Prove: 23 mutants; first pass 18 killed, 5 survived; after fixture fixes 21 killed; 2 survive by design (fallback, R8 and S8)
- [x] Review: lead read the diffs of P1 and P3 (small, exact brief text); no reviewer run

## Assumption Log

- Plan written by the lead without an architect run: exact code and fixtures are seeded, and the risky claim (far rows are not built; a finite large cache extent builds them and lands them exactly) was probed on 60 uneven cards before writing.
- Not yet proven on the real screens: the routine editor's rows sit in a shrink-wrapped, non-scrolling `ReorderableListView` inside the outer list; `Scrollable.ensureVisible` must pass through it. S-13903 is the first test written and decides this before anything else is built on it.
- The fallback line (`reveal()` false → `_scrollListToBottom()`) cannot be reached from a screen test without a stale registry; it is guarded by the helper tests S-13902 plus a mutation, and listed as defence in depth.
- Defaults taken without asking (owner may change): the row lands at 30% from the top; back from the first rows lands at the top instead of today's bottom; no animation.
- (owner) Device check: open a routine or a live session with many exercises, open one in the middle, press back (header arrow, then again with the system back gesture): that exercise is in view near the upper third. Walk with the arrows to another exercise, press back: that one is in view. Add an exercise, press back: the end of the list shows.
- Mutation pass 2026-11-10: 23 mutants of the helper (7), routine editor (8) and session screen (8). First pass: R1 (routine list without the cache extent), S1 (rolling list without it) and S7 (no rebuild after reveal) survived because the fixtures could not see them: three block cards of ten rows were all inside the default build range, the rolling fixture was one card, and `pumpAndSettle` let a timer rebuild the screen. Fixed by six blocks of four in both fixtures and a test that pumps two frames with no time passing. All three were then killed.
- Survivors by design: R8 and S8 (`if (!_rowFocus.reveal()) _scrollListToBottom();` reduced to `_rowFocus.reveal();`). The fallback runs only when the focused row is missing, which a screen cannot produce (an empty list has nothing to scroll). It is defence in depth, as the plan said; the helper's `reveal() == false` cases are pinned by S-13902.
- The P2 builder reported that a drag starting on a routine row never scrolls the outer list (nested `ReorderableListView`). The lead's probe (touch drag from a row: offset 0 to 270) shows it does; the builder's `scrollUntilVisible` stalled for another reason. The test now scrolls with the list's own controller, and the claim and its workaround are removed from the file. No product bug.
- Keying: the helper's `Builder` is keyed by row id. Without it an unkeyed row (the session tiles) lets Flutter reuse one element for the next row, so a removed row's registration would point at a live, different row. The routine editor also keys its items.
- Four old tests that pinned the bottom landing were deleted from `test/interaction_flow_test.dart` (D-9): their rows were six identical squats, so they could not tell "focus" from "bottom"; the routine twin `system back gesture returns to routine list view and scrolls to bottom` still passed after the change (it only asserted `offset > 0`), which is why it was weak.
- The full suite is clean now, which also clears the "one clean full run owed" note of plan 138.
