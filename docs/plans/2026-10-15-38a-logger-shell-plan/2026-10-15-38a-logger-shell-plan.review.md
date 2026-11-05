# Review: plan 38a (logger shell) · P1+P2+P3+D · base 80928669..working tree

Verdict: APPROVE
Counts: blocker 0 · major 0 · minor 2 · tests: +4787 ~1 all passed (this run)
Diff vs Predicted Files: conforms — `pubspec.yaml` (version `1.0.3+18`→`+19`) is outside the
brief's path list but is the unrelated change the plan header declares pre-existing ("never touch it").

Full suite this run (gateway `test`, 2026-10-15 19:24): `+4787 ~1: All tests passed!`
(lead's end-of-build count was `+4784 ~1`; delta is run-to-run, zero failures either way).

## Question table

| # | question | verdict | evidence |
|---|---|---|---|
| 1 | Lock (D-5): any remaining path that changes a logged entry's values live? | OK | `set`: `workout_session_detail_view.dart:220-222` `isLoggedNow = !widget.editMode && _isSetLogged(...)`, passed to both editors (`:233`, `:243`). `timed` live: duration editor `isReadOnly: true, onTap: null` (`:343-344`); weight section `isReadOnly: !widget.editMode && _isSetLogged(...)` (`:388-392`). `round` live: `isReadOnly: isFinished` / `onTap: isFinished ? null : dialog` (`:532-533`); a logged round is `RoundState.finished` (`workout_session_screen.dart:768-770`) and `isFinished` includes it (`detail_view:447-449`), so logged ⇒ locked. `drill` live: duration `isReadOnly: true, onTap: null` (`:681-682`); weight section locked (`:721-726`). The collapsed weight section cannot expand while locked (`:124` `onPressed: isReadOnly && !isExpanded ? null : …`). Centre control shows `LOGGED` when logged (`:866`), so no Start/Resume/Log button renders on a logged entry; the play/pause glyphs in the timed/round/drill branches are plain `Icon`s, not tappable. No remaining path found. |
| 2 | Delete (D-7): focus validity when the deleted index is below the focused set | OK (asked scenario) / MINOR (general case) | `workout_session_screen.dart:1311-1391` `_deleteSetAt`: after `deleteEntry` + `_loadExercises`, `:1390-1392` clamps `_currentSet` to `entries.length - 1` (old count − 1 = new count). Asked scenario (3 sets, focus set 3, set 2 last unlogged → target index 1): newCount 2, `_currentSet` 3 → clamped to 2 = old set 3, which is now `Set 2 of 2` — the same logical set the user was reading. `_currentSet` stays in range in every below-focus case. MINOR: when focus is *not* the last set, no decrement compensates for the removed index (see Findings 1). |
| 3 | Advance (D-6): other `_logSet` callers; `_nextUnloggedSetAfter` bound; early return reachable? | OK | Sole caller of the screen's `_logSet` is the Log button (`detail_view:1007`); `lib/watch/debug/watch_session_debug_surface.dart:214` is a different class's own `_logSet` that appends an engine observation. `_nextUnloggedSetAfter` (`screen:797-805`) loops `i` from `_currentSet` to `entryCount - 1` and returns `i + 1 ≤ entryCount` — never above the count. The already-logged early return (`screen:819-834`) is not reachable through the button: `_loggedSetKeys` is populated only from `_isSetLogged` (`:597`) or the log flow that records the matching rest (`:961`), and the Log button is hidden whenever `_isSetLogged` is true (`detail_view:827,866`) — defensive dead code, exactly as plan D-6 states. |
| 4 | Docs: Lock/Auto-Advance/Stepper Remove paragraphs; widget-catalog entries | OK | `docs/modality_based_exercise_ui.md:209-243`: Lock Rule matches Q1 (live locked, editMode unlocked, `LOGGED` kept); Auto-Advance Rule matches `_nextUnloggedSetAfter` + next-exercise fallback + stay-on-last (`screen:982-999`); Stepper Remove Rule matches `_deleteLastUnloggedSet` (`screen:1404-1420`: last unlogged, else last set) and `_deleteSetAt`'s two confirmations (`:1330-1352` `Delete logged …?`, `:1322-1341` `Remove Exercise?` — the `entries.length == 1` branch runs before the logged check). Every test the paragraphs name exists (grepped `test/logger_shell_screen_test.dart`: S-4210/4214/4215×3/4216×3/4217×3/4220×5/4221/4223/4230/4231/4232/4224 all present). `docs/widget_catalog/session_widgets.md:59-137`: the three entries match the constructors, props, keys (`set-segment-$i`, `logged-values-line`, `set-count-remove`, `set-count-add`), tooltips and the `loggedValuesText` helper exactly as implemented. No false claim found. |
| 5 | Standards: do the three new widgets break a written rule? | OK | `docs/design_system.md:211` "tap areas meet the platform minimum (`kMinInteractiveDimension`)": segment tap area `SizedBox(height: 48)` (`set_segment_bar.dart:88`), stepper `minimumSize: const Size(48, 48)` (`set_count_stepper.dart:70`). `design_system.md:621-622` "Every `IconButton` carries a tooltip; every button sets its `shape` explicitly": stepper tooltips `Remove set`/`Remove exercise`/`Add set`/`Max 12 entries` (`set_count_stepper.dart:76,100-103`) and `shape: const CircleBorder()` (`:71`). S-2604 no raw colours: all three widgets colour only from `Theme.of(context).colorScheme` / `OmniTheme.colors` (`set_segment_bar.dart:66,94-101`; `set_count_stepper.dart:66-69`; `logged_values_line.dart:47`). Text styles from the theme: `titleMedium`/`labelSmall` (`set_count_stepper.dart:85,88`), `bodyMedium` (`logged_values_line.dart:46`). No rule broken. |

## Findings

1. [MINOR] `lib/features/session/workout_session_screen.dart:1388-1392` — after `_deleteSetAt` removes an
   index *below* the focused set while the focused set is not the last, `_currentSet` is not decremented, so
   focus lands one logical set later than the one the user was reading. Example: 3 sets, focus set 2, sets 2–3
   logged and set 1 the last unlogged → `−` deletes set 1; newCount 2, `_currentSet` 2 is not > 2, so the
   screen shows `Set 2 of 2` = old set 3, while old set 2 (the set the user was on) is now `Set 1 of 2`.
   No data loss and no out-of-range index; the asked scenario (focus on the last set) is handled correctly by
   the clamp. Fix: in the final `setState` of `_deleteSetAt`, before the clamp, `if (index < _currentSet - 1) {
   _currentSet--; }`. Guard: a `logger_shell_screen_test.dart` case — focus set 2 of 3 with sets 2–3 logged,
   tap `set-count-remove`, expect `Set 1 of 2` (today it shows `Set 2 of 2`).
2. [MINOR] `docs/design_system.md:484-485` — FI-3/T-1 says "the three widgets are registered in the
   `docs/design_system.md` shared-pieces table", but the diff adds rows only for `SetSegmentBar` and
   `SetCountStepper`; `LoggedValuesLine` has no row, so a hand-built copy of the logged line elsewhere in the
   series would not be named by the table. The plan's own Phase D item 3 names only the two, so the docs
   keeper followed the plan; the invariant text and the table disagree. Fix: add a `LoggedValuesLine` row to
   the shared-pieces table (or amend FI-3 to two pieces). Unguarded (no scan counts hand-built logged lines).

## Assumption Log rulings

- (none in the plan — nothing to rule on)

## Scenario coverage

- S-4201..S-4204 → `test/set_shell_widgets_test.dart` (11 tests, all present, green)
- S-4210..S-4214, S-4215×4, S-4216×2, S-4217×3, S-4220×5, S-4221, S-4222, S-4223, S-4224, S-4230, S-4231, S-4232, S-4233 → `test/logger_shell_screen_test.dart` (28 tests, all present, green)
- S-015/S-016 migrations, dot-reader migrations → `test/session_toolbar_rework_test.dart`, `test/resistance_emphasis_redesign_test.dart`, `test/sports_emphasis_redesign_test.dart` (green in the full run)
- Full suite this run: `+4787 ~1: All tests passed!`
