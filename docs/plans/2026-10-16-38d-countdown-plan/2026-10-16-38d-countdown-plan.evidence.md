# Evidence — plan 38d, phase D (docs keeper, 2026-10-16)

Docs brought in step with the built code. Every behaviour sentence added or
kept names a test whose group and test name was read in the test file this
run. `lib/` was read for each claim; file:line below is what this run saw.

| Doc | Section | What changed | Verified against file:line |
| --- | --- | --- | --- |
| `docs/design_system.md` | Shared pieces and rules per job | Added the `TimerRing` row (job "Countdown ring") and the rule sentence after the table (time running out against a set length → `TimerRing`, marked unguarded). ValueStepperRow's job line now reads "reps, weight or duration" to match the duration mode added in this plan. | `lib/widgets/session/timer_ring.dart:25`; `lib/features/session/workout_session_detail_view.dart:406`; `lib/widgets/session/value_stepper_row.dart:55,62,82` |
| `docs/modality_based_exercise_ui.md` | Core UX Patterns — "Count-up efforts render plain digits" | Caption sentence corrected: 38d restores it — `ELAPSED` while the entry is unfinished, `COMPLETED` once finished (the old text said "no `ELAPSED` / `COMPLETED` caption"); the S-4402 finished-caption group was added to that paragraph's verification block. | `lib/features/session/workout_session_detail_view.dart:280` (timed), `:513` (drill); `test/count_up_screen_test.dart:242-247` (`_expectNoTimedChrome` asserts `ELAPSED` present), `:972-1022` (group `Count-up — a finished entry reads COMPLETED (S-4402)`) |
| `docs/modality_based_exercise_ui.md` | Wall-Clock Timer Lifecycle — "Round Countdown Display" | Stale derivation removed (`round.remainingMs / 1000`); replaced with the screen's real source — the timer mixin's `_effortElapsed` + `_getEffortTargetDuration`, `effectiveTarget - elapsed` clamped to `[0, effectiveTarget]`, never `RoundInstance.remainingMs`. Added: ring states (full before Start, sweeps while running, frozen paused, empty finished), captions `REMAINING`/`COMPLETED` and the gone chrome, the `ROUND LENGTH` row (15 s step, 15 s floor, duration dialog, read-only while running/mid-round/finished), the apply-to-later-rounds rule via `updatePlannedDurationFrom`, and the edit-mode row — each with its test. | `lib/features/session/workout_session_detail_view.dart:288-440` (ring `:406`, caption `:416`, row `:427-439` with `min: 15 :432`, edit-mode row `:366-393`); `lib/state/workout/timer_manager.dart:372-412`; `lib/state/workout/workout_state.dart:246-254`; `lib/features/session/workout_session_screen.dart:1484-1489`; `lib/data/models/models.dart:1244` (`remainingMs` still exists — it is the model getter the doc now says the display does not read); tests `test/round_countdown_screen_test.dart:202-560`, `test/timer_ring_test.dart:44-158`, `test/state_test.dart:2458-2555`, `test/round_planned_duration_parity_test.dart:74-118` |
| `docs/modality_based_exercise_ui.md` | Component Hierarchy; "Effort kinds and their timer model" table | Not changed: neither names the removed status row or the `ROUND n` heading (checked this run), which is the brief's only trigger for touching them. | — |
| `docs/modality_based_exercise_ui.md` | Version footer | Version 1.6 → 1.7; Last Updated and the freshness reconciliation date → 2026-10-16. | — |
| `docs/widget_catalog/session_widgets.md` | `InlineMetricEditor` — Session context | The round status-label sentence is replaced: the live `round` editor sits inside a `TimerRing` with the caption `REMAINING` (`COMPLETED` once finished); the old `RUNNING` / `STOPPED` status label is described as gone. The timed/drill sentence now carries the restored caption, and `Log Round` joined the centre-button list. Sports S-001/S-002 re-cited — they now assert the ring and its caption. | `lib/features/session/workout_session_detail_view.dart:406-424`; `test/sports_emphasis_redesign_test.dart:267-336` (group `Sports effort emphasis redesign` · `S-001 free session stopped hierarchy is correct`, `S-002 free session running hierarchy is correct`) |
| `docs/widget_catalog/session_widgets.md` | New `TimerRing` entry | Props table, behaviour (1 s linear sweep while running on a falling progress; instant apply when stopped or when the progress rises; `Time remaining` semantics label; `FittedBox` digits; size clamped on a narrow surface — the doc names the owning file, not the value) and the sole call site. | `lib/widgets/session/timer_ring.dart:10,25,65-72,80-82,86,142`; `test/timer_ring_test.dart:44-158`; `test/round_countdown_screen_test.dart:202-240,473-560` |
| `docs/widget_catalog/session_widgets.md` | `ValueStepperRow` | Entry extended for the duration mode: intro and prop table (`metricType` gains `duration`, `step` optional with the 15 s duration default, new `min` and `onEditorTap` rows), a duration-mode paragraph, duration tooltip nouns, group `S-4413 duration mode` cited, and a round-length call-site paragraph (live row `min: 15`, dialog, lock rule, apply-to-later-rounds; editor row without the ring). | `lib/widgets/session/value_stepper_row.dart:55,62,82,238-241,259-266`; `lib/features/session/workout_session_detail_view.dart:366-393,427-439`; `test/value_stepper_row_test.dart:652-790` (group `S-4413 duration mode`); `test/round_countdown_screen_test.dart:271-394,455-472`; `test/state_test.dart:2458-2555`; `test/round_planned_duration_parity_test.dart:74-118` |

