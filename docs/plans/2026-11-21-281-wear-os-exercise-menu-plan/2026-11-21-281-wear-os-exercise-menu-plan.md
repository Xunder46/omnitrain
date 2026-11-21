# Plan 281 — The Wear OS exercise menu

Owner request (2026-11-21), open item 1 of plan 280: "plan the exercise menu as the next PR". The stopgap `End` button under the Wear logging surface is replaced by the Apple wrist's menu. Owner answers (2026-11-21): match Apple with **no wrist-side remove-exercise** (the Apple menu has none; removal only arrives from the phone); **include the exercise rows** (jump to an exercise: Wear has no pager yet); the menu opens from a **bottom `Menu` button** that replaces `End` and also appears on the rest surface.
Wrist only (`lib/watch/`). No wire, phone, storage or schema change. Base commit: `.work/2026-11-21-281-wear-os-exercise-menu/base.txt`. Analyze baseline: 174 issues, 0 errors.

## Goal and acceptance

On the Wear wrist, with a session running, the logging surface and the rest surface each show a `Menu` button under the main control (`Log` / `Next`); the stopgap `End` is gone. `Menu` opens a full-screen menu holding, in this order:

1. One row per exercise of the session, in ladder order: the exercise name, plus `N logged` underneath when N is above zero (never `0 logged`); the current exercise's row is the prominent one. Tapping a row switches to that exercise and closes the menu. While a hold, round or timed effort clock is running the rows are disabled and the caption `An effort is running` shows; a running **rest** never disables them.
2. `Add Exercise`: opens the exercise list; picking one appends it at the end of the session and keeps the user on the exercise they were on. Never disabled.
3. `End Session`: with at least one logged effort asks `Finish Workout?` (`This action will save and close the workout session.`, `Cancel` / `Finish`) and then finishes; with none, asks the discard question instead (below). Never disabled.
4. `Discard Session` (red): asks `Discard session?` (`This will permanently delete this session and all its data. You will return to the start screen.`, `Cancel` / `Discard`), then abandons the session. Logged entries stay in history. Never disabled.

There is no remove control anywhere. The menu closes by system back, a successful jump, Finish or Discard, and by itself when the session stops being active (the phone ended it). After Finish or Discard the start surface shows.

Acceptance: S-28101..S-28131 green and each guard red without the change; `flutter analyze` at most 174 issues, 0 errors; `test/wear_app_test.dart` (S-28021 rewritten), `test/watch_session_start_test.dart`, `test/watch_session_engine_test.dart`, `test/ui_standards_contract_test.dart`, `test/docs_indexing_contract_test.dart` green; no new red in the full suite; Docs delta applied; the macOS desktop harness opens the menu on a 227x227 window (D-28111).

## Feature invariants

- The wrist's engine stays append-only: the menu writes no session structure of its own except `insertExercise` (add) and a position move (jump); it never removes or edits an exercise or an entry (D-28102).
- A Wear deviation from Apple is a plan decision, never silent: no effort-rating prompt (D-28107), no wrist-started work clock to log on End (D-28106).
- Copy is the owner's words, copied from `WatchMenuCopy` (`WatchMenu.swift`); the Dart constants are named like the Swift ones.
- All new files are in `lib/watch/`; nothing in `lib/state`, `lib/features` or the phone transport changes.

## Decision Ledger

