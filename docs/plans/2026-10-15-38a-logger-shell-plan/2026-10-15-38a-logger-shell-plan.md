# Plan 38a — Logger shell: set bar, logged line, locked logged sets, sets stepper, layout

Status: SEEDED by the lead. Base commit `80928669` (branch `claude_develop`; `pubspec.yaml` has an unrelated change: never touch it). Not authorised to commit: the owner commits; never push.
Series: `docs/plans/2026-10-15-38-logger-rework-series.md` (read its O-1..O-12 and T-1..T-4 first; they bind this plan). Owner scenario ids: `S-42xx`.

## Goal and acceptance

What a user sees on the exercise screen (`WorkoutSessionScreen` detail view), for every modality and in the session editor:

- A1. Under the header, one thin bar with one segment per set / interval / round / hold. Three looks: not logged, focused (the set on screen), logged. A set that is both logged and focused shows logged with the focus mark. Tapping a segment jumps to that set (the dots did the same).
- A2. The count text stays as today (`Set 1 of 3`, `Interval 1 of 3`, `Round 1 of 3` / `Period …`, `Hold 1 of 3`, same text style) and sits with the bar. The section name stays the small line under the exercise name in the header (unchanged).
- A3. One compact line under the bar lists the values of logged sets, in set order, joined by ` · `. Unlogged sets add nothing (no dash, no gap). Nothing logged: no text, but the line keeps its height so nothing jumps. Formats: reps exercise `10×60` (reps × weight in the user's unit, no trailing `.0`; weight 0 shows reps only: `12`); intervals and holds `m:ss` of the locked time (`0:42`); rounds `m:ss` of the time done.
- A4. In a live session a logged set cannot be edited: reps, weight and hold weight are read-only on it; the centre control keeps showing `LOGGED`. In the session editor (`editMode`) nothing is locked and its controls stay as today (navigation arrows only, screen-level Save).
- A5. After a log, focus moves to the next unlogged set after this one; if none is left in this exercise it goes to the next exercise (as today); on the last exercise it stays (as today). A set a watch logged does not move focus (S-3610, unchanged).
- A6. The `−  3  +` row beside the count text is gone. A small secondary control (label `SETS` / `INTERVALS` / `ROUNDS` or `PERIODS` / `HOLDS`, the count, `−`, `+`) sits in the body below the exercise's controls, away from the primary row. `+` adds a set; `−` removes the last unlogged set (the last set when every set is logged), with today's confirmations (logged set: `Delete logged …?`; only set left: `Remove Exercise?`). Tooltips `Add set`, `Remove set`, `Remove exercise` kept. Every tap target 48 dp or more (the glyphs may be smaller).
- A7. Layout: bar block at the top, the exercise's controls directly under it (top-aligned, not vertically centred), the sets stepper under them, the empty space below that; the rest strip, then the arrows-and-button row at the bottom exactly as today. The rest chip, its strip and its rules are untouched (O-8).
- A8. Unchanged: header, info/note actions, PR toast, Log/Start button logic, timers, `Previous` / `Next` arrows, persistence, the rest chip, list view, watch sync.
- A9. `flutter analyze` not above the baseline recorded at Phase 0 (0 errors); `flutter test` not below the current pass count minus tests this plan removes (list them in Progress); no allowlist entry added, no ratchet raised.

## Feature invariants (this plan only; project-wide rules stay in `docs/global_conventions.md`)

- FI-1 Units: the logged line formats weight through `UnitFormatter.formatWeightValue` only; kg stays canonical, converted at the display boundary (global_conventions "Units + canonical storage").
- FI-2 Theme tokens only: the three new widgets colour from `Theme.of(context).colorScheme` / `OmniTheme` (global_conventions "Theme tokens only"; ratchet in `test/palette_legibility_contract_test.dart`).
- FI-3 Shared UI pieces: the three widgets are registered in the `docs/design_system.md` shared-pieces table (T-1); no hand-built copy may appear elsewhere in the series.
- FI-4 Rest rule: logging still opens exactly one count-up rest; no rest record, ping or chip behaviour changes (O-8, global_conventions "Rest rule").
- FI-5 Touch targets ≥ 48 dp (T-3); tooltips `Add set` / `Remove set` / `Remove exercise` kept verbatim (T-4).
- FI-6 No data-model, repository or watch-wire change (T-2); the bar and line read only what `_exercises`, `getEntryRests`, timed instances and round instances already expose.

## Existing-functionality impact (searches run 2026-10-15, base `80928669`)

| Touched surface | What already reads it (search result) | Effect | Guarded by |
|---|---|---|---|
| `_buildSetProgress` / `_buildSetIndicator` (`workout_session_detail_view.dart:686-833`) | Callers: `workout_session_list_view.dart:834,840` only. `lib/features/routine/routine_setup_screen.dart:1407,1522` defines its own same-named methods (routine screen — untouched). Test dot readers: `resistance_emphasis_redesign_test.dart:164,280,302`, `sports_emphasis_redesign_test.dart:456`. | Deleted; bar replaces them | S-4223, S-4201, P2 migrations |
| `_deleteCurrentSet` (`workout_session_screen.dart:1295`) | Single caller `workout_session_detail_view.dart:721`, inside `_buildSetProgress` (deleted). No other caller in `lib/`. | Rename to `_deleteSetAt(index)` safe; `_deleteLastUnloggedSet` wraps it | S-4220, S-015/S-016 migrations |
| `_skippedSets` (`workout_session_screen.dart:123`) | Never written anywhere in `lib/`; sole reader `workout_session_detail_view.dart:800` (inside `_buildSetIndicator`). | Deletion safe (D-10) | S-4223 |
| Count text | Session-screen readers: `watch_live_refresh_screen_test.dart` (10 asserts), `session_toolbar_rework_test.dart` (15), `pr2_launch_quality_hotfix_test.dart` (15), `widget_test.dart:158+`. The `screen_widget_test.dart` count asserts (`:1381,:1592,:1771,:1808,:1879`) are all `RoutineSetupScreen` tests — unaffected. | Text kept verbatim, moves into the bar block; still exactly one `Text` | S-4210 + existing asserts |
| Logged-set inputs (D-5) | No test edits reps/weight after a `Log Set` tap (searched `screen_widget_test`, `resistance/timed/exercise_detail` emphasis, `in_session_pr_toast`, `interaction_flow`, `pr2`): pr2 S-003e (`:447`) edits an unlogged set; `in_session_pr_toast_test.dart:1040-1045` seeds via `updateEntryValue` before pump; `timed_emphasis_redesign_test.dart:317` reads the Weight-adjustment style in STOPPED state. | The lock breaks no existing test | S-4216, S-4217 |
| Rest chip / strip | `rest_timer_docked_strip_test.dart`, `unified_rest_overlay_test.dart`, `round_auto_expiry_test.dart`, `session_rest_closing_race_test.dart`, `screen_widget_test.dart:10101-10310` geometry tests | Untouched; must stay green with no edit | S-4222 |

## Decision Ledger

- D-1 `SetSegmentBar` (new, `lib/widgets/session/set_segment_bar.dart`): `StatelessWidget(count, focusedIndex, isLogged: bool Function(int), onTap: ValueChanged<int>)`. A `Row` of `Expanded` segments, 6 dp gap; each segment is an `InkWell`/`GestureDetector` with `HitTestBehavior.opaque` in a `SizedBox(height: 48)` whose painted bar is a `Container` 6 dp tall (focused 10 dp tall) with `BorderRadius.circular(3)`. Colours from `Theme.of(context).colorScheme` only: logged `primary`, focused-not-logged `primary` at 0.45 alpha plus a `primary` 1.5 dp border, unlogged `onSurface` at 0.2 alpha (the alpha the dots used). Keys `set-segment-$i`; each wrapped in `Semantics(label: 'Set $n of $count, logged|not logged|current', button: true)`. More than 12 segments never happens (`maxEntriesPerEffort` = 12, `lib/core/constants/workout_constants.dart:4`).
- D-2 `SetCountStepper` (new, `lib/widgets/session/set_count_stepper.dart`): `StatelessWidget(label, count, canAdd, removeIsExercise, onAdd, onRemove)`. A `Row`: `IconButton(Icons.remove or Icons.delete_outline when removeIsExercise)`, a `Column(count as titleMedium, label as labelSmall letterSpaced)`, `IconButton(Icons.add)`. Each `IconButton` has `tooltip` (`Remove set` / `Remove exercise` / `Add set`; disabled add: `Max 12 entries`, as today `workout_session_detail_view.dart:756-758`), `style` with `minimumSize: Size(48, 48)` and a `shape`, `iconSize: 20`, colour `onSurface` at 0.45 alpha. Keys `set-count-remove`, `set-count-add`.
- D-3 Logged line (new, `lib/widgets/session/logged_values_line.dart`): a pure function `String loggedValuesText(List<String?> perSet)` (null = unlogged; joins the non-null with ` · `) and `LoggedValuesLine(text)` = `SizedBox(height: 24)` with a centred one-line `Text` (`maxLines: 2` is not allowed: use `maxLines: 1, overflow: TextOverflow.ellipsis`, `bodyMedium`, `OmniTheme.colors.textSecondary`), key `logged-values-line`. 12 sets of `10×135` is about 100 characters; ellipsis is accepted.
- D-4 Per-set value text, built in `workout_session_detail_view.dart` as `String? _loggedValueText(effortId, index, effortKind, entry)`: null when `!_isSetLogged(...)`. `set`: reps from `entry['reps']`, weight kg from `entry['weight']`; weight text `UnitFormatter.formatWeightValue(kg, widget.settingsState)` (`lib/core/utils/unit_formatter.dart:69`, trims `.0`); `kg <= 0` → `'$reps'`, else `'$reps×$weightText'`. `timed` / `drill`: `OmniDateUtils.formatClock(secs * 1000)` of `_getTimedInstance(effortId, index)?.actualDurationSecs` (`lib/core/utils/date_utils.dart:177`). `round`: same with `_getRoundInstance(effortId, index)?.actualDurationSecs`. A logged set whose time is missing or 0 gives `0:00`. Cache freshness (verified): live `_updateMetricValue` persists then `await _loadExercises()` (`workout_session_screen.dart:1432`), replacing the `_exercises` cache; edit mode writes the cache directly (`:1415-1417`); `_logSet`'s `_persistEntryValues` (`:1115`) re-persists the same cached values, so `entry['reps']`/`entry['weight']` are present after a phone log (existing proof: `test/widget_test.dart:246-249` reads them from `getExercisesWithEntries()`); watch writes resync via `_resyncExercisesFromState` (`:525`).
- D-5 Lock (A4): in live mode (`!widget.editMode`), `_buildMetricWidget` passes `isReadOnly: isLoggedNow` to the `set` branch's two `InlineMetricEditor`s (`workout_session_detail_view.dart:181-196`) and `_buildWeightAdjustmentSection` gains an `isReadOnly` parameter (passed to its `InlineMetricEditor` at `:144` and used to disable the expand `OutlinedButton` `onPressed` at `:121` only when the section is collapsed and read-only). Timer displays are already read-only on a finished entry. `isLoggedNow = _isSetLogged(effortId, entryIndex, effortKind)`.
- D-6 Auto-advance (A5): in `_logSet` replace the advance block (`workout_session_screen.dart:966-979`: `if (_currentSet < entries.length) { _currentSet++; } else if (...) {...}`) with: the first index `i` in `_currentSet … entries.length - 1` (0-based, strictly after the current one) for which `!_isSetLogged(effortId, i, effortKind)` and `i != _currentSet - 1` becomes `_currentSet = i + 1`; none found → the existing next-exercise branch unchanged. The early return for an already-logged set (`:802-818`) is untouched. A new helper `int? _nextUnloggedSetAfter(effortId, effortKind, entries.length)` keeps it testable. Reachability confirmed: `_logSet` is invoked only from `_buildLogSetButton.onPressed` (`workout_session_detail_view.dart:1023`), rendered only when `!_isSetLogged` (`_buildSetControls :879-889`); the Next arrow calls `_nextSet` (`:984`), which only jumps. `_loggedSetKeys` is pre-populated from `_isSetLogged` at load (`workout_session_screen.dart:585-597`) and added only in the log flow (`:947`), which also records the rest that makes `_isSetLogged` true; `_resyncExercisesFromState` (`:517-525`) deliberately does not fill it, but there the button is hidden anyway. The last set reads logged because the rest is recorded at `nextEntryIndex = _currentSet` = `entries.length` (`:946-955`) and `_isSetLogged` matches `r.entryIndex == entryIndex + 1` (`:751-769`). The early return is defensive dead code in live mode once D-5 locks logged sets — kept untouched.
- D-7 Remove (A6, O-4): new `_deleteLastUnloggedSet` in `workout_session_screen.dart` next to `_deleteCurrentSet` (`:1295-1383`): pick `target` = the last index for which `!_isSetLogged(...)`, else `entries.length - 1`; then the same body as `_deleteCurrentSet` with `currentIndex = target` (same confirmations, same `deleteEntry`, same single-set exercise removal, same `_hasStructuralChanges` in edit mode, same `_currentSet` clamp). To avoid copy-paste, change `_deleteCurrentSet` into `_deleteSetAt(int index)` and make `_deleteLastUnloggedSet` call it. `_deleteCurrentSet` is not called elsewhere after this change (builder greps; remove it if so).
- D-8 Layout (A7): in the detail `build` (`lib/features/session/workout_session_list_view.dart:821-851`) the scrollable's inner `Column` becomes `mainAxisAlignment: MainAxisAlignment.start` and its children, in order: `_buildSetBar` (bar, `SizedBox(height: 8)`, count text, `SizedBox(height: 4)`, `LoggedValuesLine`), `_buildMetricWidget(...)`, `SizedBox(height: 24)`, `SetCountStepper`. The two old calls `_buildSetProgress` / `_buildSetIndicator` and their definitions (`workout_session_detail_view.dart:686-833`) are deleted. The count text keeps the style at `:746-751` (titleMedium, letterSpacing, textSecondary, w500). The `ConstrainedBox`/`Expanded` skeleton, the `RestTimerStrip`, `_buildSetControls` and the bottom `SizedBox(height: 32)` stay.
- D-9 Rolling and free-training sessions use the same detail view: no special case.
- D-10 `_skippedSets` (`workout_session_screen.dart:123`) is never written; delete it with its only reader (the dots). Allowed under "fix what you touch".

## Readers of what this plan changes (grep them first; migrate, never loosen)

- Count text `Set 1 of N` and friends: kept, so `test/watch_live_refresh_screen_test.dart`, `screen_widget_test.dart`, `session_toolbar_rework_test.dart`, `pr2_launch_quality_hotfix_test.dart` keep reading them. Check each still finds exactly one widget (the text now sits inside the bar block).
- `Add set` / `Remove set` / `Remove exercise` tooltips: `test/exercise_set_last_value_test.dart:106`, `screen_widget_test.dart` `sets can be added in detail view` (`:1550`), `session_toolbar_rework_test.dart` S-015 (`:625`), S-016 (`:676`). S-015/S-016 tap `arrow_back` to a logged set and delete it: under O-4 `−` removes the last unlogged set, so those tests are migrated: log every set first, then `−` removes the last set and asks `Delete logged Set?` (same keys). Say so in Progress.
- Focus after a log: `test/widget_test.dart:158` (three `Log Set` taps), `unified_rest_overlay_test.dart` S-005 (`:468`), `session_toolbar_rework_test.dart` S-015/S-016 comments — normal flow is unchanged (D-6 matches the old `+1` when nothing ahead is logged).
- Inputs of a logged set: `test/screen_widget_test.dart`, `resistance_emphasis_redesign_test.dart`, `timed_emphasis_redesign_test.dart` (`:317` taps `Weight adjustment`), `exercise_detail_emphasis_tier_test.dart`, `in_session_pr_toast_test.dart`: grep for tests that edit reps or weight AFTER a log; those migrate to editing before the log (or to `editMode: true`).
- Rest chip / strip tests (`rest_timer_docked_strip_test.dart`, `unified_rest_overlay_test.dart`, `round_auto_expiry_test.dart`, `session_rest_closing_race_test.dart`): must stay green with no edit.
- Contract tests: `test/ui_standards_contract_test.dart` (shape on every button, tooltip on every `IconButton`, no raw colours, `Colors.white/black` ratchet), `test/docs_indexing_contract_test.dart`, `test/palette_legibility_contract_test.dart`, `test/navigation_contract_enforcement_test.dart`. A red one means fix the new code.
- Docs: `docs/modality_based_exercise_ui.md` (Component Hierarchy lists "Set Progress Indicator / Set Dots"; section 6 Set Navigation; `:298` "Skip Set vs Delete" describes the dot and the minus), `docs/widget_catalog/session_widgets.md`, `docs/design_system.md` shared-pieces table (add `SetSegmentBar`, `SetCountStepper`), `docs/README.md` if it lists widgets.

### Readers table (verified against `test/` at base `80928669`)

| Test (file:line) | Why it breaks or needs migration | Change |
|---|---|---|
| `session_toolbar_rework_test.dart:625` S-015 | Taps `Icons.remove` focused on logged set 2 of 3; under D-7 `−` removes the last unlogged set (set 3) with no dialog | Log all 3 sets first (`recordRestStart(effortId, 1..3)` before pump), then `−` → `Delete logged Set?` → 'Delete' → `of 2` (same keys) |
| `session_toolbar_rework_test.dart:676` S-016 | Same rule, 2 sets | Log both sets, `−` → dialog → 'Cancel' → still `of 2` |
| `resistance_emphasis_redesign_test.dart:310` | Reads dot colours (`:348,:357`) and add-set icon alpha 0.35 (`:338`); dots deleted (D-8), D-2 icon alpha 0.45 | Replace dot asserts with `set-segment-$i` colour asserts; expect 0.45 icon alpha |
| `resistance_emphasis_redesign_test.dart:361` 'skipped set dot … primary' | Skipped (0-reps) log marks today's dot primary; the bar has no skipped look (no rest row → `_isSetLogged` false) | Drop the dot assert; assert the segment stays unlogged and the line omits it (O-9); behaviour change — see Open questions |
| `resistance_emphasis_redesign_test.dart:~490` theme sweep | Session dot asserts (`:526,:533,:556-570`) break; routine-setup dot asserts (`:606`) stay (routine screen untouched) | Migrate the session parts to bar asserts, keep the routine-setup parts |
| `sports_emphasis_redesign_test.dart:443` | Reads session dots, expects exactly 1 primary (the current dot) | Assert exactly one focused segment (10 dp / border) via `set-segment-*` |
| `widget_test.dart:158` | 3 `Log Set` taps; D-6 keeps the old `+1` path when nothing ahead is logged (set 2 is skipped → unlogged) | None — guard |
| `unified_rest_overlay_test.dart:468` S-005 | 2 `Log Set` taps, same path | None — guard |
| `pr2_launch_quality_hotfix_test.dart:447` S-003e | Edits reps on an unlogged set | None — guard |
| `interaction_flow_test.dart:577` | Navigates away from a logged set with arrows; never taps Log Set on it | None — guard |
| `in_session_pr_toast_test.dart` | Seeds values via `updateEntryValue` before pump; never edits after a log | None — guard |
| `exercise_detail_emphasis_tier_test.dart` | No `Log Set` tap; editors render on unlogged sets | None — guard |
| `timed_emphasis_redesign_test.dart:317` | Reads the `Weight adjustment` button style in STOPPED state (nothing logged) | None — guard |
| `screen_widget_test.dart:1381,1550,1592,1771,1808,1879` | All `RoutineSetupScreen` tests (own `_buildSetProgress`/`_buildSetIndicator`, `routine_setup_screen.dart:1407,1522`) | None — out of scope |
| `watch_live_refresh_screen_test.dart` | Reads count text + `LOGGED`; fixtures use `recordRestStart` | None — guard |
| `session_toolbar_rework_test.dart` S-014/S-020/S-021/S-022/S-023 | Icon swap, tooltip text, no-dialog delete paths preserved by D-2/D-7 (S-022's `−` now deletes set 2 instead of set 1; outcome identical) | None — guard |
| Contract tests: `ui_standards_contract_test.dart`, `palette_legibility_contract_test.dart`, `docs_indexing_contract_test.dart`, `navigation_contract_enforcement_test.dart` | New widgets must satisfy shape/tooltip/colour rules | Red → fix the new code, never the contract |

## Core scenarios (exact fixtures)

Fixtures: `MockWorkoutRepository`, the pump helper of `test/session_toolbar_rework_test.dart:57` for the screen tests; plain `testWidgets` for the three widgets (no timers, so FakeAsync is safe).

Widgets (`test/set_shell_widgets_test.dart`):
- S-4201 `SetSegmentBar(count: 3, focusedIndex: 1, isLogged: (i) => i == 0)`: three `set-segment-0..2` exist; semantics labels are `Set 1 of 3, logged`, `Set 2 of 3, current`, `Set 3 of 3, not logged`; tapping `set-segment-2` calls `onTap(2)`; each segment's tap area is at least 48 dp tall. Fails today: the widget does not exist.
- S-4202 `isLogged` true for index 1 with `focusedIndex: 1`: the label reads `Set 2 of 3, logged, current` (logged wins the fill, focus is added).
- S-4203 `loggedValuesText([ '10×60', null, '8×62.5' ])` is `10×60 · 8×62.5`; `loggedValuesText([null, null])` is the empty string; `LoggedValuesLine('')` has the same height as `LoggedValuesLine('10×60')`.
- S-4204 `SetCountStepper(label: 'SETS', count: 3, canAdd: true, removeIsExercise: false, …)`: tooltips `Remove set` and `Add set`; both buttons at least 48 x 48; `removeIsExercise: true` shows `Icons.delete_outline` with tooltip `Remove exercise`; `canAdd: false` makes `Add set` disabled with tooltip `Max 12 entries`.

Screen (`test/logger_shell_screen_test.dart`, new):
- S-4210 Resistance exercise `Bench`, 3 sets, set 1 reps 10 weight 60.0 kg and set 2 reps 8 weight 62.5 kg logged through `Log Set`: the bar shows segments 0 and 1 logged and 2 focused; `logged-values-line` reads `10×60 · 8×62.5`; `Set 3 of 3` text present once. Fails today: no bar, no line.
- S-4211 Same session in pounds (`preferredWeightUnit` lbs), set 1 reps 5 weight 100.0 kg: the line reads `5×` followed by `UnitFormatter.formatWeightValue(100.0, settings)` (the test derives the expected string from the formatter and ALSO asserts the literal after the lead derives it: Phase 0 prints it).
- S-4212 Weight 0.0 kg, reps 12, logged: the line reads `12` (no `×`).
- S-4213 Interval exercise (`timed`), interval 1 finished with `actualDurationSecs` 42 and interval 2 finished with 38: the line reads `0:42 · 0:38`; a round exercise with one finished round of 95 s reads `1:35`.
- S-4214 Nothing logged: `logged-values-line` text is empty and its height equals S-4210's.
- S-4215 Logging set 1 of 3 moves focus to set 2 (`Set 2 of 3`); with set 2 already logged first (through the repository: an `EntryRest` at index 2) logging set 1 moves focus to set 3 (`Set 3 of 3`) — D-6. On the last set of the first exercise of two, logging moves to exercise 2 set 1 (as today).
- S-4216 Live mode, set 1 logged and focused (navigate back): the two reps/weight `InlineMetricEditor`s are read-only (tapping the reps number opens no dialog: `find.byType(AlertDialog)` finds nothing); the centre control shows `LOGGED`; an unlogged set's reps tap opens the dialog as today. Edit mode (`editMode: true`) on the same data: tapping reps opens the dialog.
- S-4217 Hold exercise (`drill`) set 1 logged: the hold weight is read-only (live), editable in `editMode`.
- S-4220 Sets stepper: `+` adds a set (`Set 1 of 4` after one tap); `−` with sets 1-2 logged and 3 unlogged removes set 3 without a dialog (focus on set 3 clamps to set 2: `Set 2 of 2`); with all 3 logged `−` shows `Delete logged Set?`, confirm removes the last set; with one set left `−` shows `Remove Exercise?`.
- S-4221 Layout: the exercise's controls start within 40 dp of the bottom of the logged line (not centred); the `SetCountStepper` sits below them; the rest strip and the arrows row positions are the same as before (assert the primary button's bottom edge and the `Next` arrow position equal those of a pump of the base screen: the builder records the base values in the test as literals at 390 x 844 dp, measured on the old build before the change).
- S-4222 Rest chip untouched: after `Log Set` the `rest-overlay-chip` appears; tapping it pauses (existing behaviour, unchanged tests stay green: the existing rest tests are the guard, list their file names in Progress).
- S-4223 Guard that the dots are gone: `_buildSetIndicator` / `_buildSetProgress` do not exist (source scan: `lib/features/session/workout_session_detail_view.dart` contains neither name).

Why they fail without the change: S-4201..S-4204 and S-4210..S-4214 need widgets and a line that do not exist; S-4215 needs next-unlogged logic (today `+1`); S-4216/S-4217 need the lock (today every editor on a logged set is live); S-4220 needs the last-unlogged rule (today `−` deletes the focused set); S-4221 needs the layout change.

## Edge scenarios (each maps to an acceptance criterion)

- S-4230 Cap (A6): exercise at 12 entries (`maxEntriesPerEffort`, `lib/core/constants/workout_constants.dart:4`): bar renders 12 segments; `+` disabled, tooltip `Max 12 entries` (D-2). Fails today: no stepper.
- S-4231 Single logged set (A6/O-4): one-set exercise, logged: `−` shows `Remove Exercise?` (D-7 keeps the `entries.length == 1` branch before the logged check, `workout_session_screen.dart:1317-1352`).
- S-4232 Bar tap jumps (A1): from `Set 3 of 3`, tapping `set-segment-0` shows `Set 1 of 3` (`_jumpToSet` unchanged, `workout_session_screen.dart:1456-1469`).
- S-4233 Skipped set (O-9): a 0-reps log records no rest → the segment stays unlogged and the line omits it; replaces the deleted skipped-dot behaviour (see Readers table).
- S-4234 Watch-logged set (A5/S-3610): a wrist log does not move phone focus — guarded by `watch_live_refresh_screen_test.dart` S-3514 staying green, no new test.

## Phase outline

- Phase 0 (lead): `flutter analyze` count and the last full-suite pass count into Progress; measure the S-4221 base positions and the S-4211 lbs string with a throwaway test; list the test files that edit values after a log.
- Phase P1 — `crew-builder-app`, scope `lib/widgets/session/set_segment_bar.dart,lib/widgets/session/set_count_stepper.dart,lib/widgets/session/logged_values_line.dart,test/set_shell_widgets_test.dart`: D-1, D-2, D-3 and S-4201..S-4204, red first. Create the directories first (lead). Items: 4 files.
- Phase P2 — `crew-builder-app`, scope `lib/features/session/workout_session_detail_view.dart,lib/features/session/workout_session_list_view.dart,lib/features/session/workout_session_screen.dart,test/logger_shell_screen_test.dart,test/session_toolbar_rework_test.dart,test/screen_widget_test.dart,test/exercise_set_last_value_test.dart`: D-4, D-5, D-8, D-10 (wiring: bar, count text, line, lock, layout, stepper UI) and S-4210..S-4214, S-4216, S-4217, S-4221, S-4223; the tests the swap breaks are fixed in this phase. The stepper's `−` still calls the old delete here.
- Phase P3 — `crew-builder-app`, same scope plus `test/widget_test.dart,test/unified_rest_overlay_test.dart`: D-6, D-7 and S-4215, S-4220, S-4222; migrate S-015 / S-016.
- Phase D — `crew-docs-keeper` after P3 verified: the docs listed under Readers plus this plan's evidence file.
- Then `crew-prover` on S-4210, S-4215, S-4216, S-4220 and the lead's mutations (D-5 flag removed, D-6 `+1` restored, D-7 focused-set delete restored), then `crew-reviewer` (facts and at most 5 questions), then the lead looks at every changed screen on the iOS simulator at phone width (resistance, interval, hold, round; live and `Edit Session`; unlogged, partly logged, all logged; pounds).

### Phase P1 — `crew-builder-app` (runs first; P2/P3 import its widgets)

Write scope: `lib/widgets/session/set_segment_bar.dart,lib/widgets/session/set_count_stepper.dart,lib/widgets/session/logged_values_line.dart,test/set_shell_widgets_test.dart` (the `lib/widgets/session/` directory already exists — `inline_metric_editor.dart` lives there).

1. [ ] Red: write S-4201..S-4204 against the three missing widgets — `test/set_shell_widgets_test.dart` · `main`
2. [ ] Implement `SetSegmentBar` per D-1 (48 dp hit area, colour rules, keys, Semantics) — `lib/widgets/session/set_segment_bar.dart` · `SetSegmentBar`
3. [ ] Implement `SetCountStepper` per D-2 (tooltips, 48 dp `IconButton` style, keys) — `lib/widgets/session/set_count_stepper.dart` · `SetCountStepper`
4. [ ] Implement `loggedValuesText` + `LoggedValuesLine` per D-3 (24 dp box, `maxLines: 1`, ellipsis) — `lib/widgets/session/logged_values_line.dart` · `loggedValuesText` / `LoggedValuesLine`

Done criteria: `flutter test test/set_shell_widgets_test.dart` green (4 tests); `flutter test test/ui_standards_contract_test.dart test/palette_legibility_contract_test.dart` green; `flutter analyze` at the Phase 0 baseline count.
Predicted files: the 4 above (~210 production, ~150 test lines).

### Phase P2 — `crew-builder-app` (after P1)

Write scope: `lib/features/session/workout_session_detail_view.dart,lib/features/session/workout_session_list_view.dart,lib/features/session/workout_session_screen.dart,test/logger_shell_screen_test.dart,test/session_toolbar_rework_test.dart,test/screen_widget_test.dart,test/exercise_set_last_value_test.dart,test/resistance_emphasis_redesign_test.dart,test/sports_emphasis_redesign_test.dart`.

1. [ ] Add `_loggedValueText` per D-4 (incl. the appended cache note) — `lib/features/session/workout_session_detail_view.dart` · `_loggedValueText`
2. [ ] Lock logged sets per D-5 (`isReadOnly` on the two `set` editors; `_buildWeightAdjustmentSection` parameter + collapsed-expand guard) — `lib/features/session/workout_session_detail_view.dart` · `_buildMetricWidget` / `_buildWeightAdjustmentSection`
3. [ ] Build `_buildSetBar` (bar + count text + line) and rewire the detail Column per D-8 (start-aligned; delete `_buildSetProgress`/`_buildSetIndicator` `:686-833`) — `lib/features/session/workout_session_list_view.dart` · detail build; `lib/features/session/workout_session_detail_view.dart` · `_buildSetProgress` / `_buildSetIndicator`
4. [ ] Mount `SetCountStepper` below the controls, `−` still calling `_deleteCurrentSet` — `lib/features/session/workout_session_list_view.dart` · detail build
5. [ ] Delete `_skippedSets` (D-10) — `lib/features/session/workout_session_screen.dart` · `_skippedSets`
6. [ ] S-4210..S-4214, S-4216, S-4217, S-4221, S-4223 (fixtures: `_buildDeps`/`_buildSessionScreen`/`_openDetailView` copied from `test/session_toolbar_rework_test.dart:34-70`; values seeded via `updateEntryValue` before pump) — `test/logger_shell_screen_test.dart` · `main`
7. [ ] Migrate the dot readers per the Readers table — `test/resistance_emphasis_redesign_test.dart` · `_expectDotColors` callers; `test/sports_emphasis_redesign_test.dart` · 'accent appears only on current dot and primary action'
8. [ ] Verify no-edit guards stay green: rest suites + `screen_widget_test.dart` chip geometry + `watch_live_refresh_screen_test.dart` — (no edit)

Done criteria: `flutter test test/logger_shell_screen_test.dart test/session_toolbar_rework_test.dart test/screen_widget_test.dart test/exercise_set_last_value_test.dart test/resistance_emphasis_redesign_test.dart test/sports_emphasis_redesign_test.dart test/rest_timer_docked_strip_test.dart test/unified_rest_overlay_test.dart` green; `flutter analyze` at baseline; S-4223 source scan passes.
Predicted files: `workout_session_detail_view.dart` (~+60/−160), `workout_session_list_view.dart` (~±40), `workout_session_screen.dart` (−2), `logger_shell_screen_test.dart` (new ~380), the two migrations (~±50).

### Phase P3 — `crew-builder-app` (after P2; same scope plus `test/widget_test.dart,test/unified_rest_overlay_test.dart`)

1. [ ] Add `_nextUnloggedSetAfter` and rewire the `_logSet` advance block (`:966-979`) per D-6 — `lib/features/session/workout_session_screen.dart` · `_nextUnloggedSetAfter` / `_logSet`
2. [ ] Refactor `_deleteCurrentSet` → `_deleteSetAt(int index)`; add `_deleteLastUnloggedSet` per D-7 — `lib/features/session/workout_session_screen.dart` · `_deleteSetAt` / `_deleteLastUnloggedSet`
3. [ ] Point the stepper's `−` at `_deleteLastUnloggedSet` — `lib/features/session/workout_session_list_view.dart` · detail build
4. [ ] S-4215, S-4220, S-4222 (logged sets via `recordRestStart(effortId, nextIndex)`; timed/round via `setTimedEntryDuration`/`setRoundDuration`, `lib/state/workout/workout_state.dart:277,285`) — `test/logger_shell_screen_test.dart` · `main`
5. [ ] Migrate S-015/S-016 per the Readers table — `test/session_toolbar_rework_test.dart` · S-015 / S-016
6. [ ] Verify `widget_test.dart:158` and `unified_rest_overlay_test.dart:468` stay green (no edit)

Done criteria: `flutter test test/logger_shell_screen_test.dart test/session_toolbar_rework_test.dart test/widget_test.dart test/unified_rest_overlay_test.dart test/interaction_flow_test.dart` green; `flutter analyze` at baseline.
Predicted files: `workout_session_screen.dart` (~+55), `workout_session_list_view.dart` (~±3), `logger_shell_screen_test.dart` (+~140), toolbar migrations (~±30).

### Phase D — `crew-docs-keeper` (after P3 verified)

1. [ ] Update Component Hierarchy (`:50-51`), section 6 Set Navigation (`:183`), Set Skip vs Delete (`:298`) — `docs/modality_based_exercise_ui.md`
2. [ ] Add the three widgets — `docs/widget_catalog/session_widgets.md`
3. [ ] Add `SetSegmentBar`/`SetCountStepper` to the shared-pieces table — `docs/design_system.md` (`:463`)
4. [ ] Update this plan's Progress table

Parallelism: P1 ∥ nothing (P2 imports P1's widgets); P2 → P3 strictly (P3 rewires P2's wiring); Phase D after P3. P1's write scope is disjoint from P2's, but P2 cannot go green without P1, so no parallel run.

## Code pointers (current lines)

- `lib/features/session/workout_session_detail_view.dart`: `_buildWeightAdjustmentSection :106-155`; `_buildMetricWidget :159-682` (`set` branch `:169-198`); `_buildSetProgress :686-786`; `_buildSetIndicator :788-833`; `_buildSetControls :835-905` (stays); `_buildLoggedLabel :924-938` (stays).
- `lib/features/session/workout_session_list_view.dart`: detail body `:786-888` (inner Column `:824-849`, rest strip `:865`, controls `:873-876`); `_buildHeader :976-1062` (no change).
- `lib/features/session/workout_session_screen.dart`: `_isSetLogged :751-769`; `_logSet :794-984` (advance block `:966-979`); `_deleteCurrentSet :1295-1383`; `_jumpToSet :1456-1469`; `_skippedSets :123`.
- `lib/widgets/session/inline_metric_editor.dart`: `isReadOnly` parameter exists (tap returns at once, `:114`).
- Formatters: `UnitFormatter.formatWeightValue` (`lib/core/utils/unit_formatter.dart:69`), `OmniDateUtils.formatClock` (`lib/core/utils/date_utils.dart:177`).

## Progress / Assumption Log / Feedback / Open questions

### Progress
- Seeded 2026-10-15. Baseline at base `80928669` (lead-run): analyze 182; full suite `+4748 ~1` all passed (4m 20s).

| Item | Status |
|---|---|
| Seed verified: all Code-pointer and D-5..D-8 line numbers checked against disk | done — no drift found (D-5 `:181-196`, D-6 `:966-979`/`:802-818`, D-7 `:1295-1383`, D-8 `:824-849`/`:865`/`:873-876` all exact) |
| Readers swept (`test/` grep + targeted reads) | done — Readers table above |
| `lib/` callers of deleted symbols | done — safe (impact table) |
| D-6 confirmed | done — paragraph under D-6 |
| D-4 cache freshness | done — sentence appended to D-4 |
| S-4215/S-4220 fixtures named | done — Phase P3 item 4 |
| Phase 0 measurements (analyze count, pass count, S-4221 base positions, S-4211 lbs literal) | done — analyze 182 (0 errors); pass count: see Progress below; S-4221 base at 390x844 (resistance, 3 sets, base build): `Log Set` button rect L96 T752 R294 B808; `Next` arrow L306 T748 R370 B812; `Previous Set` arrow L20 T748 R84 B812; REPS label L169 T248, KG label L182 T408; S-4211 literal: 100.0 kg in lbs = `220.5` (62.5 kg in lbs = `137.8`) |
| P1 (crew-builder-app, 3 min) | done, lead-verified: 11 widget tests + 43 contract tests green, analyze 182, invariant clean |
| P2 (crew-builder-app, 15 min) | done, lead-verified: full suite `+4772 ~1` all passed (= 4748 + 11 + 13), analyze 182. Builder noted: wrote code before tests (red proof taken afterwards via prove-red: 12 of 13 red at HEAD) |
| P3 (crew-builder-app, 7 min) | done, lead-verified; builder wrote no report (friction logged) |
| D (crew-docs-keeper, 4 min) | done, lead-verified against code; evidence in the `.evidence.md` file |
| Simulator look (iPhone 17) | reps screen live: bar, count text, logged line, `LOGGED`, focus mark, stepper: OK. Found stepper below the fold while the rest chip shows -> fix 1 (editor padding) + S-4224, re-checked on the simulator: stepper visible. Timed / hold / round screens measured by a throwaway geometry probe at 390x844 (stepper reachable), NOT looked at on the device; session editor and pounds covered by tests only |
| Prover (glm) mutation list + lead mutations | 27 single-line mutations, each restored byte-identical (`cmp`): 26 red; 4 unproven ones got tests (fix 2, fix 3); 1 unobservable (`MainAxisAlignment.start` vs `center` in a scroll view) |
| Fix 1 (stepper reachable) / fix 2 (4 guard tests) / fix 3 (stepper icon wiring) / fix 4 (focus after delete below focus, review MINOR 1) / fix 5 (design-system row, review MINOR 2) | all done, lead-verified; fix rounds 5 of which 3 tests-only |
| Review (glm, 7 min) | APPROVE: 0 blocker, 0 major, 2 minors (both fixed) |
| Final | analyze 182 (= baseline, 0 errors); full suite `+4788 ~1` all passed (base `+4748 ~1`; +40 new tests); invariant grep clean; not committed |

### Assumption Log
- (none — no seeded entry needed a factual fix; no D/S wording changed)

### Feedback
- (none yet)

### Open questions
- (owner, report only) In the session editor there is no per-set Update button: values commit with the screen-level Save, as today. Confirm that is what "update a completed set only in the edit screen" means.
- (owner, report only) Live logged sets become read-only: a behaviour change from today, where reps and weight stay tappable after a log.
- (owner, report only) The skipped-set dot ("skipped renders primary") is not preserved: a skipped set records no rest, so `_isSetLogged` is false and the bar shows it unlogged (evidence: `workout_session_screen.dart:826-830` `isSkippedSetKindEntry` skips `recordRestStart`; `_isSetLogged:756-758`). Confirm the bar/line treatment (unlogged, omitted from the line) is intended.
- (owner, report only) `resistance_emphasis_redesign_test.dart:338` asserts the add-set icon at 0.35 alpha; D-2 specifies 0.45. The test migrates to 0.45 — confirm the alpha change is intended.
- (architect, report only) `screen_widget_test.dart:1550` "sets can be added in detail view" targets `RoutineSetupScreen` (key `routine-add-set`), not the session detail view; the seeded Readers bullet over-states its coupling. No migration needed.

Handoff: Phase P1 → `crew-builder-app`, scope `lib/widgets/session/set_segment_bar.dart,lib/widgets/session/set_count_stepper.dart,lib/widgets/session/logged_values_line.dart,test/set_shell_widgets_test.dart` (Phase 0 measurements by the lead first).