## Grep for the removed names across `docs/` (`RUNNING` / `STOPPED` / `PAUSED` round status label, `ROUND n` heading)

- In scope, fixed: `docs/widget_catalog/session_widgets.md` (the "round effort
  keeps its status label" sentence and the "(the round status label stays)"
  citation tail); `docs/modality_based_exercise_ui.md` Round Countdown Display
  (the whole old block, including the stale `remainingMs` lines) — replaced as
  tabled above. `modality_based_exercise_ui.md` keeps `STOPPED` / `RUNNING` /
  `PAUSED` inside the timed/drill "no status row" claim, which is still true
  and verified: `test/count_up_screen_test.dart` `_expectNoTimedChrome`
  (`:239-253`) asserts those strings are `findsNothing`, cited in the same
  paragraph.
- Outside scope, not changed: `docs/plans/…` and `docs/releases/…` mentions
  are planning/release records, out of this standard's scope. `data_models.md:98`
  and `modality_tracking.md:365` name the `remainingMs` **model getter**, which
  still exists (`lib/data/models/models.dart:1244`) — not a removed name. No
  non-plan doc names the `ROUND n` / `PERIOD n` heading.

## Notes

- First contract-test run failed `no design doc carries a unit value or a
  percentage` on two findings in the new TimerRing entry
  (`docs/widget_catalog/session_widgets.md:104 64 dp`, `:115 260 dp` — the
  latter inside the quoted test name `260 dp by default, screen minus 64 on a
  narrow surface`). Fixed by naming the owner file instead of the inset value
  in the `size` prop row and by citing group `S-4408 size` without quoting
  that test name; re-run green (paste above). The scan reads inline code
  spans, only fenced blocks are exempt (`test/docs_indexing_contract_test.dart:270-292`).
- `wc -c` is not available to this agent (only `gateway.sh` is); the per-file
  64 KiB ceiling was validated by the docs indexing contract test above
  (`no documentation file exceeds the indexing ceiling` — green), which passes
  for all three edited docs plus the new evidence file's directory.
- Component Hierarchy and timer-model rows left untouched — they do not name
  the removed chrome (see table).
- The edit-mode round row read `min: 0` early in this run and `min: 15` later;
  `lib/` is another agent's write scope, the docs make no claim about the
  edit-mode floor, so no doc text depends on which value lands.

## Docs contract test

`.github/copilot/scripts/macos/gateway.sh test test/docs_indexing_contract_test.dart`,
run 2026-10-16 after the edits above (first run failed the value scan, see
Notes; the re-run after the fix):

```
00:00 +11: Docs indexing contract the value scan flags a unit value and a percentage, and skips a fence and a test id
00:00 +12: Docs indexing contract no design doc carries a unit value or a percentage
00:00 +13: All tests passed!
```