| ID | Decision | Backed by |
|---|---|---|
| D-28101 | The `Menu` button is a bottom `TextButton` that replaces the stopgap `End` on the logging surface and is added under `Next` on the rest surface. `WearApp.endLabel` is removed; `WearApp.menuLabel = 'Menu'` replaces it. Owner answer 2026-11-21. | `wear_app.dart` `_surface`, `WearApp.endLabel`; Apple `ContentView.swift` toolbar `list.bullet` (rest surface ~532, logging ~658) |
| D-28102 | The menu's content is the Apple menu minus nothing and plus nothing: exercise rows, lock caption, `Add Exercise`, `End Session`, `Discard Session`. **No wrist-side remove**: the Apple menu has none (`testS1108TheMenuSourceNamesNoRestEditOrDelete` greps the source for `removeExercise`); a phone removal is applied by `_removeSlotFromChange` as today. Owner answer 2026-11-21. | `WatchMenu.swift`, `WatchMenuView.swift`; `watch_session_engine.dart` `_removeSlotFromChange` |
| D-28103 | The logic is a plain Dart class `WatchMenuState` (new file `lib/watch/logging/watch_menu_state.dart`) mirroring `WatchMenuState` in `WatchMenu.swift`: `rows`, `isLocked`, `hasLoggedEfforts`, `hasWorkToSave`, `jump(slotId)`, `addExercise(exercise)`, `finish()`, `discard()`. The screen is `WatchMenuScreen` (new file `lib/watch/logging/watch_menu_screen.dart`). Technical call: logic in a testable class, view thin. | `WatchMenu.swift` `WatchMenuState`; `WatchLoggingState` precedent (state class + screen) |
| D-28104 | The engine gains `selectExercise(String slotId)`: finds the slot, moves `currentExerciseIndex` to it and emits the `exercise_advanced` lifecycle through `_transitionTo`, exactly as `advanceExercise` does; an unknown slot returns null and changes nothing. The start paths gain `addExerciseToEnd(exercise)`: `insertExercise(slot, moveTo: false)` with the slot id from `_availableSlotId`; appended last, position kept (an empty session lands on the new slot: `_positionAfterInsert` `wasEmpty`). `addExerciseToSession` (moves to the pick) is untouched: the start picker keeps using it. | Swift `WatchSessionEngine.selectExercise(slotId:)` (`WatchSessionEngine.swift` ~433); `watch_session_engine.dart` `advanceExercise` ~353, `insertExercise` ~405, `_positionAfterInsert` ~1464; `WatchStartPaths.addExerciseToEnd` (Swift ~912); `testS3612AddExerciseAppendsAtTheEndAndKeepsThePosition` |
| D-28105 | `isLocked` is true while any of the `elapsed`, `hold` or `round` timers is not stopped, read with `engine.timerFor(kind)` and `WatchTimerRecord.state != WatchTimerState.stopped`; a running `rest` never locks. Only the jump rows obey the lock. | `WatchMenu.swift` `isLocked` ~231; `watch_session_engine.dart` `timerFor` ~237; `WatchTimerKind`, `WatchTimerState` (`watch_records.dart` 30-50) |
| D-28106 | `hasLoggedEfforts` counts the current session's **projected** `engine.entries` whose `kind` is in `WatchObservationKind.efforts` (a rest, water or food entry never counts; an entry the phone deleted does not count). `hasWorkToSave` = `hasLoggedEfforts` **or** a work clock is running (`isLocked`). Apple logs a running clock on End first; the Wear logging screen cannot start a work clock of its own (it starts only `rest` and the `round` follow-on, `watch_logging_state.dart` ~731), so a clock that is running was adopted from the phone: End asks the Finish question and finishes, which stops every timer; the clock is **not** logged by the wrist (deviation, documented). Reason for counting the clock: a wrist Discard sends an `abandoned` lifecycle that discards the phone's copy. | `WatchMenu.swift` `finish()` ~261, `hasLoggedEfforts` ~286; `watch_session_engine.dart` `entries` ~246; `WatchObservationKind.efforts` (`watch_records.dart` 95); `watch_logging_state.dart` `_startFollowOnTimer` |
| D-28107 | No effort-rating prompt: End after the Finish question calls `engine.finishSession()` directly. The prompt is plan 280 open item 3. | `WatchEffortRating.swift` `end()` ~167 (no Dart counterpart); `wear_app.dart` header |
| D-28108 | `Add Exercise` reuses `WatchExercisePickerScreen`; it gains an optional `keepPosition` flag (default false). With it true a pick calls `paths.addExerciseToEnd`, pops, and calls `onExerciseAdded` as today. The start screen's use is unchanged. | `watch_exercise_picker.dart` `_add` ~95; `testS3617TheMenuAddsFromItsOwnListNotTheStartPicker` (Apple adds from its own list, keeping position) |
| D-28109 | The menu is a pushed `MaterialPageRoute` over the shell (as the nutrition screen is). It refreshes itself once a second while open (its own `Timer.periodic`, cancelled on dispose) so the lock caption and a phone-ended session are noticed; when `engine.session` is no longer active it pops itself. The shell closes the menu after Finish and Discard by popping to the first route. | `wear_app.dart` `_openNutrition`, `_syncTicker`; Apple `ContentView.swift` ~602 (`if status != active { showingMenu = false }`) |
| D-28110 | The menu opens on the rest surface too and a running rest keeps running through a jump or an add (Apple: `testS3102AAddingAnExerciseDuringARestKeepsTheRestRunning`, `testS1307ARunningRestDoesNotLockTheMenu`). | `WatchRestScreen`, `WatchLoggingState.isResting` |
| D-28111 | A new QA harness `lib/watch/debug/wear_menu_debug_main.dart` (header says `debug entry point`) runs `WearApp` over an in-memory store with a no-op radio and a seeded running session of three exercises, so the owner can see and click the menu in a macOS desktop window. It is not the production entry point and no production file imports it. | `lib/watch/debug/watch_start_debug_main.dart` composition; `test/wear_os_config_test.dart` S-28034 |
| D-28112 | Owner checks for this PR go in `docs/wear_os_app.md` (a "Checks on a watch" list), **not** in `docs/watch-app-setup-and-qa.md`, which is 56,130 bytes, above the 52 KB split band. The QA doc is edited only to shrink the two sentences that name the stopgap. | `wc -c docs/watch-app-setup-and-qa.md` |

