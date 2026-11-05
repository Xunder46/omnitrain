# Plan 38d — Countdown screens (martial-arts rounds, sports periods): ring, big remaining digits, round-length row

Status: SEEDED by the lead on 2026-10-16; NOT STARTED. Runs AFTER plan 38f has landed (38f is being built in another session and edits the same screen files: one writer in the tree). Re-quote every "current line" from the tree at brief time; pointers below are symbols. Not authorised to commit: the owner commits; never push.
Evidence: `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.evidence.md` (reserved). Review: `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.review.md` (reserved).
Series: `docs/plans/2026-10-15-38-logger-rework-series.md` (O-1..O-12, T-1..T-4). Scenario ids: `S-44xx` (grep-check free before use).
Owner input: the spec ("Countdown modality (rounds)") and mockup 3 (a full orange ring, `03:00` inside with a small caption `REMAINING`, a `ROUND LENGTH` row and a `ROUNDS` row, Start button), and on 2026-10-16 a screenshot of the sports screen: it still looks like the old version ("PERIOD 2" heading, `15:00` + `DURATION`, a `STOPPED` status row, no ring); "there needs to be a ring that expires along with the timer, and no old labels".

## Goal and acceptance (what the user sees)

Effort kind `round` (martial arts `Round`, sports `Period`), live session:
- A1. Hero: large remaining-time digits inside a progress ring. Before Start the ring is full and the digits show the round length (`03:00`). While running the ring empties in step with the digits and is empty at `00:00`; on expiry the existing global beep fires as today and the round finishes as today. The ring is a shared piece (`TimerRing`, see D-1); only this modality has a ring.
- A2. No old chrome: the big `ROUND n` / `PERIOD n` heading, the `DURATION` / `RUNNING` / `STOPPED` / `PAUSED` label variants and the play/pause status row are gone from this screen. CAPTIONS STAY (owner, 2026-10-16: "keep all captions, don't remove them yet"): a small caption under the digits inside the ring, `REMAINING` while not started or running, `COMPLETED` once the round is finished (the old `COMPLETED` unit label, in the same place and style `InlineMetricEditor` used for unit labels). The `ROUND LENGTH` caption is kept under the round-length row's number.
- A3. Round length row under the ring: `ValueStepperRow` (38b) for the round length: − left, + right, the number `mm:ss`, a unit/label `ROUND LENGTH` only if Q-1 says captions stay; step 15 s (O-6), minimum 15 s, maximum as today's duration dialog allows; tap the number opens the existing duration dialog (`showDurationEntryDialog`, O-12). Editable before Start; LOCKED (read-only, − and + disabled) while the round runs and on a finished round (38a lock rule). A change before Start applies to this round AND every later round of the exercise that has not started (O-6); finished and running rounds keep their own length.
- A4. Primary button: `Start` → `Log Round` (`Log Period` for sports) as today (no Pause, O-1; the button never dims). `Log Round` mid-round records the time actually completed (as `endRoundEarly` does today) and 38a's auto-advance moves to the next unlogged round.
- A5. The sets control (38f) shows `Round 2 of 3` / `Period 2 of 3` in the middle; no separate count text, no `ROUNDS` count box. The bar, captions under the bar (`m:ss` of each logged round, 5 rounds or fewer) and the rest chip are the 38a/38f ones, untouched.
- A6. Session editor (`editMode`): keeps a round-length editor for a past round (a past round cannot be Start→Log'ed) built with the same `ValueStepperRow`, without the ring; the old heading and labels are gone there too (architect states exactly what edit mode shows today and what it shows after).
- A7. Unchanged: timers and persistence (`RoundInstance`, wall-clock derived), the expiry beep and notification, the rest chip and its rules, the lock of logged rounds, `maxEntriesPerEffort`.
- A8. `flutter analyze` not above the Phase 0 baseline (0 errors); `flutter test` not below the Phase 0 count plus new tests minus removed ones (list); no allowlist entry, no ratchet raised.

## Open owner question (ask in the report, default shown)

- Q-1 RESOLVED by the owner on 2026-10-16: keep all captions. For 38d: `REMAINING` / `COMPLETED` under the digits, `ROUND LENGTH` under the length row. The 38c count-up screens dropped `ELAPSED` / `COMPLETED`: this plan RESTORES them (phase P3 item: `ELAPSED` while not started or running, `COMPLETED` when finished, under the plain digits, in the unit-label style used before 38c; weight row caption as 38c has it) and migrates the 38c tests that assert their absence.

## Decision Ledger

- D-1 `TimerRing` (new, `lib/widgets/session/timer_ring.dart`): a `StatelessWidget(progress: double /*0..1 remaining fraction*/, child: Widget, size)` drawing a track circle (`onSurface` at alpha 51) and an arc (`primary`, round cap, stroke 8) sweeping `progress * 2π` clockwise from the top, with `child` (the digits) centred; built on a `CustomPaint`/`CustomPainter`; colours from `Theme.of(context).colorScheme` only; size about 260 dp but never wider than the screen minus 2 x 32 dp. `Semantics(label: 'Time remaining ...', value: ...)` excluded from the painter. Smooth sweep between the screen's 1 Hz ticks: `TweenAnimationBuilder<double>` with `Duration(milliseconds: 1000)` and `Curves.linear` while running, no animation when not running or when the value jumps backwards (round length edited). Registered in the `docs/design_system.md` shared-pieces table (job: "Countdown ring").
- D-2 Remaining fraction = `remaining / effectiveTarget` using the same `remaining`, `effectiveTarget` the `round` case computes today (`_effortElapsed`, `_getEffortTargetDuration`); not started → 1.0; finished by logging early → the ring shows what was completed? Architect decides between "empty" and "frozen at the remaining fraction" and states it; the digits show the time done (as `stoppedDisplayValue` does today).
  - D-2 decision (architect, 2026-10-16): EMPTY when finished — by expiry (remaining 0) and by early log (progress forced 0). The caption reads `COMPLETED` and the round is over; a frozen partial arc would read as time remaining. Source stays the digits' source (`_effortElapsed` / `effectiveTarget`), NOT `RoundInstance.remainingMs`: it re-derives from `DateTime.now()` at build time (models.dart:1228-1242), so between ticks it can disagree with the digits by up to 1 s, and under fake-async `DateTime.now()` does not advance, so a remainingMs-driven ring would not move in pumped tests. Not started → 1.0. Mid-round paused (restored session only; the live UI cannot pause a round) → frozen fraction, no animation (D-1).
- D-3 Round-length row = `ValueStepperRow` configured for seconds: needs a duration mode (display `mm:ss`, step 15, min 15, max from the dialog's limit) — extend `ValueStepperRow` only if 38b's API cannot express it; the architect states the smallest change. Writes go through `_updateMetricValue(effortId, entryIndex, 'round-duration', secs)`.
- D-4 Apply-to-later-rounds (O-6): new state method (e.g. `updatePlannedDurationFrom(effortId, fromIndex, secs)` in `TimerManager`, exposed by `WorkoutState`) that sets `plannedDurationSecs` for the round at `fromIndex` and every later round whose `state == RoundState.notStarted`, one `updateRoundInstance` per round, cache updated first. `_updateMetricValue`'s `round-duration` branch calls it in live mode and also refreshes `_effortTargetDuration` for each touched round (as the single-round branch does for one). Edit mode keeps its single-round buffer behaviour (a past round) — architect confirms.
- D-5 The old `round` branch of `_buildMetricWidget` (heading `Text('$roundLabel $rounds')`, `InlineMetricEditor` with `DURATION`/`REMAINING`/`COMPLETED`, the status `Row`) is replaced; `entryData['rounds']` is no longer read by this screen (grep other readers before removing anything outside the screen).
- D-6 No data-model or repository-interface change; existing repository methods only.
- D-7 `ValueStepperRow` today cannot show a duration (`lib/widgets/session/value_stepper_row.dart`): `_shownValue` (:96-101) hands the editor a `double` for non-reps and the `'duration'` case does `currentValue as int?` (`inline_metric_editor.dart:63-69`) → cast error; `MetricStepCalc.parseAndClamp('duration', ...)` clamps 0..3600 (`metric_crown_widget.dart:37-38`), min 0 not 15; there is no `onTap` hook (the inner editor would open the generic `showMetricEditPopup`, not the duration dialog); the step-button noun is `metricType == 'reps' ? 'reps' : 'weight'` (:202-204). Smallest extension, all optional so existing callers are unchanged: (a) accept `metricType: 'duration'` — `_shownValue` keeps `int` for `'duration'` (as for `'reps'`), step-button noun `'duration'`; (b) `final VoidCallback? onEditorTap;` passed to the inner `InlineMetricEditor.onTap` — the round row opens `showDurationEntryDialog` (O-12); null keeps today's popup; (c) `final num? min;` clamped in `_steppedValue` after `parseAndClamp` (next < min → min; unchanged → null). Max 3600 comes from `MetricStepCalc`. The label renders inline beside the number (`showUnitInline: true`), the style every 38b/38f row uses (the hold row shows `KG` the same way, detail_view :105-127).
- D-8 Count-up caption restore (Q-1): in the two live branches only, `unitLabel: ''` → `isTimedFinished ? 'COMPLETED' : 'ELAPSED'` (timed, detail_view :278) and the drill equivalent (:539); the edit-mode branches already pass `'ELAPSED'` (:246, :503) — untouched. Style is the editor's stacked unit label (`labelMedium`, letterSpacing 1, `onSurface` alpha 0.5, below the value, `inline_metric_editor.dart:207-215`) — the same style the round captions use. No new widget.

## Feature invariants
- State and features persist only through `WorkoutState` → `TimerManager` → `WorkoutRepository`; the screen never touches the repository.
- Digits and ring derive from the same pair (`_effortElapsed[timerKey]`, `_getEffortTargetDuration`); no second clock.
- Captions are `InlineMetricEditor` unit labels; no new text style, no new widget for captions.
- No model, repository-interface or `scripts/sqlite_schema.sql` change (D-6).
- Widget tests run Mock-first; Hive is seeded in `setUp`, never opened inside `testWidgets`.
- Docs: every behaviour sentence names an existing test; files stay below 52 KB.

## Existing-functionality impact (searched 2026-10-16)
| Touched surface | Already read by (search result) | Effect | Guarded by |
| --- | --- | --- | --- |
| `round` branch of `_buildMetricWidget` (detail_view :286-455) | sports S-001/S-002/S-003/S-005, exercise_detail S-101/S-103 (live screens) | branch rewritten; those tests migrate (table below) | S-4401, S-4402, S-4411 |
| `entryData['rounds']` read (detail_view :287) | only screen reader in `lib/` (other `['rounds']` matches are capability/metric names: modality_config.dart :64,:111, session_summary_service.dart) | read removed with the branch | S-4402 |
| timed/drill live `unitLabel: ''` (detail_view :278, :539) | count_up_screen_test :242-243, :484, :899, :945 assert absence | captions restored; those tests migrate | S-4402 |
| `updateRoundPlannedDuration` (timer_manager :335-360) | state_test :2427 area, round_auto_expiry_test :100-101/:179-180/:247-248, watch_session_import_test :1527, watch_session_adoption_bridge_test :1378/:1499 | kept single-round, untouched | S-4404, S-4414 |
| `_updateMetricValue` round-duration refresh (screen :1506-1510) | no direct test | replaced by touched-index refresh | S-4404 |
| `ValueStepperRow` | value_stepper_row_test.dart; 38b/38f rows (hold row detail_view :105-127) | optional params only; existing callers unchanged | value_stepper_row_test stays green |
| RoutineSetupScreen round editor (routine_setup_screen.dart :1263, :1337-1357) | screen_widget_test :1812 | untouched (38e scope) | stays green |

## Current code (verified 2026-10-16; tree = 38a+38b+38c+38f)

Round case, live (`lib/features/session/workout_session_detail_view.dart`, `_buildMetricWidget`):
- :286-292 `final rounds = entryData['rounds'] as int? ?? 1;` · `roundDuration = entryData['round-duration'] as int? ?? WorkoutConstants.defaultRoundDurationSecs;` · `roundLabel = modality == 'sports' ? 'PERIOD' : 'ROUND';`
- :294-297 `elapsed = _effortElapsed[timerKey] ?? 0;` · `targetSeconds = _getEffortTargetDuration(...)` · `effectiveTarget = targetSeconds > 0 ? targetSeconds : roundDuration;` · `remaining = (effectiveTarget - elapsed).clamp(0, effectiveTarget);`
- :308-313 `isFinished = isExpired || round?.state == RoundState.finished;` · `isMidRound = !isFinished && round != null && round.state != RoundState.notStarted;`
- :316-318 `stoppedDisplayValue`: finished → `actualDurationSecs > 0 ? actualDurationSecs : effectiveTarget`; mid-round → `remaining`; else `roundDuration`. :329-331 `stoppedUnitLabel`: finished → `'COMPLETED'`, mid-round → `'REMAINING'`, else `'DURATION'`.
- :393-449 live: heading `Text('$roundLabel $rounds')` (displayLarge, w300, letterSpacing -2, textSecondary); `InlineMetricEditor(metricType: 'duration', currentValue: running ? remaining : stoppedDisplayValue, unitLabel: running ? 'RUNNING' : stoppedUnitLabel, unitLabelColor: isExpired ? error : null, isReadOnly: isFinished, onTap: showDurationEntryDialog('Edit Round Duration') when !isFinished)`; then a status `Row` (play/pause icon 30 + `RUNNING`/`PAUSED`/`STOPPED`, labelMedium, textMuted).
- Edit mode (:336-391): heading + `InlineMetricEditor(unitLabel: 'DURATION')` (:359) fed from `_editBuffer['$effortId-$entryIndex']?['round-duration']`; save routes `round-duration` → `WorkoutState.setRoundDuration` (single round) then `normalizeRoundsToFinished()` (`workout_session_edit_mode.dart:196-202,220`).

Persist path: `_updateMetricValue` (`workout_session_screen.dart:1478-1482`) → `updateEntryValue` → `session_core_entry.dart:258-264` routes round → `_timerManager.updateRoundPlannedDuration(effortId, entryIndex, value)`; the screen then refreshes only the current entry (`workout_session_screen.dart:1506-1510`): `_effortTargetDuration[timerKey] = entry['round-duration'] as int? ?? 0; _effortAlerted[timerKey] = false;`.

`TimerManager.updateRoundPlannedDuration` (`lib/state/workout/timer_manager.dart:335-360`): blocks only `RoundState.finished`; `copyWith(plannedDurationSecs: newDurationSecs)`; `await _repository.updateRoundInstance(updated)` THEN `list[roundIndex] = updated` (cache after persist); `_notify()`. `WorkoutState.updateRoundPlannedDuration` (`workout_state.dart:234-240`) forwards.

Repaint: per-effort `Timer.periodic(_kTimerUpdateInterval = Duration(seconds: 1))` (screen :52, started in `_toggleEffortTimer`) → `_onEffortTick` (`workout_session_timer_mixin.dart:608-646`) reads `round.elapsedMs` and `setState(() { _effortElapsed[timerKey] = elapsed; })` — the 1 Hz driver the ring needs; no new hook. The global `_ticker` (screen :251) drives only the header clock and rest pings (`workout_session_global_timer.dart:10-33`). Restore (`_restoreTimerStateFromPersisted` :171-205): active → elapsed from wall-clock (auto-completes past target), paused → frozen + not running, finished → `actualDurationSecs`, notStarted → 0; `_effortTargetDuration[timerKey] = round.plannedDurationSecs` for all.

`RoundInstance` (`lib/data/models/models.dart:1228-1247`): `elapsedMs` wall-clock derived, capped at `plannedDurationSecs * 2000`; `remainingMs = (planned - elapsedMs).clamp(0, planned)` (:1244-1246).

Count-up today (Q-1): timed live branch `unitLabel: ''` (detail_view :278, comment :274-276 "plain digits, no caption"); drill live branch `unitLabel: ''` (:539). The edit-mode branches already pass `unitLabel: 'ELAPSED'` (:246, :503). Pre-38c caption code NOT quotable this run (gateway `git-show` cannot print file content); per the 38c plan D-4 the same editor carried `ELAPSED`/`COMPLETED` as its `unitLabel` — restore mechanism in D-8.

## Readers (to grep and migrate, never loosen)

`test/round_auto_expiry_test.dart`, `test/sports_emphasis_redesign_test.dart`, `test/timed_emphasis_redesign_test.dart` (round parts), `test/screen_widget_test.dart` (`round effort detail view still renders round-duration editor`, round edit-mode tests), `test/exercise_detail_emphasis_tier_test.dart` ("Round X of Y" comment and tier assertions), `test/state_test.dart` (`round: addEntry carries round-duration forward`, `updateRoundPlannedDuration`), `test/session_toolbar_rework_test.dart` (round landing tests), `test/logger_shell_screen_test.dart` (S-4213 round caption), docs `docs/modality_based_exercise_ui.md` (Round Countdown Display), `docs/widget_catalog/session_widgets.md`, `docs/design_system.md`.

## Readers migration (never loosen)
| Test (file:line) | Why it breaks / stays | Change |
| --- | --- | --- |
| sports_emphasis_redesign_test :247 S-001 | asserts `PERIOD 1` heading + `STOPPED` + play icon on the live screen | rewrite the live leg: ring + `REMAINING` + no chrome; keep the segment-accent part |
| :297 S-002 | `RUNNING` + pause icon while running | rewrite: digits tick, no chrome |
| :341 S-003 | both, routine-backed session | rewrite as S-002 |
| :461 S-005 | theme parity asserts `PERIOD 1`/`STOPPED` on live screens | rewrite the live legs for ring/caption; the routine-setup leg stays |
| exercise_detail_emphasis_tier_test :326 S-101, :359 S-103 | `ROUND 1`/`PERIOD 1` header colour, live | heading removed → assert ring + caption instead |
| count_up_screen_test :242-243, :484, :899, :945 | assert `ELAPSED`/`COMPLETED` absence (38c) | `ELAPSED` → findsOneWidget (unstarted/running/paused); `COMPLETED` asserted on finished fixtures |
| sports :386 S-004, :421; exercise_detail S-105/S-106/S-106b/S-108/S-110; screen_widget_test :1812, :5442/:5480; session_toolbar_rework_test :238/:332/:355; logger_shell_screen_test :268; round_auto_expiry_test (all); state_test :2427; timed_emphasis_redesign_test :282/:333/:376 | no removed-chrome assertions (routine setup, summary, set bar, buttons, expiry, single-round state) | stay green, no change |

## Scenarios (architect to complete with exact fixtures; ids S-44xx)

- S-4401 ring is a `TimerRing` with progress 1.0 before Start (round 180 s); after `startRound` and 45 s elapsed progress is 0.75 (derive with a controlled clock/`RoundInstance`, not `Future.delayed`).
- S-4402 digits inside the ring read `03:00` with the caption `REMAINING`; after finishing a round the caption reads `COMPLETED`; none of the strings `DURATION`, `RUNNING`, `STOPPED`, `PAUSED`, `ROUND 1`, `PERIOD 1` exist on the screen; count-up screens (`timed`, `drill`) show `ELAPSED` before and while running and `COMPLETED` when finished (restored from before 38c).
- S-4403 round-length row: + adds 15 s (`03:15`), − removes 15 s (`02:45`), never below `00:15`; tap on the number opens the duration dialog; read-only while running and when finished.
- S-4404 change length of round 1 of 3 before Start: rounds 2 and 3 (not started) follow; a finished round 1 stays when round 2's length changes later; a running round never changes (state-layer test, Mock AND Hive, playbook (i)).
- S-4405 `Log Round` mid-round at 60 s of 180 records 60 s and focus moves to round 2; the logged caption under the bar reads `1:00`.
- S-4406 expiry still beeps / finishes (existing `round_auto_expiry_test` stays green).
- S-4407 sports modality shows `Period 2 of 3` in the sets control and `Log Period`; martial arts shows `Round …` and `Log Round`.
- S-4408 layout at 390 x 844 with the rest strip up: ring, length row, sets control and the primary row all hit-testable; ring not clipped (measure first with a throwaway probe, playbook (o)).
- S-4409 edit mode: round-length row shown without a ring; old labels gone.
- S-4410 restored mid-round-paused round: seed `RoundInstance(state: paused, startedAtMs: now-45s, totalPausedDurationMs: 0, plannedDurationSecs: 180)` → digits `02:15`, caption `REMAINING`, ring frozen at 0.75 across pumps (no animation), centre control as the restore path offers today (mixin :191-194). Fails without: the ring would read 1.0 or animate.
- S-4411 finished by early log: seed `RoundInstance(state: finished, actualDurationSecs: 60, plannedDurationSecs: 180)` → digits `01:00`, caption `COMPLETED`, ring EMPTY (progress 0), row read-only. Fails without: a frozen 2/3 arc contradicts `COMPLETED`.
- S-4412 state parity (playbook (i)): change round 0's length while round 1 is active → round 1 keeps its length, round 2 (notStarted) follows; Mock and Hive bodies identical (`test/round_planned_duration_parity_test.dart`, harness of `test/helpers/repository_harness.dart`). Fails without D-4's `notStarted` filter.
- S-4413 limits: − at `00:15` stays `00:15`; + at `60:00` stays `60:00` (`MetricStepCalc` 'duration' clamp 0..3600, metric_crown_widget.dart:37-38); the dialog path stays as today (no clamp, `duration_entry_dialog.dart:86-93`) — not harmonised in 38d.
- S-4414 edit-mode regression: buffer a round-length edit on a past round, Save → `setRoundDuration` writes that round only; other rounds' `plannedDurationSecs` unchanged (guards D-4's "edit mode keeps single-round").

## Phase outline (each at most 8 items; builders `crew-builder-app`)

- Phase 0 (lead): baselines with 38f landed; probe positions at 390 x 844 (rest strip up) and 375 x 667.
- P1 state (D-4): `timer_manager.dart`, `workout_state.dart`, `workout_session_screen.dart` (`_updateMetricValue` round branch), state tests Mock+Hive: S-4404.
- P2 widget (D-1, D-3): `lib/widgets/session/timer_ring.dart`, `value_stepper_row.dart` (only if needed), their widget tests. P1 and P2 are disjoint and may run in parallel.
- P3 wiring (D-2, D-5, A1-A6): `workout_session_detail_view.dart` (`round` branch), `workout_session_timer_mixin.dart` only if the ring needs a repaint hook, screen tests S-4401..S-4409, migrations. Also restore the count-up captions on the `timed` and `drill` screens (Q-1) and migrate the 38c tests that assert their absence.
- D docs after P3; then prover (mutation list), lead mutations by script, reviewer, simulator look (sports and martial arts; start a short round, let it expire; log mid-round; change length; 3 and 6 rounds).

## Phases (expanded; each item `N. [ ] imperative — file · symbol`; ≤ 8 items)

### Phase 0 — baselines (lead, before P1/P2)
1. [ ] Record the analyze baseline (182 notices expected) and the full-suite baseline (builder-reported +4893 ~1; lead re-runs) — evidence file · baselines
2. [ ] Probe ring/row positions at 390x844 (rest strip up) and 375x667 with a throwaway probe, then delete it — playbook (o) · S-4408
Done: baselines in the evidence file. Predicted files: evidence file only. Scope: `docs/plans/2026-10-16-38d-countdown-plan/2026-10-16-38d-countdown-plan.evidence.md`.

### P1 — state layer (D-4) · owner `crew-builder-data` · PARALLEL with P2 (disjoint writes)
1. [ ] Red test first: apply-to-later-rounds body (3 rounds; change round 0 before start → 1,2 follow; finish 0, change 1 → 2 follows and 0 keeps its length; a running round never changes) — test/state_test.dart · new test beside 'round: addEntry carries round-duration forward' (:2427), Mock repo
2. [ ] Add `Future<List<int>> updatePlannedDurationFrom(String effortId, int fromIndex, int newDurationSecs)` — write the round at `fromIndex` unless finished, every later round only when `state == RoundState.notStarted`; cache `list[i] = updated` BEFORE each `await _repository.updateRoundInstance`; `_notify()` once; return the touched indexes — lib/state/workout/timer_manager.dart · TimerManager.updatePlannedDurationFrom
3. [ ] Expose the same signature on the state — lib/state/workout/workout_state.dart · WorkoutState.updatePlannedDurationFrom
4. [ ] Live `round-duration` branch: call `updatePlannedDurationFrom`, then after `_loadExercises()` refresh `_effortTargetDuration`/`_effortAlerted` for every returned index (replaces the single-entry refresh :1506-1510) — lib/features/session/workout_session_screen.dart · _updateMetricValue
5. [ ] Same body against Hive, bodies identical (harness of test/helpers/repository_harness.dart, pattern of distance_source_test.dart) — test/round_planned_duration_parity_test.dart · new (S-4412)
6. [ ] Regression: edit-mode single-round save unchanged (S-4414) — test/state_test.dart · round lifecycle group
Done: `flutter test test/state_test.dart test/round_planned_duration_parity_test.dart test/round_auto_expiry_test.dart` green; S-4404, S-4412, S-4414 pass; `updateRoundPlannedDuration` untouched (its readers in the impact table stay green). Predicted files: `lib/state/workout/timer_manager.dart`, `lib/state/workout/workout_state.dart`, `lib/features/session/workout_session_screen.dart`, `test/state_test.dart`, `test/round_planned_duration_parity_test.dart`. Scope: `lib/state/workout/timer_manager.dart lib/state/workout/workout_state.dart lib/features/session/workout_session_screen.dart test/state_test.dart test/round_planned_duration_parity_test.dart`.

### P2 — shared widgets (D-1, D-7) · owner `crew-builder-app` · PARALLEL with P1 (disjoint writes)
1. [ ] Red test: TimerRing paints track + arc at progress 1.0 / 0.75 / 0.0; size 260 but clamped to screen minus 64; colours from colorScheme only — test/timer_ring_test.dart · new
2. [ ] Create `TimerRing` per D-1 (CustomPaint painter, TweenAnimationBuilder 1000 ms linear while running, no animation otherwise) — lib/widgets/session/timer_ring.dart · TimerRing
3. [ ] Red test: duration mode — int-preserving value through the editor, step-button noun 'duration', `min` clamp (15), `onEditorTap` passthrough, existing reps/weight cases unchanged — test/value_stepper_row_test.dart · extend
4. [ ] Extend `ValueStepperRow` per D-7 (accept 'duration', `onEditorTap`, `min`) — lib/widgets/session/value_stepper_row.dart · ValueStepperRow
Done: `flutter test test/timer_ring_test.dart test/value_stepper_row_test.dart` green; every existing value_stepper_row_test case stays green (optional params only). Predicted files: `lib/widgets/session/timer_ring.dart`, `lib/widgets/session/value_stepper_row.dart`, `test/timer_ring_test.dart`, `test/value_stepper_row_test.dart`. Scope: `lib/widgets/session/timer_ring.dart lib/widgets/session/value_stepper_row.dart test/timer_ring_test.dart test/value_stepper_row_test.dart`.

### P3 — screen wiring + migrations (D-2, D-5, D-8; A1-A6) · owner `crew-builder-app` · AFTER P1+P2 (consumes TimerRing, the duration-mode row and the state method)
1. [ ] Red tests: S-4401, S-4402, S-4403, S-4407, S-4408, S-4410, S-4411 (Mock-first; Hive seeded in setUp only) — test/sports_emphasis_redesign_test.dart · rewrite S-001/S-002/S-003/S-005 live legs; test/exercise_detail_emphasis_tier_test.dart · rewrite S-101/S-103
2. [ ] Replace the round branch per A1/A2/D-2/D-5: TimerRing + digits + captions + length row + sets control; heading and status row gone; `entryData['rounds']` read removed — lib/features/session/workout_session_detail_view.dart · _buildMetricWidget round case (:286-455)
3. [ ] Restore count-up captions per D-8 — lib/features/session/workout_session_detail_view.dart · timed live branch (:278), drill live branch (:539)
4. [ ] Migrate the 38c absence assertions (Q-1): `ELAPSED` → findsOneWidget for unstarted/running/paused, `COMPLETED` asserted on finished fixtures — test/count_up_screen_test.dart · :242-243, :484, :899, :945
5. [ ] Edit-mode round row per A6/S-4409: ValueStepperRow without the ring, old labels gone — lib/features/session/workout_session_detail_view.dart · edit-mode round branch (:336-391)
6. [ ] Keep S-4405/S-4406/S-4407 green (Log Round mid-round, expiry beep/finish, modality labels); extend a fixture only if it needs the new chrome — test/round_auto_expiry_test.dart, test/session_toolbar_rework_test.dart
Done: `flutter test test/sports_emphasis_redesign_test.dart test/exercise_detail_emphasis_tier_test.dart test/count_up_screen_test.dart test/round_auto_expiry_test.dart test/session_toolbar_rework_test.dart test/screen_widget_test.dart test/logger_shell_screen_test.dart` green; S-4401..S-4411 pass. Predicted files: `lib/features/session/workout_session_detail_view.dart`, `test/sports_emphasis_redesign_test.dart`, `test/exercise_detail_emphasis_tier_test.dart`, `test/count_up_screen_test.dart` (+ round_auto_expiry/session_toolbar only if item 6 needs it). Scope: `lib/features/session/workout_session_detail_view.dart test/sports_emphasis_redesign_test.dart test/exercise_detail_emphasis_tier_test.dart test/count_up_screen_test.dart test/round_auto_expiry_test.dart test/session_toolbar_rework_test.dart`.

### D — docs · owner `crew-docs-keeper` · AFTER P3 (documents what landed)
1. [ ] Shared-pieces table: add the TimerRing row (job "Countdown ring") — docs/design_system.md · :484-486
2. [ ] Round Countdown Display: ring + `REMAINING`/`COMPLETED` + length row; fix the stale `round.remainingMs / 1000` line — docs/modality_based_exercise_ui.md · :238-241
3. [ ] Session context note (the round no longer keeps a status label), TimerRing, ValueStepperRow duration mode — docs/widget_catalog/session_widgets.md · :55-76, :168-192
Done: every behaviour sentence names an existing test; each file < 52 KB. Predicted files: the three docs. Scope: `docs/design_system.md docs/modality_based_exercise_ui.md docs/widget_catalog/session_widgets.md`.

### Prover / reviewer / simulator (lead, after D)
- Prover mutations: (m1) revert P1's cache-before-await order → S-4412 fails; (m2) drop the `notStarted` filter → S-4412 fails (running round changes); (m3) drop the `min` clamp → S-4403/S-4413 fails; (m4) drive the ring from `remainingMs` → S-4401 fails under fake-async; (m5) freeze the ring on early-log finish → S-4411 fails.
- Reviewer: findings to `2026-10-16-38d-countdown-plan.review.md`. Simulator: sports and martial arts; start a short round, let it expire; log mid-round; change length; 3 and 6 rounds.

## Risks
- Sibling session (38f follow-up) edits `lib/core/services/watch_session_importer.dart` + its tests (rests by position). It writes `RoundInstance` rows via the repository directly, never through TimerManager/WorkoutState round methods — no symbol overlap with 38d's P1; both touch `round_instances` data only. One-writer rule: 38d does not touch the importer.
- `flutter analyze` exits non-zero with 182 pre-existing notices; compare counts with the Phase 0 baseline, never ratchet.
- Full `flutter test` takes minutes (900 s timeout). A red Mock group can leave its Hive group hanging behind it: fix the red group first.

## Progress / Assumption Log / Feedback / Open questions

### Progress
| Item | Result |
| --- | --- |
| Seed kept (Goal, Q-1, D-1..D-6, S-4401..S-4409, outline) | done 2026-10-16 (architect) |
| Brief items 1-6 verified against the tree (quotes above) | done 2026-10-16 (architect) |
| Plan completed (D-2 decision, D-7/D-8, impact, readers, S-4410..S-4414, phases) | done 2026-10-16 (architect) |
| Phase 0 baselines (lead) | analyze 182; full suite after 38f `+4893 ~1` (lead-run, 38f verified) |
| P1 state (builder-app, 7 min) | done, lead-verified: `updatePlannedDurationFrom` (cache before persist, later rounds only when not started), screen refresh of every touched round, state + Mock/Hive parity tests |
| P2 widgets (builder-app, 6 min) | done, lead-verified: `TimerRing`, duration mode of `ValueStepperRow` (`min`, `onEditorTap`, int seconds, step 15) |
| P3a round screen (builder-app) | first run stopped by the runner (`no_write`, 15 min, wrote test migrations only); re-run with the exact code in the brief: done in 10 min; one deviation kept: digits in the ring wrapped in `FittedBox(scaleDown)` |
| P3b count-up captions (builder-app, 5 min) | done: `ELAPSED` / `COMPLETED` restored on interval and hold live screens (owner O-13) |
| P3c round screen tests (builder-app, 23 min) | done: `test/round_countdown_screen_test.dart` |
| D docs (docs-keeper, 27 min) | done, reviewer checked against code |
| Lead mutations | 25 single-line mutations (`mutate38d.py`, restored by `cmp`): 3 survivors judged equivalent (R3 ring progress not-started is 1.0 either way, R7 finished row length equals planned, R10 alert flag is reset on navigation); fix rounds closed R5a, R9, R11, R13 with tests-only briefs (a state test, an edit-mode floor test, an expiry test S-4415 with a real 16 s wait, a canvas arc test) |
| Review (reviewer, 13 min) | APPROVE: 0 blocker, 0 major, 1 minor (a doc comment that read two ways: reworded) |
| Simulator look | rounds screen looked at on the iPhone 17: ring, digits, `REMAINING`, `ROUND LENGTH` row, Start; found the sets control below the fold while the rest chip shows (leftover double padding of the rest strip in the detail body): fix 3 removed the double allowance (guard S-4416), the control was still about 15 pt clipped on the device, fix 5 shrank the ring to 232 and the top gap to 8; re-checked on the device: bar, ring, `REMAINING`, `ROUND LENGTH` row, `Period 1 of 1` control, rest chip and `Log Period` all visible, a started round counts down with the ring emptying and the length row locked. The widget harness could not reproduce the clip (test font), so fix 4 only strengthened the guard. Interval and hold screens NOT looked at on the device this round |
| Final | analyze 182 (= baseline, 0 errors); full suite `+4969 ~1` all passed (lead-run after fix 5; the 38f baseline was `+4893 ~1`); invariant grep clean; not committed |

### Assumption Log
- Pre-38c `timedUnitLabel`/`drillUnitLabel` not quoted verbatim: gateway `git-show` cannot print file content; mechanism derived from the 38c plan D-4 + the round branch's parallel structure (D-8). Builder re-checks the editor's stacked label (`inline_metric_editor.dart:207-215`) before relying on it.
- A2's "under the round-length row's number" renders as the row's inline unit label (`showUnitInline: true`, like `KG` on the hold row) — the row has no below-number slot; flagged for the simulator look.
- S-4413 max: the dialog path has no clamp today (`duration_entry_dialog.dart:86-93` returns h*3600+m*60+s unclamped); A3's "max as today's dialog allows" = dialog unchanged; the stepper clamps at 3600 via `MetricStepCalc`. Not harmonised in 38d.

### Feedback
- (none yet; reviewer writes `2026-10-16-38d-countdown-plan.review.md`; pointer + fix checklist go here)

### Open questions
- Pre-38c caption code not quotable this run (Assumption Log) — the builder verifies against the editor's label rendering instead.
- Facts taken from the brief, not re-measured: analyze baseline 182 notices; full suite after 38f +4893 ~1 (builder-reported; lead re-runs in Phase 0).
- Sibling-session overlap: none found on symbols (the importer writes `RoundInstance` rows via the repository directly, never through TimerManager/WorkoutState round methods); see Risks.

Handoff: P1 → `crew-builder-data`, scope `lib/state/workout/timer_manager.dart lib/state/workout/workout_state.dart lib/features/session/workout_session_screen.dart test/state_test.dart test/round_planned_duration_parity_test.dart`; P2 → `crew-builder-app`, scope `lib/widgets/session/timer_ring.dart lib/widgets/session/value_stepper_row.dart test/timer_ring_test.dart test/value_stepper_row_test.dart`. P1 and P2 are disjoint and may run in parallel; P3 waits for both (it consumes the TimerRing, the duration-mode row and the state method); D waits for P3.
