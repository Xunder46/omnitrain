# Feature: 41 — `−` deletes the focused set

> Status: BUILT, PROVED (4 mutations), REVIEWED (approve with fixes, both fixed) and checked on the iOS simulator (2026-10-18); uncommitted; owner checks open
> Next handoff: owner walkthrough (running-timer prompt on a device), then commit
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: e6ff75b0 (branch claude_develop; tree clean at start). Team: the crew (`.claude/crew.md`). Reverses owner decision O-4 of plan 38a (`−` removed the last unlogged set).
> Scout sheet: `.work/crew/2026-10-18-41-delete-focused-set/scout-state.md` (facts below are quoted from it and spot-checked).

## Goal and acceptance

On the exercise logging screen the `−` in the set-count stepper deletes the set the user is looking at (the focused set), not the last unlogged one.

| Focused set | What `−` does |
|---|---|
| unlogged, not started | deletes at once, no dialog |
| started and not logged (timer, interval or round running or paused) | dialog `Delete running <Set\|Interval\|Round\|Hold>?` / "The timer is running. Deleting it loses this progress."; Cancel keeps everything; Delete stops that timer and its alert and deletes the set |
| logged | dialog `Delete logged <label>?` / "This cannot be undone." (today's text, unchanged) |
| the only set of the exercise | dialog `Remove Exercise?` (today's text, unchanged), running or not |

After a delete the focus stays on the same position (it now shows the set that slid up), or moves to the new last set when the deleted set was last. A running timer on ANOTHER set of the same exercise keeps running and keeps showing its own time. Rests, rest chip and pings of the other sets stay on their own sets. The routine editor's stepper is untouched.

## Owner decisions (2026-10-18, in chat)

- O-1 focused set only (reverses 38a O-4). O-2 unlogged idle: no dialog. O-3 logged: confirm. O-4 only set: `Remove Exercise?`. O-5 a started, unlogged set confirms before deleting (the owner changed "delete and stop silently").

## Decision Ledger

- D-1 Target = `_currentSet - 1`. `workout_session_list_view.dart:843` `onRemove: _deleteLastUnloggedSet` becomes `onRemove: () => _deleteSetAt(_currentSet - 1)`; `_deleteLastUnloggedSet` (`workout_session_screen.dart:1426-1443`) is deleted (builder greps for other callers; scout says none).
- D-2 Running confirm lives in `_deleteSetAt`'s multi-set branch, after the `entries.length == 1` branch and beside the `isLogged` confirm (`workout_session_screen.dart:1382-1396`): `final isStarted = !isLogged && _inProgressKeys.contains('$effortId-$index');` (`_inProgressKeys` holds every started, unlogged timed/drill/round entry, paused ones included: timer mixin restore adds on active and paused). Dialog keys `workout-delete-running-entry-cancel` / `-confirm`, `isDestructive: true`. Kind `set` has no timers, so `isStarted` is always false there.
- D-3 Timer UI state is keyed `'$effortId-$entryIndex'` and survives a delete (scout Q2/Q3): `_restoreTimerStateFromPersisted` only overwrites surviving keys, never clears, never touches `_effortTimers`; `_deleteSetAt` cancels no Timer. With a middle delete the persisted instances ARE shifted down (`deleteTimedEntry`/`deleteRound` in `timer_manager.dart`, `rekeyEntryRestsAfterDelete`), so the UI maps must shift the same way or the next set shows the deleted set's elapsed time and a ticker keeps writing the old index. New mixin method `_rekeyTimerStateAfterDelete(String effortId, int deletedIndex)` in `workout_session_timer_mixin.dart`, called in `_deleteSetAt` after `deleteEntry` and before `_loadExercises` in BOTH branches (single-set branch too: it drops everything of the effort). It replaces the existing `_inProgressKeys.removeWhere(...)` lines in the multi-set branch only (the single-set branch keeps its `_inProgressKeys`/`_loggedSetKeys` removeWhere lines as they are).
- D-4 Persisted data is not touched by this plan: observations keep their ids and leave a numbering hole (`entry_rows.dart` `loggedSetNumbersOf` doc), rests/timed/round instances are already re-indexed by the state layer. Not changed, not re-tested beyond S-4907.
- D-5 No new setting, no new widget. Tooltip/icon logic of `SetCountStepper` unchanged.

## Code pointers (current text)

`workout_session_list_view.dart:843`: `onRemove: _deleteLastUnloggedSet,`

`workout_session_screen.dart:1382-1400` (multi-set branch):
```dart
      // Multi-set: only confirm if the set has been logged
      if (isLogged) {
        final confirmed = await ConfirmationDialog.showTwoChoice(
          ... title: 'Delete logged $setLabel?', body: const Text('This cannot be undone.'),
          dismissKey: const Key('workout-delete-logged-entry-cancel'),
          confirmKey: const Key('workout-delete-logged-entry-confirm'), isDestructive: true);
        if (!confirmed) return;
      }

      if (widget.editMode) _hasStructuralChanges = true;
      _inProgressKeys.removeWhere((k) => k.startsWith('$effortId-'));
      await widget.workoutState.deleteEntry(effortId, index);
      if (deletedRestWasOpen) { ... }
      await _loadExercises();
```
`_deleteSetAt` single-set branch (`:1359-1369`) calls `deleteEntry` then `removeExerciseFromSession`.

`workout_session_timer_mixin.dart:211-220` `_resetTimerState` (per-key reset, the model for what a key holds): `_effortTimers`, `_effortRunning`, `_effortElapsed`, `_effortTargetDuration`, `_effortAlerted`, `_inProgressKeys`. Also per key: `_pendingRoundTransitions`, `_pendingTimedTransitions`. Ticker creation: `Timer.periodic(_kTimerUpdateInterval, (_) => _onEffortTick(effortId, entryIndex))` (`:461`, `:496`, `:544`, `:578`); `_onEffortTick` reads the persisted instance by `(effortId, entryIndex)`, so a re-created ticker with the shifted index is correct.

## Core scenarios (fixtures exact; ids checked unused: `grep S-49` in test/docs/watch/lib returns nothing)

Harness: copy the setup of `test/logger_shell_screen_test.dart` S-4220 (`:724`, `:758`) for `set` efforts and `test/session_toolbar_rework_test.dart` S-013b (`:761`) for timed efforts. Weights/reps below are labels to tell sets apart.

- S-4901 `set`, 3 sets with reps 5, 6, 8; set 1 logged (rest at entry 1); focus set 2 (unlogged). Tap `−`. Expect no dialog, `Set 2 of 2`, position 1 still the logged 5, position 2 now reads 8. Fails without the change: today the LAST unlogged set (the 8) is deleted, so position 2 reads 6.
- S-4902 `set`, 3 sets, sets 1 and 2 logged (rests at 1 and 2), set 3 unlogged; focus set 1 (navigate back). Tap `−`: `Delete logged Set?`. Cancel: still `of 3`. Tap `−`, Delete: `Set 1 of 2`, rests `[1]` (set 1's own rest at 1 is dropped, the rest at 2 moves to 1). Fails without: today `−` removes unlogged set 3 with no dialog.
- S-4903 `set`, 3 sets all logged, focus set 3: `−` asks `Delete logged Set?`, Delete gives `Set 2 of 2` (regression guard, same as existing S-4220 all-logged; keep that test, do not duplicate).
- S-4904 `timed` (label Interval), 3 intervals, interval 2 started (in progress), focus interval 2. Tap `−`: `Delete running Interval?`. Cancel: `Interval 2 of 3`, interval 2 still running. Tap `−`, Delete: `Interval 2 of 2`; after `pump(const Duration(seconds: 3))` the interval now at position 2 (old interval 3) shows 0 elapsed and not running, and no ticker is left for the deleted index. Fails without: no dialog today.
- S-4905 `timed`, 3 intervals, interval 3 started and running, focus interval 1 (unlogged, idle). Tap `−`: no dialog. Navigate to position 2 (old interval 3): `Interval 2 of 2`, still running, still showing its own seeded time `00:45`, not a fresh `00:00`. Built as an own-time/running-control check only: the readout is wall clock and a widget test cannot show a ticker moving, so this test does NOT guard `_rekeyTimerStateAfterDelete` (review finding 1); that guard is the end of S-4904 (the next `−` on the slid-up idle interval shows no dialog, which fails while a stale started-marker survives).
- S-4906 `round` (label Round): same as S-4904 with a started round: title `Delete running Round?`. One test, round kind only.
- S-4907 `set`, 3 sets all logged, set 3's rest still open (rests 1,2,3), focus set 1. Tap `−`, confirm. Expect `Set 1 of 2`, rests `[1, 2]` and the open one now at entry 2, rest chip still visible. Guards the other-sets-keep-their-rests promise (scout found no test for an open rest above a deleted set).
- S-4908 one-set exercise with a started interval: `−` shows `Remove Exercise?` (not the running dialog). Existing S-4231 covers the logged case; add only the started case.

Existing tests to migrate (scout Q5): `logger_shell_screen_test.dart:758` (`S-4220: − drops the last set when the last two are unlogged`) is replaced by S-4901 (delete it and say so); `session_toolbar_rework_test.dart` S-014 (`:604`, focus set 1 of 2, end state `of 1`) and S-022 (`:871`) should pass unchanged; `logger_shell_screen_test.dart` S-4222 (`:1048`, taps `−` at `:1128`) and S-4310 depend on which set is focused: the builder runs each and fixes only what the new rule changes.

## Phases

- P1 `crew-builder-app` (production + migrate): scope `lib/features/session/workout_session_screen.dart`, `lib/features/session/workout_session_list_view.dart`, `lib/features/session/workout_session_timer_mixin.dart`, `test/logger_shell_screen_test.dart`, `test/session_toolbar_rework_test.dart`. Items: D-1, D-2, D-3 plus migration. Serial.
- P2 `crew-builder-app` (new tests): new file `test/delete_focused_set_test.dart` with S-4901, S-4902, S-4904, S-4905, S-4906, S-4907, S-4908. Serial after P1.
- P3 `crew-docs-keeper`: `docs/modality_based_exercise_ui.md` (lines 434-441 and 545 say "not the focused set"), `docs/widget_catalog/session_widgets.md` if it repeats the rule, `docs/state_management/*` if the timer mixin is described there, plan evidence.
- Then `crew-prover` on S-4901, S-4902, S-4904, S-4905 (lead mutations: restore `_deleteLastUnloggedSet` target; remove the running confirm; remove `_rekeyTimerStateAfterDelete`), `crew-reviewer`, then the lead looks at the screen on the iOS simulator at phone width (set, interval, round; focused unlogged / logged / running).

Size: about 60 production lines, about 250 test lines, 3 phases, one track: inside the scope budget. The architect step is skipped on purpose (seed already has decisions, scenarios and phases; the lead validates it).

## Progress

| Phase | What | Result |
|---|---|---|
| P1 (builder) | D-1/D-2/D-3: `onRemove: () => _deleteSetAt(_currentSet - 1)` (`workout_session_list_view.dart:843`), the started-but-unlogged confirm in `_deleteSetAt` (`workout_session_screen.dart`, keys `workout-delete-running-entry-cancel`/`-confirm`), `_rekeyTimerStateAfterDelete` in the timer mixin called after `deleteEntry` in both branches; `_deleteLastUnloggedSet` deleted; S-4220/S-4225 migrations | done (verified in code by docs keeper) |
| P2a (builder) | `test/delete_focused_set_test.dart` — S-4901, S-4902, S-4907 | done; 3 pass |
| P2b (builder) | `test/delete_focused_timer_test.dart` — S-4904, S-4905, S-4906, S-4908 | done; 4 pass |
| fix 1 (builder) | Timer-state shift guard — a test for the stale started-marker after a delete | being added and proven separately (lead); not verified this run |
| P3 (docs keeper) | Stepper Remove Rule and Remove Entry rewritten to the focused-set rule; `_deleteLastUnloggedSet` dropped from the architecture tree; `_rekeyTimerStateAfterDelete` listed in `docs/state_management/services_and_utils.md`; evidence file written | done |

## Assumption Log

- A-1 Paused counts as started for the running dialog (progress would be lost). Owner said "currently active running set"; stated in the report.