Added during the build (2026-11-21), from rendering the surfaces at 227x227 and 192x192 dp with a throwaway widget probe and from running the macOS harness:

| ID | Decision | Backed by |
|---|---|---|
| D-28113 | The Finish and Discard questions are a **full-screen scrollable page** (`_ConfirmScreen`, `Dialog.fullscreen`), not an `AlertDialog`: the stock dialog cut its body and buttons off at 227 dp and was unreadable at 192 dp in the render. The destructive action (Discard) is drawn in the theme's error colour. | throwaway render at 227 and 192 dp; `watch_menu_screen.dart` `_ConfirmScreen` |
| D-28114 | The shell's `Navigator` is reached through a `GlobalKey<NavigatorState>` on its own `MaterialApp`, not `Navigator.of(context)`: `WearAppState.context` sits above the `MaterialApp` it builds, so `Navigator.of(context)` has no navigator. This also repairs the nutrition push (`_openNutrition`), which used the same call and could not open. `WearApp` takes an optional `navigatorKey` so the desktop harness can offer Back and Esc. | `wear_app.dart` `_openMenu`, `_openNutrition`, `navigatorKey`; the S-28122 test that opens the menu through it |
| D-28115 | **Known limit, not fixed here:** the Wear logging surface's own layout does not fit a 227 dp screen (overflow 25 px) or a 192 dp one (60 px) with the bottom button under it. The button is the same height as the `End` it replaced, so the menu did not cause it; fixing it is a layout pass of its own (plan 280 open items did not list it). The menu itself fits both sizes (rows scroll). | throwaway render at 227 and 192 dp; macOS harness run (`RenderFlex overflowed by 1.00 pixels` in `watch_logging_screen.dart`) |
| D-28116 | The shell's one-second ticker is brought up when the launch restore finds a session already active (`_boot` calls `_syncTicker` with `_ready = true`). Before, only a frame, a started session, a rest end or a menu action started it, so a workout restored after the app was killed did not tick until one of those happened. `WearAppState.isTicking` (`@visibleForTesting`) lets a test read it. Found while proving the `_menuChanged` ticker guard (S-28136). | `wear_app.dart` `_boot`, `isTicking`; S-28136 premise line |

## Input-reality checklist

1. **Writers.** The ladder and current index: the engine (`insertExercise`, `selectExercise`, `advanceExercise`), the phone (`exercise_push`, `structure_change` via `_ladderAfter`). Work clocks: adopted from the phone (`_adoptTimers`) or the wrist's own `round` follow-on. Logged efforts: the wrist's `log()` and the phone's deletions/corrections (`engine.entries` projects both), so `hasLoggedEfforts` reads `entries`, never raw `observations`.
2. **Lifecycle.** A phone-started session adopted by the wrist (no wrist log), an unfinished session, a slot the phone removed while the menu is open (a row vanishes; a tapped stale row returns false and changes nothing, S-28114), a phone-ended session while the menu is open (S-28129).
3. **Settings.** None change the menu. Units appear only inside the logging fields, not here.
4. **Time.** A work clock that finished on the phone while the menu is open clears the lock on the next 1 s refresh (S-28127b).
5. **Cost.** `entries` is rebuilt on each read: the menu reads it once per refresh, not once per row.
6. **Words.** Old wording found by grep: `stopgap End`, `WearApp.endLabel`, `A stopgap End`, `the exercise menu (a`, in `docs/wear_os_app.md` and `docs/watch-app-setup-and-qa.md`, and `S-28021`/`S-28022` in `test/wear_app_test.dart` (the Docs delta below).
7. **Competition.** The `Menu` button and `Log`/`Next` share the bottom of a round screen; layout is measured at 192x192 and 227x227 dp with a throwaway probe (checklist (o)), then seen on the macOS harness.

## Scenarios

Phase 1 — engine and start paths (`test/watch_session_menu_engine_test.dart`, new):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28101 | active session, 3 slots `sx-a, sx-b, sx-c`, index 0; `selectExercise('sx-c')` | returns the row with index 2; exactly one `session_lifecycle` frame with state `exercise_advanced` and `exerciseIndex` 2 | the method does not exist (D-28104) |
| S-28102 | same session; `selectExercise('gone')` | returns null; index 0; no frame emitted | an unknown slot moves the user or emits |
| S-28103 | active session, 2 slots, index 0; `paths.addExerciseToEnd(<a third exercise>)` | 3 slots, the new one last, index still 0, one `session_snapshot` with `revision` + 1 | the add used `addExerciseToSession` (`moveTo: true`) and jumped to the new exercise |
| S-28104 | an active free workout with no exercise; `addExerciseToEnd(x)` | 1 slot and index 0 (the new slot is current) | an empty session is left without a current exercise |
| S-28105 | a session already holding exercise `x`; `addExerciseToEnd(x)` again | 2 slots with different `sessionExerciseId` (the `-2` suffix rule), the first slot's id unchanged | a second pick of one exercise is swallowed as a duplicate |

