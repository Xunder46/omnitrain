# Plan 285 — The Wear effort-rating prompt screen and its wiring (series 283, unit c)

Series 283: 283a (committed `8cda033a`) the wrist reads the phone's settings; 283b (committed `c8f0d6e4`) the rating state; **283c = this plan** the prompt screen, the menu's End going through the rating state, and the shell showing the prompt. Closes plan 280's open item 3. Wrist only, `lib/watch/`. No wire, phone or schema change. Base commit: `.work/2026-11-21-285-wear-effort-rating-prompt/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

What a user sees on a Wear watch (matching the Apple wrist): when the phone's effort-rating setting is on (it reached the watch at a sync) and a workout that holds at least one logged effort is ended from the watch's menu (`End Session` then `Finish`), the watch shows one question screen alone — "How hard was this session?", the numbers 1 to 5 with "Very easy" and "Max effort" under the ends, a **Confirm** button that is greyed until a number is picked, and a small **Skip**. A tap on a number picks it; turning the rotary (or dragging) steps it (the first turn up picks 1, each further turn moves one number, it stops at the ends). Confirm sends the rating to the phone and shows the start screen; Skip shows the start screen and sends nothing (the phone still asks its own question). There is no menu and no back button on this screen: an answer or Skip is the only way past. If the watch is closed or killed on that screen, the question is asked again the next time the app opens. If the phone answers first, the question closes by itself. With the setting off, with nothing logged, or when the phone ended the session, nothing changes from today.

Acceptance: S-28501..S-28514 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/wear_menu_screen_test.dart`, `test/wear_app_test.dart`, `test/watch_menu_state_test.dart`, `test/wear_os_config_test.dart`, `test/wear_logging_layout_test.dart`, `test/watch_effort_rating_state_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; no new red in the full suite; Docs delta applied; PNGs of the screen at 227 and 192 dp looked at.

## Feature invariants

