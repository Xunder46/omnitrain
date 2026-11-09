# Feature: 43a — a watch interval fills the phone's unfinished interval (no more doubled intervals)

> Status: BUILT, PROVED, docs written, review pending (2026-10-19)
> Next handoff: P1 (`crew-builder-app`)
> Binding conventions: docs/global_conventions.md; docs/documentation_standard.md; .github/copilot/pr-scope-budget.md
> Base commit: e6ff75b0 + plans 42a/42b (uncommitted, reviewed); the tree also holds unrelated uncommitted work from plan 41. Team: the crew (`.claude/crew.md`). Architect step skipped on purpose (seed carries decisions, scenarios, phases; the lead validates). First step of the series in `docs/plans/2026-10-19-43-shared-running-timer-plan/` (43b timer on both devices and 43c finish-once come later and need the owner's three answers).
> Scout sheet: `.work/crew/2026-10-19-43a-timed-fill/scout-state.md` (quotes below read from it, spot-checked).

## Goal and acceptance

On a cardio, hold or round exercise, an interval the watch logs lands in the interval the phone has not finished yet, instead of being added as an extra one beside it. Resistance sets already do this (plan 36a); timed, hold and round entries did not.

| Situation | Now | After 43a |
|---|---|---|
| Phone shows "Interval 2 of 2" not started (or running/paused); the watch logs an interval | the phone gets a third interval; its own stays | the watch's interval becomes interval 2; the phone still shows 2 of 2 |
| The phone's own timer for that interval was running | keeps running beside the extra one | stops: that interval is done once, with the watch's time |
| Every phone interval is finished; the watch logs one | one more interval is added | unchanged: one more interval is added |
| A second watch interval arrives after the first filled the last open one | — | it is added as a new interval |
| The watch's own interval is later shown back to the watch | never doubled | unchanged (still never doubled) |

Applies to `timed` (cardio), `hold` (isometric) and `round` efforts, in the live session only; a history import still appends. No wire change.

## Owner decision (2026-10-19, in chat)

- O-1 (series) start on one device starts the same timer on the other; finishing on either logs once. 43a delivers the "logs once" half for an interval logged on the watch; the shared running timer is 43b/43c.
- O-2 build 43a now, with a repro of the phone crash; ask the three timer questions before 43b.

## Decision Ledger

- D-1 Fill rule, importer live merge only (`lib/core/services/watch_session_importer.dart` `_placeAroundUserRows`, ~:836-840: `final fills = fillPlanned && entry.wireKind == WatchInboxEntry.kindSet;` and `final index = unfinished ?? fill?.number ?? next++;`). For a wrist entry of wire kind `timed` or `hold` the target is the first `TimedInstance` of the effort, in `getTimedInstances(effortId)` order (both stores return it sorted by `entryIndex`; the projection and `EntryRows.distanceEntries` use the same order), whose `state != TimedState.finished`; for `round` the first `RoundInstance` (`getRoundInstances`, sorted by `roundIndex`) with `state != RoundState.finished`. Only when `unfinished == null` (a half-written earlier pass keeps its place) and `fillPlanned` is true. No unfinished instance: append as today.
- D-2 How the fill writes (parallel to the set fill, `:831-838`, "The planned row's own rows go"): delete the target instance (`deleteTimedInstance(id)` / `deleteRoundInstance(id)`) and, for `timed`/`hold`, the observation rows it is paired with, then create the wrist's entry through `_createEntry` so the wrist's id, window and `createdAtMs = entry.loggedAtMs` are what the phone now holds (that stamp is what keeps `PhoneEntries.projectTimed`/`resolveRecordClaims` from sending it back to the watch). The instance keeps the deleted instance's `entryIndex`/`roundIndex` (so every later instance keeps its position). Rows pairing (scout Q1): the phone pairs rows to instances BY POSITION among the effort's instances in row-number order (`EntryRows.companions`, `lib/core/utils/entry_rows.dart:155-168`; `distanceEntries` `:246`); the doomed rows for position p are `companions(...)[p]` for `MetricIds.distance` and for `MetricIds.extraWeight` (use the same helper the phone's own delete uses, read `deleteEntry` in `lib/state/workout/session_core_entry.dart` ~:648 for timed/drill). The new rows reuse the doomed distance row's NUMBER (its id's number, `EntryRows.numberInId`) so the pairing order is unchanged and no id collides; `_createEntry` gains an optional `rowNumber` for that (default: `index`). A round has no rows. Everything stays inside the importer.
- D-3 No rest is opened for these kinds (the set fill's rest rule is `fills`-only, `:848-882`); the wrist's own rest report is applied by `_applyRests` exactly as before.
- D-4 The phone's open session screen: `_resyncExercisesFromState` (`lib/features/session/workout_session_screen.dart` ~:524) replaces `_exercises` only and, by its doc, touches no timers. After the fill a ticker for the filled index keeps firing as a no-op (`_onEffortTick` returns for a non-active instance), but `_effortRunning['$effortId-$index']` stays true and the key stays in `_inProgressKeys` until `_toggleEffortTimer`'s `_drainStaleInProgressKeys` (`workout_session_timer_mixin.dart` ~:76) runs (scout Q3). Add one mixin method, `_dropFinishedTimerState()`, called at the end of `_resyncExercisesFromState`: for every key in `_effortRunning`/`_inProgressKeys`/`_effortTimers` whose persisted instance (via `_getTimedInstance`/`_getRoundInstance`) is now `finished` (a key whose instance is gone is deliberately left alone: a reload may be in flight), cancel its `Timer`, set running false, remove it from `_inProgressKeys` and its pending transitions. A running interval of another index is untouched.
- D-5 Crash (not diagnosed, owner has no log): the lead's reading is that today's append gives the open screen an extra interval it does not expect, but that is a guess. P2's S-5008 is the repro: the owner's exact order (phone logs interval 1, phone interval 2 running, watch logs) pumped on the real screen, asserted with `tester.takeException()`. The builder runs S-5008 against the CURRENT code first and reports whether it throws, and with what. Whatever the result, S-5008 stays in the suite and must pass after the fix.
- D-6 A phone interval that is `active` (running) or `paused` is filled like a not-started one (the wrist finished that interval once, "logs once"). Stated as an assumption for 43b's owner question 3 ("earlier start wins").

## Code pointers (current text)

`watch_session_importer.dart` ~:832-852:
```dart
    var next = rows.lastIndex + 1;
    for (final entry in now) {
      if (placed.contains(entry.entryId)) continue;
      final unfinished = rows.unfinishedPlaceOf(entry);
      final fills = fillPlanned && entry.wireKind == WatchInboxEntry.kindSet;
      final fill = unfinished == null && fills
          ? await _plannedSetToFill(effortId, rested)
          : null;
      final index = unfinished ?? fill?.number ?? next++;
      if (fill != null) {
        for (final row in fill.rows) { await _repository.deleteObservation(row.id); }
        changed = true;
      }
      await _createEntry(key, entry, effortId, index);
```
`_createEntry` ~:1116 builds `LoggedEntryRows.timedObservations(effortId:, entryIndex: index, distanceMeters:, distanceSource:, atMs:)` / `drillObservations(...)` / `_createRoundInstance(entry, effortId, index)`; `_createTimedInstance` ~:1160 writes `TimedInstance(id: timedInstanceIdFor(sessionId, entry.entryId), effortId:, entryIndex: index, actualDurationSecs: entry.activeSecs(), startedAtMs:, finishedAtMs:, state: TimedState.finished, createdAtMs: entry.loggedAtMs, updatedAtMs: entry.windowStampMs)`.

The phone's planned interval: `TimerManager.addTimedEntry` (`timer_manager.dart` ~:464) writes `TimedInstance(entryIndex: existing.length, state: TimedState.notStarted, startedAtMs: 0, finishedAtMs: null)`; `addRound` ~:99 the same for `RoundInstance(roundIndex:, state: RoundState.notStarted)`; `session_core_entry.dart` `addEntry` ~:93-200 adds the rows (`timedObservations`/`drillObservations` numbered `EntryRows.nextNumber`).

Screen: `workout_session_screen.dart` ~:336-341 the listener runs `_resyncExercisesFromState()` when `watchRefreshRevision` moved; `_getTimedInstance` ~:741 reads by position in `getTimedInstancesForEffort`; `workout_session_timer_mixin.dart` `_onEffortTick` ~:662 returns early when the instance is not `active`.

Harness for the state tests: `test/watch_session_merge_test.dart` (live merge into a held session, Mock + Hive, `phoneOwnsSession: bridge.holdsSession`, fixtures `_plannedRows` ~:424). Harness for the screen test: `test/watch_live_refresh_screen_test.dart` (`_phone()`, `_screen()`, `_mount()`, `S-3512` ~:520 wrist timed entry on a timed effort).

## Core scenarios (ids checked unused: `grep -rE "S-50[0-9]{2}"` returns nothing)

State, plain `test()`, Mock AND Hive. Fixture T: the phone holds a session with one `timed` effort `sl-run` (exercise with `time`, `distance` capabilities) and TWO intervals the way `addEntry` writes them: instances idx 0 and idx 1 (`TimerManager.addTimedEntry` shape, ids `phone-ti-0`, `phone-ti-1`, createdAtMs the phone's), rows `timedObservations` numbers 0 and 1 (distance 0). Interval 0 finished by the phone (`state: finished`, `startedAtMs`/`finishedAtMs` set), interval 1 `notStarted`. The wrist's entry `sx-run-1`: `kind timed`, `startedAt 2026-10-05T10:10:00Z`, `endedAt 2026-10-05T10:30:00Z`, `distanceMeters 2500`, `distanceSource gps`.

- S-5001 Fixture T, wrist entry merged live. Expect `getTimedInstances('sl-run')` length 2; idx 1 is now `finished`, id `timed-<session>-sx-run-1`, `startedAtMs` the wrist's, `createdAtMs` the wrist's `loggedAt`; idx 0 untouched; distance rows: two, the second 2500 with source `gps`, the first as before. Fails without: three instances.
- S-5002 Fixture T with interval 1 `active` (`startedAtMs` set, running) then with `paused`: same expectations as S-5001 (D-6). Fails without: running interval stays and a third appears.
- S-5003 Fixture T but BOTH intervals finished by the phone: the wrist entry appends: three instances, the new one idx 2, no row removed (regression guard of the append branch, A-51 behaviour).
- S-5004 Fixture T, two wrist entries (`sx-run-1` then `sx-run-2`, later stamps) in one pass: the first fills idx 1, the second appends idx 2 (no unfinished left): three instances in order.
- S-5005 The same wrist entry delivered twice (redelivery): still two instances, nothing re-filled, no error.
- S-5006 Hold (`drill` effort, exercise with `hold` capability; rows `drillObservations` extra weight 5.0 kg on the phone's planned interval): a wrist `hold` entry with `extraLoadKg 10` fills idx 1; instance finished; the extra-weight row at the paired number is 10; interval 0's row untouched; two instances.
- S-5007 Round (`round` effort, two `RoundInstance`s, idx 1 `notStarted`): a wrist `round` entry fills `roundIndex 1`: two instances, idx 1 `finished`, `completed true`, wrist window; no observation rows created.
- S-5007b Provenance: after S-5001 `PhoneEntries.projectTimed` over the effort's instances with `wristLoggedAtMs: [the wrist's loggedAt]` returns an entry for idx 0 only (the filled one is the wrist's own, not sent back).
- S-5010 (added in fix round 1) Hole in the row numbers: the phone deleted a middle interval, so instances are `entryIndex` 0 and 1 but rows are numbered 0 and 2; the wrist's entry fills instance 1 and its rows keep numbers 0 and 2 (distances 0.0 then 2500.0), two instances.
- S-5011 (added in fix round 1) A half-written earlier pass: the wrist's own instance exists at idx 1 without rows and the phone has another unfinished interval at idx 2; re-merging the entry finishes idx 1 in place and never touches the phone's idx 2 (three instances).

Screen, `testWidgets`, Mock only, the live-refresh harness:
- S-5008 (the crash probe, D-5) Phone-held session with a timed effort of two intervals; interval 0 logged by the phone (finished), interval 1 STARTED on the phone (active, a ticker running via the screen's own start); pump 2 s; the wrist logs a timed entry (observations_up as `S-3512` does); pump. Expect `tester.takeException()` null, `Interval 2 of 2` still shown, interval 2 shown as logged with the wrist's total, no running timer left for it (e.g. no pause control for it), and after `pump(const Duration(seconds: 3))` still no exception. Run first against the CURRENT code; report the outcome.
- S-5009 The same on a round effort ("Round 2 of 2").

## Phases (serial; the lead verifies after each; no builder runs the full suite)

- P1 `crew-builder-app` — importer fill D-1/D-2/D-3 with S-5001..S-5007b (tests first: write them, see them fail for the stated reason, then implement). Scope: `lib/core/services/watch_session_importer.dart`, new `test/watch_timed_fill_test.dart`.
- P2 `crew-builder-app` — screen D-4 with S-5008, S-5009 (run S-5008 on the current code first and report; then implement). Scope: `lib/features/session/workout_session_screen.dart`, `lib/features/session/workout_session_timer_mixin.dart`, new `test/watch_timed_fill_screen_test.dart`. Note `lib/features/session/workout_session_screen.dart` already shows uncommitted changes from plan 41: leave them, edit only the resync method.
- P3 `crew-docs-keeper` — `docs/state_management/watch_surface.md` (47,850 bytes: add at most ~1 KB), `docs/watch_session_capture.md`, `docs/modality_based_exercise_ui.md` only if it states how watch intervals land, plan evidence. NOT `docs/watch_session_sync.md` unless the net size change is zero or negative (it sits 5 bytes under the 80% band: replace its sentence on in-progress timed/hold/round entries instead of adding).
- Then `crew-prover` is not used: the lead applies the mutations (D-1 target choice, the `unfinished == null` guard, row deletion, `rowNumber`, `_dropFinishedTimerState`), `crew-reviewer`, a simulator look is not needed (no layout change) but the owner check below is.

Size: about 90 production lines, about 450 test lines, 3 phases, one track (phone): inside the budget.

## Readers of what this seed touches (builders run them)

`_createEntry` callers (`:749`, `:849`, grep `_createEntry(`); tests of timed/round import: `test/watch_session_import_test.dart` (`A-51 ...` timed and round), `test/watch_session_merge_test.dart`, `test/watch_live_refresh_screen_test.dart` (S-3512), `test/watch_session_projection_test.dart` (S-140..S-143), `test/watch_session_adoption_bridge_test.dart` (S-144), `test/watch_capture_repository_parity_test.dart`; `_resyncExercisesFromState` readers: `test/watch_live_refresh_screen_test.dart`, `test/session_screen_build_phase_notify_test.dart`, `test/delete_focused_timer_test.dart`, `test/count_up_screen_test.dart`, `test/round_countdown_screen_test.dart`.

## Owner checks (owner)

- (owner) On a cardio exercise with "Interval 2 of 2" open on the phone, log an interval on the watch: the phone shows the watch's time in interval 2 and no third interval appears.
- (owner) Repeat with the phone's own timer running on that interval: it stops.
- (owner) If the phone crashes, run `flutter run 2>&1 | tee ~/omnitrain-run.log` and send the file.

## Progress

| Phase | What | Result |
|---|---|---|
| P1 | `crew-builder-app` — importer fill D-1/D-2/D-3, tests first (S-5001..S-5007b) | done; lead-verified |
| P2 | `crew-builder-app` — screen `_dropFinishedTimerState` D-4 (S-5008, S-5009) | done; lead-verified |
| Fix round 1 | tests after the lead's verification | done; lead-verified |
| P3 | `crew-docs-keeper` — docs + evidence | done (2026-10-19) |

## Assumption Log

- A-1 Filling a running/paused phone interval (D-6) is the product-neutral reading of "finishing on either logs once"; 43b's owner question 3 may refine it.
- A-2 The crash cause is unknown (D-5); S-5008 decides what is known.