Phase 2 — menu logic (`test/watch_menu_state_test.dart`, new; plain `test()`, Mock-style in-memory store):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28110 | 3 slots, index 1, two `set` entries logged on slot 1 | `rows` has 3 entries in ladder order; row 1 `isCurrent`; `countLabel` is `2 logged` for row 1 and null for rows 0 and 2 | rows are unordered, or a `0 logged` is shown (D-28102) |
| S-28111 | only a `rest`, a `water_glass`, a `nutrition_quick_log` and a `session_end` observation in the session | `hasLoggedEfforts` is false | non-effort entries count as work and End asks Finish on an empty session (D-28106) |
| S-28112a..c | a running `elapsed`, then a running `hold`, then a running `round` timer, each alone | `isLocked` true for each (three tests) | a work kind is left out of the list (arm per kind) |
| S-28112d | a running `rest` timer alone | `isLocked` false | rest locks the menu (D-28105, D-28110) |
| S-28112e | each work kind once running then stopped | `isLocked` false | a stopped clock still locks |
| S-28113 | locked session; `jump('sx-c')` | returns false, index unchanged; then stop the clock, `jump('sx-c')` returns true and index moves | the lock guard is missing, or it never releases |
| S-28114 | `jump('gone')` | returns false, nothing changes | a stale row moves the session |
| S-28115 | one logged `set`; `finish()` | session status `completed`, one `completed` lifecycle frame | End does not finish |
| S-28116 | nothing logged; `finish()` | session status `abandoned`, one `abandoned` lifecycle frame | an empty End is saved as a finished workout |
| S-28117 | two logged sets; `discard()` | status `abandoned`; the two entries are still in `entries` | Discard deletes history |
| S-28118a..c | (a) one logged effort; (b) nothing logged but a running `hold`; (c) nothing at all | `hasWorkToSave` true; true; false | a phone-clock-only session is offered Discard (D-28106) |
| S-28119 | a finished session; `addExercise(x)` | returns false, ladder unchanged | a stale menu grows a closed session |
| S-28119b | an entry the phone deleted: `engine.applyMessage(<structure_change envelope>)` whose payload `changes` carry `{'kind': 'delete_entry', 'entryId': ...}` — the shape `test/watch_session_engine_test.dart` `_structureChange` (line 115) builds and its test at 951 uses | `hasLoggedEfforts` false when it was the only effort | raw `observations` are read instead of `entries` (D-28106) |

Phase 3 — screens and shell (`test/wear_menu_screen_test.dart`, new, copying the `_Harness` block of `test/wear_app_test.dart`; `test/wear_app_test.dart` edited):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28120 | active session at the logging surface | `find.text('Menu')` one widget, `find.text('End')` none | `End` still there (D-28101); this rewrites S-28021 |
| S-28121 | active session with a running rest | `Menu` and `Next` both shown | the rest surface has no way to the menu (D-28110) |
| S-28122 | tap `Menu` | menu shows the 3 exercise names, `Add Exercise`, `End Session`, `Discard Session`; `find.textContaining('Remove')` finds nothing | a remove control sneaks in (D-28102) |
| S-28123 | one logged set; tap `End Session` | the `Finish Workout?` question shows; `Cancel` returns to the menu; `Finish` ends the session and the start surface shows | End skips the question or does not finish |
| S-28124 | nothing logged; tap `End Session` | the `Discard session?` question shows, not `Finish Workout?` | an empty End asks to finish |
| S-28125 | tap `Discard Session`; `Cancel`, then again and `Discard` | cancel changes nothing; discard abandons and the start surface shows | Discard acts without asking |
| S-28126 | tap the row of the third exercise | the menu closes and the logging surface names the third exercise | rows do not jump |
| S-28127 | a running `hold` timer | the caption `An effort is running` shows; tapping a row changes nothing; `Add Exercise`, `End Session`, `Discard Session` are enabled | the lock caption or the lock is missing; the lock covers too much |
| S-28127b | the lock case above, then the clock is stopped, `pump(1 s)` | the caption is gone and rows are enabled | the menu never refreshes |
| S-28128 | tap `Add Exercise`, pick an exercise | the menu returns/closes with 4 slots; the logging surface is on the same exercise as before | the add jumped to the new exercise (D-28108) |
| S-28129 | menu open; a `session_lifecycle` `completed` frame delivered through the transport | the menu is closed and the start surface shows | a menu over a dead session stays open (D-28109) |
| S-28130 | a running rest, tap `Menu`, add an exercise | the rest timer is still running | adding stops the rest (D-28110) |
| S-28131 | the start screen's free-workout picker (existing `watch_session_start_test.dart` "the exercise added mid-session becomes the one being logged") | unchanged: the pick still moves to the new exercise | `keepPosition` defaulted true (D-28108) |