- The prompt is the owed question, alone: while `WatchEffortRatingState.isPromptOwed` the shell shows it instead of every other surface (Apple `ContentView.body`, `owedRating`), and it carries no other control than the five numbers, Confirm and Skip.
- All the decisions (owed rule, picking, Confirm, Skip, order) stay in `WatchEffortRatingState` (plan 284); the screen only binds to it.
- The screen fits 192 and 227 dp (plan 282's compact look rule) and never overflows.
- Shells and menus built without a rating state behave exactly as before (every existing test).

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28501 | New `WatchEffortRatingScreen` (`lib/watch/logging/watch_effort_rating_screen.dart`), a `StatefulWidget` over a `WatchEffortRatingState`: `ListenableBuilder` on the state; the whole body in a `FittedBox(scaleDown)` inside a `LayoutBuilder` (like plan 282's compact rows: it can never overflow); title (`state.title`), a row of the five numbers (selected = `FilledButton`, others `OutlinedButton`, 32x36 dp, shape at `OmniTheme.buttonUtilityRadius`), the two end labels, `Confirm` (`FilledButton`, null `onPressed` until `state.canConfirm`, 40 dp compact / `OmniTheme.buttonPrimaryHeight` large, shrink-wrapped tap target when compact) and `Skip` (`TextButton`, `WatchEffortRatingCopy.skipLabel`). Each number carries the semantic label `N of 5`. | Swift `WatchEffortRatingView.swift`; plan 282 D-28202; `watch_logging_screen.dart` `_compactRows` |
| D-28502 | Rotary: a `Listener(onPointerSignal)` for `PointerScrollEvent` and a `GestureDetector(onVerticalDragUpdate)` over the screen feed one `WatchRotaryTurn` (`lib/watch/widgets/watch_controls.dart`); `detentsFor(travel)` whole detents go to `state.step(detents)`. The direction is the logging surface's: a turn away from the wrist (negative `dy`) raises the number. | `watch_logging_screen.dart` `_turnField`; `WatchRotaryTurn` |
| D-28503 | `WatchMenuState` gains an optional `WatchEffortRatingState? rating`. `finish()` with work to save calls `rating.end()` when it is given, `engine.finishSession()` when it is not. `hasWorkToSave` is unchanged. `discard()` is unchanged (a discarded workout owes no rating). | `watch_menu_state.dart` `finish` (159-166); Swift `WatchMenuState.finish` (rating `end()`) |
| D-28504 | The shell: `WearApp` gains an optional `WatchEffortRatingState? rating`. `_menu` is built with it; `initState` adds a listener (`_ratingChanged`: `setState(_syncTicker)` when mounted), `dispose` removes it; `_boot` calls `await widget.rating?.restore()` after the engine restore (the engine must know the session rows to tell which prompts are answered); `_surface` returns `WatchEffortRatingScreen(state: rating)` first (after the `_ready` check) while `rating.isPromptOwed`. With `rating` null nothing changes. | `wear_app.dart` `_menu`, `initState`, `dispose`, `_boot`, `_surface`; Swift `ContentView.body` 515-517 |
| D-28505 | `wear_main.dart` builds the state (`WatchEffortRatingState(engine:, store:, preferences:)`) and passes it to `WearApp`. The QA harness `wear_menu_debug_main.dart` also applies a `preferences_down` with the setting on (`effortRatingPrompt: true`, `restPingSeconds: 0`) and passes the rating state, so End shows the prompt on the desktop; the harness guard (`S-28132`) stays green. | `wear_main.dart`; `wear_menu_debug_main.dart` |
| D-28506 | Not in scope: a prompt on top of an open pushed route (nutrition) at the moment a rating becomes owed (the menu closes itself after End, and a phone-ended session owes nothing); haptics; the accent colour; the swipe pager. | Apple D-3114 handles the menu; here End closes it |

## Input-reality checklist

1. **Writers.** The owed note: `WatchEffortRatingState.end()` (the menu's End) only. The answer: `confirm()`. Skip: in memory. The phone's own answer: a snapshot entry the engine stores; the shell's frame handler already redraws.
2. **Lifecycle.** Owed then killed on the prompt: restore at launch (S-28510); owed then the phone answers: the shell redraws on the frame (S-28511); owed with the app foregrounded for hours: no clock involved; a new session cannot start while the prompt is up (the start surface is not shown).
3. **Settings changing while open.** The setting is read at End only.
4. **Time.** None on this screen.
5. **Load.** One `ListenableBuilder`; the owed getters read `hasEffortRating` for a handful of notes per rebuild.
6. **Words.** The copy is the contract's; "Confirm" and "Skip" are Apple's words (`WatchEffortRatingView`). Old wording found by grep: `has no effort-rating prompt either` and the Apple-hosts-more line in `docs/wear_os_app.md`, and `D-28107` (no prompt) in `test/wear_menu_screen_test.dart`/`watch_menu_state_test.dart` headers; their tests keep a rating-less menu, so they stay true.
7. **Competition.** The screen replaces the whole surface: no `Menu`, no bottom button of the shell.

## Scenarios

`test/wear_effort_rating_screen_test.dart` (new): the harness is copied from `test/wear_logging_layout_test.dart` plus a `WatchPhonePreferences` and a `WatchEffortRatingState` wired into the shell.

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28501 | setting on (a `preferences_down` applied), a running session with one logged set; the menu's `End Session` then `Finish` | the question screen shows: the title, numbers 1..5, `Very easy`, `Max effort`, `Confirm` (disabled), `Skip`; no `Menu` button; the session is completed | End bypasses the rating state, or the shell ignores it |
| S-28502 | the same with the setting off; and with the setting on but nothing logged (only End after a phone clock)... use no logged set: `End Session` asks the discard question and discards | the start surface shows, no prompt | the prompt appears when nothing is owed |
| S-28503 | S-28501's screen: tap `4`, `Confirm` | the engine holds `rating-<id>` with `rating` 4 and one `observations_up` carrying it; the start surface shows | Confirm does not record, or the shell stays on the prompt |
| S-28504 | tap `2`, `Skip` | start surface; no `effort_rating` row; the `rating_prompt` note still stored | Skip records or loses the note |
| S-28505 | on the prompt, deliver rotary scrolls over it: `-32` (one detent up) from nothing | `1` becomes the selected number (its button is the filled one) and `Confirm` is enabled; two more `-32` -> 3; a `+32` from nothing on a fresh screen picks nothing | the rotary is not wired, or it points the wrong way |
| S-28506 | a vertical drag of -40 points over the screen from nothing | the lowest number is picked (the drag feeds the same turn counter) | only the scroll event is wired |
| S-28507 | the prompt at 227x227 and at 192x192 | `takeException()` null; `Confirm` and `Skip` rects inside the view; every number button inside the view | the screen overflows a watch |
| S-28508 | `Confirm` before any pick | its `onPressed` is null; tapping it records nothing | Confirm is enabled without a pick |
| S-28509 | the semantic labels of the five numbers | `1 of 5` .. `5 of 5`, the picked one `selected` | the numbers are unnamed for a screen reader |
| S-28510 | owed (End), the shell torn down and a NEW shell over the same store, `restore()` run by `_boot` | the prompt shows at launch before the start surface | `_boot` forgets `rating.restore()` |
| S-28511 | the prompt showing; the phone's `session_snapshot` carrying `rating-<id>` is received | the prompt closes: the start surface shows | the shell does not redraw on the rating change |
| S-28512 | a shell built WITHOUT a rating state: the same End | start surface, no prompt (today's behaviour) | the new parameter is required, or End needs it |
| S-28513 | `WatchMenuState(rating: r).finish()` (in `test/watch_menu_state_test.dart`'s style, plain `test()`): with setting on and a logged set; with the setting off; without the parameter | the first leaves a prompt owed (`r.isPromptOwed`); the other two leave none; all three complete the session | the menu bypasses `end()` |
| S-28514 | `WatchMenuState(rating: r).discard()` with the setting on and a logged set | session abandoned, no prompt owed | Discard owes a rating |

## Phases

Every builder brief opens with "Never run the full `flutter test`" and "write the report FIRST as a skeleton". Serial.

1. **P1 — screen, menu End, shell, entry points** (`crew-builder-watch`; scope `lib/watch/logging/watch_effort_rating_screen.dart`, `lib/watch/logging/watch_menu_state.dart`, `lib/watch/app/wear_app.dart`, `lib/watch/wear_main.dart`, `lib/watch/debug/wear_menu_debug_main.dart`). Exact code in the brief. About 230 lines.
2. **P2 — tests** (`crew-builder-watch`; scope `test/wear_effort_rating_screen_test.dart`). S-28501..S-28514.
3. **P3 — docs** (`crew-docs-keeper`, no test run).
4. **Lead:** mutation pass, PNG look at 227/192, full suite.

Predicted production code about 230 lines in 5 files, one track: inside the budget.

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | has no effort-rating prompt either — that is plan 280's open item 3. | ends through the effort-rating state when the shell wires one (D-28503). | S-28513 |
| docs/wear_os_app.md | REMOVED | the effort-rating prompt, | - | S-28501 |
| docs/wear_os_app.md | MODIFIED | nothing on the Wear screen asks for it yet | the Wear screen asks for it after End and at launch | S-28501 |
| docs/wear_os_app.md | ADDED | - | ## The effort-rating prompt | S-28503 |
| docs/wear_os_app.md | ADDED | - | 7. (owner) with a paired phone whose effort-rating setting is on | S-28501 |

Stale-term sweep: `grep -rIn "effort-rating prompt" docs | grep -v "docs/plans\|docs/history\|docs/releases"` hits `docs/wear_os_app.md` 134 and 376 (rows above) and unrelated Apple/phone pages that stay; plan 280's open item 3 in its plan file is a plan record (the keeper adds one line "built by plan 285").

## Assumption Log

- `WatchRotaryTurn.detentsFor(travel)` raises on negative travel (`_pending - travel`), verified in `watch_controls.dart`; a `PointerScrollEvent` delivered through `tester.binding.handlePointerEvent`, as `S-28205` in `test/wear_logging_layout_test.dart` does, reaches the `Listener`.
- The shell's frame handler (`_onFrame`) already runs `setState` after `orchestrator.receive`, so the phone's snapshot closes the prompt without a new listener; the rating listener covers `confirm`, `skip` and `end`.
- Closing the menu after End is the existing `_closeToStart` path (plan 281); the shell then sees `isPromptOwed` on its rebuild.

## Progress

- [x] P1 production
- [x] P2 tests
- [x] P3 docs
- [x] Mutation pass, PNG look, full suite