Phase 1h — source guard (`test/wear_os_config_test.dart`, one test added):

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28132 | the harness file `lib/watch/debug/wear_menu_debug_main.dart` and every file under `lib/` | the harness exists and contains `debug entry point`; no file outside `lib/watch/debug` imports it | the harness is missing, or production code imports a QA entry point (D-28111) |

Appended by the architect (2026-11-21) — edges the seed misses, each produced by a real writer, all guarded in P3:

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28133 | menu open over 3 slots; the phone removes `sx-c` while it is open (`engine.applyMessage(<structure_change envelope>)` with `changes: [{'kind': 'remove_exercise', 'sessionExerciseId': 'sx-c'}]`, the writer `test/watch_session_engine_test.dart` `_structureChange` builds); then the menu's 1 s refresh pumps | the row of `sx-c` no longer shows; tapping the row widget the test pumped before the change leaves the index unchanged and emits no frame | a menu that never rebuilds shows a row whose slot is gone, and a tap on it advances the session to a slot that does not exist |
| S-28134 | the Add list open; the same exercise row tapped twice inside one frame (the double-tap `test/pr7_exercise_details_view_test.dart` "rapid Add taps pop the picker exactly once" pins on the phone picker) | exactly one slot added and exactly one pop: the menu shows one new slot, not two | `_add` adds per tap, so the second tap lands before the pop and the session grows two slots from one pick |
| S-28135 | menu open over a one-slot session; the phone removes the last exercise (same `structure_change` writer as S-28133); the refresh pumps | no exercise rows remain; the menu stays open with `Add Exercise`, `End Session`, `Discard Session`; tapping `End Session` raises the discard question, not `Finish Workout?` | the menu built its rows once, so a now-empty session shows a stale row and an End that asks to finish an empty workout |

Added during the build (2026-11-21) — each closes a mutant the lead's pass found alive, or a reviewer finding:

| S-n | fixture | expect | fails without |
|---|---|---|---|
| S-28123b | the Finish (and, as S-28125b, the Discard) question open; dismissed with no button | the session stays active, the menu stays, nothing is sent | a dismissed question counts as a yes (`answer ?? true`) |
| S-28123c | the Finish question open over a logged set | no `AlertDialog`; the page inside the dialog is as big as the app | the question reverts to the stock dialog that cut its buttons off at watch sizes (D-28113) |
| S-28129b | the Finish question open; the phone's `completed` frame arrives | the question page and the menu are both gone; the start surface shows | the menu pops only itself and leaves the question over a dead session |
| S-28131b | a session holding one exercise; the picker with its default flag; a pick (test `S-28131`), and with `keepPosition: true` (test `S-28131b`) | 2 slots, position on the pick; with the flag, position stays 0 | `keepPosition` defaults to true and the start screen's pick stops following the user |
| S-28134b | the Add list; the same row's `onPressed` called twice with no await between | exactly one slot added and the menu still open | no `_adding` guard: the second pick pops the menu under the list |
| S-28136 | a restored active session ticks; after End from the menu | `WearAppState.isTicking` true, then false | a finished workout leaves a one-second rebuild running on the idle start surface (D-28116) |
| S-28137 | the idle start surface; tap `Log food` | the nutrition screen opens, no exception | `Navigator.of(context)` from the shell's own context has no navigator (D-28114) |

## Phases

Every builder brief opens with "Never run the full `flutter test`" and carries "do not clear the capture between act and assert". Serial unless marked.

1. **P1 — engine and start paths** (`crew-builder-watch`; scope `lib/watch/session/watch_session_engine.dart`, `lib/watch/start/watch_session_start_paths.dart`, `test/watch_session_menu_engine_test.dart`). Items: `selectExercise`, `addExerciseToEnd`, S-28101..S-28105. Done: the new test file and `test/watch_session_start_test.dart`, `test/watch_session_engine_test.dart` green. Production about 40 lines. **Parallel with P1h** (disjoint scope).
1h. **P1h — desktop harness** (`crew-builder-watch`; scope `lib/watch/debug/wear_menu_debug_main.dart`, `test/wear_os_config_test.dart`). Item: D-28111, S-28132. Done: `flutter analyze` clean for the file and the config test green. About 80 lines.
2. **P2 — menu logic** (`crew-builder-watch`; scope `lib/watch/logging/watch_menu_state.dart`, `test/watch_menu_state_test.dart`). Needs P1. Items: S-28110..S-28119b. Production about 130 lines.
3. **P3 — screens, picker flag, shell** (`crew-builder-watch`; scope `lib/watch/logging/watch_menu_screen.dart`, `lib/watch/start/watch_exercise_picker.dart`, `lib/watch/app/wear_app.dart`, `test/wear_menu_screen_test.dart`, `test/wear_app_test.dart`). Needs P2. Production code goes in as exact text in the brief; the new screen test file is a **separate run** that starts from a copied helper block (checklist (z)). Items: D-28101, D-28108, D-28109, S-28120..S-28131, and the appended S-28133..S-28135 (above). About 230 lines.
4. **P4 — docs** (`crew-docs-keeper`, after the last test-adding run): the Docs delta rows. No tests run by the keeper (checklist (ap)).

Predicted production code about 480 lines, one track (the wrist client), four phases plus one parallel harness run: inside the budget.

### Predicted files and readers

| Phase | File | Change | Predicted lines |
|---|---|---|---|
| P1 | `lib/watch/session/watch_session_engine.dart` | edit | +14 (`selectExercise`) |
| P1 | `lib/watch/start/watch_session_start_paths.dart` | edit | +12 (`addExerciseToEnd`) |
| P1 | `test/watch_session_menu_engine_test.dart` | create | ~120 |
| P1h | `lib/watch/debug/wear_menu_debug_main.dart` | create | ~80 |
| P1h | `test/wear_os_config_test.dart` | edit | +20 (S-28132) |
| P2 | `lib/watch/logging/watch_menu_state.dart` | create | ~130 |
| P2 | `test/watch_menu_state_test.dart` | create | ~180 |
| P3 | `lib/watch/logging/watch_menu_screen.dart` | create | ~140 |
| P3 | `lib/watch/start/watch_exercise_picker.dart` | edit | +6 (`keepPosition`) |
| P3 | `lib/watch/app/wear_app.dart` | edit | +15 −12 (`Menu` replaces `End`, `menuLabel`, pop-to-start after Finish/Discard) |
| P3 | `test/wear_app_test.dart` | edit | ~12 rewritten (`endLabel` finds at 138, 159) |
| P3 | `test/wear_menu_screen_test.dart` | create | ~300 |
| P4 | `docs/wear_os_app.md` | edit | ~25 |
| P4 | `docs/watch-app-setup-and-qa.md` | edit | ~4 |

Readers — the test files that already pin what each phase touches (greps run 2026-11-21; builders run these):

- **P1.** `finishSession`: `test/watch_session_engine_test.dart` (22 calls), `test/watch_session_finish_test.dart` (1501, 1543), `test/watch_session_end_owed_test.dart` (616, 646), `test/watch_session_start_test.dart` (762), `test/watch_session_projection_test.dart` (1928), `test/live_mirroring_test.dart` (1312), `test/watch_reconciliation_cross_stack_test.dart` (392), `test/watch_logging_surfaces_test.dart` (682), `test/watch_sensor_recording_test.dart` (5 calls), `test/watch_session_auto_push_test.dart` (1307), `test/watch_timer_adoption_test.dart` (674), `test/watch_timer_release_test.dart` (1154), `test/watch_rest_surface_test.dart` (196), `test/rating_first_answer_push_test.dart` (203), `test/watch_second_session_same_exercise_repro_test.dart` (218), `test/watch_convergence_harness_test.dart`, `test/helpers/watch_replay_recorder.dart` (595, 597), `test/helpers/watch_pair_harness.dart`. `insertExercise`: `test/watch_session_engine_test.dart` (1849). `addExerciseToSession`: `test/watch_session_start_test.dart` (502, 554, 1281, 1285, 1308, 1309), `test/watch_second_session_same_exercise_repro_test.dart` (214, 223). (The phone-side `WorkoutState.addExerciseToSession` — 554 hits across 109 files — is not a reader of the wrist paths.)
- **P1h.** `WearApp(`: `test/wear_app_test.dart` (61), `test/wear_os_config_test.dart` (113); the S-28034 group at 107 pins the production entry point the new harness must not replace.
- **P2.** Nothing imports what P2 creates. The state reads `engine.entries` and `engine.timerFor`, pinned by `test/watch_session_engine_test.dart` (`delete_entry` at 964, 1900, 1945, 1993, 2044, 2088, 2149, 2224, 2288; `insertExercise` 1849) and `test/watch_session_projection_test.dart` (1580, 2335).
- **P3.** `WearApp(`: `test/wear_app_test.dart` (61) — its `WearApp.endLabel` finds at 138 and 159 are the lines this phase rewrites. `WatchExercisePickerScreen`: no type reference anywhere in `test/` (grep found none); the picker's flow is pinned by `test/watch_session_start_test.dart` "free workout opens the picker, which offers exactly the fallback list" (1425). The `addExerciseToSession` readers above also run here.
- **P4.** `test/docs_indexing_contract_test.dart` (73 lists `watch-app-setup-and-qa.md`), `test/rest_is_count_up_contract_test.dart` (46, 339), `test/ui_standards_contract_test.dart` (it excludes `lib/watch/`, so the phase's code never reaches it).

### Code pointers (current lines, read 2026-11-21)

**P1 — `watch_session_engine.dart` `advanceExercise` (signature line 353): the body `selectExercise` copies; its `lifecycle:` argument is line 363.**

```dart
  Future<WatchSessionRecord> advanceExercise() async {
    final session = _requireSession();
    final lastIndex = session.exercises.isEmpty
        ? 0
        : session.exercises.length - 1;
    return _transitionTo(
      currentExerciseIndex: (session.currentExerciseIndex + 1).clamp(
        0,
        lastIndex,
      ),
      lifecycle: WatchLifecycleState.exerciseAdvanced,
    );
```
(closing `}` at 365; the position rule P1's `addExerciseToEnd` relies on is `_positionAfterInsert`, line 1464: `moveTo || wasEmpty ? insertedAt : (currentIndex >= insertedAt ? currentIndex + 1 : currentIndex)`.)

**P1 — `watch_session_start_paths.dart` `addExerciseToSession` (signature line 219, doc 214-218): untouched by this plan; shown so `addExerciseToEnd` sits next to it, same slot id rule.**

```dart
  Future<WatchSessionRecord> addExerciseToSession(
    WatchCatalogExercise exercise, {
    int? atIndex,
  }) => _engine.insertExercise(
    exercise.toSlot(sessionExerciseId: _availableSlotId(exercise)),
    atIndex: atIndex,
    moveTo: true,
  );
```

**P2 — the two engine getters the menu state reads, both unchanged: `watch_session_engine.dart` line 237 and the projection head at 246 (deleted entries dropped at 249).**

```dart
  WatchTimerRecord? timerFor(String kind) => _newestTimer(kind: kind);
```
```dart
  List<WatchObservationRecord> get entries {
    final projected = <WatchObservationRecord>[
      for (final observation in observations)
        if (!_deletedEntryIds.contains(observation.entryId))
```

**P3 — `wear_app.dart` `_surface()` (declared at 202) logging branch, the `TextButton` (lines 215-226) that `Menu` replaces:**

```dart
          TextButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            onPressed: _finish,
            child: const Text(WearApp.endLabel),
```
(it sits inside `return Column(children: [Expanded(child: WatchLoggingScreen(state: _logging)), <this button>, ], );` at 212-228; the rest branch is at 210 and the start surface at 232 — both untouched.)

**P3 — `watch_exercise_picker.dart` `_add` (lines 96-101), the method that gains `keepPosition`:**

```dart
  Future<void> _add(BuildContext context, WatchCatalogExercise exercise) async {
    final session = await paths.addExerciseToSession(exercise);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    onExerciseAdded?.call(session);
  }
```

**P3 — `test/wear_app_test.dart` helper block the new screen test copies: `_Harness` at 39, its `app()` at 61, `_open` at 70 — copy lines 39-76 verbatim. First 12:**

```dart
class _Harness {
  _Harness()
    : store = InMemoryWatchSessionStore(),
      transport = WearWatchTransport(link: WatchLink()) {
    engine = WatchSessionEngine(store, onEmit: transport.send);
    paths = WatchSessionStartPaths(engine: engine, store: store);
    nutrition = WatchNutritionState(engine: engine, store: store);
    orchestrator = WatchSyncOrchestrator(
      transport: transport,
      paths: paths,
      engine: engine,
      nutrition: nutrition,
    );
```
(continue verbatim through `_open` at 70-76; the imports the copy needs are lines 14-27 of the same file, plus the `_methods`/`_events` channels and the `setUp`/`tearDown` mocks at 80-109 if the screen test delivers frames through the transport.)

## Docs delta

| Doc | Change | Old marker | New marker | Backed by |
|---|---|---|---|---|
| docs/wear_os_app.md | MODIFIED | A stopgap End | The Menu button under the logging surface | S-28120 |
| docs/wear_os_app.md | MODIFIED | control under the logging surface finishes the workout; it stands in for the | and the rest surface opens the exercise menu, the Apple wrist's menu without a remove control (D-28102). | S-28122 |
| docs/wear_os_app.md | REMOVED | Apple wrist's exercise menu until that menu is ported. | - | S-28120 |
| docs/wear_os_app.md | MODIFIED | menu, the effort-rating prompt, the personal-record banner, the water bar, the | the effort-rating prompt, the personal-record banner, the water bar, the | S-28122 |
| docs/wear_os_app.md | ADDED | - | ## The exercise menu | S-28122 |
| docs/wear_os_app.md | ADDED | - | End Session asks Finish Workout? only when a logged effort or a running work clock is there | S-28123 |
| docs/wear_os_app.md | ADDED | - | A clock the phone started is not logged by the wrist's End | S-28116 |
| docs/wear_os_app.md | ADDED | - | ## Checks on a watch | S-28132 |
| docs/wear_os_app.md | ADDED | - | The Finish and Discard questions are a full-screen page | S-28123 |
| docs/wear_os_app.md | ADDED | - | flutter run -d macos -t lib/watch/debug/wear_menu_debug_main.dart | S-28132 |
| docs/wear_os_app.md | ADDED | - | The logging surface does not yet fit a 192 dp or 227 dp screen | D-28115 |
| docs/watch-app-setup-and-qa.md | MODIFIED | the exercise menu (a | the exercise menu is on the Wear wrist; it does without | S-28122 |
| docs/watch-app-setup-and-qa.md | MODIFIED | stopgap End control finishes the workout), the effort-rating prompt, the | the effort-rating prompt, the | S-28120 |

Stale-term sweep (run by the lead at seed time, result copied here): `grep -rIn "stopgap\|endLabel\|exercise menu" docs | grep -v "docs/plans\|docs/history\|docs/releases"` hits only `docs/wear_os_app.md` 115-123 and `docs/watch-app-setup-and-qa.md` 256-258 (the rows above); the other `menu` hits describe the Apple menu and stay. Re-run by the architect 2026-11-21 (same pattern, ripgrep): the same four doc lines and nothing else — no new row needed. Each Old marker above is on one line of its doc today: `docs/wear_os_app.md` 115, 116, 117, 119; `docs/watch-app-setup-and-qa.md` 256, 257.

## Assumption Log

- Architect checks (2026-11-21), all five seed claims verified against the files; **no seeded entry was wrong, no new decision needed**:
  (a) `WatchSessionEngine.timerFor(String kind)` exists at `watch_session_engine.dart:237` and `WatchTimerRecord.state` is a derived getter at `watch_records.dart:471` (stopped if `stoppedAt`, paused if `pausedAt`, else running) — as D-28105 uses them.
  (b) `engine.entries` (246-266) drops `_deletedEntryIds` and applies corrections/space-merges — the projection D-28106 says. The engine call a test makes to delete an entry is `engine.applyMessage(<structure_change envelope>)` whose payload `changes` carry `{'kind': 'delete_entry', 'entryId': ...}` (helper `_structureChange` at `test/watch_session_engine_test.dart:115`, used by its test at 951); S-28119b's fixture now names it.
  (c) `advanceExercise` (353-365) ends in `_transitionTo(currentExerciseIndex: ..., lifecycle: WatchLifecycleState.exerciseAdvanced)` — exactly what D-28104 has `selectExercise` copy.
  (d) `_add` (96-101) is a private method on the `StatelessWidget` picker; an optional `keepPosition` (default false) leaves the start screen's constructor untouched, as D-28108 says.
  (e) grep `endLabel` over the repo returns only `lib/watch/app/wear_app.dart` (62, 226) and `test/wear_app_test.dart` (138, 159) — no third reference.
- The wrist picker has **no type reference** in `test/` (grep `WatchExercisePickerScreen` finds none); the only pin is the start-screen flow test "free workout opens the picker, which offers exactly the fallback list" (`test/watch_session_start_test.dart:1425`).
- S-28133, S-28134 and S-28135 appended (architect, 2026-11-21), all guarded in P3; no other scenario, decision or phase was touched.
- The Wear wrist cannot start a hold, elapsed or round work clock of its own except the `round` follow-on; the clocks it sees are adopted from the phone. Verified by `grep -rn "startTimer(" lib/watch` (two callers, both in `watch_logging_state.dart`). If a later PR lets the wrist start one, End must log it first (D-28106).
- The macOS desktop window runs `WearApp` with the plain Material theme and the real Roboto/system font; it shows layout and flow, not a round bezel or the watch's pixel density. Only a Wear emulator or a watch shows those (owner check).
- `WatchExercisePickerScreen` already lists the fallback exercises when the phone is unreachable (scout sheet `sheet-dart-wrist.md` Q2); the Add list on a paired wrist shows what `paths` holds, the same list as the start picker.

## Progress

- [x] P1 engine and start paths (5 tests green)
- [x] P1h desktop harness (S-28132 green; harness runs in a macOS window)
- [x] P2 menu logic (17 tests green)
- [x] P3a screen, picker flag, shell; P3b screen tests (13 tests green); P3c watch-sized confirmation, navigator seam, harness Back/Esc (D-28113, D-28114)
- [ ] P4 docs
- [ ] Lead mutation pass, review, full suite
